// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — MIDI Synth Service
//
// Plays the full MIDI file as audio (all channels) using an SF2 soundfont
// while silencing channel 9 (drums) — the game engine handles drum sounds
// independently via its own sample pool.
//
// Soundfont setup
// ───────────────
//   PRIMARY (recommended): Bundle the SF2 in the app.
//     1. Download TimGM6mb.sf2 (MIT-licensed, ~5.7 MB) from MuseScore or GitHub.
//     2. Place it at:  assets/soundfonts/TimGM6mb.sf2
//     3. Declare in pubspec.yaml:  - assets/soundfonts/
//   The service tries the bundled asset first — no Firebase Storage needed.
//
//   FALLBACK: Firebase Storage download (first run, if no bundled asset).
//     Upload to:  soundfonts/TimGM6mb.sf2
//     The file is cached locally after first download.
//
// Transport model
// ───────────────
//   flutter_pcm_sound is purely callback-driven (no pause/stop API).
//   Pausing is achieved by not feeding in the callback so the buffer drains
//   naturally; the MidiFileSequencer position is preserved because render()
//   is only called when _isPlaying == true.
//
// Dependencies: dart_melty_soundfont, flutter_pcm_sound, firebase_storage,
//               path_provider
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';
import 'package:dart_melty_soundfont/dart_melty_soundfont.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:path_provider/path_provider.dart';

// ── Constants ────────────────────────────────────────────────────────────────

/// Firebase Storage path where the SF2 soundfont is hosted.
const _kSfStoragePath = 'soundfonts/TimGM6mb.sf2';

/// Local cache filename.
const _kSfCacheFile = 'TimGM6mb.sf2';

/// Bundled asset path (only resolves if declared in pubspec.yaml assets).
const _kSfAssetPath = 'assets/soundfonts/TimGM6mb.sf2';

const int _kSampleRate  = 44100;
const int _kChannels    = 2;
const int _kBlockFrames = 4096; // ~93 ms per render call

// ═════════════════════════════════════════════════════════════════════════════
// MidiSynthService
// ═════════════════════════════════════════════════════════════════════════════
class MidiSynthService {
  static final MidiSynthService instance = MidiSynthService._();
  MidiSynthService._();

  // ── Internal state ─────────────────────────────────────────────────────────
  Synthesizer?       _synth;
  MidiFileSequencer? _seq;
  MidiFile?          _midiFile;

  bool   _pcmSetUp    = false;
  bool   _isPlaying   = false;
  bool   _isAvailable = false;
  bool   _rendering   = false; // prevents concurrent render calls
  double _volume      = 0.85; // 0.0–1.0

  // ── Public API ─────────────────────────────────────────────────────────────

  /// True once the soundfont has been successfully loaded.
  bool get isAvailable => _isAvailable;

  // ── Initialization ──────────────────────────────────────────────────────────

  /// Loads the soundfont and configures PCM output.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> init() async {
    if (_isAvailable) return;
    try {
      final sfData = await _loadSoundfontBytes();
      if (sfData == null) {
        debugPrint('[MidiSynth] Soundfont unavailable — synth disabled');
        return;
      }

      _synth = Synthesizer.loadByteData(
        sfData,
        SynthesizerSettings(sampleRate: _kSampleRate),
      );
      _muteDrumChannel();

      if (!_pcmSetUp) {
        await FlutterPcmSound.setup(
          sampleRate: _kSampleRate,
          channelCount: _kChannels,
        );
        await FlutterPcmSound.setFeedThreshold(_kBlockFrames * 2);
        FlutterPcmSound.setFeedCallback(_onFeedRequest);
        _pcmSetUp = true;
      }

      _isAvailable = true;
      debugPrint('[MidiSynth] Ready');
    } catch (e) {
      debugPrint('[MidiSynth] init() error: $e');
    }
  }

  /// Loads a MIDI file and positions the sequencer at tick 0.
  ///
  /// Call this after [init()] and before [play()].
  Future<void> load(Uint8List midiBytes) async {
    if (!_isAvailable) return;
    try {
      _isPlaying = false;
      // MidiFileSequencer has no stop() — just replace the instance.
      _midiFile = MidiFile.fromByteData(ByteData.sublistView(midiBytes));
      _seq = MidiFileSequencer(_synth!);
      _seq!.play(_midiFile!, loop: false);
      _muteDrumChannel();

      debugPrint('[MidiSynth] MIDI loaded');
    } catch (e) {
      debugPrint('[MidiSynth] load() error: $e');
      _seq = null;
    }
  }

  // ── Transport ───────────────────────────────────────────────────────────────

  /// Starts (or resumes) audio output.
  ///
  /// flutter_pcm_sound restarts the feed loop automatically when the
  /// buffer has fully drained (_needsStart == true).
  void play() {
    if (!_isAvailable || _seq == null || _isPlaying) return;
    _isPlaying = true;
    // start() only triggers the callback when _needsStart==true (buffer fully
    // drained). If it returns false the buffer still has data and the callback
    // will fire on its own — but we kick one frame manually to be safe.
    final started = FlutterPcmSound.start();
    if (!started) _onFeedRequest(0);
  }

  /// Pauses audio by no longer feeding in the callback.
  ///
  /// The sequencer position is preserved because render() is only
  /// called when _isPlaying == true.
  void pause() {
    _isPlaying = false;
    // Buffer drains naturally; _needsStart becomes true → play() re-arms it.
  }

  /// Stops and rewinds to the beginning of the MIDI file.
  void stop() {
    _isPlaying = false;
    if (_midiFile != null && _synth != null) {
      // Silence held notes via CC 123 (All Notes Off) on every channel.
      for (int ch = 0; ch < 16; ch++) {
        _synth!.processMidiMessage(
          channel: ch, command: 0xB0, data1: 123, data2: 0,
        );
      }
      // Reposition sequencer to tick 0 by replacing the instance.
      _seq = MidiFileSequencer(_synth!);
      _seq!.play(_midiFile!, loop: false);
      _muteDrumChannel();
    } else {
      _seq = null;
    }
  }

  /// Updates output volume (0.0–1.0). Mirrors the backing-track volume slider.
  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
  }

  /// Releases resources. Call when leaving the practice screen.
  void dispose() {
    stop();
    _seq      = null;
    _midiFile = null;
    // Keep _synth and PCM setup alive — init() is idempotent but
    // FlutterPcmSound.setup() should only be called once per app session.
  }

  // ── PCM feed callback ───────────────────────────────────────────────────────

  void _onFeedRequest(int remainingFrames) {
    if (!_isPlaying || _seq == null) return;
    if (_rendering) return; // prevent concurrent render calls
    _rendering = true;

    try {
      // Re-mute channel 9 before each block so MIDI CC events cannot un-mute it.
      _muteDrumChannel();

      final left  = Float32List(_kBlockFrames);
      final right = Float32List(_kBlockFrames);
      _seq!.render(left, right);

      final vol      = _volume;
      final byteData = ByteData(_kBlockFrames * _kChannels * 2);
      for (int i = 0; i < _kBlockFrames; i++) {
        final l = (left[i].clamp(-1.0, 1.0)  * vol * 32767.0).round();
        final r = (right[i].clamp(-1.0, 1.0) * vol * 32767.0).round();
        byteData.setInt16((i * 2)       * 2, l, Endian.host);
        byteData.setInt16((i * 2 + 1)   * 2, r, Endian.host);
      }

      FlutterPcmSound.feed(PcmArrayInt16(bytes: byteData));
    } finally {
      _rendering = false;
    }
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  /// Silences GM percussion channel (ch 9) via CC 7 (Channel Volume = 0).
  void _muteDrumChannel() {
    _synth?.processMidiMessage(
      channel: 9,
      command: 0xB0,  // Control Change
      data1:   0x07,  // Channel Volume
      data2:   0,
    );
  }

  /// Returns SF2 bytes in priority order:
  ///   1. Bundled Flutter asset
  ///   2. Previously-downloaded local cache
  ///   3. Firebase Storage download (first run)
  Future<ByteData?> _loadSoundfontBytes() async {
    // 1. Bundled asset
    try {
      final data = await rootBundle.load(_kSfAssetPath);
      debugPrint('[MidiSynth] SF2 loaded from bundled asset');
      return data;
    } catch (_) {
      // Not bundled — continue.
    }

    // 2. Local cache
    final cacheFile = await _sfCacheFile();
    if (cacheFile.existsSync()) {
      debugPrint('[MidiSynth] SF2 loaded from cache: ${cacheFile.path}');
      final bytes = await cacheFile.readAsBytes();
      return ByteData.sublistView(bytes);
    }

    // 3. Firebase Storage download
    return _downloadSf(cacheFile);
  }

  Future<ByteData?> _downloadSf(File dest) async {
    debugPrint('[MidiSynth] Downloading soundfont from Firebase Storage...');
    try {
      // Firebase Storage requires an authenticated user — sign in anonymously
      // if no session exists yet. This mirrors the auth guard in RemoteSongRepository.
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
        debugPrint('[MidiSynth] Anonymous sign-in OK');
      }
      await dest.parent.create(recursive: true);
      final ref  = FirebaseStorage.instance.ref(_kSfStoragePath);
      final data = await ref.getData(64 * 1024 * 1024); // 64 MB max
      if (data == null) {
        debugPrint('[MidiSynth] Download returned null');
        return null;
      }
      await dest.writeAsBytes(data);
      debugPrint('[MidiSynth] SF2 cached at ${dest.path}');
      return ByteData.sublistView(data);
    } on FirebaseException catch (e) {
      debugPrint('[MidiSynth] Firebase error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[MidiSynth] SF2 download error: $e');
      return null;
    }
  }

  Future<File> _sfCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/soundfonts/$_kSfCacheFile');
  }
}
