# Firebase App Check・費用アラート設定

このプロジェクトのWebクライアントは、ビルド時に
`FIREBASE_APP_CHECK_WEB_SITE_KEY`を渡すとFirebase App Checkを初期化します。
Callable Functionsは`ENFORCE_APP_CHECK`パラメーターで一括強制できます。

## 安全な有効化手順

1. Firebase Consoleの「App Check」でWebアプリをreCAPTCHA v3へ登録する。
2. 発行された公開用サイトキーを指定してWebをビルド・配信する。

   ```powershell
   flutter build web --release --no-wasm-dry-run `
     --dart-define=FIREBASE_APP_CHECK_WEB_SITE_KEY=公開用サイトキー
   firebase deploy --only hosting --project tier-online
   ```

3. Firebase Consoleの「App Check > APIs」で、Authentication、Cloud
   Firestore、Cloud Storage、Cloud Functionsの正規リクエスト率を確認する。
4. 正規リクエストがほぼ「検証済み」になったら、Firebase Consoleで
   Authentication、Cloud Firestore、Cloud Storageを強制する。
5. `functions/.env.tier-online`へ次を設定してFunctionsを再デプロイする。

   ```dotenv
   ENFORCE_APP_CHECK=true
   ```

   ```powershell
   firebase deploy --only functions --project tier-online
   ```

ローカルビルドでサイトキーを渡さない場合はApp Checkを初期化しません。
強制後にローカルからFirebaseへ接続する場合は、Firebase Consoleへ登録した
App Checkデバッグトークンを使ってください。

`renderTopic`と`sitemap`は検索エンジンが認証なしで取得する公開HTTP関数のため、
App Check強制の対象外です。

## 予算アラート

Google Cloud Consoleの「Billing > Budgets & alerts」で、請求先アカウントと
プロジェクト`tier-online`を対象に月次予算を作成します。

- 予算額: 実際に支払える月額を指定する
- 通知しきい値: 50%、80%、100%
- 実績額と予測額の両方を通知対象にする
- 請求管理者にも通知が届くことを確認する

予算アラートは通知のみで、利用や請求を自動停止しません。このコードでは追加の
費用防止策として、Functions第2世代を各関数最大5インスタンス、最小0
インスタンスに制限しています。完全なハード上限が必要な場合は、予算Pub/Sub通知を
受けてサービスを停止する別の仕組みが必要ですが、障害を自動発生させるため導入時は
慎重な確認が必要です。
