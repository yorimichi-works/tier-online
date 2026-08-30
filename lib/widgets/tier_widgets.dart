import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/tier_models.dart';
import '../theme/app_theme.dart';

class TierBadge extends StatelessWidget {
  const TierBadge({super.key, required this.rank, this.size = 34});
  final TierRank rank;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: rank.color,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: rank.color),
    ),
    child: Text(
      rank.label,
      style: TextStyle(
        color: Colors.black,
        fontSize: size * .5,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class TierItemCard extends StatelessWidget {
  const TierItemCard({
    super.key,
    required this.item,
    this.size = 70,
    this.onTap,
    this.editable = false,
  });
  final TierItem item;
  final double size;
  final VoidCallback? onTap;
  final bool editable;

  double _nameFontSize(String name, {required bool overlay}) {
    final length = name.runes.length;
    if (overlay) {
      if (length <= 2) return size * .18;
      if (length <= 5) return size * .15;
      return size * .12;
    }
    if (length <= 2) return size * .32;
    if (length <= 4) return size * .25;
    if (length <= 7) return size * .19;
    return size * .15;
  }

  @override
  Widget build(BuildContext context) {
    final imagePlaceholderColors = [
      const Color(0xFF49365E),
      const Color(0xFF285060),
      const Color(0xFF5A3C42),
      const Color(0xFF3E4F39),
      const Color(0xFF484A66),
    ];
    final textCardGradients = [
      const [Color(0xFF1687A7), Color(0xFF22536B)],
      const [Color(0xFF5D9147), Color(0xFF365F3A)],
      const [Color(0xFF8A57B5), Color(0xFF573A74)],
      const [Color(0xFFB65F70), Color(0xFF75434D)],
      const [Color(0xFF6D79BB), Color(0xFF484F82)],
    ];
    final paletteIndex = item.colorSeed % textCardGradients.length;
    final textGradient = textCardGradients[paletteIndex];
    final card = Semantics(
      label: item.accessibleLabel,
      button: onTap != null,
      child: Container(
        key: ValueKey('tier-item-surface-${item.id}'),
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: item.hasImage
              ? imagePlaceholderColors[item.colorSeed %
                    imagePlaceholderColors.length]
              : null,
          gradient: item.hasImage
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: textGradient,
                ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: item.hasImage
                ? AppColors.outline
                : textGradient.first.withValues(alpha: .92),
            width: item.hasImage ? 1 : 1.4,
          ),
          boxShadow: item.hasImage
              ? null
              : [
                  BoxShadow(
                    color: textGradient.first.withValues(alpha: .24),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (item.hasImage)
              _TierItemImage(imageUrl: item.imageUrl!)
            else
              Center(
                child: Padding(
                  padding: EdgeInsets.all(size * .09),
                  child: Text(
                    item.hasName ? item.name! : '◈',
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: item.hasName
                          ? _nameFontSize(item.name!, overlay: false)
                          : size * .35,
                      height: 1.08,
                    ),
                  ),
                ),
              ),
            if (item.hasImage && item.hasName)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 4,
                  ),
                  color: Colors.black.withValues(alpha: .68),
                  child: Text(
                    item.name!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: _nameFontSize(item.name!, overlay: true),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            if (editable)
              Positioned(
                top: 4,
                right: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .78),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .4),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.edit_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return onTap == null
        ? card
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: card,
          );
  }
}

class _TierItemImage extends StatelessWidget {
  const _TierItemImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    Widget errorBuilder(
      BuildContext context,
      Object error,
      StackTrace? stackTrace,
    ) => const Center(child: Icon(Icons.broken_image_outlined));

    if (imageUrl.startsWith('assets/')) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: errorBuilder,
      );
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: errorBuilder,
    );
  }
}

class TierRowView extends StatelessWidget {
  const TierRowView({
    super.key,
    required this.rank,
    required this.items,
    this.cardSize = 58,
  });
  final TierRank rank;
  final List<TierItem> items;
  final double cardSize;
  @override
  Widget build(BuildContext context) => Container(
    height: cardSize + 16,
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.outline)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: rank.color,
            border: Border(right: BorderSide(color: rank.color)),
          ),
          child: Text(
            rank.label,
            style: TextStyle(
              color: Colors.black,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: Row(
              children: items.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          '—',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ]
                  : [
                      for (final item in items)
                        Padding(
                          padding: const EdgeInsets.only(right: 7),
                          child: TierItemCard(item: item, size: cardSize),
                        ),
                    ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// Card display density. Persist the user's choice with a toggle at the
/// list level (see `TopicViewModeToggle`) so it is consistent across a
/// screen's grid.
enum TopicCardDensity { full, compact }

class TopicViewModeToggle extends StatelessWidget {
  const TopicViewModeToggle({
    super.key,
    required this.density,
    required this.onChanged,
  });
  final TopicCardDensity density;
  final ValueChanged<TopicCardDensity> onChanged;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget button(TopicCardDensity value, IconData icon, String label) {
      final selected = density == value;
      return Tooltip(
        message: label,
        child: InkWell(
          onTap: () => onChanged(value),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: selected ? scheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            TopicCardDensity.full,
            Icons.grid_view_rounded,
            context.l10n.t('viewModeFull'),
          ),
          button(
            TopicCardDensity.compact,
            Icons.view_list_rounded,
            context.l10n.t('viewModeCompact'),
          ),
        ],
      ),
    );
  }
}

class TopicCard extends StatelessWidget {
  const TopicCard({
    super.key,
    required this.topic,
    required this.onTap,
    this.progress,
    this.liked = false,
    this.onLike,
    this.managementAction,
    this.showJoinAction = true,
    this.density = TopicCardDensity.full,
  });
  final TierTopic topic;
  final VoidCallback onTap;
  final double? progress;
  final bool liked;
  final VoidCallback? onLike;
  final Widget? managementAction;
  final bool showJoinAction;
  final TopicCardDensity density;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: density == TopicCardDensity.compact
          ? _CompactTopicCardBody(topic: topic, liked: liked)
          : _FullTopicCardBody(
              topic: topic,
              progress: progress,
              liked: liked,
              onLike: onLike,
              managementAction: managementAction,
              showJoinAction: showJoinAction,
              onTap: onTap,
            ),
    ),
  );
}

class _TrendingBadge extends StatelessWidget {
  const _TrendingBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFFF575E),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.local_fire_department_rounded, size: 13, color: Colors.white),
        const SizedBox(width: 3),
        Text(
          context.l10n.t('trending'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _LikeCountBadge extends StatelessWidget {
  const _LikeCountBadge({required this.count, required this.liked});
  final int count;
  final bool liked;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        size: 17,
        color: const Color(0xFFFF7186),
      ),
      const SizedBox(width: 5),
      Text(
        '$count',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _WinnerRow extends StatelessWidget {
  const _WinnerRow({required this.topic});
  final TierTopic topic;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Text('👑', style: TextStyle(fontSize: 15)),
      const SizedBox(width: 6),
      Text(
        context.l10n.format('firstPlace', {
          'rank': topic.faceRank?.label ?? context.l10n.t('notAggregated'),
        }),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
      ),
      if (topic.faceItem?.hasName ?? false) ...[
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            topic.faceItem!.name!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    ],
  );
}

class _TagWrap extends StatelessWidget {
  const _TagWrap({required this.tags, this.max = 3});
  final List<String> tags;
  final int max;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in tags.take(max))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '#$tag',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

class _FullTopicCardBody extends StatelessWidget {
  const _FullTopicCardBody({
    required this.topic,
    required this.progress,
    required this.liked,
    required this.onLike,
    required this.managementAction,
    required this.showJoinAction,
    required this.onTap,
  });
  final TierTopic topic;
  final double? progress;
  final bool liked;
  final VoidCallback? onLike;
  final Widget? managementAction;
  final bool showJoinAction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final face = topic.faceItem;
    final hasBanner = face?.hasImage ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasBanner)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _TierItemImage(imageUrl: face!.imageUrl!),
                if (topic.isTrending)
                  const Positioned(top: 10, right: 10, child: _TrendingBadge()),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!hasBanner)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      if (topic.isTrending) const _TrendingBadge(),
                      const Spacer(),
                      GestureDetector(
                        onTap: onLike,
                        child: _LikeCountBadge(
                          count: topic.likeCount,
                          liked: liked,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      topic.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (hasBanner) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onLike,
                      child: _LikeCountBadge(
                        count: topic.likeCount,
                        liked: liked,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.topicDescription(topic.description),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 13),
              _WinnerRow(topic: topic),
              const SizedBox(height: 11),
              Row(
                children: [
                  Icon(
                    Icons.people_outline_rounded,
                    size: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      context.l10n.format('topicStats', {
                        'participants': topic.participants,
                        'items': topic.items.length,
                      }),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              if (topic.tags.isNotEmpty) ...[
                const SizedBox(height: 11),
                _TagWrap(tags: topic.tags),
              ],
              if (progress != null) ...[
                const SizedBox(height: 11),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(99),
                  backgroundColor: AppColors.elevated,
                ),
              ],
              if (managementAction != null) ...[
                const SizedBox(height: 13),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                const SizedBox(height: 5),
                SizedBox(width: double.infinity, child: managementAction!),
              ],
              if (showJoinAction) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.playlist_add_rounded, size: 21),
                    label: Text(context.l10n.t('joinTier')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      backgroundColor: AppColors.purple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactTopicCardBody extends StatelessWidget {
  const _CompactTopicCardBody({required this.topic, required this.liked});
  final TierTopic topic;
  final bool liked;

  @override
  Widget build(BuildContext context) {
    final face = topic.faceItem;
    final hasThumb = face?.hasImage ?? false;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (hasThumb) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 64,
                height: 64,
                child: _TierItemImage(imageUrl: face!.imageUrl!),
              ),
            ),
            const SizedBox(width: 13),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        topic.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _LikeCountBadge(count: topic.likeCount, liked: liked),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        context.l10n.format('firstPlace', {
                          'rank':
                              topic.faceRank?.label ??
                              context.l10n.t('notAggregated'),
                        }),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.people_outline_rounded,
                      size: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${topic.participants}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (topic.tags.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  _TagWrap(tags: topic.tags, max: 3),
                ],
              ],
            ),
          ),
          if (topic.isTrending) ...[
            const SizedBox(width: 10),
            const _TrendingBadge(),
          ],
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
