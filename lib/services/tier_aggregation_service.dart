import 'dart:math' as math;

import '../models/tier_models.dart';

class TierAggregate {
  const TierAggregate({
    required this.ranks,
    required this.distributions,
    required this.disagreement,
    required this.submissionCount,
  });

  final Map<String, TierRank> ranks;
  final Map<String, Map<TierRank, int>> distributions;
  final Map<String, double> disagreement;
  final int submissionCount;
}

class TierAggregationService {
  const TierAggregationService();

  TierAggregate aggregate(
    List<TierItem> items,
    List<UserTierSubmission> submissions,
  ) {
    final ranks = <String, TierRank>{};
    final distributions = <String, Map<TierRank, int>>{};
    final disagreement = <String, double>{};
    for (final item in items) {
      final counts = {for (final rank in TierRank.values) rank: 0};
      final scores = <int>[];
      for (final submission in submissions) {
        for (final entry in submission.placements.entries) {
          if (entry.value.contains(item.id)) {
            counts[entry.key] = counts[entry.key]! + 1;
            scores.add(entry.key.score);
            break;
          }
        }
      }
      distributions[item.id] = counts;
      if (scores.isEmpty) continue;
      final average = scores.reduce((a, b) => a + b) / scores.length;
      ranks[item.id] = TierRank.values.reduce(
        (best, candidate) =>
            (candidate.score - average).abs() < (best.score - average).abs()
            ? candidate
            : best,
      );
      final variance =
          scores
              .map((score) => math.pow(score - average, 2).toDouble())
              .reduce((a, b) => a + b) /
          scores.length;
      disagreement[item.id] = variance;
    }
    return TierAggregate(
      ranks: ranks,
      distributions: distributions,
      disagreement: disagreement,
      submissionCount: submissions.length,
    );
  }
}
