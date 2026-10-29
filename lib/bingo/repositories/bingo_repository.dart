import '../models/bingo_models.dart';

/// Error codes surfaced to the UI. They map 1:1 to localization keys.
enum BingoFailure {
  blocked,
  rateLimited,
  notFound,
  alreadyReported,
  emailUnverified,
  network,
}

class BingoException implements Exception {
  const BingoException(this.failure, [this.cause]);
  final BingoFailure failure;
  final Object? cause;

  String get localizationKey => switch (failure) {
    BingoFailure.blocked => 'publishBlocked',
    BingoFailure.rateLimited => 'rateLimited',
    BingoFailure.notFound => 'notFound',
    BingoFailure.alreadyReported => 'alreadyReported',
    BingoFailure.emailUnverified => 'emailUnverified',
    BingoFailure.network => 'actionFailed',
  };

  @override
  String toString() => 'BingoException($failure, $cause)';
}

/// Storage backend for bingo data. [LocalBingoRepository] keeps everything on
/// the device; [FirebaseBingoRepository] shares it through Firestore. The
/// state layer decides which one to use per board (samples are always local).
abstract interface class BingoRepository {
  String get currentUserId;

  /// Public, non-blocked boards, newest first.
  Future<List<BingoBoard>> loadListedBoards();

  /// Boards created by [currentUserId], including private ones.
  Future<List<BingoBoard>> loadOwnBoards();

  Future<BingoBoard?> loadBoard(String boardId);

  /// Publishes a new board. Uploaded `data:` images are stored by the backend.
  Future<BingoBoard> publishBoard(BingoBoard board);

  Future<void> setBoardPublic(BingoBoard board, {required bool isPublic});

  Future<void> deleteBoard(String boardId);

  Future<BingoEntry?> loadEntry(String boardId);

  /// Entries of [currentUserId] across all boards.
  Future<List<BingoEntry>> loadOwnEntries();

  Future<void> saveEntry(BingoEntry entry);

  /// Entries of every participant. Only needed where no server aggregates.
  Future<List<BingoEntry>> loadEntries(String boardId);

  Future<List<BingoComment>> loadComments(String boardId);

  /// Posts a comment. With [attachResult] the backend freezes the author's
  /// current card into the comment.
  Future<BingoComment> postComment({
    required BingoBoard board,
    required String authorName,
    required String body,
    required bool attachResult,
  });

  Future<void> deleteComment(String boardId, String commentId);

  Future<void> report({
    required String boardId,
    required String targetType,
    required String targetId,
  });

  /// Whether [currentUserId] likes the board.
  Future<bool> loadBoardLike(String boardId);

  Future<void> setBoardLike(String boardId, {required bool liked});

  /// commentId -> [BingoReaction.id] chosen by [currentUserId] on the board.
  Future<Map<String, String>> loadMyReactions(String boardId);

  /// Sets (or with null removes) the user's single reaction on a comment.
  Future<void> setCommentReaction(
    String boardId,
    String commentId,
    String? reactionId,
  );

  Future<void> saveProfile({
    required String displayName,
    required String preferredLocale,
    required String region,
  });
}
