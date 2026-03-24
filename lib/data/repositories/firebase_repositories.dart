// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Firebase Repository Implementations
// Concrete implementations using Firebase Auth, Firestore, and Storage.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../models/firestore_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AuthRepositoryImpl
// ─────────────────────────────────────────────────────────────────────────────

class AuthRepositoryImpl implements AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Stream<String?> get authStateChanges =>
      _auth.authStateChanges().map((u) => u?.uid);

  @override
  String? get currentUserId => _auth.currentUser?.uid;

  @override
  Future<String> signInAnonymously() async {
    final cred = await _auth.signInAnonymously();
    return cred.user!.uid;
  }

  @override
  Future<String> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) throw Exception('Google sign-in cancelled');
    final googleAuth = await googleUser.authentication;
    final credential  = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken:     googleAuth.idToken,
    );
    final cred = await _auth.signInWithCredential(credential);
    return cred.user!.uid;
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

// ─────────────────────────────────────────────────────────────────────────────
// UserRepositoryImpl
// ─────────────────────────────────────────────────────────────────────────────

class UserRepositoryImpl implements UserRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get _users    => _db.collection('users');
  CollectionReference get _progress => _db.collection('progress');

  @override
  Future<void> upsertUser({
    required String userId,
    required String displayName,
    String? email,
    String? photoUrl,
  }) async {
    await _users.doc(userId).set({
      'displayName': displayName,
      'email':       email,
      'photoUrl':    photoUrl,
      'lastSeen':    FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<UserProgress?> getProgress(String userId) async {
    final userDoc = await _users.doc(userId).get();
    final progDoc = await _progress.doc(userId).get();
    if (!progDoc.exists) return null;

    final displayName = (userDoc.data() as Map<String, dynamic>?)?['displayName']
        as String? ?? 'Drummer';
    return ProgressModel.fromDoc(progDoc).toDomain(displayName);
  }

  @override
  Future<void> updateProgress(UserProgress progress) async {
    await _progress.doc(progress.userId).set(
      ProgressModel(
        userId:           progress.userId,
        totalXp:          progress.totalXp,
        level:            progress.level,
        currentStreak:    progress.currentStreak,
        maxStreak:        progress.maxStreak,
        songBestScores:   progress.songBestScores,
        achievements:     progress.achievements,
        lastPracticeDate: progress.lastPracticeDate,
      ).toMap(),
      SetOptions(merge: true),
    );
  }

  @override
  Future<UserProgress> addXp(String userId, int xpAmount) async {
    final progRef  = _progress.doc(userId);
    final userSnap = await _users.doc(userId).get();
    final displayName = (userSnap.data() as Map<String, dynamic>?)?['displayName']
        as String? ?? 'Drummer';

    return _db.runTransaction((tx) async {
      final snap = await tx.get(progRef);
      final current = snap.exists
          ? ProgressModel.fromDoc(snap)
          : ProgressModel(
              userId: userId, totalXp: 0, level: 1,
              currentStreak: 0, maxStreak: 0,
              songBestScores: {}, achievements: [],
            );

      final newXp    = current.totalXp + xpAmount;
      final newLevel = _calculateLevel(newXp);

      final updated = ProgressModel(
        userId:           userId,
        totalXp:          newXp,
        level:            newLevel,
        currentStreak:    current.currentStreak,
        maxStreak:        current.maxStreak,
        songBestScores:   current.songBestScores,
        achievements:     current.achievements,
        lastPracticeDate: current.lastPracticeDate,
      );
      tx.set(progRef, updated.toMap(), SetOptions(merge: true));
      return updated.toDomain(displayName);
    });
  }

  @override
  Future<void> unlockAchievement(String userId, String achievementId) async {
    await _progress.doc(userId).set({
      'achievements': FieldValue.arrayUnion([achievementId]),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> updateBestScore(String userId, String songId, int score) async {
    final progRef = _progress.doc(userId);
    return _db.runTransaction((tx) async {
      final snap    = await tx.get(progRef);
      final current = snap.exists ? ProgressModel.fromDoc(snap) : null;
      final existing = current?.songBestScores[songId] ?? 0;
      if (score > existing) {
        tx.set(progRef, {
          'songBestScores': {songId: score},
        }, SetOptions(merge: true));
      }
    });
  }

  @override
  Future<void> updateStreak(String userId) async {
    final progRef = _progress.doc(userId);
    return _db.runTransaction((tx) async {
      final snap    = await tx.get(progRef);
      final current = snap.exists ? ProgressModel.fromDoc(snap) : null;
      final today   = DateTime.now();
      final last    = current?.lastPracticeDate;

      int newStreak = current?.currentStreak ?? 0;
      if (last == null) {
        newStreak = 1;
      } else {
        final diff = today.difference(last).inDays;
        if (diff == 0) return; // already practiced today
        if (diff == 1) newStreak++;
        else           newStreak = 1;
      }

      final newMax = (newStreak > (current?.maxStreak ?? 0))
          ? newStreak
          : (current?.maxStreak ?? 0);

      tx.set(progRef, {
        'currentStreak':    newStreak,
        'maxStreak':        newMax,
        'lastPracticeDate': Timestamp.fromDate(today),
      }, SetOptions(merge: true));
    });
  }

  int _calculateLevel(int totalXp) {
    // Level thresholds: 500, 1000, 2000, 3500, 5500, 8000, 11000...
    int level = 1;
    int threshold = 500;
    int xpLeft = totalXp;
    while (xpLeft >= threshold) {
      xpLeft    -= threshold;
      level++;
      threshold  = (threshold * 1.5).toInt();
    }
    return level;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SessionRepositoryImpl
// ─────────────────────────────────────────────────────────────────────────────

class SessionRepositoryImpl implements SessionRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get _sessions => _db.collection('sessions');

  @override
  Future<void> saveSession(PerformanceSession session, String userId) async {
    final model = SessionModel.fromDomain(session, userId);
    await _sessions.doc(session.id).set(model.toMap());
  }

  @override
  Future<List<PerformanceSession>> getRecentSessions(
    String userId, {
    int limit = 20,
    String? songId,
  }) async {
    Query q = _sessions
        .where('userId', isEqualTo: userId)
        .orderBy('startedAt', descending: true)
        .limit(limit);

    if (songId != null) {
      q = q.where('songId', isEqualTo: songId);
    }

    final snap = await q.get();
    return snap.docs.map(_sessionFromDoc).toList();
  }

  @override
  Future<Map<DateTime, double>> getDailyAccuracy(
    String userId, {
    int days = 7,
  }) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final snap = await _sessions
        .where('userId', isEqualTo: userId)
        .where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('startedAt')
        .get();

    // Group by day and average accuracy
    final Map<DateTime, List<double>> grouped = {};
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final date = (d['startedAt'] as Timestamp).toDate();
      final day  = DateTime(date.year, date.month, date.day);
      final acc  = (d['accuracyPercent'] as num?)?.toDouble() ?? 0;
      grouped.putIfAbsent(day, () => []).add(acc);
    }
    return grouped.map((day, vals) {
      final avg = vals.reduce((a, b) => a + b) / vals.length;
      return MapEntry(day, avg);
    });
  }

  PerformanceSession _sessionFromDoc(DocumentSnapshot doc) {
    final model = SessionModel.fromDoc(doc);
    // Minimal re-hydration — hit results not needed for list views
    return PerformanceSession(
      id:              model.id,
      song: Song(
        id:           model.songId,
        title:        model.songTitle,
        artist:       '',
        difficulty:   Difficulty.beginner,
        genre:        Genre.rock,
        bpm:          120,
        duration:     model.totalDuration,
        midiAssetPath: '',
        isUnlocked:   true,
        xpReward:     model.xpEarned,
      ),
      startedAt:       model.startedAt,
      hitResults:      [],
      totalScore:      model.totalScore,
      accuracyPercent: model.accuracyPercent,
      perfectCount:    model.perfectCount,
      goodCount:       model.goodCount,
      okayCount:       model.okayCount,
      missCount:       model.missCount,
      maxCombo:        model.maxCombo,
      xpEarned:        model.xpEarned,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SongRepositoryImpl
// ─────────────────────────────────────────────────────────────────────────────

class SongRepositoryImpl implements SongRepository {
  final FirebaseFirestore _db      = FirebaseFirestore.instance;
  final FirebaseStorage   _storage = FirebaseStorage.instance;

  CollectionReference get _songs => _db.collection('Songs');

  @override
  Future<List<Song>> getAllSongs() async {
    try {
      final snap = await _songs.orderBy('requiredLevel').get();
      return snap.docs.map(_songFromModel).toList();
    } catch (_) {
      // Return local sample catalog if Firestore unavailable
      return _localSampleSongs();
    }
  }

  @override
  Future<String> getMidiDownloadUrl(String songId) async {
    final ref = _storage.ref('midi/$songId.mid');
    return ref.getDownloadURL();
  }

  @override
  Future<List<int>> getMidiBytes(String songId) async {
    // Try local cache first
    final cacheFile = await _cacheFile(songId);
    if (await cacheFile.exists()) {
      return cacheFile.readAsBytesSync().toList();
    }

    // Download from Firebase Storage
    final ref  = _storage.ref('midi/$songId.mid');
    final data = await ref.getData();
    if (data == null) throw Exception('MIDI file not found: $songId');

    // Cache locally
    await cacheFile.writeAsBytes(data);
    return data.toList();
  }

  Future<File> _cacheFile(String songId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/midi_cache/$songId.mid');
  }

  /// Converts a Firestore [DocumentSnapshot] to a [Song] domain entity.
  /// Uses [SongModel.toDomain()] which correctly handles [storageFolderPath]
  /// → [Song.packageAssetDir] so the practice screen can download the package.
  Song _songFromModel(DocumentSnapshot doc) => SongModel.fromDoc(doc).toDomain();

  /// Empty fallback — shown when Firestore is unavailable (no network).
  /// Songs come exclusively from Firebase Storage/Firestore; no local MIDI
  /// assets are bundled in the app binary anymore.
  List<Song> _localSampleSongs() => const [];
}
