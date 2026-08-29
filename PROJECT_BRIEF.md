# ティア表オンライン / Tier Table Online

## 中心思想

「みんなで決める、みんなのTier。」テーマ + 共通選択肢セット + 各ユーザーのTier配置を中心にした集合Tierサービス。人を追うSNSにはせず、フォロー、DM、タイムライン等は作らない。テーマ専用掲示板は「語る」と呼ぶ。

## 体験

ホーム/検索 → 詳細で「みんなのTier」 → 「自分も作る」 → 共通カードをSS/S/A/B/C/Dへ配置 → 「あなたのTier」と一致率を表示 → 共有/「語る」。PCはドラッグ＆ドロップ中心、スマホはドラッグとタップ指定の両方を提供する。Tier間移動と同一Tier内の並び替えに対応する。

## テーマ作成（最新仕様）

- 必須はタイトルと1件以上のカード。タグ、説明、カテゴリ、サムネイルは任意。
- カードは「画像のみ」「画像+名前」「名前のみ」の3形式。`TierItem.name` と `imageUrl` はそれぞれ任意で、どちらか一方が必要。
- 複数画像を一括選択すると正方形カードを自動生成する。名前入力は強制しない。
- カードをタップすると、その場のモーダル/BottomSheetで名前追加、画像変更、画像削除、カード削除ができる。
- 作成フローはタイトル → タグ → 複数画像追加 → 必要な名前だけ編集 → SS〜D配置 → 公開。写真を放り込んで、並べて、公開できる速度を最優先する。
- 作成者自身が最初の配置を完成して公開する。2人目以降は同じ画像カード/選択肢セットを利用し、追加しない。
- 画像UIには権利保有または利用許諾のある画像のみ使う旨を表示する。

## データ

- `TierTopic`: id, title, description?, tags, category?, creatorId, thumbnail?, createdAt
- `TierItem`: id, tierTopicId, imageUrl?, name?, sortIndex（画像か名前の一方が必須）
- `UserTierSubmission`: id, tierTopicId, anonymousId, createdAt
- `UserTierPlacement`: submissionId, itemId, rank, order
- 集合TierはS=5〜D=1の単純平均。将来、人数、評価分布、S率、分散を扱える構造にする。

## UI

ダークテーマ（背景 `#0D0D0F`、カード `#17171B`、サブカード `#202025`、紫/青紫アクセント）。TierはSS/S/A/B/C/Dの6段階。左ラベルとBadgeは半透明にせず、SS赤、Sピンク、Aオレンジ、B黄、C黄緑、D青の明るいソリッドカラーと黒文字で強く表示する。選択肢カードは正方形で画像をcover表示し、名前がある場合だけ小さなオーバーレイを表示する。390/430/768/1024/1440pxを意識したモバイルファーストとする。

ナビゲーションはホーム、探す、作る、マイTier、設定。ホームは検索、カテゴリ、人気/急上昇/新着。詳細は「みんなのTier」「語る」のタブ。タグChipから同一タグ検索へ遷移できるようにする。

## Phase 1 / 技術方針

Flutter Web中心、ダミーデータで操作できるプロトタイプ。最低10テーマ。認証、Firebase、Firestore、Cloud Storage、リアルタイム同期、通知、推薦、課金、管理画面は後回し。端末内保存を使う。

`models / repositories / services / screens / widgets / theme / utils` に分離し、UIはRepository経由で取得する。現在は `DummyTierRepository`、将来は `FirebaseTierRepository` に交換可能とする。過剰設計しない。

## oshireco参照

`oshireco` の600/900/1440pxブレークポイント、中央寄せContentFrame、LayoutBuilder+WrapのGrid、Material 3 Theme、NavigationBar、Model/Repository/UI分離を参考に、こちらへ単純化して実装する。直接importしない。SNS、推し、認証、Supabase/Firebase、ブランド、不要依存は持ち込まない。

## 完了条件

390pxで崩れずPCで中央表示。ナビ、カード→詳細、タグ検索、ドラッグ/タップ配置、並べ替え、個人/集合比較が動く。画像なし・名前なし画像カードの両方が成立。`flutter analyze` とWeb buildが成功する。今後の作業では最初に本ファイルを読む。
