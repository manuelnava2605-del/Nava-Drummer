// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Sheet Music View  (MIDI-native, Flutter CustomPainter)
//
// Renders drum notation DIRECTLY from List<NoteEvent>.
// No MusicXML. No WebView. No external assets.
//
// Pipeline:
//   NoteEvent list
//     → DrumNotationMapper  (one-time: NoteEvent → NotationNote)
//     → SheetLayoutEngine   (per-frame: NotationNote → LaidOutNote positions)
//     → SheetMusicPainter   (per-frame: draw staff, notes, cursor, highlights)
//
// The [scoreAssetPath] parameter is accepted for API compatibility but ignored.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/material.dart';
import '../../domain/entities/entities.dart';
import '../../core/practice_engine.dart';
import '../../core/sync_diagnostics.dart';
import '../theme/nava_theme.dart';
import 'notation/notation_models.dart';
import 'notation/drum_notation_mapper.dart';
import 'notation/sheet_layout_engine.dart';
import 'notation/sheet_music_painter.dart';

// ─────────────────────────────────────────────────────────────────────────────
class SheetMusicView extends StatefulWidget {
  final List<NoteEvent>            noteEvents;
  final Stream<double>             playheadStream;
  final Stream<HitResult>          hitResultStream;
  final Stream<ScoreState>         scoreStream;
  final double                     bpm;
  final int                        beatsPerBar;
  /// Accepted for API compatibility — ignored. MIDI is the sole data source.
  final String?                    scoreAssetPath;
  final void Function(DrumPad pad)? onPadTap;

  const SheetMusicView({
    super.key,
    required this.noteEvents,
    required this.playheadStream,
    required this.hitResultStream,
    required this.scoreStream,
    required this.bpm,
    this.beatsPerBar  = 4,
    this.scoreAssetPath,   // ignored
    this.onPadTap,
  });

  @override
  State<SheetMusicView> createState() => _SheetMusicViewState();
}

// ─────────────────────────────────────────────────────────────────────────────
class _SheetMusicViewState extends State<SheetMusicView> {

  // ── Notation data (built once at load) ────────────────────────────────────
  late final List<NotationNote> _notes;
  late final SheetLayoutEngine  _layout;

  // ── Live state (updated by streams) ───────────────────────────────────────
  double          _currentTime = 0;
  final Set<DrumPad> _recentlyHit = {};

  // ── Repaint notifier (avoids full widget rebuild on every frame) ──────────
  final _RepaintNotifier _repaint = _RepaintNotifier();

  // ── Stream subscriptions ──────────────────────────────────────────────────
  StreamSubscription<double>?    _playheadSub;
  StreamSubscription<HitResult>? _hitSub;

  @override
  void initState() {
    super.initState();
    _notes  = DrumNotationMapper.fromChart(widget.noteEvents);
    _layout = const SheetLayoutEngine();

    _playheadSub = widget.playheadStream.listen((t) {
      _currentTime = t;
      // Publish the sheet playhead so SyncDiagnostics can compare it
      // against the game/audio playheads in the timing debug overlay.
      SyncDiagnostics.instance.sheetPlayheadSec = t;
      _repaint.notify();
    });

    _hitSub = widget.hitResultStream.listen((hit) {
      // Only highlight on non-miss hits
      if (hit.grade != HitGrade.miss) {
        _recentlyHit.add(hit.expected.pad);
        _repaint.notify();
        Future.delayed(const Duration(milliseconds: 180), () {
          if (mounted) {
            _recentlyHit.remove(hit.expected.pad);
            _repaint.notify();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _playheadSub?.cancel();
    _hitSub?.cancel();
    _repaint.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NavaTheme.background,
      child: Column(children: [
        _buildLegend(),
        Expanded(child: _buildCanvas()),
        if (widget.onPadTap != null) _buildPadRow(),
      ]),
    );
  }

  // ─── Legend bar ───────────────────────────────────────────────────────────

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      color: const Color(0xFF090D14),
      child: Row(children: [
        const Text('PARTITURA', style: TextStyle(
          fontFamily: 'DrummerBody', fontSize: 9, letterSpacing: 2,
          color: NavaTheme.textMuted,
        )),
        const Spacer(),
        _LegendItem(color: NavaTheme.neonCyan,    label: '× Platillos'),
        const SizedBox(width: 10),
        _LegendItem(color: NavaTheme.neonGold,    label: '● Toms'),
        const SizedBox(width: 10),
        _LegendItem(color: NavaTheme.textPrimary, label: '● Caja/BD'),
      ]),
    );
  }

  // ─── Staff canvas ─────────────────────────────────────────────────────────

  Widget _buildCanvas() {
    return LayoutBuilder(builder: (ctx, constraints) {
      final h  = constraints.maxHeight;
      final w  = constraints.maxWidth;

      // Staff geometry
      const ls           = 11.0;  // line spacing in pixels
      const staffH       = ls * 4; // 44 px
      const reserveAbove = 85.0;   // room for crash/hi-hat ledger lines
      const reserveBelow = 55.0;   // room for kick ledger line

      // Center the staff block vertically
      final staffTop = (h - staffH - reserveAbove - reserveBelow) / 2
                       + reserveAbove;

      return RepaintBoundary(
        child: CustomPaint(
          size: Size(w, h),
          painter: _LivePainter(
            repaint:      _repaint,
            notes:        _notes,
            layout:       _layout,
            timeGetter:   () => _currentTime,
            hitGetter:    () => Set.unmodifiable(_recentlyHit),
            bpm:          widget.bpm,
            beatsPerBar:  widget.beatsPerBar,
            staffTop:     staffTop,
            lineSpacing:  ls,
          ),
        ),
      );
    });
  }

  // ─── On-screen pad row ────────────────────────────────────────────────────

  static const _padDefs = [
    (pad: DrumPad.kick,        label: 'BD', color: Color(0xFFE53935)),
    (pad: DrumPad.snare,       label: 'SD', color: Color(0xFFFFD600)),
    (pad: DrumPad.hihatClosed, label: 'HH', color: Color(0xFF00E5FF)),
    (pad: DrumPad.crash1,      label: 'CR', color: Color(0xFFE040FB)),
    (pad: DrumPad.ride,        label: 'RD', color: Color(0xFFFFAB40)),
    (pad: DrumPad.tom1,        label: 'T1', color: Color(0xFF7C4DFF)),
    (pad: DrumPad.floorTom,    label: 'FT', color: Color(0xFF7C4DFF)),
  ];

  Widget _buildPadRow() {
    return Container(
      color: const Color(0xFF0B0F18),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: _padDefs.map((def) => Expanded(
          child: GestureDetector(
            onTapDown: (_) => widget.onPadTap!(def.pad),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 46,
              decoration: BoxDecoration(
                color: def.color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: def.color.withOpacity(0.50), width: 1.4),
              ),
              child: Center(child: Text(
                def.label,
                style: TextStyle(
                  fontFamily: 'DrummerBody', fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: def.color, letterSpacing: 0.5,
                ),
              )),
            ),
          ),
        )).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RepaintNotifier — lightweight ChangeNotifier that triggers CustomPainter
// ─────────────────────────────────────────────────────────────────────────────
class _RepaintNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

// ─────────────────────────────────────────────────────────────────────────────
// _LivePainter — bridges the repaint notifier to SheetMusicPainter
// ─────────────────────────────────────────────────────────────────────────────
class _LivePainter extends CustomPainter {
  final _RepaintNotifier    repaint;
  final List<NotationNote>  notes;
  final SheetLayoutEngine   layout;
  final double Function()   timeGetter;
  final Set<DrumPad> Function() hitGetter;
  final double bpm;
  final int    beatsPerBar;
  final double staffTop;
  final double lineSpacing;

  _LivePainter({
    required this.repaint,
    required this.notes,
    required this.layout,
    required this.timeGetter,
    required this.hitGetter,
    required this.bpm,
    required this.beatsPerBar,
    required this.staffTop,
    required this.lineSpacing,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final model = layout.layout(
      notes:        notes,
      currentTime:  timeGetter(),
      playheadX:    size.width * 0.28,
      staffTop:     staffTop,
      lineSpacing:  lineSpacing,
      bpm:          bpm,
      beatsPerBar:  beatsPerBar,
      screenWidth:  size.width,
      recentlyHit:  hitGetter(),
    );
    SheetMusicPainter(model: model).paint(canvas, size);
  }

  @override
  bool shouldRepaint(_LivePainter old) =>
      old.staffTop    != staffTop    ||
      old.lineSpacing != lineSpacing ||
      old.bpm         != bpm;
}

// ─────────────────────────────────────────────────────────────────────────────
// _LegendItem
// ─────────────────────────────────────────────────────────────────────────────
class _LegendItem extends StatelessWidget {
  final Color  color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 7, height: 7, decoration: BoxDecoration(
      color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(
      fontFamily: 'DrummerBody', fontSize: 8, color: color)),
  ]);
}
