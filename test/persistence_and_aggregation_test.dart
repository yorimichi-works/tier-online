import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tier_table_online/l10n/app_localizations.dart';
import 'package:tier_table_online/models/tier_models.dart';
import 'package:tier_table_online/repositories/cloud_tier_repository.dart';
import 'package:tier_table_online/repositories/dummy_tier_repository.dart';
import 'package:tier_table_online/services/app_state.dart';
import 'package:tier_table_online/services/local_tier_store.dart';
import 'package:tier_table_online/services/tier_aggregation_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('JPは日本語、KRは韓国語、それ以外は英語へ振り分ける', () {
    expect(AppLocaleParser.fromDevice(const Locale('en', 'JP')), AppLocale.ja);
    expect(AppLocaleParser.fromDevice(const Locale('en', 'KR')), AppLocale.ko);
    expect(AppLocaleParser.fromDevice(const Locale('fr', 'FR')), AppLocale.en);
    expect(AppLocaleParser.fromDevice(const Locale('ja')), AppLocale.ja);
  });

  test('いいね・うーん・通報の文言を3言語で提供する', () {
    for (final entry in const [
      (AppLocale.ja, '👍 いいね 0', '🤔 うーん 0', '通報する'),
      (AppLocale.ko, '👍 좋아요 0', '🤔 글쎄요 0', '신고하기'),
      (AppLocale.en, '👍 Like 0', '🤔 Hmm 0', 'Report'),
    ]) {
      final l10n = AppLocalizations(entry.$1);
      expect(l10n.format('reactionLike', const {'count': 0}), entry.$2);
      expect(l10n.format('reactionHmm', const {'count': 0}), entry.$3);
      expect(l10n.t('reportComment'), entry.$4);
    }
  });

  test('作成テーマ・画像・投稿・配置を復元できる', () async {
    final store = LocalTierStore();
    const item = TierItem(
      id: 'local-1-0',
      topicId: 'local-1',
      sortIndex: 0,
      imageUrl: 'data:image/jpeg;base64,AA==',
    );
    const topic = TierTopic(
      id: 'local-1',
      title: '画像だけのTier',
      description: '',
      tags: ['写真'],
      category: 'その他',
      creatorName: 'あなた',
      participants: 1,
      items: [item],
      community: {'local-1-0': TierRank.s},
    );
    final submission = UserTierSubmission(
      id: 'submission-1',
      topicId: topic.id,
      userId: 'anonymous-1',
      createdAt: DateTime(2026),
      placements: {
        TierRank.s: [item.id],
      },
    );
    final talk = TalkPost(
      id: 'talk-1',
      author: 'あなた',
      body: 'これはS',
      rank: TierRank.s,
      minutesAgo: 0,
      createdAt: DateTime(2026),
      replies: [
        TalkReply(
          id: 'reply-1',
          author: '返信者',
          body: '賛成です',
          createdAt: DateTime(2026),
          stance: ReplyStance.agree,
        ),
      ],
    );

    await store.saveTopic(topic);
    await store.saveSubmission(submission);
    await store.saveTalks(topic.id, [talk]);

    final restoredTopic = (await store.loadTopics()).single;
    final restoredSubmission = await store.loadSubmission(topic.id);
    final restoredTalk = (await store.loadTalks(topic.id)).single;
    expect(restoredTopic.items.single.name, isNull);
    expect(restoredTopic.items.single.imageUrl, item.imageUrl);
    expect(restoredSubmission!.placements[TierRank.s], [item.id]);
    expect(restoredTalk.body, 'これはS');
    expect(restoredTalk.replies.single.stance, ReplyStance.agree);
  });

  test('複数回答の単純平均と評価分散を集計できる', () {
    const item = TierItem(
      id: 'item-1',
      topicId: 'topic-1',
      sortIndex: 0,
      name: '対象',
    );
    final submissions = [
      UserTierSubmission(
        id: 'a',
        topicId: 'topic-1',
        userId: 'a',
        createdAt: DateTime(2026),
        placements: const {
          TierRank.s: ['item-1'],
        },
      ),
      UserTierSubmission(
        id: 'b',
        topicId: 'topic-1',
        userId: 'b',
        createdAt: DateTime(2026),
        placements: const {
          TierRank.d: ['item-1'],
        },
      ),
    ];

    final aggregate = const TierAggregationService().aggregate(const [
      item,
    ], submissions);
    expect(aggregate.ranks[item.id], TierRank.b);
    expect(aggregate.distributions[item.id]![TierRank.s], 1);
    expect(aggregate.disagreement[item.id], greaterThan(0));
  });

  test('Firebase接続時は評価を同期して集合Tierを更新する', () async {
    final cloud = _FakeCloudTierRepository();
    final state = AppState(DummyTierRepository(), cloudRepository: cloud);
    await state.initialize();
    await state.load('cloud-topic');
    await state.setPlacements('cloud-topic', const {
      TierRank.ss: ['cloud-item'],
    });

    expect(cloud.savedSubmissions, hasLength(1));
    expect(
      state.topics
          .firstWhere((topic) => topic.id == 'cloud-topic')
          .participants,
      1,
    );
  });

  test('テーマのいいねは同じ利用者が切り替えて集計できる', () async {
    final repository = DummyTierRepository();
    final state = AppState(repository);
    await state.initialize();
    final before = repository.getById('yokai')!.likeCount;

    await state.toggleTopicLike('yokai');
    expect(state.isTopicLiked('yokai'), isTrue);
    expect(repository.getById('yokai')!.likeCount, before + 1);

    await state.toggleTopicLike('yokai');
    expect(state.isTopicLiked('yokai'), isFalse);
    expect(repository.getById('yokai')!.likeCount, before);
  });

  test('テーマの顔は最上位Tierで最も左のカードになる', () {
    const items = [
      TierItem(id: 'a', topicId: 'face', sortIndex: 0, name: 'A'),
      TierItem(id: 'ss-left', topicId: 'face', sortIndex: 1, name: '左'),
      TierItem(id: 'ss-right', topicId: 'face', sortIndex: 2, name: '右'),
    ];
    const topic = TierTopic(
      id: 'face',
      title: '顔テスト',
      description: '',
      tags: [],
      category: 'その他',
      creatorName: 'テスト',
      participants: 1,
      items: items,
      community: {
        'a': TierRank.a,
        'ss-left': TierRank.ss,
        'ss-right': TierRank.ss,
      },
    );
    expect(topic.faceItem, items[1]);
    expect(topic.faceRank, TierRank.ss);
  });

  test('返信への返信とコメントリアクションを保存できる', () async {
    final repository = DummyTierRepository();
    final state = AppState(repository);
    await state.initialize();
    final topic = repository.getById('yokai')!;
    await state.load(topic.id);
    const postId = 'yokai-talk-1';

    await state.replyToTalk(
      topic,
      postId: postId,
      body: '最初の返信',
      stance: ReplyStance.agree,
    );
    final firstReply = state
        .talksFor(topic)
        .firstWhere((post) => post.id == postId)
        .replies
        .single;
    await state.replyToTalk(
      topic,
      postId: postId,
      parentReplyId: firstReply.id,
      body: '返信への返信',
    );
    await state.reactToTalk(topic, postId: postId, positive: true);
    await state.reactToTalk(
      topic,
      postId: postId,
      replyId: firstReply.id,
      positive: false,
    );

    final updated = state
        .talksFor(topic)
        .firstWhere((post) => post.id == postId);
    expect(updated.upvotes, 1);
    expect(updated.replies.single.downvotes, 1);
    expect(updated.replies.single.replies.single.body, '返信への返信');
  });

  test('言語と地域の設定を独立して保持できる', () async {
    final state = AppState(DummyTierRepository());
    await state.initialize();
    await state.setLocale(AppLocale.ko);
    await state.setRegion('JP');

    final restored = AppState(DummyTierRepository());
    await restored.initialize();
    expect(restored.locale, AppLocale.ko);
    expect(restored.region, 'JP');
  });

  test('アニメーション設定を再起動後も保持できる', () async {
    final state = AppState(DummyTierRepository());
    await state.initialize();
    expect(state.animationsEnabled, isTrue);
    await state.setAnimationsEnabled(false);

    final restored = AppState(DummyTierRepository());
    await restored.initialize();
    expect(restored.animationsEnabled, isFalse);
  });

  test('コメント通報を重複させず再起動後も保持できる', () async {
    final state = AppState(DummyTierRepository());
    await state.initialize();
    expect(await state.reportTalk('yokai', postId: 'yokai-talk-1'), isTrue);
    expect(await state.reportTalk('yokai', postId: 'yokai-talk-1'), isFalse);

    final restored = AppState(DummyTierRepository());
    await restored.initialize();
    expect(restored.isTalkReported('yokai', postId: 'yokai-talk-1'), isTrue);
  });

  test('Tierの言語・対象地域・派生元を保存して復元できる', () async {
    const topic = TierTopic(
      id: 'localized-tier',
      title: '게임 티어',
      description: '',
      tags: ['게임'],
      category: '게임',
      categoryId: 'games',
      creatorName: '사용자',
      participants: 1,
      items: [],
      community: {},
      contentLanguage: AppLocale.ko,
      targetRegion: 'KR',
      sourceTierId: 'source-tier',
    );
    final store = LocalTierStore();
    await store.saveTopic(topic);
    final restored = (await store.loadTopics()).single;

    expect(restored.contentLanguage, AppLocale.ko);
    expect(restored.targetRegion, 'KR');
    expect(restored.categoryId, 'games');
    expect(restored.sourceTierId, 'source-tier');
  });
}

class _FakeCloudTierRepository implements CloudTierRepository {
  final submissions = <UserTierSubmission>[];
  final savedSubmissions = <UserTierSubmission>[];

  @override
  String get currentUserId => 'firebase-user';

  @override
  Future<List<TierTopic>> loadTopics() async => const [
    TierTopic(
      id: 'cloud-topic',
      title: 'クラウドTier',
      description: '',
      tags: ['共有'],
      category: 'その他',
      creatorName: 'あなた',
      creatorId: 'firebase-user',
      participants: 0,
      items: [
        TierItem(
          id: 'cloud-item',
          topicId: 'cloud-topic',
          sortIndex: 0,
          name: '対象',
        ),
      ],
      community: {},
    ),
  ];

  @override
  Future<TierTopic> saveTopic(TierTopic topic) async => topic;

  @override
  Future<void> saveSubmission(UserTierSubmission submission) async {
    savedSubmissions.add(submission);
    submissions
      ..removeWhere((existing) => existing.userId == submission.userId)
      ..add(submission);
  }

  @override
  Future<List<UserTierSubmission>> loadSubmissions(String topicId) async =>
      List.of(submissions);

  @override
  Future<List<TalkPost>> loadTalks(String topicId) async => const [];

  @override
  Future<void> saveTalks(String topicId, List<TalkPost> posts) async {}

  @override
  Future<void> reportTalk(
    String topicId, {
    required String postId,
    String? replyId,
  }) async {}

  @override
  Future<void> setTopicLike(String topicId, {required bool liked}) async {}

  @override
  Future<void> saveUserPreferences({
    required String preferredLocale,
    required String region,
  }) async {}

  @override
  Future<({String preferredLocale, String region})?>
  loadUserPreferences() async => null;
}
