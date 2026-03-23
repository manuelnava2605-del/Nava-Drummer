// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Practice Engine  (Phase 6 — Upgraded + Sync Fix)
// Integrates: GlobalTimingController + MathTimingEngine + AdvancedNoteMatcher
//             + MidiStabilizer + DrumNoteNormalizer + SongSyncProfile
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import '../domain/entities/entities.dart';
import '../domain/entities/song_package.dart';
import '../data/datasources/local/midi_engine.dart';
import 'drum_engine.dart';
import 'backing_track_service.dart';
import 'advanced_matching.dart';
import 'song_sync_profile.dart';
import 'sync_diagnostics.dart';

export 'global_timing_controller.dart'
    show TimingAnalysis, TimingBias, TimingTrend;

// ── Engine state ──────────────────────────────────────────────────────────────
enum EngineState { idle, ready, countIn, playing, paused, finished }

// ── Score snapshot emitted every hit ─────────────────────────────────────────
class ScoreState {
  final int score, combo, maxCombo, multiplier;
  final double accuracy; // 0–1
  final int perfectCount, goodCount, earlyCount, lateCount, missCount;
  final double gaussianScore; // last hit Gaussian score 0–1

  /// Source of the most-recent hit (for HUD input-source indicator).
  final InputSourceType lastInputSource;

  const ScoreState({
    required this.score,
    required this.accuracy,
    required this.combo,
    required this.maxCombo,
    required this.multiplier,
    required this.perfectCount,
    required this.goodCount,
    required this.earlyCount,
    required this.lateCount,
    required this.missCount,
    this.gaussianScore = 0,
    this.lastInputSource = InputSourceType.connectedDrum,
  });

  factory ScoreState.initial() => const ScoreState(
        score: 0,
        accuracy: 0,
        combo: 0,
        maxCombo: 0,
        multiplier: 1,
        perfectCount: 0,
        goodCount: 0,
        earlyCount: 0,
        lateCount: 0,
        missCount: 0,
      );

  String get accuracyString => '${(accuracy * 100).toStringAsFixed(1)}%';
}

// ═══════════════════════════════════════════════════════════════════════════
// PracticeEngine
// ═══════════════════════════════════════════════════════════════════════════
class PracticeEngine {
  final MidiEngine _midi;

  // ── Sub-systems (injected at loadSong) ─────────────────────────────────────
  late MathTimingEngine _timingEngine;
  late ContextAwareMatcher _matcher;
  late AdaptiveMidiStabilizer _stabilizer;
  late DrumNoteNormalizer _normalizer;
  final GlobalTimingController _clock = GlobalTimingController.instance;

  // ── Config ─────────────────────────────────────────────────────────────────
  Song? currentSong;
  List<NoteEvent> _notes = [];
  DrumMapping? _mapping;
  double _tempo         = 1.0; // 0.5–1.2 — user-requested rate
  double _baseTempoFactor = 1.0; // same as _tempo; drift correction always offsets from this
  bool _loop = false;
  bool _hasBackingTrack = false;
  double? _loopStart, _loopEnd;
  int _bpm = 120;
  // ignore: unused_field
  int _userLevel = 1;
  // ignore: unused_field
  double _recentAccuracy = 70.0;

  // ── Engine state ───────────────────────────────────────────────────────────
  EngineState _state = EngineState.idle;
  EngineState get state => _state;
  int _playUs = 0;
  int _startRef = 0;
  DateTime? _startTime;
  int _lastBeat = -1;

  // ── Scoring state ──────────────────────────────────────────────────────────
  int _score = 0, _combo = 0, _maxCombo = 0;
  int _perfect = 0, _good = 0, _early = 0, _late = 0, _miss = 0;
  InputSourceType _lastSource = InputSourceType.connectedDrum;
  double _lastGaussian = 0;

  // ── Per-drum timing history (for AI analysis) ──────────────────────────────
  final Map<DrumPad, List<double>> _padDeltas = {};
  final List<double> _allDeltas = [];
  final Map<DrumPad, List<int>> _padVelocities = {};
  final List<RecentHit> _recentHits = [];

  // ── Pending notes queue ────────────────────────────────────────────────────
  final List<PendingNote> _pending = [];

  // ── Streams ────────────────────────────────────────────────────────────────
  final _hitSubject = PublishSubject<HitResult>();
  final _scoreSubject =
      BehaviorSubject<ScoreState>.seeded(ScoreState.initial());
  final _phSubject = BehaviorSubject<double>.seeded(0);
  final _stateSubject =
      BehaviorSubject<EngineState>.seeded(EngineState.idle);
  final _metSubject = PublishSubject<int>();
  final _countSubject = PublishSubject<int>();

  Stream<HitResult> get hitResults => _hitSubject.stream;
  Stream<ScoreState> get scoreUpdates => _scoreSubject.stream;
  Stream<double> get playheadTime => _phSubject.stream;
  Stream<EngineState> get stateChanges => _stateSubject.stream;
  Stream<int> get metronomeBeat => _metSubject.stream;
  Stream<int> get countInBeat => _countSubject.stream;
  int get currentCombo => _combo;
  bool get hasBackingTrack => _hasBackingTrack;

  StreamSubscription? _midiSub;
  StreamSubscription<Duration>? _audioPosSub;
  Timer? _timer;

  // Sync profile for the current song (set at loadSong)
  SongSyncProfile? _syncProfile;

  // Last audio position from just_audio (authoritative clock when playing)
  int _lastAudioUs = 0;
  bool _audioSyncActive = false;

  // Counter for periodic audio drift correction (every ~2s)
  int _tickCount = 0;

  // Drift correction: gentle speed-nudge timer (cancelled when drift clears)
  Timer? _driftCorrectionTimer;

  // One-shot timer that fires when audio should call play().
  // Tracked so stop()/pause() can cancel it and prevent stale play() calls.
  Timer? _audioDelayTimer;

  // Count-in timers — kept so stop() can cancel them mid count-in
  final List<Timer> _countInTimers = [];

  PracticeEngine({required MidiEngine midiEngine}) : _midi = midiEngine;

  // ══════════════════════════════════════════════════════════════════════════
  // LOAD
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> loadSong(
    Song song,
    List<NoteEvent> notes,
    DrumMapping mapping, {
    int userLevel = 1,
    double recentAccuracy = 70.0,
    double swingRatio = 0.0,
  }) async {
    currentSong = song;
    _bpm = song.bpm;
    _mapping = mapping;
    _userLevel = userLevel;
    _recentAccuracy = recentAccuracy;

    // ── Initialise sub-systems ────────────────────────────────────────────
    _timingEngine = MathTimingEngine.forSong(
      bpm: _bpm,
      userLevel: userLevel,
      recentAccuracy: recentAccuracy,
      swingRatio: swingRatio,
    );
    _matcher = ContextAwareMatcher(_timingEngine);
    _stabilizer = AdaptiveMidiStabilizer();
    // Use the active mapping's noteMap as the primary lookup so that
    // Clone Hero (notes 95-100), Roland TD, and other non-GM kits resolve
    // correctly. The DrumMappingBrand extension always returns .generic, so
    // brand-based lookup was a silent no-op — primaryMap fixes this properly.
    _normalizer = DrumNoteNormalizer(primaryMap: _mapping?.noteMap, brand: DrumKitBrand.generic);

    // Apply swing to note timestamps if needed
    if (swingRatio > 0) {
      notes = notes.map((n) {
        final adjustedMs =
            _timingEngine.swingAdjusted(n.timeSeconds * 1000, n.beatPosition);
        return NoteEvent(
          pad: n.pad,
          midiNote: n.midiNote,
          beatPosition: n.beatPosition,
          timeSeconds: adjustedMs / 1000.0,
          velocity: n.velocity,
          duration: n.duration,
        );
      }).toList();
    }

    // Normalise pads from MIDI file
    _notes = _normalizer.normalizeEvents(notes);
    _notes.sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));

    _resetCounters();
    _buildPending();

    // MIDI-only songs have no bundled backing track.
    // Package-based songs load OGG stems via loadSongPackage() → loadPackage().
    _hasBackingTrack = false;
    await BackingTrackService.instance.setTempoFactor(_tempo);

    // Load sync profile for this song (authoritative timing parameters)
    _syncProfile = SongSyncRegistry.forSong(song.id);
    assert(_syncProfile == null || _syncProfile!.audioSeekSeconds >= 0,
        'Invalid SongSyncProfile: audioSeekSeconds=${_syncProfile?.audioSeekSeconds} must be >= 0');
    assert(_syncProfile == null || _syncProfile!.audioDelaySeconds >= 0,
        'Invalid SongSyncProfile: audioDelaySeconds=${_syncProfile?.audioDelaySeconds} must be >= 0');

    // Seed diagnostics with BPM info and sync profile
    SyncDiagnostics.instance.configuredBpm = _bpm.toDouble();
    SyncDiagnostics.instance.configuredBeatDur = 60.0 / _bpm;
    SyncDiagnostics.instance.syncProfile = _syncProfile;

    _clock.startSession();
    _setState(EngineState.ready);
  }

  /// Load a fully-parsed [SongPackage] (Clone Hero / RBN format).
  ///
  /// This is the preferred entry point for package-based songs.
  /// It calls [loadSong] with the chart and a probe mapping, then:
  ///   1. Replaces the generic M4A backing track with the OGG stem from the package.
  ///   2. Overrides the sync profile with the one auto-derived by [SongPackageLoader].
  Future<void> loadSongPackage(SongPackage package) async {
    final mapping = DrumMapping(
      deviceId: package.isCloneHeroFormat ? 'clone_hero' : 'gm',
      noteMap: package.isCloneHeroFormat
          ? StandardDrumMaps.cloneHeroExpert
          : StandardDrumMaps.generalMidi,
    );

    await loadSong(package.song, package.chart, mapping);

    final hasOgg = await BackingTrackService.instance.loadPackage(package.audio);
    _hasBackingTrack = hasOgg;
    if (hasOgg) {
      await BackingTrackService.instance.setTempoFactor(_tempo);
      debugPrint('[PracticeEngine] Package OGG stem loaded for ${package.id}');
    }

    _syncProfile = package.syncProfile;
    SyncDiagnostics.instance.syncProfile = _syncProfile;

    debugPrint(
      '[PracticeEngine] loadSongPackage complete: ${package.id}, '
      '${package.noteCount} notes, BPM=${package.syncProfile.bpm.toStringAsFixed(1)}, '
      'hasAudio=$hasOgg',
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PLAYBACK CONTROL
  // ══════════════════════════════════════════════════════════════════════════
  /// Plays 4 count-in beats then starts the engine on the beat.
  ///
  /// All beats and the engine start are scheduled from a single wall-clock
  /// anchor captured right now — no Future.delayed drift accumulation.
  Future<void> startWithCountIn() async {
    if (_state != EngineState.ready) return;
    _setState(EngineState.countIn);
    _countInTimers
      ..forEach((t) => t.cancel())
      ..clear();

    // Beat duration in microseconds at current tempo
    final beatUs = (60000000.0 / (_bpm * _tempo)).round();

    // Anchor: the wall-clock epoch from which all timers are scheduled.
    // Beat i fires at anchor + beatUs × i  (i = 0..3 → beats 1..4).
    // Engine starts at anchor + beatUs × 4.
    final anchor = DateTime.now().microsecondsSinceEpoch;

    for (int i = 0; i < 4; i++) {
      final delayUs = beatUs * i;
      final beat = i + 1;
      _countInTimers.add(
        Timer(Duration(microseconds: delayUs), () {
          if (_state == EngineState.countIn) _countSubject.add(beat);
        }),
      );
    }

    // The engine start wall-clock: exactly 4 beats after the anchor.
    final startWallUs = anchor + beatUs * 4;
    _countInTimers.add(
      Timer(Duration(microseconds: beatUs * 4), () => _doStart(startWallUs)),
    );
  }

  /// Starts immediately (no count-in). Safe to call from paused state too.
  void start() {
    if (_state == EngineState.countIn ||
        _state == EngineState.ready ||
        _state == EngineState.paused) {
      _doStart(DateTime.now().microsecondsSinceEpoch);
    }
  }

  /// Internal start. [startWallUs] is the exact wall-clock microsecond at which
  /// chart-time 0 is defined.  For resume, [_playUs] is already non-zero so
  /// _startRef is adjusted accordingly (startWallUs − _playUs).
  void _doStart(int startWallUs) {
    if (_state != EngineState.countIn &&
        _state != EngineState.ready &&
        _state != EngineState.paused) return;

    _startTime = DateTime.fromMicrosecondsSinceEpoch(startWallUs);
    // _playUs may be non-zero on resume; keep it as-is.
    _startRef = startWallUs - _playUs;
    _setState(EngineState.playing);

    if (_hasBackingTrack) {
      _startBackingTrackSynced(startWallUs);
    }

    _midiSub = _midi.midiEvents.listen(_onMidi);
    _timer = Timer.periodic(
      const Duration(microseconds: 16667),
      (_) => _tick(),
    );
  }

  /// Seeks audio and schedules its playback so that the audio beat-1 lands
  /// exactly when the chart beat-1 does, based on [startWallUs].
  ///
  /// Uses a one-shot [Timer] anchored to [startWallUs] — never Future.delayed.
  void _startBackingTrackSynced(int startWallUs) {
    _audioDelayTimer?.cancel();
    _audioDelayTimer = null;

    final profile   = _syncProfile;
    final seekSec   = profile?.audioSeekSeconds ?? 0.0;
    final delayUs   = ((profile?.audioDelaySeconds ?? 0.0) * 1e6).round();
    final audioStartWallUs = startWallUs + delayUs;

    void firePlay([double? overrideSeekSec]) {
      if (_state != EngineState.playing) return;
      final target = overrideSeekSec ?? seekSec;
      if (overrideSeekSec != null) {
        // Catch-up: seekTo took longer than the pre-gap; jump to correct position.
        unawaited(
          BackingTrackService.instance.seekTo(target).then((_) {
            if (_state == EngineState.playing) {
              unawaited(
                BackingTrackService.instance.play().then((_) => _subscribeAudioPosition()),
              );
            }
          }),
        );
      } else {
        unawaited(
          BackingTrackService.instance.play().then((_) => _subscribeAudioPosition()),
        );
      }
    }

    unawaited(
      BackingTrackService.instance.seekTo(seekSec).then((_) {
        final remainingUs = audioStartWallUs - DateTime.now().microsecondsSinceEpoch;

        if (remainingUs <= 0) {
          // seekTo took longer than the audio pre-gap — play from correct position.
          final catchUpSec = (seekSec + (-remainingUs / 1e6)).clamp(0.0, double.infinity);
          firePlay(catchUpSec);
        } else if (remainingUs <= 2000) {
          // ≤2ms remaining — fire immediately.
          firePlay();
        } else {
          _audioDelayTimer = Timer(Duration(microseconds: remainingUs), () => firePlay());
        }
      }),
    );
  }

  void _subscribeAudioPosition() {
    _audioPosSub?.cancel();
    final stream = BackingTrackService.instance.authoritativePositionStream;
    if (stream == null) return;

    _audioSyncActive = true;
    _audioPosSub = stream.listen((pos) {
      if (_state != EngineState.playing) return;
      _lastAudioUs = pos.inMicroseconds;

      SyncDiagnostics.instance.audioPositionSec = pos.inMicroseconds / 1e6;
      SyncDiagnostics.instance.gamePlayheadSec = _playUs / 1e6;
      SyncDiagnostics.instance.update();
    });
  }

  void pause() {
    if (_state != EngineState.playing) return;

    _timer?.cancel();
    _midiSub?.cancel();
    _audioPosSub?.cancel();
    _audioPosSub = null;
    _audioSyncActive = false;
    _audioDelayTimer?.cancel();
    _audioDelayTimer = null;
    _driftCorrectionTimer?.cancel();
    _driftCorrectionTimer = null;

    if (_hasBackingTrack) BackingTrackService.instance.pause();
    _setState(EngineState.paused);
  }

  void resume() {
    if (_state != EngineState.paused) return;

    _driftCorrectionTimer?.cancel();
    _driftCorrectionTimer = null;
    _startRef = _clock.currentTimeMicros() - _playUs;
    _setState(EngineState.playing);
    _midiSub = _midi.midiEvents.listen(_onMidi);
    _timer = Timer.periodic(
      const Duration(microseconds: 16667),
      (_) => _tick(),
    );

    if (_hasBackingTrack) {
      final profile = _syncProfile;
      if (profile != null) {
        final expectedAudioSec =
            profile.audioPositionForChartTime(_playUs / 1e6);
        if (expectedAudioSec != null) {
          unawaited(
            BackingTrackService.instance.seekTo(expectedAudioSec).then((_) async {
              await BackingTrackService.instance.play();
              _subscribeAudioPosition();
            }),
          );
        } else {
          // Pre-gap: audio starts from the top with its full delay applied.
          _startBackingTrackSynced(_clock.currentTimeMicros());
        }
      } else {
        unawaited(BackingTrackService.instance.resume());
        _subscribeAudioPosition();
      }
    }
  }

  void stop() {
    // Cancel any pending count-in beats, audio delay, or drift corrections first.
    for (final t in _countInTimers) { t.cancel(); }
    _countInTimers.clear();
    _audioDelayTimer?.cancel();
    _audioDelayTimer = null;
    _driftCorrectionTimer?.cancel();
    _driftCorrectionTimer = null;

    _timer?.cancel();
    _midiSub?.cancel();
    _audioPosSub?.cancel();
    _audioPosSub = null;
    _audioSyncActive = false;

    BackingTrackService.instance.stop();
    _playUs = 0;
    _lastAudioUs = 0;
    _tickCount = 0;

    SyncDiagnostics.instance.reset();
    _setState(EngineState.idle);
    _broadcast();
  }

  PerformanceSession finish() {
    _audioDelayTimer?.cancel();
    _audioDelayTimer = null;
    _driftCorrectionTimer?.cancel();
    _driftCorrectionTimer = null;
    _timer?.cancel();
    _midiSub?.cancel();
    _audioPosSub?.cancel();
    _audioPosSub = null;
    _audioSyncActive = false;
    _setState(EngineState.finished);

    final total = _notes.length;
    final hit = _perfect + _good + _early + _late;
    final acc = total > 0 ? (hit / total) * 100.0 : 0.0;

    final perDrumAnalysis = <DrumPad, TimingAnalysis>{};
    for (final entry in _padDeltas.entries) {
      if (entry.value.length >= 3) {
        perDrumAnalysis[entry.key] = _timingEngine.analyse(entry.value);
      }
    }

    final globalAnalysis =
        _allDeltas.isNotEmpty ? _timingEngine.analyse(_allDeltas) : null;

    return PerformanceSession(
      id: '${_clock.currentTimeMicros()}',
      song: currentSong!,
      startedAt: _startTime ??
          DateTime.fromMicrosecondsSinceEpoch(_clock.currentTimeMicros()),
      hitResults: const [],
      totalScore: _score,
      accuracyPercent: acc,
      perfectCount: _perfect,
      goodCount: _good,
      okayCount: _early + _late,
      missCount: _miss,
      maxCombo: _maxCombo,
      xpEarned: _calcXp(acc),
      perDrumAnalysis: perDrumAnalysis,
      globalAnalysis: globalAnalysis,
      timingEngine: _timingEngine,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TICK (60 FPS)
  // ══════════════════════════════════════════════════════════════════════════
  void _tick() {
    _playUs = _clock.currentTimeMicros() - _startRef;

    _tickCount++;
    if (_audioSyncActive &&
        _hasBackingTrack &&
        _playUs > 0 &&
        _tickCount % 120 == 0) {
      _checkAndCorrectAudioDrift();
    }

    _phSubject.add(_playUs / 1e6);
    _expireNotes();

    final beatUs = (60000000 / (_bpm * _tempo)).round();
    final beat = _playUs ~/ beatUs;
    if (beat != _lastBeat) {
      _lastBeat = beat;
      _metSubject.add(beat % 4);
    }

    if (_loop && _loopEnd != null && _playUs / 1e6 >= _loopEnd!) {
      _restartLoop();
    }

    if (currentSong != null &&
        _playUs >= currentSong!.duration.inMicroseconds) {
      finish();
    }
  }

  void _checkAndCorrectAudioDrift() {
    if (_lastAudioUs <= 0) return;

    // audioPositionForChartTime returns null while still in the pre-gap
    // (audio not started yet) — skip correction in that case.
    final expectedAudioSec = _syncProfile != null
        ? _syncProfile!.audioPositionForChartTime(_playUs / 1e6)
        : _playUs / 1e6;
    if (expectedAudioSec == null) {
      if (_syncProfile != null && _playUs > 500000) {
        debugPrint(
          '[Sync] audioPositionForChartTime() null at ${(_playUs / 1e6).toStringAsFixed(3)}s '
          '— check SongSyncProfile.audioDelaySeconds=${_syncProfile!.audioDelaySeconds.toStringAsFixed(3)}s',
        );
      }
      return;
    }

    final audioPosSec = _lastAudioUs / 1e6;
    // Positive drift  → audio is ahead of chart
    // Negative drift  → audio is behind chart
    final drift    = audioPosSec - expectedAudioSec;
    final absDrift = drift.abs();

    if (absDrift > 0.200) {
      // Gross desync (>200 ms): hard-seek — audible click acceptable here
      // because we have already drifted far enough to cause missed notes.
      debugPrint(
        '[Sync] Hard seek: drift=${(drift * 1000).toStringAsFixed(0)}ms',
      );
      unawaited(
        BackingTrackService.instance.seekTo(
          expectedAudioSec.clamp(0.0, double.infinity),
        ),
      );
    } else if (absDrift > 0.020) {
      // Minor drift (20–200 ms): gentle ±1.5% tempo nudge.
      // audio behind (drift < 0) → speed audio up; ahead (drift > 0) → slow down.
      final correction = drift < 0 ? 1.015 : 0.985;
      debugPrint(
        '[Sync] Nudge: drift=${(drift * 1000).toStringAsFixed(1)}ms '
        'speed=${correction.toStringAsFixed(3)}',
      );
      unawaited(BackingTrackService.instance.setTempoFactor(_baseTempoFactor * correction));

      // After ~1.3 s the small drift should be absorbed; restore base tempo.
      _driftCorrectionTimer?.cancel();
      _driftCorrectionTimer = Timer(const Duration(milliseconds: 1300), () {
        if (_state == EngineState.playing) {
          unawaited(BackingTrackService.instance.setTempoFactor(_baseTempoFactor));
        }
      });
    }
    // < 20 ms: within acceptable tolerance — do nothing.
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MIDI HANDLER
  // ══════════════════════════════════════════════════════════════════════════
  void _onMidi(MidiEvent raw) {
    if (_state != EngineState.playing) return;

    // ── Step 1: Resolve pad via active mapping (GM / Clone Hero / Roland…)
    final normalizedPad = _normalizer.normalize(midiNote: raw.note, channel: raw.channel);
    if (normalizedPad == null) return;

    // ── Step 2: Ghost-note context using resolved pad
    final expectsGhost = AdaptiveMidiStabilizer.nextNoteIsGhost(
      normalizedPad,
      _pending,
      _playUs / 1000.0,
      bpm: _bpm,
    );

    // ── Step 3: Stabilise (debounce / jitter-smooth) using resolved pad
    final stable = _stabilizer.process(raw, normalizedPad, expectsGhost);
    if (stable == null) return;

    // stable.pad is authoritative from here — may differ from normalizedPad
    // when hi-hat open/closed state overrides the initial resolution.
    final pad = stable.pad;

    // ── Step 4: Play drum sound for physical kit
    if (raw.inputSource == InputSourceType.connectedDrum) {
      DrumEngine.instance.hit(pad, velocity: raw.velocity);
    }

    if (kDebugMode) {
      final sourceStr =
          raw.inputSource == InputSourceType.onScreenPad ? 'PAD' : 'DRUM';
      debugPrint(
        '[INPUT] src=$sourceStr pad=${pad.shortName} '
        'note=${raw.note} vel=${raw.velocity} '
        'smoothedMs=${stable.smoothedTimeMs.toStringAsFixed(1)} '
        'playheadMs=${_playUs ~/ 1000}',
      );
    }

    SyncDiagnostics.instance.lastInputSource = raw.inputSource;
    SyncDiagnostics.instance.lastPadId = pad.shortName;
    SyncDiagnostics.instance.lastVelocity = raw.velocity;
    SyncDiagnostics.instance.lastRawArrivalUs = raw.timestampMicros;
    SyncDiagnostics.instance.lastDeviceId = raw.deviceId;

    // Use the jitter-smoothed timestamp consistently for both flam detection
    // and matcher input — eliminates the native-vs-global time domain split.
    final hitMs = stable.smoothedTimeMs;
    final hitUs = _clock.nativeToGlobal((hitMs * 1000).round());

    _recentHits.add(RecentHit(pad: pad, timestampMs: hitMs));
    if (_recentHits.length > 8) _recentHits.removeAt(0);

    if (_matcher.isFlamGhost(hitMs, pad)) return;

    final result = _matcher.match(
      hitTimestampUs: hitUs,
      hitPad: pad,
      hitVelocity: raw.velocity,
      pendingNotes: _pending,
      playheadMs: _playUs / 1000.0,
    );

    _processMatchResult(result, raw, source: raw.inputSource);
  }

  void _processMatchResult(
    MatchResult m,
    MidiEvent raw, {
    InputSourceType source = InputSourceType.connectedDrum,
  }) {
    late HitResult hit;

    if (m.isExtra) {
      _lastGaussian = 0;

      final dummy = NoteEvent(
        pad: m.hitVelocity > 0
            ? (raw.note >= 35 && raw.note <= 36
                ? DrumPad.kick
                : DrumPad.snare)
            : DrumPad.snare,
        midiNote: raw.note,
        beatPosition: 0,
        timeSeconds: _playUs / 1e6,
        velocity: raw.velocity,
      );

      hit = HitResult(
        expected: dummy,
        actual: raw,
        grade: HitGrade.extra,
        timingDeltaMs: 0,
        correctPad: false,
        score: 0,
        inputSource: source,
      );
    } else {
      final grade = _mapGrade(m.grade);
      final int scoreVal = m.padMatch ? m.score : 0;

      hit = HitResult(
        expected: m.expectedNote!,
        actual: raw,
        grade: grade,
        timingDeltaMs: m.deltaMs,
        correctPad: m.padMatch,
        score: scoreVal,
        inputSource: source,
      );

      if (m.padMatch && grade != HitGrade.miss) {
        _allDeltas.add(m.deltaMs);
        final pad = m.expectedNote!.pad;
        _padDeltas.putIfAbsent(pad, () => []).add(m.deltaMs);
        _padVelocities.putIfAbsent(pad, () => []).add(m.hitVelocity);
        _lastGaussian = _timingEngine.gaussianScore(m.deltaMs);
      } else {
        _lastGaussian = 0;
      }
    }

    _hitSubject.add(hit);
    _updateScore(hit);
  }

  HitGrade _mapGrade(TimingGrade g) {
    switch (g) {
      case TimingGrade.perfect:
        return HitGrade.perfect;
      case TimingGrade.good:
        return HitGrade.good;
      case TimingGrade.early:
        return HitGrade.early;
      case TimingGrade.late:
        return HitGrade.late;
      case TimingGrade.miss:
        return HitGrade.miss;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MISS PROCESSING
  // ══════════════════════════════════════════════════════════════════════════
  void _expireNotes() {
    final nowMs = _playUs / 1000.0;
    final limitMs = _timingEngine.windowOkayMs * 1.2;

    _pending.removeWhere((p) {
      if (p.matched) return true;
      final delta = nowMs - p.expectedMs;
      if (delta > limitMs) {
        _registerMiss(p.note);
        return true;
      }
      return false;
    });
  }

  void _registerMiss(NoteEvent note) {
    final hit = HitResult(
      expected: note,
      grade: HitGrade.miss,
      timingDeltaMs: 0,
      correctPad: false,
      score: 0,
    );
    _hitSubject.add(hit);
    _updateScore(hit);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SCORING
  // ══════════════════════════════════════════════════════════════════════════
  void _updateScore(HitResult r) {
    _lastSource = r.inputSource;

    int baseScore = 0;

    switch (r.grade) {
      case HitGrade.perfect:
        _perfect++;
        baseScore = 1000;
        _combo++;
        break;

      case HitGrade.good:
        _good++;
        baseScore = 700;
        _combo++;
        break;

      case HitGrade.early:
        if (r.correctPad) {
          _early++;
          baseScore = 400;
          _combo++;
        } else {
          _miss++;
          _combo = 0;
          baseScore = 0;
        }
        break;

      case HitGrade.late:
        if (r.correctPad) {
          _late++;
          baseScore = 400;
          _combo++;
        } else {
          _miss++;
          _combo = 0;
          baseScore = 0;
        }
        break;

      case HitGrade.miss:
      case HitGrade.extra:
        _miss++;
        _combo = 0;
        baseScore = 0;
        break;
    }

    if (_combo > _maxCombo) {
      _maxCombo = _combo;
    }

    SyncDiagnostics.instance.lastDeltaMs = r.timingDeltaMs;
    SyncDiagnostics.instance.lastJudgement = r.grade.name.toUpperCase();
    SyncDiagnostics.instance.updateInput();

    _score += (baseScore * _multiplier).round();
    _broadcast();
  }

  int get _multiplier {
    if (_combo >= 40) return 4;
    if (_combo >= 20) return 3;
    if (_combo >= 10) return 2;
    return 1;
  }

  void _broadcast() {
    final total = _notes.length;
    final hit = _perfect + _good + _early + _late;

    _scoreSubject.add(
      ScoreState(
        score: _score,
        accuracy: total > 0 ? hit / total : 0,
        combo: _combo,
        maxCombo: _maxCombo,
        multiplier: _multiplier,
        perfectCount: _perfect,
        goodCount: _good,
        earlyCount: _early,
        lateCount: _late,
        missCount: _miss,
        gaussianScore: _lastGaussian,
        lastInputSource: _lastSource,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════
  void _buildPending() {
    _pending.clear();
    for (final n in _notes) {
      _pending.add(PendingNote(n));
    }
  }

  void _resetCounters() {
    _score = _combo = _maxCombo = _perfect = _good = _early = _late = _miss = 0;
    _playUs = 0;
    _lastBeat = -1;
    _lastGaussian = 0;
    _padDeltas.clear();
    _allDeltas.clear();
    _recentHits.clear();
    _padVelocities.clear();
    _matcher.resetContext();
  }

  void _restartLoop() {
    _playUs = ((_loopStart ?? 0) * 1e6).round();
    _startRef = _clock.currentTimeMicros() - _playUs;
    _lastAudioUs = 0;
    _buildPending();

    if (_hasBackingTrack && _syncProfile != null) {
      final audioSec =
          _syncProfile!.audioPositionForChartTime(_playUs / 1e6) ?? 0.0;
      unawaited(BackingTrackService.instance.seekTo(audioSec));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ON-SCREEN PAD INPUT
  // ══════════════════════════════════════════════════════════════════════════

  static const Map<DrumPad, int> _padToNote = {
    DrumPad.kick: 36,
    DrumPad.snare: 38,
    DrumPad.rimshot: 37,
    DrumPad.crossstick: 37,
    DrumPad.hihatClosed: 42,
    DrumPad.hihatPedal: 44,
    DrumPad.hihatOpen: 46,
    DrumPad.crash1: 49,
    DrumPad.crash2: 55,
    DrumPad.ride: 51,
    DrumPad.rideBell: 53,
    DrumPad.tom1: 48,
    DrumPad.tom2: 47,
    DrumPad.tom3: 45,
    DrumPad.floorTom: 43,
  };

  void onScreenHit(DrumPad pad, {int velocity = 100}) {
    // Always play the drum sound — even during count-in or before the engine
    // starts. DrumEngine.hit() is synchronous fire-and-forget → minimum latency.
    DrumEngine.instance.hit(pad, velocity: velocity);

    // Timing evaluation only applies while the engine is actively playing.
    if (_state != EngineState.playing) return;

    final now = _clock.currentTimeMicros();
    final event = MidiEvent(
      type: MidiEventType.noteOn,
      channel: 9,
      note: _padToNote[pad] ?? 38,
      velocity: velocity,
      timestampMicros: now,
      inputSource: InputSourceType.onScreenPad,
    );

    _onMidi(event);
  }

  void setTempoFactor(double f) {
    _tempo = f.clamp(0.5, 1.2);
    _baseTempoFactor = _tempo;
    if (_hasBackingTrack) {
      unawaited(BackingTrackService.instance.setTempoFactor(_tempo));
    }
  }

  void setLoop({double? start, double? end, bool enabled = true}) {
    _loopStart = start;
    _loopEnd = end;
    _loop = enabled;
  }

  void seekChartTo(double seconds) {
    _playUs = (seconds * 1e6).round();
    _startRef = _clock.currentTimeMicros() - _playUs;
    _buildPending();
    _pending.removeWhere((p) => p.note.timeSeconds < seconds);
    _phSubject.add(seconds);
  }

  void _setState(EngineState s) {
    _state = s;
    _stateSubject.add(s);
  }

  int _calcXp(double acc) {
    final base = currentSong?.xpReward ?? 100;
    if (acc >= 95) return (base * 1.5).round();
    if (acc >= 85) return base;
    if (acc >= 70) return (base * 0.7).round();
    return (base * 0.3).round();
  }

  Map<DrumPad, TimingAnalysis> getPerDrumAnalysis() {
    return Map.fromEntries(
      _padDeltas.entries
          .where((e) => e.value.length >= 3)
          .map((e) => MapEntry(e.key, _timingEngine.analyse(e.value))),
    );
  }

  TimingAnalysis? getGlobalAnalysis() =>
      _allDeltas.length >= 3 ? _timingEngine.analyse(_allDeltas) : null;

  Future<void> dispose() async {
    for (final t in _countInTimers) { t.cancel(); }
    _countInTimers.clear();
    _audioDelayTimer?.cancel();
    _audioDelayTimer = null;
    _driftCorrectionTimer?.cancel();
    _driftCorrectionTimer = null;
    _timer?.cancel();
    _midiSub?.cancel();
    _audioPosSub?.cancel();
    _audioPosSub = null;

    await Future.wait([
      _hitSubject.close(),
      _scoreSubject.close(),
      _phSubject.close(),
      _stateSubject.close(),
      _metSubject.close(),
      _countSubject.close(),
    ]);
  }
}

// ── Utility ───────────────────────────────────────────────────────────────────
void unawaited(Future<void> f) {}

bool get hasBackingTrack => false; // per engine instance