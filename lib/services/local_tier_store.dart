import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/tier_models.dart';
import '../models/tier_serialization.dart';

class LocalTierStore {
  static const _topicIdsKey = 'localTopicIds.v1';

  Future<List<TierTopic>> loadTopics() async {
    final preferences = await SharedPreferences.getInstance();
    final topics = <TierTopic>[];
    for (final id in preferences.getStringList(_topicIdsKey) ?? const []) {
      final encoded = preferences.getString('localTopic.$id');
      if (encoded == null) continue;
      try {
        final json = (jsonDecode(encoded) as Map).cast<String, Object?>();
        topics.add(TierSerialization.topicFromJson(json));
      } on FormatException {
        // Ignore a damaged local draft without preventing app startup.
      }
    }
    return topics;
  }

  Future<void> saveTopic(TierTopic topic) async {
    final preferences = await SharedPreferences.getInstance();
    final ids = preferences.getStringList(_topicIdsKey) ?? <String>[];
    if (!ids.contains(topic.id)) {
      ids.insert(0, topic.id);
      await preferences.setStringList(_topicIdsKey, ids);
    }
    await preferences.setString(
      'localTopic.${topic.id}',
      jsonEncode(TierSerialization.topicToJson(topic)),
    );
  }

  Future<void> deleteTopic(String topicId) async {
    final preferences = await SharedPreferences.getInstance();
    final ids = preferences.getStringList(_topicIdsKey) ?? <String>[];
    ids.remove(topicId);
    await preferences.setStringList(_topicIdsKey, ids);
    await preferences.remove('localTopic.$topicId');
    await preferences.remove('submission.$topicId');
    await preferences.remove('talks.$topicId');
    await preferences.remove('placements.$topicId');
  }

  Future<void> saveSubmission(UserTierSubmission submission) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'submission.${submission.topicId}',
      jsonEncode(TierSerialization.submissionToJson(submission)),
    );
  }

  Future<UserTierSubmission?> loadSubmission(String topicId) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString('submission.$topicId');
    if (encoded == null) return null;
    try {
      return TierSerialization.submissionFromJson(
        (jsonDecode(encoded) as Map).cast<String, Object?>(),
      );
    } on FormatException {
      return null;
    }
  }

  Future<List<TalkPost>> loadTalks(String topicId) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString('talks.$topicId');
    if (encoded == null) return const [];
    try {
      return (jsonDecode(encoded) as List<Object?>)
          .map(
            (post) => TierSerialization.talkFromJson(
              (post! as Map).cast<String, Object?>(),
            ),
          )
          .toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> saveTalks(String topicId, List<TalkPost> posts) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'talks.$topicId',
      jsonEncode(posts.map(TierSerialization.talkToJson).toList()),
    );
  }

  Future<void> clearUserData() async {
    final preferences = await SharedPreferences.getInstance();
    final keys = preferences.getKeys().where(
      (key) =>
          key == _topicIdsKey ||
          key.startsWith('localTopic.') ||
          key.startsWith('submission.') ||
          key.startsWith('talks.') ||
          key.startsWith('placements.'),
    );
    for (final key in keys.toList(growable: false)) {
      await preferences.remove(key);
    }
  }
}
