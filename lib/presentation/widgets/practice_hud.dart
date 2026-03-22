// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Practice HUD  (premium overlay for gameplay screen)
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../domain/entities/entities.dart';
import '../../core/practice_engine.dart';
import '../theme/nava_theme.dart';

// ── Song Progress Bar ─────────────────────────────────────────────────────────
class SongProgressBar extends StatelessWidget {
  final double progress; // 0.0–1.0
  final Color  color;
  const SongProgressBar({super.key, required this.progress, this.color = NavaTheme.neonCyan});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value:           progress.clamp(0.0, 1.0),
          backgroundColor: NavaTheme.surface,
          valueColor:      AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }
}

// ── Combo Widget ──────────────────────────────────────────────────────────────
class ComboWidget extends StatelessWidget {
  final int   combo;
  final int   multiplier;
  const ComboWidget({super.key, required this.combo, required this.multiplier});

  Color get _color {
    if (multiplier >= 8) return NavaTheme.neonMagenta;
    if (multiplier >= 4) return NavaTheme.neonGold;
    if (multiplier >= 2) return NavaTheme.neonCyan;
    return NavaTheme.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    if (combo == 0) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(
        '$combo',
        style: TextStyle(
          fontFamily:  'DrummerDisplay',
          fontSize:    28,
          fontWeight:  FontWeight.bold,
          color:       _color,
          shadows:     [Shadow(color: _color.withOpacity(0.7), blurRadius: 12)],
        ),
      ).animate(key: ValueKey(combo))
       .scale(begin: const Offset(1.3, 1.3), duration: 200.ms, curve: Curves.easeOut),
      Text(
        'COMBO',
        style: TextStyle(
          fontFamily:  'DrummerBody',
          fontSize:    8,
          letterSpacing: 2,
          color:       _color.withOpacity(0.7),
        ),
      ),
      if (multiplier > 1)
        Container(
          margin: const EdgeInsets.only(top: 3),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _color.withOpacity(0.5)),
          ),
          child: Text('×$multiplier', style: TextStyle(
            fontFamily: 'DrummerDisplay', fontSize: 9,
            color: _color, fontWeight: FontWeight.bold,
          )),
        ).animate(key: ValueKey(multiplier))
         .scale(begin: const Offset(1.5, 1.5), duration: 200.ms, curve: Curves.easeOut),
    ]);
  }
}

// ── Animated Score Counter ────────────────────────────────────────────────────
class AnimatedScoreCounter extends StatefulWidget {
  final int   score;
  const AnimatedScoreCounter({super.key, required this.score});

  @override
  State<AnimatedScoreCounter> createState() => _AnimatedScoreCounterState();
}

class _AnimatedScoreCounterState extends State<AnimatedScoreCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<int>      _anim;
  int _prev = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: 250.ms);
    _anim = IntTween(begin: 0, end: widget.score).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _prev = widget.score;
  }

  @override
  void didUpdateWidget(AnimatedScoreCounter old) {
    super.didUpdateWidget(old);
    if (widget.score != _prev) {
      _anim = IntTween(begin: _prev, end: widget.score).animate(
          CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
      _prev = widget.score;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Text(
      _anim.value.toString().padLeft(6, '0'),
      style: const TextStyle(
        fontFamily: 'DrummerDisplay', fontSize: 14,
        color: NavaTheme.neonCyan, fontWeight: FontWeight.bold,
        shadows: [Shadow(color: NavaTheme.neonCyan, blurRadius: 8)],
      ),
    ),
  );
}

// ── Accuracy Badge ────────────────────────────────────────────────────────────
class AccuracyBadge extends StatelessWidget {
  final double accuracy; // 0.0–1.0
  const AccuracyBadge({super.key, required this.accuracy});

  Color get _color {
    final pct = accuracy * 100;
    if (pct >= 95) return NavaTheme.hitPerfect;
    if (pct >= 80) return NavaTheme.neonGold;
    if (pct >= 60) return NavaTheme.neonPurple;
    return NavaTheme.hitMiss;
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${(accuracy * 100).toStringAsFixed(1)}%',
      style: TextStyle(
        fontFamily: 'DrummerBody', fontSize: 12,
        color: _color, fontWeight: FontWeight.bold,
      ),
    );
  }
}

// ── Hit Breakdown Mini ────────────────────────────────────────────────────────
class HitBreakdownMini extends StatelessWidget {
  final int perfect, good, early, late, miss;
  const HitBreakdownMini({super.key,
    required this.perfect, required this.good,
    required this.early,   required this.late,
    required this.miss});

  @override
  Widget build(BuildContext context) => Column(children: [
    _Row('P',  perfect, NavaTheme.hitPerfect),
    _Row('G',  good,    NavaTheme.hitGood),
    _Row('E',  early,   const Color(0xFF00E5FF)),   // cyan — early
    _Row('L',  late,    const Color(0xFFFF9800)),   // orange — late
    _Row('M',  miss,    NavaTheme.hitMiss),
  ]);

  Widget _Row(String l, int v, Color c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(fontFamily: 'DrummerBody', fontSize: 8, color: c)),
      const SizedBox(width: 8),
      Text('$v', style: TextStyle(fontFamily: 'DrummerDisplay',
          fontSize: 9, color: c, fontWeight: FontWeight.bold)),
    ]),
  );
}

// ── Practice HUD (full overlay layout) ───────────────────────────────────────
class PracticeHud extends StatelessWidget {
  final Song          song;
  final ScoreState    scoreState;
  final EngineState   engineState;
  final double        playheadSeconds;
  final double        tempoMultiplier;
  final bool          isLoading;
  final bool          loopEnabled;
  final bool          showSettings;
  final VoidCallback  onBack;
  final VoidCallback  onPlayPause;
  final VoidCallback  onRestart;
  final VoidCallback  onToggleLoop;
  final VoidCallback  onToggleSettings;
  final VoidCallback  onToggleMode;
  final bool          isGameMode;

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
    required this.onBack,
    required this.onPlayPause,
    required this.onRestart,
    required this.onToggleLoop,
    required this.onToggleSettings,
    required this.onToggleMode,
    required this.isGameMode,
  });

  double get _progress {
    final dur = song.duration.inSeconds.toDouble();
    if (dur <= 0) return 0;
    return (playheadSeconds / dur).clamp(0.0, 1.0);
  }

  bool get _isPlaying =>
      engineState == EngineState.playing || engineState == EngineState.countIn;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // ── Top bar ──────────────────────────────────────────────────────────
      Positioned(
        top: 0, left: 0, right: 0,
        child: _TopBar(
          song:             song,
          bpm:              (tempoMultiplier * song.bpm).round(),
          isGameMode:       isGameMode,
          isPlaying:        _isPlaying,
          isLoading:        isLoading,
          engineState:      engineState,
          loopEnabled:      loopEnabled,
          onBack:           onBack,
          onToggleMode:     onToggleMode,
          onToggleSettings: onToggleSettings,
          onPlayPause:      onPlayPause,
          onRestart:        onRestart,
          onToggleLoop:     onToggleLoop,
          progress:         _progress,
        ),
      ),

      // ── Score + Combo panel (right side) ─────────────────────────────────
      Positioned(
        right: 10,
        top:   MediaQuery.of(context).padding.top + 64,
        child: _ScorePanel(scoreState: scoreState),
      ),

      // transport moved to top bar — no bottom overlay
    ]);
  }
}

// ── Top Bar ───────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final Song        song;
  final int         bpm;
  final bool        isGameMode, isPlaying, isLoading, loopEnabled;
  final EngineState engineState;
  final double      progress;
  final VoidCallback onBack, onToggleMode, onToggleSettings;
  final VoidCallback onPlayPause, onRestart, onToggleLoop;

  const _TopBar({
    required this.song, required this.bpm, required this.isGameMode,
    required this.isPlaying, required this.isLoading, required this.engineState,
    required this.loopEnabled, required this.progress,
    required this.onBack, required this.onToggleMode, required this.onToggleSettings,
    required this.onPlayPause, required this.onRestart, required this.onToggleLoop,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [NavaTheme.background, NavaTheme.background.withOpacity(0)],
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
            ),
          ),
          child: Row(children: [
            // Back
            _HudBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
            const SizedBox(width: 8),
            // Song info
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(song.title,
                style: const TextStyle(fontFamily: 'DrummerDisplay', fontSize: 11,
                    color: NavaTheme.textPrimary, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
              Text('${song.artist} · $bpm BPM',
                style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 9,
                    color: NavaTheme.textSecondary)),
            ])),
            // ── Transport controls ─────────────────────────
            _HudBtn(icon: Icons.replay_rounded, onTap: onRestart),
            const SizedBox(width: 6),
            _PlayPauseBtn(
              isLoading: isLoading, isPlaying: isPlaying,
              engineState: engineState, onTap: onPlayPause, small: true),
            const SizedBox(width: 6),
            _HudBtn(
              icon: Icons.repeat_rounded,
              active: loopEnabled,
              onTap: onToggleLoop,
              tooltip: 'Loop',
            ),
            const SizedBox(width: 8),
            // Mode toggle
            _ModeChip(isGame: isGameMode, onTap: onToggleMode),
            const SizedBox(width: 6),
            // Settings
            _HudBtn(icon: Icons.tune_rounded, onTap: onToggleSettings),
          ]),
        ),
        // Progress bar (full width)
        SongProgressBar(progress: progress),
      ]),
    );
  }
}

// ── Score panel ───────────────────────────────────────────────────────────────
class _ScorePanel extends StatelessWidget {
  final ScoreState scoreState;
  const _ScorePanel({required this.scoreState});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: NavaTheme.surface.withOpacity(0.90),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NavaTheme.neonCyan.withOpacity(0.18)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12)],
      ),
      child: Column(children: [
        AnimatedScoreCounter(score: scoreState.score),
        const SizedBox(height: 4),
        AccuracyBadge(accuracy: scoreState.accuracy),
        const SizedBox(height: 8),
        ComboWidget(combo: scoreState.combo, multiplier: scoreState.multiplier),
        const SizedBox(height: 8),
        HitBreakdownMini(
          perfect: scoreState.perfectCount,
          good:    scoreState.goodCount,
          early:   scoreState.earlyCount,
          late:    scoreState.lateCount,
          miss:    scoreState.missCount,
        ),
        const SizedBox(height: 6),
        _InputSourceChip(source: scoreState.lastInputSource),
      ]),
    );
  }
}

// ── Bottom transport ──────────────────────────────────────────────────────────
class _BottomTransport extends StatelessWidget {
  final bool       isPlaying, isLoading, loopEnabled;
  final EngineState engineState;
  final VoidCallback onPlayPause, onRestart, onToggleLoop;
  const _BottomTransport({required this.isPlaying, required this.isLoading,
    required this.engineState, required this.loopEnabled,
    required this.onPlayPause, required this.onRestart, required this.onToggleLoop});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 32),
        decoration: BoxDecoration(gradient: LinearGradient(
          colors: [NavaTheme.background.withOpacity(0), NavaTheme.background],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        )),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _HudBtn(icon: Icons.replay_rounded, onTap: onRestart),
          const SizedBox(width: 20),
          _PlayPauseBtn(
            isLoading:   isLoading,
            isPlaying:   isPlaying,
            engineState: engineState,
            onTap:       onPlayPause,
          ),
          const SizedBox(width: 20),
          _HudBtn(
            icon: Icons.loop_rounded,
            active: loopEnabled,
            onTap: onToggleLoop,
          ),
        ]),
      ),
    );
  }
}

// ── Input Source Chip ─────────────────────────────────────────────────────────
class _InputSourceChip extends StatelessWidget {
  final InputSourceType source;
  const _InputSourceChip({required this.source});

  @override
  Widget build(BuildContext context) {
    final isOnScreen = source == InputSourceType.onScreenPad;
    final color = isOnScreen ? NavaTheme.neonCyan : NavaTheme.neonGold;
    final label = isOnScreen ? 'PANTALLA' : 'MIDI/HW';
    final icon  = isOnScreen ? Icons.touch_app_rounded : Icons.cable_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 9, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(
          fontFamily: 'DrummerBody', fontSize: 7,
          color: color, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ]),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────
class _HudBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool   active;
  final String? tooltip;
  const _HudBtn({required this.icon, required this.onTap,
      this.active = false, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final btn = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: active ? NavaTheme.neonCyan.withOpacity(0.15) : NavaTheme.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? NavaTheme.neonCyan.withOpacity(0.8)
                          : NavaTheme.neonCyan.withOpacity(0.25)),
        ),
        child: Icon(icon,
          color: active ? NavaTheme.neonCyan : NavaTheme.textPrimary, size: 17),
      ),
    );
    if (tooltip != null) return Tooltip(message: tooltip!, child: btn);
    return btn;
  }
}

class _ModeChip extends StatelessWidget {
  final bool isGame;
  final VoidCallback onTap;
  const _ModeChip({required this.isGame, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: 200.ms,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isGame
            ? NavaTheme.neonPurple.withOpacity(0.15)
            : NavaTheme.neonCyan.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isGame
            ? NavaTheme.neonPurple.withOpacity(0.6)
            : NavaTheme.neonCyan.withOpacity(0.6)),
      ),
      child: Text(isGame ? 'JUEGO' : 'PARTITURA',
        style: TextStyle(fontFamily: 'DrummerBody', fontSize: 9, letterSpacing: 1,
          fontWeight: FontWeight.bold,
          color: isGame ? NavaTheme.neonPurple : NavaTheme.neonCyan)),
    ),
  );
}

class _PlayPauseBtn extends StatelessWidget {
  final bool isLoading, isPlaying;
  final bool small;
  final EngineState engineState;
  final VoidCallback onTap;
  const _PlayPauseBtn({required this.isLoading, required this.isPlaying,
    required this.engineState, required this.onTap, this.small = false});

  @override
  Widget build(BuildContext context) {
    final size   = small ? 34.0 : 58.0;
    final radius = size / 2;
    final iconSz = small ? 18.0 : 26.0;
    final spnrSz = small ? 16.0 : 22.0;

    if (isLoading) return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: NavaTheme.surfaceCard,
          borderRadius: BorderRadius.circular(radius)),
      child: Center(child: SizedBox(width: spnrSz, height: spnrSz,
          child: const CircularProgressIndicator(color: NavaTheme.neonCyan, strokeWidth: 2))));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: NavaTheme.neonCyan,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: small ? null : NavaTheme.cyanGlow,
        ),
        child: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: NavaTheme.background, size: iconSz),
      ),
    );
  }
}
