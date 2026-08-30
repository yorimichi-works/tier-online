import '../l10n/app_localizations.dart';
import 'tier_models.dart';

abstract final class TierSerialization {
  static Map<String, Object?> itemToJson(TierItem item) => {
    'id': item.id,
    'topicId': item.topicId,
    'name': item.name,
    'imageUrl': item.imageUrl,
    'sortIndex': item.sortIndex,
    'colorSeed': item.colorSeed,
    'contentLanguage': item.contentLanguage?.code,
    'isLanguageNeutral': item.isLanguageNeutral,
  };

  static TierItem itemFromJson(Map<String, Object?> json) => TierItem(
    id: json['id']! as String,
    topicId: json['topicId']! as String,
    name: json['name'] as String?,
    imageUrl: json['imageUrl'] as String?,
    sortIndex: json['sortIndex']! as int,
    colorSeed: json['colorSeed'] as int? ?? 0,
    contentLanguage: AppLocaleParser.fromCode(
      json['contentLanguage'] as String?,
    ),
    isLanguageNeutral:
        json['isLanguageNeutral'] as bool? ??
        (json['contentLanguage'] == null && json['name'] == null),
  );

  static Map<String, Object?> talkToJson(TalkPost post) => {
    'id': post.id,
    'author': post.author,
    'body': post.body,
    'rank': post.rank.name,
    'minutesAgo': post.minutesAgo,
    'createdAt': post.createdAt?.toIso8601String(),
    'replies': post.replies.map(replyToJson).toList(),
    'upvotes': post.upvotes,
    'downvotes': post.downvotes,
    'authorUserId': post.authorUserId,
    'attachedTier': post.attachedTier,
  };

  static TalkPost talkFromJson(Map<String, Object?> json) => TalkPost(
    id: json['id'] as String?,
    author: json['author']! as String,
    body: json['body']! as String,
    rank: TierRank.parse(json['rank']! as String) ?? TierRank.b,
    minutesAgo: json['minutesAgo'] as int? ?? 0,
    createdAt: json['createdAt'] == null
        ? null
        : DateTime.parse(json['createdAt']! as String),
    replies: (json['replies'] as List<Object?>? ?? const [])
        .map((reply) => replyFromJson((reply! as Map).cast<String, Object?>()))
        .toList(),
    upvotes: json['upvotes'] as int? ?? 0,
    downvotes: json['downvotes'] as int? ?? 0,
    authorUserId: json['authorUserId'] as String?,
    attachedTier: json['attachedTier'] as bool? ?? false,
  );

  static Map<String, Object?> replyToJson(TalkReply reply) => {
    'id': reply.id,
    'author': reply.author,
    'body': reply.body,
    'createdAt': reply.createdAt.toIso8601String(),
    'stance': reply.stance?.name,
    'replies': reply.replies.map(replyToJson).toList(),
    'upvotes': reply.upvotes,
    'downvotes': reply.downvotes,
  };

  static TalkReply replyFromJson(Map<String, Object?> json) => TalkReply(
    id: json['id']! as String,
    author: json['author']! as String,
    body: json['body']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
    stance: json['stance'] == null
        ? null
        : ReplyStance.values.byName(json['stance']! as String),
    replies: (json['replies'] as List<Object?>? ?? const [])
        .map((child) => replyFromJson((child! as Map).cast<String, Object?>()))
        .toList(),
    upvotes: json['upvotes'] as int? ?? 0,
    downvotes: json['downvotes'] as int? ?? 0,
  );

  static Map<String, Object?> topicToJson(TierTopic topic) => {
    'id': topic.id,
    'title': topic.title,
    'description': topic.description,
    'tags': topic.tags,
    'category': topic.category,
    'creatorName': topic.creatorName,
    'creatorId': topic.creatorId,
    'participants': topic.participants,
    'likeCount': topic.likeCount,
    'items': topic.items.map(itemToJson).toList(),
    'community': topic.community.map((key, value) => MapEntry(key, value.name)),
    'talks': topic.talks.map(talkToJson).toList(),
    'isTrending': topic.isTrending,
    'createdDaysAgo': topic.createdDaysAgo,
    'contentLanguage': topic.contentLanguage.code,
    'targetRegion': topic.targetRegion,
    'categoryId': topic.categoryId,
    'sourceTierId': topic.sourceTierId,
    'sourceTemplateId': topic.sourceTemplateId,
    'isLanguageNeutral': topic.isLanguageNeutral,
    'isPublic': topic.isPublic,
  };

  static TierTopic topicFromJson(Map<String, Object?> json) => TierTopic(
    id: json['id']! as String,
    title: json['title']! as String,
    description: json['description'] as String? ?? '',
    tags: (json['tags'] as List<Object?>? ?? const []).cast<String>(),
    category: json['category'] as String? ?? 'その他',
    creatorName: json['creatorName'] as String? ?? '匿名クリエイター',
    creatorId: json['creatorId'] as String?,
    participants: json['participants'] as int? ?? 1,
    likeCount: json['likeCount'] as int? ?? 0,
    items: (json['items'] as List<Object?>? ?? const [])
        .map((item) => itemFromJson((item! as Map).cast<String, Object?>()))
        .toList(),
    community: (json['community'] as Map<Object?, Object?>? ?? const {}).map(
      (key, value) => MapEntry(
        key! as String,
        TierRank.parse(value! as String) ?? TierRank.b,
      ),
    ),
    talks: (json['talks'] as List<Object?>? ?? const [])
        .map((post) => talkFromJson((post! as Map).cast<String, Object?>()))
        .toList(),
    isTrending: json['isTrending'] as bool? ?? false,
    createdDaysAgo: json['createdDaysAgo'] as int? ?? 0,
    contentLanguage:
        AppLocaleParser.fromCode(json['contentLanguage'] as String?) ??
        AppLocale.ja,
    targetRegion: json['targetRegion'] as String? ?? 'JP',
    categoryId:
        json['categoryId'] as String? ??
        TierCategory.fromLegacy(json['category'] as String? ?? ''),
    sourceTierId: json['sourceTierId'] as String?,
    sourceTemplateId: json['sourceTemplateId'] as String?,
    isLanguageNeutral: json['isLanguageNeutral'] as bool? ?? false,
    isPublic: json['isPublic'] as bool? ?? true,
  );

  static Map<String, Object?> submissionToJson(UserTierSubmission value) => {
    'id': value.id,
    'topicId': value.topicId,
    'userId': value.userId,
    'createdAt': value.createdAt.toIso8601String(),
    'placements': value.placements.map(
      (key, items) => MapEntry(key.name, items),
    ),
    'region': value.region,
  };

  static UserTierSubmission submissionFromJson(Map<String, Object?> json) =>
      UserTierSubmission(
        id: json['id']! as String,
        topicId: json['topicId']! as String,
        userId: json['userId']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String),
        placements: _placementsFromJson(
          json['placements']! as Map<Object?, Object?>,
        ),
        region: json['region'] as String? ?? 'JP',
      );

  static Map<TierRank, List<String>> _placementsFromJson(
    Map<Object?, Object?> json,
  ) {
    final result = <TierRank, List<String>>{};
    for (final entry in json.entries) {
      final rank = TierRank.parse(entry.key! as String);
      if (rank != null) {
        result[rank] = (entry.value! as List<Object?>).cast<String>();
      }
    }
    return result;
  }
}
