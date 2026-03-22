// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Song Sync Profile
// Single source of truth for per-song timing calibration.
//
// Analysis results for te_quiero_hombres_g:
//   MIDI: PPQN=480, BPM=75 (800000µs/beat), Time sig=12/8
//   First note: tick=4320 (beat 9.0), time=7.2000s from chart start
//   Chart has 9 beats of silence (7.2s) before beat 1 of music
//   Audio: 228.043s total, elst media_time=2048 samples (42.67ms AAC encoder delay)
//   Audio duration (228s) < MIDI chart duration (311s) → audio covers first ~228s
//   The chart pre-gap of 7.2s and audio pre-gap of 42.67ms must be aligned.
//
// Timing maths for 12/8 at quarter-note BPM=75:
//   quarter-note  = 60/75       = 0.8000s
//   dotted-quarter = 0.8 × 1.5  = 1.2000s  (primary beat in 12/8)
//   bar (4 dotted-quarters)     = 4.8000s
//   eighth-note                 = 0.4000s
//   Chart bar 1 starts at chartSec = 7.2000s (= pre-gap)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// SongSyncSection — a named rehearsal section within a song.
// ─────────────────────────────────────────────────────────────────────────────

/// A named section of the song used for focused / loop practice.
///
/// All times are in CHART seconds (engine clock from tick 0, including pre-gap).
class SongSyncSection {
  /// Unique machine-readable identifier, e.g. "ritmo_hh".
  final String id;

  /// Human-readable name shown in the UI, e.g. "Ritmo Hi-Hat".
  final String name;

  /// Short label for tight spaces, e.g. "RHH".
  final String displayLabel;

  /// Chart time (seconds) at which this section starts (inclusive).
  final double startSeconds;

  /// Chart time (seconds) at which this section ends (exclusive).
  final double endSeconds;

  /// Optional free-text description of the rhythmic pattern.
  final String patternType;

  const SongSyncSection({
    required this.id,
    required this.name,
    required this.startSeconds,
    required this.endSeconds,
    this.displayLabel = '',
    this.patternType  = '',
  });

  double get durationSeconds => endSeconds - startSeconds;

  @override
  String toString() =>
      'SongSyncSection($id, ${startSeconds.toStringAsFixed(2)}s–${endSeconds.toStringAsFixed(2)}s)';
}

// ─────────────────────────────────────────────────────────────────────────────
// SongSyncProfile
// ─────────────────────────────────────────────────────────────────────────────

/// Sync profile for a specific song — single source of truth for timing.
///
/// All time-related data for a song lives here.  No component may hardcode
/// BPM, bar length, beat duration, offsets, or section boundaries.
class SongSyncProfile {
  final String songId;

  // ── Tempo ──────────────────────────────────────────────────────────────────

  /// BPM as stored in the MIDI file (always quarter-note BPM).
  /// For 12/8 at dotted-quarter=75: the MIDI stores 75 quarter-note BPM
  /// (800000µs/beat), which equals 50 dotted-quarter BPM.
  /// Display BPM to the user as [displayBpm].
  final double bpm;

  /// Display-facing BPM — what the user sees and what the score notation says.
  /// For 12/8, this is the dotted-quarter BPM (e.g. 75).
  /// Equals [bpm] for 4/4 songs.
  final double displayBpm;

  // ── Time signature ─────────────────────────────────────────────────────────

  /// Time signature string, e.g. "4/4", "12/8", "6/8".
  final String timeSignature;

  /// Number of PRIMARY beats per bar (not eighth-note beats).
  /// 12/8 → 4 (four dotted-quarter beats).
  /// 4/4  → 4 (four quarter beats).
  final int beatsPerBar;

  /// Number of subdivisions (smallest rhythmic unit) per primary beat.
  /// 12/8 → 3 (three eighth notes per dotted-quarter beat).
  /// 4/4  → 2 (two eighth notes per quarter beat).
  final int subdivisions;

  // ── Audio/chart alignment ──────────────────────────────────────────────────

  /// How many seconds of silence exist at the start of the audio file
  /// before the musical content begins.
  /// Derived from the M4A elst (edit list) media_time field.
  /// For te_quiero: 2048 samples / 48000 Hz = 0.042667s (AAC encoder delay).
  final double audioOffsetSeconds;

  /// How many seconds of silence exist at the start of the MIDI chart
  /// before the first note event.
  /// For te_quiero: first note at tick=4320 = beat 9 = 7.2s at BPM=75.
  /// The audio backing track begins at the same musical point as the chart,
  /// so this offset is used to align the chart's beat-0 with the audio's beat-0.
  final double chartOffsetSeconds;

  // ── Song length ────────────────────────────────────────────────────────────

  /// Total playable song length in seconds.
  /// Sourced from song.ini `song_length` (ms) for package-based songs.
  /// 0.0 means "not specified" — caller should derive from last note + padding.
  final double songLengthSeconds;

  // ── Sections ───────────────────────────────────────────────────────────────

  /// Named sections for structured practice.
  /// startSeconds / endSeconds are in CHART time (from tick 0, including pre-gap).
  final List<SongSyncSection> sections;

  /// Human-readable explanation of the timing parameters.
  final String notes;

  const SongSyncProfile({
    required this.songId,
    required this.bpm,
    double? displayBpm,
    this.timeSignature      = '4/4',
    this.beatsPerBar        = 4,
    this.subdivisions       = 2,
    this.audioOffsetSeconds = 0.0,
    this.chartOffsetSeconds = 0.0,
    this.songLengthSeconds  = 0.0,
    this.sections           = const [],
    this.notes              = '',
  }) : displayBpm = displayBpm ?? bpm;

  // ── Derived timing ─────────────────────────────────────────────────────────

  /// Duration of one primary beat in seconds.
  /// For 12/8: dotted-quarter = 1.5 × (60/bpm).
  /// For 4/4:  quarter = 60/bpm.
  double get beatDurationSeconds {
    // subdivisions encodes the note-value of the primary beat:
    //   subdivisions=3 → dotted-quarter (= 3 eighth notes = 1.5 quarter notes)
    //   subdivisions=2 → quarter note
    //   subdivisions=4 → eighth note
    final eighthDuration = (60.0 / bpm) / 2.0; // one eighth note
    return eighthDuration * subdivisions;
  }

  /// Duration of one full bar in seconds.
  double get barDurationSeconds => beatDurationSeconds * beatsPerBar;

  // ── Audio alignment ────────────────────────────────────────────────────────

  /// Seconds to seek into the audio file before starting playback,
  /// in order to skip the encoder pre-roll silence (AAC delay).
  double get audioSeekSeconds => audioOffsetSeconds > 0 ? audioOffsetSeconds : 0.0;

  /// Seconds to delay audio start after the engine clock begins,
  /// so that audio beat-1 aligns with chart beat-1.
  /// = max(0, chartOffsetSeconds − audioOffsetSeconds)
  double get audioDelaySeconds {
    final delay = chartOffsetSeconds - audioOffsetSeconds;
    return delay > 0 ? delay : 0.0;
  }

  /// THE single authoritative formula for audio/chart alignment.
  ///
  /// Given a chart position [chartSec] (engine clock seconds from tick 0),
  /// returns the expected audio player position in seconds.
  ///
  ///   audioPos = chartSec − audioDelaySeconds + audioSeekSeconds
  ///            = chartSec − (chartOffsetSeconds − audioOffsetSeconds) + audioOffsetSeconds
  ///
  /// Returns null when the chart is still in the pre-gap and audio has not
  /// started yet (audioPos would be negative).
  ///
  /// Every place in the engine that needs to know "where should the audio be?"
  /// must call this method — never replicate the formula inline.
  double? audioPositionForChartTime(double chartSec) {
    final pos = chartSec - audioDelaySeconds + audioSeekSeconds;
    return pos >= 0.0 ? pos : null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Song Sync Registry
// ─────────────────────────────────────────────────────────────────────────────

// Te Quiero bar timestamps (chart seconds, pre-gap = 7.2s included):
//   Bar 1 = 7.20s  (first drum hit)
//   Bar n = 7.20 + (n-1) × 4.80s
//
// Section bar ranges derived from the printed score (PDF):
//   Entrada          bars  1– 4   →  7.20s –  26.40s
//   Ritmo HH         bars  5–18   →  26.40s – 94.40s  (NOTE: 14 bars)
//   Break            bars 19–20   →  94.40s – 104.00s
//   3 Cajas HH       bars 21–30   → 104.00s – 152.00s
//   3 Cajas Ride     bars 31–38   → 152.00s – 190.40s
//   1 Caja Ride      bars 39–42   → 190.40s – 209.60s
//   Ritmo Ride       bars 43–50   → 209.60s – 248.00s
//   Corte            bars 51–52   → 248.00s – 257.60s
//   1 Caja HH        bars 53–56   → 257.60s – 276.80s
//   Final            bars 57–end  → 276.80s – 311.00s
//
// These bar boundaries are initial estimates from the PDF layout.
// Calibrate by playing back with the timing overlay and adjusting.

class SongSyncRegistry {
  static const List<SongSyncSection> _teQuieroSections = [
    SongSyncSection(
      id: 'entrada',
      name: 'Entrada',
      displayLabel: 'ENT',
      startSeconds: 7.20,
      endSeconds: 26.40,
      patternType: 'intro — tacet / light hi-hat',
    ),
    SongSyncSection(
      id: 'ritmo_hh',
      name: 'Ritmo Hi-Hat',
      displayLabel: 'RHH',
      startSeconds: 26.40,
      endSeconds: 94.40,
      patternType: '12/8 groove — hi-hat ostinato, snare on 3 & 4',
    ),
    SongSyncSection(
      id: 'break',
      name: 'Break',
      displayLabel: 'BRK',
      startSeconds: 94.40,
      endSeconds: 104.00,
      patternType: 'fill / transition break',
    ),
    SongSyncSection(
      id: '3cajas_hh',
      name: '3 Cajas Hi-Hat',
      displayLabel: '3HH',
      startSeconds: 104.00,
      endSeconds: 152.00,
      patternType: '12/8 groove — 3-snare figure with hi-hat',
    ),
    SongSyncSection(
      id: '3cajas_ride',
      name: '3 Cajas Ride',
      displayLabel: '3RD',
      startSeconds: 152.00,
      endSeconds: 190.40,
      patternType: '12/8 groove — 3-snare figure with ride cymbal',
    ),
    SongSyncSection(
      id: '1caja_ride',
      name: '1 Caja Ride',
      displayLabel: '1RD',
      startSeconds: 190.40,
      endSeconds: 209.60,
      patternType: 'simplified groove — single snare with ride',
    ),
    SongSyncSection(
      id: 'ritmo_ride',
      name: 'Ritmo Ride',
      displayLabel: 'RRD',
      startSeconds: 209.60,
      endSeconds: 248.00,
      patternType: '12/8 groove — full ride cymbal ostinato',
    ),
    SongSyncSection(
      id: 'corte',
      name: 'Corte',
      displayLabel: 'CRT',
      startSeconds: 248.00,
      endSeconds: 257.60,
      patternType: 'cut / stop-time figure',
    ),
    SongSyncSection(
      id: '1caja_hh',
      name: '1 Caja Hi-Hat',
      displayLabel: '1HH',
      startSeconds: 257.60,
      endSeconds: 276.80,
      patternType: 'simplified groove — single snare with hi-hat',
    ),
    SongSyncSection(
      id: 'final',
      name: 'Final',
      displayLabel: 'FIN',
      startSeconds: 276.80,
      endSeconds: 311.00,
      patternType: 'outro — full groove to end',
    ),
  ];

  static const Map<String, SongSyncProfile> _profiles = {
    'te_quiero_hombres_g': SongSyncProfile(
      songId: 'te_quiero_hombres_g',
      bpm: 75.0,
      displayBpm: 75.0,           // dotted-quarter = 75 BPM as notated in score
      timeSignature: '12/8',
      beatsPerBar: 4,             // four dotted-quarter beats per bar
      subdivisions: 3,            // three eighth notes per dotted-quarter beat
      // Audio encoder delay from elst: media_time=2048 samples at 48000Hz = 42.67ms
      audioOffsetSeconds: 0.042667,
      // Chart pre-gap: first note at tick=4320, beat=9.0, time=7.2s at BPM=75
      // The audio backing track is aligned to beat 1 of the song, not chart tick 0.
      // So the chart has 7.2s of silence before beat 1.
      chartOffsetSeconds: 7.2,
      sections: _teQuieroSections,
      notes: 'Te Quiero - Hombres G. '
             'MIDI: PPQN=480, BPM=75 (800000us/beat), time sig 12/8. '
             'First note at tick=4320 (beat 9.0, time=7.2000s). '
             'Chart pre-gap: 9 beats = 7.2s before first drum hit. '
             'Audio: 228.043s, elst media_time=2048 samples/48000Hz = 42.67ms encoder delay. '
             'audioPositionForChartTime(t) = t - 7.157333 + 0.042667 = t - 7.114667. '
             'chart leads audio by 7.157s: audio should start 7.157s after engine. '
             'bar = 4.8s (4 dotted-quarter beats × 1.2s/beat). '
             'BackingTrack M4A is faststart-converted.',
    ),
  };

  static SongSyncProfile? forSong(String songId) => _profiles[songId];

  static SongSyncProfile defaultProfile(String songId) =>
      _profiles[songId] ?? SongSyncProfile(songId: songId, bpm: 120.0);
}
