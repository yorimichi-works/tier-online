import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'bingo/bingo_app.dart';
import 'bingo/services/bingo_firebase_bootstrap.dart';
import 'bingo/services/bingo_state.dart';
import 'domain/internationalization.dart';
import 'services/account_auth_service.dart';

/// Entry point for Bingo Online:
/// `flutter run -d chrome -t lib/main_bingo.dart`.
///
/// It lives in the tier-online project so both services share the Firebase
/// project, internationalization domain and font assets, and can later be
/// mounted into one app shell.
Future<void> main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  final state = BingoState(
    initialPath: Uri.base.path,
    deviceLocale: WidgetsBinding.instance.platformDispatcher.locale,
  );
  runApp(BingoOnlineApp(state: state));
  unawaited(_initializeServices(state));
}

Future<void> _initializeServices(BingoState state) async {
  try {
    await state.initialize();
    await WidgetsBinding.instance.endOfFrame;
    for (final delay in const [
      Duration.zero,
      Duration(seconds: 5),
      Duration(seconds: 15),
    ]) {
      await Future<void>.delayed(delay);
      final firebase = await BingoFirebaseBootstrap.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () => (repository: null, auth: null),
      );
      if (firebase.repository != null) {
        final account = AccountAuthService(
          firebase.auth!,
          languageCode: () => state.locale.firebaseAuthCode,
        );
        await state.attachCloud(firebase.repository!, account: account);
        // Finishes a Google sign-in that used the mobile redirect flow.
        await state.consumeGoogleRedirectResult();
        return;
      }
    }
  } finally {
    state.completeCloudBootstrap();
  }
}
