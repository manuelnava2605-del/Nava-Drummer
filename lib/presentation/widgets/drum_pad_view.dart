// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — DrumPadView
// On-screen virtual drum pads. Fires onScreenHit() through PracticeEngine so
// both sources share the same evaluation pipeline.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../../domain/entities/entities.dart';
import '../../core/practice_engine.dart';
import '../theme/nava_theme.dart';

// ── Layout definition ─────────────────────────────────────────────────────────
// Two rows:
//   Top:    Crash1 | HH-Closed | Ride | Crash2
//   Middle: Tom1   | Tom2      | Tom3 | FloorTom
//   Bottom: Kick   | Snare     |      | HH-Pedal

const _kTopRow    = [DrumPad.crash1, DrumPad.hihatClosed, DrumPad.ride, DrumPad.crash2];
const _kMidRow    = [DrumPad.tom1,   DrumPad.tom2,        DrumPad.tom3, DrumPad.floorTom];
const _kBottomRow = [DrumPad.kick,   DrumPad.snare,       DrumPad.hihatOpen, DrumPad.hihatPedal];

// Accent colours per pad family
Color _padColor(DrumPad pad) {
  switch (pad) {
    case DrumPad.kick:
      return const Color(0xFFFF6B6B);   // red — kick
    case DrumPad.snare:
      return const Color(0xFFFFD93D);   // gold — snare
    case DrumPad.hihatClosed:
    case DrumPad.hihatOpen:
    case DrumPad.hihatPedal:
      return NavaTheme.neonCyan;
    case DrumPad.crash1:
    case DrumPad.crash2:
      return NavaTheme.neonMagenta;
    case DrumPad.ride:
    case DrumPad.rideBell:
      return NavaTheme.neonGold;
    case DrumPad.tom1:
    case DrumPad.tom2:
    case DrumPad.tom3:
    case DrumPad.floorTom:
      return NavaTheme.neonPurple;
    default:
      return NavaTheme.textSecondary;
  }
}

// ── DrumPadView ───────────────────────────────────────────────────────────────
class DrumPadView extends StatelessWidget {
  final PracticeEngine engine;
  const DrumPadView({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NavaTheme.background.withOpacity(0.92),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PadRow(pads: _kTopRow,    engine: engine, small: true),
          const SizedBox(height: 5),
          _PadRow(pads: _kMidRow,    engine: engine, small: true),
          const SizedBox(height: 5),
          _PadRow(pads: _kBottomRow, engine: engine, small: false),
        ],
      ),
    );
  }
}

// ── Single row ────────────────────────────────────────────────────────────────
class _PadRow extends StatelessWidget {
  final List<DrumPad>  pads;
  final PracticeEngine engine;
  final bool           small;
  const _PadRow({required this.pads, required this.engine, required this.small});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: pads.map((pad) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: _PadButton(pad: pad, engine: engine, small: small),
        ),
      )).toList(),
    );
  }
}

// ── Individual pad button ─────────────────────────────────────────────────────
class _PadButton extends StatefulWidget {
  final DrumPad        pad;
  final PracticeEngine engine;
  final bool           small;
  const _PadButton({required this.pad, required this.engine, required this.small});

  @override
  State<_PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<_PadButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 80));
    _scale = Tween<double>(begin: 1.0, end: 0.88)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _onTapDown(TapDownDetails _) {
    _ctrl.forward(from: 0);
    widget.engine.onScreenHit(widget.pad, velocity: 100);
  }

  void _onTapUp(TapUpDetails _)       => _ctrl.reverse();
  void _onTapCancel()                  => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    final color    = _padColor(widget.pad);
    final height   = widget.small ? 38.0 : 48.0;
    final fontSize = widget.small ? 8.0  : 10.0;

    return GestureDetector(
      onTapDown:   _onTapDown,
      onTapUp:     _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.55), width: 1.5),
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.12), blurRadius: 6),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.pad.shortName,
                style: TextStyle(
                  fontFamily:  'DrummerDisplay',
                  fontSize:    fontSize + 2,
                  fontWeight:  FontWeight.bold,
                  color:       color,
                ),
              ),
              Text(
                widget.pad.displayName.split(' ').first,
                style: TextStyle(
                  fontFamily: 'DrummerBody',
                  fontSize:   fontSize - 1,
                  color:      color.withOpacity(0.65),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
