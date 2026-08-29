import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../models/tier_models.dart';
import '../repositories/cloud_tier_repository.dart';
import '../repositories/tier_repository.dart';
import 'local_tier_store.dart';
import 'tier_aggregation_service.dart';

enum AuthResultStatus {
  success,
  emailInUse,
  weakPassword,
  invalidEmail,
  wrongPassword,
  userNotFound,
  credentialInUse,
  generic,
}

class AuthResult {
  const AuthResult(this.status);
  final AuthResultStatus status;
  bool get isSuccess => status == AuthResultStatus.success;

  factory AuthResult.fromException(FirebaseAuthException error) {
    final status = switch (error.code) {
      'email-already-in-use' => AuthResultStatus.emailInUse,
      'weak-password' => AuthResultStatus.weakPassword,
      'invalid-email' => AuthResultStatus.invalidEmail,
      'wrong-password' ||
      'invalid-credential' => AuthResultStatus.wrongPassword,
      'user-not-found' => AuthResultStatus.userNotFound,
      'credential-already-in-use' => AuthResultStatus.credentialInUse,
      _ => AuthResultStatus.generic,
    };
    return AuthResult(status);
  }
}

class AppState extends ChangeNotifier {
  AppState(
    this._repository, {
    LocalTierStore? localStore,
    CloudTierRepository? cloudRepository,
    FirebaseAuth? auth,
    TierAggregationService aggregationService = const TierAggregationService(),
    String initialPath = '/',
    Locale deviceLocale = const Locale('ja'),
  }) : _localStore = localStore ?? LocalTierStore(),
       _cloudRepository = cloudRepository,
       _auth = auth,
       _aggregationService = aggregationService,
       _initialPath = initialPath,
       _deviceLocale = deviceLocale {
    if (_auth != null) {
      _authSubscription = _auth.userChanges().listen((_) => notifyListeners());
    }
  }
  final TierRepository _repository;
  final LocalTierStore _localStore;
  final CloudTierRepository? _cloudRepository;
  final FirebaseAuth? _auth;
  StreamSubscription<User?>? _authSubscription;
  final TierAggregationService _aggregationService;
  final String _initialPath;
  final Locale _deviceLocale;
  final Map<String, Map<TierRank, List<String>>> _placements = {};
  final Map<String, List<TalkPost>> _localTalks = {};
  final Set<String> _loaded = {};
  final Set<String> _cloudTopicIds = {};
  final Set<String> _likedTopicIds = {};
  final Map<String, String> _talkReactions = {};
  final Set<String> _reportedTalkTargets = {};
  String _anonymousId = '';
  bool _initialized = false;
  Object? _cloudError;
  ThemeMode _themeMode = ThemeMode.dark;
  bool _animationsEnabled = true;
  AppLocale _locale = AppLocale.ja;
  String _region = 'JP';

  bool get initialized => _initialized;
  bool get cloudEnabled => _cloudRepository != null;
  Object? get cloudError => _cloudError;
  bool get authEnabled => _auth != null;
  bool get isAnonymous => _auth?.currentUser?.isAnonymous ?? true;
  String? get userEmail => _auth?.currentUser?.email;
  ThemeMode get themeMode => _themeMode;
  bool get animationsEnabled => _animationsEnabled;
  AppLocale get locale => _locale;
  String get region => _region;
  String get initialPath => _initialPath;
  String get currentUserName => switch (_locale) {
    AppLocale.ja => 'あなた',
    AppLocale.ko => '나',
    AppLocale.en => 'You',
  };

  List<TierTopic> get topics => _repository.getAll();
  Map<TierRank, List<String>> placementsFor(String topicId) => {
    for (final rank in TierRank.values)
      rank: List.unmodifiable(_placements[topicId]?[rank] ?? const []),
  };

  List<TalkPost> talksFor(TierTopic topic) {
    final local = _localTalks[topic.id] ?? const [];
    final overrides = {
      for (final post in local)
        if (post.id != null) post.id!: post,
    };
    final seedIds = {
      for (final post in topic.talks)
        if (post.id != null) post.id!,
    };
    return List.unmodifiable([
      for (final post in local)
        if (post.id == null || !seedIds.contains(post.id)) post,
      for (final post in topic.talks) overrides[post.id] ?? post,
    ]);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final preferences = await SharedPreferences.getInstance();
    final pathLocale = AppLocaleParser.fromPath(_initialPath);
    final savedLocale = AppLocaleParser.fromCode(
      preferences.getString('preferredLocale'),
    );
    _locale =
        pathLocale ?? savedLocale ?? AppLocaleParser.fromDevice(_deviceLocale);
    _region = preferences.getString('region') ?? _locale.defaultRegion;
    if (_cloudRepository != null && pathLocale == null) {
      try {
        final remote = await _cloudRepository.loadUserPreferences();
        if (remote != null) {
          _locale = AppLocaleParser.fromCode(remote.preferredLocale) ?? _locale;
          _region = remote.region;
          await preferences.setString('preferredLocale', _locale.code);
          await preferences.setString('region', _region);
        }
      } on Object catch (error) {
        _cloudError = error;
      }
    }
    _themeMode = switch (preferences.getString('themeMode')) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    _animationsEnabled = preferences.getBool('animationsEnabled') ?? true;
    _anonymousId = preferences.getString('anonymousId') ?? '';
    _likedTopicIds.addAll(
      preferences.getStringList('likedTopicIds') ?? const [],
    );
    for (final entry
        in preferences.getStringList('talkReactions') ?? const []) {
      final separator = entry.lastIndexOf('=');
      if (separator > 0) {
        _talkReactions[entry.substring(0, separator)] = entry.substring(
          separator + 1,
        );
      }
    }
    _reportedTalkTargets.addAll(
      preferences.getStringList('reportedTalkTargets') ?? const [],
    );
    if (_anonymousId.isEmpty) {
      _anonymousId = 'local-${DateTime.now().microsecondsSinceEpoch}';
      await preferences.setString('anonymousId', _anonymousId);
    }
    for (final topic in await _localStore.loadTopics()) {
      _repository.add(topic);
    }
    if (_cloudRepository != null) {
      try {
        for (final topic in await _cloudRepository.loadTopics()) {
          _cloudTopicIds.add(topic.id);
          _repository.add(topic);
          await _localStore.saveTopic(topic);
        }
      } on Object catch (error) {
        _cloudError = error;
      }
      try {
        await _cloudRepository.saveUserPreferences(
          preferredLocale: _locale.code,
          region: _region,
        );
      } on Object catch (error) {
        _cloudError = error;
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('themeMode', mode.name);
  }

  Future<void> setAnimationsEnabled(bool value) async {
    if (_animationsEnabled == value) return;
    _animationsEnabled = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('animationsEnabled', value);
  }

  Future<void> setLocale(AppLocale value) async {
    if (_locale == value) return;
    _locale = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('preferredLocale', value.code);
    await _syncUserPreferences();
  }

  Future<void> setRegion(String value) async {
    final changed = _region != value;
    _region = value;
    if (changed) notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('region', value);
    await _syncUserPreferences();
  }

  Future<void> _syncUserPreferences() async {
    if (_cloudRepository == null) return;
    try {
      await _cloudRepository.saveUserPreferences(
        preferredLocale: _locale.code,
        region: _region,
      );
    } on Object catch (error) {
      _cloudError = error;
      notifyListeners();
    }
  }

  bool isTopicLiked(String topicId) => _likedTopicIds.contains(topicId);

  bool isOwnTopic(TierTopic topic) =>
      topic.creatorName == currentUserName ||
      const {'あなた', '나', 'You'}.contains(topic.creatorName) ||
      topic.id.startsWith('local-') ||
      (_cloudRepository != null &&
          topic.creatorId == _cloudRepository.currentUserId);

  Future<void> toggleTopicLike(String topicId) async {
    final topic = _repository.getById(topicId);
    if (topic == null) return;
    final wasLiked = _likedTopicIds.contains(topicId);
    final liked = !wasLiked;
    if (liked) {
      _likedTopicIds.add(topicId);
    } else {
      _likedTopicIds.remove(topicId);
    }
    final updated = topic.copyWith(
      likeCount: (topic.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 31).toInt(),
    );
    _repository.add(updated);
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      'likedTopicIds',
      _likedTopicIds.toList(growable: false),
    );
    await _localStore.saveTopic(updated);
    if (_cloudRepository == null || !_cloudTopicIds.contains(topicId)) return;
    try {
      await _cloudRepository.setTopicLike(topicId, liked: liked);
    } on Object catch (error) {
      _cloudError = error;
      if (wasLiked) {
        _likedTopicIds.add(topicId);
      } else {
        _likedTopicIds.remove(topicId);
      }
      _repository.add(topic);
      await preferences.setStringList(
        'likedTopicIds',
        _likedTopicIds.toList(growable: false),
      );
      notifyListeners();
    }
  }

  Future<void> load(String topicId) async {
    if (_loaded.contains(topicId)) return;
    final submission = await _localStore.loadSubmission(topicId);
    if (submission != null) {
      _placements[topicId] = {
        for (final rank in TierRank.values)
          rank: List.of(submission.placements[rank] ?? const []),
      };
    }
    final preferences = await SharedPreferences.getInstance();
    if (submission == null) {
      final stored =
          preferences.getStringList('placements.$topicId') ?? const [];
      final map = {for (final rank in TierRank.values) rank: <String>[]};
      for (final value in stored) {
        final parts = value.split(':');
        final rank = parts.length == 2 ? TierRank.parse(parts.first) : null;
        if (rank != null) map[rank]!.add(parts.last);
      }
      _placements[topicId] = map;
    }
    _localTalks[topicId] = List.of(await _localStore.loadTalks(topicId));
    if (_cloudRepository != null && _cloudTopicIds.contains(topicId)) {
      try {
        final cloudTalks = await _cloudRepository.loadTalks(topicId);
        final byId = <String, TalkPost>{
          for (final post in cloudTalks)
            if (post.id != null) post.id!: post,
          for (final post in _localTalks[topicId]!)
            if (post.id != null) post.id!: post,
        };
        final withoutId = _localTalks[topicId]!.where(
          (post) => post.id == null,
        );
        _localTalks[topicId] = [...withoutId, ...byId.values];
      } on Object catch (error) {
        _cloudError = error;
      }
    }
    _loaded.add(topicId);
    notifyListeners();
  }

  Future<void> setPlacements(
    String topicId,
    Map<TierRank, List<String>> value,
  ) async {
    _placements[topicId] = {
      for (final rank in TierRank.values)
        rank: List.of(value[rank] ?? const []),
    };
    _loaded.add(topicId);
    notifyListeners();
    final submission = UserTierSubmission(
      id: '$_anonymousId-$topicId',
      topicId: topicId,
      userId: _anonymousId,
      createdAt: DateTime.now(),
      placements: _placements[topicId]!,
      region: _region,
    );
    await _localStore.saveSubmission(submission);
    final topic = _repository.getById(topicId);
    if (topic != null) {
      var submissions = [submission];
      if (_cloudRepository != null && _cloudTopicIds.contains(topicId)) {
        try {
          await _cloudRepository.saveSubmission(submission);
          submissions = await _cloudRepository.loadSubmissions(topicId);
        } on Object catch (error) {
          _cloudError = error;
        }
      }
      final aggregate = _aggregationService.aggregate(topic.items, submissions);
      final updated = topic.copyWith(
        community: aggregate.ranks,
        participants: aggregate.submissionCount,
      );
      _repository.add(updated);
      if (topicId.startsWith('local-')) await _localStore.saveTopic(updated);
      notifyListeners();
    }
  }

  Future<void> addTopic(
    TierTopic topic,
    Map<TierRank, List<String>> placements,
  ) async {
    _repository.add(topic);
    _placements[topic.id] = placements;
    _loaded.add(topic.id);
    notifyListeners();
    await _localStore.saveTopic(topic);
    if (_cloudRepository != null) {
      try {
        final uploaded = await _cloudRepository.saveTopic(topic);
        _cloudTopicIds.add(uploaded.id);
        _repository.add(uploaded);
        await _localStore.saveTopic(uploaded);
      } on Object catch (error) {
        _cloudError = error;
        notifyListeners();
      }
    }
    await setPlacements(topic.id, placements);
  }

  Future<void> postTalk(
    String topicId, {
    required String body,
    required TierRank rank,
  }) async {
    final posts = _localTalks.putIfAbsent(topicId, () => []);
    posts.insert(
      0,
      TalkPost(
        id: 'talk-${DateTime.now().microsecondsSinceEpoch}',
        author: currentUserName,
        body: body,
        rank: rank,
        minutesAgo: 0,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
    await _localStore.saveTalks(topicId, posts);
    await _syncTalks(topicId, posts);
  }

  Future<void> replyToTalk(
    TierTopic topic, {
    required String postId,
    required String body,
    ReplyStance? stance,
    String? parentReplyId,
  }) async {
    final local = _localTalks.putIfAbsent(topic.id, () => []);
    var index = local.indexWhere((post) => post.id == postId);
    if (index < 0) {
      TalkPost? seed;
      for (final post in topic.talks) {
        if (post.id == postId) {
          seed = post;
          break;
        }
      }
      if (seed == null) return;
      local.add(seed);
      index = local.length - 1;
    }
    final post = local[index];
    final reply = TalkReply(
      id: 'reply-${DateTime.now().microsecondsSinceEpoch}',
      author: currentUserName,
      body: body,
      createdAt: DateTime.now(),
      stance: stance,
    );
    local[index] = post.copyWith(
      replies: parentReplyId == null
          ? [...post.replies, reply]
          : _appendNestedReply(post.replies, parentReplyId, reply),
    );
    notifyListeners();
    await _localStore.saveTalks(topic.id, local);
    await _syncTalks(topic.id, talksFor(topic));
  }

  List<TalkReply> _appendNestedReply(
    List<TalkReply> replies,
    String parentId,
    TalkReply reply,
  ) => [
    for (final current in replies)
      if (current.id == parentId)
        current.copyWith(replies: [...current.replies, reply])
      else
        current.copyWith(
          replies: _appendNestedReply(current.replies, parentId, reply),
        ),
  ];

  Future<void> reactToTalk(
    TierTopic topic, {
    required String postId,
    required bool positive,
    String? replyId,
  }) async {
    final local = _localTalks.putIfAbsent(topic.id, () => []);
    var index = local.indexWhere((post) => post.id == postId);
    if (index < 0) {
      TalkPost? seed;
      for (final candidate in topic.talks) {
        if (candidate.id == postId) {
          seed = candidate;
          break;
        }
      }
      if (seed == null) return;
      local.add(seed);
      index = local.length - 1;
    }
    final key = '${topic.id}|$postId|${replyId ?? 'root'}';
    final previous = _talkReactions[key];
    final next = positive ? 'up' : 'down';
    final togglingOff = previous == next;
    final addUp = !togglingOff && next == 'up' ? 1 : 0;
    final addDown = !togglingOff && next == 'down' ? 1 : 0;
    final removeUp = previous == 'up' ? 1 : 0;
    final removeDown = previous == 'down' ? 1 : 0;
    final post = local[index];
    if (replyId == null) {
      local[index] = post.copyWith(
        upvotes: (post.upvotes + addUp - removeUp).clamp(0, 1 << 31).toInt(),
        downvotes: (post.downvotes + addDown - removeDown)
            .clamp(0, 1 << 31)
            .toInt(),
      );
    } else {
      local[index] = post.copyWith(
        replies: _updateReplyReaction(
          post.replies,
          replyId,
          addUp - removeUp,
          addDown - removeDown,
        ),
      );
    }
    if (previous == next) {
      _talkReactions.remove(key);
    } else {
      _talkReactions[key] = next;
    }
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      'talkReactions',
      _talkReactions.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .toList(),
    );
    await _localStore.saveTalks(topic.id, local);
    await _syncTalks(topic.id, talksFor(topic));
  }

  List<TalkReply> _updateReplyReaction(
    List<TalkReply> replies,
    String replyId,
    int upDelta,
    int downDelta,
  ) => [
    for (final reply in replies)
      if (reply.id == replyId)
        reply.copyWith(
          upvotes: (reply.upvotes + upDelta).clamp(0, 1 << 31).toInt(),
          downvotes: (reply.downvotes + downDelta).clamp(0, 1 << 31).toInt(),
        )
      else
        reply.copyWith(
          replies: _updateReplyReaction(
            reply.replies,
            replyId,
            upDelta,
            downDelta,
          ),
        ),
  ];

  bool isTalkReported(
    String topicId, {
    required String postId,
    String? replyId,
  }) => _reportedTalkTargets.contains(
    '$topicId|$postId|${replyId ?? 'root'}',
  );

  Future<bool> reportTalk(
    String topicId, {
    required String postId,
    String? replyId,
  }) async {
    final key = '$topicId|$postId|${replyId ?? 'root'}';
    if (!_reportedTalkTargets.add(key)) return false;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      'reportedTalkTargets',
      _reportedTalkTargets.toList(growable: false),
    );
    if (_cloudRepository != null && _cloudTopicIds.contains(topicId)) {
      try {
        await _cloudRepository.reportTalk(
          topicId,
          postId: postId,
          replyId: replyId,
        );
      } on Object catch (error) {
        _cloudError = error;
        notifyListeners();
      }
    }
    return true;
  }

  Future<void> _syncTalks(String topicId, List<TalkPost> posts) async {
    if (_cloudRepository == null || !_cloudTopicIds.contains(topicId)) return;
    try {
      await _cloudRepository.saveTalks(topicId, posts);
    } on Object catch (error) {
      _cloudError = error;
      notifyListeners();
    }
  }

  Future<AuthResult> signUpWithEmail(String email, String password) async {
    final auth = _auth;
    if (auth == null) return const AuthResult(AuthResultStatus.generic);
    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      final current = auth.currentUser;
      if (current != null && current.isAnonymous) {
        await current.linkWithCredential(credential);
      } else {
        await auth.signInWithEmailAndPassword(email: email, password: password);
      }
      notifyListeners();
      return const AuthResult(AuthResultStatus.success);
    } on FirebaseAuthException catch (error) {
      return AuthResult.fromException(error);
    }
  }

  Future<AuthResult> signInWithEmail(String email, String password) async {
    final auth = _auth;
    if (auth == null) return const AuthResult(AuthResultStatus.generic);
    try {
      await auth.signInWithEmailAndPassword(email: email, password: password);
      notifyListeners();
      return const AuthResult(AuthResultStatus.success);
    } on FirebaseAuthException catch (error) {
      return AuthResult.fromException(error);
    }
  }

  Future<AuthResult> sendPasswordReset(String email) async {
    final auth = _auth;
    if (auth == null) return const AuthResult(AuthResultStatus.generic);
    try {
      await auth.sendPasswordResetEmail(email: email);
      return const AuthResult(AuthResultStatus.success);
    } on FirebaseAuthException catch (error) {
      return AuthResult.fromException(error);
    }
  }

  Future<void> signOut() async {
    final auth = _auth;
    if (auth == null) return;
    await auth.signOut();
    try {
      await auth.signInAnonymously();
    } on Object catch (error) {
      _cloudError = error;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Iterable<TierTopic> get startedTopics => topics.where(
    (topic) =>
        (_placements[topic.id]?.values.any((items) => items.isNotEmpty) ??
        false),
  );
}
