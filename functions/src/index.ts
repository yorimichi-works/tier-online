import {initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";

import {assertAdmin, loadNgWordConfig, updateNgWordConfigForAdmin} from "./adminConfig";
import {aggregateTier, Placements} from "./aggregation";
import {
  computeDailyCreateUpdate,
  confirmAdBonus,
  DailyCounterData,
  dailyTierCounterRef,
  getDailyStatus,
  requestAdBonusToken,
} from "./dailyLimit";
import {moderateText} from "./moderation";
import {checkAndConsume, computeRateLimitUpdate, loadLimits, rateLimitRef} from "./rateLimit";

initializeApp();

export {renderTopic, sitemap} from "./seo";

const googleSearchApiKey = defineSecret("GOOGLE_SEARCH_API_KEY");
const googleSearchEngineId = defineSecret("GOOGLE_SEARCH_ENGINE_ID");

function isAnonymousRequest(authToken: {firebase?: {sign_in_provider?: string}}): boolean {
  return authToken.firebase?.sign_in_provider === "anonymous";
}

// メール/パスワード登録ユーザーのみメール確認を必須にする。匿名・Google
// (既にGoogle側で確認済み)ユーザーは対象外。
function requiresUnverifiedEmailBlock(authToken: {
  firebase?: {sign_in_provider?: string};
  email_verified?: boolean;
}): boolean {
  return (
    authToken.firebase?.sign_in_provider === "password" &&
    authToken.email_verified !== true
  );
}

const REPORT_BLOCK_THRESHOLD = 5;

type ImageSearchResult = {
  query: string;
  imageUrl?: string;
  sourceUrl?: string;
};

export const searchTierItemImages = onCall(
  {secrets: [googleSearchApiKey, googleSearchEngineId]},
  async (request): Promise<{results: ImageSearchResult[]}> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    await checkAndConsume(
      getFirestore(),
      request.auth.uid,
      isAnonymousRequest(request.auth.token),
      "imageSearch",
    );
    const rawNames = request.data?.names;
    if (!Array.isArray(rawNames)) {
      throw new HttpsError("invalid-argument", "namesが必要です");
    }
    const names = rawNames
      .filter((name): name is string => typeof name === "string")
      .map((name) => name.trim())
      .filter((name) => name.length > 0 && name.length <= 100);
    if (names.length === 0 || names.length > 30) {
      throw new HttpsError(
        "invalid-argument",
        "一度に検索できるカード名は1〜30件です",
      );
    }
    const locale = ["ja", "ko", "en"].includes(request.data?.locale) ?
      request.data.locale as string : "en";
    const apiKey = googleSearchApiKey.value();
    const engineId = googleSearchEngineId.value();
    if (!apiKey || !engineId) {
      throw new HttpsError(
        "failed-precondition",
        "Google画像検索が設定されていません",
      );
    }

    const results = await Promise.all(names.map(async (query) => {
      const url = new URL("https://customsearch.googleapis.com/customsearch/v1");
      url.search = new URLSearchParams({
        key: apiKey,
        cx: engineId,
        q: query,
        searchType: "image",
        num: "1",
        safe: "active",
        hl: locale,
      }).toString();
      const response = await fetch(url, {
        headers: {"Accept": "application/json"},
      });
      if (!response.ok) {
        const detail = await response.text();
        console.error("Google image search failed", response.status, detail);
        throw new HttpsError(
          "unavailable",
          "Google画像検索へ接続できませんでした",
        );
      }
      const payload = await response.json() as {
        items?: Array<{
          link?: string;
          image?: {contextLink?: string};
        }>;
      };
      const first = payload.items?.[0];
      return {
        query,
        imageUrl: first?.link,
        sourceUrl: first?.image?.contextLink,
      };
    }));
    return {results};
  },
);

export const aggregateTopicTier = onDocumentWritten(
  "topics/{topicId}/submissions/{userId}",
  async (event) => {
    const topicId = event.params.topicId;
    const database = getFirestore();
    const topic = database.collection("topics").doc(topicId);
    const [items, submissions] = await Promise.all([
      topic.collection("items").orderBy("sortIndex").get(),
      topic.collection("submissions").get(),
    ]);
    const itemIds = items.docs.map((document) => document.id);
    const submissionData = submissions.docs.map((document) => ({
      region: (document.data().region as string | undefined) ?? "JP",
      placements: (document.data().placements ?? {}) as Placements,
    }));
    const aggregate = aggregateTier(
      itemIds,
      submissionData.map((submission) => submission.placements),
    );
    await topic.set({
      ...aggregate,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    const regions = new Set(submissionData.map((submission) =>
      submission.region,
    ));
    regions.add("GLOBAL");
    const batch = database.batch();
    for (const region of regions) {
      const regional = region === "GLOBAL" ? submissionData :
        submissionData.filter((submission) => submission.region === region);
      const regionAggregate = aggregateTier(
        itemIds,
        regional.map((submission) => submission.placements),
      );
      batch.set(database.collection("tierRegionStats").doc(
        `${topicId}_${region}`,
      ), {
        tierId: topicId,
        region,
        ...regionAggregate,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    await batch.commit();
  },
);

export const aggregateTopicLikes = onDocumentWritten(
  "topics/{topicId}/likes/{userId}",
  async (event) => {
    const topic = getFirestore().collection("topics").doc(event.params.topicId);
    const snapshot = await topic.collection("likes").count().get();
    await topic.set({
      likeCount: snapshot.data().count,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  },
);

type PublishItem = {
  id: string;
  name?: string;
  imageUrl?: string;
  sortIndex?: number;
  colorSeed?: number;
  contentLanguage?: string;
  isLanguageNeutral?: boolean;
};

export const publishTierTopic = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  if (requiresUnverifiedEmailBlock(request.auth.token)) {
    throw new HttpsError(
      "permission-denied",
      "メールアドレスの確認が完了していません",
    );
  }
  const uid = request.auth.uid;
  const anonymous = isAnonymousRequest(request.auth.token);
  const data = request.data ?? {};
  const topicId = data.topicId;
  if (typeof topicId !== "string" || topicId.length === 0) {
    throw new HttpsError("invalid-argument", "topicIdが必要です");
  }

  const firestore = getFirestore();
  const topicReference = firestore.collection("topics").doc(topicId);
  const existingItemsSnapshot = await topicReference.collection("items").get();

  // モデレーション判定はFirestoreの状態に依存しないため、トランザクション
  // の外で先に評価する。ここで拒否すれば、日次作成カウント・レート制限の
  // 消費は一切発生しない(公開失敗時にカウントだけ増えることはない)。
  const items: PublishItem[] = Array.isArray(data.items) ? data.items : [];
  const config = await loadNgWordConfig(firestore);
  const moderationFields: Record<string, string> = {
    title: String(data.title ?? ""),
    description: String(data.description ?? ""),
    tags: Array.isArray(data.tags) ? data.tags.join(" ") : "",
    itemNames: items.map((item) => item.name ?? "").join(" "),
  };
  const moderation = moderateText(moderationFields, config);
  if (moderation.status === "blocked") {
    throw new HttpsError(
      "failed-precondition",
      "不適切な内容が含まれているため公開できません",
    );
  }

  const publishLimits = await loadLimits(firestore);
  const publishLimit = (anonymous ?
    publishLimits.anonymous :
    publishLimits.authenticated).publish;
  const dailyCounterReference = dailyTierCounterRef(firestore, uid);
  const rateLimitReference = rateLimitRef(firestore, uid);

  const result = await firestore.runTransaction(async (transaction) => {
    // --- 読み取りフェーズ(Firestoreトランザクションは読み取りを全て
    //     終えてからでないと書き込みできない) ---
    const existing = await transaction.get(topicReference);
    const isNewTopic = !existing.exists;
    if (existing.exists && existing.data()?.creatorId !== uid) {
      throw new HttpsError(
        "permission-denied",
        "作成者だけがTier表を編集できます",
      );
    }
    const dailyCounterSnapshot = isNewTopic ?
      await transaction.get(dailyCounterReference) :
      null;
    const rateLimitSnapshot = await transaction.get(rateLimitReference);

    // --- 判定フェーズ(上限超過ならここで例外、書き込みは一切行われない) ---
    const dailyCounterUpdate = isNewTopic && dailyCounterSnapshot ?
      computeDailyCreateUpdate(
        (dailyCounterSnapshot.data() ?? {}) as DailyCounterData,
        anonymous,
      ) :
      null;
    const rateLimitUpdate = computeRateLimitUpdate(
      rateLimitSnapshot.data() ?? {},
      publishLimit,
      "publish",
    );

    // --- 書き込みフェーズ ---
    if (dailyCounterUpdate) {
      transaction.set(dailyCounterReference, dailyCounterUpdate, {merge: true});
    }
    transaction.set(rateLimitReference, rateLimitUpdate, {merge: true});

    transaction.set(topicReference, {
      title: data.title,
      description: data.description,
      tags: data.tags ?? [],
      category: data.category,
      categoryId: data.categoryId,
      contentLanguage: data.contentLanguage,
      targetRegion: data.targetRegion,
      sourceTierId: data.sourceTierId ?? null,
      sourceTemplateId: data.sourceTemplateId ?? null,
      isLanguageNeutral: data.isLanguageNeutral ?? false,
      creatorName: data.creatorName,
      creatorId: uid,
      participants: data.participants ?? 0,
      likeCount: data.likeCount ?? 0,
      community: data.community ?? {},
      isTrending: data.isTrending ?? false,
      isPublic: data.isPublic ?? true,
      moderationStatus: moderation.status,
      moderationReasons: moderation.reasons,
      ...(isNewTopic ?
        {
          reportCount: 0,
          createdByAnonymous: anonymous,
          createdAt: FieldValue.serverTimestamp(),
        } :
        {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    for (const item of items) {
      if (!item.id) continue;
      transaction.set(topicReference.collection("items").doc(item.id), {
        name: item.name ?? null,
        imageUrl: item.imageUrl ?? null,
        sortIndex: item.sortIndex ?? 0,
        colorSeed: item.colorSeed ?? 0,
        contentLanguage: item.contentLanguage ?? null,
        isLanguageNeutral: item.isLanguageNeutral ?? false,
      });
    }
    const incomingItemIds = new Set(
      items.map((item) => item.id).filter((id): id is string => Boolean(id)),
    );
    for (const existingItem of existingItemsSnapshot.docs) {
      if (!incomingItemIds.has(existingItem.id)) {
        transaction.delete(existingItem.ref);
      }
    }

    return {
      reportCount: isNewTopic ? 0 : (existing.data()?.reportCount as number | undefined) ?? 0,
    };
  });

  return {
    moderationStatus: moderation.status,
    reportCount: result.reportCount,
  };
});

export const deleteTierTopic = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  const topicId = request.data?.topicId;
  if (typeof topicId !== "string" || topicId.length === 0) {
    throw new HttpsError("invalid-argument", "topicIdが必要です");
  }

  const firestore = getFirestore();
  const reference = firestore.collection("topics").doc(topicId);
  const snapshot = await reference.get();
  if (!snapshot.exists) return {ok: true};
  if (snapshot.data()?.creatorId !== request.auth.uid) {
    throw new HttpsError(
      "permission-denied",
      "作成者だけがTier表を削除できます",
    );
  }
  await firestore.recursiveDelete(reference);
  return {ok: true};
});

export const reportContent = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  if (requiresUnverifiedEmailBlock(request.auth.token)) {
    throw new HttpsError(
      "permission-denied",
      "メールアドレスの確認が完了していません",
    );
  }
  const data = request.data ?? {};
  const topicId = data.topicId;
  const targetType = data.targetType;
  const targetId = data.targetId;
  const reason = typeof data.reason === "string" ? data.reason : "user_report";
  if (
    typeof topicId !== "string" || topicId.length === 0 ||
    typeof targetType !== "string" ||
    typeof targetId !== "string" || targetId.length === 0
  ) {
    throw new HttpsError("invalid-argument", "パラメータが不正です");
  }

  const uid = request.auth.uid;
  const reportId = `${targetType}_${targetId}_${uid}`.replace(/\//g, "_");
  const firestore = getFirestore();
  const reference = firestore
    .collection("topics").doc(topicId)
    .collection("reports").doc(reportId);

  const existing = await reference.get();
  if (existing.exists) {
    throw new HttpsError("already-exists", "既に通報済みです");
  }

  await reference.set({
    topicId,
    targetType,
    targetId,
    reporterUserId: uid,
    reason,
    createdAt: FieldValue.serverTimestamp(),
  });

  return {ok: true};
});

export const onReportWritten = onDocumentWritten(
  "topics/{topicId}/reports/{reportId}",
  async (event) => {
    const topicId = event.params.topicId;
    const firestore = getFirestore();
    const topic = firestore.collection("topics").doc(topicId);
    const snapshot = await topic.collection("reports").count().get();
    const reportCount = snapshot.data().count;

    const update: Record<string, unknown> = {
      reportCount,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (reportCount >= REPORT_BLOCK_THRESHOLD) {
      update.moderationStatus = "blocked";
    }
    await topic.set(update, {merge: true});
  },
);

export const setModerationStatus = onCall(async (request) => {
  const firestore = getFirestore();
  await assertAdmin(firestore, request);

  const data = request.data ?? {};
  const topicId = data.topicId;
  const status = data.status;
  if (
    typeof topicId !== "string" || topicId.length === 0 ||
    !["approved", "flagged", "blocked"].includes(status)
  ) {
    throw new HttpsError("invalid-argument", "パラメータが不正です");
  }

  await firestore.collection("topics").doc(topicId).set({
    moderationStatus: status,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});

  return {ok: true};
});

export const getNgWordConfig = onCall(async (request) => {
  const firestore = getFirestore();
  await assertAdmin(firestore, request);
  return loadNgWordConfig(firestore);
});

export const updateNgWordConfig = onCall(async (request) => {
  const firestore = getFirestore();
  await assertAdmin(firestore, request);
  return updateNgWordConfigForAdmin(firestore, request.data ?? {});
});

export const getDailyCreateStatus = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  return getDailyStatus(
    getFirestore(),
    request.auth.uid,
    isAnonymousRequest(request.auth.token),
  );
});

export const requestCreateAdBonusToken = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  if (isAnonymousRequest(request.auth.token)) {
    throw new HttpsError(
      "failed-precondition",
      "広告ボーナスの利用には登録済みアカウントが必要です",
    );
  }
  const token = await requestAdBonusToken(getFirestore(), request.auth.uid);
  return {token};
});

export const confirmCreateAdBonus = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  if (isAnonymousRequest(request.auth.token)) {
    throw new HttpsError(
      "failed-precondition",
      "広告ボーナスの利用には登録済みアカウントが必要です",
    );
  }
  const token = request.data?.token;
  if (typeof token !== "string" || token.length === 0) {
    throw new HttpsError("invalid-argument", "tokenが必要です");
  }
  return confirmAdBonus(getFirestore(), request.auth.uid, token);
});

// 匿名ユーザーがFirebase Authから削除されても、公開済みTier表(topicsコレクション)は
// 意図的に削除しない(要件: 公開Tier表はAuth削除だけでは自動削除しない)。
// 下書きはサーバー(Firestore)に一切保存されずローカル(端末)のみで完結しているため、
// このトリガーで削除すべきサーバー側データは現状存在しない。
//
// 以前はここに firebase-functions/v1 の auth.user().onDelete トリガー(no-op)を
// 定義していたが、1st Gen関数はApp Engineのセットアップを本番プロジェクトに
// 要求するため撤去した。何もしない関数のためにその依存を追加する価値がなく、
// 将来サーバー側の削除対象データ(例: 下書きのFirestore同期)が生まれた場合は
// v2の識別トリガーが使えないか改めて検討し、必要ならApp Engineの導入を検討する。
