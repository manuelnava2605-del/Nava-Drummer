// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Domain Repository Interfaces
// Pure abstract contracts — no Firebase imports here.
// ─────────────────────────────────────────────────────────────────────────────

import '../entities/entities.dart';

// ── Auth ──────────────────────────────────────────────────────────────────────

abstract class AuthRepository {
  /// Stream of the currently authenticated user ID, or null if signed out.
  Stream<String?> get authStateChanges;

  String? get currentUserId;

  Future<String> signInAnonymously();
  Future<String> signInWithGoogle();
  Future<void>   signOut();
}

// ── User / Progress ───────────────────────────────────────────────────────────

abstract class UserRepository {
  /// Creates or updates the user profile document.
  Future<void> upsertUser({
    required String userId,
    required String displayName,
    String? email,
    String? photoUrl,
  });

  Future<UserProgress?> getProgress(String userId);

  Future<void> updateProgress(UserProgress progress);

  /// Adds XP and recalculates level. Returns updated progress.
  Future<UserProgress> addXp(String userId, int xpAmount);

  /// Records a new achievement if not already earned.
  Future<void> unlockAchievement(String userId, String achievementId);

  /// Updates best score for a song if new score is higher.
  Future<void> updateBestScore(String userId, String songId, int score);

  /// Increments streak if practiced today, resets if gap > 1 day.
  Future<void> updateStreak(String userId);
}

// ── Sessions ──────────────────────────────────────────────────────────────────

abstract class SessionRepository {
  Future<void> saveSession(PerformanceSession session, String userId);

  /// Returns the most recent [limit] sessions for a user.
  Future<List<PerformanceSession>> getRecentSessions(
    String userId, {
    int limit = 20,
    String? songId,
  });

  /// Returns per-day accuracy averages for the last [days] days.
  Future<Map<DateTime, double>> getDailyAccuracy(String userId, {int days = 7});
}

// ── Songs ─────────────────────────────────────────────────────────────────────

abstract class SongRepository {
  /// Returns all available songs from Firestore (with local fallback).
  Future<List<Song>> getAllSongs();

  /// Returns the download URL for a song's MIDI file.
  Future<String> getMidiDownloadUrl(String songId);

  /// Downloads MIDI bytes and caches locally.
  Future<List<int>> getMidiBytes(String songId);
}
