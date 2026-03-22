// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Skill Model  /core/coach/skill_model.dart
// Tracks long-term skill progression with exponential moving average.
// newScore = oldScore × 0.8 + currentPerformance × 0.2
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math' as math;
import '../../domain/entities/entities.dart';

// ── Skill dimensions ──────────────────────────────────────────────────────────
class SkillDimensions {
  /// 0–100 for each dimension
  double timing;       // precision of hit timing
  double accuracy;     // correct pad / note hit rate
  double consistency;  // low std-dev across session
  double velocity;     // dynamic control
  double readAhead;    // ability to read and anticipate notes
  DateTime lastUpdated;

  SkillDimensions({
    this.timing       = 50,
    this.accuracy     = 50,
    this.consistency  = 50,
    this.velocity     = 50,
    this.readAhead    = 50,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  double get overall =>
      (timing * 0.30 + accuracy * 0.30 + consistency * 0.20 +
       velocity * 0.10 + readAhead * 0.10).clamp(0, 100);

  String get rank {
    final o = overall;
    if (o >= 90) return 'S';
    if (o >= 80) return 'A';
    if (o >= 65) return 'B';
    if (o >= 50) return 'C';
    return 'D';
  }

  SkillDimensions copyWith({
    double? timing, double? accuracy, double? consistency,
    double? velocity, double? readAhead,
  }) => SkillDimensions(
    timing:      timing      ?? this.timing,
    accuracy:    accuracy    ?? this.accuracy,
    consistency: consistency ?? this.consistency,
    velocity:    velocity    ?? this.velocity,
    readAhead:   readAhead   ?? this.readAhead,
    lastUpdated: DateTime.now(),
  );

  Map<String, double> toMap() => {
    'timing':      timing,
    'accuracy':    accuracy,
    'consistency': consistency,
    'velocity':    velocity,
    'readAhead':   readAhead,
  };

  factory SkillDimensions.fromMap(Map<String, double> m) => SkillDimensions(
    timing:      m['timing']      ?? 50,
    accuracy:    m['accuracy']    ?? 50,
    consistency: m['consistency'] ?? 50,
    velocity:    m['velocity']    ?? 50,
    readAhead:   m['readAhead']   ?? 50,
  );
}

// ── Per-drum skill ────────────────────────────────────────────────────────────
class DrumSkill {
  final DrumPad pad;
  double timingScore;       // 0–100
  double consistencyScore;  // 0–100
  double velocityScore;     // 0–100
  int    totalHits;
  int    sessionsPlayed;

  DrumSkill({
    required this.pad,
    this.timingScore      = 50,
    this.consistencyScore = 50,
    this.velocityScore    = 50,
    this.totalHits        = 0,
    this.sessionsPlayed   = 0,
  });

  double get overall =>
      (timingScore * 0.5 + consistencyScore * 0.3 + velocityScore * 0.2)
          .clamp(0, 100);

  String get weakestArea {
    final scores = {
      'timing':      timingScore,
      'consistencia':consistencyScore,
      'dinámica':    velocityScore,
    };
    return scores.entries
        .reduce((a, b) => a.value < b.value ? a : b)
        .key;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SkillModel — singleton, persists across sessions
// ═══════════════════════════════════════════════════════════════════════════
class SkillModel {
  static final SkillModel instance = SkillModel._();
  SkillModel._();

  // EMA smoothing factor (0.2 = slow/stable, 0.5 = fast/reactive)
  static const double _alpha = 0.2;

  // Overall skill dimensions (global)
  SkillDimensions _skills = SkillDimensions();
  SkillDimensions get skills => _skills;

  // Per-drum skills
  final Map<DrumPad, DrumSkill> _drumSkills = {};

  // Session history for trend analysis
  final List<_SessionSnapshot> _history = [];

  // ── Update after session ────────────────────────────────────────────────────

  /// Apply exponential moving average:
  ///   newScore = oldScore × (1 - α) + currentPerformance × α
  void updateFromSession({
    required double timingPct,      // 0–100
    required double accuracyPct,    // 0–100
    required double consistencyPct, // 0–100
    required double velocityPct,    // 0–100
    required double readAheadPct,   // 0–100 (estimated from anticipation)
    required Map<DrumPad, DrumSessionData> drumData,
    required Song song,
  }) {
    // EMA update for each dimension
    _skills = SkillDimensions(
      timing:      _ema(_skills.timing,      timingPct),
      accuracy:    _ema(_skills.accuracy,    accuracyPct),
      consistency: _ema(_skills.consistency, consistencyPct),
      velocity:    _ema(_skills.velocity,    velocityPct),
      readAhead:   _ema(_skills.readAhead,   readAheadPct),
    );

    // Update per-drum skills
    for (final entry in drumData.entries) {
      final pad = entry.key;
      final d   = entry.value;
      final existing = _drumSkills[pad] ?? DrumSkill(pad: pad);
      _drumSkills[pad] = DrumSkill(
        pad:              pad,
        timingScore:      _ema(existing.timingScore,      d.timingScore),
        consistencyScore: _ema(existing.consistencyScore, d.consistencyScore),
        velocityScore:    _ema(existing.velocityScore,    d.velocityScore),
        totalHits:        existing.totalHits + d.hits,
        sessionsPlayed:   existing.sessionsPlayed + 1,
      );
    }

    // Record snapshot
    _history.add(_SessionSnapshot(
      timestamp:  DateTime.now(),
      skills:     _skills.copyWith(),
      songTitle:  song.title,
      songBpm:    song.bpm,
    ));
    if (_history.length > 100) _history.removeAt(0);
  }

  double _ema(double old, double current) =>
      (old * (1 - _alpha) + current * _alpha).clamp(0, 100);

  // ── Queries ─────────────────────────────────────────────────────────────────

  DrumSkill? drumSkill(DrumPad pad) => _drumSkills[pad];

  /// Returns the weakest drum pad by overall skill score.
  DrumPad? get weakestDrum {
    if (_drumSkills.isEmpty) return null;
    return _drumSkills.entries
        .where((e) => e.value.totalHits > 20)  // need enough data
        .fold<MapEntry<DrumPad, DrumSkill>?>(null, (best, e) =>
            best == null || e.value.overall < best.value.overall ? e : best)
        ?.key;
  }

  /// Returns the strongest drum pad.
  DrumPad? get strongestDrum {
    if (_drumSkills.isEmpty) return null;
    return _drumSkills.entries
        .where((e) => e.value.totalHits > 20)
        .fold<MapEntry<DrumPad, DrumSkill>?>(null, (best, e) =>
            best == null || e.value.overall > best.value.overall ? e : best)
        ?.key;
  }

  /// Trend: is the player improving overall?
  SkillTrend get trend {
    if (_history.length < 3) return SkillTrend.insufficient;
    final recent = _history.takeLast(3).map((s) => s.skills.overall).toList();
    final older  = _history.take(_history.length - 3).map((s) => s.skills.overall).toList();
    if (older.isEmpty) return SkillTrend.insufficient;
    final recentAvg = recent.reduce((a,b)=>a+b) / recent.length;
    final olderAvg  = older.reduce((a,b)=>a+b) / older.length;
    final delta = recentAvg - olderAvg;
    if (delta >  3) return SkillTrend.improving;
    if (delta < -3) return SkillTrend.declining;
    return SkillTrend.stable;
  }

  /// Returns the skill delta over last N sessions.
  SkillDelta skillDelta({int sessions = 5}) {
    if (_history.length < 2) {
      return const SkillDelta(timing:0, accuracy:0, consistency:0, velocity:0);
    }
    final recent = _history.takeLast(sessions).map((s) => s.skills).toList();
    final older  = _history.take(math.max(1, _history.length - sessions))
        .map((s) => s.skills).toList();
    final rAvg = _avgDimensions(recent);
    final oAvg = _avgDimensions(older);
    return SkillDelta(
      timing:      rAvg.timing      - oAvg.timing,
      accuracy:    rAvg.accuracy    - oAvg.accuracy,
      consistency: rAvg.consistency - oAvg.consistency,
      velocity:    rAvg.velocity    - oAvg.velocity,
    );
  }

  SkillDimensions _avgDimensions(List<SkillDimensions> list) {
    if (list.isEmpty) return SkillDimensions();
    return SkillDimensions(
      timing:      list.map((s)=>s.timing).reduce((a,b)=>a+b)      / list.length,
      accuracy:    list.map((s)=>s.accuracy).reduce((a,b)=>a+b)    / list.length,
      consistency: list.map((s)=>s.consistency).reduce((a,b)=>a+b) / list.length,
      velocity:    list.map((s)=>s.velocity).reduce((a,b)=>a+b)    / list.length,
      readAhead:   list.map((s)=>s.readAhead).reduce((a,b)=>a+b)   / list.length,
    );
  }

  List<_SessionSnapshot> get history => List.unmodifiable(_history);

  void reset() {
    _skills = SkillDimensions();
    _drumSkills.clear();
    _history.clear();
  }
}

// ── Supporting types ──────────────────────────────────────────────────────────
enum SkillTrend { improving, declining, stable, insufficient }

class SkillDelta {
  final double timing, accuracy, consistency, velocity;
  const SkillDelta({
    required this.timing,    required this.accuracy,
    required this.consistency, required this.velocity,
  });
  String sign(double v) => v >= 0 ? '+${v.toStringAsFixed(1)}' : v.toStringAsFixed(1);
}

class _SessionSnapshot {
  final DateTime       timestamp;
  final SkillDimensions skills;
  final String         songTitle;
  final int            songBpm;
  _SessionSnapshot({
    required this.timestamp, required this.skills,
    required this.songTitle, required this.songBpm,
  });
}

class DrumSessionData {
  final double timingScore, consistencyScore, velocityScore;
  final int    hits;
  const DrumSessionData({
    required this.timingScore, required this.consistencyScore,
    required this.velocityScore, required this.hits,
  });
}

extension _TakeLast<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
