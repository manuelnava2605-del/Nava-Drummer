// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Sheet Music Painter
// Pure CustomPainter — receives a SheetRenderModel and draws everything.
// No state, no streams — just draw().
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math' show min, max, pi;
import 'package:flutter/material.dart';
import '../../theme/nava_theme.dart';
import '../../../domain/entities/entities.dart';
import 'notation_models.dart';

class SheetMusicPainter extends CustomPainter {
  final SheetRenderModel model;

  const SheetMusicPainter({required this.model}) : super();

  // ─── Static paints (created once, reused every frame) ────────────────────

  static final Paint _staffPaint = Paint()
    ..color = const Color(0xFF5A7888)
    ..strokeWidth = 1.8
    ..style = PaintingStyle.stroke;

  static final Paint _barPaint = Paint()
    ..color = const Color(0xFF7090A0)
    ..strokeWidth = 2.2
    ..style = PaintingStyle.stroke;

  static final Paint _beatPaint = Paint()
    ..color = const Color(0xFF344858)
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;

  static final Paint _ledgerPaint = Paint()
    ..color = const Color(0xFF5A7888)
    ..strokeWidth = 1.8
    ..style = PaintingStyle.stroke;

  static final Paint _beamPaint = Paint()
    ..color = const Color(0xFF6A8A9A)
    ..strokeWidth = 4.0
    ..strokeCap = StrokeCap.square
    ..style = PaintingStyle.stroke;

  // ─── Instrument abbreviations for note labels ─────────────────────────────

  static const Map<DrumPad, String> _padLabel = {
    DrumPad.kick:        'BD',
    DrumPad.snare:       'SD',
    DrumPad.rimshot:     'SD',
    DrumPad.crossstick:  'CS',
    DrumPad.hihatClosed: 'HH',
    DrumPad.hihatOpen:   'HH',
    DrumPad.hihatPedal:  'HH',
    DrumPad.crash1:      'CR',
    DrumPad.crash2:      'CR',
    DrumPad.ride:        'RD',
    DrumPad.rideBell:    'RB',
    DrumPad.tom1:        'T1',
    DrumPad.tom2:        'T2',
    DrumPad.tom3:        'T3',
    DrumPad.floorTom:    'FT',
  };

  // ─── Main paint entry point ───────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final m = model;

    // Pre-compute per-frame helper maps (cheap O(n) passes)
    final beamYForNote    = _buildBeamYMap(m);
    final drawStemForNote = _buildDrawStemFlags(m);
    final stemFromY       = _buildStemFromY(m);
    // Set of note indices that are part of a beam group (suppress individual flags)
    final beamedIndices   = _buildBeamedSet(m);

    _drawBeatLines(canvas, size, m);
    _drawBarLines(canvas, size, m);
    _drawStaff(canvas, size, m);
    _drawClef(canvas, m);
    _drawTimeSignature(canvas, m);

    // Draw order: stems → beams → flags → note heads (heads on top)
    _drawStems(canvas, m, drawStemForNote, stemFromY, beamYForNote);
    _drawBeams(canvas, m, beamYForNote, stemFromY);
    _drawFlags(canvas, m, drawStemForNote, stemFromY, beamedIndices);
    _drawNoteHeads(canvas, m);

    _drawPlayhead(canvas, size, m);
    _drawBarLabel(canvas, size, m);
  }

  // ─── Pre-computation helpers ──────────────────────────────────────────────

  Map<int, double> _buildBeamYMap(SheetRenderModel m) {
    final map = <int, double>{};
    for (final group in m.beamGroups) {
      if (group.length < 2) continue;
      double beamY = double.maxFinite;
      for (final idx in group) {
        final nat = _naturalStemTip(m.notes[idx], m.lineSpacing);
        if (nat < beamY) beamY = nat;
      }
      for (final idx in group) map[idx] = beamY;
    }
    return map;
  }

  List<bool> _buildDrawStemFlags(SheetRenderModel m) {
    final flags = List.filled(m.notes.length, true);
    for (final group in m.chordGroups) {
      final upIdxs = group.where((i) => m.notes[i].note.stemUp).toList();
      if (upIdxs.length > 1) {
        final owner = upIdxs.reduce(
            (a, b) => m.notes[a].y > m.notes[b].y ? a : b);
        for (final i in upIdxs) if (i != owner) flags[i] = false;
      }
      final downIdxs = group.where((i) => !m.notes[i].note.stemUp).toList();
      if (downIdxs.length > 1) {
        final owner = downIdxs.reduce(
            (a, b) => m.notes[a].y < m.notes[b].y ? a : b);
        for (final i in downIdxs) if (i != owner) flags[i] = false;
      }
    }
    return flags;
  }

  List<double> _buildStemFromY(SheetRenderModel m) {
    final fromY = List.generate(m.notes.length, (i) => m.notes[i].y);
    for (final group in m.chordGroups) {
      final upIdxs = group.where((i) => m.notes[i].note.stemUp).toList();
      if (upIdxs.isNotEmpty) {
        final maxY = upIdxs.map((i) => m.notes[i].y).reduce(max);
        for (final i in upIdxs) fromY[i] = maxY;
      }
      final downIdxs = group.where((i) => !m.notes[i].note.stemUp).toList();
      if (downIdxs.isNotEmpty) {
        final minY = downIdxs.map((i) => m.notes[i].y).reduce(min);
        for (final i in downIdxs) fromY[i] = minY;
      }
    }
    return fromY;
  }

  /// Returns the set of note indices that belong to a beam group.
  /// Notes in beam groups don't draw individual flags.
  Set<int> _buildBeamedSet(SheetRenderModel m) {
    final set = <int>{};
    for (final group in m.beamGroups) {
      for (final idx in group) set.add(idx);
    }
    return set;
  }

  double _naturalStemTip(LaidOutNote n, double ls) {
    if (n.note.stemUp) {
      return n.y - 3.5 * ls;
    } else {
      return n.y + 3.5 * ls;
    }
  }

  // ─── 5-line staff ─────────────────────────────────────────────────────────

  void _drawStaff(Canvas canvas, Size size, SheetRenderModel m) {
    for (int i = 0; i < 5; i++) {
      final y = m.staffTop + (4 - i) * m.lineSpacing;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), _staffPaint);
    }
  }

  // ─── Percussion clef (two vertical rectangles) ───────────────────────────

  void _drawClef(Canvas canvas, SheetRenderModel m) {
    final ls      = m.lineSpacing;
    const clefX   = 8.0;
    final clefW   = ls * 0.28;
    final clefGap = ls * 0.42;
    final top     = m.staffTop;
    final bottom  = m.staffBottom;
    final paint   = Paint()
      ..color = const Color(0xFF7A9AAA)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(clefX,           top, clefW, bottom - top), paint);
    canvas.drawRect(Rect.fromLTWH(clefX + clefGap, top, clefW, bottom - top), paint);
  }

  // ─── Time signature ───────────────────────────────────────────────────────

  void _drawTimeSignature(Canvas canvas, SheetRenderModel m) {
    const timeSigX = 32.0;
    final midY     = m.staffTop + m.lineSpacing * 2;
    final fontSize = m.lineSpacing * 1.8;
    const col      = Color(0xFF6A8898);

    _paintTimeSigDigit(canvas, '${m.timeSigNumerator}',
        timeSigX, midY - m.lineSpacing * 0.95, fontSize, col);
    _paintTimeSigDigit(canvas, '${m.timeSigDenominator}',
        timeSigX, midY + m.lineSpacing * 0.95, fontSize, col);
  }

  void _paintTimeSigDigit(Canvas canvas, String text, double cx, double cy,
      double fontSize, Color color) {
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: text,
        style: TextStyle(
          fontSize:   fontSize,
          color:      color,
          fontWeight: FontWeight.bold,
          height:     1.0,
        ),
      )
      ..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  // ─── Bar lines ────────────────────────────────────────────────────────────

  void _drawBarLines(Canvas canvas, Size size, SheetRenderModel m) {
    for (final x in m.barLineXs) {
      if (x < 0 || x > size.width) continue;
      canvas.drawLine(Offset(x, m.staffTop), Offset(x, m.staffBottom), _barPaint);
    }
  }

  void _drawBeatLines(Canvas canvas, Size size, SheetRenderModel m) {
    for (final x in m.beatLineXs) {
      if (x < 0 || x > size.width) continue;
      canvas.drawLine(Offset(x, m.staffTop), Offset(x, m.staffBottom), _beatPaint);
    }
  }

  // ─── Stems ────────────────────────────────────────────────────────────────

  void _drawStems(
    Canvas canvas,
    SheetRenderModel m,
    List<bool> drawStemForNote,
    List<double> stemFromY,
    Map<int, double> beamYForNote,
  ) {
    for (int i = 0; i < m.notes.length; i++) {
      if (!drawStemForNote[i]) continue;
      // Whole notes have no stem
      if (!m.notes[i].noteValue.hasStem) continue;

      final n    = m.notes[i];
      final from = stemFromY[i];

      final naturalTip = n.note.stemUp
          ? from - 3.5 * m.lineSpacing
          : from + 3.5 * m.lineSpacing;

      final tip = beamYForNote.containsKey(i)
          ? (n.note.stemUp
              ? min(naturalTip, beamYForNote[i]!)
              : max(naturalTip, beamYForNote[i]!))
          : naturalTip;

      final stemX = n.x + (n.note.stemUp ? m.lineSpacing * 0.5 : -m.lineSpacing * 0.5);
      final paint = Paint()
        ..color       = n.note.color.withValues(alpha: 0.80)
        ..strokeWidth = m.lineSpacing * 0.14
        ..style       = PaintingStyle.stroke;

      canvas.drawLine(Offset(stemX, from), Offset(stemX, tip), paint);
    }
  }

  // ─── Beams (primary + secondary for 16th notes) ───────────────────────────

  void _drawBeams(
    Canvas canvas,
    SheetRenderModel m,
    Map<int, double> beamYForNote,
    List<double> stemFromY,
  ) {
    for (final group in m.beamGroups) {
      if (group.length < 2) continue;

      final beamY  = beamYForNote[group.first]!;
      final firstN = m.notes[group.first];
      final lastN  = m.notes[group.last];
      final beamOffX = m.lineSpacing * 0.5;

      // Primary beam (always for eighth+ notes)
      canvas.drawLine(
        Offset(firstN.x + beamOffX, beamY),
        Offset(lastN.x  + beamOffX, beamY),
        _beamPaint,
      );

      // Secondary beam for 16th-note density groups
      final has16th = group.any((idx) =>
          m.notes[idx].noteValue == NoteValueType.sixteenth ||
          m.notes[idx].noteValue == NoteValueType.thirtySecond ||
          m.notes[idx].noteValue == NoteValueType.sixtyFourth);
      if (has16th && group.length >= 2) {
        final secondBeamY = beamY + (firstN.note.stemUp ? 1 : -1) * m.lineSpacing * 0.65;
        canvas.drawLine(
          Offset(firstN.x + beamOffX, secondBeamY),
          Offset(lastN.x  + beamOffX, secondBeamY),
          Paint()
            ..color       = const Color(0xFF5A7888)
            ..strokeWidth = 3.0
            ..strokeCap   = StrokeCap.square
            ..style       = PaintingStyle.stroke,
        );
      }

      // Tertiary beam for 32nd-note density
      final has32nd = group.any((idx) =>
          m.notes[idx].noteValue == NoteValueType.thirtySecond ||
          m.notes[idx].noteValue == NoteValueType.sixtyFourth);
      if (has32nd && group.length >= 2) {
        final thirdBeamY = beamY + (firstN.note.stemUp ? 1 : -1) * m.lineSpacing * 1.3;
        canvas.drawLine(
          Offset(firstN.x + beamOffX, thirdBeamY),
          Offset(lastN.x  + beamOffX, thirdBeamY),
          Paint()
            ..color       = const Color(0xFF4A6878)
            ..strokeWidth = 2.5
            ..strokeCap   = StrokeCap.square
            ..style       = PaintingStyle.stroke,
        );
      }
    }
  }

  // ─── Flags (for unbeamed eighth/16th/32nd notes) ──────────────────────────

  void _drawFlags(
    Canvas canvas,
    SheetRenderModel m,
    List<bool> drawStemForNote,
    List<double> stemFromY,
    Set<int> beamedIndices,
  ) {
    for (int i = 0; i < m.notes.length; i++) {
      if (!drawStemForNote[i]) continue;
      if (beamedIndices.contains(i)) continue; // beamed notes don't get flags

      final n = m.notes[i];
      final flagCount = n.noteValue.flagCount;
      if (flagCount == 0) continue;
      if (!n.noteValue.hasStem) continue;

      final from   = stemFromY[i];
      final stemX  = n.x + (n.note.stemUp ? m.lineSpacing * 0.5 : -m.lineSpacing * 0.5);
      final tipY   = n.note.stemUp
          ? from - 3.5 * m.lineSpacing
          : from + 3.5 * m.lineSpacing;

      final color = n.note.color.withValues(alpha: 0.80);
      final ls    = m.lineSpacing;

      for (int f = 0; f < flagCount; f++) {
        // Each flag is offset from the previous by 0.6 line spacings
        final flagY = tipY + (n.note.stemUp ? 1.0 : -1.0) * f * ls * 0.6;
        _drawFlag(canvas, stemX, flagY, color, ls, n.note.stemUp);
      }
    }
  }

  /// Draws a single curved flag starting at (x, y).
  void _drawFlag(Canvas canvas, double x, double y, Color color, double ls, bool stemUp) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = ls * 0.14
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round;

    // A simple curved flag: cubic bezier curving to the right
    final sign   = stemUp ? 1.0 : -1.0;
    final path   = Path();
    path.moveTo(x, y);
    path.cubicTo(
      x + ls * 1.2, y + sign * ls * 0.3,
      x + ls * 1.4, y + sign * ls * 1.0,
      x + ls * 0.5, y + sign * ls * 1.4,
    );
    canvas.drawPath(path, paint);
  }

  // ─── Note heads (and glow / ledger lines / labels) ────────────────────────

  void _drawNoteHeads(Canvas canvas, SheetRenderModel m) {
    for (int i = 0; i < m.notes.length; i++) {
      final n = m.notes[i];
      final Color baseColor = n.highlighted
          ? Color.lerp(n.note.color, Colors.white, 0.55)!
          : n.note.color;

      if (n.highlighted) {
        canvas.drawCircle(
          Offset(n.x, n.y),
          m.lineSpacing * 1.1,
          Paint()
            ..color     = n.note.color.withValues(alpha: 0.30)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
      }

      _drawLedgerLines(canvas, n, m);

      final ls = m.lineSpacing;
      final isOpen = n.noteValue.isOpen;

      switch (n.note.headType) {
        case NoteHeadType.normal:
          _drawNormalHead(canvas, n.x, n.y, baseColor, ls: ls, hollow: isOpen);
        case NoteHeadType.xmark:
          _drawXHead(canvas, n.x, n.y, baseColor, ls: ls);
        case NoteHeadType.diamond:
          _drawDiamondHead(canvas, n.x, n.y, baseColor, ls: ls, hollow: isOpen);
      }

      if (n.note.openHihat) {
        canvas.drawCircle(
          Offset(n.x, n.y - m.lineSpacing * 1.3),
          m.lineSpacing * 0.38,
          Paint()
            ..color       = baseColor
            ..strokeWidth = 1.5
            ..style       = PaintingStyle.stroke,
        );
      }

      _drawNoteLabel(canvas, n, m);
    }
  }

  // ─── Instrument label ─────────────────────────────────────────────────────

  void _drawNoteLabel(Canvas canvas, LaidOutNote n, SheetRenderModel m) {
    final label = _padLabel[n.note.pad];
    if (label == null) return;

    final labelY = n.note.stemUp
        ? n.y + m.lineSpacing * 0.90
        : n.y - m.lineSpacing * 0.90;

    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text:  label,
        style: TextStyle(
          fontSize:    m.lineSpacing * 0.78,
          color:       n.note.color.withValues(alpha: 0.55),
          letterSpacing: 0,
          height:      1.0,
        ),
      )
      ..layout();

    tp.paint(canvas, Offset(n.x - tp.width / 2, labelY - tp.height / 2));
  }

  // ─── Normal note head (filled oval, rotated) ──────────────────────────────

  void _drawNormalHead(Canvas canvas, double x, double y, Color color,
      {double ls = 17.0, bool hollow = false}) {
    final hw = ls * 0.57;
    final hh = ls * 0.36;
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(-0.22);
    if (hollow) {
      // Half / whole note: hollow (open) oval — outline only
      canvas.drawOval(
        Rect.fromLTWH(-hw, -hh, hw * 2, hh * 2),
        Paint()
          ..color = color
          ..strokeWidth = ls * 0.14
          ..style = PaintingStyle.stroke,
      );
      // Thin fill to distinguish from empty space
      canvas.drawOval(
        Rect.fromLTWH(-hw * 0.55, -hh * 0.55, hw * 1.10, hh * 1.10),
        Paint()..color = color.withValues(alpha: 0.12)..style = PaintingStyle.fill,
      );
    } else {
      canvas.drawOval(
        Rect.fromLTWH(-hw, -hh, hw * 2, hh * 2),
        Paint()..color = color..style = PaintingStyle.fill,
      );
    }
    canvas.restore();
  }

  // ─── X note head (hi-hat, cymbals) ────────────────────────────────────────

  void _drawXHead(Canvas canvas, double x, double y, Color color,
      {double ls = 17.0}) {
    final r = ls * 0.46;
    final p = Paint()
      ..color       = color
      ..strokeWidth = ls * 0.17
      ..strokeCap   = StrokeCap.round
      ..style       = PaintingStyle.stroke;
    canvas.drawLine(Offset(x - r, y - r), Offset(x + r, y + r), p);
    canvas.drawLine(Offset(x + r, y - r), Offset(x - r, y + r), p);
  }

  // ─── Diamond note head (ride bell) ────────────────────────────────────────

  void _drawDiamondHead(Canvas canvas, double x, double y, Color color,
      {double ls = 17.0, bool hollow = false}) {
    final hy = ls * 0.60;
    final hx = ls * 0.46;
    final path = Path()
      ..moveTo(x, y - hy)
      ..lineTo(x + hx, y)
      ..lineTo(x, y + hy)
      ..lineTo(x - hx, y)
      ..close();
    if (hollow) {
      canvas.drawPath(path,
        Paint()..color = color..strokeWidth = ls * 0.14..style = PaintingStyle.stroke);
    } else {
      canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
    }
  }

  // ─── Ledger lines ─────────────────────────────────────────────────────────

  void _drawLedgerLines(Canvas canvas, LaidOutNote n, SheetRenderModel m) {
    final hw = m.lineSpacing * 0.90;
    final sl  = n.note.staffLine;
    final top = m.staffTop;
    final ls  = m.lineSpacing;

    if (sl > 4.5) {
      final maxLine = sl.ceil();
      for (int i = 5; i <= maxLine; i++) {
        final y = top + (4.0 - i) * ls;
        canvas.drawLine(Offset(n.x - hw, y), Offset(n.x + hw, y), _ledgerPaint);
      }
    }

    if (sl < -0.5) {
      final minLine = sl.floor();
      for (int i = -1; i >= minLine; i--) {
        final y = top + (4.0 - i) * ls;
        canvas.drawLine(Offset(n.x - hw, y), Offset(n.x + hw, y), _ledgerPaint);
      }
    }
  }

  // ─── Playhead cursor ──────────────────────────────────────────────────────

  void _drawPlayhead(Canvas canvas, Size size, SheetRenderModel m) {
    final x = m.playheadX;

    canvas.drawLine(
      Offset(x, m.staffTop - 20),
      Offset(x, m.staffBottom + 20),
      Paint()
        ..color       = NavaTheme.neonMagenta.withValues(alpha: 0.18)
        ..strokeWidth = 12
        ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color       = NavaTheme.neonMagenta
        ..strokeWidth = 2.0,
    );

    final arrow = Path()
      ..moveTo(x - 7, m.staffTop - 14)
      ..lineTo(x + 7, m.staffTop - 14)
      ..lineTo(x,     m.staffTop + 2)
      ..close();
    canvas.drawPath(
      arrow,
      Paint()..color = NavaTheme.neonMagenta..style = PaintingStyle.fill,
    );
  }

  // ─── Bar number label ─────────────────────────────────────────────────────

  void _drawBarLabel(Canvas canvas, Size size, SheetRenderModel m) {
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: 'COMPÁS ${m.currentBar}',
        style: const TextStyle(
          fontSize:      9,
          color:         Color(0xFF5A7080),
          letterSpacing: 1.2,
          fontFamily:    'DrummerBody',
        ),
      )
      ..layout(maxWidth: 140);
    tp.paint(
      canvas,
      Offset(m.playheadX - tp.width / 2, m.staffTop - 30),
    );
  }

  @override
  bool shouldRepaint(SheetMusicPainter old) => old.model != model;
}
