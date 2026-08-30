/**
 * NGワード判定の枠組み。
 *
 * 実際の禁止語彙(児童性的表現・露骨な性的表現・差別語・脅迫語など)は
 * Firestore の moderationConfig/ngWords ドキュメント(
 *   {blockWords: string[], flagWords: string[], allowWords: string[]}
 * )に管理者が投入する運用とし、このファイルにはワードを直接記載しない。
 * 未投入の間は個人情報・スパムなどの構造的パターン判定のみが有効になる。
 * 変更は adminConfig.ts の updateNgWordConfig(管理者専用Callable)経由。
 */

export type ModerationDecision = "approved" | "flagged" | "blocked";

export interface ModerationResult {
  status: ModerationDecision;
  reasons: string[];
}

export interface NgWordConfig {
  blockWords: string[];
  flagWords: string[];
  // 部分一致による誤検知を避けるための許可語。ここに含まれる語の出現箇所は
  // block/flag判定の対象文字列から取り除いてから判定する。
  allowWords: string[];
}

export const emptyNgWordConfig: NgWordConfig = {
  blockWords: [],
  flagWords: [],
  allowWords: [],
};

// 全角→半角(英数記号)変換
function toHalfWidth(input: string): string {
  return input.replace(/[Ａ-Ｚａ-ｚ０-９]/g, (char) =>
    String.fromCharCode(char.charCodeAt(0) - 0xfee0),
  );
}

// カタカナ→ひらがな変換(表記揺れの吸収)
function toHiragana(input: string): string {
  return input.replace(/[ァ-ヶ]/g, (char) =>
    String.fromCharCode(char.charCodeAt(0) - 0x60),
  );
}

// 判定を妨害するために挿入されがちな空白・記号・約物を除去
const NOISE_PATTERN =
  /[\s\-_・.。,、!！?？~〜'"「」『』【】()（）\[\]｛｝{}*＊#＃/／\\＼|｜]+/g;

export function normalizeText(input: string): string {
  return toHiragana(toHalfWidth(input.normalize("NFKC")))
    .toLowerCase()
    .replace(NOISE_PATTERN, "");
}

// allowWords に一致する箇所を対象文字列から取り除き、block/flag判定が
// 許可語を内包する語(例: 許可語がblock語の一部として偶然出現する場合)に
// 過剰反応しないようにする。
function stripAllowedSegments(normalized: string, allowWords: string[]): string {
  let result = normalized;
  for (const word of allowWords) {
    const normalizedWord = normalizeText(word);
    if (normalizedWord.length === 0) continue;
    result = result.split(normalizedWord).join("");
  }
  return result;
}

export function matchNgWords(
  normalized: string,
  config: NgWordConfig,
): {blockedHit: boolean; flaggedHit: boolean; matches: string[]} {
  const matches: string[] = [];
  let blockedHit = false;
  let flaggedHit = false;
  const sanitized = stripAllowedSegments(normalized, config.allowWords);

  for (const word of config.blockWords) {
    const normalizedWord = normalizeText(word);
    if (normalizedWord.length > 0 && sanitized.includes(normalizedWord)) {
      blockedHit = true;
      matches.push(`block:${word}`);
    }
  }
  for (const word of config.flagWords) {
    const normalizedWord = normalizeText(word);
    if (normalizedWord.length > 0 && sanitized.includes(normalizedWord)) {
      flaggedHit = true;
      matches.push(`flag:${word}`);
    }
  }
  return {blockedHit, flaggedHit, matches};
}

// 個人情報っぽい構造的パターン(単語辞書ではなく形式判定なのでコードに直接持つ)
const PERSONAL_INFO_PATTERNS: Array<{name: string; pattern: RegExp}> = [
  {name: "phone", pattern: /0\d{1,4}-?\d{1,4}-?\d{3,4}/},
  {name: "email", pattern: /[\w.+-]+@[\w-]+\.[\w.-]+/},
  {name: "postalCode", pattern: /\b\d{3}-?\d{4}\b/},
];

// スパムっぽい構造的パターン
const SPAM_PATTERNS: Array<{name: string; pattern: RegExp}> = [
  {name: "url", pattern: /https?:\/\/\S+/i},
  {name: "repeatedUrl", pattern: /(https?:\/\/\S+.*){2,}/i},
  {name: "repeatedChar", pattern: /(.)\1{9,}/},
  {name: "inviteSpam", pattern: /(line|telegram|line@|ライン|テレグラム).{0,10}(id|追加|登録)/i},
];

function matchStructuralPatterns(
  raw: string,
  patterns: Array<{name: string; pattern: RegExp}>,
): string[] {
  const hits: string[] = [];
  for (const {name, pattern} of patterns) {
    if (pattern.test(raw)) hits.push(name);
  }
  return hits;
}

export function moderateText(
  fields: Record<string, string | undefined | null>,
  config: NgWordConfig,
): ModerationResult {
  const reasons: string[] = [];
  let status: ModerationDecision = "approved";

  for (const [fieldName, value] of Object.entries(fields)) {
    if (!value) continue;
    const normalized = normalizeText(value);
    const {blockedHit, flaggedHit, matches} = matchNgWords(normalized, config);
    if (blockedHit) {
      status = "blocked";
      reasons.push(...matches.map((match) => `${fieldName}:${match}`));
      continue;
    }
    if (flaggedHit && status !== "blocked") {
      status = "flagged";
      reasons.push(...matches.map((match) => `${fieldName}:${match}`));
    }

    const personalHits = matchStructuralPatterns(value, PERSONAL_INFO_PATTERNS);
    if (personalHits.length > 0) {
      status = "blocked";
      reasons.push(...personalHits.map((hit) => `${fieldName}:personalInfo:${hit}`));
    }

    const spamHits = matchStructuralPatterns(value, SPAM_PATTERNS);
    if (spamHits.length > 0 && status !== "blocked") {
      status = "flagged";
      reasons.push(...spamHits.map((hit) => `${fieldName}:spam:${hit}`));
    }
  }

  return {status, reasons};
}
