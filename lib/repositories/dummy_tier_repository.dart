import '../models/tier_models.dart';
import 'tier_repository.dart';

class DummyTierRepository implements TierRepository {
  DummyTierRepository() : _topics = _seed();
  final List<TierTopic> _topics;

  @override
  List<TierTopic> getAll() => List.unmodifiable(_topics);

  @override
  TierTopic? getById(String id) {
    for (final topic in _topics) {
      if (topic.id == id) return topic;
    }
    return null;
  }

  @override
  void add(TierTopic topic) {
    _topics.removeWhere((existing) => existing.id == topic.id);
    _topics.insert(0, topic);
  }

  @override
  void remove(String id) => _topics.removeWhere((topic) => topic.id == id);

  static List<TierTopic> _seed() => [
    _make(
      'yokai',
      '最強の妖怪Tier',
      '伝承・知名度・能力をまとめて評価。あなたが思う最強は？',
      ['妖怪', '民俗', '日本文化'],
      'キャラクター',
      12842,
      [
        '鬼',
        '天狗',
        '河童',
        '九尾の狐',
        'ぬらりひょん',
        '雪女',
        '一反木綿',
        '座敷童子',
        '酒呑童子',
        '玉藻前',
        '鵺',
        '猫又',
      ],
      trending: true,
      talks: const [
        TalkPost(
          id: 'yokai-talk-1',
          author: '夜ふかし太郎',
          body: '天狗は飛行と神通力込みならSでいいと思う。',
          rank: TierRank.s,
          minutesAgo: 12,
        ),
        TalkPost(
          id: 'yokai-talk-2',
          author: '妖怪好き',
          body: '河童Bは低すぎる。水辺ならAはあるはず。',
          rank: TierRank.a,
          minutesAgo: 38,
        ),
      ],
    ),
    _make(
      'games',
      '歴代最強ゲームTier',
      '時代を変えた名作を、いま遊んだ目線で並べよう。',
      ['ゲーム', '名作'],
      'ゲーム',
      8240,
      [
        'クロノ・トリガー',
        'ゼルダの伝説',
        'Minecraft',
        'テトリス',
        'Portal 2',
        'UNDERTALE',
        'スーパーマリオ64',
        'ELDEN RING',
      ],
      trending: true,
    ),
    _make(
      'food',
      '好きなコンビニ飯Tier',
      'おにぎりからホットスナックまで、日常の最強を決めよう。',
      ['食べ物', 'コンビニ'],
      '食べ物',
      6451,
      ['ツナマヨおにぎり', 'からあげ', '肉まん', 'サンドイッチ', 'カップ麺', 'プリン', 'おでん', '焼き鳥'],
    ),
    _make(
      'jump',
      '歴代ジャンプ作品Tier',
      '何度でも読み返したい歴代作品を並べよう。',
      ['漫画', '少年ジャンプ'],
      '漫画',
      5890,
      [
        'DRAGON BALL',
        'ONE PIECE',
        'NARUTO',
        'SLAM DUNK',
        'HUNTER×HUNTER',
        'BLEACH',
        '鬼滅の刃',
        'チェンソーマン',
      ],
    ),
    _make(
      'cities',
      '住みたい都道府県Tier',
      '交通、食、自然。暮らすならどこ？',
      ['生活', '日本'],
      '生活',
      3912,
      ['北海道', '宮城', '東京', '神奈川', '愛知', '京都', '大阪', '福岡'],
    ),
    _make(
      'rpg',
      '最強RPG主人公Tier',
      'ゲーム内性能と物語での活躍から評価。',
      ['ゲーム', 'RPG', '主人公'],
      'ゲーム',
      2841,
      ['勇者ロト', '光の戦士', 'クロノ', 'クラウド', 'ネス', 'リンク', 'ジョーカー', '褪せ人'],
    ),
    _make(
      'history',
      '一緒に飲みたい歴史人物Tier',
      '一晩語るなら誰を選ぶ？',
      ['人物', '歴史'],
      '人物',
      2218,
      ['織田信長', '坂本龍馬', '紫式部', '伊達政宗', '卑弥呼', '徳川家康', '聖徳太子', '葛飾北斎'],
    ),
    _make(
      'scary',
      '絶対に遭遇したくない妖怪Tier',
      '強さより怖さ。夜道で会いたくない順。',
      ['妖怪', 'ネタ'],
      'ネタ',
      1954,
      ['がしゃどくろ', '牛鬼', '土蜘蛛', '海坊主', '絡新婦', '輪入道', 'のっぺらぼう', '枕返し'],
    ),
    _make(
      'anime',
      '平成アニメTier',
      '平成を彩った作品を思い出補正込みで評価。',
      ['アニメ', '平成'],
      'アニメ',
      5197,
      [
        'エヴァンゲリオン',
        'カウボーイビバップ',
        '鋼の錬金術師',
        'けいおん！',
        'コードギアス',
        'まどか☆マギカ',
        '進撃の巨人',
        '日常',
      ],
    ),
    _make(
      'ramen',
      '最強ラーメンTier',
      '今日食べたい一杯を、直感で並べよう。',
      ['食べ物', 'ラーメン'],
      '食べ物',
      4377,
      ['醤油', '味噌', '塩', '豚骨', '家系', '二郎系', 'つけ麺', '担々麺'],
      createdDaysAgo: 1,
    ),
  ];

  static TierTopic _make(
    String id,
    String title,
    String description,
    List<String> tags,
    String category,
    int participants,
    List<String?> names, {
    bool trending = false,
    int createdDaysAgo = 4,
    List<TalkPost> talks = const [],
  }) {
    final items = [
      for (var i = 0; i < names.length; i++)
        TierItem(
          id: '$id-$i',
          topicId: id,
          sortIndex: i,
          name: names[i],
          colorSeed: i,
        ),
    ];
    return TierTopic(
      id: id,
      title: title,
      description: description,
      tags: tags,
      category: category,
      categoryId: TierCategory.fromLegacy(category),
      creatorName: ['tier猫', '並べる人', '匿名クリエイター'][id.length % 3],
      participants: participants,
      likeCount: (participants / 17).round(),
      items: items,
      community: {
        for (var i = 0; i < items.length; i++)
          items[i].id:
              TierRank.values[(i * 3 + id.length) % TierRank.values.length],
      },
      talks: talks,
      isTrending: trending,
      createdDaysAgo: createdDaysAgo,
    );
  }
}
