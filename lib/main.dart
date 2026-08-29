import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'repositories/dummy_tier_repository.dart';
import 'screens/app_shell.dart';
import 'screens/topic_detail_screen.dart';
import 'services/app_state.dart';
import 'services/firebase_bootstrap.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebase = await FirebaseBootstrap.initialize();
  final appState = AppState(
    DummyTierRepository(),
    cloudRepository: firebase.repository,
    auth: firebase.auth,
    initialPath: Uri.base.path,
    deviceLocale: WidgetsBinding.instance.platformDispatcher.locale,
  );
  await appState.initialize();
  runApp(TierTableOnlineApp(appState: appState));
}

class TierTableOnlineApp extends StatelessWidget {
  const TierTableOnlineApp({super.key, required this.appState});
  final AppState appState;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appState,
    builder: (context, _) => MaterialApp(
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
