// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Insight Generator + Recommendation Engine
// /core/coach/insight_generator.dart
//
// Converts typed PerformanceIssues → human-readable Spanish feedback.
// Max 3 insights per session, language is simple and actionable.
// ─────────────────────────────────────────────────────────────────────────────
import '../../domain/entities/entities.dart';
import 'performance_analyzer.dart';

// ── Output types ──────────────────────────────────────────────────────────────
class CoachMessage {
  final String emoji;
  final String title;
  final String body;      // human-readable, actionable
  final double priority;
  final bool   isPositive;

  const CoachMessage({
    required this.emoji,  required this.title,
    required this.body,   required this.priority,
    this.isPositive = false,
  });
}

class PracticeRecommendation {
  final String      title;
  final String      description;
  final int         bpm;
  final String      exerciseId;  // links to lesson catalog
  final String      icon;
  final DrumPad?    targetDrum;
  final int         durationMin;

  const PracticeRecommendation({
    required this.title,      required this.description,
    required this.bpm,        required this.exerciseId,
    required this.icon,       this.targetDrum,
    this.durationMin = 5,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// InsightGenerator
// ═══════════════════════════════════════════════════════════════════════════
class InsightGenerator {

  /// Generate up to [maxInsights] insights from ranked issues.
  /// Always ends with a positive note if performance was good.
  List<CoachMessage> generate(
    List<PerformanceIssue> issues, {
    required double accuracyPct,
    required int    maxInsights,
    int             combo = 0,
  }) {
    final messages = <CoachMessage>[];

    // Top issues → messages (max 3)
    for (final issue in issues.take(maxInsights)) {
      final msg = _issueToMessage(issue);
      if (msg != null) messages.add(msg);
    }

    // Always include one positive if good performance
    if (accuracyPct >= 85) {
      messages.add(CoachMessage(
        emoji:      '🔥',
        title:      '¡Excelente sesión!',
        body:       _positiveMessage(accuracyPct, combo),
        priority:   0,
        isPositive: true,
      ));
    } else if (accuracyPct >= 70 && messages.isNotEmpty) {
      messages.add(CoachMessage(
        emoji:      '💪',
        title:      'Buen trabajo',
        body:       'Llevas ${accuracyPct.toStringAsFixed(0)}% de precisión. '
                    'Sigue practicando — la mejora viene con la repetición.',
        priority:   0,
        isPositive: true,
      ));
    }

    return messages;
  }

  CoachMessage? _issueToMessage(PerformanceIssue issue) {
    final name = issue.drum.displayName;

    switch (issue.type) {
      case IssueType.timingLate:
        return CoachMessage(
          emoji:    '⏪',
          title:    '$name — estás llegando tarde',
          body:     'Tu ${name.toLowerCase()} llega ${issue.mean.toStringAsFixed(0)}ms después '
                    'del beat. Anticipa el golpe un poco más, como si quisieras tocar '
                    'justo cuando escuchas el click, no después.',
          priority: issue.priority,
        );

      case IssueType.timingEarly:
        return CoachMessage(
          emoji:    '⏩',
          title:    '$name — estás llegando temprano',
          body:     'Tu ${name.toLowerCase()} llega ${issue.mean.abs().toStringAsFixed(0)}ms antes '
                    'del beat. Respira y espera el click antes de golpear. '
                    'La paciencia es la clave del groove.',
          priority: issue.priority,
        );

      case IssueType.timingUnstable:
        return CoachMessage(
          emoji:    '📉',
          title:    '$name — timing inestable',
          body:     'Tu ${name.toLowerCase()} varía ±${issue.std.toStringAsFixed(0)}ms '
                    'de golpe en golpe. Practica solo este instrumento con metrónomo '
                    'a 60% de tempo hasta lograr uniformidad.',
          priority: issue.priority,
        );

      case IssueType.velocityWeak:
        return CoachMessage(
          emoji:    '💨',
          title:    '$name — golpes muy suaves',
          body:     'Tus golpes en el ${name.toLowerCase()} son muy suaves (promedio ${issue.mean.toStringAsFixed(0)}/127). '
                    'Usa más velocidad de muñeca — el movimiento viene del antebrazo, '
                    'no solo los dedos.',
          priority: issue.priority,
        );

      case IssueType.velocityUnstable:
        return CoachMessage(
          emoji:    '🔊',
          title:    '$name — dinámica irregular',
          body:     'La fuerza de tus golpes en ${name.toLowerCase()} varía mucho '
                    '(std: ${issue.std.toStringAsFixed(0)}). Practica cuatro niveles: '
                    'pp, p, f, ff — 4 compases de cada uno.',
          priority: issue.priority,
        );

      case IssueType.missRate:
        return CoachMessage(
          emoji:    '❌',
          title:    'Muchos fallos en $name',
          body:     'Fallaste el ${issue.mean.toStringAsFixed(0)}% de los '
                    '${name.toLowerCase()} (${issue.sampleSize} notas). '
                    'Aísla este instrumento: practica solo ese ritmo a 50% de tempo.',
          priority: issue.priority,
        );

      case IssueType.fillBreakdown:
        return CoachMessage(
          emoji:    '🥁',
          title:    'Fallos en fills — $name',
          body:     'Cometes errores en las secciones rápidas con ${name.toLowerCase()}. '
                    'Practica los fills individualmente, muy despacio, hasta que '
                    'el movimiento sea automático.',
          priority: issue.priority,
        );

      case IssueType.transitionError:
      case IssueType.transitions:
        return CoachMessage(
          emoji:    '↩️',
          title:    'Transición groove → fill',
          body:     'Tienes ${issue.mean.toStringAsFixed(0)} errores al volver del fill '
                    'al groove. Practica el "1" después del fill: debe ser '
                    'el golpe más fuerte y más preciso.',
          priority: issue.priority,
        );

      case IssueType.coordination:
        return CoachMessage(
          emoji:    '🤝',
          title:    'Coordinación de extremidades',
          body:     'Múltiples partes fallan al mismo tiempo. Practica cada '
                    'extremidad por separado y combínalas de a una.',
          priority: issue.priority,
        );
      case IssueType.velocityStrong:
        return CoachMessage(
          emoji:    '💪',
          title:    'Controla la dinámica',
          body:     'Tus golpes son demasiado fuertes. Practica con cuatro '
                    'niveles de velocidad: pp, mp, mf, ff.',
          priority: issue.priority,
        );
    }
  }

  String _positiveMessage(double accuracy, int combo) {
    if (accuracy >= 95) {
      return 'Precisión de ${accuracy.toStringAsFixed(1)}%. '
             'Eso es nivel profesional. Aumenta el tempo o prueba '
             'una canción más difícil.';
    }
    if (combo >= 25) {
      return 'Combo de $combo — tu groove está sólido. '
             'Trabaja en mantener esa concentración todo el tiempo.';
    }
    return 'Buena sesión con ${accuracy.toStringAsFixed(0)}% de precisión. '
           'Tu oído está mejorando.';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RecommendationEngine
// ═══════════════════════════════════════════════════════════════════════════
class RecommendationEngine {

  /// Map issues → specific practice exercises.
  /// Returns exercises sorted by relevance (most critical first).
  List<PracticeRecommendation> recommend(
    List<PerformanceIssue> issues, {
    required double accuracyPct,
    required int    songBpm,
    required Song   song,
  }) {
    final recs = <PracticeRecommendation>[];

    for (final issue in issues.take(3)) {
      final rec = _mapToExercise(issue, songBpm: songBpm, song: song);
      if (rec != null) recs.add(rec);
    }

    // If performance was good, suggest challenge
    if (accuracyPct >= 90 && recs.isEmpty) {
      recs.add(PracticeRecommendation(
        title:       '¡Sube la dificultad!',
        description: 'Dominas esta canción. Prueba aumentar el tempo al 110% '
                     'o elige una canción de mayor dificultad.',
        bpm:         (songBpm * 1.1).round(),
        exerciseId:  'challenge_next',
        icon:        '🚀',
        durationMin: 5,
      ));
    }

    // Always add slow practice if accuracy < 75
    if (accuracyPct < 75) {
      recs.add(PracticeRecommendation(
        title:       'Práctica lenta: ${song.title}',
        description: 'Toca esta canción al 60% de tempo. La velocidad viene '
                     'después de la precisión — nunca antes.',
        bpm:         (songBpm * 0.6).round(),
        exerciseId:  'slow_practice_${song.id}',
        icon:        '🐢',
        durationMin: 10,
      ));
    }

    return recs;
  }

  PracticeRecommendation? _mapToExercise(
    PerformanceIssue issue, {
    required int  songBpm,
    required Song song,
  }) {
    final name = issue.drum.displayName;
    final slowBpm = (songBpm * 0.65).round().clamp(40, 120);

    switch (issue.type) {
      case IssueType.timingLate:
      case IssueType.timingEarly:
        return PracticeRecommendation(
          title:       'Corrección de bias — $name',
          description: 'Toca solo el $name con metrónomo a $slowBpm BPM. '
                       'Grábate y escucha si estás "en el beat". '
                       'Repite hasta que sientas la diferencia.',
          bpm:         slowBpm,
          exerciseId:  'bias_${issue.drum.name}',
          icon:        '🎯',
          targetDrum:  issue.drum,
          durationMin: 5,
        );

      case IssueType.timingUnstable:
        return PracticeRecommendation(
          title:       'Estabilidad — $name',
          description: 'Practica solo $name en corcheas durante 2 minutos '
                       'a ${slowBpm} BPM. Objetivo: cada golpe dentro de ±10ms.',
          bpm:         slowBpm,
          exerciseId:  'stability_${issue.drum.name}',
          icon:        '⏱️',
          targetDrum:  issue.drum,
          durationMin: 3,
        );

      case IssueType.velocityWeak:
        return PracticeRecommendation(
          title:       'Potencia de golpe — $name',
          description: 'Practica el $name a cuatro niveles de fuerza: '
                       'pp → p → f → ff, 4 compases cada uno a ${slowBpm} BPM. '
                       'Mantén el tempo constante.',
          bpm:         slowBpm,
          exerciseId:  'velocity_power_${issue.drum.name}',
          icon:        '💪',
          targetDrum:  issue.drum,
          durationMin: 5,
        );

      case IssueType.velocityUnstable:
        return PracticeRecommendation(
          title:       'Control dinámico — $name',
          description: 'Practica el $name a cuatro niveles de volumen estables. '
                       'Escucha que cada nivel suene exactamente igual '
                       'de golpe en golpe.',
          bpm:         slowBpm,
          exerciseId:  'velocity_control_${issue.drum.name}',
          icon:        '🔊',
          targetDrum:  issue.drum,
          durationMin: 5,
        );

      case IssueType.missRate:
        return PracticeRecommendation(
          title:       'Práctica aislada — $name',
          description: 'Toca SOLO el $name en la canción actual al '
                       '${(songBpm * 0.6).round()} BPM. Sin distracciones '
                       'de otros instrumentos.',
          bpm:         (songBpm * 0.6).round(),
          exerciseId:  'isolated_${issue.drum.name}',
          icon:        '🎵',
          targetDrum:  issue.drum,
          durationMin: 5,
        );

      case IssueType.fillBreakdown:
        return PracticeRecommendation(
          title:       'Fills lentos',
          description: 'Practica las secciones de fill a 50% de tempo. '
                       'Cuando puedas ejecutarlo 10 veces seguidas sin error, '
                       'sube 10 BPM.',
          bpm:         (songBpm * 0.5).round(),
          exerciseId:  'fills_slow_${song.id}',
          icon:        '🥁',
          durationMin: 8,
        );

      case IssueType.transitionError:
      case IssueType.transitions:
        return PracticeRecommendation(
          title:       'Aterrizaje del fill',
          description: 'Practica el fill + el "1" del siguiente compás a '
                       '${slowBpm} BPM. El tiempo 1 después del fill debe ser '
                       'el golpe más preciso y más fuerte.',
          bpm:         slowBpm,
          exerciseId:  'transition_${song.id}',
          icon:        '🎯',
          durationMin: 5,
        );

      case IssueType.coordination:
        return PracticeRecommendation(
          title:       'Coordinación por capas',
          description: 'Practica añadiendo una extremidad a la vez: '
                       '1) Solo kick → 2) Kick + snare → 3) + hi-hat → 4) completo.',
          bpm:         (songBpm * 0.6).round(),
          exerciseId:  'coordination_layers',
          icon:        '🤝',
          durationMin: 10,
        );
      case IssueType.velocityStrong:
        return PracticeRecommendation(
          title:       'Control de dinámica',
          description: 'Practica los mismos patrones con velocidad controlada.',
          bpm:         songBpm,
          exerciseId:  'velocity_control',
          icon:        '💪',
          durationMin: 5,
        );
    }
  }
}
