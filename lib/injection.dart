// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Dependency Injection
// Wires up all repositories, use cases, and blocs.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/widgets.dart';
import 'data/datasources/local/midi_engine.dart';
import 'core/practice_engine.dart';
import 'data/repositories/firebase_repositories.dart';
import 'domain/repositories/repositories.dart';
import 'domain/usecases/usecases.dart';
import 'presentation/bloc/blocs.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ServiceLocator
// ─────────────────────────────────────────────────────────────────────────────

class ServiceLocator {
  static final _instance = ServiceLocator._();
  factory ServiceLocator() => _instance;
  ServiceLocator._();

  // Core
  late final MidiEngine    midiEngine;
  late final PracticeEngine practiceEngine;

  // Repositories
  late final AuthRepository    authRepo;
  late final UserRepository    userRepo;
  late final SessionRepository sessionRepo;
  late final SongRepository    songRepo;

  // Use Cases
  late final SignInAnonymouslyUseCase              signInAnon;
  late final SignInWithGoogleUseCase               signInGoogle;
  late final GetUserProgressUseCase                getProgress;
  late final SaveSessionAndUpdateProgressUseCase   saveSession;
  late final GetRecentSessionsUseCase              getRecent;
  late final GetWeeklyAccuracyUseCase              getWeekly;
  late final GetTimingCorrectionSuggestionsUseCase getCoach;
  late final GetSongsUseCase                       getSongs;
  late final GetMidiBytesUseCase                   getMidiBytes;
  late final GetLessonsUseCase                     getLessons;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Core engines
    midiEngine     = MidiEngine();
    practiceEngine = PracticeEngine(midiEngine: midiEngine);

    // Repositories
    authRepo    = AuthRepositoryImpl();
    userRepo    = UserRepositoryImpl();
    sessionRepo = SessionRepositoryImpl();
    songRepo    = SongRepositoryImpl();

    // Use cases
    signInAnon    = SignInAnonymouslyUseCase(authRepo, userRepo);
    signInGoogle  = SignInWithGoogleUseCase(authRepo, userRepo);
    getProgress   = GetUserProgressUseCase(userRepo);
    saveSession   = SaveSessionAndUpdateProgressUseCase(sessionRepo, userRepo);
    getRecent     = GetRecentSessionsUseCase(sessionRepo);
    getWeekly     = GetWeeklyAccuracyUseCase(sessionRepo);
    getCoach      = GetTimingCorrectionSuggestionsUseCase();
    getSongs      = GetSongsUseCase(songRepo);
    getMidiBytes  = GetMidiBytesUseCase(songRepo);
    getLessons    = GetLessonsUseCase();
  }

  void dispose() {
    midiEngine.dispose();
    practiceEngine.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppProviders — MultiBlocProvider widget for the app root
// ─────────────────────────────────────────────────────────────────────────────

class AppProviders extends StatelessWidget {
  final Widget child;
  final ServiceLocator sl;

  const AppProviders({super.key, required this.child, required this.sl});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => AuthBloc(
            signInAnon:   sl.signInAnon,
            signInGoogle: sl.signInGoogle,
          )..add(AuthSignInAnonymous()),
        ),
        BlocProvider(
          create: (_) => ProgressBloc(
            getProgress: sl.getProgress,
            saveSession: sl.saveSession,
            getRecent:   sl.getRecent,
            getWeekly:   sl.getWeekly,
            getCoach:    sl.getCoach,
          ),
        ),
        BlocProvider(
          create: (_) => SongsBloc(sl.getSongs)..add(SongsLoadRequested()),
        ),
      ],
      child: child,
    );
  }
}
