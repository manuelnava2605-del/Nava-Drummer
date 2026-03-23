// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Song Loader
//
// Single entry point for loading the song catalog at runtime.
//
// Strategy (in order):
//   1. Firestore — fetchCatalog() from RemoteSongRepository.
//      Songs with storageFolderPath are "remote packages" that must be
//      downloaded before practice. Already-cached songs get their local path
//      resolved automatically by RemoteSongRepository.
//
//   2. Local manifest fallback — assets/songs/songs_manifest.json.
//      Used when offline or when Firestore returns nothing.
//      Songs here have packageAssetDir = 'assets/songs/...' (bundled).
//
// The caller (SongLibraryScreen) does not need to know which source was used.
// The distinction between remote/bundled/local-cached is encoded in Song fields:
//   • song.isRemoteSong  → needs download (Storage path)
//   • song.isLocalFile   → already cached (filesystem path)
//   • neither            → bundled asset (always available)
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:convert';
import 'package:flutter/services.dart';
import '../domain/entities/entities.dart';
import 'remote_song_repository.dart';

class SongLoader {
  // ── Public API ─────────────────────────────────────────────────────────────

  /// Load the full song catalog.
  ///
  /// Tries Firestore first; falls back to the bundled manifest if Firestore
  /// returns nothing or an error occurs.
  static Future<List<Song>> loadSongs() async {
    // 1. Try remote catalog
    final remoteSongs = await RemoteSongRepository.instance.fetchCatalog();
    if (remoteSongs.isNotEmpty) return remoteSongs;

    // 2. Fall back to local manifest
    return _loadFromManifest();
  }

  // ── Manifest fallback ──────────────────────────────────────────────────────

  static Future<List<Song>> _loadFromManifest() async {
    try {
      final manifestStr =
          await rootBundle.loadString('assets/songs/songs_manifest.json');
      final data = json.decode(manifestStr) as Map<String, dynamic>;
      final list = (data['songs'] as List).cast<String>();

      final songs = <Song>[];
      for (final path in list) {
        final song = await _loadSongFromIni(path);
        if (song != null) songs.add(song);
      }
      return songs;
    } catch (_) {
      return [];
    }
  }

  static Future<Song?> _loadSongFromIni(String dir) async {
    try {
      final iniStr = await rootBundle.loadString('$dir/song.ini');
      final map    = _parseIni(iniStr);

      final id      = dir.split('/').last;
      final bpm     = int.tryParse(map['bpm'] ?? '') ?? 120;
      final lengthMs = int.tryParse(map['song_length'] ?? '');
      final duration = lengthMs != null
          ? Duration(milliseconds: lengthMs)
          : const Duration(minutes: 3);

      return Song(
        id:             id,
        title:          map['name']   ?? id,
        artist:         map['artist'] ?? 'Unknown',
        difficulty:     _parseDifficulty(map['diff_drums'] ?? map['difficulty']),
        genre:          _parseGenre(map['genre']),
        bpm:            bpm,
        duration:       duration,
        packageAssetDir: dir,   // bundled asset path
        midiAssetPath:  '',
        isUnlocked:     true,
        xpReward:       200,
        description:    map['loading_phrase'] ?? 'Auto-loaded song',
        techniqueTag:   map['pro_drums']?.toLowerCase() == 'true'
            ? 'Pro Drums'
            : map['charter'],
      );
    } catch (_) {
      return null;
    }
  }

  // ── INI parser ─────────────────────────────────────────────────────────────

  static Map<String, String> _parseIni(String content) {
    final map = <String, String>{};
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('[') || !trimmed.contains('=')) continue;
      final idx = trimmed.indexOf('=');
      final key = trimmed.substring(0, idx).trim().toLowerCase();
      final val = trimmed.substring(idx + 1).trim();
      if (key.isNotEmpty) map[key] = val;
    }
    return map;
  }

  // ── Mapping helpers ────────────────────────────────────────────────────────

  static Difficulty _parseDifficulty(String? raw) {
    if (raw == null) return Difficulty.intermediate;
    final v = int.tryParse(raw);
    if (v != null) {
      if (v <= 2) return Difficulty.beginner;
      if (v <= 4) return Difficulty.intermediate;
      if (v <= 6) return Difficulty.advanced;
      return Difficulty.expert;
    }
    switch (raw.toLowerCase()) {
      case 'easy':
      case 'beginner':      return Difficulty.beginner;
      case 'medium':
      case 'intermediate':  return Difficulty.intermediate;
      case 'hard':
      case 'advanced':      return Difficulty.advanced;
      case 'expert':        return Difficulty.expert;
      default:              return Difficulty.intermediate;
    }
  }

  static Genre _parseGenre(String? raw) {
    if (raw == null) return Genre.rock;
    final lower = raw.toLowerCase();
    if (lower.contains('rock')     || lower.contains('metal'))    return Genre.rock;
    if (lower.contains('pop')      || lower.contains('wave'))     return Genre.pop;
    if (lower.contains('jazz'))                                    return Genre.jazz;
    if (lower.contains('funk'))                                    return Genre.funk;
    if (lower.contains('latin')    || lower.contains('latino'))   return Genre.latin;
    if (lower.contains('cristiana')|| lower.contains('christian'))return Genre.cristiana;
    return Genre.rock;
  }
}
