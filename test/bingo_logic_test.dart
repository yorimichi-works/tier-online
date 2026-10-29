import 'package:flutter_test/flutter_test.dart';
import 'package:tier_table_online/bingo/domain/bingo_logic.dart';
import 'package:tier_table_online/bingo/l10n/bingo_localizations.dart';
import 'package:tier_table_online/bingo/models/bingo_models.dart';
import 'package:tier_table_online/bingo/repositories/sample_bingo_boards.dart';
import 'package:tier_table_online/bingo/services/apple_artwork_service.dart';

BingoBoard _board({
  int size = 3,
  bool freeCenter = true,
  bool shuffle = true,
  int cells = 8,
}) => BingoBoard(
  id: 'board-1',
  title: 'Test',
  size: size,
  freeCenter: freeCenter,
  shufflePerPlayer: shuffle,
  cells: [for (var i = 0; i < cells; i++) BingoCell(text: 'cell $i')],
  creatorId: 'creator',
  creatorName: 'Creator',
  contentLanguage: AppLocale.ja,
  targetRegion: 'JP',
);

void main() {
  group('カード生成', () {
    test('同じ参加者には同じカード、別の参加者には別のカードを配る', () {
      final board = _board(size: 5, cells: 40);
      final first = BingoLogic.generateLayout(board, 'alice');
      expect(BingoLogic.generateLayout(board, 'alice'), first);
      expect(BingoLogic.generateLayout(board, 'bob'), isNot(first));
      expect(first, hasLength(25));
      expect(first[12], BingoEntry.free);
      final picked = first.where((cell) => cell != BingoEntry.free).toList();
      expect(picked.toSet(), hasLength(24), reason: 'マスは重複しない');
      expect(picked.every((cell) => cell >= 0 && cell < 40), isTrue);
    });

    test('シャッフルなしでは作成者の並び順をそのまま使う', () {
      final board = _board(shuffle: false, cells: 12);
      expect(BingoLogic.generateLayout(board, 'anyone'), [
        0,
        1,
        2,
        3,
        BingoEntry.free,
        4,
        5,
        6,
        7,
      ]);
    });

    test('偶数サイズにはFREEマスを置かない', () {
      final board = _board(size: 4, cells: 16);
      expect(board.requiredCells, 16);
      expect(
        BingoLogic.generateLayout(board, 'x'),
        isNot(contains(BingoEntry.free)),
      );
    });

    test('シード値は端末に依存しないFNV-1aで計算する', () {
      expect(BingoLogic.seedOf(''), 0x811c9dc5);
      expect(BingoLogic.seedOf('a'), 0xe40c292c);
    });
  });

  group('BINGO判定', () {
    const layout = [0, 1, 2, 3, BingoEntry.free, 4, 5, 6, 7];

    test('FREEを含む斜め・行・列を数える', () {
      expect(BingoLogic.lineCount(3, layout, {}), 0);
      expect(BingoLogic.lineCount(3, layout, {0, 8}), 1);
      expect(BingoLogic.lineCount(3, layout, {0, 8, 3, 5, 1, 7}), 3);
    });

    test('あと1マスのリーチ位置を返す', () {
      final marks = BingoLogic.effectiveMarks(layout, {0});
      expect(BingoLogic.reachPositions(3, marks), contains(8));
    });

    test('結果を絵文字グリッドで共有できる', () {
      expect(BingoLogic.emojiGrid(3, layout, {0, 8, 1}), '🟧🟦⬜\n⬜⭐⬜\n⬜⬜🟧');
    });

    test('集計はServerのaggregateBingoと同じ規則で数える', () {
      final board = _board();
      final aggregated = BingoLogic.aggregate(board, [
        BingoEntry(
          boardId: board.id,
          userId: 'a',
          userName: 'A',
          layout: layout,
          marked: const {0, 8},
        ),
        BingoEntry(
          boardId: board.id,
          userId: 'b',
          userName: 'B',
          layout: const [7, 6, 5, 4, BingoEntry.free, 3, 2, 1, 0],
          marked: const {0},
        ),
      ]);
      expect(aggregated.participants, 2);
      expect(aggregated.bingoCount, 1);
      expect(aggregated.markCounts[7], 2);
      expect(aggregated.appearanceCounts[0], 2);
      expect(BingoLogic.ranking(aggregated).first.cell, 7);
    });
  });

  group('作成フォーム検証', () {
    test('タイトル・マス数・重複・文字数を検証する', () {
      List<BingoDraftIssue> validate(
        List<BingoCell> cells, {
        String title = 'x',
      }) => BingoDraftValidator.validate(
        title: title,
        description: '',
        tags: const [],
        size: 3,
        freeCenter: true,
        cells: cells,
      );
      final ok = [for (var i = 0; i < 8; i++) BingoCell(text: '$i')];
      expect(validate(ok), isEmpty);
      expect(validate(ok, title: ' '), contains(BingoDraftIssue.titleRequired));
      expect(
        validate(ok.take(7).toList()),
        contains(BingoDraftIssue.notEnoughCells),
      );
      expect(
        validate([...ok.take(7), const BingoCell(text: ' 0 ')]),
        contains(BingoDraftIssue.duplicateCells),
      );
      expect(
        validate([...ok.take(7), BingoCell(text: 'あ' * 41)]),
        contains(BingoDraftIssue.cellTextTooLong),
      );
    });

    test('画像だけのマスは同じ文字列がなくても重複扱いしない', () {
      final cells = [
        for (var i = 0; i < 8; i++)
          BingoCell(imageUrl: 'data:image/jpeg;base64,$i'),
      ];
      expect(
        BingoDraftValidator.validate(
          title: 'x',
          description: '',
          tags: const [],
          size: 3,
          freeCenter: true,
          cells: cells,
        ),
        isEmpty,
      );
    });

    test('まとめ入力とタグを分割する', () {
      expect(BingoDraftValidator.splitBulkText('A\n\n b \r\nA\nC'), [
        'A',
        'b',
        'C',
      ]);
      expect(BingoDraftValidator.parseTags('夏 #旅行、夏,休日'), ['夏', '旅行', '休日']);
    });
  });

  group('保存形式', () {
    test('ボードと参加記録をJSONで往復できる', () {
      final board = _board().copyWith(
        markCounts: {1: 3},
        appearanceCounts: {1: 4},
        cells: const [
          BingoCell(text: 'a'),
          BingoCell(
            imageUrl: 'https://is1-ssl.mzstatic.com/a/600x600bb.jpg',
            imageSource: BingoImageSource.itunes,
            imageCredit: 'Artist – Album',
          ),
        ],
      );
      final restored = BingoBoard.fromJson(board.toJson());
      expect(restored.cells[1].imageCredit, 'Artist – Album');
      expect(restored.markCounts, {1: 3});
      expect(restored.contentLanguage, AppLocale.ja);

      final entry = BingoEntry(
        boardId: 'b',
        userId: 'u',
        userName: 'U',
        layout: const [0, 1, 2, 3, -1, 4, 5, 6, 7],
        marked: const {3, 1},
      );
      final restoredEntry = BingoEntry.fromJson(entry.toJson());
      expect(restoredEntry.marked, {1, 3});
      expect(restoredEntry.layout, entry.layout);
    });

    test('壊れた結果スナップショットは表示しない', () {
      expect(
        BingoResultSnapshot.fromJson({
          'size': 3,
          'layout': [0, 1],
          'marked': [0],
        }),
        isNull,
      );
    });
  });

  group('サンプルと多言語', () {
    test('全言語のサンプルが同じIDと同じマス数を持つ', () {
      final reference = SampleBingoBoards.forLocale(AppLocale.ja);
      for (final locale in AppLocale.values) {
        final samples = SampleBingoBoards.forLocale(locale);
        expect(samples.map((board) => board.id), reference.map((b) => b.id));
        for (var i = 0; i < samples.length; i++) {
          expect(samples[i].cells, hasLength(reference[i].cells.length));
          expect(
            samples[i].cells.length,
            greaterThanOrEqualTo(samples[i].requiredCells),
          );
          expect(
            BingoDraftValidator.validate(
              title: samples[i].title,
              description: samples[i].description,
              tags: samples[i].tags,
              size: samples[i].size,
              freeCenter: samples[i].freeCenter,
              cells: samples[i].cells,
            ),
            isEmpty,
            reason: '${locale.code} ${samples[i].id}',
          );
        }
      }
    });

    test('UI辞書は全言語で同じキーを持つ', () {
      final reference = BingoLocalizations.keysForTesting(AppLocale.ja);
      expect(reference, isNotEmpty);
      for (final locale in AppLocale.values) {
        expect(
          BingoLocalizations.keysForTesting(locale),
          reference,
          reason: locale.code,
        );
      }
      for (final region in SupportedRegion.values) {
        expect(reference, contains('region.${region.code}'));
      }
      for (final issue in BingoDraftIssue.values) {
        expect(reference, contains('issue.${issue.name}'));
      }
    });
  });

  group('Apple画像', () {
    test('mzstaticのURLだけを受け付け、HTTPSの600pxへ変換する', () {
      expect(
        AppleArtworkResolver.resize(
          'http://is1-ssl.mzstatic.com/image/thumb/a/b.jpg/100x100bb.jpg',
          600,
        ),
        'https://is1-ssl.mzstatic.com/image/thumb/a/b.jpg/600x600bb.jpg',
      );
      expect(
        AppleArtworkResolver.resize('https://example.com/a.jpg', 600),
        isNull,
      );
      expect(AppleArtworkResolver.resize('javascript:alert(1)', 600), isNull);
    });

    test('アルバム検索結果からジャケットを重複なく取り出す', () {
      const art = 'https://is1-ssl.mzstatic.com/image/thumb/x/100x100bb.jpg';
      final results = AppleArtworkService.parse({
        'results': [
          {
            'wrapperType': 'collection',
            'collectionType': 'Album',
            'collectionId': 1,
            'collectionName': 'Album A',
            'artistName': 'Artist',
            'artworkUrl100': art,
          },
          {
            'wrapperType': 'collection',
            'collectionType': 'Album',
            'collectionId': 2,
            'collectionName': 'Album A (dup art)',
            'artistName': 'Artist',
            'artworkUrl100': art,
          },
          {
            'wrapperType': 'track',
            'kind': 'song',
            'trackId': 3,
            'trackName': 'Song',
            'artworkUrl100': art,
          },
        ],
      }, AppleArtworkKind.album);
      expect(results, hasLength(1));
      expect(results.single.credit, 'Artist – Album A');
      expect(results.single.artworkUrl, endsWith('/400x400bb.jpg'));
    });

    test('地域コードからiTunesストアの国を選ぶ', () {
      expect(AppleArtworkService.countryFor('JP'), 'JP');
      expect(AppleArtworkService.countryFor('GLOBAL'), 'US');
    });
  });
}
