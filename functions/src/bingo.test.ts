import assert from "node:assert/strict";
import test from "node:test";

import {
  aggregateBingo,
  FREE,
  isValidLayout,
  lineCount,
  reactionDelta,
  requiredCells,
  validateBingoInput,
} from "./bingo";

const context = {uid: "user-1", bingoId: "bingo-abc", bucket: "tier-online.firebasestorage.app"};

function textCells(count: number) {
  return Array.from({length: count}, (_, index) => ({text: `マス${index}`}));
}

test("FREEは奇数サイズの中央だけで、必要マス数から除く", () => {
  assert.equal(requiredCells(5, true), 24);
  assert.equal(requiredCells(4, true), 16);
  assert.equal(requiredCells(3, false), 9);
});

test("行・列・斜めのBINGOを数え、FREEはチェック済みとして扱う", () => {
  const layout = [0, 1, 2, 3, FREE, 4, 5, 6, 7];
  assert.equal(lineCount(3, layout, []), 0);
  // 対角線 0-4-8 (4はFREE)
  assert.equal(lineCount(3, layout, [0, 8]), 1);
  // 中央の行 3-4-5 と 中央の列 1-4-7 も追加
  assert.equal(lineCount(3, layout, [0, 8, 3, 5, 1, 7]), 3);
  // 範囲外のマークは無視する
  assert.equal(lineCount(3, layout, [-1, 99]), 0);
});

test("カード配置は重複・範囲外・FREE位置の不正を拒否する", () => {
  assert.equal(isValidLayout(3, true, 8, [0, 1, 2, 3, FREE, 4, 5, 6, 7]), true);
  assert.equal(isValidLayout(3, true, 8, [0, 0, 2, 3, FREE, 4, 5, 6, 7]), false);
  assert.equal(isValidLayout(3, true, 8, [0, 1, 2, 3, 8, 4, 5, 6, 7]), false);
  assert.equal(isValidLayout(3, true, 8, [0, 1, 2, 3, FREE, 4, 5, 6, 99]), false);
  assert.equal(isValidLayout(3, true, 8, [0, 1, 2]), false);
});

test("参加者・BINGO達成者・マスごとのチェック率を集計する", () => {
  const result = aggregateBingo(3, true, 8, [
    {layout: [0, 1, 2, 3, FREE, 4, 5, 6, 7], marked: [0, 8]},
    {layout: [7, 6, 5, 4, FREE, 3, 2, 1, 0], marked: [0]},
    {layout: [0, 1], marked: [0]},
  ]);
  assert.equal(result.participants, 2);
  assert.equal(result.bingoCount, 1);
  assert.equal(result.markCounts["0"], 1);
  assert.equal(result.markCounts["7"], 2);
  assert.equal(result.appearanceCounts["0"], 2);
});

test("公開データを検証し、Apple画像と自分のアップロード画像だけを許可する", () => {
  const upload = `https://firebasestorage.googleapis.com/v0/b/${context.bucket}/o/` +
    encodeURIComponent("users/user-1/bingos/bingo-abc/cells/0.jpg") + "?alt=media";
  const result = validateBingoInput({
    title: "  夏ビンゴ ",
    size: 3,
    freeCenter: true,
    cells: [
      {imageUrl: upload},
      {text: "曲", imageUrl: "https://is1-ssl.mzstatic.com/image/thumb/x/600x600bb.jpg", imageCredit: "Artist – Album"},
      ...textCells(6),
    ],
  }, context);
  assert.equal(result.title, "夏ビンゴ");
  assert.equal(result.cells[0].imageSource, "upload");
  assert.equal(result.cells[1].imageSource, "itunes");
  assert.equal(result.cells[1].imageCredit, "Artist – Album");

  const otherUser = upload.replace("user-1", "user-2");
  assert.throws(() => validateBingoInput({
    title: "x", size: 3, cells: [{imageUrl: otherUser}, ...textCells(7)],
  }, context));
  assert.throws(() => validateBingoInput({
    title: "x", size: 3, cells: [{imageUrl: "https://example.com/a.jpg"}, ...textCells(7)],
  }, context));
});

test("マス不足・重複・長すぎる文字列を拒否する", () => {
  assert.throws(() => validateBingoInput({title: "x", size: 5, cells: textCells(23)}, context));
  assert.throws(() => validateBingoInput({
    title: "x", size: 3, cells: [{text: "A"}, {text: " a "}, ...textCells(6)],
  }, context));
  assert.throws(() => validateBingoInput({
    title: "x", size: 3, cells: [{text: "あ".repeat(41)}, ...textCells(7)],
  }, context));
  assert.throws(() => validateBingoInput({title: "", size: 3, cells: textCells(8)}, context));
  assert.throws(() => validateBingoInput({title: "x", size: 6, cells: textCells(40)}, context));
});

test("リアクションの付け替え・取り消しを件数の増減に変換する", () => {
  assert.deepEqual(reactionDelta(undefined, "clap"), {clap: 1});
  assert.deepEqual(reactionDelta("clap", "heart"), {clap: -1, heart: 1});
  assert.deepEqual(reactionDelta("heart", undefined), {heart: -1});
  assert.deepEqual(reactionDelta("clap", "clap"), {});
  assert.deepEqual(reactionDelta(undefined, "evil"), {});
});
