import 'package:flutter/material.dart';

import '../l10n/bingo_localizations.dart';
import '../services/bingo_state.dart';
import '../widgets/bingo_widgets.dart';
import 'bingo_home_screen.dart';

class BingoMyScreen extends StatefulWidget {
  const BingoMyScreen({
    super.key,
    required this.state,
    required this.onCreate,
    required this.onTagTap,
  });

  final BingoState state;
  final VoidCallback onCreate;
  final ValueChanged<String> onTagTap;

  @override
  State<BingoMyScreen> createState() => _BingoMyScreenState();
}

class _BingoMyScreenState extends State<BingoMyScreen> {
  @override
  void initState() {
    super.initState();
    widget.state.loadJoinedBoards();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.bingo;
    final state = widget.state;
    final created = state.ownBoards;
    final joined = state.joinedBoards;
    Widget heading(String key) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(
        strings.t(key),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
    );
    return RefreshIndicator(
      onRefresh: () async {
        await state.refreshBoards();
        await state.loadJoinedBoards();
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          BingoFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading('myJoined'),
                if (joined.isEmpty)
                  BingoEmptyState(
                    icon: Icons.style_outlined,
                    title: strings.t('myEmptyJoined'),
                  )
                else
                  BingoBoardGrid(
                    state: state,
                    boards: joined,
                    onTagTap: widget.onTagTap,
                  ),
                heading('myCreated'),
                if (created.isEmpty)
                  BingoEmptyState(
                    icon: Icons.grid_on_rounded,
                    title: strings.t('myEmptyCreated'),
                    action: FilledButton.icon(
                      onPressed: widget.onCreate,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(strings.t('createFirst')),
                    ),
                  )
                else
                  BingoBoardGrid(
                    state: state,
                    boards: created,
                    onTagTap: widget.onTagTap,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
