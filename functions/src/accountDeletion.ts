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
  const query = firestore.collectionGroup("variants")
    .where("sourceTopicId", "==", topicId);
  while (true) {
    const snapshot = await query.limit(100).get();
    if (snapshot.empty) return;
    await Promise.all(snapshot.docs.map(async (document) => {
      const storagePath = document.data().storagePath;
      if (typeof storagePath === "string" && storagePath.length > 0) {
        await storage.bucket().file(storagePath).delete({ignoreNotFound: true});
      }
      await document.ref.delete();
    }));
    if (snapshot.size < 100) return;
  }
}

async function deleteOwnedTopics(
  firestore: Firestore,
  storage: ReturnType<typeof getStorage>,
  uid: string,
): Promise<void> {
  const query = firestore.collection("topics").where("creatorId", "==", uid);
  // Each recursive delete may itself fan out.  Work through a small page so a
  // prolific account never requires every owned topic in Function memory.
  while (true) {
    const snapshot = await query.limit(20).get();
    if (snapshot.empty) return;
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
    if (snapshot.size < 20) return;
  }
}

async function deleteTalkData(firestore: Firestore, uid: string): Promise<void> {
  const containingReplies = firestore.collectionGroup("talks")
    .where("replyAuthorIds", "array-contains", uid);
  while (true) {
    const snapshot = await containingReplies.limit(100).get();
    if (snapshot.empty) break;
    for (const document of snapshot.docs) {
      // Do not rewrite a large legacy array when the complete authored parent
      // is being removed. Recursively remove its new-format reply subtree as
      // well; deleting only the parent document would leave orphan replies.
      if (document.data().authorUserId === uid) {
        await firestore.recursiveDelete(document.ref);
        continue;
      }
      const replies = Array.isArray(document.data().replies) ?
        document.data().replies as RawReply[] : [];
      const filtered = removeRepliesByAuthor(replies, uid);
      await document.ref.update({
        replies: filtered,
        replyAuthorIds: collectReplyAuthorIds(filtered),
      });
    }
    if (snapshot.size < 100) break;
  }

  // Authored parent comments without legacy replies are not returned by the
  // `replyAuthorIds` query above. Use recursive deletion so their replies are
  // never orphaned in Firestore.
  const authoredTalks = firestore.collectionGroup("talks")
    .where("authorUserId", "==", uid);
  while (true) {
    const snapshot = await authoredTalks.limit(20).get();
    if (snapshot.empty) break;
    for (const document of snapshot.docs) {
      await firestore.recursiveDelete(document.ref);
    }
    if (snapshot.size < 20) break;
  }

  await Promise.all([
    // New replies do not live inside a growing parent array and can be removed
    // in fixed-size batches.
    deleteQueryDocuments(
      firestore.collectionGroup("replies").where("authorUserId", "==", uid),
    ),
  ]);
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
    deleteQueryDocuments(
      firestore.collection("users").doc(uid).collection("participations"),
    ),
    deleteQueryDocuments(
      firestore.collection("users").doc(uid).collection("likeRefs"),
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

/// Firebase Auth's automatic anonymous-account cleanup removes only the Auth
/// record.  Keep the actual submission documents (they contribute to the
/// public Tier aggregate), but remove every other user-owned artifact once the
/// Auth record is confirmed gone.
export async function deleteExpiredAnonymousData(
  firestore: Firestore,
  storage: ReturnType<typeof getStorage>,
  uid: string,
): Promise<void> {
  await deleteOwnedTopics(firestore, storage, uid);
  await Promise.all([
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
    deleteQueryDocuments(
      firestore.collection("users").doc(uid).collection("participations"),
    ),
    deleteQueryDocuments(
      firestore.collection("users").doc(uid).collection("likeRefs"),
    ),
    deleteTalkData(firestore, uid),
    storage.bucket().deleteFiles({prefix: `users/${uid}/`}).catch((error) => {
      console.error("deleteExpiredAnonymousData: failed to clean storage", error);
    }),
  ]);
  await Promise.all([
    firestore.doc(`users/${uid}`).delete(),
    firestore.doc(`dailyTierCounters/${uid}`).delete(),
    firestore.doc(`rateLimits/${uid}`).delete(),
    firestore.doc(`anonymousUserLifecycle/${uid}`).delete(),
  ]);
}
