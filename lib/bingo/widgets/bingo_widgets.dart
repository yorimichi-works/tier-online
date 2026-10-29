import 'dart:convert';

import 'package:flutter/material.dart';

import '../domain/bingo_logic.dart';
import '../l10n/bingo_localizations.dart';
import '../models/bingo_models.dart';
import '../theme/bingo_theme.dart';

/// Centered max-width column, like tier-online's ContentFrame.
class BingoFrame extends StatelessWidget {
  const BingoFrame({
    super.key,
    required this.child,
    this.maxWidth = 1080,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  /// Always as wide as possible (up to [maxWidth]) so stacked frames line up.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Align(
      alignment: alignment,
      child: SizedBox(
        width: constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(0, maxWidth).toDouble()
            : maxWidth,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

/// Renders `data:` (unpublished uploads), bundled assets and network images.
class BingoImage extends StatefulWidget {
  const BingoImage({super.key, required this.url, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  State<BingoImage> createState() => _BingoImageState();
}

class _BingoImageState extends State<BingoImage> {
  static const _maxRetries = 2;
  int _attempt = 0;

  @override
  void didUpdateWidget(BingoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _attempt = 0;
  }

  /// Flutter caches a failed network image, so a single dropped request
  /// would leave the square broken until reload. Evict and retry a few times.
  void _retryLater() {
    if (_attempt >= _maxRetries) return;
    final attempt = _attempt;
    Future<void>.delayed(Duration(seconds: 1 + attempt * 2), () async {
      if (!mounted || _attempt != attempt) return;
      await NetworkImage(widget.url).evict();
      if (mounted) setState(() => _attempt++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    final fit = widget.fit;
    Widget fallback(BuildContext context, Object error, StackTrace? stack) =>
        const ColoredBox(
          color: BingoColors.surfaceStrong,
          child: Center(
            child: Icon(Icons.image_not_supported_outlined, size: 18),
          ),
        );
    if (url.startsWith('data:')) {
      try {
        return Image.memory(
          base64Decode(url.substring(url.indexOf(',') + 1)),
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: fallback,
        );
      } on FormatException {
        return fallback(context, const FormatException(), null);
      }
    }
    if (url.startsWith('assets/')) {
      return Image.asset(url, fit: fit, errorBuilder: fallback);
    }
    return Image.network(
      url,
      key: ValueKey('$url#$_attempt'),
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) {
        _retryLater();
        return fallback(context, error, stack);
      },
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const ColoredBox(color: BingoColors.surface),
    );
  }
}

/// Visual state of one square on a card.
enum SquareState { plain, marked, inLine, reach }

class BingoSquare extends StatelessWidget {
  const BingoSquare({
    super.key,
    required this.cell,
    required this.isFree,
    this.state = SquareState.plain,
    this.onTap,
    this.compact = false,
    this.semanticsLabel,
  });

  final BingoCell? cell;
  final bool isFree;
  final SquareState state;
  final VoidCallback? onTap;

  /// Compact squares (comment thumbnails) hide text when an image exists.
  final bool compact;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final extent = constraints.maxWidth;
      final marked = state == SquareState.marked || state == SquareState.inLine;
      final radius = BorderRadius.circular(extent < 40 ? 4 : 10);
      final hasImage = cell?.hasImage ?? false;
      final text = isFree ? context.bingo.t('free') : cell?.text?.trim() ?? '';
      final fontSize = (extent / (text.length > 14 ? 7.2 : 5.6)).clamp(
        7.0,
        17.0,
      );
      final background = isFree
          ? BingoColors.goldSoft
          : state == SquareState.inLine
          ? BingoColors.goldSoft
          : marked
          ? BingoColors.primarySoft
          : Colors.white;
      final borderColor = state == SquareState.inLine
          ? BingoColors.line
          : marked
          ? BingoColors.marked
          : state == SquareState.reach
          ? BingoColors.blue
          : BingoColors.outline;

      final content = Stack(
        fit: StackFit.expand,
        children: [
          if (hasImage && !isFree)
            Opacity(
              opacity: marked ? .55 : 1,
              child: BingoImage(url: cell!.imageUrl!),
            ),
          // Stamp ring sits under the text so the square stays readable.
          if (marked && !isFree)
            IgnorePointer(
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: .78,
                  heightFactor: .78,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            (state == SquareState.inLine
                                    ? BingoColors.line
                                    : BingoColors.marked)
                                .withValues(alpha: .45),
                        width: (extent / 14).clamp(1.5, 5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (text.isNotEmpty && !(compact && hasImage))
            Align(
              alignment: hasImage ? Alignment.bottomCenter : Alignment.center,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: extent < 50 ? 2 : 5,
                  vertical: hasImage ? 2 : 4,
                ),
                color: hasImage ? Colors.white.withValues(alpha: .86) : null,
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  maxLines: hasImage ? 2 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: hasImage ? fontSize * .82 : fontSize,
                    height: 1.15,
                    fontWeight: isFree ? FontWeight.w900 : FontWeight.w700,
                    color: isFree ? const Color(0xFF8A5A00) : BingoColors.ink,
                  ),
                ),
              ),
            ),
        ],
      );

      return Semantics(
        button: onTap != null,
        selected: marked,
        label: semanticsLabel ?? text,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: background,
            borderRadius: radius,
            border: Border.all(
              color: borderColor,
              width: state == SquareState.plain ? 1 : (extent < 40 ? 1.5 : 2.4),
            ),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap, child: content),
            ),
          ),
        ),
      );
    },
  );
}

/// A square bingo card. [marked] are card positions; FREE is implicit.
class BingoCardGrid extends StatelessWidget {
  const BingoCardGrid({
    super.key,
    required this.board,
    required this.layout,
    this.marked = const {},
    this.onTapSquare,
    this.compact = false,
    this.showReach = false,
  });

  final BingoBoard board;
  final List<int> layout;
  final Set<int> marked;
  final ValueChanged<int>? onTapSquare;
  final bool compact;
  final bool showReach;

  @override
  Widget build(BuildContext context) {
    final size = board.size;
    final marks = BingoLogic.effectiveMarks(layout, marked);
    final inLine = {
      for (final line in BingoLogic.completedLines(size, marks)) ...line,
    };
    final reach = showReach
        ? BingoLogic.reachPositions(size, marks)
        : const <int>{};
    // Every square gets the same half-gap on all sides, so equal Expanded
    // shares stay exactly square inside the AspectRatio.
    final halfGap = compact ? 1.0 : 3.0;
    return AspectRatio(
      aspectRatio: 1,
      child: Column(
        children: [
          for (var row = 0; row < size; row++)
            Expanded(
              child: Row(
                children: [
                  for (var column = 0; column < size; column++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(halfGap),
                        child: _square(
                          row * size + column,
                          marks,
                          inLine,
                          reach,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _square(
    int position,
    Set<int> marks,
    Set<int> inLine,
    Set<int> reach,
  ) {
    final cellIndex = position < layout.length
        ? layout[position]
        : BingoEntry.free;
    final isFree = cellIndex == BingoEntry.free;
    final cell = !isFree && cellIndex < board.cells.length
        ? board.cells[cellIndex]
        : null;
    return BingoSquare(
      key: ValueKey('square-$position'),
      cell: cell,
      isFree: isFree,
      compact: compact,
      state: isFree
          ? SquareState.plain
          : inLine.contains(position)
          ? SquareState.inLine
          : marks.contains(position)
          ? SquareState.marked
          : reach.contains(position)
          ? SquareState.reach
          : SquareState.plain,
      onTap: isFree || onTapSquare == null
          ? null
          : () => onTapSquare!(position),
    );
  }
}

class StatPill extends StatelessWidget {
  const StatPill({
    super.key,
    required this.icon,
    required this.label,
    this.color = BingoColors.inkMuted,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class BingoBadge extends StatelessWidget {
  const BingoBadge({
    super.key,
    required this.label,
    this.background = BingoColors.surfaceStrong,
    this.foreground = BingoColors.inkMuted,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: foreground,
      ),
    ),
  );
}

/// Board card used on home and "My Bingo".
class BingoBoardTile extends StatelessWidget {
  const BingoBoardTile({
    super.key,
    required this.board,
    required this.onTap,
    this.entry,
    this.onTagTap,
  });

  final BingoBoard board;
  final BingoEntry? entry;
  final VoidCallback onTap;
  final ValueChanged<String>? onTagTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.bingo;
    final previewLayout = entry?.layout ?? BingoLogic.previewLayout(board, 0);
    final lines = entry == null
        ? 0
        : BingoLogic.lineCount(board.size, entry!.layout, entry!.marked);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: IgnorePointer(
                  child: BingoCardGrid(
                    board: board,
                    layout: previewLayout,
                    marked: entry?.marked ?? const {},
                    compact: true,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        BingoBadge(
                          label: strings.format('sizeLabel', {
                            'size': board.size,
                          }),
                          background: BingoColors.blueSoft,
                          foreground: BingoColors.blue,
                        ),
                        if (board.isSample)
                          BingoBadge(label: strings.t('sampleBadge')),
                        if (!board.isPublic)
                          BingoBadge(label: strings.t('privateBadge')),
                        if (lines > 0)
                          BingoBadge(
                            label: strings.count('bingoLines', lines),
                            background: BingoColors.goldSoft,
                            foreground: const Color(0xFF8A5A00),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      board.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      strings.format('byCreator', {'name': board.creatorName}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: BingoColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        StatPill(
                          icon: Icons.people_alt_outlined,
                          label: strings.count(
                            'participantsCount',
                            board.participants,
                          ),
                        ),
                        StatPill(
                          icon: Icons.emoji_events_outlined,
                          label: strings.count('bingoCount', board.bingoCount),
                        ),
                        StatPill(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: strings.count(
                            'commentsCount',
                            board.commentCount,
                          ),
                        ),
                      ],
                    ),
                    if (board.tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          for (final tag in board.tags)
                            InkWell(
                              onTap: onTagTap == null
                                  ? null
                                  : () => onTagTap!(tag),
                              child: Text(
                                '#$tag',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: BingoColors.blue,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BingoEmptyState extends StatelessWidget {
  const BingoEmptyState({
    super.key,
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
    child: Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: BingoColors.primarySoft,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: BingoColors.primary, size: 30),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        if (body != null) ...[
          const SizedBox(height: 6),
          Text(
            body!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: BingoColors.inkMuted),
          ),
        ],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

/// Bingo Online wordmark: a 3×3 mini card next to the service name.
class BingoBrandMark extends StatelessWidget {
  const BingoBrandMark({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox.square(
        dimension: 28,
        child: GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var index = 0; index < 9; index++)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const {0, 4, 8}.contains(index)
                      ? BingoColors.primary
                      : index == 2 || index == 6
                      ? BingoColors.gold
                      : BingoColors.surfaceStrong,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(width: 10),
      Text(
        context.bingo.t('appName'),
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w900,
          letterSpacing: -.2,
        ),
      ),
    ],
  );
}
