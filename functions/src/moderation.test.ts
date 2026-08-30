import assert from "node:assert/strict";
import test from "node:test";

import {matchNgWords, moderateText, normalizeText} from "./moderation";

test("全角半角・空白・記号・カタカナ揺れを正規化する", () => {
  assert.equal(normalizeText("ＡＢＣ"), "abc");
  assert.equal(normalizeText("あ　い-う_え・お"), "あいうえお");
  assert.equal(normalizeText("ｱｲｳ"), normalizeText("あいう"));
});

test("正規化後にNGワードへ一致するかを判定する", () => {
  const config = {blockWords: ["きんし"], flagWords: ["ちゅうい"], allowWords: []};
  const blocked = matchNgWords(normalizeText("これはき　ん-し語です"), config);
  assert.equal(blocked.blockedHit, true);

  const flagged = matchNgWords(normalizeText("ちゅういしてください"), config);
  assert.equal(flagged.flaggedHit, true);
});

test("allowWordsに含まれる語は誤検知として除外される", () => {
  const config = {
    blockWords: ["すぱむ"],
    flagWords: [],
    allowWords: ["あんぜんなすぱむよけ"],
  };
  // "すぱむ" が許可語 "あんぜんなすぱむよけ" の一部としてのみ出現する場合はヒットしない
  const result = matchNgWords(normalizeText("あんぜんなすぱむよけ対策"), config);
  assert.equal(result.blockedHit, false);
  // 許可語と無関係な単独出現はヒットする
  const stillBlocked = matchNgWords(normalizeText("これはすぱむです"), config);
  assert.equal(stillBlocked.blockedHit, true);
});

test("明確な禁止語を含む場合はblockedを返す", () => {
  const config = {blockWords: ["ng"], flagWords: [], allowWords: []};
  const result = moderateText({title: "これはNGワードです"}, config);
  assert.equal(result.status, "blocked");
});

test("要注意語のみの場合はflaggedを返す", () => {
  const config = {blockWords: [], flagWords: ["ようちゅうい"], allowWords: []};
  const result = moderateText({title: "ようちゅういな内容です"}, config);
  assert.equal(result.status, "flagged");
});

test("該当語がなければapprovedを返す", () => {
  const config = {blockWords: ["ng"], flagWords: ["caution"], allowWords: []};
  const result = moderateText({title: "普通のタイトルです"}, config);
  assert.equal(result.status, "approved");
});

test("電話番号やメールアドレスなど個人情報を含む場合はblockedを返す", () => {
  const config = {blockWords: [], flagWords: [], allowWords: []};
  const phone = moderateText({description: "連絡先は090-1234-5678です"}, config);
  assert.equal(phone.status, "blocked");

  const email = moderateText({description: "test@example.com へ連絡"}, config);
  assert.equal(email.status, "blocked");
});

test("URLを含むスパムらしき投稿はflaggedを返す", () => {
  const config = {blockWords: [], flagWords: [], allowWords: []};
  const result = moderateText({description: "詳しくはhttps://example.comへ"}, config);
  assert.equal(result.status, "flagged");
});
