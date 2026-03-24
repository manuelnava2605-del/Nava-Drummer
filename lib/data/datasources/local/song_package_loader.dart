// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Song Package Loader
//
// Converts a MIDI-only song bundle (notes.mid + optional OGG stems)
// into a fully-loaded SongPackage ready for PracticeEngine and UI.
//
// Pipeline:
//   1. Parse notes.mid  → List<NoteEvent> using GM standard mapping
//   2. Read song.ini    → optional metadata (title/artist/delay) — graceful
//                         fallback to MIDI-derived values if file is absent
//   3. Derive SongSyncProfile from MIDI tempo map + optional ini delay
//   4. Scan OGG stems   → AudioTrackSet (song.ogg / guitar.ogg / vocals.ogg …)
//   5. Build Song entity → SongPackage
//
// Clone Hero / Rock Band Network format is NOT supported. All charts must
// use the GM percussion standard (channel 9, note numbers 35–81).
// OGG stems are kept for future vocal / backing-track support.
//
// Single entry point: SongPackageLoader.load(packageDir)
//
// Path routing (automatic — callers do not need to know):
//   'assets/songs/...'  → Flutter asset bundle  (rootBundle)
//   '/data/...'         → Local filesystem       (dart:io File)
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';
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

class SongPackageLoader {
  SongPackageLoader._();

  // ── Known OGG stem filenames ────────────────────────────────────────────────
  static const Map<StemType, List<String>> _stemCandidates = {
    StemType.song:   ['song.ogg',    'mix.ogg',   'preview.ogg'],
    StemType.vocals: ['vocals.ogg',  'vocal.ogg'],
    StemType.guitar: ['guitar.ogg',  'lead.ogg'],
    StemType.rhythm: ['rhythm.ogg',  'rhytm.ogg'],
    StemType.bass:   ['bass.ogg'],
    StemType.keys:   ['keys.ogg',    'keyboard.ogg'],
    StemType.drums:  ['drums.ogg',   'drum.ogg'],
    StemType.crowd:  ['crowd.ogg'],
  };

  // ── Public API ──────────────────────────────────────────────────────────────

  static bool _isLocalPath(String packageDir) => packageDir.startsWith('/');

  /// Load and parse a complete song package from [packageDir].
  ///
  /// Accepts both Flutter asset paths ('assets/songs/foo') and
  /// absolute local filesystem paths ('/data/.../song_cache/foo').
  ///
  /// Throws [SongPackageLoadException] if notes.mid is missing or empty.
  static Future<SongPackage> load(String packageDir) async {
    // ── Step 1: Load song.ini (optional — metadata only) ─────────────────────
    SongIni? ini;
    try {
      ini = await _loadIni(packageDir);
      debugPrint('[SongPackageLoader] ini: ${ini.name} — ${ini.artist}');
    } catch (_) {
      debugPrint('[SongPackageLoader] No song.ini found — using MIDI-derived metadata');
    }

    // ── Step 2: Parse notes.mid with GM mapping ───────────────────────────────
    final ByteData midiBytes;
    try {
      midiBytes = await _loadMidiBytes(packageDir);
    } catch (e) {
      throw SongPackageLoadException(
        'Cannot read notes.mid at $packageDir: $e',
      );
    }

    final parser     = MidiFileParser();
    final gmMapping  = DrumMapping(
      deviceId: 'gm',
      noteMap:  StandardDrumMaps.generalMidi,
    );
    final midiResult = parser.parse(midiBytes.buffer.asUint8List(), gmMapping);
    final chart      = midiResult.noteEvents;

    if (chart.isEmpty) {
      throw SongPackageLoadException(
        'No playable GM drum notes found in $packageDir/notes.mid. '
        'Ensure the file uses channel 9 and standard GM note numbers (35–81).',
      );
    }

    debugPrint('[SongPackageLoader] GM chart: ${chart.length} notes, '
        'first=${chart.first.timeSeconds.toStringAsFixed(3)}s');

    // ── Step 3: Derive SyncProfile ────────────────────────────────────────────
    final syncProfile = _buildSyncProfile(
      ini:        ini,
      midiResult: midiResult,
      songId:     _songIdFromDir(packageDir),
    );

    debugPrint('[SongPackageLoader] SyncProfile: '
        'BPM=${syncProfile.bpm.toStringAsFixed(1)}, '
        'chartOffset=${syncProfile.chartOffsetSeconds.toStringAsFixed(3)}s, '
        'timeSig=${syncProfile.timeSignature}');

    // ── Step 4: Scan OGG stems ────────────────────────────────────────────────
    final audio = await _buildAudioTrackSet(packageDir);
    debugPrint('[SongPackageLoader] Stems: '
        '${audio.availableStems.map((s) => s.name).join(', ')}');

    // ── Step 5: Build Song entity ─────────────────────────────────────────────
    final song = _buildSong(ini, midiResult, syncProfile, packageDir, audio);

    return SongPackage(
      song:        song,
      chart:       chart,
      syncProfile: syncProfile,
      audio:       audio,
    );
  }

  // ── Source-agnostic file loaders ────────────────────────────────────────────

  static Future<SongIni> _loadIni(String packageDir) async {
    final text = _isLocalPath(packageDir)
        ? await File('$packageDir/song.ini').readAsString()
        : await rootBundle.loadString('$packageDir/song.ini');
    return SongIniParser.parse(text);
  }

  static Future<ByteData> _loadMidiBytes(String packageDir) async {
    if (_isLocalPath(packageDir)) {
      final bytes = await File('$packageDir/notes.mid').readAsBytes();
      return bytes.buffer.asByteData();
    }
    return rootBundle.load('$packageDir/notes.mid');
  }

  // ── SyncProfile builder ────────────────────────────────────────────────────

  static SongSyncProfile _buildSyncProfile({
    required SongIni?        ini,
    required MidiParseResult midiResult,
    required String          songId,
  }) {
    final bpm        = midiResult.bpm > 0 ? midiResult.bpm : 120.0;
    final timeSig    = '${midiResult.timeSignature.numerator}/'
                       '${midiResult.timeSignature.denominator}';
    final bpb        = _beatsPerBar(midiResult.timeSignature.numerator,
                                    midiResult.timeSignature.denominator);
    final subs       = _subdivisions(midiResult.timeSignature.numerator,
                                     midiResult.timeSignature.denominator);
    final delayMs    = ini?.delayMs ?? 0;
    final chartOff   = (delayMs / 1000.0).clamp(0.0, double.infinity);
    final songLenSec = (ini?.songLengthMs ?? 0) > 0
        ? ini!.songLengthMs / 1000.0
        : midiResult.totalDuration.inMilliseconds / 1000.0;

    return SongSyncProfile(
      songId:             songId,
      bpm:                bpm,
      timeSignature:      timeSig,
      beatsPerBar:        bpb,
      subdivisions:       subs,
      audioOffsetSeconds: 0.0,
      chartOffsetSeconds: chartOff,
      songLengthSeconds:  songLenSec,
      notes: 'Auto-derived from MIDI. '
             'BPM=$bpm, timeSig=$timeSig, '
             'chartOffset=${chartOff.toStringAsFixed(3)}s (delayMs=$delayMs).',
    );
  }

  // ── AudioTrackSet scanner ─────────────────────────────────────────────────

  static Future<AudioTrackSet> _buildAudioTrackSet(String packageDir) async {
    final isLocal = _isLocalPath(packageDir);
    final found   = <StemType, String>{};

    for (final entry in _stemCandidates.entries) {
      for (final filename in entry.value) {
        final path   = '$packageDir/$filename';
        final exists = isLocal
            ? File(path).existsSync()
            : await _assetExists(path);
        if (exists) {
          found[entry.key] = filename;
          break;
        }
      }
    }

    if (found.isEmpty) {
      debugPrint('[SongPackageLoader] ⚠ No OGG stems in $packageDir — '
          'MIDI-only mode (synth will render full mix).');
    }

    return AudioTrackSet(packageDir: packageDir, stems: found, isLocal: isLocal);
  }

  static Future<bool> _assetExists(String assetPath) async {
    try {
      await rootBundle.load(assetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Song entity builder ───────────────────────────────────────────────────

  static Song _buildSong(
    SongIni?         ini,
    MidiParseResult  midiResult,
    SongSyncProfile  syncProfile,
    String           packageDir,
    AudioTrackSet    audio,
  ) {
    final id    = _songIdFromDir(packageDir);
    final bpm   = syncProfile.bpm.round();
    final durMs = syncProfile.songLengthSeconds > 0
        ? (syncProfile.songLengthSeconds * 1000).round()
        : midiResult.totalDuration.inMilliseconds;

    return Song(
      id:              id,
      title:           ini?.name   ?? _titleFromId(id),
      artist:          ini?.artist ?? 'Unknown Artist',
      difficulty:      _mapDifficulty(ini?.diffDrums ?? -1),
      genre:           _mapGenre(ini?.genre ?? ''),
      bpm:             bpm,
      duration:        Duration(milliseconds: durMs),
      midiAssetPath:   '$packageDir/notes.mid',
      isUnlocked:      true,
      xpReward:        _calcXpReward(ini),
      description:     ini != null && ini.album.isNotEmpty
                         ? '${ini.album}${ini.year.isNotEmpty ? " (${ini.year})" : ""}'
                         : null,
      techniqueTag:    'Standard',
      genreLabel:      ini?.genre ?? '',
      timeSignature:   '${midiResult.timeSignature.numerator}/${midiResult.timeSignature.denominator}',
      beatsPerBar:     syncProfile.beatsPerBar,
      packageAssetDir: packageDir,
    );
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  static int _beatsPerBar(int num, int den) {
    if (den == 8 && num % 3 == 0) return num ~/ 3;
    return num;
  }

  static int _subdivisions(int num, int den) {
    if (den == 8 && num % 3 == 0) return 3;
    return 2;
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
    if (g.contains('gospel') || g.contains('worship') || g.contains('christian'))
      return Genre.cristiana;
    return Genre.rock;
  }

  static int _calcXpReward(SongIni? ini) {
    if (ini == null) return 100;
    final base = 100 + (ini.diffDrums.clamp(0, 6) * 25);
    return base;
  }

  static String _songIdFromDir(String packageDir) {
    final parts = packageDir.split('/');
    return parts.isNotEmpty ? parts.last : packageDir;
  }

  /// Converts a snake_case or kebab-case id to a human-readable title.
  /// e.g. 'aun_coda' → 'Aun Coda'
  static String _titleFromId(String id) {
    return id
        .replaceAll(RegExp(r'[_-]'), ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
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
