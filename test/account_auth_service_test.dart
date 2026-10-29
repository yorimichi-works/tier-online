import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tier_table_online/services/account_auth_service.dart';

UserInfo _provider(String providerId) =>
    // ignore: invalid_use_of_protected_member
    UserInfo.fromJson({
      'uid': 'provider-uid',
      'providerId': providerId,
      'isAnonymous': false,
      'isEmailVerified': false,
    });

void main() {
  test('Googleログインの失敗コードから回復方法を選ぶ', () {
    expect(
      googleAuthRecoveryForErrorCode('credential-already-in-use'),
      GoogleAuthRecovery.signInExistingGoogle,
    );
    expect(
      googleAuthRecoveryForErrorCode(
        'account-exists-with-different-credential',
      ),
      GoogleAuthRecovery.linkDifferentProvider,
    );
    expect(
      googleAuthRecoveryForErrorCode('network-request-failed'),
      GoogleAuthRecovery.none,
    );
  });

  test('ゲストはゲスト、メール登録済みは登録済みとして扱う', () async {
    final guest = MockFirebaseAuth();
    await guest.signInAnonymously();
    final service = AccountAuthService(guest, languageCode: () => 'ja');
    addTearDown(service.dispose);
    expect(service.session.isGuest, isTrue);
    expect(service.needsEmailVerification, isFalse);
  });

  test('ログアウトすると新しいゲストとして続ける', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'member', email: 'fan@example.com'),
    );
    final service = AccountAuthService(auth, languageCode: () => 'ja');
    addTearDown(service.dispose);
    expect(service.session.email, 'fan@example.com');

    await service.signOut();

    expect(service.session.isGuest, isTrue);
    expect(service.uid, isNot('member'));
  });

  test('パスワード登録で未確認のときだけメール確認を求める', () async {
    final unverified = AccountAuthService(
      MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          email: 'a@example.com',
          isEmailVerified: false,
          providerData: [_provider('password')],
        ),
      ),
      languageCode: () => 'ja',
    );
    final google = AccountAuthService(
      MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          email: 'b@example.com',
          isEmailVerified: false,
          providerData: [_provider('google.com')],
        ),
      ),
      languageCode: () => 'ja',
    );
    addTearDown(unverified.dispose);
    addTearDown(google.dispose);

    expect(unverified.needsEmailVerification, isTrue);
    expect(google.needsEmailVerification, isFalse);
  });
}
