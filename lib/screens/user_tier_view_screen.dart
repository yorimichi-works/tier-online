import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/tier_models.dart';
import '../widgets/common_widgets.dart';
import '../widgets/tier_widgets.dart';

/// コメント投稿者が「自分のtierを載せる」を選んだ場合に、その人の
/// 個別Tier回答を閲覧専用で表示する画面。
class UserTierViewScreen extends StatelessWidget {
  const UserTierViewScreen({
    super.key,
    required this.topic,
    required this.submission,
    required this.authorName,
  });

  final TierTopic topic;
  final UserTierSubmission submission;
  final String authorName;

  TierItem? _item(String id) =>
      topic.items.where((item) => item.id == id).firstOrNull;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.l10n.format('authorTierTitle', {'name': authorName})),
    ),
    body: SingleChildScrollView(
      child: ContentFrame(
        maxWidth: 840,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              topic.title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
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
                        for (final id in submission.placements[rank] ?? const [])
                          if (_item(id) != null) _item(id)!,
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
