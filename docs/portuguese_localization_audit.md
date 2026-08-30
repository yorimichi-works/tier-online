# ブラジルポルトガル語対応監査

## 対応方針

- localeコード: `pt-br`
- Flutter locale: `pt_BR`
- URL: `/pt-br/`
- `hreflang`: `pt-BR`
- OGP locale: `pt_BR`
- 既定地域: `BR`
- ロゴ: 現行の英語版ロゴを共用

## 対応範囲

- 固定UI文言、エラー、認証、投稿、コメント、通報、設定、法務画面
- 言語・地域の選択肢と端末言語判定
- ブラジル向け簡易テンプレート
- Firebase Hostingの言語別ルーティング
- Functionsの画像検索locale、認証メール、SEO HTML、sitemap
- 日本語UI上の言語名「ポルトガル語」を含む全言語名のローカライズ

## 運用上の区別

UI locale、Tierの原文言語 (`contentLanguage`)、対象地域 (`targetRegion`) は別概念として保持する。
ポルトガル語端末は `pt-br` を既定とし、対象地域はブラジル (`BR`) を既定とする。
