import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/bingo_logic.dart';
import '../models/bingo_models.dart';
import 'bingo_repository.dart';

/// Device-only storage. Used before Firebase connects, when it is unavailable,
/// and always for bundled samples (which have no Firestore document).
class LocalBingoRepository implements BingoRepository {
  LocalBingoRepository({required this.userId});

  static const _boardIdsKey = 'bingo.boardIds.v1';
  static const _boardPrefix = 'bingo.board.';
  static const _entryPrefix = 'bingo.entry.';
  static const _commentsPrefix = 'bingo.comments.';

  final String userId;

  @override
  String get currentUserId => userId;

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  Map<String, Object?>? _decode(String? encoded) {
    if (encoded == null) return null;
    try {
      return (jsonDecode(encoded) as Map).cast<String, Object?>();
    } on FormatException {
      return null;
    }
  }

  Future<List<BingoBoard>> _allBoards() async {
    final preferences = await _preferences;
    return [
      for (final id in preferences.getStringList(_boardIdsKey) ?? const [])
        if (_decode(preferences.getString('$_boardPrefix$id')) case final json?)
          BingoBoard.fromJson(json),
    ];
  }

  @override
  Future<List<BingoBoard>> loadListedBoards() async => [
    for (final board in await _allBoards())
      if (board.isListed) await _withStats(board),
  ];

  @override
  Future<List<BingoBoard>> loadOwnBoards() async => [
    for (final board in await _allBoards())
      if (board.creatorId == userId) await _withStats(board),
  ];

  Future<BingoBoard> _withStats(BingoBoard board) async {
    final comments = await loadComments(board.id);
    return BingoLogic.aggregate(
      board,
      await loadEntries(board.id),
    ).copyWith(commentCount: comments.length);
  }

  @override
  Future<BingoBoard?> loadBoard(String boardId) async {
    final preferences = await _preferences;
    final json = _decode(preferences.getString('$_boardPrefix$boardId'));
    return json == null ? null : _withStats(BingoBoard.fromJson(json));
  }

  @override
  Future<BingoBoard> publishBoard(BingoBoard board) async {
    final preferences = await _preferences;
    final ids = preferences.getStringList(_boardIdsKey) ?? <String>[];
    if (!ids.contains(board.id)) {
      ids.insert(0, board.id);
      await preferences.setStringList(_boardIdsKey, ids);
    }
    final saved = board.copyWith(creatorId: userId);
    await preferences.setString(
      '$_boardPrefix${board.id}',
      jsonEncode(saved.toJson()),
    );
    return saved;
  }

  /// Caches a board that came from another source (used for samples).
  Future<void> cacheBoard(BingoBoard board) async {
    final preferences = await _preferences;
    await preferences.setString(
      '$_boardPrefix${board.id}',
      jsonEncode(board.toJson()),
    );
  }

  @override
  Future<void> setBoardPublic(BingoBoard board, {required bool isPublic}) =>
      publishBoard(board.copyWith(isPublic: isPublic));

  @override
  Future<void> deleteBoard(String boardId) async {
    final preferences = await _preferences;
    final ids = preferences.getStringList(_boardIdsKey) ?? <String>[];
    ids.remove(boardId);
    await preferences.setStringList(_boardIdsKey, ids);
    await preferences.remove('$_boardPrefix$boardId');
    await preferences.remove('$_commentsPrefix$boardId');
    for (final key in preferences.getKeys().toList()) {
      if (key.startsWith('$_entryPrefix$boardId.')) {
        await preferences.remove(key);
      }
    }
  }

  @override
  Future<BingoEntry?> loadEntry(String boardId) async {
    final preferences = await _preferences;
    final json = _decode(
      preferences.getString('$_entryPrefix$boardId.$userId'),
    );
    return json == null ? null : BingoEntry.fromJson(json);
  }

  @override
  Future<List<BingoEntry>> loadOwnEntries() async {
    final preferences = await _preferences;
    return [
      for (final key in preferences.getKeys())
        if (key.startsWith(_entryPrefix) && key.endsWith('.$userId'))
          if (_decode(preferences.getString(key)) case final json?)
            BingoEntry.fromJson(json),
    ];
  }

  @override
  Future<void> saveEntry(BingoEntry entry) async {
    final preferences = await _preferences;
    await preferences.setString(
      '$_entryPrefix${entry.boardId}.${entry.userId}',
      jsonEncode(entry.toJson()),
    );
  }

  @override
  Future<List<BingoEntry>> loadEntries(String boardId) async {
    final preferences = await _preferences;
    return [
      for (final key in preferences.getKeys())
        if (key.startsWith('$_entryPrefix$boardId.'))
          if (_decode(preferences.getString(key)) case final json?)
            BingoEntry.fromJson(json),
    ];
  }

  @override
  Future<List<BingoComment>> loadComments(String boardId) async {
    final preferences = await _preferences;
    final encoded = preferences.getString('$_commentsPrefix$boardId');
    if (encoded == null) return const [];
    try {
      return [
        for (final raw in jsonDecode(encoded) as List<Object?>)
          if (raw is Map) BingoComment.fromJson(raw.cast<String, Object?>()),
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> _saveComments(
    String boardId,
    List<BingoComment> comments,
  ) async {
    final preferences = await _preferences;
    await preferences.setString(
      '$_commentsPrefix$boardId',
      jsonEncode([for (final comment in comments) comment.toJson()]),
    );
  }

  @override
  Future<BingoComment> postComment({
    required BingoBoard board,
    required String authorName,
    required String body,
    required bool attachResult,
  }) async {
    final entry = attachResult ? await loadEntry(board.id) : null;
    final comment = BingoComment(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      boardId: board.id,
      authorId: userId,
      authorName: authorName,
      body: body.trim(),
      createdAt: DateTime.now(),
      result: entry == null ? null : BingoLogic.snapshotOf(board, entry),
    );
    await _saveComments(board.id, [comment, ...await loadComments(board.id)]);
    return comment;
  }

  @override
  Future<void> deleteComment(String boardId, String commentId) async {
    final comments = await loadComments(boardId);
    await _saveComments(boardId, [
      for (final comment in comments)
        if (comment.id != commentId) comment,
    ]);
  }

  /// Local content is only visible on this device, so a report has no
  /// moderator to reach; the state layer still remembers it to hide the item.
  @override
  Future<void> report({
    required String boardId,
    required String targetType,
    required String targetId,
  }) async {}

  @override
  Future<void> saveProfile({
    required String displayName,
    required String preferredLocale,
    required String region,
  }) async {}
}
