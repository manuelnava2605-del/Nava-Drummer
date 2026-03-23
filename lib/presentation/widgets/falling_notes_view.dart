// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Falling Notes View  (InstaDrum visual style, smooth render)
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/entities/entities.dart';
import '../../core/practice_engine.dart';
import '../../core/global_timing_controller.dart';
import '../../core/sync_diagnostics.dart';
import '../../core/drum_lane_mapping.dart';
import '../theme/nava_theme.dart';

class FallingNotesView extends StatefulWidget {
  final List<NoteEvent>    noteEvents;
  final Stream<double>     playheadStream;
  final Stream<HitResult>  hitResultStream;
  final Stream<ScoreState> scoreStream;
  final Stream<int>        beatStream;
  final double             lookAheadSeconds;
  final double             hitLinePosition;
  final double             tempoFactor;

  /// Called when the user taps a pad circle in the bottom area.
  /// Pass this to the engine to register on-screen hits without needing
  /// the separate DrumPadView overlay.
  final void Function(DrumPad pad)? onPadTap;

  const FallingNotesView({
    super.key,
    required this.noteEvents,
    required this.playheadStream,
    required this.hitResultStream,
    required this.scoreStream,
    required this.beatStream,
    this.lookAheadSeconds = 3.0,
    this.hitLinePosition  = 0.22,
    this.tempoFactor      = 1.0,
    this.onPadTap,
  });

  @override
  State<FallingNotesView> createState() => _FallingNotesViewState();
}

class _FallingNotesViewState extends State<FallingNotesView>
    with SingleTickerProviderStateMixin {

  late AnimationController       _controller;
  final RenderPlayheadInterpolator _interp = RenderPlayheadInterpolator();
  StreamSubscription<double>? _playheadSub;
  Offset _shakeOffset = Offset.zero;

  final List<_PadFlash>   _padFlashes = [];
  final List<_SqParticle> _particles  = [];
  final math.Random       _rng        = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))..repeat();

    _playheadSub = widget.playheadStream.listen(_interp.onEngineUpdate);
    widget.hitResultStream.listen(_onHit);
  }

  @override
  void didUpdateWidget(FallingNotesView old) {
    super.didUpdateWidget(old);
    _interp.setTempo(widget.tempoFactor);
  }

  void _onHit(HitResult r) {
    final now   = DateTime.now();
    final flash = _PadFlash(pad: r.expected.pad, grade: r.grade, createdAt: now);
    if (_padFlashes.length >= 14) _padFlashes.removeAt(0);
    _padFlashes.add(flash);
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _padFlashes.remove(flash));
    });
    if (r.grade == HitGrade.perfect || r.grade == HitGrade.good) {
      _spawnSquares(r.expected.pad, now, r.grade);
    }
    if (r.grade != HitGrade.miss &&
        (r.expected.pad == DrumPad.kick || r.expected.pad == DrumPad.snare)) {
      _triggerShake(r.expected.pad == DrumPad.kick ? 5.0 : 3.0);
    }
    if (mounted) setState(() {});
  }

  void _triggerShake(double mag) {
    setState(() => _shakeOffset = Offset(
      (_rng.nextDouble() - 0.5) * mag * 2,
      (_rng.nextDouble() - 0.5) * mag,
    ));
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) setState(() => _shakeOffset = Offset(
        (_rng.nextDouble() - 0.5) * mag,
        (_rng.nextDouble() - 0.5) * mag * 0.5,
      ));
    });
    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted) setState(() => _shakeOffset = Offset.zero);
    });
  }

  void _spawnSquares(DrumPad pad, DateTime now, HitGrade grade) {
    final color = NavaTheme.padColor(pad);
    final count = grade == HitGrade.perfect ? 20 : 10;
    for (int i = 0; i < count; i++) {
      _particles.add(_SqParticle(
        pad:       pad,
        color:     color,
        angle:     _rng.nextDouble() * math.pi * 2,
        speed:     80 + _rng.nextDouble() * 220,
        size:      4.0 + _rng.nextDouble() * 8.0,
        rotation:  _rng.nextDouble() * math.pi * 2,
        createdAt: now,
        life:      380 + _rng.nextInt(260),
      ));
    }
    _particles.removeWhere(
        (p) => now.difference(p.createdAt).inMilliseconds > 900);
    if (_particles.length > 120) {
      _particles.removeRange(0, _particles.length - 120);
    }
  }

  @override
  void dispose() {
    _playheadSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  DrumPad? _padForTap(Offset localPos, Size size) {
    final hitY = size.height * (1 - widget.hitLinePosition);
    if (localPos.dy < hitY) return null;
    final laneW = size.width / kDrumLanes.length;
    final li    = (localPos.dx / laneW).floor().clamp(0, kDrumLanes.length - 1);
    return kDrumLanes[li];
  }

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: _shakeOffset,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onPadTap == null ? null : (details) {
          // Use a LayoutBuilder size approximation via RenderBox
          final rb  = context.findRenderObject() as RenderBox?;
          if (rb == null) return;
          final pad = _padForTap(details.localPosition, rb.size);
          if (pad != null) widget.onPadTap!(pad);
        },
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            final ph = _interp.smoothSeconds;
            // Publish the interpolated render playhead to the diagnostics
            // overlay so it can be compared against audio and engine positions.
            SyncDiagnostics.instance.renderPlayheadSec = ph;
            return CustomPaint(
              painter: _NotesPainter(
                noteEvents:  widget.noteEvents,
                playhead:    ph,
                lookAhead:   widget.lookAheadSeconds,
                hitLinePos:  widget.hitLinePosition,
                padFlashes:  List.from(_padFlashes),
                particles:   List.from(_particles),
                now:         DateTime.now(),
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter — InstaDrum style
// ─────────────────────────────────────────────────────────────────────────────
class _NotesPainter extends CustomPainter {
  final List<NoteEvent>  noteEvents;
  final double           playhead;
  final double           lookAhead;
  final double           hitLinePos;
  final List<_PadFlash>  padFlashes;
  final List<_SqParticle> particles;
  final DateTime         now;

  // Lane layout and names come from drum_lane_mapping.dart (single source of truth).

  _NotesPainter({
    required this.noteEvents, required this.playhead, required this.lookAhead,
    required this.hitLinePos, required this.padFlashes, required this.particles,
    required this.now,
  });

  @override bool shouldRepaint(_NotesPainter _) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final padAreaH = size.height * hitLinePos;
    final hitY     = size.height - padAreaH;
    final laneW    = size.width / kDrumLanes.length;

    _drawBg(canvas, size);
    _drawLaneBgs(canvas, size, hitY, laneW);
    _drawLaneDividers(canvas, size, laneW);
    _drawNotes(canvas, size, hitY, laneW);
    _drawHitZones(canvas, size, hitY, laneW);
    _drawPads(canvas, size, hitY, laneW);
    _drawSquareParticles(canvas, size, hitY, laneW);
    _drawGradeLabels(canvas, size, hitY, laneW);
  }

  void _drawBg(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0E1218),
    );
  }

  void _drawLaneBgs(Canvas canvas, Size size, double hitY, double laneW) {
    for (int i = 0; i < kDrumLanes.length; i++) {
      final color = NavaTheme.padColor(kDrumLanes[i]);
      canvas.drawRect(
        Rect.fromLTWH(i * laneW, 0, laneW, hitY),
        Paint()..shader = LinearGradient(
          colors: [color.withOpacity(0.02), color.withOpacity(0.12)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(i * laneW, 0, laneW, hitY)),
      );
      canvas.drawRect(
        Rect.fromLTWH(i * laneW, hitY, laneW, size.height - hitY),
        Paint()..color = color.withOpacity(0.08),
      );
    }
  }

  void _drawLaneDividers(Canvas canvas, Size size, double laneW) {
    final p = Paint()..color = const Color(0xFF252D3D)..strokeWidth = 1.0;
    for (int i = 1; i < kDrumLanes.length; i++) {
      canvas.drawLine(Offset(i * laneW, 0), Offset(i * laneW, size.height), p);
    }
  }

  void _drawNotes(Canvas canvas, Size size, double hitY, double laneW) {
    final wStart = playhead - 0.25;
    final wEnd   = playhead + lookAhead;

    for (final note in noteEvents) {
      if (note.timeSeconds < wStart) continue;
      if (note.timeSeconds > wEnd)   break;

      final li = drumLaneIndex(note.pad);
      if (li < 0) continue;

      final progress = (note.timeSeconds - playhead) / lookAhead;
      final y        = hitY - (hitY * progress);
      final cx       = li * laneW + laneW / 2;
      _drawRectNote(canvas, cx, y, laneW, note);
    }
  }

  static const double _noteW = 0.82; // fraction of lane width
  static const double _noteH = 12.0; // fixed height in dp

  void _drawRectNote(Canvas canvas, double cx, double y,
      double laneW, NoteEvent note) {
    final color  = NavaTheme.padColor(note.pad);
    final w      = laneW * _noteW;
    const h      = _noteH;
    const radius = Radius.circular(5);
    final rect   = Rect.fromCenter(center: Offset(cx, y), width: w, height: h);
    final rr     = RRect.fromRectAndRadius(rect, radius);

    // Glow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, y), width: w + 10, height: h + 8),
          const Radius.circular(8)),
      Paint()
        ..color      = color.withOpacity(0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    // Fill
    canvas.drawRRect(rr, Paint()..color = color);
    // Top highlight strip
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - w / 2, y - h / 2, w, h / 2), radius));
    canvas.drawRRect(rr, Paint()..color = Colors.white.withOpacity(0.22));
    canvas.restore();
    // Bottom edge
    canvas.drawRRect(rr,
        Paint()
          ..style       = PaintingStyle.stroke
          ..color       = color.withOpacity(0.75)
          ..strokeWidth = 1.0);
  }

  // Hit zones — one colored target rectangle per lane at the hit line
  void _drawHitZones(Canvas canvas, Size size, double hitY, double laneW) {
    const noteW  = _noteW;
    const noteH  = _noteH;
    const radius = Radius.circular(5);
    for (int i = 0; i < kDrumLanes.length; i++) {
      final cx    = i * laneW + laneW / 2;
      final color = NavaTheme.padColor(kDrumLanes[i]);
      final flash = padFlashes.where((f) => f.pad == kDrumLanes[i]).firstOrNull;
      final hitT  = flash != null
          ? (1 - now.difference(flash.createdAt).inMilliseconds / 450.0).clamp(0.0, 1.0)
          : 0.0;
      final rect  = Rect.fromCenter(
          center: Offset(cx, hitY), width: laneW * noteW, height: noteH);
      final rr    = RRect.fromRectAndRadius(rect, radius);

      // Background
      canvas.drawRRect(rr,
          Paint()..color = color.withOpacity(0.08 + hitT * 0.18));
      // Border
      canvas.drawRRect(rr,
          Paint()
            ..style       = PaintingStyle.stroke
            ..color       = color.withOpacity(0.40 + hitT * 0.55)
            ..strokeWidth = hitT > 0 ? 2.5 : 1.5);
    }
  }

  void _drawPads(Canvas canvas, Size size, double hitY, double laneW) {
    final padAreaH = size.height - hitY;
    final padCY    = hitY + padAreaH * 0.50;
    final padR     = math.min(laneW * 0.42, padAreaH * 0.46);

    for (int i = 0; i < kDrumLanes.length; i++) {
      final cx    = i * laneW + laneW / 2;
      final pad   = kDrumLanes[i];
      final color = NavaTheme.padColor(pad);
      final name  = kDrumLaneNames[i];

      final flash = padFlashes.where((f) => f.pad == pad).firstOrNull;
      final ageMs = flash != null ? now.difference(flash.createdAt).inMilliseconds : 9999;
      final hitT  = flash != null ? (1 - ageMs / 450.0).clamp(0.0, 1.0) : 0.0;

      // Hit glow
      if (hitT > 0) {
        canvas.drawCircle(Offset(cx, padCY), padR * (1.4 + hitT * 0.3),
          Paint()..color = color.withOpacity(hitT * 0.38)
                 ..maskFilter = MaskFilter.blur(BlurStyle.normal, 22 * hitT));
      }
      // Body
      canvas.drawCircle(Offset(cx, padCY), padR,
        Paint()..color = Color.lerp(const Color(0xFF1A2030), color.withOpacity(0.30), hitT * 0.85)!);
      // Outer ring
      canvas.drawCircle(Offset(cx, padCY), padR,
        Paint()..style = PaintingStyle.stroke
               ..color = Color.lerp(color.withOpacity(0.55), color, hitT)!
               ..strokeWidth = 3.5);
      // Inner ring
      canvas.drawCircle(Offset(cx, padCY), padR * 0.65,
        Paint()..style = PaintingStyle.stroke
               ..color = color.withOpacity(0.22 + hitT * 0.28)
               ..strokeWidth = 1.2);
      // Center dot
      canvas.drawCircle(Offset(cx, padCY - padR * 0.28), padR * 0.08,
        Paint()..color = color.withOpacity(0.45 + hitT * 0.55));

      // Label
      final tp = TextPainter(
        text: TextSpan(text: name, style: TextStyle(
          color: Colors.white.withOpacity(0.60 + hitT * 0.40),
          fontSize: padR * 0.30, fontWeight: FontWeight.bold, fontFamily: 'DrummerBody',
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width/2, padCY + padR * 0.20));

      // Ripple
      if (hitT > 0 && ageMs < 450) {
        final rT = 1 - hitT;
        canvas.drawCircle(Offset(cx, padCY), padR * (1.0 + rT * 1.0),
          Paint()..style = PaintingStyle.stroke
                 ..color = color.withOpacity(hitT * 0.55)
                 ..strokeWidth = 2.5 * hitT);
      }
    }
  }

  void _drawSquareParticles(Canvas canvas, Size size, double hitY, double laneW) {
    for (final p in particles) {
      final ageMs = now.difference(p.createdAt).inMilliseconds;
      if (ageMs > p.life) continue;
      final t       = ageMs / p.life.toDouble();
      final opacity = (1 - t * t).clamp(0.0, 1.0);
      final dist    = p.speed * (ageMs / 1000.0);
      final gravity = 200 * t * t;
      final li      = drumLaneIndex(p.pad);
      final padAreaH = size.height - hitY;
      final startX  = li >= 0 ? li * laneW + laneW / 2 : size.width / 2;
      final startY  = hitY + padAreaH * 0.50;
      final px = startX + math.cos(p.angle) * dist;
      final py = startY + math.sin(p.angle) * dist + gravity;
      final sz = p.size * (1 - t * 0.6);
      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(p.rotation + t * math.pi);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: sz, height: sz),
        Paint()..color = p.color.withOpacity(opacity));
      canvas.restore();
    }
  }

  void _drawGradeLabels(Canvas canvas, Size size, double hitY, double laneW) {
    for (final flash in padFlashes) {
      final ageMs = now.difference(flash.createdAt).inMilliseconds;
      if (ageMs > 600) continue;
      final opacity = (1 - ageMs / 600.0).clamp(0.0, 1.0);
      final rise    = -52.0 * (ageMs / 600.0);
      final li = drumLaneIndex(flash.pad);
      if (li < 0) continue;
      final cx = li * laneW + laneW / 2;
      final isPerfect = flash.grade == HitGrade.perfect;
      final tp = TextPainter(
        text: TextSpan(text: flash.gradeLabel, style: TextStyle(
          color:      isPerfect ? Colors.white.withOpacity(opacity) : flash.gradeColor.withOpacity(opacity),
          fontSize:   isPerfect ? 15.0 : 12.0,
          fontWeight: FontWeight.bold,
          fontFamily: 'DrummerDisplay',
          letterSpacing: 1.5,
          shadows: [Shadow(color: flash.gradeColor.withOpacity(opacity * 0.9), blurRadius: 10)],
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width/2, hitY - 38 + rise));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data classes
// ─────────────────────────────────────────────────────────────────────────────
class _PadFlash {
  final DrumPad  pad;
  final HitGrade grade;
  final DateTime createdAt;
  _PadFlash({required this.pad, required this.grade, required this.createdAt});

  Color get gradeColor {
    switch (grade) {
      case HitGrade.perfect: return NavaTheme.hitPerfect;
      case HitGrade.good:    return NavaTheme.hitGood;
      case HitGrade.early:   return Colors.cyanAccent;
      case HitGrade.late:    return Colors.orangeAccent;
      case HitGrade.miss:    return NavaTheme.hitMiss;
      default:               return NavaTheme.textMuted;
    }
  }

  String get gradeLabel {
    switch (grade) {
      case HitGrade.perfect: return 'Perfect';
      case HitGrade.good:    return 'Good';
      case HitGrade.early:   return 'Early';
      case HitGrade.late:    return 'Late';
      case HitGrade.miss:    return 'Miss';
      default:               return '';
    }
  }
}

class _SqParticle {
  final DrumPad  pad;
  final Color    color;
  final double   angle, speed, size, rotation;
  final DateTime createdAt;
  final int      life;
  _SqParticle({required this.pad, required this.color, required this.angle,
    required this.speed, required this.size, required this.rotation,
    required this.createdAt, required this.life});
}
