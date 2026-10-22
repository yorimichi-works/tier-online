import assert from "node:assert/strict";
import test, {after} from "node:test";
import {initializeApp, deleteApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {deleteAccountData} from "./accountDeletion";

// Never create an Admin client without this local-only guard.
assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? "", /^127\.0\.0\.1:\d+$/);
// Disable cloud metadata probing in this local test process. No credential
// file or production authentication is created for the emulator.
process.env.METADATA_SERVER_DETECTION = "none";
const app = initializeApp({projectId: "demo-tier-authorization"}, "account-deletion-tests");
const db = getFirestore(app);
after(async () => { await db.terminate(); await deleteApp(app); });
const storageCalls: string[] = [];
// No Storage SDK client, bucket, credentials, or real image is used.
const storage = {bucket: () => ({deleteFiles: async ({prefix}: {prefix: string}) => {
  storageCalls.push(prefix);
}})} as unknown as ReturnType<typeof getStorage>;

async function put(path: string, data: Record<string, unknown>) { await db.doc(path).set(data); }
async function exists(path: string) { return (await db.doc(path).get()).exists; }
const root = "topics/deletion-fixture/talks";

test("account deletion removes only its new activity, retains unrelated and ownerless legacy content, and is repeatable", async () => {
  const uid = "deletion-target";
  await put("topics/deletion-fixture", {creatorId: "other", isPublic: true});
  await put(`${root}/keep`, {authorUserId: "other", body: "keep", upvotes: 7,
    replies: [{id: "legacy-unknown", body: "owner unknown"}], replyAuthorIds: []});
  await put(`${root}/keep/replies/remove`, {authorUserId: uid, body: "delete mine"});
  await put(`${root}/keep/replies/keep`, {authorUserId: "other", body: "keep other", parentReplyId: "remove"});
  await put(`${root}/keep/reactions/${uid}`, {userId: uid, votes: {root: "up"}});
  await put(`${root}/keep/reactions/other`, {userId: "other", votes: {root: "down"}});
  await put(`${root}/ownerless`, {body: "unknown author", upvotes: 3, replies: []});
  await put(`unrelated/a/replies/${uid}`, {authorUserId: uid, body: "not a talk"});
  await put(`unrelated/a/reactions/${uid}`, {userId: uid, votes: {root: "up"}});
  await put(`users/${uid}`, {uid});
  await deleteAccountData(db, storage, uid);
  assert.equal(await exists(`${root}/keep/replies/remove`), false);
  assert.equal(await exists(`${root}/keep/reactions/${uid}`), false);
  assert.equal(await exists(`${root}/keep/replies/keep`), true);
  assert.equal(await exists(`${root}/keep/reactions/other`), true);
  assert.deepEqual((await db.doc(`${root}/keep`).get()).data(), {authorUserId: "other", body: "keep", upvotes: 7,
    replies: [{id: "legacy-unknown", body: "owner unknown"}], replyAuthorIds: []});
  assert.equal(await exists(`${root}/ownerless`), true);
  assert.equal(await exists(`unrelated/a/replies/${uid}`), true);
  assert.equal(await exists(`unrelated/a/reactions/${uid}`), true);
  assert.equal(await exists(`users/${uid}`), false);
  assert.ok(storageCalls.includes(`users/${uid}/`));
  await deleteAccountData(db, storage, uid);
  assert.equal(await exists(`${root}/keep/replies/keep`), true);
});

test("deleting an authored post recursively removes all its descendants", async () => {
  const uid = "deletion-post-author";
  await put(`${root}/authored`, {authorUserId: uid, body: "mine"});
  await put(`${root}/authored/replies/other`, {authorUserId: "other", body: "thread child"});
  await put(`${root}/authored/reactions/other`, {userId: "other", votes: {root: "up"}});
  await put(`${root}/authored/replies/other/children/deep`, {body: "descendant"});
  await deleteAccountData(db, storage, uid);
  for (const path of ["authored", "authored/replies/other", "authored/reactions/other",
    "authored/replies/other/children/deep"]) assert.equal(await exists(`${root}/${path}`), false);
});

test("legacy reply cleanup keeps the parent body, counters and ownerless replies", async () => {
  const uid = "deletion-legacy";
  await put(`${root}/legacy`, {authorUserId: "other", body: "original", upvotes: 9,
    replies: [{id: "unknown", body: "keep without owner"},
      {id: "remove", authorUserId: uid, body: "mine", replies: []},
      {id: "keep", authorUserId: "other", replies: [{id: "nested", authorUserId: uid, replies: []}]}],
    replyAuthorIds: [uid, "other"]});
  await deleteAccountData(db, storage, uid);
  const saved = (await db.doc(`${root}/legacy`).get()).data()!;
  assert.equal(saved.body, "original");
  assert.equal(saved.upvotes, 9);
  assert.deepEqual(saved.replyAuthorIds, ["other"]);
  assert.deepEqual(saved.replies, [{id: "unknown", body: "keep without owner", replies: []},
    {id: "keep", authorUserId: "other", replies: []}]);
});

test("a multi-page cleanup cannot skip documents or delete another user's choices", async () => {
  const uid = "deletion-many";
  await put(`${root}/many`, {authorUserId: "other", body: "preserved"});
  // More than one cleanup page; no production data or emulator DB clearing.
  const batch = db.batch();
  for (let i = 0; i < 405; i++) batch.set(db.doc(`${root}/many/replies/r${i}`), {authorUserId: uid});
  batch.set(db.doc(`${root}/many/replies/keep`), {authorUserId: "other"});
  await batch.commit();
  await deleteAccountData(db, storage, uid);
  const remaining = await db.doc(`${root}/many`).collection("replies").get();
  assert.deepEqual(remaining.docs.map((doc) => doc.id), ["keep"]);
});

test("the existing owned-topic cleanup also recursively removes v2 activity", async () => {
  const uid = "deletion-topic-owner";
  await put("topics/deletion-owned", {creatorId: uid});
  await put("topics/deletion-owned/talks/post", {authorUserId: "other"});
  await put("topics/deletion-owned/talks/post/replies/reply", {authorUserId: "other"});
  await put("topics/deletion-owned/talks/post/reactions/other", {userId: "other"});
  await deleteAccountData(db, storage, uid);
  assert.equal(await exists("topics/deletion-owned"), false);
  assert.equal(await exists("topics/deletion-owned/talks/post/replies/reply"), false);
  assert.equal(await exists("topics/deletion-owned/talks/post/reactions/other"), false);
});
