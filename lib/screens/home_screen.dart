import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/tier_models.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/app_breakpoints.dart';
import '../widgets/common_widgets.dart';
import '../widgets/tier_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.appState,
    required this.onExplore,
    required this.onCreate,
    this.scrollController,
  });
  final AppState appState;
  final ValueChanged<String?> onExplore;
  final VoidCallback onCreate;
  final ScrollController? scrollController;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _filter = 0;
  String? _category;
  bool _viewWorldTiers = false;
  final Set<AppLocale> _languages = {};
  TopicCardDensity _density = TopicCardDensity.full;
  void _open(TierTopic topic) => Navigator.of(context).pushNamed(
    '/${widget.appState.locale.code}/tier/${topic.id}',
    arguments: widget.onExplore,
  );

  @override
  Widget build(BuildContext context) {
    if (!_viewWorldTiers) {
      _languages
        ..clear()
        ..add(widget.appState.locale);
    }
    final languageTopics = widget.appState.publicTopics
        .where(
          (topic) =>
              topic.isLanguageNeutral ||
              _languages.contains(topic.contentLanguage),
        )
        .toList();
    final topics = [...languageTopics]
      ..sort((a, b) => _localePriority(b).compareTo(_localePriority(a)));
    if (_filter == 0) {
      topics.sort((a, b) => b.likeCount.compareTo(a.likeCount));
    }
    if (_filter == 1) {
      topics.sort(
        (a, b) => (b.isTrending ? 1 : 0).compareTo(a.isTrending ? 1 : 0),
      );
    }
    if (_filter == 2) {
      topics.sort((a, b) => a.createdDaysAgo.compareTo(b.createdDaysAgo));
    }
    final shown = _category == null
        ? topics
        : topics.where((topic) => topic.categoryId == _category).toList();
    final categories = {
      for (final topic in languageTopics) topic.categoryId,
    }.toList();
    return SingleChildScrollView(
      controller: widget.scrollController,
      child: ContentFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF28223E), Color(0xFF172D35)],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.t('heroTitle'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    context.l10n.t('heroSubtitle'),
                    style: const TextStyle(color: Color(0xFFC8CBD8)),
                  ),
                  const SizedBox(height: 19),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 7.0;
                      final badgeSize =
                          ((constraints.maxWidth -
                                      gap * (TierRank.values.length - 1)) /
                                  TierRank.values.length)
                              .clamp(28.0, 37.0);
                      return Row(
                        children: [
                          for (
                            var index = 0;
                            index < TierRank.values.length;
                            index++
                          ) ...[
                            if (index > 0) const SizedBox(width: gap),
                            TierBadge(
                              rank: TierRank.values[index],
                              size: badgeSize,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: widget.onCreate,
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    label: Text(context.l10n.t('createFromImages')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(210, 50),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      backgroundColor: AppColors.purple,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              readOnly: true,
              onTap: () => widget.onExplore(null),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: context.l10n.t('searchTitleTag'),
              ),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: CategoryFilterChip(
                      label: context.l10n.t('all'),
                      selected: _category == null,
                      onTap: () => setState(() => _category = null),
                    ),
                  ),
                  for (final category in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: CategoryFilterChip(
                        label: context.l10n.categoryName(category),
                        selected: _category == category,
                        onTap: () => setState(() => _category = category),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            WorldLanguageFilter(
              enabled: _viewWorldTiers,
              selected: _languages,
              onEnabledChanged: (value) => setState(() {
                _viewWorldTiers = value;
                if (_languages.isEmpty) {
                  _languages.add(widget.appState.locale);
                }
              }),
              onLanguageChanged: (locale, selected) => setState(() {
                if (selected) {
                  _languages.add(locale);
                } else {
                  _languages.remove(locale);
                }
              }),
            ),
            const SizedBox(height: 26),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: SectionHeader(
                    title: context.l10n.t('findInteresting'),
                    subtitle: context.l10n.count('themeCount', shown.length),
                  ),
                ),
                TopicViewModeToggle(
                  density: _density,
                  onChanged: (value) => setState(() => _density = value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _SortFilter(
                selected: _filter,
                onSelected: (value) => setState(() => _filter = value),
              ),
            ),
            const SizedBox(height: 14),
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
                    for (final topic in shown)
                      SizedBox(
                        width: width,
                        child: TopicCard(
                          topic: topic,
                          density: _density,
                          liked: widget.appState.isTopicLiked(topic.id),
                          onLike: () async {
                            await widget.appState.toggleTopicLike(topic.id);
                            if (mounted) setState(() {});
                          },
                          onTap: () => _open(topic),
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
  }

  int _localePriority(TierTopic topic) {
    if (topic.contentLanguage == widget.appState.locale &&
        topic.targetRegion == widget.appState.region) {
      return 4;
    }
    if (topic.contentLanguage == widget.appState.locale &&
        topic.targetRegion == 'GLOBAL') {
      return 3;
    }
    if (topic.isLanguageNeutral) return 2;
    return 1;
  }
}

class _SortFilter extends StatelessWidget {
  const _SortFilter({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outline),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SortFilterItem(
          label: context.l10n.t('popular'),
          selected: selected == 0,
          onTap: () => onSelected(0),
        ),
        _SortFilterItem(
          label: context.l10n.t('trending'),
          selected: selected == 1,
          onTap: () => onSelected(1),
        ),
        _SortFilterItem(
          label: context.l10n.t('newest'),
          selected: selected == 2,
          onTap: () => onSelected(2),
        ),
      ],
    ),
  );
}

class _SortFilterItem extends StatelessWidget {
  const _SortFilterItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? AppColors.cyan : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(
            label,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: selected
                  ? AppColors.background
                  : Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    ),
  );
}
