// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Domain Use Cases
// Each use case encapsulates a single business operation.
// ─────────────────────────────────────────────────────────────────────────────

import '../entities/entities.dart';
import '../repositories/repositories.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Auth Use Cases
// ─────────────────────────────────────────────────────────────────────────────

class SignInAnonymouslyUseCase {
  final AuthRepository _auth;
  final UserRepository _user;

  SignInAnonymouslyUseCase(this._auth, this._user);

  Future<String> call() async {
    final uid = await _auth.signInAnonymously();
    await _user.upsertUser(userId: uid, displayName: 'Drummer');
    return uid;
  }
}

class SignInWithGoogleUseCase {
  final AuthRepository _auth;
  final UserRepository _user;

  SignInWithGoogleUseCase(this._auth, this._user);

  Future<String> call() async {
    final uid = await _auth.signInWithGoogle();
    // Profile info would normally be passed from Google
    await _user.upsertUser(userId: uid, displayName: 'Drummer');
    return uid;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Progress Use Cases
// ─────────────────────────────────────────────────────────────────────────────

class GetUserProgressUseCase {
  final UserRepository _repo;
  GetUserProgressUseCase(this._repo);

  Future<UserProgress?> call(String userId) => _repo.getProgress(userId);
}

class SaveSessionAndUpdateProgressUseCase {
  final SessionRepository _sessions;
  final UserRepository    _users;

  SaveSessionAndUpdateProgressUseCase(this._sessions, this._users);

  /// Saves the session, awards XP, updates best score, and refreshes streak.
  Future<UserProgress> call(PerformanceSession session, String userId) async {
    // 1. Persist the session
    await _sessions.saveSession(session, userId);

    // 2. Update best score for this song
    await _users.updateBestScore(userId, session.song.id, session.totalScore);

    // 3. Award XP
    final updatedProgress = await _users.addXp(userId, session.xpEarned);

    // 4. Update streak
    await _users.updateStreak(userId);

    // 5. Check for achievements
    await _checkAchievements(session, updatedProgress, userId);

    return updatedProgress;
  }

  Future<void> _checkAchievements(
    PerformanceSession session,
    UserProgress progress,
    String userId,
  ) async {
    final achievements = <String>[];

    // First hit ever
    if (!progress.achievements.contains('first_session')) {
      achievements.add('first_session');
    }

    // Perfect score
    if (session.accuracyPercent >= 100 &&
        !progress.achievements.contains('perfectionist')) {
      achievements.add('perfectionist');
    }

    // S grade
    if (session.letterGrade == 'S' &&
        !progress.achievements.contains('s_rank')) {
      achievements.add('s_rank');
    }

    // 50+ combo
    if (session.maxCombo >= 50 &&
        !progress.achievements.contains('combo_king')) {
      achievements.add('combo_king');
    }

    // 7-day streak
    if (progress.currentStreak >= 7 &&
        !progress.achievements.contains('week_warrior')) {
      achievements.add('week_warrior');
    }

    // Level 5
    if (progress.level >= 5 &&
        !progress.achievements.contains('level_5')) {
      achievements.add('level_5');
    }

    for (final a in achievements) {
      await _users.unlockAchievement(userId, a);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Song Use Cases
// ─────────────────────────────────────────────────────────────────────────────

class GetSongsUseCase {
  final SongRepository _repo;
  GetSongsUseCase(this._repo);

  Future<List<Song>> call() => _repo.getAllSongs();
}

class GetMidiBytesUseCase {
  final SongRepository _repo;
  GetMidiBytesUseCase(this._repo);

  Future<List<int>> call(String songId) => _repo.getMidiBytes(songId);
}

// ─────────────────────────────────────────────────────────────────────────────
// Analytics / History Use Cases
// ─────────────────────────────────────────────────────────────────────────────

class GetRecentSessionsUseCase {
  final SessionRepository _repo;
  GetRecentSessionsUseCase(this._repo);

  Future<List<PerformanceSession>> call(String userId, {int limit = 10}) =>
      _repo.getRecentSessions(userId, limit: limit);
}

class GetWeeklyAccuracyUseCase {
  final SessionRepository _repo;
  GetWeeklyAccuracyUseCase(this._repo);

  Future<Map<DateTime, double>> call(String userId) =>
      _repo.getDailyAccuracy(userId, days: 7);
}

// ─────────────────────────────────────────────────────────────────────────────
// AI Timing Coach Use Case (Bonus Feature)
// ─────────────────────────────────────────────────────────────────────────────

class GetTimingCorrectionSuggestionsUseCase {
  /// Analyzes hit results and returns personalized suggestions.
  List<TimingCoachSuggestion> call(PerformanceSession session) {
    final suggestions = <TimingCoachSuggestion>[];

    if (session.hitResults.isEmpty) return suggestions;

    // Analyze timing tendency (early vs late)
    final scored = session.hitResults
        .where((r) => r.grade != HitGrade.miss && r.timingDeltaMs != null)
        .toList();

    if (scored.isEmpty) return suggestions;

    final avgDelta = scored
        .map((r) => r.timingDeltaMs!)
        .reduce((a, b) => a + b) / scored.length;

    if (avgDelta < -20) {
      suggestions.add(TimingCoachSuggestion(
        type:    SuggestionType.timing,
        title:   'You\'re playing early',
        detail:  'Your average timing is ${avgDelta.abs().toStringAsFixed(0)}ms '
                 'ahead of the beat. Try listening more to the metronome click '
                 'before striking.',
        icon:    '⏩',
      ));
    } else if (avgDelta > 20) {
      suggestions.add(TimingCoachSuggestion(
        type:    SuggestionType.timing,
        title:   'You\'re playing late',
        detail:  'Your average timing is ${avgDelta.toStringAsFixed(0)}ms behind '
                 'the beat. Anticipate the note slightly earlier.',
        icon:    '⏪',
      ));
    } else {
      suggestions.add(TimingCoachSuggestion(
        type:    SuggestionType.timing,
        title:   'Timing is solid!',
        detail:  'Your average timing offset is only ${avgDelta.abs().toStringAsFixed(0)}ms. '
                 'Keep it up!',
        icon:    '🎯',
      ));
    }

    // Consistency analysis (std deviation)
    if (scored.length >= 5) {
      final mean    = avgDelta;
      final stdDev  = _stdDev(scored.map((r) => r.timingDeltaMs!).toList(), mean);
      if (stdDev > 40) {
        suggestions.add(TimingCoachSuggestion(
          type:    SuggestionType.consistency,
          title:   'Work on timing consistency',
          detail:  'Your timing varies by ±${stdDev.toStringAsFixed(0)}ms. '
                   'Practice with a metronome at 50% speed until each stroke lands '
                   'within ±20ms.',
          icon:    '📊',
        ));
      }
    }

    // Miss analysis by pad
    final missByPad = <DrumPad, int>{};
    for (final r in session.hitResults) {
      if (r.grade == HitGrade.miss) {
        missByPad[r.expectedNote.pad] =
            (missByPad[r.expectedNote.pad] ?? 0) + 1;
      }
    }

    if (missByPad.isNotEmpty) {
      final worstPad = missByPad.entries
          .reduce((a, b) => a.value > b.value ? a : b);
      suggestions.add(TimingCoachSuggestion(
        type:    SuggestionType.padAccuracy,
        title:   'Practice your ${worstPad.key.displayName}',
        detail:  'You missed the ${worstPad.key.displayName} ${worstPad.value} '
                 'times. Try an isolated exercise focusing only on this drum.',
        icon:    '🥁',
      ));
    }

    // Overall accuracy suggestion
    if (session.accuracyPercent < 75) {
      suggestions.add(TimingCoachSuggestion(
        type:    SuggestionType.general,
        title:   'Try a slower tempo',
        detail:  'At ${session.accuracyPercent.toStringAsFixed(0)}% accuracy, '
                 'practicing at 70% speed will help your muscle memory lock in '
                 'before returning to full speed.',
        icon:    '🐢',
      ));
    }

    return suggestions;
  }

  double _stdDev(List<double> values, double mean) {
    final variance = values
        .map((v) => (v - mean) * (v - mean))
        .reduce((a, b) => a + b) / values.length;
    return variance > 0 ? variance : 0; // sqrt approximation
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lesson Use Case
// ─────────────────────────────────────────────────────────────────────────────

class GetLessonsUseCase {
  /// Returns a structured curriculum of lessons.
  List<Lesson> call() => LessonCatalog.allLessons;
}

// ─────────────────────────────────────────────────────────────────────────────
// Value Objects
// ─────────────────────────────────────────────────────────────────────────────

enum SuggestionType { timing, consistency, padAccuracy, general }

class TimingCoachSuggestion {
  final SuggestionType type;
  final String         title;
  final String         detail;
  final String         icon;

  const TimingCoachSuggestion({
    required this.type,
    required this.title,
    required this.detail,
    required this.icon,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Lesson Catalog
// ─────────────────────────────────────────────────────────────────────────────

class LessonCatalog {
  static const List<Lesson> allLessons = [
    // ── Beginner ────────────────────────────────────────────────────────────
    Lesson(
      id: 'beg_01',
      title: 'Your First Beat',
      description: 'Learn to play a basic kick + snare pattern.',
      difficulty: Difficulty.beginner,
      estimatedMinutes: 5,
      steps: [
        LessonStep(
          id: 's1', title: 'The Kick Drum',
          instruction: 'Strike the kick drum (bass drum pedal) on beats 1 and 3.',
          notePattern: [NoteEvent(pad: DrumPad.kick, midiNote: 36, beatPosition: 1.0, timeSeconds: 0.0, velocity: 100),
                        NoteEvent(pad: DrumPad.kick, midiNote: 36, beatPosition: 3.0, timeSeconds: 1.0, velocity: 100)],
        ),
        LessonStep(
          id: 's2', title: 'Add the Snare',
          instruction: 'Add the snare on beats 2 and 4.',
          notePattern: [
            NoteEvent(pad: DrumPad.kick,  midiNote: 36, beatPosition: 1.0, timeSeconds: 0.0,  velocity: 100),
            NoteEvent(pad: DrumPad.snare, midiNote: 38, beatPosition: 2.0, timeSeconds: 0.5,  velocity: 100),
            NoteEvent(pad: DrumPad.kick,  midiNote: 36, beatPosition: 3.0, timeSeconds: 1.0,  velocity: 100),
            NoteEvent(pad: DrumPad.snare, midiNote: 38, beatPosition: 4.0, timeSeconds: 1.5,  velocity: 100),
          ],
        ),
        LessonStep(
          id: 's3', title: 'Add the Hi-Hat',
          instruction: 'Play the closed hi-hat on every beat to keep steady time.',
          notePattern: [
            NoteEvent(pad: DrumPad.hihatClosed, midiNote: 42, beatPosition: 1.0, timeSeconds: 0.0,  velocity: 80),
            NoteEvent(pad: DrumPad.kick,        midiNote: 36, beatPosition: 1.0, timeSeconds: 0.0,  velocity: 100),
            NoteEvent(pad: DrumPad.hihatClosed, midiNote: 42, beatPosition: 2.0, timeSeconds: 0.5,  velocity: 80),
            NoteEvent(pad: DrumPad.snare,       midiNote: 38, beatPosition: 2.0, timeSeconds: 0.5,  velocity: 100),
            NoteEvent(pad: DrumPad.hihatClosed, midiNote: 42, beatPosition: 3.0, timeSeconds: 1.0,  velocity: 80),
            NoteEvent(pad: DrumPad.kick,        midiNote: 36, beatPosition: 3.0, timeSeconds: 1.0,  velocity: 100),
            NoteEvent(pad: DrumPad.hihatClosed, midiNote: 42, beatPosition: 4.0, timeSeconds: 1.5,  velocity: 80),
            NoteEvent(pad: DrumPad.snare,       midiNote: 38, beatPosition: 4.0, timeSeconds: 1.5,  velocity: 100),
          ],
        ),
      ],
      songId: 'basic_rock_i',
      xpReward: 75,
    ),

    Lesson(
      id: 'beg_02',
      title: 'Eighth-Note Hi-Hat',
      description: 'Double the hi-hat density for a driving rock feel.',
      difficulty: Difficulty.beginner,
      estimatedMinutes: 8,
      steps: [
        LessonStep(
          id: 's1', title: 'Eighth Notes on Hi-Hat',
          instruction: 'Play the hi-hat on every eighth note (twice per beat) using a consistent wrist motion.',
          notePattern: [],
        ),
        LessonStep(
          id: 's2', title: 'Full Pattern',
          instruction: 'Combine eighth-note hi-hat with kick on 1 & 3, snare on 2 & 4.',
          notePattern: [],
        ),
      ],
      songId: 'basic_rock_i',
      xpReward: 100,
    ),

    // ── Intermediate ─────────────────────────────────────────────────────────
    Lesson(
      id: 'int_01',
      title: 'Funk 16th Notes',
      description: 'Master the 16th-note hi-hat pattern with ghosted snares.',
      difficulty: Difficulty.intermediate,
      estimatedMinutes: 15,
      steps: [
        LessonStep(
          id: 's1', title: 'Ghost Notes',
          instruction: 'Play very soft snare strokes (velocity ~20–40) between the main snare hits. These add texture without overpowering the groove.',
          notePattern: [],
        ),
        LessonStep(
          id: 's2', title: '16th Hi-Hat Grid',
          instruction: 'Four hi-hat strokes per beat, alternating hand-to-hand. Keep them even and light.',
          notePattern: [],
        ),
        LessonStep(
          id: 's3', title: 'Full Funk Groove',
          instruction: 'Combine 16th-note hi-hat, ghost notes, and syncopated kick.',
          notePattern: [],
        ),
      ],
      songId: 'funk_groove',
      xpReward: 200,
    ),

    Lesson(
      id: 'int_02',
      title: 'Jazz Ride Pattern',
      description: 'The classic jazz cymbal pattern with ride, kick, and hihat foot.',
      difficulty: Difficulty.intermediate,
      estimatedMinutes: 12,
      steps: [
        LessonStep(
          id: 's1', title: 'Ride Cymbal Pattern',
          instruction: 'Play the signature jazz ride: beat 1 on the bow, upswing on the "and", beat 2 on the bell, etc.',
          notePattern: [],
        ),
        LessonStep(
          id: 's2', title: 'Left Hand Independence',
          instruction: 'Add soft snare presses on beats 2 and 4 while maintaining the ride pattern.',
          notePattern: [],
        ),
      ],
      songId: 'jazz_ride',
      xpReward: 250,
    ),

    // ── Advanced ─────────────────────────────────────────────────────────────
    Lesson(
      id: 'adv_01',
      title: 'Double Bass Essentials',
      description: 'Build your double kick technique for metal and rock.',
      difficulty: Difficulty.advanced,
      estimatedMinutes: 20,
      steps: [
        LessonStep(
          id: 's1', title: 'Heel-Toe Technique',
          instruction: 'Roll your foot from heel to toe for rapid single-pedal strokes before attempting double pedal.',
          notePattern: [],
        ),
        LessonStep(
          id: 's2', title: 'Alternating Feet',
          instruction: 'Start at 60 BPM, alternating right-left-right-left. Build up 5 BPM per day.',
          notePattern: [],
        ),
        LessonStep(
          id: 's3', title: 'Metal Pattern',
          instruction: 'Eighth-note double bass with straight 8th hi-hat. Keep the bass drum notes even and powerful.',
          notePattern: [],
        ),
      ],
      songId: 'metal_double',
      xpReward: 400,
    ),

    Lesson(
      id: 'adv_02',
      title: 'Polyrhythm 3 over 4',
      description: 'Play triplets on the hi-hat while the kick/snare stay in 4/4.',
      difficulty: Difficulty.advanced,
      estimatedMinutes: 25,
      steps: [
        LessonStep(
          id: 's1', title: 'Triplet Feel',
          instruction: 'Isolate triplets on the hi-hat: three evenly-spaced strokes per beat.',
          notePattern: [],
        ),
        LessonStep(
          id: 's2', title: 'Maintain the 4/4 Pulse',
          instruction: 'While your hand plays triplets, your foot keeps the standard kick-snare pattern.',
          notePattern: [],
        ),
        LessonStep(
          id: 's3', title: 'Full Polyrhythm',
          instruction: 'Merge both parts. The tension between triplets and quarter notes creates the groove.',
          notePattern: [],
        ),
      ],
      songId: 'polyrhythm_7_4',
      xpReward: 500,
    ),
  ];
}
