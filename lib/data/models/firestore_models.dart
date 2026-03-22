// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Firestore Data Models
// Handles serialization / deserialization between domain entities and Firestore.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/entities.dart';

// ── UserModel ────────────────────────────────────────────────────────────────

class UserModel {
  final String uid;
  final String displayName;
  final String? email;
  final String? photoUrl;
  final DateTime createdAt;
  final DateTime lastSeen;
  final String? activeDeviceId;

  const UserModel({
    required this.uid,
    required this.displayName,
    this.email,
    this.photoUrl,
    required this.createdAt,
    required this.lastSeen,
    this.activeDeviceId,
  });

  factory UserModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid:            doc.id,
      displayName:    d['displayName'] as String? ?? 'Drummer',
      email:          d['email']    as String?,
      photoUrl:       d['photoUrl'] as String?,
      createdAt:      (d['createdAt']  as Timestamp?)?.toDate() ?? DateTime.now(),
      lastSeen:       (d['lastSeen']   as Timestamp?)?.toDate() ?? DateTime.now(),
      activeDeviceId: d['activeDeviceId'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'displayName':    displayName,
    'email':          email,
    'photoUrl':       photoUrl,
    'createdAt':      Timestamp.fromDate(createdAt),
    'lastSeen':       Timestamp.fromDate(lastSeen),
    'activeDeviceId': activeDeviceId,
  };
}

// ── ProgressModel ─────────────────────────────────────────────────────────────

class ProgressModel {
  final String userId;
  final int totalXp;
  final int level;
  final int currentStreak;
  final int maxStreak;
  final Map<String, int> songBestScores;
  final List<String> achievements;
  final DateTime? lastPracticeDate;

  const ProgressModel({
    required this.userId,
    required this.totalXp,
    required this.level,
    required this.currentStreak,
    required this.maxStreak,
    required this.songBestScores,
    required this.achievements,
    this.lastPracticeDate,
  });

  factory ProgressModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ProgressModel(
      userId:           doc.id,
      totalXp:          (d['totalXp']       as int?) ?? 0,
      level:            (d['level']          as int?) ?? 1,
      currentStreak:    (d['currentStreak']  as int?) ?? 0,
      maxStreak:        (d['maxStreak']      as int?) ?? 0,
      songBestScores:   Map<String, int>.from(d['songBestScores'] as Map? ?? {}),
      achievements:     List<String>.from(d['achievements']       as List? ?? []),
      lastPracticeDate: (d['lastPracticeDate'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'totalXp':          totalXp,
    'level':            level,
    'currentStreak':    currentStreak,
    'maxStreak':        maxStreak,
    'songBestScores':   songBestScores,
    'achievements':     achievements,
    'lastPracticeDate': lastPracticeDate != null
        ? Timestamp.fromDate(lastPracticeDate!)
        : null,
  };

  UserProgress toDomain(String displayName) => UserProgress(
    userId:           userId,
    displayName:      displayName,
    totalXp:          totalXp,
    level:            level,
    currentStreak:    currentStreak,
    maxStreak:        maxStreak,
    songBestScores:   songBestScores,
    achievements:     achievements,
    lastPracticeDate: lastPracticeDate,
  );
}

// ── SessionModel ──────────────────────────────────────────────────────────────

class SessionModel {
  final String id;
  final String userId;
  final String songId;
  final String songTitle;
  final DateTime startedAt;
  final Duration totalDuration;
  final int totalScore;
  final double accuracyPercent;
  final int perfectCount;
  final int goodCount;
  final int okayCount;
  final int missCount;
  final int maxCombo;
  final int xpEarned;
  final String letterGrade;

  const SessionModel({
    required this.id,
    required this.userId,
    required this.songId,
    required this.songTitle,
    required this.startedAt,
    required this.totalDuration,
    required this.totalScore,
    required this.accuracyPercent,
    required this.perfectCount,
    required this.goodCount,
    required this.okayCount,
    required this.missCount,
    required this.maxCombo,
    required this.xpEarned,
    required this.letterGrade,
  });

  factory SessionModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SessionModel(
      id:               doc.id,
      userId:           d['userId']           as String,
      songId:           d['songId']           as String,
      songTitle:        d['songTitle']         as String? ?? '',
      startedAt:        (d['startedAt']        as Timestamp).toDate(),
      totalDuration:    Duration(seconds:      d['durationSeconds'] as int? ?? 0),
      totalScore:       d['totalScore']        as int? ?? 0,
      accuracyPercent:  (d['accuracyPercent']  as num?)?.toDouble() ?? 0,
      perfectCount:     d['perfectCount']      as int? ?? 0,
      goodCount:        d['goodCount']         as int? ?? 0,
      okayCount:        d['okayCount']         as int? ?? 0,
      missCount:        d['missCount']         as int? ?? 0,
      maxCombo:         d['maxCombo']          as int? ?? 0,
      xpEarned:         d['xpEarned']          as int? ?? 0,
      letterGrade:      d['letterGrade']        as String? ?? 'D',
    );
  }

  factory SessionModel.fromDomain(PerformanceSession session, String userId) {
    return SessionModel(
      id:               session.id,
      userId:           userId,
      songId:           session.song.id,
      songTitle:        session.song.title,
      startedAt:        session.startedAt,
      totalDuration:    session.totalDuration,
      totalScore:       session.totalScore,
      accuracyPercent:  session.accuracyPercent,
      perfectCount:     session.perfectCount,
      goodCount:        session.goodCount,
      okayCount:        session.okayCount,
      missCount:        session.missCount,
      maxCombo:         session.maxCombo,
      xpEarned:         session.xpEarned,
      letterGrade:      session.letterGrade,
    );
  }

  Map<String, dynamic> toMap() => {
    'userId':          userId,
    'songId':          songId,
    'songTitle':       songTitle,
    'startedAt':       Timestamp.fromDate(startedAt),
    'durationSeconds': totalDuration.inSeconds,
    'totalScore':      totalScore,
    'accuracyPercent': accuracyPercent,
    'perfectCount':    perfectCount,
    'goodCount':       goodCount,
    'okayCount':       okayCount,
    'missCount':       missCount,
    'maxCombo':        maxCombo,
    'xpEarned':        xpEarned,
    'letterGrade':     letterGrade,
  };
}

// ── SongModel ─────────────────────────────────────────────────────────────────

class SongModel {
  final String id;
  final String title;
  final String artist;
  final String difficulty;
  final String genre;
  final int bpm;
  final int durationSeconds;
  final String midiStoragePath;
  final bool isPremium;
  final int xpReward;
  final int requiredLevel;

  const SongModel({
    required this.id,
    required this.title,
    required this.artist,
    required this.difficulty,
    required this.genre,
    required this.bpm,
    required this.durationSeconds,
    required this.midiStoragePath,
    required this.isPremium,
    required this.xpReward,
    required this.requiredLevel,
  });

  factory SongModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SongModel(
      id:               doc.id,
      title:            d['title']            as String,
      artist:           d['artist']           as String? ?? 'NavaDrummer',
      difficulty:       d['difficulty']        as String? ?? 'beginner',
      genre:            d['genre']             as String? ?? 'rock',
      bpm:              d['bpm']               as int? ?? 100,
      durationSeconds:  d['durationSeconds']   as int? ?? 60,
      midiStoragePath:  d['midiStoragePath']   as String? ?? '',
      isPremium:        d['isPremium']          as bool? ?? false,
      xpReward:         d['xpReward']           as int? ?? 100,
      requiredLevel:    d['requiredLevel']      as int? ?? 1,
    );
  }

  Map<String, dynamic> toMap() => {
    'title':           title,
    'artist':          artist,
    'difficulty':      difficulty,
    'genre':           genre,
    'bpm':             bpm,
    'durationSeconds': durationSeconds,
    'midiStoragePath': midiStoragePath,
    'isPremium':       isPremium,
    'xpReward':        xpReward,
    'requiredLevel':   requiredLevel,
  };
}
