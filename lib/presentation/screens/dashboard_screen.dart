import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../domain/entities/entities.dart';
import '../../core/analytics_service.dart';
import '../theme/nava_theme.dart';

class DashboardScreen extends StatefulWidget {
  final UserProgress               progress;
  final List<PerformanceSession>   recentSessions;
  final Map<DateTime, double>      weeklyAccuracy;

  const DashboardScreen({
    super.key,
    required this.progress,
    this.recentSessions = const [],
    this.weeklyAccuracy = const {},
  });
  @override State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  UserProgress get progress => widget.progress;
  List<DailyStats> _dailyStats = [];
  // ignore: unused_field
  bool _loadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    // If real data was passed from Firestore, skip local fetch
    if (widget.weeklyAccuracy.isNotEmpty) {
      if (mounted) setState(() => _loadingStats = false);
      return;
    }
    try {
      final stats = await AnalyticsService.instance.getDailyStats(
          progress.userId, days: 7);
      if (mounted) setState(() { _dailyStats = stats; _loadingStats = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  /// Build a 7-day accuracy list from a Map<DateTime, double>.
  List<double> _buildWeeklyFromMap(Map<DateTime, double> map) {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = DateTime(now.year, now.month, now.day - 6 + i);
      final entries = map.entries.where((e) =>
          e.key.year == day.year &&
          e.key.month == day.month &&
          e.key.day == day.day);
      if (entries.isEmpty) return 0.0;
      return entries.map((e) => e.value).reduce((a, b) => a + b) / entries.length;
    });
  }

  List<double> get _weeklyAccuracy {
    if (widget.weeklyAccuracy.isNotEmpty) {
      return _buildWeeklyFromMap(widget.weeklyAccuracy);
    }
    if (_dailyStats.isEmpty) return [0,0,0,0,0,0,0];
    return _dailyStats.map((s) => s.avgAccuracy).toList();
  }

  static final _achievements = [
    _Achievement('Primera nota',   '🥁', 'Golpea tu primera nota', true),
    _Achievement('Combo King',     '⚡', 'Alcanza 10x combo',       true),
    _Achievement('Perfeccionista', '💎', 'Logra 100% de precisión', false),
    _Achievement('Velocista',      '🔥', 'Toca a 150+ BPM',         false),
    _Achievement('Dedicado',       '📅', 'Racha de 7 días',          true),
    _Achievement('Maestro',        '🎵', 'Completa todos los géneros',false),
  ];


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavaTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGreeting(),
              const SizedBox(height: 24),
              _buildLevelCard(),
              const SizedBox(height: 20),
              _buildStatsRow(),
              const SizedBox(height: 24),
              _buildAccuracyChart(),
              const SizedBox(height: 24),
              _buildAchievements(),
              const SizedBox(height: 24),
              _buildRecentActivity(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGreeting() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, ${progress.displayName} 👋',
                style: const TextStyle(
                  fontFamily: 'DrummerDisplay', fontSize: 18,
                  color: NavaTheme.textPrimary, fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${progress.currentStreak}-day streak 🔥',
                style: const TextStyle(
                  fontFamily: 'DrummerBody', fontSize: 13, color: NavaTheme.neonGold,
                ),
              ),
            ],
          ),
        ),
        // Avatar
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            gradient: NavaTheme.neonGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: NavaTheme.cyanGlow,
          ),
          child: Center(
            child: Text(
              progress.displayName.isNotEmpty ? progress.displayName[0].toUpperCase() : 'D',
              style: const TextStyle(
                fontFamily: 'DrummerDisplay', fontSize: 22,
                color: NavaTheme.background, fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 600.ms);
  }

  Widget _buildLevelCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            NavaTheme.neonCyan.withOpacity(0.15),
            NavaTheme.neonPurple.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NavaTheme.neonCyan.withOpacity(0.3)),
        boxShadow: NavaTheme.neonGlow(NavaTheme.neonCyan, radius: 20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('LEVEL', style: TextStyle(
                    fontFamily: 'DrummerBody', fontSize: 11,
                    color: NavaTheme.textMuted, letterSpacing: 2,
                  )),
                  Text(
                    progress.level.toString(),
                    style: const TextStyle(
                      fontFamily: 'DrummerDisplay', fontSize: 52,
                      color: NavaTheme.neonCyan, fontWeight: FontWeight.bold, height: 1,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('TOTAL XP', style: TextStyle(
                    fontFamily: 'DrummerBody', fontSize: 11,
                    color: NavaTheme.textMuted, letterSpacing: 2,
                  )),
                  Text(
                    _formatNumber(progress.totalXp),
                    style: const TextStyle(
                      fontFamily: 'DrummerDisplay', fontSize: 28,
                      color: NavaTheme.neonGold,
                    ),
                  ),
                  Text(
                    '+${_formatNumber(progress.xpForNextLevel - progress.xpInCurrentLevel)} to next',
                    style: const TextStyle(
                      fontFamily: 'DrummerBody', fontSize: 11, color: NavaTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // XP Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.levelProgress.clamp(0, 1),
              backgroundColor: NavaTheme.surfaceCard,
              valueColor: const AlwaysStoppedAnimation(NavaTheme.neonCyan),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatNumber(progress.xpInCurrentLevel), style: const TextStyle(
                fontFamily: 'DrummerBody', fontSize: 10, color: NavaTheme.textMuted,
              )),
              Text(_formatNumber(progress.xpForNextLevel), style: const TextStyle(
                fontFamily: 'DrummerBody', fontSize: 10, color: NavaTheme.textMuted,
              )),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1);
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _StatCard(label: 'STREAK', value: '${progress.currentStreak}d', icon: '🔥', color: NavaTheme.neonGold),
        const SizedBox(width: 12),
        _StatCard(label: 'BEST COMBO', value: '${progress.maxStreak}', icon: '⚡', color: NavaTheme.neonCyan),
        const SizedBox(width: 12),
        _StatCard(label: 'SONGS', value: progress.songBestScores.length.toString(), icon: '🎵', color: NavaTheme.neonPurple),
      ],
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildAccuracyChart() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ACCURACY THIS WEEK', style: TextStyle(
          fontFamily: 'DrummerDisplay', fontSize: 13,
          color: NavaTheme.textSecondary, letterSpacing: 2,
        )),
        const SizedBox(height: 14),
        Container(
          height: 160,
          padding: const EdgeInsets.fromLTRB(0, 12, 12, 0),
          decoration: BoxDecoration(
            color: NavaTheme.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NavaTheme.neonCyan.withOpacity(0.1)),
          ),
          child: LineChart(
            LineChartData(
              minY: 0, maxY: 100,
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                      return Text(days[v.toInt() % 7], style: const TextStyle(
                        fontFamily: 'DrummerBody', fontSize: 10, color: NavaTheme.textMuted,
                      ));
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 25,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: const TextStyle(
                      fontFamily: 'DrummerBody', fontSize: 9, color: NavaTheme.textMuted,
                    )),
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                getDrawingHorizontalLine: (_) => FlLine(
                  color: NavaTheme.neonCyan.withOpacity(0.05), strokeWidth: 1,
                ),
                getDrawingVerticalLine: (_) => const FlLine(color: Colors.transparent),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: _weeklyAccuracy.asMap().entries
                      .map((e) => FlSpot(e.key.toDouble(), e.value))
                      .toList(),
                  isCurved: true,
                  color: NavaTheme.neonCyan,
                  barWidth: 2.5,
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [NavaTheme.neonCyan.withOpacity(0.3), NavaTheme.neonCyan.withOpacity(0)],
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    ),
                  ),
                  dotData: FlDotData(
                    getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                      radius: 4,
                      color: NavaTheme.neonCyan,
                      strokeWidth: 2,
                      strokeColor: NavaTheme.background,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 300.ms);
  }

  Widget _buildAchievements() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('ACHIEVEMENTS', style: TextStyle(
              fontFamily: 'DrummerDisplay', fontSize: 13,
              color: NavaTheme.textSecondary, letterSpacing: 2,
            )),
            Text('${_achievements.where((a) => a.unlocked).length}/${_achievements.length}',
              style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 12, color: NavaTheme.neonGold),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: _achievements.map((a) => _AchievementTile(achievement: a)).toList(),
        ),
      ],
    ).animate().fadeIn(delay: 400.ms);
  }

  Widget _buildRecentActivity() {
    // Prefer real Firestore sessions; fall back to songBestScores map
    final hasSessions = widget.recentSessions.isNotEmpty;
    final hasFallback = progress.songBestScores.isNotEmpty;
    if (!hasSessions && !hasFallback) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('RECENT SESSIONS', style: TextStyle(
          fontFamily: 'DrummerDisplay', fontSize: 13,
          color: NavaTheme.textSecondary, letterSpacing: 2,
        )),
        const SizedBox(height: 14),

        if (hasSessions)
          ...widget.recentSessions.take(5).map((s) => _SessionTile(session: s))
        else
          ...progress.songBestScores.entries.take(3).map((e) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: NavaTheme.surfaceCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NavaTheme.neonCyan.withOpacity(0.1)),
            ),
            child: Row(children: [
              const Icon(Icons.music_note, color: NavaTheme.neonCyan, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(e.key, style: const TextStyle(
                fontFamily: 'DrummerBody', fontSize: 13, color: NavaTheme.textPrimary))),
              Text(_formatNumber(e.value), style: const TextStyle(
                fontFamily: 'DrummerDisplay', fontSize: 14, color: NavaTheme.neonGold)),
            ]),
          )),
      ],
    ).animate().fadeIn(delay: 500.ms);
  }

  String _formatNumber(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

class _StatCard extends StatelessWidget {
  final String label, value, icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NavaTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(
            fontFamily: 'DrummerDisplay', fontSize: 20, color: color, fontWeight: FontWeight.bold,
          )),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(
            fontFamily: 'DrummerBody', fontSize: 9,
            color: NavaTheme.textMuted, letterSpacing: 1,
          )),
        ],
      ),
    ),
  );
}

class _Achievement {
  final String name, emoji, description;
  final bool unlocked;
  const _Achievement(this.name, this.emoji, this.description, this.unlocked);
}

class _AchievementTile extends StatelessWidget {
  final _Achievement achievement;
  const _AchievementTile({required this.achievement});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: achievement.unlocked ? NavaTheme.neonGold.withOpacity(0.1) : NavaTheme.surfaceCard,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: achievement.unlocked ? NavaTheme.neonGold.withOpacity(0.5) : NavaTheme.neonCyan.withOpacity(0.1),
      ),
    ),
    child: Tooltip(
      message: achievement.description,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            achievement.emoji,
            style: TextStyle(fontSize: 24, color: achievement.unlocked ? null : const Color(0x44FFFFFF)),
          ),
          const SizedBox(height: 6),
          Text(
            achievement.name,
            style: TextStyle(
              fontFamily: 'DrummerBody', fontSize: 9,
              color: achievement.unlocked ? NavaTheme.neonGold : NavaTheme.textMuted,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ],
      ),
    ),
  );
}

// ── Real session tile ─────────────────────────────────────────────────────────
class _SessionTile extends StatelessWidget {
  final PerformanceSession session;
  const _SessionTile({required this.session});

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
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: NavaTheme.surfaceCard,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _gradeColor.withOpacity(0.2)),
    ),
    child: Row(children: [
      // Grade badge
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: _gradeColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _gradeColor.withOpacity(0.4)),
        ),
        child: Center(child: Text(session.letterGrade, style: TextStyle(
          fontFamily: 'DrummerDisplay', fontSize: 14,
          color: _gradeColor, fontWeight: FontWeight.bold))),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(session.song.title, style: const TextStyle(
          fontFamily: 'DrummerBody', fontSize: 13, color: NavaTheme.textPrimary,
          fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(
          '${session.accuracyPercent.toStringAsFixed(1)}%  ·  ${session.maxCombo}x combo',
          style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 10,
              color: NavaTheme.textMuted)),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${session.xpEarned} XP', style: const TextStyle(
          fontFamily: 'DrummerDisplay', fontSize: 13, color: NavaTheme.neonGold)),
        Text('${session.totalScore}pts', style: const TextStyle(
          fontFamily: 'DrummerBody', fontSize: 10, color: NavaTheme.textMuted)),
      ]),
    ]),
  );
}
