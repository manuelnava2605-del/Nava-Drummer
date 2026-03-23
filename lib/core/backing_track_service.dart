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

  // Single-stem player (used when song.ogg is present).
  final AudioPlayer _player = AudioPlayer();

  // Multi-stem players (used when song.ogg is absent — one player per stem).
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
    for (final p in _stemPlayers) {
      await p.dispose();
    }
    _stemPlayers.clear();
  }

  Future<bool> _loadSingle(String path, bool isLocal) async {
    try {
      if (isLocal) {
        await _player.setFilePath(path);
      } else {
        await _player.setAsset(path);
      }
      await _player.setVolume(_volume);
      return true;
    } catch (e) {
      debugPrint('[BackingTrackService] Failed to load $path: $e');
      return false;
    }
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  /// Load backing audio from an [AudioTrackSet].
  ///
  /// • If song.ogg is present → single-player mode (full pre-mix).
  /// • Otherwise              → multi-player mode: all non-drum, non-crowd
  ///   stems (vocals, guitar, rhythm, bass, keys) played simultaneously.
  ///
  /// Returns true when at least one player was loaded successfully.
  Future<bool> loadPackage(AudioTrackSet audio) async {
    _state = BackingTrackState.loading;
    await _disposeStemPlayers();
    _isMultiStem = false;

    final singlePath = audio.primaryBackingPath; // song.ogg or null

    if (singlePath != null) {
      // ── Single-stem (song.ogg) ───────────────────────────────────────────
      final ok = await _loadSingle(singlePath, audio.isLocal);
      if (!ok) {
        _state = BackingTrackState.noTrack;
        return false;
      }
      _state = BackingTrackState.ready;
      debugPrint('[BackingTrackService] Single stem loaded: $singlePath');
      return true;
    }

    // ── Multi-stem (vocals + guitar + rhythm + bass + keys) ─────────────────
    final paths = audio.backingPaths; // excludes drums + crowd
    if (paths.isEmpty) {
      _state = BackingTrackState.noTrack;
      debugPrint('[BackingTrackService] No backing stems available');
      return false;
    }

    _isMultiStem = true;
    int loaded = 0;
    for (final path in paths) {
      final p = AudioPlayer();
      try {
        if (audio.isLocal) {
          await p.setFilePath(path);
        } else {
          await p.setAsset(path);
        }
        await p.setVolume(_volume);
        _stemPlayers.add(p);
        loaded++;
        debugPrint('[BackingTrackService] Stem loaded: $path');
      } catch (e) {
        await p.dispose();
        debugPrint('[BackingTrackService] Stem failed: $path — $e');
      }
    }

    if (loaded == 0) {
      _isMultiStem = false;
      _state = BackingTrackState.noTrack;
      return false;
    }

    _state = BackingTrackState.ready;
    debugPrint('[BackingTrackService] Multi-stem ready: $loaded/${paths.length} stems');
    return true;
  }

  // ── Playback control ───────────────────────────────────────────────────────

  Future<void> play() async {
    if (_state != BackingTrackState.ready &&
        _state != BackingTrackState.paused) return;
    if (_isMultiStem) {
      for (final p in _stemPlayers) { await p.play(); }
    } else {
      await _player.play();
    }
    _state = BackingTrackState.playing;
  }

  Future<void> pause() async {
    if (_isMultiStem) {
      for (final p in _stemPlayers) { await p.pause(); }
    } else {
      await _player.pause();
    }
    _state = BackingTrackState.paused;
  }

  Future<void> resume() async {
    if (_isMultiStem) {
      for (final p in _stemPlayers) { await p.play(); }
    } else {
      await _player.play();
    }
    _state = BackingTrackState.playing;
  }

  Future<void> stop() async {
    if (_isMultiStem) {
      for (final p in _stemPlayers) {
        await p.stop();
        await p.seek(Duration.zero);
      }
    } else {
      await _player.stop();
      await _player.seek(Duration.zero);
    }
    _state = isReady ? BackingTrackState.ready : _state;
  }

  Future<void> seekTo(double seconds) async {
    final dur = Duration(milliseconds: (seconds * 1000).round());
    if (_isMultiStem) {
      for (final p in _stemPlayers) { await p.seek(dur); }
    } else {
      await _player.seek(dur);
    }
  }

  // ── Tempo / volume ─────────────────────────────────────────────────────────

  Future<void> setTempoFactor(double factor) async {
    _tempoFactor = factor.clamp(0.5, 1.2);
    if (_isMultiStem) {
      for (final p in _stemPlayers) { await p.setSpeed(_tempoFactor); }
    } else {
      await _player.setSpeed(_tempoFactor);
    }
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0, 1);
    if (_isMultiStem) {
      for (final p in _stemPlayers) { await p.setVolume(_volume); }
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
