import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/bingo_localizations.dart';
import 'screens/bingo_detail_screen.dart';
import 'screens/bingo_shell.dart';
import 'services/bingo_state.dart';
import 'theme/bingo_theme.dart';

/// Routes (all prefixed by the UI locale, as in tier-online):
///
/// - `/{locale}/` home, `/{locale}/create`, `/{locale}/my`,
///   `/{locale}/settings`
/// - `/{locale}/bingo/{bingoId}` board detail
abstract final class BingoRoutes {
  static String home(AppLocale locale) => '/${locale.code}/';
  static String tab(AppLocale locale, BingoTab tab) =>
      tab == BingoTab.home ? home(locale) : '/${locale.code}/${tab.path}';
  static String board(AppLocale locale, String boardId) =>
      '/${locale.code}/bingo/$boardId';
}

class BingoOnlineApp extends StatelessWidget {
  const BingoOnlineApp({super.key, required this.state});

  final BingoState state;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => MaterialApp(
      onGenerateTitle: (context) => context.bingo.t('appName'),
      debugShowCheckedModeBanner: false,
      theme: buildBingoTheme(),
      locale: state.locale.flutterLocale,
      supportedLocales: BingoLocalizations.supportedLocales,
      localizationsDelegates: const [
        BingoLocalizations.delegate,
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
      initialRoute: AppLocaleParser.fromPath(state.initialPath) == null
          ? BingoRoutes.home(state.locale)
          : state.initialPath,
      onGenerateRoute: (settings) => _route(settings),
      // The default splits `/ja/bingo/x` into one route per path prefix.
      // A deep link should open exactly one page; its back button falls
      // back to home.
      onGenerateInitialRoutes: (initialRoute) => [
        _route(RouteSettings(name: initialRoute)),
      ],
    ),
  );

  Route<void> _route(RouteSettings settings) {
    final segments =
        Uri.tryParse(settings.name ?? '/')?.pathSegments ?? const <String>[];
    final meaningful = segments.where((segment) => segment.isNotEmpty).toList();
    if (meaningful.length >= 3 && meaningful[1] == 'bingo') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => BingoDetailScreen(state: state, boardId: meaningful[2]),
      );
    }
    final tab = meaningful.length < 2
        ? BingoTab.home
        : BingoTab.values.firstWhere(
            (candidate) => candidate.path == meaningful[1],
            orElse: () => BingoTab.home,
          );
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => BingoShell(state: state, initialTab: tab),
    );
  }
}
