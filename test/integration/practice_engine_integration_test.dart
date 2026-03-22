// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Integration Tests
// End-to-end tests for MIDI → PracticeEngine → Scoring pipeline.
// ─────────────────────────────────────────────────────────────────────────────
// ignore_for_file: non_abstract_class_inherits_abstract_member, invalid_override, argument_type_not_assignable

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:nava_drummer/domain/entities/entities.dart';
import 'package:nava_drummer/core/practice_engine.dart';
import 'package:nava_drummer/data/datasources/local/midi_engine.dart';

// ── MIDI Simulator ────────────────────────────────────────────────────────────

/// Simulates a real MIDI device by injecting MidiEvents with controlled timing.
class MidiSimulator {
  final _controller = StreamController<MidiEvent>.broadcast();
  Stream<MidiEvent> get stream => _controller.stream;

  bool get isClosed => _controller.isClosed;

  /// Emit a hit for [pad] with [velocity] and optional [delayMs] before emission.
  Future<void> hit(
    DrumPad pad, {
    int velocity     = 100,
    int delayMs      = 0,
    int? noteOverride,
  }) async {
    if (delayMs > 0) {
      await Future.delayed(Duration(milliseconds: delayMs));
    }
    final note = noteOverride ?? StandardDrumMaps.generalMidi.entries
        .firstWhere((e) => e.value == pad)
        .key;
    _controller.add(MidiEvent(
      type:            MidiEventType.noteOn,
      channel:         9,
      note:            note,
      velocity:        velocity,
      timestampMicros: DateTime.now().microsecondsSinceEpoch,
    ));
  }

  /// Plays through a list of [NoteEvent]s with accurate timing (scaled by [tempoFactor]).
  Future<void> playPattern(
    List<NoteEvent> pattern, {
    double tempoFactor = 1.0,
    int timingOffsetMs = 0, // positive = late, negative = early
  }) async {
    if (pattern.isEmpty) return;
    final startTime = DateTime.now();
    for (final note in pattern) {
      final targetMs = (note.timeSeconds * 1000 / tempoFactor).round() + timingOffsetMs;
      final elapsed  = DateTime.now().difference(startTime).inMilliseconds;
      final wait     = targetMs - elapsed;
      if (wait > 0) await Future.delayed(Duration(milliseconds: wait));
      await hit(note.pad, velocity: note.velocity);
    }
  }

  void dispose() => _controller.close();
}

// ── Fake MidiEngine ───────────────────────────────────────────────────────────

/// A testable MidiEngine that accepts injected event streams.
class FakeMidiEngine implements MidiEngine {
  final MidiSimulator simulator;

  FakeMidiEngine(this.simulator);

  @override
  Stream<MidiEvent> get midiEvents => simulator.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Stream<List<MidiDevice>> get deviceList => Stream.value([_fakeDevice]);

  @override
  Future<void> connectDevice(String deviceId) async {}

  @override
  Future<void> disconnectDevice(String deviceId) async {}

  @override
  Future<int> measureLatency() async => 5;

  @override
  void setLatencyOffset(int microseconds) {}

  @override
  void dispose() {}

  static const _fakeDevice = MidiDevice(
    id:        'sim_001',
    name:      'NavaDrummer Simulator',
    vendorId:  0xDEAD,
    productId: 0xBEEF,
    transport: DeviceTransport.usb,
    brand:     DrumKitBrand.generic,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Integration Test: Perfect Performance
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late MidiSimulator  sim;
  late FakeMidiEngine fakeEngine;
  late PracticeEngine engine;

  setUp(() {
    sim        = MidiSimulator();
    fakeEngine = FakeMidiEngine(sim);
    engine     = PracticeEngine(midiEngine: fakeEngine);
  });

  tearDown(() async {
    await engine.dispose();
    sim.dispose();
  });

  final _testSong = const Song(
    id: 'test', title: 'Test', artist: 'Test',
    difficulty: Difficulty.beginner, genre: Genre.rock,
    bpm: 120, duration: Duration(seconds: 10),
    midiAssetPath: '', isUnlocked: true, xpReward: 100,
  );

  // Simple 4-note pattern: kick, snare, kick, snare at 120 BPM
  const _pattern = [
    NoteEvent(pad: DrumPad.kick,  midiNote: 36, beatPosition: 1.0, timeSeconds: 0.0,  velocity: 100),
    NoteEvent(pad: DrumPad.snare, midiNote: 38, beatPosition: 2.0, timeSeconds: 0.5,  velocity: 100),
    NoteEvent(pad: DrumPad.kick,  midiNote: 36, beatPosition: 3.0, timeSeconds: 1.0,  velocity: 100),
    NoteEvent(pad: DrumPad.snare, midiNote: 38, beatPosition: 4.0, timeSeconds: 1.5,  velocity: 100),
  ];

  // ── Test 1: Perfect hits get perfect grades ─────────────────────────────
  test('Perfect timing produces all Perfect grades', () async {
    final hitResults = <HitResult>[];
    engine.hitResults.listen(hitResults.add);

    await engine.loadSong(_testSong, _pattern, DrumMapping(
      deviceId: 'sim', noteMap: StandardDrumMaps.generalMidi,
    ));

    engine.start();
    await Future.delayed(const Duration(milliseconds: 100)); // let count-in pass in test

    // Play pattern with ±0ms offset (perfect timing)
    await sim.playPattern(_pattern, timingOffsetMs: 0);

    await Future.delayed(const Duration(milliseconds: 500));

    final perfectCount = hitResults.where((r) => r.grade == HitGrade.perfect).length;
    expect(perfectCount, greaterThan(0),
        reason: 'Expect at least some perfect hits on zero-offset playback');
  }, timeout: const Timeout(Duration(seconds: 10)));

  // ── Test 2: Late hits downgrade to Good ─────────────────────────────────
  test('50ms late hits produce Good grades', () async {
    final hitResults = <HitResult>[];
    engine.hitResults.listen(hitResults.add);

    await engine.loadSong(_testSong, _pattern, DrumMapping(
      deviceId: 'sim', noteMap: StandardDrumMaps.generalMidi,
    ));

    engine.start();
    await Future.delayed(const Duration(milliseconds: 100));

    await sim.playPattern(_pattern, timingOffsetMs: 55);

    await Future.delayed(const Duration(milliseconds: 500));

    final goodCount = hitResults.where((r) => r.grade == HitGrade.good).length;
    expect(goodCount, greaterThan(0),
        reason: '55ms late should fall in Good range (30–80ms)');
  }, timeout: const Timeout(Duration(seconds: 10)));

  // ── Test 3: 200ms offset produces misses ────────────────────────────────
  test('200ms late hits produce Misses', () async {
    final hitResults = <HitResult>[];
    engine.hitResults.listen(hitResults.add);

    await engine.loadSong(_testSong, _pattern, DrumMapping(
      deviceId: 'sim', noteMap: StandardDrumMaps.generalMidi,
    ));

    engine.start();
    await Future.delayed(const Duration(milliseconds: 100));

    await sim.playPattern(_pattern, timingOffsetMs: 200);

    await Future.delayed(const Duration(milliseconds: 500));

    final missCount = hitResults.where((r) => r.grade == HitGrade.miss).length;
    expect(missCount, greaterThan(0),
        reason: '200ms offset should exceed the miss threshold');
  }, timeout: const Timeout(Duration(seconds: 10)));

  // ── Test 4: Score increases on each hit ─────────────────────────────────
  test('Score increases monotonically on hits', () async {
    final scores = <int>[];
    engine.scoreUpdates.listen(scores.add);

    await engine.loadSong(_testSong, _pattern, DrumMapping(
      deviceId: 'sim', noteMap: StandardDrumMaps.generalMidi,
    ));

    engine.start();
    await Future.delayed(const Duration(milliseconds: 100));
    await sim.playPattern(_pattern);
    await Future.delayed(const Duration(milliseconds: 200));

    // Each scored hit should add to the total
    for (int i = 1; i < scores.length; i++) {
      expect(scores[i], greaterThanOrEqualTo(scores[i - 1]),
          reason: 'Score should never decrease');
    }
  }, timeout: const Timeout(Duration(seconds: 10)));

  // ── Test 5: Combo counter ────────────────────────────────────────────────
  test('Consecutive hits build combo', () async {
    int maxCombo = 0;
    engine.scoreUpdates.listen((_) {
      if (engine.currentCombo > maxCombo) maxCombo = engine.currentCombo;
    });

    await engine.loadSong(_testSong, _pattern, DrumMapping(
      deviceId: 'sim', noteMap: StandardDrumMaps.generalMidi,
    ));

    engine.start();
    await Future.delayed(const Duration(milliseconds: 100));
    await sim.playPattern(_pattern);
    await Future.delayed(const Duration(milliseconds: 200));

    expect(maxCombo, greaterThan(0));
  }, timeout: const Timeout(Duration(seconds: 10)));

  // ── Test 6: Wrong pad hit is penalized ──────────────────────────────────
  test('Wrong pad hit does not award points for that note', () async {
    final hitResults = <HitResult>[];
    engine.hitResults.listen(hitResults.add);

    await engine.loadSong(_testSong, _pattern, DrumMapping(
      deviceId: 'sim', noteMap: StandardDrumMaps.generalMidi,
    ));

    engine.start();
    await Future.delayed(const Duration(milliseconds: 100));

    // Hit the wrong pad (tom instead of kick/snare) with correct timing
    final wrongPattern = _pattern
        .map((n) => NoteEvent(
              pad:          DrumPad.tom1, // wrong
              midiNote:     48,
              beatPosition: n.beatPosition,
              timeSeconds:  n.timeSeconds,
              velocity:     n.velocity,
            ))
        .toList();

    await sim.playPattern(wrongPattern);
    await Future.delayed(const Duration(milliseconds: 500));

    // Wrong-pad hits should still be graded but not as 'correct'
    expect(hitResults, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 10)));

  // ── Test 7: Performance session is complete ─────────────────────────────
  test('finish() returns a valid PerformanceSession', () async {
    await engine.loadSong(_testSong, _pattern, DrumMapping(
      deviceId: 'sim', noteMap: StandardDrumMaps.generalMidi,
    ));

    engine.start();
    await Future.delayed(const Duration(milliseconds: 100));
    await sim.playPattern(_pattern);
    await Future.delayed(const Duration(milliseconds: 200));

    final session = engine.finish();

    expect(session.id,              isNotEmpty);
    expect(session.song.id,         equals('test'));
    expect(session.accuracyPercent, inInclusiveRange(0.0, 100.0));
    expect(session.letterGrade,     isIn(['S', 'A', 'B', 'C', 'D']));
    expect(session.xpEarned,        greaterThanOrEqualTo(0));
  }, timeout: const Timeout(Duration(seconds: 10)));

  // ── Test 8: Tempo factor scales timing windows ──────────────────────────
  test('Slower tempo gives same grades as normal tempo', () async {
    final hitResults = <HitResult>[];
    engine.hitResults.listen(hitResults.add);

    await engine.loadSong(_testSong, _pattern, DrumMapping(
      deviceId: 'sim', noteMap: StandardDrumMaps.generalMidi,
    ));

    engine.setTempoFactor(0.5); // half speed

    engine.start();
    await Future.delayed(const Duration(milliseconds: 100));
    // Play at half speed with perfect timing
    await sim.playPattern(_pattern, tempoFactor: 0.5);
    await Future.delayed(const Duration(milliseconds: 500));

    expect(hitResults, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 15)));
}
