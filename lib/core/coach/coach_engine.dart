import 'dart:math' as math;
// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Coach Engine  /core/coach/coach_engine.dart
// Main orchestrator: Practice Engine → Coach Engine → Insights + Recommendations
//
// Pipeline:
//   1. Receive session data (HitData list)
//   2. PerformanceAnalyzer → ranked PerformanceIssues
//   3. InsightGenerator    → human-readable CoachMessages (max 3)
//   4. RecommendationEngine → PracticeRecommendations
//   5. SkillModel.update    → EMA skill progression
//   6. Return CoachReport
// ─────────────────────────────────────────────────────────────────────────────
import '../../domain/entities/entities.dart';
import 'performance_analyzer.dart';
import 'insight_generator.dart';
import 'skill_model.dart';

// ── Full coach report returned after each session ─────────────────────────────
class CoachReport {
  // Session basics
  final String   sessionId;
  final Song     song;
  final DateTime playedAt;
  final double   accuracyPct;
  final int      maxCombo;

  // Analysis
  final List<PerformanceIssue>      issues;       // ranked by priority
  final List<CoachMessage>           messages;     // human-readable (max 3)
  final List<PracticeRecommendation> exercises;    // what to practice next

  // Skill update
  final SkillDimensions skillsBefore;
  final SkillDimensions skillsAfter;
  final SkillTrend      trend;
  final SkillDelta      delta;

  // Per-drum metrics
  final Map<DrumPad, DrumMetrics> drumMetrics;

  const CoachReport({
    required this.sessionId,   required this.song,
    required this.playedAt,    required this.accuracyPct,
    required this.maxCombo,    required this.issues,
    required this.messages,    required this.exercises,
    required this.skillsBefore,required this.skillsAfter,
    required this.trend,       required this.delta,
    required this.drumMetrics,
  });

  /// True if this is considered a "successful" session.
  bool get isGoodSession => accuracyPct >= 75;

  /// The single most important thing to work on.
  String get topPriority {
    if (issues.isEmpty) return '¡Sigue practicando!';
    final top = issues.first;
    return '${top.drum.displayName}: ${_issueLabel(top.type)}';
  }

  static String _issueLabel(IssueType t) {
    switch (t) {
      case IssueType.timingLate:      return 'Timing tarde';
      case IssueType.timingEarly:     return 'Timing temprano';
      case IssueType.timingUnstable:  return 'Timing inestable';
      case IssueType.velocityWeak:    return 'Golpes débiles';
      case IssueType.velocityStrong:  return 'Golpes fuertes';
      case IssueType.velocityUnstable:return 'Dinámica irregular';
      case IssueType.missRate:        return 'Muchos fallos';
      case IssueType.fillBreakdown:   return 'Errores en fills';
      case IssueType.transitionError: return 'Transiciones';
      case IssueType.coordination:    return 'Coordinación';
      case IssueType.transitions:     return 'Transiciones';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CoachEngine — singleton, stateless except for SkillModel
// ═══════════════════════════════════════════════════════════════════════════
class CoachEngine {
  static final CoachEngine instance = CoachEngine._();
  CoachEngine._();

  final _analyzer      = PerformanceAnalyzer();
  final _insights      = InsightGenerator();
  final _recommender   = RecommendationEngine();
  final _skillModel    = SkillModel.instance;

  // ══════════════════════════════════════════════════════════════════════════
  // processSession — main entry point called by PracticeEngine after finish()
  // ══════════════════════════════════════════════════════════════════════════
  CoachReport processSession(PerformanceSession session) {
    // 1. Convert HitResults → HitData
    final hitData = _toHitData(session);

    // 2. Skill snapshot before update
    final skillsBefore = _skillModel.skills.copyWith();

    // 3. Analyse performance
    final issues = _analyzer.analyse(hitData, totalNotes: session.hitResults.length);

    // 4. Per-drum metrics
    final drumMetrics = _analyzer.computeDrumMetrics(hitData);

    // 5. Generate insights (max 3, human language)
    final messages = _insights.generate(
      issues,
      accuracyPct: (session.accuracyPercent).toDouble(),
      maxInsights: 3,
      combo:       session.maxCombo,
    );

    // 6. Recommendations
    final exercises = _recommender.recommend(
      issues,
      accuracyPct: (session.accuracyPercent).toDouble(),
      songBpm:     session.song.bpm,
      song:        session.song,
    );

    // 7. Update SkillModel with EMA
    _updateSkillModel(session, drumMetrics);

    // 8. Skill snapshot after
    final skillsAfter = _skillModel.skills.copyWith();

    return CoachReport(
      sessionId:    session.id,
      song:         session.song,
      playedAt:     session.startedAt,
      accuracyPct: (session.accuracyPercent).toDouble(),
      maxCombo:     session.maxCombo,
      issues:       issues,
      messages:     messages,
      exercises:    exercises,
      skillsBefore: skillsBefore,
      skillsAfter:  skillsAfter,
      trend:        _skillModel.trend,
      delta:        _skillModel.skillDelta(),
      drumMetrics:  drumMetrics,
    );
  }

  // ── Convert domain HitResult → HitData ────────────────────────────────────
  List<HitData> _toHitData(PerformanceSession session) {
    final hits = <HitData>[];

    for (int i = 0; i < session.hitResults.length; i++) {
      final r = session.hitResults[i];

      // Detect fill context: 4+ notes within 200ms window
      int density = 0;
      final centerTime = r.expected.timeSeconds;
      for (final other in session.hitResults) {
        if ((other.expected.timeSeconds - centerTime).abs() < 0.2) density++;
      }

      hits.add(HitData(
        deltaMs:   r.timingDeltaMs,
        velocity: r.actual?.velocity ?? r.expected.velocity,
        drum:      r.expected.pad,
        bpm:       session.song.bpm.toDouble(),
        isPerfect: r.grade == HitGrade.perfect,
        isMiss:    r.grade == HitGrade.miss,
        inFill:    density >= 4,
        noteIndex: i,
      ));
    }
    return hits;
  }

  // ── Update SkillModel ──────────────────────────────────────────────────────
  void _updateSkillModel(
    PerformanceSession session,
    Map<DrumPad, DrumMetrics> drumMetrics,
  ) {
    // Compute global skill signals
    final allDeltas = session.hitResults
        .where((r) => r.grade != HitGrade.miss)
        .map((r) => r.timingDeltaMs)
        .toList();

    double timingScore      = 50;
    double consistencyScore = 50;

    if (allDeltas.isNotEmpty) {
      final mean = allDeltas.reduce((a,b)=>a+b) / allDeltas.length;
      final std  = _std(allDeltas, mean);
      final tBeat = session.song.bpm > 0 ? 60000 / session.song.bpm : 500;
      timingScore      = (100 - (mean.abs() / tBeat * 100)).clamp(0, 100);
      consistencyScore = (100 - (std / tBeat * 100)).clamp(0, 100);
    }

    // Velocity consistency (global)
    final vels = session.hitResults
        .where((r) => r.grade != HitGrade.miss)
        .map((r) => (r.actual?.velocity ?? r.expected.velocity).toDouble())
        .toList();
    double velocityScore = 50;
    if (vels.length >= 3) {
      final vMean = vels.reduce((a,b)=>a+b) / vels.length;
      final vStd  = _std(vels, vMean);
      velocityScore = vMean > 0 ? (100 - (vStd / vMean * 100)).clamp(0, 100) : 50;
    }

    // Read-ahead: estimated from how early perfect hits were detected
    final earlyPerfects = session.hitResults
        .where((r) => r.grade == HitGrade.perfect && r.timingDeltaMs < -5)
        .length;
    final readAheadScore = session.hitResults.isNotEmpty
        ? (earlyPerfects / session.hitResults.length * 200).clamp(0, 100)
        : 50;

    // Convert DrumMetrics to DrumSessionData
    final drumData = <DrumPad, DrumSessionData>{};
    drumMetrics.forEach((pad, m) { drumData[pad] = DrumSessionData(
      timingScore: (m.timingScore).toDouble(),
      consistencyScore: (m.consistencyScore).toDouble(),
      velocityScore: (m.velocityScore).toDouble(),
      hits:             m.hits,
    ); });

    _skillModel.updateFromSession(
      timingPct: (timingScore).toDouble(),
      accuracyPct: (session.accuracyPercent).toDouble(),
      consistencyPct: (consistencyScore).toDouble(),
      velocityPct: (velocityScore).toDouble(),
      readAheadPct: (readAheadScore).toDouble(),
      drumData:       drumData,
      song:           session.song,
    );
  }

  double _std(List<double> vals, double mean) {
    if (vals.length < 2) return 0;
    return math.sqrt(vals.map((v) => (v-mean)*(v-mean))
        .reduce((a,b)=>a+b) / vals.length);
  }

  // ── Accessors ──────────────────────────────────────────────────────────────
  SkillDimensions get currentSkills => _skillModel.skills;
  SkillTrend      get trend         => _skillModel.trend;
  DrumPad?        get weakestDrum   => _skillModel.weakestDrum;
  DrumPad?        get strongestDrum => _skillModel.strongestDrum;
}
