// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — AudioService  (v3 — thin wrapper over DrumEngine)
//
// All drum percussion audio is handled by DrumEngine (soundpool).
// This class exists only to preserve the public API used by PracticeEngine
// and the rest of the app — no callers need to change.
//
// BackingTrackService (just_audio) handles long-form stems, unchanged.
// ─────────────────────────────────────────────────────────────────────────────
import '../domain/entities/entities.dart';
import 'drum_engine.dart';

class AudioService {
  static final AudioService instance = AudioService._();
  AudioService._();

  // ── Volume controls ────────────────────────────────────────────────────────

  bool   get enabled        => DrumEngine.instance.enabled;
  set    enabled(bool v)    { DrumEngine.instance.enabled = v; }

  double get drumVolume     => DrumEngine.instance.drumVolume;
  set    drumVolume(double v) { DrumEngine.instance.drumVolume = v; }

  double get feedbackVolume => DrumEngine.instance.feedbackVolume;
  set    feedbackVolume(double v) { DrumEngine.instance.feedbackVolume = v; }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Initialise the drum engine. Called once from main().
  Future<void> init() => DrumEngine.instance.init();

  void dispose() => DrumEngine.instance.dispose();

  // ── Drum hit ──────────────────────────────────────────────────────────────

  /// Trigger a drum sound.
  ///
  /// [velocityNorm] — 0.0 to 1.0 (normalized from MIDI 0-127 or simulated).
  /// Internally converts to int velocity 1-127 for DrumEngine.
  ///
  /// This call is fire-and-forget; it returns immediately. DrumEngine dispatches
  /// to soundpool with a single native call (no seek, no async volume set).
  Future<void> playDrumPad(DrumPad pad, {double velocityNorm = 1.0}) async {
    final vel = (velocityNorm * 127).round().clamp(1, 127);
    DrumEngine.instance.hit(pad, velocity: vel);
  }

  // ── Game feedback sounds ──────────────────────────────────────────────────

  Future<void> playGradeSound(HitGrade grade) async {
    DrumEngine.instance.playGradeSound(grade);
  }

  Future<void> playMetronome({bool isDownbeat = false}) async {
    DrumEngine.instance.playMetronome(isDownbeat: isDownbeat);
  }

  Future<void> playCountIn() async {
    DrumEngine.instance.playCountIn();
  }
}
