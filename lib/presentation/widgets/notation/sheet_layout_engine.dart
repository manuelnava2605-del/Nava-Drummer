// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Sheet Layout Engine
// Converts a list of NotationNotes + current playhead position into a
// SheetRenderModel that the painter can draw directly.
//
// Coordinate system (screen):
//   X  — increases rightward.  Notes to the RIGHT of the playhead are in the future.
//   Y  — increases downward.   Higher staff positions → smaller Y values.
//
// Scroll model:
//   The playhead is fixed at playheadX (28 % of screen width).
//   Notes slide from right to left as time advances.
//   noteX = playheadX + (noteTime - currentTime) * pixelsPerSecond
// ─────────────────────────────────────────────────────────────────────────────
import 'notation_models.dart';
import '../../../domain/entities/entities.dart';

class SheetLayoutEngine {
  /// How many pixels represent one second of audio at 100 % zoom.
  final double pixelsPerSecond;

  /// Window (in seconds) shown before the playhead (past notes).
  final double lookBehind;

  /// Window (in seconds) shown after the playhead (future notes).
  final double lookAhead;

  const SheetLayoutEngine({
    this.pixelsPerSecond = 240.0,
    this.lookBehind      = 1.5,
    this.lookAhead       = 8.0,
  });

  // ── Coordinate helpers ────────────────────────────────────────────────────

  double _noteX(double noteTime, double currentTime, double playheadX) =>
      playheadX + (noteTime - currentTime) * pixelsPerSecond;

  /// Convert a staffLine value to a screen Y coordinate.
  /// staffLine 0 = bottom staff line, 4 = top staff line.
  /// Y decreases as staffLine increases (higher pitch = higher on screen).
  double _noteY(double staffLine, double staffTop, double lineSpacing) =>
      staffTop + (4.0 - staffLine) * lineSpacing;

  // ── Note value from gap + BPM ─────────────────────────────────────────────

  /// Convert a time gap (seconds) to the nearest standard note value.
  /// Uses mid-point thresholds between consecutive standard values.
  static NoteValueType noteValueFromGap(double gapSeconds, double bpm) {
    if (bpm <= 0) return NoteValueType.eighth;
    final beats = gapSeconds * bpm / 60.0;
    if (beats >= 3.0)   return NoteValueType.whole;
    if (beats >= 1.5)   return NoteValueType.half;
    if (beats >= 0.75)  return NoteValueType.quarter;
    if (beats >= 0.375) return NoteValueType.eighth;
    if (beats >= 0.1875) return NoteValueType.sixteenth;
    if (beats >= 0.09375) return NoteValueType.thirtySecond;
    return NoteValueType.sixtyFourth;
  }

  // ── Main layout ───────────────────────────────────────────────────────────

  SheetRenderModel layout({
    required List<NotationNote> notes,
    required double currentTime,
    required double playheadX,
    required double staffTop,
    required double lineSpacing,
    required double bpm,
    required int    beatsPerBar,
    required double screenWidth,
    required Set<DrumPad> recentlyHit,
  }) {
    final secPerBeat = 60.0 / bpm;
    final secPerBar  = secPerBeat * beatsPerBar;

    final minTime = currentTime - lookBehind;
    final maxTime = currentTime + lookAhead;

    // ── Lay out visible notes ─────────────────────────────────────────────
    final laidOut = <LaidOutNote>[];

    // Binary search for first note in range (notes are sorted by time)
    int lo = 0, hi = notes.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (notes[mid].timeSeconds < minTime) lo = mid + 1; else hi = mid;
    }
    for (int i = lo; i < notes.length; i++) {
      final n = notes[i];
      if (n.timeSeconds > maxTime) break;
      final x         = _noteX(n.timeSeconds, currentTime, playheadX);
      final y         = _noteY(n.staffLine,   staffTop,    lineSpacing);
      final highlighted = recentlyHit.contains(n.pad) &&
          (n.timeSeconds - currentTime).abs() < 0.20;
      final noteValue = noteValueFromGap(n.gapToNextSeconds, bpm);
      laidOut.add(LaidOutNote(
        note:        n,
        x:           x,
        y:           y,
        highlighted: highlighted,
        noteValue:   noteValue,
      ));
    }

    // ── Chord groups (notes within 6 ms of each other) ───────────────────
    const chordEpsilon = 0.006; // seconds
    final chordGroups = <List<int>>[];
    {
      int start = 0;
      while (start < laidOut.length) {
        final t0  = laidOut[start].note.timeSeconds;
        int   end = start + 1;
        while (end < laidOut.length &&
               laidOut[end].note.timeSeconds - t0 <= chordEpsilon) {
          end++;
        }
        if (end - start >= 2) {
          chordGroups.add(List.generate(end - start, (k) => start + k));
        }
        start = end;
      }
    }

    // ── Beam groups (up-stem eighth/16th notes in the same beat) ──────────
    // Only beam notes that have noteValue ≤ eighth (i.e. flagCount ≥ 1).
    final beamGroups = <List<int>>[];
    if (secPerBeat > 0) {
      final beatMap = <int, List<int>>{};
      for (int k = 0; k < laidOut.length; k++) {
        final n = laidOut[k];
        if (!n.note.stemUp) continue;
        if (n.noteValue.flagCount < 1) continue; // only beam eighth notes and shorter
        final beatIdx = (n.note.timeSeconds / secPerBeat).floor();
        beatMap.putIfAbsent(beatIdx, () => []).add(k);
      }
      final sortedKeys = beatMap.keys.toList()..sort();
      for (final key in sortedKeys) {
        final group = beatMap[key]!;
        if (group.length >= 2) beamGroups.add(group);
      }
    }

    // ── Bar lines ─────────────────────────────────────────────────────────
    final barLineXs  = <double>[];
    final beatLineXs = <double>[];

    if (secPerBar > 0) {
      final firstBar = (minTime / secPerBar).floor();
      for (int i = firstBar; ; i++) {
        final t = i * secPerBar;
        if (t > maxTime) break;
        barLineXs.add(_noteX(t, currentTime, playheadX));
      }
    }

    if (secPerBeat > 0) {
      final firstBeat = (minTime / secPerBeat).floor();
      for (int i = firstBeat; ; i++) {
        final t = i * secPerBeat;
        if (t > maxTime) break;
        final x = _noteX(t, currentTime, playheadX);
        // Omit positions that already have a bar line (within 2 px)
        if (!barLineXs.any((bx) => (bx - x).abs() < 2.0)) {
          beatLineXs.add(x);
        }
      }
    }

    final currentBar = secPerBar > 0
        ? (currentTime / secPerBar).floor() + 1
        : 1;

    return SheetRenderModel(
      notes:              laidOut,
      playheadX:          playheadX,
      staffTop:           staffTop,
      lineSpacing:        lineSpacing,
      barLineXs:          barLineXs,
      beatLineXs:         beatLineXs,
      currentBar:         currentBar,
      timeSigNumerator:   beatsPerBar,
      timeSigDenominator: 4,
      chordGroups:        chordGroups,
      beamGroups:         beamGroups,
    );
  }
}
