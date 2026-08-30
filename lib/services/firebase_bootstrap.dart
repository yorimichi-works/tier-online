import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../repositories/firebase_tier_repository.dart';

class FirebaseBootstrapResult {
  const FirebaseBootstrapResult({this.repository, this.auth, this.error});
  final FirebaseTierRepository? repository;
  final FirebaseAuth? auth;
  final Object? error;
  bool get enabled => repository != null;
}

abstract final class FirebaseBootstrap {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const _storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );

  static bool get _environmentConfigured =>
      _apiKey.isNotEmpty &&
      _appId.isNotEmpty &&
      _messagingSenderId.isNotEmpty &&
      _projectId.isNotEmpty;

  static bool get configured => kIsWeb || _environmentConfigured;

  static FirebaseOptions get _options => _environmentConfigured
      ? const FirebaseOptions(
          apiKey: _apiKey,
          appId: _appId,
          messagingSenderId: _messagingSenderId,
          projectId: _projectId,
          authDomain: _authDomain,
          storageBucket: _storageBucket,
        )
      : DefaultFirebaseOptions.web;

  static Future<FirebaseBootstrapResult> initialize() async {
    if (!configured) return const FirebaseBootstrapResult();
    try {
      await Firebase.initializeApp(options: _options);
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }
      return FirebaseBootstrapResult(
        repository: FirebaseTierRepository(auth: auth),
        auth: auth,
      );
    } on Object catch (error) {
      return FirebaseBootstrapResult(error: error);
    }
  }
}
