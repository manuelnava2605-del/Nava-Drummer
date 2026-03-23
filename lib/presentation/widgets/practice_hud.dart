import 'package:flutter/material.dart';
import '../../domain/entities/entities.dart';
import '../../core/practice_engine.dart';
import '../theme/nava_theme.dart';

class PracticeHud extends StatelessWidget {
  final Song         song;
  final ScoreState   scoreState;
  final EngineState  engineState;
  final double       playheadSeconds;
  final double       tempoMultiplier;

  final bool isLoading;
  final bool loopEnabled;
  final bool showSettings;
  final bool isGameMode;

  final VoidCallback onBack;
  final VoidCallback onPlayPause;
  final VoidCallback onRestart;
  final VoidCallback onToggleLoop;
  final VoidCallback onToggleSettings;  // opens the in-game settings panel
  final VoidCallback onToggleMode;

  const PracticeHud({
    super.key,
    required this.song,
    required this.scoreState,
    required this.engineState,
    required this.playheadSeconds,
    required this.tempoMultiplier,
    required this.isLoading,
    required this.loopEnabled,
    required this.showSettings,
    required this.isGameMode,
    required this.onBack,
    required this.onPlayPause,
    required this.onRestart,
    required this.onToggleLoop,
    required this.onToggleSettings,
    required this.onToggleMode,
  });

  bool get _isPlaying =>
      engineState == EngineState.playing ||
      engineState == EngineState.countIn;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          // ── TOP BAR: back · title · controls ──────────────────────────────
          _TopBar(
            title:            song.title,
            artist:           song.artist,
            isPlaying:        _isPlaying,
            loopEnabled:      loopEnabled,
            isGameMode:       isGameMode,
            showSettings:     showSettings,
            tempoMultiplier:  tempoMultiplier,
            onBack:           onBack,
            onPlayPause:      onPlayPause,
            onRestart:        onRestart,
            onToggleLoop:     onToggleLoop,
            onToggleSettings: onToggleSettings,
            onToggleMode:     onToggleMode,
          ),

          const SizedBox(height: 4),

          // ── SCORE · COMBO · ACC ───────────────────────────────────────────
          _ScoreRow(scoreState: scoreState),

          const SizedBox(height: 6),

          // ── PROGRESS ──────────────────────────────────────────────────────
          _ProgressBar(progress: playheadSeconds, song: song),

          // No Spacer — HUD ends here, leaving the full lower area for pads.
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP BAR  (back + title/artist + compact controls)
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String title;
  final String artist;
  final bool   isPlaying;
  final bool   loopEnabled;
  final bool   isGameMode;
  final bool   showSettings;
  final double tempoMultiplier;

  final VoidCallback onBack;
  final VoidCallback onPlayPause;
  final VoidCallback onRestart;
  final VoidCallback onToggleLoop;
  final VoidCallback onToggleSettings;
  final VoidCallback onToggleMode;

  const _TopBar({
    required this.title,
    required this.artist,
    required this.isPlaying,
    required this.loopEnabled,
    required this.isGameMode,
    required this.showSettings,
    required this.tempoMultiplier,
    required this.onBack,
    required this.onPlayPause,
    required this.onRestart,
    required this.onToggleLoop,
    required this.onToggleSettings,
    required this.onToggleMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          // Back
          _TinyBtn(Icons.arrow_back_ios_new, onBack, size: 16),

          const SizedBox(width: 4),

          // Title + artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'DrummerDisplay',
                    fontSize: 12,
                    color: NavaTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'DrummerBody',
                    fontSize: 9,
                    color: NavaTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // ── Compact control buttons ────────────────────────────────────
          _TinyBtn(Icons.refresh, onRestart),
          const SizedBox(width: 2),

          // Play/pause — slightly larger to be the primary action
          _TinyBtn(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            onPlayPause,
            size: 20,
            color: NavaTheme.neonCyan,
            highlighted: true,
          ),
          const SizedBox(width: 2),

          _TinyBtn(
            loopEnabled ? Icons.repeat_on_rounded : Icons.repeat_rounded,
            onToggleLoop,
            color: loopEnabled ? NavaTheme.neonGold : NavaTheme.textSecondary,
          ),
          const SizedBox(width: 2),

          _TinyBtn(
            isGameMode ? Icons.music_note_rounded : Icons.notes_rounded,
            onToggleMode,
          ),
          const SizedBox(width: 2),

          // Settings — highlighted when panel is open
          _TinyBtn(
            Icons.tune_rounded,
            onToggleSettings,
            color: showSettings ? NavaTheme.neonCyan : NavaTheme.textSecondary,
            highlighted: showSettings,
          ),

          const SizedBox(width: 4),
          // Tempo label (tap settings to change)
          Text(
            '${(tempoMultiplier * 100).round()}%',
            style: const TextStyle(
              fontFamily: 'DrummerBody',
              fontSize: 9,
              color: NavaTheme.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tiny icon button — no large circular background, minimal footprint
// ─────────────────────────────────────────────────────────────────────────────
class _TinyBtn extends StatelessWidget {
  final IconData     icon;
  final VoidCallback onTap;
  final double       size;
  final Color        color;
  final bool         highlighted;

  const _TinyBtn(
    this.icon,
    this.onTap, {
    this.size        = 18,
    this.color       = NavaTheme.textSecondary,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: highlighted
            ? BoxDecoration(
                shape: BoxShape.circle,
                color: NavaTheme.neonCyan.withOpacity(0.12),
                border: Border.all(
                    color: NavaTheme.neonCyan.withOpacity(0.4), width: 1),
              )
            : null,
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCORE / COMBO / ACC
// ─────────────────────────────────────────────────────────────────────────────
class _ScoreRow extends StatelessWidget {
  final ScoreState scoreState;
  const _ScoreRow({required this.scoreState});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _Stat(label: 'SCORE', value: scoreState.score.toString()),
        _Stat(
          label: 'COMBO',
          value: scoreState.combo.toString(),
          highlight: true,
        ),
        _Stat(
          label: 'ACC',
          value: '${(scoreState.accuracy * 100).toStringAsFixed(1)}%',
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final bool   highlight;
  const _Stat({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label,
        style: const TextStyle(
          fontFamily: 'DrummerBody', fontSize: 9,
          color: NavaTheme.textMuted, letterSpacing: 1,
        )),
      const SizedBox(height: 1),
      Text(value,
        style: TextStyle(
          fontFamily: 'DrummerDisplay',
          fontSize: highlight ? 18 : 14,
          fontWeight: FontWeight.bold,
          color: highlight ? NavaTheme.neonCyan : NavaTheme.textPrimary,
        )),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PROGRESS BAR
// ─────────────────────────────────────────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  final double progress;
  final Song   song;
  const _ProgressBar({required this.progress, required this.song});

  @override
  Widget build(BuildContext context) {
    final total    = song.duration.inSeconds.toDouble();
    final fraction = (total > 0) ? (progress / total).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 3,
        borderRadius: BorderRadius.circular(2),
        color: NavaTheme.neonCyan,
        backgroundColor: NavaTheme.textMuted.withOpacity(0.15),
      ),
    );
  }
}
