import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

class GoogleImageSearchResult {
  const GoogleImageSearchResult({
    required this.query,
    this.imageUrl,
    this.sourceUrl,
  });

  final String query;
  final String? imageUrl;
  final String? sourceUrl;
}

class GoogleImageSearchService {
  const GoogleImageSearchService();

  Future<List<GoogleImageSearchResult>> searchFirstImages(
    List<String> names, {
    required String locale,
    required String region,
  }) async {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebaseが未設定です');
    }
    final callable = FirebaseFunctions.instance.httpsCallable(
      'searchTierItemImages',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );
    final results = <GoogleImageSearchResult>[];
    for (var start = 0; start < names.length; start += 30) {
      final end = (start + 30).clamp(0, names.length);
      final response = await callable.call<Map<String, dynamic>>({
        'names': names.sublist(start, end),
        'locale': locale,
        'region': region,
      });
      final rawResults = response.data['results'];
      if (rawResults is! List) continue;
      results.addAll(
        rawResults.whereType<Map<Object?, Object?>>().map((raw) {
          return GoogleImageSearchResult(
            query: raw['query'] as String? ?? '',
            imageUrl: raw['imageUrl'] as String?,
            sourceUrl: raw['sourceUrl'] as String?,
          );
        }),
      );
    }
    return results;
  }
}
