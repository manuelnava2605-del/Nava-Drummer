// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Performance Analyzer
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math' as math;
import '../../domain/entities/entities.dart';

class HitData {
  final double  deltaMs;
  final int     velocity;
  final DrumPad drum;
  final double  bpm;
  final bool    isPerfect;
  final bool    isMiss;
  final bool    inFill;
  final int     noteIndex;

  const HitData({
    required this.deltaMs,   required this.velocity,
    required this.drum,      required this.bpm,
    required this.isPerfect, required this.isMiss,
    required this.inFill,    required this.noteIndex,
  });
}

enum IssueType {
  timingLate, timingEarly, timingUnstable,
  velocityWeak, velocityStrong, velocityUnstable,
  missRate, fillBreakdown, transitionError, coordination, transitions,
}

class PerformanceIssue {
  final IssueType type;
  final DrumPad   drum;
  final double    severity;
  final double    frequency;
  final double    priority;
  final double    mean;
  final double    std;
  final int       sampleSize;

  const PerformanceIssue({
    required this.type,      required this.drum,
    required this.severity,  required this.frequency,
    required this.priority,  required this.mean,
    required this.std,       required this.sampleSize,
  });
}

class PerformanceAnalyzer {

  List<PerformanceIssue> analyse(List<HitData> hits, {int totalNotes = 0}) {
    if (hits.isEmpty) return [];
    final total = totalNotes > 0 ? totalNotes : hits.length;
    final byDrum = <DrumPad, List<HitData>>{};
    for (final h in hits) byDrum.putIfAbsent(h.drum, () => []).add(h);

    final issues = <PerformanceIssue>[];

    for (final entry in byDrum.entries) {
      final pad       = entry.key;
      final drumHits  = entry.value;
      final frequency = drumHits.length / total;

      final timedHits = drumHits.where((h) => !h.isMiss).toList();
      final deltas    = timedHits.map((h) => h.deltaMs).toList();

      if (deltas.length >= 3) {
        final mean  = _mean(deltas);
        final std   = _std(deltas, mean);
        final tBeat = drumHits.first.bpm > 0 ? 60000 / drumHits.first.bpm : 500.0;

        if (mean > _timingThreshold(drumHits.first.bpm)) {
          final sev = (mean / (tBeat * 0.3)).clamp(0.0, 1.0);
          issues.add(PerformanceIssue(
            type: IssueType.timingLate, drum: pad,
            severity: sev.toDouble(), frequency: frequency.toDouble(),
            priority: (sev * frequency).toDouble(), mean: mean, std: std,
            sampleSize: deltas.length,
          ));
        } else if (mean < -_timingThreshold(drumHits.first.bpm)) {
          final sev = (mean.abs() / (tBeat * 0.3)).clamp(0.0, 1.0);
          issues.add(PerformanceIssue(
            type: IssueType.timingEarly, drum: pad,
            severity: sev.toDouble(), frequency: frequency.toDouble(),
            priority: (sev * frequency).toDouble(), mean: mean, std: std,
            sampleSize: deltas.length,
          ));
        }

        if (std > _consistencyThreshold(drumHits.first.bpm)) {
          final sev = (std / (tBeat * 0.25)).clamp(0.0, 1.0);
          issues.add(PerformanceIssue(
            type: IssueType.timingUnstable, drum: pad,
            severity: sev.toDouble(), frequency: frequency.toDouble(),
            priority: (sev * frequency * 0.8).toDouble(), mean: mean, std: std,
            sampleSize: deltas.length,
          ));
        }
      }

      final velocities = timedHits.map((h) => h.velocity.toDouble()).toList();
      if (velocities.length >= 3) {
        final vMean = _mean(velocities);
        final vStd  = _std(velocities, vMean);

        if (vMean < 40) {
          final sev = (1 - vMean / 40).clamp(0.0, 1.0);
          issues.add(PerformanceIssue(
            type: IssueType.velocityWeak, drum: pad,
            severity: sev.toDouble(), frequency: frequency.toDouble(),
            priority: (sev * frequency * 0.6).toDouble(),
            mean: vMean, std: vStd, sampleSize: velocities.length,
          ));
        }

        final cv = vMean > 0 ? vStd / vMean : 0.0;
        if (cv > 0.35) {
          issues.add(PerformanceIssue(
            type: IssueType.velocityUnstable, drum: pad,
            severity: cv.clamp(0.0, 1.0).toDouble(), frequency: frequency.toDouble(),
            priority: (cv * frequency * 0.5).toDouble(),
            mean: vMean, std: vStd, sampleSize: velocities.length,
          ));
        }
      }

      final missCount = drumHits.where((h) => h.isMiss).length;
      final missRate  = missCount / drumHits.length;
      if (missRate > 0.15 && drumHits.length >= 5) {
        issues.add(PerformanceIssue(
          type: IssueType.missRate, drum: pad,
          severity: missRate.clamp(0.0, 1.0).toDouble(), frequency: frequency.toDouble(),
          priority: (missRate * frequency * 1.2).toDouble(),
          mean: missRate * 100, std: 0, sampleSize: drumHits.length,
        ));
      }

      final fillHits = drumHits.where((h) => h.inFill).toList();
      if (fillHits.length >= 3) {
        final fillMisses = fillHits.where((h) => h.isMiss).length;
        final fillErr    = fillMisses / fillHits.length;
        if (fillErr > 0.25) {
          issues.add(PerformanceIssue(
            type: IssueType.fillBreakdown, drum: pad,
            severity: fillErr.clamp(0.0, 1.0).toDouble(),
            frequency: (fillHits.length / total).toDouble(),
            priority: (fillErr * 0.7).toDouble(),
            mean: fillErr * 100, std: 0, sampleSize: fillHits.length,
          ));
        }
      }

      int transitionErrors = 0;
      for (int i = 1; i < drumHits.length; i++) {
        if (!drumHits[i-1].inFill && drumHits[i].inFill) continue;
        if (drumHits[i-1].inFill && !drumHits[i].inFill) {
          if (drumHits[i].isMiss || drumHits[i].deltaMs.abs() > 50) transitionErrors++;
        }
      }
      if (transitionErrors >= 2) {
        final sev = (transitionErrors / 5).clamp(0.0, 1.0);
        issues.add(PerformanceIssue(
          type: IssueType.transitionError, drum: pad,
          severity: sev.toDouble(), frequency: frequency.toDouble(),
          priority: (sev * 0.6).toDouble(),
          mean: transitionErrors.toDouble(), std: 0, sampleSize: drumHits.length,
        ));
      }
    }

    issues.sort((a, b) => b.priority.compareTo(a.priority));
    return issues;
  }

  Map<DrumPad, DrumMetrics> computeDrumMetrics(List<HitData> hits) {
    final byDrum = <DrumPad, List<HitData>>{};
    for (final h in hits) byDrum.putIfAbsent(h.drum, () => []).add(h);

    return byDrum.map((pad, drumHits) {
      final timed  = drumHits.where((h) => !h.isMiss).toList();
      final deltas = timed.map((h) => h.deltaMs).toList();
      final vels   = timed.map((h) => h.velocity.toDouble()).toList();
      final tBeat  = drumHits.first.bpm > 0 ? 60000 / drumHits.first.bpm : 500.0;

      final dMean    = deltas.isNotEmpty ? _mean(deltas) : 0.0;
      final dStd     = deltas.length > 1 ? _std(deltas, dMean) : tBeat * 0.3;
      final vMean    = vels.isNotEmpty ? _mean(vels) : 64.0;
      final vStd     = vels.length > 1 ? _std(vels, vMean) : 30.0;
      final missRate = drumHits.where((h) => h.isMiss).length / drumHits.length;

      final timingScore = math.max(0.0, 100 - (dStd / tBeat * 100)).clamp(0.0, 100.0);
      final consScore   = math.max(0.0, 100 - (dStd / 30) * 100).clamp(0.0, 100.0);
      final velScore    = vMean > 0
          ? math.max(0.0, 100 - (vStd / vMean * 100)).clamp(0.0, 100.0)
          : 50.0;

      return MapEntry(pad, DrumMetrics(
        timingScore:      timingScore.toDouble(),
        consistencyScore: consScore.toDouble(),
        velocityScore:    velScore.toDouble(),
        missRate:         missRate,
        meanDeltaMs:      dMean,
        stdDeltaMs:       dStd,
        hits:             drumHits.length,
      ));
    });
  }

  double _mean(List<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

  double _std(List<double> v, double mean) {
    if (v.length < 2) return 0;
    return math.sqrt(v.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / v.length);
  }

  double _timingThreshold(double bpm) {
    if (bpm <= 0) return 12;
    return (8 + (bpm - 60) / 120 * 7).clamp(8.0, 20.0);
  }

  double _consistencyThreshold(double bpm) {
    if (bpm <= 0) return 20;
    return (15 + (bpm - 60) / 120 * 15).clamp(15.0, 35.0);
  }
}

class DrumMetrics {
  final double timingScore, consistencyScore, velocityScore;
  final double missRate, meanDeltaMs, stdDeltaMs;
  final int    hits;
  const DrumMetrics({
    required this.timingScore,      required this.consistencyScore,
    required this.velocityScore,    required this.missRate,
    required this.meanDeltaMs,      required this.stdDeltaMs,
    required this.hits,
  });
}
