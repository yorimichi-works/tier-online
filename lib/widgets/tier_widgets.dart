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
              Image.network(
                item.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Center(child: Icon(Icons.broken_image_outlined)),
              )
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
  });
  final TierTopic topic;
  final VoidCallback onTap;
  final double? progress;
  final bool liked;
  final VoidCallback? onLike;
  final Widget? managementAction;
  final bool showJoinAction;
  @override
  Widget build(BuildContext context) {
    final face = topic.faceItem;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (face != null) TierItemCard(item: face, size: 82),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onLike,
                        icon: Icon(
                          liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: liked ? const Color(0xFFFF7186) : null,
                          size: 18,
                        ),
                        label: Text('${topic.likeCount}'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHigh,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurface,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 7,
                          ),
                          minimumSize: const Size(0, 36),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF575E),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          context.l10n.format('firstPlace', {
                            'rank':
                                topic.faceRank?.label ??
                                context.l10n.t('notAggregated'),
                          }),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (topic.isTrending) ...[
                        const SizedBox(height: 8),
                        Text(
                          context.l10n.t('trending'),
                          style: const TextStyle(
                            color: Color(0xFFFF7186),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Text(
                topic.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                context.l10n.topicDescription(topic.description),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 11),
              Wrap(
                spacing: 5,
                children: [
                  for (final tag in topic.tags.take(3))
                    Text(
                      '#$tag',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  const Icon(Icons.people_outline_rounded, size: 15),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      context.l10n.format('topicStats', {
                        'participants': topic.participants,
                        'items': topic.items.length,
                      }),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
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
                const SizedBox(height: 13),
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
      ),
    );
  }
}
