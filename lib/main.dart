// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Entry Point  (v2: landscape + fixes)
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/firebase_init.dart';
import 'core/audio_service.dart';
import 'core/subscription_service.dart';
import 'core/error_handler.dart';
import 'core/analytics_service.dart';
import 'injection.dart';
import 'presentation/theme/nava_theme.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/device_setup_screen.dart';
import 'presentation/screens/song_library_screen.dart';
import 'presentation/screens/practice_screen.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/screens/paywall_screen.dart';
import 'presentation/widgets/mode_selector.dart';
import 'domain/entities/entities.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Allow both portrait (menus) and landscape (practice).
  // Practice screen sets landscape; navigator pop restores portrait.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Firebase (non-fatal if missing config during dev)
  try { await initializeFirebase(); } catch (e) {
    debugPrint('Firebase init skipped: $e');
  }

  await SubscriptionService.instance.init();
  await AudioService.instance.init();
  ConnectivityService.instance.init();

  final sl = ServiceLocator();
  await sl.initialize();

  runApp(AppErrorBoundary(
    child: AppProviders(sl: sl, child: NavaDrummerApp(sl: sl)),
  ));
}

// ─────────────────────────────────────────────────────────────────────────────
class NavaDrummerApp extends StatelessWidget {
  final ServiceLocator sl;
  const NavaDrummerApp({super.key, required this.sl});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title:                      'NavaDrummer',
    debugShowCheckedModeBanner: false,
    theme:                      NavaTheme.darkTheme,
    home:                       OfflineBanner(child: _AppRoot(sl: sl)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
class _AppRoot extends StatefulWidget {
  final ServiceLocator sl;
  const _AppRoot({required this.sl});
  @override State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  static const _kOnboarded   = 'onboarding_done_v2';
  static const _kDeviceSetup = 'device_setup_done_v2';

  bool _loading    = true;
  bool _onboarded  = false;
  bool _deviceDone = false;
  bool _showBanner = false;
  int  _navIndex   = 0;

  MidiDevice?  _connectedDevice;
  DrumMapping? _drumMapping;

  UserProgress _userProgress = const UserProgress(
    userId: 'guest', displayName: 'Drummer',
    totalXp: 0, level: 1, currentStreak: 0, maxStreak: 0,
    songBestScores: {}, achievements: [],
  );

  ServiceLocator get sl => widget.sl;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _onboarded  = prefs.getBool(_kOnboarded)   ?? false;
      _deviceDone = prefs.getBool(_kDeviceSetup) ?? false;
      _showBanner = !_onboarded;
      _loading    = false;
    });
  }

  Future<void> _completeOnboarding() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOnboarded, true);
    setState(() { _onboarded = true; _showBanner = true; });
  }

  Future<void> _completeDeviceSetup(MidiDevice? d, DrumMapping? m) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDeviceSetup, true);
    setState(() { _connectedDevice = d; _drumMapping = m; _deviceDone = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(
      backgroundColor: NavaTheme.background,
      body: Center(child: CircularProgressIndicator(color: NavaTheme.neonCyan)),
    );

    if (!_onboarded) return OnboardingScreen(onComplete: _completeOnboarding);

    if (!_deviceDone) return DeviceSetupScreen(
      midiEngine:       sl.midiEngine,
      onDeviceSelected: (d, m) => _completeDeviceSetup(d, m),
    );

    return Scaffold(
      backgroundColor: NavaTheme.background,
      body:            _buildCurrentTab(),
      bottomNavigationBar: _buildNav(),
    );
  }

  Widget _buildCurrentTab() {
    switch (_navIndex) {
      case 0: return _buildSongsTab();
      case 1: return DashboardScreen(progress: _userProgress);
      case 2: return DeviceSetupScreen(
        midiEngine:       sl.midiEngine,
        onDeviceSelected: (d, m) => setState(() {
          _connectedDevice = d; _drumMapping = m; _navIndex = 0;
        }),
      );
      default: return _buildSongsTab();
    }
  }

  Widget _buildSongsTab() => Column(children: [
    SafeArea(bottom: false, child: const TrialReminderBanner()),
    if (_showBanner)
      QuickStartBanner(
        onDemo:    () => setState(() => _showBanner = false),
        onDismiss: () => setState(() => _showBanner = false),
      ),
    Expanded(child: SongLibraryScreen(
      onSongSelected:    _startSong,
      onSectionPractice: _startSongSection,
      userLevel:         _userProgress.level,
    )),
  ]);

  Widget _buildNav() => Container(
    decoration: BoxDecoration(
      color:  NavaTheme.surface,
      border: Border(top: BorderSide(
          color: NavaTheme.neonCyan.withOpacity(0.1))),
    ),
    child: BottomNavigationBar(
      currentIndex:        _navIndex,
      onTap:               (i) => setState(() => _navIndex = i),
      backgroundColor:     Colors.transparent,
      elevation:           0,
      selectedItemColor:   NavaTheme.neonCyan,
      unselectedItemColor: NavaTheme.textMuted,
      selectedLabelStyle:   const TextStyle(
          fontFamily: 'DrummerBody', fontSize: 10, letterSpacing: 1),
      unselectedLabelStyle: const TextStyle(
          fontFamily: 'DrummerBody', fontSize: 10, letterSpacing: 1),
      items: const [
        BottomNavigationBarItem(
          icon:       Icon(Icons.library_music_outlined),
          activeIcon: Icon(Icons.library_music),
          label:      'CANCIONES',
        ),
        BottomNavigationBarItem(
          icon:       Icon(Icons.bar_chart_outlined),
          activeIcon: Icon(Icons.bar_chart),
          label:      'PROGRESO',
        ),
        BottomNavigationBarItem(
          icon:       Icon(Icons.settings_input_component_outlined),
          activeIcon: Icon(Icons.settings_input_component),
          label:      'DISPOSITIVO',
        ),
      ],
    ),
  );

  /// Called by SongLibraryScreen when the user picks a full-song mode.
  void _startSong(Song song, [PracticeMode? mode]) =>
      _launchPractice(song, mode, null);

  /// Called by SongLibraryScreen when the user picks a section practice mode.
  void _startSongSection(Song song, SongSection section, PracticeMode mode) =>
      _launchPractice(song, mode, section);

  Future<void> _launchPractice(Song song, PracticeMode? mode, SongSection? section) async {
    // Force landscape for practice
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // If mode already chosen from SongDetailScreen, skip the selector sheet
    if (mode == null) {
      mode = await showModeSelectorSheet(context, song: song);
    }
    if (mode == null || !mounted) {
      await _restorePortrait();
      return;
    }

    final canPlay = await GateKeeper.checkAccess(context, song);
    if (!canPlay || !mounted) {
      await _restorePortrait();
      return;
    }

    await SubscriptionService.instance.incrementSession();

    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => PracticeScreen(
          song:        song,
          engine:      sl.practiceEngine,
          initialMode: mode!,
          section:     section,
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );

    // Restore portrait when returning to menus
    await _restorePortrait();

    if (!mounted) return;
    setState(() {});

    if (SubscriptionService.instance.shouldShowPaywall) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.92,
          child: PaywallScreen(
            onSubscribed: () => Navigator.pop(context),
            onDismiss:    () => Navigator.pop(context),
          ),
        ),
      );
    }
  }

  Future<void> _restorePortrait() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}
