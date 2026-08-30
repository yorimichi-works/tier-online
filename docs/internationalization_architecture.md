# 国際展開を支えるコード設計

この文書は、国際展開の設計思想を既存コードへ適用するときの境界と互換性を定義する。
現在の対応言語は日本語、韓国語、英語、繁体字中国語、ブラジルポルトガル語で、
将来の言語追加時も同じ境界を維持する。

## 分離する概念

次の値は似ていても用途が異なるため、相互に推測して上書きしない。

- `AppLocale`: アプリの固定UIを表示する言語。
- `contentLanguage`: Tier表や投稿の原文言語。UI言語と一致するとは限らない。
- `region` / `targetRegion`: ユーザーまたはTierが主に対象とする地域。
- `RankingScope`: 集合ランキングを世界・地域・言語のどの単位で見るか。

Dart側の正本は `lib/domain/internationalization.dart`、Functions側の正本は
`functions/src/internationalization.ts` とする。ルーティング、Firestore、SEO、外部API用の
言語コードを画面やサービスへ個別に直書きしない。Flutter起動前に実行される
`web/index.html` だけはDartを参照できないため、canonical codeとhreflangの小さな読み取り専用
ミラーを持つ。この一覧は言語追加テスト時に両方の正本と一致することを確認する。

## 現在のデータとの互換性

現段階ではFirestoreのコレクション名と既存フィールドを変更しない。

- 公開Tierは引き続き `topics` に保存する。
- ユーザー配置は `submissions` に保存し、今後の集計に備えて `contentLanguage` と
  `region` を保持する。古い端末データに値がない場合は `ja` / `JP` として読む。
- 地域別集計は引き続き `tierRegionStats/{tierId}_{region}` を利用する。
- `RankingScope.storageKey` は将来、世界・地域・言語別の共通集計コレクションを導入する際の
  安定した識別子として使えるが、今回データ移行は行わない。

## Presetと公開Tier

将来は再利用可能な素材セットをPreset、ユーザーが公開して参加を受け付けるものをTierとして
別エンティティにする。現在の `sourceTemplateId` は移行までの橋渡しとして維持し、Preset本体を
公開Tierの参加数・コメント・評価へ混在させない。正式なPresetコレクション追加は、既存データの
移行計画とRulesを同時に用意できる段階で行う。

## 翻訳とローカライズ

固定UIはローカライズ辞書で管理する。ユーザー生成テキストは原文を保持し、閲覧時の同期翻訳は
前提にしない。将来の翻訳はモデレーション後の非同期処理とし、翻訳結果を保存して再利用する。
詳細は [future_multilingual_translation.md](future_multilingual_translation.md) を参照する。

## 言語・地域を追加するとき

1. DartとFunctionsの言語プロファイルへコードを追加する。
2. 全UI翻訳キー、ルート、SEOメタデータ、Firebase Authの言語コードを追加する。
3. 必要な地域を `SupportedRegion` とFunctionsの地域コード一覧へ追加する。
4. 言語と地域の既定値を決めるが、両者を同一概念にはしない。
5. 正規化、URL、SEO、端末判定、旧データ読み込みのテストを追加する。

## 今回意図的に行わないこと

- Firestoreスキーマ・コレクション・Rulesの変更
- Presetコレクションや翻訳Functionの追加
- 地域ごとのFirebaseプロジェクト分離
- 既存UIや推薦ロジックの挙動変更
