// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Song INI Parser
// Parses Clone Hero / Rock Band Network song.ini files.
//
// Format spec:
//   [song]
//   key = value
//   (one section, optional whitespace around '=')
//
// Used by SongPackageLoader to extract metadata, BPM hints, and flags.
// ─────────────────────────────────────────────────────────────────────────────

/// Parsed contents of a Clone Hero / RBN song.ini file.
///
/// All values are stored as strings. Typed accessors provide safe conversion.
class SongIni {
  final Map<String, String> _fields;
  const SongIni._(this._fields);

  // ── Raw access ──────────────────────────────────────────────────────────────

  String?  operator [](String key) => _fields[key.toLowerCase()];
  bool     has(String key)         => _fields.containsKey(key.toLowerCase());

  // ── Typed accessors ─────────────────────────────────────────────────────────

  String  string(String key, {String fallback = ''}) =>
      _fields[key.toLowerCase()] ?? fallback;

  int intValue(String key, {int fallback = 0}) =>
      int.tryParse(_fields[key.toLowerCase()] ?? '') ?? fallback;

  double  doubleValue(String key, {double fallback = 0.0}) =>
      double.tryParse(_fields[key.toLowerCase()] ?? '') ?? fallback;

  bool boolValue(String key, {bool fallback = false}) {
    final v = _fields[key.toLowerCase()];
    if (v == null) return fallback;
    return v.toLowerCase() == 'true' || v == '1';
  }

  // ── Convenience getters ─────────────────────────────────────────────────────

  /// Song title.
  String get name        => string('name', fallback: 'Unknown');

  /// Artist name.
  String get artist      => string('artist', fallback: 'Unknown Artist');

  /// Album name.
  String get album       => string('album', fallback: '');

  /// Release year.
  String get year        => string('year', fallback: '');

  /// Genre (e.g. "Metal", "Rock").
  String get genre       => string('genre', fallback: 'Rock');

  /// Global delay offset in milliseconds (shift chart relative to audio).
  /// Positive = chart is delayed (notes appear later).
  /// Negative = chart is early.
  int get delayMs        => intValue('delay', fallback: 0);

  /// Total song length in milliseconds.
  int get songLengthMs   => intValue('song_length', fallback: 0);

  /// Preview start time in milliseconds (for song-select screen).
  int get previewStartMs => intValue('preview_start_time', fallback: 0);

  /// Whether this chart uses Rock Band Pro Drums notation.
  /// Pro drums add cymbal/tom distinction via marker notes (110-112).
  bool get isProDrums    => boolValue('pro_drums', fallback: false);

  /// Expert drums difficulty rating (1–7, -1 = not charted).
  int get diffDrums      => intValue('diff_drums', fallback: -1);

  /// Expert Pro drums difficulty rating.
  int get diffDrumsReal  => intValue('diff_drums_real', fallback: -1);

  /// Note number used for Star Power / Overdrive phrases.
  int get multiplierNote => intValue('multiplier_note', fallback: 116);

  /// Charter (transcriber) name.
  String get charter     => string('charter', fallback: '');

  /// Video start time offset in milliseconds.
  int get videoStartMs   => intValue('video_start_time', fallback: 0);

  // ── Difficulty helpers ──────────────────────────────────────────────────────

  /// True if there is a charted Expert drum part.
  bool get hasExpertDrums => diffDrums >= 0;

  /// True if there is a charted Expert Pro drum part.
  bool get hasProDrums    => diffDrumsReal >= 0 && isProDrums;

  @override
  String toString() => 'SongIni(name: $name, artist: $artist, '
      'delayMs: $delayMs, songLengthMs: $songLengthMs, proDrums: $isProDrums)';
}

// ─────────────────────────────────────────────────────────────────────────────
// SongIniParser
// ─────────────────────────────────────────────────────────────────────────────

/// Parses the text content of a Clone Hero / RBN song.ini file.
///
/// Usage:
/// ```dart
/// final text = await rootBundle.loadString('assets/songs/aun_coda/song.ini');
/// final ini  = SongIniParser.parse(text);
/// print(ini.name);    // "Aun"
/// print(ini.artist);  // "Coda"
/// ```
class SongIniParser {
  SongIniParser._();

  /// Parse the raw INI file content into a [SongIni] instance.
  static SongIni parse(String content) {
    final fields = <String, String>{};
    bool inSongSection = false;

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();

      // Skip empty lines and comments
      if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) {
        continue;
      }

      // Section header: [song]
      if (line.startsWith('[') && line.endsWith(']')) {
        final section = line.substring(1, line.length - 1).trim().toLowerCase();
        inSongSection = section == 'song';
        continue;
      }

      // Key = value inside [song] section
      if (!inSongSection) continue;

      final eqIdx = line.indexOf('=');
      if (eqIdx < 0) continue;

      final key   = line.substring(0, eqIdx).trim().toLowerCase();
      final value = line.substring(eqIdx + 1).trim();
      if (key.isNotEmpty) {
        fields[key] = value;
      }
    }

    return SongIni._(fields);
  }
}
