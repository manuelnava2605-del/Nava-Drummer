// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Song Package Domain Models
//
// A SongPackage is the internal representation of a Clone Hero / RBN song
// bundle after it has been fully loaded by SongPackageLoader.
//
// Pipeline:
//   assets/songs/<id>/         ← Clone Hero bundle on disk
//     song.ini                 → SongPackage.meta (name, artist, genre…)
//     notes.mid                → SongPackage.chart (List<NoteEvent>)
//     *.ogg stems              → SongPackage.audio (AudioTrackSet)
//   + derived from MIDI        → SongPackage.syncProfile (BPM, offsets…)
//
// The SongPackage is the NEW single source of truth for a song.
// No other place may hardcode BPM, chart offsets, stem paths, or note data.
// ─────────────────────────────────────────────────────────────────────────────
import 'entities.dart';
import '../../core/song_sync_profile.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StemType — which instrument stem is this OGG file?
// ─────────────────────────────────────────────────────────────────────────────
enum StemType {
  drums,   // Isolated drum track  (mute this to let user hear their own playing)
  guitar,  // Lead guitar
  rhythm,  // Rhythm guitar / bass
  vocals,  // Vocal track
  song,    // Full pre-mixed track (single-stem packages)
  keys,    // Keyboard / synths
  bass,    // Dedicated bass stem
  crowd,   // Crowd ambience (Rock Band feature)
}

extension StemTypeExt on StemType {
  String get displayName {
    switch (this) {
      case StemType.drums:   return 'Drums';
      case StemType.guitar:  return 'Guitar';
      case StemType.rhythm:  return 'Rhythm';
      case StemType.vocals:  return 'Vocals';
      case StemType.song:    return 'Full Mix';
      case StemType.keys:    return 'Keys';
      case StemType.bass:    return 'Bass';
      case StemType.crowd:   return 'Crowd';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AudioTrackSet — all audio stems for a song package
// ─────────────────────────────────────────────────────────────────────────────

/// Manages audio stem references for a song package.
///
/// Stems are stored as asset paths relative to the Flutter asset bundle.
/// All stems are expected to be OGG Vorbis files.
///
/// Usage:
/// ```dart
/// final audio = package.audio;
/// final backingPath = audio.primaryBackingPath; // for practicing drums
/// final drumsPath   = audio.stemPath(StemType.drums);
/// ```
class AudioTrackSet {
  /// Asset or local filesystem directory containing all stems.
  /// • Asset path:  'assets/songs/aun_coda'  (Flutter bundle)
  /// • Local path:  '/data/.../song_cache/aun_coda'  (downloaded from Storage)
  final String packageDir;

  /// Map from StemType to filename within [packageDir].
  final Map<StemType, String> stems;

  /// True when [packageDir] is a local filesystem path (downloaded from Storage).
  /// False when it is a Flutter asset bundle path.
  /// [BackingTrackService] uses this flag to choose setFilePath() vs setAsset().
  final bool isLocal;

  const AudioTrackSet({
    required this.packageDir,
    required this.stems,
    this.isLocal = false,
  });

  // ── Path access ─────────────────────────────────────────────────────────────

  /// Returns the full asset path for a stem, or null if not available.
  String? stemPath(StemType type) {
    final filename = stems[type];
    if (filename == null) return null;
    return '$packageDir/$filename';
  }

  /// True if this stem type is available.
  bool has(StemType type) => stems.containsKey(type);

  /// All available stem types.
  List<StemType> get availableStems => stems.keys.toList();

  // ── Backing track logic ──────────────────────────────────────────────────────

  /// Returns the full-mix path (song.ogg) when available, or null.
  ///
  /// A non-null value signals [BackingTrackService] to use single-player mode.
  /// A null value signals multi-stem mode: [BackingTrackService] plays all
  /// stems in [backingPaths] simultaneously for a complete backing mix.
  String? get primaryBackingPath => stemPath(StemType.song);

  /// All non-drum stem paths (for mixed backing when multi-track playback
  /// is supported in the future).
  List<String> get backingPaths {
    return availableStems
        .where((t) => t != StemType.drums && t != StemType.crowd)
        .map((t) => stemPath(t)!)
        .toList();
  }

  /// Drum stem path (for "drum-only" reference playback or muting).
  String? get drumsPath => stemPath(StemType.drums);

  @override
  String toString() {
    final names = stems.entries.map((e) => '${e.key.name}=${e.value}').join(', ');
    return 'AudioTrackSet($packageDir, [$names])';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SongPackage — complete loaded representation of a song bundle
// ─────────────────────────────────────────────────────────────────────────────

/// The canonical internal representation of a fully-loaded song package.
///
/// Created by [SongPackageLoader.load()] and consumed by [PracticeEngine] and
/// [BackingTrackService].  All song data flows from here — no other component
/// may hold independent copies of chart, BPM, or stem paths.
///
/// The [song] entity is synthesized from package metadata and is compatible
/// with the existing UI layer (catalog, HUD, session summary).
class SongPackage {
  /// The [Song] entity for this package — used by the UI and engine.
  final Song song;

  /// The drum chart as parsed NoteEvents, one per drum hit.
  /// Already sorted ascending by [NoteEvent.timeSeconds].
  final List<NoteEvent> chart;

  /// Single source of truth for timing: BPM, offsets, sections, beat grid.
  final SongSyncProfile syncProfile;

  /// Audio stems available for this package.
  final AudioTrackSet audio;

  /// True when the chart used the Clone Hero / RBN Expert note range (95–100).
  final bool isCloneHeroFormat;

  const SongPackage({
    required this.song,
    required this.chart,
    required this.syncProfile,
    required this.audio,
    this.isCloneHeroFormat = false,
  });

  // ── Convenience pass-throughs ─────────────────────────────────────────────

  String get id     => song.id;
  String get title  => song.title;
  String get artist => song.artist;

  /// Total note count in the chart.
  int get noteCount => chart.length;

  /// Duration as reported by the last note event.
  Duration get chartDuration => song.duration;

  @override
  String toString() =>
      'SongPackage($id, ${chart.length} notes, ${syncProfile.bpm.toStringAsFixed(1)} BPM)';
}
