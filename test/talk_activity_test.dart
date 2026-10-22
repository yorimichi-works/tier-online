import 'package:flutter_test/flutter_test.dart';
import 'package:tier_table_online/domain/talk_activity.dart';
import 'package:tier_table_online/models/tier_models.dart';
import 'package:tier_table_online/models/tier_serialization.dart';

void main() {
  final created = DateTime.utc(2026, 10, 22);
  TalkReply reply(
    String id, {
    String? authorId,
    List<TalkReply> children = const [],
  }) => TalkReply(
    id: id,
    author: 'name',
    body: 'body $id',
    createdAt: created,
    authorUserId: authorId,
    replies: children,
  );
  Map<String, Object?> separate(TalkReply value, String? parent) => {
    ...TierSerialization.replyToJson(value),
    'parentReplyId': parent,
  };

  test(
    'legacy identities, bodies, nested replies and historical votes survive activity projection',
    () {
      final post = TalkPost(
        id: 'post',
        author: 'legacy author',
        body: 'original',
        rank: TierRank.s,
        minutesAgo: 1,
        upvotes: 7,
        downvotes: 2,
        replies: [
          reply('legacy', children: [reply('nested')]),
        ],
      );
      final before = TierSerialization.talkToJson(post);
      final projected = withTalkActivity(
        post,
        [
          separate(reply('new', authorId: 'bob'), 'nested'),
          separate(reply('child', authorId: 'alice'), 'new'),
          separate(reply('top', authorId: 'bob'), null),
        ],
        [
          {
            'votes': {'root': 'up', 'legacy': 'down', 'new': 'up'},
          },
          {
            'votes': {'root': 'down', 'new': 'up'},
          },
        ],
      );
      expect(projected.body, 'original');
      expect(projected.authorUserId, isNull);
      expect(projected.upvotes, 8);
      expect(projected.downvotes, 3);
      expect(projected.replies.map((r) => r.id), ['legacy', 'top']);
      final legacy = projected.replies.first;
      expect(legacy.authorUserId, isNull);
      expect(legacy.downvotes, 1);
      final newReply = legacy.replies.single.replies.single;
      expect(newReply.id, 'new');
      expect(newReply.upvotes, 2);
      expect(newReply.replies.single.id, 'child');
      expect(TierSerialization.talkToJson(post), before);
    },
  );

  test('a duplicate document cannot overwrite an embedded legacy reply', () {
    final post = TalkPost(
      author: 'name',
      body: 'parent',
      rank: TierRank.b,
      minutesAgo: 0,
      replies: [reply('legacy')],
    );
    final projected = withTalkActivity(post, [
      {
        ...separate(reply('legacy', authorId: 'attacker'), null),
        'body': 'forged',
      },
    ], []);
    expect(projected.replies.single.body, 'body legacy');
    expect(projected.replies.single.authorUserId, isNull);
  });

  test(
    'orphaned and cyclic links remain visible once and do not recurse forever',
    () {
      final post = TalkPost(
        author: 'name',
        body: 'parent',
        rank: TierRank.b,
        minutesAgo: 0,
      );
      final projected = withTalkActivity(post, [
        separate(reply('orphan'), 'deleted-parent'),
        separate(reply('cycle-a'), 'cycle-b'),
        separate(reply('cycle-b'), 'cycle-a'),
        separate(reply('self'), 'self'),
      ], []);
      final ids = <String>[];
      void collect(List<TalkReply> replies) {
        for (final value in replies) {
          ids.add(value.id);
          collect(value.replies);
        }
      }

      collect(projected.replies);
      expect(ids.toSet(), {'orphan', 'cycle-a', 'cycle-b', 'self'});
      expect(ids.length, 4);
    },
  );

  test(
    'replacing/removing a personal vote changes totals without touching legacy baseline',
    () {
      const post = TalkPost(
        author: 'name',
        body: 'parent',
        rank: TierRank.b,
        minutesAgo: 0,
        upvotes: 7,
        downvotes: 2,
      );
      final switched = withTalkActivity(post, [], [
        {
          'votes': {'root': 'down'},
        },
        {
          'votes': {'root': 'up'},
        },
      ]);
      final removed = withTalkActivity(post, [], [
        {'votes': {}},
        {
          'votes': {'root': 'up'},
        },
      ]);
      expect([switched.upvotes, switched.downvotes], [8, 3]);
      expect([removed.upvotes, removed.downvotes], [8, 2]);
      expect([post.upvotes, post.downvotes], [7, 2]);
    },
  );
}
