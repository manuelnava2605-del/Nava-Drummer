// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — DrumEngine  (Professional Low-Latency Drum Sampler)
//
// Replaces just_audio for percussion with soundpool:
//   • Android → android.media.SoundPool  (game audio, <5ms latency)
//   • iOS     → AVAudioPlayer pool       (~5-10ms latency)
//
// Architecture:
//   DrumEngine.instance.hit(pad, velocity)
//     → VelocityLayer selection   (soft | medium | hard)
//     → Round-robin counter       (cycles through sample variations)
//     → SoundId lookup            (pre-loaded into soundpool)
//     → pool.play(soundId, vol, rate)   ← single native call, fire+forget
//     → HiHatController           (chokes open hi-hat on closed/pedal)
//
// ── Sample layout (GSCW Kit 1 — Yamaha / Sabian / StarClassic) ────────────
//   assets/sounds/drums/<pad>/<pad>_<layer>_<n>.wav
//   layer: soft | medium | hard
//   Kick:          12 samples (Yamaha 16x16 bass drum)
//   Snare:         20 samples (Custom Works 6x13)
//   HiHat Closed:  10 samples (Sabian AAX)
//   HiHat Open:     8 samples (Sabian AAX)
//   HiHat Pedal:    4 samples (Sabian AAX)
//   Crash:          5 samples (Sabian 18")
//   Crash2:         6 samples (Sabian 14")
//   Ride:           8 samples (Rob Mor Sabian 22")
//   Ride Bell:      8 samples (Rob Mor Sabian 22" bell)
//   Tom1:           7 samples (Star Classic 10x10)
//   Tom2:           8 samples (Star Classic 13x13)
//   Floor Tom:      6 samples (Star Classic 13x13 offset)
//   Rimshot:        8 samples (Custom Works 6x13 rim)
//   Crossstick:     8 samples (Custom Works 6x13 sidestick)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:soundpool/soundpool.dart';

import '../domain/entities/entities.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Velocity Layer
// ═══════════════════════════════════════════════════════════════════════════════

enum VelocityLayer { soft, medium, hard }

VelocityLayer _layerFor(int velocity) {
  if (velocity < 50) return VelocityLayer.soft;
  if (velocity < 90) return VelocityLayer.medium;
  return VelocityLayer.hard;
}

// ═══════════════════════════════════════════════════════════════════════════════
// HiHatController — manages open hi-hat choke
// ═══════════════════════════════════════════════════════════════════════════════

class _HiHatController {
  int _openStreamId = -1;

  int get openStreamId => _openStreamId;

  void registerOpen(int streamId) {
    _openStreamId = streamId > 0 ? streamId : -1;
  }

  void clear() => _openStreamId = -1;

  /// Stop the open hi-hat stream. Call BEFORE triggering closed/pedal.
  void choke(Soundpool pool) {
    if (_openStreamId > 0) {
      pool.stop(_openStreamId).catchError((_) {});
      _openStreamId = -1;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DrumEngine — main singleton
// ═══════════════════════════════════════════════════════════════════════════════

class DrumEngine {
  static final DrumEngine instance = DrumEngine._();
  DrumEngine._();

  late Soundpool _pool;

  // Sample bank: pad → [layerIndex 0-2][rrIndex] = soundId
  // layerIndex: 0=soft, 1=medium, 2=hard
  // rrIndex: round-robin variation slot
  final Map<DrumPad, List<List<int>>> _bank = {};

  // Round-robin counters: pad → [counterPerLayer * 3]
  final Map<DrumPad, List<int>> _rrCounters = {};

  final _HiHatController _hihat = _HiHatController();

  // Feedback sound IDs
  int _sfxPerfect = -1;
  int _sfxGood    = -1;
  int _sfxMiss    = -1;
  int _sfxMetro   = -1;
  int _sfxCountIn = -1;

  bool   _ready   = false;
  bool   _enabled = true;
  double _drumVolume     = 1.0;
  double _feedbackVolume = 0.6;

  bool   get enabled        => _enabled;
  set    enabled(bool v)    { _enabled = v; }
  double get drumVolume     => _drumVolume;
  set    drumVolume(double v) { _drumVolume = v.clamp(0.0, 1.0); }
  double get feedbackVolume => _feedbackVolume;
  set    feedbackVolume(double v) { _feedbackVolume = v.clamp(0.0, 1.0); }
  bool   get isReady        => _ready;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_ready) return;

    try {
      _pool = Soundpool.fromOptions(
        options: const SoundpoolOptions(
          streamType: StreamType.music,
          maxStreams: 16, // polyphony ceiling
        ),
      );

      // Initialise round-robin counters for every pad
      for (final pad in DrumPad.values) {
        _rrCounters[pad] = [0, 0, 0]; // one counter per velocity layer
      }

      // Load all drum samples — every pad has its own authentic sample bank
      await Future.wait([
        _loadPad(DrumPad.kick,        _kKickPaths),
        _loadPad(DrumPad.snare,       _kSnarePaths),
        _loadPad(DrumPad.hihatClosed, _kHihatClosedPaths),
        _loadPad(DrumPad.hihatOpen,   _kHihatOpenPaths),
        _loadPad(DrumPad.hihatPedal,  _kHihatPedalPaths),
        _loadPad(DrumPad.crash1,      _kCrashPaths),
        _loadPad(DrumPad.crash2,      _kCrash2Paths),
        _loadPad(DrumPad.ride,        _kRidePaths),
        _loadPad(DrumPad.rideBell,    _kRideBellPaths),
        _loadPad(DrumPad.tom1,        _kTom1Paths),
        _loadPad(DrumPad.tom2,        _kTom2Paths),
        _loadPad(DrumPad.floorTom,    _kFloorTomPaths),
        _loadPad(DrumPad.rimshot,     _kRimshotPaths),
        _loadPad(DrumPad.crossstick,  _kCrossstickPaths),
        _loadFeedback(),
      ]);

      // Only alias tom3 (no dedicated sample recorded for 3rd tom)
      _bank[DrumPad.tom3] = _bank[DrumPad.floorTom]!;

      _ready = true;
      debugPrint('[DrumEngine] Ready — ${_bank.length} pad banks loaded');
    } catch (e, st) {
      debugPrint('[DrumEngine] Init failed: $e\n$st');
      _ready = false;
    }
  }

  // ── Sample path tables ─────────────────────────────────────────────────────
  //
  // Format: [ [soft_rr...], [medium_rr...], [hard_rr...] ]
  // GSCW Kit 1 — Yamaha / Sabian / StarClassic samples

  static const _kKickPaths = [
    // soft  — light heel-toe, ghost kicks
    ['assets/sounds/drums/kick/kick_soft_1.wav',
     'assets/sounds/drums/kick/kick_soft_2.wav',
     'assets/sounds/drums/kick/kick_soft_3.wav',
     'assets/sounds/drums/kick/kick_soft_4.wav'],
    // medium — typical playing
    ['assets/sounds/drums/kick/kick_medium_1.wav',
     'assets/sounds/drums/kick/kick_medium_2.wav',
     'assets/sounds/drums/kick/kick_medium_3.wav',
     'assets/sounds/drums/kick/kick_medium_4.wav'],
    // hard  — full-power accents
    ['assets/sounds/drums/kick/kick_hard_1.wav',
     'assets/sounds/drums/kick/kick_hard_2.wav',
     'assets/sounds/drums/kick/kick_hard_3.wav',
     'assets/sounds/drums/kick/kick_hard_4.wav'],
  ];

  static const _kSnarePaths = [
    // soft  — ghost notes
    ['assets/sounds/drums/snare/snare_soft_1.wav',
     'assets/sounds/drums/snare/snare_soft_2.wav',
     'assets/sounds/drums/snare/snare_soft_3.wav',
     'assets/sounds/drums/snare/snare_soft_4.wav',
     'assets/sounds/drums/snare/snare_soft_5.wav',
     'assets/sounds/drums/snare/snare_soft_6.wav'],
    // medium
    ['assets/sounds/drums/snare/snare_medium_1.wav',
     'assets/sounds/drums/snare/snare_medium_2.wav',
     'assets/sounds/drums/snare/snare_medium_3.wav',
     'assets/sounds/drums/snare/snare_medium_4.wav',
     'assets/sounds/drums/snare/snare_medium_5.wav',
     'assets/sounds/drums/snare/snare_medium_6.wav',
     'assets/sounds/drums/snare/snare_medium_7.wav'],
    // hard  — backbeat accents
    ['assets/sounds/drums/snare/snare_hard_1.wav',
     'assets/sounds/drums/snare/snare_hard_2.wav',
     'assets/sounds/drums/snare/snare_hard_3.wav',
     'assets/sounds/drums/snare/snare_hard_4.wav',
     'assets/sounds/drums/snare/snare_hard_5.wav',
     'assets/sounds/drums/snare/snare_hard_6.wav',
     'assets/sounds/drums/snare/snare_hard_7.wav'],
  ];

  static const _kHihatClosedPaths = [
    ['assets/sounds/drums/hihat_closed/hihat_closed_soft_1.wav',
     'assets/sounds/drums/hihat_closed/hihat_closed_soft_2.wav',
     'assets/sounds/drums/hihat_closed/hihat_closed_soft_3.wav'],
    ['assets/sounds/drums/hihat_closed/hihat_closed_medium_1.wav',
     'assets/sounds/drums/hihat_closed/hihat_closed_medium_2.wav',
     'assets/sounds/drums/hihat_closed/hihat_closed_medium_3.wav',
     'assets/sounds/drums/hihat_closed/hihat_closed_medium_4.wav'],
    ['assets/sounds/drums/hihat_closed/hihat_closed_hard_1.wav',
     'assets/sounds/drums/hihat_closed/hihat_closed_hard_2.wav',
     'assets/sounds/drums/hihat_closed/hihat_closed_hard_3.wav'],
  ];

  static const _kHihatOpenPaths = [
    ['assets/sounds/drums/hihat_open/hihat_open_soft_1.wav',
     'assets/sounds/drums/hihat_open/hihat_open_soft_2.wav'],
    ['assets/sounds/drums/hihat_open/hihat_open_medium_1.wav',
     'assets/sounds/drums/hihat_open/hihat_open_medium_2.wav',
     'assets/sounds/drums/hihat_open/hihat_open_medium_3.wav'],
    ['assets/sounds/drums/hihat_open/hihat_open_hard_1.wav',
     'assets/sounds/drums/hihat_open/hihat_open_hard_2.wav',
     'assets/sounds/drums/hihat_open/hihat_open_hard_3.wav'],
  ];

  static const _kHihatPedalPaths = [
    ['assets/sounds/drums/hihat_pedal/hihat_pedal_soft_1.wav'],
    ['assets/sounds/drums/hihat_pedal/hihat_pedal_medium_1.wav'],
    ['assets/sounds/drums/hihat_pedal/hihat_pedal_hard_1.wav',
     'assets/sounds/drums/hihat_pedal/hihat_pedal_hard_2.wav'],
  ];

  static const _kCrashPaths = [
    ['assets/sounds/drums/crash/crash_soft_1.wav',
     'assets/sounds/drums/crash/crash_soft_2.wav'],
    ['assets/sounds/drums/crash/crash_medium_1.wav'],
    ['assets/sounds/drums/crash/crash_hard_1.wav',
     'assets/sounds/drums/crash/crash_hard_2.wav'],
  ];

  static const _kCrash2Paths = [
    ['assets/sounds/drums/crash2/crash2_soft_1.wav',
     'assets/sounds/drums/crash2/crash2_soft_2.wav'],
    ['assets/sounds/drums/crash2/crash2_medium_1.wav',
     'assets/sounds/drums/crash2/crash2_medium_2.wav'],
    ['assets/sounds/drums/crash2/crash2_hard_1.wav',
     'assets/sounds/drums/crash2/crash2_hard_2.wav'],
  ];

  static const _kRidePaths = [
    ['assets/sounds/drums/ride/ride_soft_1.wav',
     'assets/sounds/drums/ride/ride_soft_2.wav'],
    ['assets/sounds/drums/ride/ride_medium_1.wav',
     'assets/sounds/drums/ride/ride_medium_2.wav',
     'assets/sounds/drums/ride/ride_medium_3.wav'],
    ['assets/sounds/drums/ride/ride_hard_1.wav',
     'assets/sounds/drums/ride/ride_hard_2.wav',
     'assets/sounds/drums/ride/ride_hard_3.wav'],
  ];

  static const _kRideBellPaths = [
    ['assets/sounds/drums/ride_bell/ride_bell_soft_1.wav',
     'assets/sounds/drums/ride_bell/ride_bell_soft_2.wav'],
    ['assets/sounds/drums/ride_bell/ride_bell_medium_1.wav',
     'assets/sounds/drums/ride_bell/ride_bell_medium_2.wav',
     'assets/sounds/drums/ride_bell/ride_bell_medium_3.wav'],
    ['assets/sounds/drums/ride_bell/ride_bell_hard_1.wav',
     'assets/sounds/drums/ride_bell/ride_bell_hard_2.wav',
     'assets/sounds/drums/ride_bell/ride_bell_hard_3.wav'],
  ];

  static const _kTom1Paths = [
    ['assets/sounds/drums/tom1/tom1_soft_1.wav',
     'assets/sounds/drums/tom1/tom1_soft_2.wav'],
    ['assets/sounds/drums/tom1/tom1_medium_1.wav',
     'assets/sounds/drums/tom1/tom1_medium_2.wav'],
    ['assets/sounds/drums/tom1/tom1_hard_1.wav',
     'assets/sounds/drums/tom1/tom1_hard_2.wav',
     'assets/sounds/drums/tom1/tom1_hard_3.wav'],
  ];

  static const _kTom2Paths = [
    ['assets/sounds/drums/tom2/tom2_soft_1.wav',
     'assets/sounds/drums/tom2/tom2_soft_2.wav'],
    ['assets/sounds/drums/tom2/tom2_medium_1.wav',
     'assets/sounds/drums/tom2/tom2_medium_2.wav',
     'assets/sounds/drums/tom2/tom2_medium_3.wav'],
    ['assets/sounds/drums/tom2/tom2_hard_1.wav',
     'assets/sounds/drums/tom2/tom2_hard_2.wav',
     'assets/sounds/drums/tom2/tom2_hard_3.wav'],
  ];

  static const _kFloorTomPaths = [
    ['assets/sounds/drums/floor_tom/floor_tom_soft_1.wav',
     'assets/sounds/drums/floor_tom/floor_tom_soft_2.wav'],
    ['assets/sounds/drums/floor_tom/floor_tom_medium_1.wav',
     'assets/sounds/drums/floor_tom/floor_tom_medium_2.wav'],
    ['assets/sounds/drums/floor_tom/floor_tom_hard_1.wav',
     'assets/sounds/drums/floor_tom/floor_tom_hard_2.wav'],
  ];

  static const _kRimshotPaths = [
    ['assets/sounds/drums/rimshot/rimshot_soft_1.wav',
     'assets/sounds/drums/rimshot/rimshot_soft_2.wav'],
    ['assets/sounds/drums/rimshot/rimshot_medium_1.wav',
     'assets/sounds/drums/rimshot/rimshot_medium_2.wav',
     'assets/sounds/drums/rimshot/rimshot_medium_3.wav'],
    ['assets/sounds/drums/rimshot/rimshot_hard_1.wav',
     'assets/sounds/drums/rimshot/rimshot_hard_2.wav',
     'assets/sounds/drums/rimshot/rimshot_hard_3.wav'],
  ];

  static const _kCrossstickPaths = [
    ['assets/sounds/drums/crossstick/crossstick_soft_1.wav',
     'assets/sounds/drums/crossstick/crossstick_soft_2.wav'],
    ['assets/sounds/drums/crossstick/crossstick_medium_1.wav',
     'assets/sounds/drums/crossstick/crossstick_medium_2.wav',
     'assets/sounds/drums/crossstick/crossstick_medium_3.wav'],
    ['assets/sounds/drums/crossstick/crossstick_hard_1.wav',
     'assets/sounds/drums/crossstick/crossstick_hard_2.wav',
     'assets/sounds/drums/crossstick/crossstick_hard_3.wav'],
  ];

  // ── Load helpers ──────────────────────────────────────────────────────────

  Future<void> _loadPad(DrumPad pad, List<List<String>> layerPaths) async {
    final layerBank = <List<int>>[];

    for (final rrPaths in layerPaths) {
      final rrIds = <int>[];
      for (final path in rrPaths) {
        rrIds.add(await _loadAsset(path));
      }
      layerBank.add(rrIds);
    }

    _bank[pad] = layerBank;
  }

  Future<int> _loadAsset(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return await _pool.load(data, priority: 1);
    } catch (e) {
      debugPrint('[DrumEngine] ⚠ Cannot load $assetPath: $e');
      return -1;
    }
  }

  Future<void> _loadFeedback() async {
    _sfxPerfect = await _loadAsset('assets/sounds/hit_perfect.wav');
    _sfxGood    = await _loadAsset('assets/sounds/hit_good.wav');
    _sfxMiss    = await _loadAsset('assets/sounds/hit_miss.wav');
    _sfxMetro   = await _loadAsset('assets/sounds/metronome_click.wav');
    _sfxCountIn = await _loadAsset('assets/sounds/count_in.wav');
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HIT — main entry point (synchronous from caller's perspective)
  //
  // This method returns immediately. Audio dispatch happens via fire-and-forget
  // MethodChannel calls that are queued in order on the native side.
  // Total latency: ~1 MethodChannel round-trip (~1-3ms) vs. previous 3 awaits.
  // ═════════════════════════════════════════════════════════════════════════

  void hit(DrumPad pad, {int velocity = 100}) {
    if (!_enabled || !_ready) return;

    final vel = velocity.clamp(1, 127);

    // 1. Haptic — fires immediately (synchronous platform call)
    _haptic(pad);

    // 2. Hi-hat choke — stop open stream BEFORE triggering new sound.
    //    Both pool.stop() and pool.play() are queued MethodChannel calls;
    //    they execute in order on the platform thread.
    if (pad == DrumPad.hihatClosed || pad == DrumPad.hihatPedal) {
      _hihat.choke(_pool); // fire-and-forget, ordered before play below
    }

    // 3. Select sound
    final layerIdx = _layerFor(vel).index; // 0, 1, or 2
    final layerBank = _bank[pad];
    if (layerBank == null || layerBank.isEmpty) return;

    final rrSlots = layerBank[layerIdx.clamp(0, layerBank.length - 1)];
    if (rrSlots.isEmpty) return;

    final counters = _rrCounters[pad]!;
    final rrIdx    = counters[layerIdx];
    counters[layerIdx] = (rrIdx + 1) % rrSlots.length;

    final soundId = rrSlots[rrIdx];
    if (soundId < 0) return; // sample failed to load — silently skip

    // 4. Volume curve
    // Hi-hat pedal: inherently softer — scale down by ~35%
    final pedalScale = (pad == DrumPad.hihatPedal) ? 0.65 : 1.0;
    final vol = (_drumVolume * _velocityToVolume(vel, pad) * pedalScale)
        .clamp(0.0, 1.0);

    // 5. Rate (playback speed = pitch variation)
    final rate = _velocityToRate(vel, pad, rrIdx);

    // 6. Play — fire and forget (no await = no latency in calling thread)
    // soundpool 2.4+ does not accept `volume` in play(); set it on the stream.
    if (pad == DrumPad.hihatOpen) {
      // Need the streamId so we can choke it later
      _pool.play(soundId, rate: rate).then((streamId) {
        if (streamId > 0) {
          _pool.setVolume(streamId: streamId, volume: vol);
          _hihat.registerOpen(streamId);
        }
        return streamId;
      }).catchError((_) => -1);
    } else {
      _pool.play(soundId, rate: rate).then((streamId) {
        if (streamId > 0) _pool.setVolume(streamId: streamId, volume: vol);
        return streamId;
      }).catchError((_) => -1);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Volume curve:  velocity → perceived loudness
  //
  // Uses a gentle S-curve so soft hits are clearly audible (not inaudible)
  // and hard hits are full volume without clipping.
  //   vel=1   → 0.18  (very soft, still hearable)
  //   vel=64  → 0.60
  //   vel=90  → 0.82
  //   vel=127 → 1.00
  // ─────────────────────────────────────────────────────────────────────────

  double _velocityToVolume(int vel, DrumPad pad) {
    final v = vel / 127.0;
    // Blend linear (0.6 weight) + quadratic (0.4 weight) for gentle curve
    return 0.18 + 0.82 * (v * 0.6 + v * v * 0.4);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Rate (playback speed / pitch):
  //
  // Harder hits on real drums have slightly higher fundamental frequency
  // due to increased membrane tension. We simulate this with rate variation.
  //
  // Additionally, each round-robin slot gets a micro-variation (±1.5%) that
  // breaks the machine-gun effect even when only one sample exists.
  //
  // Cymbals (crash, ride): rate = 1.0 always. Their long sustain makes
  // pitch shift audible and unnatural.
  //
  // All others:
  //   vel=1   → rate ≈ 0.94  (low, softer attack)
  //   vel=64  → rate ≈ 1.00  (nominal)
  //   vel=127 → rate ≈ 1.06  (slightly higher pitch, punchier)
  //   + micro-variation per RR slot
  // ─────────────────────────────────────────────────────────────────────────

  static const _kRrRateOffsets = [0.000, 0.013, -0.010, 0.007, -0.005, 0.011];

  double _velocityToRate(int vel, DrumPad pad, int rrIdx) {
    if (_isCymbal(pad)) return 1.0;

    final v         = vel / 127.0;
    final baseRate  = 0.94 + 0.12 * v;
    final rrOffset  = _kRrRateOffsets[rrIdx % _kRrRateOffsets.length];
    return (baseRate + rrOffset).clamp(0.5, 2.0);
  }

  bool _isCymbal(DrumPad pad) =>
      pad == DrumPad.crash1   ||
      pad == DrumPad.crash2   ||
      pad == DrumPad.ride     ||
      pad == DrumPad.rideBell;

  // ─────────────────────────────────────────────────────────────────────────
  // Haptic feedback — differentiated per drum family for tactile realism
  // ─────────────────────────────────────────────────────────────────────────

  void _haptic(DrumPad pad) {
    switch (pad) {
      case DrumPad.kick:
        HapticFeedback.heavyImpact();
      case DrumPad.snare:
      case DrumPad.rimshot:
      case DrumPad.tom1:
      case DrumPad.tom2:
      case DrumPad.tom3:
      case DrumPad.floorTom:
        HapticFeedback.mediumImpact();
      case DrumPad.crossstick:
        HapticFeedback.lightImpact();
      case DrumPad.hihatClosed:
      case DrumPad.hihatOpen:
      case DrumPad.hihatPedal:
        HapticFeedback.selectionClick();
      case DrumPad.crash1:
      case DrumPad.crash2:
      case DrumPad.ride:
      case DrumPad.rideBell:
        HapticFeedback.lightImpact();
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // FEEDBACK SOUNDS (perfect / good / miss / metronome / count-in)
  // Also moved to soundpool — consistent low latency for all sounds.
  // ═════════════════════════════════════════════════════════════════════════

  void playGradeSound(HitGrade grade) {
    if (!_enabled || !_ready) return;
    switch (grade) {
      case HitGrade.perfect:
        _playSfx(_sfxPerfect, _feedbackVolume);
      case HitGrade.good:
        _playSfx(_sfxGood, _feedbackVolume * 0.85);
      case HitGrade.early:
      case HitGrade.late:
        _playSfx(_sfxGood, _feedbackVolume * 0.65);
        HapticFeedback.lightImpact();
      case HitGrade.miss:
        _playSfx(_sfxMiss, _feedbackVolume * 0.35);
        HapticFeedback.heavyImpact();
      default:
        break;
    }
  }

  void playMetronome({bool isDownbeat = false}) {
    if (!_enabled || !_ready) return;
    if (isDownbeat) HapticFeedback.selectionClick();
    _playSfx(_sfxMetro, _feedbackVolume * 0.9);
  }

  void playCountIn() {
    if (!_enabled || !_ready) return;
    HapticFeedback.mediumImpact();
    _playSfx(_sfxCountIn, _feedbackVolume);
  }

  void _playSfx(int soundId, double vol) {
    if (soundId < 0) return;
    final clamped = vol.clamp(0.0, 1.0);
    _pool.play(soundId).then((streamId) {
      if (streamId > 0) _pool.setVolume(streamId: streamId, volume: clamped);
      return streamId;
    }).catchError((_) => -1);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═════════════════════════════════════════════════════════════════════════

  void dispose() {
    if (!_ready) return;
    try { _pool.dispose(); } catch (_) {}
    _bank.clear();
    _hihat.clear();
    _ready = false;
    debugPrint('[DrumEngine] Disposed');
  }
}
