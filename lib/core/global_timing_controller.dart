// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Global Timing Controller  (Phase 1)
// + Mathematical Timing Engine          (Phase 2)
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math' as math;

class GlobalTimingController {
  static final GlobalTimingController instance = GlobalTimingController._();
  GlobalTimingController._();

  int syncOffsetMicros = 0;
  int userOffsetMicros = 0;
  double _driftCorrectionUs = 0;

  static const int _driftWindowSize = 32;
  final List<_DriftSample> _driftSamples = [];
  int? _sessionStartUs;

  int currentTimeMicros() =>
      DateTime.now().microsecondsSinceEpoch +
      syncOffsetMicros +
      userOffsetMicros +
      _driftCorrectionUs.round();

  int sessionElapsedMicros() {
    if (_sessionStartUs == null) return 0;
    return currentTimeMicros() - _sessionStartUs!;
  }

  double sessionElapsedSeconds() => sessionElapsedMicros() / 1e6;

  void startSession() => _sessionStartUs = currentTimeMicros();

  void applySyncOffset(int measuredLatencyUs) {
    syncOffsetMicros = -measuredLatencyUs;
  }

  void setUserOffsetMs(double ms) {
    userOffsetMicros = (ms * 1000).round();
  }

  double get userOffsetMs => userOffsetMicros / 1000.0;

  void feedDriftSample(int dartUs, int nativeUs) {
    _driftSamples.add(_DriftSample(dartUs: dartUs, nativeUs: nativeUs));
    if (_driftSamples.length > _driftWindowSize) _driftSamples.removeAt(0);
    if (_driftSamples.length >= 4) _estimateDrift();
  }

  void _estimateDrift() {
    double sumDiff = 0;
    for (final s in _driftSamples) {
      sumDiff += (s.nativeUs - s.dartUs);
    }
    _driftCorrectionUs = sumDiff / _driftSamples.length;
  }

  int nativeToGlobal(int nativeTimestampUs) =>
      nativeTimestampUs +
      syncOffsetMicros +
      userOffsetMicros +
      _driftCorrectionUs.round();

  void reset() {
    syncOffsetMicros = 0;
    userOffsetMicros = 0;
    _driftCorrectionUs = 0;
    _sessionStartUs = null;
    _driftSamples.clear();
  }
}

class _DriftSample {
  final int dartUs, nativeUs;
  _DriftSample({required this.dartUs, required this.nativeUs});
}

class MathTimingEngine {
  static const double _alphaPerfect = 0.03;
  static const double _betaGood = 0.08;
  static const double _betaOkay = 0.14;
  static const double _sigmaBaseFraction = 0.10;
  static const int maxHitScore = 1000;

  final int bpm;
  final double skillFactor;
  final double swingRatio;

  late final double tBeatMs;
  late final double t16thMs;
  late final double sigmaMs;
  late final double windowPerfectMs;
  late final double windowGoodMs;
  late final double windowOkayMs;

  MathTimingEngine({
    required this.bpm,
    this.skillFactor = 0.0,
    this.swingRatio = 0.0,
  }) {
    tBeatMs = 60000.0 / bpm;
    t16thMs = tBeatMs / 4.0;

    final adaptiveFraction =
        _sigmaBaseFraction * (1 + (1 - skillFactor) * 0.5);
    sigmaMs = tBeatMs * adaptiveFraction;

    windowPerfectMs =
        tBeatMs * _alphaPerfect * (1 + (1 - skillFactor) * 0.5);
    windowGoodMs = tBeatMs * _betaGood * (1 + (1 - skillFactor) * 0.4);
    windowOkayMs = tBeatMs * _betaOkay * (1 + (1 - skillFactor) * 0.3);
  }

  double timingError(double tInputMs, double tExpectedMs) =>
      tInputMs - tExpectedMs;

  double normalizedError(double deltaMs) => deltaMs / tBeatMs;

  double gaussianScore(double deltaMs) =>
      math.exp(-(deltaMs * deltaMs) / (2 * sigmaMs * sigmaMs));

  int hitScore(double deltaMs) => (gaussianScore(deltaMs) * maxHitScore).round();

  TimingGrade grade(double deltaMs) {
    final abs = deltaMs.abs();
    if (abs <= windowPerfectMs) return TimingGrade.perfect;
    if (abs <= windowGoodMs) return TimingGrade.good;
    if (abs <= windowOkayMs) {
      return deltaMs < 0 ? TimingGrade.early : TimingGrade.late;
    }
    return TimingGrade.miss;
  }

  String qualityLabel(double deltaMs) {
    switch (grade(deltaMs)) {
      case TimingGrade.perfect:
        return 'PERFECT';
      case TimingGrade.good:
        return 'GOOD';
      case TimingGrade.early:
        return 'EARLY';
      case TimingGrade.late:
        return 'LATE';
      case TimingGrade.miss:
        return 'MISS';
    }
  }

  double swingAdjusted(double tExpectedMs, double beatPosition) {
    if (swingRatio == 0) return tExpectedMs;

    final posInBeat = beatPosition % 1.0;
    final isOffBeat = (posInBeat - 0.5).abs() < 0.05 ||
        (posInBeat - 0.25).abs() < 0.05 ||
        (posInBeat - 0.75).abs() < 0.05;

    if (!isOffBeat) return tExpectedMs;
    return tExpectedMs + swingRatio * (tBeatMs / 2.0);
  }

  TimingAnalysis analyse(List<double> deltas) {
    if (deltas.isEmpty) {
      return const TimingAnalysis(
        mean: 0,
        stdDev: 0,
        bias: TimingBias.neutral,
        consistency: 1.0,
        trend: TimingTrend.stable,
      );
    }

    final mean = deltas.reduce((a, b) => a + b) / deltas.length;
    final variance = deltas
            .map((d) => (d - mean) * (d - mean))
            .reduce((a, b) => a + b) /
        deltas.length;
    final std = math.sqrt(variance);

    final normMean = mean / tBeatMs;
    final bias = normMean < -0.02
        ? TimingBias.early
        : normMean > 0.02
            ? TimingBias.late
            : TimingBias.neutral;

    final consistency = math.max(0.0, 1.0 - (std / tBeatMs));

    TimingTrend trend = TimingTrend.stable;
    if (deltas.length >= 8) {
      final firstHalf = deltas.sublist(0, deltas.length ~/ 2);
      final lastHalf = deltas.sublist(deltas.length ~/ 2);
      final firstStd = _stdDev(firstHalf);
      final lastStd = _stdDev(lastHalf);
      if (lastStd < firstStd * 0.85) {
        trend = TimingTrend.improving;
      } else if (lastStd > firstStd * 1.15) {
        trend = TimingTrend.degrading;
      }
    }

    return TimingAnalysis(
      mean: mean,
      stdDev: std,
      bias: bias,
      consistency: consistency,
      trend: trend,
    );
  }

  double _stdDev(List<double> vals) {
    if (vals.isEmpty) return 0;
    final m = vals.reduce((a, b) => a + b) / vals.length;
    return math.sqrt(
      vals.map((v) => (v - m) * (v - m)).reduce((a, b) => a + b) / vals.length,
    );
  }

  static double computeSkillFactor({
    required double accuracyPct,
    required double consistency,
    required int currentLevel,
  }) {
    final accNorm = accuracyPct / 100.0;
    final levelNorm = (currentLevel / 15.0).clamp(0.0, 1.0);
    return ((accNorm * 0.5) + (consistency * 0.3) + (levelNorm * 0.2))
        .clamp(0.0, 1.0);
  }

  factory MathTimingEngine.forSong({
    required int bpm,
    required int userLevel,
    required double recentAccuracy,
    double swingRatio = 0.0,
  }) {
    final skill = computeSkillFactor(
      accuracyPct: recentAccuracy,
      consistency: 0.5,
      currentLevel: userLevel,
    );
    return MathTimingEngine(
      bpm: bpm,
      skillFactor: skill,
      swingRatio: swingRatio,
    );
  }
}

enum TimingGrade { perfect, good, early, late, miss }
enum TimingBias { early, late, neutral }
enum TimingTrend { improving, degrading, stable }

class TimingAnalysis {
  final double mean;
  final double stdDev;
  final TimingBias bias;
  final double consistency;
  final TimingTrend trend;

  const TimingAnalysis({
    required this.mean,
    required this.stdDev,
    required this.bias,
    required this.consistency,
    required this.trend,
  });

  String get insightText {
    final buffer = StringBuffer();

    switch (bias) {
      case TimingBias.early:
        buffer.write(
          'Tocas ${mean.abs().toStringAsFixed(0)}ms antes del beat. '
          'Intenta esperar la nota antes de golpear.',
        );
        break;
      case TimingBias.late:
        buffer.write(
          'Tocas ${mean.toStringAsFixed(0)}ms después del beat. '
          'Anticipa el golpe un poco más.',
        );
        break;
      case TimingBias.neutral:
        buffer.write(
          'Tu timing centrado es bueno (${mean.abs().toStringAsFixed(0)}ms de promedio).',
        );
        break;
    }

    if (consistency < 0.6) {
      buffer.write(
        ' Tu consistencia (±${stdDev.toStringAsFixed(0)}ms) necesita trabajo — '
        'practica con metrónomo a 50% de tempo.',
      );
    } else if (consistency > 0.85) {
      buffer.write(
        ' Excelente consistencia (±${stdDev.toStringAsFixed(0)}ms).',
      );
    }

    switch (trend) {
      case TimingTrend.improving:
        buffer.write(' Mejora durante esta sesión.');
        break;
      case TimingTrend.degrading:
        buffer.write(' Hay fatiga: conviene descansar unos minutos.');
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
      'consistency=${(consistency * 100).toStringAsFixed(0)}%, trend=$trend)';
}

class RenderPlayheadInterpolator {
  double _lastSeconds = 0;
  int _lastWallUs = 0;
  double _tempoFactor = 1.0;
  bool _running = false;

  void onEngineUpdate(double playheadSeconds) {
    _lastSeconds = playheadSeconds;
    _lastWallUs = DateTime.now().microsecondsSinceEpoch;
    _running = true;
  }

  void setTempo(double factor) => _tempoFactor = factor.clamp(0.1, 2.0);
  void setRunning(bool running) => _running = running;

  double get smoothSeconds {
    if (!_running || _lastWallUs == 0) return _lastSeconds;
    final elapsedUs = DateTime.now().microsecondsSinceEpoch - _lastWallUs;
    final cappedUs = elapsedUs.clamp(0, 100000);
    return _lastSeconds + (cappedUs / 1e6) * _tempoFactor;
  }

  void reset() {
    _lastSeconds = 0;
    _lastWallUs = 0;
    _running = false;
  }
}
