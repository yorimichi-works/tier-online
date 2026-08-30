import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'repositories/starter_tier_repository.dart';
import 'screens/app_shell.dart';
import 'screens/email_verification_pending_screen.dart';
import 'screens/topic_detail_screen.dart';
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

  AppState get appState => widget.appState;

  void _maybePromptVerification() {
    if (_verificationPromptShown || !appState.needsEmailVerification) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    _verificationPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => EmailVerificationPendingScreen(appState: appState),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _maybePromptVerification();
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
      final topic = appState.topics
          .where((topic) => topic.id == segments[2])
          .firstOrNull;
      if (topic != null) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => TopicDetailScreen(
            appState: appState,
            topic: topic,
            onTagTap: settings.arguments is ValueChanged<String?>
                ? settings.arguments! as ValueChanged<String?>
                : (_) {},
          ),
        );
      }
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
