import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/tier_models.dart';
import '../services/app_state.dart';
import '../services/firebase_bootstrap.dart';
import '../services/rewarded_ad_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/tier_widgets.dart';
import 'account_sheet.dart';
import 'email_verification_pending_screen.dart';
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
  final _rewardedAdService = RewardedAdService();

  TierItem _item(String id) =>
      widget.topic.items.firstWhere((item) => item.id == id);

  /// クラウド接続が確立していない場合(起動時のFirebase初期化がタイムアウト
  /// した等)、この場で再接続を試みる。これに失敗した状態で公開を進めると、
  /// 画像がアップロードされないまま「local-」始まりのローカル限定Tierとして
  /// 静かに保存されてしまう(=公開に見えて実際は公開されていない)ため、
  /// 公開操作は必ずクラウド接続を要求する。
  Future<bool> _ensureCloudConnected() async {
    if (widget.appState.cloudEnabled) return true;
    final firebase = await FirebaseBootstrap.initialize().timeout(
      const Duration(seconds: 12),
      onTimeout: () => const FirebaseBootstrapResult(),
    );
    if (firebase.repository != null && firebase.auth != null) {
      await widget.appState.attachCloud(
        cloudRepository: firebase.repository!,
        auth: firebase.auth!,
      );
    }
    return widget.appState.cloudEnabled;
  }

  Future<bool> _ensureRegisteredAccount() async {
    if (!widget.appState.authEnabled) return true;
    if (widget.appState.isAnonymous) {
      final authenticated = await showAccountSheet(context, widget.appState);
      if (!mounted || !authenticated) return false;
    }
    if (widget.appState.needsEmailVerification) {
      final verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) =>
              EmailVerificationPendingScreen(appState: widget.appState),
        ),
      );
      if (!mounted || verified != true) return false;
    }
    return !widget.appState.isAnonymous &&
        !widget.appState.needsEmailVerification;
  }

  Future<void> _publish() async {
    if (_publishing) return;
    setState(() => _publishing = true);
    if (!await _ensureCloudConnected()) {
      if (!mounted) return;
      setState(() => _publishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('publishRequiresConnection'))),
      );
      return;
    }
    if (!mounted) return;
    if (!await _ensureRegisteredAccount()) {
      if (!mounted) return;
      setState(() => _publishing = false);
      return;
    }
    if (!mounted) return;
    try {
      await widget.appState.addTopic(widget.topic, widget.placements);
      if (!mounted) return;
      final published = widget.appState.topics.firstWhere(
        (topic) => topic.id == widget.topic.id,
        orElse: () => widget.topic,
      );
      if (published.moderationStatus == 'flagged') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('publishFlaggedNotice'))),
        );
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              TierResultScreen(appState: widget.appState, topic: published),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() => _publishing = false);
      if (error.code == 'resource-exhausted' &&
          error.details is Map &&
          (error.details as Map)['reason'] == 'dailyLimit') {
        await _handleDailyLimitReached();
        return;
      }
      final messageKey = switch (error.code) {
        'failed-precondition' => 'publishBlocked',
        'resource-exhausted' => 'publishRateLimited',
        _ => null,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            messageKey != null
                ? context.l10n.t(messageKey)
                : context.l10n.format('publishFailed', {
                    'error': error.message ?? error.code,
                  }),
          ),
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

  Future<void> _handleDailyLimitReached() async {
    if (widget.appState.isAnonymous) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.l10n.t('publishRateLimited')),
          content: const Text('無料登録すると1日10件まで作成できます'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.t('cancel')),
            ),
          ],
        ),
      );
      return;
    }
    final wantsAd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('publishRateLimited')),
        content: const Text('広告を見るとあと1件作成できます'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('広告を見る'),
          ),
        ],
      ),
    );
    if (wantsAd != true || !mounted) return;
    if (!_rewardedAdService.isSupported) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('この環境では広告を利用できません')));
      return;
    }
    final earned = await _rewardedAdService.showAndAwaitReward();
    if (!mounted) return;
    if (!earned) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('広告の視聴が完了しませんでした')));
      return;
    }
    final status = await widget.appState.claimCreateAdBonus();
    if (!mounted) return;
    if (status == null || !status.canCreate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ボーナスの付与に失敗しました。もう一度お試しください')),
      );
      return;
    }
    await _publish();
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
            const SizedBox(height: 6),
            Text(
              context.l10n.topicDescription(widget.topic.description),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
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
            if (widget.appState.authEnabled && widget.appState.isAnonymous) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  context.l10n.t('accountRequiredToCreateTier'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            PrimaryButton(
              label: _publishing
                  ? context.l10n.t('publishing')
                  : context.l10n.t(
                      widget.appState.authEnabled && widget.appState.isAnonymous
                          ? 'saveAndCreateAccount'
                          : 'publish',
                    ),
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
