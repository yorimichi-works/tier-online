import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/tier_models.dart';
import '../services/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/tier_widgets.dart';
import 'tier_builder_screen.dart';
import 'tier_result_screen.dart';

class TierPublishPreviewScreen extends StatefulWidget {
  const TierPublishPreviewScreen({
    super.key,
    required this.appState,
    required this.topic,
    required this.placements,
  });

  final AppState appState;
  final TierTopic topic;
  final Map<TierRank, List<String>> placements;

  @override
  State<TierPublishPreviewScreen> createState() =>
      _TierPublishPreviewScreenState();
}

class _TierPublishPreviewScreenState extends State<TierPublishPreviewScreen> {
  bool _publishing = false;

  TierItem _item(String id) =>
      widget.topic.items.firstWhere((item) => item.id == id);

  Future<void> _publish() async {
    if (_publishing) return;
    setState(() => _publishing = true);
    try {
      await widget.appState.addTopic(widget.topic, widget.placements);
      if (!mounted) return;
      final published = widget.appState.topics.firstWhere(
        (topic) => topic.id == widget.topic.id,
        orElse: () => widget.topic,
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              TierResultScreen(appState: widget.appState, topic: published),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _publishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.format('publishFailed', {'error': error})),
        ),
      );
    }
  }

  void _backToEdit() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TierBuilderScreen(
          appState: widget.appState,
          topic: widget.topic,
          initialPlacements: widget.placements,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.t('publishPreview'))),
    body: SingleChildScrollView(
      child: ContentFrame(
        maxWidth: 900,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF55D4E5).withValues(alpha: .09),
                border: Border.all(color: const Color(0xFF55D4E5)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    color: Color(0xFF55D4E5),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.l10n.t('publishNotice'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.topic.title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            if (widget.topic.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.topic.description,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                Chip(label: Text(widget.topic.category)),
                for (final tag in widget.topic.tags) Chip(label: Text('#$tag')),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final rank in TierRank.values)
                    TierRowView(
                      rank: rank,
                      items: [
                        for (final id in widget.placements[rank] ?? const [])
                          _item(id),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.topic.items.length}枚のカード ・ 画像と名前は公開後の共通選択肢になります',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: _publishing
                  ? context.l10n.t('publishing')
                  : context.l10n.t('publish'),
              icon: Icons.public_rounded,
              onPressed: _publishing ? null : _publish,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _publishing ? null : _backToEdit,
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text(context.l10n.t('fixPlacement')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
