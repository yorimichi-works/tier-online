import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/tier_models.dart';
import '../models/tier_serialization.dart';
import '../l10n/app_localizations.dart';
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
    final reference = _users.doc(currentUserId);
    final existing = await reference.get();
    await reference.set({
      'uid': currentUserId,
      'preferredLocale': preferredLocale,
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
      preferredLocale: data['preferredLocale'] as String? ?? 'ja',
      region: data['region'] as String? ?? 'JP',
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
          AppLocaleParser.fromCode(data['contentLanguage'] as String?) ??
          AppLocale.ja,
      targetRegion: data['targetRegion'] as String? ?? 'JP',
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
          region: document.data()['region'] as String? ?? 'JP',
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
    final snapshot = await _topics.doc(topicId).collection('talks').get();
    return [
      for (final document in snapshot.docs)
        TierSerialization.talkFromJson({...document.data(), 'id': document.id}),
    ];
  }

  @override
  Future<void> saveTalks(String topicId, List<TalkPost> posts) async {
    final batch = _firestore.batch();
    final collection = _topics.doc(topicId).collection('talks');
    for (final post in posts) {
      if (post.id == null) continue;
      batch.set(collection.doc(post.id), {
        ...TierSerialization.talkToJson(post),
        'replyAuthorIds': _replyAuthorIds(post.replies).toList(),
      });
    }
    await batch.commit();
  }

  Set<String> _replyAuthorIds(List<TalkReply> replies) {
    final ids = <String>{};
    for (final reply in replies) {
      if (reply.authorUserId != null) ids.add(reply.authorUserId!);
      ids.addAll(_replyAuthorIds(reply.replies));
    }
    return ids;
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
