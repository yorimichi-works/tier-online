import '../models/tier_models.dart';
import '../models/tier_serialization.dart';

/// Project separate activity documents without rewriting legacy content.
TalkPost withTalkActivity(
  TalkPost post,
  List<Map<String, Object?>> replyDocuments,
  List<Map<String, Object?>> reactionDocuments,
) {
  final embeddedIds = <String>{};
  void collect(List<TalkReply> replies) {
    for (final reply in replies) {
      embeddedIds.add(reply.id);
      collect(reply.replies);
    }
  }

  collect(post.replies);
  final separate = <String, TalkReply>{
    for (final data in replyDocuments)
      if (!embeddedIds.contains(data['id']))
        data['id']! as String: TierSerialization.replyFromJson(data),
  };
  final children = <String?, List<TalkReply>>{};
  for (final data in replyDocuments) {
    final reply = separate[data['id']];
    if (reply != null) {
      children
          .putIfAbsent(data['parentReplyId'] as String?, () => [])
          .add(reply);
    }
  }
  final up = <String, int>{};
  final down = <String, int>{};
  for (final data in reactionDocuments) {
    final votes = (data['votes'] as Map?) ?? const {};
    for (final entry in votes.entries) {
      final totals = entry.value == 'up'
          ? up
          : entry.value == 'down'
          ? down
          : null;
      if (totals != null && entry.key is String) {
        totals.update(
          entry.key as String,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
  }

  final visited = <String>{};
  List<TalkReply> build(List<TalkReply> replies) => [
    for (final reply in replies)
      if (visited.add(reply.id))
        reply.copyWith(
          upvotes: reply.upvotes + (up[reply.id] ?? 0),
          downvotes: reply.downvotes + (down[reply.id] ?? 0),
          replies: build([...reply.replies, ...?children[reply.id]]),
        ),
  ];
  final merged = build([...post.replies, ...?children[null]]);
  // Deleted/missing parents and cycles must not make new replies disappear.
  for (final reply in separate.values) {
    if (!visited.contains(reply.id)) merged.addAll(build([reply]));
  }
  return post.copyWith(
    replies: merged,
    upvotes: post.upvotes + (up['root'] ?? 0),
    downvotes: post.downvotes + (down['root'] ?? 0),
  );
}
