// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Practice Screen  (v4 — Premium HUD + Smooth render)
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../domain/entities/entities.dart';
import '../widgets/mode_selector.dart';
import '../../core/practice_engine.dart';
import '../../core/audio_service.dart';
import '../../core/backing_track_service.dart';
import '../widgets/falling_notes_view.dart';
import '../widgets/sheet_music_view.dart';
import '../widgets/practice_hud.dart';
import '../theme/nava_theme.dart';
import 'session_summary_screen.dart';
import '../../core/coach/coach.dart';
import '../../core/sync_diagnostics.dart';
import '../../data/datasources/local/midi_file_parser.dart';
import '../../data/datasources/local/song_package_loader.dart';

class PracticeScreen extends StatefulWidget {
  final Song           song;
  final PracticeEngine engine;
  final PracticeMode   initialMode;
  /// When set, practice starts at this section's position in loop mode.
  final SongSection?   section;

  const PracticeScreen({super.key, required this.song, required this.engine,
      this.initialMode = PracticeMode.game, this.section});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen>
    with TickerProviderStateMixin {

  late AnimationController _countInCtrl;
  late AnimationController _perfectBurstCtrl;

  List<NoteEvent> _noteEvents      = [];
  bool            _isLoading       = true;
  String?         _loadError;
  // Updated after package load — overrides widget.song values for display.
  Song?           _loadedSong;
  int             _countInNumber   = 0;
  EngineState     _engineState     = EngineState.idle;
  ScoreState      _scoreState      = ScoreState.initial();
  double          _tempoMultiplier = 1.0;
  bool            _showSettings    = false;
  bool            _loopEnabled     = false;
  double          _backingVolume   = 0.85;
  double          _drumVolume      = 1.0;
  PracticeMode    _practiceMode    = PracticeMode.game;
  Color?          _burstColor;
  double          _playheadSeconds = 0;
  int             _scorePanelTapCount = 0;
  DateTime?       _lastScoreTapTime;

  @override
  void initState() {
    super.initState();
    _countInCtrl      = AnimationController(vsync: this, duration: 600.ms);
    _perfectBurstCtrl = AnimationController(vsync: this, duration: 300.ms);
    _practiceMode     = widget.initialMode;
    _loadSong();
    _listenToEngine();
  }

  Future<void> _loadSong() async {
    setState(() { _isLoading = true; _loadError = null; });
    try {
      if (widget.song.isPackageBased) {
        // ── Package-based song (Clone Hero / RBN bundle) ─────────────────
        final package = await SongPackageLoader.load(widget.song.packageAssetDir!);
        await widget.engine.loadSongPackage(package);
        if (mounted) setState(() {
          _noteEvents = package.chart;
          _loadedSong = package.song;   // real BPM from MIDI tempo map
        });
      } else {
        // ── Legacy song (standalone MIDI asset + M4A backing track) ──────
        final bytes   = await rootBundle.load(widget.song.midiAssetPath);
        final parser  = MidiFileParser();
        final mapping = DrumMapping(deviceId: 'default',
            noteMap: StandardDrumMaps.generalMidi);
        final result  = parser.parse(bytes.buffer.asUint8List(), mapping);
        await widget.engine.loadSong(widget.song, result.noteEvents, mapping);
        if (mounted) setState(() { _noteEvents = result.noteEvents; });
      }

      // If a specific section was requested, seek to it and enable looping.
      final sec = widget.section;
      if (sec != null) {
        widget.engine.setLoop(
          start:   sec.startSeconds,
          end:     sec.endSeconds,
          enabled: true,
        );
        widget.engine.seekChartTo(sec.startSeconds);
        if (mounted) setState(() => _loopEnabled = true);
      }

      if (mounted) setState(() { _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _loadError = e.toString(); });
    }
  }

  void _listenToEngine() {
    widget.engine.stateChanges.listen((s) {
      if (mounted) setState(() => _engineState = s);
      if (s == EngineState.finished) _showResults();
    });

    widget.engine.scoreUpdates.listen((s) {
      if (mounted) setState(() {
        if (s.perfectCount > _scoreState.perfectCount) _triggerPerfectBurst();
        _scoreState = s;
      });
    });

    widget.engine.playheadTime.listen((t) {
      if (mounted) setState(() => _playheadSeconds = t);
      // Update game playhead in diagnostics
      SyncDiagnostics.instance.gamePlayheadSec = t;
      SyncDiagnostics.instance.update();
    });

    widget.engine.countInBeat.listen((beat) {
      if (mounted) {
        setState(() => _countInNumber = beat);
        _countInCtrl.forward(from: 0);
        AudioService.instance.playCountIn();
      }
    });

    widget.engine.hitResults.listen((r) {
      // Only play drum sounds when there is no backing track
      // (backing track already contains the drum audio)
      if (!BackingTrackService.instance.isReady &&
          !BackingTrackService.instance.isPlaying) {
        AudioService.instance.playDrumPad(r.expected.pad,
            velocityNorm: (r.actual?.normalizedVelocity ?? 1.0));
      }
      AudioService.instance.playGradeSound(r.grade);
    });
  }

  void _triggerPerfectBurst() {
    _burstColor = NavaTheme.hitPerfect;
    _perfectBurstCtrl.forward(from: 0).then((_) {
      if (mounted) setState(() => _burstColor = null);
    });
  }

  void _showResults() {
    final session = widget.engine.finish();
    if (!mounted) return;
    final report = CoachEngine.instance.processSession(session);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SessionSummaryScreen(
        session: session, report: report,
        onRetry: () { Navigator.pop(context); _restart(); },
        onExit:  () { Navigator.pop(context); Navigator.pop(context); },
      ),
    ));
  }

  void _restart() {
    widget.engine.stop();
    _loadSong().then((_) { if (mounted) widget.engine.startWithCountIn(); });
  }

  /// Triple-tap on the HUD toggles the sync diagnostics overlay.
  void _handleHudTap() {
    final now = DateTime.now();
    final last = _lastScoreTapTime;
    if (last != null && now.difference(last).inMilliseconds < 600) {
      _scorePanelTapCount++;
    } else {
      _scorePanelTapCount = 1;
    }
    _lastScoreTapTime = now;
    if (_scorePanelTapCount >= 3) {
      _scorePanelTapCount = 0;
      setState(() {
        SyncDiagnostics.instance.enabled = !SyncDiagnostics.instance.enabled;
      });
    }
  }

  void _handlePlayPause() {
    final playing = _engineState == EngineState.playing ||
                    _engineState == EngineState.countIn;
    if (playing)                                onPause();
    else if (_engineState == EngineState.paused) onResume();
    else                                         widget.engine.startWithCountIn();
  }

  void onPause()  => widget.engine.pause();
  void onResume() => widget.engine.resume();

  @override
  void dispose() {
    _countInCtrl.dispose();
    _perfectBurstCtrl.dispose();
    widget.engine.stop();
    super.dispose();
  }

  /// The canonical song after loading — updated from package when available.
  Song get _song => _loadedSong ?? widget.song;

  @override
  Widget build(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    return Scaffold(
      backgroundColor: NavaTheme.background,
      body: Stack(children: [

        // ── Main visualisation (full screen) ──────────────────────────────
        if (!_isLoading && _loadError == null)
          _practiceMode == PracticeMode.game
            ? FallingNotesView(
                noteEvents:       _noteEvents,
                playheadStream:   widget.engine.playheadTime,
                hitResultStream:  widget.engine.hitResults,
                scoreStream:      widget.engine.scoreUpdates,
                beatStream:       widget.engine.metronomeBeat,
                lookAheadSeconds: 2.0,
                hitLinePosition:  0.38,
                tempoFactor:      _tempoMultiplier,
                onPadTap:         (pad) => widget.engine.onScreenHit(pad),
              )
            : SheetMusicView(
                noteEvents:      _noteEvents,
                playheadStream:  widget.engine.playheadTime,
                hitResultStream: widget.engine.hitResults,
                scoreStream:     widget.engine.scoreUpdates,
                bpm:             _song.bpm.toDouble(),
                beatsPerBar:     _song.beatsPerBar,
                scoreAssetPath:  _song.scoreAssetPath,
                onPadTap:        (pad) => widget.engine.onScreenHit(pad),
              ),

        // ── Perfect burst flash ────────────────────────────────────────────
        if (_burstColor != null)
          AnimatedBuilder(
            animation: _perfectBurstCtrl,
            builder: (_, __) => Container(
              color: _burstColor!.withOpacity(
                  (1 - _perfectBurstCtrl.value) * 0.10),
            ),
          ),

        // ── Premium HUD ────────────────────────────────────────────────────
        // Triple-tap on HUD toggles sync diagnostics overlay.
        if (!_isLoading && _loadError == null)
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _handleHudTap,
            child: PracticeHud(
            song:             _song,
            scoreState:       _scoreState,
            engineState:      _engineState,
            playheadSeconds:  _playheadSeconds,
            tempoMultiplier:  _tempoMultiplier,
            isLoading:        _isLoading,
            loopEnabled:      _loopEnabled,
            showSettings:     _showSettings,
            isGameMode:       _practiceMode == PracticeMode.game,
            onBack:           _showExitDialog,
            onPlayPause:      _handlePlayPause,
            onRestart:        _restart,
            onToggleLoop:     () {
              setState(() => _loopEnabled = !_loopEnabled);
              widget.engine.setLoop(enabled: _loopEnabled);
            },
            onToggleSettings: () => setState(() => _showSettings = !_showSettings),
            onToggleMode:     () => setState(() {
              _practiceMode = _practiceMode == PracticeMode.game
                  ? PracticeMode.sheet : PracticeMode.game;
            }),
          ),
          ),  // GestureDetector

        // ── Count-in overlay ───────────────────────────────────────────────
        if (_engineState == EngineState.countIn) _buildCountIn(),

        // ── Settings overlay ───────────────────────────────────────────────
        if (_showSettings) _buildSettings(context),

        // ── Loading / error ────────────────────────────────────────────────
        if (_isLoading)         _buildLoading(),
        if (_loadError != null) _buildError(),

        // ── Sync diagnostics overlay (toggle: triple-tap the score area) ──
        const TimingDebugOverlay(),
      ]),
    );
  }

  Widget _buildCountIn() => Container(
    color: Colors.black.withOpacity(0.55),
    child: Center(
      child: AnimatedBuilder(
        animation: _countInCtrl,
        builder: (_, __) => Transform.scale(
          scale: 1 + (1 - _countInCtrl.value) * 0.6,
          child: Text('$_countInNumber',
            style: TextStyle(
              fontFamily: 'DrummerDisplay', fontSize: 120,
              fontWeight: FontWeight.bold, color: NavaTheme.neonCyan,
              shadows: [Shadow(color: NavaTheme.neonCyan.withOpacity(0.6), blurRadius: 30)],
            )),
        ),
      ),
    ),
  );

  Widget _buildSettings(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top + 58;
    return Positioned(
      top: safeTop, right: 108,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 230,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NavaTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NavaTheme.neonCyan.withOpacity(0.3)),
            boxShadow: NavaTheme.cyanGlow,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('AJUSTES', style: TextStyle(fontFamily: 'DrummerDisplay',
                  fontSize: 11, color: NavaTheme.textSecondary, letterSpacing: 2)),
              GestureDetector(
                onTap: () => setState(() => _showSettings = false),
                child: const Icon(Icons.close, color: NavaTheme.textMuted, size: 16)),
            ]),
            const SizedBox(height: 12),
            _SliderRow(label: 'TEMPO', value: _tempoMultiplier,
              min: 0.5, max: 1.2, divisions: 14,
              valueStr: '${(_tempoMultiplier * 100).round()}%',
              color: NavaTheme.neonGold,
              onChanged: (v) {
                setState(() => _tempoMultiplier = v);
                widget.engine.setTempoFactor(v);
              }),
            const SizedBox(height: 8),
            _SliderRow(label: 'BATERÍA', value: _drumVolume,
              min: 0, max: 1, divisions: 10,
              valueStr: '${(_drumVolume * 100).round()}%',
              color: NavaTheme.neonCyan,
              onChanged: (v) {
                setState(() => _drumVolume = v);
                AudioService.instance.drumVolume = v;
              }),
            const SizedBox(height: 8),
            _SliderRow(label: 'PISTA', value: _backingVolume,
              min: 0, max: 1, divisions: 10,
              valueStr: '${(_backingVolume * 100).round()}%',
              color: NavaTheme.neonPurple,
              onChanged: (v) {
                setState(() => _backingVolume = v);
                BackingTrackService.instance.setVolume(v);
              }),
          ]),
        ),
      ).animate().slideX(begin: 0.3, duration: 180.ms),
    );
  }

  Widget _buildLoading() => Container(
    color: NavaTheme.background,
    child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(color: NavaTheme.neonCyan),
      SizedBox(height: 16),
      Text('Cargando canción…', style: TextStyle(
          fontFamily: 'DrummerBody', color: NavaTheme.textSecondary)),
    ])),
  );

  Widget _buildError() => Container(
    color: NavaTheme.background,
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, color: NavaTheme.hitMiss, size: 48),
      const SizedBox(height: 12),
      const Text('Error al cargar', style: TextStyle(
          fontFamily: 'DrummerDisplay', color: NavaTheme.hitMiss, fontSize: 18)),
      const SizedBox(height: 8),
      TextButton(onPressed: _loadSong,
        child: const Text('Reintentar', style: TextStyle(color: NavaTheme.neonCyan))),
    ])),
  );

  void _showExitDialog() {
    widget.engine.pause();
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: NavaTheme.surfaceElevated,
      title: const Text('¿Salir?', style: TextStyle(
          color: NavaTheme.textPrimary, fontFamily: 'DrummerDisplay')),
      content: const Text('El progreso no se guardará.',
          style: TextStyle(color: NavaTheme.textSecondary, fontFamily: 'DrummerBody')),
      actions: [
        TextButton(onPressed: () { Navigator.pop(context); widget.engine.resume(); },
          child: const Text('Cancelar', style: TextStyle(color: NavaTheme.neonCyan))),
        ElevatedButton(
          onPressed: () { Navigator.pop(context); Navigator.pop(context); },
          style: ElevatedButton.styleFrom(backgroundColor: NavaTheme.hitMiss),
          child: const Text('Salir', style: TextStyle(fontFamily: 'DrummerBody'))),
      ],
    ));
  }
}

// ── Slider row (settings panel) ───────────────────────────────────────────────
class _SliderRow extends StatelessWidget {
  final String label, valueStr;
  final double value, min, max;
  final int    divisions;
  final Color  color;
  final ValueChanged<double> onChanged;
  const _SliderRow({required this.label, required this.value, required this.min,
    required this.max, required this.divisions, required this.valueStr,
    required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontFamily: 'DrummerBody',
            fontSize: 9, color: NavaTheme.textMuted, letterSpacing: 1)),
        Text(valueStr, style: TextStyle(fontFamily: 'DrummerDisplay',
            fontSize: 10, color: color)),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor:   color,
          thumbColor:         color,
          inactiveTrackColor: NavaTheme.textMuted.withOpacity(0.2),
          overlayColor:       color.withOpacity(0.1),
          trackHeight:        2,
          thumbShape:         const RoundSliderThumbShape(enabledThumbRadius: 7),
        ),
        child: Slider(value: value, min: min, max: max, divisions: divisions,
            onChanged: onChanged),
      ),
    ],
  );
}
