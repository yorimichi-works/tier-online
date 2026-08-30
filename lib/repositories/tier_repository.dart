import '../models/tier_models.dart';

abstract interface class TierRepository {
  List<TierTopic> getAll();
  TierTopic? getById(String id);
  void add(TierTopic topic);
  void remove(String id);
}
