// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Backing Track Service
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../domain/entities/entities.dart';
import '../domain/entities/song_package.dart';

enum BackingTrackState {
  idle,
  loading,
  ready,
  playing,
  paused,
  error,
  noTrack,
}

class BackingTrackService {
  static final BackingTrackService instance = BackingTrackService._();
  BackingTrackService._();

  // Single-stem player (song.ogg when present).
  final AudioPlayer _player = AudioPlayer();

  // Multi-stem players — one per non-drum stem, all kept in lock-step.
  final List<AudioPlayer> _stemPlayers = [];
  bool _isMultiStem = false;

  BackingTrackState _state       = BackingTrackState.idle;
  Song?             _song;
  double            _volume      = 0.85;
  double            _tempoFactor = 1.0;

  BackingTrackState get state    => _state;
  Song?             get song     => _song;
  bool get isReady   => _state == BackingTrackState.ready ||
                        _state == BackingTrackState.paused;
  bool get isPlaying => _state == BackingTrackState.playing;

  // Position comes from the primary active player.
  Stream<Duration> get positionStream =>
      _isMultiStem && _stemPlayers.isNotEmpty
          ? _stemPlayers.first.positionStream
          : _player.positionStream;

  Stream<Duration>? get authoritativePositionStream {
    if (_state == BackingTrackState.playing ||
        _state == BackingTrackState.paused) {
      return positionStream;
    }
    return null;
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  Future<void> _disposeStemPlayers() async {
    await Future.wait(_stemPlayers.map((p) => p.dispose()));
    _stemPlayers.clear();
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  /// Load backing audio from an [AudioTrackSet].
  ///
  /// • song.ogg present → single-player mode (full pre-mix).
  /// • song.ogg absent  → multi-player mode: guitar + rhythm + vocals + bass +
  ///   keys played simultaneously. Drums and crowd are always excluded.
  ///
  /// All multi-stem operations use Future.wait() so players stay frame-accurate.
  Future<bool> loadPackage(AudioTrackSet audio) async {
    _state = BackingTrackState.loading;
    await _disposeStemPlayers();
    _isMultiStem = false;

    final singlePath = audio.primaryBackingPath; // song.ogg or null

    if (singlePath != null) {
      // ── Single-stem (song.ogg) ────────────────────────────────────────────
      try {
        if (audio.isLocal) {
          await _player.setFilePath(singlePath);
        } else {
          await _player.setAsset(singlePath);
        }
        await _player.setVolume(_volume);
        _state = BackingTrackState.ready;
        debugPrint('[BackingTrackService] Single stem: $singlePath');
        return true;
      } catch (e) {
        _state = BackingTrackState.noTrack;
        debugPrint('[BackingTrackService] Failed: $singlePath — $e');
        return false;
      }
    }

    // ── Multi-stem (guitar + rhythm + vocals + bass + keys) ──────────────────
    // backingPaths already excludes drums and crowd.
    final paths = audio.backingPaths;
    if (paths.isEmpty) {
      _state = BackingTrackState.noTrack;
      debugPrint('[BackingTrackService] No backing stems available');
      return false;
    }

    // Create and load all players in parallel.
    final players = await Future.wait(paths.map((path) async {
      final p = AudioPlayer();
      try {
        if (audio.isLocal) {
          await p.setFilePath(path);
        } else {
          await p.setAsset(path);
        }
        await p.setVolume(_volume);
        debugPrint('[BackingTrackService] Stem loaded: $path');
        return p;
      } catch (e) {
        await p.dispose();
        debugPrint('[BackingTrackService] Stem failed: $path — $e');
        return null;
      }
    }));

    final loaded = players.whereType<AudioPlayer>().toList();
    if (loaded.isEmpty) {
      _state = BackingTrackState.noTrack;
      return false;
    }

    _stemPlayers.addAll(loaded);
    _isMultiStem = true;
    _state = BackingTrackState.ready;
    debugPrint('[BackingTrackService] Multi-stem ready: '
        '${loaded.length}/${paths.length} stems');
    return true;
  }

  // ── Playback control ───────────────────────────────────────────────────────

  Future<void> play() async {
    if (_state != BackingTrackState.ready &&
        _state != BackingTrackState.paused) return;
    if (_isMultiStem) {
      await Future.wait(_stemPlayers.map((p) => p.play()));
    } else {
      await _player.play();
    }
    _state = BackingTrackState.playing;
  }

  Future<void> pause() async {
    if (_isMultiStem) {
      await Future.wait(_stemPlayers.map((p) => p.pause()));
    } else {
      await _player.pause();
    }
    _state = BackingTrackState.paused;
  }

  Future<void> resume() async {
    if (_isMultiStem) {
      await Future.wait(_stemPlayers.map((p) => p.play()));
    } else {
      await _player.play();
    }
    _state = BackingTrackState.playing;
  }

  Future<void> stop() async {
    if (_isMultiStem) {
      await Future.wait(_stemPlayers.map((p) async {
        await p.stop();
        await p.seek(Duration.zero);
      }));
    } else {
      await _player.stop();
      await _player.seek(Duration.zero);
    }
    _state = isReady ? BackingTrackState.ready : _state;
  }

  Future<void> seekTo(double seconds) async {
    final dur = Duration(milliseconds: (seconds * 1000).round());
    if (_isMultiStem) {
      await Future.wait(_stemPlayers.map((p) => p.seek(dur)));
    } else {
      await _player.seek(dur);
    }
  }

  // ── Tempo / volume ─────────────────────────────────────────────────────────

  Future<void> setTempoFactor(double factor) async {
    _tempoFactor = factor.clamp(0.5, 1.2);
    if (_isMultiStem) {
      await Future.wait(_stemPlayers.map((p) => p.setSpeed(_tempoFactor)));
    } else {
      await _player.setSpeed(_tempoFactor);
    }
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0, 1);
    if (_isMultiStem) {
      await Future.wait(_stemPlayers.map((p) => p.setVolume(_volume)));
    } else {
      await _player.setVolume(_volume);
    }
  }

  double get volume => _volume;

  // ── Dispose ───────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _disposeStemPlayers();
    await _player.dispose();
  }
}
