// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Drum Notation Mapper
// Converts NoteEvent / DrumPad to notation descriptors.
// This is the ONLY place that encodes the music-theory mapping.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../../../domain/entities/entities.dart';
import '../../theme/nava_theme.dart';
import 'notation_models.dart';

class DrumNotationMapper {
  // ── Staff-line map ───────────────────────────────────────────────────────
  // staffLine: 0.0 = bottom staff line | 4.0 = top staff line
  // Positions above 4.0 and below 0.0 get ledger lines automatically.
  //
  //  6.5 ─── crash 2 (×)
  //  6.0 ─── crash 1 (×)
  //  5.5 ─── hi-hat closed / open (×)
  //  5.0 ─── ride / ride bell (×/◆)
  //  ════ top staff line (4.0) ════════
  //  3.5 ─── tom 1
  //  3.0 ─── tom 2 / snare (centre space)
  //  2.5 ─── tom 3
  //  ════ middle staff line (2.0) ═════
  //  1.5 ─── floor tom
  //  ════ bottom staff line (0.0) ═════
  // -1.0 ─── kick (one ledger line below)
  // -1.5 ─── hi-hat pedal (one ledger line below)

  static const Map<DrumPad, DrumNotationInfo> _map = {
    // ── Kick ────────────────────────────────────────────────────────────
    DrumPad.kick: DrumNotationInfo(
      staffLine:   -1.0,
      headType:    NoteHeadType.normal,
      colorFamily: NoteColorFamily.kickSnare,
      stemUp:      false,
    ),
    // ── Hi-Hat family ───────────────────────────────────────────────────
    DrumPad.hihatClosed: DrumNotationInfo(
      staffLine:   5.5,
      headType:    NoteHeadType.xmark,
      colorFamily: NoteColorFamily.cymbal,
    ),
    DrumPad.hihatOpen: DrumNotationInfo(
      staffLine:   5.5,
      headType:    NoteHeadType.xmark,
      colorFamily: NoteColorFamily.cymbal,
      openHihat:   true,
    ),
    DrumPad.hihatPedal: DrumNotationInfo(
      staffLine:   -1.5,
      headType:    NoteHeadType.xmark,
      colorFamily: NoteColorFamily.cymbal,
      stemUp:      false,
    ),
    // ── Snare family ────────────────────────────────────────────────────
    DrumPad.snare: DrumNotationInfo(
      staffLine:   3.0,
      headType:    NoteHeadType.normal,
      colorFamily: NoteColorFamily.kickSnare,
    ),
    DrumPad.rimshot: DrumNotationInfo(
      staffLine:   3.0,
      headType:    NoteHeadType.normal,
      colorFamily: NoteColorFamily.kickSnare,
    ),
    DrumPad.crossstick: DrumNotationInfo(
      staffLine:   3.0,
      headType:    NoteHeadType.xmark,
      colorFamily: NoteColorFamily.kickSnare,
    ),
    // ── Toms ────────────────────────────────────────────────────────────
    DrumPad.tom1: DrumNotationInfo(
      staffLine:   3.5,
      headType:    NoteHeadType.normal,
      colorFamily: NoteColorFamily.tom,
    ),
    DrumPad.tom2: DrumNotationInfo(
      staffLine:   2.5,
      headType:    NoteHeadType.normal,
      colorFamily: NoteColorFamily.tom,
    ),
    DrumPad.tom3: DrumNotationInfo(
      staffLine:   2.0,
      headType:    NoteHeadType.normal,
      colorFamily: NoteColorFamily.tom,
    ),
    DrumPad.floorTom: DrumNotationInfo(
      staffLine:   1.5,
      headType:    NoteHeadType.normal,
      colorFamily: NoteColorFamily.tom,
    ),
    // ── Crashes ─────────────────────────────────────────────────────────
    DrumPad.crash1: DrumNotationInfo(
      staffLine:   6.0,
      headType:    NoteHeadType.xmark,
      colorFamily: NoteColorFamily.cymbal,
    ),
    DrumPad.crash2: DrumNotationInfo(
      staffLine:   6.5,
      headType:    NoteHeadType.xmark,
      colorFamily: NoteColorFamily.cymbal,
    ),
    // ── Ride ────────────────────────────────────────────────────────────
    DrumPad.ride: DrumNotationInfo(
      staffLine:   5.0,
      headType:    NoteHeadType.xmark,
      colorFamily: NoteColorFamily.cymbal,
    ),
    DrumPad.rideBell: DrumNotationInfo(
      staffLine:   5.0,
      headType:    NoteHeadType.diamond,
      colorFamily: NoteColorFamily.cymbal,
    ),
  };

  // ── Color resolver ───────────────────────────────────────────────────────
  static Color _resolveColor(NoteColorFamily family) {
    switch (family) {
      case NoteColorFamily.cymbal:    return NavaTheme.neonCyan;
      case NoteColorFamily.tom:       return NavaTheme.neonGold;
      case NoteColorFamily.kickSnare: return NavaTheme.textPrimary;
    }
  }

  // ── Public API ───────────────────────────────────────────────────────────

  /// Convert a single NoteEvent to a NotationNote.
  /// [gapToNext] is the time in seconds to the next note in the chart (for
  /// computing rhythmic note value). Defaults to 1.0 (quarter note at 60 BPM).
  static NotationNote? fromEvent(NoteEvent event, {double gapToNext = 1.0}) {
    final info = _map[event.pad];
    if (info == null) return null;
    return NotationNote(
      source:           event,
      pad:              event.pad,
      timeSeconds:      event.timeSeconds,
      staffLine:        info.staffLine,
      headType:         info.headType,
      stemUp:           info.stemUp,
      openHihat:        info.openHihat,
      color:            _resolveColor(info.colorFamily),
      gapToNextSeconds: gapToNext,
    );
  }

  /// Convert an entire chart of NoteEvents to notation notes in time order.
  /// Gap-to-next is computed here so SheetLayoutEngine can derive note values.
  /// Called once at song load — O(n log n), not per-frame.
  static List<NotationNote> fromChart(List<NoteEvent> events) {
    if (events.isEmpty) return [];
    final sorted = List<NoteEvent>.from(events)
      ..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));

    final result = <NotationNote>[];
    for (int i = 0; i < sorted.length; i++) {
      final gap = (i + 1 < sorted.length)
          ? (sorted[i + 1].timeSeconds - sorted[i].timeSeconds).clamp(0.01, 8.0)
          : 1.0; // default: assume 1 second gap for last note
      final n = fromEvent(sorted[i], gapToNext: gap.toDouble());
      if (n != null) result.add(n);
    }
    return result;
  }
}
