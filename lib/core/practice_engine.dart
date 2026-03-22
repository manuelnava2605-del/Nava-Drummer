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
import 'audio_service.dart';
import 'backing_track_service.dart';
import 'global_timing_controller.dart';
import 'advanced_matching.dart';
import 'song_sync_profile.dart';
import 'sync_diagnostics.dart';

export 'global_timing_controller.dart' show TimingAnalysis, TimingBias, TimingTrend;

// ── Engine state ──────────────────────────────────────────────────────────────
enum EngineState { idle, ready, countIn, playing, paused, finished }

// ── Score snapshot emitted every hit ─────────────────────────────────────────
class ScoreState {
  final int    score, combo, maxCombo, multiplier;
  final double accuracy;        // 0–1
  final int    perfectCount, goodCount, earlyCount, lateCount, missCount;
  final double gaussianScore;   // last hit Gaussian score 0–1
  /// Source of the most-recent hit (for HUD input-source indicator).
  final InputSourceType lastInputSource;

  const ScoreState({
    required this.score,        required this.accuracy,
    required this.combo,        required this.maxCombo,
    required this.multiplier,   required this.perfectCount,
    required this.goodCount,    required this.earlyCount,
    required this.lateCount,    required this.missCount,
    this.gaussianScore = 0,
    this.lastInputSource = InputSourceType.connectedDrum,
  });

  factory ScoreState.initial() => const ScoreState(
    score:0, accuracy:0, combo:0, maxCombo:0, multiplier:1,
    perfectCount:0, goodCount:0, earlyCount:0, lateCount:0, missCount:0,
  );

  String get accuracyString => '${(accuracy*100).toStringAsFixed(1)}%';
}

// ═══════════════════════════════════════════════════════════════════════════
// PracticeEngine
// ═══════════════════════════════════════════════════════════════════════════
class PracticeEngine {
  final MidiEngine _midi;

  // ── Sub-systems (injected at loadSong) ─────────────────────────────────────
  late MathTimingEngine    _timingEngine;
  late ContextAwareMatcher _matcher;
  late AdaptiveMidiStabilizer _stabilizer;
  late DrumNoteNormalizer  _normalizer;
  final GlobalTimingController _clock = GlobalTimingController.instance;

  // ── Config ─────────────────────────────────────────────────────────────────
  Song?           currentSong;
  List<NoteEvent> _notes   = [];
  DrumMapping?    _mapping;
  double          _tempo   = 1.0;   // 0.5–1.2
  bool            _loop    = false;
  bool            _hasBackingTrack = false;
  double?         _loopStart, _loopEnd;
  int             _bpm     = 120;
  int             _userLevel = 1;
  double          _recentAccuracy = 70.0;

  // ── Engine state ───────────────────────────────────────────────────────────
  EngineState _state   = EngineState.idle;
  EngineState get state => _state;
  int         _playUs  = 0;
  int         _startRef = 0;
  DateTime?   _startTime;
  int         _lastBeat = -1;

  // ── Scoring state ──────────────────────────────────────────────────────────
  int    _score=0, _combo=0, _maxCombo=0;
  int    _perfect=0, _good=0, _early=0, _late=0, _miss=0;
  InputSourceType _lastSource = InputSourceType.connectedDrum;
  double _lastGaussian = 0;

  // ── Per-drum timing history (for AI analysis) ──────────────────────────────
  final Map<DrumPad, List<double>> _padDeltas   = {};
  final List<double>               _allDeltas   = [];
  final Map<DrumPad, List<int>>    _padVelocities = {};
  final List<RecentHit>            _recentHits  = [];

  // ── Pending notes queue ────────────────────────────────────────────────────
  final List<PendingNote> _pending = [];

  // ── Streams ────────────────────────────────────────────────────────────────
  final _hitSubject    = PublishSubject<HitResult>();
  final _scoreSubject  = BehaviorSubject<ScoreState>.seeded(ScoreState.initial());
  final _phSubject     = BehaviorSubject<double>.seeded(0);
  final _stateSubject  = BehaviorSubject<EngineState>.seeded(EngineState.idle);
  final _metSubject    = PublishSubject<int>();
  final _countSubject  = PublishSubject<int>();

  Stream<HitResult>   get hitResults    => _hitSubject.stream;
  Stream<ScoreState>  get scoreUpdates  => _scoreSubject.stream;
  Stream<double>      get playheadTime  => _phSubject.stream;
  Stream<EngineState> get stateChanges  => _stateSubject.stream;
  Stream<int>         get metronomeBeat => _metSubject.stream;
  Stream<int>         get countInBeat   => _countSubject.stream;
  int  get currentCombo     => _combo;
  bool get hasBackingTrack  => _hasBackingTrack;

  StreamSubscription?      _midiSub;
  StreamSubscription<Duration>? _audioPosSub;
  Timer?                   _timer;

  // Sync profile for the current song (set at loadSong)
  SongSyncProfile?         _syncProfile;

  // Last audio position from just_audio (authoritative clock when playing)
  int                      _lastAudioUs = 0;
  bool                     _audioSyncActive = false;

  // Counter for periodic audio drift correction (every ~2s)
  int                      _tickCount = 0;

  PracticeEngine({required MidiEngine midiEngine}) : _midi = midiEngine;

  // ══════════════════════════════════════════════════════════════════════════
  // LOAD
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> loadSong(
    Song song,
    List<NoteEvent> notes,
    DrumMapping mapping, {
    int    userLevel       = 1,
    double recentAccuracy  = 70.0,
    double swingRatio      = 0.0,
  }) async {
    currentSong      = song;
    _bpm             = song.bpm;
    _mapping         = mapping;
    _userLevel       = userLevel;
    _recentAccuracy  = recentAccuracy;

    // ── Initialise sub-systems ────────────────────────────────────────────
    _timingEngine = MathTimingEngine.forSong(
      bpm:           _bpm,
      userLevel:     userLevel,
      recentAccuracy:recentAccuracy,
      swingRatio:    swingRatio,
    );
    _matcher    = ContextAwareMatcher(_timingEngine);
    _stabilizer = AdaptiveMidiStabilizer();
    _normalizer = DrumNoteNormalizer(
        brand: _mapping?.brand ?? DrumKitBrand.generic);

    // Apply swing to note timestamps if needed
    if (swingRatio > 0) {
      notes = notes.map((n) {
        final adjustedMs = _timingEngine.swingAdjusted(
            n.timeSeconds * 1000, n.beatPosition);
        return NoteEvent(
          pad:          n.pad,
          midiNote:     n.midiNote,
          beatPosition: n.beatPosition,
          timeSeconds:  adjustedMs / 1000.0,
          velocity:     n.velocity,
          duration:     n.duration,
        );
      }).toList();
    }

    // Normalise pads from MIDI file
    _notes = _normalizer.normalizeEvents(notes);
    _notes.sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));

    _resetCounters();
    _buildPending();
    // Load backing track if available
    _hasBackingTrack = await BackingTrackService.instance.load(song);
    await BackingTrackService.instance.setTempoFactor(_tempo);

    // Load sync profile for this song (authoritative timing parameters)
    _syncProfile = SongSyncRegistry.forSong(song.id);

    // Seed diagnostics with BPM info and sync profile
    SyncDiagnostics.instance.configuredBpm     = _bpm.toDouble();
    SyncDiagnostics.instance.configuredBeatDur = 60.0 / _bpm;
    SyncDiagnostics.instance.syncProfile       = _syncProfile;

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
    // Build a drum mapping that matches the format detected by the loader.
    final mapping = DrumMapping(
      deviceId: package.isCloneHeroFormat ? 'clone_hero' : 'gm',
      noteMap:  package.isCloneHeroFormat
          ? StandardDrumMaps.cloneHeroExpert
          : StandardDrumMaps.generalMidi,
    );

    // loadSong will try to load the M4A backing track and fail silently
    // (the package song has no .m4a). We override below.
    await loadSong(package.song, package.chart, mapping);

    // ── Override backing track with OGG stem from the package ──────────────
    final hasOgg = await BackingTrackService.instance.loadPackage(package.audio);
    _hasBackingTrack = hasOgg;
    if (hasOgg) {
      await BackingTrackService.instance.setTempoFactor(_tempo);
      debugPrint('[PracticeEngine] Package OGG stem loaded for ${package.id}');
    }

    // ── Override sync profile with auto-derived one from MIDI ───────────────
    _syncProfile = package.syncProfile;
    SyncDiagnostics.instance.syncProfile = _syncProfile;

    debugPrint('[PracticeEngine] loadSongPackage complete: ${package.id}, '
        '${package.noteCount} notes, BPM=${package.syncProfile.bpm.toStringAsFixed(1)}, '
        'hasAudio=$hasOgg');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PLAYBACK CONTROL
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> startWithCountIn() async {
    if (_state != EngineState.ready) return;
    _setState(EngineState.countIn);
    final beatMs = (60000 / (_bpm * _tempo)).round();
    for (int i = 1; i <= 4; i++) {
      _countSubject.add(i);
      await Future.delayed(Duration(milliseconds: beatMs));
    }
    start();
  }

  void start() {
    if (_state == EngineState.countIn ||
        _state == EngineState.ready   ||
        _state == EngineState.paused) {
      _startTime = DateTime.fromMicrosecondsSinceEpoch(_clock.currentTimeMicros());
      _startRef  = _clock.currentTimeMicros() - _playUs;
      _setState(EngineState.playing);

      if (_hasBackingTrack) {
        _startBackingTrackSynced();
      }

      _midiSub   = _midi.midiEvents.listen(_onMidi);
      _timer     = Timer.periodic(
          const Duration(microseconds: 16667), (_) => _tick());
    }
  }

  /// Start the backing track with proper sync offset from SongSyncProfile.
  ///
  /// Strategy:
  ///   - The engine clock starts at 0 (or _playUs for resume).
  ///   - The MIDI chart for te_quiero has 7.2s of silence before note 1.
  ///   - The audio file has 42.67ms of AAC encoder delay.
  ///   - We must delay audio start by (chartOffsetSeconds - audioOffsetSeconds)
  ///     so that audio beat 1 aligns with chart beat 1.
  ///   - We also seek the audio past its encoder delay before playing.
  void _startBackingTrackSynced() {
    final profile = _syncProfile;

    if (profile == null) {
      // No profile: start immediately at position 0
      unawaited(BackingTrackService.instance.seekTo(0).then((_) =>
          BackingTrackService.instance.play()));
      _subscribeAudioPosition();
      return;
    }

    // audioSeekSeconds: skip encoder delay in audio file
    // audioDelaySeconds: wait this long before starting audio
    //   (when chart has more pre-gap than audio, e.g. te_quiero: 7.2s - 0.043s = 7.157s)
    final seekSec  = profile.audioSeekSeconds;
    final delaySec = profile.audioDelaySeconds;

    if (delaySec > 0) {
      // Chart starts immediately; audio must be delayed to align with chart beat 1.
      unawaited(BackingTrackService.instance.seekTo(seekSec).then((_) async {
        await Future.delayed(Duration(microseconds: (delaySec * 1e6).round()));
        if (_state == EngineState.playing) {
          await BackingTrackService.instance.play();
          _subscribeAudioPosition();
        }
      }));
    } else {
      // Audio starts immediately (possibly after seek to skip encoder delay).
      unawaited(BackingTrackService.instance.seekTo(seekSec).then((_) async {
        await BackingTrackService.instance.play();
        _subscribeAudioPosition();
      }));
    }
  }

  /// Subscribe to just_audio's position stream as the authoritative clock.
  /// When a backing track is playing, we correct _playUs toward audio position
  /// rather than the other way around.
  void _subscribeAudioPosition() {
    _audioPosSub?.cancel();
    final stream = BackingTrackService.instance.authoritativePositionStream;
    if (stream == null) return;

    _audioSyncActive = true;
    _audioPosSub = stream.listen((pos) {
      if (_state != EngineState.playing) return;
      _lastAudioUs = pos.inMicroseconds;

      // Write to diagnostics
      SyncDiagnostics.instance.audioPositionSec = pos.inMicroseconds / 1e6;
      SyncDiagnostics.instance.gamePlayheadSec  = _playUs / 1e6;
      SyncDiagnostics.instance.update();
    });
  }

  void pause() {
    if (_state != EngineState.playing) return;
    _timer?.cancel(); _midiSub?.cancel();
    _audioPosSub?.cancel(); _audioPosSub = null;
    _audioSyncActive = false;
    if (_hasBackingTrack) BackingTrackService.instance.pause();
    _setState(EngineState.paused);
  }

  void resume() {
    if (_state != EngineState.paused) return;
    _startRef = _clock.currentTimeMicros() - _playUs;
    _setState(EngineState.playing);
    _midiSub = _midi.midiEvents.listen(_onMidi);
    _timer   = Timer.periodic(
        const Duration(microseconds: 16667), (_) => _tick());
    if (_hasBackingTrack) {
      // Re-seek audio to the chart-aligned position before resuming.
      // This corrects any drift that accumulated while paused.
      final profile = _syncProfile;
      if (profile != null) {
        final expectedAudioSec = profile.audioPositionForChartTime(_playUs / 1e6);
        if (expectedAudioSec != null) {
          unawaited(BackingTrackService.instance
              .seekTo(expectedAudioSec)
              .then((_) async {
            await BackingTrackService.instance.play();
            _subscribeAudioPosition();
          }));
        } else {
          // Still in the pre-gap: re-run the full synced start from current position
          _startBackingTrackSynced();
        }
      } else {
        unawaited(BackingTrackService.instance.resume());
        _subscribeAudioPosition();
      }
    }
  }

  void stop() {
    _timer?.cancel(); _midiSub?.cancel();
    _audioPosSub?.cancel(); _audioPosSub = null;
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
    _timer?.cancel(); _midiSub?.cancel();
    _audioPosSub?.cancel(); _audioPosSub = null;
    _audioSyncActive = false;
    _setState(EngineState.finished);

    final total = _notes.length;
    final hit   = _perfect + _good + _early + _late;
    final acc   = total > 0 ? (hit / total) * 100.0 : 0.0;

    // Per-drum analysis
    final perDrumAnalysis = <DrumPad, TimingAnalysis>{};
    for (final entry in _padDeltas.entries) {
      if (entry.value.length >= 3) {
        perDrumAnalysis[entry.key] = _timingEngine.analyse(entry.value);
      }
    }

    // Global timing analysis
    final globalAnalysis = _allDeltas.isNotEmpty
        ? _timingEngine.analyse(_allDeltas)
        : null;

    return PerformanceSession(
      id:              '${_clock.currentTimeMicros()}',
      song:            currentSong!,
      startedAt:       _startTime ?? DateTime.fromMicrosecondsSinceEpoch(_clock.currentTimeMicros()),
      hitResults:      const [],
      totalScore:      _score,
      accuracyPercent: acc,
      perfectCount:    _perfect,
      goodCount:       _good,
      okayCount:       _early + _late,  // stored combined for Firestore compat
      missCount:       _miss,
      maxCombo:        _maxCombo,
      xpEarned:        _calcXp(acc),
      perDrumAnalysis: perDrumAnalysis,
      globalAnalysis:  globalAnalysis,
      timingEngine:    _timingEngine,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TICK (60 FPS)
  // ══════════════════════════════════════════════════════════════════════════
  void _tick() {
    _playUs = _clock.currentTimeMicros() - _startRef;

    // ── Audio drift correction ──────────────────────────────────────────────
    // Every ~2 seconds, if a backing track is playing, check drift between
    // the wall-clock engine position and the audio player's reported position.
    //
    // The audio is adjusted to the chart position, NOT the other way around,
    // because the chart timestamps are the authoritative score reference.
    // However, if the audio drifts significantly, the user will hear it.
    // We correct by seeking audio to the current chart position.
    //
    // chartOffsetSeconds accounts for the pre-gap: the audio backing track
    // starts at beat 1 of the song, but _playUs counts from chart tick 0
    // (which is 7.2s before beat 1 for te_quiero).
    _tickCount++;
    if (_audioSyncActive && _hasBackingTrack && _playUs > 0 &&
        _tickCount % 120 == 0) {  // ~every 2 seconds at 60fps
      _checkAndCorrectAudioDrift();
    }

    _phSubject.add(_playUs / 1e6);
    _expireNotes();

    // Metronome
    final beatUs  = (60000000 / (_bpm * _tempo)).round();
    final beat    = _playUs ~/ beatUs;
    if (beat != _lastBeat) {
      _lastBeat = beat;
      _metSubject.add(beat % 4);
    }

    // Loop
    if (_loop && _loopEnd != null && _playUs / 1e6 >= _loopEnd!) _restartLoop();

    // Song end
    if (currentSong != null &&
        _playUs >= currentSong!.duration.inMicroseconds) finish();
  }

  /// Checks drift between engine wall-clock position and audio position.
  /// If drift exceeds 50ms, seeks audio to the expected position.
  ///
  /// Expected audio position = (_playUs/1e6) - audioDelaySeconds + audioSeekSeconds
  /// where audioDelaySeconds accounts for the chart pre-gap offset.
  void _checkAndCorrectAudioDrift() {
    if (_lastAudioUs <= 0) return;
    final audioPosSec = _lastAudioUs / 1e6;

    // Calculate where the audio SHOULD be given current chart position.
    // audioPositionForChartTime() is the single authoritative formula.
    final expectedAudioSec =
        _syncProfile?.audioPositionForChartTime(_playUs / 1e6) ?? (_playUs / 1e6);

    final drift = (audioPosSec - expectedAudioSec).abs();
    if (drift > 0.020) {  // 20ms threshold — 50ms was too loose for live drumming
      // Drift exceeds 50ms — seek audio to correct position
      unawaited(BackingTrackService.instance.seekTo(
          expectedAudioSec.clamp(0.0, double.infinity)));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MIDI HANDLER
  // ══════════════════════════════════════════════════════════════════════════
  void _onMidi(MidiEvent raw) {
    if (_state != EngineState.playing) return;

    // Phase 4+5: adaptive stabilize (pass ghost context)
    final expectsGhost = AdaptiveMidiStabilizer.nextNoteIsGhost(
        StandardDrumMaps.generalMidi[raw.note] ?? DrumPad.snare,
        _pending, _playUs / 1000.0);
    final stable = _stabilizer.process(raw, patternExpectsGhost: expectsGhost);
    if (stable == null) return;

    // Phase 5: normalise
    final pad = _normalizer.normalize(
        midiNote: raw.note, channel: raw.channel);
    if (pad == null) return;

    // 🔊 Play drum sound for connected-drum events.
    // On-screen pad events already played in onScreenHit().
    if (raw.inputSource == InputSourceType.connectedDrum) {
      AudioService.instance.playDrumPad(pad,
          velocityNorm: raw.velocity / 127.0);
    }

    // 🛠️ Debug log (active only in debug mode)
    if (kDebugMode) {
      final sourceStr = raw.inputSource == InputSourceType.onScreenPad
          ? 'PAD' : 'DRUM';
      debugPrint('[INPUT] src=$sourceStr pad=${pad.shortName} '
          'note=${raw.note} vel=${raw.velocity} '
          'arrivalMs=${raw.timestampMicros ~/ 1000} '
          'playheadMs=${_playUs ~/ 1000}');
    }

    // Feed input diagnostics
    SyncDiagnostics.instance.lastInputSource  = raw.inputSource;
    SyncDiagnostics.instance.lastPadId        = pad.shortName;
    SyncDiagnostics.instance.lastVelocity     = raw.velocity;
    SyncDiagnostics.instance.lastRawArrivalUs = raw.timestampMicros;
    SyncDiagnostics.instance.lastDeviceId     = raw.deviceId;

    // Track recent hits for flam/chord detection
    final hitMs = raw.timestampMicros / 1000.0;
    _recentHits.add(RecentHit(pad: pad, timestampMs: hitMs));
    if (_recentHits.length > 8) _recentHits.removeAt(0);

    // Flam check
    if (_matcher.isFlamGhost(hitMs, pad)) {
      return; // ghost stroke of a flam — ignore
    }

    // Dynamic window
    final windowMs = _matcher.dynamicWindowMs(
        _pending, _timingEngine.windowOkayMs);

    // Phase 1+2: context-aware + perceptual matching
    final result = _matcher.match(
      hitTimestampUs: _clock.nativeToGlobal(raw.timestampMicros),
      hitPad:         pad,
      hitVelocity:    raw.velocity,
      pendingNotes:   _pending,
      playheadMs:     _playUs / 1000.0,
    );

    _processMatchResult(result, raw, source: raw.inputSource);
  }

  void _processMatchResult(MatchResult m, MidiEvent raw, {InputSourceType source = InputSourceType.connectedDrum}) {
    // Convert MatchResult → HitResult (domain entity)
    late HitResult hit;

    if (m.isExtra) {
      // No expected note found
      final dummy = NoteEvent(
        pad: m.hitVelocity > 0
            ? (raw.note >= 35 && raw.note <= 36 ? DrumPad.kick : DrumPad.snare)
            : DrumPad.snare,
        midiNote:     raw.note,
        beatPosition: 0,
        timeSeconds:  _playUs / 1e6,
        velocity:     raw.velocity,
      );
      hit = HitResult(
        expected:      dummy,
        actual:        raw,
        grade:         HitGrade.extra,
        timingDeltaMs: 0,
        correctPad:    false,
        score:         0,
        inputSource:   source,
      );
    } else {
      // Map MathTimingEngine grade → HitGrade
      final grade = _mapGrade(m.grade);
      final int scoreVal = m.padMatch ? m.score : 0;

      hit = HitResult(
        expected:      m.expectedNote!,
        actual:        raw,
        grade:         grade,
        timingDeltaMs: m.deltaMs,
        correctPad:    m.padMatch,
        score:         scoreVal,
        inputSource:   source,
      );

      // Record delta + velocity for AI analysis
      if (m.padMatch && grade != HitGrade.miss) {
        _allDeltas.add(m.deltaMs);
        final pad = m.expectedNote!.pad;
        _padDeltas.putIfAbsent(pad, () => []).add(m.deltaMs);
        _padVelocities.putIfAbsent(pad, () => []).add(m.hitVelocity);
        _lastGaussian = _timingEngine.gaussianScore(m.deltaMs);
      }
    }

    _hitSubject.add(hit);
    _updateScore(hit);
  }

  HitGrade _mapGrade(TimingGrade g) {
    switch (g) {
      case TimingGrade.perfect: return HitGrade.perfect;
      case TimingGrade.good:    return HitGrade.good;
      case TimingGrade.early:   return HitGrade.early;
      case TimingGrade.late:    return HitGrade.late;
      case TimingGrade.miss:    return HitGrade.miss;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MISS PROCESSING
  // ══════════════════════════════════════════════════════════════════════════
  void _expireNotes() {
    final nowMs    = _playUs / 1000.0;   // chart playhead, NOT session wall-clock
    final limitMs  = _timingEngine.windowOkayMs * 1.5;

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
      expected:      note,
      grade:         HitGrade.miss,
      timingDeltaMs: 0,
      correctPad:    false,
      score:         0,
    );
    _hitSubject.add(hit);
    _updateScore(hit);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SCORING
  // ══════════════════════════════════════════════════════════════════════════
  void _updateScore(HitResult r) {
    _lastSource = r.inputSource;
    if (r.grade == HitGrade.miss || r.grade == HitGrade.extra) {
      _miss++; _combo = 0;
    } else {
      switch (r.grade) {
        case HitGrade.perfect: _perfect++; break;
        case HitGrade.good:    _good++;    break;
        case HitGrade.early:   _early++;   break;
        case HitGrade.late:    _late++;    break;
        default: break;
      }
      _combo++;
      if (_combo > _maxCombo) _maxCombo = _combo;
    }

    // Update diagnostics with timing feedback
    SyncDiagnostics.instance.lastDeltaMs   = r.timingDeltaMs;
    SyncDiagnostics.instance.lastJudgement = r.grade.name.toUpperCase();
    SyncDiagnostics.instance.updateInput();

    _score += r.score * _multiplier;
    _broadcast();
  }

  int get _multiplier {
    if (_combo >= 50) return 8;
    if (_combo >= 25) return 4;
    if (_combo >= 10) return 2;
    return 1;
  }

  void _broadcast() {
    final total = _notes.length;
    final hit   = _perfect + _good + _early + _late;
    _scoreSubject.add(ScoreState(
      score:          _score,
      accuracy:       total > 0 ? hit / total : 0,
      combo:          _combo,
      maxCombo:       _maxCombo,
      multiplier:     _multiplier,
      perfectCount:   _perfect,
      goodCount:      _good,
      earlyCount:     _early,
      lateCount:      _late,
      missCount:      _miss,
      gaussianScore:  _lastGaussian,
      lastInputSource: _lastSource,
    ));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════
  void _buildPending() {
    _pending.clear();
    for (final n in _notes) _pending.add(PendingNote(n));
  }

  void _resetCounters() {
    _score=_combo=_maxCombo=_perfect=_good=_early=_late=_miss=0;
    _playUs=0; _lastBeat=-1; _lastGaussian=0;
    _padDeltas.clear(); _allDeltas.clear(); _recentHits.clear();
    _padVelocities.clear();
    _matcher.resetContext();
  }

  void _restartLoop() {
    _playUs      = ((_loopStart ?? 0) * 1e6).round();
    _startRef    = _clock.currentTimeMicros() - _playUs;
    _lastAudioUs = 0;
    _buildPending();
    // Re-align backing track to loop start position
    if (_hasBackingTrack && _syncProfile != null) {
      final audioSec = _syncProfile!.audioPositionForChartTime(_playUs / 1e6) ?? 0.0;
      unawaited(BackingTrackService.instance.seekTo(audioSec));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ON-SCREEN PAD INPUT
  // ══════════════════════════════════════════════════════════════════════════

  /// Standard General MIDI note number for each DrumPad.
  /// Used when on-screen pad taps need to synthesize a MidiEvent.
  static const Map<DrumPad, int> _padToNote = {
    DrumPad.kick:        36,
    DrumPad.snare:       38,
    DrumPad.rimshot:     37,
    DrumPad.crossstick:  37,
    DrumPad.hihatClosed: 42,
    DrumPad.hihatPedal:  44,
    DrumPad.hihatOpen:   46,
    DrumPad.crash1:      49,
    DrumPad.crash2:      55,
    DrumPad.ride:        51,
    DrumPad.rideBell:    53,
    DrumPad.tom1:        48,
    DrumPad.tom2:        47,
    DrumPad.tom3:        45,
    DrumPad.floorTom:    43,
  };

  /// Called by the on-screen DrumPadView when a virtual pad is tapped.
  ///
  /// Plays the drum sound immediately, then routes the hit through the same
  /// [_onMidi] pipeline as real MIDI events so evaluation logic is identical.
  void onScreenHit(DrumPad pad, {int velocity = 100}) {
    if (_state != EngineState.playing) return;
    // Sound is played here so it fires even if the engine has no note to match
    AudioService.instance.playDrumPad(pad,
        velocityNorm: velocity / 127.0);
    final now = _clock.currentTimeMicros();
    final event = MidiEvent(
      type:           MidiEventType.noteOn,
      channel:        9,
      note:           _padToNote[pad] ?? 38,
      velocity:       velocity,
      timestampMicros: now,
      inputSource:    InputSourceType.onScreenPad,
    );
    _onMidi(event);
  }

  void setTempoFactor(double f) {
    _tempo = f.clamp(0.5, 1.2);
    if (_hasBackingTrack) {
      unawaited(BackingTrackService.instance.setTempoFactor(_tempo));
    }
  }
  void setLoop({double? start, double? end, bool enabled = true}) {
    _loopStart = start; _loopEnd = end; _loop = enabled;
  }

  /// Seek the engine playhead to [seconds] (chart time from tick 0).
  ///
  /// Call this while in [EngineState.ready] or [EngineState.paused] to
  /// start practice from a specific section.  Re-filters [_pending] so only
  /// notes at or after the seek point are evaluated.
  void seekChartTo(double seconds) {
    _playUs   = (seconds * 1e6).round();
    _startRef = _clock.currentTimeMicros() - _playUs;
    // Rebuild pending list and discard notes before the seek point
    _buildPending();
    _pending.removeWhere((p) => p.note.timeSeconds < seconds);
    _phSubject.add(seconds);
  }

  void _setState(EngineState s) { _state = s; _stateSubject.add(s); }

  int _calcXp(double acc) {
    final base = currentSong?.xpReward ?? 100;
    if (acc >= 95) return (base * 1.5).round();
    if (acc >= 85) return base;
    if (acc >= 70) return (base * 0.7).round();
    return (base * 0.3).round();
  }

  /// Per-drum timing analysis (for Phase 8 AI coach).
  Map<DrumPad, TimingAnalysis> getPerDrumAnalysis() {
    return Map.fromEntries(_padDeltas.entries
        .where((e) => e.value.length >= 3)
        .map((e) => MapEntry(e.key, _timingEngine.analyse(e.value))));
  }

  /// Global timing analysis.
  TimingAnalysis? getGlobalAnalysis() =>
      _allDeltas.length >= 3 ? _timingEngine.analyse(_allDeltas) : null;

  Future<void> dispose() async {
    _timer?.cancel(); _midiSub?.cancel();
    _audioPosSub?.cancel(); _audioPosSub = null;
    await Future.wait([
      _hitSubject.close(), _scoreSubject.close(), _phSubject.close(),
      _stateSubject.close(), _metSubject.close(), _countSubject.close(),
    ]);
  }
}

// ── DrumMapping extension ─────────────────────────────────────────────────────
void unawaited(Future<void> f) {}

bool get hasBackingTrack => false; // per engine instance

extension DrumMappingBrand on DrumMapping {
  DrumKitBrand get brand => DrumKitBrand.generic; // override in subclass if needed
}
