import '../models/tier_models.dart';

class TalkReactionResult {
  const TalkReactionResult({required this.reaction, required this.ownVotes});
  final String? reaction;
  final Map<String, String> ownVotes;
}

class TalkReplyTargetUnavailable implements Exception {
  const TalkReplyTargetUnavailable(this.postId);
  final String postId;
  @override
  String toString() =>
      'The reply target is unavailable; the draft is kept locally.';
}

abstract interface class CloudTierRepository {
  String get currentUserId;
  Future<List<TierTopic>> loadTopics();
  Future<TierTopic?> loadTopic(String topicId);
  Future<TierTopic> saveTopic(TierTopic topic);
  Future<void> setTopicPublic(String topicId, {required bool isPublic});
  Future<void> deleteTopic(String topicId);
  Future<void> saveSubmission(UserTierSubmission submission);
  Future<List<UserTierSubmission>> loadSubmissions(String topicId);
  Future<List<TalkPost>> loadTalks(String topicId);
  Future<void> createTalk(String topicId, TalkPost post);
  Future<void> createTalkReply(
    String topicId,
    String postId,
    TalkReply reply, {
    String? parentReplyId,
  });
  Future<Map<String, String>> loadOwnTalkReactions(String topicId);
  Future<TalkReactionResult> toggleTalkReaction(
    String topicId,
    String postId, {
    String? replyId,
    required bool positive,
  });
  Future<void> reportTalk(
    String topicId, {
    required String postId,
    String? replyId,
  });
  Future<bool> reportTopic(String topicId, {required String reason});
  Future<void> setTopicLike(String topicId, {required bool liked});
  Future<void> saveUserPreferences({
    required String preferredLocale,
    required String region,
  });
  Future<({String preferredLocale, String region})?> loadUserPreferences();
}
