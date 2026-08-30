import '../models/tier_models.dart';
import 'tier_repository.dart';

const starterTierCreatorName = 'tier_online';
const starterTierCreatorId = 'tier_online';

class StarterTierRepository implements TierRepository {
  StarterTierRepository() : _topics = _specs.map(_buildTopic).toList();

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
    _topics.removeWhere((current) => current.id == topic.id);
    _topics.insert(0, topic);
  }

  @override
  void remove(String id) => _topics.removeWhere((topic) => topic.id == id);

  static TierTopic _buildTopic(_StarterSpec spec) {
    final id = 'starter-${spec.slug}';
    final items = [
      for (var index = 0; index < spec.items.length; index++)
        TierItem(
          id: '$id-${spec.items[index].slug}',
          topicId: id,
          sortIndex: index,
          name: spec.items[index].name,
          imageUrl:
              'assets/starter_tiers/items/${spec.slug}/${spec.items[index].slug}.jpg',
          colorSeed: index,
        ),
    ];
    const ranks = [
      TierRank.ss,
      TierRank.s,
      TierRank.a,
      TierRank.b,
      TierRank.c,
      TierRank.d,
      TierRank.a,
      TierRank.b,
      TierRank.c,
    ];
    return TierTopic(
      id: id,
      title: spec.title,
      description: spec.description,
      tags: spec.tags,
      category: spec.category,
      categoryId: spec.category == '食べ物' ? 'food' : 'lifestyle',
      creatorName: starterTierCreatorName,
      creatorId: starterTierCreatorId,
      participants: 1,
      likeCount: 0,
      items: items,
      community: {
        for (var index = 0; index < items.length; index++)
          items[index].id: ranks[index],
      },
      createdDaysAgo: spec.createdDaysAgo,
      moderationStatus: 'approved',
      reportCount: 0,
      createdByAnonymous: false,
      isPublic: true,
    );
  }
}

class _StarterSpec {
  const _StarterSpec(
    this.slug,
    this.title,
    this.description,
    this.tags,
    this.category,
    this.createdDaysAgo,
    this.items,
  );
  final String slug;
  final String title;
  final String description;
  final List<String> tags;
  final String category;
  final int createdDaysAgo;
  final List<_ItemSpec> items;
}

class _ItemSpec {
  const _ItemSpec(this.name, this.slug);
  final String name;
  final String slug;
}

const _specs = <_StarterSpec>[
  _StarterSpec(
    'pasta',
    '美味しいパスタTier',
    'ソースの完成度、香り、食感を思い浮かべながら、好きなパスタを並べよう。',
    ['パスタ', 'イタリア料理', 'グルメ'],
    '食べ物',
    0,
    [
      _ItemSpec('カルボナーラ', 'carbonara'),
      _ItemSpec('ボロネーゼ', 'bolognese'),
      _ItemSpec('ジェノベーゼ', 'genovese'),
      _ItemSpec('アラビアータ', 'arrabbiata'),
      _ItemSpec('ボンゴレ', 'vongole'),
      _ItemSpec('カチョ・エ・ペペ', 'cacio-e-pepe'),
      _ItemSpec('ラザニア', 'lasagna'),
      _ItemSpec('アーリオ・オーリオ', 'aglio-e-olio'),
      _ItemSpec('魚介のトマトパスタ', 'seafood-tomato'),
    ],
  ),
  _StarterSpec(
    'breakfast',
    '世界の朝ごはんTier',
    '一日の始まりに食べたい、世界の朝ごはんを自由にランク付け。',
    ['朝ごはん', '世界の料理', 'グルメ'],
    '食べ物',
    1,
    [
      _ItemSpec('パンケーキ', 'pancakes'),
      _ItemSpec('クロワッサン', 'croissant'),
      _ItemSpec('シャクシュカ', 'shakshuka'),
      _ItemSpec('和朝食', 'japanese-breakfast'),
      _ItemSpec('イングリッシュブレックファスト', 'english-breakfast'),
      _ItemSpec('マサラドーサ', 'masala-dosa'),
      _ItemSpec('アボカドトースト', 'avocado-toast'),
      _ItemSpec('ブレックファストタコス', 'breakfast-tacos'),
      _ItemSpec('お粥', 'congee'),
    ],
  ),
  _StarterSpec(
    'pizza',
    'ピザTier',
    '定番から個性派まで、今すぐ食べたいピザを本気で選ぼう。',
    ['ピザ', 'イタリア料理', 'グルメ'],
    '食べ物',
    2,
    [
      _ItemSpec('マルゲリータ', 'margherita'),
      _ItemSpec('ペパロニ', 'pepperoni'),
      _ItemSpec('クアトロフォルマッジ', 'quattro-formaggi'),
      _ItemSpec('生ハムとルッコラ', 'prosciutto'),
      _ItemSpec('マリナーラ', 'marinara'),
      _ItemSpec('ハワイアン', 'hawaiian'),
      _ItemSpec('きのこ', 'mushroom'),
      _ItemSpec('彩り野菜', 'vegetable'),
      _ItemSpec('スパイシーサラミ', 'spicy-salami'),
    ],
  ),
  _StarterSpec(
    'sweets',
    '世界のスイーツTier',
    'ご褒美に選ぶならどれ？ 人気スイーツを見た目と味で並べよう。',
    ['スイーツ', 'デザート', 'お菓子'],
    '食べ物',
    3,
    [
      _ItemSpec('チーズケーキ', 'cheesecake'),
      _ItemSpec('ティラミス', 'tiramisu'),
      _ItemSpec('マカロン', 'macarons'),
      _ItemSpec('プリン', 'flan'),
      _ItemSpec('チョコレートケーキ', 'chocolate-cake'),
      _ItemSpec('フルーツタルト', 'fruit-tart'),
      _ItemSpec('ドーナツ', 'donut'),
      _ItemSpec('ジェラート', 'gelato'),
      _ItemSpec('ショートケーキ', 'strawberry-shortcake'),
    ],
  ),
  _StarterSpec(
    'ramen',
    'ラーメンTier',
    'スープ、麺、香り、トッピング。あなたの最強の一杯を決めよう。',
    ['ラーメン', '麺', 'グルメ'],
    '食べ物',
    4,
    [
      _ItemSpec('醤油', 'shoyu'),
      _ItemSpec('味噌', 'miso'),
      _ItemSpec('塩', 'shio'),
      _ItemSpec('豚骨', 'tonkotsu'),
      _ItemSpec('担々麺', 'tantanmen'),
      _ItemSpec('つけ麺', 'tsukemen'),
      _ItemSpec('鶏白湯', 'chicken-paitan'),
      _ItemSpec('旨辛', 'spicy'),
      _ItemSpec('海鮮', 'seafood'),
    ],
  ),
  _StarterSpec(
    'coffee',
    'コーヒーTier',
    '香りを楽しむ一杯から甘いデザート系まで、好みのコーヒーを比較。',
    ['コーヒー', 'カフェ', 'ドリンク'],
    '食べ物',
    5,
    [
      _ItemSpec('エスプレッソ', 'espresso'),
      _ItemSpec('カフェラテ', 'latte'),
      _ItemSpec('カプチーノ', 'cappuccino'),
      _ItemSpec('アメリカーノ', 'americano'),
      _ItemSpec('カフェモカ', 'mocha'),
      _ItemSpec('フラットホワイト', 'flat-white'),
      _ItemSpec('コールドブリュー', 'cold-brew'),
      _ItemSpec('アフォガート', 'affogato'),
      _ItemSpec('ベトナムコーヒー', 'vietnamese-iced'),
    ],
  ),
  _StarterSpec(
    'curry',
    '世界のカレーTier',
    '濃厚、爽やか、激辛。個性豊かな世界のカレーを食べ比べる気分で並べよう。',
    ['カレー', '世界の料理', 'スパイス'],
    '食べ物',
    6,
    [
      _ItemSpec('日本のカレー', 'japanese'),
      _ItemSpec('バターチキン', 'butter-chicken'),
      _ItemSpec('グリーンカレー', 'green'),
      _ItemSpec('マッサマン', 'massaman'),
      _ItemSpec('ヴィンダルー', 'vindaloo'),
      _ItemSpec('ダール', 'dal'),
      _ItemSpec('スリランカカレー', 'sri-lankan'),
      _ItemSpec('カツカレー', 'katsu'),
      _ItemSpec('野菜ココナッツカレー', 'vegetable-coconut'),
    ],
  ),
  _StarterSpec(
    'bread',
    '世界のパンTier',
    '香ばしいハード系からふわふわ食パンまで、好きなパンを選ぼう。',
    ['パン', 'ベーカリー', '朝ごはん'],
    '食べ物',
    7,
    [
      _ItemSpec('バゲット', 'baguette'),
      _ItemSpec('クロワッサン', 'croissant'),
      _ItemSpec('サワードウ', 'sourdough'),
      _ItemSpec('ブリオッシュ', 'brioche'),
      _ItemSpec('プレッツェル', 'pretzel'),
      _ItemSpec('フォカッチャ', 'focaccia'),
      _ItemSpec('ベーグル', 'bagel'),
      _ItemSpec('ミルク食パン', 'milk-bread'),
      _ItemSpec('ライ麦パン', 'rye'),
    ],
  ),
  _StarterSpec(
    'fruit',
    '好きなフルーツTier',
    '甘さ、酸味、香り、食感。毎日でも食べたいフルーツはどれ？',
    ['フルーツ', '果物', '食べ物'],
    '食べ物',
    8,
    [
      _ItemSpec('いちご', 'strawberry'),
      _ItemSpec('マンゴー', 'mango'),
      _ItemSpec('すいか', 'watermelon'),
      _ItemSpec('桃', 'peach'),
      _ItemSpec('ぶどう', 'grapes'),
      _ItemSpec('パイナップル', 'pineapple'),
      _ItemSpec('キウイ', 'kiwi'),
      _ItemSpec('りんご', 'apple'),
      _ItemSpec('バナナ', 'banana'),
    ],
  ),
  _StarterSpec(
    'landscapes',
    '行ってみたい絶景Tier',
    '海、山、砂漠、雪景色。次の旅で見てみたい景色を直感で選ぼう。',
    ['旅行', '絶景', '自然'],
    '生活',
    9,
    [
      _ItemSpec('南国のビーチ', 'tropical-beach'),
      _ItemSpec('アルプスの湖', 'alpine-lake'),
      _ItemSpec('黄金の砂丘', 'desert-dunes'),
      _ItemSpec('オーロラ', 'aurora'),
      _ItemSpec('大瀑布', 'waterfall'),
      _ItemSpec('桜の谷', 'cherry-valley'),
      _ItemSpec('赤い大峡谷', 'red-canyon'),
      _ItemSpec('雪の山村', 'snow-village'),
      _ItemSpec('青の洞窟', 'blue-cave'),
    ],
  ),
];
