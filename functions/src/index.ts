import {initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {setGlobalOptions} from "firebase-functions/v2";
import {onDocumentCreated, onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {defineBoolean} from "firebase-functions/params";
import {createHash, randomUUID} from "node:crypto";

import {assertAdmin, loadNgWordConfig, updateNgWordConfigForAdmin} from "./adminConfig";
import {deleteAccountData, deleteSharedImagesForTopic} from "./accountDeletion";
import {aggregateTier, Placements} from "./aggregation";
import {
  aggregateBingo,
  BINGO_MAX_AUTHOR_NAME,
  BINGO_MAX_COMMENT,
  BINGO_REPORT_HIDE_THRESHOLD,
  BingoEntryData,
  isValidLayout,
  lineCount,
  validateBingoInput,
} from "./bingo";
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
import {assertTierCreationAllowed} from "./tierCreationPolicy";
import {
  firestoreLanguage,
  normalizeLocale,
  SUPPORTED_REGION_CODES,
  wikipediaLanguage,
} from "./internationalization";
import {
  contentVersionOf,
  pendingTranslationsAfterSourceChange,
  sourceFingerprint,
} from "./translation/translationBatch";

initializeApp();
// 小規模運用で突発アクセスがそのまま大量インスタンス化しないよう上限を置く。
// minInstancesは既定の0のままなので、待機中の固定費は発生しない。
setGlobalOptions({maxInstances: 5});

// App Checkはクライアントを先に配布してメトリクスを確認してから強制する。
// Firebase Functions parameter ENFORCE_APP_CHECK=true で全Callableを一括強制できる。
const enforceAppCheck = defineBoolean("ENFORCE_APP_CHECK", {default: false});
const callableOptions = {enforceAppCheck};

export {renderHome, renderTopic, sitemap} from "./seo";

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

const SHARED_IMAGE_COLLECTION = "sharedItemImages";
const STARTER_CREATOR = {
  creatorName: "tier_online",
  creatorId: "tier_online",
  createdByAnonymous: false,
};

function starterCreatorFields(topicId: string): Record<string, unknown> {
  return topicId.startsWith("starter-") ? STARTER_CREATOR : {};
}

export function normalizeImageName(value: string): string {
  return value.normalize("NFKC").trim().toLocaleLowerCase().replace(/\s+/gu, " ");
}

export function sharedImageKey(value: string, locale: string): string {
  return createHash("sha256")
    .update(`${locale}:${normalizeImageName(value)}`)
    .digest("hex");
}

function firebaseDownloadUrl(
  bucketName: string,
  storagePath: string,
  token: string,
): string {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/` +
    `${encodeURIComponent(storagePath)}?alt=media&token=${token}`;
}

async function cacheSharedUploadedImages(params: {
  uid: string;
  topicId: string;
  locale: string;
  items: PublishItem[];
}): Promise<void> {
  const firestore = getFirestore();
  const bucket = getStorage().bucket();
  await Promise.all(params.items.map(async (item) => {
    const name = item.name?.trim();
    if (!item.id || !name) return;
    const key = sharedImageKey(name, params.locale);
    const cacheReference = firestore.collection(SHARED_IMAGE_COLLECTION).doc(key);
    if ((await cacheReference.get()).exists) return;

    // Only images uploaded for this exact topic are shareable. Asset images and
    // third-party URLs are intentionally excluded from the shared cache.
    const sourcePath = `users/${params.uid}/topics/${params.topicId}/items/${item.id}.jpg`;
    const source = bucket.file(sourcePath);
    const [exists] = await source.exists();
    if (!exists) return;

    const destinationPath = `shared-item-images/${key}.jpg`;
    const destination = bucket.file(destinationPath);
    const token = randomUUID();
    await source.copy(destination);
    await destination.setMetadata({
      cacheControl: "public,max-age=31536000,immutable",
      metadata: {firebaseStorageDownloadTokens: token},
    });
    await cacheReference.create({
      normalizedName: normalizeImageName(name),
      displayName: name,
      locale: params.locale,
      imageUrl: firebaseDownloadUrl(bucket.name, destinationPath, token),
      storagePath: destinationPath,
      sourceTopicId: params.topicId,
      sourceItemId: item.id,
      createdAt: FieldValue.serverTimestamp(),
    });
  }));
}

// 元Tierがブロック/削除された際、そこから共有領域へ複製された画像を検索
// 対象から外す。物理削除はせず(誤ブロック解除時に復元できるよう)hiddenを
// 立てるだけに留める。完全な削除は管理画面から個別に行う。
async function hideSharedImagesForTopic(
  topicId: string,
  hidden: boolean,
): Promise<void> {
  const firestore = getFirestore();
  const snapshot = await firestore
    .collection(SHARED_IMAGE_COLLECTION)
    .where("sourceTopicId", "==", topicId)
    .get();
  if (snapshot.empty) return;
  const batch = firestore.batch();
  for (const doc of snapshot.docs) {
    batch.set(doc.ref, {
      hidden,
      hiddenReason: hidden ? "sourceTopicBlocked" : FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  await batch.commit();
}

async function searchWikipediaImage(
  query: string,
  locale: string,
): Promise<ImageSearchResult> {
  const language = wikipediaLanguage(locale);
  const url = new URL(`https://${language}.wikipedia.org/w/api.php`);
  url.search = new URLSearchParams({
    action: "query",
    format: "json",
    generator: "search",
    gsrsearch: query,
    gsrnamespace: "0",
    gsrlimit: "5",
    prop: "pageimages|info",
    piprop: "thumbnail",
    pithumbsize: "1024",
    inprop: "url",
  }).toString();
  const response = await fetch(url, {
    headers: {
      "Accept": "application/json",
      "User-Agent": "tier-online/1.0",
    },
  });
  if (!response.ok) {
    const detail = await response.text();
    console.error("Wikipedia image fallback failed", response.status, detail);
    throw new HttpsError(
      "unavailable",
      "画像検索へ接続できませんでした",
    );
  }
  const payload = await response.json() as {
    query?: {
      pages?: Record<string, {
        fullurl?: string;
        thumbnail?: {source?: string};
      }>;
    };
  };
  const pages = Object.values(payload.query?.pages ?? {});
  const first = pages.find((page) => page.thumbnail?.source);
  return {
    query,
    imageUrl: first?.thumbnail?.source,
    sourceUrl: first?.fullurl,
  };
}

async function searchOpenverseImage(
  query: string,
  locale: string,
): Promise<ImageSearchResult> {
  const url = new URL("https://api.openverse.org/v1/images/");
  url.search = new URLSearchParams({
    q: query,
    mature: "false",
    page_size: "1",
  }).toString();
  const response = await fetch(url, {
    headers: {
      "Accept": "application/json",
      "User-Agent": "tier-online/1.0",
    },
  });
  if (!response.ok) {
    const detail = await response.text();
    console.error("Openverse image fallback failed", response.status, detail);
    throw new HttpsError(
      "unavailable",
      "画像検索へ接続できませんでした",
    );
  }
  const payload = await response.json() as {
    results?: Array<{
      url?: string;
      foreign_landing_url?: string;
    }>;
  };
  const first = payload.results?.[0];
  if (!first?.url) {
    // Openverse has sparse results for some CJK queries. A localized
    // Wikipedia lead image is a useful final fallback and keeps attribution
    // available through the source page.
    return searchWikipediaImage(query, locale);
  }
  return {
    query,
    imageUrl: first?.url,
    sourceUrl: first?.foreign_landing_url,
  };
}

export const searchTierItemImages = onCall(
  callableOptions,
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
    const locale = normalizeLocale(request.data?.locale);
    const firestore = getFirestore();
    const references = names.map((name) => firestore
      .collection(SHARED_IMAGE_COLLECTION)
      .doc(sharedImageKey(name, locale)));
    const cachedSnapshots = await firestore.getAll(...references);
    const results = await Promise.all(names.map(async (query, index) => {
      const cached = cachedSnapshots[index].data();
      const cachedImageUrl = cached?.imageUrl;
      if (
        cached?.hidden !== true &&
        typeof cachedImageUrl === "string" && cachedImageUrl.length > 0
      ) {
        return {
          query,
          imageUrl: cachedImageUrl,
          sourceUrl: typeof cached?.sourceTopicId === "string" ?
            `/topics/${cached.sourceTopicId}` : undefined,
        };
      }
      return searchOpenverseImage(query, locale);
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
    const [topicSnapshot, items, submissions] = await Promise.all([
      topic.get(),
      topic.collection("items").orderBy("sortIndex").get(),
      topic.collection("submissions").get(),
    ]);
    if (!topicSnapshot.exists || topicSnapshot.data()?.deleting === true) return;
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
      ...starterCreatorFields(topicId),
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
    const topicSnapshot = await topic.get();
    if (!topicSnapshot.exists || topicSnapshot.data()?.deleting === true) return;
    const snapshot = await topic.collection("likes").count().get();
    await topic.set({
      likeCount: snapshot.data().count,
      ...starterCreatorFields(event.params.topicId),
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
  sourceLanguage?: string;
  isLanguageNeutral?: boolean;
};

export const publishTierTopic = onCall(callableOptions, async (request) => {
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
  if (topicId.startsWith("starter-")) {
    throw new HttpsError(
      "permission-denied",
      "公式Tier表は編集できません",
    );
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
  const incomingSourceFingerprint = sourceFingerprint({
    title: data.title,
    description: data.description,
    category: data.category,
    tags: data.tags,
    sourceLanguage: data.sourceLanguage ?? data.contentLanguage,
  }, items.map((item) => ({id: item.id, name: item.name})));

  const result = await firestore.runTransaction(async (transaction) => {
    // --- 読み取りフェーズ(Firestoreトランザクションは読み取りを全て
    //     終えてからでないと書き込みできない) ---
    const existing = await transaction.get(topicReference);
    const isNewTopic = !existing.exists;
    const existingData = (existing.data() ?? {}) as Record<string, unknown>;
    const sourceChanged = isNewTopic ||
      existingData.sourceContentHash !== incomingSourceFingerprint;
    const contentVersion = isNewTopic ? 1 :
      contentVersionOf(existingData) + (sourceChanged ? 1 : 0);
    assertTierCreationAllowed(isNewTopic, anonymous);
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
      contentLanguage: normalizeLocale(data.sourceLanguage ?? data.contentLanguage),
      sourceLanguage: firestoreLanguage(data.sourceLanguage ?? data.contentLanguage),
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
      shareUploadedImages: data.shareUploadedImages ?? false,
      moderationStatus: moderation.status,
      moderationReasons: moderation.reasons,
      contentVersion,
      sourceContentHash: incomingSourceFingerprint,
      ...(sourceChanged ? {
        translations: pendingTranslationsAfterSourceChange(existingData),
        translationStatus: "pending",
        translationBatchId: FieldValue.delete(),
        processingStartedAt: FieldValue.delete(),
        translationUpdatedAt: FieldValue.serverTimestamp(),
      } : {}),
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
        contentLanguage: item.contentLanguage || item.sourceLanguage ?
          normalizeLocale(item.sourceLanguage ?? item.contentLanguage) : null,
        sourceLanguage: item.contentLanguage || item.sourceLanguage ?
          firestoreLanguage(item.sourceLanguage ?? item.contentLanguage) : null,
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

  if (
    data.isPublic !== false &&
    data.shareUploadedImages === true
  ) {
    try {
      await cacheSharedUploadedImages({
        uid,
        topicId,
        locale: normalizeLocale(data.sourceLanguage ?? data.contentLanguage),
        items,
      });
    } catch (error) {
      // Publishing must still succeed if optional cache contribution fails.
      console.error("Failed to cache shared item images", error);
    }
  }

  return {
    moderationStatus: moderation.status,
    reportCount: result.reportCount,
  };
});

export const deleteTierTopic = onCall(callableOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  const topicId = request.data?.topicId;
  if (typeof topicId !== "string" || topicId.length === 0) {
    throw new HttpsError("invalid-argument", "topicIdが必要です");
  }
  if (topicId.startsWith("starter-")) {
    throw new HttpsError(
      "permission-denied",
      "公式Tier表は削除できません",
    );
  }

  const firestore = getFirestore();
  const reference = firestore.collection("topics").doc(topicId);
  const snapshot = await reference.get();
  if (snapshot.exists && snapshot.data()?.creatorId !== request.auth.uid) {
    throw new HttpsError(
      "permission-denied",
      "作成者だけがTier表を削除できます",
    );
  }
  if (snapshot.exists) {
    await reference.set({deleting: true}, {merge: true});
    await deleteSharedImagesForTopic(firestore, getStorage(), topicId);
    await firestore.recursiveDelete(reference);
  }
  // Firestoreの削除が本体。以降のStorage残存ファイル掃除に失敗しても、既に
  // 削除は完了しているため呼び出し元にはエラーを返さない(ログにのみ残す)。
  try {
    await getStorage().bucket().deleteFiles({
      prefix: `users/${request.auth.uid}/topics/${topicId}/`,
    });
  } catch (error) {
    console.error("deleteTierTopic: failed to clean up storage files", error);
  }
  return {ok: true};
});

export const deleteUserAccount = onCall(callableOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  if (isAnonymousRequest(request.auth.token)) {
    throw new HttpsError(
      "failed-precondition",
      "登録済みアカウントのみ削除できます",
    );
  }
  const authTime = Number(request.auth.token.auth_time ?? 0) * 1000;
  if (!authTime || Date.now() - authTime > 10 * 60 * 1000) {
    throw new HttpsError(
      "failed-precondition",
      "アカウントを削除する前に再認証してください",
      {reason: "recentLoginRequired"},
    );
  }

  const uid = request.auth.uid;
  await deleteAccountData(getFirestore(), getStorage(), uid);
  // Authentication is intentionally removed last. If data cleanup fails, the
  // user can retry instead of being left with inaccessible orphaned data.
  await getAuth().deleteUser(uid);
  return {ok: true};
});

export const reportContent = onCall(callableOptions, async (request) => {
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

const CONTACT_CATEGORIES = [
  "general",
  "rightsInfringement",
  "deletionRequest",
  "other",
] as const;

// 利用規約・プライバシーポリシー記載の問い合わせ/削除依頼窓口。メール送信
// 基盤は持たないため、Firestoreに保存して運営がコンソールから確認する。
export const submitContactRequest = onCall(callableOptions, async (request) => {
  const data = request.data ?? {};
  const category = CONTACT_CATEGORIES.includes(data.category) ?
    data.category as string : "general";
  const message = typeof data.message === "string" ? data.message.trim() : "";
  const contactEmail = typeof data.contactEmail === "string" ?
    data.contactEmail.trim() : "";
  const relatedUrl = typeof data.relatedUrl === "string" ?
    data.relatedUrl.trim() : "";
  if (message.length === 0 || message.length > 4000) {
    throw new HttpsError("invalid-argument", "内容を入力してください(4000文字以内)");
  }
  if (contactEmail.length > 200 || relatedUrl.length > 500) {
    throw new HttpsError("invalid-argument", "入力内容が長すぎます");
  }

  await getFirestore().collection("contactRequests").add({
    category,
    message,
    contactEmail,
    relatedUrl,
    uid: request.auth?.uid ?? null,
    anonymous: request.auth ? isAnonymousRequest(request.auth.token) : true,
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
    const topicSnapshot = await topic.get();
    if (!topicSnapshot.exists || topicSnapshot.data()?.deleting === true) return;
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
    if (reportCount >= REPORT_BLOCK_THRESHOLD) {
      await hideSharedImagesForTopic(topicId, true);
    }
  },
);

export const setModerationStatus = onCall(callableOptions, async (request) => {
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
  await hideSharedImagesForTopic(topicId, status === "blocked");

  return {ok: true};
});

// 管理画面: 全Tierを検索・一覧表示する(公開/非公開・審査状態を問わない)。
// 通常のクライアントはFirestore rules上、自分のTierか公開Tierしか読めない
// ため、Admin SDK経由でこのCallableからのみ横断的に取得できるようにする。
export const adminListTopics = onCall(callableOptions, async (request) => {
  const firestore = getFirestore();
  await assertAdmin(firestore, request);

  const snapshot = await firestore
    .collection("topics")
    .orderBy("updatedAt", "desc")
    .limit(500)
    .get();
  return {
    results: snapshot.docs.map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        title: (data.title as string | undefined) ?? "",
        creatorName: (data.creatorName as string | undefined) ?? "",
        isPublic: data.isPublic !== false,
        moderationStatus: (data.moderationStatus as string | undefined) ?? "approved",
        participants: (data.participants as number | undefined) ?? 0,
        reportCount: (data.reportCount as number | undefined) ?? 0,
      };
    }),
  };
});

// 管理画面: 作成者に関わらず任意のTierの公開/非公開を切り替える。
export const adminSetTopicPublic = onCall(callableOptions, async (request) => {
  const firestore = getFirestore();
  await assertAdmin(firestore, request);

  const topicId = request.data?.topicId;
  const isPublic = request.data?.isPublic;
  if (
    typeof topicId !== "string" || topicId.length === 0 ||
    typeof isPublic !== "boolean"
  ) {
    throw new HttpsError("invalid-argument", "パラメータが不正です");
  }
  await firestore.collection("topics").doc(topicId).set({
    isPublic,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {ok: true};
});

// 管理画面: 作成者に関わらず任意のTierを削除する(通報対応・利用規約違反等)。
export const adminDeleteTopic = onCall(callableOptions, async (request) => {
  const firestore = getFirestore();
  await assertAdmin(firestore, request);

  const topicId = request.data?.topicId;
  if (typeof topicId !== "string" || topicId.length === 0) {
    throw new HttpsError("invalid-argument", "topicIdが必要です");
  }
  const reference = firestore.collection("topics").doc(topicId);
  const snapshot = await reference.get();
  if (!snapshot.exists) return {ok: true};
  const creatorId = snapshot.data()?.creatorId as string | undefined;

  await reference.set({deleting: true}, {merge: true});
  await deleteSharedImagesForTopic(firestore, getStorage(), topicId);
  await firestore.recursiveDelete(reference);
  if (creatorId) {
    try {
      await getStorage().bucket().deleteFiles({
        prefix: `users/${creatorId}/topics/${topicId}/`,
      });
    } catch (error) {
      console.error("adminDeleteTopic: failed to clean up storage files", error);
    }
  }
  return {ok: true};
});

// 管理画面: 共有画像キャッシュ(sharedItemImages)を名前の前方一致で検索する。
// クエリが空の場合は新着順で一覧表示する。
export const adminSearchSharedImages = onCall(callableOptions, async (request) => {
  const firestore = getFirestore();
  await assertAdmin(firestore, request);

  const rawQuery = typeof request.data?.query === "string" ?
    request.data.query.trim() : "";
  let query: FirebaseFirestore.Query = firestore.collection(SHARED_IMAGE_COLLECTION);
  if (rawQuery.length > 0) {
    const normalized = normalizeImageName(rawQuery);
    query = query
      .orderBy("normalizedName")
      .startAt(normalized)
      .endAt(normalized + "");
  } else {
    query = query.orderBy("createdAt", "desc");
  }
  const snapshot = await query.limit(50).get();
  return {
    results: snapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
      createdAt: undefined,
      updatedAt: undefined,
    })),
  };
});

// 管理画面: 共有画像キャッシュを検索対象から非表示/再表示する(物理削除しない)。
export const adminSetSharedImageHidden = onCall(callableOptions, async (request) => {
  const firestore = getFirestore();
  await assertAdmin(firestore, request);

  const key = request.data?.key;
  const hidden = request.data?.hidden;
  if (typeof key !== "string" || key.length === 0 || typeof hidden !== "boolean") {
    throw new HttpsError("invalid-argument", "パラメータが不正です");
  }
  await firestore.collection(SHARED_IMAGE_COLLECTION).doc(key).set({
    hidden,
    hiddenReason: hidden ? "adminHidden" : FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {ok: true};
});

// 管理画面: 共有画像キャッシュをStorage/Firestoreから完全に削除する。
export const adminDeleteSharedImage = onCall(callableOptions, async (request) => {
  const firestore = getFirestore();
  await assertAdmin(firestore, request);

  const key = request.data?.key;
  if (typeof key !== "string" || key.length === 0) {
    throw new HttpsError("invalid-argument", "keyが必要です");
  }
  const reference = firestore.collection(SHARED_IMAGE_COLLECTION).doc(key);
  const snapshot = await reference.get();
  const storagePath = snapshot.data()?.storagePath;
  if (typeof storagePath === "string" && storagePath.length > 0) {
    await getStorage().bucket().file(storagePath).delete({ignoreNotFound: true});
  }
  await reference.delete();
  return {ok: true};
});

export const getNgWordConfig = onCall(callableOptions, async (request) => {
  const firestore = getFirestore();
  await assertAdmin(firestore, request);
  return loadNgWordConfig(firestore);
});

export const updateNgWordConfig = onCall(callableOptions, async (request) => {
  const firestore = getFirestore();
  await assertAdmin(firestore, request);
  return updateNgWordConfigForAdmin(firestore, request.data ?? {});
});

export const getDailyCreateStatus = onCall(callableOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  return getDailyStatus(
    getFirestore(),
    request.auth.uid,
    isAnonymousRequest(request.auth.token),
  );
});

export const requestCreateAdBonusToken = onCall(callableOptions, async (request) => {
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

export const confirmCreateAdBonus = onCall(callableOptions, async (request) => {
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

// ---------------------------------------------------------------------------
// Bingo Online (lib/bingo). Boards live in `bingos/{bingoId}` with
// `bingoEntries`, `comments` and `reports` subcollections. Pure rules are in
// bingo.ts; moderation, NG words and rate limits are shared with Tier.
// ---------------------------------------------------------------------------

const BINGO_ID_PATTERN = /^[A-Za-z0-9_-]{6,64}$/;

function assertBingoCaller(request: {
  auth?: {uid: string; token: Record<string, unknown>};
}): {uid: string; anonymous: boolean} {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  const token = request.auth.token as {
    firebase?: {sign_in_provider?: string};
    email_verified?: boolean;
  };
  if (requiresUnverifiedEmailBlock(token)) {
    throw new HttpsError(
      "permission-denied",
      "メールアドレスの確認が完了していません",
    );
  }
  return {uid: request.auth.uid, anonymous: isAnonymousRequest(token)};
}

function bingoIdFrom(data: Record<string, unknown>): string {
  const bingoId = data.bingoId;
  if (typeof bingoId !== "string" || !BINGO_ID_PATTERN.test(bingoId) ||
    bingoId.startsWith("sample-")) {
    throw new HttpsError("invalid-argument", "bingoIdが不正です");
  }
  return bingoId;
}

export const publishBingo = onCall(callableOptions, async (request) => {
  const {uid, anonymous} = assertBingoCaller(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const bingoId = bingoIdFrom(data);
  const firestore = getFirestore();
  const input = validateBingoInput(data, {
    uid,
    bingoId,
    bucket: getStorage().bucket().name,
  });

  const moderation = moderateText({
    title: input.title,
    description: input.description,
    tags: input.tags.join(" "),
    cells: input.cells.map((cell) => cell.text ?? "").join(" "),
    creatorName: input.creatorName,
  }, await loadNgWordConfig(firestore));
  if (moderation.status === "blocked") {
    throw new HttpsError(
      "failed-precondition",
      "不適切な内容が含まれているため公開できません",
    );
  }

  const limits = await loadLimits(firestore);
  const limit = (anonymous ? limits.anonymous : limits.authenticated).bingoPublish;
  const reference = firestore.collection("bingos").doc(bingoId);
  const rateLimitReference = rateLimitRef(firestore, uid);
  const targetRegion = (SUPPORTED_REGION_CODES as readonly string[])
    .includes(String(data.targetRegion)) ? String(data.targetRegion) : "GLOBAL";

  await firestore.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    if (existing.exists) {
      // Cards reference pool indices, so a published board is immutable.
      throw new HttpsError("already-exists", "このビンゴは既に公開されています");
    }
    const rateLimitSnapshot = await transaction.get(rateLimitReference);
    transaction.set(
      rateLimitReference,
      computeRateLimitUpdate(rateLimitSnapshot.data() ?? {}, limit, "bingoPublish"),
      {merge: true},
    );
    transaction.set(reference, {
      ...input,
      creatorId: uid,
      contentLanguage: normalizeLocale(data.sourceLanguage ?? data.contentLanguage),
      sourceLanguage: firestoreLanguage(data.sourceLanguage ?? data.contentLanguage),
      targetRegion,
      listed: input.isPublic,
      moderationStatus: moderation.status,
      moderationReasons: moderation.reasons,
      participants: 0,
      bingoCount: 0,
      markCounts: {},
      appearanceCounts: {},
      commentCount: 0,
      reportCount: 0,
      createdByAnonymous: anonymous,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return {moderationStatus: moderation.status};
});

export const deleteBingo = onCall(callableOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  const uid = request.auth.uid;
  const bingoId = bingoIdFrom((request.data ?? {}) as Record<string, unknown>);
  const firestore = getFirestore();
  const reference = firestore.collection("bingos").doc(bingoId);
  const snapshot = await reference.get();
  if (snapshot.exists && snapshot.data()?.creatorId !== uid) {
    throw new HttpsError("permission-denied", "作成者だけが削除できます");
  }
  if (snapshot.exists) {
    await reference.set({deleting: true, listed: false}, {merge: true});
    await firestore.recursiveDelete(reference);
  }
  try {
    await getStorage().bucket().deleteFiles({
      prefix: `users/${uid}/bingos/${bingoId}/`,
    });
  } catch (error) {
    console.error("deleteBingo: failed to clean up storage files", error);
  }
  return {ok: true};
});

export const postBingoComment = onCall(callableOptions, async (request) => {
  const {uid, anonymous} = assertBingoCaller(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const bingoId = bingoIdFrom(data);
  const body = typeof data.body === "string" ? data.body.normalize("NFC").trim() : "";
  if (body.length > BINGO_MAX_COMMENT) {
    throw new HttpsError("invalid-argument", "コメントが長すぎます");
  }
  const authorName = (typeof data.authorName === "string" ?
    data.authorName.trim().slice(0, BINGO_MAX_AUTHOR_NAME) : "") || "Guest";
  const attachResult = data.attachResult === true;
  if (body.length === 0 && !attachResult) {
    throw new HttpsError("invalid-argument", "コメントが空です");
  }

  const firestore = getFirestore();
  const board = firestore.collection("bingos").doc(bingoId);
  const boardSnapshot = await board.get();
  const boardData = boardSnapshot.data();
  if (!boardData || boardData.deleting === true ||
    (boardData.listed !== true && boardData.creatorId !== uid)) {
    throw new HttpsError("not-found", "ビンゴが見つかりません");
  }

  const moderation = moderateText({body, authorName}, await loadNgWordConfig(firestore));
  if (moderation.status === "blocked") {
    throw new HttpsError(
      "failed-precondition",
      "不適切な内容が含まれているため投稿できません",
    );
  }

  // The result is copied from the stored card on the server, so a comment can
  // only show the author's real marks.
  let result: Record<string, unknown> | null = null;
  if (attachResult) {
    const entry = (await board.collection("bingoEntries").doc(uid).get()).data();
    const size = Number(boardData.size);
    const freeCenter = boardData.freeCenter !== false;
    const cellCount = Array.isArray(boardData.cells) ? boardData.cells.length : 0;
    if (entry && isValidLayout(size, freeCenter, cellCount, entry.layout)) {
      const marked = (Array.isArray(entry.marked) ? entry.marked : [])
        .filter((value: unknown) => Number.isInteger(value) &&
          (value as number) >= 0 && (value as number) < size * size);
      result = {
        size,
        layout: entry.layout,
        marked,
        lines: lineCount(size, entry.layout, marked),
      };
    }
  }

  const limits = await loadLimits(firestore);
  const limit = (anonymous ? limits.anonymous : limits.authenticated).bingoComment;
  const rateLimitReference = rateLimitRef(firestore, uid);
  const comment = board.collection("comments").doc();
  await firestore.runTransaction(async (transaction) => {
    const rateLimitSnapshot = await transaction.get(rateLimitReference);
    transaction.set(
      rateLimitReference,
      computeRateLimitUpdate(rateLimitSnapshot.data() ?? {}, limit, "bingoComment"),
      {merge: true},
    );
    transaction.set(comment, {
      authorId: uid,
      authorName,
      body,
      ...(result ? {result} : {}),
      moderationStatus: moderation.status,
      moderationReasons: moderation.reasons,
      hidden: false,
      reportCount: 0,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return {id: comment.id, result};
});

export const aggregateBingoEntries = onDocumentWritten(
  "bingos/{bingoId}/bingoEntries/{userId}",
  async (event) => {
    const firestore = getFirestore();
    const board = firestore.collection("bingos").doc(event.params.bingoId);
    const [boardSnapshot, entries] = await Promise.all([
      board.get(),
      board.collection("bingoEntries").get(),
    ]);
    const data = boardSnapshot.data();
    if (!data || data.deleting === true) return;
    const aggregate = aggregateBingo(
      Number(data.size),
      data.freeCenter !== false,
      Array.isArray(data.cells) ? data.cells.length : 0,
      entries.docs.map((document) => document.data() as BingoEntryData),
    );
    await board.update({...aggregate, updatedAt: FieldValue.serverTimestamp()});
  },
);

export const countBingoComments = onDocumentWritten(
  "bingos/{bingoId}/comments/{commentId}",
  async (event) => {
    const created = !event.data?.before.exists && event.data?.after.exists;
    const deleted = event.data?.before.exists && !event.data?.after.exists;
    if (!created && !deleted) return;
    const board = getFirestore().collection("bingos").doc(event.params.bingoId);
    const snapshot = await board.get();
    if (!snapshot.exists || snapshot.data()?.deleting === true) return;
    await board.update({commentCount: FieldValue.increment(created ? 1 : -1)});
  },
);

export const onBingoReportCreated = onDocumentCreated(
  "bingos/{bingoId}/reports/{reportId}",
  async (event) => {
    const report = event.data?.data();
    if (!report) return;
    const firestore = getFirestore();
    const board = firestore.collection("bingos").doc(event.params.bingoId);
    const target = report.targetType === "comment" ?
      board.collection("comments").doc(String(report.targetId)) :
      board;
    await firestore.runTransaction(async (transaction) => {
      const [boardSnapshot, targetSnapshot] = await Promise.all([
        transaction.get(board),
        transaction.get(target),
      ]);
      if (!boardSnapshot.exists || boardSnapshot.data()?.deleting === true ||
        !targetSnapshot.exists) {
        return;
      }
      const reportCount = Number(targetSnapshot.data()?.reportCount ?? 0) + 1;
      const update: Record<string, unknown> = {reportCount};
      if (reportCount >= BINGO_REPORT_HIDE_THRESHOLD) {
        if (report.targetType === "comment") {
          update.hidden = true;
        } else {
          update.moderationStatus = "blocked";
          update.listed = false;
        }
      }
      transaction.update(target, update);
    });
  },
);
