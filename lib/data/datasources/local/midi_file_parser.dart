import 'dart:typed_data';
import '../../../domain/entities/entities.dart';

/// Parses Standard MIDI Files (SMF) format 0 and 1.
/// Extracts note events, tempo map, and time signature for the drum track.
class MidiFileParser {

  // ── Public API ─────────────────────────────────────────────────────────────
  MidiParseResult parse(Uint8List bytes, DrumMapping mapping) {
    final reader = _ByteReader(bytes);

    // Parse header
    final header = _parseHeader(reader);

    // Parse all tracks
    final tracks = <_Track>[];
    for (int i = 0; i < header.numTracks; i++) {
      tracks.add(_parseTrack(reader));
    }

    // Build tempo map from all tracks
    final tempoMap = _buildTempoMap(tracks);

    // Find drum track (channel 10 / 0-indexed 9, or track with most note 36-81).
    // Also returns the drum channel so _convertToNoteEvents can filter out
    // non-drum instruments in Format-0 / multi-instrument MIDIs.
    final (:track, :drumChannel) = _findDrumTrackWithChannel(tracks);

    // Convert raw events → NoteEvents with real timestamps
    final noteEvents = _convertToNoteEvents(
      track.events,
      header.ppq,
      tempoMap,
      mapping,
      drumChannel: drumChannel,
    );

    return MidiParseResult(
      noteEvents: noteEvents,
      tempoMap: tempoMap,
      timeSignature: _extractTimeSignature(tracks),
      totalDuration: _calcDuration(noteEvents),
      ppq: header.ppq,
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────
  _Header _parseHeader(_ByteReader r) {
    final magic = r.readUint32();
    if (magic != 0x4D546864) throw const MidiParseException('Invalid MIDI header');
    final chunkLen = r.readUint32();
    assert(chunkLen == 6);
    final format    = r.readUint16();
    final numTracks = r.readUint16();
    final division  = r.readUint16();

    if (division & 0x8000 != 0) {
      throw const MidiParseException('SMPTE time division not supported');
    }
    return _Header(format: format, numTracks: numTracks, ppq: division);
  }

  // ── Track ───────────────────────────────────────────────────────────────────
  _Track _parseTrack(_ByteReader r) {
    final magic = r.readUint32();
    if (magic != 0x4D54726B) throw const MidiParseException('Invalid track chunk');
    final chunkLen = r.readUint32();
    final end = r.position + chunkLen;
    final events = <_RawEvent>[];

    int absoluteTick = 0;
    int runningStatus = 0;
    String trackName = '';

    while (r.position < end) {
      final delta = r.readVarLen();
      absoluteTick += delta;

      int statusByte = r.peekByte();

      // Running status: if high bit not set, reuse last status
      if (statusByte & 0x80 == 0) {
        statusByte = runningStatus;
      } else {
        statusByte = r.readByte();
        if (statusByte != 0xF0 && statusByte != 0xF7 && statusByte != 0xFF) {
          runningStatus = statusByte;
        }
      }

      if (statusByte == 0xFF) {
        // Meta event
        final metaType = r.readByte();
        final metaLen  = r.readVarLen();
        final metaData = r.readBytes(metaLen);
        // Meta type 0x03 = Track Name (used by Clone Hero / RBN to mark "PART DRUMS")
        if (metaType == 0x03 && metaData.isNotEmpty) {
          trackName = String.fromCharCodes(metaData);
        }
        events.add(_MetaEvent(tick: absoluteTick, type: metaType, data: metaData));
      } else if (statusByte == 0xF0 || statusByte == 0xF7) {
        // SysEx
        final sysexLen = r.readVarLen();
        r.skip(sysexLen);
      } else {
        final msgType = statusByte & 0xF0;
        final channel = statusByte & 0x0F;

        switch (msgType) {
          case 0x80: // Note Off
          case 0x90: // Note On
            final note     = r.readByte();
            final velocity = r.readByte();
            events.add(_NoteRaw(
              tick: absoluteTick, channel: channel,
              note: note, velocity: velocity,
              isOn: msgType == 0x90 && velocity > 0,
            ));
            break;
          case 0xA0: r.skip(2); break; // Aftertouch
          case 0xB0: r.skip(2); break; // CC
          case 0xC0: r.skip(1); break; // Program Change
          case 0xD0: r.skip(1); break; // Channel Pressure
          case 0xE0: r.skip(2); break; // Pitch Bend
          default: break;
        }
      }
    }
    r.seekTo(end);
    return _Track(events: events, name: trackName);
  }

  // ── Tempo Map ───────────────────────────────────────────────────────────────
  List<_TempoChange> _buildTempoMap(List<_Track> tracks) {
    final changes = <_TempoChange>[];
    for (final track in tracks) {
      for (final event in track.events) {
        if (event is _MetaEvent && event.type == 0x51 && event.data.length >= 3) {
          final uspb = (event.data[0] << 16) | (event.data[1] << 8) | event.data[2];
          changes.add(_TempoChange(tick: event.tick, microsecondsPerBeat: uspb));
        }
      }
    }
    changes.sort((a, b) => a.tick.compareTo(b.tick));
    if (changes.isEmpty) {
      changes.add(_TempoChange(tick: 0, microsecondsPerBeat: 500000)); // default 120 BPM
    }
    return changes;
  }

  // ── Time Signature ──────────────────────────────────────────────────────────
  /// Returns the FIRST time signature (for legacy compatibility).
  _TimeSignature _extractTimeSignature(List<_Track> tracks) {
    return _buildTimeSigMap(tracks).firstOrNull?.sig
        ?? const _TimeSignature(numerator: 4, denominator: 4);
  }

  /// Returns ALL time signature changes sorted by tick (for odd-time songs).
  List<_TimeSigChange> _buildTimeSigMap(List<_Track> tracks) {
    final changes = <_TimeSigChange>[];
    for (final track in tracks) {
      for (final event in track.events) {
        if (event is _MetaEvent && event.type == 0x58 && event.data.length >= 2) {
          changes.add(_TimeSigChange(
            tick:        event.tick,
            sig:         _TimeSignature(
              numerator:   event.data[0],
              denominator: 1 << event.data[1],
            ),
          ));
        }
      }
    }
    changes.sort((a, b) => a.tick.compareTo(b.tick));
    if (changes.isEmpty) {
      changes.add(_TimeSigChange(
          tick: 0, sig: const _TimeSignature(numerator: 4, denominator: 4)));
    }
    return changes;
  }

  /// Returns the beat position accounting for variable time signatures.
  /// In 7/4 sections, bar length is 7 beats; in 4/4 it's 4 beats.
  // ignore: unused_element
  double _tickToBeatPosition(int tick, int ppq, List<_TimeSigChange> timeSigMap) {
    double beats = 0.0;
    int    lastTick = 0;
    // ignore: unused_local_variable
    _TimeSignature currentSig = timeSigMap.first.sig;

    for (final change in timeSigMap) {
      if (change.tick >= tick) break;
      beats   += (change.tick - lastTick) / ppq.toDouble();
      lastTick = change.tick;
      currentSig = change.sig;
    }
    beats += (tick - lastTick) / ppq.toDouble();
    return beats;
  }

  // ── Find Drum Track ─────────────────────────────────────────────────────────
  //
  // Returns the drum track AND the identified drum channel (-1 = all channels).
  // The drum channel is used by _convertToNoteEvents to filter out non-drum
  // instruments that happen to share the same track in Format-0 MIDIs.
  ({_Track track, int drumChannel}) _findDrumTrackWithChannel(List<_Track> tracks) {
    // 1. Clone Hero / RBN format: track named "PART DRUMS" or similar.
    //    These tracks use MIDI channel 0 (not 9) and note range 95–100.
    //    All channels are valid — return drumChannel = -1 (no filter).
    for (final track in tracks) {
      final n = track.name.toUpperCase();
      if (n == 'PART DRUMS' || n == 'PART DRUMS REAL' || n == 'DRUMS') {
        return (track: track, drumChannel: -1);
      }
    }
    // 2. Standard GM: MIDI channel 10 (0-indexed: 9).
    //    Return drumChannel = 9 so that non-drum notes on other channels
    //    (piano, bass, guitar) are ignored in multi-instrument MIDIs.
    for (final track in tracks) {
      final drumNotes = track.events
          .whereType<_NoteRaw>()
          .where((e) => e.channel == 9)
          .length;
      if (drumNotes > 0) return (track: track, drumChannel: 9);
    }
    // 3. Fallback: track with most notes in extended drum range (35–116).
    //    Upper bound 116 covers Clone Hero star-power and RBN expert notes.
    //    No channel filter since we don't know which channel carries drums.
    _Track? best;
    int bestCount = 0;
    for (final track in tracks) {
      final count = track.events
          .whereType<_NoteRaw>()
          .where((e) => e.note >= 35 && e.note <= 116)
          .length;
      if (count > bestCount) { bestCount = count; best = track; }
    }
    final fallback = best ?? tracks.first;
    return (track: fallback, drumChannel: -1);
  }

  // ── Tick → Seconds Conversion ───────────────────────────────────────────────
  double _tickToSeconds(int tick, int ppq, List<_TempoChange> tempoMap) {
    double seconds = 0;
    int lastTick = 0;
    double currentUspb = 500000; // default 120 BPM

    for (final change in tempoMap) {
      if (change.tick >= tick) break;
      seconds += (change.tick - lastTick) * currentUspb / (ppq * 1000000.0);
      lastTick = change.tick;
      currentUspb = change.microsecondsPerBeat.toDouble();
    }
    seconds += (tick - lastTick) * currentUspb / (ppq * 1000000.0);
    return seconds;
  }

  // ── Convert Raw → NoteEvents ────────────────────────────────────────────────
  //
  // Clone Hero Expert pro-drums emit a base gem note (95–100) AND an optional
  // cymbal marker note (110–112) at the same tick.  The marker determines
  // whether the gem is a cymbal or a tom:
  //
  //   97 alone → tom1 (yellow tom)
  //   97 + 110 → hihatClosed (yellow cymbal)
  //   98 alone → tom2 (blue tom)
  //   98 + 111 → ride (blue cymbal)
  //  100 alone → floorTom (green tom)
  //  100 + 112 → crash1 (green cymbal)
  //
  // Marker notes 110/111/112 are modifiers only and never become NoteEvents.
  List<NoteEvent> _convertToNoteEvents(
    List<_RawEvent> rawEvents,
    int ppq,
    List<_TempoChange> tempoMap,
    DrumMapping mapping, {
    int drumChannel = -1,   // -1 = accept all channels
  }) {
    // Detect Clone Hero Expert mode: mapping covers note 95 or 99 (CH-specific).
    final isChExpert = mapping.noteMap.containsKey(95) ||
                       mapping.noteMap.containsKey(99);

    // Group note-on events by tick.
    // For GM (non-CH-Expert) with a known drum channel (identified via ch 9),
    // skip notes from other channels — this prevents piano/bass/guitar notes
    // in range 35–81 from being misidentified as drum hits in Format-0 MIDIs.
    final byTick = <int, List<_NoteRaw>>{};
    for (final raw in rawEvents) {
      if (raw is! _NoteRaw || !raw.isOn) continue;
      if (!isChExpert && drumChannel >= 0 && raw.channel != drumChannel) continue;
      (byTick[raw.tick] ??= []).add(raw);
    }

    const markerNotes = {110, 111, 112};
    final result = <NoteEvent>[];

    for (final entry in byTick.entries) {
      final tick  = entry.key;
      final notes = entry.value;

      // Collect pro-cymbal markers present at this tick.
      final markers = <int>{};
      for (final n in notes) {
        if (markerNotes.contains(n.note)) markers.add(n.note);
      }

      for (final raw in notes) {
        if (markerNotes.contains(raw.note)) continue; // modifier only — no NoteEvent

        DrumPad? pad;
        if (isChExpert) {
          switch (raw.note) {
            case 97:  pad = markers.contains(110) ? DrumPad.hihatClosed : DrumPad.tom1;    break;
            case 98:  pad = markers.contains(111) ? DrumPad.ride        : DrumPad.tom2;    break;
            case 100: pad = markers.contains(112) ? DrumPad.crash1      : DrumPad.floorTom; break;
            default:  pad = mapping.getPad(raw.note);
          }
        } else {
          pad = mapping.getPad(raw.note);
        }
        if (pad == null) continue;

        result.add(NoteEvent(
          pad:          pad,
          midiNote:     raw.note,
          beatPosition: tick / ppq.toDouble(),
          timeSeconds:  _tickToSeconds(tick, ppq, tempoMap),
          velocity:     raw.velocity,
        ));
      }
    }

    result.sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
    return result;
  }

  Duration _calcDuration(List<NoteEvent> events) {
    if (events.isEmpty) return Duration.zero;
    final lastMs = (events.last.timeSeconds * 1000).round();
    return Duration(milliseconds: lastMs + 2000); // pad 2s at end
  }
}

// ── Result ─────────────────────────────────────────────────────────────────
class MidiParseResult {
  final List<NoteEvent>    noteEvents;
  final List<_TempoChange> tempoMap;
  final _TimeSignature     timeSignature;
  final Duration           totalDuration;
  final int                ppq;

  const MidiParseResult({
    required this.noteEvents,
    required this.tempoMap,
    required this.timeSignature,
    required this.totalDuration,
    required this.ppq,
  });

  /// Returns the average BPM (first tempo if single, or initial tempo).
  double get bpm => 60000000 / (tempoMap.first.microsecondsPerBeat.toDouble());

  /// Returns true if this song has tempo changes (e.g. accelerando).
  bool get hasTempoChanges => tempoMap.length > 1;

  /// Returns BPM at a given position in seconds.
  double bpmAt(double seconds) {
    if (tempoMap.length == 1) return bpm;
    _TempoChange current = tempoMap.first;
    double elapsed = 0;
    for (int i = 1; i < tempoMap.length; i++) {
      final segSeconds = (tempoMap[i].tick - tempoMap[i-1].tick) *
          current.microsecondsPerBeat / (ppq * 1e6);
      if (elapsed + segSeconds >= seconds) break;
      elapsed += segSeconds;
      current = tempoMap[i];
    }
    return 60000000 / current.microsecondsPerBeat.toDouble();
  }
}

// ── Private types ──────────────────────────────────────────────────────────
class _Header {
  final int format, numTracks, ppq;
  const _Header({required this.format, required this.numTracks, required this.ppq});
}

class _Track {
  final List<_RawEvent> events;
  /// Track name from Meta type 0x03 (Track Name) event.
  /// Set for Clone Hero / RBN files (e.g. "PART DRUMS").
  final String name;
  const _Track({required this.events, this.name = ''});
}

abstract class _RawEvent { final int tick; const _RawEvent({required this.tick}); }
class _NoteRaw extends _RawEvent {
  final int channel, note, velocity;
  final bool isOn;
  const _NoteRaw({required super.tick, required this.channel, required this.note, required this.velocity, required this.isOn});
}
class _MetaEvent extends _RawEvent {
  final int type;
  final List<int> data;
  const _MetaEvent({required super.tick, required this.type, required this.data});
}

class _TempoChange {
  final int tick, microsecondsPerBeat;
  const _TempoChange({required this.tick, required this.microsecondsPerBeat});
}

class _TimeSignature {
  final int numerator, denominator;
  const _TimeSignature({required this.numerator, required this.denominator});
}

// ── Byte Reader ────────────────────────────────────────────────────────────
class _TimeSigChange {
  final int          tick;
  final _TimeSignature sig;
  const _TimeSigChange({required this.tick, required this.sig});
}

extension _ListFirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _ByteReader {
  final Uint8List _bytes;
  int _pos = 0;

  _ByteReader(this._bytes);

  int get position => _pos;

  int peekByte() => _bytes[_pos];

  int readByte() => _bytes[_pos++];

  int readUint16() {
    final v = (_bytes[_pos] << 8) | _bytes[_pos + 1];
    _pos += 2;
    return v;
  }

  int readUint32() {
    final v = (_bytes[_pos] << 24) | (_bytes[_pos+1] << 16) | (_bytes[_pos+2] << 8) | _bytes[_pos+3];
    _pos += 4;
    return v;
  }

  int readVarLen() {
    int value = 0;
    int b;
    do {
      b = readByte();
      value = (value << 7) | (b & 0x7F);
    } while (b & 0x80 != 0);
    return value;
  }

  List<int> readBytes(int count) {
    final result = _bytes.sublist(_pos, _pos + count);
    _pos += count;
    return result;
  }

  void skip(int n) => _pos += n;
  void seekTo(int pos) => _pos = pos;
}

class MidiParseException implements Exception {
  final String message;
  const MidiParseException(this.message);
  @override String toString() => 'MidiParseException: $message';
}

// ═══════════════════════════════════════════════════════════════════════════
// ChartFileParser  —  Clone Hero / Moonscraper  .chart  format
// ═══════════════════════════════════════════════════════════════════════════

/// Parses a Clone Hero .chart text file and returns a [MidiParseResult]
/// fully compatible with the rest of the NavaDrummer pipeline.
///
/// Only [ExpertDrums] is read for notes.  BPM / time-sig come from [SyncTrack].
///
/// Drum note → [DrumPad] mapping:
///   0 / 5 → kick          (bass pedal 1 / 2)
///   1     → snare         (red)
///   2     → hihatClosed   (yellow — resolved later via pro-marker logic)
///   3     → tom2          (blue   — resolved later via pro-marker logic)
///   4     → crash1        (green  — resolved later via pro-marker logic)
///   32    → rimshot       (sentinel: yellow cymbal marker)
///   33    → rideBell      (sentinel: blue   cymbal marker)
///   34    → crash2        (sentinel: green  cymbal marker)
class ChartFileParser {
  MidiParseResult parse(String text) {
    final resolution = _parseResolution(text);
    final tempoMap   = _parseTempoMap(text);
    final timeSig    = _parseTimeSig(text);
    final notes      = _parseDrumSection(text, resolution, tempoMap);

    return MidiParseResult(
      noteEvents:    notes,
      tempoMap:      tempoMap,
      timeSignature: timeSig,
      totalDuration: _calcDuration(notes),
      ppq:           resolution,
    );
  }

  // ── [Song] ──────────────────────────────────────────────────────────────

  int _parseResolution(String text) {
    final m = RegExp(
      r'^\s*Resolution\s*=\s*(\d+)',
      multiLine: true,
    ).firstMatch(text);
    return int.tryParse(m?.group(1) ?? '') ?? 192;
  }

  // ── [SyncTrack] ─────────────────────────────────────────────────────────

  List<_TempoChange> _parseTempoMap(String text) {
    final section = _section(text, 'SyncTrack');
    final changes = <_TempoChange>[];

    for (final line in section.split('\n')) {
      // "tick = BPM value"  — value = actualBPM × 1000
      final m = RegExp(r'^\s*(\d+)\s*=\s*BPM\s+(\d+)').firstMatch(line);
      if (m == null) continue;
      final tick  = int.parse(m.group(1)!);
      final value = int.parse(m.group(2)!);         // BPM × 1000
      // μs/beat = 60 000 000 / bpm = 60 000 000 000 / value
      final uspb  = (60000000000.0 / value).round();
      changes.add(_TempoChange(tick: tick, microsecondsPerBeat: uspb));
    }

    changes.sort((a, b) => a.tick.compareTo(b.tick));
    if (changes.isEmpty) {
      changes.add(_TempoChange(tick: 0, microsecondsPerBeat: 500000)); // 120 BPM
    }
    return changes;
  }

  _TimeSignature _parseTimeSig(String text) {
    final section = _section(text, 'SyncTrack');
    for (final line in section.split('\n')) {
      // "tick = TS numerator [denomExponent]"  — denominator = 2^denExp (default 2)
      final m = RegExp(
        r'^\s*\d+\s*=\s*TS\s+(\d+)(?:\s+(\d+))?',
      ).firstMatch(line);
      if (m == null) continue;
      final num    = int.parse(m.group(1)!);
      final denExp = int.tryParse(m.group(2) ?? '') ?? 2;
      return _TimeSignature(numerator: num, denominator: 1 << denExp);
    }
    return const _TimeSignature(numerator: 4, denominator: 4);
  }

  // ── [ExpertDrums] ───────────────────────────────────────────────────────

  List<NoteEvent> _parseDrumSection(
    String text,
    int    resolution,
    List<_TempoChange> tempoMap,
  ) {
    final section = _section(text, 'ExpertDrums');
    if (section.isEmpty) return const [];

    // Group chart note numbers by tick.
    final byTick = <int, List<int>>{};
    for (final line in section.split('\n')) {
      // "tick = N noteNum length"
      final m = RegExp(r'^\s*(\d+)\s*=\s*N\s+(\d+)').firstMatch(line);
      if (m == null) continue;
      final tick = int.parse(m.group(1)!);
      final note = int.parse(m.group(2)!);
      (byTick[tick] ??= []).add(note);
    }

    final result = <NoteEvent>[];
    for (final entry in byTick.entries) {
      final tick    = entry.key;
      final timeSec = _tickToSec(tick, resolution, tempoMap);

      for (final note in entry.value.toSet()) {
        final pad = _noteToPad(note);
        if (pad == null) continue;
        result.add(NoteEvent(
          pad:          pad,
          midiNote:     note,
          beatPosition: tick / resolution.toDouble(),
          timeSeconds:  timeSec,
          velocity:     100,
        ));
      }
    }

    result.sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
    return result;
  }

  // ── Note mapping ────────────────────────────────────────────────────────

  DrumPad? _noteToPad(int note) {
    switch (note) {
      case 0:
      case 5:  return DrumPad.kick;
      case 1:  return DrumPad.snare;
      case 2:  return DrumPad.hihatClosed; // yellow (HH or T1 — resolved later)
      case 3:  return DrumPad.tom2;        // blue   (T2 or Ride — resolved later)
      case 4:  return DrumPad.crash1;      // green  (Crash or Floor — resolved later)
      case 32: return DrumPad.rimshot;     // sentinel: yellow cymbal marker
      case 33: return DrumPad.rideBell;    // sentinel: blue   cymbal marker
      case 34: return DrumPad.crash2;      // sentinel: green  cymbal marker
      default: return null;                // star power, open notes, etc.
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  /// Extracts the content between `[SectionName] {` and the closing `}`.
  String _section(String text, String name) {
    final m = RegExp(
      r'\[' + name + r'\]\s*\{([^}]*)\}',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);
    return m?.group(1) ?? '';
  }

  double _tickToSec(int tick, int ppq, List<_TempoChange> tempoMap) {
    double sec      = 0;
    int    lastTick = 0;
    double uspb     = 500000; // default 120 BPM
    for (final change in tempoMap) {
      if (change.tick >= tick) break;
      sec     += (change.tick - lastTick) * uspb / (ppq * 1000000.0);
      lastTick = change.tick;
      uspb     = change.microsecondsPerBeat.toDouble();
    }
    sec += (tick - lastTick) * uspb / (ppq * 1000000.0);
    return sec;
  }

  Duration _calcDuration(List<NoteEvent> events) {
    if (events.isEmpty) return Duration.zero;
    return Duration(milliseconds: (events.last.timeSeconds * 1000).round() + 2000);
  }
}
