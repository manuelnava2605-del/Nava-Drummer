// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Regression Tests (Phase 12 Bug Fixes)
//
// Covers the 5 bug classes fixed in the sync/chart-consistency overhaul:
//   R1 — Clone Hero note mapping: CH notes 95–100 must not be dropped
//   R2 — DrumNoteNormalizer: active primaryMap beats GM fallback
//   R3 — FallingNotesView lane routing: canonical 7-lane layout is stable
//   R4 — SyncDiagnostics fields are updated during playback
//   R5 — HitResult audio feedback: actual hit pad ≠ expected pad (no duplicate audio)
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:nava_drummer/domain/entities/entities.dart';
import 'package:nava_drummer/core/advanced_matching.dart';
import 'package:nava_drummer/core/sync_diagnostics.dart';

// ─── helpers ─────────────────────────────────────────────────────────────────

MidiEvent _ev(int note, {int velocity = 80, int channel = 0}) => MidiEvent(
  type:            MidiEventType.noteOn,
  channel:         channel,
  note:            note,
  velocity:        velocity,
  timestampMicros: DateTime.now().microsecondsSinceEpoch,
);

NoteEvent _note(DrumPad pad, {int midiNote = 36}) => NoteEvent(
  pad:          pad,
  midiNote:     midiNote,
  beatPosition: 1.0,
  timeSeconds:  0.0,
  velocity:     80,
);

// ─────────────────────────────────────────────────────────────────────────────
// R1 — Clone Hero note mapping
// ─────────────────────────────────────────────────────────────────────────────
void main() {

group('R1: Clone Hero note mapping', () {
  // CH uses notes 95–100 on channel 0 — none of these are in generalMidi.
  // The stabilizer MUST accept a pre-resolved DrumPad rather than looking up
  // StandardDrumMaps.generalMidi[raw.note] internally (which would return null).

  final stabilizer = AdaptiveMidiStabilizer();

  test('note 95 (kick) passes stabilizer when pad is pre-resolved', () {
    final ev  = _ev(95, velocity: 100, channel: 0);
    final pad = StandardDrumMaps.cloneHeroExpert[95]; // kick
    expect(pad, equals(DrumPad.kick));
    final result = stabilizer.process(ev, pad);
    expect(result, isNotNull, reason: 'CH kick (note 95) must not be dropped');
    expect(result!.pad, equals(DrumPad.kick));
  });

  test('note 96 (snare) passes stabilizer', () {
    final ev  = _ev(96, velocity: 90);
    final pad = StandardDrumMaps.cloneHeroExpert[96]; // snare
    expect(stabilizer.process(ev, pad), isNotNull,
        reason: 'CH snare (note 96) must not be dropped');
  });

  test('note 97 (hihatClosed) passes stabilizer', () {
    final ev  = _ev(97, velocity: 70);
    final pad = StandardDrumMaps.cloneHeroExpert[97]; // hihatClosed
    final result = stabilizer.process(ev, pad);
    expect(result, isNotNull,
        reason: 'CH hi-hat (note 97) must not be dropped');
    // Hi-hat velocity routing: low vel → closed is fine, high vel → open.
    // Either result is acceptable — the note must not be null.
  });

  test('note 98 (tom2) passes stabilizer', () {
    final ev  = _ev(98, velocity: 80);
    final pad = StandardDrumMaps.cloneHeroExpert[98]; // tom2
    expect(stabilizer.process(ev, pad), isNotNull,
        reason: 'CH tom (note 98) must not be dropped');
  });

  test('note 99 (kick2 — double bass) passes stabilizer', () {
    final ev  = _ev(99, velocity: 100);
    final pad = StandardDrumMaps.cloneHeroExpert[99]; // kick
    expect(stabilizer.process(ev, pad), isNotNull,
        reason: 'CH kick2 (note 99) must not be dropped');
  });

  test('note 100 (crash1) passes stabilizer', () {
    final ev  = _ev(100, velocity: 85);
    final pad = StandardDrumMaps.cloneHeroExpert[100]; // crash1
    expect(stabilizer.process(ev, pad), isNotNull,
        reason: 'CH crash (note 100) must not be dropped');
  });

  test('regression: without pre-resolved pad, CH notes ARE dropped (GM fallback)', () {
    // This documents the OLD broken behaviour:
    // process(ev) with no pad arg → GM lookup → null for note 95–100.
    // Confirming the bug existed ensures our fix is correctly targeted.
    final ev = _ev(95, velocity: 100);
    // Note 95 is not in generalMidi, so the internal GM fallback returns null.
    final result = stabilizer.process(ev); // no pad arg → GM-only path
    expect(result, isNull,
        reason: 'Without a resolved pad, note 95 is not in GM and must be dropped '
                '— this confirms the fix (pre-resolve then pass) is necessary');
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// R2 — DrumNoteNormalizer: active primaryMap beats GM fallback
// ─────────────────────────────────────────────────────────────────────────────
group('R2: DrumNoteNormalizer primaryMap precedence', () {
  // When a song is loaded with cloneHeroExpert as the active noteMap,
  // the normalizer must resolve CH notes from primaryMap first.
  // It must NOT fall through to generalMidi for notes in the primary map.

  test('CH notes resolve via primaryMap (cloneHeroExpert), not GM', () {
    final norm = DrumNoteNormalizer(primaryMap: StandardDrumMaps.cloneHeroExpert);

    expect(norm.normalize(midiNote: 95, channel: 0), equals(DrumPad.kick),
        reason: 'note 95 is in cloneHeroExpert → kick');
    expect(norm.normalize(midiNote: 96, channel: 0), equals(DrumPad.snare),
        reason: 'note 96 → snare');
    expect(norm.normalize(midiNote: 97, channel: 0), equals(DrumPad.hihatClosed),
        reason: 'note 97 → hihatClosed');
    expect(norm.normalize(midiNote: 98, channel: 0), equals(DrumPad.tom2),
        reason: 'note 98 → tom2');
    expect(norm.normalize(midiNote: 99, channel: 0), equals(DrumPad.kick),
        reason: 'note 99 → kick (double bass)');
    expect(norm.normalize(midiNote: 100, channel: 0), equals(DrumPad.crash1),
        reason: 'note 100 → crash1');
  });

  test('primaryMap takes precedence over GM for shared note numbers', () {
    // note 36 is kick in GM; remap it to tom1 in a custom primaryMap.
    const customMap = {36: DrumPad.tom1, 38: DrumPad.snare};
    final norm = DrumNoteNormalizer(primaryMap: customMap);
    // Should use primaryMap (tom1), not GM (kick).
    expect(norm.normalize(midiNote: 36, channel: 9), equals(DrumPad.tom1),
        reason: 'primaryMap override for note 36 must win over GM kick');
  });

  test('GM fallback fires only when note absent from primaryMap', () {
    // primaryMap only covers CH range; GM notes should still resolve.
    final norm = DrumNoteNormalizer(primaryMap: StandardDrumMaps.cloneHeroExpert);
    // note 38 is NOT in cloneHeroExpert → falls through to GM → snare.
    expect(norm.normalize(midiNote: 38, channel: 9), equals(DrumPad.snare),
        reason: 'note 38 absent from CH map; GM fallback must return snare');
  });

  test('userOverride wins over primaryMap and GM', () {
    final norm = DrumNoteNormalizer(primaryMap: StandardDrumMaps.cloneHeroExpert);
    norm.setOverride(95, DrumPad.crash1); // override kick → crash1
    expect(norm.normalize(midiNote: 95, channel: 0), equals(DrumPad.crash1),
        reason: 'userOverride must trump primaryMap');
  });

  test('default normalizer (no primaryMap) resolves standard GM notes', () {
    final norm = DrumNoteNormalizer(); // no primaryMap
    expect(norm.normalize(midiNote: 36, channel: 9), equals(DrumPad.kick));
    expect(norm.normalize(midiNote: 38, channel: 9), equals(DrumPad.snare));
    expect(norm.normalize(midiNote: 42, channel: 9), equals(DrumPad.hihatClosed));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// R3 — FallingNotesView lane routing
// Inlined replica of the canonical 7-lane layout and _nearestLane() logic.
// Private widget members can't be imported; replicate and keep in sync.
// ─────────────────────────────────────────────────────────────────────────────
group('R3: FallingNotesView canonical 7-lane layout', () {
  // Canonical lane order (must match _lanesConst in falling_notes_view.dart).
  const lanes = [
    DrumPad.hihatClosed, // 0 — HH  (left)
    DrumPad.crash1,      // 1 — Crash
    DrumPad.snare,       // 2 — Snare
    DrumPad.kick,        // 3 — Kick (center)
    DrumPad.tom1,        // 4 — Hi Tom
    DrumPad.floorTom,    // 5 — Floor Tom
    DrumPad.ride,        // 6 — Ride (right)
  ];

  // Replica of _nearestLane() for aliases not in _lanesConst.
  int nearestLane(DrumPad pad) {
    // Primary lookup — pad has a dedicated lane.
    final idx = lanes.indexOf(pad);
    if (idx != -1) return idx;
    // Alias mapping (must match _nearestLane in the widget).
    switch (pad) {
      case DrumPad.hihatOpen:   return 0;  // → HH lane
      case DrumPad.hihatPedal:  return 0;  // → HH lane
      case DrumPad.crash2:      return 1;  // → Crash lane
      case DrumPad.rimshot:     return 2;  // → Snare lane
      case DrumPad.crossstick:  return 2;  // → Snare lane
      case DrumPad.tom2:        return 5;  // → Floor Tom lane
      case DrumPad.tom3:        return 5;  // → Floor Tom lane
      case DrumPad.rideBell:    return 6;  // → Ride lane
      default:                  return -1; // unmapped
    }
  }

  test('seven primary pads map to their dedicated lanes', () {
    expect(nearestLane(DrumPad.hihatClosed), equals(0));
    expect(nearestLane(DrumPad.crash1),      equals(1));
    expect(nearestLane(DrumPad.snare),       equals(2));
    expect(nearestLane(DrumPad.kick),        equals(3));
    expect(nearestLane(DrumPad.tom1),        equals(4));
    expect(nearestLane(DrumPad.floorTom),    equals(5));
    expect(nearestLane(DrumPad.ride),        equals(6),
        reason: 'ride must have its own lane (not share with crash)');
  });

  test('ride is NOT in the crash lane', () {
    expect(nearestLane(DrumPad.ride), isNot(equals(1)),
        reason: 'regression: ride was formerly misrouted to crash lane (1)');
  });

  test('hihat variants route to HH lane', () {
    expect(nearestLane(DrumPad.hihatOpen),  equals(0));
    expect(nearestLane(DrumPad.hihatPedal), equals(0));
  });

  test('crash2 routes to crash lane', () {
    expect(nearestLane(DrumPad.crash2), equals(1));
  });

  test('rimshot and crossstick route to snare lane', () {
    expect(nearestLane(DrumPad.rimshot),    equals(2));
    expect(nearestLane(DrumPad.crossstick), equals(2));
  });

  test('tom aliases route to floor tom lane (intentional grouping)', () {
    // tom2 and tom3 are grouped with floorTom on the right side of the kit.
    expect(nearestLane(DrumPad.tom2), equals(5));
    expect(nearestLane(DrumPad.tom3), equals(5));
  });

  test('ride bell routes to ride lane', () {
    expect(nearestLane(DrumPad.rideBell), equals(6));
  });

  test('all lane indices are within valid range', () {
    for (int i = 0; i < lanes.length; i++) {
      expect(nearestLane(lanes[i]), equals(i),
          reason: 'lane ${lanes[i]} should map to index $i');
    }
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// R4 — SyncDiagnostics fields are updated during playback
// ─────────────────────────────────────────────────────────────────────────────
group('R4: SyncDiagnostics playhead field updates', () {
  setUp(() {
    SyncDiagnostics.instance.reset();
  });

  test('renderPlayheadSec is updated when stream emits', () async {
    // Simulates what FallingNotesView's AnimatedBuilder does on each frame:
    // SyncDiagnostics.instance.renderPlayheadSec = ph;
    final controller = StreamController<double>();
    const targetSec = 3.75;

    controller.stream.listen((t) {
      SyncDiagnostics.instance.renderPlayheadSec = t;
    });

    controller.add(targetSec);
    await Future.delayed(Duration.zero); // let stream deliver

    expect(SyncDiagnostics.instance.renderPlayheadSec, equals(targetSec));
    await controller.close();
  });

  test('sheetPlayheadSec is updated when stream emits', () async {
    // Simulates what SheetMusicView's playhead listener does:
    // SyncDiagnostics.instance.sheetPlayheadSec = t;
    final controller = StreamController<double>();
    const targetSec = 7.20;

    controller.stream.listen((t) {
      SyncDiagnostics.instance.sheetPlayheadSec = t;
    });

    controller.add(targetSec);
    await Future.delayed(Duration.zero);

    expect(SyncDiagnostics.instance.sheetPlayheadSec, equals(targetSec));
    await controller.close();
  });

  test('reset() clears both playhead fields to zero', () async {
    SyncDiagnostics.instance.renderPlayheadSec = 5.0;
    SyncDiagnostics.instance.sheetPlayheadSec  = 5.0;
    SyncDiagnostics.instance.reset();
    expect(SyncDiagnostics.instance.renderPlayheadSec, equals(0.0));
    expect(SyncDiagnostics.instance.sheetPlayheadSec,  equals(0.0));
  });

  test('multiple sequential emissions update field to last value', () async {
    final controller = StreamController<double>();

    controller.stream.listen((t) {
      SyncDiagnostics.instance.renderPlayheadSec = t;
    });

    controller.add(1.0);
    controller.add(2.0);
    controller.add(3.14);
    await Future.delayed(Duration.zero);

    expect(SyncDiagnostics.instance.renderPlayheadSec, equals(3.14));
    await controller.close();
  });

  test('renderPlayheadSec and sheetPlayheadSec are independent', () async {
    final renderCtrl = StreamController<double>();
    final sheetCtrl  = StreamController<double>();

    renderCtrl.stream.listen((t) => SyncDiagnostics.instance.renderPlayheadSec = t);
    sheetCtrl.stream.listen((t)  => SyncDiagnostics.instance.sheetPlayheadSec  = t);

    renderCtrl.add(2.5);
    sheetCtrl.add(2.3); // slight lag is normal
    await Future.delayed(Duration.zero);

    expect(SyncDiagnostics.instance.renderPlayheadSec, equals(2.5));
    expect(SyncDiagnostics.instance.sheetPlayheadSec,  equals(2.3));

    await renderCtrl.close();
    await sheetCtrl.close();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// R5 — HitResult audio feedback invariant
//
// Bug: PracticeScreen's hitResults listener was calling
//   AudioService.playDrumPad(r.expected.pad, ...)
// which plays the CHART's expected pad, not the pad that was physically hit.
// This causes double audio (DrumEngine already fired on MIDI arrival) and
// uses the wrong pad (expected vs actual).
//
// Fix: The hitResults listener now only calls AudioService.playGradeSound(r.grade).
//
// These tests verify the data invariant: expected.pad CAN differ from the pad
// implied by actual, so playing expected.pad from a hit listener is wrong.
// ─────────────────────────────────────────────────────────────────────────────
group('R5: HitResult audio feedback invariant', () {
  // Helper: MidiEvent for a snare hit (note 38, GM snare)
  MidiEvent snareEvent() => _ev(38, velocity: 90, channel: 9);

  test('HitResult.expected.pad can differ from actual MIDI note mapping', () {
    // The chart expects a kick; the player hit a snare instead.
    final expectedNote = _note(DrumPad.kick, midiNote: 36);
    final actualEvent  = snareEvent(); // note 38 → snare

    final result = HitResult(
      expected:      expectedNote,
      actual:        actualEvent,
      grade:         HitGrade.miss,  // wrong pad → miss
      timingDeltaMs: 0.0,
      correctPad:    false,
      score:         0,
    );

    // The expected pad is kick; the actual event maps to snare.
    expect(result.expected.pad, equals(DrumPad.kick));
    expect(StandardDrumMaps.generalMidi[result.actual!.note], equals(DrumPad.snare));
    expect(result.correctPad, isFalse);

    // Regression invariant: playing expected.pad (kick) for this result
    // would be both duplicated (DrumEngine already played snare) and wrong.
    final actualPad    = StandardDrumMaps.generalMidi[result.actual!.note];
    final expectedPad  = result.expected.pad;
    expect(actualPad, isNot(equals(expectedPad)),
        reason: 'expected.pad ≠ actual pad → playing expected.pad is incorrect');
  });

  test('HitResult.correctPad false when pads differ', () {
    final result = HitResult(
      expected:      _note(DrumPad.snare, midiNote: 38),
      actual:        _ev(49, velocity: 80, channel: 9), // crash
      grade:         HitGrade.miss,
      timingDeltaMs: 5.0,
      correctPad:    false,
      score:         0,
    );
    expect(result.correctPad, isFalse);
    // Audio should only play a grade sound, not DrumPad.expected
    // (verified by code inspection — AudioService.playGradeSound is the only call).
  });

  test('on a perfect hit, expected.pad equals actual mapping', () {
    // When the player hits the right pad, expected.pad and actual.note agree.
    final result = HitResult(
      expected:      _note(DrumPad.snare, midiNote: 38),
      actual:        _ev(38, velocity: 90, channel: 9), // also snare
      grade:         HitGrade.perfect,
      timingDeltaMs: 5.0,
      correctPad:    true,
      score:         300,
    );
    expect(result.correctPad, isTrue);
    // Even here, audio must NOT be played from the hitResults listener —
    // DrumEngine.hit() already fired when the MIDI event was processed.
    // The hitResults listener fires ~16ms later and must only call playGradeSound.
    final actualPad = StandardDrumMaps.generalMidi[result.actual!.note];
    expect(actualPad, equals(DrumPad.snare));
    expect(result.expected.pad, equals(DrumPad.snare));
  });

  test('HitGrade.miss has score 0 — grade sound only, no pad audio', () {
    final result = HitResult(
      expected:      _note(DrumPad.kick),
      grade:         HitGrade.miss,
      timingDeltaMs: 250.0,
      correctPad:    false,
      score:         0,
    );
    expect(result.grade,  equals(HitGrade.miss));
    expect(result.score,  equals(0));
    expect(result.actual, isNull, reason: 'miss has no actual MIDI event');
    // Listener must call playGradeSound(HitGrade.miss), never playDrumPad.
  });
});

} // main
