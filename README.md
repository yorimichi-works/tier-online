# ティア表オンライン

「みんなで決める、みんなのTier。」をコンセプトにした Flutter Web のMVPです。

## 多言語・地域対応

対応言語は日本語 (`ja`)、韓国語 (`ko`)、英語 (`en`)、繁体字中国語 (`zh-tw`)、ブラジルポルトガル語 (`pt-br`) です。Web URLは
`/{locale}/` を先頭に持ち、Tier詳細は `/{locale}/tier/{tierId}` で直接開けます。
表示言語 (`preferredLocale`) と利用地域 (`region`) は独立した設定として端末と
Firestoreの `users/{uid}` に保存されます。

言語・原文言語・地域・集計範囲を分離するコード上の方針は
[`docs/internationalization_architecture.md`](docs/internationalization_architecture.md)を参照してください。

Tierには `contentLanguage`、`targetRegion`、`categoryId` を保存します。地域は
Firestoreパスへ埋め込まず、共通の `topics` コレクションを利用します。集合結果の
地域別集計は `tierRegionStats/{tierId}_{region}` に保存されます。

既存データの移行は、Firebase Admin SDKの認証情報を設定したうえでFunctions
ディレクトリから次を実行します。最初のコマンドは件数確認のみで、書き込みません。

```powershell
npm run migrate:localization
npm run migrate:localization -- --apply
```

既存Tierには `contentLanguage=ja`、`targetRegion=JP`、既存ユーザーには
`preferredLocale=ja`、`region=JP` が欠損時のみ追加されます。

## 起動

```sh
flutter pub get
flutter run -d chrome
```

Firebase設定なしでも起動でき、作成テーマ・評価・投稿を端末内へ保存します。

## Firebase Hosting

HostingはFirebaseプロジェクト `tier-online` のデフォルトサイトへ接続済みです。
公開先は `https://tier-online.web.app` です。

```sh
flutter build web --release --no-wasm-dry-run
firebase deploy --only hosting --project tier-online --dry-run
firebase deploy --only hosting --project tier-online
```

現段階のHostingは全URLをFlutter Webの `index.html` へ返します。これにより
`/{locale}/` と `/{locale}/tier/{tierId}` の直接アクセスにも対応します。
Firestore、Authentication、Cloud FunctionsのデプロイはHosting手順に含めません。

## Firebaseを使う

Firebase Authenticationで匿名認証を有効にし、Firestore DatabaseとStorageを作成してください。
Webアプリの設定値はソースへ書き込まず、起動時に渡します。

```sh
flutter run -d chrome \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=FIREBASE_AUTH_DOMAIN=... \
  --dart-define=FIREBASE_STORAGE_BUCKET=... \
  --dart-define=FIREBASE_APP_CHECK_WEB_SITE_KEY=...
```

設定済みの場合は匿名認証し、テーマ、画像、評価、集合Tier、語る投稿・返信をクラウド同期します。通信エラー時も端末内への保存は継続します。

集合Tierは `topics/{topicId}/submissions/{userId}` の変更をCloud Functions第2世代が検知し、サーバー側で参加者数、平均Tier、ランク分布、意見の分散を再計算します。クライアントから集計結果を直接変更することはFirestore Rulesで禁止しています。

```sh
cd functions
npm install
npm test
cd ..
firebase deploy --only firestore:rules,storage,functions
```

Cloud FunctionsやStorageの利用には、Firebaseプロジェクト側で請求先設定が必要になる場合があります。
App Checkの段階的な有効化と予算アラートの設定手順は
[`docs/firebase-app-check-and-budget.md`](docs/firebase-app-check-and-budget.md)を参照してください。

### Google画像検索を使う

Programmable Search Engineを作成して画像検索を有効にし、Custom Search JSON APIのAPIキーと検索エンジンIDをCloud FunctionsのSecret Managerへ登録します。APIキーはFlutter Webへ埋め込みません。

```sh
firebase functions:secrets:set GOOGLE_SEARCH_API_KEY
firebase functions:secrets:set GOOGLE_SEARCH_ENGINE_ID
firebase deploy --only functions:searchTierItemImages
```

「名前でカードを追加」の直後に、各名前の検索結果の先頭画像を一括設定できます。検索画像の権利・利用条件は、公開前に利用者が確認する必要があります。

## 構成

- `models/`: Tierテーマ・項目・評価
- `repositories/`: ローカル表示用データとFirebaseデータアクセス
- `services/`: アプリ状態、ローカル保存、集合Tier集計、画像処理
- `screens/`: ホーム、探す、作成、マイTier、評価、結果
- `widgets/`: 共通Scaffold、カード、Tier表示
- `theme/`: ダークテーマ
