/**
 * Bingo Online (lib/bingo) server rules. Pure helpers are exported for tests;
 * the Firestore triggers and callables are wired in index.ts.
 *
 * Line detection and aggregation mirror lib/bingo/domain/bingo_logic.dart.
 */
import {HttpsError} from "firebase-functions/v2/https";

export const BINGO_SIZES = [3, 4, 5] as const;
export const BINGO_MAX_CELLS = 75;
export const BINGO_MAX_CELL_TEXT = 40;
export const BINGO_MAX_TITLE = 60;
export const BINGO_MAX_DESCRIPTION = 300;
export const BINGO_MAX_TAGS = 5;
export const BINGO_MAX_TAG = 20;
export const BINGO_MAX_COMMENT = 500;
export const BINGO_MAX_AUTHOR_NAME = 24;
export const BINGO_REPORT_HIDE_THRESHOLD = 5;
export const FREE = -1;
export const BINGO_REACTIONS = ["clap", "party", "laugh", "heart"] as const;
export type BingoReactionId = (typeof BINGO_REACTIONS)[number];

export interface BingoCellInput {
  text?: string;
  imageUrl?: string;
  imageSource?: string;
  imageCredit?: string;
}

export interface BingoCell {
  text?: string;
  imageUrl?: string;
  imageSource?: "upload" | "itunes";
  imageCredit?: string;
}

export interface BingoEntryData {
  layout: number[];
  marked: number[];
}

export interface BingoAggregate {
  participants: number;
  bingoCount: number;
  markCounts: Record<string, number>;
  appearanceCounts: Record<string, number>;
}

export function requiredCells(size: number, freeCenter: boolean): number {
  return size * size - (freeCenter && size % 2 === 1 ? 1 : 0);
}

export function freePosition(size: number, freeCenter: boolean): number {
  return freeCenter && size % 2 === 1 ? Math.floor((size * size) / 2) : -1;
}

export function allLines(size: number): number[][] {
  const lines: number[][] = [];
  for (let row = 0; row < size; row++) {
    lines.push(Array.from({length: size}, (_, column) => row * size + column));
  }
  for (let column = 0; column < size; column++) {
    lines.push(Array.from({length: size}, (_, row) => row * size + column));
  }
  lines.push(Array.from({length: size}, (_, index) => index * size + index));
  lines.push(Array.from({length: size}, (_, index) => index * size + size - 1 - index));
  return lines;
}

export function effectiveMarks(layout: number[], marked: number[]): Set<number> {
  const marks = new Set<number>();
  for (const position of marked) {
    if (Number.isInteger(position) && position >= 0 && position < layout.length) {
      marks.add(position);
    }
  }
  layout.forEach((cell, position) => {
    if (cell === FREE) marks.add(position);
  });
  return marks;
}

export function lineCount(size: number, layout: number[], marked: number[]): number {
  const marks = effectiveMarks(layout, marked);
  return allLines(size).filter((line) => line.every((position) => marks.has(position))).length;
}

/** A card is valid when it has size² squares that reference distinct pool cells. */
export function isValidLayout(
  size: number,
  freeCenter: boolean,
  cellCount: number,
  layout: unknown,
): layout is number[] {
  if (!Array.isArray(layout) || layout.length !== size * size) return false;
  const free = freePosition(size, freeCenter);
  const seen = new Set<number>();
  for (let position = 0; position < layout.length; position++) {
    const value = layout[position];
    if (!Number.isInteger(value)) return false;
    if (position === free) {
      if (value !== FREE) return false;
      continue;
    }
    if (value < 0 || value >= cellCount || seen.has(value)) return false;
    seen.add(value);
  }
  return true;
}

export function aggregateBingo(
  size: number,
  freeCenter: boolean,
  cellCount: number,
  entries: BingoEntryData[],
): BingoAggregate {
  const result: BingoAggregate = {
    participants: 0,
    bingoCount: 0,
    markCounts: {},
    appearanceCounts: {},
  };
  for (const entry of entries) {
    if (!isValidLayout(size, freeCenter, cellCount, entry.layout)) continue;
    const marked = Array.isArray(entry.marked) ? entry.marked : [];
    const markedSet = new Set(marked);
    result.participants += 1;
    if (lineCount(size, entry.layout, marked) > 0) result.bingoCount += 1;
    entry.layout.forEach((cell, position) => {
      if (cell === FREE) return;
      const key = String(cell);
      result.appearanceCounts[key] = (result.appearanceCounts[key] ?? 0) + 1;
      if (markedSet.has(position)) {
        result.markCounts[key] = (result.markCounts[key] ?? 0) + 1;
      }
    });
  }
  return result;
}

function isAllowedImageUrl(url: string, uid: string, bingoId: string, bucket: string): boolean {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  if (parsed.protocol !== "https:") return false;
  const host = parsed.hostname.toLowerCase();
  // Apple artwork is referenced remotely, as in oshireco.
  if (host === "mzstatic.com" || host.endsWith(".mzstatic.com")) return true;
  // Uploaded images must live in this user's folder for this bingo.
  if (host === "firebasestorage.googleapis.com") {
    const expected = `/v0/b/${bucket}/o/` +
      encodeURIComponent(`users/${uid}/bingos/${bingoId}/cells/`);
    return parsed.pathname.startsWith(expected);
  }
  return false;
}

function trimmedString(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  const trimmed = value.normalize("NFC").trim();
  return trimmed.length > max ? trimmed.slice(0, max) : trimmed;
}

export interface ValidBingoInput {
  title: string;
  description: string;
  tags: string[];
  size: number;
  freeCenter: boolean;
  shufflePerPlayer: boolean;
  cells: BingoCell[];
  creatorName: string;
  isPublic: boolean;
}

/** Validates and normalizes a publishBingo payload, throwing HttpsError. */
export function validateBingoInput(
  data: Record<string, unknown>,
  context: {uid: string; bingoId: string; bucket: string},
): ValidBingoInput {
  const title = trimmedString(data.title, BINGO_MAX_TITLE + 1);
  if (title.length === 0 || title.length > BINGO_MAX_TITLE) {
    throw new HttpsError("invalid-argument", "タイトルが不正です");
  }
  const description = trimmedString(data.description, BINGO_MAX_DESCRIPTION + 1);
  if (description.length > BINGO_MAX_DESCRIPTION) {
    throw new HttpsError("invalid-argument", "説明が長すぎます");
  }
  const rawTags = Array.isArray(data.tags) ? data.tags : [];
  if (rawTags.length > BINGO_MAX_TAGS) {
    throw new HttpsError("invalid-argument", "タグが多すぎます");
  }
  const tags = rawTags
    .map((tag) => trimmedString(tag, BINGO_MAX_TAG))
    .filter((tag) => tag.length > 0);
  const size = Number(data.size);
  if (!(BINGO_SIZES as readonly number[]).includes(size)) {
    throw new HttpsError("invalid-argument", "カードの大きさが不正です");
  }
  const freeCenter = data.freeCenter !== false;
  const rawCells = Array.isArray(data.cells) ? data.cells : [];
  if (
    rawCells.length < requiredCells(size, freeCenter) ||
    rawCells.length > BINGO_MAX_CELLS
  ) {
    throw new HttpsError("invalid-argument", "マスの数が不正です");
  }
  const seenTexts = new Set<string>();
  const cells: BingoCell[] = rawCells.map((raw: unknown) => {
    const input = (raw ?? {}) as BingoCellInput;
    const text = trimmedString(input.text, BINGO_MAX_CELL_TEXT + 1);
    if (text.length > BINGO_MAX_CELL_TEXT) {
      throw new HttpsError("invalid-argument", "マスの文字数が多すぎます");
    }
    const imageUrl = typeof input.imageUrl === "string" ? input.imageUrl.trim() : "";
    if (imageUrl.length > 0 &&
      !isAllowedImageUrl(imageUrl, context.uid, context.bingoId, context.bucket)) {
      throw new HttpsError("invalid-argument", "画像URLが不正です");
    }
    if (text.length === 0 && imageUrl.length === 0) {
      throw new HttpsError("invalid-argument", "空のマスがあります");
    }
    if (imageUrl.length === 0) {
      const key = text.toLowerCase().replace(/\s+/gu, " ");
      if (seenTexts.has(key)) {
        throw new HttpsError("invalid-argument", "同じ内容のマスがあります");
      }
      seenTexts.add(key);
    }
    const cell: BingoCell = {};
    if (text.length > 0) cell.text = text;
    if (imageUrl.length > 0) {
      cell.imageUrl = imageUrl;
      cell.imageSource = imageUrl.includes("mzstatic.com") ? "itunes" : "upload";
      const credit = trimmedString(input.imageCredit, 120);
      if (credit.length > 0 && cell.imageSource === "itunes") cell.imageCredit = credit;
    }
    return cell;
  });
  return {
    title,
    description,
    tags,
    size,
    freeCenter,
    shufflePerPlayer: data.shufflePerPlayer !== false,
    cells,
    creatorName: trimmedString(data.creatorName, BINGO_MAX_AUTHOR_NAME) || "Guest",
    isPublic: data.isPublic !== false,
  };
}

function reactionId(value: unknown): BingoReactionId | null {
  return (BINGO_REACTIONS as readonly unknown[]).includes(value) ?
    value as BingoReactionId :
    null;
}

/**
 * Count changes for one person's reaction document moving from `before` to
 * `after` (either may be missing or invalid). Unchanged reactions yield {}.
 */
export function reactionDelta(
  before: unknown,
  after: unknown,
): Partial<Record<BingoReactionId, number>> {
  const from = reactionId(before);
  const to = reactionId(after);
  if (from === to) return {};
  const delta: Partial<Record<BingoReactionId, number>> = {};
  if (from) delta[from] = -1;
  if (to) delta[to] = (delta[to] ?? 0) + 1;
  return delta;
}
