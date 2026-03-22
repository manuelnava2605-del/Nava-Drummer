// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Song Detail Screen
// Shows full song metadata before entering practice mode.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../domain/entities/entities.dart';
import '../theme/nava_theme.dart';
import '../widgets/mode_selector.dart';

class SongDetailScreen extends StatelessWidget {
  final Song           song;
  final int            userLevel;
  final void Function(Song, PracticeMode) onStartPractice;
  /// Called when the user taps a section and picks a practice mode.
  final void Function(Song, SongSection, PracticeMode)? onSectionPractice;

  const SongDetailScreen({
    super.key,
    required this.song,
    required this.userLevel,
    required this.onStartPractice,
    this.onSectionPractice,
  });

  Color get _diffColor {
    switch (song.difficulty) {
      case Difficulty.beginner:     return NavaTheme.neonGreen;
      case Difficulty.intermediate: return NavaTheme.neonGold;
      case Difficulty.advanced:     return const Color(0xFFFF8C00);
      case Difficulty.expert:       return NavaTheme.neonMagenta;
    }
  }

  String get _diffLabel {
    switch (song.difficulty) {
      case Difficulty.beginner:     return 'PRINCIPIANTE';
      case Difficulty.intermediate: return 'INTERMEDIO';
      case Difficulty.advanced:     return 'AVANZADO';
      case Difficulty.expert:       return 'EXPERTO';
    }
  }

  String get _genreEmoji {
    switch (song.genre) {
      case Genre.cristiana: return '✝️';
      case Genre.rock:      return '🎸';
      case Genre.pop:       return '🎵';
      case Genre.metal:     return '🔥';
      case Genre.funk:      return '🎷';
      case Genre.jazz:      return '🎺';
      case Genre.latin:     return '🪘';
      default:              return '🥁';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavaTheme.background,
      body: Stack(children: [
        // Gradient header background
        Container(
          height: 280,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _diffColor.withOpacity(0.35),
                NavaTheme.background,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),

        SafeArea(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Back button
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 24),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: NavaTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: NavaTheme.neonCyan.withOpacity(0.2)),
                ),
                child: const Icon(Icons.arrow_back_ios_new, color: NavaTheme.textPrimary, size: 18),
              ),
            ).animate().fadeIn(duration: 300.ms),

            // Drum icon + song header
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Album art placeholder
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: _diffColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _diffColor.withOpacity(0.4), width: 2),
                ),
                child: Center(child: Text(_genreEmoji, style: const TextStyle(fontSize: 44))),
              ).animate().scale(duration: 400.ms, curve: Curves.easeOut),

              const SizedBox(width: 20),

              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(song.title,
                  style: const TextStyle(fontFamily: 'DrummerDisplay', fontSize: 20,
                      color: NavaTheme.textPrimary, fontWeight: FontWeight.bold, height: 1.2),
                ).animate().fadeIn(delay: 100.ms).slideX(begin: 0.1),

                const SizedBox(height: 6),
                Text(song.artist,
                  style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 14,
                      color: NavaTheme.textSecondary),
                ).animate().fadeIn(delay: 150.ms),

                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _Badge(_diffLabel, _diffColor),
                  _Badge('${song.bpm} BPM', NavaTheme.neonCyan),
                  _Badge(_formatDuration(song.duration), NavaTheme.textMuted),
                  if (song.techniqueTag != null)
                    _Badge(song.techniqueTag!, NavaTheme.neonPurple),
                ]).animate().fadeIn(delay: 200.ms),
              ])),
            ]),

            const SizedBox(height: 32),

            // XP reward
            _InfoCard(children: [
              _InfoRow(Icons.star_rounded, '+${song.xpReward} XP', NavaTheme.neonGold),
              _InfoRow(Icons.music_note_rounded, _genreLabel(song.genre), NavaTheme.neonPurple),
              _InfoRow(Icons.speed_rounded, '${song.bpm} BPM', NavaTheme.neonCyan),
              _InfoRow(Icons.timer_outlined, _formatDuration(song.duration), NavaTheme.textSecondary),
            ]).animate().fadeIn(delay: 250.ms),

            const SizedBox(height: 24),

            // Sections if available
            if (song.sections.isNotEmpty) ...[
              const _SectionLabel('SECCIONES'),
              const SizedBox(height: 10),
              ...song.sections.map((s) => _SectionTile(
                section: s,
                onTap: onSectionPractice != null
                    ? () => _showSectionModeSheet(context, s)
                    : null,
              )).toList().animate(interval: 60.ms).fadeIn(),
              const SizedBox(height: 24),
            ],

            // Mode selection label
            const _SectionLabel('MODO DE PRÁCTICA'),
            const SizedBox(height: 12),

            // Mode buttons
            Row(children: [
              Expanded(child: _ModeButton(
                icon:    Icons.sports_esports_rounded,
                label:   'JUEGO',
                subtitle:'Notas cayendo',
                color:   NavaTheme.neonPurple,
                onTap:   () => onStartPractice(song, PracticeMode.game),
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2)),
              const SizedBox(width: 12),
              Expanded(child: _ModeButton(
                icon:    Icons.music_note_rounded,
                label:   'PARTITURA',
                subtitle:'Notación musical',
                color:   NavaTheme.neonCyan,
                onTap:   () => onStartPractice(song, PracticeMode.sheet),
              ).animate().fadeIn(delay: 360.ms).slideY(begin: 0.2)),
            ]),

            const SizedBox(height: 16),

            // Start button
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () => onStartPractice(song, PracticeMode.game),
              style: ElevatedButton.styleFrom(
                backgroundColor: NavaTheme.neonCyan,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.play_arrow_rounded, color: NavaTheme.background, size: 24),
                SizedBox(width: 8),
                Text('TOCAR', style: TextStyle(fontFamily: 'DrummerDisplay',
                    fontSize: 16, color: NavaTheme.background,
                    fontWeight: FontWeight.bold, letterSpacing: 2)),
              ]),
            ).animate().fadeIn(delay: 400.ms)),
          ]),
        )),
      ]),
    );
  }

  void _showSectionModeSheet(BuildContext context, SongSection section) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NavaTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(section.name, style: const TextStyle(fontFamily: 'DrummerDisplay',
              fontSize: 16, color: NavaTheme.textPrimary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          if (section.patternType.isNotEmpty)
            Text(section.patternType, style: const TextStyle(fontFamily: 'DrummerBody',
                fontSize: 11, color: NavaTheme.textMuted)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _ModeButton(
              icon: Icons.sports_esports_rounded, label: 'JUEGO',
              subtitle: 'Notas cayendo', color: NavaTheme.neonPurple,
              onTap: () {
                Navigator.pop(context);
                onSectionPractice!(song, section, PracticeMode.game);
              },
            )),
            const SizedBox(width: 12),
            Expanded(child: _ModeButton(
              icon: Icons.music_note_rounded, label: 'PARTITURA',
              subtitle: 'Notación musical', color: NavaTheme.neonCyan,
              onTap: () {
                Navigator.pop(context);
                onSectionPractice!(song, section, PracticeMode.sheet);
              },
            )),
          ]),
        ]),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _genreLabel(Genre? g) {
    if (g == null) return 'Varios';
    switch (g) {
      case Genre.cristiana: return 'Cristiana';
      case Genre.rock:      return 'Rock';
      case Genre.pop:       return 'Pop';
      case Genre.metal:     return 'Metal';
      case Genre.funk:      return 'Funk';
      case Genre.jazz:      return 'Jazz';
      case Genre.latin:     return 'Latino';
      default:              return 'Varios';
    }
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String text; final Color color;
  const _Badge(this.text, this.color);
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.35)),
    ),
    child: Text(text, style: TextStyle(fontFamily: 'DrummerBody',
        fontSize: 10, color: color, fontWeight: FontWeight.bold)),
  );
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: NavaTheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: NavaTheme.neonCyan.withOpacity(0.12)),
    ),
    child: Column(children: children),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon; final String text; final Color color;
  const _InfoRow(this.icon, this.text, this.color);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 12),
      Text(text, style: TextStyle(fontFamily: 'DrummerBody',
          fontSize: 13, color: color)),
    ]),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override Widget build(BuildContext context) => Text(text,
    style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 10,
        letterSpacing: 2, color: NavaTheme.textMuted));
}

class _SectionTile extends StatelessWidget {
  final SongSection  section;
  final VoidCallback? onTap;
  const _SectionTile({required this.section, this.onTap});

  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: NavaTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: onTap != null
            ? NavaTheme.neonCyan.withOpacity(0.28)
            : NavaTheme.neonCyan.withOpacity(0.12)),
      ),
      child: Row(children: [
        Icon(onTap != null ? Icons.play_circle_fill : Icons.play_circle_outline,
            color: NavaTheme.neonCyan, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(section.name, style: const TextStyle(
              fontFamily: 'DrummerBody', fontSize: 13, color: NavaTheme.textPrimary)),
          if (section.patternType.isNotEmpty)
            Text(section.patternType, style: const TextStyle(
                fontFamily: 'DrummerBody', fontSize: 9, color: NavaTheme.textMuted)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${section.durationSeconds.toStringAsFixed(0)}s',
            style: const TextStyle(fontFamily: 'DrummerBody',
                fontSize: 11, color: NavaTheme.textMuted)),
          if (section.displayLabel.isNotEmpty)
            Text(section.displayLabel, style: const TextStyle(
                fontFamily: 'DrummerDisplay', fontSize: 9, color: NavaTheme.neonCyan,
                fontWeight: FontWeight.bold)),
        ]),
      ]),
    ),
  );
}

class _ModeButton extends StatelessWidget {
  final IconData icon; final String label, subtitle;
  final Color color; final VoidCallback onTap;
  const _ModeButton({required this.icon, required this.label,
    required this.subtitle, required this.color, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontFamily: 'DrummerDisplay',
            fontSize: 12, color: color, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontFamily: 'DrummerBody',
            fontSize: 9, color: NavaTheme.textMuted)),
      ]),
    ),
  );
}
