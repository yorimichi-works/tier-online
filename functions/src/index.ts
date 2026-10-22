import {initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {setGlobalOptions} from "firebase-functions/v2";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {defineBoolean} from "firebase-functions/params";
import {createHash, randomUUID} from "node:crypto";

import {assertAdmin, loadNgWordConfig, updateNgWordConfigForAdmin} from "./adminConfig";
import {
  advanceAnonymousDataTransfer,
  startAnonymousDataTransfer,
} from "./anonymousAccountMigration";
import {
  deleteAccountData,
  deleteExpiredAnonymousData,
  deleteSharedImagesForTopic,
} from "./accountDeletion";
import {
  applySubmissionDelta,
  incrementalAggregateFrom,
  IncrementalAggregate,
  Placements,
} from "./aggregation";
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
  collectReplyAuthorIds,
  deleteReplyTree,
  findReplyBody,
  setLegacyReplyReaction,
  setReplyBody,
} from "./talkModeration";
import {
  firestoreLanguage,
  normalizeLocale,
  wikipediaLanguage,
} from "./internationalization";
import {
  customTagsFromUnknown,
  inheritLegacyTagTranslations,
  markCustomTagTranslationsPending,
  prepareCustomTags,
  searchTagsFor,
} from "./customTags";
import {topicSearchTokens} from "./searchTokens";
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

export {
  canonicalLocaleRedirect,
  renderHome,
  renderTopic,
  robots,
  sitemap,
  sitemapLocale,
} from "./seo";

export const getAdminStatus = onCall(callableOptions, async (request) => {
  if (!request.auth) return {isAdmin: false};
  const snapshot = await getFirestore().collection("admins")
    .doc(request.auth.uid).get();
  return {isAdmin: snapshot.exists};
});

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

// A deliberately small, Firestore-native first-stage search index.  It is not
// intended to replace a dedicated full-text engine at large scale, but it
// avoids filtering an arbitrary first 50 topics on the client.  Tokens include
// whole words and short 2-character n-grams, which work for Japanese, Korean,
// Chinese, and Latin scripts without locale-specific word segmentation.
export {topicSearchTokens} from "./searchTokens";

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

function isFirebaseDownloadUrlForPath(value: unknown, storagePath: string): boolean {
  return typeof value === "string" && value.includes(
    `/o/${encodeURIComponent(storagePath)}?`,
  );
}

// Firebase download-token URLs can be read by anyone who already knows the
// token, even after normal Storage rules become more restrictive.  Rotate the
// tokens whenever a Tier stops being public so previously copied URLs stop
// working.  The fresh URLs are written only to the now-private documents and
// remain available to the owner through the normal authenticated app flow.
async function rotateTopicImageDownloadTokens(
  topicId: string,
  creatorId: unknown,
): Promise<void> {
  if (typeof creatorId !== "string" || creatorId.length === 0) return;
  const firestore = getFirestore();
  const topic = firestore.collection("topics").doc(topicId);
  const [topicSnapshot, itemsSnapshot] = await Promise.all([
    topic.get(),
    topic.collection("items").get(),
  ]);
  if (!topicSnapshot.exists) return;

  const bucket = getStorage().bucket();
  const prefix = `users/${creatorId}/topics/${topicId}/items/`;
  const [files] = await bucket.getFiles({prefix});
  const rotatedUrls = new Map<string, string>();
  // User-created Tiers have a bounded item count.  Keep this sequential so a
  // one-off privacy operation does not fan out unbounded Storage requests.
  for (const file of files) {
    const token = randomUUID();
    await file.setMetadata({
      metadata: {firebaseStorageDownloadTokens: token},
    });
    rotatedUrls.set(file.name, firebaseDownloadUrl(bucket.name, file.name, token));
  }
  if (rotatedUrls.size === 0) return;

  const batch = firestore.batch();
  for (const item of itemsSnapshot.docs) {
    const storagePath = `${prefix}${item.id}.jpg`;
    const replacement = rotatedUrls.get(storagePath);
    if (replacement != null &&
        isFirebaseDownloadUrlForPath(item.data().imageUrl, storagePath)) {
      batch.update(item.ref, {imageUrl: replacement});
    }
  }
  const thumbnailUrl = topicSnapshot.data()?.thumbnailUrl;
  for (const [storagePath, replacement] of rotatedUrls) {
    if (isFirebaseDownloadUrlForPath(thumbnailUrl, storagePath)) {
      batch.update(topic, {thumbnailUrl: replacement});
      break;
    }
  }
  batch.set(topic, {
    imageDownloadTokensRotatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await batch.commit();
}

// 「アリス」のような同じ名前でも、作品が違えば別キャラである可能性がある。
// 1名前=1画像だった旧構造を、名前(グループ)の下に複数の画像候補(バリアント)
// を持てる構造へ拡張したもの。衝突がない大多数のケースでは、グループの
// 最初の1件目が自動的にqualifier無しのバリアントとして登録されるだけで、
// ユーザーへの追加確認は発生しない(docs/shared_image_disambiguation.md 3章)。
type VariantModerationStatus = "pending" | "approved";

function variantModerationStatusFor(topicModerationStatus: string): VariantModerationStatus {
  return topicModerationStatus === "approved" ? "approved" : "pending";
}

async function cacheSharedUploadedImages(params: {
  uid: string;
  topicId: string;
  locale: string;
  items: PublishItem[];
  topicModerationStatus: string;
}): Promise<void> {
  const firestore = getFirestore();
  const bucket = getStorage().bucket();
  const moderationStatus = variantModerationStatusFor(params.topicModerationStatus);
  await Promise.all(params.items.map(async (item) => {
    const name = item.name?.trim();
    if (!item.id || !name) return;
    // ユーザーが既存バリアントと同一だと確認した場合は、新規登録しない
    // (共有プールに重複登録しないだけで、本人のTier表の表示には影響しない)。
    if (item.sharedImageSelection?.variantId) return;

    const groupKey = sharedImageKey(name, params.locale);
    const groupReference = firestore.collection(SHARED_IMAGE_COLLECTION).doc(groupKey);

    // Only images uploaded for this exact topic are shareable. Asset images and
    // third-party URLs are intentionally excluded from the shared cache.
    const sourcePath = `users/${params.uid}/topics/${params.topicId}/items/${item.id}.jpg`;
    const source = bucket.file(sourcePath);
    const [exists] = await source.exists();
    if (!exists) return;

    const variantReference = groupReference.collection("variants").doc();
    const destinationPath = `shared-item-images/${groupKey}/${variantReference.id}.jpg`;
    const destination = bucket.file(destinationPath);
    const token = randomUUID();
    await source.copy(destination);
    await destination.setMetadata({
      cacheControl: "public,max-age=31536000,immutable",
      metadata: {firebaseStorageDownloadTokens: token},
    });

    const qualifier = item.sharedImageSelection?.qualifier?.trim() || null;
    await firestore.runTransaction(async (transaction) => {
      transaction.set(groupReference, {
        normalizedName: normalizeImageName(name),
        locale: params.locale,
        createdAt: FieldValue.serverTimestamp(),
        variantCount: FieldValue.increment(1),
      }, {merge: true});
      transaction.create(variantReference, {
        displayName: name,
        qualifier,
        locale: params.locale,
        imageUrl: firebaseDownloadUrl(bucket.name, destinationPath, token),
        storagePath: destinationPath,
        sourceTopicId: params.topicId,
        sourceItemId: item.id,
        moderationStatus,
        hidden: false,
        createdAt: FieldValue.serverTimestamp(),
      });
    });
  }));
}

// 元Tierのモデレーション状態が変わった際、そこから共有領域へ複製された
// バリアントの状態も追従させる。ブロック時はhiddenを立てて検索対象から
// 外す(物理削除はせず、誤ブロック解除時に復元できるようにする)。承認時は
// pending→approvedにして、他ユーザーの候補一覧に出せるようにする。
async function syncSharedImageVariantsForTopic(
  topicId: string,
  topicModerationStatus: string,
): Promise<void> {
  const firestore = getFirestore();
  const snapshot = await firestore
    .collectionGroup("variants")
    .where("sourceTopicId", "==", topicId)
    .get();
  if (snapshot.empty) return;
  const hidden = topicModerationStatus === "blocked";
  const moderationStatus = variantModerationStatusFor(topicModerationStatus);
  const batch = firestore.batch();
  for (const doc of snapshot.docs) {
    batch.set(doc.ref, {
      hidden,
      hiddenReason: hidden ? "sourceTopicBlocked" : FieldValue.delete(),
      moderationStatus,
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
    // 名前ごとに承認済み・非表示でない最古のバリアントを1件だけ使う。複数
    // バリアントがある場合の候補一覧表示はlookupSharedImageVariantsで別途
    // 行う(docs/shared_image_disambiguation.md 5.3)。
    const results = await Promise.all(names.map(async (query) => {
      const groupKey = sharedImageKey(query, locale);
      const variantSnapshot = await firestore
        .collection(SHARED_IMAGE_COLLECTION).doc(groupKey)
        .collection("variants")
        .where("moderationStatus", "==", "approved")
        .where("hidden", "==", false)
        .orderBy("createdAt", "asc")
        .limit(1)
        .get();
      const cached = variantSnapshot.docs[0]?.data();
      const cachedImageUrl = cached?.imageUrl;
      if (typeof cachedImageUrl === "string" && cachedImageUrl.length > 0) {
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

// アイテムに名前をつけてアップロードするとき、既に共有プールへ登録された
// 同名画像の候補(バリアント)を一覧取得する。承認済み・非表示でないものだけ
// を返す(モデレーション未確定のものを他ユーザーへ見せない)。
export const lookupSharedImageVariants = onCall(callableOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  const name = typeof request.data?.name === "string" ? request.data.name.trim() : "";
  if (!name || name.length > 100) {
    throw new HttpsError("invalid-argument", "nameが必要です");
  }
  const locale = normalizeLocale(request.data?.locale);
  const groupKey = sharedImageKey(name, locale);
  const snapshot = await getFirestore()
    .collection(SHARED_IMAGE_COLLECTION).doc(groupKey)
    .collection("variants")
    .where("moderationStatus", "==", "approved")
    .where("hidden", "==", false)
    .orderBy("createdAt", "asc")
    .limit(5)
    .get();
  return {
    variants: snapshot.docs.map((doc) => ({
      variantId: doc.id,
      imageUrl: doc.data().imageUrl as string,
      qualifier: (doc.data().qualifier as string | null) ?? null,
    })),
  };
});

type SubmissionAggregateInput = {
  placements: Placements;
  region: string;
};

function submissionInput(
  data: FirebaseFirestore.DocumentData | undefined,
): SubmissionAggregateInput | undefined {
  if (!data) return undefined;
  return {
    placements: (data.placements ?? {}) as Placements,
    region: typeof data.region === "string" && data.region.length > 0 ?
      data.region : "JP",
  };
}

function placementsForRegion(
  input: SubmissionAggregateInput | undefined,
  region: string,
): Placements | undefined {
  if (!input || (region !== "GLOBAL" && input.region !== region)) return undefined;
  return input.placements;
}

function aggregateFields(aggregate: IncrementalAggregate) {
  return {
    participants: aggregate.participants,
    community: aggregate.community,
    distributions: aggregate.distributions,
    disagreement: aggregate.disagreement,
  };
}

function storedItemIds(data: FirebaseFirestore.DocumentData | undefined): string[] {
  const value = data?.itemIds;
  return Array.isArray(value) ? value.filter((id): id is string => typeof id === "string") : [];
}

async function deleteTierAggregationStats(
  firestore: FirebaseFirestore.Firestore,
  topicId: string,
): Promise<void> {
  while (true) {
    const snapshot = await firestore.collection("tierRegionStats")
      .where("tierId", "==", topicId)
      .limit(400)
      .get();
    if (snapshot.empty) return;
    const batch = firestore.batch();
    for (const document of snapshot.docs) batch.delete(document.ref);
    await batch.commit();
    if (snapshot.size < 400) return;
  }
}

function itemIdsIn(placements: Placements | undefined): string[] {
  if (!placements) return [];
  return [...new Set(Object.values(placements).flatMap((itemIds) => itemIds ?? []))]
    .filter((itemId): itemId is string => typeof itemId === "string" && itemId.length > 0);
}

// 1投票につき全submissionを読み直すのではなく、CloudEventが持つbefore/after
// 差分だけをGlobal・変更前地域・変更後地域の集計へ反映する。event receiptを
// transaction内に残し、少なくとも1回配送のFunctions再試行でも二重加算しない。
export const aggregateTopicTier = onDocumentWritten(
  "topics/{topicId}/submissions/{userId}",
  async (event) => {
    const before = submissionInput(event.data?.before.data());
    const after = submissionInput(event.data?.after.data());
    const samePlacements = JSON.stringify(before?.placements ?? {}) ===
      JSON.stringify(after?.placements ?? {});
    if (before?.region === after?.region && samePlacements) return;

    const topicId = event.params.topicId;
    const userId = event.params.userId;
    const database = getFirestore();
    const topic = database.collection("topics").doc(topicId);
    const participationReference = database.collection("users").doc(userId)
      .collection("participations").doc(topicId);
    const globalReference = database.collection("tierRegionStats").doc(`${topicId}_GLOBAL`);
    const regions = new Set(["GLOBAL"]);
    if (before != null) regions.add(before.region);
    if (after != null) regions.add(after.region);
    const regionReferences = [...regions].map((region) => ({
      region,
      reference: database.collection("tierRegionStats").doc(`${topicId}_${region}`),
    }));
    const receipt = topic.collection("aggregationEvents").doc(event.id);

    await database.runTransaction(async (transaction) => {
      // Cloud Functionsの少なくとも1回配送では同じevent.idが再試行され得る。
      // receiptだけを先に確認して、再試行時は集計文書すら読まずにno-opにする。
      const receiptSnapshot = await transaction.get(receipt);
      if (receiptSnapshot.exists) return;
      const [topicSnapshot, globalSnapshot, ...regionalSnapshots] = await Promise.all([
        transaction.get(topic),
        transaction.get(globalReference),
        ...regionReferences
          .filter(({region}) => region !== "GLOBAL")
          .map(({reference}) => transaction.get(reference)),
      ]);
      if (
        !topicSnapshot.exists ||
        topicSnapshot.data()?.deleting === true ||
        topicSnapshot.data()?.aggregationRebuilding === true
      ) {
        // A recursively deleted Tier still emits child deletion events. Keep
        // the per-user activity mirror from becoming an orphan in that case.
        if (after == null) transaction.delete(participationReference);
        return;
      }

      // itemIds は初回だけitemsサブコレクションから取得する。以降は集計文書に
      // 保持するため、投票数Nに比例したitem読み取りも発生しない。Tierの編集で
      // 後から追加されたカードは、最初に投票された時だけ対象docを直接確認して
      // 加える(全itemsの再scanはしない)。
      let itemIds = storedItemIds(globalSnapshot.data());
      if (itemIds.length === 0) {
        const items = await transaction.get(topic.collection("items").orderBy("sortIndex"));
        itemIds = items.docs.map((document) => document.id);
      } else {
        const known = new Set(itemIds);
        const candidates = [...new Set([
          ...itemIdsIn(before?.placements),
          ...itemIdsIn(after?.placements),
        ])].filter((itemId) => !known.has(itemId));
        if (candidates.length > 0) {
          const itemSnapshots = await Promise.all(candidates.map((itemId) =>
            transaction.get(topic.collection("items").doc(itemId)),
          ));
          itemIds = [...itemIds, ...itemSnapshots
            .filter((snapshot) => snapshot.exists)
            .map((snapshot) => snapshot.id)];
        }
      }
      const globalSeed = globalSnapshot.exists &&
          globalSnapshot.data()?.aggregationVersion === 2 ?
        globalSnapshot.data() : topicSnapshot.data();
      const globalAggregate = applySubmissionDelta(
        incrementalAggregateFrom(itemIds, globalSeed),
        before?.placements,
        after?.placements,
      );
      transaction.set(topic, {
        ...aggregateFields(globalAggregate),
        ...starterCreatorFields(topicId),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(globalReference, {
        tierId: topicId,
        region: "GLOBAL",
        ...aggregateFields(globalAggregate),
        itemIds,
        aggregationVersion: 2,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      let snapshotIndex = 0;
      for (const {region, reference} of regionReferences) {
        if (region === "GLOBAL") continue;
        const regionalSnapshot = regionalSnapshots[snapshotIndex++];
        const regionalSeed = regionalSnapshot.exists &&
            regionalSnapshot.data()?.aggregationVersion === 2 ?
          regionalSnapshot.data() : regionalSnapshot.data();
        const regionalAggregate = applySubmissionDelta(
          incrementalAggregateFrom(itemIds, regionalSeed),
          placementsForRegion(before, region),
          placementsForRegion(after, region),
        );
        transaction.set(reference, {
          tierId: topicId,
          region,
          ...aggregateFields(regionalAggregate),
          itemIds,
          aggregationVersion: 2,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
      transaction.set(receipt, {
        eventId: event.id,
        expiresAt: new Date(Date.now() + 1000 * 60 * 60 * 24 * 14),
        createdAt: FieldValue.serverTimestamp(),
      });
      // Maintain a compact per-user index at the same time as the existing
      // aggregate transaction.  App bootstrap can now read only this user's
      // documents instead of an unbounded collectionGroup scan.
      if (after == null) {
        transaction.delete(participationReference);
      } else {
        const afterData = event.data?.after.data() ?? {};
        transaction.set(participationReference, {
          topicId,
          userId,
          placements: after.placements,
          region: after.region,
          contentLanguage: afterData.contentLanguage ?? null,
          sourceLanguage: afterData.sourceLanguage ?? null,
          createdAt: afterData.createdAt ?? FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
    });
  },
);

export const aggregateTopicLikes = onDocumentWritten(
  "topics/{topicId}/likes/{userId}",
  async (event) => {
    const beforeExists = event.data?.before.exists === true;
    const afterExists = event.data?.after.exists === true;
    const delta = Number(afterExists) - Number(beforeExists);
    if (delta === 0) return;
    const topic = getFirestore().collection("topics").doc(event.params.topicId);
    const userLikeReference = getFirestore().collection("users").doc(event.params.userId)
      .collection("likeRefs").doc(event.params.topicId);
    const receipt = getFirestore().doc(
      `topicLikeAggregationReceipts/${event.id}`,
    );
    await getFirestore().runTransaction(async (transaction) => {
      const [topicSnapshot, receiptSnapshot] = await Promise.all([
        transaction.get(topic),
        transaction.get(receipt),
      ]);
      if (receiptSnapshot.exists) return;
      if (!topicSnapshot.exists || topicSnapshot.data()?.deleting === true) {
        if (!afterExists) transaction.delete(userLikeReference);
        return;
      }
      transaction.set(topic, {
        likeCount: Math.max(
          0,
          nonNegativeCounter(topicSnapshot.data()?.likeCount) + delta,
        ),
        ...starterCreatorFields(event.params.topicId),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(receipt, {
        eventId: event.id,
        topicId: event.params.topicId,
        expiresAt: new Date(Date.now() + 1000 * 60 * 60 * 24 * 30),
        createdAt: FieldValue.serverTimestamp(),
      });
      if (afterExists) {
        transaction.set(userLikeReference, {
          topicId: event.params.topicId,
          userId: event.params.userId,
          createdAt: event.data?.after.data()?.createdAt ??
            FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      } else {
        transaction.delete(userLikeReference);
      }
    });
  },
);

// コメント件数をTier本文へ保持する。表示時にtalks全件を数えないための
// 集計値で、リアクション更新など存在状態が変わらない書き込みはno-opにする。
export const aggregateTopicCommentCount = onDocumentWritten(
  "topics/{topicId}/talks/{talkId}",
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    const beforeCounted = before?.exists && before.data()?.isDeleted !== true;
    const afterCounted = after?.exists && after.data()?.isDeleted !== true;
    const delta = Number(afterCounted) - Number(beforeCounted);
    if (delta === 0) return;
    const topic = getFirestore().collection("topics").doc(event.params.topicId);
    const topicSnapshot = await topic.get();
    if (!topicSnapshot.exists || topicSnapshot.data()?.deleting === true) return;
    await topic.update({
      commentCount: FieldValue.increment(delta),
      updatedAt: FieldValue.serverTimestamp(),
    });
  },
);

// 新形式の返信はコメント文書と分離して保存する。返信数も親コメントの
// スカラー値だけを更新し、返信本文の配列を読み書きしない。
export const aggregateTalkReplyCount = onDocumentWritten(
  "topics/{topicId}/talks/{talkId}/replies/{replyId}",
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    const beforeCounted = before?.exists && before.data()?.isDeleted !== true;
    const afterCounted = after?.exists && after.data()?.isDeleted !== true;
    const delta = Number(afterCounted) - Number(beforeCounted);
    if (delta === 0) return;
    const talk = getFirestore().doc(
      `topics/${event.params.topicId}/talks/${event.params.talkId}`,
    );
    const talkSnapshot = await talk.get();
    if (!talkSnapshot.exists || talkSnapshot.data()?.isDeleted === true) return;
    await talk.update({
      replyCount: FieldValue.increment(delta),
      updatedAt: FieldValue.serverTimestamp(),
    });
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
  // 同名の共有画像候補がある場合に、ユーザーが選んだ結果。
  // variantId: 既存バリアントと同一だと確認した(新規登録しない)。
  // qualifier: 「同じものはない」を選び、作品名等の補足情報を入力した。
  sharedImageSelection?: {
    variantId?: string;
    qualifier?: string;
  };
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
  const incomingSourceLocale = firestoreLanguage(
    data.sourceLocale ?? data.sourceLanguage ?? data.contentLanguage,
  );
  let incomingCustomTags;
  try {
    // Validate and normalize before moderation. The transaction below repeats
    // this conversion with existing records so unchanged source tags retain
    // their opaque IDs and any manual translations.
    incomingCustomTags = prepareCustomTags(data.tags, incomingSourceLocale, []);
  } catch (error: unknown) {
    throw new HttpsError(
      "invalid-argument",
      error instanceof Error ? error.message : "タグの形式が正しくありません",
    );
  }
  const sourceTagTexts = incomingCustomTags.map((tag) => tag.sourceText);
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
  const publishedItemCount = new Set(
    items
      .map((item) => typeof item.id === "string" ? item.id.trim() : "")
      .filter((id) => id.length > 0),
  ).size;
  // 一覧用サムネイルはクライアントがアップロードした先頭画像を指す。
  // 親ドキュメントへ要約を保存することで、一覧を描画するたびに各Tierの
  // items サブコレクションを1件ずつ読むN+1を避ける。
  const requestedThumbnailItemId = typeof data.thumbnailItemId === "string" ?
    data.thumbnailItemId : undefined;
  const thumbnailItem = requestedThumbnailItemId ?
    items.find((item) => item.id === requestedThumbnailItemId) : undefined;
  const thumbnailUrl = thumbnailItem && typeof data.thumbnailUrl === "string" &&
      data.thumbnailUrl.trim().length > 0 ? data.thumbnailUrl : null;
  const config = await loadNgWordConfig(firestore);
  const moderationFields: Record<string, string> = {
    title: String(data.title ?? ""),
    description: String(data.description ?? ""),
    creatorName: String(data.creatorName ?? ""),
    tags: sourceTagTexts.join(" "),
    itemNames: items.map((item) => item.name ?? "").join(" "),
    itemQualifiers: items
      .map((item) => item.sharedImageSelection?.qualifier ?? "")
      .join(" "),
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
    tags: sourceTagTexts,
    sourceLanguage: incomingSourceLocale,
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
    const sourceLocale = incomingSourceLocale;
    const originalLocale = firestoreLanguage(
      existingData.originalLocale ?? data.originalLocale ?? sourceLocale,
    );
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

    const baseCustomTags = prepareCustomTags(
      sourceTagTexts,
      sourceLocale,
      existingData.customTags,
    );
    const preparedCustomTags = customTagsFromUnknown(existingData.customTags).length === 0 &&
        !sourceChanged ?
      inheritLegacyTagTranslations(baseCustomTags, existingData.translations) :
      baseCustomTags;
    const customTags = sourceChanged ?
      markCustomTagTranslationsPending(preparedCustomTags, sourceLocale) :
      preparedCustomTags;
    const searchTags = searchTagsFor(customTags);
    const updatedSearchTokens = topicSearchTokens([
      data.title,
      data.description,
      data.category,
      data.categoryId,
      ...searchTags,
      ...items.map((item) => item.name),
    ]);
    transaction.set(topicReference, {
      title: data.title,
      description: data.description,
      // Legacy projection used by existing tag-chip filters. `customTags` is
      // the authoritative representation for free input tags.
      tags: customTags.map((tag) => tag.sourceText),
      customTags,
      searchTags,
      category: data.category,
      categoryId: data.categoryId,
      contentLanguage: normalizeLocale(sourceLocale),
      sourceLanguage: sourceLocale,
      sourceLocale,
      originalLocale,
      targetRegion: data.targetRegion,
      sourceTierId: data.sourceTierId ?? null,
      sourceTemplateId: data.sourceTemplateId ?? null,
      isLanguageNeutral: data.isLanguageNeutral ?? false,
      creatorName: data.creatorName,
      creatorId: uid,
      participants: data.participants ?? 0,
      // SEO indexability and sitemap generation must not query every items
      // subcollection. Keep a trusted server-side summary on the parent.
      itemCount: publishedItemCount,
      searchTokens: updatedSearchTokens,
      thumbnailUrl,
      thumbnailItemId: thumbnailUrl ? thumbnailItem?.id ?? null : null,
      thumbnailItemName: thumbnailUrl ? thumbnailItem?.name ?? null : null,
      thumbnailColorSeed: thumbnailUrl ? thumbnailItem?.colorSeed ?? 0 : null,
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
        hasTranslationReviewRequired: false,
        hasTranslationFailures: false,
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
        sharedImageVariantId: item.sharedImageSelection?.variantId ?? null,
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
        topicModerationStatus: moderation.status,
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
    await Promise.all([
      deleteSharedImagesForTopic(firestore, getStorage(), topicId),
      deleteTierAggregationStats(firestore, topicId),
    ]);
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

const ANONYMOUS_ARTIFACT_GRACE_DAYS = 31;

// Registering is intentionally cheap and idempotent.  It gives the cleanup
// job a bounded list of anonymous accounts; it never scans Firebase Auth or
// every comment/like in the project.
export const registerAnonymousLifecycle = onCall(callableOptions, async (request) => {
  if (!request.auth || !isAnonymousRequest(request.auth.token)) {
    throw new HttpsError("failed-precondition", "匿名アカウントが必要です");
  }
  const now = Date.now();
  await getFirestore().collection("anonymousUserLifecycle").doc(request.auth.uid).set({
    uid: request.auth.uid,
    createdAt: FieldValue.serverTimestamp(),
    eligibleAfter: new Date(
      now + ANONYMOUS_ARTIFACT_GRACE_DAYS * 24 * 60 * 60 * 1000,
    ),
    lastSeenAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {ok: true};
});

export const cleanupExpiredAnonymousArtifacts = onSchedule(
  {schedule: "every day 03:20", timeZone: "Asia/Tokyo", maxInstances: 1},
  async () => {
    const firestore = getFirestore();
    const candidates = await firestore.collection("anonymousUserLifecycle")
      .where("eligibleAfter", "<=", new Date())
      .orderBy("eligibleAfter")
      .limit(100)
      .get();
    for (const candidate of candidates.docs) {
      const uid = candidate.id;
      try {
        // Auth still exists: automatic cleanup has not happened, or the
        // account is active. Never remove its Firestore artifacts early.
        await getAuth().getUser(uid);
      } catch (error: unknown) {
        if ((error as {code?: string}).code !== "auth/user-not-found") {
          console.error("anonymous cleanup could not inspect auth user", uid, error);
          continue;
        }
        await deleteExpiredAnonymousData(firestore, getStorage(), uid);
      }
    }
  },
);

function nonNegativeCounter(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ?
    Math.max(0, Math.trunc(value)) : 0;
}

function canUseTopicInteraction(
  topic: Record<string, unknown>,
  uid: string,
): boolean {
  if (topic.creatorId === uid) return true;
  // moderationStatus未設定の(モデレーション導入前からある)Tierはapproved扱い
  // にする。firestore.rulesのisPubliclyVisibleTopic()と判定基準を揃えないと、
  // 古いTierへのいいね/うーん等がここだけpermission-deniedになってしまう。
  return topic.isPublic !== false &&
    (topic.moderationStatus == null || topic.moderationStatus === "approved") &&
    topic.hidden !== true &&
    topic.isHidden !== true &&
    topic.deleting !== true &&
    topic.deleted !== true &&
    topic.isDeleted !== true &&
    topic.isSpam !== true &&
    topic.spam !== true;
}

const MAX_CONTRIBUTED_IMAGE_BYTES = 5 * 1024 * 1024;

// 第三者が画像未設定のカードへ画像を提供できる。作成者本人の画像を上書き
// させないため、既に画像があるアイテムへは常に拒否する。承認フローは設け
// ず(ユーザー合意の上で)即時反映する — NGワード判定のような画像内容の
// 自動審査は対象外(通報での事後対応に委ねる)。
export const contributeItemImage = onCall(callableOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  if (isAnonymousRequest(request.auth.token)) {
    throw new HttpsError(
      "permission-denied",
      "ログインユーザーのみ画像を追加できます",
    );
  }
  if (requiresUnverifiedEmailBlock(request.auth.token)) {
    throw new HttpsError(
      "permission-denied",
      "メールアドレスの確認が完了していません",
    );
  }
  const data = request.data ?? {};
  const topicId = data.topicId;
  const itemId = data.itemId;
  const imageDataUri = data.imageDataUri;
  if (
    typeof topicId !== "string" || topicId.length === 0 || topicId.includes("/") ||
    typeof itemId !== "string" || itemId.length === 0 || itemId.includes("/") ||
    typeof imageDataUri !== "string" || !imageDataUri.startsWith("data:image/")
  ) {
    throw new HttpsError("invalid-argument", "パラメータが不正です");
  }
  const comma = imageDataUri.indexOf(",");
  if (comma < 0) {
    throw new HttpsError("invalid-argument", "画像データが不正です");
  }
  const contentType = imageDataUri.slice(5, imageDataUri.indexOf(";"));
  const bytes = Buffer.from(imageDataUri.slice(comma + 1), "base64");
  if (bytes.length === 0 || bytes.length > MAX_CONTRIBUTED_IMAGE_BYTES) {
    throw new HttpsError("invalid-argument", "画像サイズが不正です");
  }

  const uid = request.auth.uid;
  const firestore = getFirestore();
  await checkAndConsume(firestore, uid, false, "contributeImage");

  const topicReference = firestore.collection("topics").doc(topicId);
  const itemReference = topicReference.collection("items").doc(itemId);
  const [topicSnapshot, itemSnapshot] = await Promise.all([
    topicReference.get(),
    itemReference.get(),
  ]);
  if (!topicSnapshot.exists || !canUseTopicInteraction(topicSnapshot.data() ?? {}, uid)) {
    throw new HttpsError("permission-denied", "このTierには操作できません");
  }
  if (!itemSnapshot.exists) {
    throw new HttpsError("not-found", "カードが見つかりません");
  }
  const existingImageUrl = itemSnapshot.data()?.imageUrl;
  if (typeof existingImageUrl === "string" && existingImageUrl.length > 0) {
    throw new HttpsError(
      "already-exists",
      "このカードには既に画像が設定されています",
    );
  }

  const ownerId = topicSnapshot.data()?.creatorId;
  if (typeof ownerId !== "string" || ownerId.length === 0) {
    throw new HttpsError("failed-precondition", "Tierの作成者情報が不正です");
  }
  const bucket = getStorage().bucket();
  const extension = contentType === "image/png" ? "png" : "jpg";
  const file = bucket.file(
    `users/${ownerId}/topics/${topicId}/items/${itemId}.${extension}`,
  );
  const downloadToken = randomUUID();
  await file.save(bytes, {
    contentType,
    metadata: {
      cacheControl: "public,max-age=3600",
      metadata: {firebaseStorageDownloadTokens: downloadToken},
    },
  });
  const imageUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
    `${encodeURIComponent(file.name)}?alt=media&token=${downloadToken}`;

  await itemReference.set({
    imageUrl,
    contributedByUserId: uid,
    contributedAt: FieldValue.serverTimestamp(),
  }, {merge: true});

  return {imageUrl};
});

/**
 * Store each user's reaction separately and update only the affected counter.
 * This prevents direct counter tampering, does not re-save sibling comments,
 * and is idempotent when a callable request is retried with the same desired
 * state.  Legacy embedded replies remain supported until the migration script
 * has emptied their arrays.
 */
export const setTalkReaction = onCall(callableOptions, async (request) => {
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
  const postId = data.postId;
  const replyId = data.replyId == null ? null : data.replyId;
  const desiredReaction = data.desiredReaction == null ? null : data.desiredReaction;
  if (
    typeof topicId !== "string" || topicId.length === 0 || topicId.includes("/") ||
    typeof postId !== "string" || postId.length === 0 || postId.includes("/") ||
    (replyId !== null && (typeof replyId !== "string" || replyId.length === 0 ||
      replyId.includes("/"))) ||
    (desiredReaction !== null && desiredReaction !== "up" && desiredReaction !== "down")
  ) {
    throw new HttpsError("invalid-argument", "パラメータが不正です");
  }

  const firestore = getFirestore();
  const uid = request.auth.uid;
  const topicReference = firestore.collection("topics").doc(topicId);
  const talkReference = topicReference.collection("talks").doc(postId);
  const reactionKey = createHash("sha256")
    .update(`${replyId ?? "root"}\u0000${uid}`)
    .digest("hex");
  const reactionReference = talkReference.collection("reactionStates").doc(reactionKey);
  const replyReference = replyId == null ? null :
    talkReference.collection("replies").doc(replyId);
  let result: {upvotes: number; downvotes: number; reaction: string | null} | null = null;

  await firestore.runTransaction(async (transaction) => {
    const [topicSnapshot, talkSnapshot, reactionSnapshot, replySnapshot] = await Promise.all([
      transaction.get(topicReference),
      transaction.get(talkReference),
      transaction.get(reactionReference),
      replyReference == null ? Promise.resolve(null) : transaction.get(replyReference),
    ]);
    if (!topicSnapshot.exists || !canUseTopicInteraction(topicSnapshot.data() ?? {}, uid)) {
      throw new HttpsError("permission-denied", "このTierには操作できません");
    }
    if (!talkSnapshot.exists || talkSnapshot.data()?.isHidden === true ||
      talkSnapshot.data()?.isDeleted === true) {
      throw new HttpsError("not-found", "コメントが見つかりません");
    }
    if (replySnapshot?.exists && (replySnapshot.data()?.isHidden === true ||
      replySnapshot.data()?.isDeleted === true)) {
      throw new HttpsError("not-found", "返信が見つかりません");
    }

    const previous = reactionSnapshot.data()?.reaction;
    const oldReaction = previous === "up" || previous === "down" ? previous : null;
    const base = replySnapshot?.exists ? replySnapshot.data() ?? {} : talkSnapshot.data() ?? {};
    const upvotes = Math.max(
      0,
      nonNegativeCounter(base.upvotes) + Number(desiredReaction === "up") - Number(oldReaction === "up"),
    );
    const downvotes = Math.max(
      0,
      nonNegativeCounter(base.downvotes) + Number(desiredReaction === "down") - Number(oldReaction === "down"),
    );

    if (oldReaction !== desiredReaction) {
      if (desiredReaction == null) {
        if (reactionSnapshot.exists) transaction.delete(reactionReference);
      } else {
        transaction.set(reactionReference, {
          uid,
          reaction: desiredReaction,
          targetReplyId: replyId,
          updatedAt: FieldValue.serverTimestamp(),
          createdAt: reactionSnapshot.exists ?
            reactionSnapshot.data()?.createdAt ?? FieldValue.serverTimestamp() :
            FieldValue.serverTimestamp(),
        });
      }

      if (replySnapshot?.exists && replyReference != null) {
        transaction.update(replyReference, {
          upvotes,
          downvotes,
          updatedAt: FieldValue.serverTimestamp(),
        });
      } else if (replyId == null) {
        transaction.update(talkReference, {
          upvotes,
          downvotes,
          updatedAt: FieldValue.serverTimestamp(),
        });
      } else {
        const legacy = setLegacyReplyReaction(
          talkSnapshot.data()?.replies,
          replyId,
          upvotes,
          downvotes,
        );
        if (!legacy.found) {
          throw new HttpsError("not-found", "返信が見つかりません");
        }
        transaction.update(talkReference, {
          replies: legacy.replies,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }
    result = {upvotes, downvotes, reaction: desiredReaction};
  });
  return result ?? {upvotes: 0, downvotes: 0, reaction: null};
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
  if (!["topic", "talk", "reply"].includes(targetType) || targetId.length > 300) {
    throw new HttpsError("invalid-argument", "通報対象が不正です");
  }

  const uid = request.auth.uid;
  const firestore = getFirestore();
  // One deterministic report document per reporter and topic.  A user may
  // report their most relevant target once, but cannot inflate a topic's
  // block threshold by varying report IDs.
  const topicReference = firestore.collection("topics").doc(topicId);
  const reference = topicReference.collection("reports").doc(uid);
  await firestore.runTransaction(async (transaction) => {
    const [topicSnapshot, existing] = await Promise.all([
      transaction.get(topicReference),
      transaction.get(reference),
    ]);
    if (!topicSnapshot.exists || !canUseTopicInteraction(topicSnapshot.data() ?? {}, uid)) {
      throw new HttpsError("permission-denied", "このTierは通報できません");
    }
    if (existing.exists) {
      throw new HttpsError("already-exists", "既に通報済みです");
    }
    transaction.create(reference, {
      topicId,
      targetType,
      targetId,
      reporterUserId: uid,
      reason: reason.slice(0, 200),
      createdAt: FieldValue.serverTimestamp(),
    });
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

// 登録済みアカウントの表示名を設定する。他ユーザーにも見える公開情報のため
// NGワード判定を通す(匿名ユーザーの名前は固定表記のまま変更不可)。
export const setDisplayName = onCall(callableOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  if (isAnonymousRequest(request.auth.token)) {
    throw new HttpsError(
      "permission-denied",
      "匿名アカウントでは表示名を設定できません",
    );
  }
  const displayName = typeof request.data?.displayName === "string" ?
    request.data.displayName.trim() : "";
  if (displayName.length === 0 || displayName.length > 24) {
    throw new HttpsError("invalid-argument", "表示名は1〜24文字で入力してください");
  }
  const firestore = getFirestore();
  const config = await loadNgWordConfig(firestore);
  const moderation = moderateText({displayName}, config);
  if (moderation.status !== "approved") {
    throw new HttpsError(
      "failed-precondition",
      "その表示名は使用できません",
    );
  }
  await firestore.collection("users").doc(request.auth.uid).set({
    uid: request.auth.uid,
    displayName,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {ok: true};
});

export const onReportWritten = onDocumentWritten(
  "topics/{topicId}/reports/{reportId}",
  async (event) => {
    const beforeExists = event.data?.before.exists === true;
    const afterExists = event.data?.after.exists === true;
    const delta = Number(afterExists) - Number(beforeExists);
    if (delta === 0) return;
    const topicId = event.params.topicId;
    const firestore = getFirestore();
    const topic = firestore.collection("topics").doc(topicId);
    const receipt = firestore.doc(`topicReportAggregationReceipts/${event.id}`);
    let shouldBlock = false;
    let becameBlocked = false;
    let blockedCreatorId: unknown;
    await firestore.runTransaction(async (transaction) => {
      const [topicSnapshot, receiptSnapshot] = await Promise.all([
        transaction.get(topic),
        transaction.get(receipt),
      ]);
      if (receiptSnapshot.exists || !topicSnapshot.exists ||
        topicSnapshot.data()?.deleting === true) return;
      const reportCount = Math.max(
        0,
        nonNegativeCounter(topicSnapshot.data()?.reportCount) + delta,
      );
      shouldBlock = reportCount >= REPORT_BLOCK_THRESHOLD;
      becameBlocked = shouldBlock &&
        topicSnapshot.data()?.moderationStatus !== "blocked";
      blockedCreatorId = topicSnapshot.data()?.creatorId;
      transaction.set(topic, {
        reportCount,
        ...(shouldBlock ? {moderationStatus: "blocked"} : {}),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(receipt, {
        eventId: event.id,
        topicId,
        expiresAt: new Date(Date.now() + 1000 * 60 * 60 * 24 * 30),
        createdAt: FieldValue.serverTimestamp(),
      });
    });
    if (becameBlocked) {
      await rotateTopicImageDownloadTokens(topicId, blockedCreatorId);
      await syncSharedImageVariantsForTopic(topicId, "blocked");
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

  const topicReference = firestore.collection("topics").doc(topicId);
  const topicSnapshot = await topicReference.get();
  if (!topicSnapshot.exists) {
    throw new HttpsError("not-found", "Tierが見つかりません");
  }
  if (status === "blocked" && topicSnapshot.data()?.moderationStatus !== "blocked") {
    await rotateTopicImageDownloadTokens(topicId, topicSnapshot.data()?.creatorId);
  }
  await topicReference.set({
    moderationStatus: status,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await syncSharedImageVariantsForTopic(topicId, status);

  return {ok: true};
});

// Visibility is server-mediated so changing a public Tier to private also
// revokes old Firebase Storage download-token URLs.  Client-side topic updates
// must not be able to bypass that privacy step.
export const setTopicVisibility = onCall(callableOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  const topicId = request.data?.topicId;
  const isPublic = request.data?.isPublic;
  if (typeof topicId !== "string" || topicId.length === 0 ||
      typeof isPublic !== "boolean") {
    throw new HttpsError("invalid-argument", "パラメータが不正です");
  }
  const topic = getFirestore().collection("topics").doc(topicId);
  const snapshot = await topic.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Tierが見つかりません");
  }
  const data = snapshot.data() ?? {};
  if (data.creatorId !== request.auth.uid) {
    throw new HttpsError("permission-denied", "このTierは変更できません");
  }
  const wasPublic = data.isPublic !== false;
  if (wasPublic && !isPublic) {
    await rotateTopicImageDownloadTokens(topicId, data.creatorId);
  }
  await topic.update({
    isPublic,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {isPublic};
});

// 管理者だけが、任意の「語る」コメントまたは返信を非公開・復元・削除できる。
// 非公開本文は一般クライアントから読めない管理専用コレクションへ退避する。
export const adminModerateTalk = onCall(callableOptions, async (request) => {
  const firestore = getFirestore();
  const adminUid = await assertAdmin(firestore, request);
  const topicId = request.data?.topicId;
  const postId = request.data?.postId;
  const replyId = request.data?.replyId;
  const action = request.data?.action;
  if (
    typeof topicId !== "string" || topicId.length === 0 ||
    typeof postId !== "string" || postId.length === 0 ||
    (replyId != null && (typeof replyId !== "string" || replyId.length === 0)) ||
    !["hide", "show", "delete"].includes(action)
  ) {
    throw new HttpsError("invalid-argument", "パラメータが不正です");
  }

  const talkReference = firestore.doc(`topics/${topicId}/talks/${postId}`);
  const backupReferenceFor = (targetReplyId: string | null) => {
    const key = createHash("sha256")
      .update(`${topicId}\u0000${postId}\u0000${targetReplyId ?? "root"}`)
      .digest("hex");
    return firestore.doc(`adminTalkModeration/${key}`);
  };
  const backupReference = backupReferenceFor(replyId ?? null);

  // 新形式の返信は replies サブコレクションにある。既存の配列形式に見つから
  // ない場合だけではなく、まずこちらを優先して1返信だけを更新する。
  if (replyId != null) {
    const replyReference = talkReference.collection("replies").doc(replyId);
    const existingReply = await replyReference.get();
    if (existingReply.exists) {
      await firestore.runTransaction(async (transaction) => {
        const [replySnapshot, backupSnapshot] = await Promise.all([
          transaction.get(replyReference),
          transaction.get(backupReference),
        ]);
        if (!replySnapshot.exists) {
          throw new HttpsError("not-found", "返信が見つかりません");
        }
        const reply = replySnapshot.data() ?? {};
        if (reply.isDeleted === true) return;
        if (action === "hide") {
          if (reply.isHidden === true) return;
          transaction.set(backupReference, {
            topicId,
            postId,
            replyId,
            body: typeof reply.body === "string" ? reply.body : "",
            hiddenBy: adminUid,
            hiddenAt: FieldValue.serverTimestamp(),
          });
          transaction.update(replyReference, {
            body: "",
            isHidden: true,
            moderatedAt: FieldValue.serverTimestamp(),
          });
        } else if (action === "show") {
          if (reply.isHidden !== true) return;
          const restoredBody = backupSnapshot.data()?.body;
          if (typeof restoredBody !== "string") {
            throw new HttpsError("failed-precondition", "復元する本文がありません");
          }
          transaction.update(replyReference, {
            body: restoredBody,
            isHidden: false,
            moderatedAt: FieldValue.serverTimestamp(),
          });
          if (backupSnapshot.exists) transaction.delete(backupReference);
        } else {
          transaction.update(replyReference, {
            body: "",
            isHidden: false,
            isDeleted: true,
            moderatedAt: FieldValue.serverTimestamp(),
            deletedBy: adminUid,
          });
          if (backupSnapshot.exists) transaction.delete(backupReference);
        }
      });
      return {ok: true};
    }
  }

  await firestore.runTransaction(async (transaction) => {
    const [talkSnapshot, backupSnapshot] = await Promise.all([
      transaction.get(talkReference),
      transaction.get(backupReference),
    ]);
    if (!talkSnapshot.exists) {
      throw new HttpsError("not-found", "コメントが見つかりません");
    }
    const talk = talkSnapshot.data() ?? {};
    if (talk.isDeleted === true) return;

    if (replyId == null) {
      if (action === "hide") {
        if (talk.isHidden === true) return;
        transaction.set(backupReference, {
          topicId,
          postId,
          replyId: null,
          body: typeof talk.body === "string" ? talk.body : "",
          hiddenBy: adminUid,
          hiddenAt: FieldValue.serverTimestamp(),
        });
        transaction.update(talkReference, {
          body: "",
          isHidden: true,
          moderatedAt: FieldValue.serverTimestamp(),
        });
      } else if (action === "show") {
        if (talk.isHidden !== true) return;
        const restoredBody = backupSnapshot.data()?.body;
        if (typeof restoredBody !== "string") {
          throw new HttpsError("failed-precondition", "復元する本文がありません");
        }
        transaction.update(talkReference, {
          body: restoredBody,
          isHidden: false,
          moderatedAt: FieldValue.serverTimestamp(),
        });
        if (backupSnapshot.exists) transaction.delete(backupReference);
      } else {
        const hiddenReplyIds = Array.isArray(talk.hiddenReplyIds) ?
          talk.hiddenReplyIds.filter((id): id is string => typeof id === "string") : [];
        transaction.update(talkReference, {
          body: "",
          replies: [],
          replyAuthorIds: [],
          isHidden: false,
          isDeleted: true,
          hiddenReplyIds: [],
          deletedReplyIds: [],
          moderatedAt: FieldValue.serverTimestamp(),
          deletedBy: adminUid,
        });
        if (backupSnapshot.exists) transaction.delete(backupReference);
        for (const hiddenReplyId of hiddenReplyIds) {
          transaction.delete(backupReferenceFor(hiddenReplyId));
        }
      }
      return;
    }

    const replies = talk.replies;
    const hiddenIds = new Set(Array.isArray(talk.hiddenReplyIds) ?
      talk.hiddenReplyIds.filter((id): id is string => typeof id === "string") : []);
    const deletedIds = new Set(Array.isArray(talk.deletedReplyIds) ?
      talk.deletedReplyIds.filter((id): id is string => typeof id === "string") : []);
    if (deletedIds.has(replyId)) return;

    if (action === "hide") {
      if (hiddenIds.has(replyId)) return;
      const body = findReplyBody(replies, replyId);
      if (body == null) throw new HttpsError("not-found", "返信が見つかりません");
      const updated = setReplyBody(replies, replyId, "");
      hiddenIds.add(replyId);
      transaction.set(backupReference, {
        topicId,
        postId,
        replyId,
        body,
        hiddenBy: adminUid,
        hiddenAt: FieldValue.serverTimestamp(),
      });
      transaction.update(talkReference, {
        replies: updated.replies,
        hiddenReplyIds: [...hiddenIds],
        moderatedAt: FieldValue.serverTimestamp(),
      });
    } else if (action === "show") {
      if (!hiddenIds.has(replyId)) return;
      const body = backupSnapshot.data()?.body;
      if (typeof body !== "string") {
        throw new HttpsError("failed-precondition", "復元する本文がありません");
      }
      const updated = setReplyBody(replies, replyId, body);
      if (!updated.found) throw new HttpsError("not-found", "返信が見つかりません");
      hiddenIds.delete(replyId);
      transaction.update(talkReference, {
        replies: updated.replies,
        hiddenReplyIds: [...hiddenIds],
        moderatedAt: FieldValue.serverTimestamp(),
      });
      transaction.delete(backupReference);
    } else {
      const updated = deleteReplyTree(replies, replyId);
      if (updated.deletedIds.length === 0) {
        throw new HttpsError("not-found", "返信が見つかりません");
      }
      for (const id of updated.deletedIds) {
        deletedIds.add(id);
        hiddenIds.delete(id);
        transaction.delete(backupReferenceFor(id));
      }
      transaction.update(talkReference, {
        replies: updated.replies,
        replyAuthorIds: collectReplyAuthorIds(updated.replies),
        hiddenReplyIds: [...hiddenIds],
        deletedReplyIds: [...deletedIds],
        moderatedAt: FieldValue.serverTimestamp(),
      });
    }
  });
  // 親コメントを削除したら新形式の返信本文も同時に不可視化する。親の
  // tombstone は残すため、古いタブが同じIDを再作成することも防げる。
  if (replyId == null && action === "delete") {
    const replies = await talkReference.collection("replies").get();
    await Promise.all(replies.docs.map((reply) => reply.ref.update({
      body: "",
      isHidden: false,
      isDeleted: true,
      moderatedAt: FieldValue.serverTimestamp(),
      deletedBy: adminUid,
    })));
  }
  return {ok: true};
});

// 匿名UIDが既存アカウントへのログインで切り替わる直前に、移行権限を
// サーバー側だけで発行する。クライアントは任意のUIDを指定して他人の
// データを移せず、移行元が匿名として認証されていた時の一回限りの秘密値を
// 持つ場合だけ、ログイン後の既存UIDへ引き継げる。
export const startAnonymousAccountTransfer = onCall(
  callableOptions,
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    return startAnonymousDataTransfer({
      firestore: getFirestore(),
      sourceUid: request.auth.uid,
      sourceIsAnonymous: isAnonymousRequest(request.auth.token),
    });
  },
);

// 1呼び出しにつき高々1ページだけを移す。途中失敗時はphaseを進めないため、
// 同じCallableを再実行しても作成済みの宛先documentを優先して安全に再開できる。
export const continueAnonymousAccountTransfer = onCall(
  callableOptions,
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const sourceUid = request.data?.sourceUid;
    const secret = request.data?.secret;
    if (typeof sourceUid !== "string" || typeof secret !== "string") {
      throw new HttpsError("invalid-argument", "引き継ぎ情報が不足しています");
    }
    return advanceAnonymousDataTransfer({
      firestore: getFirestore(),
      destinationUid: request.auth.uid,
      destinationIsAnonymous: isAnonymousRequest(request.auth.token),
      sourceUid,
      secret,
    });
  },
);

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
  const topicReference = firestore.collection("topics").doc(topicId);
  const topicSnapshot = await topicReference.get();
  if (!topicSnapshot.exists) {
    throw new HttpsError("not-found", "Tierが見つかりません");
  }
  if (topicSnapshot.data()?.isPublic !== false && !isPublic) {
    await rotateTopicImageDownloadTokens(topicId, topicSnapshot.data()?.creatorId);
  }
  await topicReference.set({
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
  await Promise.all([
    deleteSharedImagesForTopic(firestore, getStorage(), topicId),
    deleteTierAggregationStats(firestore, topicId),
  ]);
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

// 管理画面: 共有画像バリアントを名前の前方一致で検索する(collectionGroup、
// 全グループ横断)。クエリが空の場合は新着順で一覧表示する。
export const adminSearchSharedImages = onCall(callableOptions, async (request) => {
  const firestore = getFirestore();
  await assertAdmin(firestore, request);

  const rawQuery = typeof request.data?.query === "string" ?
    request.data.query.trim() : "";
  let query: FirebaseFirestore.Query = firestore.collectionGroup("variants");
  if (rawQuery.length > 0) {
    const normalized = normalizeImageName(rawQuery);
    query = query
      .orderBy("displayName")
      .startAt(normalized)
      .endAt(normalized + "");
  } else {
    query = query.orderBy("createdAt", "desc");
  }
  const snapshot = await query.limit(50).get();
  return {
    results: snapshot.docs.map((doc) => ({
      groupKey: doc.ref.parent.parent?.id,
      variantId: doc.id,
      ...doc.data(),
      createdAt: undefined,
      updatedAt: undefined,
    })),
  };
});

// 管理画面: 共有画像バリアントを検索対象から非表示/再表示する(物理削除しない)。
export const adminSetSharedImageHidden = onCall(callableOptions, async (request) => {
  const firestore = getFirestore();
  await assertAdmin(firestore, request);

  const groupKey = request.data?.groupKey;
  const variantId = request.data?.variantId;
  const hidden = request.data?.hidden;
  if (
    typeof groupKey !== "string" || groupKey.length === 0 ||
    typeof variantId !== "string" || variantId.length === 0 ||
    typeof hidden !== "boolean"
  ) {
    throw new HttpsError("invalid-argument", "パラメータが不正です");
  }
  await firestore
    .collection(SHARED_IMAGE_COLLECTION).doc(groupKey)
    .collection("variants").doc(variantId)
    .set({
      hidden,
      hiddenReason: hidden ? "adminHidden" : FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  return {ok: true};
});

// 管理画面: 共有画像バリアントをStorage/Firestoreから完全に削除する。
export const adminDeleteSharedImage = onCall(callableOptions, async (request) => {
  const firestore = getFirestore();
  await assertAdmin(firestore, request);

  const groupKey = request.data?.groupKey;
  const variantId = request.data?.variantId;
  if (
    typeof groupKey !== "string" || groupKey.length === 0 ||
    typeof variantId !== "string" || variantId.length === 0
  ) {
    throw new HttpsError("invalid-argument", "groupKey/variantIdが必要です");
  }
  const reference = firestore
    .collection(SHARED_IMAGE_COLLECTION).doc(groupKey)
    .collection("variants").doc(variantId);
  const snapshot = await reference.get();
  const storagePath = snapshot.data()?.storagePath;
  if (typeof storagePath === "string" && storagePath.length > 0) {
    await getStorage().bucket().file(storagePath).delete({ignoreNotFound: true});
  }
  await reference.delete();
  await firestore.collection(SHARED_IMAGE_COLLECTION).doc(groupKey).set({
    variantCount: FieldValue.increment(-1),
  }, {merge: true});
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
