// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Practice Screen (FIXED PRO VERSION)
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/entities.dart';
import '../bloc/blocs.dart';
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
  final Song song;
  final PracticeEngine engine;
  final PracticeMode initialMode;
  final SongSection? section;

  const PracticeScreen({
    super.key,
    required this.song,
    required this.engine,
    this.initialMode = PracticeMode.game,
    this.section,
  });

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen>
    with TickerProviderStateMixin {

  late AnimationController _countInCtrl;
  late AnimationController _perfectBurstCtrl;

  final List<StreamSubscription> _subs = [];
  bool _showingResults = false;

  List<NoteEvent> _noteEvents = [];
  bool _isLoading = true;
  String? _loadError;
  Song? _loadedSong;

  int _countInNumber = 0;
  EngineState _engineState = EngineState.idle;
  ScoreState _scoreState = ScoreState.initial();

  double _tempoMultiplier = 1.0;
  bool _showSettings = false;
  bool _loopEnabled = false;

  double _backingVolume = 0.85;
  double _drumVolume = 1.0;

  PracticeMode _practiceMode = PracticeMode.game;
  Color? _burstColor;
  double _playheadSeconds = 0;

  int _scorePanelTapCount = 0;
  DateTime? _lastScoreTapTime;

  @override
  void initState() {
    super.initState();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _countInCtrl = AnimationController(vsync: this, duration: 600.ms);
    _perfectBurstCtrl = AnimationController(vsync: this, duration: 300.ms);
    _practiceMode = widget.initialMode;

    _loadSong();
    _listenToEngine();
  }

  Future<void> _loadSong() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      if (widget.song.isPackageBased) {
        final package = await SongPackageLoader.load(widget.song.packageAssetDir!);
        await widget.engine.loadSongPackage(package);

        if (mounted) {
          setState(() {
            _noteEvents = package.chart;
            _loadedSong = package.song;
          });
        }
      } else {
        final bytes = await rootBundle.load(widget.song.midiAssetPath);
        final parser = MidiFileParser();

        final mapping = DrumMapping(
          deviceId: 'default',
          noteMap: StandardDrumMaps.generalMidi,
        );

        final result = parser.parse(bytes.buffer.asUint8List(), mapping);

        await widget.engine.loadSong(widget.song, result.noteEvents, mapping);

        if (mounted) {
          setState(() => _noteEvents = result.noteEvents);
        }
      }

      final sec = widget.section;
      if (sec != null) {
        widget.engine.setLoop(
          start: sec.startSeconds,
          end: sec.endSeconds,
          enabled: true,
        );

        widget.engine.seekChartTo(sec.startSeconds);

        if (mounted) setState(() => _loopEnabled = true);
      }

      if (mounted) setState(() => _isLoading = false);

    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = e.toString();
        });
      }
    }
  }

  void _listenToEngine() {

    _subs.add(widget.engine.stateChanges.listen((s) {
      if (!mounted) return;

      if (_engineState != s) {
        setState(() => _engineState = s);
      }

      if (s == EngineState.finished && !_showingResults) {
        _showingResults = true;
        _showResults();
      }
    }));

    _subs.add(widget.engine.scoreUpdates.listen((s) {
      if (!mounted) return;

      if (s.perfectCount > _scoreState.perfectCount) {
        _triggerPerfectBurst();
      }

      setState(() => _scoreState = s);
    }));

    _subs.add(widget.engine.playheadTime.listen((t) {
      _playheadSeconds = t;
      SyncDiagnostics.instance.gamePlayheadSec = t;
      SyncDiagnostics.instance.update();
    }));

    _subs.add(widget.engine.countInBeat.listen((beat) {
      if (!mounted) return;

      setState(() => _countInNumber = beat);
      _countInCtrl.forward(from: 0);
      AudioService.instance.playCountIn();
    }));

    _subs.add(widget.engine.hitResults.listen((r) {
      // Drum-pad audio is handled upstream:
      //   • Physical kit hits  → DrumEngine.hit() in PracticeEngine._onMidi()
      //   • On-screen pad taps → DrumEngine.hit() in PracticeEngine.onScreenHit()
      // Playing r.expected.pad here was wrong (it echoes the CHART note, not
      // the pad the user actually hit) and caused double-sound on every hit.
      // Only grade feedback (click/chime) belongs here.
      AudioService.instance.playGradeSound(r.grade);
    }));
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

    // ── Persist session & update Firestore progress ───────────────────────
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      context.read<ProgressBloc>().add(ProgressSessionCompleted(session, uid));
    }

    final report = CoachEngine.instance.processSession(session);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SessionSummaryScreen(
          session: session,
          report: report,
          onRetry: () {
            Navigator.pop(context);
            _showingResults = false;
            _restart();
          },
          onExit: () {
            Navigator.pop(context);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _restart() {
    _showingResults = false;
    widget.engine.stop();
    SyncDiagnostics.instance.reset();

    _loadSong().then((_) {
      if (mounted) widget.engine.startWithCountIn();
    });
  }

  void _handleHudTap() {
    // The sync debug panel is a developer tool only.
    // In release/profile builds this gesture does nothing so it never
    // interrupts gameplay for end users.
    if (!kDebugMode) return;

    final now = DateTime.now();
    final last = _lastScoreTapTime;

    if (last != null && now.difference(last).inMilliseconds < 600) {
      _scorePanelTapCount++;
    } else {
      _scorePanelTapCount = 1;
    }

    _lastScoreTapTime = now;

    if (_scorePanelTapCount >= 5) {
      _scorePanelTapCount = 0;

      setState(() {
        SyncDiagnostics.instance.enabled =
            !SyncDiagnostics.instance.enabled;
      });

      SyncDiagnostics.instance.update();
    }
  }

  void _handlePlayPause() {
    final playing =
        _engineState == EngineState.playing ||
        _engineState == EngineState.countIn;

    if (playing) {
      widget.engine.pause();
    } else if (_engineState == EngineState.paused) {
      widget.engine.resume();
    } else {
      widget.engine.startWithCountIn();
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }

    _countInCtrl.dispose();
    _perfectBurstCtrl.dispose();

    widget.engine.stop();

    super.dispose();
  }

  Song get _song => _loadedSong ?? widget.song;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavaTheme.background,
      body: Stack(children: [

        if (!_isLoading && _loadError == null)
          _practiceMode == PracticeMode.game
              ? FallingNotesView(
                  noteEvents: _noteEvents,
                  playheadStream: widget.engine.playheadTime,
                  hitResultStream: widget.engine.hitResults,
                  scoreStream: widget.engine.scoreUpdates,
                  beatStream: widget.engine.metronomeBeat,
                  lookAheadSeconds: 2.0,
                  hitLinePosition: 0.38,
                  tempoFactor: _tempoMultiplier,
                  onPadTap: (pad) => widget.engine.onScreenHit(pad),
                )
              : SheetMusicView(
                  noteEvents: _noteEvents,
                  playheadStream: widget.engine.playheadTime,
                  hitResultStream: widget.engine.hitResults,
                  scoreStream: widget.engine.scoreUpdates,
                  bpm: _song.bpm.toDouble(),
                  beatsPerBar: _song.beatsPerBar,
                  scoreAssetPath: _song.scoreAssetPath,
                  onPadTap: (pad) => widget.engine.onScreenHit(pad),
                ),

        if (_burstColor != null)
          AnimatedBuilder(
            animation: _perfectBurstCtrl,
            builder: (_, __) => Container(
              color: _burstColor!
                  .withOpacity((1 - _perfectBurstCtrl.value) * 0.10),
            ),
          ),

        if (!_isLoading && _loadError == null)
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _handleHudTap,
            child: PracticeHud(
              song: _song,
              scoreState: _scoreState,
              engineState: _engineState,
              playheadSeconds: _playheadSeconds,
              tempoMultiplier: _tempoMultiplier,
              isLoading: _isLoading,
              loopEnabled: _loopEnabled,
              showSettings: _showSettings,
              isGameMode: _practiceMode == PracticeMode.game,
              onBack: _showExitDialog,
              onPlayPause: _handlePlayPause,
              onRestart: _restart,
              onToggleLoop: () {
                setState(() => _loopEnabled = !_loopEnabled);
                widget.engine.setLoop(enabled: _loopEnabled);
              },
              onToggleSettings: () =>
                  setState(() => _showSettings = !_showSettings),
              onToggleMode: () => setState(() {
                _practiceMode =
                    _practiceMode == PracticeMode.game
                        ? PracticeMode.sheet
                        : PracticeMode.game;
              }),
            ),
          ),

        if (_engineState == EngineState.countIn) _buildCountIn(),
        if (_showSettings) _buildSettings(context),
        if (_isLoading) _buildLoading(),
        if (_loadError != null) _buildError(),

        if (SyncDiagnostics.instance.enabled)
          const TimingDebugOverlay(),
      ]),
    );
  }

  Widget _buildCountIn() => Container(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: Text('$_countInNumber',
              style: const TextStyle(fontSize: 120)),
        ),
      );

  // ── Exit dialog ───────────────────────────────────────────────────────────

  void _showExitDialog() {
    final wasPlaying =
        _engineState == EngineState.playing ||
        _engineState == EngineState.countIn;

    if (wasPlaying) widget.engine.pause();

    showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: NavaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🥁', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              const Text('¿Salir de la sesión?',
                  style: TextStyle(
                      fontFamily: 'DrummerDisplay',
                      fontSize: 18,
                      color: NavaTheme.textPrimary,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                  'Tu progreso en esta sesión\nno se guardará.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'DrummerBody',
                      fontSize: 13,
                      color: NavaTheme.textSecondary)),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: NavaTheme.textMuted),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('CONTINUAR',
                        style: TextStyle(
                            fontFamily: 'DrummerBody',
                            fontSize: 12,
                            color: NavaTheme.textSecondary,
                            letterSpacing: 1)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NavaTheme.hitMiss,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('SALIR',
                        style: TextStyle(
                            fontFamily: 'DrummerDisplay',
                            fontSize: 13,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    ).then((confirmed) {
      if (!mounted) return;
      if (confirmed == true) {
        widget.engine.stop();
        Navigator.pop(context);
      } else if (wasPlaying) {
        widget.engine.resume();
      }
    });
  }

  // ── In-game settings panel ────────────────────────────────────────────────

  Widget _buildSettings(BuildContext context) {
    return Stack(children: [
      // dim backdrop — tap to close
      GestureDetector(
        onTap: () => setState(() => _showSettings = false),
        child: Container(color: Colors.black45),
      ),
      // panel slides in from the right
      Align(
        alignment: Alignment.centerRight,
        child: _SettingsPanel(
          tempoMultiplier: _tempoMultiplier,
          backingVolume:   _backingVolume,
          drumVolume:      _drumVolume,
          loopEnabled:     _loopEnabled,
          isGameMode:      _practiceMode == PracticeMode.game,
          onTempoChanged: (v) {
            setState(() => _tempoMultiplier = v);
            widget.engine.setTempoFactor(v);
          },
          onBackingVolumeChanged: (v) {
            setState(() => _backingVolume = v);
            BackingTrackService.instance.setVolume(v);
          },
          onDrumVolumeChanged: (v) {
            setState(() => _drumVolume = v);
            AudioService.instance.drumVolume = v;
          },
          onClose: () => setState(() => _showSettings = false),
        ),
      ),
    ]);
  }

  // ── Loading screen ─────────────────────────────────────────────────────────

  Widget _buildLoading() => Container(
        color: NavaTheme.background,
        child: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: NavaTheme.neonCyan, strokeWidth: 2),
            SizedBox(height: 16),
            Text('Cargando canción…',
                style: TextStyle(
                    fontFamily: 'DrummerBody',
                    fontSize: 13,
                    color: NavaTheme.textSecondary)),
          ]),
        ),
      );

  // ── Error screen ───────────────────────────────────────────────────────────

  Widget _buildError() => Container(
        color: NavaTheme.background,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('⚠️', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                const Text('No se pudo cargar la canción',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'DrummerDisplay',
                        fontSize: 18,
                        color: NavaTheme.textPrimary,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_loadError ?? '',
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'DrummerBody',
                        fontSize: 11,
                        color: NavaTheme.textMuted)),
                const SizedBox(height: 32),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, size: 16,
                        color: NavaTheme.textSecondary),
                    label: const Text('VOLVER',
                        style: TextStyle(
                            fontFamily: 'DrummerBody',
                            fontSize: 12,
                            color: NavaTheme.textSecondary,
                            letterSpacing: 1)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: NavaTheme.textMuted),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _loadSong,
                    icon: const Icon(Icons.refresh, size: 16,
                        color: NavaTheme.background),
                    label: const Text('REINTENTAR',
                        style: TextStyle(
                            fontFamily: 'DrummerDisplay',
                            fontSize: 12,
                            color: NavaTheme.background,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NavaTheme.neonCyan,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// Settings panel — slide-in from right during practice
// ═════════════════════════════════════════════════════════════════════════════

class _SettingsPanel extends StatelessWidget {
  final double  tempoMultiplier;
  final double  backingVolume;
  final double  drumVolume;
  final bool    loopEnabled;
  final bool    isGameMode;

  final ValueChanged<double> onTempoChanged;
  final ValueChanged<double> onBackingVolumeChanged;
  final ValueChanged<double> onDrumVolumeChanged;
  final VoidCallback         onClose;

  const _SettingsPanel({
    required this.tempoMultiplier,
    required this.backingVolume,
    required this.drumVolume,
    required this.loopEnabled,
    required this.isGameMode,
    required this.onTempoChanged,
    required this.onBackingVolumeChanged,
    required this.onDrumVolumeChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: NavaTheme.surface,
        border: Border(left: BorderSide(color: NavaTheme.neonCyan, width: 0.5)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                const Text('AJUSTES',
                    style: TextStyle(
                        fontFamily: 'DrummerDisplay',
                        fontSize: 13,
                        color: NavaTheme.neonCyan,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(Icons.close,
                      color: NavaTheme.textMuted, size: 20),
                ),
              ]),

              const SizedBox(height: 24),

              // Tempo
              _SliderRow(
                label: 'TEMPO',
                value: tempoMultiplier,
                min: 0.5,
                max: 1.2,
                displayText: '${(tempoMultiplier * 100).round()}%',
                color: NavaTheme.neonCyan,
                onChanged: onTempoChanged,
              ),

              const SizedBox(height: 20),

              // Backing track volume
              _SliderRow(
                label: 'PISTA',
                value: backingVolume,
                min: 0.0,
                max: 1.0,
                displayText: '${(backingVolume * 100).round()}%',
                color: NavaTheme.neonGold,
                onChanged: onBackingVolumeChanged,
              ),

              const SizedBox(height: 20),

              // Drum volume
              _SliderRow(
                label: 'BATERÍA',
                value: drumVolume,
                min: 0.0,
                max: 1.0,
                displayText: '${(drumVolume * 100).round()}%',
                color: NavaTheme.neonGreen,
                onChanged: onDrumVolumeChanged,
              ),

              const SizedBox(height: 28),

              // Info chips
              _InfoChip(
                icon: Icons.loop,
                label: loopEnabled ? 'Loop ACTIVADO' : 'Loop desactivado',
                active: loopEnabled,
              ),
              const SizedBox(height: 8),
              _InfoChip(
                icon: isGameMode ? Icons.music_note : Icons.notes,
                label: isGameMode ? 'Modo: Notas cayendo' : 'Modo: Partitura',
                active: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String  label;
  final double  value, min, max;
  final String  displayText;
  final Color   color;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.displayText,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Text(label,
            style: const TextStyle(
                fontFamily: 'DrummerBody',
                fontSize: 9,
                color: NavaTheme.textMuted,
                letterSpacing: 2)),
        const Spacer(),
        Text(displayText,
            style: TextStyle(
                fontFamily: 'DrummerDisplay',
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 4),
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor:   color,
          inactiveTrackColor: color.withOpacity(0.15),
          thumbColor:         color,
          overlayColor:       color.withOpacity(0.1),
          trackHeight:        3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        ),
        child: Slider(value: value, min: min, max: max, onChanged: onChanged),
      ),
    ],
  );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool     active;
  const _InfoChip({required this.icon, required this.label, required this.active});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: (active ? NavaTheme.neonCyan : NavaTheme.textMuted).withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
          color: (active ? NavaTheme.neonCyan : NavaTheme.textMuted).withOpacity(0.25)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon,
          size: 13,
          color: active ? NavaTheme.neonCyan : NavaTheme.textMuted),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(
              fontFamily: 'DrummerBody',
              fontSize: 10,
              color: active ? NavaTheme.textSecondary : NavaTheme.textMuted)),
    ]),
  );
}