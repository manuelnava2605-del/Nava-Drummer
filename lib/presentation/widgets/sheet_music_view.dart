// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Sheet Music View  (VexFlow via WebView)
// Renders real drum notation from NoteEvent list.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../domain/entities/entities.dart';
import '../../core/practice_engine.dart';
import '../../core/sync_diagnostics.dart';
import '../theme/nava_theme.dart';

class SheetMusicView extends StatefulWidget {
  final List<NoteEvent>            noteEvents;
  final Stream<double>             playheadStream;
  final Stream<HitResult>          hitResultStream;
  final Stream<ScoreState>         scoreStream;
  final double                     bpm;
  final int                        beatsPerBar;
  final String?                    scoreAssetPath;

  /// Called when the user taps a pad button in the on-screen pad row.
  final void Function(DrumPad pad)? onPadTap;

  const SheetMusicView({
    super.key,
    required this.noteEvents,
    required this.playheadStream,
    required this.hitResultStream,
    required this.scoreStream,
    required this.bpm,
    this.beatsPerBar = 4,
    this.scoreAssetPath,
    this.onPadTap,
  });

  @override
  State<SheetMusicView> createState() => _SheetMusicViewState();
}

class _SheetMusicViewState extends State<SheetMusicView> {
  WebViewController? _controller;
  bool               _webViewReady = false;
  bool               _scoreLoaded  = false;
  StreamSubscription<double>? _playheadSub;
  double _lastPlayhead = 0;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _playheadSub = widget.playheadStream.listen(_onPlayhead);
  }

  void _initWebView() async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: _onJsMessage,
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _onPageReady(),
      ));

    // Load bundled HTML via asset URI so relative paths (vexflow.js) resolve
    await controller.loadFlutterAsset('assets/score/drum_score.html');

    if (mounted) setState(() => _controller = controller);
  }

  void _onPageReady() {
    setState(() => _webViewReady = true);
    _sendScore();
  }

  void _onJsMessage(JavaScriptMessage msg) {
    try {
      final data = jsonDecode(msg.message) as Map<String, dynamic>;
      if (data['event'] == 'ready') {
        _sendScore();
      }
    } catch (_) {}
  }

  Future<void> _sendScore() async {
    if (_controller == null || !_webViewReady) return;

    // Prefer MusicXML score if available
    if (widget.scoreAssetPath != null) {
      try {
        final xml     = await rootBundle.loadString(widget.scoreAssetPath!);
        final payload = jsonEncode({'action': 'renderXML', 'xml': xml});
        _controller!.runJavaScript('NavaScoreChannel(${jsonEncode(payload)});');
        _scoreLoaded = true;
        return;
      } catch (e) {
        debugPrint('SheetMusicView: failed to load XML score: $e');
        // Fall through to MIDI-based rendering
      }
    }

    // Fallback: MIDI-derived NoteEvents
    final noteList = widget.noteEvents.map((e) => {
      'pad':          _padName(e.pad),
      'beatPosition': e.beatPosition,
      'velocity':     e.velocity,
      'duration':     e.duration,
    }).toList();

    final payload = jsonEncode({
      'action':      'render',
      'notes':       noteList,
      'bpm':         widget.bpm,
      'beatsPerBar': widget.beatsPerBar,
      'theme':       'dark',
    });

    _controller!.runJavaScript('NavaScoreChannel(${jsonEncode(payload)});');
    _scoreLoaded = true;
  }

  void _onPlayhead(double timeSeconds) {
    // Update diagnostics with the sheet playhead value
    SyncDiagnostics.instance.sheetPlayheadSec = timeSeconds;
    SyncDiagnostics.instance.update();

    if (_controller == null || !_scoreLoaded) return;
    // Throttle to 10fps to avoid flooding WebView
    if ((timeSeconds - _lastPlayhead).abs() < 0.05) return;
    _lastPlayhead = timeSeconds;

    final payload = jsonEncode({
      'action':      'updatePlayhead',
      'timeSeconds': timeSeconds,
    });
    _controller!.runJavaScript(
      'NavaScoreChannel(${jsonEncode(payload)});'
    );
  }

  String _padName(DrumPad pad) {
    switch (pad) {
      case DrumPad.kick:        return 'kick';
      case DrumPad.snare:       return 'snare';
      case DrumPad.hihatClosed: return 'hihatClosed';
      case DrumPad.hihatOpen:   return 'hihatOpen';
      case DrumPad.hihatPedal:  return 'hihatPedal';
      case DrumPad.crash1:      return 'crash1';
      case DrumPad.crash2:      return 'crash2';
      case DrumPad.ride:        return 'ride';
      case DrumPad.rideBell:    return 'rideBell';
      case DrumPad.tom1:        return 'tom1';
      case DrumPad.tom2:        return 'tom2';
      case DrumPad.tom3:        return 'tom3';
      case DrumPad.floorTom:    return 'floorTom';
      case DrumPad.rimshot:     return 'rimshot';
      case DrumPad.crossstick:  return 'crossstick';
    }
  }

  @override
  void dispose() {
    _playheadSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NavaTheme.background,
      child: Column(children: [
        // Score type label
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            const Text('PARTITURA', style: TextStyle(
              fontFamily: 'DrummerBody', fontSize: 10, letterSpacing: 2,
              color: NavaTheme.textMuted)),
            const Spacer(),
            _LegendDot(color: NavaTheme.neonCyan,    label: 'Platillos'),
            const SizedBox(width: 12),
            _LegendDot(color: NavaTheme.neonGold,    label: 'Toms'),
            const SizedBox(width: 12),
            _LegendDot(color: NavaTheme.textPrimary, label: 'Caja/Bombo'),
          ]),
        ),

        // Score content
        Expanded(
          child: widget.scoreAssetPath == null
              // ── No MusicXML available ─────────────────────────────────
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.music_off_rounded,
                        size: 48, color: NavaTheme.textMuted.withOpacity(0.4)),
                    const SizedBox(height: 16),
                    const Text('Partitura no disponible',
                      style: TextStyle(fontFamily: 'DrummerDisplay',
                          fontSize: 15, color: NavaTheme.textSecondary)),
                    const SizedBox(height: 8),
                    const Text(
                      'Esta canción no tiene partitura en MusicXML.\n'
                      'Usa el modo JUEGO para practicar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'DrummerBody',
                          fontSize: 11, color: NavaTheme.textMuted, height: 1.6)),
                  ]),
                ))
              // ── WebView VexFlow score ─────────────────────────────────
              : _controller == null
                  ? const Center(child: CircularProgressIndicator(
                      color: NavaTheme.neonCyan))
                  : Stack(children: [
                      WebViewWidget(controller: _controller!),
                      if (!_webViewReady)
                        Container(
                          color: NavaTheme.background,
                          child: const Center(child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: NavaTheme.neonCyan),
                              SizedBox(height: 12),
                              Text('Renderizando partitura…',
                                style: TextStyle(fontFamily: 'DrummerBody',
                                    color: NavaTheme.textSecondary, fontSize: 12)),
                            ],
                          )),
                        ),
                    ]),
        ),

        // On-screen pad row (compact, for playing without a drum kit)
        if (widget.onPadTap != null) _buildPadRow(),
      ]),
    );
  }

  // ── Pad definitions for the on-screen row ──────────────────────────────────
  static const _padDefs = [
    (pad: DrumPad.kick,        label: 'BD',  color: Color(0xFFE53935)),
    (pad: DrumPad.snare,       label: 'SD',  color: Color(0xFFFFD600)),
    (pad: DrumPad.hihatClosed, label: 'HH',  color: Color(0xFF00E5FF)),
    (pad: DrumPad.crash1,      label: 'CR',  color: Color(0xFFE040FB)),
    (pad: DrumPad.ride,        label: 'RD',  color: Color(0xFFFFAB40)),
    (pad: DrumPad.tom1,        label: 'T1',  color: Color(0xFF7C4DFF)),
    (pad: DrumPad.floorTom,    label: 'FT',  color: Color(0xFF7C4DFF)),
  ];

  Widget _buildPadRow() {
    return Container(
      color: const Color(0xFF0E1218),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: _padDefs.map((def) {
          return Expanded(
            child: GestureDetector(
              onTapDown: (_) => widget.onPadTap!(def.pad),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 48,
                decoration: BoxDecoration(
                  color: def.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: def.color.withOpacity(0.55), width: 1.5),
                ),
                child: Center(
                  child: Text(def.label, style: TextStyle(
                    fontFamily: 'DrummerBody',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: def.color,
                    letterSpacing: 0.5,
                  )),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color  color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(
        color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(fontFamily: 'DrummerBody',
        fontSize: 9, color: color)),
  ]);
}

class _LegendItem extends StatelessWidget {
  final String symbol, label;
  final Color  color;
  const _LegendItem({required this.symbol, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 14),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(symbol, style: TextStyle(color: color, fontSize: 14,
          fontWeight: FontWeight.bold)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontFamily: 'DrummerBody',
          fontSize: 9, color: NavaTheme.textMuted)),
    ]),
  );
}
