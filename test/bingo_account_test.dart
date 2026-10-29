import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tier_table_online/bingo/bingo_app.dart';
import 'package:tier_table_online/bingo/models/bingo_models.dart';
import 'package:tier_table_online/bingo/repositories/bingo_repository.dart';
import 'package:tier_table_online/bingo/repositories/local_bingo_repository.dart';
import 'package:tier_table_online/bingo/services/bingo_state.dart';
import 'package:tier_table_online/domain/internationalization.dart';
import 'package:tier_table_online/services/account_auth_service.dart';

UserInfo _password() =>
    // ignore: invalid_use_of_protected_member
    UserInfo.fromJson({
      'uid': 'p',
      'providerId': 'password',
      'isAnonymous': false,
      'isEmailVerified': false,
    });

/// Uses the device-only repository as a stand-in "cloud" whose user id
/// follows the mock Firebase session.
class _SessionRepository extends LocalBingoRepository {
  _SessionRepository(this.auth) : super(userId: 'unused');
  final FirebaseAuth auth;

  @override
  String get currentUserId => auth.currentUser?.uid ?? '';
}

BingoBoard _cloudBoard() => BingoBoard(
  id: 'cloud-board',
  title: 'Cloud',
  size: 3,
  cells: [for (var i = 0; i < 8; i++) BingoCell(text: '$i')],
  creatorId: 'someone',
  creatorName: 'Someone',
  contentLanguage: AppLocale.ja,
  targetRegion: 'JP',
);

Future<(BingoState, MockFirebaseAuth)> _attach({MockUser? user}) async {
  final auth = user == null
      ? MockFirebaseAuth()
      : MockFirebaseAuth(signedIn: true, mockUser: user);
  if (user == null) await auth.signInAnonymously();
  final state = BingoState(entrySaveDelay: Duration.zero);
  await state.initialize();
  final repository = _SessionRepository(auth);
  await repository.publishBoard(_cloudBoard());
  await state.attachCloud(
    repository,
    account: AccountAuthService(auth, languageCode: () => 'ja'),
  );
  return (state, auth);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('オンラインのゲストは画像をアップロードできない（Tierと同じ方針）', () async {
    final (state, _) = await _attach();
    expect(state.isRegistered, isFalse);
    expect(state.canUploadImages, isFalse);

    final offline = BingoState();
    await offline.initialize();
    expect(offline.canUploadImages, isTrue, reason: '端末内保存なら画像は端末に残る');
  });

  test('メール未確認のパスワード登録者は投稿前に止める', () async {
    final (state, _) = await _attach(
      user: MockUser(
        uid: 'member',
        email: 'fan@example.com',
        isEmailVerified: false,
        providerData: [_password()],
      ),
    );
    expect(state.isRegistered, isTrue);
    expect(state.canUploadImages, isTrue);
    expect(state.needsEmailVerification, isTrue);
    await expectLater(
      state.postComment(_cloudBoard(), body: 'hi', attachResult: false),
      throwsA(
        isA<BingoException>().having(
          (error) => error.failure,
          'failure',
          BingoFailure.emailUnverified,
        ),
      ),
    );
  });

  test('アカウントが切り替わると前のユーザーのカードを外し、サンプルは残す', () async {
    final (state, auth) = await _attach();
    final sample = state.samples.first;
    await state.join(_cloudBoard());
    await state.join(sample);
    expect(state.entryFor('cloud-board'), isNotNull);

    await state.signOut();
    await pumpEventQueue();

    expect(auth.currentUser!.isAnonymous, isTrue);
    expect(state.entryFor('cloud-board'), isNull);
    expect(state.entryFor(sample.id), isNotNull);
  });

  testWidgets('設定画面にゲスト表示とログインボタンが出る', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (state, _) = await tester.runAsync(() => _attach()).then((v) => v!);
    await tester.pumpWidget(BingoOnlineApp(state: state));
    await tester.pumpAndSettle();
    // Bottom navigation: Settings is the last tab.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('ゲストとして利用中'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-sign-in')), findsOneWidget);
    expect(find.byKey(const ValueKey('top-sign-in')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('top-sign-in')));
    await tester.pumpAndSettle();
    expect(find.text('Googleでログイン'), findsOneWidget);
  });
}
