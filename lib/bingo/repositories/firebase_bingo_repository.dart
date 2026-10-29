import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../domain/internationalization.dart';
import '../models/bingo_models.dart';
import 'bingo_repository.dart';

/// Firestore layout (same Firebase project as tier-online):
///
/// - `bingos/{bingoId}`: board, written only by the `publishBingo` callable.
///   `listed` = public and not blocked; stats are server-aggregated.
/// - `bingos/{bingoId}/bingoEntries/{uid}`: each participant's card.
/// - `bingos/{bingoId}/comments/{commentId}`: created by `postBingoComment`.
/// - `bingos/{bingoId}/reports/{type}_{targetId}_{uid}`: user reports.
class FirebaseBingoRepository implements BingoRepository {
  FirebaseBingoRepository({
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
  // Briefly null while signing out; callers then treat the user as unknown.
  String get currentUserId => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _bingos =>
      _firestore.collection('bingos');

  BingoBoard _boardFromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return BingoBoard.fromJson({
      ...data,
      'id': doc.id,
      'createdAt': null,
    }, createdAt: (data['createdAt'] as Timestamp?)?.toDate());
  }

  @override
  Future<List<BingoBoard>> loadListedBoards() async {
    final snapshot = await _bingos
        .where('listed', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();
    return snapshot.docs.map(_boardFromDocument).toList();
  }

  @override
  Future<List<BingoBoard>> loadOwnBoards() async {
    final snapshot = await _bingos
        .where('creatorId', isEqualTo: currentUserId)
        .limit(100)
        .get();
    return snapshot.docs.map(_boardFromDocument).toList();
  }

  @override
  Future<BingoBoard?> loadBoard(String boardId) async {
    try {
      final document = await _bingos.doc(boardId).get();
      if (!document.exists) return null;
      return _boardFromDocument(document);
    } on FirebaseException catch (error) {
      // Rules hide private/blocked boards; treat a denied read as missing.
      if (error.code == 'permission-denied') return null;
      rethrow;
    }
  }

  Future<List<BingoCell>> _uploadImages(BingoBoard board) async {
    final cells = <BingoCell>[];
    for (var index = 0; index < board.cells.length; index++) {
      final cell = board.cells[index];
      final imageUrl = cell.imageUrl;
      if (imageUrl == null || !imageUrl.startsWith('data:')) {
        cells.add(cell);
        continue;
      }
      final bytes = base64Decode(imageUrl.substring(imageUrl.indexOf(',') + 1));
      final reference = _storage.ref(
        'users/$currentUserId/bingos/${board.id}/cells/$index.jpg',
      );
      await reference.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      cells.add(
        cell.copyWith(
          imageUrl: await reference.getDownloadURL(),
          imageSource: BingoImageSource.upload,
        ),
      );
    }
    return cells;
  }

  BingoException _mapFunctionsError(FirebaseFunctionsException error) =>
      switch (error.code) {
        'failed-precondition' => BingoException(BingoFailure.blocked, error),
        'resource-exhausted' => BingoException(BingoFailure.rateLimited, error),
        'not-found' ||
        'permission-denied' => BingoException(BingoFailure.notFound, error),
        'already-exists' => BingoException(BingoFailure.alreadyReported, error),
        _ => BingoException(BingoFailure.network, error),
      };

  @override
  Future<BingoBoard> publishBoard(BingoBoard board) async {
    final cells = await _uploadImages(board);
    try {
      final result = await _functions
          .httpsCallable('publishBingo')
          .call<Map<String, dynamic>>({
            'bingoId': board.id,
            'title': board.title,
            'description': board.description,
            'tags': board.tags,
            'size': board.size,
            'freeCenter': board.freeCenter,
            'shufflePerPlayer': board.shufflePerPlayer,
            'cells': [for (final cell in cells) cell.toJson()],
            'creatorName': board.creatorName,
            'contentLanguage': board.contentLanguage.code,
            'sourceLanguage': board.contentLanguage.storageCode,
            'targetRegion': board.targetRegion,
            'isPublic': board.isPublic,
          });
      final response = Map<String, dynamic>.from(result.data as Map);
      return board.copyWith(
        cells: cells,
        creatorId: currentUserId,
        moderationStatus: response['moderationStatus'] as String? ?? 'approved',
      );
    } on FirebaseFunctionsException catch (error) {
      throw _mapFunctionsError(error);
    }
  }

  @override
  Future<void> setBoardPublic(BingoBoard board, {required bool isPublic}) =>
      _bingos.doc(board.id).update({
        'isPublic': isPublic,
        'listed': isPublic && board.moderationStatus != 'blocked',
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> deleteBoard(String boardId) async {
    try {
      await _functions.httpsCallable('deleteBingo').call<void>({
        'bingoId': boardId,
      });
    } on FirebaseFunctionsException catch (error) {
      throw _mapFunctionsError(error);
    }
  }

  DocumentReference<Map<String, dynamic>> _entryReference(String boardId) =>
      _bingos.doc(boardId).collection('bingoEntries').doc(currentUserId);

  BingoEntry _entryFromDocument(String boardId, Map<String, dynamic> data) =>
      BingoEntry.fromJson(
        {...data, 'boardId': boardId, 'firstBingoAt': null, 'updatedAt': null},
        firstBingoAt: (data['firstBingoAt'] as Timestamp?)?.toDate(),
        updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      );

  @override
  Future<BingoEntry?> loadEntry(String boardId) async {
    final snapshot = await _entryReference(boardId).get();
    final data = snapshot.data();
    return data == null ? null : _entryFromDocument(boardId, data);
  }

  @override
  Future<List<BingoEntry>> loadOwnEntries() async {
    final snapshot = await _firestore
        .collectionGroup('bingoEntries')
        .where('userId', isEqualTo: currentUserId)
        .limit(200)
        .get();
    return [
      for (final document in snapshot.docs)
        if (document.reference.parent.parent case final board?)
          _entryFromDocument(board.id, document.data()),
    ];
  }

  @override
  Future<void> saveEntry(BingoEntry entry) async {
    final reference = _entryReference(entry.boardId);
    await reference.set({
      'userId': currentUserId,
      'userName': entry.userName,
      'layout': entry.layout,
      'marked': entry.marked.toList()..sort(),
      'firstBingoAt': entry.firstBingoAt == null
          ? null
          : Timestamp.fromDate(entry.firstBingoAt!),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Aggregates are maintained by the `aggregateBingoEntries` trigger, so the
  /// client never needs every participant's card.
  @override
  Future<List<BingoEntry>> loadEntries(String boardId) async => const [];

  @override
  Future<List<BingoComment>> loadComments(String boardId) async {
    final snapshot = await _bingos
        .doc(boardId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();
    return [
      for (final document in snapshot.docs)
        BingoComment.fromJson({
          ...document.data(),
          'id': document.id,
          'boardId': boardId,
          'createdAt': null,
        }, createdAt: (document.data()['createdAt'] as Timestamp?)?.toDate()),
    ];
  }

  @override
  Future<BingoComment> postComment({
    required BingoBoard board,
    required String authorName,
    required String body,
    required bool attachResult,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('postBingoComment')
          .call<Map<String, dynamic>>({
            'bingoId': board.id,
            'authorName': authorName,
            'body': body,
            'attachResult': attachResult,
          });
      final data = Map<String, dynamic>.from(result.data as Map);
      return BingoComment(
        id: data['id'] as String,
        boardId: board.id,
        authorId: currentUserId,
        authorName: authorName,
        body: body.trim(),
        createdAt: DateTime.now(),
        result: BingoResultSnapshot.fromJson(data['result']),
      );
    } on FirebaseFunctionsException catch (error) {
      throw _mapFunctionsError(error);
    }
  }

  @override
  Future<void> deleteComment(String boardId, String commentId) =>
      _bingos.doc(boardId).collection('comments').doc(commentId).delete();

  @override
  Future<void> report({
    required String boardId,
    required String targetType,
    required String targetId,
  }) async {
    final reportId = '${targetType}_${targetId}_$currentUserId';
    try {
      await _bingos.doc(boardId).collection('reports').doc(reportId).set({
        'bingoId': boardId,
        'targetType': targetType,
        'targetId': targetId,
        'reporterUserId': currentUserId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      // Rules only allow creating a report once; a second write is an update.
      if (error.code == 'permission-denied') {
        throw BingoException(BingoFailure.alreadyReported, error);
      }
      rethrow;
    }
  }

  @override
  Future<void> saveProfile({
    required String displayName,
    required String preferredLocale,
    required String region,
  }) async {
    final locale = AppLocaleParser.fromCode(preferredLocale) ?? AppLocale.ja;
    // Same `users/{uid}` document as tier-online, so the language and region
    // follow the account when both services are merged.
    await _firestore.collection('users').doc(currentUserId).set({
      'uid': currentUserId,
      'preferredLocale': locale.code,
      'preferredLanguage': locale.storageCode,
      'region': region,
      'bingoDisplayName': displayName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
