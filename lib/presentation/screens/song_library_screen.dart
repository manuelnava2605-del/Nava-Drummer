import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../domain/entities/entities.dart';
import '../../domain/usecases/real_song_catalog.dart';
import '../../domain/usecases/song_catalog.dart';
import '../theme/nava_theme.dart';
import '../../core/backing_track_service.dart';
import '../widgets/mode_selector.dart';
import 'song_detail_screen.dart';

class SongLibraryScreen extends StatefulWidget {
  final void Function(Song, PracticeMode?) onSongSelected;
  /// Called when the user picks a section from the detail screen.
  final void Function(Song, SongSection, PracticeMode)? onSectionPractice;
  final int userLevel;

  const SongLibraryScreen({
    super.key,
    required this.onSongSelected,
    this.onSectionPractice,
    this.userLevel = 1,
  });

  @override
  State<SongLibraryScreen> createState() => _SongLibraryScreenState();
}

class _SongLibraryScreenState extends State<SongLibraryScreen>
    with SingleTickerProviderStateMixin {
  Difficulty? _filterDifficulty;
  Genre?      _filterGenre;
  String      _searchQuery = '';
  late TabController _tabController;

  // Combined catalog: real songs first, then practice lessons
  static final List<Song> _allSongs = [
    ...RealSongCatalog.songs,
    ...NavaSongCatalog.songs,
  ];

  List<Song> get _filteredSongs {
    return _allSongs.where((s) {
      if (_filterDifficulty != null && s.difficulty != _filterDifficulty) return false;
      if (_filterGenre     != null && s.genre      != _filterGenre)      return false;
      if (_searchQuery.isNotEmpty &&
          !s.title.toLowerCase().contains(_searchQuery.toLowerCase()) &&
          !s.artist.toLowerCase().contains(_searchQuery.toLowerCase()))  return false;
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavaTheme.background,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          _buildGenreBar(),
          _buildDiffBar(),
          Expanded(child: _buildSongList()),
        ]),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('CANCIONES', style: TextStyle(
              fontFamily: 'DrummerDisplay', fontSize: 20,
              color: NavaTheme.textPrimary, fontWeight: FontWeight.bold, letterSpacing: 2,
            ), maxLines: 1,),
            Text('${_filteredSongs.length} canciones disponibles',
              style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 11,
                  color: NavaTheme.textMuted, letterSpacing: 1)),
          ]),
        ),
        Container(
          decoration: BoxDecoration(
            color: NavaTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: NavaTheme.neonCyan.withOpacity(0.2)),
          ),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 13,
                color: NavaTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Buscar...',
              hintStyle: TextStyle(color: NavaTheme.textMuted, fontSize: 13),
              prefixIcon: Icon(Icons.search, color: NavaTheme.textMuted, size: 18),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              constraints: BoxConstraints(maxWidth: 160),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Genre Filter ──────────────────────────────────────────────────────────
  Widget _buildGenreBar() {
    final genres = [
      (null,           'TODAS',     NavaTheme.neonCyan),
      (Genre.cristiana,'✝️ CRISTIANA', NavaTheme.neonGold),
      (Genre.rock,     '🎸 ROCK',    NavaTheme.neonCyan),
      (Genre.pop,      '🎵 POP',     NavaTheme.neonPurple),
      (Genre.funk,     '🎷 FUNK',    NavaTheme.neonGreen),
      (Genre.metal,    '🔥 METAL',   NavaTheme.neonMagenta),
      (Genre.jazz,     '🎺 JAZZ',    NavaTheme.neonCyan),
      (Genre.latin,    '🪘 LATINO',  NavaTheme.neonGold),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 0, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: genres.map((g) => _GenreChip(
            label:  g.$2,
            active: _filterGenre == g.$1,
            color:  g.$3,
            onTap:  () => setState(() => _filterGenre = _filterGenre == g.$1 ? null : g.$1),
          )).toList(),
        ),
      ),
    );
  }

  // ── Difficulty Filter ─────────────────────────────────────────────────────
  Widget _buildDiffBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 0, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _DiffChip(label: 'TODOS',         active: _filterDifficulty == null,
              onTap: () => setState(() => _filterDifficulty = null)),
          ...Difficulty.values.map((d) => _DiffChip(
            label:  d.name.toUpperCase(),
            active: _filterDifficulty == d,
            color:  _diffColor(d),
            onTap:  () => setState(() => _filterDifficulty = _filterDifficulty == d ? null : d),
          )),
        ]),
      ),
    );
  }

  // ── Song List ─────────────────────────────────────────────────────────────
  Widget _buildSongList() {
    final songs = _filteredSongs;
    if (songs.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🥁', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        const Text('Sin canciones', style: TextStyle(
          fontFamily: 'DrummerDisplay', fontSize: 16, color: NavaTheme.textMuted)),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => setState(() { _filterDifficulty = null; _filterGenre = null; _searchQuery = ''; }),
          child: const Text('Limpiar filtros', style: TextStyle(color: NavaTheme.neonCyan)),
        ),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      itemCount: songs.length,
      itemBuilder: (ctx, i) => _SongCard(
        song:       songs[i],
        userLevel:  widget.userLevel,
        onTap:      () => _onSongTap(songs[i]),
      ).animate().fadeIn(delay: Duration(milliseconds: i * 40), duration: 300.ms),
    );
  }

  void _onSongTap(Song song) {
    final isLocked = !song.isUnlocked && widget.userLevel < _levelReq(song);
    if (isLocked) {
      showDialog(
        context: context,
        builder: (_) => _LockedDialog(song: song, requiredLevel: _levelReq(song)),
      );
      return;
    }
    // Route through SongDetailScreen for a richer selection experience
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SongDetailScreen(
        song:      song,
        userLevel: widget.userLevel,
        onStartPractice: (s, mode) {
          Navigator.pop(context);
          widget.onSongSelected(s, mode);
        },
        onSectionPractice: widget.onSectionPractice != null
            ? (s, sec, mode) {
                Navigator.pop(context);
                widget.onSectionPractice!(s, sec, mode);
              }
            : null,
      ),
    ));
  }

  Color _diffColor(Difficulty d) {
    switch (d) {
      case Difficulty.beginner:     return NavaTheme.neonGreen;
      case Difficulty.intermediate: return NavaTheme.neonGold;
      case Difficulty.advanced:     return const Color(0xFFFF8C00);
      case Difficulty.expert:       return NavaTheme.neonMagenta;
    }
  }

  int _levelReq(Song s) {
    switch (s.difficulty) {
      case Difficulty.beginner:     return 1;
      case Difficulty.intermediate: return 3;
      case Difficulty.advanced:     return 7;
      case Difficulty.expert:       return 12;
    }
  }
}

// ── Song Card ─────────────────────────────────────────────────────────────────
class _SongCard extends StatelessWidget {
  final Song     song;
  final int      userLevel;
  final VoidCallback onTap;

  const _SongCard({required this.song, required this.userLevel, required this.onTap});

  bool get _isLocked => !song.isUnlocked && userLevel < _levelReq;
  int  get _levelReq {
    switch (song.difficulty) {
      case Difficulty.beginner:     return 1;
      case Difficulty.intermediate: return 3;
      case Difficulty.advanced:     return 7;
      case Difficulty.expert:       return 12;
    }
  }

  Color get _diffColor {
    switch (song.difficulty) {
      case Difficulty.beginner:     return NavaTheme.neonGreen;
      case Difficulty.intermediate: return NavaTheme.neonGold;
      case Difficulty.advanced:     return const Color(0xFFFF8C00);
      case Difficulty.expert:       return NavaTheme.neonMagenta;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color:        NavaTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(
            color: _isLocked
                ? NavaTheme.textMuted.withOpacity(0.15)
                : _diffColor.withOpacity(0.25),
          ),
        ),
        child: Opacity(
          opacity: _isLocked ? 0.55 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              // Difficulty bar
              Container(
                width: 4, height: 56,
                decoration: BoxDecoration(
                  color:        _diffColor,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow:    [BoxShadow(color: _diffColor.withOpacity(0.4), blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (song.genre == Genre.cristiana)
                    const Text('✝️ ', style: TextStyle(fontSize: 13)),
                  Expanded(child: Text(song.title,
                    style: const TextStyle(
                      fontFamily: 'DrummerDisplay', fontSize: 14,
                      color: NavaTheme.textPrimary, fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  )),
                ]),
                const SizedBox(height: 3),
                Text(song.artist,
                  style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 11,
                      color: NavaTheme.textMuted),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Tag(song.difficulty.name.toUpperCase(), _diffColor),
                    _Tag('${song.bpm} BPM', NavaTheme.textMuted),
                    if (song.techniqueTag != null)
                      _Tag(song.techniqueTag!, NavaTheme.neonPurple),
                  ],
                ),
              ])),
              const SizedBox(width: 12),
              // Right side
              Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _isLocked
                    ? Column(children: [
                        const Icon(Icons.lock_outline, color: NavaTheme.textMuted, size: 18),
                        const SizedBox(height: 4),
                        Text('Nv.$_levelReq', style: const TextStyle(
                            fontFamily: 'DrummerBody', fontSize: 9, color: NavaTheme.textMuted)),
                      ])
                    : const Icon(Icons.play_circle_fill, color: NavaTheme.neonCyan, size: 28),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: NavaTheme.neonGold.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('+${song.xpReward} XP',
                    style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 10,
                        color: NavaTheme.neonGold, fontWeight: FontWeight.bold)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color  color;
  const _Tag(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(
      fontFamily: 'DrummerBody', fontSize: 9, color: color, letterSpacing: 0.5)),
  );
}

class _GenreChip extends StatelessWidget {
  final String     label;
  final bool       active;
  final Color      color;
  final VoidCallback onTap;
  const _GenreChip({required this.label, required this.active,
      required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.15) : NavaTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? color : NavaTheme.textMuted.withOpacity(0.2)),
      ),
      child: Text(label, style: TextStyle(
        fontFamily: 'DrummerBody', fontSize: 10, letterSpacing: 1,
        color: active ? color : NavaTheme.textMuted,
        fontWeight: active ? FontWeight.bold : FontWeight.normal,
      )),
    ),
  );
}

class _DiffChip extends StatelessWidget {
  final String     label;
  final bool       active;
  final Color      color;
  final VoidCallback onTap;
  const _DiffChip({required this.label, required this.active,
      this.color = NavaTheme.textMuted, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: active ? color : NavaTheme.textMuted.withOpacity(0.15)),
      ),
      child: Text(label, style: TextStyle(
        fontFamily: 'DrummerBody', fontSize: 9, letterSpacing: 1,
        color: active ? color : NavaTheme.textMuted,
      )),
    ),
  );
}

class _LockedDialog extends StatelessWidget {
  final Song song;
  final int  requiredLevel;
  const _LockedDialog({required this.song, required this.requiredLevel});
  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: NavaTheme.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text('🔒 Canción bloqueada', style: TextStyle(
      fontFamily: 'DrummerDisplay', fontSize: 16, color: NavaTheme.textPrimary)),
    content: Column(mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(song.title, style: const TextStyle(fontFamily: 'DrummerBody',
          fontSize: 14, color: NavaTheme.neonCyan, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text('Alcanza el Nivel $requiredLevel para desbloquear esta canción.',
        style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 13,
            color: NavaTheme.textMuted)),
    ]),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('OK', style: TextStyle(color: NavaTheme.neonCyan,
            fontFamily: 'DrummerBody', letterSpacing: 2)),
      ),
    ],
  );
}
