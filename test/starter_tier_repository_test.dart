import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tier_table_online/models/tier_models.dart';
import 'package:tier_table_online/repositories/starter_tier_repository.dart';

void main() {
  test(
    'starter topics are complete, image-backed, and start with zero likes',
    () {
      final topics = StarterTierRepository().getAll();

      expect(topics, hasLength(10));
      expect(topics.map((topic) => topic.id).toSet(), hasLength(10));
      for (final topic in topics) {
        expect(topic.isPublic, isTrue);
        expect(topic.moderationStatus, 'approved');
        expect(topic.likeCount, 0);
        expect(topic.items, hasLength(9));
        expect(topic.faceRank, TierRank.ss);
        expect(topic.faceItem, topic.items.first);

        for (final item in topic.items) {
          expect(item.hasImage, isTrue);
          expect(item.hasName, isTrue);
          expect(item.imageUrl, startsWith('assets/starter_tiers/items/'));
          expect(File(item.imageUrl!).existsSync(), isTrue);
        }
      }
    },
  );
}
