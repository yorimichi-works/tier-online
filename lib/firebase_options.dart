import 'package:firebase_core/firebase_core.dart';

/// Public Firebase client configuration for the tier-online Web app.
///
/// This configuration identifies the Firebase project. Server-side secrets,
/// including the Google Custom Search API key and engine ID, do not belong
/// here and are stored in Google Secret Manager.
abstract final class DefaultFirebaseOptions {
  static const web = FirebaseOptions(
    apiKey: 'AIzaSyAFNxcPTqD8LK6IWXlygncDoaUFRAdb6sQ',
    appId: '1:553966867727:web:15a764db13734847b8da7a',
    messagingSenderId: '553966867727',
    projectId: 'tier-online',
    authDomain: 'tier-online.firebaseapp.com',
    storageBucket: 'tier-online.firebasestorage.app',
  );
}
