import 'package:flutter_test/flutter_test.dart';
import 'package:tier_table_online/services/google_image_search_service.dart';

void main() {
  test('同梱済みの食べ物画像はFirebaseなしで再利用できる', () async {
    const service = GoogleImageSearchService();

    final results = await service.searchFirstImages(
      const ['カルボナーラ', ' いちご '],
      locale: 'ja',
      region: 'JP',
    );

    expect(results, hasLength(2));
    expect(results[0].query, 'カルボナーラ');
    expect(
      results[0].imageUrl,
      'assets/starter_tiers/items/pasta/carbonara.jpg',
    );
    expect(results[1].query, ' いちご ');
    expect(
      results[1].imageUrl,
      'assets/starter_tiers/items/fruit/strawberry.jpg',
    );
  });
}
