// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Entry Point
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/firebase_init.dart';
import 'core/audio_service.dart';
import 'core/global_timing_controller.dart';
import 'core/locale_controller.dart';
import 'core/notification_service.dart';
import 'presentation/screens/latency_calibration_screen.dart';
import 'core/subscription_service.dart';
import 'core/error_handler.dart';
import 'injection.dart';
import 'presentation/bloc/blocs.dart';
import 'presentation/theme/nava_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/auth_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/device_setup_screen.dart';
import 'presentation/screens/song_library_screen.dart';
import 'presentation/screens/practice_screen.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'presentation/screens/paywall_screen.dart';
import 'presentation/widgets/mode_selector.dart';
import 'domain/entities/entities.dart';
import 'l10n/strings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await WakelockPlus.enable(); }
  catch (e) { debugPrint('[main] WakelockPlus: $e'); }

  // Portrait only. PracticeScreen forces landscape temporarily.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  try {
    await initializeFirebase();
  } catch (e, st) {
    debugPrint('Firebase init failed: $e');
    debugPrintStack(stackTrace: st);
  }

  // ── Fast path: only blocking inits that must precede runApp ─────────────────
  // LocaleController and calibration offset are lightweight (SharedPrefs only).
  try { await LocaleController.instance.init(); }
  catch (e) { debugPrint('[main] LocaleController: $e'); }

  // Apply saved latency calibration offset to the global timing controller.
  try {
    final savedOffsetMs = await CalibrationRepository.loadOffset();
    if (savedOffsetMs != 0) {
      GlobalTimingController.instance.applySyncOffset(savedOffsetMs * 1000);
    }
  } catch (e) { debugPrint('[main] CalibrationRepository: $e'); }

  ConnectivityService.instance.init();

  final sl = ServiceLocator();
  try { await sl.initialize(); }
  catch (e) { debugPrint('[main] ServiceLocator: $e'); }

  // ── Run app immediately — heavy inits happen in background ──────────────────
  // SubscriptionService, AudioService (soundpool + 200+ WAV loads) and
  // NotificationService (FCM permission prompt) are all deferred so they cannot
  // block the first frame.  DrumEngine guards every hit with `if (!_ready)`.
  runApp(
    AppErrorBoundary(
      child: AppProviders(sl: sl, child: NavaDrummerApp(sl: sl)),
    ),
  );

  // ── Deferred heavy inits (run after first frame is visible) ─────────────────
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await SubscriptionService.instance.init()
          .timeout(const Duration(seconds: 10));
    } catch (e) { debugPrint('[main] SubscriptionService: $e'); }

    try {
      await AudioService.instance.init()
          .timeout(const Duration(seconds: 15));
    } catch (e) { debugPrint('[main] AudioService: $e'); }

    try {
      await NotificationService.instance.init()
          .timeout(const Duration(seconds: 8));
    } catch (e) { debugPrint('[main] NotificationService: $e'); }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
class NavaDrummerApp extends StatelessWidget {
  final ServiceLocator sl;
  const NavaDrummerApp({super.key, required this.sl});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LocaleController.instance,
      builder: (_, locale, __) => MaterialApp(
        title: 'NavaDrummer',
        debugShowCheckedModeBanner: false,
        theme: NavaTheme.darkTheme,
        locale: locale,
        supportedLocales: const [Locale('es'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: OfflineBanner(child: _AppRoot(sl: sl)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _AppRoot extends StatefulWidget {
  final ServiceLocator sl;
  const _AppRoot({required this.sl});

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> with WidgetsBindingObserver {
  // ── Pref keys ──────────────────────────────────────────────────────────────
  static const _kOnboarded   = 'onboarding_done_v3';
  static const _kDeviceSetup = 'device_setup_done_v2';
  static const _kRememberMe  = 'remember_me';

  // ── Flow state ─────────────────────────────────────────────────────────────
  bool _splashDone  = false;
  bool _authDone    = false;
  bool _loading     = true;
  bool _onboarded   = false;
  bool _deviceDone  = false;
  bool _showBanner  = false;
  int  _navIndex    = 0;

  // ignore: unused_field
  MidiDevice?  _connectedDevice;
  // ignore: unused_field
  DrumMapping? _drumMapping;

  // ── Progress (synced from ProgressBloc) ───────────────────────────────────
  UserProgress _userProgress = const UserProgress(
    userId: 'guest',
    displayName: 'Drummer',
    totalXp: 0,
    level: 1,
    currentStreak: 0,
    maxStreak: 0,
    songBestScores: {},
    achievements: [],
  );
  List<PerformanceSession> _recentSessions = const [];
  Map<DateTime, double>    _weeklyAccuracy = const {};

  ServiceLocator get sl => widget.sl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-enable wakelock when the app returns to foreground.
    // The drum practice experience requires the screen to stay on at all times.
    if (state == AppLifecycleState.resumed) {
      WakelockPlus.enable().catchError((e) {
        debugPrint('[AppRoot] WakelockPlus resume: $e');
      });
    }
  }

  Future<void> _init() async {
    try {
      final prefs      = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool(_kRememberMe) ?? false;
      final currentUser = FirebaseAuth.instance.currentUser;

      // If the user is logged in but hasn't checked "remember me", sign them
      // out on every fresh launch.  Timeout after 5 s so a bad network can't
      // block the app forever.
      if (currentUser != null && !rememberMe) {
        try {
          await FirebaseAuth.instance.signOut()
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          debugPrint('[AppRoot] signOut error/timeout: $e');
        }
      }

      final freshUser = FirebaseAuth.instance.currentUser;

      if (!mounted) return;
      setState(() {
        _onboarded  = prefs.getBool(_kOnboarded)   ?? false;
        _deviceDone = prefs.getBool(_kDeviceSetup) ?? false;
        _showBanner = !_onboarded;
        _authDone   = freshUser != null;
        _loading    = false;
      });

      // Load real progress if user is already authenticated.
      if (freshUser != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.read<ProgressBloc>().add(ProgressLoadRequested(freshUser.uid));
          SubscriptionService.instance.setUserId(freshUser.uid);
        });
      }
    } catch (e) {
      debugPrint('[AppRoot] _init error: $e');
      // Always unblock the UI even if init partially failed.
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _completeOnboarding() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOnboarded, true);
    setState(() {
      _onboarded  = true;
      _showBanner = true;
    });
  }

  Future<void> _completeDeviceSetup(MidiDevice? d, DrumMapping? m) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDeviceSetup, true);
    // Apply the physical kit's note mapping to the practice engine so incoming
    // MIDI notes resolve correctly regardless of the song's built-in map.
    if (m != null) sl.practiceEngine.setDeviceMapping(m);
    setState(() {
      _connectedDevice = d;
      _drumMapping     = m;
      _deviceDone      = true;
    });
  }

  void _onAuthenticated() {
    setState(() => _authDone = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        context.read<ProgressBloc>().add(ProgressLoadRequested(uid));
        SubscriptionService.instance.setUserId(uid);
      }
    });
  }

  void _onLogout() {
    setState(() {
      _authDone       = false;
      _recentSessions = const [];
      _weeklyAccuracy = const {};
      _userProgress   = const UserProgress(
        userId: 'guest', displayName: 'Drummer',
        totalXp: 0, level: 1, currentStreak: 0, maxStreak: 0,
        songBestScores: {}, achievements: [],
      );
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 1. Splash (every launch)
    if (!_splashDone) {
      return SplashScreen(onDone: () => setState(() => _splashDone = true));
    }

    // 2. Loading prefs
    if (_loading) {
      return const Scaffold(
        backgroundColor: NavaTheme.background,
        body: Center(child: CircularProgressIndicator(color: NavaTheme.neonCyan)),
      );
    }

    // 3. Onboarding (first time only)
    if (!_onboarded) {
      return OnboardingScreen(onComplete: _completeOnboarding);
    }

    // 4. Auth — login / register / guest
    if (!_authDone) {
      return AuthScreen(onAuthenticated: _onAuthenticated);
    }

    // 5. Device setup (first time after auth)
    if (!_deviceDone) {
      return DeviceSetupScreen(
        midiEngine:      sl.midiEngine,
        onDeviceSelected: (d, m) => _completeDeviceSetup(d, m),
      );
    }

    // 6. Main app — BlocListener syncs progress state into local fields
    return BlocListener<ProgressBloc, ProgressState>(
      listener: (ctx, state) {
        if (state is ProgressLoaded && mounted) {
          setState(() {
            _userProgress   = state.progress;
            _recentSessions = state.recentSessions;
            _weeklyAccuracy = state.weeklyAccuracy;
          });
        }
      },
      child: Scaffold(
        backgroundColor: NavaTheme.background,
        body: IndexedStack(
          index: _navIndex,
          children: [
            _buildSongsTab(),
            DashboardScreen(
              progress:       _userProgress,
              recentSessions: _recentSessions,
              weeklyAccuracy: _weeklyAccuracy,
            ),
            SettingsScreen(
              midiEngine:      sl.midiEngine,
              onLogout:        _onLogout,
              onDeviceSelected: (d, m) {
                if (m != null) sl.practiceEngine.setDeviceMapping(m);
                setState(() {
                  _connectedDevice = d;
                  _drumMapping     = m;
                });
              },
            ),
          ],
        ),
        bottomNavigationBar: _buildNav(),
      ),
    );
  }

  // ── Songs Tab ──────────────────────────────────────────────────────────────

  Widget _buildSongsTab() => Column(
        children: [
          SafeArea(bottom: false, child: const TrialReminderBanner()),
          if (_showBanner)
            QuickStartBanner(
              onDemo:    () => setState(() => _showBanner = false),
              onDismiss: () => setState(() => _showBanner = false),
            ),
          Expanded(
            child: SongLibraryScreen(
              onSongSelected:  _startSong,
              onSectionPractice: _startSongSection,
              userLevel:       _userProgress.level,
            ),
          ),
        ],
      );

  // ── Bottom Nav ─────────────────────────────────────────────────────────────

  Widget _buildNav() => Container(
        decoration: BoxDecoration(
          color: NavaTheme.surface,
          border: Border(
            top: BorderSide(
              color: NavaTheme.neonCyan.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _navIndex,
          onTap: (i) => setState(() => _navIndex = i),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor:   NavaTheme.neonCyan,
          unselectedItemColor: NavaTheme.textMuted,
          selectedLabelStyle: const TextStyle(
            fontFamily: 'DrummerBody', fontSize: 10, letterSpacing: 1),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'DrummerBody', fontSize: 10, letterSpacing: 1),
          items: [
            BottomNavigationBarItem(
              icon:       const Icon(Icons.library_music_outlined),
              activeIcon: const Icon(Icons.library_music),
              label: S.of(context).navSongs,
            ),
            BottomNavigationBarItem(
              icon:       const Icon(Icons.bar_chart_outlined),
              activeIcon: const Icon(Icons.bar_chart),
              label: S.of(context).navProgress,
            ),
            BottomNavigationBarItem(
              icon:       const Icon(Icons.settings_outlined),
              activeIcon: const Icon(Icons.settings),
              label: S.of(context).navSettings,
            ),
          ],
        ),
      );

  // ── Practice launch ────────────────────────────────────────────────────────

  void _startSong(Song song, [PracticeMode? mode]) =>
      _launchPractice(song, mode, null);

  void _startSongSection(Song song, SongSection section, PracticeMode mode) =>
      _launchPractice(song, mode, section);

  Future<void> _launchPractice(
    Song        song,
    PracticeMode? mode,
    SongSection?  section,
  ) async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

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
    ]);
  }
}
