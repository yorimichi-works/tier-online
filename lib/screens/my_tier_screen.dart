import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/tier_models.dart';
import '../services/app_state.dart';
import '../utils/app_breakpoints.dart';
import '../widgets/common_widgets.dart';
import '../widgets/tier_widgets.dart';

class MyTierScreen extends StatefulWidget {
  const MyTierScreen({
    super.key,
    required this.appState,
    required this.onTagTap,
    required this.onEdit,
    this.scrollController,
  });
  final AppState appState;
  final ValueChanged<String?> onTagTap;
  final ValueChanged<TierTopic> onEdit;
  final ScrollController? scrollController;

  @override
  State<MyTierScreen> createState() => _MyTierScreenState();
}

enum _MyTierSection { created, joined }

class _MyTierScreenState extends State<MyTierScreen> {
  _MyTierSection _section = _MyTierSection.created;
  TopicCardDensity _density = TopicCardDensity.full;
  final Set<String> _deletingTopicIds = {};
  final Set<String> _togglingVisibilityTopicIds = {};

  Future<void> _deleteTopic(BuildContext context, TierTopic topic) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('deleteTierConfirmTitle')),
        content: Text(context.l10n.t('deleteTierConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.l10n.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingTopicIds.add(topic.id));
    final deleted = await widget.appState.deleteOwnTopic(topic);
    if (!mounted || !context.mounted) return;
    setState(() => _deletingTopicIds.remove(topic.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.t(deleted ? 'deleteTierSuccess' : 'deleteTierFailure'),
        ),
      ),
    );
  }

  Future<void> _makePrivate(BuildContext context, TierTopic topic) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('makePrivateConfirmTitle')),
        content: Text(context.l10n.t('makePrivateConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.visibility_off_outlined),
            label: Text(context.l10n.t('makePrivate')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _setTopicPublic(topic, false);
  }

  Future<void> _setTopicPublic(TierTopic topic, bool isPublic) async {
    setState(() => _togglingVisibilityTopicIds.add(topic.id));
    await widget.appState.setTopicPublic(topic, isPublic);
    if (!mounted) return;
    setState(() => _togglingVisibilityTopicIds.remove(topic.id));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.appState,
    builder: (context, _) {
      final appState = widget.appState;
      final topics =
          (_section == _MyTierSection.created
                  ? appState.createdTopics
                  : appState.joinedTopics)
              .toList();
      return SingleChildScrollView(
        controller: widget.scrollController,
        child: ContentFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.t('myTier'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                context.l10n.t('savedOnDevice'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_MyTierSection>(
                  segments: [
                    ButtonSegment(
                      value: _MyTierSection.created,
                      icon: const Icon(Icons.edit_note_rounded),
                      label: Text(context.l10n.t('createdTiers')),
                    ),
                    ButtonSegment(
                      value: _MyTierSection.joined,
                      icon: const Icon(Icons.how_to_vote_outlined),
                      label: Text(context.l10n.t('joinedTiers')),
                    ),
                  ],
                  selected: {_section},
                  onSelectionChanged: (selection) {
                    setState(() => _section = selection.first);
                  },
                  showSelectedIcon: false,
                ),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: TopicViewModeToggle(
                  density: _density,
                  onChanged: (value) => setState(() => _density = value),
                ),
              ),
              const SizedBox(height: 14),
              if (topics.isEmpty)
                EmptyState(
                  title: context.l10n.t(
                    _section == _MyTierSection.created
                        ? 'noCreatedTier'
                        : 'noJoinedTier',
                  ),
                  message: context.l10n.t(
                    _section == _MyTierSection.created
                        ? 'noCreatedTierMessage'
                        : 'noJoinedTierMessage',
                  ),
                  icon: Icons.view_agenda_outlined,
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = _density == TopicCardDensity.compact
                        ? 1
                        : AppBreakpoints.gridColumns(constraints.maxWidth);
                    const gap = 13.0;
                    final width =
                        (constraints.maxWidth - gap * (columns - 1)) / columns;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final topic in topics)
                          SizedBox(
                            width: width,
                            child: TopicCard(
                              topic: topic,
                              density: _density,
                              liked: appState.isTopicLiked(topic.id),
                              onLike: () => appState.toggleTopicLike(topic.id),
                              managementAction:
                                  _section == _MyTierSection.created
                                  ? Wrap(
                                      spacing: 7,
                                      runSpacing: 7,
                                      children: [
                                        if (!topic.isPublic)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHigh,
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                            ),
                                            child: Text(
                                              context.l10n.t('privateTier'),
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        OutlinedButton.icon(
                                          onPressed: () => widget.onEdit(topic),
                                          icon: const Icon(Icons.edit_outlined),
                                          label: Text(
                                            context.l10n.t('editTier'),
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed:
                                              _togglingVisibilityTopicIds
                                                  .contains(topic.id)
                                              ? null
                                              : () => topic.isPublic
                                                    ? _makePrivate(
                                                        context,
                                                        topic,
                                                      )
                                                    : _setTopicPublic(
                                                        topic,
                                                        true,
                                                      ),
                                          icon:
                                              _togglingVisibilityTopicIds
                                                  .contains(topic.id)
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : Icon(
                                                  topic.isPublic
                                                      ? Icons
                                                            .visibility_off_outlined
                                                      : Icons
                                                            .visibility_outlined,
                                                ),
                                          label: Text(
                                            context.l10n.t(
                                              topic.isPublic
                                                  ? 'makePrivate'
                                                  : 'makePublic',
                                            ),
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed:
                                              _deletingTopicIds.contains(
                                                topic.id,
                                              )
                                              ? null
                                              : () => _deleteTopic(
                                                  context,
                                                  topic,
                                                ),
                                          icon: _deletingTopicIds.contains(
                                            topic.id,
                                          )
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.delete_outline_rounded,
                                                ),
                                          label: Text(
                                            context.l10n.t('deleteTier'),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                            side: BorderSide(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error
                                                  .withValues(alpha: .55),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : null,
                              showJoinAction: false,
                              progress:
                                  appState
                                      .placementsFor(topic.id)
                                      .values
                                      .fold(
                                        0,
                                        (total, items) => total + items.length,
                                      ) /
                                  topic.items.length,
                              onTap: () => Navigator.of(context).pushNamed(
                                '/${appState.locale.code}/tier/${topic.id}',
                                arguments: widget.onTagTap,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}
