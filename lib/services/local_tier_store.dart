import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/tier_models.dart';
import '../models/tier_serialization.dart';

class PendingTalkReply {
  const PendingTalkReply({
    required this.postId,
    required this.reply,
    this.parentReplyId,
    this.failureCode,
    this.requiresManualRetry = false,
  });
  final String postId;
  final TalkReply reply;
  final String? parentReplyId;
  final String? failureCode;
  final bool requiresManualRetry;
  PendingTalkReply withFailure(String code, {required bool manualRetry}) =>
      PendingTalkReply(
        postId: postId,
        reply: reply,
        parentReplyId: parentReplyId,
        failureCode: code,
        requiresManualRetry: manualRetry,
      );
  Map<String, Object?> toJson() => {
    'postId': postId,
    'parentReplyId': parentReplyId,
    'reply': TierSerialization.replyToJson(reply),
    'failureCode': failureCode,
    'requiresManualRetry': requiresManualRetry,
  };
  factory PendingTalkReply.fromJson(Map<String, Object?> data) =>
      PendingTalkReply(
        postId: data['postId']! as String,
        parentReplyId: data['parentReplyId'] as String?,
        failureCode: data['failureCode'] as String?,
        requiresManualRetry: data['requiresManualRetry'] == true,
        reply: TierSerialization.replyFromJson(
          (data['reply']! as Map).cast<String, Object?>(),
        ),
      );
}

class LocalTierStore {
  static const _topicIdsKey = 'localTopicIds.v1';
  // Serialize only local read/modify/write operations. A pending network call
  // must never hold this lock or prevent another draft from reaching storage.
  static final Map<String, Future<void>> _pendingMutations = {};
  String _userPrefix(String kind, String uid) =>
      '$kind.${base64Url.encode(utf8.encode(uid))}.';

  // Retain the pre-upgrade snapshot once. An old cache cannot prove whether
  // a missing reply was ever accepted, so never infer ownership or auto-send it.
  Future<void> backupLegacyTalks(
    String uid,
    String topicId,
    List<TalkPost> posts,
  ) async {
    if (posts.isEmpty) return;
    final preferences = await SharedPreferences.getInstance();
    final key = '${_userPrefix('legacyTalkBackup.v2', uid)}$topicId';
    if (!preferences.containsKey(key)) {
      await preferences.setString(
        key,
        jsonEncode(posts.map(TierSerialization.talkToJson).toList()),
      );
    }
  }

  Future<List<TalkPost>> loadLegacyTalkBackup(
    String uid,
    String topicId,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final data = preferences.getString(
      '${_userPrefix('legacyTalkBackup.v2', uid)}$topicId',
    );
    if (data == null) return [];
    return (jsonDecode(data) as List)
        .map(
          (post) => TierSerialization.talkFromJson(
            (post as Map).cast<String, Object?>(),
          ),
        )
        .toList();
  }

  Future<List<PendingTalkReply>> loadPendingTalkReplies(
    String uid,
    String topicId,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(
      '${_userPrefix('pendingTalkReplies.v2', uid)}$topicId',
    );
    if (encoded == null) return [];
    // Invalid pending data must surface as an error, never be silently erased.
    return (jsonDecode(encoded) as List)
        .map(
          (data) =>
              PendingTalkReply.fromJson((data as Map).cast<String, Object?>()),
        )
        .toList();
  }

  Future<void> savePendingTalkReplies(
    String uid,
    String topicId,
    List<PendingTalkReply> pending,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      '${_userPrefix('pendingTalkReplies.v2', uid)}$topicId',
      jsonEncode(pending.map((reply) => reply.toJson()).toList()),
    );
    if (!saved) {
      throw StateError('The pending reply could not be saved locally');
    }
  }

  Future<void> _updatePendingTalkReplies(
    String uid,
    String topicId,
    void Function(List<PendingTalkReply>) update,
  ) async {
    final key = '${_userPrefix('pendingTalkReplies.v2', uid)}$topicId';
    final previous = _pendingMutations[key] ?? Future<void>.value();
    final result = previous.then((_) async {
      final pending = await loadPendingTalkReplies(uid, topicId);
      update(pending);
      await savePendingTalkReplies(uid, topicId, pending);
    });
    final settled = result.catchError((Object _) {});
    _pendingMutations[key] = settled;
    unawaited(
      settled.then((_) {
        if (identical(_pendingMutations[key], settled)) {
          _pendingMutations.remove(key);
        }
      }),
    );
    await result;
  }

  Future<void> addPendingTalkReply(
    String uid,
    String topicId,
    PendingTalkReply entry,
  ) => _updatePendingTalkReplies(uid, topicId, (pending) {
    if (!pending.any((reply) => reply.reply.id == entry.reply.id)) {
      pending.add(entry);
    }
  });

  Future<void> acknowledgePendingTalkReply(
    String uid,
    String topicId,
    String replyId,
  ) => _updatePendingTalkReplies(
    uid,
    topicId,
    (pending) => pending.removeWhere((reply) => reply.reply.id == replyId),
  );

  Future<void> recordPendingTalkReplyFailure(
    String uid,
    String topicId,
    String replyId,
    String code, {
    required bool manualRetry,
  }) => _updatePendingTalkReplies(uid, topicId, (pending) {
    final index = pending.indexWhere((reply) => reply.reply.id == replyId);
    if (index >= 0) {
      pending[index] = pending[index].withFailure(
        code,
        manualRetry: manualRetry,
      );
    }
  });

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

  Future<void> clearUserData({String? uid}) async {
    final preferences = await SharedPreferences.getInstance();
    bool userKey(String key, String kind) =>
        key.startsWith('$kind.') &&
        (uid == null || key.startsWith(_userPrefix(kind, uid)));
    final keys = preferences.getKeys().where(
      (key) =>
          key == _topicIdsKey ||
          key.startsWith('localTopic.') ||
          key.startsWith('submission.') ||
          key.startsWith('talks.') ||
          userKey(key, 'pendingTalkReplies.v2') ||
          userKey(key, 'legacyTalkBackup.v2') ||
          key.startsWith('placements.'),
    );
    for (final key in keys.toList(growable: false)) {
      await preferences.remove(key);
    }
  }
}
