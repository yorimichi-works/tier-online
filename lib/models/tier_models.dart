import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

abstract final class TierCategory {
  static const ids = <String>[
    'games',
    'manga',
    'anime',
    'characters',
    'people',
    'food',
    'sports',
    'lifestyle',
    'humor',
    'other',
  ];

  static String fromLegacy(String value) =>
      const {
        'ゲーム': 'games',
        '漫画': 'manga',
        'アニメ': 'anime',
        'キャラクター': 'characters',
        '人物': 'people',
        '食べ物': 'food',
        'スポーツ': 'sports',
        '生活': 'lifestyle',
        'ネタ': 'humor',
        'Games': 'games',
        'Manga': 'manga',
        'Anime': 'anime',
        'Characters': 'characters',
        'People': 'people',
        'Food': 'food',
        'Sports': 'sports',
        'Lifestyle': 'lifestyle',
        'Humor': 'humor',
        '게임': 'games',
        '만화': 'manga',
        '애니메이션': 'anime',
        '캐릭터': 'characters',
        '인물': 'people',
        '음식': 'food',
        '스포츠': 'sports',
        '생활': 'lifestyle',
        '유머': 'humor',
      }[value] ??
      'other';
}

enum TierRank {
  ss('SS', 6, Color(0xFFFF575E)),
  s('S', 5, Color(0xFFFF8085)),
  a('A', 4, Color(0xFFFFBD76)),
  b('B', 3, Color(0xFFFFFF75)),
  c('C', 2, Color(0xFFB5FF72)),
  d('D', 1, Color(0xFF78C7FF));

  const TierRank(this.label, this.score, this.color);
  final String label;
  final int score;
  final Color color;

  static TierRank? parse(String value) {
    for (final rank in values) {
      if (rank.name == value) return rank;
    }
    return null;
  }
}

class TierItem {
  const TierItem({
    required this.id,
    required this.topicId,
    required this.sortIndex,
    this.name,
    this.imageUrl,
    this.colorSeed = 0,
    this.contentLanguage,
    this.isLanguageNeutral = false,
  }) : assert(name != null || imageUrl != null);

  final String id;
  final String topicId;
  final String? name;
  final String? imageUrl;
  final int sortIndex;
  final int colorSeed;
  final AppLocale? contentLanguage;
  final bool isLanguageNeutral;
  bool get hasName => name?.trim().isNotEmpty ?? false;
  bool get hasImage => imageUrl?.trim().isNotEmpty ?? false;
  String get accessibleLabel => hasName ? name! : '画像カード ${sortIndex + 1}';
}

class TalkPost {
  const TalkPost({
    required this.author,
    required this.body,
    required this.rank,
    required this.minutesAgo,
    this.id,
    this.createdAt,
    this.replies = const [],
    this.upvotes = 0,
    this.downvotes = 0,
    this.authorUserId,
    this.attachedTier = false,
  });
  final String? id;
  final String author;
  final String body;
  final TierRank rank;
  final int minutesAgo;
  final DateTime? createdAt;
  final List<TalkReply> replies;
  final int upvotes;
  final int downvotes;
  /// 投稿者の匿名/アカウントID。「自分のtierを載せる」で自分のTier結果に
  /// リンクするために使う。
  final String? authorUserId;
  /// 投稿時に「自分のtierを載せる」がチェックされていたかどうか。
  final bool attachedTier;
  int get displayMinutesAgo => createdAt == null
      ? minutesAgo
      : DateTime.now().difference(createdAt!).inMinutes.clamp(0, 999999);

  TalkPost copyWith({List<TalkReply>? replies, int? upvotes, int? downvotes}) =>
      TalkPost(
        id: id,
        author: author,
        body: body,
        rank: rank,
        minutesAgo: minutesAgo,
        createdAt: createdAt,
        replies: replies ?? this.replies,
        upvotes: upvotes ?? this.upvotes,
        downvotes: downvotes ?? this.downvotes,
        authorUserId: authorUserId,
        attachedTier: attachedTier,
      );
}

enum ReplyStance { agree, object }

class TalkReply {
  const TalkReply({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
    this.stance,
    this.replies = const [],
    this.upvotes = 0,
    this.downvotes = 0,
  });

  final String id;
  final String author;
  final String body;
  final DateTime createdAt;
  final ReplyStance? stance;
  final List<TalkReply> replies;
  final int upvotes;
  final int downvotes;

  TalkReply copyWith({
    List<TalkReply>? replies,
    int? upvotes,
    int? downvotes,
  }) => TalkReply(
    id: id,
    author: author,
    body: body,
    createdAt: createdAt,
    stance: stance,
    replies: replies ?? this.replies,
    upvotes: upvotes ?? this.upvotes,
    downvotes: downvotes ?? this.downvotes,
  );
}

class TierTopic {
  const TierTopic({
    required this.id,
    required this.title,
    required this.description,
    required this.tags,
    required this.category,
    required this.creatorName,
    required this.participants,
    required this.items,
    required this.community,
    this.talks = const [],
    this.isTrending = false,
    this.createdDaysAgo = 0,
    this.creatorId,
    this.likeCount = 0,
    this.contentLanguage = AppLocale.ja,
    this.targetRegion = 'JP',
    this.categoryId = 'other',
    this.sourceTierId,
    this.sourceTemplateId,
    this.isLanguageNeutral = false,
    this.moderationStatus = 'approved',
    this.reportCount = 0,
    this.createdByAnonymous = false,
    this.isPublic = true,
  });

  final String id;
  final String title;
  final String description;
  final List<String> tags;
  final String category;
  final String creatorName;
  final String? creatorId;
  final int participants;
  final List<TierItem> items;
  final Map<String, TierRank> community;
  final List<TalkPost> talks;
  final bool isTrending;
  final int createdDaysAgo;
  final int likeCount;
  final AppLocale contentLanguage;
  final String targetRegion;
  final String categoryId;
  final String? sourceTierId;
  final String? sourceTemplateId;
  final bool isLanguageNeutral;

  /// 'approved' | 'flagged' | 'blocked'
  final String moderationStatus;
  final int reportCount;
  final bool createdByAnonymous;
  final bool isPublic;

  TierItem? get faceItem {
    for (final rank in TierRank.values) {
      for (final item in items) {
        if (community[item.id] == rank) return item;
      }
    }
    return items.isEmpty ? null : items.first;
  }

  TierRank? get faceRank {
    final face = faceItem;
    return face == null ? null : community[face.id];
  }

  TierTopic copyWith({
    int? participants,
    Map<String, TierRank>? community,
    List<TalkPost>? talks,
    int? likeCount,
    AppLocale? contentLanguage,
    String? targetRegion,
    String? categoryId,
    String? sourceTierId,
    String? sourceTemplateId,
    bool? isLanguageNeutral,
    String? moderationStatus,
    int? reportCount,
    bool? isPublic,
  }) => TierTopic(
    id: id,
    title: title,
    description: description,
    tags: tags,
    category: category,
    creatorName: creatorName,
    creatorId: creatorId,
    participants: participants ?? this.participants,
    items: items,
    community: community ?? this.community,
    talks: talks ?? this.talks,
    isTrending: isTrending,
    createdDaysAgo: createdDaysAgo,
    likeCount: likeCount ?? this.likeCount,
    contentLanguage: contentLanguage ?? this.contentLanguage,
    targetRegion: targetRegion ?? this.targetRegion,
    categoryId: categoryId ?? this.categoryId,
    sourceTierId: sourceTierId ?? this.sourceTierId,
    sourceTemplateId: sourceTemplateId ?? this.sourceTemplateId,
    isLanguageNeutral: isLanguageNeutral ?? this.isLanguageNeutral,
    moderationStatus: moderationStatus ?? this.moderationStatus,
    reportCount: reportCount ?? this.reportCount,
    createdByAnonymous: createdByAnonymous,
    isPublic: isPublic ?? this.isPublic,
  );
}

class UserTierSubmission {
  const UserTierSubmission({
    required this.id,
    required this.topicId,
    required this.userId,
    required this.createdAt,
    required this.placements,
    this.region = 'JP',
  });
  final String id;
  final String topicId;
  final String userId;
  final DateTime createdAt;
  final Map<TierRank, List<String>> placements;
  final String region;
  int get placedCount =>
      placements.values.fold(0, (total, items) => total + items.length);
}
