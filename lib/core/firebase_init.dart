// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Firebase Initialization
// ─────────────────────────────────────────────────────────────────────────────

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Initialize Firebase with crash reporting.
/// Call this in main() before runApp().
Future<void> initializeFirebase() async {
  await Firebase.initializeApp();

  // Route Flutter framework errors to Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Route async errors
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // Disable crash reporting in debug builds
  if (kDebugMode) {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Firestore Collection Constants
// ─────────────────────────────────────────────────────────────────────────────

abstract class FirestoreCollections {
  static const users       = 'users';
  static const progress    = 'progress';
  static const sessions    = 'sessions';
  static const songs       = 'songs';
  static const leaderboard = 'leaderboard';
}

// ─────────────────────────────────────────────────────────────────────────────
// Storage Path Constants
// ─────────────────────────────────────────────────────────────────────────────

abstract class StoragePaths {
  static String midi(String songId)      => 'midi/$songId.mid';
  static String avatar(String userId)    => 'avatars/$userId/profile.jpg';
}
