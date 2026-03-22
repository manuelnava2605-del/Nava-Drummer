// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Full Song & Lesson Catalog
// 16 practice songs from beginner to expert, modeled after InstaDrum's
// progressive learning approach. Each song includes groove breakdowns,
// technique tips, and sub-lessons (Groove + Fill sections).
// ─────────────────────────────────────────────────────────────────────────────

import '../entities/entities.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SONG CATALOG
// ═════════════════════════════════════════════════════════════════════════════

class NavaSongCatalog {
  static const List<Song> songs = [

    // ── BEGINNER ─────────────────────────────────────────────────────────────

    Song(
      id:           'slow_blues',
      title:        'Slow Blues',
      artist:       'NavaDrummer — Lesson 1',
      difficulty:   Difficulty.beginner,
      genre:        Genre.rock,
      bpm:          60,
      duration:     Duration(seconds: 48),
      midiAssetPath: 'assets/midi/slow_blues.mid',
      isUnlocked:   true,
      xpReward:     50,
      description:  'Your very first song. A 12-bar blues at 60 BPM with '
                    'a gentle shuffle feel. Just kick on 1&3, snare on 2&4.',
      techniqueTag: 'Kick + Snare Coordination',
    ),

    Song(
      id:           'quarter_notes',
      title:        'Quarter Notes',
      artist:       'NavaDrummer — Lesson 2',
      difficulty:   Difficulty.beginner,
      genre:        Genre.rock,
      bpm:          80,
      duration:     Duration(seconds: 24),
      midiAssetPath: 'assets/midi/quarter_notes.mid',
      isUnlocked:   true,
      xpReward:     75,
      description:  'Lock in the foundation: kick, snare, and quarter-note '
                    'hi-hat. The backbone of every style.',
      techniqueTag: 'Steady Pulse',
    ),

    Song(
      id:           'hihat_drill',
      title:        'Hi-Hat Drill',
      artist:       'NavaDrummer — Lesson 3',
      difficulty:   Difficulty.beginner,
      genre:        Genre.rock,
      bpm:          75,
      duration:     Duration(seconds: 32),
      midiAssetPath: 'assets/midi/hihat_drill.mid',
      isUnlocked:   true,
      xpReward:     75,
      description:  'Train your left foot. Hi-hat pedal on every beat while '
                    'the hands play a simple 8th-note pattern.',
      techniqueTag: 'Left Foot Independence',
    ),

    Song(
      id:           'tom_exercise',
      title:        'Tom-Tom Workout',
      artist:       'NavaDrummer — Lesson 4',
      difficulty:   Difficulty.beginner,
      genre:        Genre.rock,
      bpm:          80,
      duration:     Duration(seconds: 32),
      midiAssetPath: 'assets/midi/tom_exercise.mid',
      isUnlocked:   true,
      xpReward:     100,
      description:  'Ascending and descending tom runs in 16th notes. Builds '
                    'stick control and spatial awareness around the kit.',
      techniqueTag: 'Tom Navigation',
    ),

    Song(
      id:           'basic_rock_i',
      title:        'Basic Rock Beat',
      artist:       'NavaDrummer — Lesson 5',
      difficulty:   Difficulty.beginner,
      genre:        Genre.rock,
      bpm:          90,
      duration:     Duration(seconds: 43),
      midiAssetPath: 'assets/midi/basic_rock_i.mid',
      isUnlocked:   true,
      xpReward:     125,
      description:  'The classic rock beat: 8th-note hi-hat, kick on 1&3, '
                    'snare on 2&4. Foundation of pop, rock and country.',
      techniqueTag: '8th Note Hi-Hat',
    ),

    Song(
      id:           'rock_with_fill',
      title:        'Rock Beat + Fill',
      artist:       'NavaDrummer — Lesson 6',
      difficulty:   Difficulty.beginner,
      genre:        Genre.rock,
      bpm:          95,
      duration:     Duration(seconds: 43),
      midiAssetPath: 'assets/midi/rock_with_fill.mid',
      isUnlocked:   true,
      xpReward:     150,
      description:  'Add your first fills! Every 4 bars a tom run transitions '
                    'to the next section. Learn to connect grooves.',
      techniqueTag: 'Basic Tom Fill',
    ),

    // ── INTERMEDIATE ──────────────────────────────────────────────────────────

    Song(
      id:           'blues_shuffle',
      title:        'Blues Shuffle',
      artist:       'NavaDrummer — Lesson 7',
      difficulty:   Difficulty.intermediate,
      genre:        Genre.rock,
      bpm:          85,
      duration:     Duration(seconds: 46),
      midiAssetPath: 'assets/midi/blues_shuffle.mid',
      isUnlocked:   true,
      xpReward:     175,
      description:  'Swing those 8ths! The shuffle feel is the heart of blues, '
                    'R&B, and classic rock. The "long-short" triplet feel.',
      techniqueTag: 'Shuffle / Swing Feel',
    ),

    Song(
      id:           'half_time_groove',
      title:        'Half-Time Groove',
      artist:       'NavaDrummer — Lesson 8',
      difficulty:   Difficulty.intermediate,
      genre:        Genre.rock,
      bpm:          95,
      duration:     Duration(seconds: 43),
      midiAssetPath: 'assets/midi/half_time_groove.mid',
      isUnlocked:   true,
      xpReward:     200,
      description:  'Snare moves to beat 3, making the music feel twice as slow. '
                    'Used in ballads, hip-hop, and modern pop.',
      techniqueTag: 'Half-Time Feel',
    ),

    Song(
      id:           'funk_groove',
      title:        'Funk Groove',
      artist:       'NavaDrummer — Lesson 9',
      difficulty:   Difficulty.intermediate,
      genre:        Genre.funk,
      bpm:          100,
      duration:     Duration(seconds: 58),
      midiAssetPath: 'assets/midi/funk_groove.mid',
      isUnlocked:   true,
      xpReward:     250,
      description:  '16th-note hi-hat with ghost notes on the snare. '
                    'The pocket groove that drives funk, soul, and R&B.',
      techniqueTag: '16th Note + Ghost Notes',
    ),

    Song(
      id:           'bossa_nova',
      title:        'Bossa Nova',
      artist:       'NavaDrummer — Lesson 10',
      difficulty:   Difficulty.intermediate,
      genre:        Genre.latin,
      bpm:          110,
      duration:     Duration(seconds: 44),
      midiAssetPath: 'assets/midi/bossa_nova.mid',
      isUnlocked:   false,
      xpReward:     275,
      description:  'Classic Brazilian ride pattern with cross-stick snare. '
                    'Relaxed, sophisticated, and deceptively tricky.',
      techniqueTag: 'Ride Pattern + Cross-Stick',
    ),

    Song(
      id:           'jazz_ride',
      title:        'Jazz Ride',
      artist:       'NavaDrummer — Lesson 11',
      difficulty:   Difficulty.intermediate,
      genre:        Genre.jazz,
      bpm:          120,
      duration:     Duration(seconds: 32),
      midiAssetPath: 'assets/midi/jazz_ride.mid',
      isUnlocked:   false,
      xpReward:     300,
      description:  'The quintessential jazz feel: triplet ride cymbal with '
                    'hi-hat foot on 2&4 and loose snare comping.',
      techniqueTag: 'Jazz Ride + Comping',
    ),

    // ── ADVANCED ──────────────────────────────────────────────────────────────

    Song(
      id:           'latin_songo',
      title:        'Songo (Latin Fusion)',
      artist:       'NavaDrummer — Lesson 12',
      difficulty:   Difficulty.advanced,
      genre:        Genre.latin,
      bpm:          120,
      duration:     Duration(seconds: 43),
      midiAssetPath: 'assets/midi/latin_songo.mid',
      isUnlocked:   false,
      xpReward:     375,
      description:  'Afro-Cuban meets rock in this complex fusion pattern. '
                    'Syncopated kick, clave-inspired ride, hi-hat foot.',
      techniqueTag: 'Songo / Afro-Cuban',
    ),

    Song(
      id:           'metal_double',
      title:        'Metal Double Bass',
      artist:       'NavaDrummer — Lesson 13',
      difficulty:   Difficulty.advanced,
      genre:        Genre.metal,
      bpm:          150,
      duration:     Duration(seconds: 43),
      midiAssetPath: 'assets/midi/metal_double.mid',
      isUnlocked:   false,
      xpReward:     400,
      description:  '16th-note double bass at 150 BPM. Alternating heel-toe '
                    'technique under straight 8th hi-hat and power snare.',
      techniqueTag: 'Double Bass Pedal',
    ),

    Song(
      id:           'polyrhythm_3_4',
      title:        'Polyrhythm 3 over 4',
      artist:       'NavaDrummer — Lesson 14',
      difficulty:   Difficulty.advanced,
      genre:        Genre.rock,
      bpm:          100,
      duration:     Duration(seconds: 38),
      midiAssetPath: 'assets/midi/polyrhythm_3_4.mid',
      isUnlocked:   false,
      xpReward:     450,
      description:  'Triplets on the hi-hat while kick and snare stay in 4/4. '
                    'A mind-bending independence challenge.',
      techniqueTag: 'Polyrhythm / Independence',
    ),

    // ── EXPERT ────────────────────────────────────────────────────────────────

    Song(
      id:           'polyrhythm_7_4',
      title:        '7/4 Odd Time',
      artist:       'NavaDrummer — Lesson 15',
      difficulty:   Difficulty.expert,
      genre:        Genre.rock,
      bpm:          100,
      duration:     Duration(seconds: 59),
      midiAssetPath: 'assets/midi/polyrhythm_7_4.mid',
      isUnlocked:   false,
      xpReward:     600,
      description:  '7 beats per bar — a demanding odd-time groove used by '
                    'Tool, King Crimson, and progressive rock legends.',
      techniqueTag: 'Odd Time Signatures',
    ),

    Song(
      id:           'blast_beat',
      title:        'Blast Beat',
      artist:       'NavaDrummer — Lesson 16',
      difficulty:   Difficulty.expert,
      genre:        Genre.metal,
      bpm:          180,
      duration:     Duration(seconds: 18),
      midiAssetPath: 'assets/midi/blast_beat.mid',
      isUnlocked:   false,
      xpReward:     700,
      description:  'Alternating kick and snare on every 16th note at 180 BPM. '
                    'The extreme metal technique that requires months of training.',
      techniqueTag: 'Blast Beat',
    ),
  ];

  /// Returns songs filtered by difficulty level.
  static List<Song> byDifficulty(Difficulty d) =>
      songs.where((s) => s.difficulty == d).toList();

  /// Returns songs the user has unlocked (by required level).
  static List<Song> unlockedFor(int userLevel) =>
      songs.where((s) => s.isUnlocked || userLevel >= _requiredLevel(s)).toList();

  static int _requiredLevel(Song s) {
    switch (s.difficulty) {
      case Difficulty.beginner:     return 1;
      case Difficulty.intermediate: return 3;
      case Difficulty.advanced:     return 6;
      case Difficulty.expert:       return 10;
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DETAILED LESSON CATALOG (InstaDrum-style: Groove + Fill breakdown)
// ═════════════════════════════════════════════════════════════════════════════

class NavaLessonCatalog {

  /// Returns full lesson plan for a given song.
  static SongLesson? lessonFor(String songId) =>
      _lessons.firstWhere((l) => l.songId == songId, orElse: () => _lessons.first);

  static final List<SongLesson> _lessons = [

    // ── Slow Blues ────────────────────────────────────────────────────────────
    SongLesson(
      songId: 'slow_blues',
      sections: [
        LessonSection(
          name:        'The Main Groove',
          description: 'A 12-bar blues at 60 BPM. Play kick on beats 1 and 3, '
                       'snare on 2 and 4. Let the hi-hat swing gently.',
          bpmRange:    (50, 70),
          tips: [
            'Keep your hi-hat strokes even — the swing comes from the spacing, not volume.',
            'The kick and snare should feel like your heartbeat.',
            'Open the hi-hat slightly on the "and" of beat 4 for a classic blues feel.',
          ],
          loopBars: (0, 4),
        ),
        LessonSection(
          name:        'The Full Song',
          description: '12 bars from top to bottom. The blues progression repeats '
                       'twice (24 bars total).',
          bpmRange:    (55, 70),
          tips: [
            'Don\'t speed up! 60 BPM is intentional — blues lives in the pocket.',
            'Try singing "boom-chick boom-chick" as you play to internalize the feel.',
          ],
          loopBars: (0, 12),
        ),
      ],
    ),

    // ── Quarter Notes ─────────────────────────────────────────────────────────
    SongLesson(
      songId: 'quarter_notes',
      sections: [
        LessonSection(
          name:        'Kick + Snare Only',
          description: 'Before adding hi-hat, just play kick on 1&3 and snare on 2&4. '
                       'Count out loud: "1 2 3 4".',
          bpmRange:    (60, 80),
          tips: [
            'Tap your foot on every beat as you count. This builds internal pulse.',
            'Kick = your right foot. Snare = your left hand (or right, depending on setup).',
          ],
          loopBars: (0, 4),
        ),
        LessonSection(
          name:        'Add the Hi-Hat',
          description: 'Now add the right hand on the hi-hat — one stroke per beat '
                       '(quarter notes). Three limbs coordinating: right hand, right foot, left hand.',
          bpmRange:    (65, 80),
          tips: [
            'Start at 60 BPM and work up 5 BPM at a time.',
            'The hi-hat, kick, and snare should all land EXACTLY together on beats 1&3 and 2&4.',
            'Keep your hi-hat arm relaxed — no tension in the shoulder.',
          ],
          loopBars: (0, 8),
        ),
      ],
    ),

    // ── Basic Rock Beat ───────────────────────────────────────────────────────
    SongLesson(
      songId: 'basic_rock_i',
      sections: [
        LessonSection(
          name:        'Groove 1 — 8th Note Hi-Hat',
          description: 'Move your hi-hat to 8th notes (twice per beat). '
                       'Count: "1-and-2-and-3-and-4-and".',
          bpmRange:    (70, 90),
          tips: [
            'Your right hand is now a constant 8th-note motor — keep it going no matter what.',
            'Accent (play louder) on the downbeats: 1, 2, 3, 4.',
            'The off-beats (the "ands") should be lighter.',
          ],
          loopBars: (0, 4),
        ),
        LessonSection(
          name:        'Groove 2 — Full Pattern',
          description: 'Add kick on 1&3, snare on 2&4 under the 8th hi-hat. '
                       'This is the most common beat in popular music.',
          bpmRange:    (75, 95),
          tips: [
            'The crash on bar 1 signals the start of a phrase. Add it when comfortable.',
            'Keep the snare snappy — firm stroke, then let the stick bounce back.',
            'You\'re now playing like a session drummer!',
          ],
          loopBars: (0, 16),
        ),
      ],
    ),

    // ── Rock with Fill ────────────────────────────────────────────────────────
    SongLesson(
      songId: 'rock_with_fill',
      sections: [
        LessonSection(
          name:        'Groove — Basic Rock',
          description: 'The same rock beat as before. Make sure you own it before adding fills.',
          bpmRange:    (75, 95),
          tips: ['If the groove is shaky, practice it without the fills first.'],
          loopBars: (0, 3),
        ),
        LessonSection(
          name:        'Fill 1 — Tom Run',
          description: 'On bar 4, drop the hi-hat and play: Hi Tom → Hi Tom → Mid Tom → Floor Tom → Snare. '
                       'That\'s 8 16th-note strokes.',
          bpmRange:    (65, 95),
          tips: [
            'Practice the fill on its own in a loop before combining with the groove.',
            'The fill ends ON the crash/snare of bar 5. That landing is everything.',
            'Think of the fill as a small story: tension → release.',
          ],
          loopBars: (3, 5),
        ),
        LessonSection(
          name:        'Full Song',
          description: '16 bars: groove for 3 bars, fill on bar 4, repeat.',
          bpmRange:    (80, 100),
          tips: [
            'Keep the fill relaxed — many beginners tense up and rush.',
            'The crash after each fill should feel like a exhale of breath.',
          ],
          loopBars: (0, 16),
        ),
      ],
    ),

    // ── Funk Groove ───────────────────────────────────────────────────────────
    SongLesson(
      songId: 'funk_groove',
      sections: [
        LessonSection(
          name:        'Groove 1 — 16th Note Hi-Hat',
          description: '4 hi-hat strokes per beat. Count: "1-e-and-a-2-e-and-a-3-e-and-a-4-e-and-a". '
                       'This is hand-to-hand: R-L-R-L.',
          bpmRange:    (70, 100),
          tips: [
            'Start at 70 BPM. The 16th note hi-hat is the engine of funk.',
            'Alternate hands: R-L-R-L. No consecutive strokes with the same hand.',
            'Keep it even. A metronome is your best friend here.',
          ],
          loopBars: (0, 2),
        ),
        LessonSection(
          name:        'Groove 2 — Add Ghost Notes',
          description: 'Play very soft snare strokes (velocity 20–40) between the main snare '
                       'hits. These "ghost notes" add texture without volume.',
          bpmRange:    (75, 100),
          tips: [
            'Ghost notes should be barely audible — like a whisper.',
            'Use the wrist alone, no arm movement, for the ghosts.',
            'Accent the main snare on 2&4 to contrast with the ghosts.',
          ],
          loopBars: (0, 4),
        ),
        LessonSection(
          name:        'Full Funk Groove',
          description: '16th hi-hat + ghost notes + syncopated kick. '
                       'The kick hits on unexpected subdivisions for that "chicken" funk feel.',
          bpmRange:    (85, 105),
          tips: [
            'The syncopated kick is what makes funk feel alive. Don\'t straighten it out!',
            'Listen to James Brown, Sly Stone, or Tower of Power to internalize the feel.',
            'At 100 BPM this groove should feel effortless. If not, go slower.',
          ],
          loopBars: (0, 16),
        ),
      ],
    ),

    // ── Jazz Ride ─────────────────────────────────────────────────────────────
    SongLesson(
      songId: 'jazz_ride',
      sections: [
        LessonSection(
          name:        'Ride Pattern',
          description: 'The jazz ride: 3 strokes per beat in a triplet feel. '
                       '"ding-ding-da" per beat. Beats 1&3 on the bow, upbeats on the bell.',
          bpmRange:    (80, 120),
          tips: [
            'The ride should sound "singing" — let the stick bounce, don\'t choke it.',
            'Use the shoulder of the stick on the bell for a higher ping.',
            'Relax! Jazz drumming is 80% about feel, 20% about technique.',
          ],
          loopBars: (0, 4),
        ),
        LessonSection(
          name:        'Hi-Hat Foot + Snare Comping',
          description: 'Add hi-hat pedal on beats 2 and 4. Then add loose, improvised '
                       'snare hits between the ride strokes.',
          bpmRange:    (85, 120),
          tips: [
            'The snare in jazz is a "conversation", not a metronome. Be loose.',
            'Hi-hat foot on 2&4 is the "timekeeper" — keep it steady.',
            'Listen to any Art Blakey or Elvin Jones record for reference.',
          ],
          loopBars: (0, 16),
        ),
      ],
    ),

    // ── Metal Double ──────────────────────────────────────────────────────────
    SongLesson(
      songId: 'metal_double',
      sections: [
        LessonSection(
          name:        'Heel-Toe Warm-Up',
          description: 'Before double bass: practice rolling your foot from heel to toe '
                       'on a single pedal at 80 BPM to get rapid single-pedal strokes.',
          bpmRange:    (60, 100),
          tips: [
            'Heel-toe = one motion of the foot = two kick strokes.',
            'Keep your heel light on the pedal, not pressing down.',
          ],
          loopBars: (0, 4),
        ),
        LessonSection(
          name:        'Alternating Double Bass',
          description: 'Right-left-right-left on two pedals at 80 BPM. '
                       'Keep strokes even in volume and spacing.',
          bpmRange:    (60, 120),
          tips: [
            'Weaker foot is usually the left. Give it equal practice time.',
            'Record yourself — uneven double bass is easy to hear.',
            'Build up 5 BPM per day, never skip steps.',
          ],
          loopBars: (0, 4),
        ),
        LessonSection(
          name:        'Full Metal Pattern',
          description: '16th double bass under straight 8th hi-hat and power snare. '
                       'The wall-of-sound metal feel.',
          bpmRange:    (100, 155),
          tips: [
            'The hi-hat provides a ceiling — it should be relentless and even.',
            'Snare hits at 120+ dB in real metal. Make it crack!',
          ],
          loopBars: (0, 16),
        ),
      ],
    ),

    // ── Polyrhythm 7/4 ────────────────────────────────────────────────────────
    SongLesson(
      songId: 'polyrhythm_7_4',
      sections: [
        LessonSection(
          name:        'Feel the 7',
          description: 'Count to 7 out loud with a metronome: "1-2-3-4-5-6-7". '
                       'The bar is asymmetric: think of it as 4+3.',
          bpmRange:    (60, 100),
          tips: [
            'The natural accent falls on beat 1 and beat 5 (the "3" group starts).',
            'Clap along before picking up sticks.',
            'Listen to Tool\'s "The Grudge" or Radiohead\'s "Pyramid Song".',
          ],
          loopBars: (0, 2),
        ),
        LessonSection(
          name:        '7/4 Groove',
          description: 'Kick on beats 1, 2, 4, 5, 7. Snare on 3 and 6. '
                       'Hi-hat drives on every 16th.',
          bpmRange:    (70, 105),
          tips: [
            'Once it clicks, it will feel completely natural.',
            'Don\'t fight the odd feel — lean into it.',
          ],
          loopBars: (0, 7),
        ),
      ],
    ),

    // ── Blast Beat ────────────────────────────────────────────────────────────
    SongLesson(
      songId: 'blast_beat',
      sections: [
        LessonSection(
          name:        'Slow Practice',
          description: 'Alternating kick and snare on every 16th note. '
                       'Start at 80 BPM — left hand snare, right foot kick, alternating.',
          bpmRange:    (80, 140),
          tips: [
            'This requires months of daily practice. Do not rush.',
            'Protect your wrists — stretch before and after.',
            'Start with 2-minute sessions to avoid injury.',
          ],
          loopBars: (0, 2),
        ),
        LessonSection(
          name:        'Speed Build',
          description: 'Gradually increase tempo. Target: 180 BPM over weeks of practice.',
          bpmRange:    (120, 185),
          tips: [
            'Stop immediately if you feel any wrist or elbow pain.',
            'Economy of motion: small strokes, maximum speed.',
            'At full speed this is one of the hardest techniques in drumming.',
          ],
          loopBars: (0, 8),
        ),
      ],
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Value Objects
// ─────────────────────────────────────────────────────────────────────────────

class SongLesson {
  final String           songId;
  final List<LessonSection> sections;

  const SongLesson({required this.songId, required this.sections});
}

class LessonSection {
  final String        name;
  final String        description;
  final (int, int)    bpmRange;
  final List<String>  tips;
  final (int, int)    loopBars;

  const LessonSection({
    required this.name,
    required this.description,
    required this.bpmRange,
    required this.tips,
    required this.loopBars,
  });
}
