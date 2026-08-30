import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'repositories/starter_tier_repository.dart';
import 'screens/account_sheet.dart';
import 'screens/app_shell.dart';
import 'screens/contact_screen.dart';
import 'screens/email_action_screen.dart';
import 'screens/email_verification_pending_screen.dart';
import 'screens/legal_screen.dart';
import 'screens/topic_route_screen.dart';
import 'services/app_state.dart';
import 'services/firebase_bootstrap.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState(
    StarterTierRepository(),
    initialPath: Uri.base.path,
    deviceLocale: WidgetsBinding.instance.platformDispatcher.locale,
  );
  runApp(TierTableOnlineApp(appState: appState));
  unawaited(_initializeServices(appState));
}

Future<void> _initializeServices(AppState appState) async {
  // The bundled starter tiers must be usable immediately. Network-dependent
  // Firebase setup starts only after Flutter has painted its first frame, so a
  // slow or blocked connection can never hold the loading cover over the UI.
  try {
    final localInitialization = appState.initialize();
    await WidgetsBinding.instance.endOfFrame;
    final firebase = await FirebaseBootstrap.initialize().timeout(
      const Duration(seconds: 8),
      onTimeout: () => const FirebaseBootstrapResult(),
    );
    await localInitialization;
    if (firebase.repository != null && firebase.auth != null) {
      await appState.attachCloud(
        cloudRepository: firebase.repository!,
        auth: firebase.auth!,
      );
    }
  } finally {
    appState.completeCloudBootstrap();
  }
}

class TierTableOnlineApp extends StatefulWidget {
  const TierTableOnlineApp({super.key, required this.appState});
  final AppState appState;

  @override
  State<TierTableOnlineApp> createState() => _TierTableOnlineAppState();
}

class _TierTableOnlineAppState extends State<TierTableOnlineApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _verificationPromptShown = false;
  bool _redirectResultConsumed = false;

  AppState get appState => widget.appState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybePromptVerification();
    });
  }

  void _maybePromptVerification() {
    if (_verificationPromptShown || !appState.needsEmailVerification) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    _verificationPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigator.push(
        MaterialPageRoute<bool>(
          builder: (_) => EmailVerificationPendingScreen(appState: appState),
        ),
      );
    });
  }

  // モバイルWebのGoogleログインはリダイレクト方式(main.dartのコメント参照
  // のsignInWithGoogle実装)で行うため、アカウント競合(既にパスワードで
  // 登録済みのメール)が起きていないかをアプリ再読み込み時に確認する。
  void _maybeConsumeGoogleRedirectResult() {
    if (_redirectResultConsumed || !appState.cloudBootstrapComplete) return;
    _redirectResultConsumed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final result = await appState.consumeGoogleRedirectResult();
      if (!mounted ||
          result?.status != AuthResultStatus.googleAccountConflict) {
        return;
      }
      final context = _navigatorKey.currentState?.context;
      if (context != null && context.mounted) {
        await showAccountSheet(context, appState);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _maybeConsumeGoogleRedirectResult();
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigatorKey,
        onGenerateTitle: (context) => context.l10n.t('appName'),
        debugShowCheckedModeBanner: false,
        theme: buildLightAppTheme(),
        darkTheme: buildDarkAppTheme(),
        themeMode: appState.themeMode,
        locale: appState.locale.flutterLocale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        initialRoute: AppLocaleParser.fromPath(appState.initialPath) == null
            ? '/${appState.locale.code}/'
            : appState.initialPath,
        onGenerateRoute: _route,
      ),
    );
  }

  Route<void> _route(RouteSettings settings) {
    final segments =
        Uri.tryParse(settings.name ?? '/')?.pathSegments ?? const [];
    if (segments.length >= 3 && segments[1] == 'tier') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => TopicRouteScreen(
          appState: appState,
          topicId: segments[2],
          onTagTap: settings.arguments is ValueChanged<String?>
              ? settings.arguments! as ValueChanged<String?>
              : (_) {},
        ),
      );
    }
    if (segments.length >= 3 &&
        segments[1] == 'auth' &&
        segments[2] == 'action') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => EmailActionScreen(appState: appState),
      );
    }
    if (segments.length >= 2 && segments[1] == 'terms') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => TermsScreen(appState: appState),
      );
    }
    if (segments.length >= 2 && segments[1] == 'privacy') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => PrivacyScreen(appState: appState),
      );
    }
    if (segments.length >= 2 && segments[1] == 'contact') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => ContactScreen(appState: appState),
      );
    }
    final initialIndex = segments.length < 2
        ? 0
        : switch (segments[1]) {
            'search' => 1,
            'template' || 'create' => 2,
            'user' => 3,
            'settings' => 4,
            _ => 0,
          };
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => AppShell(appState: appState, initialIndex: initialIndex),
    );
  }
}
