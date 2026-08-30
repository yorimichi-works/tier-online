import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

import '../repositories/starter_tier_repository.dart';

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

  static String _normalizeName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static final Map<String, String> _bundledFoodImages = () {
    final images = <String, String>{};
    for (final topic in StarterTierRepository().getAll()) {
      if (topic.categoryId != 'food') continue;
      for (final item in topic.items) {
        if (item.hasName && item.hasImage) {
          images.putIfAbsent(_normalizeName(item.name!), () => item.imageUrl!);
        }
      }
    }
    return images;
  }();

  Future<List<GoogleImageSearchResult>> searchFirstImages(
    List<String> names, {
    required String locale,
    required String region,
  }) async {
    final results = <GoogleImageSearchResult>[];
    final unresolved = <String>[];
    for (final name in names) {
      final bundledImage = _bundledFoodImages[_normalizeName(name)];
      if (bundledImage == null) {
        unresolved.add(name);
      } else {
        results.add(
          GoogleImageSearchResult(query: name, imageUrl: bundledImage),
        );
      }
    }
    if (unresolved.isEmpty) return results;
    if (Firebase.apps.isEmpty) throw StateError('Firebaseが未設定です');

    final callable = FirebaseFunctions.instance.httpsCallable(
      'searchTierItemImages',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );
    for (var start = 0; start < unresolved.length; start += 30) {
      final end = (start + 30).clamp(0, unresolved.length);
      final response = await callable.call<Map<String, dynamic>>({
        'names': unresolved.sublist(start, end),
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
