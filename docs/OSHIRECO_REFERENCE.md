# oshireco 参照調査

確認した実装は `core/responsive/app_breakpoints.dart` の600/900/1440px区分、`responsive_widgets.dart` の `LayoutBuilder` + `Wrap`、`widgets/content_frame.dart` の960px中央寄せ、`screens/app_shell.dart` のMaterial 3ナビゲーション、`widgets/section_header.dart`、`main.dart` の共通Themeです。

ティア表オンラインでは、中央寄せ、利用可能幅基準のGrid、Material 3 Theme、モバイルのBottomNavigation/PCのNavigationRail、Model/Repository/UI分離という考え方だけを単純化して実装します。コードの直接importはありません。

Supabase、認証、フォロー、タイムライン、プロフィール、推し、作品記録、推薦、実況、既存ブランドや文言、不要な依存は持ち込みません。
