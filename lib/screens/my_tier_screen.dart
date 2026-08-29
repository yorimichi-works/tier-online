import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/app_state.dart';
import '../utils/app_breakpoints.dart';
import '../widgets/common_widgets.dart';
import '../widgets/tier_widgets.dart';

class MyTierScreen extends StatelessWidget {
  const MyTierScreen({
    super.key,
    required this.appState,
    required this.onTagTap,
    this.scrollController,
  });
  final AppState appState;
  final ValueChanged<String?> onTagTap;
  final ScrollController? scrollController;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appState,
    builder: (context, _) {
      final topics = appState.startedTopics.toList();
      return SingleChildScrollView(
        controller: scrollController,
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
              const SizedBox(height: 22),
              if (topics.isEmpty)
                EmptyState(
                  title: context.l10n.t('noTier'),
                  message: context.l10n.t('noTierMessage'),
                  icon: Icons.view_agenda_outlined,
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = AppBreakpoints.gridColumns(
                      constraints.maxWidth,
                    );
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
                              liked: appState.isTopicLiked(topic.id),
                              onLike: () => appState.toggleTopicLike(topic.id),
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
                                arguments: onTagTap,
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
