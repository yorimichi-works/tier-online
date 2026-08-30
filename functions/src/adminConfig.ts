import {Firestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";

import {emptyNgWordConfig, NgWordConfig} from "./moderation";

const MAX_WORDS_PER_LIST = 2000;
const MAX_WORD_LENGTH = 100;

export async function assertAdmin(
  firestore: Firestore,
  request: CallableRequest,
): Promise<string> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  const uid = request.auth.uid;
  const adminDoc = await firestore.collection("admins").doc(uid).get();
  if (!adminDoc.exists) {
    throw new HttpsError("permission-denied", "管理者のみ実行できます");
  }
  return uid;
}

export async function loadNgWordConfig(firestore: Firestore): Promise<NgWordConfig> {
  const snapshot = await firestore.doc("moderationConfig/ngWords").get();
  const data = snapshot.data();
  if (!data) return emptyNgWordConfig;
  return {
    blockWords: normalizeList(data.blockWords),
    flagWords: normalizeList(data.flagWords),
    allowWords: normalizeList(data.allowWords),
  };
}

function normalizeList(value: unknown): string[] {
  return Array.isArray(value) ? (value as string[]) : [];
}

function sanitizeWordList(value: unknown, fieldName: string): string[] {
  if (!Array.isArray(value)) {
    throw new HttpsError("invalid-argument", `${fieldName}は配列で指定してください`);
  }
  const words = value
    .filter((word): word is string => typeof word === "string")
    .map((word) => word.trim())
    .filter((word) => word.length > 0 && word.length <= MAX_WORD_LENGTH);
  const deduped = Array.from(new Set(words));
  if (deduped.length > MAX_WORDS_PER_LIST) {
    throw new HttpsError(
      "invalid-argument",
      `${fieldName}は${MAX_WORDS_PER_LIST}件までです`,
    );
  }
  return deduped;
}

export async function updateNgWordConfigForAdmin(
  firestore: Firestore,
  data: Record<string, unknown>,
): Promise<NgWordConfig> {
  const config: NgWordConfig = {
    blockWords: sanitizeWordList(data.blockWords, "blockWords"),
    flagWords: sanitizeWordList(data.flagWords, "flagWords"),
    allowWords: sanitizeWordList(data.allowWords, "allowWords"),
  };
  await firestore.doc("moderationConfig/ngWords").set(config);
  return config;
}
