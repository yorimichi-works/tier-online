import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/account_auth_service.dart';
import '../domain/bingo_logic.dart';
import '../l10n/bingo_localizations.dart';
import '../models/bingo_models.dart';
import '../repositories/bingo_repository.dart';
import '../repositories/local_bingo_repository.dart';
import '../repositories/sample_bingo_boards.dart';
import 'apple_artwork_service.dart';

enum BingoSort { newest, popular }

/// Result of a tap on a card square.
typedef MarkResult = ({int linesBefore, int linesAfter});

/// App state for Bingo Online, modeled on tier-online's `AppState`: the local
/// repository makes the app usable immediately, and Firebase is attached in
/// the background when it becomes reachable.
class BingoState extends ChangeNotifier {
  BingoState({
    String initialPath = '/',
    Locale deviceLocale = const Locale('ja'),
    AppleArtworkService? appleArtwork,
    this.entrySaveDelay = const Duration(milliseconds: 700),
  }) : _initialPath = initialPath,
       _deviceLocale = deviceLocale,
       appleArtwork = appleArtwork ?? AppleArtworkService();

  final String _initialPath;
  final Locale _deviceLocale;
  final AppleArtworkService appleArtwork;

  /// Marks are written after a short pause so rapid taps cost one write (and
  /// one server aggregation) instead of many.
  final Duration entrySaveDelay;

  late LocalBingoRepository _local;
  BingoRepository? _cloud;
  AccountAuthService? _account;
  String? _accountUid;
  bool _initialized = false;
  bool _cloudBootstrapComplete = false;
  bool _loadingBoards = false;
  Object? _lastError;

  AppLocale _locale = AppLocale.ja;
  String _region = 'JP';
  String _displayName = '';
  String _localUserId = '';
  bool _languageExplicitlySelected = false;

  final Map<String, BingoBoard> _boards = {};
  final List<String> _listedIds = [];
  final Set<String> _ownIds = {};
  final Set<String> _localOnlyIds = {};
  final Map<String, BingoEntry> _entries = {};
  final Map<String, List<BingoComment>> _comments = {};
  final Set<String> _reported = {};
  final Set<String> _likedBoards = {};

  /// boardId -> commentId -> [BingoReaction.id] chosen by this user.
  final Map<String, Map<String, String>> _myReactions = {};
  final Map<String, Timer> _saveTimers = {};

  bool get initialized => _initialized;
  bool get cloudEnabled => _cloud != null;

  /// Login shared with Tier Online (same Firebase project and users).
  AccountAuthService? get account => _account;
  bool get isRegistered => _account?.session.isRegistered ?? false;
  String? get accountEmail => _account?.session.email;
  bool get needsEmailVerification => _account?.needsEmailVerification ?? false;

  /// Image uploads go to Firebase Storage, which (like Tier) only accepts
  /// registered users. Offline, images stay on the device and are allowed.
  bool get canUploadImages => _cloud == null || isRegistered;
  bool get cloudBootstrapComplete => _cloudBootstrapComplete;
  bool get loadingBoards => _loadingBoards;
  Object? get lastError => _lastError;
  AppLocale get locale => _locale;
  String get region => _region;
  String get displayName => _displayName;
  String get initialPath => _initialPath;
  String get currentUserId => _cloud?.currentUserId ?? _localUserId;
  BingoLocalizations get _strings => BingoLocalizations(_locale);

  /// Name stored with comments and cards. Guests appear as "Guest" to others.
  String get authorName =>
      _displayName.trim().isEmpty ? _strings.t('guest') : _displayName.trim();

  BingoRepository _repositoryFor(String boardId) =>
      SampleBingoBoards.isSampleId(boardId) ||
          _localOnlyIds.contains(boardId) ||
          _cloud == null
      ? _local
      : _cloud!;

  Future<void> initialize() async {
    if (_initialized) return;
    final preferences = await SharedPreferences.getInstance();
    // Same keys and priority as tier-online: explicit choice > URL > saved >
    // device. Region stays independent of the UI language.
    _languageExplicitlySelected =
        preferences.getBool('languageExplicitlySelected') ?? false;
    final savedLocale = AppLocaleParser.fromCode(
      preferences.getString('preferredLanguage') ??
          preferences.getString('preferredLocale'),
    );
    _locale =
        (_languageExplicitlySelected ? savedLocale : null) ??
        AppLocaleParser.fromPath(_initialPath) ??
        savedLocale ??
        AppLocaleParser.fromDevice(_deviceLocale);
    _region = SupportedRegion.normalize(
      preferences.getString('region'),
      fallback: _locale.defaultRegion,
    );
    _displayName = preferences.getString('bingo.displayName') ?? '';
    _localUserId = preferences.getString('anonymousId') ?? '';
    if (_localUserId.isEmpty) {
      _localUserId = 'local-${DateTime.now().microsecondsSinceEpoch}';
      await preferences.setString('anonymousId', _localUserId);
    }
    _reported.addAll(preferences.getStringList('bingo.reported') ?? const []);
    await preferences.setString('preferredLocale', _locale.code);
    await preferences.setString('preferredLanguage', _locale.storageCode);
    await preferences.setString('region', _region);
    _local = LocalBingoRepository(userId: _localUserId);
    await _loadLocal();
    _initialized = true;
    notifyListeners();
  }

  Future<void> _loadLocal() async {
    for (final board in await _local.loadOwnBoards()) {
      _boards[board.id] = board;
      _ownIds.add(board.id);
      _localOnlyIds.add(board.id);
      if (board.isListed && !_listedIds.contains(board.id)) {
        _listedIds.add(board.id);
      }
    }
    for (final entry in await _local.loadOwnEntries()) {
      _entries[entry.boardId] = entry;
    }
  }

  Future<void> attachCloud(
    BingoRepository repository, {
    AccountAuthService? account,
  }) async {
    if (identical(_cloud, repository)) return;
    _cloud = repository;
    _account?.removeListener(_onAccountChanged);
    _account = account;
    _accountUid = account?.uid;
    account?.addListener(_onAccountChanged);
    await _loadCloudUserData();
  }

  Future<void> _loadCloudUserData() async {
    final cloud = _cloud;
    if (cloud == null) return;
    await refreshBoards();
    try {
      for (final entry in await cloud.loadOwnEntries()) {
        _entries[entry.boardId] = entry;
      }
      await cloud.saveProfile(
        displayName: _displayName,
        preferredLocale: _locale.storageCode,
        region: _region,
      );
    } on Object catch (error) {
      _lastError = error;
    }
    notifyListeners();
  }

  /// Signing in to another account (or out) switches the uid. Cloud cards,
  /// own boards, comments and reactions belong to the previous user, so they
  /// are dropped and reloaded; device-only boards and samples stay.
  void _onAccountChanged() {
    final uid = _account?.uid;
    if (uid != null && uid != _accountUid) {
      _accountUid = uid;
      _entries.removeWhere(
        (boardId, _) =>
            !SampleBingoBoards.isSampleId(boardId) &&
            !_localOnlyIds.contains(boardId),
      );
      _ownIds.retainAll(_localOnlyIds);
      _comments.clear();
      _clearReactionsForUserSwitch();
      unawaited(_loadCloudUserData());
    }
    notifyListeners();
  }

  void _clearReactionsForUserSwitch() {
    _likedBoards.clear();
    _myReactions.clear();
  }

  /// Email of an existing password account that a Google sign-in collided
  /// with; the account dialog asks for its password to merge both.
  String? get pendingGoogleAccountEmail => _account?.pendingGoogleAccountEmail;

  Future<void> consumeGoogleRedirectResult() async {
    await _account?.consumeGoogleRedirectResult();
    notifyListeners();
  }

  Future<void> signOut() async => _account?.signOut();

  /// Deletes the account and all of its Tier/Bingo data on the server.
  Future<AccountDeletionStatus> deleteAccount({String? password}) async {
    final account = _account;
    if (account == null) return AccountDeletionStatus.failed;
    final owned = _ownIds.difference(_localOnlyIds);
    final status = await account.deleteAccount(password: password);
    if (status == AccountDeletionStatus.success) {
      for (final id in owned) {
        _boards.remove(id);
        _listedIds.remove(id);
      }
      notifyListeners();
    }
    return status;
  }

  void completeCloudBootstrap() {
    if (_cloudBootstrapComplete) return;
    _cloudBootstrapComplete = true;
    notifyListeners();
  }

  Future<void> refreshBoards() async {
    final cloud = _cloud;
    if (cloud == null) return;
    _loadingBoards = true;
    notifyListeners();
    try {
      final listed = await cloud.loadListedBoards();
      final own = await cloud.loadOwnBoards();
      _listedIds
        ..removeWhere((id) => !_localOnlyIds.contains(id))
        ..insertAll(0, listed.map((board) => board.id));
      for (final board in [...listed, ...own]) {
        _boards[board.id] = board;
      }
      _ownIds.addAll(own.map((board) => board.id));
      _lastError = null;
    } on Object catch (error) {
      _lastError = error;
    } finally {
      _loadingBoards = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- boards

  List<BingoBoard> get samples => [
    for (final sample in SampleBingoBoards.forLocale(_locale))
      _withCachedStats(sample),
  ];

  BingoBoard _withCachedStats(BingoBoard sample) {
    final cached = _boards[sample.id];
    if (cached == null) return sample;
    return sample.copyWith(
      participants: cached.participants,
      bingoCount: cached.bingoCount,
      markCounts: cached.markCounts,
      appearanceCounts: cached.appearanceCounts,
      commentCount: cached.commentCount,
      likeCount: cached.likeCount,
    );
  }

  BingoBoard? cachedBoard(String boardId) {
    if (SampleBingoBoards.isSampleId(boardId)) {
      for (final sample in samples) {
        if (sample.id == boardId) return sample;
      }
      return null;
    }
    return _boards[boardId];
  }

  List<BingoBoard> listedBoards({
    BingoSort sort = BingoSort.newest,
    String query = '',
  }) {
    final boards = [
      for (final id in _listedIds)
        if (_boards[id] case final board? when board.isListed) board,
    ];
    final normalized = query.trim().toLowerCase().replaceFirst('#', '');
    final filtered = normalized.isEmpty
        ? boards
        : boards
              .where(
                (board) =>
                    board.title.toLowerCase().contains(normalized) ||
                    board.description.toLowerCase().contains(normalized) ||
                    board.tags.any(
                      (tag) => tag.toLowerCase().contains(normalized),
                    ),
              )
              .toList();
    if (sort == BingoSort.popular) {
      filtered.sort((a, b) {
        final byPopularity = b.popularity.compareTo(a.popularity);
        return byPopularity != 0
            ? byPopularity
            : b.participants.compareTo(a.participants);
      });
    } else {
      filtered.sort(
        (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
          a.createdAt ?? DateTime(2000),
        ),
      );
    }
    return filtered;
  }

  List<BingoBoard> get ownBoards {
    final boards = [for (final id in _ownIds) ?_boards[id]];
    boards.sort(
      (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
        a.createdAt ?? DateTime(2000),
      ),
    );
    return boards;
  }

  /// Boards the user holds a card for, most recently played first. Boards not
  /// yet cached are fetched by [loadJoinedBoards].
  List<BingoBoard> get joinedBoards {
    final entries = _entries.values.toList()
      ..sort(
        (a, b) => (b.updatedAt ?? DateTime(2000)).compareTo(
          a.updatedAt ?? DateTime(2000),
        ),
      );
    return [for (final entry in entries) ?cachedBoard(entry.boardId)];
  }

  Future<void> loadJoinedBoards() async {
    final missing = _entries.keys.where(
      (id) => cachedBoard(id) == null && !SampleBingoBoards.isSampleId(id),
    );
    var changed = false;
    for (final id in missing.toList()) {
      try {
        final board = await _repositoryFor(id).loadBoard(id);
        if (board != null) {
          _boards[id] = board;
          changed = true;
        }
      } on Object catch (error) {
        _lastError = error;
      }
    }
    if (changed) notifyListeners();
  }

  bool isOwner(BingoBoard board) =>
      board.creatorId == currentUserId || _localOnlyIds.contains(board.id);

  /// Loads a board for its detail page, refreshing stats from the backend.
  Future<BingoBoard?> loadBoard(String boardId) async {
    if (SampleBingoBoards.isSampleId(boardId)) {
      BingoBoard? sample;
      for (final candidate in SampleBingoBoards.forLocale(_locale)) {
        if (candidate.id == boardId) sample = candidate;
      }
      if (sample == null) return null;
      final aggregated =
          BingoLogic.aggregate(
            sample,
            await _local.loadEntries(boardId),
          ).copyWith(
            commentCount: (await _local.loadComments(boardId)).length,
            likeCount: await _local.loadBoardLike(boardId) ? 1 : 0,
          );
      _boards[boardId] = aggregated;
      await _loadEntry(boardId);
      await _loadLike(boardId);
      return aggregated;
    }
    final board = await _repositoryFor(boardId).loadBoard(boardId);
    if (board == null) {
      _boards.remove(boardId);
      _listedIds.remove(boardId);
    } else {
      _boards[boardId] = board;
      if (board.creatorId == currentUserId) _ownIds.add(boardId);
      await _loadEntry(boardId);
      await _loadLike(boardId);
    }
    notifyListeners();
    return board;
  }

  Future<void> _loadEntry(String boardId) async {
    if (_saveTimers.containsKey(boardId)) return;
    try {
      final entry = await _repositoryFor(boardId).loadEntry(boardId);
      if (entry != null) _entries[boardId] = entry;
    } on Object catch (error) {
      _lastError = error;
    }
  }

  /// Publishes a new board. Offline, the board is kept on this device.
  Future<BingoBoard> publish(BingoBoard draft) async {
    _assertCanPost();
    final cloud = _cloud;
    final board = draft.copyWith(creatorId: currentUserId);
    final BingoBoard saved;
    if (cloud == null) {
      saved = await _local.publishBoard(board);
      _localOnlyIds.add(saved.id);
    } else {
      saved = await cloud.publishBoard(board);
    }
    final withDate = BingoBoard.fromJson(
      saved.toJson(),
      createdAt: saved.createdAt ?? DateTime.now(),
    );
    _boards[withDate.id] = withDate;
    _ownIds.add(withDate.id);
    _listedIds.remove(withDate.id);
    if (withDate.isListed) _listedIds.insert(0, withDate.id);
    notifyListeners();
    return withDate;
  }

  Future<void> setBoardPublic(BingoBoard board, bool isPublic) async {
    await _repositoryFor(board.id).setBoardPublic(board, isPublic: isPublic);
    final updated = board.copyWith(isPublic: isPublic);
    _boards[board.id] = updated;
    _listedIds.remove(board.id);
    if (updated.isListed) _listedIds.insert(0, board.id);
    notifyListeners();
  }

  Future<void> deleteBoard(BingoBoard board) async {
    await _repositoryFor(board.id).deleteBoard(board.id);
    _boards.remove(board.id);
    _listedIds.remove(board.id);
    _ownIds.remove(board.id);
    _localOnlyIds.remove(board.id);
    _entries.remove(board.id);
    _comments.remove(board.id);
    notifyListeners();
  }

  // ---------------------------------------------------------------- cards

  BingoEntry? entryFor(String boardId) => _entries[boardId];

  Future<BingoEntry> join(BingoBoard board) async {
    final existing = _entries[board.id];
    if (existing != null) return existing;
    final entry = BingoEntry(
      boardId: board.id,
      userId: _repositoryFor(board.id).currentUserId,
      userName: authorName,
      layout: BingoLogic.generateLayout(board, currentUserId),
      updatedAt: DateTime.now(),
    );
    _entries[board.id] = entry;
    _boards[board.id] = (cachedBoard(board.id) ?? board).copyWith(
      participants: (cachedBoard(board.id) ?? board).participants + 1,
    );
    notifyListeners();
    await _repositoryFor(board.id).saveEntry(entry);
    return entry;
  }

  MarkResult toggleMark(BingoBoard board, int position) {
    final entry = _entries[board.id];
    if (entry == null ||
        position < 0 ||
        position >= entry.layout.length ||
        entry.layout[position] == BingoEntry.free) {
      return (linesBefore: 0, linesAfter: 0);
    }
    final before = BingoLogic.lineCount(board.size, entry.layout, entry.marked);
    final marked = {...entry.marked};
    if (!marked.remove(position)) marked.add(position);
    final after = BingoLogic.lineCount(board.size, entry.layout, marked);
    _entries[board.id] = entry.copyWith(
      marked: marked,
      userName: authorName,
      firstBingoAt: entry.firstBingoAt ?? (after > 0 ? DateTime.now() : null),
    );
    // Reflect reaching (or losing) BINGO in the header right away; the
    // server/local aggregation replaces this on the next load.
    if ((before > 0) != (after > 0)) {
      final cached = cachedBoard(board.id) ?? board;
      _boards[board.id] = cached.copyWith(
        bingoCount: (cached.bingoCount + (after > 0 ? 1 : -1)).clamp(
          0,
          cached.participants,
        ),
      );
    }
    _scheduleEntrySave(board.id);
    notifyListeners();
    return (linesBefore: before, linesAfter: after);
  }

  Future<void> resetMarks(BingoBoard board) async {
    final entry = _entries[board.id];
    if (entry == null) return;
    if (BingoLogic.lineCount(board.size, entry.layout, entry.marked) > 0) {
      final cached = cachedBoard(board.id) ?? board;
      _boards[board.id] = cached.copyWith(
        bingoCount: (cached.bingoCount - 1).clamp(0, cached.participants),
      );
    }
    _entries[board.id] = entry.copyWith(marked: {}, clearFirstBingo: true);
    notifyListeners();
    await flushEntry(board.id);
  }

  void _scheduleEntrySave(String boardId) {
    _saveTimers[boardId]?.cancel();
    _saveTimers[boardId] = Timer(entrySaveDelay, () => flushEntry(boardId));
  }

  /// Writes a pending card immediately (before attaching it to a comment).
  Future<void> flushEntry(String boardId) async {
    _saveTimers.remove(boardId)?.cancel();
    final entry = _entries[boardId];
    if (entry == null) return;
    try {
      await _repositoryFor(boardId).saveEntry(entry);
    } on Object catch (error) {
      _lastError = error;
    }
  }

  // ---------------------------------------------------------------- comments

  List<BingoComment> commentsFor(String boardId) =>
      List.unmodifiable(_comments[boardId] ?? const <BingoComment>[]);

  Future<List<BingoComment>> loadComments(String boardId) async {
    final repository = _repositoryFor(boardId);
    final comments = await repository.loadComments(boardId);
    _comments[boardId] = comments;
    try {
      _myReactions[boardId] = await repository.loadMyReactions(boardId);
    } on Object catch (error) {
      _lastError = error;
    }
    notifyListeners();
    return comments;
  }

  // ---------------------------------------------------------------- likes

  bool isLiked(String boardId) => _likedBoards.contains(boardId);

  Future<void> _loadLike(String boardId) async {
    try {
      if (await _repositoryFor(boardId).loadBoardLike(boardId)) {
        _likedBoards.add(boardId);
      } else {
        _likedBoards.remove(boardId);
      }
    } on Object catch (error) {
      _lastError = error;
    }
  }

  /// Optimistic like toggle; the server trigger keeps `likeCount` exact.
  Future<void> toggleBoardLike(BingoBoard board) async {
    _assertCanPost();
    final liked = !isLiked(board.id);
    void apply(bool value) {
      final cached = cachedBoard(board.id) ?? board;
      if (value) {
        _likedBoards.add(board.id);
      } else {
        _likedBoards.remove(board.id);
      }
      _boards[board.id] = cached.copyWith(
        likeCount: (cached.likeCount + (value ? 1 : -1)).clamp(0, 1 << 30),
      );
      notifyListeners();
    }

    apply(liked);
    try {
      await _repositoryFor(board.id).setBoardLike(board.id, liked: liked);
    } on Object {
      apply(!liked);
      rethrow;
    }
  }

  // ---------------------------------------------------------------- reactions

  String? reactionFor(String boardId, String commentId) =>
      _myReactions[boardId]?[commentId];

  /// Picks [reaction] on a comment, or removes it when already chosen. One
  /// reaction per person per comment, like a poll.
  Future<void> toggleReaction(
    BingoBoard board,
    BingoComment comment,
    BingoReaction reaction,
  ) async {
    _assertCanPost();
    final previous = reactionFor(board.id, comment.id);
    final next = previous == reaction.id ? null : reaction.id;
    void apply(String? from, String? to) {
      final mine = _myReactions.putIfAbsent(board.id, () => {});
      if (to == null) {
        mine.remove(comment.id);
      } else {
        mine[comment.id] = to;
      }
      _comments[board.id] = [
        for (final existing in commentsFor(board.id))
          if (existing.id != comment.id)
            existing
          else
            existing.copyWith(
              reactionCounts: _shiftReaction(existing.reactionCounts, from, to),
            ),
      ];
      notifyListeners();
    }

    apply(previous, next);
    try {
      await _repositoryFor(
        board.id,
      ).setCommentReaction(board.id, comment.id, next);
    } on Object {
      apply(next, previous);
      rethrow;
    }
  }

  static Map<String, int> _shiftReaction(
    Map<String, int> counts,
    String? from,
    String? to,
  ) {
    final result = {...counts};
    if (from != null) {
      final value = (result[from] ?? 0) - 1;
      if (value > 0) {
        result[from] = value;
      } else {
        result.remove(from);
      }
    }
    if (to != null) result[to] = (result[to] ?? 0) + 1;
    return result;
  }

  Future<BingoComment> postComment(
    BingoBoard board, {
    required String body,
    required bool attachResult,
  }) async {
    _assertCanPost();
    if (attachResult) await flushEntry(board.id);
    final comment = await _repositoryFor(board.id).postComment(
      board: board,
      authorName: authorName,
      body: body,
      attachResult: attachResult && _entries.containsKey(board.id),
    );
    _comments[board.id] = [comment, ...commentsFor(board.id)];
    final cached = cachedBoard(board.id) ?? board;
    _boards[board.id] = cached.copyWith(commentCount: cached.commentCount + 1);
    notifyListeners();
    return comment;
  }

  /// Password accounts must verify their address first; rules and Functions
  /// would reject the write anyway, so fail early with a clear message.
  void _assertCanPost() {
    if (cloudEnabled && needsEmailVerification) {
      throw const BingoException(BingoFailure.emailUnverified);
    }
  }

  bool canDeleteComment(BingoBoard board, BingoComment comment) =>
      comment.authorId == currentUserId || isOwner(board);

  Future<void> deleteComment(BingoBoard board, BingoComment comment) async {
    await _repositoryFor(board.id).deleteComment(board.id, comment.id);
    _comments[board.id] = [
      for (final existing in commentsFor(board.id))
        if (existing.id != comment.id) existing,
    ];
    final cached = cachedBoard(board.id) ?? board;
    _boards[board.id] = cached.copyWith(
      commentCount: (cached.commentCount - 1).clamp(0, 1 << 30),
    );
    notifyListeners();
  }

  bool hasReported(String targetType, String targetId) =>
      _reported.contains('$targetType:$targetId');

  /// Returns false when the target was already reported by this user.
  Future<bool> report(
    BingoBoard board, {
    required String targetType,
    required String targetId,
  }) async {
    if (hasReported(targetType, targetId)) return false;
    try {
      await _repositoryFor(
        board.id,
      ).report(boardId: board.id, targetType: targetType, targetId: targetId);
    } on BingoException catch (error) {
      if (error.failure != BingoFailure.alreadyReported) rethrow;
    }
    _reported.add('$targetType:$targetId');
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList('bingo.reported', _reported.toList());
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------- settings

  Future<void> setLocale(AppLocale value) async {
    _languageExplicitlySelected = true;
    if (_locale == value) return;
    _locale = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('languageExplicitlySelected', true);
    await preferences.setString('preferredLocale', value.code);
    await preferences.setString('preferredLanguage', value.storageCode);
    notifyListeners();
    await _syncProfile();
  }

  Future<void> setRegion(String value) async {
    final normalized = SupportedRegion.normalize(value);
    if (_region == normalized) return;
    _region = normalized;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('region', normalized);
    notifyListeners();
    await _syncProfile();
  }

  Future<void> setDisplayName(String value) async {
    final trimmed = value.trim();
    _displayName = trimmed.length > 24 ? trimmed.substring(0, 24) : trimmed;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('bingo.displayName', _displayName);
    notifyListeners();
    await _syncProfile();
  }

  Future<void> _syncProfile() async {
    try {
      await _cloud?.saveProfile(
        displayName: _displayName,
        preferredLocale: _locale.storageCode,
        region: _region,
      );
    } on Object catch (error) {
      _lastError = error;
    }
  }

  @override
  void dispose() {
    _account?.removeListener(_onAccountChanged);
    for (final boardId in _saveTimers.keys.toList()) {
      unawaited(flushEntry(boardId));
    }
    super.dispose();
  }
}
