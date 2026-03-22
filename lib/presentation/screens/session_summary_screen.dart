// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Session Summary Screen
// Uses CoachReport for real data: issues, messages, exercises, skill progression
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../domain/entities/entities.dart';
import '../../core/coach/coach.dart';
import '../theme/nava_theme.dart';

class SessionSummaryScreen extends StatelessWidget {
  final PerformanceSession session;
  final CoachReport        report;
  final VoidCallback       onRetry;
  final VoidCallback       onExit;

  const SessionSummaryScreen({
    super.key,
    required this.session,
    required this.report,
    required this.onRetry,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavaTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(children: [

            // ── Grade + Skill delta ───────────────────────────────────────
            _GradeHeader(session: session, report: report)
                .animate().fadeIn(duration: 400.ms),

            const SizedBox(height: 20),

            // ── Stats row ─────────────────────────────────────────────────
            _StatsRow(session: session)
                .animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 20),

            // ── Skill bars with delta ─────────────────────────────────────
            _SkillBars(report: report)
                .animate().fadeIn(delay: 180.ms),

            const SizedBox(height: 20),

            // ── Coach messages (top 3, ranked by priority) ────────────────
            if (report.messages.isNotEmpty) ...[
              _SectionLabel('🧠 COACH DICE'),
              const SizedBox(height: 10),
              ...report.messages.asMap().entries.map((e) =>
                _MessageCard(msg: e.value, rank: e.key)
                    .animate()
                    .fadeIn(delay: Duration(milliseconds: 250 + e.key * 80))
                    .slideX(begin: 0.08)
              ),
              const SizedBox(height: 16),
            ],

            // ── Per-drum grid ──────────────────────────────────────────────
            if (report.drumMetrics.isNotEmpty) ...[
              _SectionLabel('🥁 POR INSTRUMENTO'),
              const SizedBox(height: 10),
              _DrumGrid(metrics: report.drumMetrics)
                  .animate().fadeIn(delay: 420.ms),
              const SizedBox(height: 16),
            ],

            // ── Exercises ────────────────────────────────────────────────
            if (report.exercises.isNotEmpty) ...[
              _SectionLabel('📚 PRACTICA ESTO'),
              const SizedBox(height: 10),
              ...report.exercises.take(3).map((e) =>
                _ExerciseCard(ex: e)
                    .animate().fadeIn(delay: 500.ms)),
              const SizedBox(height: 16),
            ],

            // ── Actions ──────────────────────────────────────────────────
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: onExit,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: NavaTheme.textMuted),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('SALIR', style: TextStyle(
                    fontFamily: 'DrummerBody', letterSpacing: 2,
                    color: NavaTheme.textSecondary)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: NavaTheme.neonCyan,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('REINTENTAR', style: TextStyle(
                    fontFamily: 'DrummerDisplay', fontSize: 13,
                    color: NavaTheme.background, letterSpacing: 1,
                    fontWeight: FontWeight.bold)),
              )),
            ]).animate().fadeIn(delay: 600.ms),

            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }
}

// ── Grade + skill delta header ────────────────────────────────────────────────
class _GradeHeader extends StatelessWidget {
  final PerformanceSession session;
  final CoachReport        report;
  const _GradeHeader({required this.session, required this.report});

  Color get _gradeColor {
    switch (session.letterGrade) {
      case 'S': return NavaTheme.neonCyan;
      case 'A': return NavaTheme.neonGreen;
      case 'B': return NavaTheme.neonGold;
      case 'C': return const Color(0xFFFF8C00);
      default:  return NavaTheme.hitMiss;
    }
  }

  @override
  Widget build(BuildContext context) {
    final after  = report.skillsAfter;
    final before = report.skillsBefore;
    final delta  = after.overall - before.overall;

    return Column(children: [
      // Grade circle
      Container(
        width: 86, height: 86,
        decoration: BoxDecoration(
          shape:     BoxShape.circle,
          border:    Border.all(color: _gradeColor, width: 3),
          boxShadow: NavaTheme.neonGlow(_gradeColor),
        ),
        child: Center(child: Text(session.letterGrade,
            style: TextStyle(fontFamily: 'DrummerDisplay', fontSize: 44,
                fontWeight: FontWeight.bold, color: _gradeColor))),
      ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),

      const SizedBox(height: 8),
      Text(session.song.title,
          style: const TextStyle(fontFamily: 'DrummerDisplay', fontSize: 15,
              color: NavaTheme.textPrimary, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),

      // Skill rank + delta
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _MiniTag('+${session.xpEarned} XP', NavaTheme.neonGold),
        const SizedBox(width: 8),
        _MiniTag('Rango ${after.rank}', NavaTheme.neonCyan),
        const SizedBox(width: 8),
        _MiniTag(
          '${delta >= 0 ? "+" : ""}${delta.toStringAsFixed(1)} pts',
          delta >= 0 ? NavaTheme.neonGreen : NavaTheme.hitMiss,
        ),
      ]),
    ]);
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final PerformanceSession session;
  const _StatsRow({required this.session});

  @override
  Widget build(BuildContext context) {
    final total  = session.perfectCount + session.goodCount +
                   session.okayCount  + session.missCount;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _Stat('PUNTOS',    session.totalScore.toString(), NavaTheme.neonCyan),
        _Stat('PRECISIÓN', '${session.accuracyPercent.toStringAsFixed(1)}%', NavaTheme.neonGold),
        _Stat('COMBO MAX', session.maxCombo.toString(),   NavaTheme.neonPurple),
        _Stat('PERFECT',   session.perfectCount.toString(), NavaTheme.hitPerfect),
      ]),
      if (total > 0) ...[
        const SizedBox(height: 16),
        _HitDistributionBar(session: session, total: total),
      ],
    ]);
  }
}

// ── Hit distribution bar ──────────────────────────────────────────────────────
class _HitDistributionBar extends StatelessWidget {
  final PerformanceSession session;
  final int total;
  const _HitDistributionBar({required this.session, required this.total});

  @override
  Widget build(BuildContext context) {
    final p = session.perfectCount / total;
    final g = session.goodCount    / total;
    final o = session.okayCount    / total;
    final m = session.missCount    / total;

    return Column(children: [
      // Segmented bar
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(height: 10, child: Row(children: [
          if (p > 0) Expanded(flex: (p * 1000).round(),
            child: Container(color: NavaTheme.hitPerfect)),
          if (g > 0) Expanded(flex: (g * 1000).round(),
            child: Container(color: NavaTheme.hitGood)),
          if (o > 0) Expanded(flex: (o * 1000).round(),
            child: Container(color: NavaTheme.neonPurple)),
          if (m > 0) Expanded(flex: (m * 1000).round(),
            child: Container(color: NavaTheme.hitMiss)),
        ])),
      ),
      const SizedBox(height: 8),
      // Legend
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _HitLegend('PERFECT', session.perfectCount, NavaTheme.hitPerfect),
        _HitLegend('GOOD',    session.goodCount,    NavaTheme.hitGood),
        _HitLegend('OKAY',    session.okayCount,    NavaTheme.neonPurple),
        _HitLegend('MISS',    session.missCount,    NavaTheme.hitMiss),
      ]),
    ]);
  }
}

class _HitLegend extends StatelessWidget {
  final String label; final int count; final Color color;
  const _HitLegend(this.label, this.count, this.color);
  @override Widget build(BuildContext context) => Column(children: [
    Text('$count', style: TextStyle(fontFamily: 'DrummerDisplay',
        fontSize: 14, color: color, fontWeight: FontWeight.bold)),
    Text(label, style: TextStyle(fontFamily: 'DrummerBody',
        fontSize: 7, color: color.withOpacity(0.7), letterSpacing: 1)),
  ]);
}

// ── Skill bars with before/after delta ───────────────────────────────────────
class _SkillBars extends StatelessWidget {
  final CoachReport report;
  const _SkillBars({required this.report});
  @override Widget build(BuildContext context) {
    final a = report.skillsAfter;
    final b = report.skillsBefore;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NavaTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NavaTheme.neonCyan.withOpacity(0.15)),
      ),
      child: Column(children: [
        _SectionLabel('HABILIDADES'),
        const SizedBox(height: 10),
        _SkillBar('TIMING',       a.timing,       b.timing,       NavaTheme.neonCyan),
        _SkillBar('PRECISIÓN',    a.accuracy,     b.accuracy,     NavaTheme.neonGold),
        _SkillBar('CONSISTENCIA', a.consistency,  b.consistency,  NavaTheme.neonPurple),
        _SkillBar('DINÁMICA',     a.velocity,     b.velocity,     NavaTheme.neonGreen),
      ]),
    );
  }
}

class _SkillBar extends StatelessWidget {
  final String label;
  final double current, previous;
  final Color  color;
  const _SkillBar(this.label, this.current, this.previous, this.color);

  @override Widget build(BuildContext context) {
    final delta = current - previous;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        SizedBox(width: 90, child: Text(label, style: const TextStyle(
            fontFamily: 'DrummerBody', fontSize: 9,
            color: NavaTheme.textMuted, letterSpacing: 1))),
        Expanded(child: Stack(children: [
          Container(height: 6, decoration: BoxDecoration(
              color: NavaTheme.textMuted.withOpacity(0.12),
              borderRadius: BorderRadius.circular(3))),
          FractionallySizedBox(
            widthFactor: (current / 100).clamp(0, 1),
            child: Container(height: 6, decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withOpacity(0.6), color]),
              borderRadius: BorderRadius.circular(3),
              boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 4)],
            )),
          ).animate().slideX(begin: -1, duration: 500.ms, curve: Curves.easeOut),
        ])),
        const SizedBox(width: 6),
        SizedBox(width: 28, child: Text(current.toStringAsFixed(0),
            style: TextStyle(fontFamily: 'DrummerDisplay', fontSize: 10,
                color: color, fontWeight: FontWeight.bold))),
        SizedBox(width: 36, child: Text(
          '${delta >= 0 ? "+" : ""}${delta.toStringAsFixed(1)}',
          style: TextStyle(fontFamily: 'DrummerBody', fontSize: 9,
              color: delta >= 0 ? NavaTheme.neonGreen : NavaTheme.hitMiss),
        )),
      ]),
    );
  }
}

// ── Coach message card ────────────────────────────────────────────────────────
class _MessageCard extends StatelessWidget {
  final CoachMessage msg;
  final int          rank;
  const _MessageCard({required this.msg, required this.rank});

  Color get _rankColor {
    if (msg.isPositive) return NavaTheme.neonGreen;
    if (rank == 0) return NavaTheme.hitMiss;
    if (rank == 1) return NavaTheme.neonGold;
    return NavaTheme.textSecondary;
  }

  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: NavaTheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _rankColor.withOpacity(0.3)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(msg.emoji, style: const TextStyle(fontSize: 20)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(msg.title, style: TextStyle(fontFamily: 'DrummerDisplay', fontSize: 12,
            color: _rankColor, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(msg.body, style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 12,
            color: NavaTheme.textSecondary, height: 1.4)),
      ])),
    ]),
  );
}

// ── Per-drum grid ─────────────────────────────────────────────────────────────
class _DrumGrid extends StatelessWidget {
  final Map<DrumPad, DrumMetrics> metrics;
  const _DrumGrid({required this.metrics});
  @override Widget build(BuildContext context) {
    final sorted = metrics.entries.toList()
      ..sort((a,b) => b.value.hits.compareTo(a.value.hits));
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: sorted.take(8).map((e) => _DrumChip(e.key, e.value)).toList(),
    );
  }
}

class _DrumChip extends StatelessWidget {
  final DrumPad    pad;
  final DrumMetrics m;
  const _DrumChip(this.pad, this.m);

  Color get _statusColor {
    if (m.missRate > 0.3)         return NavaTheme.hitMiss;
    if (m.consistencyScore < 50)  return NavaTheme.neonGold;
    if (m.timingScore > 80)       return NavaTheme.neonGreen;
    return NavaTheme.textSecondary;
  }

  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: _statusColor.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _statusColor.withOpacity(0.3)),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(pad.shortName, style: TextStyle(fontFamily: 'DrummerDisplay',
          fontSize: 13, color: _statusColor, fontWeight: FontWeight.bold)),
      const SizedBox(height: 2),
      Text('${m.hits} hits', style: const TextStyle(fontFamily: 'DrummerBody',
          fontSize: 9, color: NavaTheme.textMuted)),
      if (m.meanDeltaMs.abs() > 5)
        Text('${m.meanDeltaMs > 0 ? "+" : ""}${m.meanDeltaMs.toStringAsFixed(0)}ms',
            style: TextStyle(fontFamily: 'DrummerBody', fontSize: 9,
                color: _statusColor.withOpacity(0.8))),
    ]),
  );
}

// ── Exercise card ─────────────────────────────────────────────────────────────
class _ExerciseCard extends StatelessWidget {
  final PracticeRecommendation ex;
  const _ExerciseCard({required this.ex});
  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: NavaTheme.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: NavaTheme.neonPurple.withOpacity(0.2)),
    ),
    child: Row(children: [
      Text(ex.icon, style: const TextStyle(fontSize: 24)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ex.title, style: const TextStyle(fontFamily: 'DrummerDisplay',
            fontSize: 12, color: NavaTheme.textPrimary, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(ex.description, style: const TextStyle(fontFamily: 'DrummerBody',
            fontSize: 11, color: NavaTheme.textSecondary, height: 1.4)),
      ])),
      const SizedBox(width: 10),
      Column(children: [
        Text('${ex.durationMin}min', style: const TextStyle(
            fontFamily: 'DrummerDisplay', fontSize: 12, color: NavaTheme.neonCyan)),
        Text('${ex.bpm} BPM', style: const TextStyle(
            fontFamily: 'DrummerBody', fontSize: 9, color: NavaTheme.textMuted)),
      ]),
    ]),
  );
}

// ── Shared helpers ────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(text, style: const TextStyle(fontFamily: 'DrummerBody',
        fontSize: 10, letterSpacing: 2, color: NavaTheme.textMuted)),
  );
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _Stat(this.label, this.value, this.color);
  @override Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(fontFamily: 'DrummerDisplay', fontSize: 18,
        color: color, fontWeight: FontWeight.bold)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 8,
        color: NavaTheme.textMuted, letterSpacing: 1)),
  ]);
}

class _MiniTag extends StatelessWidget {
  final String text; final Color color;
  const _MiniTag(this.text, this.color);
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4))),
    child: Text(text, style: TextStyle(fontFamily: 'DrummerBody',
        fontSize: 11, color: color, fontWeight: FontWeight.bold)),
  );
}
