import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/app_breakpoints.dart';
import '../bingo_app.dart';
import '../l10n/bingo_localizations.dart';
import '../services/bingo_state.dart';
import '../theme/bingo_theme.dart';
import '../widgets/bingo_widgets.dart';
import 'bingo_create_screen.dart';
import 'bingo_home_screen.dart';
import 'bingo_my_screen.dart';
import 'bingo_settings_screen.dart';

enum BingoTab {
  home('', Icons.home_outlined, Icons.home_rounded, 'navHome'),
  create(
    'create',
    Icons.add_circle_outline_rounded,
    Icons.add_circle_rounded,
    'navCreate',
  ),
  my('my', Icons.grid_view_outlined, Icons.grid_view_rounded, 'navMy'),
  settings(
    'settings',
    Icons.settings_outlined,
    Icons.settings_rounded,
    'navSettings',
  );

  const BingoTab(this.path, this.icon, this.selectedIcon, this.labelKey);
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
}

class BingoShell extends StatefulWidget {
  const BingoShell({
    super.key,
    required this.state,
    this.initialTab = BingoTab.home,
  });

  final BingoState state;
  final BingoTab initialTab;

  @override
  State<BingoShell> createState() => _BingoShellState();
}

class _BingoShellState extends State<BingoShell> {
  late BingoTab _tab = widget.initialTab;
  String? _homeQuery;
  int _createKey = 0;
  AppLocale? _urlLocale;

  BingoState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.addListener(_syncUrlLocale);
  }

  @override
  void dispose() {
    state.removeListener(_syncUrlLocale);
    super.dispose();
  }

  /// Keeps the `/{locale}/` prefix in the address bar in sync with the UI
  /// language, as tier-online does for shareable URLs.
  void _syncUrlLocale() {
    if (!state.initialized || _urlLocale == state.locale) return;
    _urlLocale = state.locale;
    _updateUrl();
  }

  void _updateUrl() {
    SystemNavigator.routeInformationUpdated(
      uri: Uri.parse(BingoRoutes.tab(state.locale, _tab)),
      replace: true,
    );
  }

  void _select(BingoTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    _updateUrl();
  }

  void _openTag(String tag) {
    setState(() {
      _homeQuery = tag;
      _tab = BingoTab.home;
    });
    _updateUrl();
  }

  void _onPublished() => setState(() {
    _createKey++;
    _tab = BingoTab.my;
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      if (!state.initialized) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final pages = [
        BingoHomeScreen(
          state: state,
          initialQuery: _homeQuery,
          onCreate: () => _select(BingoTab.create),
        ),
        BingoCreateScreen(
          key: ValueKey('create-$_createKey'),
          state: state,
          onPublished: _onPublished,
        ),
        BingoMyScreen(
          state: state,
          onCreate: () => _select(BingoTab.create),
          onTagTap: _openTag,
        ),
        BingoSettingsScreen(state: state),
      ];
      return LayoutBuilder(
        builder: (context, constraints) {
          final desktop = AppBreakpoints.isDesktop(constraints.maxWidth);
          return Scaffold(
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(64),
              child: _TopBar(
                state: state,
                desktop: desktop,
                tab: _tab,
                onSelected: _select,
              ),
            ),
            body: IndexedStack(index: _tab.index, children: pages),
            bottomNavigationBar: desktop
                ? null
                : NavigationBar(
                    selectedIndex: _tab.index,
                    onDestinationSelected: (index) =>
                        _select(BingoTab.values[index]),
                    destinations: [
                      for (final tab in BingoTab.values)
                        NavigationDestination(
                          icon: Icon(tab.icon),
                          selectedIcon: Icon(tab.selectedIcon),
                          label: context.bingo.t(tab.labelKey),
                        ),
                    ],
                  ),
          );
        },
      );
    },
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.state,
    required this.desktop,
    required this.tab,
    required this.onSelected,
  });

  final BingoState state;
  final bool desktop;
  final BingoTab tab;
  final ValueChanged<BingoTab> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: BingoColors.outline)),
      ),
      child: BingoFrame(
        maxWidth: 1180,
        alignment: Alignment.center,
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSelected(BingoTab.home),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: BingoBrandMark(),
              ),
            ),
            const Spacer(),
            if (desktop) ...[
              for (final item in BingoTab.values)
                if (item != BingoTab.create)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: TextButton.icon(
                      onPressed: () => onSelected(item),
                      style: TextButton.styleFrom(
                        foregroundColor: item == tab
                            ? BingoColors.primary
                            : BingoColors.inkMuted,
                      ),
                      icon: Icon(item == tab ? item.selectedIcon : item.icon),
                      label: Text(
                        context.bingo.t(item.labelKey),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () => onSelected(BingoTab.create),
                icon: const Icon(Icons.add_rounded),
                label: Text(context.bingo.t('createTitle')),
              ),
            ] else
              Tooltip(
                message: context.bingo.t(
                  state.cloudEnabled ? 'syncOnline' : 'syncOffline',
                ),
                child: Icon(
                  state.cloudEnabled
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  size: 20,
                  color: BingoColors.inkMuted,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
