import 'package:flutter_test/flutter_test.dart';
import 'package:nava_drummer/domain/entities/entities.dart';

void main() {
  group('ScoringConfig Tests', () {
    test('Perfect hit within 30ms', () {
      expect(ScoringConfig.gradeFromDelta(0), HitGrade.perfect);
      expect(ScoringConfig.gradeFromDelta(15), HitGrade.perfect);
      expect(ScoringConfig.gradeFromDelta(-28), HitGrade.perfect);
    });

    test('Good hit 30–80ms', () {
      expect(ScoringConfig.gradeFromDelta(50), HitGrade.good);
      expect(ScoringConfig.gradeFromDelta(-70), HitGrade.good);
    });

    test('Late hit 80–150ms (positive delta)', () {
      expect(ScoringConfig.gradeFromDelta(100), HitGrade.late);
    });

    test('Early hit 80–150ms (negative delta)', () {
      expect(ScoringConfig.gradeFromDelta(-140), HitGrade.early);
    });

    test('Miss beyond 150ms', () {
      expect(ScoringConfig.gradeFromDelta(200), HitGrade.miss);
      expect(ScoringConfig.gradeFromDelta(-500), HitGrade.miss);
    });

    test('Score values correct', () {
      expect(ScoringConfig.scoreFromGrade(HitGrade.perfect), 300);
      expect(ScoringConfig.scoreFromGrade(HitGrade.good),    200);
      expect(ScoringConfig.scoreFromGrade(HitGrade.early),   100);
      expect(ScoringConfig.scoreFromGrade(HitGrade.late),    100);
      expect(ScoringConfig.scoreFromGrade(HitGrade.miss),    0);
    });
  });

  group('DrumMapping Tests', () {
    test('GM drum map contains standard notes', () {
      expect(StandardDrumMaps.generalMidi[36], DrumPad.kick);
      expect(StandardDrumMaps.generalMidi[38], DrumPad.snare);
      expect(StandardDrumMaps.generalMidi[42], DrumPad.hihatClosed);
      expect(StandardDrumMaps.generalMidi[46], DrumPad.hihatOpen);
      expect(StandardDrumMaps.generalMidi[49], DrumPad.crash1);
      expect(StandardDrumMaps.generalMidi[51], DrumPad.ride);
    });

    test('Roland TD map has expected notes', () {
      expect(StandardDrumMaps.rolandTD[36], DrumPad.kick);
      expect(StandardDrumMaps.rolandTD[38], DrumPad.snare);
    });

    test('DrumMapping.getPad returns correct pad', () {
      final mapping = DrumMapping(deviceId: 'test', noteMap: StandardDrumMaps.generalMidi);
      expect(mapping.getPad(36), DrumPad.kick);
      expect(mapping.getPad(38), DrumPad.snare);
      expect(mapping.getPad(99), isNull);
    });
  });

  group('UserProgress XP Tests', () {
    const progress = UserProgress(
      userId: 'test',
      displayName: 'Test',
      totalXp: 2800,
      level: 4,
      currentStreak: 3,
      maxStreak: 10,
      songBestScores: {},
      achievements: [],
      lastPracticeDate: null,
    );

    test('Level progress is valid fraction', () {
      expect(progress.levelProgress, greaterThan(0));
      expect(progress.levelProgress, lessThanOrEqualTo(1));
    });

    test('XP for next level is positive', () {
      expect(progress.xpForNextLevel, greaterThan(0));
    });
  });

  group('PerformanceSession letter grade', () {
    _makeSession(double accuracy) => PerformanceSession(
      id: 'test', song: _testSong,
      startedAt: DateTime.now(), hitResults: [],
      totalScore: 0, accuracyPercent: accuracy,
      perfectCount: 0, goodCount: 0, okayCount: 0,
      missCount: 0, maxCombo: 0, xpEarned: 0,
    );

    test('95%+ → S grade', () {
      expect(_makeSession(96.0).letterGrade, 'S');
      expect(_makeSession(100.0).letterGrade, 'S');
    });
    test('88-95% → A grade', () {
      expect(_makeSession(90.0).letterGrade, 'A');
    });
    test('75-88% → B grade', () {
      expect(_makeSession(80.0).letterGrade, 'B');
    });
    test('60-75% → C grade', () {
      expect(_makeSession(65.0).letterGrade, 'C');
    });
    test('<60% → D grade', () {
      expect(_makeSession(50.0).letterGrade, 'D');
    });
  });

  group('MidiEvent Tests', () {
    const event = MidiEvent(
      type: MidiEventType.noteOn,
      channel: 9,
      note: 36,
      velocity: 100,
      timestampMicros: 1000000,
    );

    test('noteOn with velocity > 0 is isNoteOn', () {
      expect(event.isNoteOn, isTrue);
    });

    test('normalizedVelocity in range', () {
      expect(event.normalizedVelocity, closeTo(100 / 127, 0.01));
    });

    test('noteOn with velocity 0 is isNoteOff', () {
      const offEvent = MidiEvent(
        type: MidiEventType.noteOn,
        channel: 9, note: 36, velocity: 0,
        timestampMicros: 1000000,
      );
      expect(offEvent.isNoteOff, isTrue);
      expect(offEvent.isNoteOn, isFalse);
    });
  });

  group('NoteEvent Tests', () {
    const note = NoteEvent(
      pad: DrumPad.kick,
      midiNote: 36,
      beatPosition: 1.0,
      timeSeconds: 0.5,
      velocity: 100,
    );

    test('NoteEvent properties correct', () {
      expect(note.pad, DrumPad.kick);
      expect(note.timeSeconds, 0.5);
      expect(note.velocity, 100);
    });
  });
}

// ── Test Fixtures ─────────────────────────────────────────────────────────
const _testSong = Song(
  id: 'test_song',
  title: 'Test Song',
  artist: 'Test Artist',
  difficulty: Difficulty.beginner,
  genre: Genre.rock,
  bpm: 120,
  duration: Duration(seconds: 60),
  midiAssetPath: 'assets/midi/test.mid',
  isUnlocked: true,
  xpReward: 100,
);
