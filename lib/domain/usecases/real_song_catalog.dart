// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Catálogo de Canciones
//
// Solo se listan canciones con contenido REAL:
//   • Paquete completo (song.ini + notes.mid + stems OGG) → packageAssetDir
//   • MIDI transcrito + backing track M4A                 → midiAssetPath
//
// No agregar stubs ni placeholders. Cada entrada debe tener assets funcionales.
// ─────────────────────────────────────────────────────────────────────────────

import '../entities/entities.dart';

class RealSongCatalog {
  static const List<Song> songs = [

    // ══════════════════════════════════════════════════════════════════
    // 📦  PAQUETES CLONE HERO / RBN
    //     song.ini + notes.mid + stems OGG — carga automática
    // ══════════════════════════════════════════════════════════════════

    Song(
      id:              'aun_coda',
      title:           'Aún',
      artist:          'Coda',
      difficulty:      Difficulty.beginner,
      genre:           Genre.rock,
      bpm:             120,            // placeholder — MIDI tempo map es autoritativo
      duration:        Duration(milliseconds: 294319),
      midiAssetPath:   '',
      packageAssetDir: 'assets/songs/aun_coda',
      isUnlocked:      true,
      xpReward:        175,
      description:     'Veinte Para Las Doce (1995). Balada de rock mexicano '
                       'con pro drums. Carta completa Clone Hero / RBN.',
      techniqueTag:    'Pro Drums',
      genreLabel:      '🎸 Rock Latinoamericano',
    ),

  ];

  /// Songs grouped by genre for the browse screen
  static Map<String, List<Song>> get byGenre {
    final map = <String, List<Song>>{};
    for (final s in songs) {
      map.putIfAbsent(s.genreLabel ?? s.genre.name, () => []).add(s);
    }
    return map;
  }

  /// Returns all unlocked songs for a given user level
  static List<Song> availableFor(int level) =>
      songs.where((s) => s.isUnlocked || level >= _levelReq(s)).toList();

  static int _levelReq(Song s) {
    switch (s.difficulty) {
      case Difficulty.beginner:     return 1;
      case Difficulty.intermediate: return 3;
      case Difficulty.advanced:     return 7;
      case Difficulty.expert:       return 12;
    }
  }
}
