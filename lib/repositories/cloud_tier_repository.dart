import '../models/tier_models.dart';

abstract interface class CloudTierRepository {
  String get currentUserId;
  Future<List<TierTopic>> loadTopics();
  Future<TierTopic> saveTopic(TierTopic topic);
  Future<void> saveSubmission(UserTierSubmission submission);
  Future<List<UserTierSubmission>> loadSubmissions(String topicId);
  Future<List<TalkPost>> loadTalks(String topicId);
  Future<void> saveTalks(String topicId, List<TalkPost> posts);
  Future<void> reportTalk(
    String topicId, {
    required String postId,
    String? replyId,
  });
  Future<void> setTopicLike(String topicId, {required bool liked});
  Future<void> saveUserPreferences({
    required String preferredLocale,
    required String region,
  });
  Future<({String preferredLocale, String region})?> loadUserPreferences();
}
