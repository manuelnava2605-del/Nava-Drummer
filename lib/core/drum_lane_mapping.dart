import '../domain/entities/entities.dart';

const List<DrumPad> kDrumLanes = [
  DrumPad.hihatClosed,
  DrumPad.crash1,
  DrumPad.snare,
  DrumPad.kick,
  DrumPad.tom1,
  DrumPad.floorTom,
  DrumPad.ride,
];

const List<String> kDrumLaneNames = [
  'HH', 'CRASH', 'SNARE', 'KICK', 'TOM', 'FLOOR', 'RIDE',
];

int drumLaneIndex(DrumPad pad) {
  final idx = kDrumLanes.indexOf(pad);
  if (idx != -1) return idx;
  switch (pad) {
    case DrumPad.hihatOpen:   return 0;
    case DrumPad.hihatPedal:  return 0;
    case DrumPad.crash2:      return 1;
    case DrumPad.rimshot:     return 2;
    case DrumPad.crossstick:  return 2;
    case DrumPad.tom2:        return 5;
    case DrumPad.tom3:        return 5;
    case DrumPad.rideBell:    return 6;
    default:                  return -1;
  }
}
