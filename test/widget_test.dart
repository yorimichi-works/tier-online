import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tier_table_online/main.dart';
import 'package:tier_table_online/l10n/app_localizations.dart';
import 'package:tier_table_online/models/tier_models.dart';
import 'package:tier_table_online/repositories/cloud_tier_repository.dart';
import 'package:tier_table_online/repositories/dummy_tier_repository.dart';
import 'package:tier_table_online/repositories/starter_tier_repository.dart';
import 'package:tier_table_online/screens/create_screen.dart';
import 'package:tier_table_online/screens/app_scaffold.dart';
import 'package:tier_table_online/screens/email_action_screen.dart';
import 'package:tier_table_online/screens/tier_builder_screen.dart';
import 'package:tier_table_online/screens/tier_result_screen.dart';
import 'package:tier_table_online/screens/tier_publish_preview_screen.dart';
import 'package:tier_table_online/screens/topic_detail_screen.dart';
import 'package:tier_table_online/services/app_state.dart';
import 'package:tier_table_online/theme/app_theme.dart';
import 'package:tier_table_online/widgets/common_widgets.dart';
import 'package:tier_table_online/widgets/tier_widgets.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('ダークモードの通知は明るい文字で表示する', (tester) async {
    final theme = buildDarkAppTheme();
    expect(theme.snackBarTheme.backgroundColor, AppColors.elevated);
    expect(theme.snackBarTheme.contentTextStyle?.color, Colors.white);
    expect(theme.colorScheme.onErrorContainer, const Color(0xFFFFE8EC));
  });

  testWidgets('ゲストのアカウントメニューはログイン後すぐ登録済み表示になる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const _AuthMenuHarness());

    await tester.tap(find.byKey(const ValueKey('account-menu-button')));
    await tester.pumpAndSettle();
    expect(find.text('ゲストとして利用中です'), findsOneWidget);
    expect(find.text('ログイン / 新規登録'), findsOneWidget);
    expect(find.text('ログアウト'), findsNothing);

    await tester.tap(find.text('ログイン / 新規登録'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-menu-button')));
    await tester.pumpAndSettle();
    expect(find.text('ゲストとして利用中です'), findsNothing);
    expect(find.text('マイTier'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('ログアウト'), findsOneWidget);
  });

  testWidgets('登録済みメニューは各画面幅でゲスト表示せずログアウト後すぐ切り替わる', (tester) async {
    for (final size in const [
      Size(390, 844),
      Size(430, 932),
      Size(1440, 1000),
    ]) {
      await tester.binding.setSurfaceSize(size);
      var myTierOpened = false;
      await tester.pumpWidget(
        _AuthMenuHarness(
          key: ValueKey(size),
          initiallyRegistered: true,
          onMyTier: () => myTierOpened = true,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('account-menu-button')));
      await tester.pumpAndSettle();
      expect(find.text('ゲストとして利用中です'), findsNothing);
      expect(find.text('マイTier'), findsOneWidget);
      expect(find.text('設定'), findsOneWidget);
      expect(find.text('ログアウト'), findsOneWidget);

      await tester.tap(find.text('マイTier'));
      await tester.pumpAndSettle();
      expect(myTierOpened, isTrue);

      await tester.tap(find.byKey(const ValueKey('account-menu-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ログアウト'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-menu-button')));
      await tester.pumpAndSettle();
      expect(find.text('ゲストとして利用中です'), findsOneWidget);
      expect(find.text('ログイン / 新規登録'), findsOneWidget);
      expect(find.text('ログアウト'), findsNothing);

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('独自メール確認ページは確認完了後に元のブラウザへ戻る案内を表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final appState = AppState(DummyTierRepository());
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildDarkAppTheme(),
        home: EmailActionScreen(
          appState: appState,
          actionUri: Uri.parse(
            'https://tier-online.web.app/ja/auth/action'
            '?mode=verifyEmail&oobCode=test-code',
          ),
          applyActionCode: (code) async => code == 'test-code',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('メールアドレスの確認が完了しました'), findsOneWidget);
    expect(find.text('元のブラウザに戻って「確認しました」を押してください。'), findsOneWidget);
    expect(find.text('閉じる'), findsOneWidget);
    expect(find.byType(BrandMark), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('期限切れのメール確認リンクは再送案内を表示する', (tester) async {
    final appState = AppState(DummyTierRepository());
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: EmailActionScreen(
          appState: appState,
          actionUri: Uri.parse(
            'https://tier-online.web.app/ja/auth/action'
            '?mode=verifyEmail&oobCode=expired-code',
          ),
          applyActionCode: (_) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('この確認リンクは使用できません'), findsOneWidget);
    expect(find.textContaining('確認メールを再送してください'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('390pxでホームからTier作成画面まで進める', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TierTableOnlineApp(
        appState: AppState(DummyTierRepository(), trustLocalSharedRoutes: true),
      ),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('最強の妖怪Tier'), findsWidgets);
    expect(find.text('すべて'), findsOneWidget);
    expect(find.text('キャラクター'), findsOneWidget);
    expect(find.text('ゲーム'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final firstTopic = find.text('最強の妖怪Tier').last;
    await tester.ensureVisible(firstTopic);
    await tester.pumpAndSettle();
    await tester.tap(firstTopic);
    await tester.pumpAndSettle();
    expect(find.text('みんなのTier'), findsWidgets);
    expect(find.text('自分も作る'), findsOneWidget);
    expect(find.byType(SegmentedButton<int>), findsNothing);
    expect(
      tester.getTopLeft(find.text('みんなのTier').first).dy,
      lessThan(tester.getTopLeft(find.text('自分も作る')).dy),
    );
    expect(
      tester.getTopLeft(find.text('自分も作る')).dy,
      lessThan(tester.getTopLeft(find.text('語る')).dy),
    );

    await tester.ensureVisible(find.text('自分も作る'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自分も作る'));
    await tester.pumpAndSettle();
    expect(find.text('未配置'), findsOneWidget);
    expect(find.text('カードを掴んで、あなたのTierを作ろう'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('鬼'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('S').last);
    await tester.pumpAndSettle();
    expect(find.text('1 / 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('共有URLからTier詳細を直接表示する', (tester) async {
    final state = AppState(
      StarterTierRepository(),
      initialPath: '/ja/tier/starter-pasta',
    );
    await tester.pumpWidget(TierTableOnlineApp(appState: state));
    await tester.pumpAndSettle();

    expect(find.byType(TopicDetailScreen), findsOneWidget);
    expect(find.text('美味しいパスタTier'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('存在しない共有URLは404表示になる', (tester) async {
    final state = AppState(
      DummyTierRepository(),
      cloudRepository: _MissingTopicCloudRepository(),
      initialPath: '/ja/tier/not-found',
    );
    await tester.pumpWidget(TierTableOnlineApp(appState: state));
    await tester.pumpAndSettle();

    expect(find.text('削除された、または非公開のTier表です。'), findsOneWidget);
    expect(find.text('ホーム'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1440pxでは左右広告と中央ポータルを使う', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TierTableOnlineApp(appState: AppState(DummyTierRepository())),
    );

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(Scrollbar), findsOneWidget);
    expect(tester.getRect(find.byType(Scrollbar)).right, 1440);
    final logo = tester.widget<Image>(find.byType(Image).first);
    expect(
      (logo.image as AssetImage).assetName,
      'assets/branding/tier-logo.png',
    );
    expect(tester.getSize(find.byType(BrandMark).first).width, 300);
    expect(find.text('広告掲載スペース'), findsNWidgets(2));
    expect(find.text('メニュー'), findsOneWidget);
    expect(find.text('画像からTierを作る'), findsOneWidget);
    expect(find.text('新しいTierを作る'), findsOneWidget);
    expect(find.text('みんなで決める、\nみんなのTier。'), findsOneWidget);
    final trending = tester.widget<Text>(find.text('急上昇').first);
    expect(trending.softWrap, isFalse);
    final homeButton = find.ancestor(
      of: find.text('ホーム').first,
      matching: find.byType(InkWell),
    );
    final exploreButton = find.ancestor(
      of: find.text('探す').first,
      matching: find.byType(InkWell),
    );
    expect(
      tester.getRect(exploreButton.first).left -
          tester.getRect(homeButton.first).right,
      greaterThan(0),
    );
    expect(tester.getRect(homeButton.first).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('1024pxのデスクトップは広告を外して中央メニューを優先する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TierTableOnlineApp(appState: AppState(DummyTierRepository())),
    );

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('広告掲載スペース'), findsNothing);
    expect(find.text('メニュー'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新規TierをマイTier画面から削除できる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = DummyTierRepository();
    final state = AppState(repository);
    await state.initialize();
    const topic = TierTopic(
      id: 'local-delete-test',
      title: '削除テストTier',
      description: '削除確認用',
      tags: ['テスト'],
      category: 'その他',
      creatorName: 'あなた',
      participants: 1,
      items: [
        TierItem(
          id: 'local-delete-test-0',
          topicId: 'local-delete-test',
          sortIndex: 0,
          name: 'テスト項目',
        ),
      ],
      community: {'local-delete-test-0': TierRank.s},
    );
    await state.addTopic(topic, const {
      TierRank.s: ['local-delete-test-0'],
    });
    await tester.pumpWidget(TierTableOnlineApp(appState: state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('マイTier').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Tier削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tier削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除').last);
    await tester.pumpAndSettle();

    expect(repository.getById(topic.id), isNull);
    expect(find.text('Tier表を削除しました'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('デスクトップ作成画面は画像ドロップ導線を表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateScreen(appState: AppState(DummyTierRepository())),
        ),
      ),
    );

    expect(find.text('画像をドラッグ＆ドロップ'), findsOneWidget);
    expect(find.textContaining('複数の画像を選ぶ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('既存Tierを検索し、いいね・自分のTierで絞り込める', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateScreen(appState: AppState(DummyTierRepository())),
        ),
      ),
    );

    await tester.tap(find.text('既存のTierから作る'));
    await tester.pumpAndSettle();
    expect(find.text('自分のTier'), findsOneWidget);
    expect(find.text('いいねしたTier'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'ゲーム');
    await tester.pumpAndSettle();
    expect(find.text('歴代最強ゲームTier'), findsOneWidget);
    await tester.tap(find.text('歴代最強ゲームTier'));
    await tester.pumpAndSettle();

    expect(find.byType(TierBuilderScreen), findsNothing);
    expect(find.widgetWithText(TextField, '歴代最強ゲームTier'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'ゲーム, 名作'), findsOneWidget);
    expect(find.text('クロノ・トリガー'), findsOneWidget);
    expect(find.textContaining('8枚追加済み'), findsOneWidget);
    expect(find.textContaining('自由に編集できます'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('絵文字テンプレートを作成フォームへ読み込んで編集できる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateScreen(appState: AppState(DummyTierRepository())),
        ),
      ),
    );

    await tester.tap(find.text('テンプレートから作る'));
    await tester.pumpAndSettle();
    expect(find.text('動物Tier'), findsOneWidget);
    expect(find.text('国Tier'), findsOneWidget);
    expect(find.text('食べ物Tier'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quick-template-animals')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '動物Tier'), findsOneWidget);
    expect(find.widgetWithText(TextField, '動物, 生き物'), findsOneWidget);
    expect(find.text('🐶 犬'), findsOneWidget);
    expect(find.text('🦉 フクロウ'), findsOneWidget);
    expect(find.textContaining('8枚追加済み'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('デスクトップのカード編集は中央ダイアログで開く', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateScreen(appState: AppState(DummyTierRepository())),
        ),
      ),
    );

    final addByName = find.text('名前でカードを追加');
    await tester.ensureVisible(addByName);
    await tester.pumpAndSettle();
    await tester.tap(addByName);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '苺虫');
    await tester.tap(find.text('まとめて追加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('あとで'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('苺虫'));
    await tester.pumpAndSettle();
    final card = find.ancestor(
      of: find.text('苺虫'),
      matching: find.byType(InkWell),
    );
    expect(card, findsOneWidget);
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byTooltip('閉じる'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('作る画面は画像中心の簡略フローを表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TierTableOnlineApp(appState: AppState(DummyTierRepository())),
    );

    await tester.tap(find.text('作る').last);
    await tester.pumpAndSettle();
    expect(find.text('複数の画像を選ぶ'), findsOneWidget);
    expect(find.text('名前でカードを追加'), findsOneWidget);
    expect(find.textContaining('権利を保有している画像'), findsOneWidget);
    expect(find.text('名前付きのアップロード画像をみんなで再利用する'), findsOneWidget);

    await tester.tap(find.text('名前でカードを追加'));
    await tester.pumpAndSettle();
    final namesField = tester.widget<TextField>(find.byType(TextField).last);
    expect(namesField.decoration?.hintText, 'ねこ\nコーヒー\n青');
    await tester.enterText(find.byType(TextField).last, '鬼\n天狗\n河童');
    await tester.tap(find.text('まとめて追加'));
    await tester.pumpAndSettle();
    expect(find.text('無料の画像候補を取得しますか？'), findsOneWidget);
    await tester.tap(find.text('あとで'));
    await tester.pumpAndSettle();
    expect(find.text('鬼'), findsOneWidget);
    expect(find.text('天狗'), findsOneWidget);
    expect(find.text('河童'), findsOneWidget);
    expect(find.textContaining('3枚追加済み'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('設定からライトテーマへ切り替えられる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final appState = AppState(DummyTierRepository());
    await appState.initialize();
    await tester.pumpWidget(TierTableOnlineApp(appState: appState));

    await tester.tap(find.text('設定').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ライト'));
    await tester.pumpAndSettle();

    expect(appState.themeMode, ThemeMode.light);
    expect(
      Theme.of(tester.element(find.text('表示テーマ'))).brightness,
      Brightness.light,
    );
    await tester.tap(find.text('ホーム').last);
    await tester.pumpAndSettle();
    final heroTitle = tester.widget<Text>(find.text('みんなで決める、\nみんなのTier。'));
    expect(heroTitle.style?.color, Colors.white);
    expect(find.byKey(const ValueKey('brand-shadow')), findsOneWidget);
    expect(find.byKey(const ValueKey('brand-backplate')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('語るへの返信は任意の賛成・異議ありを付けられる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final appState = AppState(
      DummyTierRepository(),
      trustLocalSharedRoutes: true,
    );
    await appState.initialize();
    await appState.markOnboardingSeen();
    await tester.pumpWidget(TierTableOnlineApp(appState: appState));

    final topic = find.text('最強の妖怪Tier').last;
    await tester.ensureVisible(topic);
    await tester.pumpAndSettle();
    await tester.tap(topic);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('語る'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('返信する').first);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('評価'), findsNothing);
    expect(find.text('賛成！'), findsOneWidget);
    expect(find.text('異議あり！'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '自分もそう思います');
    await tester.ensureVisible(find.text('賛成！'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('賛成！'));
    await tester.ensureVisible(find.text('返信を投稿する'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('返信を投稿する'));
    await tester.pumpAndSettle();

    expect(find.text('自分もそう思います'), findsNothing);
    expect(find.text('返信を表示（1）'), findsOneWidget);
    await tester.ensureVisible(find.text('返信を表示（1）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('返信を表示（1）'));
    await tester.pumpAndSettle();
    expect(find.text('自分もそう思います'), findsOneWidget);
    expect(find.text('賛成！'), findsOneWidget);
    expect(find.textContaining('👍 いいね'), findsWidgets);
    expect(find.textContaining('🤔 うーん'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('コメントを確認後に通報できる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final appState = AppState(
      DummyTierRepository(),
      trustLocalSharedRoutes: true,
    );
    await appState.initialize();
    await appState.markOnboardingSeen();
    await tester.pumpWidget(TierTableOnlineApp(appState: appState));

    final topic = find.text('最強の妖怪Tier').last;
    await tester.ensureVisible(topic);
    await tester.pumpAndSettle();
    await tester.tap(topic);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('語る'));
    await tester.pumpAndSettle();
    expect(find.text('👍 いいね 0'), findsWidgets);
    expect(find.text('🤔 うーん 0'), findsWidgets);

    await tester.ensureVisible(find.text('通報する').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('通報する').first);
    await tester.pumpAndSettle();
    expect(find.text('このコメントを通報しますか？'), findsOneWidget);
    await tester.tap(find.text('通報する').last);
    await tester.pumpAndSettle();
    expect(find.text('通報を受け付けました'), findsOneWidget);
    expect(appState.isTalkReported('yokai', postId: 'yokai-talk-1'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tier詳細は3件だけコメントを表示し残りを語る専用画面で開く', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = DummyTierRepository();
    final appState = AppState(repository);
    await appState.initialize();
    final source = repository.getById('yokai')!;
    final topic = source.copyWith(
      talks: [
        for (var i = 1; i <= 4; i++)
          TalkPost(
            id: 'preview-$i',
            author: 'user$i',
            body: 'コメント$i',
            rank: TierRank.b,
            minutesAgo: i,
          ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TopicDetailScreen(
          appState: appState,
          topic: topic,
          onTagTap: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('コメント1'), findsOneWidget);
    expect(find.text('コメント3'), findsOneWidget);
    expect(find.text('コメント4'), findsNothing);
    final showAll = find.text('すべてのコメントを見る（4件）');
    await tester.ensureVisible(showAll);
    await tester.pumpAndSettle();
    await tester.tap(showAll);
    await tester.pumpAndSettle();
    expect(find.text('コメント4'), findsOneWidget);
    expect(find.byType(SegmentedButton<int>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tierカードは短い名前を大きく表示する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              TierItemCard(
                item: TierItem(
                  id: 'short',
                  topicId: 'topic',
                  sortIndex: 0,
                  name: '鬼',
                ),
                size: 58,
              ),
              TierItemCard(
                item: TierItem(
                  id: 'long',
                  topicId: 'topic',
                  sortIndex: 1,
                  name: 'ぬらりひょん',
                ),
                size: 58,
              ),
            ],
          ),
        ),
      ),
    );

    final shortName = tester.widget<Text>(find.text('鬼'));
    final longName = tester.widget<Text>(find.text('ぬらりひょん'));
    expect(shortName.style!.fontSize, greaterThan(longName.style!.fontSize!));
    expect(shortName.style!.fontSize, greaterThanOrEqualTo(18));
    expect(shortName.style!.color, Colors.white);
    expect(longName.style!.color, Colors.white);

    final shortSurface = tester.widget<Container>(
      find.byKey(const ValueKey('tier-item-surface-short')),
    );
    final decoration = shortSurface.decoration! as BoxDecoration;
    expect(decoration.gradient, isA<LinearGradient>());
    expect(decoration.boxShadow, isNotEmpty);
  });

  testWidgets('探すカードの表示アニメーションを設定で無効化できる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final appState = AppState(DummyTierRepository());
    await appState.initialize();
    await tester.pumpWidget(TierTableOnlineApp(appState: appState));

    await tester.tap(find.text('探す').last);
    await tester.pump();
    final firstReveal = find.byKey(const ValueKey('explore-reveal-0'));
    expect(firstReveal, findsOneWidget);
    expect(
      find.descendant(of: firstReveal, matching: find.byType(FadeTransition)),
      findsOneWidget,
    );

    await appState.setAnimationsEnabled(false);
    await tester.pump();
    expect(
      find.descendant(of: firstReveal, matching: find.byType(FadeTransition)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('世界のTierを有効にすると5言語を複数選択できる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = DummyTierRepository()
      ..add(
        const TierTopic(
          id: 'korean-topic',
          title: '한국 티어',
          description: '',
          tags: ['한국'],
          category: '게임',
          categoryId: 'games',
          creatorName: '테스터',
          participants: 1,
          items: [
            TierItem(
              id: 'korean-item',
              topicId: 'korean-topic',
              sortIndex: 0,
              name: '카드',
            ),
          ],
          community: {'korean-item': TierRank.s},
          contentLanguage: AppLocale.ko,
          targetRegion: 'KR',
        ),
      );
    await tester.pumpWidget(TierTableOnlineApp(appState: AppState(repository)));

    expect(find.text('한국 티어'), findsNothing);
    await tester.tap(find.text('世界のTierを見る'));
    await tester.pumpAndSettle();
    expect(find.text('日本語'), findsOneWidget);
    expect(find.text('韓国語'), findsOneWidget);
    expect(find.text('英語'), findsOneWidget);
    expect(find.text('繁体字'), findsOneWidget);
    expect(find.text('ポルトガル語'), findsOneWidget);
    await tester.tap(find.text('韓国語'));
    await tester.pumpAndSettle();
    expect(find.text('한국 티어'), findsWidgets);
  });

  testWidgets('結果画面に共有PNG用の描画領域を表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(840, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = DummyTierRepository();
    final appState = AppState(repository);
    await appState.initialize();
    final topic = repository.getById('yokai')!;
    await appState.setPlacements('yokai', {
      for (final rank in TierRank.values)
        rank: [
          for (final item in topic.items)
            if (topic.community[item.id] == rank) item.id,
        ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: TierResultScreen(appState: appState, topic: topic),
      ),
    );
    expect(find.text('tier表オンライン'), findsOneWidget);
    expect(find.text('結果を共有'), findsOneWidget);
    expect(find.text('X'), findsOneWidget);
    expect(find.text('LINE'), findsOneWidget);
    expect(find.text('画像を保存'), findsOneWidget);
    expect(find.text('語りに行く'), findsOneWidget);
    expect(find.byType(RepaintBoundary), findsWidgets);
    expect(find.text('共有画像は次のフェーズで追加します'), findsNothing);
  });

  testWidgets('公開前プレビューで確認してからテーマを保存する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = DummyTierRepository();
    final appState = AppState(repository);
    await appState.initialize();
    const topic = TierTopic(
      id: 'local-preview',
      title: 'プレビューTier',
      description: '公開前の確認',
      tags: ['確認'],
      category: 'その他',
      creatorName: 'あなた',
      participants: 0,
      items: [
        TierItem(
          id: 'local-preview-0',
          topicId: 'local-preview',
          sortIndex: 0,
          name: 'カード',
        ),
      ],
      community: {'local-preview-0': TierRank.ss},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TierPublishPreviewScreen(
          appState: appState,
          topic: topic,
          placements: const {
            TierRank.ss: ['local-preview-0'],
          },
        ),
      ),
    );
    expect(find.text('まだ公開されていません。タイトルとカードの配置を確認してください。'), findsOneWidget);
    expect(repository.getById(topic.id), isNull);

    await tester.tap(find.text('この内容で公開する'));
    await tester.pumpAndSettle();
    expect(repository.getById(topic.id), isNotNull);
    expect(find.text('あなたのTierが完成！'), findsOneWidget);
  });

  testWidgets('5言語URLが対応言語のUIを表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final entry in const [
      ('ja', 'ホーム'),
      ('ko', '홈'),
      ('zh-tw', '首頁'),
      ('pt-br', 'Início'),
      ('en', 'Home'),
    ]) {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(
        DummyTierRepository(),
        initialPath: '/${entry.$1}/',
      );
      await state.initialize();
      await tester.pumpWidget(TierTableOnlineApp(appState: state));
      await tester.pumpAndSettle();
      expect(find.text(entry.$2), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('狭い画面でも5言語のテーマ切替とロゴが崩れない', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final entry in const [
      (
        code: 'ja',
        settings: '設定',
        system: '端末設定',
        asset: 'assets/branding/tier-logo.png',
      ),
      (
        code: 'ko',
        settings: '설정',
        system: '기기 설정',
        asset: 'assets/branding/tier-logo-ko.png',
      ),
      (
        code: 'zh-tw',
        settings: '設定',
        system: '跟隨系統',
        asset: 'assets/branding/tier-logo-en.png',
      ),
      (
        code: 'pt-br',
        settings: 'Configurações',
        system: 'Sistema',
        asset: 'assets/branding/tier-logo-en.png',
      ),
      (
        code: 'en',
        settings: 'Settings',
        system: 'System',
        asset: 'assets/branding/tier-logo-en.png',
      ),
    ]) {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(
        DummyTierRepository(),
        initialPath: '/${entry.code}/',
      );
      await state.initialize();
      await tester.pumpWidget(TierTableOnlineApp(appState: state));
      await tester.pumpAndSettle();

      final logo = tester.widget<Image>(
        find.byKey(ValueKey('brand-logo-${entry.code}')),
      );
      expect((logo.image as AssetImage).assetName, entry.asset);

      await tester.tap(find.text(entry.settings).last);
      await tester.pumpAndSettle();
      expect(find.text(entry.system), findsOneWidget);
      final selectorSize = tester.getSize(
        find.byKey(const ValueKey('theme-mode-selector')),
      );
      expect(selectorSize.height, 64);
      expect(selectorSize.width, lessThanOrEqualTo(256));
      expect(selectorSize.width, greaterThan(200));
      expect(tester.takeException(), isNull);
    }
  });
}

class _AuthMenuHarness extends StatefulWidget {
  const _AuthMenuHarness({
    super.key,
    this.initiallyRegistered = false,
    this.onMyTier,
  });

  final bool initiallyRegistered;
  final VoidCallback? onMyTier;

  @override
  State<_AuthMenuHarness> createState() => _AuthMenuHarnessState();
}

class _AuthMenuHarnessState extends State<_AuthMenuHarness> {
  late AuthSessionState _authSession;

  @override
  void initState() {
    super.initState();
    _authSession = widget.initiallyRegistered
        ? const AuthSessionState.registered(email: 'user@example.com')
        : const AuthSessionState.guest();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('ja'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Align(
        alignment: Alignment.topRight,
        child: AccountMenuButton(
          authSession: _authSession,
          onMyTier: widget.onMyTier ?? () {},
          onSettings: () {},
          onSignIn: () async {
            setState(() {
              _authSession = const AuthSessionState.registered(
                email: 'user@example.com',
              );
            });
          },
          onSignOut: () async {
            setState(() {
              _authSession = const AuthSessionState.guest();
            });
          },
        ),
      ),
    ),
  );
}

class _MissingTopicCloudRepository implements CloudTierRepository {
  @override
  String get currentUserId => 'test-user';

  @override
  Future<TierTopic?> loadTopic(String topicId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
