import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/tier_models.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/tier_widgets.dart';
import 'tier_publish_preview_screen.dart';

class TierBuilderScreen extends StatefulWidget {
  const TierBuilderScreen({
    super.key,
    required this.appState,
    required this.topic,
    this.initialPlacements,
  });
  final AppState appState;
  final TierTopic topic;
  final Map<TierRank, List<String>>? initialPlacements;
  @override
  State<TierBuilderScreen> createState() => _TierBuilderScreenState();
}

class _TierBuilderScreenState extends State<TierBuilderScreen> {
  late Map<TierRank, List<String>> _placements;
  late List<String> _unplaced;

  @override
  void initState() {
    super.initState();
    final saved =
        widget.initialPlacements ??
        widget.appState.placementsFor(widget.topic.id);
    _placements = {
      for (final rank in TierRank.values)
        rank: List.of(saved[rank] ?? const []),
    };
    final placed = _placements.values.expand((ids) => ids).toSet();
    _unplaced = [
      for (final item in widget.topic.items)
        if (!placed.contains(item.id)) item.id,
    ];
  }

  TierItem _item(String id) =>
      widget.topic.items.firstWhere((item) => item.id == id);
  void _remove(String id) {
    _unplaced.remove(id);
    for (final ids in _placements.values) {
      ids.remove(id);
    }
  }

  void _move(String id, TierRank? rank, [int? index]) {
    setState(() {
      _remove(id);
      final target = rank == null ? _unplaced : _placements[rank]!;
      target.insert((index ?? target.length).clamp(0, target.length), id);
    });
  }

  Future<void> _chooseRank(String id) async {
    final rank = await showModalBottomSheet<TierRank?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _item(id).hasName ? _item(id).name! : 'この画像カードを移動',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final value in TierRank.values)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: value == TierRank.d ? 0 : 7,
                        ),
                        child: InkWell(
                          onTap: () => Navigator.pop(context, value),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: TierBadge(rank: value, size: 46),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () {
                  _move(id, null);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.undo_rounded),
                label: Text(context.l10n.t('returnUnplaced')),
              ),
            ],
          ),
        ),
      ),
    );
    if (rank != null) _move(id, rank);
  }

  Widget _draggableCard(String id, {TierRank? rank, int? index}) {
    final item = _item(id);
    final card = TierItemCard(
      item: item,
      size: 68,
      onTap: () => _chooseRank(id),
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != id,
      onAcceptWithDetails: (details) => _move(details.data, rank, index),
      builder: (context, candidates, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? Colors.transparent
              : AppColors.purple.withValues(alpha: .25),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Draggable<String>(
          data: id,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: .9,
              child: TierItemCard(item: item, size: 72),
            ),
          ),
          childWhenDragging: Opacity(opacity: .25, child: card),
          child: card,
        ),
      ),
    );
  }

  Widget _dropRow(TierRank rank) => DragTarget<String>(
    onAcceptWithDetails: (details) => _move(details.data, rank),
    builder: (context, candidates, _) => AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 88,
      decoration: BoxDecoration(
        color: candidates.isEmpty
            ? AppColors.card
            : rank.color.withValues(alpha: .1),
        border: Border(
          bottom: const BorderSide(color: AppColors.outline),
          left: BorderSide(
            color: candidates.isEmpty ? AppColors.outline : rank.color,
            width: candidates.isEmpty ? 1 : 2,
          ),
          right: const BorderSide(color: AppColors.outline),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 54,
            alignment: Alignment.center,
            color: rank.color,
            child: Text(
              rank.label,
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 23,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(7),
              child: Row(
                children: [
                  for (var i = 0; i < _placements[rank]!.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: _draggableCard(
                        _placements[rank]![i],
                        rank: rank,
                        index: i,
                      ),
                    ),
                  if (_placements[rank]!.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        context.l10n.t('dropHere'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _complete() async {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TierPublishPreviewScreen(
          appState: widget.appState,
          topic: widget.topic,
          placements: _placements,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final placedCount = widget.topic.items.length - _unplaced.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.topic.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 15),
            child: Center(
              child: Text(
                '$placedCount / ${widget.topic.items.length}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: ContentFrame(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.t('builderTitle'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                context.l10n.t('builderHelp'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.t('unplaced'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              DragTarget<String>(
                onAcceptWithDetails: (details) => _move(details.data, null),
                builder: (context, candidates, _) => AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 96),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: candidates.isEmpty
                        ? AppColors.elevated
                        : AppColors.purple.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: candidates.isEmpty
                          ? AppColors.outline
                          : AppColors.purple,
                    ),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < _unplaced.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: _draggableCard(_unplaced[i], index: i),
                          ),
                        if (_unplaced.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_outline_rounded,
                                  color: Color(0xFF55D6A2),
                                ),
                                const SizedBox(width: 8),
                                Text(context.l10n.t('allPlaced')),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final rank in TierRank.values) _dropRow(rank),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                label: _unplaced.isEmpty
                    ? context.l10n.t('finishTier')
                    : placedCount > 0
                    ? context.l10n.format('finishTierPartial', {
                        'count': _unplaced.length,
                      })
                    : context.l10n.format('remainingCards', {
                        'count': _unplaced.length,
                      }),
                icon: Icons.auto_awesome_rounded,
                onPressed: placedCount > 0 ? _complete : null,
              ),
              const SizedBox(height: 9),
              Center(
                child: Text(
                  context.l10n.t('placementSaved'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
