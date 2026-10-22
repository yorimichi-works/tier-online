import {createHash, randomUUID} from "node:crypto";

import {getAuth} from "firebase-admin/auth";
import {
  FieldValue,
  Firestore,
  QueryDocumentSnapshot,
  Timestamp,
} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {HttpsError} from "firebase-functions/https";

import {deleteAccountData} from "./accountDeletion";

const TRANSFER_COLLECTION = "anonymousDataTransfers";
const PAGE_SIZE = 25;
// Topic ownership transfer can include Storage image copies. Keep this smaller
// than document-only pages so one callable stays well below its deadline.
const TOPIC_PAGE_SIZE = 2;
const LEASE_MS = 1000 * 60 * 5;
const TRANSFER_TTL_MS = 1000 * 60 * 60 * 24 * 30;

type TransferPhase =
  | "profile"
  | "topics"
  | "submissions"
  | "likes"
  | "talks"
  | "replies"
  | "reports"
  | "contactRequests"
  | "cleanup";

const phases: TransferPhase[] = [
  "profile",
  "topics",
  "submissions",
  "likes",
  "talks",
  "replies",
  "reports",
  "contactRequests",
  "cleanup",
];

type RawReply = Record<string, unknown>;

interface TransferContext {
  sourceUid: string;
  destinationUid: string;
  transferId: string;
  phase: TransferPhase;
  leaseId: string;
}

function secretHash(secret: string): string {
  return createHash("sha256").update(secret).digest("hex");
}

function requireNonAnonymous(uid: string, anonymous: boolean): void {
  if (!uid || anonymous) {
    throw new HttpsError(
      "failed-precondition",
      "登録済みアカウントで引き継ぎを完了してください",
    );
  }
}

function isAnonymousUserRecord(user: {providerData: unknown[]}): boolean {
  return user.providerData.length === 0;
}

function nextPhase(phase: TransferPhase): TransferPhase | undefined {
  const index = phases.indexOf(phase);
  return index < 0 ? undefined : phases[index + 1];
}

function replyAuthorIds(replies: RawReply[]): string[] {
  const ids = new Set<string>();
  const visit = (items: RawReply[]) => {
    for (const reply of items) {
      if (typeof reply.authorUserId === "string") ids.add(reply.authorUserId);
      if (Array.isArray(reply.replies)) visit(reply.replies as RawReply[]);
    }
  };
  visit(replies);
  return [...ids];
}

export function replaceReplyAuthorUid(
  replies: RawReply[],
  sourceUid: string,
  destinationUid: string,
): RawReply[] {
  return replies.map((reply) => ({
    ...reply,
    ...(reply.authorUserId === sourceUid ? {authorUserId: destinationUid} : {}),
    ...(Array.isArray(reply.replies) ? {
      replies: replaceReplyAuthorUid(
        reply.replies as RawReply[],
        sourceUid,
        destinationUid,
      ),
    } : {}),
  }));
}

function firebaseDownloadUrl(bucketName: string, storagePath: string, token: string): string {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/` +
    `${encodeURIComponent(storagePath)}?alt=media&token=${token}`;
}

async function copyTopicImages(
  firestore: Firestore,
  sourceUid: string,
  destinationUid: string,
  topicId: string,
): Promise<void> {
  const bucket = getStorage().bucket();
  const topicReference = firestore.collection("topics").doc(topicId);
  const [topicSnapshot, items] = await Promise.all([
    topicReference.get(),
    topicReference.collection("items").get(),
  ]);
  const thumbnailItemId = topicSnapshot.data()?.thumbnailItemId;
  let copiedThumbnailUrl: string | undefined;

  const copyImageAtPath = async (suffix: string): Promise<string | undefined> => {
    const sourcePath = `users/${sourceUid}/topics/${topicId}/items/${suffix}`;
    const source = bucket.file(sourcePath);
    const [exists] = await source.exists();
    if (!exists) return undefined;

    const destinationPath = `users/${destinationUid}/topics/${topicId}/items/${suffix}`;
    const destination = bucket.file(destinationPath);
    await source.copy(destination);
    const [metadata] = await destination.getMetadata();
    const existingTokens = metadata.metadata?.firebaseStorageDownloadTokens;
    const token = typeof existingTokens === "string" && existingTokens.length > 0 ?
      existingTokens.split(",")[0] : randomUUID();
    if (!existingTokens) {
      await destination.setMetadata({
        metadata: {
          ...(metadata.metadata ?? {}),
          firebaseStorageDownloadTokens: token,
        },
      });
    }
    return firebaseDownloadUrl(bucket.name, destinationPath, token);
  };

  for (const item of items.docs) {
    const imageUrl = await copyImageAtPath(`${item.id}.jpg`);
    // サムネイルは新形式だけに存在する。古いTierでは元画像URLを親へ
    // 引き継ぎ、一覧表示が壊れないようにする。
    const thumbnailUrl = await copyImageAtPath(`${item.id}.thumb.jpg`);
    if (imageUrl) {
      await item.ref.set({
        imageUrl,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    if (item.id === thumbnailItemId) {
      copiedThumbnailUrl = thumbnailUrl ?? imageUrl;
    }
  }
  if (copiedThumbnailUrl) {
    await topicReference.set({
      thumbnailUrl: copiedThumbnailUrl,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
}

async function moveSubmissionsOrLikes(
  firestore: Firestore,
  collection: "submissions" | "likes",
  sourceUid: string,
  destinationUid: string,
): Promise<boolean> {
  const sourceDocuments = await firestore.collectionGroup(collection)
    .where("userId", "==", sourceUid)
    .limit(PAGE_SIZE)
    .get();
  if (sourceDocuments.empty) return true;

  await Promise.all(sourceDocuments.docs.map((source) => firestore.runTransaction(async (transaction) => {
    const freshSource = await transaction.get(source.ref);
    if (!freshSource.exists || freshSource.data()?.userId !== sourceUid) return;
    const destination = source.ref.parent.doc(destinationUid);
    const existingDestination = await transaction.get(destination);
    // 同一Tierで両方のUIDが既に操作していた場合は、既存アカウント側を
    // 優先する。匿名側を消すことでlikeは1件、submissionは1参加者に保つ。
    if (!existingDestination.exists) {
      transaction.set(destination, {
        ...freshSource.data(),
        userId: destinationUid,
        migratedFromAnonymousUid: sourceUid,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.delete(source.ref);
  })));
  return false;
}

async function moveReports(
  firestore: Firestore,
  sourceUid: string,
  destinationUid: string,
): Promise<boolean> {
  const sourceDocuments = await firestore.collectionGroup("reports")
    .where("reporterUserId", "==", sourceUid)
    .limit(PAGE_SIZE)
    .get();
  if (sourceDocuments.empty) return true;
  await Promise.all(sourceDocuments.docs.map((source) => firestore.runTransaction(async (transaction) => {
    const freshSource = await transaction.get(source.ref);
    const data = freshSource.data();
    if (!freshSource.exists || data?.reporterUserId !== sourceUid) return;
    const postId = typeof data.postId === "string" ? data.postId : "topic";
    const replyId = typeof data.replyId === "string" ? data.replyId : "root";
    const targetId = `${postId}_${replyId}_${destinationUid}`.replaceAll("/", "_");
    const destination = source.ref.parent.doc(targetId);
    const existingDestination = await transaction.get(destination);
    if (!existingDestination.exists) {
      transaction.set(destination, {
        ...data,
        reporterUserId: destinationUid,
        migratedFromAnonymousUid: sourceUid,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.delete(source.ref);
  })));
  return false;
}

async function updateTopics(
  firestore: Firestore,
  sourceUid: string,
  destinationUid: string,
  destinationName: string | undefined,
): Promise<boolean> {
  const topics = await firestore.collection("topics")
    .where("creatorId", "==", sourceUid)
    .limit(TOPIC_PAGE_SIZE)
    .get();
  if (topics.empty) return true;
  for (const topic of topics.docs) {
    // 画像のコピーが先。失敗した場合は所有UIDを書き換えないので安全に再試行できる。
    await copyTopicImages(firestore, sourceUid, destinationUid, topic.id);
    await topic.ref.update({
      creatorId: destinationUid,
      createdByAnonymous: false,
      ...(destinationName ? {creatorName: destinationName} : {}),
      migratedFromAnonymousUid: sourceUid,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  return false;
}

async function updateTalks(
  firestore: Firestore,
  sourceUid: string,
  destinationUid: string,
): Promise<boolean> {
  // 新形式では親コメントの authorUserId、旧形式では replies 配列を持つ親の
  // replyAuthorIds のどちらに匿名UIDが現れる。両方を対象にしないと、他人の
  // 親コメントに付けた匿名返信だけが取り残される。
  const [authored, containingReplies] = await Promise.all([
    firestore.collectionGroup("talks")
      .where("authorUserId", "==", sourceUid)
      .limit(PAGE_SIZE)
      .get(),
    firestore.collectionGroup("talks")
      .where("replyAuthorIds", "array-contains", sourceUid)
      .limit(PAGE_SIZE)
      .get(),
  ]);
  const talks = new Map<string, QueryDocumentSnapshot>();
  for (const talk of [...authored.docs, ...containingReplies.docs]) {
    talks.set(talk.ref.path, talk);
  }
  if (talks.size === 0) return true;
  await Promise.all([...talks.values()].map(async (talk) => {
    const data = talk.data();
    const legacyReplies = Array.isArray(data.replies) ? data.replies as RawReply[] : [];
    const replies = replaceReplyAuthorUid(legacyReplies, sourceUid, destinationUid);
    await talk.ref.update({
      ...(data.authorUserId === sourceUid ? {authorUserId: destinationUid} : {}),
      replies,
      replyAuthorIds: replyAuthorIds(replies),
      migratedFromAnonymousUid: sourceUid,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }));
  return false;
}

async function updateReplies(
  firestore: Firestore,
  sourceUid: string,
  destinationUid: string,
): Promise<boolean> {
  const replies = await firestore.collectionGroup("replies")
    .where("authorUserId", "==", sourceUid)
    .limit(PAGE_SIZE)
    .get();
  if (replies.empty) return true;
  await Promise.all(replies.docs.map((reply) => reply.ref.update({
    authorUserId: destinationUid,
    migratedFromAnonymousUid: sourceUid,
    updatedAt: FieldValue.serverTimestamp(),
  })));
  return false;
}

async function updateContactRequests(
  firestore: Firestore,
  sourceUid: string,
  destinationUid: string,
): Promise<boolean> {
  const contacts = await firestore.collection("contactRequests")
    .where("uid", "==", sourceUid)
    .limit(PAGE_SIZE)
    .get();
  if (contacts.empty) return true;
  await Promise.all(contacts.docs.map((contact) => contact.ref.update({
    uid: destinationUid,
    anonymous: false,
    migratedFromAnonymousUid: sourceUid,
    updatedAt: FieldValue.serverTimestamp(),
  })));
  return false;
}

async function mergeProfile(
  firestore: Firestore,
  sourceUid: string,
  destinationUid: string,
): Promise<string | undefined> {
  const [source, destination] = await Promise.all([
    firestore.collection("users").doc(sourceUid).get(),
    firestore.collection("users").doc(destinationUid).get(),
  ]);
  const sourceData = source.data() ?? {};
  const destinationData = destination.data() ?? {};
  const destinationName = typeof destinationData.displayName === "string" &&
      destinationData.displayName.trim().length > 0 ?
    destinationData.displayName.trim() : undefined;
  // 既存アカウントの表示名・言語・地域を優先し、未設定の項目だけ匿名側から補う。
  await destination.ref.set({
    ...sourceData,
    ...destinationData,
    uid: destinationUid,
    migratedAnonymousUid: sourceUid,
    updatedAt: FieldValue.serverTimestamp(),
    ...(!destination.exists ? {createdAt: sourceData.createdAt ?? FieldValue.serverTimestamp()} : {}),
  }, {merge: true});
  return destinationName;
}

async function assertSourceDataRemoved(
  firestore: Firestore,
  sourceUid: string,
): Promise<void> {
  // 移行対象として監査した UID 紐付けを、Auth の匿名UIDを消す前に再確認する。
  // 新しい UID を作り直せない状態でデータだけ残すことを防ぎ、失敗時には
  // transfer ticket を残して安全に再実行できるようにする。
  const [
    profile,
    counter,
    rateLimit,
    admin,
    topics,
    submissions,
    likes,
    talks,
    talksContainingReplies,
    replies,
    reports,
    contacts,
    tokens,
  ] = await Promise.all([
    firestore.doc(`users/${sourceUid}`).get(),
    firestore.doc(`dailyTierCounters/${sourceUid}`).get(),
    firestore.doc(`rateLimits/${sourceUid}`).get(),
    firestore.doc(`admins/${sourceUid}`).get(),
    firestore.collection("topics").where("creatorId", "==", sourceUid).limit(1).get(),
    firestore.collectionGroup("submissions").where("userId", "==", sourceUid).limit(1).get(),
    firestore.collectionGroup("likes").where("userId", "==", sourceUid).limit(1).get(),
    firestore.collectionGroup("talks").where("authorUserId", "==", sourceUid).limit(1).get(),
    firestore.collectionGroup("talks")
      .where("replyAuthorIds", "array-contains", sourceUid)
      .limit(1)
      .get(),
    firestore.collectionGroup("replies").where("authorUserId", "==", sourceUid).limit(1).get(),
    firestore.collectionGroup("reports").where("reporterUserId", "==", sourceUid).limit(1).get(),
    firestore.collection("contactRequests").where("uid", "==", sourceUid).limit(1).get(),
    firestore.collection("adBonusTokens").where("uid", "==", sourceUid).limit(1).get(),
  ]);
  const hasResidualData = [
    profile.exists,
    counter.exists,
    rateLimit.exists,
    admin.exists,
    !topics.empty,
    !submissions.empty,
    !likes.empty,
    !talks.empty,
    !talksContainingReplies.empty,
    !replies.empty,
    !reports.empty,
    !contacts.empty,
    !tokens.empty,
  ].some(Boolean);
  if (hasResidualData) {
    throw new HttpsError(
      "aborted",
      "匿名データの削除確認に失敗しました。もう一度お試しください",
    );
  }
}

async function destinationDisplayName(
  firestore: Firestore,
  destinationUid: string,
): Promise<string | undefined> {
  const data = (await firestore.collection("users").doc(destinationUid).get()).data();
  const value = data?.displayName;
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

async function claimTransfer(
  firestore: Firestore,
  destinationUid: string,
  sourceUid: string,
  secret: string,
): Promise<TransferContext | {completed: true}> {
  const transfer = firestore.collection(TRANSFER_COLLECTION).doc(sourceUid);
  const leaseId = randomUUID();
  return firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(transfer);
    const data = snapshot.data();
    if (!snapshot.exists || data?.secretHash !== secretHash(secret)) {
      throw new HttpsError("permission-denied", "引き継ぎの確認情報が無効です");
    }
    if (data.destinationUid != null && data.destinationUid !== destinationUid) {
      throw new HttpsError("permission-denied", "この引き継ぎは別アカウントへ紐付いています");
    }
    const expiresAt = data.expiresAt as Timestamp | undefined;
    if (expiresAt != null && expiresAt.toMillis() <= Date.now()) {
      throw new HttpsError("failed-precondition", "引き継ぎの有効期限が切れました");
    }
    if (data.status === "completed") return {completed: true} as const;
    const leaseUntil = data.leaseExpiresAt as Timestamp | undefined;
    if (leaseUntil != null && leaseUntil.toMillis() > Date.now()) {
      throw new HttpsError("aborted", "別の引き継ぎ処理が進行中です。少し待って再試行してください");
    }
    const phase = phases.includes(data.phase as TransferPhase) ?
      data.phase as TransferPhase : "profile";
    transaction.set(transfer, {
      destinationUid,
      status: "processing",
      phase,
      leaseId,
      leaseExpiresAt: new Date(Date.now() + LEASE_MS),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {sourceUid, destinationUid, transferId: sourceUid, phase, leaseId};
  });
}

async function finishStep(
  firestore: Firestore,
  context: TransferContext,
  next: TransferPhase,
): Promise<void> {
  const transfer = firestore.collection(TRANSFER_COLLECTION).doc(context.transferId);
  await firestore.runTransaction(async (transaction) => {
    const current = await transaction.get(transfer);
    // Lease を失った古い実行が、後から進んだphaseや新しいleaseを巻き戻さない。
    if (current.data()?.leaseId !== context.leaseId) return;
    transaction.set(transfer, {
      phase: next,
      status: "prepared",
      leaseId: FieldValue.delete(),
      leaseExpiresAt: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

async function releaseFailedLease(
  firestore: Firestore,
  context: TransferContext,
  error: unknown,
): Promise<void> {
  const transfer = firestore.collection(TRANSFER_COLLECTION).doc(context.transferId);
  await firestore.runTransaction(async (transaction) => {
    const current = await transaction.get(transfer);
    if (current.data()?.leaseId !== context.leaseId) return;
    transaction.set(transfer, {
      status: "prepared",
      leaseId: FieldValue.delete(),
      leaseExpiresAt: FieldValue.delete(),
      lastError: error instanceof Error ? error.message : String(error),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

export async function startAnonymousDataTransfer(params: {
  firestore: Firestore;
  sourceUid: string;
  sourceIsAnonymous: boolean;
}): Promise<{sourceUid: string; secret: string}> {
  if (!params.sourceIsAnonymous) {
    throw new HttpsError("failed-precondition", "匿名アカウントからのみ引き継げます");
  }
  const source = await getAuth().getUser(params.sourceUid);
  if (!isAnonymousUserRecord(source)) {
    throw new HttpsError("failed-precondition", "匿名アカウントではありません");
  }
  const secret = randomUUID();
  await params.firestore.collection(TRANSFER_COLLECTION).doc(params.sourceUid).set({
    sourceUid: params.sourceUid,
    secretHash: secretHash(secret),
    status: "prepared",
    phase: "profile",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    expiresAt: new Date(Date.now() + TRANSFER_TTL_MS),
  }, {merge: true});
  return {sourceUid: params.sourceUid, secret};
}

export async function advanceAnonymousDataTransfer(params: {
  firestore: Firestore;
  destinationUid: string;
  destinationIsAnonymous: boolean;
  sourceUid: string;
  secret: string;
}): Promise<{completed: boolean; phase?: string}> {
  requireNonAnonymous(params.destinationUid, params.destinationIsAnonymous);
  if (!params.sourceUid || !params.secret) {
    throw new HttpsError("invalid-argument", "引き継ぎ情報が不足しています");
  }
  const context = await claimTransfer(
    params.firestore,
    params.destinationUid,
    params.sourceUid,
    params.secret,
  );
  if ("completed" in context) return {completed: true};

  try {
    const source = await getAuth().getUser(context.sourceUid);
    if (!isAnonymousUserRecord(source)) {
      throw new HttpsError("failed-precondition", "移行元の匿名アカウントが無効です");
    }
    let batchComplete = false;
    switch (context.phase) {
      case "profile":
        await mergeProfile(params.firestore, context.sourceUid, context.destinationUid);
        batchComplete = true;
        break;
      case "topics":
        batchComplete = await updateTopics(
          params.firestore,
          context.sourceUid,
          context.destinationUid,
          await destinationDisplayName(params.firestore, context.destinationUid),
        );
        break;
      case "submissions":
        batchComplete = await moveSubmissionsOrLikes(
          params.firestore,
          "submissions",
          context.sourceUid,
          context.destinationUid,
        );
        break;
      case "likes":
        batchComplete = await moveSubmissionsOrLikes(
          params.firestore,
          "likes",
          context.sourceUid,
          context.destinationUid,
        );
        break;
      case "talks":
        batchComplete = await updateTalks(
          params.firestore,
          context.sourceUid,
          context.destinationUid,
        );
        break;
      case "replies":
        batchComplete = await updateReplies(
          params.firestore,
          context.sourceUid,
          context.destinationUid,
        );
        break;
      case "reports":
        batchComplete = await moveReports(
          params.firestore,
          context.sourceUid,
          context.destinationUid,
        );
        break;
      case "contactRequests":
        batchComplete = await updateContactRequests(
          params.firestore,
          context.sourceUid,
          context.destinationUid,
        );
        break;
      case "cleanup":
        await deleteAccountData(params.firestore, getStorage(), context.sourceUid);
        // deleteAccountData は通常のアカウント削除では Storage 障害をログだけに
        // 留める。引き継ぎでは所有権のない匿名ファイルを残さないことを優先し、
        // ここでは成功を必須にしてから Auth UID を削除する。
        await getStorage().bucket().deleteFiles({
          prefix: `users/${context.sourceUid}/`,
        });
        await assertSourceDataRemoved(params.firestore, context.sourceUid);
        await getAuth().deleteUser(context.sourceUid);
        await params.firestore.collection(TRANSFER_COLLECTION).doc(context.transferId).set({
          status: "completed",
          completedAt: FieldValue.serverTimestamp(),
          leaseId: FieldValue.delete(),
          leaseExpiresAt: FieldValue.delete(),
          expiresAt: new Date(Date.now() + TRANSFER_TTL_MS),
        }, {merge: true});
        return {completed: true};
    }
    if (batchComplete) {
      const next = nextPhase(context.phase);
      if (next == null) throw new HttpsError("internal", "移行段階が不正です");
      await finishStep(params.firestore, context, next);
      return {completed: false, phase: next};
    }
    await finishStep(params.firestore, context, context.phase);
    return {completed: false, phase: context.phase};
  } catch (error) {
    await releaseFailedLease(params.firestore, context, error);
    throw error;
  }
}
