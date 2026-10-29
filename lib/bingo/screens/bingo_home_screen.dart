import 'package:flutter/material.dart';

import '../../utils/app_breakpoints.dart';
import '../bingo_app.dart';
import '../l10n/bingo_localizations.dart';
import '../models/bingo_models.dart';
import '../services/bingo_state.dart';
import '../theme/bingo_theme.dart';
import '../widgets/bingo_widgets.dart';

void openBingoBoard(BuildContext context, BingoState state, BingoBoard board) =>
    Navigator.of(context).pushNamed(BingoRoutes.board(state.locale, board.id));

/// Responsive grid of board tiles (1/2/3 columns like tier-online).
class BingoBoardGrid extends StatelessWidget {
  const BingoBoardGrid({
    super.key,
    required this.state,
    required this.boards,
    this.onTagTap,
  });

  final BingoState state;
  final List<BingoBoard> boards;
  final ValueChanged<String>? onTagTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = AppBreakpoints.gridColumns(constraints.maxWidth);
      const spacing = 12.0;
      final width =
          (constraints.maxWidth - spacing * (columns - 1)) / columns - .1;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final board in boards)
            SizedBox(
              width: width,
              child: BingoBoardTile(
                key: ValueKey('board-${board.id}'),
                board: board,
                entry: state.entryFor(board.id),
                onTagTap: onTagTap,
                onTap: () => openBingoBoard(context, state, board),
              ),
            ),
        ],
      );
    },
  );
}

class BingoHomeScreen extends StatefulWidget {
  const BingoHomeScreen({
    super.key,
    required this.state,
    required this.onCreate,
    this.initialQuery,
  });

  final BingoState state;
  final VoidCallback onCreate;
  final String? initialQuery;

  @override
  State<BingoHomeScreen> createState() => _BingoHomeScreenState();
}

class _BingoHomeScreenState extends State<BingoHomeScreen> {
  late final _search = TextEditingController(text: widget.initialQuery ?? '');
  BingoSort _sort = BingoSort.newest;

  @override
  void didUpdateWidget(BingoHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery &&
        widget.initialQuery != null) {
      _search.text = widget.initialQuery!;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.bingo;
    final state = widget.state;
    final query = _search.text.trim();
    final boards = state.listedBoards(sort: _sort, query: query);
    return RefreshIndicator(
      onRefresh: state.refreshBoards,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (query.isEmpty) _Hero(onCreate: widget.onCreate),
          BingoFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('bingo-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: strings.t('searchHint'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: strings.t('close'),
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(_search.clear),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    SegmentedButton<BingoSort>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: BingoSort.newest,
                          icon: const Icon(Icons.schedule_rounded, size: 18),
                          label: Text(strings.t('newest')),
                        ),
                        ButtonSegment(
                          value: BingoSort.popular,
                          icon: const Icon(
                            Icons.local_fire_department_outlined,
                            size: 18,
                          ),
                          label: Text(strings.t('popular')),
                        ),
                      ],
                      selected: {_sort},
                      onSelectionChanged: (value) =>
                          setState(() => _sort = value.first),
                    ),
                    const Spacer(),
                    if (state.loadingBoards)
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (boards.isEmpty)
                  BingoEmptyState(
                    icon: Icons.grid_on_rounded,
                    title: query.isEmpty
                        ? strings.t('noBoards')
                        : strings.format('noSearchResults', {'query': query}),
                    body: query.isEmpty ? strings.t('noBoardsBody') : null,
                    action: query.isEmpty
                        ? FilledButton.icon(
                            onPressed: widget.onCreate,
                            icon: const Icon(Icons.add_rounded),
                            label: Text(strings.t('createFirst')),
                          )
                        : null,
                  )
                else
                  BingoBoardGrid(
                    state: state,
                    boards: boards,
                    onTagTap: (tag) => setState(() => _search.text = tag),
                  ),
                if (query.isEmpty) ...[
                  const SizedBox(height: 28),
                  Text(
                    strings.t('samples'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  BingoBoardGrid(state: state, boards: state.samples),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final strings = context.bingo;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF4EF), Color(0xFFFFFBEA), Colors.white],
        ),
        border: Border(bottom: BorderSide(color: BingoColors.outline)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: BingoFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.t('tagline'),
              style: const TextStyle(
                fontSize: 26,
                height: 1.25,
                fontWeight: FontWeight.w900,
                letterSpacing: -.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              strings.t('createLead'),
              style: const TextStyle(color: BingoColors.inkMuted, height: 1.5),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('hero-create'),
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: Text(strings.t('createTitle')),
            ),
          ],
        ),
      ),
    );
  }
}
