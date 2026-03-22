// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Analytics Service  (Phase 10)
// Stores per-note Δt, velocity, score per session.
// Aggregates trends and skill progression for dashboards.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/entities/entities.dart';
import 'ai_learning_system.dart';
import 'global_timing_controller.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AnalyticsService
// ═══════════════════════════════════════════════════════════════════════════
class AnalyticsService {
  static final AnalyticsService instance = AnalyticsService._();
  AnalyticsService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Stores full note-level analytics for a session.
  /// Collection: analytics/{userId}/sessions/{sessionId}
  Future<void> saveSessionAnalytics({
    required String           userId,
    required PerformanceSession session,
    required SessionInsight   insight,
  }) async {
    try {
      final noteData = session.hitResults.map((r) => {
        'pad':         r.expected.pad.name,
        'deltaMs':     r.timingDeltaMs,
        'velocity':    r.actual?.velocity ?? r.expected.velocity,
        'grade':       r.grade.name,
        'score':       r.score,
        'beatPos':     r.expected.beatPosition,
        'timeSec':     r.expected.timeSeconds,
      }).toList();

      final drumData = insight.drumInsights.map((pad, di) => MapEntry(pad.name, {
        'hitCount':      di.hitCount,
        'meanDeltaMs':   di.meanDeltaMs,
        'stdDeltaMs':    di.stdDeltaMs,
        'bias':          di.bias.name,
        'consistency':   di.consistency,
        'velConsistency':di.velConsistency,
        'trend':         di.trend.name,
      }));

      await _db
          .collection('analytics')
          .doc(userId)
          .collection('sessions')
          .doc(session.id)
          .set({
        'songId':        session.song.id,
        'songTitle':     session.song.title,
        'bpm':           session.song.bpm,
        'playedAt':      Timestamp.fromDate(session.startedAt),
        'totalScore':    session.totalScore,
        'accuracyPct':   session.accuracyPercent,
        'perfectCount':  session.perfectCount,
        'goodCount':     session.goodCount,
        'okayCount':     session.okayCount,
        'missCount':     session.missCount,
        'maxCombo':      session.maxCombo,
        'xpEarned':      session.xpEarned,
        // Phase 10 specific
        'noteData':      noteData,
        'drumAnalysis':  drumData,
        'skillVector': {
          'timing':      insight.skillVector.timing,
          'accuracy':    insight.skillVector.accuracy,
          'consistency': insight.skillVector.consistency,
          'velocity':    insight.skillVector.velocity,
          'overall':     insight.skillVector.overall,
        },
        'globalBias':    insight.globalAnalysis?.bias.name ?? 'neutral',
        'globalStdMs':   insight.globalAnalysis?.stdDev ?? 0,
        'globalMeanMs':  insight.globalAnalysis?.mean ?? 0,
      });

      // Also update the daily aggregate
      await _updateDailyAggregate(userId, session, insight);
    } catch (e) {
      // Analytics failures should never crash the app
    }
  }

  /// Updates the rolling daily aggregate for the dashboard chart.
  Future<void> _updateDailyAggregate(
    String userId, PerformanceSession session, SessionInsight insight,
  ) async {
    final today = DateTime.now();
    final dayKey = '${today.year}-${today.month.toString().padLeft(2,'0')}'
                   '-${today.day.toString().padLeft(2,'0')}';

    final ref = _db
        .collection('analytics')
        .doc(userId)
        .collection('daily')
        .doc(dayKey);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final existing = snap.exists ? snap.data() as Map<String, dynamic> : {};

      final sessionCount  = (existing['sessionCount']  as int? ?? 0) + 1;
      final totalAccuracy = (existing['totalAccuracy'] as num? ?? 0) +
          session.accuracyPercent;
      final totalScore    = (existing['totalScore']    as int? ?? 0) +
          session.totalScore;
      final totalXp       = (existing['totalXp']       as int? ?? 0) +
          session.xpEarned;

      tx.set(ref, {
        'date':          dayKey,
        'sessionCount':  sessionCount,
        'avgAccuracy':   totalAccuracy / sessionCount,
        'totalScore':    totalScore,
        'totalXp':       totalXp,
        'totalAccuracy': totalAccuracy,
        'lastSongTitle': session.song.title,
        'updatedAt':     FieldValue.serverTimestamp(),
        // Rolling skill averages
        'avgTiming':      ((existing['avgTiming'] as num? ?? 0) * (sessionCount-1) +
                           insight.skillVector.timing)        / sessionCount,
        'avgConsistency': ((existing['avgConsistency'] as num? ?? 0) * (sessionCount-1) +
                           insight.skillVector.consistency)   / sessionCount,
      });
    });
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns daily accuracy for the last [days] days — for the dashboard chart.
  Future<List<DailyStats>> getDailyStats(String userId, {int days = 14}) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      final snap = await _db
          .collection('analytics')
          .doc(userId)
          .collection('daily')
          .where('date', isGreaterThanOrEqualTo:
              '${cutoff.year}-${cutoff.month.toString().padLeft(2,'0')}'
              '-${cutoff.day.toString().padLeft(2,'0')}')
          .orderBy('date')
          .get();

      return snap.docs.map((d) {
        final data = d.data();
        return DailyStats(
          date:          DateTime.parse(d.id),
          avgAccuracy:   (data['avgAccuracy']   as num? ?? 0).toDouble(),
          totalXp:       (data['totalXp']        as num? ?? 0).toInt(),
          sessionCount:  (data['sessionCount']   as num? ?? 0).toInt(),
          avgTiming:     (data['avgTiming']      as num? ?? 0).toDouble(),
          avgConsistency:(data['avgConsistency'] as num? ?? 0).toDouble(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Returns the per-drum timing history for a user (last 30 sessions).
  Future<Map<String, List<double>>> getPerDrumHistory(String userId) async {
    try {
      final snap = await _db
          .collection('analytics')
          .doc(userId)
          .collection('sessions')
          .orderBy('playedAt', descending: true)
          .limit(30)
          .get();

      final Map<String, List<double>> result = {};
      for (final doc in snap.docs) {
        final drumData = doc.data()['drumAnalysis'] as Map<String, dynamic>? ?? {};
        for (final entry in drumData.entries) {
          final mean = (entry.value['meanDeltaMs'] as num? ?? 0).toDouble();
          result.putIfAbsent(entry.key, () => []).add(mean);
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Returns skill vector progression for the last [n] sessions.
  Future<List<SkillVector>> getSkillProgression(String userId, {int n = 10}) async {
    try {
      final snap = await _db
          .collection('analytics')
          .doc(userId)
          .collection('sessions')
          .orderBy('playedAt', descending: true)
          .limit(n)
          .get();

      return snap.docs.reversed.map((doc) {
        final sv = doc.data()['skillVector'] as Map<String, dynamic>? ?? {};
        return SkillVector(
          timing:      (sv['timing']      as num? ?? 50).toDouble(),
          accuracy:    (sv['accuracy']    as num? ?? 50).toDouble(),
          consistency: (sv['consistency'] as num? ?? 50).toDouble(),
          velocity:    (sv['velocity']    as num? ?? 50).toDouble(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}

// ── Value Objects ─────────────────────────────────────────────────────────────
class DailyStats {
  final DateTime date;
  final double   avgAccuracy;
  final int      totalXp;
  final int      sessionCount;
  final double   avgTiming;
  final double   avgConsistency;

  const DailyStats({
    required this.date,
    required this.avgAccuracy,
    required this.totalXp,
    required this.sessionCount,
    required this.avgTiming,
    required this.avgConsistency,
  });
}
