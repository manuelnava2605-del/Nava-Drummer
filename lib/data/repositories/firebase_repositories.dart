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
    final progRef = _progress.doc(userId);

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
      return updated.toDomain('');
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

  CollectionReference get _songs => _db.collection('songs');

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

  Song _songFromModel(DocumentSnapshot doc) {
    final m = SongModel.fromDoc(doc);
    return Song(
      id:           m.id,
      title:        m.title,
      artist:       m.artist,
      difficulty:   _parseDifficulty(m.difficulty),
      genre:        _parseGenre(m.genre),
      bpm:          m.bpm,
      duration:     Duration(seconds: m.durationSeconds),
      midiAssetPath: 'assets/midi/${m.id}.mid',
      isUnlocked:   !m.isPremium,
      xpReward:     m.xpReward,
    );
  }

  Difficulty _parseDifficulty(String s) {
    switch (s.toLowerCase()) {
      case 'intermediate': return Difficulty.intermediate;
      case 'advanced':     return Difficulty.advanced;
      case 'expert':       return Difficulty.expert;
      default:             return Difficulty.beginner;
    }
  }

  Genre _parseGenre(String s) {
    switch (s.toLowerCase()) {
      case 'funk':        return Genre.funk;
      case 'jazz':        return Genre.jazz;
      case 'metal':       return Genre.metal;
      case 'electronic':  return Genre.electronic;
      case 'latin':       return Genre.latin;
      default:            return Genre.rock;
    }
  }

  // Local sample songs (used when Firestore is unavailable / first launch)
  List<Song> _localSampleSongs() => [
    const Song(
      id: 'quarter_notes', title: 'Quarter Notes', artist: 'NavaDrummer Tutorials',
      difficulty: Difficulty.beginner, genre: Genre.rock,
      bpm: 80, duration: Duration(seconds: 60),
      midiAssetPath: 'assets/midi/quarter_notes.mid',
      isUnlocked: true, xpReward: 50,
    ),
    const Song(
      id: 'basic_rock_i', title: 'Basic Rock Beat I', artist: 'NavaDrummer Tutorials',
      difficulty: Difficulty.beginner, genre: Genre.rock,
      bpm: 90, duration: Duration(seconds: 90),
      midiAssetPath: 'assets/midi/basic_rock_i.mid',
      isUnlocked: true, xpReward: 100,
    ),
    const Song(
      id: 'funk_groove', title: 'Funk Groove', artist: 'NavaDrummer Tutorials',
      difficulty: Difficulty.intermediate, genre: Genre.funk,
      bpm: 100, duration: Duration(seconds: 120),
      midiAssetPath: 'assets/midi/funk_groove.mid',
      isUnlocked: true, xpReward: 200,
    ),
    const Song(
      id: 'jazz_ride', title: 'Jazz Ride Pattern', artist: 'NavaDrummer Tutorials',
      difficulty: Difficulty.intermediate, genre: Genre.jazz,
      bpm: 120, duration: Duration(seconds: 120),
      midiAssetPath: 'assets/midi/jazz_ride.mid',
      isUnlocked: false, xpReward: 250,
    ),
    const Song(
      id: 'metal_double', title: 'Metal Double Bass', artist: 'NavaDrummer Tutorials',
      difficulty: Difficulty.advanced, genre: Genre.metal,
      bpm: 150, duration: Duration(seconds: 180),
      midiAssetPath: 'assets/midi/metal_double.mid',
      isUnlocked: false, xpReward: 400,
    ),
    const Song(
      id: 'polyrhythm_7_4', title: 'Polyrhythm 7/4', artist: 'NavaDrummer Tutorials',
      difficulty: Difficulty.expert, genre: Genre.rock,
      bpm: 100, duration: Duration(seconds: 180),
      midiAssetPath: 'assets/midi/polyrhythm_7_4.mid',
      isUnlocked: false, xpReward: 600,
    ),
  ];
}
