// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Sheet Music Painter
// Pure CustomPainter — receives a SheetRenderModel and draws everything.
// No state, no streams — just draw().
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../../theme/nava_theme.dart';
import 'notation_models.dart';

class SheetMusicPainter extends CustomPainter {
  final SheetRenderModel model;

  const SheetMusicPainter({required this.model}) : super();

  // ─── Static paints (created once, reused every frame) ────────────────────

  static final Paint _staffPaint = Paint()
    ..color = const Color(0xFF3D5060)
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;

  static final Paint _barPaint = Paint()
    ..color = const Color(0xFF4E6070)
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;

  static final Paint _beatPaint = Paint()
    ..color = const Color(0xFF2A3A48)
    ..strokeWidth = 0.7
    ..style = PaintingStyle.stroke;

  static final Paint _ledgerPaint = Paint()
    ..color = const Color(0xFF3D5060)
    ..strokeWidth = 1.1
    ..style = PaintingStyle.stroke;

  // ─── Main paint entry point ───────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final m = model;
    _drawBeatLines(canvas, size, m);
    _drawBarLines(canvas, size, m);
    _drawStaff(canvas, size, m);
    _drawClef(canvas, m);
    _drawNotes(canvas, m);
    _drawPlayhead(canvas, size, m);
    _drawBarLabel(canvas, size, m);
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
    const clefX    = 8.0;
    const clefW    = 4.0;
    const clefGap  = 5.0;
    final top      = m.staffTop;
    final bottom   = m.staffBottom;
    final paint    = Paint()
      ..color = const Color(0xFF5A7890)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(clefX,           top, clefW, bottom - top), paint);
    canvas.drawRect(Rect.fromLTWH(clefX + clefGap, top, clefW, bottom - top), paint);
  }

  // ─── Bar lines ────────────────────────────────────────────────────────────

  void _drawBarLines(Canvas canvas, Size size, SheetRenderModel m) {
    for (final x in m.barLineXs) {
      if (x < 0 || x > size.width) continue;
      canvas.drawLine(Offset(x, m.staffTop), Offset(x, m.staffBottom), _barPaint);
    }
  }

  // ─── Beat sub-lines ───────────────────────────────────────────────────────

  void _drawBeatLines(Canvas canvas, Size size, SheetRenderModel m) {
    for (final x in m.beatLineXs) {
      if (x < 0 || x > size.width) continue;
      canvas.drawLine(Offset(x, m.staffTop), Offset(x, m.staffBottom), _beatPaint);
    }
  }

  // ─── Notes ────────────────────────────────────────────────────────────────

  void _drawNotes(Canvas canvas, SheetRenderModel m) {
    for (final n in m.notes) {
      final Color baseColor = n.highlighted
          ? Color.lerp(n.note.color, Colors.white, 0.55)!
          : n.note.color;

      // Glow halo on hit
      if (n.highlighted) {
        canvas.drawCircle(
          Offset(n.x, n.y),
          13,
          Paint()
            ..color = n.note.color.withOpacity(0.28)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
      }

      _drawLedgerLines(canvas, n, m);
      _drawStem(canvas, n, m);

      switch (n.note.headType) {
        case NoteHeadType.normal:
          _drawNormalHead(canvas, n.x, n.y, baseColor);
        case NoteHeadType.xmark:
          _drawXHead(canvas, n.x, n.y, baseColor);
        case NoteHeadType.diamond:
          _drawDiamondHead(canvas, n.x, n.y, baseColor);
      }

      // Open hi-hat: small circle above the × head
      if (n.note.openHihat) {
        canvas.drawCircle(
          Offset(n.x, n.y - 14),
          4.5,
          Paint()
            ..color = baseColor
            ..strokeWidth = 1.3
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  // ─── Normal note head (filled oval, rotated) ──────────────────────────────

  void _drawNormalHead(Canvas canvas, double x, double y, Color color) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(-0.22); // standard music note inclination
    canvas.drawOval(
      const Rect.fromLTWH(-6.5, -4.0, 13, 8),
      Paint()..color = color..style = PaintingStyle.fill,
    );
    canvas.restore();
  }

  // ─── X note head (hi-hat, cymbals) ────────────────────────────────────────

  void _drawXHead(Canvas canvas, double x, double y, Color color) {
    final p = Paint()
      ..color       = color
      ..strokeWidth = 2.2
      ..strokeCap   = StrokeCap.round
      ..style       = PaintingStyle.stroke;
    const r = 5.5;
    canvas.drawLine(Offset(x - r, y - r), Offset(x + r, y + r), p);
    canvas.drawLine(Offset(x + r, y - r), Offset(x - r, y + r), p);
  }

  // ─── Diamond note head (ride bell) ────────────────────────────────────────

  void _drawDiamondHead(Canvas canvas, double x, double y, Color color) {
    final path = Path()
      ..moveTo(x, y - 7)
      ..lineTo(x + 5.5, y)
      ..lineTo(x, y + 7)
      ..lineTo(x - 5.5, y)
      ..close();
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
  }

  // ─── Stem ─────────────────────────────────────────────────────────────────

  void _drawStem(Canvas canvas, LaidOutNote n, SheetRenderModel m) {
    final color = n.note.color.withOpacity(0.80);
    final paint = Paint()
      ..color       = color
      ..strokeWidth = 1.4
      ..style       = PaintingStyle.stroke;

    const stemLen = 32.0;

    if (n.note.stemUp) {
      // Stem goes UP from the right edge of the note head
      canvas.drawLine(
        Offset(n.x + 6, n.y),
        Offset(n.x + 6, n.y - stemLen),
        paint,
      );
    } else {
      // Stem goes DOWN from the left edge of the note head
      canvas.drawLine(
        Offset(n.x - 6, n.y),
        Offset(n.x - 6, n.y + stemLen),
        paint,
      );
    }
  }

  // ─── Ledger lines ─────────────────────────────────────────────────────────

  void _drawLedgerLines(Canvas canvas, LaidOutNote n, SheetRenderModel m) {
    const hw = 11.0; // half-width of ledger line
    final sl = n.note.staffLine;
    final top = m.staffTop;
    final ls  = m.lineSpacing;

    // Above staff: need ledger lines at each integer staffLine ≥ 5
    if (sl > 4.5) {
      final maxLine = sl.ceil();
      for (int i = 5; i <= maxLine; i++) {
        final y = top + (4.0 - i) * ls;
        canvas.drawLine(Offset(n.x - hw, y), Offset(n.x + hw, y), _ledgerPaint);
      }
    }

    // Below staff: need ledger lines at each integer staffLine ≤ -1
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

    // Glow
    canvas.drawLine(
      Offset(x, m.staffTop - 20),
      Offset(x, m.staffBottom + 20),
      Paint()
        ..color  = NavaTheme.neonMagenta.withOpacity(0.18)
        ..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Solid line
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color       = NavaTheme.neonMagenta
        ..strokeWidth = 1.8,
    );

    // Downward triangle at top (cursor arrow)
    final arrow = Path()
      ..moveTo(x - 6, m.staffTop - 12)
      ..lineTo(x + 6, m.staffTop - 12)
      ..lineTo(x,     m.staffTop)
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
          fontSize: 8,
          color: Color(0xFF4A6070),
          letterSpacing: 1.2,
          fontFamily: 'DrummerBody',
        ),
      )
      ..layout(maxWidth: 120);
    tp.paint(
      canvas,
      Offset(m.playheadX - tp.width / 2, m.staffTop - 26),
    );
  }

  @override
  bool shouldRepaint(SheetMusicPainter old) => old.model != model;
}
