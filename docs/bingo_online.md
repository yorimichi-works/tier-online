# ビンゴオンライン（Bingo Online）

ビンゴを作って公開し、みんなが参加して、結果をコメントで公開できる参加型SNS。
tier表オンラインと同じFlutterプロジェクト・同じFirebaseプロジェクトに同居させ、
将来ひとつの参加型SNSへ統合しやすい構成にしている。

## 機能

- **作る**: タイトル・説明・タグ、カードの大きさ（3×3 / 4×4 / 5×5）、まん中FREE、
  参加者ごとのシャッフル、公開/非公開、内容の言語・対象地域。
  - マスは「テキスト」「画像」「画像＋テキスト」の3形式。1マス40文字まで、最大75マス。
  - テキスト1件追加、まとめ入力（1行1マス）、テンプレート（サンプル）から開始。
  - **画像アップロード**: 複数選択・ドラッグ＆ドロップで一括追加。端末側で圧縮してから
    アップロードする（`BingoImagePolicy`）: 中央を正方形に切り抜き、400pxのJPEG（品質78）。
    80KBを超える場合は品質を最低50まで段階的に下げ、それでも超えれば解像度を下げる。
    向き（EXIF Orientation）を画素に反映したうえで、カメラ情報・位置情報などのEXIFは削除する。
  - **Appleのジャケット画像**: iTunes Search API（アルバム/曲）で検索して複数選択。
    oshirecoの `MusicArtworkResolver` と同じ規則（Apple画像ホストのみ許可、HTTPS化、
    `400x400bb.jpg` へ変換。Apple側で縮小された画像を取得する）。画像はコピーせず
    mzstatic.comのURLを参照する。
  - マスが必要数より多い場合、参加者ごとに違うマスが入る（faabulの「シャッフル」相当）。
- **参加する**: 参加者専用のカードを配る。配置は `ボードID:ユーザーID` のFNV-1aシードで
  決まるため再現でき、カードは `bingoEntries/{uid}` に保存される。
- **チェック**: マスをタップ。行・列・斜めのBINGO判定、リーチ表示、BINGO時の演出。
- **コメント**: 「自分のビンゴ結果を公開する」をオンにすると、その時点のカードを
  コメントに添付する（サーバーが保存済みカードからコピーするので偽装できない）。
  結果は絵文字グリッド付きテキストでもコピーできる。
- **みんなの結果**: 参加者数、BINGO達成者数・達成率、よくチェックされたマスのランキング。
- **マイビンゴ**: 参加したビンゴ・作ったビンゴ。作成者は公開/非公開切り替えと削除が可能。
- **報告**: ボード・コメントを報告。5件で自動的に非公開化（コメントは非表示）。
- **いいね・リアクション**: ビンゴに「いいね」（人気順は 参加者 + いいね×2 + コメント）。
  コメントには 👏🎉😂❤️ のリアクションを1人1つ付けられ、付け替え・取り消しもできる。
- **ログイン**: tier-onlineと共通のアカウント（メール/パスワード、Google）。ゲストのまま
  新規登録するとuidを引き継ぐ（匿名ユーザーへのリンク）ので、作ったビンゴやカードはそのまま。
  既存アカウントへのログインは切り替え確認を出す。パスワード登録はメール確認後に投稿可能。
  設定画面からログアウト・アカウント削除（Tier/Bingoの全データを削除）。画像アップロードは
  Tierと同じく登録者のみ（Appleのジャケット画像はゲストも可）。
- **共有リンクのOGP**: `/{locale}/bingo/{id}` をX・LINE等に貼ると、ビンゴのタイトル・説明と
  最初の画像マス（なければ言語別の既定画像）がプレビューに出る。

## 多言語・地域（tier-online方式）

- UI言語は `AppLocale`（ja / ko / en / zh-tw / pt-br）。正本は
  `lib/domain/internationalization.dart` をそのまま共有。
- URLは `/{locale}/`、`/{locale}/create`、`/{locale}/my`、`/{locale}/settings`、
  `/{locale}/bingo/{bingoId}`。言語を切り替えるとアドレスバーの言語部分も更新する。
- 言語決定の優先順位は tier-online と同じ（明示選択 > URL > 保存値 > 端末）。
  端末保存キー（`preferredLocale` / `preferredLanguage` / `region` /
  `languageExplicitlySelected` / `anonymousId`）も共通。
- 固定UIは `lib/bingo/l10n/bingo_localizations.dart` のキー辞書（`t()` / `format()`）。
  統合時のキー衝突を避けるためTier辞書とは別ファイル。全言語でキー集合が一致することを
  テストしている。
- ボードは `contentLanguage` / `sourceLanguage` / `targetRegion` を持ち、UI言語とは独立。
- 起動前のHTML（`web_bingo/index.html`）は `web/index.html` と同じ読み取り専用ミラーで
  タイトル・説明・hreflangを言語別に出す。

## 構成

```
lib/main_bingo.dart                 エントリポイント
lib/bingo/
  bingo_app.dart                    MaterialApp・ルーティング
  domain/bingo_logic.dart           カード生成・BINGO判定・集計・入力検証（純粋関数）
  l10n/bingo_localizations.dart     UI辞書（5言語）
  models/bingo_models.dart          BingoBoard / BingoCell / BingoEntry / BingoComment
  repositories/                     Local（端末内）/ Firebase / サンプル
  services/                         BingoState、Apple画像検索、Firebase接続
  screens/ widgets/ theme/          画面・部品・白ベースのテーマ
functions/src/bingo.ts              サーバー側の検証・判定・集計（Dartと同じ規則）
web_bingo/                          ビンゴ用 index.html / manifest.json
```

Firebaseに接続できない場合も端末内保存で動作する（tier-onlineと同じ方針）。
サンプルビンゴは常に端末内で遊べる。

## ログイン

認証の処理は `lib/services/account_auth_service.dart`（`AccountAuthService`）にまとめ、
ビンゴはこれを使う。Tierの `AppState` と同じ手順（匿名ユーザーへのリンク、Googleのアカウント
競合時のパスワード確認による統合、モバイルWebのリダイレクト方式、ログアウト後は新しいゲスト、
`deleteUserAccount` による削除）で、型（`AuthResult` など）はTierと共有している。
Tierの `AppState` もいずれこのサービスへ委譲できる。

## 共有リンクのOGP

`renderBingo`（`functions/src/bingoSeo.ts`）がHostingのリライト先になり、デプロイ済みの
`index.html` を取得して `<!--bingo-meta-->` ブロックだけを言語別・ビンゴ別のメタデータに
差し替える（Tierの `seo.ts` のようにHTMLを二重管理しない）。非公開・ブロック・存在しない
ビンゴは既定メタ＋`noindex`で404。`/sitemap.xml` は `bingoSitemap`。
サイトのURLはFunctionsのパラメータ `BINGO_SITE_ORIGIN`（既定 `https://bingo-online.web.app`）。

既定のOG画像（`web_bingo/og-image-{locale}.png`）とアイコンは `node playwright/bingo-assets.mjs`
で再生成できる。

## Firestore

| パス | 書き込み |
| --- | --- |
| `bingos/{bingoId}` | `publishBingo`（モデレーション・レート制限）。作成者は `isPublic`/`listed` のみ更新可 |
| `bingos/{id}/bingoEntries/{uid}` | 本人のみ。形式をRulesで検証 |
| `bingos/{id}/comments/{commentId}` | `postBingoComment`。削除は投稿者またはボード作成者 |
| `bingos/{id}/reports/{type}_{targetId}_{uid}` | 本人が1回だけ作成 |
| `bingos/{id}/likes/{uid}` | 本人のみ作成・削除。`aggregateBingoLikes` が `likeCount` を更新 |
| `bingos/{id}/comments/{cid}/reactions/{uid}` | 本人のみ。`countBingoCommentReactions` が `reactionCounts` を更新 |

- `listed` = 公開かつ非ブロック。一覧クエリは `listed == true` + `createdAt desc`。
- 集計（参加者数・BINGO数・マス別チェック数）は `aggregateBingoEntries` トリガー、
  コメント数は `countBingoComments`、報告は `onBingoReportCreated` が更新する。
- NGワード・個人情報判定・レート制限はTierと共通（`bingoPublish` / `bingoComment` を追加）。
- アカウント削除（`deleteUserAccount`）でビンゴのデータも削除する。
- アップロード画像は `users/{uid}/bingos/{bingoId}/cells/{n}.jpg`。Storage Rulesで
  登録ユーザー（匿名以外）・`image/jpeg`・200KB未満に制限し、圧縮されていない画像は受け付けない。

## 開発

```sh
flutter run -d chrome -t lib/main_bingo.dart
flutter test test/bingo_logic_test.dart test/bingo_widget_test.dart
cd functions && npm test
```

Rulesのテスト（Firebase Emulator、Javaが必要）:

```sh
cd scripts/bingo_rules_test
npm install
npm test
```

## デプロイ

Hostingはtier-onlineとは別サイト（例: `bingo-online`）にする。初回のみサイトを作成する。

HostingのリライトがFunctions（`renderBingo` / `bingoSitemap`）を参照するので、
Rules・インデックス・Functionsを先にデプロイする。サイトURLが既定と違う場合は
`functions/.env.tier-online` に `BINGO_SITE_ORIGIN=https://...` を書く。

```sh
firebase hosting:sites:create bingo-online --project tier-online
firebase deploy --only firestore:rules,firestore:indexes,storage,functions --project tier-online
./scripts/build_bingo_web.sh
firebase deploy --config firebase.bingo.json --only hosting --project tier-online
```

Googleログインを使うには、Firebase Authenticationの「承認済みドメイン」に
ビンゴのドメイン（例: `bingo-online.web.app`）を追加する。

## tier-onlineとの統合に向けて

- `lib/bingo/` はTierのコードに依存しない（共有するのは国際化ドメイン、フォント、
  `FirebaseBootstrap`、`ImageProcessingService`、ブレークポイントのみ）。
- `BingoShell` のタブ画面をTierの `AppShell` に「ビンゴ」として差し込めば統合できる。
  ルートは `/{locale}/bingo/...` なのでTierの `/{locale}/tier/...` と衝突しない。
- `users/{uid}` を共有しているので、Tier側でGoogle/メール登録したアカウントのまま使える。
