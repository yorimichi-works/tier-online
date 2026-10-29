import 'dart:math';

import '../models/bingo_models.dart';

/// Pure bingo rules shared by the UI, local storage and tests. The Cloud
/// Functions mirror (`functions/src/bingo.ts`) must stay behaviorally identical.
abstract final class BingoLogic {
  /// FNV-1a (32-bit). Stable across platforms, unlike [String.hashCode].
  static int seedOf(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  /// Builds a participant's card. With [BingoBoard.shufflePerPlayer] the pool
  /// is shuffled with a seed derived from board and user, so reopening the
  /// board on another device reproduces the same card.
  static List<int> generateLayout(BingoBoard board, String userId) {
    final pool = List<int>.generate(board.cells.length, (index) => index);
    if (board.shufflePerPlayer) {
      pool.shuffle(Random(seedOf('${board.id}:$userId')));
    }
    final picked = pool.take(board.requiredCells).toList();
    final layout = <int>[];
    var next = 0;
    for (var position = 0; position < board.squareCount; position++) {
      if (position == board.freePosition) {
        layout.add(BingoEntry.free);
      } else {
        layout.add(next < picked.length ? picked[next++] : BingoEntry.free);
      }
    }
    return layout;
  }

  /// A preview shuffle for the creator, independent of any participant.
  static List<int> previewLayout(BingoBoard board, int seed) =>
      generateLayout(board, 'preview-$seed');

  /// Marked positions including FREE squares.
  static Set<int> effectiveMarks(List<int> layout, Set<int> marked) => {
    ...marked.where((position) => position >= 0 && position < layout.length),
    for (var position = 0; position < layout.length; position++)
      if (layout[position] == BingoEntry.free) position,
  };

  /// Every row, column and both diagonals as lists of card positions.
  static List<List<int>> allLines(int size) => [
    for (var row = 0; row < size; row++)
      [for (var column = 0; column < size; column++) row * size + column],
    for (var column = 0; column < size; column++)
      [for (var row = 0; row < size; row++) row * size + column],
    [for (var index = 0; index < size; index++) index * size + index],
    [
      for (var index = 0; index < size; index++)
        index * size + size - 1 - index,
    ],
  ];

  static List<List<int>> completedLines(int size, Set<int> marks) => [
    for (final line in allLines(size))
      if (line.every(marks.contains)) line,
  ];

  static int lineCount(int size, List<int> layout, Set<int> marked) =>
      completedLines(size, effectiveMarks(layout, marked)).length;

  /// Positions that are one mark away from completing a line ("reach").
  static Set<int> reachPositions(int size, Set<int> marks) {
    final result = <int>{};
    for (final line in allLines(size)) {
      final missing = line.where((position) => !marks.contains(position));
      if (missing.length == 1) result.add(missing.first);
    }
    return result;
  }

  static BingoResultSnapshot snapshotOf(BingoBoard board, BingoEntry entry) =>
      BingoResultSnapshot(
        size: board.size,
        layout: entry.layout,
        marked: Set.unmodifiable(entry.marked),
        lines: lineCount(board.size, entry.layout, entry.marked),
      );

  /// Wordle-style emoji grid for sharing outside the app.
  static String emojiGrid(int size, List<int> layout, Set<int> marked) {
    final marks = effectiveMarks(layout, marked);
    final inLine = {for (final line in completedLines(size, marks)) ...line};
    final buffer = StringBuffer();
    for (var row = 0; row < size; row++) {
      for (var column = 0; column < size; column++) {
        final position = row * size + column;
        buffer.write(
          layout[position] == BingoEntry.free
              ? '⭐'
              : inLine.contains(position)
              ? '🟧'
              : marks.contains(position)
              ? '🟦'
              : '⬜',
        );
      }
      if (row < size - 1) buffer.writeln();
    }
    return buffer.toString();
  }

  /// Local equivalent of the server aggregation (`aggregateBingo`).
  static BingoBoard aggregate(BingoBoard board, Iterable<BingoEntry> entries) {
    var participants = 0;
    var bingoCount = 0;
    final markCounts = <int, int>{};
    final appearanceCounts = <int, int>{};
    for (final entry in entries) {
      if (entry.layout.length != board.squareCount) continue;
      participants++;
      if (lineCount(board.size, entry.layout, entry.marked) > 0) bingoCount++;
      for (var position = 0; position < entry.layout.length; position++) {
        final cell = entry.layout[position];
        if (cell < 0 || cell >= board.cells.length) continue;
        appearanceCounts[cell] = (appearanceCounts[cell] ?? 0) + 1;
        if (entry.marked.contains(position)) {
          markCounts[cell] = (markCounts[cell] ?? 0) + 1;
        }
      }
    }
    return board.copyWith(
      participants: participants,
      bingoCount: bingoCount,
      markCounts: markCounts,
      appearanceCounts: appearanceCounts,
    );
  }

  /// Cell indices ordered by how often participants marked them, relative to
  /// how often they appeared on cards.
  static List<({int cell, int marks, int appearances, double rate})> ranking(
    BingoBoard board,
  ) {
    final rows = [
      for (var cell = 0; cell < board.cells.length; cell++)
        if ((board.appearanceCounts[cell] ?? 0) > 0)
          (
            cell: cell,
            marks: board.markCounts[cell] ?? 0,
            appearances: board.appearanceCounts[cell]!,
            rate: (board.markCounts[cell] ?? 0) / board.appearanceCounts[cell]!,
          ),
    ];
    rows.sort((a, b) {
      final byRate = b.rate.compareTo(a.rate);
      return byRate != 0 ? byRate : b.marks.compareTo(a.marks);
    });
    return rows;
  }
}

/// Validation result for the create form. Codes map to localization keys.
enum BingoDraftIssue {
  titleRequired,
  titleTooLong,
  descriptionTooLong,
  notEnoughCells,
  tooManyCells,
  cellTextTooLong,
  duplicateCells,
  tooManyTags,
}

abstract final class BingoDraftValidator {
  static List<BingoDraftIssue> validate({
    required String title,
    required String description,
    required List<String> tags,
    required int size,
    required bool freeCenter,
    required List<BingoCell> cells,
  }) {
    final issues = <BingoDraftIssue>[];
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) issues.add(BingoDraftIssue.titleRequired);
    if (trimmedTitle.length > BingoBoard.maxTitleLength) {
      issues.add(BingoDraftIssue.titleTooLong);
    }
    if (description.trim().length > BingoBoard.maxDescriptionLength) {
      issues.add(BingoDraftIssue.descriptionTooLong);
    }
    if (tags.length > BingoBoard.maxTags) {
      issues.add(BingoDraftIssue.tooManyTags);
    }
    final required = size * size - (freeCenter && size.isOdd ? 1 : 0);
    if (cells.length < required) issues.add(BingoDraftIssue.notEnoughCells);
    if (cells.length > BingoBoard.maxCells) {
      issues.add(BingoDraftIssue.tooManyCells);
    }
    if (cells.any(
      (cell) => (cell.text?.trim().length ?? 0) > BingoCell.maxTextLength,
    )) {
      issues.add(BingoDraftIssue.cellTextTooLong);
    }
    final textOnly = [
      for (final cell in cells)
        if (!cell.hasImage && cell.hasText) normalizeCellText(cell.text!),
    ];
    if (textOnly.toSet().length != textOnly.length) {
      issues.add(BingoDraftIssue.duplicateCells);
    }
    return issues;
  }

  static String normalizeCellText(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Splits pasted text into cell texts: one per line, trimmed, deduplicated.
  static List<String> splitBulkText(String value) {
    final seen = <String>{};
    return [
      for (final line in value.split(RegExp(r'\r?\n')))
        if (line.trim().isNotEmpty && seen.add(normalizeCellText(line)))
          line.trim(),
    ];
  }

  static List<String> parseTags(String value) {
    final seen = <String>{};
    return [
      for (final raw in value.split(RegExp(r'[,、，#\s]+')))
        if (raw.trim().isNotEmpty && seen.add(raw.trim().toLowerCase()))
          raw.trim().length > BingoBoard.maxTagLength
              ? raw.trim().substring(0, BingoBoard.maxTagLength)
              : raw.trim(),
    ];
  }
}
