import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/tier_models.dart';
import '../services/app_state.dart';
import '../services/share_image_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/tier_widgets.dart';
import 'topic_detail_screen.dart';

class TierResultScreen extends StatefulWidget {
  const TierResultScreen({
    super.key,
    required this.appState,
    required this.topic,
  });
  final AppState appState;
  final TierTopic topic;

  @override
  State<TierResultScreen> createState() => _TierResultScreenState();
}

class _TierResultScreenState extends State<TierResultScreen> {
  static const _publicAppUrl = String.fromEnvironment('PUBLIC_APP_URL');
  final _shareBoundaryKey = GlobalKey();
  bool _generatingShareImage = false;

  AppState get appState => widget.appState;
  TierTopic get topic => widget.topic;
  TierItem _item(String id) => topic.items.firstWhere((item) => item.id == id);

  Future<void> _saveShareImage() async {
    if (_generatingShareImage) return;
    setState(() => _generatingShareImage = true);
    try {
      await ShareImageService.captureAndDownload(
        boundaryKey: _shareBoundaryKey,
        fileName: topic.title,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('shareDownloaded'))),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.format('shareGenerateFailed', {'error': error}),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _generatingShareImage = false);
    }
  }

  Uri get _shareUrl {
    final base = _publicAppUrl.isEmpty ? Uri.base : Uri.parse(_publicAppUrl);
    return base.replace(
      path: '/${appState.locale.code}/tier/${topic.id}',
      queryParameters: const {},
      fragment: null,
    );
  }

  Future<void> _openShareUrl(Uri uri) async {
    try {
      final opened = await launchUrl(uri, webOnlyWindowName: '_blank');
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('shareOpenFailed'))),
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.l10n.t('shareOpenFailed')}: $error')),
      );
    }
  }

  void _shareToX() {
    _openShareUrl(
      Uri.https('twitter.com', '/intent/tweet', {
        'text':
            '${context.l10n.shareMessage(topic.title)} #${context.l10n.t('appName').replaceAll(' ', '')}',
        'url': _shareUrl.toString(),
      }),
    );
  }

  void _shareToLine() {
    _openShareUrl(
      Uri.https('social-plugins.line.me', '/lineit/share', {
        'url': _shareUrl.toString(),
        'text': context.l10n.shareMessage(topic.title),
      }),
    );
  }

  void _openTalk() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TopicDetailScreen(
          appState: appState,
          topic: topic,
          initialTab: 1,
          onTagTap: (_) {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final placements = appState.placementsFor(topic.id);
    final mine = <String, TierRank>{
      for (final entry in placements.entries)
        for (final id in entry.value) id: entry.key,
    };
    final matches = topic.items
        .where((item) => mine[item.id] == topic.community[item.id])
        .length;
    final agreement = topic.items.isEmpty
        ? 0
        : (matches / topic.items.length * 100).round();
    TierItem? different;
    var maxGap = -1;
    for (final item in topic.items) {
      final gap = (mine[item.id]!.index - topic.community[item.id]!.index)
          .abs();
      if (gap > maxGap) {
        maxGap = gap;
        different = item;
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.t('yourTier'))),
      body: SingleChildScrollView(
        child: ContentFrame(
          maxWidth: 840,
          child: Column(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFFFFD166),
                size: 35,
              ),
              const SizedBox(height: 7),
              Text(
                context.l10n.t('tierComplete'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              const SizedBox(height: 14),
              RepaintBoundary(
                key: _shareBoundaryKey,
                child: ColoredBox(
                  color: const Color(0xFF101114),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.t('appName'),
                          style: const TextStyle(
                            color: Color(0xFF55D4E5),
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          topic.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          clipBehavior: Clip.antiAlias,
                          margin: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (final rank in TierRank.values)
                                TierRowView(
                                  rank: rank,
                                  items: [
                                    for (final id in placements[rank]!)
                                      _item(id),
                                  ],
                                ),
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
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.t('matchRate'),
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$agreement%',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                      if (different != null)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l10n.t('mostDifferent'),
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                different.accessibleLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  TierBadge(
                                    rank: mine[different.id]!,
                                    size: 26,
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    child: Text('↔'),
                                  ),
                                  TierBadge(
                                    rank: topic.community[different.id]!,
                                    size: 26,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 13),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.l10n.t('shareResults'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 720 ? 4 : 2;
                  const spacing = 9.0;
                  final buttonWidth =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      SizedBox(
                        width: buttonWidth,
                        child: _ShareActionButton(
                          label: 'X',
                          icon: Icons.close_rounded,
                          onPressed: _shareToX,
                        ),
                      ),
                      SizedBox(
                        width: buttonWidth,
                        child: _ShareActionButton(
                          label: 'LINE',
                          icon: Icons.chat_bubble_rounded,
                          backgroundColor: const Color(0xFF06C755),
                          foregroundColor: Colors.white,
                          onPressed: _shareToLine,
                        ),
                      ),
                      SizedBox(
                        width: buttonWidth,
                        child: _ShareActionButton(
                          label: _generatingShareImage
                              ? context.l10n.t('saving')
                              : context.l10n.t('saveImage'),
                          icon: Icons.download_rounded,
                          loading: _generatingShareImage,
                          onPressed: _generatingShareImage
                              ? null
                              : _saveShareImage,
                        ),
                      ),
                      SizedBox(
                        width: buttonWidth,
                        child: _ShareActionButton(
                          label: context.l10n.t('goDiscuss'),
                          icon: Icons.forum_outlined,
                          backgroundColor: const Color(0xFF7E6BF2),
                          foregroundColor: Colors.white,
                          onPressed: _openTalk,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareActionButton extends StatelessWidget {
  const _ShareActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool loading;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: loading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 19),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        side: BorderSide(
          color: backgroundColor ?? Theme.of(context).colorScheme.outline,
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}
