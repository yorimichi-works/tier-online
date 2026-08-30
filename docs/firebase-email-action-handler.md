# Firebaseメール確認

現在はFirebase Authenticationの標準確認メールと標準Action URLを使用する。
メール送信はFlutterの`sendEmailVerification`から行い、表示中の言語を
`languageCode`へ設定する。対応言語は日本語、韓国語、繁體中文、
ポルトガル語（ブラジル）、英語。

独自確認ページ`https://tier-online.web.app/{locale}/auth/action`は実装済みだが、
Firebase側がテンプレートのAction URL更新を
`EMAIL_TEMPLATE_UPDATE_NOT_ALLOWED`で拒否しているため、現在は未使用。
Firebaseサポートによる制限解除後、Authentication → Templates →
Customize action URLから独自ページへ切り替える。
