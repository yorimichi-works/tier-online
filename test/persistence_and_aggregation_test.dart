import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:tier_table_online/domain/talk_reactions.dart';
import 'package:tier_table_online/domain/talk_activity.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tier_table_online/l10n/app_localizations.dart';
import 'package:tier_table_online/models/tier_models.dart';
import 'package:tier_table_online/models/tier_serialization.dart';
import 'package:tier_table_online/repositories/cloud_tier_repository.dart';
import 'package:tier_table_online/repositories/dummy_tier_repository.dart';
import 'package:tier_table_online/services/app_state.dart';
import 'package:tier_table_online/services/local_tier_store.dart';
import 'package:tier_table_online/services/tier_aggregation_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'a deleted reply target is isolated while other replies, posts and votes proceed',
    () async {
      final cloud = _FakeCloudTierRepository()..denyTalkReplies = true;
      const gone = TalkPost(
        id: 'gone',
        author: 'former',
        body: 'former parent',
        rank: TierRank.b,
        minutesAgo: 0,
      );
      const healthy = TalkPost(
        id: 'healthy',
        author: 'other',
        body: 'healthy body',
        rank: TierRank.b,
        minutesAgo: 0,
      );
      cloud.createdTalks.addAll([gone, healthy]);
      final store = LocalTierStore(), repository = DummyTierRepository();
      final state = AppState(
        repository,
        cloudRepository: cloud,
        localStore: store,
      );
      await state.initialize();
      final topic = repository.getById('cloud-topic')!;
      await state.load(topic.id);
      expect(
        await state.replyToTalk(
          topic,
          postId: 'gone',
          body: 'keep orphaned draft',
        ),
        isFalse,
      );
      cloud.denyTalkReplies = false;
      cloud.createdTalks.removeWhere(
        (post) => post.id == 'gone',
      ); // Author account cleanup fixture.
      expect(
        await state.replyToTalk(topic, postId: 'healthy', body: 'valid reply'),
        isTrue,
      );
      var pending = (await store.loadPendingTalkReplies(
        cloud.userId,
        topic.id,
      )).single;
      expect(pending.reply.body, 'keep orphaned draft');
      expect(pending.requiresManualRetry, isTrue);
      expect(pending.failureCode, 'parent-unavailable');
      final attempts = cloud.replyAttempts.where((id) => id == 'gone').length;
      await state.postTalk(
        topic.id,
        body: 'a new post still works',
        rank: TierRank.a,
      );
      await state.reactToTalk(topic, postId: 'healthy', positive: true);
      expect(
        cloud.createdTalks.any((post) => post.body == 'a new post still works'),
        isTrue,
      );
      expect(cloud.votes['firebase-user|healthy']?['root'], 'up');
      expect(cloud.replyAttempts.where((id) => id == 'gone').length, attempts);
      expect(await state.retryPendingTalkReplies(topic.id), isFalse);
      pending = (await store.loadPendingTalkReplies(
        cloud.userId,
        topic.id,
      )).single;
      expect(pending.reply.body, 'keep orphaned draft');
      expect(pending.requiresManualRetry, isTrue);
      cloud.createdTalks.add(
        gone,
      ); // Explicit local-fixture restoration permits manual retry.
      expect(await state.retryPendingTalkReplies(topic.id), isTrue);
      expect(
        await store.loadPendingTalkReplies(cloud.userId, topic.id),
        isEmpty,
      );
      expect(
        cloud.createdReplies
            .where((entry) => entry.reply.body == 'keep orphaned draft')
            .single
            .postId,
        'gone',
      );
      state.dispose();
    },
  );

  test(
    'a second reply is durable before an earlier network request finishes, including restart',
    () async {
      final hold = Completer<void>();
      final cloud = _FakeCloudTierRepository()..holdNextReply = hold;
      cloud.createdTalks.add(
        const TalkPost(
          id: 'post',
          author: 'other',
          body: 'canonical',
          rank: TierRank.b,
          minutesAgo: 0,
        ),
      );
      final store = _ObservedPendingStore(), repository = DummyTierRepository();
      final state = AppState(
        repository,
        cloudRepository: cloud,
        localStore: store,
      );
      await state.initialize();
      final topic = repository.getById('cloud-topic')!;
      await state.load(topic.id);
      unawaited(
        state.replyToTalk(
          topic,
          postId: 'post',
          body: 'first waiting for network',
        ),
      );
      await cloud.replyStarted.future.timeout(const Duration(seconds: 2));
      unawaited(
        state.replyToTalk(
          topic,
          postId: 'post',
          body: 'second must survive exit',
        ),
      );
      await store.secondPersisted.future.timeout(const Duration(seconds: 2));
      expect(
        (await store.loadPendingTalkReplies(
          cloud.userId,
          topic.id,
        )).map((entry) => entry.reply.body),
        ['first waiting for network', 'second must survive exit'],
      );
      expect(hold.isCompleted, isFalse);
      state
          .dispose(); // Simulate process exit; the old transport never returns.
      final restarted = AppState(
        repository,
        cloudRepository: cloud,
        localStore: LocalTierStore(),
      );
      await restarted.initialize();
      await restarted.load(topic.id);
      final shown = restarted.talksFor(topic).single;
      expect(shown.body, 'canonical');
      expect(shown.replies.map((reply) => reply.body), [
        'first waiting for network',
        'second must survive exit',
      ]);
      expect(await restarted.retryPendingTalkReplies(topic.id), isTrue);
      expect(
        cloud.createdReplies.map((entry) => entry.reply.id).toSet().length,
        2,
      );
      expect(
        await store.loadPendingTalkReplies(cloud.userId, topic.id),
        isEmpty,
      );
      restarted.dispose();
    },
  );

  test(
    'acknowledging an earlier write cannot erase a later durable reply',
    () async {
      final hold = Completer<void>();
      final cloud = _FakeCloudTierRepository()..holdNextReply = hold;
      cloud.createdTalks.add(
        const TalkPost(
          id: 'post',
          author: 'other',
          body: 'canonical',
          rank: TierRank.b,
          minutesAgo: 0,
        ),
      );
      final store = _ObservedPendingStore(), repository = DummyTierRepository();
      final state = AppState(
        repository,
        cloudRepository: cloud,
        localStore: store,
      );
      await state.initialize();
      final topic = repository.getById('cloud-topic')!;
      await state.load(topic.id);
      final first = state.replyToTalk(topic, postId: 'post', body: 'first');
      await cloud.replyStarted.future.timeout(const Duration(seconds: 2));
      final second = state.replyToTalk(topic, postId: 'post', body: 'second');
      await store.secondPersisted.future.timeout(const Duration(seconds: 2));
      hold.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(cloud.createdReplies.map((entry) => entry.reply.body), [
        'first',
        'second',
      ]);
      expect(
        await store.loadPendingTalkReplies(cloud.userId, topic.id),
        isEmpty,
      );
      expect(
        (await store.loadTalks(
          topic.id,
        )).single.replies.map((reply) => reply.body),
        ['first', 'second'],
      );
      state.dispose();
    },
  );

  test(
    'local queue mutations preserve concurrent additions and exact-ID acknowledgments',
    () async {
      final a = LocalTierStore(), b = LocalTierStore();
      PendingTalkReply entry(String id) => PendingTalkReply(
        postId: 'post',
        reply: TalkReply(
          id: id,
          author: 'name',
          body: id,
          createdAt: DateTime.utc(2026),
        ),
      );
      await Future.wait([
        a.addPendingTalkReply('uid', 'topic', entry('a')),
        b.addPendingTalkReply('uid', 'topic', entry('b')),
      ]);
      await Future.wait([
        a.acknowledgePendingTalkReply('uid', 'topic', 'a'),
        b.addPendingTalkReply('uid', 'topic', entry('c')),
      ]);
      expect(
        (await a.loadPendingTalkReplies(
          'uid',
          'topic',
        )).map((reply) => reply.reply.id).toSet(),
        {'b', 'c'},
      );
    },
  );

  test(
    'local account cleanup preserves another UID pending replies and recovery backups',
    () async {
      final store = LocalTierStore();
      const post = TalkPost(
        id: 'post',
        author: 'name',
        body: 'body',
        rank: TierRank.b,
        minutesAgo: 0,
      );
      for (final uid in ['target', 'target.other']) {
        await store.savePendingTalkReplies(uid, 'topic', [
          PendingTalkReply(
            postId: 'post',
            reply: TalkReply(
              id: uid,
              author: 'name',
              body: 'draft $uid',
              createdAt: DateTime.utc(2026),
            ),
          ),
        ]);
        await store.backupLegacyTalks(uid, 'topic', [post]);
      }
      await store.clearUserData(uid: 'target');
      expect(await store.loadPendingTalkReplies('target', 'topic'), isEmpty);
      expect(await store.loadLegacyTalkBackup('target', 'topic'), isEmpty);
      expect(
        (await store.loadPendingTalkReplies(
          'target.other',
          'topic',
        )).single.reply.body,
        'draft target.other',
      );
      expect(
        (await store.loadLegacyTalkBackup('target.other', 'topic')).single.body,
        'body',
      );
    },
  );

  test(
    'switching accounts never sends the previous UID pending reply',
    () async {
      final cloud = _FakeCloudTierRepository()..denyTalkReplies = true;
      cloud.createdTalks.add(
        const TalkPost(
          id: 'post',
          author: 'name',
          body: 'body',
          rank: TierRank.b,
          minutesAgo: 0,
        ),
      );
      final repository = DummyTierRepository(), store = LocalTierStore();
      final state = AppState(repository, cloudRepository: cloud);
      await state.initialize();
      final topic = repository.getById('cloud-topic')!;
      await state.load(topic.id);
      expect(
        await state.replyToTalk(topic, postId: 'post', body: 'UID-bound draft'),
        isFalse,
      );
      cloud.userId = 'second-account';
      cloud.denyTalkReplies = false;
      await state.load(topic.id);
      await state.reactToTalk(topic, postId: 'post', positive: true);
      expect(cloud.createdReplies, isEmpty);
      expect(
        (await store.loadPendingTalkReplies(
          'firebase-user',
          topic.id,
        )).single.reply.body,
        'UID-bound draft',
      );
      cloud.userId = 'firebase-user';
      await state.load(topic.id);
      expect(await state.retryPendingTalkReplies(topic.id), isTrue);
      expect(cloud.createdReplies.single.reply.body, 'UID-bound draft');
      expect(cloud.createdReplies.single.reply.authorUserId, 'firebase-user');
      state.dispose();
    },
  );

  test(
    'pre-upgrade local replies have a permanent backup without guessed ownership or auto-send',
    () async {
      final cloud = _FakeCloudTierRepository();
      const server = TalkPost(
        id: 'legacy',
        author: 'name',
        body: 'original server',
        rank: TierRank.b,
        minutesAgo: 0,
        upvotes: 7,
      );
      cloud.createdTalks.add(server);
      final repository = DummyTierRepository(), store = LocalTierStore();
      final state = AppState(repository, cloudRepository: cloud);
      await state.initialize();
      final topic = repository.getById('cloud-topic')!;
      await store.saveTalks(topic.id, [
        server.copyWith(
          replies: [
            TalkReply(
              id: 'unconfirmed-old',
              author: 'unknown',
              body: 'old local text',
              createdAt: DateTime.utc(2026),
            ),
          ],
        ),
      ]);
      await state.load(topic.id);
      await state.reactToTalk(topic, postId: 'legacy', positive: true);
      final backup = (await store.loadLegacyTalkBackup(
        cloud.userId,
        topic.id,
      )).single;
      expect(backup.replies.single.body, 'old local text');
      expect(backup.replies.single.authorUserId, isNull);
      expect(backup.upvotes, 7);
      expect(cloud.createdReplies, isEmpty);
      expect(state.talksFor(topic).single.body, 'original server');
      state.dispose();
    },
  );

  for (final nextOperation in ['reply', 'reaction']) {
    test(
      'permission-denied reply survives restart and a later $nextOperation',
      () async {
        final cloud = _FakeCloudTierRepository()..denyTalkReplies = true;
        cloud.createdTalks.add(
          const TalkPost(
            id: 'server-post',
            author: 'other',
            authorUserId: 'someone-else',
            body: 'server body',
            rank: TierRank.b,
            minutesAgo: 0,
          ),
        );
        final repository = DummyTierRepository();
        var state = AppState(repository, cloudRepository: cloud);
        await state.initialize();
        final topic = repository.getById('cloud-topic')!;
        await state.load(topic.id);
        expect(
          await state.replyToTalk(
            topic,
            postId: 'server-post',
            body: 'keep this failed reply',
          ),
          isFalse,
        );
        expect(state.cloudError, isA<FirebaseException>());
        final store = LocalTierStore();
        expect(
          (await store.loadPendingTalkReplies(
            cloud.userId,
            topic.id,
          )).single.reply.body,
          'keep this failed reply',
        );
        state.dispose();
        state = AppState(repository, cloudRepository: cloud);
        await state.initialize();
        await state.load(topic.id);
        expect(
          state.talksFor(topic).single.replies.single.body,
          'keep this failed reply',
        );
        cloud.denyTalkReplies =
            false; // Equivalent to email verification succeeding.
        if (nextOperation == 'reply') {
          expect(
            await state.replyToTalk(
              topic,
              postId: 'server-post',
              body: 'second reply',
            ),
            isTrue,
          );
        } else {
          await state.reactToTalk(topic, postId: 'server-post', positive: true);
        }
        final restored = (await store.loadTalks(topic.id)).single;
        expect(restored.body, 'server body');
        expect(restored.authorUserId, 'someone-else');
        expect(
          restored.replies
              .where((r) => r.body == 'keep this failed reply')
              .length,
          1,
        );
        expect(
          await store.loadPendingTalkReplies(cloud.userId, topic.id),
          isEmpty,
        );
        state.dispose();
      },
    );
  }

  test(
    'two devices toggle the latest server vote instead of stale device preferences',
    () async {
      final sharedVotes = <String, Map<String, String>>{};
      final a = _FakeCloudTierRepository(sharedVotes: sharedVotes);
      final b = _FakeCloudTierRepository(sharedVotes: sharedVotes);
      const post = TalkPost(
        id: 'post',
        author: 'name',
        body: 'body',
        rank: TierRank.b,
        minutesAgo: 0,
      );
      a.createdTalks.add(post);
      b.createdTalks.add(post);
      final repoA = DummyTierRepository(), repoB = DummyTierRepository();
      final stateA = AppState(repoA, cloudRepository: a),
          stateB = AppState(repoB, cloudRepository: b);
      await stateA.initialize();
      await stateB.initialize();
      final topicA = repoA.getById('cloud-topic')!,
          topicB = repoB.getById('cloud-topic')!;
      await stateA.load(topicA.id);
      await stateB.load(topicB.id);
      await stateA.reactToTalk(topicA, postId: 'post', positive: true);
      await stateB.reactToTalk(topicB, postId: 'post', positive: false);
      expect(sharedVotes['firebase-user|post']?['root'], 'down');
      await stateA.reactToTalk(topicA, postId: 'post', positive: true);
      expect(sharedVotes['firebase-user|post']?['root'], 'up');
      expect(a.reactionWrites.last.reaction, 'up');
      await stateA.reactToTalk(topicA, postId: 'post', positive: true);
      expect(sharedVotes['firebase-user|post']?['root'], isNull);
      stateA.dispose();
      stateB.dispose();
    },
  );

  test(
    'account switches keep votes and pending replies isolated by UID',
    () async {
      SharedPreferences.setMockInitialValues({
        'talkReactions': ['cloud-topic|post|root=up'],
      });
      final cloud = _FakeCloudTierRepository();
      cloud.createdTalks.add(
        const TalkPost(
          id: 'post',
          author: 'name',
          body: 'body',
          rank: TierRank.b,
          minutesAgo: 0,
        ),
      );
      final repository = DummyTierRepository();
      final state = AppState(repository, cloudRepository: cloud);
      await state.initialize();
      final topic = repository.getById('cloud-topic')!;
      await state.load(topic.id);
      cloud.denyTalkReplies = true;
      expect(
        await state.replyToTalk(
          topic,
          postId: 'post',
          body: 'first account draft',
        ),
        isFalse,
      );
      cloud.denyTalkReplies = false;
      await state.reactToTalk(topic, postId: 'post', positive: true);
      cloud.userId = 'second-account';
      await state.load(topic.id);
      await state.reactToTalk(topic, postId: 'post', positive: true);
      expect(cloud.votes['firebase-user|post']?['root'], 'up');
      expect(cloud.votes['second-account|post']?['root'], 'up');
      cloud.userId = 'firebase-user';
      await state.load(topic.id);
      await state.reactToTalk(topic, postId: 'post', positive: true);
      expect(cloud.votes['firebase-user|post']?['root'], isNull);
      expect(cloud.votes['second-account|post']?['root'], 'up');
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getStringList('talkReactions'),
        contains('cloud-topic|post|root=up'),
      );
      state.dispose();
    },
  );

  test(
    'a rejected reaction never commits its optimistic local choice',
    () async {
      final cloud = _FakeCloudTierRepository()..denyTalkReactions = true;
      cloud.createdTalks.add(
        const TalkPost(
          id: 'post',
          author: 'name',
          body: 'body',
          rank: TierRank.b,
          minutesAgo: 0,
        ),
      );
      final repository = DummyTierRepository();
      final state = AppState(repository, cloudRepository: cloud);
      await state.initialize();
      final topic = repository.getById('cloud-topic')!;
      await state.load(topic.id);
      await state.reactToTalk(topic, postId: 'post', positive: true);
      expect(state.cloudError, isA<FirebaseException>());
      expect(cloud.votes, isEmpty);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getStringList('talkReactions'),
        isNot(contains('firebase-user|cloud-topic|post|root=up')),
      );
      state.dispose();
    },
  );

  test(
    'cloud actions write only a new post, reply, or personal reaction',
    () async {
      final repository = DummyTierRepository();
      final cloud = _FakeCloudTierRepository();
      final state = AppState(repository, cloudRepository: cloud);
      await state.initialize();
      final topic = repository.getById('cloud-topic')!;
      const pending = TalkPost(
        id: 'pending-local-only',
        author: 'name',
        body: 'unsent draft',
        rank: TierRank.b,
        minutesAgo: 0,
      );
      await LocalTierStore().saveTalks(topic.id, [pending]);
      await state.load(topic.id);
      await state.postTalk(topic.id, body: 'new post', rank: TierRank.s);
      expect(cloud.createdTalks.length, 1);
      expect(cloud.createdTalks.single.body, 'new post');
      final postId = cloud.createdTalks.single.id!;
      await state.replyToTalk(topic, postId: postId, body: 'new reply');
      expect(cloud.createdTalks.length, 1);
      expect(cloud.createdReplies.single.postId, postId);
      expect(cloud.createdReplies.single.reply.body, 'new reply');
      await state.reactToTalk(topic, postId: postId, positive: true);
      expect(cloud.reactionWrites.single.reaction, 'up');
      expect(cloud.createdTalks.length, 1);
      expect(cloud.createdReplies.length, 1);
      await state.reactToTalk(topic, postId: postId, positive: true);
      expect(cloud.reactionWrites.last.reaction, isNull);
      expect(
        state.talksFor(topic).any((post) => post.id == pending.id),
        isTrue,
      );
      expect(
        (await LocalTierStore().loadTalks(
          topic.id,
        )).any((post) => post.id == pending.id),
        isTrue,
      );
      state.dispose();
    },
  );

  test('JP・KR・TW/HK・BRを各言語へ、それ以外を英語へ振り分ける', () {
    expect(AppLocaleParser.fromDevice(const Locale('en', 'JP')), AppLocale.ja);
    expect(AppLocaleParser.fromDevice(const Locale('en', 'KR')), AppLocale.ko);
    expect(
      AppLocaleParser.fromDevice(const Locale('zh', 'TW')),
      AppLocale.zhTw,
    );
    expect(
      AppLocaleParser.fromDevice(const Locale('zh', 'HK')),
      AppLocale.zhTw,
    );
    expect(AppLocaleParser.fromCode('zh-TW'), AppLocale.zhTw);
    expect(
      AppLocaleParser.fromDevice(const Locale('pt', 'BR')),
      AppLocale.ptBr,
    );
    expect(AppLocaleParser.fromCode('pt-BR'), AppLocale.ptBr);
    expect(AppLocaleParser.fromDevice(const Locale('fr', 'FR')), AppLocale.en);
    expect(AppLocaleParser.fromDevice(const Locale('ja')), AppLocale.ja);
  });

  test('既存Google資格情報はパスワード統合ではなく通常ログインへ復旧する', () {
    expect(
      googleAuthRecoveryForErrorCode('credential-already-in-use'),
      GoogleAuthRecovery.signInExistingGoogle,
    );
    expect(
      googleAuthRecoveryForErrorCode(
        'account-exists-with-different-credential',
      ),
      GoogleAuthRecovery.linkDifferentProvider,
    );
    expect(
      googleAuthRecoveryForErrorCode('network-request-failed'),
      GoogleAuthRecovery.none,
    );
  });

  test('いいね・うーん・通報の文言を5言語で提供する', () {
    for (final entry in const [
      (AppLocale.ja, '👍 いいね 0', '🤔 うーん 0', '通報する'),
      (AppLocale.ko, '👍 좋아요 0', '🤔 글쎄요 0', '신고하기'),
      (AppLocale.zhTw, '👍 讚 0', '🤔 嗯… 0', '檢舉'),
      (AppLocale.ptBr, '👍 Curtir 0', '🤔 Hmm 0', 'Denunciar'),
      (AppLocale.en, '👍 Like 0', '🤔 Hmm 0', 'Report'),
    ]) {
      final l10n = AppLocalizations(entry.$1);
      expect(l10n.format('reactionLike', const {'count': 0}), entry.$2);
      expect(l10n.format('reactionHmm', const {'count': 0}), entry.$3);
      expect(l10n.t('reportComment'), entry.$4);
    }
  });

  test('全翻訳辞書は英語辞書と同じキーを持つ', () {
    for (final locale in AppLocale.values) {
      expect(
        AppLocalizations.keysForTesting(locale),
        AppLocalizations.keysForTesting(AppLocale.en),
        reason: locale.code,
      );
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
      shareUploadedImages: true,
    );
    final submission = UserTierSubmission(
      id: 'submission-1',
      topicId: topic.id,
      userId: 'anonymous-1',
      createdAt: DateTime(2026),
      placements: {
        TierRank.s: [item.id],
      },
      region: 'BR',
      contentLanguage: AppLocale.ptBr,
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
          authorUserId: 'reply-user',
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
    expect(restoredTopic.shareUploadedImages, isTrue);
    expect(restoredSubmission!.placements[TierRank.s], [item.id]);
    expect(restoredSubmission.region, 'BR');
    expect(restoredSubmission.contentLanguage, AppLocale.ptBr);
    expect(restoredTalk.body, 'これはS');
    expect(restoredTalk.replies.single.stance, ReplyStance.agree);
    expect(restoredTalk.replies.single.authorUserId, 'reply-user');
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

  test('アカウント削除時は端末内ユーザーデータだけを消去する', () async {
    final store = LocalTierStore();
    const item = TierItem(
      id: 'delete-local-item',
      topicId: 'delete-local-topic',
      sortIndex: 0,
      name: '削除対象',
    );
    const topic = TierTopic(
      id: 'delete-local-topic',
      title: '削除対象Tier',
      description: '',
      tags: [],
      category: 'その他',
      creatorName: 'あなた',
      participants: 1,
      items: [item],
      community: {'delete-local-item': TierRank.s},
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('themeMode', 'light');
    await store.saveTopic(topic);
    await store.saveTalks(topic.id, const [
      TalkPost(
        id: 'delete-talk',
        author: 'あなた',
        body: '削除対象',
        rank: TierRank.s,
        minutesAgo: 0,
      ),
    ]);

    await store.clearUserData();

    expect(await store.loadTopics(), isEmpty);
    expect(await store.loadTalks(topic.id), isEmpty);
    expect(preferences.getString('themeMode'), 'light');
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
    expect(restored.languageExplicitlySelected, isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('preferredLanguage'), 'ko');
  });

  test('localeは手動設定・URL・アカウント・端末の順で決定する', () async {
    SharedPreferences.setMockInitialValues({
      'preferredLanguage': 'ko',
      'languageExplicitlySelected': true,
    });
    final explicit = AppState(
      DummyTierRepository(),
      cloudRepository: _FakeCloudTierRepository(
        preferences: (preferredLocale: 'en', region: 'US'),
      ),
      initialPath: '/pt-br/',
      deviceLocale: const Locale('ja', 'JP'),
    );
    await explicit.initialize();
    expect(explicit.locale, AppLocale.ko);

    SharedPreferences.setMockInitialValues({});
    final url = AppState(
      DummyTierRepository(),
      cloudRepository: _FakeCloudTierRepository(
        preferences: (preferredLocale: 'en', region: 'US'),
      ),
      initialPath: '/pt-br/',
      deviceLocale: const Locale('ja', 'JP'),
    );
    await url.initialize();
    expect(url.locale, AppLocale.ptBr);

    SharedPreferences.setMockInitialValues({});
    final account = AppState(
      DummyTierRepository(),
      cloudRepository: _FakeCloudTierRepository(
        preferences: (preferredLocale: 'zh-TW', region: 'TW'),
      ),
      deviceLocale: const Locale('ja', 'JP'),
    );
    await account.initialize();
    expect(account.locale, AppLocale.zhTw);
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
    final json = TierSerialization.topicToJson(topic);
    expect(json['sourceLanguage'], 'ko');
    expect(json['contentLanguage'], 'ko');
  });

  test('未入力と旧共通説明文は閲覧言語の共通説明文へ切り替わる', () {
    expect(
      const AppLocalizations(AppLocale.ja).topicDescription(''),
      'みんなで自由に並べてみよう。',
    );
    expect(
      const AppLocalizations(AppLocale.en).topicDescription('자유롭게 배치해 보세요.'),
      'Arrange the cards any way you like.',
    );
    expect(
      const AppLocalizations(AppLocale.ko).topicDescription('独自の説明'),
      '独自の説明',
    );
  });

  test('クラウドTierの削除成功後に端末データも整理する', () async {
    SharedPreferences.setMockInitialValues({
      'likedTopicIds': ['cloud-topic'],
      'talkReactions': ['cloud-topic|post|root=up'],
      'reportedTalkTargets': ['cloud-topic|post|root'],
      'reportedTopicIds': ['cloud-topic'],
    });
    final repository = DummyTierRepository();
    final cloud = _FakeCloudTierRepository();
    final state = AppState(repository, cloudRepository: cloud);
    await state.initialize();
    final topic = repository.getById('cloud-topic')!;

    expect(await state.deleteOwnTopic(topic), isTrue);
    expect(cloud.deletedTopicIds, ['cloud-topic']);
    expect(repository.getById('cloud-topic'), isNull);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList('likedTopicIds'), isEmpty);
    expect(preferences.getStringList('talkReactions'), isEmpty);
    expect(preferences.getStringList('reportedTalkTargets'), isEmpty);
    expect(preferences.getStringList('reportedTopicIds'), isEmpty);
  });

  test('クラウド削除失敗時はTierを残して失敗を返す', () async {
    final repository = DummyTierRepository();
    final cloud = _FakeCloudTierRepository()..failDeletion = true;
    final state = AppState(repository, cloudRepository: cloud);
    await state.initialize();
    final topic = repository.getById('cloud-topic')!;

    expect(await state.deleteOwnTopic(topic), isFalse);
    expect(repository.getById('cloud-topic'), isNotNull);
    expect(state.cloudError, isA<StateError>());
  });

  test('別UIDのクラウドTierは作成者名が「あなた」でも削除しない', () async {
    final repository = DummyTierRepository();
    final cloud = _FakeCloudTierRepository();
    final state = AppState(repository, cloudRepository: cloud);
    await state.initialize();
    final topic = repository.getById('cloud-topic')!;
    cloud.userId = 'different-user';

    expect(state.isOwnTopic(topic), isFalse);
    expect(await state.deleteOwnTopic(topic), isFalse);
    expect(cloud.deletedTopicIds, isEmpty);
    expect(repository.getById('cloud-topic'), isNotNull);
  });

  test('共有URLのIDから一覧外のクラウドTierを直接取得できる', () async {
    final repository = DummyTierRepository();
    final cloud = _FakeCloudTierRepository();
    final state = AppState(repository, cloudRepository: cloud);

    final topic = await state.loadTopicById('direct-topic');

    expect(topic?.title, '直接表示Tier');
    expect(repository.getById('direct-topic'), same(topic));
    expect(cloud.loadedTopicIds, ['direct-topic']);
  });

  test('共有URLは端末キャッシュよりクラウドを優先し、消えたTierを破棄する', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = DummyTierRepository();
    final cloud = _FakeCloudTierRepository();
    final state = AppState(repository, cloudRepository: cloud);
    await state.initialize();

    expect(repository.getById('yokai'), isNotNull);
    expect(await state.loadTopicById('yokai'), isNull);
    expect(repository.getById('yokai'), isNull);
    expect(cloud.loadedTopicIds, contains('yokai'));
  });
}

class _ObservedPendingStore extends LocalTierStore {
  final secondPersisted = Completer<void>();
  @override
  Future<void> savePendingTalkReplies(
    String uid,
    String topicId,
    List<PendingTalkReply> pending,
  ) async {
    await super.savePendingTalkReplies(uid, topicId, pending);
    if (pending.length == 2 && !secondPersisted.isCompleted) {
      secondPersisted.complete();
    }
  }
}

class _FakeCloudTierRepository implements CloudTierRepository {
  _FakeCloudTierRepository({
    this.preferences,
    Map<String, Map<String, String>>? sharedVotes,
  }) : votes = sharedVotes ?? {};

  final ({String preferredLocale, String region})? preferences;
  final submissions = <UserTierSubmission>[];
  final savedSubmissions = <UserTierSubmission>[];
  final deletedTopicIds = <String>[];
  final loadedTopicIds = <String>[];
  final createdTalks = <TalkPost>[];
  final createdReplies = <({String postId, TalkReply reply})>[];
  final reactionWrites = <({String postId, String? reaction})>[];
  final Map<String, Map<String, String>> votes;
  bool denyTalkReplies = false;
  Completer<void>? holdNextReply;
  final replyStarted = Completer<void>();
  final replyAttempts = <String>[];
  bool denyTalkReactions = false;
  String userId = 'firebase-user';
  bool failDeletion = false;

  @override
  String get currentUserId => userId;

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
  Future<TierTopic?> loadTopic(String topicId) async {
    loadedTopicIds.add(topicId);
    if (topicId != 'direct-topic') return null;
    return const TierTopic(
      id: 'direct-topic',
      title: '直接表示Tier',
      description: '',
      tags: ['共有URL'],
      category: 'その他',
      creatorName: '作成者',
      participants: 1,
      items: [
        TierItem(
          id: 'direct-item',
          topicId: 'direct-topic',
          sortIndex: 0,
          name: '直接取得',
        ),
      ],
      community: {'direct-item': TierRank.s},
    );
  }

  @override
  Future<TierTopic> saveTopic(TierTopic topic) async => topic;

  @override
  Future<void> setTopicPublic(String topicId, {required bool isPublic}) async {}

  @override
  Future<void> deleteTopic(String topicId) async {
    if (failDeletion) throw StateError('delete failed');
    deletedTopicIds.add(topicId);
  }

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
  Future<List<TalkPost>> loadTalks(String topicId) async => [
    for (final post in createdTalks)
      withTalkActivity(post, [], [
        for (final entry in votes.entries)
          if (entry.key.endsWith('|${post.id}')) {'votes': entry.value},
      ]),
  ];

  @override
  Future<void> createTalk(String topicId, TalkPost post) async {
    createdTalks.add(post);
  }

  @override
  Future<void> createTalkReply(
    String topicId,
    String postId,
    TalkReply reply, {
    String? parentReplyId,
  }) async {
    replyAttempts.add(postId);
    final hold = holdNextReply;
    holdNextReply = null;
    if (hold != null) {
      if (!replyStarted.isCompleted) replyStarted.complete();
      await hold.future;
    }
    if (denyTalkReplies) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Password user has not verified their email',
      );
    }
    final index = createdTalks.indexWhere((post) => post.id == postId);
    if (index < 0) throw TalkReplyTargetUnavailable(postId);
    createdReplies.add((postId: postId, reply: reply));
    if (index >= 0) {
      createdTalks[index] = withTalkActivity(createdTalks[index], [
        {
          ...TierSerialization.replyToJson(reply),
          'parentReplyId': parentReplyId,
        },
      ], []);
    }
  }

  @override
  Future<Map<String, String>> loadOwnTalkReactions(String topicId) async => {
    for (final post in createdTalks)
      for (final vote in (votes['$userId|${post.id}'] ?? {}).entries)
        '${post.id}|${vote.key}': vote.value,
  };

  @override
  Future<TalkReactionResult> toggleTalkReaction(
    String topicId,
    String postId, {
    String? replyId,
    required bool positive,
  }) async {
    if (denyTalkReactions) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    }
    final key = '$userId|$postId';
    final result = toggleTalkVote(
      votes[key] ?? {},
      replyId ?? 'root',
      positive,
    );
    votes[key] = result.votes;
    reactionWrites.add((postId: postId, reaction: result.reaction));
    return TalkReactionResult(
      reaction: result.reaction,
      ownVotes: result.votes,
    );
  }

  @override
  Future<void> reportTalk(
    String topicId, {
    required String postId,
    String? replyId,
  }) async {}

  @override
  Future<bool> reportTopic(String topicId, {required String reason}) async =>
      true;

  @override
  Future<void> setTopicLike(String topicId, {required bool liked}) async {}

  @override
  Future<void> saveUserPreferences({
    required String preferredLocale,
    required String region,
  }) async {}

  @override
  Future<({String preferredLocale, String region})?>
  loadUserPreferences() async => preferences;
}
