# 投稿の認可修正案（2026-10-22、本番未適用）

基点: `8cb05ecacda9d4572e4cd164687f6d7729ef5d68`。
ブランチ: `fix/tier-authorization-20261022`。
依存更新ブランチおよび元の未コミット作業とは独立している。

追補で削除フロー接続・互換ゲート・未送信返信・複数端末の評価を実装した。
現行の切替手順と保持仕様は [投稿 v2 の手順書](talk_rollout_v2.md) を参照。

## 変更と互換方針

- 投稿の新規作成では `authorUserId == request.auth.uid` を必須にする。
  作者表示名は従来どおり自由な表示文字列であり、本人確認の根拠にしない。
- 本文更新は保存済み `authorUserId` の本人だけに許可する。
  変更可能フィールドを本文と互換バージョン情報に限定し、作者情報、属性、返信、評価数、未知の追加フィールドを保護する。
- 新しい返信は `topics/{topicId}/talks/{postId}/replies/{replyId}` に1件ずつ保存する。
  返信自身の作者 UID を必須にし、本文更新も返信作者だけに許可する。
  ネストは変更不可の `parentReplyId` で表す。親の本文や返信配列を書き戻さない。
- 評価は `.../talks/{postId}/reactions/{uid}` の `votes` マップに保存する。
  `root` または返信 ID ごとに `up` / `down` の1つだけを持ち、UID 本人だけが変更・削除できる。
  更新はトランザクションで本人の既存の別対象への評価も保持する。
  生の親投稿・返信の `upvotes` / `downvotes` は書き換えず、読み取り時に加算する。
- 投稿作成・返信・評価のクライアント処理を分割し、全投稿の `batch.set` を廃止した。
  書き込み後はクラウドの表示を再取得し、同じ投稿 ID の端末キャッシュより優先する。

**旧データは移行・補完・消去しない。** 作者 UID が欠落、null、空の投稿の本文や作者情報は
クライアントから編集できない。表示名・トピック所有者から作者を推定しない。
既存のネストした `replies` 配列、`replyAuthorIds`、独自フィールド、評価数はそのまま保持する。
新しい返信・評価は、この旧投稿にも別文書として追加できる。
埋め込み返信を同じ ID の新文書で上書きしない。親リンクが欠落・循環しても新返信は一度だけ表示する。

過去の評価には UID 別の内訳がないため、従来の数を履歴の基準値として保持する。
その基準値の減算・ユーザー別割当は行わない。新方式の評価だけを UID 単位で切り替え・解除する。
既存の作者 UID の過去の真正性も、この修正だけでは遡って証明できない。

## 許可・拒否の要点

| 状態 | 閲覧 | 自分の投稿作成・本文編集 | 他人の本文・作者情報変更 | 自分の返信・評価 |
| --- | --- | --- | --- | --- |
| 公開・確認済み作者 | 許可 | 許可（本文のみ） | 拒否 | 許可 |
| 公開・他人（Google） | 許可 | 自分の投稿のみ許可 | 拒否 | 許可 |
| 公開・Firebase 匿名認証 | 許可 | 自分の UID のみ許可 | 拒否 | 許可 |
| 公開・未ログイン | 許可 | 拒否 | 拒否 | 拒否 |
| 公開・未確認 password | 許可 | 拒否 | 拒否 | 拒否 |
| 非公開・トピック所有者 | 許可 | 自分の UID のみ許可 | 拒否 | 許可 |
| 非公開・その他（元の投稿作者も含む） | 拒否 | 拒否 | 拒否 | 拒否 |
| 作者 UID のない旧投稿 | 従来の公開条件 | 本文編集・作者 UID 補完を全員拒否 | 拒否 | 閲覧可能かつ投稿条件を満たす本人のみ許可 |

匿名認証は従来どおり投稿可能。匿名と未ログインは区別する。
この修正は匿名アカウント量産による評価操作や表示名の重複を防ぐものではない。
投稿・返信のクライアント直接削除は禁止し、既存のアカウント削除フローでは子文書まで削除する。

## ローカル検証

以下は初回コミット `a22cc3d` の検証記録。追補の最新結果（Firestore/削除 75 件、
Functions 33 件、対象 Flutter 38 件）と基点でも再現する画面テストの失敗は、
[v2 手順書の検証結果](talk_rollout_v2.md#検証結果) に記載した。

Node 24.19.0 / Java 21 / Firestore emulator 1.22.0 を使用。
追加 npm 依存なし。`pubspec.lock` のまま `pub get --offline --enforce-lockfile` 成功。

```powershell
$env:JAVA_BIN = '<Java 21 の java.exe>'
$env:FIRESTORE_EMULATOR_JAR = '<ローカルの cloud-firestore-emulator-v1.22.0.jar>'
node scripts/test-talk-authorization.mjs

flutter test --no-pub test/talk_activity_test.dart test/persistence_and_aggregation_test.dart
dart analyze lib/domain/talk_activity.dart lib/repositories/cloud_tier_repository.dart lib/repositories/firebase_tier_repository.dart lib/services/app_state.dart test/talk_activity_test.dart test/persistence_and_aggregation_test.dart
```

- Firestore 実ルール: **66 テスト成功**。上表の組合せ、作者 UID の追加・差替・削除、
  本文改変、他人の返信改変、旧データ、評価の切替・解除、不正な初期評価/返信の持込、
  入力型、不正な全親文書 batch の拒否と原子的ロールバックを確認。
- Flutter: **27 テスト成功**。旧返信の表示・履歴保持・循環対応と、既存の永続化・集計テストを含む。
- 変更対象の Dart 静的解析はエラーなし。`git diff --check` 成功。

指定 SHA の旧ルールでも「他人の本文変更を拒否する」1件を実行したところ、
HTTP 200 で不正変更が成功し、期待した 403 にならずテストが失敗した。
同じ拒否テストは修正後の全件実行では成功した。

ランナーは `127.0.0.1:8788` に独立した使い捨てエミュレーターを起動する。
固定の `demo-tier-authorization` のみを使用し、既存 DB の clear/import/export、
Firebase login、デプロイを行わない。モック JWT はエミュレーター専用で本番の認証情報ではない。
Windows の制限実行で一度起動がタイムアウトしたが、通常のローカル実行で最終テストは完走した。

## 追補で完了した統合作業と本番前の確認

本タスクはコードとローカル検証に限定した。本番操作は実施していない。

1. **アカウント削除との接続済み。** `deleteTalkData` に新返信・評価の UID 別削除と
   作者の投稿の recursiveDelete を接続した。ローカルの実 Firestore fixture と Storage スタブで検証する。
   関連する collection-group index 定義も追加したが、本番適用はしていない。
2. **旧クライアントとの切替を具体化。** policy 未作成/停止中は書き込みを拒否し、
   protocol 2・build 2 以上の条件と作者認可を適用する。
   読み取りとデータ保持を維持した段階的切替・停止手順は [手順書](talk_rollout_v2.md) に記載した。
3. **規模と評価情報。** 表示時に投稿ごとの返信・評価文書を取得するため読み取りが増える。
   閲覧可能者は評価文書の UID と選択も読める。大規模な投稿でのサーバー集計や、投票者情報の
   非公開仕様が必要かは、本番前に別途決める。新サーバー権限は作成していない。

## Storage の調査と本人判断が必要な点

`storage.rules` は基点のままで、画像パス `users/{uid}/topics/{topicId}/items/{fileName}` に
`read: true` がある。トピックの Firestore 非公開状態とは連動していない。

- `FirebaseTierRepository.saveTopic` はアップロード後に `getDownloadURL()` を取得し、
  `imageUrl` として Firestore に保存する。
- `lib/widgets/tier_widgets.dart` や管理画面は `Image.network` で URL を直接表示する。
- `functions/src/index.ts` は、公開かつ `shareUploadedImages == true` の名前付き画像を
  `sharedItemImages` 用にコピーし、別の download token と長期 public cacheControl を設定する。
- `functions/src/seo.ts` も画像 URL を共有ページに使用する。

本人に必要な判断:

1. 非公開 Tier の画像も「作者のみ」にするか、URL を知る人の閲覧を認めるか。
   管理者・共有相手の閲覧範囲も決める必要がある。
2. 一度明示的に共有画像へ提供したコピーは、元の Tier を非公開にした後も再利用可能にするか。
3. 非公開化を既発行 URL にも適用するなら、既存 URL・トークン・コピー・キャッシュの扱いと
   クライアント移行を設計する必要がある。ルール変更だけで URL 利用まで保護したとは扱わない。

公式資料も [URL の直接利用](https://firebase.google.com/docs/storage/web/download-files) と
[Flutter の SDK 読み取り](https://firebase.google.com/docs/storage/flutter/download-files) を分けている。
今回は Storage ルール、公開権限、トークン、既存画像を変更していない。

本番ルール適用、main 統合、本番デプロイ、権限変更、トークン失効、ストア提出は行っていない。
