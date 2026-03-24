// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Domain Entities
// Single source of truth for all domain models.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:equatable/equatable.dart';
// ignore: depend_on_referenced_packages

// ── Input Source ──────────────────────────────────────────────────────────────
/// The physical source that produced a user hit.
/// Only two sources exist — microphone mode was permanently removed.
enum InputSourceType {
  connectedDrum,  // MIDI/USB/BLE hardware drum kit
  onScreenPad,    // virtual pads tapped on the device screen
}

// ── Device ────────────────────────────────────────────────────────────────────
enum DeviceTransport { usb, bluetooth, virtual }
enum DrumKitBrand    { roland, alesis, yamaha, ddrum, pearl, generic }

class MidiDevice extends Equatable {
  final String id;
  final String name;
  final int?   vendorId;
  final int?   productId;
  final DeviceTransport transport;
  final DrumKitBrand    brand;
  final bool   isConnected;

  const MidiDevice({
    required this.id,
    required this.name,
    this.vendorId,
    this.productId,
    required this.transport,
    this.brand = DrumKitBrand.generic,
    this.isConnected = false,
  });

  MidiDevice copyWith({bool? isConnected}) =>
      MidiDevice(id:id, name:name, vendorId:vendorId, productId:productId,
          transport:transport, brand:brand, isConnected:isConnected??this.isConnected);

  @override List<Object?> get props => [id, name, transport, brand, isConnected];
}

// ── Drum Pads ─────────────────────────────────────────────────────────────────
enum DrumPad {
  kick, snare, hihatClosed, hihatOpen, hihatPedal,
  crash1, crash2, ride, rideBell,
  tom1, tom2, tom3, floorTom, rimshot, crossstick,
}

extension DrumPadExt on DrumPad {
  String get displayName {
    const names = {
      DrumPad.kick:'Kick', DrumPad.snare:'Snare',
      DrumPad.hihatClosed:'Hi-Hat (Closed)', DrumPad.hihatOpen:'Hi-Hat (Open)',
      DrumPad.hihatPedal:'Hi-Hat Pedal', DrumPad.crash1:'Crash 1',
      DrumPad.crash2:'Crash 2', DrumPad.ride:'Ride', DrumPad.rideBell:'Ride Bell',
      DrumPad.tom1:'Tom 1', DrumPad.tom2:'Tom 2', DrumPad.tom3:'Tom 3',
      DrumPad.floorTom:'Floor Tom', DrumPad.rimshot:'Rimshot',
      DrumPad.crossstick:'Cross Stick',
    };
    return names[this] ?? name;
  }
  String get shortName {
    const shorts = {
      DrumPad.kick:'KD', DrumPad.snare:'SD', DrumPad.hihatClosed:'HH',
      DrumPad.hihatOpen:'OH', DrumPad.hihatPedal:'HP', DrumPad.crash1:'C1',
      DrumPad.crash2:'C2', DrumPad.ride:'RD', DrumPad.rideBell:'RB',
      DrumPad.tom1:'T1', DrumPad.tom2:'T2', DrumPad.tom3:'T3',
      DrumPad.floorTom:'FT', DrumPad.rimshot:'RS', DrumPad.crossstick:'CS',
    };
    return shorts[this] ?? name.substring(0,2).toUpperCase();
  }
}

// ── Drum Mapping ──────────────────────────────────────────────────────────────
class DrumMapping extends Equatable {
  final String deviceId;
  final Map<int, DrumPad> noteMap;

  const DrumMapping({required this.deviceId, required this.noteMap});

  DrumPad? getPad(int note) => noteMap[note];

  @override List<Object?> get props => [deviceId, noteMap];
}

class StandardDrumMaps {
  static const Map<int, DrumPad> generalMidi = {
    // ── Kick ──────────────────────────────────────────────────────────────────
    35: DrumPad.kick,        36: DrumPad.kick,
    // ── Snare ─────────────────────────────────────────────────────────────────
    38: DrumPad.snare,       40: DrumPad.snare,
    37: DrumPad.crossstick,
    // ── Hi-Hat ────────────────────────────────────────────────────────────────
    42: DrumPad.hihatClosed, 44: DrumPad.hihatPedal, 46: DrumPad.hihatOpen,
    // ── Crashes ───────────────────────────────────────────────────────────────
    49: DrumPad.crash1,      55: DrumPad.crash2,      57: DrumPad.crash2,
    // ── Ride ──────────────────────────────────────────────────────────────────
    51: DrumPad.ride,        53: DrumPad.rideBell,    59: DrumPad.ride,
    // ── Toms (50=High Tom, 48=Hi-Mid, 47=Low-Mid, 45=Low) ────────────────────
    50: DrumPad.tom1,        48: DrumPad.tom1,
    47: DrumPad.tom2,        45: DrumPad.tom2,
    // ── Floor Tom ─────────────────────────────────────────────────────────────
    43: DrumPad.floorTom,    41: DrumPad.floorTom,
  };

  static const Map<int, DrumPad> rolandTD = {
    36: DrumPad.kick,
    38: DrumPad.snare, 40: DrumPad.rimshot,
    42: DrumPad.hihatClosed, 44: DrumPad.hihatPedal, 46: DrumPad.hihatOpen,
    49: DrumPad.crash1, 57: DrumPad.crash2,
    51: DrumPad.ride,  53: DrumPad.rideBell,
    50: DrumPad.tom1,  48: DrumPad.tom2, 45: DrumPad.tom3, 43: DrumPad.floorTom,
  };

  static const Map<int, DrumPad> alesis = {
    36: DrumPad.kick,
    38: DrumPad.snare, 40: DrumPad.snare,
    42: DrumPad.hihatClosed, 44: DrumPad.hihatPedal, 46: DrumPad.hihatOpen,
    49: DrumPad.crash1, 51: DrumPad.ride,
    50: DrumPad.tom1,  48: DrumPad.tom2, 47: DrumPad.tom3, 43: DrumPad.floorTom,
  };

  static Map<int, DrumPad> forBrand(DrumKitBrand brand) {
    switch (brand) {
      case DrumKitBrand.roland: return rolandTD;
      case DrumKitBrand.alesis: return alesis;
      default:                  return generalMidi;
    }
  }
}

// ── MIDI Event ────────────────────────────────────────────────────────────────
enum MidiEventType { noteOn, noteOff, controlChange, programChange, other }

class MidiEvent extends Equatable {
  final MidiEventType   type;
  final int             channel;
  final int             note;
  final int             velocity;
  final int             timestampMicros;
  final String?         deviceId;
  /// Which input source produced this event.
  /// Defaults to [InputSourceType.connectedDrum] for real MIDI events.
  final InputSourceType inputSource;

  const MidiEvent({
    required this.type,
    required this.channel,
    required this.note,
    required this.velocity,
    required this.timestampMicros,
    this.deviceId,
    this.inputSource = InputSourceType.connectedDrum,
  });

  bool get isNoteOn  => type == MidiEventType.noteOn  && velocity > 0;
  bool get isNoteOff => type == MidiEventType.noteOff || (type == MidiEventType.noteOn && velocity == 0);
  double get normalizedVelocity => velocity / 127.0;

  @override List<Object?> get props => [type, channel, note, velocity, timestampMicros];
}

// ── Song Section ──────────────────────────────────────────────────────────────
/// Represents a named section of a song for targeted practice.
class SongSection extends Equatable {
  final String id;
  final String name;          // e.g. "Intro", "Verse", "Chorus", "Bridge", "Outro"
  final double startSeconds;
  final double endSeconds;
  /// Short label for tight UI spaces, e.g. "RHH".
  final String displayLabel;
  /// Description of the rhythmic pattern in this section.
  final String patternType;

  const SongSection({
    required this.id,
    required this.name,
    required this.startSeconds,
    required this.endSeconds,
    this.displayLabel = '',
    this.patternType  = '',
  });

  double get durationSeconds => endSeconds - startSeconds;
  bool contains(double t) => t >= startSeconds && t < endSeconds;

  @override
  List<Object?> get props => [id, name, startSeconds, endSeconds];
}

// ── Song ──────────────────────────────────────────────────────────────────────
enum Difficulty  { beginner, intermediate, advanced, expert }
enum Genre       { rock, jazz, funk, metal, latin, pop, electronic, cristiana, custom }

class Song extends Equatable {
  final String    id;
  final String    title;
  final String    artist;
  final Difficulty difficulty;
  final Genre     genre;
  final int       bpm;
  final Duration  duration;
  final String    midiAssetPath;
  final String?   coverArtUrl;
  final bool      isUnlocked;
  final int       xpReward;
  final String?   description;
  final String?   techniqueTag;
  final String?   genreLabel;
  final List<SongSection> sections;
  final String?   scoreAssetPath;
  /// Time signature string, e.g. "4/4", "12/8".
  final String    timeSignature;
  /// Number of primary beats per bar (4 for both 4/4 and 12/8).
  final int       beatsPerBar;
  /// Asset directory of a Clone Hero / RBN song package.
  /// When non-null, the song is loaded via [SongPackageLoader] instead of
  /// reading [midiAssetPath] directly.  Includes the trailing format:
  /// e.g. 'assets/songs/aun_coda'
  final String?   packageAssetDir;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.difficulty,
    required this.genre,
    required this.bpm,
    required this.duration,
    this.midiAssetPath  = '',
    this.coverArtUrl,
    this.isUnlocked = false,
    this.xpReward   = 100,
    this.description,
    this.techniqueTag,
    this.genreLabel,
    this.sections      = const [],
    this.scoreAssetPath,
    this.timeSignature = '4/4',
    this.beatsPerBar   = 4,
    this.packageAssetDir,
  });

  /// True when this song is loaded from a Clone Hero / RBN song package.
  bool get isPackageBased => packageAssetDir != null;

  /// True when packageAssetDir points to a Firebase Storage path (remote song).
  /// Remote songs must be downloaded before practice can start.
  bool get isRemoteSong =>
      packageAssetDir != null && !packageAssetDir!.startsWith('assets/') && !packageAssetDir!.startsWith('/');

  /// True when packageAssetDir points to a local filesystem path (downloaded).
  bool get isLocalFile =>
      packageAssetDir != null && packageAssetDir!.startsWith('/');

  Song copyWith({
    String?           id,
    String?           title,
    String?           artist,
    Difficulty?       difficulty,
    Genre?            genre,
    int?              bpm,
    Duration?         duration,
    String?           midiAssetPath,
    String?           coverArtUrl,
    bool?             isUnlocked,
    int?              xpReward,
    String?           description,
    String?           techniqueTag,
    String?           genreLabel,
    List<SongSection>? sections,
    String?           scoreAssetPath,
    String?           timeSignature,
    int?              beatsPerBar,
    String?           packageAssetDir,
  }) => Song(
    id:             id             ?? this.id,
    title:          title          ?? this.title,
    artist:         artist         ?? this.artist,
    difficulty:     difficulty     ?? this.difficulty,
    genre:          genre          ?? this.genre,
    bpm:            bpm            ?? this.bpm,
    duration:       duration       ?? this.duration,
    midiAssetPath:  midiAssetPath  ?? this.midiAssetPath,
    coverArtUrl:    coverArtUrl    ?? this.coverArtUrl,
    isUnlocked:     isUnlocked     ?? this.isUnlocked,
    xpReward:       xpReward       ?? this.xpReward,
    description:    description    ?? this.description,
    techniqueTag:   techniqueTag   ?? this.techniqueTag,
    genreLabel:     genreLabel     ?? this.genreLabel,
    sections:       sections       ?? this.sections,
    scoreAssetPath: scoreAssetPath ?? this.scoreAssetPath,
    timeSignature:  timeSignature  ?? this.timeSignature,
    beatsPerBar:    beatsPerBar    ?? this.beatsPerBar,
    packageAssetDir: packageAssetDir ?? this.packageAssetDir,
  );

  @override List<Object?> get props => [id];
}

// ── Note Event ────────────────────────────────────────────────────────────────
class NoteEvent extends Equatable {
  final DrumPad pad;
  final int     midiNote;
  final double  beatPosition;
  final double  timeSeconds;
  final int     velocity;
  final double  duration;

  const NoteEvent({
    required this.pad,
    required this.midiNote,
    required this.beatPosition,
    required this.timeSeconds,
    required this.velocity,
    this.duration = 0.05,
  });

  @override List<Object?> get props => [pad, midiNote, timeSeconds];
}

// ── Hit Result ────────────────────────────────────────────────────────────────
/// Grade assigned to each user hit.
/// • perfect / good → within tight/wide timing window
/// • early  → hit was too early (outside good window but within okay window)
/// • late   → hit was too late  (outside good window but within okay window)
/// • miss   → no matching note found or far outside all windows
/// • extra  → hit with no corresponding expected note
enum HitGrade { perfect, good, early, late, miss, extra }

class HitResult extends Equatable {
  final NoteEvent      expected;
  final MidiEvent?     actual;
  final HitGrade       grade;
  final double         timingDeltaMs;
  final bool           correctPad;
  final int            score;
  final InputSourceType inputSource;
  /// The actual pad the user hit (may differ from [expected].pad on wrong-pad hits).
  final DrumPad?       hitPad;

  const HitResult({
    required this.expected,
    this.actual,
    required this.grade,
    required this.timingDeltaMs,
    required this.correctPad,
    required this.score,
    this.inputSource = InputSourceType.connectedDrum,
    this.hitPad,
  });

  NoteEvent get expectedNote => expected;
  int?      get actualTimestampMicros => actual?.timestampMicros;
  bool      get isMiss => grade == HitGrade.miss;

  @override List<Object?> get props => [expected, grade, timingDeltaMs];
}

// ── Scoring ───────────────────────────────────────────────────────────────────
class ScoringConfig {
  static const int    perfectScore  = 300;
  static const int    goodScore     = 200;
  static const int    okayScore     = 100;
  static const int    missScore     = 0;
  static const double perfectWindow = 30.0;
  static const double goodWindow    = 80.0;
  static const double okayWindow    = 150.0;

  /// Grade from a signed delta (positive = late, negative = early).
  /// Returns [early] or [late] when within the okay window but outside good.
  static HitGrade gradeFromDelta(double deltaMs) {
    final a = deltaMs.abs();
    if (a <= perfectWindow) return HitGrade.perfect;
    if (a <= goodWindow)    return HitGrade.good;
    if (a <= okayWindow)    return deltaMs < 0 ? HitGrade.early : HitGrade.late;
    return HitGrade.miss;
  }

  static int scoreFromGrade(HitGrade g) {
    switch (g) {
      case HitGrade.perfect: return perfectScore;
      case HitGrade.good:    return goodScore;
      case HitGrade.early:   return okayScore;
      case HitGrade.late:    return okayScore;
      default:               return missScore;
    }
  }
}

// ── Performance Session ───────────────────────────────────────────────────────
class PerformanceSession extends Equatable {
  final String         id;
  final Song           song;
  final DateTime       startedAt;
  final List<HitResult> hitResults;
  final int            totalScore;
  final double         accuracyPercent;
  final int            perfectCount;
  final int            goodCount;
  final int            okayCount;
  final int            missCount;
  final int            maxCombo;
  final int            xpEarned;

  final Map<DrumPad, dynamic>? perDrumAnalysis; // TimingAnalysis per pad
  final dynamic                globalAnalysis;  // TimingAnalysis global
  final dynamic                timingEngine;    // MathTimingEngine reference

  const PerformanceSession({
    required this.id,
    required this.song,
    required this.startedAt,
    required this.hitResults,
    required this.totalScore,
    required this.accuracyPercent,
    required this.perfectCount,
    required this.goodCount,
    required this.okayCount,
    required this.missCount,
    required this.maxCombo,
    required this.xpEarned,
    this.perDrumAnalysis,
    this.globalAnalysis,
    this.timingEngine,
  });

  Duration get totalDuration => song.duration;

  String get letterGrade {
    if (accuracyPercent >= 95) return 'S';
    if (accuracyPercent >= 88) return 'A';
    if (accuracyPercent >= 75) return 'B';
    if (accuracyPercent >= 60) return 'C';
    return 'D';
  }

  @override List<Object?> get props => [id, totalScore, accuracyPercent];

}

// ── User Progress ─────────────────────────────────────────────────────────────
class UserProgress extends Equatable {
  final String           userId;
  final String           displayName;
  final int              totalXp;
  final int              level;
  final int              currentStreak;
  final int              maxStreak;
  final Map<String, int> songBestScores;
  final List<String>     achievements;
  final DateTime?        lastPracticeDate;

  const UserProgress({
    required this.userId,
    required this.displayName,
    required this.totalXp,
    required this.level,
    required this.currentStreak,
    required this.maxStreak,
    required this.songBestScores,
    required this.achievements,
    this.lastPracticeDate,
  });

  static const _thresholds = {
    1:500, 2:1200, 3:2500, 4:4500, 5:7500,
    6:12000, 7:18000, 8:26000, 9:36000, 10:50000,
  };

  int    get xpForNextLevel    => _thresholds[level] ?? (level * 1200);
  int    get xpInCurrentLevel  => totalXp - (_thresholds[(level-1).clamp(1,10)] ?? 0);
  double get levelProgress     => (xpInCurrentLevel / xpForNextLevel).clamp(0.0, 1.0);

  UserProgress copyWith({
    String?           displayName,
    int?              totalXp,
    int?              level,
    int?              currentStreak,
    int?              maxStreak,
    Map<String, int>? songBestScores,
    List<String>?     achievements,
    DateTime?         lastPracticeDate,
  }) => UserProgress(
    userId:           userId,
    displayName:      displayName      ?? this.displayName,
    totalXp:          totalXp          ?? this.totalXp,
    level:            level            ?? this.level,
    currentStreak:    currentStreak    ?? this.currentStreak,
    maxStreak:        maxStreak        ?? this.maxStreak,
    songBestScores:   songBestScores   ?? this.songBestScores,
    achievements:     achievements     ?? this.achievements,
    lastPracticeDate: lastPracticeDate ?? this.lastPracticeDate,
  );

  @override List<Object?> get props => [userId, totalXp, level, currentStreak];
}

// ── Lesson ────────────────────────────────────────────────────────────────────
class Lesson extends Equatable {
  final String         id;
  final String         title;
  final String         description;
  final Difficulty     difficulty;
  final int            estimatedMinutes;
  final List<LessonStep> steps;
  final String?        songId;
  final int            xpReward;

  const Lesson({
    required this.id,
    required this.title,
    required this.description,
    required this.difficulty,
    this.estimatedMinutes = 10,
    required this.steps,
    this.songId,
    this.xpReward = 100,
  });

  @override List<Object?> get props => [id];
}

class LessonStep extends Equatable {
  final String         id;
  final String         title;
  final String         instruction;
  final List<NoteEvent> notePattern;

  const LessonStep({
    required this.id,
    required this.title,
    required this.instruction,
    this.notePattern = const [],
  });

  @override List<Object?> get props => [id];
}
