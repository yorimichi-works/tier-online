import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tier_table_online/bingo/bingo_app.dart';
import 'package:tier_table_online/bingo/models/bingo_models.dart';
import 'package:tier_table_online/bingo/services/bingo_state.dart';
import 'package:tier_table_online/domain/internationalization.dart';

BingoBoard _board(String id, {required int participants}) => BingoBoard(
  id: id,
  title: id,
  size: 3,
  cells: [for (var i = 0; i < 8; i++) BingoCell(text: '$i')],
  creatorId: 'me',
  creatorName: 'Me',
  contentLanguage: AppLocale.ja,
  targetRegion: 'JP',
  participants: participants,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('いいねは押すと増え、もう一度押すと取り消せる', () async {
    final state = BingoState();
    await state.initialize();
    final sample = state.samples.first;
    await state.loadBoard(sample.id);

    await state.toggleBoardLike(sample);
    expect(state.isLiked(sample.id), isTrue);
    expect(state.cachedBoard(sample.id)!.likeCount, 1);

    await state.toggleBoardLike(sample);
    expect(state.isLiked(sample.id), isFalse);
    expect(state.cachedBoard(sample.id)!.likeCount, 0);
  });

  test('リアクションは1人1つで、付け替え・取り消しができ、端末に残る', () async {
    final state = BingoState();
    await state.initialize();
    final sample = state.samples.first;
    await state.loadBoard(sample.id);
    final comment = await state.postComment(
      sample,
      body: 'すごい',
      attachResult: false,
    );

    await state.toggleReaction(sample, comment, BingoReaction.clap);
    expect(state.reactionFor(sample.id, comment.id), 'clap');
    expect(state.commentsFor(sample.id).single.reactionCounts, {'clap': 1});

    await state.toggleReaction(sample, comment, BingoReaction.heart);
    expect(state.commentsFor(sample.id).single.reactionCounts, {'heart': 1});

    final reloaded = BingoState();
    await reloaded.initialize();
    await reloaded.loadBoard(sample.id);
    await reloaded.loadComments(sample.id);
    expect(reloaded.reactionFor(sample.id, comment.id), 'heart');
    expect(reloaded.commentsFor(sample.id).single.reactionCounts, {'heart': 1});

    await reloaded.toggleReaction(
      sample,
      reloaded.commentsFor(sample.id).single,
      BingoReaction.heart,
    );
    expect(reloaded.reactionFor(sample.id, comment.id), isNull);
    expect(reloaded.commentsFor(sample.id).single.reactionCounts, isEmpty);
  });

  test('人気順は参加者・いいね・コメントを合わせて並べる', () async {
    final state = BingoState();
    await state.initialize();
    await state.publish(_board('many-joined', participants: 3));
    await state.publish(_board('liked', participants: 0));
    await state.toggleBoardLike(state.cachedBoard('liked')!);
    expect(state.cachedBoard('liked')!.popularity, 2);

    final popular = state.listedBoards(sort: BingoSort.popular);
    expect(popular.map((board) => board.id), ['many-joined', 'liked']);
  });

  testWidgets('詳細画面でいいねとコメントへのリアクションができる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = BingoState(
      initialPath: '/ja/bingo/sample-travel',
      entrySaveDelay: Duration.zero,
    );
    await tester.runAsync(state.initialize);
    await tester.pumpWidget(BingoOnlineApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('like-button')));
    await tester.pumpAndSettle();
    expect(find.text('いいね  1'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('comment-field')), '楽しい');
    await tester.tap(find.byKey(const ValueKey('post-comment')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    final comment = state.commentsFor('sample-travel').single;

    final clap = find.byKey(ValueKey('reaction-${comment.id}-clap'));
    await tester.ensureVisible(clap);
    await tester.pumpAndSettle();
    await tester.tap(clap);
    await tester.pumpAndSettle();
    expect(state.reactionFor('sample-travel', comment.id), 'clap');
    expect(find.descendant(of: clap, matching: find.text('1')), findsOneWidget);
  });
}
