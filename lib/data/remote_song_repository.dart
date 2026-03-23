// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Remote Song Repository
//
// Fetches song catalog from Firestore and downloads song packages from
// Firebase Storage to the local device cache.
//
// Firestore collection: "songs"
// Document fields:
//   title             String   — display title
//   artist            String
//   genre             String   — matches Genre enum name (rock, pop, cristiana…)
//   difficulty        String   — beginner | intermediate | advanced | expert
//   bpm               int
//   durationSeconds   int
//   storageFolderPath String   — Firebase Storage dir, e.g. "songs/Coda - Aún"
//   isPremium         bool     — if true, isUnlocked = false
//   xpReward          int
//   requiredLevel     int
//   techniqueTag      String?  — e.g. "Pro Drums"
//   description       String?
//   order             int      — sort order in the library
//   version           int      — increment to force re-download on clients
//
// Firebase Storage layout:
//   songs/
//     Coda - Aún/
//       song.ini
//       notes.mid
//       guitar.ogg
//       drums.ogg
//       rhythm.ogg
//       vocals.ogg
//       bass.ogg
//       song.ogg
//       crowd.ogg
//       keys.ogg
//       album.png    ← optional cover art
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../domain/entities/entities.dart';
import 'models/firestore_models.dart';
import 'song_cache_service.dart';

class RemoteSongRepository {
  static final RemoteSongRepository instance = RemoteSongRepository._();
  RemoteSongRepository._();

  static const _kCollection = 'Songs';

  /// All files we try to download from each Storage folder.
  /// Files not present are silently skipped — never a crash.
  static const _kKnownFiles = [
    'song.ini',
    'notes.mid',
    'drums.ogg',
    'guitar.ogg',
    'rhythm.ogg',
    'vocals.ogg',
    'bass.ogg',
    'song.ogg',
    'crowd.ogg',
    'keys.ogg',
    'album.png',
  ];

  final _db      = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  // ── Catalog ────────────────────────────────────────────────────────────────

  /// Fetches the song catalog from Firestore.
  ///
  /// Returns songs as domain [Song] entities with:
  ///   • [Song.packageAssetDir] = local filesystem path  (if already cached)
  ///   • [Song.packageAssetDir] = Firebase Storage path  (if not yet cached)
  ///
  /// Returns an empty list if offline or if the collection is empty.
  Future<List<Song>> fetchCatalog() async {
    try {
      // Sin orderBy: evita excluir documentos que no tengan el campo 'order'.
      // La ordenación se realiza en Dart sobre los modelos antes de convertir.
      final snap = await _db
          .collection(_kCollection)
          .get(const GetOptions(source: Source.serverAndCache));

      debugPrint('[RemoteSongRepository] Raw docs received: ${snap.docs.length}');

      final cache  = SongCacheService.instance;
      final models = <SongModel>[];

      for (final doc in snap.docs) {
        try {
          models.add(SongModel.fromDoc(doc));
        } catch (e) {
          debugPrint('[RemoteSongRepository] Skip doc ${doc.id}: $e');
        }
      }

      // Ordenar por campo 'order'; documentos sin el campo tienen order=0
      models.sort((a, b) => a.order.compareTo(b.order));

      // Convertir a dominio, resolviendo la ruta local si ya está en caché
      final songs = <Song>[];
      for (final model in models) {
        String? localPath;
        if (model.storageFolderPath.isNotEmpty &&
            await cache.isDownloaded(model.id)) {
          localPath = await cache.localDir(model.id);
        }
        songs.add(model.toDomain(localCachePath: localPath));
      }

      debugPrint('[RemoteSongRepository] Fetched ${songs.length} songs from Firestore');
      return songs;
    } catch (e, st) {
      debugPrint('[RemoteSongRepository] fetchCatalog error: $e');
      debugPrint('[RemoteSongRepository] stacktrace: $st');
      return [];
    }
  }

  // ── Download ───────────────────────────────────────────────────────────────

  /// Downloads all known files from [storageFolderPath] in Firebase Storage
  /// into [localDir] on the device.
  ///
  /// • Skips files not found in Storage (no crash).
  /// • [onProgress] receives values from 0.0 to 1.0 as files complete.
  /// • Throws on critical failure (notes.mid missing after download attempt).
  Future<void> downloadSong({
    required String songId,
    required String storageFolderPath,
    required String localDir,
    void Function(double progress)? onProgress,
  }) async {
    debugPrint('[RemoteSongRepository] Downloading $songId from $storageFolderPath → $localDir');

    // Ensure the local directory exists before writing any file
    await Directory(localDir).create(recursive: true);

    final folderRef  = _storage.ref(storageFolderPath);
    int   done       = 0;
    int   downloaded = 0;
    int   skipped    = 0;
    final errors     = <String>[];

    for (final filename in _kKnownFiles) {
      try {
        final fileRef   = folderRef.child(filename);
        final localFile = File('$localDir/$filename');
        await fileRef.writeToFile(localFile).timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw TimeoutException(
            'Timeout al descargar $filename (60 s). '
            'Verifica tu conexión o las reglas de Firebase Storage.',
          ),
        );
        downloaded++;
        debugPrint('[RemoteSongRepository] ✓ $filename');
      } catch (e) {
        // Optional stems that don't exist in Storage → silent skip.
        // Permission errors / network errors → logged so we can diagnose.
        skipped++;
        errors.add('$filename: $e');
        debugPrint('[RemoteSongRepository] ✗ $filename — $e');
      }
      done++;
      onProgress?.call(done / _kKnownFiles.length);
    }

    debugPrint('[RemoteSongRepository] done=$done downloaded=$downloaded skipped=$skipped');

    // Verify the critical file landed on disk
    if (!File('$localDir/notes.mid').existsSync()) {
      final detail = errors.isNotEmpty ? errors.first : 'unknown error';
      throw Exception(
        'notes.mid missing after download of "$songId". '
        'First error: $detail. '
        'Check Firebase Storage security rules at '
        'Firebase Console → Storage → Rules.',
      );
    }

    debugPrint('[RemoteSongRepository] Download complete: $songId');
  }

  // ── Auth helper ────────────────────────────────────────────────────────────

  /// Garantiza que existe un usuario autenticado (anónimo si es necesario)
  /// para que Firebase Storage pueda adjuntar un token válido a las descargas.
  // ignore: unused_element
  Future<void> _ensureAuth() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[RemoteSongRepository] No user — signing in anonymously...');
        await FirebaseAuth.instance.signInAnonymously();
        debugPrint('[RemoteSongRepository] Anonymous sign-in OK');
      } else {
        debugPrint('[RemoteSongRepository] Auth OK: ${user.uid} (anonymous: ${user.isAnonymous})');
      }
    } catch (e) {
      // Si el sign-in anónimo falla, intentamos la descarga de todas formas.
      // Funcionará si las reglas de Storage permiten lectura pública (if true).
      debugPrint('[RemoteSongRepository] Auth warning (will try anyway): $e');
    }
  }

  // ── Version check ──────────────────────────────────────────────────────────

  /// Returns the remote version for [songId], or 0 if unavailable.
  /// Compare with [SongCacheService.cachedVersion] to detect stale caches.
  Future<int> remoteVersion(String songId) async {
    try {
      final doc = await _db.collection(_kCollection).doc(songId).get();
      return (doc.data()?['version'] as num?)?.toInt() ?? 1;
    } catch (_) {
      return 0;
    }
  }
}
