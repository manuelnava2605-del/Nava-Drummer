// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Context-Aware Note Matching  (Phase 1 — Full Upgrade)
// + MIDI Stabilization                       (Phase 5 — Adaptive)
// + DrumNoteNormalizer                       (Phase 3 support)
//
// NEW in this version:
//   w_s  sequencePenalty  — penalises skipping expected order
//   w_h  historyPenalty   — biases toward user's established pattern
//   Asymmetric sliding window ±150ms explicit
//   Adaptive debounce f(velocity, padType)
//   Ghost note filter using pattern context
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:collection';
import 'dart:math' as math;
import '../domain/entities/entities.dart';
import 'global_timing_controller.dart';

export 'global_timing_controller.dart' show
    MathTimingEngine, TimingGrade, TimingBias, TimingTrend,
    TimingAnalysis, GlobalTimingController;


// ═══════════════════════════════════════════════════════════════════════════
// PHASE 1 — Context-Aware Probabilistic Note Matcher
// ═══════════════════════════════════════════════════════════════════════════

/// Full 4-component cost function:
///
///   C(i,j) = w_t·|t_i−t_j| + w_p·padMismatch + w_s·sequencePenalty(j)
///            + w_h·historyPenalty(j)
///
/// Context state (last matched note, history bias) persists across the session
/// and is updated on every successful match.
class ContextAwareMatcher {

  // ── Cost weights ──────────────────────────────────────────────────────────
  static const double wTiming   = 1.0;   // w_t: primary timing
  static const double wPad      = 75.0;  // w_p: wrong pad (hard penalty)
  static const double wSequence = 12.0;  // w_s: sequence disorder (new)
  static const double wHistory  = 8.0;   // w_h: against established pattern (new)
  static const double wVelocity = 0.12;  // w_v: velocity mismatch (soft)

  // ── Sliding window ────────────────────────────────────────────────────────
  // ±150ms around current playhead — explicit per spec
  static const double windowBackMs  = 150.0;  // look-behind
  static const double windowFrontMs = 150.0;  // look-ahead

  // ── Flam / chord ──────────────────────────────────────────────────────────
  static const double flamWindowMs  = 30.0;
  static const double chordWindowMs = 15.0;

  // ── Context state (persists across session) ───────────────────────────────
  final MathTimingEngine _timing;

  int?           _lastMatchedIdx;       // index of last matched note in full list
  DrumPad?       _lastMatchedPad;
  double?        _lastMatchedMs;

  // History: for each pad, sliding buffer of last 8 time-deltas to that pad
  final Map<DrumPad, Queue<double>> _padHistory = {};

  // Match count per pad (for history penalty weight)
  final Map<DrumPad, int> _padMatchCount = {};

  // Recent hits for flam detection
  final List<RecentHit> _recentHits = [];

  ContextAwareMatcher(this._timing);

  // ══════════════════════════════════════════════════════════════════════════
  // MAIN MATCH METHOD
  // ══════════════════════════════════════════════════════════════════════════

  /// Match a live hit against the pending note queue.
  /// Updates internal context state on success.
  MatchResult match({
    required int           hitTimestampUs,
    required DrumPad       hitPad,
    required int           hitVelocity,
    required List<PendingNote> pendingNotes,
    required double        playheadMs,
  }) {
    final hitMs = hitTimestampUs / 1000.0;

    // ── 1. Build sliding window W = notes within ±150ms of playhead ──────────
    final candidates = <int>[];
    for (int i = 0; i < pendingNotes.length; i++) {
      final p = pendingNotes[i];
      if (p.matched) continue;
      final dt = p.expectedMs - playheadMs;
      if (dt < -windowBackMs)  continue;   // too far behind
      if (dt >  windowFrontMs) break;       // sorted, can stop
      candidates.add(i);
    }

    if (candidates.isEmpty) {
      return MatchResult.extra(hitPad: hitPad, hitMs: hitMs, velocity: hitVelocity);
    }

    // ── 2. Evaluate C(i,j) for ALL j in W ────────────────────────────────────
    double bestCost = double.infinity;
    int    bestIdx  = -1;

    for (final idx in candidates) {
      final note    = pendingNotes[idx];
      final deltaMs = hitMs - note.expectedMs;
      final cost    = _fullCost(idx, note, deltaMs, hitPad, hitVelocity, pendingNotes);
      if (cost < bestCost) { bestCost = bestCost == double.infinity ? cost : bestCost;
        bestCost = cost; bestIdx = idx; }
    }

    // ── 3. Apply match ────────────────────────────────────────────────────────
    final matched = pendingNotes[bestIdx];
    matched.matched = true;
    final deltaMs  = hitMs - matched.expectedMs;
    final grade    = _timing.grade(deltaMs);
    final scored   = hitPad == matched.pad;

    // Update context
    _updateContext(bestIdx, matched.pad, hitMs, deltaMs, hitVelocity);

    // Update recent hits for flam detection
    _recentHits.add(RecentHit(pad: hitPad, timestampMs: hitMs));
    if (_recentHits.length > 10) _recentHits.removeAt(0);

    return MatchResult(
      expectedNote: matched.note,
      hitMs:        hitMs,
      deltaMs:      deltaMs,
      cost:         bestCost,
      padMatch:     scored,
      hitVelocity:  hitVelocity,
      grade:        grade,
      score:        scored ? _timing.hitScore(deltaMs) : 0,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FULL COST FUNCTION  C(i,j) = w_t + w_p + w_s + w_h + w_v
  // ══════════════════════════════════════════════════════════════════════════

  double _fullCost(
    int idx,
    PendingNote note,
    double deltaMs,
    DrumPad hitPad,
    int hitVelocity,
    List<PendingNote> all,
  ) {
    // w_t: timing component
    final timingCost = wTiming * deltaMs.abs();

    // w_p: pad mismatch
    final padCost = wPad * (hitPad == note.pad ? 0.0 : 1.0);

    // w_v: velocity deviation (normalised 0-127)
    final velCost = wVelocity * (hitVelocity - note.velocity).abs().toDouble();

    // w_s: sequence penalty — how far from the "next expected" note is this?
    final seqCost = _sequencePenalty(idx, note, all);

    // w_h: history penalty — does this note deviate from user's pattern?
    final histCost = _historyPenalty(note, deltaMs);

    return timingCost + padCost + velCost + seqCost + histCost;
  }

  // ── w_s: Sequence penalty ─────────────────────────────────────────────────
  /// Penalises matching a note that is far from the expected next position.
  /// If last matched was at index k, the "ideal" next note is at k+1.
  /// Matching a note further away (k+3, k+5...) costs proportionally more.
  double _sequencePenalty(int idx, PendingNote note, List<PendingNote> all) {
    if (_lastMatchedIdx == null) return 0; // no context yet

    // Find where idx sits relative to last match
    int gapForward = idx - _lastMatchedIdx!;
    if (gapForward <= 0) gapForward = 0; // shouldn't go backward

    // Ideal: gap = 1 (next note in sequence) → no penalty
    // Gap of 2 → small penalty, gap of 5+ → large penalty
    if (gapForward <= 1) return 0;
    return wSequence * math.log(gapForward.toDouble());
  }

  // ── w_h: History penalty ──────────────────────────────────────────────────
  /// If the user has established a pattern of hitting this pad with a
  /// consistent timing bias, reward notes close to that bias and penalise
  /// notes that would require a very different timing.
  double _historyPenalty(PendingNote note, double candidateDeltaMs) {
    final history = _padHistory[note.pad];
    if (history == null || history.length < 4) return 0;

    // User's typical delta for this pad
    final typicalDelta = history.reduce((a, b) => a + b) / history.length;

    // If the candidate's timing matches user's tendency, reward it (low cost)
    final deviation = (candidateDeltaMs - typicalDelta).abs();
    if (deviation < 10) return 0;           // matches habit → no penalty
    if (deviation < 30) return wHistory * 0.3;
    return wHistory * (deviation / 100).clamp(0, 1.0);
  }

  // ── Context update ────────────────────────────────────────────────────────
  void _updateContext(int idx, DrumPad pad, double hitMs, double deltaMs, int vel) {
    _lastMatchedIdx = idx;
    _lastMatchedPad = pad;
    _lastMatchedMs  = hitMs;

    // Update pad history (rolling buffer of 8)
    final buf = _padHistory.putIfAbsent(pad, () => Queue<double>());
    buf.addLast(deltaMs);
    if (buf.length > 8) buf.removeFirst();

    _padMatchCount[pad] = (_padMatchCount[pad] ?? 0) + 1;
  }

  // ── Flam detection ────────────────────────────────────────────────────────
  bool isFlamGhost(double hitMs, DrumPad pad) {
    final cutoff = hitMs - flamWindowMs;
    for (final r in _recentHits.reversed) {
      if (r.timestampMs < cutoff) break;
      if (r.pad == pad) return true;
    }
    return false;
  }

  // ── Dynamic window expansion for fills ────────────────────────────────────
  double dynamicWindowMs(List<PendingNote> pending, double baseMs) {
    if (pending.length < 3) return baseMs;
    double minInterval = double.infinity;
    for (int i = 0; i < math.min(3, pending.length - 1); i++) {
      if (pending[i + 1].expectedMs - pending[i].expectedMs < minInterval) {
        minInterval = pending[i + 1].expectedMs - pending[i].expectedMs;
      }
    }
    if (minInterval < 50) return baseMs * 1.3;  // very fast fill
    if (minInterval < 80) return baseMs * 1.15; // fast fill
    return baseMs;
  }

  void resetContext() {
    _lastMatchedIdx = null;
    _lastMatchedPad = null;
    _lastMatchedMs  = null;
    _padHistory.clear();
    _padMatchCount.clear();
    _recentHits.clear();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PHASE 2 — Perceptual Timing Engine (wraps MathTimingEngine)
// ═══════════════════════════════════════════════════════════════════════════

/// Applies human-perception corrections on top of mathematical timing:
///
///   1. BPM-based tolerance scaling:
///        BPM > 140  →  +15% tolerance (notes blur at high speed)
///        BPM < 80   →  −10% tolerance (slow songs need precision)
///
///   2. Asymmetric window:
///        earlyWindow = 0.80 × base  (humans tolerate early less)
///        lateWindow  = 1.20 × base  (humans tolerate late more)
///
///   3. Groove compensation via inherited swing support
class PerceptualTimingEngine extends MathTimingEngine {
  // ── Perceptual constants ──────────────────────────────────────────────────
  static const double _earlyFactor  = 0.80; // tighter for early hits
  static const double _lateFactor   = 1.20; // more lenient for late hits
  static const double _highBpmBonus = 0.15; // extra tolerance above 140 BPM
  static const double _lowBpmCut    = 0.10; // tighter below 80 BPM

  /// Perceptual multiplier derived from BPM
  final double _bpmTolerance;

  PerceptualTimingEngine({
    required super.bpm,
    super.skillFactor,
    super.swingRatio,
  }) : _bpmTolerance = _computeBpmTolerance(bpm);

  static double _computeBpmTolerance(int bpm) {
    if (bpm > 140) return 1.0 + _highBpmBonus * ((bpm - 140) / 60).clamp(0, 1);
    if (bpm < 80)  return 1.0 - _lowBpmCut   * ((80 - bpm)  / 40).clamp(0, 1);
    return 1.0;
  }

  // ── Asymmetric grade ──────────────────────────────────────────────────────

  @override
  TimingGrade grade(double deltaMs) {
    // Apply asymmetric scaling: negative=early, positive=late
    final scaled = deltaMs < 0
        ? deltaMs / _earlyFactor   // early hits → tighter window
        : deltaMs / _lateFactor;   // late hits  → wider window

    // Apply BPM tolerance on top
    final effective = scaled / _bpmTolerance;

    final abs = effective.abs();
    if (abs <= windowPerfectMs) return TimingGrade.perfect;
    if (abs <= windowGoodMs)    return TimingGrade.good;
    if (abs <= windowOkayMs)    return deltaMs < 0 ? TimingGrade.early : TimingGrade.late;
    return TimingGrade.miss;
  }

  /// Asymmetric window accessor (used by UI display)
  double get earlyWindowMs  => windowPerfectMs * _earlyFactor * _bpmTolerance;
  double get lateWindowMs   => windowPerfectMs * _lateFactor  * _bpmTolerance;
  double get bpmTolerance   => _bpmTolerance;

  factory PerceptualTimingEngine.forSong({
    required int    bpm,
    required int    userLevel,
    required double recentAccuracy,
    double swingRatio = 0.0,
  }) {
    final skill = MathTimingEngine.computeSkillFactor(
      accuracyPct:  recentAccuracy,
      consistency:  0.5,
      currentLevel: userLevel,
    );
    return PerceptualTimingEngine(bpm: bpm, skillFactor: skill, swingRatio: swingRatio);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PHASE 5 — Adaptive MIDI Stabilizer
// ═══════════════════════════════════════════════════════════════════════════

/// Upgraded MidiStabilizer with:
///   - Adaptive debounce: threshold = f(velocity, padType)
///   - Ghost note filter using pattern context
///   - Improved hi-hat state logic
class AdaptiveMidiStabilizer {
  // ── Per-pad-type base debounce (ms) ───────────────────────────────────────
  static const Map<_PadCategory, double> _baseDebounce = {
    _PadCategory.kick:    15.0,  // kick pedal needs more debounce
    _PadCategory.snare:   10.0,
    _PadCategory.hihat:   8.0,   // hi-hat can be legitimately fast
    _PadCategory.cymbal:  12.0,
    _PadCategory.tom:     10.0,
  };

  static const int    _minVelocity    = 5;
  static const int    _ghostVelocity  = 20; // below this = potential ghost
  static const int    _jitterWindow   = 4;

  // ── State ──────────────────────────────────────────────────────────────────
  final Map<DrumPad, double>         _lastHitMs   = {};
  final Map<DrumPad, Queue<double>>  _jitterBufs  = {};
  HiHatState _hiHatState = HiHatState.closed;

  // ── Process ────────────────────────────────────────────────────────────────
  StabilizedEvent? process(MidiEvent raw, {bool patternExpectsGhost = false}) {
    if (!raw.isNoteOn) return null;
    if (raw.velocity < _minVelocity) return null;

    final pad = StandardDrumMaps.generalMidi[raw.note];
    if (pad == null) return null;

    final rawMs  = raw.timestampMicros / 1000.0;
    final cat    = _category(pad);

    // ── Adaptive debounce = f(velocity, padType) ──────────────────────────
    //    High velocity hits need less debounce (likely intentional)
    //    Low velocity hits need more (might be bounce)
    final velFactor  = 1.0 - (raw.velocity / 127.0) * 0.4; // 0.6–1.0
    final debounceMs = (_baseDebounce[cat] ?? 10.0) * velFactor;

    final last = _lastHitMs[pad];
    if (last != null && (rawMs - last) < debounceMs) return null;
    _lastHitMs[pad] = rawMs;

    // ── Ghost note filter ─────────────────────────────────────────────────
    //    Very low velocity hits filtered UNLESS pattern expects ghost note
    if (raw.velocity < _ghostVelocity && !patternExpectsGhost) return null;

    // ── Jitter smoothing ──────────────────────────────────────────────────
    final smoothedMs = _smooth(pad, rawMs);

    // ── Hi-hat resolution ─────────────────────────────────────────────────
    DrumPad resolvedPad = pad;
    if (pad == DrumPad.hihatClosed || pad == DrumPad.hihatOpen) {
      resolvedPad = _resolveHiHat(raw.velocity);
    }

    return StabilizedEvent(
      originalEvent:  raw,
      pad:            resolvedPad,
      smoothedTimeMs: smoothedMs,
      hiHatState:     resolvedPad == DrumPad.hihatClosed || resolvedPad == DrumPad.hihatOpen
          ? _hiHatState : null,
    );
  }

  void processCCMessage(int cc, int value) {
    if (cc == 4) _hiHatState = value < 64 ? HiHatState.open : HiHatState.closed;
  }

  double _smooth(DrumPad pad, double rawMs) {
    final buf = _jitterBufs.putIfAbsent(pad, () => Queue<double>());
    buf.addLast(rawMs);
    if (buf.length > _jitterWindow) buf.removeFirst();
    return buf.reduce((a, b) => a + b) / buf.length;
  }

  DrumPad _resolveHiHat(int velocity) =>
      _hiHatState == HiHatState.open && velocity < 90
          ? DrumPad.hihatOpen
          : DrumPad.hihatClosed;

  _PadCategory _category(DrumPad pad) {
    switch (pad) {
      case DrumPad.kick:                                     return _PadCategory.kick;
      case DrumPad.snare: case DrumPad.rimshot:
      case DrumPad.crossstick:                               return _PadCategory.snare;
      case DrumPad.hihatClosed: case DrumPad.hihatOpen:
      case DrumPad.hihatPedal:                               return _PadCategory.hihat;
      case DrumPad.crash1: case DrumPad.crash2:
      case DrumPad.ride:   case DrumPad.rideBell:            return _PadCategory.cymbal;
      default:                                               return _PadCategory.tom;
    }
  }

  void reset() {
    _lastHitMs.clear(); _jitterBufs.clear();
    _hiHatState = HiHatState.closed;
  }

  /// Returns whether the next expected note on [pad] is a ghost note (low velocity).
  static bool nextNoteIsGhost(DrumPad pad, List<PendingNote> pending, double playheadMs) {
    for (final p in pending) {
      if (p.matched) continue;
      if ((p.expectedMs - playheadMs).abs() < 100 && p.pad == pad) {
        return p.velocity < 40;
      }
    }
    return false;
  }
}

enum _PadCategory { kick, snare, hihat, cymbal, tom }

// ═══════════════════════════════════════════════════════════════════════════
// DrumNoteNormalizer (unchanged from previous — kept for single import)
// ═══════════════════════════════════════════════════════════════════════════
class DrumNoteNormalizer {
  final DrumKitBrand _brand;
  final Map<int, DrumPad> _userOverrides = {};

  DrumNoteNormalizer({DrumKitBrand brand = DrumKitBrand.generic}) : _brand = brand;

  DrumPad? normalize({required int midiNote, required int channel}) {
    // Accept all MIDI channels — some controllers use channels other than 9/10
    if (_userOverrides.containsKey(midiNote)) return _userOverrides[midiNote];
    final map = StandardDrumMaps.forBrand(_brand);
    if (map.containsKey(midiNote)) return map[midiNote];
    if (StandardDrumMaps.generalMidi.containsKey(midiNote)) return StandardDrumMaps.generalMidi[midiNote];
    return _heuristic(midiNote);
  }

  void setOverride(int midiNote, DrumPad pad) => _userOverrides[midiNote] = pad;
  void clearOverride(int midiNote)             => _userOverrides.remove(midiNote);
  void clearAllOverrides()                     => _userOverrides.clear();

  DrumPad? _heuristic(int note) {
    if (note >= 22 && note <= 26) return DrumPad.hihatClosed;
    if (note >= 35 && note <= 36) return DrumPad.kick;
    if (note >= 37 && note <= 40) return DrumPad.snare;
    if (note >= 41 && note <= 47) return DrumPad.floorTom;
    if (note >= 48 && note <= 50) return DrumPad.tom1;
    if (note >= 51 && note <= 53) return DrumPad.ride;
    if (note >= 55 && note <= 57) return DrumPad.crash1;
    if (note >= 60 && note <= 64) return DrumPad.tom2;
    return null;
  }

  List<NoteEvent> normalizeEvents(List<NoteEvent> events) => events.map((e) {
    final p = normalize(midiNote: e.midiNote, channel: 9);
    if (p == null || p == e.pad) return e;
    return NoteEvent(pad: p, midiNote: e.midiNote,
        beatPosition: e.beatPosition, timeSeconds: e.timeSeconds,
        velocity: e.velocity, duration: e.duration);
  }).toList();

  static Map<DrumPad, List<NoteEvent>> groupByPad(List<NoteEvent> events) {
    final map = <DrumPad, List<NoteEvent>>{};
    for (final e in events) map.putIfAbsent(e.pad, () => []).add(e);
    return map;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared value objects
// ═══════════════════════════════════════════════════════════════════════════
class PendingNote {
  final NoteEvent note;
  bool matched = false;
  PendingNote(this.note);
  double get expectedMs => note.timeSeconds * 1000.0;
  DrumPad get pad       => note.pad;
  int     get velocity  => note.velocity;
}

class MatchResult {
  final NoteEvent? expectedNote;
  final double     hitMs, deltaMs, cost;
  final bool       padMatch, isExtra;
  final int        hitVelocity, score;
  final TimingGrade grade;

  const MatchResult({
    required this.expectedNote, required this.hitMs,
    required this.deltaMs,      required this.cost,
    required this.padMatch,     required this.hitVelocity,
    required this.grade,        required this.score,
    this.isExtra = false,
  });

  factory MatchResult.extra({required DrumPad hitPad, required double hitMs, required int velocity}) =>
      MatchResult(expectedNote: null, hitMs: hitMs, deltaMs: 0, cost: 0,
          padMatch: false, hitVelocity: velocity,
          grade: TimingGrade.miss, score: 0, isExtra: true);
}

class RecentHit {
  final DrumPad pad;
  final double  timestampMs;
  const RecentHit({required this.pad, required this.timestampMs});
}

enum HiHatState { closed, open, pedal }

class StabilizedEvent {
  final MidiEvent   originalEvent;
  final DrumPad     pad;
  final double      smoothedTimeMs;
  final HiHatState? hiHatState;
  const StabilizedEvent({
    required this.originalEvent, required this.pad,
    required this.smoothedTimeMs, this.hiHatState,
  });
}

