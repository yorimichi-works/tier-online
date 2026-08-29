import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/tier_models.dart';
import '../models/tier_serialization.dart';
import '../l10n/app_localizations.dart';
import 'cloud_tier_repository.dart';

class FirebaseTierRepository implements CloudTierRepository {
  FirebaseTierRepository({
    required FirebaseAuth auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _auth = auth,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

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
    final snapshot = await _topics
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
    return Future.wait(snapshot.docs.map(_topicFromDocument));
  }

  Future<TierTopic> _topicFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final data = document.data();
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
      creatorName: data['creatorName'] as String? ?? '匿名クリエイター',
      creatorId: data['creatorId'] as String?,
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
    );
  }

  @override
  Future<TierTopic> saveTopic(TierTopic topic) async {
    final topicReference = _topics.doc(topic.id);
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

    final batch = _firestore.batch();
    batch.set(topicReference, {
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
      'creatorId': currentUserId,
      'participants': topic.participants,
      'likeCount': topic.likeCount,
      'community': topic.community.map(
        (key, value) => MapEntry(key, value.name),
      ),
      'isTrending': topic.isTrending,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    for (final item in uploadedItems) {
      batch.set(topicReference.collection('items').doc(item.id), {
        'name': item.name,
        'imageUrl': item.imageUrl,
        'sortIndex': item.sortIndex,
        'colorSeed': item.colorSeed,
        'contentLanguage': item.contentLanguage?.code,
        'isLanguageNeutral': item.isLanguageNeutral,
      });
    }
    await batch.commit();
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
    );
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
      batch.set(collection.doc(post.id), TierSerialization.talkToJson(post));
    }
    await batch.commit();
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
}
