// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Song Package Loader
//
// Converts a Clone Hero / RBN song bundle (song.ini + notes.mid + stems)
// into a fully-loaded SongPackage ready for PracticeEngine and UI.
//
// Pipeline:
//   1. Read  song.ini        → SongIni (metadata + flags)
//   2. Parse notes.mid       → List<NoteEvent> (drum chart)
//   3. Derive SongSyncProfile from MIDI tempo map + song.ini delay
//   4. Scan available stems  → AudioTrackSet
//   5. Build Song entity     → SongPackage
//
// Single entry point: SongPackageLoader.load(packageAssetDir)
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../domain/entities/entities.dart';
import '../../../domain/entities/song_package.dart';
import '../../../core/song_sync_profile.dart';
import 'midi_file_parser.dart';
import 'song_ini_parser.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SongPackageLoader
// ─────────────────────────────────────────────────────────────────────────────

/// Loads a Clone Hero / RBN song bundle from the Flutter asset bundle.
///
/// Usage:
/// ```dart
/// final package = await SongPackageLoader.load('assets/songs/aun_coda');
/// await engine.loadSongPackage(package);
/// ```
class SongPackageLoader {
  SongPackageLoader._();

  // ── Known stem filenames ────────────────────────────────────────────────────
  static const Map<StemType, List<String>> _stemCandidates = {
    StemType.drums:   ['drums.ogg',   'drum.ogg'],
    StemType.guitar:  ['guitar.ogg',  'lead.ogg'],
    StemType.rhythm:  ['rhythm.ogg',  'bass.ogg', 'rhytm.ogg'],
    StemType.vocals:  ['vocals.ogg',  'vocal.ogg', 'song.ogg'],
    StemType.song:    ['song.ogg',    'mix.ogg',  'preview.ogg'],
    StemType.keys:    ['keys.ogg',    'keyboard.ogg'],
    StemType.bass:    ['bass.ogg'],
    StemType.crowd:   ['crowd.ogg'],
  };

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Load and parse a complete song package from [packageAssetDir].
  ///
  /// [packageAssetDir] must be a Flutter asset path without trailing slash,
  /// e.g. 'assets/songs/aun_coda'.
  ///
  /// Throws [SongPackageLoadException] if the package is invalid.
  static Future<SongPackage> load(String packageAssetDir) async {
    // ── Step 1: Parse song.ini ────────────────────────────────────────────────
    final ini = await _loadIni(packageAssetDir);
    debugPrint('[SongPackageLoader] Loaded ini: $ini');

    // ── Step 2: Detect drum mapping format from ini flags ────────────────────
    //   • pro_drums = True + diff_drums_real >= 0 → Clone Hero Expert (95–100)
    //   • diff_drums >= 0 only                    → Clone Hero Easy (60–64)
    //   • Neither                                 → GM fallback (35–81)
    final isProDrums   = ini.isProDrums && ini.diffDrumsReal >= 0;
    final hasAnyDrums  = ini.diffDrums >= 0 || ini.diffDrumsReal >= 0;

    // ── Step 3: Parse notes.mid ───────────────────────────────────────────────
    final midiBytes = await rootBundle.load('$packageAssetDir/notes.mid');
    final parser    = MidiFileParser();

    // Try to parse with Clone Hero Expert mapping first if flagged as pro drums.
    // Fall back to Easy → GM if the expert parse yields no notes.
    List<NoteEvent> chart = const [];
    bool isCloneHero = false;

    if (hasAnyDrums) {
      if (isProDrums) {
        chart = _parse(midiBytes, packageAssetDir, StandardDrumMaps.cloneHeroExpert, parser);
        if (chart.isNotEmpty) {
          isCloneHero = true;
          debugPrint('[SongPackageLoader] Using Clone Hero Expert mapping → ${chart.length} notes');
        }
      }
      if (chart.isEmpty) {
        chart = _parse(midiBytes, packageAssetDir, StandardDrumMaps.cloneHeroEasy, parser);
        if (chart.isNotEmpty) {
          isCloneHero = true;
          debugPrint('[SongPackageLoader] Using Clone Hero Easy mapping → ${chart.length} notes');
        }
      }
    }
    if (chart.isEmpty) {
      chart = _parse(midiBytes, packageAssetDir, StandardDrumMaps.generalMidi, parser);
      debugPrint('[SongPackageLoader] Using GM fallback mapping → ${chart.length} notes');
    }

    if (chart.isEmpty) {
      throw SongPackageLoadException(
        'notes.mid at $packageAssetDir produced no drum events. '
        'Check drum mapping or MIDI format.',
      );
    }

    // Re-parse to get MidiParseResult (BPM, time sig) regardless of mapping path
    final midiResult = parser.parse(
      midiBytes.buffer.asUint8List(),
      DrumMapping(
        deviceId: isCloneHero ? 'clone_hero' : 'gm',
        noteMap: isCloneHero
            ? (isProDrums ? StandardDrumMaps.cloneHeroExpert : StandardDrumMaps.cloneHeroEasy)
            : StandardDrumMaps.generalMidi,
      ),
    );

    // ── Step 4: Dedup co-incident pro cymbal marker notes ────────────────────
    // Clone Hero Expert pro drums emit both a base note (97-100) AND a cymbal
    // marker note (110-112) at the same tick. Both map to drum pads, which
    // would produce double hits. Deduplicate by dropping extra events at the
    // same tick that have the same pad.
    final dedupedChart = isCloneHero ? _deduplicateCoincidentNotes(chart) : chart;

    debugPrint('[SongPackageLoader] After dedup: ${dedupedChart.length} notes '
        '(removed ${chart.length - dedupedChart.length} duplicates)');

    // ── Step 5: Derive SyncProfile from MIDI + ini ───────────────────────────
    final syncProfile = _buildSyncProfile(
      ini:        ini,
      midiResult: midiResult,
      songId:     _songIdFromDir(packageAssetDir),
    );

    debugPrint('[SongPackageLoader] SyncProfile: BPM=${syncProfile.bpm.toStringAsFixed(1)}, '
        'chartOffset=${syncProfile.chartOffsetSeconds.toStringAsFixed(3)}s, '
        'timeSig=${syncProfile.timeSignature}');

    // ── Step 6: Scan available audio stems ───────────────────────────────────
    final audio = await _buildAudioTrackSet(packageAssetDir);
    debugPrint('[SongPackageLoader] Stems: ${audio.availableStems.map((s) => s.name).join(', ')}');

    // ── Step 7: Build Song entity ────────────────────────────────────────────
    final song = _buildSong(ini, midiResult, syncProfile, packageAssetDir, audio);

    return SongPackage(
      song:              song,
      chart:             dedupedChart,
      syncProfile:       syncProfile,
      audio:             audio,
      isCloneHeroFormat: isCloneHero,
    );
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  /// Quick-parse MIDI with a given drum mapping; returns the note events.
  static List<NoteEvent> _parse(
    ByteData midiBytes,
    String packageDir,
    Map<int, DrumPad> noteMap,
    MidiFileParser parser,
  ) {
    try {
      final result = parser.parse(
        midiBytes.buffer.asUint8List(),
        DrumMapping(deviceId: 'probe', noteMap: noteMap),
      );
      return result.noteEvents;
    } catch (e) {
      debugPrint('[SongPackageLoader] Parse error with mapping: $e');
      return const [];
    }
  }

  /// Load and parse song.ini from the package directory.
  static Future<SongIni> _loadIni(String packageDir) async {
    try {
      final text = await rootBundle.loadString('$packageDir/song.ini');
      return SongIniParser.parse(text);
    } catch (e) {
      throw SongPackageLoadException('Cannot read song.ini at $packageDir: $e');
    }
  }

  /// Build [SongSyncProfile] from MIDI data and ini metadata.
  ///
  /// For Clone Hero / RBN packages:
  /// • BPM comes from the MIDI tempo map (authoritative)
  /// • Time signature from MIDI meta events
  /// • Chart offset = time of first note (some packages have a count-in gap)
  /// • Audio offset = 0 (OGG files have no AAC encoder delay)
  /// • delay in song.ini shifts the chart start (positive = chart is later)
  static SongSyncProfile _buildSyncProfile({
    required SongIni ini,
    required MidiParseResult midiResult,
    required String songId,
  }) {
    // BPM from MIDI tempo map
    final bpmFromMidi = midiResult.bpm;
    final bpm         = bpmFromMidi > 0 ? bpmFromMidi : 120.0;

    // Time signature
    final timeSig    = '${midiResult.timeSignature.numerator}/${midiResult.timeSignature.denominator}';
    final beatsPerBar = _beatsPerBar(midiResult.timeSignature.numerator,
                                     midiResult.timeSignature.denominator);
    final subdivisions = _subdivisions(midiResult.timeSignature.numerator,
                                       midiResult.timeSignature.denominator);

    // Chart offset = time of first note (count-in gap before music starts)
    // Adjusted by ini.delayMs (milliseconds, can be negative)
    final firstNoteSeconds = midiResult.noteEvents.isNotEmpty
        ? midiResult.noteEvents.first.timeSeconds
        : 0.0;
    final delaySeconds      = ini.delayMs / 1000.0;
    final chartOffsetSec    = (firstNoteSeconds + delaySeconds).clamp(0.0, double.infinity);

    // OGG files do not have AAC encoder delay → audioOffsetSeconds = 0
    const audioOffsetSec = 0.0;

    // Song length from ini (in ms) → used for display and engine stop condition
    final songLengthSec = ini.songLengthMs > 0
        ? ini.songLengthMs / 1000.0
        : (midiResult.totalDuration.inMilliseconds / 1000.0);

    return SongSyncProfile(
      songId:               songId,
      bpm:                  bpm,
      timeSignature:        timeSig,
      beatsPerBar:          beatsPerBar,
      subdivisions:         subdivisions,
      audioOffsetSeconds:   audioOffsetSec,
      chartOffsetSeconds:   chartOffsetSec,
      songLengthSeconds:    songLengthSec,
      notes: 'Auto-derived from ${ini.name} by ${ini.artist}. '
             'BPM=$bpm (from MIDI), timeSig=$timeSig, '
             'chartOffset=${chartOffsetSec.toStringAsFixed(3)}s, '
             'delay=${ini.delayMs}ms.',
    );
  }

  /// Scan the package directory for known stem filenames.
  /// Uses [rootBundle.load] with a try/catch to detect presence without
  /// loading the full audio file (just checks if asset exists).
  static Future<AudioTrackSet> _buildAudioTrackSet(String packageDir) async {
    final found = <StemType, String>{};
    for (final entry in _stemCandidates.entries) {
      for (final filename in entry.value) {
        final path = '$packageDir/$filename';
        try {
          // Check if the asset exists by attempting a small load.
          // We only need to verify existence, not read the whole file.
          await rootBundle.load(path);
          found[entry.key] = filename;
          break; // found this stem, move on to next
        } catch (_) {
          // Asset not present — try next candidate
        }
      }
    }
    return AudioTrackSet(packageDir: packageDir, stems: found);
  }

  /// Build the [Song] entity from package metadata.
  static Song _buildSong(
    SongIni ini,
    MidiParseResult midiResult,
    SongSyncProfile syncProfile,
    String packageAssetDir,
    AudioTrackSet audio,
  ) {
    final id        = _songIdFromDir(packageAssetDir);
    final bpm       = syncProfile.bpm.round();
    final durMs     = syncProfile.songLengthSeconds > 0
        ? (syncProfile.songLengthSeconds * 1000).round()
        : midiResult.totalDuration.inMilliseconds;
    final difficulty = _mapDifficulty(ini.diffDrums);
    final genre      = _mapGenre(ini.genre);

    return Song(
      id:             id,
      title:          ini.name,
      artist:         ini.artist,
      difficulty:     difficulty,
      genre:          genre,
      bpm:            bpm,
      duration:       Duration(milliseconds: durMs),
      midiAssetPath:  '$packageAssetDir/notes.mid',
      isUnlocked:     true,
      xpReward:       _calcXpReward(ini),
      description:    ini.album.isNotEmpty ? '${ini.album}${ini.year.isNotEmpty ? " (${ini.year})" : ""}' : null,
      techniqueTag:   ini.isProDrums ? 'Pro Drums' : 'Standard',
      genreLabel:     ini.genre,
      timeSignature:  '${midiResult.timeSignature.numerator}/${midiResult.timeSignature.denominator}',
      beatsPerBar:    syncProfile.beatsPerBar,
      packageAssetDir: packageAssetDir,
    );
  }

  // ── Deduplication ────────────────────────────────────────────────────────────

  /// Remove duplicate NoteEvents that occur at the same tick.
  ///
  /// In Clone Hero pro drums, base notes (97-100) and cymbal markers (110-112)
  /// both fire at the same tick and map to the same (or very similar) DrumPad.
  /// We keep only the first event per pad per tick (within ±1ms tolerance).
  static List<NoteEvent> _deduplicateCoincidentNotes(List<NoteEvent> notes) {
    const kWindowMs = 2.0; // notes within 2ms are "simultaneous"
    final result    = <NoteEvent>[];

    for (final note in notes) {
      final isRedundant = result.any((existing) =>
          existing.pad == note.pad &&
          (existing.timeSeconds - note.timeSeconds).abs() * 1000 < kWindowMs);
      if (!isRedundant) result.add(note);
    }

    result.sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
    return result;
  }

  // ── Mapping utilities ─────────────────────────────────────────────────────

  static int _beatsPerBar(int numerator, int denominator) {
    // For compound time signatures (6/8, 12/8, 9/8), primary beats are groups
    if (denominator == 8 && numerator % 3 == 0) return numerator ~/ 3;
    return numerator; // simple: beats per bar = numerator
  }

  static int _subdivisions(int numerator, int denominator) {
    // Compound time: 3 eighth notes per beat (dotted quarter)
    if (denominator == 8 && numerator % 3 == 0) return 3;
    return 2; // simple: 2 eighth notes per quarter beat
  }

  static Difficulty _mapDifficulty(int stars) {
    if (stars <= 1) return Difficulty.beginner;
    if (stars <= 2) return Difficulty.intermediate;
    if (stars <= 4) return Difficulty.advanced;
    return Difficulty.expert;
  }

  static Genre _mapGenre(String genre) {
    final g = genre.toLowerCase();
    if (g.contains('metal') || g.contains('rock')) return Genre.rock;
    if (g.contains('jazz'))                         return Genre.jazz;
    if (g.contains('funk'))                         return Genre.funk;
    if (g.contains('pop'))                          return Genre.pop;
    if (g.contains('latin'))                        return Genre.latin;
    if (g.contains('electronic'))                   return Genre.electronic;
    if (g.contains('gospel') || g.contains('worship') || g.contains('christian')) return Genre.cristiana;
    return Genre.rock;
  }

  static int _calcXpReward(SongIni ini) {
    // Base 100 XP, scaled by difficulty and pro drums
    final base = 100 + ((ini.diffDrums.clamp(0, 6)) * 25);
    return ini.isProDrums ? (base * 1.5).round() : base;
  }

  static String _songIdFromDir(String packageAssetDir) {
    // 'assets/songs/aun_coda' → 'aun_coda'
    final parts = packageAssetDir.split('/');
    return parts.isNotEmpty ? parts.last : packageAssetDir;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SongPackageLoadException
// ─────────────────────────────────────────────────────────────────────────────
class SongPackageLoadException implements Exception {
  final String message;
  const SongPackageLoadException(this.message);
  @override String toString() => 'SongPackageLoadException: $message';
}
