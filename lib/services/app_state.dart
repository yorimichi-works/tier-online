import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../models/tier_models.dart';
import '../repositories/cloud_tier_repository.dart';
import '../repositories/tier_repository.dart';
import 'local_tier_store.dart';
import 'tier_aggregation_service.dart';

class DailyCreateStatus {
  const DailyCreateStatus({
    required this.dailyTierCount,
    required this.adBonusCount,
    required this.baseLimit,
    required this.maxAdBonus,
    required this.allowed,
    required this.remaining,
  });

  factory DailyCreateStatus.fromMap(Map<String, dynamic> data) =>
      DailyCreateStatus(
        dailyTierCount: data['dailyTierCount'] as int? ?? 0,
        adBonusCount: data['adBonusCount'] as int? ?? 0,
        baseLimit: data['baseLimit'] as int? ?? 0,
        maxAdBonus: data['maxAdBonus'] as int? ?? 0,
        allowed: data['allowed'] as int? ?? 0,
        remaining: data['remaining'] as int? ?? 0,
      );

  final int dailyTierCount;
  final int adBonusCount;
  final int baseLimit;
  final int maxAdBonus;
  final int allowed;
  final int remaining;

  bool get canCreate => remaining > 0;
}

enum AuthResultStatus {
  success,
  emailInUse,
  weakPassword,
  invalidEmail,
  wrongPassword,
  userNotFound,
  credentialInUse,
  // Googleでログイン/連携しようとしたメールアドレスが、既に別の方法
  // (主にメール/パスワード)で登録済みの場合。パスワード入力後に
  // linkPendingGoogleCredential()を呼んでアカウントを統合する。
  googleAccountConflict,
  generic,
}

enum AccountDeletionStatus { success, cancelled, wrongPassword, failed }

enum GoogleAuthRecovery { signInExistingGoogle, linkDifferentProvider, none }

@visibleForTesting
GoogleAuthRecovery googleAuthRecoveryForErrorCode(
  String code,
) => switch (code) {
  // Linking an anonymous user fails with this code when the selected Google
  // credential already belongs to an existing Firebase user. This is a normal
  // returning-user sign-in, not an email/password account conflict.
  'credential-already-in-use' => GoogleAuthRecovery.signInExistingGoogle,
  'email-already-in-use' || 'account-exists-with-different-credential' =>
    GoogleAuthRecovery.linkDifferentProvider,
  _ => GoogleAuthRecovery.none,
};

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

@immutable
class AuthSessionState {
  const AuthSessionState._({required this.isRegistered, this.email});

  const AuthSessionState.guest() : this._(isRegistered: false);

  const AuthSessionState.registered({String? email})
    : this._(isRegistered: true, email: email);

  factory AuthSessionState.fromFirebaseUser(User? user) {
    if (user == null || user.isAnonymous) {
      return const AuthSessionState.guest();
    }
    return AuthSessionState.registered(email: user.email);
  }

  final bool isRegistered;
  final String? email;

  bool get isGuest => !isRegistered;
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
    bool trustLocalSharedRoutes = false,
  }) : _localStore = localStore ?? LocalTierStore(),
       _cloudRepository = cloudRepository,
       _auth = auth,
       _cloudBootstrapComplete = cloudRepository != null,
       _aggregationService = aggregationService,
       _initialPath = initialPath,
       _deviceLocale = deviceLocale,
       _trustLocalSharedRoutes = trustLocalSharedRoutes {
    _listenToAuthChanges();
  }
  final TierRepository _repository;
  final LocalTierStore _localStore;
  CloudTierRepository? _cloudRepository;
  FirebaseAuth? _auth;
  StreamSubscription<User?>? _authSubscription;
  final TierAggregationService _aggregationService;
  final String _initialPath;
  final Locale _deviceLocale;
  final bool _trustLocalSharedRoutes;
  final Map<String, Map<TierRank, List<String>>> _placements = {};
  final Map<String, List<TalkPost>> _localTalks = {};
  final Set<String> _loaded = {};
  final Set<String> _cloudTopicIds = {};
  final Set<String> _likedTopicIds = {};
  final Map<String, String> _talkReactions = {};
  final Set<String> _reportedTalkTargets = {};
  final Set<String> _reportedTopicIds = {};
  String _anonymousId = '';
  bool _initialized = false;
  bool _cloudBootstrapComplete;
  Object? _cloudError;
  ThemeMode _themeMode = ThemeMode.dark;
  bool _animationsEnabled = true;
  bool _hasSeenOnboarding = false;
  bool _languageExplicitlySelected = false;
  AppLocale _locale = AppLocale.ja;
  String _region = 'JP';

  bool get initialized => _initialized;
  bool get cloudBootstrapComplete => _cloudBootstrapComplete;
  bool get cloudEnabled => _cloudRepository != null;
  bool get trustLocalSharedRoutes => _trustLocalSharedRoutes;
  Object? get cloudError => _cloudError;

  bool get authEnabled => _auth != null;
  AuthSessionState get authSession =>
      AuthSessionState.fromFirebaseUser(_auth?.currentUser);
  bool get isAnonymous => authSession.isGuest;
  String? get userEmail => authSession.email;
  bool get accountUsesPassword {
    final providers = _auth?.currentUser?.providerData
        .map((provider) => provider.providerId)
        .toSet();
    return providers?.contains('password') == true &&
        providers?.contains('google.com') != true;
  }

  /// メール確認が必要なのに未確認のアカウントか(匿名・Google確認済みは対象外)。
  bool get needsEmailVerification {
    final user = _auth?.currentUser;
    if (user == null || user.isAnonymous) return false;
    return !user.emailVerified;
  }

  ThemeMode get themeMode => _themeMode;
  bool get animationsEnabled => _animationsEnabled;
  bool get hasSeenOnboarding => _hasSeenOnboarding;
  bool get languageExplicitlySelected => _languageExplicitlySelected;
  AppLocale get locale => _locale;
  String get region => _region;
  String get initialPath => _initialPath;
  // 匿名ユーザーの投稿者名は、あくまで自分視点の「あなた」ではなく、
  // 他の閲覧者にも意味が通る「匿名ユーザー」で保存・表示する。
  String get currentUserName => isAnonymous
      ? AppLocalizations(_locale).t('anonymousCreatorName')
      : AppLocalizations(_locale).t('currentUserName');
  String get anonymousId => _anonymousId;
  String get currentDataUserId =>
      _cloudRepository?.currentUserId ?? _anonymousId;

  void _listenToAuthChanges() {
    final auth = _auth;
    if (auth == null) return;
    // userChanges includes authStateChanges and also reacts to user reloads,
    // so every screen observes the same Firebase Auth session after sign-in,
    // sign-out, page reload, and profile/token refreshes.
    _authSubscription = auth.userChanges().listen((_) => notifyListeners());
  }

  void completeCloudBootstrap() {
    if (_cloudBootstrapComplete) return;
    _cloudBootstrapComplete = true;
    notifyListeners();
  }

  List<TierTopic> get topics => _repository.getAll();
  TierTopic? topicById(String topicId) => _repository.getById(topicId);
  List<TierTopic> get publicTopics =>
      topics.where((topic) => topic.isPublic).toList(growable: false);
  Map<TierRank, List<String>> placementsFor(String topicId) => {
    for (final rank in TierRank.values)
      rank: List.unmodifiable(_placements[topicId]?[rank] ?? const []),
  };

  Future<TierTopic?> loadTopicById(String topicId) async {
    final existing = _repository.getById(topicId);
    // Bundled starter tiers are local assets and do not have a Firestore
    // document. Every other shared URL must be revalidated against the cloud;
    // otherwise a deleted/private topic can survive in local storage.
    if (topicId.startsWith('starter-')) return existing;
    final cloudRepository = _cloudRepository;
    if (cloudRepository == null) return null;
    try {
      final topic = await cloudRepository.loadTopic(topicId);
      if (topic != null) {
        _cloudTopicIds.add(topic.id);
        _repository.add(topic);
        await _localStore.saveTopic(topic);
      } else {
        await evictCachedTopic(topicId);
      }
      _cloudError = null;
      notifyListeners();
      return topic;
    } on Object catch (error) {
      _cloudError = error;
      notifyListeners();
      rethrow;
    }
  }

  /// Removes only the device-side copy. Used after Firestore confirms that a
  /// shared topic was deleted, made private, or blocked.
  Future<void> evictCachedTopic(String topicId) async {
    if (topicId.startsWith('starter-')) return;
    _repository.remove(topicId);
    _cloudTopicIds.remove(topicId);
    _placements.remove(topicId);
    _localTalks.remove(topicId);
    _loaded.remove(topicId);
    _likedTopicIds.remove(topicId);
    _talkReactions.removeWhere((key, _) => key.startsWith('$topicId|'));
    _reportedTalkTargets.removeWhere((key) => key.startsWith('$topicId|'));
    _reportedTopicIds.remove(topicId);
    await _localStore.deleteTopic(topicId);
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setStringList(
        'likedTopicIds',
        _likedTopicIds.toList(growable: false),
      ),
      preferences.setStringList(
        'talkReactions',
        _talkReactions.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .toList(growable: false),
      ),
      preferences.setStringList(
        'reportedTalkTargets',
        _reportedTalkTargets.toList(growable: false),
      ),
      preferences.setStringList(
        'reportedTopicIds',
        _reportedTopicIds.toList(growable: false),
      ),
    ]);
    notifyListeners();
  }

  bool hasSubmitted(String topicId) =>
      _placements[topicId]?.values.any((items) => items.isNotEmpty) ?? false;

  /// 指定したユーザーの指定topicIdへの回答(placements)を取得する。
  /// 自分自身のuserId(anonymousId)の場合はローカルのplacementsを、
  /// それ以外はクラウド上のsubmissions一覧から該当ユーザーを探す。
  Future<UserTierSubmission?> loadUserSubmission(
    String topicId,
    String userId,
  ) async {
    if (userId == _anonymousId) {
      if (!hasSubmitted(topicId)) return null;
      return UserTierSubmission(
        id: '$_anonymousId-$topicId',
        topicId: topicId,
        userId: _anonymousId,
        createdAt: DateTime.now(),
        placements: _placements[topicId]!,
        region: _region,
        contentLanguage:
            _repository.getById(topicId)?.contentLanguage ?? _locale,
      );
    }
    if (_cloudRepository == null) return null;
    try {
      final submissions = await _cloudRepository!.loadSubmissions(topicId);
      for (final submission in submissions) {
        if (submission.userId == userId) return submission;
      }
    } on Object catch (error) {
      _cloudError = error;
      notifyListeners();
    }
    return null;
  }

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
      preferences.getString('preferredLanguage') ??
          preferences.getString('preferredLocale'),
    );
    _languageExplicitlySelected =
        preferences.getBool('languageExplicitlySelected') ?? false;
    ({String preferredLocale, String region})? remotePreferences;
    if (_cloudRepository != null) {
      try {
        remotePreferences = await _cloudRepository!.loadUserPreferences();
      } on Object catch (error) {
        _cloudError = error;
      }
    }
    final accountLocale = AppLocaleParser.fromCode(
      remotePreferences?.preferredLocale,
    );
    // Phase 1-A priority: explicit choice > URL > account > device > ja.
    // A legacy local value without the explicit marker remains a compatibility
    // fallback between account and device.
    _locale =
        (_languageExplicitlySelected ? savedLocale : null) ??
        pathLocale ??
        accountLocale ??
        savedLocale ??
        AppLocaleParser.fromDevice(_deviceLocale);
    _region = SupportedRegion.normalize(
      preferences.getString('region') ?? remotePreferences?.region,
      fallback: _locale.defaultRegion,
    );
    await preferences.setString('preferredLocale', _locale.code);
    await preferences.setString('preferredLanguage', _locale.storageCode);
    await preferences.setString('region', _region);
    _themeMode = switch (preferences.getString('themeMode')) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    _animationsEnabled = preferences.getBool('animationsEnabled') ?? true;
    _hasSeenOnboarding = preferences.getBool('hasSeenOnboarding') ?? false;
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
    _reportedTopicIds.addAll(
      preferences.getStringList('reportedTopicIds') ?? const [],
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
        for (final topic in await _cloudRepository!.loadTopics()) {
          _cloudTopicIds.add(topic.id);
          _repository.add(topic);
          await _localStore.saveTopic(topic);
        }
      } on Object catch (error) {
        _cloudError = error;
      }
      try {
        await _cloudRepository!.saveUserPreferences(
          preferredLocale: _locale.storageCode,
          region: _region,
        );
      } on Object catch (error) {
        _cloudError = error;
      }
    }
    _initialized = true;
    notifyListeners();
  }

  /// Connects the already-rendered local app to Firebase without delaying the
  /// first usable frame. Remote topics then replace matching starter IDs and
  /// are cached using the same rules as a normal cloud-backed startup.
  Future<void> attachCloud({
    required CloudTierRepository cloudRepository,
    required FirebaseAuth auth,
  }) async {
    if (identical(_cloudRepository, cloudRepository) &&
        identical(_auth, auth)) {
      return;
    }
    await _authSubscription?.cancel();
    _cloudRepository = cloudRepository;
    _auth = auth;
    _listenToAuthChanges();

    try {
      final preferences = await SharedPreferences.getInstance();
      final explicitLocale =
          preferences.getBool('languageExplicitlySelected') ?? false;
      final pathLocale = AppLocaleParser.fromPath(_initialPath);
      final remote = await cloudRepository.loadUserPreferences();
      if (!explicitLocale && pathLocale == null && remote != null) {
        _locale = AppLocaleParser.fromCode(remote.preferredLocale) ?? _locale;
      }
      if (remote != null && preferences.getString('region') == null) {
        _region = SupportedRegion.normalize(
          remote.region,
          fallback: _locale.defaultRegion,
        );
      }
      await preferences.setString('preferredLocale', _locale.code);
      await preferences.setString('preferredLanguage', _locale.storageCode);
      await preferences.setString('region', _region);
      for (final topic in await cloudRepository.loadTopics()) {
        _cloudTopicIds.add(topic.id);
        _repository.add(topic);
        await _localStore.saveTopic(topic);
      }
      await cloudRepository.saveUserPreferences(
        preferredLocale: _locale.storageCode,
        region: _region,
      );
      _cloudError = null;
    } on Object catch (error) {
      _cloudError = error;
    }
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

  Future<void> markOnboardingSeen() async {
    if (_hasSeenOnboarding) return;
    _hasSeenOnboarding = true;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('hasSeenOnboarding', true);
  }

  Future<void> setLocale(AppLocale value) async {
    final changed = _locale != value;
    _locale = value;
    _languageExplicitlySelected = true;
    if (changed) notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('preferredLocale', value.code);
    await preferences.setString('preferredLanguage', value.storageCode);
    await preferences.setBool('languageExplicitlySelected', true);
    await _syncUserPreferences();
  }

  Future<void> setRegion(String value) async {
    final normalized = SupportedRegion.normalize(value);
    final changed = _region != normalized;
    _region = normalized;
    if (changed) notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('region', normalized);
    await _syncUserPreferences();
  }

  Future<void> _syncUserPreferences() async {
    if (_cloudRepository == null) return;
    try {
      await _cloudRepository!.saveUserPreferences(
        preferredLocale: _locale.storageCode,
        region: _region,
      );
    } on Object catch (error) {
      _cloudError = error;
      notifyListeners();
    }
  }

  bool isTopicLiked(String topicId) => _likedTopicIds.contains(topicId);

  bool isOwnTopic(TierTopic topic) {
    final creatorId = topic.creatorId;
    if (creatorId != null || _cloudTopicIds.contains(topic.id)) {
      return _cloudRepository != null &&
          creatorId == _cloudRepository!.currentUserId;
    }
    return topic.id.startsWith('t-') ||
        topic.id.startsWith('local-') || // 旧ID形式との互換用
        topic.creatorName == currentUserName ||
        // 旧仕様(自分視点の「あなた」等)で保存された既存データとの互換用。
        const {
          'あなた',
          '나',
          '你',
          'Você',
          'You',
          '匿名ユーザー',
          '익명 사용자',
          '匿名使用者',
          'Usuário anônimo',
          'Anonymous user',
        }.contains(topic.creatorName);
  }

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
      await _cloudRepository!.setTopicLike(topicId, liked: liked);
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
        final cloudTalks = await _cloudRepository!.loadTalks(topicId);
        final byId = <String, TalkPost>{
          for (final post in _localTalks[topicId]!)
            if (post.id != null) post.id!: post,
          for (final post in cloudTalks)
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
    final topic = _repository.getById(topicId);
    final submission = UserTierSubmission(
      id: '$_anonymousId-$topicId',
      topicId: topicId,
      userId: _anonymousId,
      createdAt: DateTime.now(),
      placements: _placements[topicId]!,
      region: _region,
      contentLanguage: topic?.contentLanguage ?? _locale,
    );
    await _localStore.saveSubmission(submission);
    if (topic != null) {
      var submissions = [submission];
      if (_cloudRepository != null && _cloudTopicIds.contains(topicId)) {
        try {
          await _cloudRepository!.saveSubmission(submission);
          submissions = await _cloudRepository!.loadSubmissions(topicId);
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
      if (topicId.startsWith('t-') || topicId.startsWith('local-')) {
        await _localStore.saveTopic(updated);
      }
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
      final uploaded = await _cloudRepository!.saveTopic(topic);
      _cloudTopicIds.add(uploaded.id);
      _repository.add(uploaded);
      await _localStore.saveTopic(uploaded);
    }
    await setPlacements(topic.id, placements);
  }

  Future<void> setTopicPublic(TierTopic topic, bool isPublic) async {
    if (!isOwnTopic(topic) || topic.isPublic == isPublic) return;
    final updated = topic.copyWith(isPublic: isPublic);
    _repository.add(updated);
    notifyListeners();
    await _localStore.saveTopic(updated);
    if (_cloudRepository != null && _cloudTopicIds.contains(topic.id)) {
      try {
        await _cloudRepository!.setTopicPublic(topic.id, isPublic: isPublic);
      } on Object catch (error) {
        _cloudError = error;
        _repository.add(topic);
        await _localStore.saveTopic(topic);
        notifyListeners();
      }
    }
  }

  Future<bool> deleteOwnTopic(TierTopic topic) async {
    if (!isOwnTopic(topic)) return false;
    try {
      if (_cloudRepository != null && _cloudTopicIds.contains(topic.id)) {
        await _cloudRepository!.deleteTopic(topic.id);
        _cloudTopicIds.remove(topic.id);
      }
    } on Object catch (error) {
      _cloudError = error;
      notifyListeners();
      return false;
    }
    _repository.remove(topic.id);
    _placements.remove(topic.id);
    _localTalks.remove(topic.id);
    _loaded.remove(topic.id);
    _likedTopicIds.remove(topic.id);
    _talkReactions.removeWhere((key, _) => key.startsWith('${topic.id}|'));
    _reportedTalkTargets.removeWhere((key) => key.startsWith('${topic.id}|'));
    _reportedTopicIds.remove(topic.id);
    await _localStore.deleteTopic(topic.id);
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setStringList(
        'likedTopicIds',
        _likedTopicIds.toList(growable: false),
      ),
      preferences.setStringList(
        'talkReactions',
        _talkReactions.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .toList(growable: false),
      ),
      preferences.setStringList(
        'reportedTalkTargets',
        _reportedTalkTargets.toList(growable: false),
      ),
      preferences.setStringList(
        'reportedTopicIds',
        _reportedTopicIds.toList(growable: false),
      ),
    ]);
    _cloudError = null;
    notifyListeners();
    return true;
  }

  Future<void> postTalk(
    String topicId, {
    required String body,
    required TierRank rank,
    bool attachOwnTier = false,
  }) async {
    final posts = _localTalks.putIfAbsent(topicId, () => []);
    final post = TalkPost(
      id: 'talk-${DateTime.now().microsecondsSinceEpoch}',
      author: currentUserName,
      body: body,
      rank: rank,
      minutesAgo: 0,
      createdAt: DateTime.now(),
      authorUserId: currentDataUserId,
      attachedTier: attachOwnTier,
    );
    posts.insert(0, post);
    notifyListeners();
    await _localStore.saveTalks(topicId, posts);
    await _syncTalkWrite(topicId, (cloud) => cloud.createTalk(topicId, post));
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
      authorUserId: currentDataUserId,
    );
    local[index] = post.copyWith(
      replies: parentReplyId == null
          ? [...post.replies, reply]
          : _appendNestedReply(post.replies, parentReplyId, reply),
    );
    notifyListeners();
    await _localStore.saveTalks(topic.id, local);
    await _syncTalkWrite(
      topic.id,
      (cloud) => cloud.createTalkReply(
        topic.id,
        postId,
        reply,
        parentReplyId: parentReplyId,
      ),
    );
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
    await _syncTalkWrite(
      topic.id,
      (cloud) => cloud.setTalkReaction(
        topic.id,
        postId,
        replyId: replyId,
        reaction: togglingOff ? null : next,
      ),
    );
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
  }) => _reportedTalkTargets.contains('$topicId|$postId|${replyId ?? 'root'}');

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
        await _cloudRepository!.reportTalk(
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

  Future<void> _syncTalkWrite(
    String topicId,
    Future<void> Function(CloudTierRepository cloud) write,
  ) async {
    if (_cloudRepository == null || !_cloudTopicIds.contains(topicId)) return;
    try {
      await write(_cloudRepository!);
      final cloudTalks = await _cloudRepository!.loadTalks(topicId);
      // Keep local-only pending posts. Confirmed cloud versions take precedence
      // for matching IDs so activity never rewrites stale content.
      final localTalks = _localTalks[topicId] ?? const <TalkPost>[];
      final byId = <String, TalkPost>{
        for (final post in localTalks)
          if (post.id != null) post.id!: post,
        for (final post in cloudTalks)
          if (post.id != null) post.id!: post,
      };
      _localTalks[topicId] = [
        ...localTalks.where((post) => post.id == null),
        ...byId.values,
      ];
      await _localStore.saveTalks(topicId, _localTalks[topicId]!);
      notifyListeners();
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
      await _sendVerificationEmail();
      notifyListeners();
      return const AuthResult(AuthResultStatus.success);
    } on FirebaseAuthException catch (error) {
      return AuthResult.fromException(error);
    }
  }

  /// Firebase Authenticationの標準メールを現在の表示言語で送る。
  /// 独自Action URLの更新制限が解除されたら、送信方式を変えずにリンク先だけ
  /// Firebase Consoleから独自ハンドラーへ切り替えられる。
  Future<bool> _sendVerificationEmail() async {
    final user = _auth?.currentUser;
    if (user == null || user.isAnonymous || user.emailVerified) return true;
    try {
      await _auth!.setLanguageCode(_locale.firebaseAuthCode);
      await user.sendEmailVerification();
      _cloudError = null;
      return true;
    } on Object catch (error) {
      _cloudError = error;
      notifyListeners();
      return false;
    }
  }

  /// メール再送。呼び出し元でクールダウン(30〜60秒)を管理すること。
  Future<bool> resendVerificationEmail() => _sendVerificationEmail();

  /// Firebaseからユーザー情報を再取得し、最新のemailVerified状態を返す。
  Future<bool> refreshEmailVerified() async {
    final user = _auth?.currentUser;
    if (user == null) return false;
    await user.reload();
    notifyListeners();
    return _auth?.currentUser?.emailVerified ?? false;
  }

  /// Firebaseの標準画面を使わず、Tier表オンライン内のメール確認ページで
  /// one-time action codeを適用する。
  Future<bool> applyEmailVerificationActionCode(String code) async {
    final auth = _auth;
    if (auth == null || code.isEmpty) return false;
    try {
      await auth.applyActionCode(code);
      await auth.currentUser?.reload();
      _cloudError = null;
      notifyListeners();
      return true;
    } on Object catch (error) {
      _cloudError = error;
      notifyListeners();
      return false;
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

  /// Googleでのログイン/連携が「このメールは別方式で登録済み」で失敗した際、
  /// パスワード確認後に統合できるよう保持しておく認証情報とメールアドレス。
  AuthCredential? _pendingGoogleCredential;
  String? _pendingGoogleEmail;
  String? get pendingGoogleAccountEmail => _pendingGoogleEmail;
  void clearPendingGoogleCredential() {
    _pendingGoogleCredential = null;
    _pendingGoogleEmail = null;
  }

  /// Web版はブラウザのモバイル判定で分岐する。モバイルSafari/Chromeでは
  /// `google_sign_in`パッケージのポップアップ実装(既にdeprecated)がタブ制御
  /// を誤り、ログイン完了後に元のタブへ戻らず他のタブへ遷移してしまう不具合
  /// があったため、Firebase Auth純正のリダイレクト方式に切り替えている。
  /// デスクトップWebはポップアップのままの方がUXが良いため維持し、ネイティブ
  /// (Android/iOSアプリ)は引き続き`google_sign_in`パッケージを使う。
  bool get _isMobileWeb =>
      kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<AuthResult> _recoverGoogleAuthError(
    FirebaseAuth auth,
    FirebaseAuthException error,
    AuthCredential? credential, {
    String? email,
  }) async {
    final pending = credential ?? error.credential;
    switch (googleAuthRecoveryForErrorCode(error.code)) {
      case GoogleAuthRecovery.signInExistingGoogle:
        if (pending == null) return AuthResult.fromException(error);
        try {
          await auth.signInWithCredential(pending);
          clearPendingGoogleCredential();
          notifyListeners();
          return const AuthResult(AuthResultStatus.success);
        } on FirebaseAuthException catch (signInError) {
          return AuthResult.fromException(signInError);
        }
      case GoogleAuthRecovery.linkDifferentProvider:
        if (pending == null) return AuthResult.fromException(error);
        _pendingGoogleCredential = pending;
        _pendingGoogleEmail = error.email ?? email;
        notifyListeners();
        return const AuthResult(AuthResultStatus.googleAccountConflict);
      case GoogleAuthRecovery.none:
        return AuthResult.fromException(error);
    }
  }

  Future<AuthResult> signInWithGoogle() async {
    final auth = _auth;
    if (auth == null) return const AuthResult(AuthResultStatus.generic);
    if (kIsWeb) return _signInWithGoogleWeb(auth);

    GoogleSignInAccount? googleUser;
    AuthCredential? credential;
    try {
      final googleSignIn = GoogleSignIn();
      googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        return const AuthResult(AuthResultStatus.generic);
      }
      final googleAuth = await googleUser.authentication;
      credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final current = auth.currentUser;
      if (current != null && current.isAnonymous) {
        await current.linkWithCredential(credential);
      } else {
        await auth.signInWithCredential(credential);
      }
      clearPendingGoogleCredential();
      notifyListeners();
      return const AuthResult(AuthResultStatus.success);
    } on FirebaseAuthException catch (error) {
      return _recoverGoogleAuthError(
        auth,
        error,
        credential,
        email: googleUser?.email,
      );
    } on Object catch (error) {
      _cloudError = error;
      notifyListeners();
      return const AuthResult(AuthResultStatus.generic);
    }
  }

  Future<AuthResult> _signInWithGoogleWeb(FirebaseAuth auth) async {
    final provider = GoogleAuthProvider();
    final current = auth.currentUser;
    try {
      if (_isMobileWeb) {
        // ページ遷移が発生し、ここから先は基本的に戻ってこない。完了後は
        // アプリ再読み込み時にconsumeGoogleRedirectResult()が結果を処理する。
        if (current != null && current.isAnonymous) {
          await current.linkWithRedirect(provider);
        } else {
          await auth.signInWithRedirect(provider);
        }
        return const AuthResult(AuthResultStatus.success);
      }
      if (current != null && current.isAnonymous) {
        await current.linkWithPopup(provider);
      } else {
        await auth.signInWithPopup(provider);
      }
      clearPendingGoogleCredential();
      notifyListeners();
      return const AuthResult(AuthResultStatus.success);
    } on FirebaseAuthException catch (error) {
      return _recoverGoogleAuthError(auth, error, null);
    } on Object catch (error) {
      _cloudError = error;
      notifyListeners();
      return const AuthResult(AuthResultStatus.generic);
    }
  }

  /// アプリ起動時に一度だけ呼ぶ。直前のsignInWithRedirect/linkWithRedirectが
  /// アカウント競合で失敗していた場合、ここでgoogleAccountConflictとして
  /// 検出しUIに伝える(成功時は既存のuserChanges()購読で自動的に反映される)。
  Future<AuthResult?> consumeGoogleRedirectResult() async {
    final auth = _auth;
    if (auth == null || !kIsWeb) return null;
    try {
      final credential = await auth.getRedirectResult();
      if (credential.user == null) return null;
      clearPendingGoogleCredential();
      notifyListeners();
      return const AuthResult(AuthResultStatus.success);
    } on FirebaseAuthException catch (error) {
      return _recoverGoogleAuthError(auth, error, null);
    } on Object {
      return null;
    }
  }

  /// [pendingGoogleAccountEmail]のパスワードでサインインし、直前に失敗した
  /// Google認証情報をそのアカウントに連携する。以降はメール/パスワードと
  /// Googleのどちらでもログインできる。
  Future<AuthResult> linkPendingGoogleCredential(String password) async {
    final auth = _auth;
    final pending = _pendingGoogleCredential;
    final email = _pendingGoogleEmail;
    if (auth == null || pending == null || email == null) {
      return const AuthResult(AuthResultStatus.generic);
    }
    try {
      await auth.signInWithEmailAndPassword(email: email, password: password);
      try {
        await auth.currentUser?.linkWithCredential(pending);
      } on FirebaseAuthException catch (error) {
        if (error.code != 'provider-already-linked') rethrow;
      }
      clearPendingGoogleCredential();
      notifyListeners();
      return const AuthResult(AuthResultStatus.success);
    } on FirebaseAuthException catch (error) {
      return AuthResult.fromException(error);
    }
  }

  /// 本日のTier表作成状況(基本枠・広告ボーナス枠)を取得する。
  Future<DailyCreateStatus?> loadDailyCreateStatus() async {
    if (_auth == null) return null;
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'getDailyCreateStatus',
      );
      final result = await callable.call<Map<String, dynamic>>();
      return DailyCreateStatus.fromMap(
        Map<String, dynamic>.from(result.data as Map),
      );
    } on Object catch (error) {
      _cloudError = error;
      notifyListeners();
      return null;
    }
  }

  /// リワード広告視聴による作成ボーナス+1を申請する。広告視聴が完了した
  /// 場合にのみ呼び出すこと(トークンはサーバー側で有効期限・一回性を検証)。
  Future<DailyCreateStatus?> claimCreateAdBonus() async {
    if (isAnonymous) return null;
    try {
      final tokenCallable = FirebaseFunctions.instance.httpsCallable(
        'requestCreateAdBonusToken',
      );
      final tokenResult = await tokenCallable.call<Map<String, dynamic>>();
      final token = (tokenResult.data as Map)['token'] as String;

      // 実際の広告視聴はUI側(RewardedAdService)で行われ、視聴完了後にこの
      // メソッドが呼ばれる想定。ここではトークンを確定させるのみ。
      final confirmCallable = FirebaseFunctions.instance.httpsCallable(
        'confirmCreateAdBonus',
      );
      await confirmCallable.call<Map<String, dynamic>>({'token': token});
      return await loadDailyCreateStatus();
    } on Object catch (error) {
      _cloudError = error;
      notifyListeners();
      return null;
    }
  }

  /// 利用規約・プライバシーポリシー記載の問い合わせ/削除依頼窓口。認証状態
  /// (匿名含む)に関わらず送信できる。
  Future<bool> submitContactRequest({
    required String category,
    required String message,
    String? contactEmail,
    String? relatedUrl,
  }) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'submitContactRequest',
      );
      await callable.call<Map<String, dynamic>>({
        'category': category,
        'message': message,
        if (contactEmail != null && contactEmail.isNotEmpty)
          'contactEmail': contactEmail,
        if (relatedUrl != null && relatedUrl.isNotEmpty)
          'relatedUrl': relatedUrl,
      });
      return true;
    } on Object catch (error) {
      _cloudError = error;
      notifyListeners();
      return false;
    }
  }

  bool isTopicReported(String topicId) => _reportedTopicIds.contains(topicId);

  Future<bool> reportTopic(
    String topicId, {
    String reason = 'user_report',
  }) async {
    if (!_reportedTopicIds.add(topicId)) return false;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      'reportedTopicIds',
      _reportedTopicIds.toList(growable: false),
    );
    if (_cloudRepository != null) {
      try {
        final submitted = await _cloudRepository!.reportTopic(
          topicId,
          reason: reason,
        );
        if (!submitted) return false;
      } on Object catch (error) {
        _cloudError = error;
        notifyListeners();
      }
    }
    return true;
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

  Future<AccountDeletionStatus> deleteAccount({String? password}) async {
    final auth = _auth;
    final user = auth?.currentUser;
    if (auth == null || user == null || user.isAnonymous) {
      return AccountDeletionStatus.failed;
    }
    try {
      if (accountUsesPassword) {
        final email = user.email;
        if (email == null || password == null || password.isEmpty) {
          return AccountDeletionStatus.wrongPassword;
        }
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: email, password: password),
        );
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) return AccountDeletionStatus.cancelled;
        final googleAuth = await googleUser.authentication;
        await user.reauthenticateWithCredential(
          GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          ),
        );
      }
      await auth.currentUser?.getIdToken(true);
      final ownedTopicIds = createdTopics.map((topic) => topic.id).toList();
      await FirebaseFunctions.instance
          .httpsCallable('deleteUserAccount')
          .call<Map<String, dynamic>>();

      for (final topicId in ownedTopicIds) {
        _repository.remove(topicId);
        _cloudTopicIds.remove(topicId);
      }
      _placements.clear();
      _localTalks.clear();
      _loaded.clear();
      _likedTopicIds.clear();
      _talkReactions.clear();
      _reportedTalkTargets.clear();
      _reportedTopicIds.clear();
      await _localStore.clearUserData();
      final preferences = await SharedPreferences.getInstance();
      await Future.wait([
        preferences.remove('likedTopicIds'),
        preferences.remove('talkReactions'),
        preferences.remove('reportedTalkTargets'),
        preferences.remove('reportedTopicIds'),
        preferences.remove('anonymousId'),
      ]);
      _anonymousId = 'local-${DateTime.now().microsecondsSinceEpoch}';
      await preferences.setString('anonymousId', _anonymousId);
      await auth.signOut();
      await auth.signInAnonymously();
      _cloudError = null;
      notifyListeners();
      return AccountDeletionStatus.success;
    } on FirebaseAuthException catch (error) {
      _cloudError = error;
      notifyListeners();
      if (error.code == 'wrong-password' ||
          error.code == 'invalid-credential') {
        return AccountDeletionStatus.wrongPassword;
      }
      return AccountDeletionStatus.failed;
    } on Object catch (error) {
      _cloudError = error;
      notifyListeners();
      return AccountDeletionStatus.failed;
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Iterable<TierTopic> get startedTopics =>
      topics.where((topic) => isOwnTopic(topic) || hasSubmitted(topic.id));

  Iterable<TierTopic> get createdTopics => topics.where(isOwnTopic);

  Iterable<TierTopic> get joinedTopics =>
      topics.where((topic) => !isOwnTopic(topic) && hasSubmitted(topic.id));
}
