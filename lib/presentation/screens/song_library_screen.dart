// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Song Library Screen  (horizontal carousel, portrait)
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../domain/entities/entities.dart';
import '../../domain/usecases/song_catalog.dart';
import '../../data/song_loader.dart';
import '../../data/song_cache_service.dart';
import '../../data/remote_song_repository.dart';
import '../theme/nava_theme.dart';
import '../widgets/mode_selector.dart';
import 'song_detail_screen.dart';

class SongLibraryScreen extends StatefulWidget {
  final void Function(Song, PracticeMode?) onSongSelected;
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

class _SongLibraryScreenState extends State<SongLibraryScreen> {
  Difficulty? _filterDifficulty;
  Genre?      _filterGenre;
  String      _searchQuery = '';

  // Carousel state
  late PageController _carouselCtrl;
  int _currentIndex = 0;

  // Songs loaded from Firestore / local manifest
  List<Song> _manifestSongs = [];

  // Download tracking
  final Map<String, bool>   _downloadedIds    = {};
  final Map<String, double> _downloadProgress = {};
  final Map<String, String> _localDirCache    = {};

  List<Song> get _allSongs => [
    ..._manifestSongs,
    ...NavaSongCatalog.songs,
  ];

  List<Song> get _filteredSongs => _allSongs.where((s) {
    if (_filterDifficulty != null && s.difficulty != _filterDifficulty) return false;
    if (_filterGenre      != null && s.genre      != _filterGenre)      return false;
    if (_searchQuery.isNotEmpty &&
        !s.title.toLowerCase().contains(_searchQuery.toLowerCase()) &&
        !s.artist.toLowerCase().contains(_searchQuery.toLowerCase()))   return false;
    return true;
  }).toList();

  @override
  void initState() {
    super.initState();
    _carouselCtrl = PageController(viewportFraction: 0.88);
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    final songs = await SongLoader.loadSongs();
    if (!mounted) return;
    setState(() => _manifestSongs = songs);
    _refreshDownloadStatus(songs);
  }

  Future<void> _refreshDownloadStatus(List<Song> songs) async {
    final cache  = SongCacheService.instance;
    final remote = songs.where((s) => s.isRemoteSong || s.isLocalFile).toList();
    if (remote.isEmpty) return;

    final updates = <String, bool>{};
    final dirs    = <String, String>{};

    await Future.wait(remote.map((song) async {
      final localDir = await cache.localDir(song.id);
      dirs[song.id]  = localDir;
      if (song.isLocalFile) {
        updates[song.id] = true;
      } else {
        updates[song.id] = await cache.isDownloaded(song.id);
      }
    }));

    if (!mounted) return;
    setState(() {
      _downloadedIds.addAll(updates);
      _localDirCache.addAll(dirs);
    });
  }

  @override
  void dispose() {
    _carouselCtrl.dispose();
    super.dispose();
  }

  // ── Filter reset ──────────────────────────────────────────────────────────

  void _resetCarousel() {
    if (mounted) {
      setState(() => _currentIndex = 0);
      if (_carouselCtrl.hasClients) _carouselCtrl.jumpToPage(0);
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<void> _onSongTap(Song song) async {
    final isLocked = !song.isUnlocked && widget.userLevel < _levelReq(song);
    if (isLocked) {
      showDialog(
        context: context,
        builder: (_) => _LockedDialog(song: song, requiredLevel: _levelReq(song)),
      );
      return;
    }

    Song resolvedSong = song;
    if (song.isRemoteSong) {
      if (_downloadedIds[song.id] != true) {
        final ok = await _downloadSong(song);
        if (!mounted || !ok) return;
      }
      final localDir = _localDirCache[song.id] ??
          await SongCacheService.instance.localDir(song.id);
      resolvedSong = song.copyWith(packageAssetDir: localDir);
    }

    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SongDetailScreen(
        song:      resolvedSong,
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

  Future<bool> _downloadSong(Song song) async {
    if (song.packageAssetDir == null) return false;
    setState(() => _downloadProgress[song.id] = 0.0);

    try {
      final localDir = _localDirCache[song.id] ??
          await SongCacheService.instance.localDir(song.id);
      _localDirCache[song.id] = localDir;

      await RemoteSongRepository.instance.downloadSong(
        songId:            song.id,
        storageFolderPath: song.packageAssetDir!,
        localDir:          localDir,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress[song.id] = p);
        },
      );

      await SongCacheService.instance.markDownloaded(song.id);
      if (mounted) setState(() => _downloadedIds[song.id] = true);
      return true;
    } catch (e) {
      debugPrint('[SongLibrary] Download error for ${song.title}: $e');
      if (mounted) {
        final msg = '$e'.contains('rules') || '$e'.contains('permission')
            ? 'Sin permiso de descarga.\nVerifica las reglas de Firebase Storage.'
            : '$e'.contains('Timeout') || '$e'.contains('timeout')
                ? 'La descarga tardó demasiado.\nRevisa tu conexión a internet.'
                : 'Error descargando ${song.title}.\nRevisa tu conexión.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg, style: const TextStyle(fontSize: 12)),
          backgroundColor: NavaTheme.neonMagenta,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          ),
        ));
      }
      return false;
    } finally {
      if (mounted) setState(() => _downloadProgress.remove(song.id));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final songs = _filteredSongs;
    return Scaffold(
      backgroundColor: NavaTheme.background,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(songs.length),
          _buildFilterRow(),
          Expanded(child: songs.isEmpty
              ? _buildEmpty()
              : _buildCarousel(songs)),
          if (songs.isNotEmpty)
            _buildPageIndicator(songs.length),
        ]),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('CANCIONES', style: TextStyle(
              fontFamily: 'DrummerDisplay', fontSize: 22,
              color: NavaTheme.textPrimary, fontWeight: FontWeight.bold,
              letterSpacing: 3,
            )),
            Text(
              '${_currentIndex + 1} / $count',
              style: const TextStyle(
                fontFamily: 'DrummerBody', fontSize: 11,
                color: NavaTheme.textMuted, letterSpacing: 1,
              ),
            ),
          ]),
        ),
        _SearchField(onChanged: (v) {
          setState(() => _searchQuery = v);
          _resetCarousel();
        }),
      ]),
    );
  }

  // ── Filter Row (genre + difficulty combined) ───────────────────────────────

  Widget _buildFilterRow() {
    final genres = [
      (null,            'TODAS',    NavaTheme.neonCyan),
      (Genre.cristiana, '✝ CRIST.', NavaTheme.neonGold),
      (Genre.rock,      '🎸 ROCK',  NavaTheme.neonCyan),
      (Genre.pop,       '🎵 POP',   NavaTheme.neonPurple),
      (Genre.funk,      '🎷 FUNK',  NavaTheme.neonGreen),
      (Genre.metal,     '🔥 METAL', NavaTheme.neonMagenta),
      (Genre.jazz,       '🎺 JAZZ',   NavaTheme.neonCyan),
      (Genre.latin,      '🪘 LATIN',  NavaTheme.neonGold),
      (Genre.electronic, '🎛 ELECTRO', NavaTheme.neonPurple),
    ];

    return Column(children: [
      // Genre chips
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 0, 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: genres.map((g) => _Chip(
            label:  g.$2,
            active: _filterGenre == g.$1,
            color:  g.$3,
            onTap:  () {
              setState(() => _filterGenre =
                  _filterGenre == g.$1 ? null : g.$1);
              _resetCarousel();
            },
          )).toList()),
        ),
      ),
      // Difficulty chips
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 0, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _Chip(
              label: 'TODOS',
              active: _filterDifficulty == null,
              color: NavaTheme.textMuted,
              onTap: () {
                setState(() => _filterDifficulty = null);
                _resetCarousel();
              },
            ),
            ...Difficulty.values.map((d) => _Chip(
              label:  d.name.toUpperCase(),
              active: _filterDifficulty == d,
              color:  _diffColor(d),
              onTap:  () {
                setState(() => _filterDifficulty =
                    _filterDifficulty == d ? null : d);
                _resetCarousel();
              },
            )),
          ]),
        ),
      ),
    ]);
  }

  // ── Carousel ──────────────────────────────────────────────────────────────

  Widget _buildCarousel(List<Song> songs) {
    return PageView.builder(
      controller:    _carouselCtrl,
      itemCount:     songs.length,
      onPageChanged: (i) => setState(() => _currentIndex = i),
      itemBuilder:   (ctx, i) {
        final song = songs[i];
        return _SongCarouselCard(
          song:             song,
          userLevel:        widget.userLevel,
          isDownloaded:     song.isRemoteSong ? _downloadedIds[song.id] : null,
          downloadProgress: _downloadProgress[song.id],
          localDir:         _localDirCache[song.id],
          onTap:            () => _onSongTap(song),
          onDownload:       () => _downloadSong(song),
        ).animate().fadeIn(duration: 250.ms);
      },
    );
  }

  // ── Page Indicator ────────────────────────────────────────────────────────

  Widget _buildPageIndicator(int count) {
    final shown = count.clamp(0, 12);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(shown, (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width:  _currentIndex == i ? 22 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: _currentIndex == i
                ? NavaTheme.neonCyan
                : NavaTheme.textMuted.withOpacity(0.3),
            borderRadius: BorderRadius.circular(3),
          ),
        )),
      ),
    );
  }

  // ── Empty State ───────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('🥁', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        const Text('Sin canciones', style: TextStyle(
          fontFamily: 'DrummerDisplay', fontSize: 16,
          color: NavaTheme.textMuted)),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            setState(() {
              _filterDifficulty = null;
              _filterGenre      = null;
              _searchQuery      = '';
            });
            _resetCarousel();
          },
          child: const Text('Limpiar filtros',
              style: TextStyle(color: NavaTheme.neonCyan)),
        ),
      ],
    ));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Song Carousel Card  — full-height portrait card
// ─────────────────────────────────────────────────────────────────────────────
class _SongCarouselCard extends StatelessWidget {
  final Song         song;
  final int          userLevel;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  /// null  = bundled asset (no download UI)
  /// false = remote, not cached
  /// true  = cached locally
  final bool?        isDownloaded;
  final double?      downloadProgress;
  final String?      localDir;

  const _SongCarouselCard({
    required this.song,
    required this.userLevel,
    required this.onTap,
    required this.onDownload,
    this.isDownloaded,
    this.downloadProgress,
    this.localDir,
  });

  bool get _isLocked => !song.isUnlocked && userLevel < _levelReq;
  int get _levelReq {
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

  String get _durationStr {
    final m = song.duration.inMinutes;
    final s = song.duration.inSeconds % 60;
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color:        NavaTheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _isLocked
                  ? NavaTheme.textMuted.withOpacity(0.12)
                  : _diffColor.withOpacity(0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _diffColor.withOpacity(0.08),
                blurRadius: 24, spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Opacity(
              opacity: _isLocked ? 0.6 : 1.0,
              child: Column(children: [
                _buildArtArea(),
                Expanded(child: _buildInfoArea()),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Art Area (top 42% gradient) ───────────────────────────────────────────

  Widget _buildArtArea() {
    return SizedBox(
      height: 200,
      child: Stack(fit: StackFit.expand, children: [
        // Gradient background
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _diffColor.withOpacity(0.25),
                NavaTheme.background.withOpacity(0.6),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        // Album art if cached
        if (localDir != null)
          _AlbumArt(localDir: localDir!),
        // Decorative drum icon
        Center(child: Icon(
          Icons.album_outlined,
          size: 72,
          color: _diffColor.withOpacity(0.18),
        )),
        // Genre badge
        Positioned(
          top: 14, left: 14,
          child: _Badge(
            label: _genreLabel(song.genre),
            color: _diffColor,
          ),
        ),
        // Premium badge
        if (!song.isUnlocked)
          Positioned(
            top: 14, right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: NavaTheme.neonGold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: NavaTheme.neonGold.withOpacity(0.5)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.workspace_premium,
                    color: NavaTheme.neonGold, size: 11),
                SizedBox(width: 4),
                Text('PREMIUM', style: TextStyle(
                  fontFamily: 'DrummerBody', fontSize: 9,
                  color: NavaTheme.neonGold, letterSpacing: 1,
                  fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
        // Lock overlay
        if (_isLocked)
          Container(
            color: NavaTheme.background.withOpacity(0.5),
            child: Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock, color: NavaTheme.textMuted, size: 32),
                const SizedBox(height: 6),
                Text('Nivel $_levelReq requerido',
                  style: const TextStyle(fontFamily: 'DrummerBody',
                      fontSize: 11, color: NavaTheme.textMuted)),
              ],
            )),
          ),
      ]),
    );
  }

  // ── Info Area (bottom section) ────────────────────────────────────────────

  Widget _buildInfoArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(song.title,
            style: const TextStyle(
              fontFamily: 'DrummerDisplay', fontSize: 18,
              color: NavaTheme.textPrimary, fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
            maxLines: 2, overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          // Artist
          Text(song.artist,
            style: const TextStyle(
              fontFamily: 'DrummerBody', fontSize: 13,
              color: NavaTheme.textSecondary)),
          const SizedBox(height: 12),
          // Stats row
          Row(children: [
            _StatPill(Icons.speed, '${song.bpm} BPM'),
            const SizedBox(width: 8),
            _StatPill(Icons.timer_outlined, _durationStr),
            const SizedBox(width: 8),
            _StatPill(Icons.star_outline, '+${song.xpReward} XP',
                color: NavaTheme.neonGold),
          ]),
          const SizedBox(height: 10),
          // Tags
          Wrap(spacing: 6, runSpacing: 4, children: [
            _Tag(song.difficulty.name.toUpperCase(), _diffColor),
            if (song.techniqueTag != null)
              _Tag(song.techniqueTag!, NavaTheme.neonPurple),
          ]),
          const Spacer(),
          // Description
          if (song.description != null) ...[
            Text(song.description!,
              style: const TextStyle(
                fontFamily: 'DrummerBody', fontSize: 10,
                color: NavaTheme.textMuted, height: 1.5),
              maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
          ],
          // Action button
          _buildActionButton(),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    // Downloading
    if (downloadProgress != null) {
      return Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Descargando...', style: TextStyle(
            fontFamily: 'DrummerBody', fontSize: 11,
            color: NavaTheme.neonCyan)),
          Text('${((downloadProgress ?? 0) * 100).round()}%',
            style: const TextStyle(
              fontFamily: 'DrummerBody', fontSize: 11,
              color: NavaTheme.neonCyan, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: downloadProgress,
            backgroundColor: NavaTheme.neonCyan.withOpacity(0.12),
            color: NavaTheme.neonCyan,
            minHeight: 6,
          ),
        ),
      ]);
    }

    // Remote not downloaded
    if (isDownloaded == false) {
      return GestureDetector(
        onTap: onDownload,
        child: Container(
          width: double.infinity, height: 48,
          decoration: BoxDecoration(
            border: Border.all(color: NavaTheme.neonCyan.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(12),
            color: NavaTheme.neonCyan.withOpacity(0.08),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.cloud_download_outlined,
                color: NavaTheme.neonCyan, size: 20),
            const SizedBox(width: 8),
            const Text('DESCARGAR', style: TextStyle(
              fontFamily: 'DrummerBody', fontSize: 12,
              color: NavaTheme.neonCyan, letterSpacing: 2,
              fontWeight: FontWeight.bold)),
          ]),
        ),
      );
    }

    // Locked
    if (_isLocked) {
      return Container(
        width: double.infinity, height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: NavaTheme.textMuted.withOpacity(0.08),
          border: Border.all(color: NavaTheme.textMuted.withOpacity(0.2)),
        ),
        child: Center(child: Text('NIVEL $_levelReq REQUERIDO',
          style: const TextStyle(
            fontFamily: 'DrummerBody', fontSize: 11,
            color: NavaTheme.textMuted, letterSpacing: 1))),
      );
    }

    // Ready
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity, height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            _diffColor,
            _diffColor.withOpacity(0.75),
          ]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
            color: _diffColor.withOpacity(0.35),
            blurRadius: 14, offset: const Offset(0, 4),
          )],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 24),
          const SizedBox(width: 6),
          const Text('TOCAR AHORA', style: TextStyle(
            fontFamily: 'DrummerBody', fontSize: 13,
            color: Colors.black, fontWeight: FontWeight.bold,
            letterSpacing: 2)),
        ]),
      ),
    );
  }

  String _genreLabel(Genre g) {
    switch (g) {
      case Genre.rock:      return '🎸 ROCK';
      case Genre.pop:       return '🎵 POP';
      case Genre.metal:     return '🔥 METAL';
      case Genre.jazz:      return '🎺 JAZZ';
      case Genre.funk:      return '🎷 FUNK';
      case Genre.latin:     return '🪘 LATINO';
      case Genre.cristiana:  return '✝ CRISTIANA';
      case Genre.electronic: return '🎛 ELECTRÓNICA';
      case Genre.custom:     return '🎵 CUSTOM';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Album Art (loads album.png from local dir if present)
// ─────────────────────────────────────────────────────────────────────────────
class _AlbumArt extends StatelessWidget {
  final String localDir;
  const _AlbumArt({required this.localDir});

  @override
  Widget build(BuildContext context) {
    final file = File('$localDir/album.png');
    if (!file.existsSync()) return const SizedBox.shrink();
    return Image.file(file, fit: BoxFit.cover);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color  color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.18),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.5)),
    ),
    child: Text(label, style: TextStyle(
      fontFamily: 'DrummerBody', fontSize: 9, letterSpacing: 1,
      color: color, fontWeight: FontWeight.bold)),
  );
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  const _StatPill(this.icon, this.label, {this.color = NavaTheme.textMuted});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(
        fontFamily: 'DrummerBody', fontSize: 11, color: color)),
    ],
  );
}

class _Tag extends StatelessWidget {
  final String text;
  final Color  color;
  const _Tag(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(
      fontFamily: 'DrummerBody', fontSize: 9,
      color: color, letterSpacing: 0.5)),
  );
}

class _Chip extends StatelessWidget {
  final String     label;
  final bool       active;
  final Color      color;
  final VoidCallback onTap;
  const _Chip({
    required this.label, required this.active,
    required this.color, required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.15) : NavaTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: active ? color : NavaTheme.textMuted.withOpacity(0.2)),
      ),
      child: Text(label, style: TextStyle(
        fontFamily: 'DrummerBody', fontSize: 10, letterSpacing: 0.8,
        color: active ? color : NavaTheme.textMuted,
        fontWeight: active ? FontWeight.bold : FontWeight.normal,
      )),
    ),
  );
}

class _SearchField extends StatefulWidget {
  final ValueChanged<String> onChanged;
  const _SearchField({required this.onChanged});
  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  bool _expanded = false;
  final _ctrl  = TextEditingController();
  final _focus = FocusNode();

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _focus.requestFocus();
    } else {
      _ctrl.clear();
      widget.onChanged('');
      _focus.unfocus();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOut,
    width: _expanded ? 170 : 38,
    height: 36,
    decoration: BoxDecoration(
      color: NavaTheme.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: _expanded
            ? NavaTheme.neonCyan.withOpacity(0.5)
            : NavaTheme.neonCyan.withOpacity(0.15)),
    ),
    child: Row(children: [
      GestureDetector(
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(
            _expanded ? Icons.close : Icons.search,
            color: NavaTheme.neonCyan, size: 18),
        ),
      ),
      if (_expanded)
        Expanded(child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          onChanged: widget.onChanged,
          style: const TextStyle(
            fontFamily: 'DrummerBody', fontSize: 13,
            color: NavaTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Buscar...',
            hintStyle: TextStyle(color: NavaTheme.textMuted, fontSize: 12),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        )),
    ]),
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
      Text(song.title, style: const TextStyle(
        fontFamily: 'DrummerBody', fontSize: 14,
        color: NavaTheme.neonCyan, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text('Alcanza el Nivel $requiredLevel para desbloquear esta canción.',
        style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 13,
            color: NavaTheme.textMuted)),
    ]),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('OK', style: TextStyle(
            color: NavaTheme.neonCyan, fontFamily: 'DrummerBody',
            letterSpacing: 2)),
      ),
    ],
  );
}
