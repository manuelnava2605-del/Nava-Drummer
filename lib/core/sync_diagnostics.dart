// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Sync Diagnostics
// Real-time timing diagnostic overlay for debugging audio/chart sync issues.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/material.dart';
import 'song_sync_profile.dart';
import '../domain/entities/entities.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SyncDiagnostics — collects timing snapshots
// ═══════════════════════════════════════════════════════════════════════════

/// Singleton that collects timing snapshots from all subsystems.
/// Write to its fields from PracticeScreen, then call [update].
/// Read from its [stream] to drive the overlay widget.
class SyncDiagnostics {
  static final SyncDiagnostics instance = SyncDiagnostics._();
  SyncDiagnostics._();

  /// Set to true to enable the overlay and stream emissions.
  bool enabled = false;

  // ── Current values ─────────────────────────────────────────────────────────
  double audioPositionSec   = 0; // just_audio reported position
  double gamePlayheadSec    = 0; // engine _playUs / 1e6
  double renderPlayheadSec  = 0; // interpolated smooth playhead in FallingNotesView
  double sheetPlayheadSec   = 0; // playhead sent to SheetMusicView

  double configuredBpm      = 0; // song.bpm
  double configuredBeatDur  = 0; // 60.0 / bpm in seconds

  /// The active sync profile for the current song.
  /// When set, [audioVsGame] shows expected-vs-actual drift instead of the
  /// raw (game - audio) difference which is misleading during the pre-gap.
  SongSyncProfile? syncProfile;

  // ── Derived drift values (computed in update()) ───────────────────────────
  /// True drift: actual audio position minus expected audio position.
  /// Positive = audio is AHEAD of where the chart expects it to be.
  /// null during the pre-gap (audio hasn't started yet).
  double? audioVsGame        = 0;
  double  audioVsRender      = 0; // renderPlayheadSec - audioPositionSec
  double  audioVsSheet       = 0; // sheetPlayheadSec - audioPositionSec
  double  driftAccumulated   = 0; // running sum of audioVsGame samples (for trend)
  bool    inPreGap           = false; // true while chart is before beat 1

  String nextNoteInfo       = ''; // debug text: next expected note

  // ── Input debug (updated on every hit) ───────────────────────────────────
  InputSourceType lastInputSource  = InputSourceType.connectedDrum;
  String          lastPadId        = '';
  int             lastVelocity     = 0;
  int             lastRawArrivalUs = 0;
  String?         lastDeviceId;
  double          lastDeltaMs      = 0;
  String          lastJudgement    = '';

  // ── Stream ────────────────────────────────────────────────────────────────
  final _controller = StreamController<SyncDiagnostics>.broadcast();
  Stream<SyncDiagnostics> get stream => _controller.stream;

  /// Recompute derived values and emit to stream if enabled.
  void update() {
    // True drift: compare actual audio position to the expected position
    // derived from the chart time.  This avoids the false ~7.2s "drift" that
    // appears during the pre-gap when audio hasn't started yet.
    final profile = syncProfile;
    if (profile != null) {
      final expectedAudio = profile.audioPositionForChartTime(gamePlayheadSec);
      if (expectedAudio == null) {
        // Chart is in the pre-gap — audio not yet playing.
        inPreGap   = true;
        audioVsGame = null;
      } else {
        inPreGap    = false;
        audioVsGame = audioPositionSec - expectedAudio;
      }
    } else {
      inPreGap    = false;
      audioVsGame = gamePlayheadSec - audioPositionSec;
    }

    audioVsRender = renderPlayheadSec - audioPositionSec;
    audioVsSheet  = sheetPlayheadSec - audioPositionSec;
    // Accumulate drift trend (only when audio is active)
    final drift = audioVsGame;
    if (drift != null) {
      driftAccumulated = driftAccumulated * 0.95 + drift * 0.05;
    }
    if (enabled && !_controller.isClosed) {
      _controller.add(this);
    }
  }

  /// Called after each hit to emit input debug snapshot.
  void updateInput() {
    if (enabled && !_controller.isClosed) {
      _controller.add(this);
    }
  }

  /// Reset all values (call on song stop/restart).
  void reset() {
    audioPositionSec  = 0;
    gamePlayheadSec   = 0;
    renderPlayheadSec = 0;
    sheetPlayheadSec  = 0;
    audioVsGame       = 0;
    audioVsRender     = 0;
    audioVsSheet      = 0;
    driftAccumulated  = 0;
    inPreGap          = false;
    nextNoteInfo      = '';
    lastInputSource   = InputSourceType.connectedDrum;
    lastPadId         = '';
    lastVelocity      = 0;
    lastRawArrivalUs  = 0;
    lastDeviceId      = null;
    lastDeltaMs       = 0;
    lastJudgement     = '';
    // syncProfile intentionally kept — it's set once at loadSong
  }

  void dispose() {
    if (!_controller.isClosed) _controller.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TimingDebugOverlay — dark translucent debug panel
// ═══════════════════════════════════════════════════════════════════════════

/// Shows a timing debug panel at the top-left when [SyncDiagnostics.enabled].
/// Place at the top of the Stack in PracticeScreen.
/// Transparent (zero-size) when disabled.
class TimingDebugOverlay extends StatelessWidget {
  const TimingDebugOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    if (!SyncDiagnostics.instance.enabled) return const SizedBox.shrink();

    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: StreamBuilder<SyncDiagnostics>(
          stream: SyncDiagnostics.instance.stream,
          builder: (context, snapshot) {
            final d = snapshot.data ?? SyncDiagnostics.instance;
            return Stack(
              children: [
                _DebugPanel(d: d),
                // Close button — top-right corner of the panel
                Positioned(
                  top: 10, right: 10,
                  child: GestureDetector(
                    onTap: () {
                      SyncDiagnostics.instance.enabled = false;
                      // Force rebuild by adding an empty update
                      SyncDiagnostics.instance.update();
                    },
                    child: Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 12, color: Colors.white70),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DebugPanel extends StatelessWidget {
  final SyncDiagnostics d;
  const _DebugPanel({required this.d});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.cyan.withOpacity(0.4), width: 1),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 9.5,
          color: Colors.white,
          height: 1.55,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('SYNC DEBUG', '', color: Colors.cyan),
            _divider(),
            _row('BPM',       '${d.configuredBpm.toStringAsFixed(1)}  beat=${(d.configuredBeatDur*1000).toStringAsFixed(0)}ms'),
            _divider(),
            _row('audio',     '${_fmt(d.audioPositionSec)}s', color: Colors.greenAccent),
            _row('game',      '${_fmt(d.gamePlayheadSec)}s',  color: Colors.white),
            _row('render',    '${_fmt(d.renderPlayheadSec)}s'),
            _row('sheet',     '${_fmt(d.sheetPlayheadSec)}s'),
            _divider(),
            _row(
              'Δ audio drift',
              d.inPreGap ? 'PRE-GAP' : _driftStr(d.audioVsGame ?? 0),
              color: d.inPreGap ? Colors.blueAccent : _driftColor(d.audioVsGame ?? 0),
            ),
            _row('Δ render-audio',_driftStr(d.audioVsRender)),
            _row('Δ sheet-audio', _driftStr(d.audioVsSheet)),
            _row('drift trend',   _driftStr(d.driftAccumulated), color: _driftColor(d.driftAccumulated)),
            if (d.nextNoteInfo.isNotEmpty) ...[
              _divider(),
              _row('next', d.nextNoteInfo, color: Colors.yellow),
            ],
            // ── Input debug section ──────────────────────────────────────
            _divider(),
            _row('INPUT DEBUG', '', color: Colors.purpleAccent),
            _divider(),
            _row('source',  d.lastInputSource == InputSourceType.onScreenPad ? 'ON-SCREEN' : 'MIDI/HW',
              color: d.lastInputSource == InputSourceType.onScreenPad ? Colors.cyanAccent : Colors.greenAccent),
            _row('pad',     d.lastPadId.isEmpty ? '—' : d.lastPadId),
            _row('velocity','${d.lastVelocity}'),
            _row('delta',   d.lastJudgement.isEmpty ? '—' : '${_signedMs(d.lastDeltaMs)}  ${d.lastJudgement}',
              color: _judgementColor(d.lastJudgement)),
            if (d.lastDeviceId != null && d.lastDeviceId!.isNotEmpty)
              _row('device', d.lastDeviceId!.length > 18 ? d.lastDeviceId!.substring(0, 18) : d.lastDeviceId!),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 100,
          child: Text('${label.padRight(14)}', style: TextStyle(
            color: Colors.white.withOpacity(0.65), fontSize: 9.5, fontFamily: 'monospace')),
        ),
        Text(value, style: TextStyle(
          color: color ?? Colors.white, fontSize: 9.5, fontFamily: 'monospace',
          fontWeight: color != null ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }

  Widget _divider() => Container(
    margin: const EdgeInsets.symmetric(vertical: 2),
    height: 1,
    width: 200,
    color: Colors.white.withOpacity(0.12),
  );

  String _fmt(double sec) => sec.toStringAsFixed(3);

  String _driftStr(double drift) {
    final ms = (drift * 1000).toStringAsFixed(1);
    final sign = drift >= 0 ? '+' : '';
    return '${sign}${ms}ms';
  }

  Color _driftColor(double drift) {
    final abs = drift.abs();
    if (abs < 0.010) return Colors.greenAccent;
    if (abs < 0.030) return Colors.yellowAccent;
    if (abs < 0.060) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  String _signedMs(double ms) {
    final sign = ms >= 0 ? '+' : '';
    return '${sign}${ms.toStringAsFixed(1)}ms';
  }

  Color _judgementColor(String j) {
    switch (j) {
      case 'PERFECT': return Colors.greenAccent;
      case 'GOOD':    return Colors.lightGreenAccent;
      case 'EARLY':   return Colors.cyanAccent;
      case 'LATE':    return Colors.orangeAccent;
      case 'MISS':    return Colors.redAccent;
      case 'EXTRA':   return Colors.pinkAccent;
      default:        return Colors.white;
    }
  }
}
