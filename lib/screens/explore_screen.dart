import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/tier_models.dart';
import '../services/app_state.dart';
import '../utils/app_breakpoints.dart';
import '../widgets/common_widgets.dart';
import '../widgets/tier_widgets.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.appState,
    this.initialTag,
    this.scrollController,
  });
  final AppState appState;
  final String? initialTag;
  final ScrollController? scrollController;
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late String _query = widget.initialTag ?? '';
  late final TextEditingController _controller = TextEditingController(
    text: _query,
  );
  bool _viewWorldTiers = false;
  final Set<AppLocale> _languages = {};
  TopicCardDensity _density = TopicCardDensity.full;
  @override
  void didUpdateWidget(covariant ExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTag != oldWidget.initialTag) {
      _query = widget.initialTag ?? '';
      _controller.text = _query;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_viewWorldTiers) {
      _languages
        ..clear()
        ..add(widget.appState.locale);
    }
    final query = _query.toLowerCase();
    final topics =
        widget.appState.publicTopics
            .where(
              (topic) =>
                  (topic.isLanguageNeutral ||
                      _languages.contains(topic.contentLanguage)) &&
                  (query.isEmpty ||
                      topic.title.toLowerCase().contains(query) ||
                      topic.description.toLowerCase().contains(query) ||
                      topic.tags.any(
                        (tag) => tag.toLowerCase().contains(query),
                      ) ||
                      topic.creatorName.toLowerCase().contains(query) ||
                      topic.category.toLowerCase().contains(query) ||
                      topic.categoryId.toLowerCase().contains(query) ||
                      topic.items.any(
                        (item) =>
                            item.name?.toLowerCase().contains(query) ?? false,
                      )),
            )
            .toList()
          ..sort((a, b) => _priority(b).compareTo(_priority(a)));
    return SingleChildScrollView(
      controller: widget.scrollController,
      child: ContentFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.t('findTier'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.t('searchDescription'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: context.l10n.t('searchExample'),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
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
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: SectionHeader(
                    title: context.l10n.count('tierCount', topics.length),
                    subtitle: query.isEmpty
                        ? context.l10n.t('availableTopics')
                        : context.l10n.queryResult(_query),
                  ),
                ),
                TopicViewModeToggle(
                  density: _density,
                  onChanged: (value) => setState(() => _density = value),
                ),
              ],
            ),
            const SizedBox(height: 13),
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
                    for (var index = 0; index < topics.length; index++)
                      SizedBox(
                        width: width,
                        child: _RevealOnScroll(
                          key: ValueKey('explore-reveal-$index'),
                          enabled: widget.appState.animationsEnabled,
                          delayIndex: index,
                          child: TopicCard(
                            topic: topics[index],
                            density: _density,
                            liked: widget.appState.isTopicLiked(
                              topics[index].id,
                            ),
                            onLike: () async {
                              await widget.appState.toggleTopicLike(
                                topics[index].id,
                              );
                              if (mounted) setState(() {});
                            },
                            onTap: () => Navigator.of(context).pushNamed(
                              '/${widget.appState.locale.code}/tier/${topics[index].id}',
                              arguments: (String? tag) {
                                Navigator.of(context).pop();
                                setState(() {
                                  _query = tag ?? '';
                                  _controller.text = _query;
                                });
                              },
                            ),
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
  }

  int _priority(TierTopic topic) {
    if (topic.contentLanguage == widget.appState.locale) return 4;
    if (topic.targetRegion == 'GLOBAL') return 3;
    if (topic.isLanguageNeutral) return 2;
    return 1;
  }
}

class _RevealOnScroll extends StatefulWidget {
  const _RevealOnScroll({
    super.key,
    required this.enabled,
    required this.delayIndex,
    required this.child,
  });

  final bool enabled;
  final int delayIndex;
  final Widget child;

  @override
  State<_RevealOnScroll> createState() => _RevealOnScrollState();
}

class _RevealOnScrollState extends State<_RevealOnScroll>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: widget.enabled ? 0 : 1,
  );
  ScrollPosition? _position;
  Timer? _delayTimer;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachToScrollPosition();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
  }

  @override
  void didUpdateWidget(covariant _RevealOnScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _delayTimer?.cancel();
      _controller.value = 1;
    } else if (!oldWidget.enabled) {
      _controller.value = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
    }
  }

  void _attachToScrollPosition() {
    final next = Scrollable.maybeOf(context)?.position;
    if (identical(next, _position)) return;
    _position?.removeListener(_checkVisibility);
    _position = next;
    _position?.addListener(_checkVisibility);
  }

  void _checkVisibility() {
    if (!mounted || !widget.enabled || _controller.value > 0 || _scheduled) {
      return;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final top = renderObject.localToGlobal(Offset.zero).dy;
    final bottom = top + renderObject.size.height;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    if (top > viewportHeight - 24 || bottom < 0) return;
    _scheduled = true;
    _delayTimer = Timer(
      Duration(milliseconds: (widget.delayIndex % 3) * 70),
      () {
        if (mounted && widget.enabled) _controller.forward();
      },
    );
  }

  @override
  void dispose() {
    _position?.removeListener(_checkVisibility);
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .1),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: .94, end: 1).animate(curved),
          child: widget.child,
        ),
      ),
    );
  }
}
