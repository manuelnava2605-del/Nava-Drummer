// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Song Cache Service
//
// Manages the local on-device cache for songs downloaded from Firebase Storage.
//
// Layout on device:
//   {documentsDir}/song_cache/{songId}/
//     song.ini
//     notes.mid
//     guitar.ogg  (or whichever stems exist)
//     ...
//
// SharedPreferences keys:
//   song_cache_v_{songId}  →  int version (0 = not downloaded)
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SongCacheService {
  static final SongCacheService instance = SongCacheService._();
  SongCacheService._();

  static const _kVersionPrefix = 'song_cache_v_';

  // ── Local directory ────────────────────────────────────────────────────────

  /// Returns the local filesystem directory for [songId].
  /// Creates it if it does not exist.
  Future<String> localDir(String songId) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir  = Directory('${docs.path}/song_cache/$songId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  // ── Download state ─────────────────────────────────────────────────────────

  /// Returns true if [songId] has been successfully downloaded and the
  /// critical file (notes.mid) still exists on disk.
  Future<bool> isDownloaded(String songId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getInt('$_kVersionPrefix$songId') ?? 0) <= 0) return false;
      final dir = await localDir(songId);
      return File('$dir/notes.mid').existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Marks [songId] as fully downloaded at [version].
  Future<void> markDownloaded(String songId, {int version = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_kVersionPrefix$songId', version);
    debugPrint('[SongCacheService] Marked downloaded: $songId v$version');
  }

  /// Returns the cached version number for [songId], or 0 if not downloaded.
  Future<int> cachedVersion(String songId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_kVersionPrefix$songId') ?? 0;
  }

  // ── Cache management ───────────────────────────────────────────────────────

  /// Deletes all cached files for [songId] and resets its download state.
  Future<void> clearSong(String songId) async {
    try {
      final dir = Directory(await localDir(songId));
      if (await dir.exists()) await dir.delete(recursive: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_kVersionPrefix$songId');
      debugPrint('[SongCacheService] Cleared: $songId');
    } catch (e) {
      debugPrint('[SongCacheService] Error clearing $songId: $e');
    }
  }

  /// Deletes ALL cached songs. Call from a settings/debug screen.
  Future<void> clearAll() async {
    try {
      final docs  = await getApplicationDocumentsDirectory();
      final root  = Directory('${docs.path}/song_cache');
      if (await root.exists()) await root.delete(recursive: true);
      final prefs = await SharedPreferences.getInstance();
      final keys  = prefs.getKeys().where((k) => k.startsWith(_kVersionPrefix));
      for (final k in keys) { await prefs.remove(k); }
      debugPrint('[SongCacheService] All cache cleared');
    } catch (e) {
      debugPrint('[SongCacheService] Error clearing all: $e');
    }
  }

  /// Total size in bytes of all cached song files.
  Future<int> totalSizeBytes() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final root = Directory('${docs.path}/song_cache');
      if (!await root.exists()) return 0;
      int total = 0;
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}
