import {FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

export const BASE_LIMITS = {anonymous: 3, authenticated: 10} as const;
export const MAX_AD_BONUS = 10;
export const MIN_CREATE_INTERVAL_MS = 10 * 1000;
const AD_TOKEN_TTL_MS = 2 * 60 * 1000;

// JST(UTC+9)の日付文字列。日次リセットの単位。
function todayKey(): string {
  const now = new Date(Date.now() + 9 * 60 * 60 * 1000);
  return now.toISOString().slice(0, 10);
}

export interface DailyCounterData {
  usageDate?: string;
  dailyTierCount?: number;
  adBonusCount?: number;
  lastCreateAt?: Timestamp;
}

function effectiveCounts(data: DailyCounterData, today: string): {
  dailyTierCount: number;
  adBonusCount: number;
} {
  if (data.usageDate !== today) {
    return {dailyTierCount: 0, adBonusCount: 0};
  }
  return {
    dailyTierCount: data.dailyTierCount ?? 0,
    adBonusCount: data.adBonusCount ?? 0,
  };
}

export function dailyTierCounterRef(firestore: Firestore, uid: string) {
  return firestore.doc(`dailyTierCounters/${uid}`);
}

/**
 * 既に読み込み済みのカウンタードキュメントに対して、日次作成の許可判定と
 * 書き込みペイロードを純粋に計算する(Firestoreへのアクセスは行わない)。
 * Firestoreトランザクションは「全ての読み取り→全ての書き込み」の順序を
 * 強制するため、読み取り(transaction.get)と書き込み(transaction.set)を
 * 呼び出し側で分離できるようにこの形にしている。これにより、モデレーション
 * 判定や他の書き込みが失敗した場合にカウントだけが増えることを防げる。
 */
export function computeDailyCreateUpdate(
  data: DailyCounterData,
  isAnonymous: boolean,
): Record<string, unknown> {
  const today = todayKey();
  const {dailyTierCount, adBonusCount} = effectiveCounts(data, today);

  if (data.usageDate === today && data.lastCreateAt) {
    const elapsed = Date.now() - data.lastCreateAt.toMillis();
    if (elapsed < MIN_CREATE_INTERVAL_MS) {
      throw new HttpsError(
        "resource-exhausted",
        "短時間に連続して作成できません。少し間隔を空けてください",
        {reason: "cooldown"},
      );
    }
  }

  const base = isAnonymous ? BASE_LIMITS.anonymous : BASE_LIMITS.authenticated;
  const allowed = base + (isAnonymous ? 0 : adBonusCount);
  if (dailyTierCount >= allowed) {
    throw new HttpsError(
      "resource-exhausted",
      "本日の作成上限に達しました",
      {reason: "dailyLimit", isAnonymous, dailyTierCount, allowed},
    );
  }

  return {
    usageDate: today,
    dailyTierCount: dailyTierCount + 1,
    adBonusCount,
    lastCreateAt: FieldValue.serverTimestamp(),
  };
}

export async function getDailyStatus(
  firestore: Firestore,
  uid: string,
  isAnonymous: boolean,
): Promise<{
  usageDate: string;
  dailyTierCount: number;
  adBonusCount: number;
  baseLimit: number;
  maxAdBonus: number;
  allowed: number;
  remaining: number;
}> {
  const today = todayKey();
  const snapshot = await firestore.doc(`dailyTierCounters/${uid}`).get();
  const data = (snapshot.data() ?? {}) as DailyCounterData;
  const {dailyTierCount, adBonusCount} = effectiveCounts(data, today);
  const base = isAnonymous ? BASE_LIMITS.anonymous : BASE_LIMITS.authenticated;
  const allowed = base + (isAnonymous ? 0 : adBonusCount);
  return {
    usageDate: today,
    dailyTierCount,
    adBonusCount,
    baseLimit: base,
    maxAdBonus: MAX_AD_BONUS,
    allowed,
    remaining: Math.max(0, allowed - dailyTierCount),
  };
}

export async function requestAdBonusToken(
  firestore: Firestore,
  uid: string,
): Promise<string> {
  const tokenId = firestore.collection("adBonusTokens").doc().id;
  await firestore.doc(`adBonusTokens/${tokenId}`).set({
    uid,
    consumed: false,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + AD_TOKEN_TTL_MS),
  });
  return tokenId;
}

export async function confirmAdBonus(
  firestore: Firestore,
  uid: string,
  token: string,
): Promise<{adBonusCount: number}> {
  const tokenReference = firestore.doc(`adBonusTokens/${token}`);
  const counterReference = firestore.doc(`dailyTierCounters/${uid}`);
  const today = todayKey();

  return firestore.runTransaction(async (transaction) => {
    const tokenSnapshot = await transaction.get(tokenReference);
    const tokenData = tokenSnapshot.data();
    if (!tokenSnapshot.exists || !tokenData) {
      throw new HttpsError("invalid-argument", "広告視聴トークンが無効です");
    }
    if (tokenData.uid !== uid) {
      throw new HttpsError("permission-denied", "広告視聴トークンが無効です");
    }
    if (tokenData.consumed) {
      throw new HttpsError("already-exists", "この広告視聴は既に処理済みです");
    }
    const expiresAt = tokenData.expiresAt as Timestamp | undefined;
    if (!expiresAt || expiresAt.toMillis() < Date.now()) {
      throw new HttpsError("deadline-exceeded", "広告視聴トークンの有効期限が切れています");
    }

    const counterSnapshot = await transaction.get(counterReference);
    const counterData = (counterSnapshot.data() ?? {}) as DailyCounterData;
    const {dailyTierCount, adBonusCount} = effectiveCounts(counterData, today);
    if (adBonusCount >= MAX_AD_BONUS) {
      throw new HttpsError(
        "resource-exhausted",
        "本日の広告ボーナス上限に達しました",
        {reason: "adBonusLimit"},
      );
    }

    transaction.set(tokenReference, {consumed: true}, {merge: true});
    transaction.set(counterReference, {
      usageDate: today,
      dailyTierCount,
      adBonusCount: adBonusCount + 1,
    }, {merge: true});

    return {adBonusCount: adBonusCount + 1};
  });
}
