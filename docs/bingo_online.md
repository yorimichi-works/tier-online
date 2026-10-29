# ビンゴオンライン（Bingo Online）

ビンゴを作って公開し、みんなが参加して、結果をコメントで公開できる参加型SNS。
tier表オンラインと同じFlutterプロジェクト・同じFirebaseプロジェクトに同居させ、
将来ひとつの参加型SNSへ統合しやすい構成にしている。

## 機能

- **作る**: タイトル・説明・タグ、カードの大きさ（3×3 / 4×4 / 5×5）、まん中FREE、
  参加者ごとのシャッフル、公開/非公開、内容の言語・対象地域。
  - マスは「テキスト」「画像」「画像＋テキスト」の3形式。1マス40文字まで、最大75マス。
  - テキスト1件追加、まとめ入力（1行1マス）、テンプレート（サンプル）から開始。
  - **画像アップロード**: 複数選択・ドラッグ＆ドロップで一括追加。600px正方形JPEGへ縮小。
  - **Appleのジャケット画像**: iTunes Search API（アルバム/曲）で検索して複数選択。
    oshirecoの `MusicArtworkResolver` と同じ規則（Apple画像ホストのみ許可、HTTPS化、
    `600x600bb.jpg` へ変換）。画像はコピーせずmzstatic.comのURLを参照する。
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

## Firestore

| パス | 書き込み |
| --- | --- |
| `bingos/{bingoId}` | `publishBingo`（モデレーション・レート制限）。作成者は `isPublic`/`listed` のみ更新可 |
| `bingos/{id}/bingoEntries/{uid}` | 本人のみ。形式をRulesで検証 |
| `bingos/{id}/comments/{commentId}` | `postBingoComment`。削除は投稿者またはボード作成者 |
| `bingos/{id}/reports/{type}_{targetId}_{uid}` | 本人が1回だけ作成 |

- `listed` = 公開かつ非ブロック。一覧クエリは `listed == true` + `createdAt desc`。
- 集計（参加者数・BINGO数・マス別チェック数）は `aggregateBingoEntries` トリガー、
  コメント数は `countBingoComments`、報告は `onBingoReportCreated` が更新する。
- NGワード・個人情報判定・レート制限はTierと共通（`bingoPublish` / `bingoComment` を追加）。
- アカウント削除（`deleteUserAccount`）でビンゴのデータも削除する。
- アップロード画像は `users/{uid}/bingos/{bingoId}/cells/{n}.jpg`。ビンゴは登録導線が
  まだないため匿名ユーザーにも1MB未満のアップロードを許可している（Tierは登録必須）。

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

```sh
firebase hosting:sites:create bingo-online --project tier-online
./scripts/build_bingo_web.sh
firebase deploy --config firebase.bingo.json --only hosting --project tier-online
firebase deploy --only firestore:rules,firestore:indexes,storage,functions --project tier-online
```

## tier-onlineとの統合に向けて

- `lib/bingo/` はTierのコードに依存しない（共有するのは国際化ドメイン、フォント、
  `FirebaseBootstrap`、`ImageProcessingService`、ブレークポイントのみ）。
- `BingoShell` のタブ画面をTierの `AppShell` に「ビンゴ」として差し込めば統合できる。
  ルートは `/{locale}/bingo/...` なのでTierの `/{locale}/tier/...` と衝突しない。
- `users/{uid}` を共有しているので、Tier側でGoogle/メール登録したアカウントのまま使える。
