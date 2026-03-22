// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Audio Service  (v2 — drum pads + feedback)
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import '../domain/entities/entities.dart';

class AudioService {
  static final AudioService instance = AudioService._();
  AudioService._();

  final _players = <String, AudioPlayer>{};
  bool _ready   = false;
  bool _enabled = true;

  double _drumVolume     = 1.0;
  double _feedbackVolume = 0.6;

  bool   get enabled       => _enabled;
  set    enabled(bool v)   => _enabled = v;
  double get drumVolume    => _drumVolume;
  double get feedbackVolume => _feedbackVolume;

  set drumVolume(double v) {
    _drumVolume = v.clamp(0.0, 1.0);
    _setGroupVolume(_drumKeys, _drumVolume);
  }
  set feedbackVolume(double v) {
    _feedbackVolume = v.clamp(0.0, 1.0);
    _setGroupVolume(_feedbackKeys, _feedbackVolume);
  }

  static const _drumKeys    = ['kick','snare','hihat_closed','hihat_open',
    'hihat_pedal','crash','ride','tom1','tom2','floor_tom'];
  static const _feedbackKeys = ['perfect','good','miss','metro','countin'];

  static const _padKey = <DrumPad, String>{
    DrumPad.kick:        'kick',
    DrumPad.snare:       'snare',
    DrumPad.rimshot:     'snare',
    DrumPad.crossstick:  'snare',
    DrumPad.hihatClosed: 'hihat_closed',
    DrumPad.hihatOpen:   'hihat_open',
    DrumPad.hihatPedal:  'hihat_pedal',
    DrumPad.crash1:      'crash',
    DrumPad.crash2:      'crash',
    DrumPad.ride:        'ride',
    DrumPad.rideBell:    'ride',
    DrumPad.tom1:        'tom1',
    DrumPad.tom2:        'tom2',
    DrumPad.tom3:        'tom2',
    DrumPad.floorTom:    'floor_tom',
  };

  Future<void> init() async {
    if (_ready) return;
    try {
      await Future.wait([
        _load('kick',         'assets/sounds/drum_kick.wav',         _drumVolume),
        _load('snare',        'assets/sounds/drum_snare.wav',        _drumVolume),
        _load('hihat_closed', 'assets/sounds/drum_hihat_closed.wav', _drumVolume),
        _load('hihat_open',   'assets/sounds/drum_hihat_open.wav',   _drumVolume),
        _load('hihat_pedal',  'assets/sounds/drum_hihat_closed.wav', _drumVolume * 0.7),
        _load('crash',        'assets/sounds/drum_crash.wav',        _drumVolume * 0.9),
        _load('ride',         'assets/sounds/drum_ride.wav',         _drumVolume * 0.85),
        _load('tom1',         'assets/sounds/drum_tom1.wav',         _drumVolume),
        _load('tom2',         'assets/sounds/drum_tom2.wav',         _drumVolume),
        _load('floor_tom',    'assets/sounds/drum_floortom.wav',     _drumVolume),
        _load('perfect',      'assets/sounds/hit_perfect.wav',       _feedbackVolume),
        _load('good',         'assets/sounds/hit_good.wav',          _feedbackVolume),
        _load('miss',         'assets/sounds/hit_miss.wav',          _feedbackVolume * 0.4),
        _load('metro',        'assets/sounds/metronome_click.wav',   _feedbackVolume),
        _load('countin',      'assets/sounds/count_in.wav',          _feedbackVolume),
      ]);
      _ready = true;
    } catch (e) {
      _ready = false;
    }
  }

  Future<void> _load(String key, String asset, double volume) async {
    try {
      final p = AudioPlayer();
      await p.setAsset(asset);
      await p.setVolume(volume);
      _players[key] = p;
    } catch (_) {}
  }

  void _setGroupVolume(List<String> keys, double vol) {
    for (final k in keys) { _players[k]?.setVolume(vol).catchError((_) {}); }
  }

  /// Play drum pad sound — call on every MIDI hit or virtual pad tap.
  Future<void> playDrumPad(DrumPad pad, {double velocityNorm = 1.0}) async {
    if (!_enabled || !_ready) return;
    final key = _padKey[pad];
    if (key == null) return;
    final p = _players[key];
    if (p == null) return;
    try {
      final vol = (_drumVolume * (0.3 + 0.7 * velocityNorm)).clamp(0.0, 1.0);
      await p.setVolume(vol);
      await p.seek(Duration.zero);
      unawaited(p.play());
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  Future<void> playGradeSound(HitGrade grade) async {
    if (!_enabled || !_ready) return;
    switch (grade) {
      case HitGrade.perfect: await _play('perfect'); break;
      case HitGrade.good:    await _play('good');    break;
      // early / late → same "good" sound with a light haptic to signal off-timing
      case HitGrade.early:
      case HitGrade.late:
        await _play('good');
        HapticFeedback.lightImpact();
        break;
      case HitGrade.miss:
        await _play('miss');
        HapticFeedback.heavyImpact();
        break;
      default: break;
    }
  }

  Future<void> playMetronome({bool isDownbeat = false}) async {
    if (!_enabled || !_ready) return;
    if (isDownbeat) HapticFeedback.selectionClick();
    await _play('metro');
  }

  Future<void> playCountIn() async {
    if (!_enabled || !_ready) return;
    HapticFeedback.mediumImpact();
    await _play('countin');
  }

  Future<void> _play(String key) async {
    try {
      final p = _players[key];
      if (p == null) return;
      await p.seek(Duration.zero);
      unawaited(p.play());
    } catch (_) {}
  }

  void dispose() {
    for (final p in _players.values) { p.dispose(); }
    _players.clear();
    _ready = false;
  }
}

void unawaited(Future<void> future) {}
