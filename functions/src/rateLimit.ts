import {FieldValue, Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

export type RateLimitAction =
  | "create"
  | "publish"
  | "imageSearch"
  | "contributeImage";

export interface RateLimitTier {
  create: number;
  publish: number;
  imageSearch: number;
  contributeImage: number;
}

export const defaultRateLimits: {anonymous: RateLimitTier; authenticated: RateLimitTier} = {
  anonymous: {create: 3, publish: 10, imageSearch: 30, contributeImage: 0},
  authenticated: {
    create: 15,
    publish: 60,
    imageSearch: 150,
    contributeImage: 20,
  },
};

const WINDOW_MS = 24 * 60 * 60 * 1000;

async function loadLimits(firestore: Firestore): Promise<{
  anonymous: RateLimitTier;
  authenticated: RateLimitTier;
}> {
  const snapshot = await firestore.doc("moderationConfig/rateLimits").get();
  const data = snapshot.data();
  if (!data) return defaultRateLimits;
  return {
    anonymous: {...defaultRateLimits.anonymous, ...(data.anonymous ?? {})},
    authenticated: {
      ...defaultRateLimits.authenticated,
      ...(data.authenticated ?? {}),
    },
  };
}

export function rateLimitRef(firestore: Firestore, uid: string) {
  return firestore.doc(`rateLimits/${uid}`);
}

/**
 * 既に読み込み済みのレート制限ドキュメントに対して許可判定と書き込み
 * ペイロードを純粋に計算する(Firestoreへのアクセスは行わない)。
 * dailyLimit.computeDailyCreateUpdate と同様の理由で読み取り/書き込みを
 * 分離できる形にしている。
 */
export function computeRateLimitUpdate(
  data: Record<string, unknown>,
  limit: number,
  action: RateLimitAction,
): Record<string, unknown> {
  const countField = `${action}Count`;
  const windowField = `${action}WindowStart`;
  const now = Date.now();
  const windowStart = (data[windowField] as {toMillis?: () => number} | undefined)
    ?.toMillis?.() ?? 0;
  const withinWindow = now - windowStart < WINDOW_MS;
  const currentCount = withinWindow ? (data[countField] as number | undefined) ?? 0 : 0;

  if (currentCount >= limit) {
    throw new HttpsError(
      "resource-exhausted",
      `${action}の利用上限に達しました。しばらくしてから再度お試しください`,
    );
  }

  return {
    [countField]: currentCount + 1,
    [windowField]: withinWindow ?
      data[windowField] ?? FieldValue.serverTimestamp() :
      FieldValue.serverTimestamp(),
  };
}

export async function checkAndConsume(
  firestore: Firestore,
  uid: string,
  isAnonymous: boolean,
  action: RateLimitAction,
): Promise<void> {
  const limits = await loadLimits(firestore);
  const limit = (isAnonymous ? limits.anonymous : limits.authenticated)[action];
  const reference = rateLimitRef(firestore, uid);

  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const update = computeRateLimitUpdate(snapshot.data() ?? {}, limit, action);
    transaction.set(reference, update, {merge: true});
  });
}

export {loadLimits};
