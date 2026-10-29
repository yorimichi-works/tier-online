import 'package:firebase_auth/firebase_auth.dart';

import '../../services/firebase_bootstrap.dart';
import '../repositories/firebase_bingo_repository.dart';

/// Reuses tier-online's Firebase initialization (same project, App Check and
/// anonymous sign-in) and wraps the session in a bingo repository.
abstract final class BingoFirebaseBootstrap {
  static Future<({FirebaseBingoRepository? repository, FirebaseAuth? auth})>
  initialize() async {
    final result = await FirebaseBootstrap.initialize();
    final auth = result.auth;
    if (auth == null || auth.currentUser == null) {
      return (repository: null, auth: null);
    }
    return (repository: FirebaseBingoRepository(auth: auth), auth: auth);
  }
}
