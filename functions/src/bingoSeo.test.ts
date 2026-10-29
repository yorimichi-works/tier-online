import assert from "node:assert/strict";
import test from "node:test";

import {bingoMetaHead, boardForPreview, injectBingoMeta} from "./bingoSeo";

const origin = "https://bingo-online.web.app";
const shell = `<html><head>
  <!--bingo-meta-->
  <title>generic</title>
  <!--/bingo-meta-->
  <meta name="theme-color" content="#FFFFFF">
</head><body></body></html>`;

test("公開ビンゴは最初の画像マスとタイトルでプレビューを作る", () => {
  const board = boardForPreview("b1", {
    listed: true,
    title: "YOASOBI <聴いた曲> ビンゴ",
    description: "",
    size: 3,
    cells: [
      {text: "テキストだけ"},
      {imageUrl: "javascript:alert(1)"},
      {imageUrl: "https://is1-ssl.mzstatic.com/a/400x400bb.jpg"},
    ],
  });
  assert.ok(board);
  assert.equal(board.imageUrl, "https://is1-ssl.mzstatic.com/a/400x400bb.jpg");

  const head = bingoMetaHead({origin, locale: "ja", path: "/ja/bingo/b1", board});
  assert.match(head, /<title>YOASOBI &lt;聴いた曲&gt; ビンゴ｜ビンゴオンライン<\/title>/);
  assert.match(head, /3×3のビンゴ。参加すると自分だけのカードが配られます。/);
  assert.match(head, /og:image" content="https:\/\/is1-ssl\.mzstatic\.com\/a\/400x400bb\.jpg"/);
  assert.match(head, /twitter:card" content="summary"/);
  assert.match(head, /hreflang="pt-BR" href="https:\/\/bingo-online\.web\.app\/pt-br\/bingo\/b1"/);
});

test("非公開・ブロック・削除中のビンゴは公開しない", () => {
  assert.equal(boardForPreview("b", {listed: false, title: "x"}), null);
  assert.equal(boardForPreview("b", {listed: true, deleting: true}), null);
  assert.equal(boardForPreview("b", undefined), null);
});

test("ホームは言語別の既定画像と説明を使い、noindexは見つからない時だけ", () => {
  const head = bingoMetaHead({origin, locale: "ko", path: "/ko/"});
  assert.match(head, /<title>빙고 온라인 \| 빙고를 만들고 다 함께 참여<\/title>/);
  assert.match(head, /og:image" content="https:\/\/bingo-online\.web\.app\/og-image-ko\.png"/);
  assert.match(head, /summary_large_image/);
  assert.doesNotMatch(head, /noindex/);
  assert.match(bingoMetaHead({origin, locale: "en", path: "/en/bingo/x", notFound: true}), /noindex/);
});

test("シェルの既定メタだけを差し替え、他のheadは残す", () => {
  const html = injectBingoMeta(shell, "<!--bingo-meta--><title>new</title><!--/bingo-meta-->");
  assert.match(html, /<title>new<\/title>/);
  assert.doesNotMatch(html, /generic/);
  assert.match(html, /theme-color/);
  assert.match(injectBingoMeta("<html><head></head></html>", "<title>x</title>"), /<title>x<\/title>\n<\/head>/);
});
