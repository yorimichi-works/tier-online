import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../domain/internationalization.dart';
import '../domain/talk_activity.dart';
import '../domain/talk_reactions.dart';
import '../domain/talk_write_policy.dart';
import '../models/tier_models.dart';
import '../models/tier_serialization.dart';
import 'cloud_tier_repository.dart';
import 'starter_tier_repository.dart';

class FirebaseTierRepository implements CloudTierRepository {
  FirebaseTierRepository({
    required FirebaseAuth auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
  }) : _auth = auth,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;
  final Map<String, Map<String, String>> _ownTalkReactions = {};

  Future<TalkWritePolicy> _talkPolicy() async {
    try {
      final snapshot = await _firestore
          .doc('clientPolicies/talks')
          .get(const GetOptions(source: Source.server));
      return TalkWritePolicy.fromMap(snapshot.data());
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return const TalkWritePolicy.legacy();
      }
      rethrow;
    }
  }

  Future<void> _requireTalkWrite(String uid) async {
    (await _talkPolicy()).requireWritable();
    if (currentUserId != uid) throw StateError('The active account changed');
  }

  @override
  String get currentUserId => _auth.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _topics =>
      _firestore.collection('topics');

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  @override
  Future<void> saveUserPreferences({
    required String preferredLocale,
    required String region,
  }) async {
    final locale = AppLocaleParser.fromCode(preferredLocale) ?? AppLocale.ja;
    final reference = _users.doc(currentUserId);
    final existing = await reference.get();
    await reference.set({
      'uid': currentUserId,
      // Keep the legacy route-form value while new readers use BCP 47.
      'preferredLocale': locale.code,
      'preferredLanguage': locale.storageCode,
      'region': region,
      'updatedAt': FieldValue.serverTimestamp(),
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<({String preferredLocale, String region})?>
  loadUserPreferences() async {
    final snapshot = await _users.doc(currentUserId).get();
    final data = snapshot.data();
    if (data == null) return null;
    return (
      preferredLocale:
          data['preferredLanguage'] as String? ??
          data['preferredLocale'] as String? ??
          'ja',
      region: SupportedRegion.normalize(
        data['region'] as String?,
        fallback: 'JP',
      ),
    );
  }

  @override
  Future<List<TierTopic>> loadTopics() async {
    final snapshots = await Future.wait([
      _topics.where('isPublic', isEqualTo: true).limit(100).get(),
      _topics.where('creatorId', isEqualTo: currentUserId).limit(100).get(),
    ]);
    final documents = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snapshot in snapshots) {
      for (final document in snapshot.docs) {
        documents[document.id] = document;
      }
    }
    final topics = await Future.wait(documents.values.map(_topicFromDocument));
    topics.removeWhere(
      (topic) =>
          topic.creatorId != currentUserId &&
          !const {'approved', 'flagged'}.contains(topic.moderationStatus),
    );
    topics.sort((a, b) => a.createdDaysAgo.compareTo(b.createdDaysAgo));
    return topics;
  }

  @override
  Future<TierTopic?> loadTopic(String topicId) async {
    final DocumentSnapshot<Map<String, dynamic>> document;
    try {
      document = await _topics.doc(topicId).get();
    } on FirebaseException catch (error) {
      // Firestore rules intentionally hide private/blocked topics from other
      // users. A missing document can be indistinguishable from a denied read,
      // and both should be presented as unavailable instead of a network error.
      if (error.code == 'permission-denied') return null;
      rethrow;
    }
    if (!document.exists) return null;
    final data = document.data()!;
    if (data['isPublic'] == false ||
        !const {
          'approved',
          'flagged',
        }.contains(data['moderationStatus'] as String? ?? 'approved')) {
      return null;
    }
    final topic = await _topicFromDocument(document);
    return topic;
  }

  Future<TierTopic> _topicFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final data = document.data()!;
    final isStarterTier = document.id.startsWith('starter-');
    final itemSnapshot = await document.reference
        .collection('items')
        .orderBy('sortIndex')
        .get();
    final items = [
      for (final item in itemSnapshot.docs)
        TierItem(
          id: item.id,
          topicId: document.id,
          name: item.data()['name'] as String?,
          imageUrl: item.data()['imageUrl'] as String?,
          sortIndex: item.data()['sortIndex'] as int? ?? 0,
          colorSeed: item.data()['colorSeed'] as int? ?? 0,
          contentLanguage: AppLocaleParser.fromCode(
            item.data()['sourceLanguage'] as String? ??
                item.data()['contentLanguage'] as String?,
          ),
          isLanguageNeutral: item.data()['isLanguageNeutral'] as bool? ?? false,
        ),
    ];
    final createdAt = data['createdAt'] as Timestamp?;
    return TierTopic(
      id: document.id,
      title: data['title'] as String,
      description: data['description'] as String? ?? '',
      tags: (data['tags'] as List<dynamic>? ?? const []).cast<String>(),
      category: data['category'] as String? ?? 'その他',
      creatorName: isStarterTier
          ? starterTierCreatorName
          : data['creatorName'] as String? ?? '匿名クリエイター',
      creatorId: isStarterTier
          ? starterTierCreatorId
          : data['creatorId'] as String?,
      participants: data['participants'] as int? ?? 0,
      likeCount: data['likeCount'] as int? ?? 0,
      items: items,
      community: (data['community'] as Map<String, dynamic>? ?? const {}).map(
        (key, value) =>
            MapEntry(key, TierRank.parse(value as String) ?? TierRank.b),
      ),
      isTrending: data['isTrending'] as bool? ?? false,
      createdDaysAgo: createdAt == null
          ? 0
          : DateTime.now().difference(createdAt.toDate()).inDays,
      contentLanguage:
          AppLocaleParser.fromCode(
            data['sourceLanguage'] as String? ??
                data['contentLanguage'] as String?,
          ) ??
          AppLocale.ja,
      targetRegion: SupportedRegion.normalize(
        data['targetRegion'] as String?,
        fallback: 'JP',
      ),
      categoryId:
          data['categoryId'] as String? ??
          TierCategory.fromLegacy(data['category'] as String? ?? ''),
      sourceTierId: data['sourceTierId'] as String?,
      sourceTemplateId: data['sourceTemplateId'] as String?,
      isLanguageNeutral: data['isLanguageNeutral'] as bool? ?? false,
      moderationStatus: data['moderationStatus'] as String? ?? 'approved',
      reportCount: data['reportCount'] as int? ?? 0,
      createdByAnonymous: data['createdByAnonymous'] as bool? ?? false,
      isPublic: data['isPublic'] as bool? ?? true,
      shareUploadedImages: data['shareUploadedImages'] as bool? ?? false,
    );
  }

  @override
  Future<TierTopic> saveTopic(TierTopic topic) async {
    final uploadedItems = <TierItem>[];
    for (final item in topic.items) {
      var imageUrl = item.imageUrl;
      if (imageUrl?.startsWith('data:') ?? false) {
        final comma = imageUrl!.indexOf(',');
        final bytes = base64Decode(imageUrl.substring(comma + 1));
        final reference = _storage.ref(
          'users/$currentUserId/topics/${topic.id}/items/${item.id}.jpg',
        );
        await reference.putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        imageUrl = await reference.getDownloadURL();
      }
      uploadedItems.add(
        TierItem(
          id: item.id,
          topicId: topic.id,
          name: item.name,
          imageUrl: imageUrl,
          sortIndex: item.sortIndex,
          colorSeed: item.colorSeed,
          contentLanguage: item.contentLanguage,
          isLanguageNeutral: item.isLanguageNeutral,
        ),
      );
    }

    final callable = _functions.httpsCallable('publishTierTopic');
    final Map<String, dynamic> response;
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'topicId': topic.id,
        'title': topic.title,
        'description': topic.description,
        'tags': topic.tags,
        'category': topic.category,
        'categoryId': topic.categoryId,
        'contentLanguage': topic.contentLanguage.code,
        'sourceLanguage': topic.sourceLanguage.storageCode,
        'targetRegion': topic.targetRegion,
        'sourceTierId': topic.sourceTierId,
        'sourceTemplateId': topic.sourceTemplateId,
        'isLanguageNeutral': topic.isLanguageNeutral,
        'creatorName': topic.creatorName,
        'participants': topic.participants,
        'likeCount': topic.likeCount,
        'community': topic.community.map(
          (key, value) => MapEntry(key, value.name),
        ),
        'isTrending': topic.isTrending,
        'isPublic': topic.isPublic,
        'shareUploadedImages': topic.shareUploadedImages,
        'items': [
          for (final item in uploadedItems)
            {
              'id': item.id,
              'name': item.name,
              'imageUrl': item.imageUrl,
              'sortIndex': item.sortIndex,
              'colorSeed': item.colorSeed,
              'contentLanguage': item.contentLanguage?.code,
              'sourceLanguage': item.sourceLanguage?.storageCode,
              'isLanguageNeutral': item.isLanguageNeutral,
            },
        ],
      });
      response = Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException {
      rethrow;
    }
    return TierTopic(
      id: topic.id,
      title: topic.title,
      description: topic.description,
      tags: topic.tags,
      category: topic.category,
      creatorName: topic.creatorName,
      creatorId: currentUserId,
      participants: topic.participants,
      items: uploadedItems,
      community: topic.community,
      talks: topic.talks,
      isTrending: topic.isTrending,
      createdDaysAgo: topic.createdDaysAgo,
      likeCount: topic.likeCount,
      contentLanguage: topic.contentLanguage,
      targetRegion: topic.targetRegion,
      categoryId: topic.categoryId,
      sourceTierId: topic.sourceTierId,
      sourceTemplateId: topic.sourceTemplateId,
      isLanguageNeutral: topic.isLanguageNeutral,
      moderationStatus: response['moderationStatus'] as String? ?? 'approved',
      reportCount: response['reportCount'] as int? ?? 0,
      isPublic: topic.isPublic,
      shareUploadedImages: topic.shareUploadedImages,
    );
  }

  @override
  Future<void> setTopicPublic(String topicId, {required bool isPublic}) =>
      _topics.doc(topicId).update({
        'isPublic': isPublic,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> deleteTopic(String topicId) async {
    await _functions.httpsCallable('deleteTierTopic').call<void>({
      'topicId': topicId,
    });
  }

  @override
  Future<void> setTopicLike(String topicId, {required bool liked}) async {
    final reference = _topics
        .doc(topicId)
        .collection('likes')
        .doc(currentUserId);
    if (liked) {
      await reference.set({
        'userId': currentUserId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await reference.delete();
    }
  }

  @override
  Future<void> saveSubmission(UserTierSubmission submission) => _topics
      .doc(submission.topicId)
      .collection('submissions')
      .doc(currentUserId)
      .set({
        'userId': currentUserId,
        'createdAt': FieldValue.serverTimestamp(),
        'placements': submission.placements.map(
          (rank, items) => MapEntry(rank.name, items),
        ),
        'region': submission.region,
        'contentLanguage': submission.contentLanguage.code,
        'sourceLanguage': submission.sourceLanguage.storageCode,
      }, SetOptions(merge: true));

  @override
  Future<List<UserTierSubmission>> loadSubmissions(String topicId) async {
    final snapshot = await _topics.doc(topicId).collection('submissions').get();
    return [
      for (final document in snapshot.docs)
        UserTierSubmission(
          id: document.id,
          topicId: topicId,
          userId: document.data()['userId'] as String? ?? document.id,
          createdAt:
              (document.data()['createdAt'] as Timestamp?)?.toDate() ??
              DateTime.now(),
          placements: _placementsFromFirestore(
            document.data()['placements'] as Map<String, dynamic>? ?? const {},
          ),
          region: SupportedRegion.normalize(
            document.data()['region'] as String?,
            fallback: 'JP',
          ),
          contentLanguage:
              AppLocaleParser.fromCode(
                document.data()['sourceLanguage'] as String? ??
                    document.data()['contentLanguage'] as String?,
              ) ??
              AppLocale.ja,
        ),
    ];
  }

  Map<TierRank, List<String>> _placementsFromFirestore(
    Map<String, dynamic> data,
  ) {
    final placements = <TierRank, List<String>>{};
    for (final entry in data.entries) {
      final rank = TierRank.parse(entry.key);
      if (rank != null) {
        placements[rank] = (entry.value as List<dynamic>).cast<String>();
      }
    }
    return placements;
  }

  @override
  Future<List<TalkPost>> loadTalks(String topicId) async {
    final uid = currentUserId;
    final policy = await _talkPolicy();
    final snapshot = await _topics.doc(topicId).collection('talks').get();
    final own = <String, String>{};
    final posts = await Future.wait(
      snapshot.docs.map((document) async {
        final post = TierSerialization.talkFromJson({
          ...document.data(),
          'id': document.id,
        });
        if (policy.readProtocol < 2) return post;
        final replies = await document.reference.collection('replies').get();
        final reactions = await document.reference
            .collection('reactions')
            .get();
        for (final reaction in reactions.docs) {
          if (reaction.id != uid) continue;
          final votes = Map<String, String>.from(
            reaction.data()['votes'] as Map? ?? const {},
          );
          for (final entry in votes.entries) {
            own['${document.id}|${entry.key}'] = entry.value;
          }
        }
        return withTalkActivity(
          post,
          [
            for (final reply in replies.docs) {...reply.data(), 'id': reply.id},
          ],
          [for (final reaction in reactions.docs) reaction.data()],
        );
      }),
    );
    _ownTalkReactions['$uid|$topicId'] = own;
    return posts;
  }

  @override
  Future<Map<String, String>> loadOwnTalkReactions(String topicId) async {
    final key = '$currentUserId|$topicId';
    if (!_ownTalkReactions.containsKey(key)) await loadTalks(topicId);
    return Map.of(_ownTalkReactions[key] ?? const {});
  }

  @override
  Future<void> createTalk(String topicId, TalkPost post) async {
    final uid = currentUserId;
    await _requireTalkWrite(uid);
    if (post.id == null) throw ArgumentError('A talk ID is required');
    await _topics.doc(topicId).collection('talks').doc(post.id).set({
      ...TierSerialization.talkToJson(post),
      'authorUserId': uid,
      ...TalkClientVersion.fields,
      'replies': <Object?>[],
      'upvotes': 0,
      'downvotes': 0,
    });
  }

  @override
  Future<void> createTalkReply(
    String topicId,
    String postId,
    TalkReply reply, {
    String? parentReplyId,
  }) async {
    final uid = currentUserId;
    await _requireTalkWrite(uid);
    await _topics
        .doc(topicId)
        .collection('talks')
        .doc(postId)
        .collection('replies')
        .doc(reply.id)
        .set({
          ...TierSerialization.replyToJson(reply),
          'authorUserId': uid,
          ...TalkClientVersion.fields,
          'parentReplyId': parentReplyId,
          'replies': <Object?>[],
          'upvotes': 0,
          'downvotes': 0,
        });
  }

  @override
  Future<TalkReactionResult> toggleTalkReaction(
    String topicId,
    String postId, {
    String? replyId,
    required bool positive,
  }) async {
    final uid = currentUserId;
    await _requireTalkWrite(uid);
    final reference = _topics
        .doc(topicId)
        .collection('talks')
        .doc(postId)
        .collection('reactions')
        .doc(uid);
    return _firestore.runTransaction((transaction) async {
      if (currentUserId != uid) throw StateError('The active account changed');
      final existing = await transaction.get(reference);
      final votes = Map<String, String>.from(
        existing.data()?['votes'] as Map? ?? const {},
      );
      final target = replyId ?? 'root';
      final next = toggleTalkVote(votes, target, positive);
      transaction.set(reference, {
        'userId': uid,
        'votes': next.votes,
        ...TalkClientVersion.fields,
      });
      return TalkReactionResult(reaction: next.reaction, ownVotes: next.votes);
    });
  }

  @override
  Future<void> reportTalk(
    String topicId, {
    required String postId,
    String? replyId,
  }) async {
    final target = '${postId}_${replyId ?? 'root'}_$currentUserId'.replaceAll(
      '/',
      '_',
    );
    await _topics.doc(topicId).collection('reports').doc(target).set({
      'topicId': topicId,
      'postId': postId,
      'replyId': replyId,
      'reporterUserId': currentUserId,
      'reason': 'user_report',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<bool> reportTopic(String topicId, {required String reason}) async {
    final callable = _functions.httpsCallable('reportContent');
    try {
      await callable.call<Map<String, dynamic>>({
        'topicId': topicId,
        'targetType': 'topic',
        'targetId': topicId,
        'reason': reason,
      });
      return true;
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'already-exists') return false;
      rethrow;
    }
  }
}
