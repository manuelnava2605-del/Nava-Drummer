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

  const NotationNote({
    required this.source,
    required this.pad,
    required this.timeSeconds,
    required this.staffLine,
    required this.headType,
    required this.stemUp,
    required this.openHihat,
    required this.color,
  });
}

// ── Note with computed screen coordinates ────────────────────────────────────
/// Result of the layout pass — ready to be painted.
class LaidOutNote {
  final NotationNote note;
  final double       x;           // center-X of the note head
  final double       y;           // center-Y of the note head
  final bool         highlighted; // true while within ~150 ms of a recent hit

  const LaidOutNote({
    required this.note,
    required this.x,
    required this.y,
    this.highlighted = false,
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

  const SheetRenderModel({
    required this.notes,
    required this.playheadX,
    required this.staffTop,
    required this.lineSpacing,
    required this.barLineXs,
    required this.beatLineXs,
    required this.currentBar,
  });

  double get staffBottom => staffTop + lineSpacing * 4;
}
