import 'package:flutter/material.dart';

import '../services/app_state.dart';
import 'app_scaffold.dart';
import 'create_screen.dart';
import 'explore_screen.dart';
import 'home_screen.dart';
import 'my_tier_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.appState, this.initialIndex = 0});
  final AppState appState;
  final int initialIndex;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index;
  String? _searchTag;
  final _scrollControllers = List.generate(5, (_) => ScrollController());

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, 4);
  }

  @override
  void dispose() {
    for (final controller in _scrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _openExplore(String? tag) => setState(() {
    _searchTag = tag;
    _index = 1;
  });
  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        appState: widget.appState,
        onExplore: _openExplore,
        onCreate: () => setState(() => _index = 2),
        scrollController: _scrollControllers[0],
      ),
      ExploreScreen(
        appState: widget.appState,
        initialTag: _searchTag,
        scrollController: _scrollControllers[1],
      ),
      CreateScreen(
        appState: widget.appState,
        scrollController: _scrollControllers[2],
      ),
      MyTierScreen(
        appState: widget.appState,
        onTagTap: _openExplore,
        scrollController: _scrollControllers[3],
      ),
      SettingsScreen(
        appState: widget.appState,
        scrollController: _scrollControllers[4],
      ),
    ];
    return AppScaffold(
      index: _index,
      onSelected: (value) => setState(() => _index = value),
      scrollController: _scrollControllers[_index],
      body: IndexedStack(index: _index, children: pages),
    );
  }
}
