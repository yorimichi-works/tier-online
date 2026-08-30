# Tier表オンライン UI自動テスト結果

## テスト環境

- アプリ: Flutter Web(`flutter build web --debug -o build/web-debug`)
  - overflowバナー・assertionメッセージはdebugモードでのみ描画されるため、
    異常検出フェーズはdebugビルドに対して実施した。
  - 最終確認は本番相当の`flutter build web --release`ビルドに対して実施(下記16節参照)。
- 配信: `playwright/spa-server.mjs`(自作の最小SPA静的サーバー、クライアントルーティング
  へのフォールバック対応)。既存のFirebase Hosting設定・本番環境には一切触れていない。
- テストランナー: `@playwright/test`(`playwright/`配下に新規導入。既存のPlaywright環境は
  プロジェクトになかったため新規セットアップ)。
- データ: `DummyTierRepository`のローカルseedデータ(`yokai`等)＋本番Firestoreの
  公開Tier表(読み取りのみ、書き込み・削除は一切行っていない)。

## 確認画面

`lib/main.dart`の`onGenerateRoute`から実際に到達可能な画面のみを対象にした。

| 画面 | パス |
|---|---|
| ホーム | `/ja/` (`/ko/`, `/en/`も確認) |
| 探す(検索) | `/ja/search` |
| 作る(Tier表作成) | `/ja/create` |
| マイTier | `/ja/user` |
| 設定 | `/ja/settings` |
| Tier表詳細(+「語る」欄までスクロール) | `/ja/tier/yokai` |

存在しない画面(プロフィール専用ページ、共有専用ページ等)は新規実装せず対象外とした。

## viewport

| 名称 | サイズ |
|---|---|
| desktop | 1440×1000 |
| laptop | 1280×800 |
| tablet | 768×1024 |
| mobile | 390×844 |
| mobile-small | 360×800 |

## 発見した問題

### 1. `create`画面がローディング中のままスクリーンショットされる(テストスクリプト側の問題)
- 初回巡回(4ワーカー並列)で、desktop viewportの`create`画面のみ読み込み中の
  スプラッシュ("tier表オンライン"のプログレスバー)のまま撮影されていた。
- 原因調査の結果、Flutter Webアプリ自体の不具合ではなく、固定`waitForTimeout(6000)`が
  並列実行時のCPU競合下では不十分だったテストスクリプトの問題と判明。
- 修正: `web/index.html`が持つ`#app-loading[hidden]`属性(Flutterの初回描画完了で
  自動的に付与される)を確実な待機シグナルとして使うよう`crawl.spec.ts`を修正し、
  ワーカー数も4→2に削減。再実行で全viewportにて正常に描画されることを確認。

## 修正した問題

- 上記1件(テスト側の待機ロジック)。アプリ本体(`lib/`配下)のコード変更は今回発生していない
  ―― 巡回の結果、overflow・RenderFlexエラー・JS例外等のアプリ側不具合は検出されなかった。

## 未解決問題

なし(`FIXME_UI_AUTOMATION`で記録すべき事項は今回発生していない)。

## console error

- 40テスト全てで`RenderFlex` / `overflowed` / `Failed assertion` / `Exception` /
  `NaN` / `Infinity` 等のパターンに一致する疑わしいconsoleエラー・pageerrorは
  検出されなかった(`crawl.spec.ts`内のassertionが全件パス)。
- Firebase/Analytics/広告等のネットワークエラーはUIバグと区別するため
  `ignoredPatterns`で除外している(今回のローカル実行では大きな影響なし)。

## 目視確認メモ

- ホーム/探す/作る/マイTier/設定/Tier表詳細を desktop・tablet・mobile・mobile-small の
  各幅で目視確認。カードの折り返し、サイドバー広告枠、ボトムナビゲーション、
  Tier行(SS/S/A/B/C/D)のラベル幅・カード配置に崩れは見当たらなかった。
- `page.screenshot({ fullPage: true })`はFlutter Web(CanvasKit)ではDOM上の
  スクロール高さがビューポート固定のため、実質「その時点でのビューポート内容」の
  撮影になる。Tier表詳細の「語る」欄まで確認するため、撮影前に`mouse.wheel`で
  明示的にスクロールしている。

## 最終確認(release build)

修正後、指示書16節に従い以下を実行した。

```bash
flutter analyze   # No issues found!
flutter test      # 36 tests passed
flutter build web --release
```

その後、`playwright/playwright.release.config.ts`で同じ巡回テスト一式を
本番相当のreleaseビルド(`build/web`)に対して再実行し、**40件全て成功**
(疑わしいconsole/pageerrorなし)。スクリーンショットは
`artifacts/screenshots-release/`に保存し、debugビルド時の
`artifacts/screenshots/`と見比べられるようにした。新たなUI崩れは
発生していない。

## 今後確認した方がいい箇所

- **ドラッグ&ドロップ**: 今回はPlaywrightからの安定した自動操作が難しく
  (Flutter CanvasKitはDOM上に実要素を持たないため、標準的なdrag-and-drop APIが
  そのまま使えない)、自動テスト化を見送った。将来的にはFlutterの
  `flutter_driver`/integration_testパッケージ、またはポインターイベントを
  座標ベースで模擬する専用ヘルパーの導入を検討すると良い。
- **モーダル/ダイアログ/アカウントシートの深い操作**: 座標クリックはviewportごとに
  位置が変わるため、今回は主要画面への到達(URL遷移)のみを全viewportで巡回し、
  モーダルを開く操作は行っていない。継続的に確認するなら、viewport非依存な
  セマンティクスベースの操作(Flutter側でSemanticsを有効化する等)を検討する価値がある。
- **本番Hosting環境そのもの**への定期的なPlaywright巡回(現状はローカルbuildのみ)。
