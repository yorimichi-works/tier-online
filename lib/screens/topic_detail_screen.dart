import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/tier_models.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/tier_widgets.dart';
import 'tier_builder_screen.dart';

class TopicDetailScreen extends StatefulWidget {
  const TopicDetailScreen({
    super.key,
    required this.appState,
    required this.topic,
    required this.onTagTap,
    this.initialTab = 0,
  });
  final AppState appState;
  final TierTopic topic;
  final ValueChanged<String?> onTagTap;
  final int initialTab;
  @override
  State<TopicDetailScreen> createState() => _TopicDetailScreenState();
}

class _TopicDetailScreenState extends State<TopicDetailScreen> {
  final _talkController = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.appState.load(widget.topic.id);
  }

  @override
  void dispose() {
    _talkController.dispose();
    super.dispose();
  }

  void _buildTier() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          TierBuilderScreen(appState: widget.appState, topic: widget.topic),
    ),
  );

  Future<void> _reportTalk(TalkPost post, String? replyId) async {
    final postId = post.id;
    if (postId == null) return;
    if (widget.appState.isTalkReported(
      widget.topic.id,
      postId: postId,
      replyId: replyId,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('reportAlreadySubmitted'))),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('reportConfirmTitle')),
        content: Text(context.l10n.t('reportConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.t('reportComment')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final submitted = await widget.appState.reportTalk(
      widget.topic.id,
      postId: postId,
      replyId: replyId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.t(
            submitted ? 'reportSubmitted' : 'reportAlreadySubmitted',
          ),
        ),
      ),
    );
  }

  Widget _talkBoard({int? previewLimit}) => _TalkBoard(
    topic: widget.topic,
    posts: widget.appState.talksFor(widget.topic),
    previewLimit: previewLimit,
    onShowAll: previewLimit == null
        ? null
        : () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TopicDetailScreen(
                appState: widget.appState,
                topic: widget.topic,
                onTagTap: widget.onTagTap,
                initialTab: 1,
              ),
            ),
          ),
    controller: _talkController,
    onReply: (post, parentReplyId, body, stance) async {
      if (post.id == null) return;
      await widget.appState.replyToTalk(
        widget.topic,
        postId: post.id!,
        parentReplyId: parentReplyId,
        body: body,
        stance: stance,
      );
    },
    onReact: (post, replyId, positive) async {
      if (post.id == null) return;
      await widget.appState.reactToTalk(
        widget.topic,
        postId: post.id!,
        replyId: replyId,
        positive: positive,
      );
    },
    onReport: _reportTalk,
    onPost: () async {
      final text = _talkController.text.trim();
      if (text.isEmpty) return;
      _talkController.clear();
      await widget.appState.postTalk(
        widget.topic.id,
        body: text,
        rank: TierRank.b,
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.l10n.t(widget.initialTab == 1 ? 'talk' : 'topic')),
    ),
    body: AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final currentTopic = widget.appState.topics.firstWhere(
          (topic) => topic.id == widget.topic.id,
          orElse: () => widget.topic,
        );
        final placements = widget.appState.placementsFor(widget.topic.id);
        final placed = placements.values.fold(
          0,
          (total, items) => total + items.length,
        );
        if (widget.initialTab == 1) {
          return SingleChildScrollView(
            child: ContentFrame(maxWidth: 840, child: _talkBoard()),
          );
        }
        return SingleChildScrollView(
          child: ContentFrame(
            maxWidth: 840,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (currentTopic.faceItem != null)
                      TierItemCard(item: currentTopic.faceItem!, size: 84),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.topic.category,
                            style: const TextStyle(
                              color: AppColors.purple,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.topic.title,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            context.l10n.format('participantsItems', {
                              'participants': widget.topic.participants,
                              'items': widget.topic.items.length,
                              'creator': widget.topic.creatorName,
                            }),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  widget.topic.description,
                  style: const TextStyle(height: 1.6),
                ),
                const SizedBox(height: 11),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    ActionChip(
                      avatar: Icon(
                        widget.appState.isTopicLiked(widget.topic.id)
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: widget.appState.isTopicLiked(widget.topic.id)
                            ? const Color(0xFFFF7186)
                            : null,
                        size: 18,
                      ),
                      label: Text(
                        context.l10n.format('likeCount', {
                          'count': currentTopic.likeCount,
                        }),
                      ),
                      onPressed: () =>
                          widget.appState.toggleTopicLike(widget.topic.id),
                    ),
                    for (final tag in widget.topic.tags)
                      ActionChip(
                        label: Text('#$tag'),
                        onPressed: () {
                          widget.onTagTap(tag);
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                _CommunityBoard(topic: currentTopic),
                const SizedBox(height: 18),
                PrimaryButton(
                  label: placed == 0
                      ? context.l10n.t('makeMine')
                      : placed == widget.topic.items.length
                      ? context.l10n.t('editMyTier')
                      : context.l10n.format('continueTier', {
                          'placed': placed,
                          'total': widget.topic.items.length,
                        }),
                  icon: Icons.dashboard_customize_rounded,
                  onPressed: _buildTier,
                ),
                const SizedBox(height: 32),
                _talkBoard(previewLimit: 3),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _CommunityBoard extends StatelessWidget {
  const _CommunityBoard({required this.topic});
  final TierTopic topic;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeader(
        title: context.l10n.t('communityTier'),
        subtitle: context.l10n.t('communityTierSubtitle'),
      ),
      const SizedBox(height: 12),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final rank in TierRank.values)
              TierRowView(
                rank: rank,
                items: topic.items
                    .where((item) => topic.community[item.id] == rank)
                    .toList(),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.call_split_rounded, color: Color(0xFFFFD166)),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.t('polarized'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.l10n.t('polarizedDescription'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _TalkBoard extends StatefulWidget {
  const _TalkBoard({
    required this.topic,
    required this.posts,
    required this.controller,
    required this.onPost,
    required this.onReply,
    required this.onReact,
    required this.onReport,
    this.previewLimit,
    this.onShowAll,
  });
  final TierTopic topic;
  final List<TalkPost> posts;
  final TextEditingController controller;
  final Future<void> Function() onPost;
  final Future<void> Function(
    TalkPost post,
    String? parentReplyId,
    String body,
    ReplyStance? stance,
  )
  onReply;
  final Future<void> Function(TalkPost post, String? replyId, bool positive)
  onReact;
  final Future<void> Function(TalkPost post, String? replyId) onReport;
  final int? previewLimit;
  final VoidCallback? onShowAll;

  @override
  State<_TalkBoard> createState() => _TalkBoardState();
}

class _TalkBoardState extends State<_TalkBoard> {
  String? _replyingToId;
  final Set<String> _expandedPostIds = {};

  @override
  Widget build(BuildContext context) {
    final visiblePosts = widget.previewLimit == null
        ? widget.posts
        : widget.posts.take(widget.previewLimit!).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: context.l10n.t('talk'),
          subtitle: context.l10n.t('boardSubtitle'),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              children: [
                TextField(
                  controller: widget.controller,
                  maxLines: 3,
                  minLines: 2,
                  decoration: InputDecoration(
                    hintText: context.l10n.t('commentHint'),
                  ),
                ),
                const SizedBox(height: 9),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: widget.onPost,
                    icon: const Icon(Icons.send_rounded, size: 17),
                    label: Text(context.l10n.t('post')),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (widget.posts.isEmpty)
          Card(
            child: EmptyState(
              title: context.l10n.t('noPosts'),
              message: context.l10n.t('noPostsMessage'),
              icon: Icons.forum_outlined,
            ),
          )
        else
          for (final post in visiblePosts)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                        child: Text(post.author.characters.first),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    post.author,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              post.body,
                              style: const TextStyle(height: 1.5),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 2,
                              runSpacing: 0,
                              children: [
                                Text(
                                  post.displayMinutesAgo == 0
                                      ? context.l10n.t('justNow')
                                      : context.l10n.format('minutesAgo', {
                                          'count': post.displayMinutesAgo,
                                        }),
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _ReactionButton(
                                  label: context.l10n.format('reactionLike', {
                                    'count': post.upvotes,
                                  }),
                                  onTap: post.id == null
                                      ? null
                                      : () => widget.onReact(post, null, true),
                                ),
                                _ReactionButton(
                                  label: context.l10n.format('reactionHmm', {
                                    'count': post.downvotes,
                                  }),
                                  onTap: post.id == null
                                      ? null
                                      : () => widget.onReact(post, null, false),
                                ),
                                TextButton.icon(
                                  onPressed: post.id == null
                                      ? null
                                      : () => setState(() {
                                          _replyingToId =
                                              _replyingToId == post.id
                                              ? null
                                              : post.id;
                                        }),
                                  icon: const Icon(
                                    Icons.reply_rounded,
                                    size: 15,
                                  ),
                                  label: Text(context.l10n.t('reply')),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    textStyle: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: post.id == null
                                      ? null
                                      : () => widget.onReport(post, null),
                                  icon: const Icon(
                                    Icons.flag_outlined,
                                    size: 14,
                                  ),
                                  label: Text(context.l10n.t('reportComment')),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    textStyle: const TextStyle(fontSize: 10),
                                  ),
                                ),
                              ],
                            ),
                            if (_replyingToId == post.id) ...[
                              const SizedBox(height: 7),
                              _ReplyComposer(
                                onSubmit: (body, stance) async {
                                  await widget.onReply(
                                    post,
                                    null,
                                    body,
                                    stance,
                                  );
                                  if (mounted) {
                                    setState(() => _replyingToId = null);
                                  }
                                },
                              ),
                            ],
                            if (post.replies.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              TextButton.icon(
                                onPressed: post.id == null
                                    ? null
                                    : () => setState(() {
                                        if (!_expandedPostIds.add(post.id!)) {
                                          _expandedPostIds.remove(post.id);
                                        }
                                      }),
                                icon: Icon(
                                  _expandedPostIds.contains(post.id)
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                ),
                                label: Text(
                                  _expandedPostIds.contains(post.id)
                                      ? context.l10n.t('hideReplies')
                                      : context.l10n.format('showReplies', {
                                          'count': post.replies.length,
                                        }),
                                ),
                              ),
                              if (_expandedPostIds.contains(post.id))
                                for (final reply in post.replies)
                                  _ReplyCard(
                                    reply: reply,
                                    onReply: (parentId, body, stance) => widget
                                        .onReply(post, parentId, body, stance),
                                    onReact: (replyId, positive) =>
                                        widget.onReact(post, replyId, positive),
                                    onReport: (replyId) =>
                                        widget.onReport(post, replyId),
                                  ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        if (widget.previewLimit != null &&
            widget.posts.length > widget.previewLimit!)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onShowAll,
              icon: const Icon(Icons.forum_outlined),
              label: Text(
                context.l10n.format('viewAllComments', {
                  'count': widget.posts.length,
                }),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReplyComposer extends StatefulWidget {
  const _ReplyComposer({required this.onSubmit});
  final Future<void> Function(String body, ReplyStance? stance) onSubmit;

  @override
  State<_ReplyComposer> createState() => _ReplyComposerState();
}

class _ReplyComposerState extends State<_ReplyComposer> {
  final _controller = TextEditingController();
  ReplyStance? _stance;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: AppColors.purple.withValues(alpha: .6)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.t('reply'),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 9),
        TextField(
          controller: _controller,
          autofocus: false,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(hintText: context.l10n.t('replyHint')),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StanceCheckbox(
              label: context.l10n.t('agree'),
              color: const Color(0xFF74E29B),
              checked: _stance == ReplyStance.agree,
              onChanged: (checked) =>
                  setState(() => _stance = checked ? ReplyStance.agree : null),
            ),
            _StanceCheckbox(
              label: context.l10n.t('object'),
              color: const Color(0xFFFF6B78),
              checked: _stance == ReplyStance.object,
              onChanged: (checked) =>
                  setState(() => _stance = checked ? ReplyStance.object : null),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: context.l10n.t('postReply'),
          icon: Icons.reply_rounded,
          onPressed: () async {
            final body = _controller.text.trim();
            if (body.isEmpty) return;
            await widget.onSubmit(body, _stance);
          },
        ),
      ],
    ),
  );
}

class _StanceCheckbox extends StatelessWidget {
  const _StanceCheckbox({
    required this.label,
    required this.color,
    required this.checked,
    required this.onChanged,
  });
  final String label;
  final Color color;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!checked),
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 13, 4),
      decoration: BoxDecoration(
        color: checked
            ? color.withValues(alpha: .16)
            : Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: checked ? color : Theme.of(context).colorScheme.outline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: checked,
            onChanged: (value) => onChanged(value ?? false),
            activeColor: color,
            checkColor: Colors.black,
            visualDensity: VisualDensity.compact,
          ),
          Text(
            label,
            style: TextStyle(
              color: checked ? color : null,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ReplyCard extends StatefulWidget {
  const _ReplyCard({
    required this.reply,
    required this.onReply,
    required this.onReact,
    required this.onReport,
    this.depth = 0,
  });
  final TalkReply reply;
  final Future<void> Function(String parentId, String body, ReplyStance? stance)
  onReply;
  final Future<void> Function(String replyId, bool positive) onReact;
  final Future<void> Function(String replyId) onReport;
  final int depth;

  @override
  State<_ReplyCard> createState() => _ReplyCardState();
}

class _ReplyCardState extends State<_ReplyCard> {
  bool _showComposer = false;
  bool _showReplies = false;

  @override
  Widget build(BuildContext context) {
    final reply = widget.reply;
    final stance = reply.stance;
    final color = stance == ReplyStance.agree
        ? const Color(0xFF74E29B)
        : const Color(0xFFFF6B78);
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: 7, left: widget.depth == 0 ? 0 : 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.outline,
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reply.author,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (stance != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: color),
                  ),
                  child: Text(
                    stance == ReplyStance.agree
                        ? context.l10n.t('agree')
                        : context.l10n.t('object'),
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(reply.body, style: const TextStyle(fontSize: 12, height: 1.45)),
          const SizedBox(height: 5),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 2,
            children: [
              _ReactionButton(
                label: context.l10n.format('reactionLike', {
                  'count': reply.upvotes,
                }),
                onTap: () => widget.onReact(reply.id, true),
              ),
              _ReactionButton(
                label: context.l10n.format('reactionHmm', {
                  'count': reply.downvotes,
                }),
                onTap: () => widget.onReact(reply.id, false),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _showComposer = !_showComposer;
                }),
                icon: const Icon(Icons.reply_rounded, size: 14),
                label: Text(context.l10n.t('reply')),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 10),
                ),
              ),
              TextButton.icon(
                onPressed: () => widget.onReport(reply.id),
                icon: const Icon(Icons.flag_outlined, size: 13),
                label: Text(context.l10n.t('reportComment')),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
          if (_showComposer) ...[
            const SizedBox(height: 6),
            _ReplyComposer(
              onSubmit: (body, stance) async {
                await widget.onReply(reply.id, body, stance);
                if (mounted) setState(() => _showComposer = false);
              },
            ),
          ],
          if (reply.replies.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () => setState(() => _showReplies = !_showReplies),
              icon: Icon(
                _showReplies
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 16,
              ),
              label: Text(
                _showReplies
                    ? context.l10n.t('hideReplies')
                    : context.l10n.format('showReplies', {
                        'count': reply.replies.length,
                      }),
              ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 10),
              ),
            ),
            if (_showReplies)
              for (final child in reply.replies)
                _ReplyCard(
                  reply: child,
                  depth: widget.depth + 1,
                  onReply: widget.onReply,
                  onReact: widget.onReact,
                  onReport: widget.onReport,
                ),
          ],
        ],
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      minimumSize: const Size(0, 30),
      textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
    ),
    child: Text(label, softWrap: false),
  );
}
