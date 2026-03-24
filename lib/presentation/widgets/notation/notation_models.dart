// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Notation Models
// Pure data classes for the drum sheet music system.
// No dependency on Flutter (except Color) — safe to unit-test.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../../../domain/entities/entities.dart';

// ── Note head shapes ──────────────────────────────────────────────────────────
enum NoteHeadType {
  normal,   // filled oval  → kick, snare, all toms
  xmark,    // × cross      → hi-hat (closed/open/pedal), crash, ride
  diamond,  // ◆ solid      → ride bell
}

// ── Color family for quick color lookup ──────────────────────────────────────
enum NoteColorFamily {
  cymbal,    // neon cyan  — hi-hat, crash, ride
  tom,       // neon gold  — high/mid/floor toms
  kickSnare, // white      — kick drum and snare family
}

// ── Rhythmic note value ───────────────────────────────────────────────────────
/// Standard note durations in Western music notation.
/// Derived from the gap to the next note in the chart (not the MIDI note-off).
enum NoteValueType {
  whole,        // semibreve        — 4 beats  — hollow oval, no stem
  half,         // minim            — 2 beats  — hollow oval + stem
  quarter,      // crotchet         — 1 beat   — filled oval + stem
  eighth,       // quaver           — ½ beat   — filled + 1 flag / 1 beam
  sixteenth,    // semiquaver       — ¼ beat   — filled + 2 flags / 2 beams
  thirtySecond, // demisemiquaver   — ⅛ beat   — filled + 3 flags
  sixtyFourth,  // hemidemisemiquaver — 1/16 beat — filled + 4 flags
}

extension NoteValueTypeExt on NoteValueType {
  /// Number of flags drawn on an unbeamed note stem.
  /// 0 = whole/half/quarter (no flag), 1 = eighth, 2 = 16th, etc.
  int get flagCount {
    switch (this) {
      case NoteValueType.whole:        return 0;
      case NoteValueType.half:         return 0;
      case NoteValueType.quarter:      return 0;
      case NoteValueType.eighth:       return 1;
      case NoteValueType.sixteenth:    return 2;
      case NoteValueType.thirtySecond: return 3;
      case NoteValueType.sixtyFourth:  return 4;
    }
  }

  /// True for note values that use a hollow (open) note head.
  bool get isOpen => this == NoteValueType.whole || this == NoteValueType.half;

  /// True for note values that use a stem.
  bool get hasStem => this != NoteValueType.whole;
}

// ── Static notation descriptor per instrument ─────────────────────────────────
/// Describes how a DrumPad maps to standard drum notation.
class DrumNotationInfo {
  /// Position on the staff.
  /// 0.0 = bottom (1st) staff line   4.0 = top (5th) staff line.
  /// Values < 0  → below staff (kick, hi-hat pedal) — require ledger lines.
  /// Values > 4  → above staff (cymbals) — require ledger lines.
  final double        staffLine;
  final NoteHeadType  headType;
  /// true = stem points up (most notes); false = stem points down (kick/pedal).
  final bool          stemUp;
  /// Draw a small open circle above the × to indicate open hi-hat.
  final bool          openHihat;
  final NoteColorFamily colorFamily;

  const DrumNotationInfo({
    required this.staffLine,
    required this.headType,
    required this.colorFamily,
    this.stemUp    = true,
    this.openHihat = false,
  });
}

// ── Note ready for notation rendering ────────────────────────────────────────
/// One note converted from NoteEvent, enriched with visual notation metadata.
class NotationNote {
  final NoteEvent      source;
  final DrumPad        pad;
  final double         timeSeconds;  // same as source.timeSeconds
  final double         staffLine;
  final NoteHeadType   headType;
  final bool           stemUp;
  final bool           openHihat;
  final Color          color;
  /// Time gap to the next note in seconds. Used by SheetLayoutEngine to
  /// determine the rhythmic note value (quarter, eighth, 16th, etc.).
  /// Set to 1.0 (assumed quarter at 60 BPM) when no next note exists.
  final double         gapToNextSeconds;

  const NotationNote({
    required this.source,
    required this.pad,
    required this.timeSeconds,
    required this.staffLine,
    required this.headType,
    required this.stemUp,
    required this.openHihat,
    required this.color,
    this.gapToNextSeconds = 1.0,
  });
}

// ── Note with computed screen coordinates ────────────────────────────────────
/// Result of the layout pass — ready to be painted.
class LaidOutNote {
  final NotationNote note;
  final double       x;           // center-X of the note head
  final double       y;           // center-Y of the note head
  final bool         highlighted; // true while within ~150 ms of a recent hit
  /// Rhythmic value computed from gap + BPM in SheetLayoutEngine.
  final NoteValueType noteValue;

  const LaidOutNote({
    required this.note,
    required this.x,
    required this.y,
    this.highlighted = false,
    this.noteValue   = NoteValueType.eighth,
  });
}

// ── Final model consumed by SheetMusicPainter ─────────────────────────────────
/// All data needed to draw one frame of the score.
class SheetRenderModel {
  final List<LaidOutNote> notes;
  final double            playheadX;
  final double            staffTop;      // Y of the top staff line
  final double            lineSpacing;   // pixels between adjacent staff lines
  final List<double>      barLineXs;     // X positions for measure bar lines
  final List<double>      beatLineXs;    // X positions for beat subdivisions
  final int               currentBar;    // 1-based bar number at playhead

  // ── Notation metadata ───────────────────────────────────────────────────
  /// Time signature numerator (beats per bar), e.g. 4.
  final int timeSigNumerator;
  /// Time signature denominator (note value), e.g. 4.
  final int timeSigDenominator;

  /// Chord groups: each sub-list holds indices into [notes] that fall within
  /// ~6 ms of each other (i.e. played simultaneously). Sub-lists have ≥ 2 entries.
  final List<List<int>> chordGroups;

  /// Beam groups: each sub-list holds indices into [notes] (up-stem only) that
  /// share a beat and should be connected with a horizontal beam. ≥ 2 entries.
  final List<List<int>> beamGroups;

  const SheetRenderModel({
    required this.notes,
    required this.playheadX,
    required this.staffTop,
    required this.lineSpacing,
    required this.barLineXs,
    required this.beatLineXs,
    required this.currentBar,
    this.timeSigNumerator   = 4,
    this.timeSigDenominator = 4,
    this.chordGroups        = const [],
    this.beamGroups         = const [],
  });

  double get staffBottom => staffTop + lineSpacing * 4;
}
