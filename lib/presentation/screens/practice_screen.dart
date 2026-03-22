// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Practice Screen (FIXED PRO VERSION)
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
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
      if (!BackingTrackService.instance.isReady &&
          !BackingTrackService.instance.isPlaying) {

        AudioService.instance.playDrumPad(
          r.expected.pad,
          velocityNorm: (r.actual?.normalizedVelocity ?? 1.0),
        );
      }

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

  Widget _buildSettings(BuildContext context) => const SizedBox();
  Widget _buildLoading() => const Center(child: CircularProgressIndicator());
  Widget _buildError() => const Center(child: Text("Error"));
  void _showExitDialog() {}
}