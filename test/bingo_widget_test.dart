import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tier_table_online/bingo/bingo_app.dart';
import 'package:tier_table_online/bingo/domain/bingo_logic.dart';
import 'package:tier_table_online/bingo/models/bingo_models.dart';
import 'package:tier_table_online/bingo/services/bingo_state.dart';

Future<BingoState> _pumpApp(
  WidgetTester tester, {
  String path = '/ja/',
  Size size = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = BingoState(initialPath: path, entrySaveDelay: Duration.zero);
  await tester.runAsync(state.initialize);
  await tester.pumpWidget(BingoOnlineApp(state: state));
  await tester.pumpAndSettle();
  return state;
}

/// Taps every square of one completed line on the player's card.
Future<void> _completeFirstLine(
  WidgetTester tester,
  BingoState state,
  String boardId,
) async {
  final board = state.cachedBoard(boardId)!;
  final entry = state.entryFor(boardId)!;
  final line = BingoLogic.allLines(board.size).first;
  for (final position in line) {
    if (entry.layout[position] == BingoEntry.free) continue;
    final square = find.descendant(
      of: find.byKey(const ValueKey('player-card')),
      matching: find.byKey(ValueKey('square-$position')),
    );
    await tester.ensureVisible(square);
    await tester.tap(square);
    await tester.pump();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('URLの言語でホームを表示し、サンプルに参加してBINGOを結果付きでコメントできる', (tester) async {
    final state = await _pumpApp(tester);
    expect(find.text('ビンゴオンライン'), findsWidgets);
    expect(find.text('休日ビンゴ'), findsOneWidget);

    await tester.ensureVisible(find.text('旅行あるあるビンゴ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旅行あるあるビンゴ'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('join-button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('join-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player-card')), findsOneWidget);
    expect(state.entryFor('sample-travel'), isNotNull);

    await _completeFirstLine(tester, state, 'sample-travel');
    await tester.pumpAndSettle();
    expect(find.text('BINGO!'), findsOneWidget);
    expect(state.cachedBoard('sample-travel')!.bingoCount, 1);

    await tester.tap(find.byKey(const ValueKey('celebrate-share')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('comment-field')),
      '1ライン揃った！',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('post-comment')));
    await tester.tap(find.byKey(const ValueKey('post-comment')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final comments = state.commentsFor('sample-travel');
    expect(comments, hasLength(1));
    expect(comments.single.body, '1ライン揃った！');
    expect(comments.single.result?.lines, 1);
    expect(find.text('1ライン揃った！'), findsOneWidget);
    expect(find.text('1 BINGO'), findsWidgets);
  });

  testWidgets('英語URLでは英語UIになり、作成画面でマスが足りないと公開できない', (tester) async {
    await _pumpApp(tester, path: '/en/create');
    expect(find.text('Create bingo'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('field-title')), 'Mine');
    // A focused field keeps scrolling itself back into view.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('publish-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('publish-button')));
    await tester.pumpAndSettle();
    expect(find.text('Not enough squares'), findsOneWidget);
  });

  testWidgets('まとめ入力で3×3ビンゴを作って公開すると詳細へ移動する', (tester) async {
    final state = await _pumpApp(
      tester,
      path: '/ja/create',
      size: const Size(1280, 900),
    );
    await tester.enterText(find.byKey(const ValueKey('field-title')), '朝ビンゴ');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('3×3'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('bulk-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bulk-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('bulk-field')),
      List.generate(10, (index) => '項目$index').join('\n'),
    );
    await tester.tap(find.byKey(const ValueKey('bulk-add-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('10マス（最低8マス）'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('publish-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('publish-button')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(state.ownBoards.single.title, '朝ビンゴ');
    expect(state.ownBoards.single.cells, hasLength(10));
    expect(find.byKey(const ValueKey('board-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('join-button')), findsOneWidget);
  });
}
