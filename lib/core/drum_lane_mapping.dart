import '../domain/entities/entities.dart';

// ── Lane order (left → right on screen) ───────────────────────────────────────
// Standard 5-piece kit with cymbals:
//   HH | CRASH | SNARE | KICK | TOM1 | TOM2 | FLOOR | RIDE
const List<DrumPad> kDrumLanes = [
  DrumPad.hihatClosed, // 0 — HH
  DrumPad.crash1,      // 1 — CRASH
  DrumPad.snare,       // 2 — SNARE
  DrumPad.kick,        // 3 — KICK
  DrumPad.tom1,        // 4 — TOM1
  DrumPad.tom2,        // 5 — TOM2
  DrumPad.floorTom,    // 6 — FLOOR
  DrumPad.ride,        // 7 — RIDE
];

const List<String> kDrumLaneNames = [
  'HH', 'CRASH', 'SNARE', 'KICK', 'T1', 'T2', 'FLOOR', 'RIDE',
];

/// Returns the visual lane index for [pad].
/// Pads that share a column (e.g. hihatOpen → HH, crash2 → CRASH) are
/// mapped via the fallback switch below.
int drumLaneIndex(DrumPad pad) {
  final idx = kDrumLanes.indexOf(pad);
  if (idx != -1) return idx;
  switch (pad) {
    case DrumPad.hihatOpen:   return 0; // HH
    case DrumPad.hihatPedal:  return 0; // HH
    case DrumPad.crash2:      return 1; // CRASH
    case DrumPad.rimshot:     return 2; // SNARE
    case DrumPad.crossstick:  return 2; // SNARE
    case DrumPad.tom3:        return 6; // FLOOR (no dedicated T3 lane)
    case DrumPad.rideBell:    return 7; // RIDE
    default:                  return -1;
  }
}
