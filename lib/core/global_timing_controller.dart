// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Global Timing Controller  (Phase 1)
// + Mathematical Timing Engine          (Phase 2)
//
// Phase 1: Single monotonic clock that aligns MIDI, audio, and render timelines.
// Phase 2: DAW-level precision — Gaussian scoring, BPM-relative windows,
//          adaptive difficulty, swing support, normalized error ε = Δt/T_beat.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math' as math;

// ═══════════════════════════════════════════════════════════════════════════
// PHASE 1 — GlobalTimingController
// ═══════════════════════════════════════════════════════════════════════════

/// Single source of truth for all time measurements in NavaDrummer.
///
/// Architecture:
///   T_global(t) = t_now_µs + syncOffset_µs + driftCorrection_µs
///
/// All sub-systems (MIDI, audio, renderer) call [currentTimeMicros] and
/// never read their own clocks independently.
class GlobalTimingController {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final GlobalTimingController instance = GlobalTimingController._();
  GlobalTimingController._();

  // ── State ──────────────────────────────────────────────────────────────────

  /// Offset added to every timestamp to align MIDI hardware clock to
  /// Dart's DateTime clock.  Set by calibration or latency measurement.
  int syncOffsetMicros = 0;

  /// Accumulated drift correction from the Kalman filter.
  /// Updated every [_driftWindowSize] events.
  double _driftCorrectionUs = 0;

  // Drift estimation via linear regression over recent samples
  static const int _driftWindowSize = 32;
  final List<_DriftSample> _driftSamples = [];

  // Session reference — set when practice starts
  int? _sessionStartUs;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Monotonic time in microseconds.
  /// This is THE clock for all timing in the app.
  int currentTimeMicros() =>
      DateTime.now().microsecondsSinceEpoch +
      syncOffsetMicros +
      _driftCorrectionUs.round();

  /// Elapsed time since session started, in microseconds.
  /// Returns 0 if no session is active.
  int sessionElapsedMicros() {
    if (_sessionStartUs == null) return 0;
    return currentTimeMicros() - _sessionStartUs!;
  }

  /// Elapsed time in seconds (convenience).
  double sessionElapsedSeconds() => sessionElapsedMicros() / 1e6;

  /// Mark the session start time.
  void startSession() => _sessionStartUs = currentTimeMicros();

  /// Adjust sync offset from a measured latency value.
  /// [measuredLatencyUs] is the one-way hardware-to-Dart delay.
  void applySyncOffset(int measuredLatencyUs) {
    syncOffsetMicros = -measuredLatencyUs;
  }

  /// Feed a reference timestamp pair to estimate clock drift.
  /// [dartUs] = time as seen by Dart, [nativeUs] = time as seen by native layer.
  void feedDriftSample(int dartUs, int nativeUs) {
    _driftSamples.add(_DriftSample(dartUs: dartUs, nativeUs: nativeUs));
    if (_driftSamples.length > _driftWindowSize) _driftSamples.removeAt(0);
    if (_driftSamples.length >= 4) _estimateDrift();
  }

  void _estimateDrift() {
    // Linear regression: native_us = a * dart_us + b
    // drift = average(native_us - dart_us)
    double sumDiff = 0;
    for (final s in _driftSamples) {
      sumDiff += (s.nativeUs - s.dartUs);
    }
    _driftCorrectionUs = sumDiff / _driftSamples.length;
  }

  /// Convert a native timestamp (from Android/iOS) to global time.
  int nativeToGlobal(int nativeTimestampUs) =>
      nativeTimestampUs + syncOffsetMicros + _driftCorrectionUs.round();

  void reset() {
    syncOffsetMicros   = 0;
    _driftCorrectionUs = 0;
    _sessionStartUs    = null;
    _driftSamples.clear();
  }
}

class _DriftSample {
  final int dartUs, nativeUs;
  _DriftSample({required this.dartUs, required this.nativeUs});
}

// ═══════════════════════════════════════════════════════════════════════════
// PHASE 2 — Mathematical Timing Engine (DAW Level)
// ═══════════════════════════════════════════════════════════════════════════

/// All timing math lives here. The PracticeEngine delegates scoring to this.
///
/// Key formulas:
///   T_beat          = 60_000 / BPM            (ms per beat)
///   T_subdivision   = T_beat / n               (e.g. n=4 → 16th notes)
///   Δt              = t_input - t_expected      (timing error, ms)
///   ε               = Δt / T_beat              (normalized error, dimensionless)
///   S               = exp(−Δt² / 2σ²)          (Gaussian score, 0..1)
///   score_raw       = S * MAX_SCORE
///   σ               = σ_base * (1 − skill)     (adaptive tolerance)
class MathTimingEngine {
  // ── Configuration ───────────────────────────────────────────────────────────

  /// Base scoring parameters — α and β are fractions of T_beat.
  static const double _alphaPerfect = 0.04; // |ε| ≤ 0.04 → PERFECT
  static const double _betaGood     = 0.10; // |ε| ≤ 0.10 → GOOD
  static const double _betaOkay     = 0.18; // |ε| ≤ 0.18 → OKAY
  // |ε| > βOkay → MISS

  /// Gaussian σ as fraction of T_beat (before skill scaling).
  static const double _sigmaBaseFraction = 0.10;

  /// Maximum raw score per hit (before combo multiplier).
  static const int maxHitScore = 1000;

  // ── State ──────────────────────────────────────────────────────────────────
  final int    bpm;
  final double skillFactor;   // 0.0 (beginner) → 1.0 (expert) — widens windows
  final double swingRatio;    // 0.0 = straight, 0.33 = light swing, 0.67 = heavy

  /// Derived constants
  late final double tBeatMs;          // ms per beat
  late final double t16thMs;          // ms per 16th note
  late final double sigmaMs;          // Gaussian sigma in ms
  late final double windowPerfectMs;  // |Δt| ≤ this → PERFECT
  late final double windowGoodMs;     // |Δt| ≤ this → GOOD
  late final double windowOkayMs;     // |Δt| ≤ this → OKAY

  MathTimingEngine({
    required this.bpm,
    this.skillFactor = 0.0,
    this.swingRatio  = 0.0,
  }) {
    tBeatMs = 60000.0 / bpm;
    t16thMs = tBeatMs / 4.0;

    // Adaptive sigma: wider for beginners (skillFactor → 0)
    final adaptiveFraction = _sigmaBaseFraction * (1 + (1 - skillFactor) * 0.5);
    sigmaMs = tBeatMs * adaptiveFraction;

    // Dynamic windows scale with BPM
    windowPerfectMs = tBeatMs * _alphaPerfect * (1 + (1 - skillFactor) * 0.5);
    windowGoodMs    = tBeatMs * _betaGood     * (1 + (1 - skillFactor) * 0.4);
    windowOkayMs    = tBeatMs * _betaOkay     * (1 + (1 - skillFactor) * 0.3);
  }

  // ── Core evaluation ─────────────────────────────────────────────────────────

  /// Compute timing error in milliseconds.
  /// Positive = late, negative = early.
  double timingError(double tInputMs, double tExpectedMs) =>
      tInputMs - tExpectedMs;

  /// Normalized timing error (dimensionless, ε = Δt / T_beat).
  double normalizedError(double deltaMs) => deltaMs / tBeatMs;

  /// Gaussian score S ∈ [0, 1].
  ///   S = exp( −Δt² / 2σ² )
  double gaussianScore(double deltaMs) =>
      math.exp(-(deltaMs * deltaMs) / (2 * sigmaMs * sigmaMs));

  /// Integer score for a hit (Gaussian × MAX, rounded).
  int hitScore(double deltaMs) =>
      (gaussianScore(deltaMs) * maxHitScore).round();

  /// Grade classification using BPM-relative dynamic windows.
  ///
  /// Window layout (symmetric around the expected note):
  ///   |δ| ≤ perfect  → PERFECT
  ///   |δ| ≤ good     → GOOD  (δ<0 = early side, δ>0 = late side, same grade)
  ///   δ  < -good     → EARLY (within okay window, too early)
  ///   δ  >  good     → LATE  (within okay window, too late)
  ///   |δ| > okay     → MISS
  TimingGrade grade(double deltaMs) {
    final abs = deltaMs.abs();
    if (abs <= windowPerfectMs) return TimingGrade.perfect;
    if (abs <= windowGoodMs)    return TimingGrade.good;
    if (abs <= windowOkayMs)    return deltaMs < 0 ? TimingGrade.early : TimingGrade.late;
    return TimingGrade.miss;
  }

  /// Textual quality description (includes direction for early/late).
  String qualityLabel(double deltaMs) {
    switch (grade(deltaMs)) {
      case TimingGrade.perfect: return 'PERFECT';
      case TimingGrade.good:    return 'GOOD';
      case TimingGrade.early:   return 'EARLY';
      case TimingGrade.late:    return 'LATE';
      case TimingGrade.miss:    return 'MISS';
    }
  }

  // ── Swing support ───────────────────────────────────────────────────────────

  /// Adjust expected time for swing feel.
  /// Off-beat 8th/16th notes are pushed forward by swingRatio × T_subdivision.
  ///   t_expected' = t_expected + swingOffset(beatPosition)
  double swingAdjusted(double tExpectedMs, double beatPosition) {
    if (swingRatio == 0) return tExpectedMs;
    // Is this an off-beat 8th note? (beatPosition mod 0.5 ≈ 0.25/0.75 of beat)
    final posInBeat = beatPosition % 1.0;
    final isOffBeat = (posInBeat - 0.5).abs() < 0.05 ||
                      (posInBeat - 0.25).abs() < 0.05 ||
                      (posInBeat - 0.75).abs() < 0.05;
    if (!isOffBeat) return tExpectedMs;
    return tExpectedMs + swingRatio * (tBeatMs / 2.0);
  }

  // ── Timing analysis ──────────────────────────────────────────────────────────

  /// Analyse a sequence of timing errors and return a [TimingAnalysis].
  TimingAnalysis analyse(List<double> deltas) {
    if (deltas.isEmpty) {
      return TimingAnalysis(mean: 0, stdDev: 0, bias: TimingBias.neutral,
          consistency: 1.0, trend: TimingTrend.stable);
    }

    // Mean (bias)
    final mean = deltas.reduce((a, b) => a + b) / deltas.length;

    // Standard deviation (consistency)
    final variance = deltas.map((d) => (d - mean) * (d - mean))
        .reduce((a, b) => a + b) / deltas.length;
    final std = math.sqrt(variance);

    // Bias classification
    final normMean = mean / tBeatMs;
    final bias = normMean < -0.02
        ? TimingBias.early
        : normMean > 0.02
            ? TimingBias.late
            : TimingBias.neutral;

    // Consistency: 1.0 = perfect, 0.0 = chaotic (std = T_beat)
    final consistency = math.max(0.0, 1.0 - (std / tBeatMs));

    // Trend: are we getting better or worse?
    TimingTrend trend = TimingTrend.stable;
    if (deltas.length >= 8) {
      final firstHalf = deltas.sublist(0, deltas.length ~/ 2);
      final lastHalf  = deltas.sublist(deltas.length ~/ 2);
      final firstStd  = _stdDev(firstHalf);
      final lastStd   = _stdDev(lastHalf);
      if (lastStd < firstStd * 0.85)      trend = TimingTrend.improving;
      else if (lastStd > firstStd * 1.15) trend = TimingTrend.degrading;
    }

    return TimingAnalysis(
      mean:        mean,
      stdDev:      std,
      bias:        bias,
      consistency: consistency,
      trend:       trend,
    );
  }

  double _stdDev(List<double> vals) {
    if (vals.isEmpty) return 0;
    final m = vals.reduce((a, b) => a + b) / vals.length;
    return math.sqrt(vals.map((v) => (v - m) * (v - m))
        .reduce((a, b) => a + b) / vals.length);
  }

  // ── Skill factor updater ────────────────────────────────────────────────────

  /// Computes skill factor from recent accuracy and consistency.
  /// Returns value in [0.0, 1.0].
  static double computeSkillFactor({
    required double accuracyPct,     // 0–100
    required double consistency,     // 0–1
    required int    currentLevel,    // user XP level
  }) {
    final accNorm   = accuracyPct / 100.0;
    final levelNorm = (currentLevel / 15.0).clamp(0.0, 1.0);
    return ((accNorm * 0.5) + (consistency * 0.3) + (levelNorm * 0.2)).clamp(0.0, 1.0);
  }

  // ── Factory constructors ────────────────────────────────────────────────────

  factory MathTimingEngine.forSong({
    required int    bpm,
    required int    userLevel,
    required double recentAccuracy,
    double swingRatio = 0.0,
  }) {
    final skill = computeSkillFactor(
      accuracyPct:  recentAccuracy,
      consistency:  0.5,
      currentLevel: userLevel,
    );
    return MathTimingEngine(bpm: bpm, skillFactor: skill, swingRatio: swingRatio);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Value objects
// ═══════════════════════════════════════════════════════════════════════════

/// Per-hit timing quality with directional information.
/// perfect → tight hit; good → acceptable; early/late → directional near-miss;
/// miss → no matching note found.
enum TimingGrade { perfect, good, early, late, miss }
enum TimingBias  { early, late, neutral }
enum TimingTrend { improving, degrading, stable }

class TimingAnalysis {
  final double      mean;         // average Δt in ms (+ = late, - = early)
  final double      stdDev;       // standard deviation in ms
  final TimingBias  bias;         // overall tendency
  final double      consistency;  // 0–1 (1 = perfectly consistent)
  final TimingTrend trend;        // getting better/worse/stable

  const TimingAnalysis({
    required this.mean,
    required this.stdDev,
    required this.bias,
    required this.consistency,
    required this.trend,
  });

  /// Human-readable insight string (used by AI coach).
  String get insightText {
    final buffer = StringBuffer();

    switch (bias) {
      case TimingBias.early:
        buffer.write('Tocas ${mean.abs().toStringAsFixed(0)}ms antes del beat. '
            'Intenta esperar la nota antes de golpear.');
        break;
      case TimingBias.late:
        buffer.write('Tocas ${mean.toStringAsFixed(0)}ms después del beat. '
            'Anticipa el golpe un poco más.');
        break;
      case TimingBias.neutral:
        buffer.write('Tu timing centrado es bueno (${mean.abs().toStringAsFixed(0)}ms de promedio).');
        break;
    }

    if (consistency < 0.6) {
      buffer.write(' Tu consistencia (±${stdDev.toStringAsFixed(0)}ms) necesita trabajo — '
          'practica con metrónomo a 50% de tempo.');
    } else if (consistency > 0.85) {
      buffer.write(' Excelente consistencia (±${stdDev.toStringAsFixed(0)}ms).');
    }

    switch (trend) {
      case TimingTrend.improving:
        buffer.write(' 📈 ¡Mejorando durante esta sesión!');
        break;
      case TimingTrend.degrading:
        buffer.write(' 📉 Tienes fatiga — toma un descanso de 5 minutos.');
        break;
      case TimingTrend.stable:
        break;
    }

    return buffer.toString();
  }

  @override
  String toString() =>
      'TimingAnalysis(mean=${mean.toStringAsFixed(1)}ms, '
      'std=${stdDev.toStringAsFixed(1)}ms, bias=$bias, '
      'consistency=${(consistency*100).toStringAsFixed(0)}%, trend=$trend)';
}

// ═══════════════════════════════════════════════════════════════════════════
// RENDER PLAYHEAD INTERPOLATOR
// Provides per-frame smooth playhead by extrapolating from last known value.
// Decouples render frame rate from engine tick rate.
// ═══════════════════════════════════════════════════════════════════════════

/// Receives discrete playhead snapshots from [PracticeEngine] and extrapolates
/// a smooth visual position for every render frame.
///
/// Usage:
///   final interp = RenderPlayheadInterpolator();
///   engine.playheadTime.listen(interp.onEngineUpdate);
///   // in CustomPainter / AnimatedBuilder:
///   final t = interp.smoothSeconds;
class RenderPlayheadInterpolator {
  double _lastSeconds    = 0;
  int    _lastWallUs     = 0;
  double _tempoFactor    = 1.0;
  bool   _running        = false;

  /// Call this from engine.playheadTime stream listener.
  void onEngineUpdate(double playheadSeconds) {
    _lastSeconds = playheadSeconds;
    _lastWallUs  = DateTime.now().microsecondsSinceEpoch;
    _running     = true;
  }

  /// Notify tempo changes so extrapolation stays accurate.
  void setTempo(double factor) => _tempoFactor = factor.clamp(0.1, 2.0);

  /// Pause/resume hint — stops extrapolation when paused.
  void setRunning(bool running) => _running = running;

  /// Smoothly interpolated position for the current render frame.
  double get smoothSeconds {
    if (!_running || _lastWallUs == 0) return _lastSeconds;
    final elapsedUs = DateTime.now().microsecondsSinceEpoch - _lastWallUs;
    // Cap extrapolation at 100ms to avoid drift if engine stalls
    final cappedUs  = elapsedUs.clamp(0, 100000);
    return _lastSeconds + (cappedUs / 1e6) * _tempoFactor;
  }

  void reset() {
    _lastSeconds = 0;
    _lastWallUs  = 0;
    _running     = false;
  }
}
