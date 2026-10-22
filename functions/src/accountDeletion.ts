import {FieldValue, Firestore, Query} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";

type RawReply = Record<string, unknown>;

export function collectReplyAuthorIds(replies: RawReply[]): string[] {
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

export function removeRepliesByAuthor(
  replies: RawReply[],
  uid: string,
): RawReply[] {
  return replies.flatMap((reply) => {
    if (reply.authorUserId === uid) return [];
    const children = Array.isArray(reply.replies) ?
      removeRepliesByAuthor(reply.replies as RawReply[], uid) : [];
    return [{...reply, replies: children}];
  });
}

async function deleteQueryDocuments(query: Query): Promise<void> {
  while (true) {
    const snapshot = await query.limit(400).get();
    if (snapshot.empty) return;
    const batch = snapshot.docs[0].ref.firestore.batch();
    for (const document of snapshot.docs) batch.delete(document.ref);
    await batch.commit();
    if (snapshot.size < 400) return;
  }
}

export async function deleteSharedImagesForTopic(
  firestore: Firestore,
  storage: ReturnType<typeof getStorage>,
  topicId: string,
): Promise<void> {
  const snapshot = await firestore.collection("sharedItemImages")
    .where("sourceTopicId", "==", topicId)
    .get();
  await Promise.all(snapshot.docs.map(async (document) => {
    const storagePath = document.data().storagePath;
    if (typeof storagePath === "string" && storagePath.length > 0) {
      await storage.bucket().file(storagePath).delete({ignoreNotFound: true});
    }
    await document.ref.delete();
  }));
}

async function deleteOwnedTopics(
  firestore: Firestore,
  storage: ReturnType<typeof getStorage>,
  uid: string,
): Promise<void> {
  const snapshot = await firestore.collection("topics")
    .where("creatorId", "==", uid)
    .get();
  for (const topic of snapshot.docs) {
    if (topic.id.startsWith("starter-")) {
      // Legacy starter documents may have inherited the UID of the first
      // participant. Preserve them and repair their official ownership.
      await topic.ref.set({
        creatorName: "tier_online",
        creatorId: "tier_online",
        createdByAnonymous: false,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      continue;
    }
    // Aggregation triggers ignore topics marked as deleting, preventing child
    // deletions from recreating a partially deleted parent document.
    await topic.ref.set({deleting: true, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    await Promise.all([
      deleteSharedImagesForTopic(firestore, storage, topic.id),
      deleteQueryDocuments(
        firestore.collection("tierRegionStats").where("tierId", "==", topic.id),
      ),
    ]);
    await firestore.recursiveDelete(topic.ref);
  }
}

async function deleteTalkData(firestore: Firestore, uid: string): Promise<void> {
  const [authored, containingReplies] = await Promise.all([
    firestore.collectionGroup("talks").where("authorUserId", "==", uid).get(),
    firestore.collectionGroup("talks")
      .where("replyAuthorIds", "array-contains", uid)
      .get(),
  ]);
  const authoredPaths = new Set(authored.docs.map((document) => document.ref.path));
  // A talk now owns reply/reaction subcollections as well as legacy arrays.
  // Ordinary delete would leave those children behind and expose them if an
  // old talk ID was ever reused. Await cleanup before deleting Authentication.
  await Promise.all(authored.docs.map((document) => firestore.recursiveDelete(document.ref)));
  await Promise.all(containingReplies.docs.map(async (document) => {
    if (authoredPaths.has(document.ref.path)) return;
    const replies = Array.isArray(document.data().replies) ?
      document.data().replies as RawReply[] : [];
    const filtered = removeRepliesByAuthor(replies, uid);
    await document.ref.update({
      replies: filtered,
      replyAuthorIds: collectReplyAuthorIds(filtered),
    });
  }));
  await Promise.all([
    deleteTalkActivityDocuments(firestore, "replies", "authorUserId", uid),
    deleteTalkActivityDocuments(firestore, "reactions", "userId", uid),
  ]);
}

async function deleteTalkActivityDocuments(
  firestore: Firestore,
  collection: "replies" | "reactions",
  ownerField: "authorUserId" | "userId",
  uid: string,
): Promise<void> {
  // Page through even unrelated same-named collections without deleting them
  // or looping forever on a skipped document. Retry remains idempotent.
  const query = firestore.collectionGroup(collection).where(ownerField, "==", uid)
    .orderBy("__name__").limit(400);
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  while (true) {
    const snapshot = await (cursor ? query.startAfter(cursor) : query).get();
    if (snapshot.empty) return;
    const batch = firestore.batch();
    for (const document of snapshot.docs) {
      const parts = document.ref.path.split("/");
      if (parts.length === 6 && parts[0] === "topics" &&
          parts[2] === "talks" && parts[4] === collection) {
        batch.delete(document.ref);
      }
    }
    await batch.commit();
    if (snapshot.size < 400) return;
    cursor = snapshot.docs[snapshot.docs.length - 1];
  }
}

export async function deleteAccountData(
  firestore: Firestore,
  storage: ReturnType<typeof getStorage>,
  uid: string,
): Promise<void> {
  await deleteOwnedTopics(firestore, storage, uid);
  await Promise.all([
    deleteQueryDocuments(
      firestore.collectionGroup("submissions").where("userId", "==", uid),
    ),
    deleteQueryDocuments(
      firestore.collectionGroup("likes").where("userId", "==", uid),
    ),
    deleteQueryDocuments(
      firestore.collectionGroup("reports").where("reporterUserId", "==", uid),
    ),
    deleteQueryDocuments(
      firestore.collection("contactRequests").where("uid", "==", uid),
    ),
    deleteQueryDocuments(
      firestore.collection("adBonusTokens").where("uid", "==", uid),
    ),
    deleteTalkData(firestore, uid),
    // Storageの残存ファイル掃除の失敗でアカウント削除全体を止めない。
    storage.bucket().deleteFiles({prefix: `users/${uid}/`}).catch((error) => {
      console.error("deleteAccountData: failed to clean up storage files", error);
    }),
  ]);
  await Promise.all([
    firestore.doc(`users/${uid}`).delete(),
    firestore.doc(`dailyTierCounters/${uid}`).delete(),
    firestore.doc(`rateLimits/${uid}`).delete(),
    firestore.doc(`admins/${uid}`).delete(),
  ]);
}
