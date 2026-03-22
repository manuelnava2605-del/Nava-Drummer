// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Backing Track Service
// Reproduce la pista de acompañamiento (sin batería) sincronizada
// con el motor MIDI y las notas cayendo.
//
// Arquitectura:
//   BackingTrackService controla just_audio
//   PracticeEngine controla el playhead
//   Ambos se sincronizan usando GlobalTimingController
//
// Uso:
//   await BackingTrackService.instance.load(song);
//   await BackingTrackService.instance.play();
//   BackingTrackService.instance.seekTo(seconds);
//   BackingTrackService.instance.stop();
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../domain/entities/entities.dart';
import '../domain/entities/song_package.dart';

// ── Estado de la pista ───────────────────────────────────────────────────────
enum BackingTrackState {
  idle,       // sin canción cargada
  loading,    // cargando archivo
  ready,      // cargada, lista para tocar
  playing,    // reproduciéndose
  paused,     // pausada
  error,      // archivo no encontrado / formato inválido
  noTrack,    // canción existe pero no tiene backing track aún
}

// ═══════════════════════════════════════════════════════════════════════════
// BackingTrackService
// ═══════════════════════════════════════════════════════════════════════════
class BackingTrackService {
  static final BackingTrackService instance = BackingTrackService._();
  BackingTrackService._();

  final AudioPlayer _player = AudioPlayer();

  BackingTrackState _state  = BackingTrackState.idle;
  Song?             _song;
  double            _volume = 0.85;   // deja espacio para la batería
  double            _tempoFactor = 1.0;

  // Estado observable
  BackingTrackState get state   => _state;
  Song?             get song    => _song;
  bool              get isReady => _state == BackingTrackState.ready ||
                                   _state == BackingTrackState.paused;
  bool              get isPlaying => _state == BackingTrackState.playing;

  // Stream de posición (para sincronizar con el playhead visual)
  Stream<Duration> get positionStream => _player.positionStream;

  /// Authoritative position stream from just_audio.
  /// Returns the player's positionStream when playing or paused.
  /// The PracticeEngine subscribes to this to detect audio drift.
  Stream<Duration>? get authoritativePositionStream {
    if (_state == BackingTrackState.playing ||
        _state == BackingTrackState.paused) {
      return _player.positionStream;
    }
    return null;
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  /// Intenta cargar la pista de acompañamiento para [song].
  /// Retorna true si el archivo existe, false si no hay backing track.
  Future<bool> load(Song song) async {
    _song  = song;
    _state = BackingTrackState.loading;

    final path = _backingTrackPath(song);

    try {
      await _player.setAsset(path);
      await _player.setVolume(_volume);
      _state = BackingTrackState.ready;
      return true;
    } catch (e) {
      // Archivo no existe todavía — modo MIDI-only
      _state = BackingTrackState.noTrack;
      debugPrint('BackingTrack not found for ${song.id}: $e');
      return false;
    }
  }

  /// Ruta del archivo de audio en assets
  String _backingTrackPath(Song song) =>
      'assets/backing_tracks/${song.id}.m4a';

  /// Load the primary backing stem from an [AudioTrackSet] (OGG package).
  ///
  /// Uses [AudioTrackSet.primaryBackingPath] priority:
  ///   guitar → rhythm → vocals → song (full mix)
  ///
  /// Returns true if a stem was found and loaded; false if no stems are
  /// available (MIDI-only mode).
  Future<bool> loadPackage(AudioTrackSet audio) async {
    _state = BackingTrackState.loading;
    final path = audio.primaryBackingPath;

    if (path == null) {
      _state = BackingTrackState.noTrack;
      debugPrint('[BackingTrackService] No backing stems in package');
      return false;
    }

    try {
      await _player.setAsset(path);
      await _player.setVolume(_volume);
      _state = BackingTrackState.ready;
      debugPrint('[BackingTrackService] Package stem loaded: $path');
      return true;
    } catch (e) {
      _state = BackingTrackState.noTrack;
      debugPrint('[BackingTrackService] Failed to load package stem $path: $e');
      return false;
    }
  }

  // ── Playback control ───────────────────────────────────────────────────────

  /// Inicia la reproducción sincronizada con el count-in.
  /// [countInMs] — tiempo del count-in para retrasar el inicio.
  Future<void> play({int countInMs = 0}) async {
    if (_state != BackingTrackState.ready &&
        _state != BackingTrackState.paused) return;

    if (countInMs > 0) {
      await Future.delayed(Duration(milliseconds: countInMs));
    }

    await _player.play();
    _state = BackingTrackState.playing;
  }

  Future<void> pause() async {
    await _player.pause();
    _state = BackingTrackState.paused;
  }

  Future<void> resume() async {
    await _player.play();
    _state = BackingTrackState.playing;
  }

  Future<void> stop() async {
    await _player.stop();
    await _player.seek(Duration.zero);
    _state = isReady ? BackingTrackState.ready : _state;
  }

  /// Seek a una posición en segundos (para sincronizar con el engine).
  Future<void> seekTo(double seconds) async {
    await _player.seek(Duration(milliseconds: (seconds * 1000).round()));
  }

  // ── Tempo adjustment ──────────────────────────────────────────────────────

  /// Ajusta la velocidad de reproducción cuando el usuario cambia el tempo.
  /// just_audio soporta speed natively.
  Future<void> setTempoFactor(double factor) async {
    _tempoFactor = factor.clamp(0.5, 1.2);
    await _player.setSpeed(_tempoFactor);
  }

  // ── Volume ────────────────────────────────────────────────────────────────

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0, 1);
    await _player.setVolume(_volume);
  }

  double get volume => _volume;

  // ── Dispose ───────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _player.dispose();
  }

  // ── Check availability ────────────────────────────────────────────────────

  /// Retorna true si esta canción tiene backing track disponible en assets.
  /// Útil para mostrar el ícono correcto en el catálogo.
  static bool hasBackingTrack(Song song) {
    // En runtime verificamos con load(). Aquí retornamos true para las
    // canciones que sabemos tienen archivo — actualizar conforme se agregan.
    const withTracks = <String>{
      'te_quiero_hombres_g',
      // Agregar más IDs conforme se consiguen las pistas
    };
    return withTracks.contains(song.id);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DrumSoundEngine — sonidos de batería realistas al tocar
// Usa SoundFont (.sf2) si está disponible, sino WAV samples básicos
// ═══════════════════════════════════════════════════════════════════════════
class DrumSoundEngine {
  static final DrumSoundEngine instance = DrumSoundEngine._();
  DrumSoundEngine._();

  // Un AudioPlayer por pad para polifonia sin latencia
  final Map<DrumPad, AudioPlayer> _padPlayers = {};
  bool _ready = false;

  /// Inicializa los players de cada pad.
  /// En producción cargar samples de batería de alta calidad.
  Future<void> init() async {
    if (_ready) return;
    // Por ahora los samples básicos — reemplazar con
    // samples de batería profesionales (.wav 24bit/44.1kHz)
    final padSamples = <DrumPad, String>{
      DrumPad.kick:        'assets/sounds/drum_kick.wav',
      DrumPad.snare:       'assets/sounds/drum_snare.wav',
      DrumPad.hihatClosed: 'assets/sounds/drum_hihat_closed.wav',
      DrumPad.hihatOpen:   'assets/sounds/drum_hihat_open.wav',
      DrumPad.crash1:      'assets/sounds/drum_crash.wav',
      DrumPad.ride:        'assets/sounds/drum_ride.wav',
      DrumPad.tom1:        'assets/sounds/drum_tom1.wav',
      DrumPad.tom2:        'assets/sounds/drum_tom2.wav',
      DrumPad.floorTom:    'assets/sounds/drum_floortom.wav',
    };

    for (final entry in padSamples.entries) {
      try {
        final p = AudioPlayer();
        await p.setAsset(entry.value);
        _padPlayers[entry.key] = p;
      } catch (_) {
        // Sample no disponible — continúa sin él
      }
    }
    _ready = true;
  }

  /// Toca el sonido de un pad al velocidad [velocity] (0-127).
  Future<void> play(DrumPad pad, {int velocity = 100}) async {
    final p = _padPlayers[pad];
    if (p == null) return;
    try {
      final vol = velocity / 127.0;
      await p.setVolume(vol.clamp(0.1, 1.0));
      await p.seek(Duration.zero);
      unawaited(p.play());
    } catch (_) {}
  }

  void dispose() {
    for (final p in _padPlayers.values) { p.dispose(); }
    _padPlayers.clear();
  }
}

void unawaited(Future<void> f) {}
