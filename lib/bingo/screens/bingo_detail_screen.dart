import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/app_breakpoints.dart';
import '../bingo_app.dart';
import '../domain/bingo_logic.dart';
import '../l10n/bingo_localizations.dart';
import '../models/bingo_models.dart';
import '../repositories/bingo_repository.dart';
import '../services/bingo_state.dart';
import '../theme/bingo_theme.dart';
import '../widgets/bingo_widgets.dart';

class BingoDetailScreen extends StatefulWidget {
  const BingoDetailScreen({
    super.key,
    required this.state,
    required this.boardId,
  });

  final BingoState state;
  final String boardId;

  @override
  State<BingoDetailScreen> createState() => _BingoDetailScreenState();
}

enum _LoadStatus { loading, ready, missing, failed }

class _BingoDetailScreenState extends State<BingoDetailScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  final _commentField = TextEditingController();
  final _commentFocus = FocusNode();
  final _composerKey = GlobalKey();
  _LoadStatus _status = _LoadStatus.loading;
  bool _attachResult = true;
  bool _posting = false;

  BingoState get state => widget.state;
  BingoBoard? get _board => state.cachedBoard(widget.boardId);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && _tabs.index == 1) _refreshBoard();
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _commentField.dispose();
    _commentFocus.dispose();
    state.flushEntry(widget.boardId);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _status = _LoadStatus.loading);
    // Wait for preferences so the local user id and language are known.
    if (!state.initialized) await state.initialize();
    try {
      final board = await state.loadBoard(widget.boardId);
      if (!mounted) return;
      if (board == null) {
        setState(() => _status = _LoadStatus.missing);
        return;
      }
      setState(() => _status = _LoadStatus.ready);
      await state.loadComments(widget.boardId);
    } on Object {
      if (mounted && _board == null) {
        setState(() => _status = _LoadStatus.failed);
      } else if (mounted) {
        setState(() => _status = _LoadStatus.ready);
      }
    }
  }

  Future<void> _refreshBoard() async {
    await state.flushEntry(widget.boardId);
    try {
      await state.loadBoard(widget.boardId);
    } on Object {
      // Keep showing cached stats.
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  String get _shareUrl =>
      '${Uri.base.origin}${BingoRoutes.board(state.locale, widget.boardId)}';

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _shareUrl));
    if (mounted) _snack(context.bingo.t('copied'));
  }

  Future<void> _copyResult(BingoBoard board, BingoEntry entry) async {
    final strings = context.bingo;
    final lines = BingoLogic.lineCount(board.size, entry.layout, entry.marked);
    final text = [
      strings.format('shareText', {'title': board.title, 'lines': lines}),
      BingoLogic.emojiGrid(board.size, entry.layout, entry.marked),
      _shareUrl,
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _snack(strings.t('copied'));
  }

  Future<void> _join(BingoBoard board) async {
    try {
      await state.join(board);
      if (mounted) _snack(context.bingo.t('joined'));
    } on Object {
      if (mounted) _snack(context.bingo.t('actionFailed'));
    }
  }

  Future<void> _toggleLike(BingoBoard board) async {
    try {
      await state.toggleBoardLike(board);
    } on BingoException catch (error) {
      if (mounted) _snack(context.bingo.t(error.localizationKey));
    } on Object {
      if (mounted) _snack(context.bingo.t('actionFailed'));
    }
  }

  Future<void> _react(
    BingoBoard board,
    BingoComment comment,
    BingoReaction reaction,
  ) async {
    try {
      await state.toggleReaction(board, comment, reaction);
    } on BingoException catch (error) {
      if (mounted) _snack(context.bingo.t(error.localizationKey));
    } on Object {
      if (mounted) _snack(context.bingo.t('actionFailed'));
    }
  }

  void _tap(BingoBoard board, int position) {
    final result = state.toggleMark(board, position);
    if (result.linesAfter > result.linesBefore) {
      HapticFeedback.mediumImpact();
      _celebrate(result.linesAfter);
    }
  }

  Future<void> _celebrate(int lines) async {
    final strings = context.bingo;
    final share = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [BingoColors.primary, BingoColors.gold],
                ).createShader(bounds),
                child: Text(
                  strings.t('bingoCelebrate'),
                  style: const TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                strings.count('bingoCelebrateBody', lines),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const ValueKey('celebrate-share'),
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: Text(strings.t('shareToComments')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(strings.t('close')),
              ),
            ],
          ),
        ),
      ),
    );
    if (share == true && mounted) _focusComposer();
  }

  void _focusComposer() {
    setState(() => _attachResult = true);
    _tabs.animateTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final composer = _composerKey.currentContext;
      if (composer != null) {
        Scrollable.ensureVisible(
          composer,
          duration: const Duration(milliseconds: 300),
          alignment: .2,
        );
      }
      _commentFocus.requestFocus();
    });
  }

  Future<void> _resetMarks(BingoBoard board) async {
    final confirmed = await _confirm(context.bingo.t('resetMarksConfirm'));
    if (confirmed) await state.resetMarks(board);
  }

  Future<bool> _confirm(String message, {String? action}) async {
    final strings = context.bingo;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(strings.t('cancel')),
              ),
              FilledButton(
                key: const ValueKey('confirm-action'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action ?? strings.t('ok')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _post(BingoBoard board) async {
    final strings = context.bingo;
    final body = _commentField.text.trim();
    final attach = _attachResult && state.entryFor(board.id) != null;
    if (body.isEmpty && !attach) {
      _snack(strings.t('commentEmpty'));
      return;
    }
    setState(() => _posting = true);
    try {
      await state.postComment(board, body: body, attachResult: attach);
      _commentField.clear();
      if (mounted) _snack(strings.t('commentPosted'));
    } on BingoException catch (error) {
      if (mounted) {
        _snack(
          strings.t(
            error.failure == BingoFailure.network
                ? 'commentFailed'
                : error.localizationKey,
          ),
        );
      }
    } on Object {
      if (mounted) _snack(strings.t('commentFailed'));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _report(
    BingoBoard board, {
    required String targetType,
    required String targetId,
  }) async {
    final strings = context.bingo;
    if (!await _confirm(
      strings.t('reportConfirm'),
      action: strings.t('report'),
    )) {
      return;
    }
    try {
      final reported = await state.report(
        board,
        targetType: targetType,
        targetId: targetId,
      );
      if (mounted) {
        _snack(strings.t(reported ? 'reported' : 'alreadyReported'));
      }
    } on Object {
      if (mounted) _snack(strings.t('actionFailed'));
    }
  }

  Future<void> _ownerAction(BingoBoard board, String action) async {
    final strings = context.bingo;
    try {
      switch (action) {
        case 'toggle-public':
          await state.setBoardPublic(board, !board.isPublic);
          if (mounted) _snack(strings.t('saved'));
        case 'delete':
          if (!await _confirm(
            strings.t('deleteBoardConfirm'),
            action: strings.t('delete'),
          )) {
            return;
          }
          await state.deleteBoard(board);
          if (!mounted) return;
          _snack(strings.t('deleted'));
          Navigator.of(context).pushNamedAndRemoveUntil(
            BingoRoutes.home(state.locale),
            (_) => false,
          );
        case 'report':
          await _report(board, targetType: 'bingo', targetId: board.id);
      }
    } on Object {
      if (mounted) _snack(strings.t('actionFailed'));
    }
  }

  void _goHome() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed(BingoRoutes.home(state.locale));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final strings = context.bingo;
      final board = _board;
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: strings.t('backHome'),
            onPressed: _goHome,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: board == null
              ? const BingoBrandMark()
              : Text(
                  board.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
          actions: [
            if (board != null && !board.isSample)
              IconButton(
                key: const ValueKey('copy-link'),
                tooltip: strings.t('copyLink'),
                onPressed: _copyLink,
                icon: const Icon(Icons.link_rounded),
              ),
            if (board != null && !board.isSample)
              PopupMenuButton<String>(
                key: const ValueKey('board-menu'),
                onSelected: (action) => _ownerAction(board, action),
                itemBuilder: (_) => state.isOwner(board)
                    ? [
                        PopupMenuItem(
                          value: 'toggle-public',
                          child: Text(
                            strings.t(
                              board.isPublic ? 'makePrivate' : 'makePublic',
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(strings.t('deleteBoard')),
                        ),
                      ]
                    : [
                        PopupMenuItem(
                          value: 'report',
                          child: Text(strings.t('report')),
                        ),
                      ],
              ),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1),
          ),
        ),
        body: switch (_status) {
          _LoadStatus.loading when board == null => const Center(
            child: CircularProgressIndicator(),
          ),
          _LoadStatus.missing => _Message(
            icon: Icons.search_off_rounded,
            title: strings.t('notFound'),
            body: strings.t('notFoundBody'),
            action: FilledButton(
              onPressed: _goHome,
              child: Text(strings.t('backHome')),
            ),
          ),
          _LoadStatus.failed when board == null => _Message(
            icon: Icons.wifi_off_rounded,
            title: strings.t('loadFailed'),
            action: FilledButton(
              onPressed: _load,
              child: Text(strings.t('retry')),
            ),
          ),
          _ => _content(board!),
        },
      );
    },
  );

  Widget _content(BingoBoard board) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = AppBreakpoints.isDesktop(constraints.maxWidth);
      final cardPanel = _CardPanel(
        board: board,
        entry: state.entryFor(board.id),
        onJoin: () => _join(board),
        onTap: (position) => _tap(board, position),
        onCopyResult: (entry) => _copyResult(board, entry),
        onShareToComments: _focusComposer,
        onReset: () => _resetMarks(board),
      );
      final tabsPanel = _tabsPanel(board);
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(top: 18, bottom: 48),
          children: [
            BingoFrame(
              maxWidth: 1180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    board: board,
                    liked: state.isLiked(board.id),
                    onLike: () => _toggleLike(board),
                  ),
                  const SizedBox(height: 18),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 520, child: cardPanel),
                        const SizedBox(width: 24),
                        Expanded(child: tabsPanel),
                      ],
                    )
                  else ...[
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: cardPanel,
                      ),
                    ),
                    const SizedBox(height: 24),
                    tabsPanel,
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _tabsPanel(BingoBoard board) {
    final strings = context.bingo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabs,
          tabs: [
            Tab(
              text:
                  '${strings.t('tabComments')} (${state.commentsFor(board.id).length})',
            ),
            Tab(text: strings.t('tabStats')),
          ],
        ),
        const SizedBox(height: 14),
        AnimatedBuilder(
          animation: _tabs,
          builder: (context, _) =>
              _tabs.index == 0 ? _comments(board) : _StatsPanel(board: board),
        ),
      ],
    );
  }

  Widget _comments(BingoBoard board) {
    final strings = context.bingo;
    final entry = state.entryFor(board.id);
    final comments = state.commentsFor(board.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          key: _composerKey,
          color: BingoColors.surface,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('comment-field'),
                  controller: _commentField,
                  focusNode: _commentFocus,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: BingoComment.maxLength,
                  decoration: InputDecoration(
                    hintText: strings.t('commentHint'),
                    fillColor: Colors.white,
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        key: const ValueKey('attach-result'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: entry != null && _attachResult,
                        onChanged: entry == null
                            ? null
                            : (value) => setState(
                                () => _attachResult = value ?? false,
                              ),
                        title: Text(
                          strings.t(
                            entry == null
                                ? 'attachResultDisabled'
                                : 'attachResult',
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    FilledButton(
                      key: const ValueKey('post-comment'),
                      onPressed: _posting ? null : () => _post(board),
                      child: Text(strings.t('post')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              strings.t('noComments'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: BingoColors.inkMuted),
            ),
          )
        else
          for (final comment in comments)
            _CommentTile(
              key: ValueKey('comment-${comment.id}'),
              board: board,
              comment: comment,
              canDelete: state.canDeleteComment(board, comment),
              reported: state.hasReported('comment', comment.id),
              myReaction: state.reactionFor(board.id, comment.id),
              onReact: (reaction) => _react(board, comment, reaction),
              onDelete: () async {
                if (!await _confirm(
                  strings.t('deleteCommentConfirm'),
                  action: strings.t('delete'),
                )) {
                  return;
                }
                try {
                  await state.deleteComment(board, comment);
                } on Object {
                  if (mounted) _snack(strings.t('actionFailed'));
                }
              },
              onReport: () =>
                  _report(board, targetType: 'comment', targetId: comment.id),
            ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: BingoEmptyState(
        icon: icon,
        title: title,
        body: body,
        action: action,
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.board,
    required this.liked,
    required this.onLike,
  });

  final BingoBoard board;
  final bool liked;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final strings = context.bingo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            BingoBadge(
              label: strings.format('sizeLabel', {'size': board.size}),
              background: BingoColors.blueSoft,
              foreground: BingoColors.blue,
            ),
            if (board.isSample) BingoBadge(label: strings.t('sampleBadge')),
            if (!board.isPublic) BingoBadge(label: strings.t('privateBadge')),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          board.title,
          key: const ValueKey('board-title'),
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          [
            strings.format('byCreator', {'name': board.creatorName}),
            if (board.createdAt != null) strings.relativeTime(board.createdAt),
          ].join(' · '),
          style: const TextStyle(color: BingoColors.inkMuted, fontSize: 13),
        ),
        if (board.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(board.description, style: const TextStyle(height: 1.5)),
        ],
        if (board.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final tag in board.tags)
                Text(
                  '#$tag',
                  style: const TextStyle(
                    color: BingoColors.blue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            StatPill(
              icon: Icons.people_alt_outlined,
              label: strings.count('participantsCount', board.participants),
            ),
            StatPill(
              icon: Icons.emoji_events_outlined,
              label: strings.count('bingoCount', board.bingoCount),
            ),
            StatPill(
              icon: Icons.chat_bubble_outline_rounded,
              label: strings.count('commentsCount', board.commentCount),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('like-button'),
            onPressed: onLike,
            style: OutlinedButton.styleFrom(
              foregroundColor: liked ? BingoColors.like : BingoColors.ink,
              backgroundColor: liked ? BingoColors.likeSoft : null,
              side: BorderSide(
                color: liked ? BingoColors.like : BingoColors.outline,
              ),
              shape: const StadiumBorder(),
            ),
            icon: Icon(
              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 20,
            ),
            label: Text(
              '${strings.t('likeAction')}  ${board.likeCount}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

class _CardPanel extends StatelessWidget {
  const _CardPanel({
    required this.board,
    required this.entry,
    required this.onJoin,
    required this.onTap,
    required this.onCopyResult,
    required this.onShareToComments,
    required this.onReset,
  });

  final BingoBoard board;
  final BingoEntry? entry;
  final VoidCallback onJoin;
  final ValueChanged<int> onTap;
  final ValueChanged<BingoEntry> onCopyResult;
  final VoidCallback onShareToComments;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final strings = context.bingo;
    final entry = this.entry;
    if (entry == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: BingoColors.outline),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.t('cardPreview'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Stack(
              children: [
                Opacity(
                  opacity: .45,
                  child: IgnorePointer(
                    child: BingoCardGrid(
                      board: board,
                      layout: BingoLogic.previewLayout(board, 0),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('join-button'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(220, 56),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          onPressed: onJoin,
                          icon: const Icon(Icons.style_rounded),
                          label: Text(strings.t('join')),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            strings.t('joinHelp'),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final marks = BingoLogic.effectiveMarks(entry.layout, entry.marked);
    final lines = BingoLogic.completedLines(board.size, marks).length;
    final reach = BingoLogic.reachPositions(board.size, marks).isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: lines > 0 ? const Color(0xFFFFFCF2) : Colors.white,
        border: Border.all(
          color: lines > 0 ? BingoColors.gold : BingoColors.outline,
          width: lines > 0 ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                strings.t('yourCard'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              if (lines > 0)
                BingoBadge(
                  key: const ValueKey('lines-badge'),
                  label: strings.count('bingoLines', lines),
                  background: BingoColors.gold,
                  foreground: Colors.white,
                )
              else if (reach)
                BingoBadge(
                  label: strings.t('reachLabel'),
                  background: BingoColors.blueSoft,
                  foreground: BingoColors.blue,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${strings.t('tapToMark')} · ${strings.count('markedCount', entry.marked.length)}',
            style: const TextStyle(color: BingoColors.inkMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          BingoCardGrid(
            key: const ValueKey('player-card'),
            board: board,
            layout: entry.layout,
            marked: entry.marked,
            showReach: true,
            onTapSquare: onTap,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey('share-to-comments'),
                onPressed: onShareToComments,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: Text(strings.t('shareToComments')),
              ),
              OutlinedButton.icon(
                key: const ValueKey('copy-result'),
                onPressed: () => onCopyResult(entry),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(strings.t('copyResult')),
              ),
              TextButton.icon(
                onPressed: entry.marked.isEmpty ? null : onReset,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: Text(strings.t('resetMarks')),
              ),
            ],
          ),
          if (board.cells.any((cell) => cell.imageCredit != null)) ...[
            const SizedBox(height: 6),
            Text(
              strings.t('appleNotice'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10.5,
                color: BingoColors.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    super.key,
    required this.board,
    required this.comment,
    required this.canDelete,
    required this.reported,
    required this.onDelete,
    required this.onReport,
    required this.onReact,
    this.myReaction,
  });

  final BingoBoard board;
  final BingoComment comment;
  final bool canDelete;
  final bool reported;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final ValueChanged<BingoReaction> onReact;
  final String? myReaction;

  @override
  Widget build(BuildContext context) {
    final strings = context.bingo;
    final result = comment.result;
    final name = comment.authorName.isEmpty
        ? strings.t('guest')
        : comment.authorName;
    final hidden = comment.hidden || reported;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        border: Border.all(color: BingoColors.outline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: BingoColors.primarySoft,
            foregroundColor: BingoColors.primary,
            child: Text(
              name.characters.first.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      strings.relativeTime(comment.createdAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: BingoColors.inkMuted,
                      ),
                    ),
                    if (result != null && result.lines > 0 && !hidden) ...[
                      const SizedBox(width: 8),
                      BingoBadge(
                        label: strings.count('bingoLines', result.lines),
                        background: BingoColors.goldSoft,
                        foreground: const Color(0xFF8A5A00),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                if (hidden)
                  Text(
                    strings.t('hiddenComment'),
                    style: const TextStyle(
                      color: BingoColors.inkMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else ...[
                  if (comment.body.isNotEmpty)
                    Text(comment.body, style: const TextStyle(height: 1.45)),
                  if (result != null &&
                      result.layout.length == board.squareCount) ...[
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: IgnorePointer(
                        child: BingoCardGrid(
                          board: board,
                          layout: result.layout,
                          marked: result.marked,
                          compact: true,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final reaction in BingoReaction.values)
                        _ReactionChip(
                          key: ValueKey(
                            'reaction-${comment.id}-${reaction.id}',
                          ),
                          reaction: reaction,
                          count: comment.reactionCounts[reaction.id] ?? 0,
                          selected: myReaction == reaction.id,
                          onTap: () => onReact(reaction),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            iconSize: 18,
            onSelected: (value) => value == 'delete' ? onDelete() : onReport(),
            itemBuilder: (_) => [
              if (canDelete)
                PopupMenuItem(
                  value: 'delete',
                  child: Text(strings.t('deleteComment')),
                ),
              if (!reported && !canDelete)
                PopupMenuItem(
                  value: 'report',
                  child: Text(strings.t('report')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.board});

  final BingoBoard board;

  @override
  Widget build(BuildContext context) {
    final strings = context.bingo;
    if (board.participants == 0) {
      return BingoEmptyState(
        icon: Icons.insights_rounded,
        title: strings.t('statsEmpty'),
      );
    }
    final ranking = BingoLogic.ranking(board).take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _StatBox(
              label: strings.t('statsParticipants'),
              value: '${board.participants}',
            ),
            const SizedBox(width: 8),
            _StatBox(
              label: strings.t('statsBingo'),
              value: '${board.bingoCount}',
            ),
            const SizedBox(width: 8),
            _StatBox(
              label: strings.t('statsRate'),
              value: '${(board.bingoRate * 100).round()}%',
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          strings.t('statsRanking'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        for (final (index, row) in ranking.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: index < 3
                          ? BingoColors.primary
                          : BingoColors.inkMuted,
                    ),
                  ),
                ),
                SizedBox.square(
                  dimension: 44,
                  child: BingoSquare(
                    cell: board.cells[row.cell],
                    isFree: false,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        board.cells[row.cell].text ??
                            board.cells[row.cell].imageCredit ??
                            '#${row.cell + 1}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: row.rate,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(99),
                        backgroundColor: BingoColors.surfaceStrong,
                        color: BingoColors.marked,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(row.rate * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: BingoColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: BingoColors.inkMuted),
          ),
        ],
      ),
    ),
  );
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    super.key,
    required this.reaction,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final BingoReaction reaction;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? BingoColors.primarySoft : BingoColors.surface,
    shape: StadiumBorder(
      side: BorderSide(
        color: selected ? BingoColors.primary : BingoColors.outline,
      ),
    ),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(reaction.emoji, style: const TextStyle(fontSize: 15)),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? BingoColors.primary : BingoColors.inkMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
