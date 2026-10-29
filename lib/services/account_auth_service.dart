import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

enum AuthResultStatus {
  success,
  emailInUse,
  weakPassword,
  invalidEmail,
  wrongPassword,
  userNotFound,
  credentialInUse,
  // Googleでログイン/連携しようとしたメールアドレスが、既に別の方法
  // (主にメール/パスワード)で登録済みの場合。パスワード入力後に
  // linkPendingGoogleCredential()を呼んでアカウントを統合する。
  googleAccountConflict,
  generic,
}

enum AccountDeletionStatus { success, cancelled, wrongPassword, failed }

enum GoogleAuthRecovery { signInExistingGoogle, linkDifferentProvider, none }

/// How to recover from a Google sign-in/link failure (shared with Tier).
GoogleAuthRecovery googleAuthRecoveryForErrorCode(
  String code,
) => switch (code) {
  // Linking an anonymous user fails with this code when the selected Google
  // credential already belongs to an existing Firebase user. This is a normal
  // returning-user sign-in, not an email/password account conflict.
  'credential-already-in-use' => GoogleAuthRecovery.signInExistingGoogle,
  'email-already-in-use' || 'account-exists-with-different-credential' =>
    GoogleAuthRecovery.linkDifferentProvider,
  _ => GoogleAuthRecovery.none,
};

class AuthResult {
  const AuthResult(this.status);
  final AuthResultStatus status;
  bool get isSuccess => status == AuthResultStatus.success;

  factory AuthResult.fromException(FirebaseAuthException error) {
    final status = switch (error.code) {
      'email-already-in-use' => AuthResultStatus.emailInUse,
      'weak-password' => AuthResultStatus.weakPassword,
      'invalid-email' => AuthResultStatus.invalidEmail,
      'wrong-password' ||
      'invalid-credential' => AuthResultStatus.wrongPassword,
      'user-not-found' => AuthResultStatus.userNotFound,
      'credential-already-in-use' => AuthResultStatus.credentialInUse,
      _ => AuthResultStatus.generic,
    };
    return AuthResult(status);
  }
}

@immutable
class AuthSessionState {
  const AuthSessionState._({required this.isRegistered, this.email});

  const AuthSessionState.guest() : this._(isRegistered: false);

  const AuthSessionState.registered({String? email})
    : this._(isRegistered: true, email: email);

  factory AuthSessionState.fromFirebaseUser(User? user) {
    if (user == null || user.isAnonymous) {
      return const AuthSessionState.guest();
    }
    return AuthSessionState.registered(email: user.email);
  }

  final bool isRegistered;
  final String? email;

  bool get isGuest => !isRegistered;
}

/// Firebase Authentication flows shared by Tier Online and Bingo Online:
/// email/password and Google sign-in that keep the guest's data by linking
/// the anonymous user, account-conflict recovery, verification mail, sign-out
/// back to a guest session and account deletion.
///
/// Mirrors the flows in `AppState` (Tier), which can delegate here later.
class AccountAuthService extends ChangeNotifier {
  AccountAuthService(
    this.auth, {
    required String Function() languageCode,
    FirebaseFunctions? functions,
  }) : _languageCode = languageCode,
       _functions = functions {
    // userChanges also fires for reloads (email verification) and token
    // refreshes, so every screen sees the same session state.
    _subscription = auth.userChanges().listen((_) => notifyListeners());
  }

  final FirebaseAuth auth;
  final String Function() _languageCode;
  final FirebaseFunctions? _functions;
  late final StreamSubscription<User?> _subscription;

  User? get user => auth.currentUser;
  String? get uid => user?.uid;
  AuthSessionState get session => AuthSessionState.fromFirebaseUser(user);

  /// Password accounts must verify their address before posting (rules and
  /// Functions enforce the same condition).
  bool get needsEmailVerification {
    final current = user;
    if (current == null || current.isAnonymous) return false;
    return accountUsesPassword && !current.emailVerified;
  }

  bool get accountUsesPassword {
    final providers = user?.providerData
        .map((provider) => provider.providerId)
        .toSet();
    return providers?.contains('password') == true &&
        providers?.contains('google.com') != true;
  }

  Future<AuthResult> signUpWithEmail(String email, String password) async {
    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      final current = auth.currentUser;
      if (current != null && current.isAnonymous) {
        // Linking keeps the uid, so the guest's boards and cards stay theirs.
        await current.linkWithCredential(credential);
      } else {
        await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
      await sendVerificationEmail();
      notifyListeners();
      return const AuthResult(AuthResultStatus.success);
    } on FirebaseAuthException catch (error) {
      return AuthResult.fromException(error);
    }
  }

  Future<AuthResult> signInWithEmail(String email, String password) async {
    try {
      await auth.signInWithEmailAndPassword(email: email, password: password);
      notifyListeners();
      return const AuthResult(AuthResultStatus.success);
    } on FirebaseAuthException catch (error) {
      return AuthResult.fromException(error);
    }
  }

  Future<AuthResult> sendPasswordReset(String email) async {
    try {
      await auth.setLanguageCode(_languageCode());
      await auth.sendPasswordResetEmail(email: email);
      return const AuthResult(AuthResultStatus.success);
    } on FirebaseAuthException catch (error) {
      return AuthResult.fromException(error);
    }
  }

  /// Sends Firebase's verification mail in the current UI language.
  Future<bool> sendVerificationEmail() async {
    final current = auth.currentUser;
    if (current == null || current.isAnonymous || current.emailVerified) {
      return true;
    }
    try {
      await auth.setLanguageCode(_languageCode());
      await current.sendEmailVerification();
      return true;
    } on Object {
      return false;
    }
  }

  /// Reloads the user and returns the latest `emailVerified`. The ID token is
  /// refreshed so rules see the new claim immediately.
  Future<bool> refreshEmailVerified() async {
    final current = auth.currentUser;
    if (current == null) return false;
    await current.reload();
    final verified = auth.currentUser?.emailVerified ?? false;
    if (verified) await auth.currentUser?.getIdToken(true);
    notifyListeners();
    return verified;
  }

  AuthCredential? _pendingGoogleCredential;
  String? _pendingGoogleEmail;

  /// Set when Google sign-in hit an address already registered with a
  /// password; [linkPendingGoogleCredential] merges the two.
  String? get pendingGoogleAccountEmail => _pendingGoogleEmail;

  void clearPendingGoogleCredential() {
    _pendingGoogleCredential = null;
    _pendingGoogleEmail = null;
  }

  /// Mobile browsers use the redirect flow because popup tab handling is
  /// unreliable there (same reasoning as Tier's AppState).
  bool get _isMobileWeb =>
      kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<AuthResult> _recoverGoogleAuthError(
    FirebaseAuthException error,
    AuthCredential? credential, {
    String? email,
  }) async {
    final pending = credential ?? error.credential;
    switch (googleAuthRecoveryForErrorCode(error.code)) {
      case GoogleAuthRecovery.signInExistingGoogle:
        if (pending == null) return AuthResult.fromException(error);
        try {
          await auth.signInWithCredential(pending);
          clearPendingGoogleCredential();
          notifyListeners();
          return const AuthResult(AuthResultStatus.success);
        } on FirebaseAuthException catch (signInError) {
          return AuthResult.fromException(signInError);
        }
      case GoogleAuthRecovery.linkDifferentProvider:
        if (pending == null) return AuthResult.fromException(error);
        _pendingGoogleCredential = pending;
        _pendingGoogleEmail = error.email ?? email;
        notifyListeners();
        return const AuthResult(AuthResultStatus.googleAccountConflict);
      case GoogleAuthRecovery.none:
        return AuthResult.fromException(error);
    }
  }

  Future<AuthResult> signInWithGoogle() async {
    if (kIsWeb) return _signInWithGoogleWeb();
    GoogleSignInAccount? googleUser;
    AuthCredential? credential;
    try {
      googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return const AuthResult(AuthResultStatus.generic);
      final googleAuth = await googleUser.authentication;
      credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final current = auth.currentUser;
      if (current != null && current.isAnonymous) {
        await current.linkWithCredential(credential);
      } else {
        await auth.signInWithCredential(credential);
      }
      clearPendingGoogleCredential();
      notifyListeners();
      return const AuthResult(AuthResultStatus.success);
    } on FirebaseAuthException catch (error) {
      return _recoverGoogleAuthError(
        error,
        credential,
        email: googleUser?.email,
      );
    } on Object {
      return const AuthResult(AuthResultStatus.generic);
    }
  }

  Future<AuthResult> _signInWithGoogleWeb() async {
    final provider = GoogleAuthProvider();
    final current = auth.currentUser;
    try {
      if (_isMobileWeb) {
        // The page navigates away; consumeGoogleRedirectResult() handles the
        // outcome after the app reloads.
        if (current != null && current.isAnonymous) {
          await current.linkWithRedirect(provider);
        } else {
          await auth.signInWithRedirect(provider);
        }
        return const AuthResult(AuthResultStatus.success);
      }
      if (current != null && current.isAnonymous) {
        await current.linkWithPopup(provider);
      } else {
        await auth.signInWithPopup(provider);
      }
      clearPendingGoogleCredential();
      notifyListeners();
      return const AuthResult(AuthResultStatus.success);
    } on FirebaseAuthException catch (error) {
      return _recoverGoogleAuthError(error, null);
    } on Object {
      return const AuthResult(AuthResultStatus.generic);
    }
  }

  /// Call once after startup on the web to finish a redirect sign-in.
  Future<AuthResult?> consumeGoogleRedirectResult() async {
    if (!kIsWeb) return null;
    try {
      final credential = await auth.getRedirectResult();
      if (credential.user == null) return null;
      clearPendingGoogleCredential();
      notifyListeners();
      return const AuthResult(AuthResultStatus.success);
    } on FirebaseAuthException catch (error) {
      return _recoverGoogleAuthError(error, null);
    } on Object {
      return null;
    }
  }

  Future<AuthResult> linkPendingGoogleCredential(String password) async {
    final pending = _pendingGoogleCredential;
    final email = _pendingGoogleEmail;
    if (pending == null || email == null) {
      return const AuthResult(AuthResultStatus.generic);
    }
    try {
      await auth.signInWithEmailAndPassword(email: email, password: password);
      try {
        await auth.currentUser?.linkWithCredential(pending);
      } on FirebaseAuthException catch (error) {
        if (error.code != 'provider-already-linked') rethrow;
      }
      clearPendingGoogleCredential();
      notifyListeners();
      return const AuthResult(AuthResultStatus.success);
    } on FirebaseAuthException catch (error) {
      return AuthResult.fromException(error);
    }
  }

  /// Signs out and immediately continues as a new guest, like Tier.
  Future<void> signOut() async {
    await auth.signOut();
    try {
      await auth.signInAnonymously();
    } on Object {
      // The app keeps working on local storage until Firebase is reachable.
    }
    notifyListeners();
  }

  /// Re-authenticates, then deletes every Tier and Bingo record of the
  /// account via the `deleteUserAccount` callable and continues as a guest.
  Future<AccountDeletionStatus> deleteAccount({String? password}) async {
    final current = auth.currentUser;
    if (current == null || current.isAnonymous) {
      return AccountDeletionStatus.failed;
    }
    try {
      if (accountUsesPassword) {
        final email = current.email;
        if (email == null || password == null || password.isEmpty) {
          return AccountDeletionStatus.wrongPassword;
        }
        await current.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: email, password: password),
        );
      } else if (kIsWeb) {
        await current.reauthenticateWithPopup(GoogleAuthProvider());
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) return AccountDeletionStatus.cancelled;
        final googleAuth = await googleUser.authentication;
        await current.reauthenticateWithCredential(
          GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          ),
        );
      }
      await auth.currentUser?.getIdToken(true);
      await (_functions ?? FirebaseFunctions.instance)
          .httpsCallable('deleteUserAccount')
          .call<Map<String, dynamic>>();
      await auth.signOut();
      await auth.signInAnonymously();
      notifyListeners();
      return AccountDeletionStatus.success;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'popup-closed-by-user' ||
          error.code == 'cancelled-popup-request') {
        return AccountDeletionStatus.cancelled;
      }
      if (error.code == 'wrong-password' ||
          error.code == 'invalid-credential') {
        return AccountDeletionStatus.wrongPassword;
      }
      return AccountDeletionStatus.failed;
    } on Object {
      return AccountDeletionStatus.failed;
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
