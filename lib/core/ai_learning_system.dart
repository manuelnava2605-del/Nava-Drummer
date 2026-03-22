// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — AI Coach System  (Phase 3 — Full Upgrade)
//
// NEW in this version:
//   • Velocity tracking per pad  (std dev of velocity = control quality)
//   • Priority ranking: priority = severity × frequency
//   • Pattern-specific error detection (fill transitions, high-density sections)
//   • Session Summary: top 3 prioritised issues + trend display
//   • Audio click feedback integration flag
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math' as math;
import '../domain/entities/entities.dart';
import 'global_timing_controller.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AICoachSystem  (renamed from AILearningSystem for clarity)
// ═══════════════════════════════════════════════════════════════════════════
class AICoachSystem {
  static final AICoachSystem instance = AICoachSystem._();
  AICoachSystem._();

  // Long-term session history (last 50)
  final List<SessionInsight> _history = [];

  // ══════════════════════════════════════════════════════════════════════════
  // MAIN ANALYSIS ENTRY POINT
  // ══════════════════════════════════════════════════════════════════════════
  SessionInsight analyse(PerformanceSession session) {
    final te = session.timingEngine as MathTimingEngine?
        ?? MathTimingEngine(bpm: session.song.bpm);

    // ── 1. Collect per-pad data from hit results ─────────────────────────
    final Map<DrumPad, List<double>> padDeltas      = {};
    final Map<DrumPad, List<int>>    padVelocities  = {};
    final Map<DrumPad, int>          padMissCount   = {};
    final Map<DrumPad, int>          padHitCount    = {};

    // Pattern context tracking: detect fill transitions
    final List<_NoteContext> noteContexts = [];
    for (int i = 0; i < session.hitResults.length; i++) {
      final r = session.hitResults[i];
      // Note density: count notes in ±200ms window
      int density = 0;
      for (final other in session.hitResults) {
        if ((other.expected.timeSeconds - r.expected.timeSeconds).abs() < 0.2) density++;
      }
      noteContexts.add(_NoteContext(
        result:  r,
        density: density,
        isFill:  density >= 4, // 4+ notes in 200ms = fill
      ));

      final pad = r.expected.pad;
      padHitCount[pad] = (padHitCount[pad] ?? 0) + 1;

      if (r.grade == HitGrade.miss) {
        padMissCount[pad] = (padMissCount[pad] ?? 0) + 1;
        continue;
      }
      padDeltas.putIfAbsent(pad, () => []).add(r.timingDeltaMs);
      padVelocities.putIfAbsent(pad, () => []).add(
          r.actual?.velocity ?? r.expected.velocity);
    }

    // ── 2. Build per-drum insights ────────────────────────────────────────
    final Map<DrumPad, DrumInsight> drumInsights = {};
    final allPads = {...padDeltas.keys, ...padMissCount.keys};

    for (final pad in allPads) {
      final deltas    = padDeltas[pad]    ?? [];
      final vels      = padVelocities[pad] ?? [];
      final misses    = padMissCount[pad]  ?? 0;
      final hits      = padHitCount[pad]   ?? 0;
      final analysis  = deltas.length >= 3 ? te.analyse(deltas) : null;

      // Velocity consistency: coeff of variation
      double velConsistency = 1.0;
      double velMean        = 0;
      double velStd         = 0;
      if (vels.length >= 3) {
        velMean        = vels.reduce((a,b)=>a+b) / vels.length;
        velStd         = _stdDev(vels.map((v)=>v.toDouble()).toList(), velMean);
        velConsistency = velMean > 0 ? (1 - velStd / velMean).clamp(0, 1) : 1;
      }

      // Pattern-specific: fill error rate
      final fillContexts = noteContexts.where((c) => c.result.expected.pad == pad && c.isFill).toList();
      final fillMisses   = fillContexts.where((c) => c.result.grade == HitGrade.miss).length;
      final fillErrorRate = fillContexts.isEmpty ? 0.0 : fillMisses / fillContexts.length;

      // Transition errors: notes immediately after a fill
      final transitionErrors = _detectTransitionErrors(pad, noteContexts);

      drumInsights[pad] = DrumInsight(
        pad:              pad,
        hitCount:         hits,
        missCount:        misses,
        missRate:         hits > 0 ? misses / hits : 0,
        meanDeltaMs:      analysis?.mean      ?? 0,
        stdDeltaMs:       analysis?.stdDev    ?? 0,
        bias:             analysis?.bias      ?? TimingBias.neutral,
        consistency: (analysis?.consistency ?? 0.5).toDouble(),
        trend:            analysis?.trend     ?? TimingTrend.stable,
        velMean:          velMean,
        velStd:           velStd,
        velConsistency:   velConsistency,
        fillErrorRate:    fillErrorRate,
        transitionErrors: transitionErrors,
      );
    }

    // ── 3. Global analysis ────────────────────────────────────────────────
    final globalDeltas   = padDeltas.values.expand((v) => v).toList();
    final globalAnalysis = globalDeltas.length >= 5 ? te.analyse(globalDeltas) : null;

    // ── 4. Skill vector ───────────────────────────────────────────────────
    final skillVector = _computeSkillVector(session, globalAnalysis, drumInsights);

    // ── 5. Prioritised issues (priority = severity × frequency) ──────────
    final issues = _rankIssues(drumInsights, globalAnalysis, session);

    // ── 6. Insights (top 3 by priority) ──────────────────────────────────
    final insights = _generateInsights(session, drumInsights, globalAnalysis, issues);

    // ── 7. Exercise recommendations ───────────────────────────────────────
    final exercises = _recommendExercises(issues, skillVector, session, drumInsights);

    // ── 8. Session summary (top 3 issues) ────────────────────────────────
    final summary = SessionSummary(
      letterGrade:    session.letterGrade,
      topIssues:      issues.take(3).toList(),
      skillVector:    skillVector,
      improvementTip: issues.isNotEmpty ? exercises.firstOrNull?.description ?? '' : '¡Excelente sesión!',
      trend:          globalAnalysis?.trend ?? TimingTrend.stable,
    );

    final result = SessionInsight(
      sessionId:     session.id,
      songTitle:     session.song.title,
      playedAt:      session.startedAt,
      skillVector:   skillVector,
      drumInsights:  drumInsights,
      globalAnalysis:globalAnalysis,
      insights:      insights,
      exercises:     exercises,
      summary:       summary,
    );

    _history.add(result);
    if (_history.length > 50) _history.removeAt(0);
    return result;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRIORITY RANKING  priority = severity × frequency
  // ══════════════════════════════════════════════════════════════════════════
  List<PrioritisedIssue> _rankIssues(
    Map<DrumPad, DrumInsight> drums,
    TimingAnalysis? global,
    PerformanceSession session,
  ) {
    final issues = <PrioritisedIssue>[];

    for (final entry in drums.entries) {
      final pad = entry.key;
      final di  = entry.value;

      if (di.hitCount < 3) continue; // not enough data

      // Issue 1: Timing bias
      if (di.meanDeltaMs.abs() > 15 && di.hitCount >= 5) {
        final severity  = (di.meanDeltaMs.abs() / 100).clamp(0, 1.0);
        final frequency = (di.hitCount / (session.hitResults.length + 1)).clamp(0, 1.0);
        issues.add(PrioritisedIssue(
          type:      IssueType.timingBias,
          pad:       pad,
          priority: (severity * frequency).toDouble(),
          severity: (severity).toDouble(),
          frequency: (frequency).toDouble(),
          detail:    '${pad.displayName} ${di.bias == TimingBias.early ? "temprano" : "tarde"}: '
                     '${di.meanDeltaMs.abs().toStringAsFixed(0)}ms',
        ));
      }

      // Issue 2: Timing inconsistency
      if (di.stdDeltaMs > 25 && di.hitCount >= 5) {
        final severity  = (di.stdDeltaMs / 100).clamp(0, 1.0);
        final frequency = (di.hitCount / (session.hitResults.length + 1)).clamp(0, 1.0);
        issues.add(PrioritisedIssue(
          type:      IssueType.inconsistency,
          pad:       pad,
          priority: (severity * frequency).toDouble(),
          severity: (severity).toDouble(),
          frequency: (frequency).toDouble(),
          detail:    '${pad.displayName} inconsistente: ±${di.stdDeltaMs.toStringAsFixed(0)}ms',
        ));
      }

      // Issue 3: Velocity inconsistency
      if (di.velConsistency < 0.6 && di.hitCount >= 5) {
        final severity  = 1 - di.velConsistency;
        final frequency = (di.hitCount / (session.hitResults.length + 1)).clamp(0, 1.0);
        issues.add(PrioritisedIssue(
          type:      IssueType.velocityControl,
          pad:       pad,
          priority: (severity * frequency * 0.7).toDouble(), // velocity less critical than timing
          severity: (severity).toDouble(),
          frequency: (frequency).toDouble(),
          detail:    '${pad.displayName} dinámica irregular: std=${di.velStd.toStringAsFixed(0)}',
        ));
      }

      // Issue 4: High miss rate
      if (di.missRate > 0.2 && di.hitCount >= 5) {
        final severity  = di.missRate.clamp(0, 1.0);
        final frequency = (di.hitCount / (session.hitResults.length + 1)).clamp(0, 1.0);
        issues.add(PrioritisedIssue(
          type:      IssueType.misses,
          pad:       pad,
          priority: (severity * frequency * 1.2).toDouble(), // misses are high priority
          severity: (severity).toDouble(),
          frequency: (frequency).toDouble(),
          detail:    '${pad.displayName} ${(di.missRate*100).toStringAsFixed(0)}% de fallos',
        ));
      }

      // Issue 5: Fill errors
      if (di.fillErrorRate > 0.3) {
        issues.add(PrioritisedIssue(
          type:      IssueType.fillErrors,
          pad:       pad,
          priority: (di.fillErrorRate * 0.8).toDouble(),
          severity: (di.fillErrorRate).toDouble(),
          frequency: (di.fillErrorRate).toDouble(),
          detail:    '${pad.displayName} falla en fills: ${(di.fillErrorRate*100).toStringAsFixed(0)}%',
        ));
      }

      // Issue 6: Transition errors
      if (di.transitionErrors > 2) {
        issues.add(PrioritisedIssue(
          type:      IssueType.transitions,
          pad:       pad,
          priority: (di.transitionErrors / 10).clamp(0.0, 1.0) * 0.6,
          severity: (di.transitionErrors / 10).clamp(0.0, 1.0),
          frequency: (di.hitCount / (session.hitResults.length + 1)).clamp(0.0, 1.0),
          detail:    '${pad.displayName} ${di.transitionErrors} errores en transiciones',
        ));
      }
    }

    // Sort by priority descending
    issues.sort((a, b) => b.priority.compareTo(a.priority));
    return issues;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INSIGHT GENERATOR
  // ══════════════════════════════════════════════════════════════════════════
  List<CoachInsight> _generateInsights(
    PerformanceSession session,
    Map<DrumPad, DrumInsight> drums,
    TimingAnalysis? global,
    List<PrioritisedIssue> issues,
  ) {
    final insights = <CoachInsight>[];

    // Top 3 prioritised issues as insights
    for (final issue in issues.take(3)) {
      insights.add(CoachInsight(
        type:     _issueToInsightType(issue.type),
        emoji:    _issueEmoji(issue.type),
        title:    _issueTitle(issue),
        detail:   _issueDetail(issue, drums),
        severity: issue.severity > 0.6 ? InsightSeverity.warning : InsightSeverity.info,
        priority: (issue.priority).toDouble(),
      ));
    }

    // Global trend
    if (global?.trend == TimingTrend.improving) {
      insights.add(CoachInsight(
        type: InsightType.positive, emoji: '📈',
        title: '¡Mejorando en esta sesión!',
        detail: 'Tu timing fue más preciso en la segunda mitad. ¡Sigue así!',
        severity: InsightSeverity.positive, priority: 0.0,
      ));
    } else if (global?.trend == TimingTrend.degrading) {
      insights.add(CoachInsight(
        type: InsightType.fatigue, emoji: '😴',
        title: 'Señales de fatiga',
        detail: 'Tu timing se deterioró hacia el final. Descansa 5–10 minutos.',
        severity: InsightSeverity.warning, priority: 0.3,
      ));
    }

    // High score positive
    if (session.accuracyPercent >= 95) {
      insights.add(CoachInsight(
        type: InsightType.positive, emoji: '🔥',
        title: '¡Sesión perfecta!',
        detail: '${session.accuracyPercent.toStringAsFixed(1)}% — prueba el siguiente nivel de dificultad.',
        severity: InsightSeverity.positive, priority: 0.0,
      ));
    }

    return insights;
  }

  String _issueTitle(PrioritisedIssue issue) {
    switch (issue.type) {
      case IssueType.timingBias:
        return '${issue.pad!.displayName} — '
               '${issue.detail.contains("temprano") ? "tocas temprano" : "tocas tarde"}';
      case IssueType.inconsistency:
        return 'Timing inestable en ${issue.pad!.displayName}';
      case IssueType.velocityControl:
        return 'Dinámica irregular en ${issue.pad!.displayName}';
      case IssueType.misses:
        return 'Muchos fallos en ${issue.pad!.displayName}';
      case IssueType.fillErrors:
        return 'Errores en fills con ${issue.pad!.displayName}';
      case IssueType.transitions:
        return 'Transiciones con ${issue.pad!.displayName}';
      case IssueType.general:
        return 'Área de mejora';
    }
  }

  String _issueDetail(PrioritisedIssue issue, Map<DrumPad, DrumInsight> drums) {
    final di = issue.pad != null ? drums[issue.pad!] : null;
    switch (issue.type) {
      case IssueType.timingBias:
        final dir = di?.bias == TimingBias.early ? 'antes' : 'después';
        return 'Golpeas el ${issue.pad!.displayName} ${di?.meanDeltaMs.abs().toStringAsFixed(0)}ms '
               '$dir del beat. ${di?.bias == TimingBias.early ? "Espera un poco más." : "Anticipa el golpe."}';
      case IssueType.inconsistency:
        return 'Tu variación de timing en ${issue.pad!.displayName} es ±${di?.stdDeltaMs.toStringAsFixed(0)}ms. '
               'Practica con metrónomo a 60% de tempo.';
      case IssueType.velocityControl:
        return 'La fuerza de tus golpes en ${issue.pad!.displayName} varía demasiado '
               '(std: ${di?.velStd.toStringAsFixed(0)}). Practica con volumen constante.';
      case IssueType.misses:
        return 'Fallaste el ${(di?.missRate ?? 0 * 100).toStringAsFixed(0)}% de los golpes de '
               '${issue.pad!.displayName}. Practica ese instrumento aislado.';
      case IssueType.fillErrors:
        return 'Cometes errores al llegar a secciones rápidas con ${issue.pad!.displayName}. '
               'Practica las transiciones fill→groove lentamente.';
      case IssueType.transitions:
        return 'Tienes ${di?.transitionErrors ?? 0} errores de timing justo después de fills. '
               'Practica el "aterrizaje" del fill en el 1 del siguiente compás.';
      case IssueType.general:
        return issue.detail;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EXERCISE RECOMMENDATIONS
  // ══════════════════════════════════════════════════════════════════════════
  List<ExerciseRecommendation> _recommendExercises(
    List<PrioritisedIssue> issues,
    SkillVector skill,
    PerformanceSession session,
    Map<DrumPad, DrumInsight> drums,
  ) {
    final recs = <ExerciseRecommendation>[];

    for (final issue in issues.take(3)) {
      switch (issue.type) {
        case IssueType.timingBias:
          recs.add(ExerciseRecommendation(
            title: 'Corrección de bias — ${issue.pad!.displayName}',
            description: 'Toca solo el ${issue.pad!.displayName} con metrónomo a 70 BPM. '
                         'Después de cada golpe, pregúntate: ¿fui temprano o tarde?',
            targetPads: [issue.pad!],
            durationMin: 5, bpm: 70, icon: '🎯',
          ));
          break;
        case IssueType.inconsistency:
          recs.add(ExerciseRecommendation(
            title: 'Estabilidad de timing — ${issue.pad!.displayName}',
            description: 'Practica solo ${issue.pad!.displayName} en 8os a 60 BPM durante 2 minutos. '
                         'Objetivo: cada golpe dentro de ±10ms del beat.',
            targetPads: [issue.pad!],
            durationMin: 3, bpm: 60, icon: '⏱️',
          ));
          break;
        case IssueType.velocityControl:
          recs.add(ExerciseRecommendation(
            title: 'Control dinámico — ${issue.pad!.displayName}',
            description: 'Practica con 4 niveles de volumen: pp, p, f, ff — 4 compases cada uno. '
                         'Mantén el tempo constante mientras cambias la fuerza.',
            targetPads: [issue.pad!],
            durationMin: 5, bpm: 80, icon: '🔊',
          ));
          break;
        case IssueType.misses:
          recs.add(ExerciseRecommendation(
            title: 'Práctica aislada — ${issue.pad!.displayName}',
            description: 'Toca SOLO el ${issue.pad!.displayName} en la canción actual '
                         'al 60% de tempo. Sin distracciones.',
            targetPads: [issue.pad!],
            durationMin: 5, bpm: (session.song.bpm * 0.6).round(), icon: '🎵',
          ));
          break;
        case IssueType.fillErrors:
          recs.add(ExerciseRecommendation(
            title: 'Práctica de fills',
            description: 'Practica las secciones de fill de esta canción al 50% de tempo. '
                         'Cuando domines el fill, practica la transición fill→groove.',
            targetPads: const [],
            durationMin: 8, bpm: (session.song.bpm * 0.5).round(), icon: '🥁',
          ));
          break;
        case IssueType.transitions:
          recs.add(ExerciseRecommendation(
            title: 'Aterrizaje de fills',
            description: 'Practica el "1" del compás después del fill. '
                         'El tiempo 1 después de un fill debe ser el más fuerte y preciso.',
            targetPads: const [],
            durationMin: 5, bpm: (session.song.bpm * 0.7).round(), icon: '🎯',
          ));
          break;
        case IssueType.general:
          break;
      }
    }

    // Always include slow practice if accuracy is low
    if (skill.accuracy < 70 && recs.none((r) => r.title.contains('lento'))) {
      recs.add(ExerciseRecommendation(
        title: 'Práctica lenta: ${session.song.title}',
        description: 'Toca la canción completa al 60% de tempo. '
                     'La velocidad viene después de la precisión, nunca antes.',
        targetPads: const [],
        durationMin: 10, bpm: (session.song.bpm * 0.6).round(), icon: '🐢',
      ));
    }

    // Challenge if skill is high
    if (skill.accuracy > 90 && skill.timing > 80) {
      recs.add(ExerciseRecommendation(
        title: '¡Siguiente reto!',
        description: 'Estás dominando esta canción. Prueba al 110% de tempo '
                     'o busca una canción de mayor dificultad.',
        targetPads: const [],
        durationMin: 5, bpm: (session.song.bpm * 1.1).round(), icon: '🚀',
      ));
    }

    return recs;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════
  int _detectTransitionErrors(DrumPad pad, List<_NoteContext> contexts) {
    int errors = 0;
    for (int i = 1; i < contexts.length; i++) {
      final prev = contexts[i - 1];
      final curr = contexts[i];
      // Transition = was in fill, now not (or vice versa)
      if (prev.isFill && !curr.isFill && curr.result.expected.pad == pad) {
        if (curr.result.grade == HitGrade.miss ||
            curr.result.timingDeltaMs.abs() > 40) {
          errors++;
        }
      }
    }
    return errors;
  }

  SkillVector _computeSkillVector(PerformanceSession session,
      TimingAnalysis? global, Map<DrumPad, DrumInsight> drums) {
    final timingScore = global != null
        ? (global.consistency * 100).clamp(0, 100)
        : 50.0;
    final accuracyScore = session.accuracyPercent.clamp(0, 100);
    final consistencyScore = drums.isEmpty ? 50.0
        : (drums.values.map((d) => d.consistency * 100)
            .reduce((a, b) => a + b) / drums.length).clamp(0, 100);
    final velocityScore = drums.isEmpty ? 50.0
        : (drums.values.map((d) => d.velConsistency * 100)
            .reduce((a, b) => a + b) / drums.length).clamp(0, 100);
    return SkillVector(timing: (timingScore).toDouble(), accuracy: (accuracyScore).toDouble(),
        consistency: (consistencyScore).toDouble(), velocity: velocityScore.toDouble());
  }

  double _stdDev(List<double> vals, double mean) {
    if (vals.length < 2) return 0;
    return math.sqrt(vals.map((v) => (v - mean) * (v - mean))
        .reduce((a, b) => a + b) / vals.length);
  }

  InsightType _issueToInsightType(IssueType t) {
    switch (t) {
      case IssueType.timingBias:
      case IssueType.inconsistency: return InsightType.timing;
      case IssueType.velocityControl: return InsightType.perDrum;
      case IssueType.misses: return InsightType.perDrum;
      case IssueType.fillErrors:
      case IssueType.transitions: return InsightType.timing;
      case IssueType.general: return InsightType.positive;
    }
  }

  String _issueEmoji(IssueType t) {
    switch (t) {
      case IssueType.timingBias:      return '⏱️';
      case IssueType.inconsistency:   return '📉';
      case IssueType.velocityControl: return '🔊';
      case IssueType.misses:          return '❌';
      case IssueType.fillErrors:      return '🥁';
      case IssueType.transitions:     return '↩️';
      case IssueType.general:         return '💡';
    }
  }

  // Long-term progression
  List<SkillVector> getProgressionHistory({int n = 10}) =>
      _history.takeLast(n).map((s) => s.skillVector).toList();

  SkillDelta computeImprovement({int compareLast = 5}) {
    if (_history.length < 2) return const SkillDelta(timing:0, accuracy:0, consistency:0, velocity:0);
    final recent = _history.takeLast(compareLast).map((s) => s.skillVector).toList();
    final older  = _history.take(_history.length - compareLast).toList();
    if (older.isEmpty) return const SkillDelta(timing:0, accuracy:0, consistency:0, velocity:0);
    final oldAvg = _avg(older.map((s) => s.skillVector).toList());
    final newAvg = _avg(recent);
    return SkillDelta(
      timing: (newAvg.timing      - oldAvg.timing).toDouble(),
      accuracy: (newAvg.accuracy    - oldAvg.accuracy).toDouble(),
      consistency: (newAvg.consistency - oldAvg.consistency).toDouble(),
      velocity: (newAvg.velocity    - oldAvg.velocity).toDouble(),
    );
  }

  SkillVector _avg(List<SkillVector> list) {
    if (list.isEmpty) return const SkillVector(timing:0, accuracy:0, consistency:0, velocity:0);
    return SkillVector(
      timing: list.map((s) => s.timing).reduce((a, b) => a + b) / list.length,
      accuracy: list.map((s) => s.accuracy).reduce((a, b) => a + b) / list.length,
      consistency: list.map((s) => s.consistency).reduce((a, b) => a + b) / list.length,
      velocity: list.map((s) => s.velocity).reduce((a, b) => a + b) / list.length,
    );
  }
}

extension _TakeLast<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
extension _None<T> on List<T> {
  bool none(bool Function(T) test) => !any(test);
}

// ═══════════════════════════════════════════════════════════════════════════
// Value Objects
// ═══════════════════════════════════════════════════════════════════════════

enum IssueType {
  timingBias, inconsistency, velocityControl,
  misses, fillErrors, transitions, general,
}

class PrioritisedIssue {
  final IssueType  type;
  final DrumPad?   pad;
  final double     priority;   // severity × frequency
  final double     severity;
  final double     frequency;
  final String     detail;
  const PrioritisedIssue({
    required this.type, this.pad, required this.priority,
    required this.severity, required this.frequency, required this.detail,
  });
}

class DrumInsight {
  final DrumPad    pad;
  final int        hitCount, missCount;
  final double     missRate;
  final double     meanDeltaMs, stdDeltaMs;
  final TimingBias bias;
  final double     consistency;
  final TimingTrend trend;
  final double     velMean, velStd, velConsistency;
  final double     fillErrorRate;
  final int        transitionErrors;

  const DrumInsight({
    required this.pad,            required this.hitCount,
    required this.missCount,      required this.missRate,
    required this.meanDeltaMs,    required this.stdDeltaMs,
    required this.bias,           required this.consistency,
    required this.trend,          required this.velMean,
    required this.velStd,         required this.velConsistency,
    required this.fillErrorRate,  required this.transitionErrors,
  });
}

class SkillVector {
  final double timing, accuracy, consistency, velocity;
  const SkillVector({
    required this.timing, required this.accuracy,
    required this.consistency, required this.velocity,
  });
  double get overall => (timing + accuracy + consistency + velocity) / 4;
}

class SkillDelta {
  final double timing, accuracy, consistency, velocity;
  const SkillDelta({
    required this.timing, required this.accuracy,
    required this.consistency, required this.velocity,
  });
}

// ── Session Summary (Phase 3 — top 3 issues) ─────────────────────────────────
class SessionSummary {
  final String               letterGrade;
  final List<PrioritisedIssue> topIssues;
  final SkillVector          skillVector;
  final String               improvementTip;
  final TimingTrend          trend;

  const SessionSummary({
    required this.letterGrade,   required this.topIssues,
    required this.skillVector,   required this.improvementTip,
    required this.trend,
  });
}

enum InsightType    { timing, perDrum, tempo, fatigue, positive }
enum InsightSeverity { info, warning, positive }

class CoachInsight {
  final InsightType     type;
  final String          emoji, title, detail;
  final InsightSeverity severity;
  final double          priority;
  const CoachInsight({
    required this.type,     required this.emoji,
    required this.title,    required this.detail,
    required this.severity, this.priority = 0,
  });
}

class ExerciseRecommendation {
  final String         title, description, icon;
  final List<DrumPad>  targetPads;
  final int            durationMin, bpm;
  const ExerciseRecommendation({
    required this.title,       required this.description,
    required this.targetPads,  required this.durationMin,
    required this.bpm,         required this.icon,
  });
}

class SessionInsight {
  final String                       sessionId, songTitle;
  final DateTime                     playedAt;
  final SkillVector                  skillVector;
  final Map<DrumPad, DrumInsight>    drumInsights;
  final TimingAnalysis?              globalAnalysis;
  final List<CoachInsight>           insights;
  final List<ExerciseRecommendation> exercises;
  final SessionSummary               summary;

  const SessionInsight({
    required this.sessionId,     required this.songTitle,
    required this.playedAt,      required this.skillVector,
    required this.drumInsights,  required this.globalAnalysis,
    required this.insights,      required this.exercises,
    required this.summary,
  });
}

// Internal helper
class _NoteContext {
  final HitResult result;
  final int       density;
  final bool      isFill;
  _NoteContext({required this.result, required this.density, required this.isFill});
}
