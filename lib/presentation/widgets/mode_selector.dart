// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Mode Selector
// Modal que aparece al seleccionar una canción.
// El usuario elige: Modo Juego (notas cayendo) o Modo Partitura.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../domain/entities/entities.dart';
import '../theme/nava_theme.dart';

// ── Enum ──────────────────────────────────────────────────────────────────────
enum PracticeMode { game, sheet }

// ─────────────────────────────────────────────────────────────────────────────
// showModeSelectorSheet — función helper para mostrar el modal
// ─────────────────────────────────────────────────────────────────────────────
Future<PracticeMode?> showModeSelectorSheet(
  BuildContext context, {
  required Song song,
}) {
  return showModalBottomSheet<PracticeMode>(
    context:             context,
    isScrollControlled:  true,
    backgroundColor:     Colors.transparent,
    builder: (_) => ModeSelectorSheet(song: song),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ModeSelectorSheet
// ─────────────────────────────────────────────────────────────────────────────
class ModeSelectorSheet extends StatefulWidget {
  final Song song;
  const ModeSelectorSheet({super.key, required this.song});

  @override
  State<ModeSelectorSheet> createState() => _ModeSelectorSheetState();
}

class _ModeSelectorSheetState extends State<ModeSelectorSheet> {
  PracticeMode _selected = PracticeMode.game;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.88;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color:        NavaTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [

        // Handle
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color:        NavaTheme.textMuted.withOpacity(0.4),
            borderRadius: BorderRadius.circular(2)),
        ),

        // Song info
        Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color:        NavaTheme.padColor(_mainPad(widget.song)).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(
                color: NavaTheme.padColor(_mainPad(widget.song)).withOpacity(0.4)),
            ),
            child: Center(child: Text(_genreEmoji(widget.song.genre),
                style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.song.title,
              style: const TextStyle(fontFamily: 'DrummerDisplay', fontSize: 15,
                  color: NavaTheme.textPrimary, fontWeight: FontWeight.bold),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(widget.song.artist,
              style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 12,
                  color: NavaTheme.textSecondary)),
          ])),
          _Tag('${widget.song.bpm} BPM', NavaTheme.neonGold),
        ]),

        const SizedBox(height: 24),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('ELIGE EL MODO', style: TextStyle(
              fontFamily: 'DrummerBody', fontSize: 10,
              color:      NavaTheme.textMuted, letterSpacing: 2)),
        ),
        const SizedBox(height: 12),

        // Mode cards
        Row(children: [
          Expanded(child: _ModeCard(
            mode:        PracticeMode.game,
            selected:    _selected == PracticeMode.game,
            title:       'MODO JUEGO',
            subtitle:    'Notas cayendo\nhacia la línea de golpe',
            emoji:       '🎮',
            badge:       'RECOMENDADO',
            badgeColor:  NavaTheme.neonGreen,
            features:    const ['Feedback PERFECT / GOOD / MISS',
                                'Sistema de combo y puntos',
                                'Partículas y efectos visuales'],
            onTap: () => setState(() => _selected = PracticeMode.game),
          )),
          const SizedBox(width: 12),
          Expanded(child: _ModeCard(
            mode:        PracticeMode.sheet,
            selected:    _selected == PracticeMode.sheet,
            title:       'PARTITURA',
            subtitle:    'Notación musical real\ncon cursor animado',
            emoji:       '🎼',
            badge:       'LEER MÚSICA',
            badgeColor:  NavaTheme.neonPurple,
            features:    const ['Pentagrama estándar de batería',
                                'Notas se iluminan al tocarlas',
                                'Ideal para aprender a leer'],
            onTap: () => setState(() => _selected = PracticeMode.sheet),
          )),
        ]).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),

        const SizedBox(height: 20),

        // Info row (difficulty, tempo, xp)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color:        NavaTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _InfoItem(label: 'DIFICULTAD',
                  value: _diffLabel(widget.song.difficulty),
                  color: _diffColor(widget.song.difficulty)),
              _Divider(),
              _InfoItem(label: 'TEMPO',
                  value: '${widget.song.bpm} BPM',
                  color: NavaTheme.neonGold),
              _Divider(),
              _InfoItem(label: 'RECOMPENSA',
                  value: '+${widget.song.xpReward} XP',
                  color: NavaTheme.neonCyan),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Start button
        SizedBox(
          width:  double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, _selected),
            style: ElevatedButton.styleFrom(
              backgroundColor: NavaTheme.neonCyan,
              shape:           RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_selected == PracticeMode.game ? '🎮' : '🎼',
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Text(
                _selected == PracticeMode.game
                    ? 'INICIAR MODO JUEGO'
                    : 'ABRIR PARTITURA',
                style: const TextStyle(
                    fontFamily:  'DrummerDisplay',
                    fontSize:    14,
                    color:       NavaTheme.background,
                    letterSpacing: 1,
                    fontWeight:  FontWeight.bold),
              ),
            ]),
          ),
        ),
      ]),
      ), // SingleChildScrollView
    );
  }

  DrumPad _mainPad(Song s) {
    switch (s.genre) {
      case Genre.metal: return DrumPad.crash1;
      case Genre.funk:  return DrumPad.snare;
      case Genre.jazz:  return DrumPad.ride;
      default:          return DrumPad.kick;
    }
  }

  String _genreEmoji(Genre g) {
    switch (g) {
      case Genre.cristiana:  return '✝️';
      case Genre.rock:       return '🎸';
      case Genre.metal:      return '🔥';
      case Genre.funk:       return '🎷';
      case Genre.jazz:       return '🎺';
      case Genre.latin:      return '🪘';
      case Genre.pop:        return '🎵';
      case Genre.electronic: return '🎛️';
      default:               return '🥁';
    }
  }

  String _diffLabel(Difficulty d) {
    switch (d) {
      case Difficulty.beginner:     return 'PRINCIPIANTE';
      case Difficulty.intermediate: return 'INTERMEDIO';
      case Difficulty.advanced:     return 'AVANZADO';
      case Difficulty.expert:       return 'EXPERTO';
    }
  }

  Color _diffColor(Difficulty d) {
    switch (d) {
      case Difficulty.beginner:     return NavaTheme.neonGreen;
      case Difficulty.intermediate: return NavaTheme.neonGold;
      case Difficulty.advanced:     return const Color(0xFFFF8C00);
      case Difficulty.expert:       return NavaTheme.neonMagenta;
    }
  }
}

// ── Mode Card ──────────────────────────────────────────────────────────────────
class _ModeCard extends StatelessWidget {
  final PracticeMode mode;
  final bool         selected;
  final String       title, subtitle, emoji, badge;
  final Color        badgeColor;
  final List<String> features;
  final VoidCallback onTap;

  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.badge,
    required this.badgeColor,
    required this.features,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 200.ms,
        padding:  const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        selected
              ? NavaTheme.neonCyan.withOpacity(0.08)
              : NavaTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border:       Border.all(
            color: selected ? NavaTheme.neonCyan : NavaTheme.textMuted.withOpacity(0.2),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected ? NavaTheme.cyanGlow : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color:        badgeColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
              border:       Border.all(color: badgeColor.withOpacity(0.4)),
            ),
            child: Text(badge, style: TextStyle(
                fontFamily: 'DrummerBody', fontSize: 8,
                color: badgeColor, letterSpacing: 1)),
          ),

          const SizedBox(height: 10),

          // Emoji
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 6),

          // Title
          Text(title, style: TextStyle(
              fontFamily:  'DrummerDisplay', fontSize: 12,
              color: selected ? NavaTheme.neonCyan : NavaTheme.textPrimary,
              fontWeight:  FontWeight.bold, letterSpacing: 1)),

          const SizedBox(height: 4),

          // Subtitle
          Text(subtitle, style: const TextStyle(
              fontFamily: 'DrummerBody', fontSize: 10,
              color: NavaTheme.textSecondary, height: 1.4)),

          const SizedBox(height: 10),

          // Feature list
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('·', style: TextStyle(
                  color: selected ? NavaTheme.neonCyan : NavaTheme.textMuted,
                  fontSize: 10)),
              const SizedBox(width: 5),
              Expanded(child: Text(f, style: const TextStyle(
                  fontFamily: 'DrummerBody', fontSize: 9,
                  color: NavaTheme.textMuted, height: 1.3))),
            ]),
          )),

          // Selected indicator
          if (selected) ...[
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:        NavaTheme.neonCyan.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('✓ SELECCIONADO', style: TextStyle(
                    fontFamily: 'DrummerBody', fontSize: 8,
                    color: NavaTheme.neonCyan, letterSpacing: 1)),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────
class _Tag extends StatelessWidget {
  final String text;
  final Color  color;
  const _Tag(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color:        color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(6),
      border:       Border.all(color: color.withOpacity(0.4)),
    ),
    child: Text(text, style: TextStyle(
        fontFamily: 'DrummerBody', fontSize: 10,
        color: color, fontWeight: FontWeight.bold)),
  );
}

class _InfoItem extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _InfoItem({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(fontFamily: 'DrummerDisplay',
        fontSize: 13, color: color, fontWeight: FontWeight.bold)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontFamily: 'DrummerBody',
        fontSize: 8, color: NavaTheme.textMuted, letterSpacing: 1)),
  ]);
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      width: 1, height: 28,
      color: NavaTheme.textMuted.withOpacity(0.15));
}
