import 'package:flutter/foundation.dart';

import '../../domain/internationalization.dart';

/// Image provenance for a bingo cell. Uploaded images are copied to Firebase
/// Storage on publish, while Apple artwork stays a remote mzstatic reference
/// (the same policy as oshireco's music pipeline).
abstract final class BingoImageSource {
  static const upload = 'upload';
  static const itunes = 'itunes';
}

/// Size limits for square images. Squares are at most ~170 logical pixels
/// wide (≈340 device pixels on 2x screens), so 400px is enough.
abstract final class BingoImagePolicy {
  static const pixels = 400;
  static const jpegQuality = 78;

  /// Uploads are recompressed until they fit. Storage rules reject files over
  /// 200KB, leaving headroom for this client-side budget.
  static const maxUploadBytes = 80 * 1024;
}

/// One square candidate on a bingo board: text only, image only, or both.
@immutable
class BingoCell {
  const BingoCell({
    this.text,
    this.imageUrl,
    this.imageSource,
    this.imageCredit,
  }) : assert(text != null || imageUrl != null);

  static const maxTextLength = 40;

  final String? text;
  final String? imageUrl;

  /// [BingoImageSource] value, or null for text-only cells.
  final String? imageSource;

  /// Attribution shown for external artwork (for example "Artist – Album").
  final String? imageCredit;

  bool get hasText => text?.trim().isNotEmpty ?? false;
  bool get hasImage => imageUrl?.trim().isNotEmpty ?? false;

  BingoCell copyWith({
    String? text,
    bool clearText = false,
    String? imageUrl,
    String? imageSource,
    String? imageCredit,
    bool clearImage = false,
  }) => BingoCell(
    text: clearText ? null : text ?? this.text,
    imageUrl: clearImage ? null : imageUrl ?? this.imageUrl,
    imageSource: clearImage ? null : imageSource ?? this.imageSource,
    imageCredit: clearImage ? null : imageCredit ?? this.imageCredit,
  );

  Map<String, Object?> toJson() => {
    if (hasText) 'text': text!.trim(),
    if (hasImage) 'imageUrl': imageUrl,
    if (hasImage && imageSource != null) 'imageSource': imageSource,
    if (hasImage && imageCredit != null) 'imageCredit': imageCredit,
  };

  static BingoCell? fromJson(Map<String, Object?> json) {
    final text = (json['text'] as String?)?.trim();
    final imageUrl = (json['imageUrl'] as String?)?.trim();
    final hasText = text != null && text.isNotEmpty;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    if (!hasText && !hasImage) return null;
    return BingoCell(
      text: hasText ? text : null,
      imageUrl: hasImage ? imageUrl : null,
      imageSource: hasImage ? json['imageSource'] as String? : null,
      imageCredit: hasImage ? json['imageCredit'] as String? : null,
    );
  }
}

@immutable
class BingoBoard {
  const BingoBoard({
    required this.id,
    required this.title,
    required this.size,
    required this.cells,
    required this.creatorId,
    required this.creatorName,
    required this.contentLanguage,
    required this.targetRegion,
    this.description = '',
    this.tags = const [],
    this.freeCenter = true,
    this.shufflePerPlayer = true,
    this.isPublic = true,
    this.moderationStatus = 'approved',
    this.participants = 0,
    this.bingoCount = 0,
    this.markCounts = const {},
    this.appearanceCounts = const {},
    this.commentCount = 0,
    this.likeCount = 0,
    this.createdAt,
    this.isSample = false,
  });

  static const supportedSizes = [3, 4, 5];
  static const maxCells = 75;
  static const maxTitleLength = 60;
  static const maxDescriptionLength = 300;
  static const maxTags = 5;
  static const maxTagLength = 20;

  final String id;
  final String title;
  final String description;
  final List<String> tags;
  final int size;
  final bool freeCenter;

  /// When true each participant gets a different seeded shuffle (and, when the
  /// pool is larger than the card, a different subset). When false everyone
  /// shares the creator's order.
  final bool shufflePerPlayer;

  /// The candidate pool. It can be larger than the card.
  final List<BingoCell> cells;
  final String creatorId;
  final String creatorName;
  final AppLocale contentLanguage;
  final String targetRegion;
  final bool isPublic;
  final String moderationStatus;
  final int participants;

  /// Participants with at least one completed line.
  final int bingoCount;

  /// cell index -> number of participants who marked it.
  final Map<int, int> markCounts;

  /// cell index -> number of cards that contain it.
  final Map<int, int> appearanceCounts;
  final int commentCount;
  final int likeCount;
  final DateTime? createdAt;

  /// Bundled, local-only example boards.
  final bool isSample;

  int get squareCount => size * size;
  bool get hasFreeSquare => freeCenter && size.isOdd;
  int get freePosition => hasFreeSquare ? squareCount ~/ 2 : -1;
  int get requiredCells => squareCount - (hasFreeSquare ? 1 : 0);
  bool get isListed => isPublic && moderationStatus != 'blocked';
  double get bingoRate => participants == 0 ? 0 : bingoCount / participants;

  /// Ranking used for the "Popular" tab.
  int get popularity => participants + likeCount * 2 + commentCount;

  BingoBoard copyWith({
    bool? isPublic,
    String? moderationStatus,
    List<BingoCell>? cells,
    int? participants,
    int? bingoCount,
    Map<int, int>? markCounts,
    Map<int, int>? appearanceCounts,
    int? commentCount,
    int? likeCount,
    String? creatorId,
  }) => BingoBoard(
    id: id,
    title: title,
    description: description,
    tags: tags,
    size: size,
    freeCenter: freeCenter,
    shufflePerPlayer: shufflePerPlayer,
    cells: cells ?? this.cells,
    creatorId: creatorId ?? this.creatorId,
    creatorName: creatorName,
    contentLanguage: contentLanguage,
    targetRegion: targetRegion,
    isPublic: isPublic ?? this.isPublic,
    moderationStatus: moderationStatus ?? this.moderationStatus,
    participants: participants ?? this.participants,
    bingoCount: bingoCount ?? this.bingoCount,
    markCounts: markCounts ?? this.markCounts,
    appearanceCounts: appearanceCounts ?? this.appearanceCounts,
    commentCount: commentCount ?? this.commentCount,
    likeCount: likeCount ?? this.likeCount,
    createdAt: createdAt,
    isSample: isSample,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'tags': tags,
    'size': size,
    'freeCenter': freeCenter,
    'shufflePerPlayer': shufflePerPlayer,
    'cells': [for (final cell in cells) cell.toJson()],
    'creatorId': creatorId,
    'creatorName': creatorName,
    'contentLanguage': contentLanguage.code,
    'sourceLanguage': contentLanguage.storageCode,
    'targetRegion': targetRegion,
    'isPublic': isPublic,
    'moderationStatus': moderationStatus,
    'participants': participants,
    'bingoCount': bingoCount,
    'markCounts': _intMapToJson(markCounts),
    'appearanceCounts': _intMapToJson(appearanceCounts),
    'commentCount': commentCount,
    'likeCount': likeCount,
    'createdAt': createdAt?.toIso8601String(),
  };

  static BingoBoard fromJson(Map<String, Object?> json, {DateTime? createdAt}) {
    final size = (json['size'] as num?)?.toInt() ?? 5;
    return BingoBoard(
      id: json['id']! as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      tags: (json['tags'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(),
      size: supportedSizes.contains(size) ? size : 5,
      freeCenter: json['freeCenter'] as bool? ?? true,
      shufflePerPlayer: json['shufflePerPlayer'] as bool? ?? true,
      cells: [
        for (final raw in json['cells'] as List<Object?>? ?? const [])
          if (raw is Map) ?BingoCell.fromJson(raw.cast<String, Object?>()),
      ],
      creatorId: json['creatorId'] as String? ?? '',
      creatorName: json['creatorName'] as String? ?? '',
      contentLanguage:
          AppLocaleParser.fromCode(
            json['sourceLanguage'] as String? ??
                json['contentLanguage'] as String?,
          ) ??
          AppLocale.ja,
      targetRegion: SupportedRegion.normalize(json['targetRegion'] as String?),
      isPublic: json['isPublic'] as bool? ?? true,
      moderationStatus: json['moderationStatus'] as String? ?? 'approved',
      participants: (json['participants'] as num?)?.toInt() ?? 0,
      bingoCount: (json['bingoCount'] as num?)?.toInt() ?? 0,
      markCounts: _intMapFromJson(json['markCounts']),
      appearanceCounts: _intMapFromJson(json['appearanceCounts']),
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      createdAt:
          createdAt ?? DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }
}

/// A participant's personal card and marks.
@immutable
class BingoEntry {
  const BingoEntry({
    required this.boardId,
    required this.userId,
    required this.userName,
    required this.layout,
    this.marked = const {},
    this.firstBingoAt,
    this.updatedAt,
  });

  /// Card position -> cell index in the board pool, `-1` for FREE.
  static const free = -1;

  final String boardId;
  final String userId;
  final String userName;
  final List<int> layout;

  /// Card positions the participant tapped (FREE is implicit).
  final Set<int> marked;
  final DateTime? firstBingoAt;
  final DateTime? updatedAt;

  BingoEntry copyWith({
    Set<int>? marked,
    DateTime? firstBingoAt,
    bool clearFirstBingo = false,
    String? userName,
  }) => BingoEntry(
    boardId: boardId,
    userId: userId,
    userName: userName ?? this.userName,
    layout: layout,
    marked: marked ?? this.marked,
    firstBingoAt: clearFirstBingo ? null : firstBingoAt ?? this.firstBingoAt,
    updatedAt: DateTime.now(),
  );

  Map<String, Object?> toJson() => {
    'boardId': boardId,
    'userId': userId,
    'userName': userName,
    'layout': layout,
    'marked': marked.toList()..sort(),
    'firstBingoAt': firstBingoAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  static BingoEntry fromJson(
    Map<String, Object?> json, {
    DateTime? firstBingoAt,
    DateTime? updatedAt,
  }) => BingoEntry(
    boardId: json['boardId'] as String? ?? '',
    userId: json['userId'] as String? ?? '',
    userName: json['userName'] as String? ?? '',
    layout: [
      for (final value in json['layout'] as List<Object?>? ?? const [])
        (value as num?)?.toInt() ?? free,
    ],
    marked: {
      for (final value in json['marked'] as List<Object?>? ?? const [])
        if (value is num) value.toInt(),
    },
    firstBingoAt:
        firstBingoAt ??
        DateTime.tryParse(json['firstBingoAt'] as String? ?? ''),
    updatedAt:
        updatedAt ?? DateTime.tryParse(json['updatedAt'] as String? ?? ''),
  );
}

/// A frozen copy of a participant's card attached to a comment, so the
/// comment keeps showing the result that was shared even if marks change.
@immutable
class BingoResultSnapshot {
  const BingoResultSnapshot({
    required this.size,
    required this.layout,
    required this.marked,
    required this.lines,
  });

  final int size;
  final List<int> layout;
  final Set<int> marked;
  final int lines;

  Map<String, Object?> toJson() => {
    'size': size,
    'layout': layout,
    'marked': marked.toList()..sort(),
    'lines': lines,
  };

  static BingoResultSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.cast<String, Object?>();
    final size = (json['size'] as num?)?.toInt() ?? 0;
    final layout = [
      for (final value in json['layout'] as List<Object?>? ?? const [])
        (value as num?)?.toInt() ?? BingoEntry.free,
    ];
    if (!BingoBoard.supportedSizes.contains(size) ||
        layout.length != size * size) {
      return null;
    }
    return BingoResultSnapshot(
      size: size,
      layout: layout,
      marked: {
        for (final value in json['marked'] as List<Object?>? ?? const [])
          if (value is num) value.toInt(),
      },
      lines: (json['lines'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class BingoComment {
  const BingoComment({
    required this.id,
    required this.boardId,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.createdAt,
    this.result,
    this.hidden = false,
    this.reactionCounts = const {},
  });

  static const maxLength = 500;

  final String id;
  final String boardId;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;
  final BingoResultSnapshot? result;
  final bool hidden;

  /// [BingoReaction.id] -> number of people who reacted with it.
  final Map<String, int> reactionCounts;

  BingoComment copyWith({Map<String, int>? reactionCounts}) => BingoComment(
    id: id,
    boardId: boardId,
    authorId: authorId,
    authorName: authorName,
    body: body,
    createdAt: createdAt,
    result: result,
    hidden: hidden,
    reactionCounts: reactionCounts ?? this.reactionCounts,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'boardId': boardId,
    'authorId': authorId,
    'authorName': authorName,
    'body': body,
    'createdAt': createdAt.toIso8601String(),
    if (result != null) 'result': result!.toJson(),
    'hidden': hidden,
    'reactionCounts': reactionCounts,
  };

  static BingoComment fromJson(
    Map<String, Object?> json, {
    DateTime? createdAt,
  }) => BingoComment(
    id: json['id'] as String? ?? '',
    boardId: json['boardId'] as String? ?? '',
    authorId: json['authorId'] as String? ?? '',
    authorName: json['authorName'] as String? ?? '',
    body: json['body'] as String? ?? '',
    createdAt:
        createdAt ??
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.now(),
    result: BingoResultSnapshot.fromJson(json['result']),
    hidden: json['hidden'] as bool? ?? false,
    reactionCounts: {
      for (final entry
          in (json['reactionCounts'] as Map?)?.entries ??
              const <MapEntry<Object?, Object?>>[])
        if (BingoReaction.byId(entry.key as String?) != null &&
            entry.value is num &&
            (entry.value as num) > 0)
          entry.key as String: (entry.value as num).toInt(),
    },
  );
}

/// Reactions people can leave on a comment (one per person per comment).
/// Stored by id so Firestore field paths stay ASCII.
enum BingoReaction {
  clap('clap', '👏'),
  party('party', '🎉'),
  laugh('laugh', '😂'),
  heart('heart', '❤️');

  const BingoReaction(this.id, this.emoji);
  final String id;
  final String emoji;

  static BingoReaction? byId(String? id) {
    for (final reaction in values) {
      if (reaction.id == id) return reaction;
    }
    return null;
  }
}

Map<String, int> _intMapToJson(Map<int, int> value) => {
  for (final entry in value.entries) '${entry.key}': entry.value,
};

Map<int, int> _intMapFromJson(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      if (int.tryParse('${entry.key}') != null && entry.value is num)
        int.parse('${entry.key}'): (entry.value as num).toInt(),
  };
}
