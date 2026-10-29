import {readFileSync} from "node:fs";
import test, {after, before, beforeEach} from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection, collectionGroup, deleteDoc, doc, getDoc, getDocs, orderBy, query,
  setDoc, updateDoc, where,
} from "firebase/firestore";
import {ref, uploadBytes} from "firebase/storage";

let env;
const board = (overrides = {}) => ({
  title: "t", size: 3, freeCenter: true, cells: [], creatorId: "owner",
  isPublic: true, listed: true, moderationStatus: "approved", participants: 0,
  createdAt: new Date(), ...overrides,
});
const entry = (uid, overrides = {}) => ({
  userId: uid, userName: "U", layout: [0, 1, 2, 3, -1, 4, 5, 6, 7], marked: [0],
  firstBingoAt: null, updatedAt: new Date(), ...overrides,
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-bingo",
    firestore: {rules: readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8"), host: "127.0.0.1", port: 8085},
    storage: {rules: readFileSync(new URL("../../storage.rules", import.meta.url), "utf8"), host: "127.0.0.1", port: 9199},
  });
});
after(() => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "bingos/pub"), board());
    await setDoc(doc(db, "bingos/priv"), board({isPublic: false, listed: false}));
    await setDoc(doc(db, "bingos/blocked"), board({moderationStatus: "blocked", listed: false}));
    await setDoc(doc(db, "bingos/pub/comments/c1"), {authorId: "alice", body: "hi"});
    await setDoc(doc(db, "bingos/pub/bingoEntries/alice"), entry("alice"));
  });
});

const as = (uid) => env.authenticatedContext(uid, {firebase: {sign_in_provider: "anonymous"}}).firestore();
const anon = () => env.unauthenticatedContext().firestore();

test("listed boards are public, private boards only for the owner", async () => {
  await assertSucceeds(getDoc(doc(anon(), "bingos/pub")));
  await assertFails(getDoc(doc(as("bob"), "bingos/priv")));
  await assertSucceeds(getDoc(doc(as("owner"), "bingos/priv")));
  await assertSucceeds(getDocs(query(collection(anon(), "bingos"), where("listed", "==", true), orderBy("createdAt", "desc"))));
  await assertFails(getDocs(collection(anon(), "bingos")));
  await assertSucceeds(getDocs(query(collection(as("owner"), "bingos"), where("creatorId", "==", "owner"))));
});

test("boards are created and deleted only by Functions", async () => {
  await assertFails(setDoc(doc(as("owner"), "bingos/new"), board()));
  await assertFails(deleteDoc(doc(as("owner"), "bingos/pub")));
});

test("owner may only toggle visibility consistently with moderation", async () => {
  await assertSucceeds(updateDoc(doc(as("owner"), "bingos/pub"), {isPublic: false, listed: false, updatedAt: new Date()}));
  await assertFails(updateDoc(doc(as("owner"), "bingos/priv"), {isPublic: true, listed: false}));
  await assertFails(updateDoc(doc(as("owner"), "bingos/blocked"), {isPublic: true, listed: true}));
  await assertSucceeds(updateDoc(doc(as("owner"), "bingos/blocked"), {isPublic: true, listed: false}));
  await assertFails(updateDoc(doc(as("owner"), "bingos/pub"), {participants: 999}));
  await assertFails(updateDoc(doc(as("bob"), "bingos/pub"), {isPublic: false, listed: false}));
});

test("participants write only their own, well-formed card", async () => {
  await assertSucceeds(setDoc(doc(as("bob"), "bingos/pub/bingoEntries/bob"), entry("bob")));
  await assertFails(setDoc(doc(as("bob"), "bingos/pub/bingoEntries/alice"), entry("alice")));
  await assertFails(setDoc(doc(as("bob"), "bingos/pub/bingoEntries/bob"), entry("bob", {layout: [0, 1]})));
  await assertFails(setDoc(doc(as("bob"), "bingos/pub/bingoEntries/bob"), entry("bob", {extra: true})));
  await assertFails(setDoc(doc(as("bob"), "bingos/priv/bingoEntries/bob"), entry("bob")));
  await assertSucceeds(setDoc(doc(as("owner"), "bingos/priv/bingoEntries/owner"), entry("owner")));
});

test("My Bingo collection-group query sees only the caller's cards", async () => {
  await assertSucceeds(getDocs(query(collectionGroup(as("alice"), "bingoEntries"), where("userId", "==", "alice"))));
  await assertFails(getDocs(query(collectionGroup(as("alice"), "bingoEntries"), where("userId", "==", "bob"))));
  await assertFails(getDocs(collectionGroup(as("alice"), "bingoEntries")));
});

test("comments are created by Functions and deleted by author or board owner", async () => {
  await assertSucceeds(getDocs(collection(anon(), "bingos/pub/comments")));
  await assertFails(setDoc(doc(as("bob"), "bingos/pub/comments/c2"), {authorId: "bob", body: "x"}));
  await assertFails(deleteDoc(doc(as("bob"), "bingos/pub/comments/c1")));
  await assertSucceeds(deleteDoc(doc(as("alice"), "bingos/pub/comments/c1")));
});

test("board owner can delete any comment", async () => {
  await assertSucceeds(deleteDoc(doc(as("owner"), "bingos/pub/comments/c1")));
});

test("reports: one per user and target, with a matching id", async () => {
  const report = {bingoId: "pub", targetType: "comment", targetId: "c1", reporterUserId: "bob"};
  await assertFails(setDoc(doc(as("bob"), "bingos/pub/reports/wrong-id"), report));
  await assertSucceeds(setDoc(doc(as("bob"), "bingos/pub/reports/comment_c1_bob"), report));
  await assertFails(setDoc(doc(as("bob"), "bingos/pub/reports/comment_c1_bob"), report));
  await assertFails(setDoc(doc(as("bob"), "bingos/pub/reports/user_c1_bob"), {...report, targetType: "user"}));
  await assertFails(getDoc(doc(as("bob"), "bingos/pub/reports/comment_c1_bob")));
});

test("storage: guests upload compressed JPEG cells only into their own folder", async () => {
  const storage = env.authenticatedContext("bob", {firebase: {sign_in_provider: "anonymous"}}).storage();
  const jpeg = new Uint8Array(1000);
  await assertSucceeds(uploadBytes(ref(storage, "users/bob/bingos/b1/cells/0.jpg"), jpeg, {contentType: "image/jpeg"}));
  await assertFails(uploadBytes(ref(storage, "users/alice/bingos/b1/cells/0.jpg"), jpeg, {contentType: "image/jpeg"}));
  await assertFails(uploadBytes(ref(storage, "users/bob/bingos/b1/cells/x.html"), jpeg, {contentType: "text/html"}));
  await assertSucceeds(uploadBytes(ref(storage, "users/bob/bingos/b1/cells/1.jpg"), new Uint8Array(150 * 1024), {contentType: "image/jpeg"}));
  await assertFails(uploadBytes(ref(storage, "users/bob/bingos/b1/cells/2.jpg"), new Uint8Array(250 * 1024), {contentType: "image/jpeg"}));
  await assertFails(uploadBytes(ref(storage, "users/bob/bingos/b1/cells/3.jpg"), jpeg, {contentType: "image/png"}));
});
