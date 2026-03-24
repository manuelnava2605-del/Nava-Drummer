// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — BLoC Layer
// State management for the main app flows.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/entities.dart';
import '../../domain/usecases/usecases.dart';

// ═════════════════════════════════════════════════════════════════════════════
// AUTH BLOC
// ═════════════════════════════════════════════════════════════════════════════

// ── Events ────────────────────────────────────────────────────────────────────
abstract class AuthEvent {}
class AuthStarted         extends AuthEvent {}
class AuthSignInAnonymous extends AuthEvent {}
class AuthSignInGoogle    extends AuthEvent {}
class AuthSignOut         extends AuthEvent {}

// ── States ────────────────────────────────────────────────────────────────────
abstract class AuthState {}
class AuthInitial      extends AuthState {}
class AuthLoading      extends AuthState {}
class AuthAuthenticated extends AuthState {
  final String userId;
  AuthAuthenticated(this.userId);
}
class AuthUnauthenticated extends AuthState {}
class AuthError        extends AuthState {
  final String message;
  AuthError(this.message);
}

// ── Bloc ──────────────────────────────────────────────────────────────────────
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final SignInAnonymouslyUseCase _signInAnon;
  final SignInWithGoogleUseCase  _signInGoogle;

  AuthBloc({
    required SignInAnonymouslyUseCase signInAnon,
    required SignInWithGoogleUseCase  signInGoogle,
  })  : _signInAnon    = signInAnon,
        _signInGoogle   = signInGoogle,
        super(AuthInitial()) {
    on<AuthSignInAnonymous>(_onSignInAnonymous);
    on<AuthSignInGoogle>(_onSignInGoogle);
    on<AuthSignOut>(_onSignOut);
  }

  Future<void> _onSignInAnonymous(
    AuthSignInAnonymous event, Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final uid = await _signInAnon();
      emit(AuthAuthenticated(uid));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onSignInGoogle(
    AuthSignInGoogle event, Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final uid = await _signInGoogle();
      emit(AuthAuthenticated(uid));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onSignOut(AuthSignOut event, Emitter<AuthState> emit) async {
    emit(AuthUnauthenticated());
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PROGRESS BLOC
// ═════════════════════════════════════════════════════════════════════════════

// ── Events ────────────────────────────────────────────────────────────────────
abstract class ProgressEvent {}

class ProgressLoadRequested extends ProgressEvent {
  final String userId;
  ProgressLoadRequested(this.userId);
}

class ProgressSessionCompleted extends ProgressEvent {
  final PerformanceSession session;
  final String             userId;
  ProgressSessionCompleted(this.session, this.userId);
}

// ── States ────────────────────────────────────────────────────────────────────
abstract class ProgressState {}

class ProgressInitial extends ProgressState {}

class ProgressLoading extends ProgressState {}

class ProgressLoaded extends ProgressState {
  final UserProgress               progress;
  final List<PerformanceSession>   recentSessions;
  final Map<DateTime, double>      weeklyAccuracy;
  final List<TimingCoachSuggestion>? lastSuggestions;

  ProgressLoaded({
    required this.progress,
    required this.recentSessions,
    required this.weeklyAccuracy,
    this.lastSuggestions,
  });

  ProgressLoaded copyWith({
    UserProgress?                 progress,
    List<PerformanceSession>?     recentSessions,
    Map<DateTime, double>?        weeklyAccuracy,
    List<TimingCoachSuggestion>?  lastSuggestions,
  }) => ProgressLoaded(
    progress:        progress       ?? this.progress,
    recentSessions:  recentSessions ?? this.recentSessions,
    weeklyAccuracy:  weeklyAccuracy ?? this.weeklyAccuracy,
    lastSuggestions: lastSuggestions ?? this.lastSuggestions,
  );
}

class ProgressError extends ProgressState {
  final String message;
  ProgressError(this.message);
}

// ── Bloc ──────────────────────────────────────────────────────────────────────
class ProgressBloc extends Bloc<ProgressEvent, ProgressState> {
  final GetUserProgressUseCase              _getProgress;
  final SaveSessionAndUpdateProgressUseCase _saveSession;
  final GetRecentSessionsUseCase            _getRecent;
  final GetWeeklyAccuracyUseCase            _getWeekly;
  final GetTimingCorrectionSuggestionsUseCase _getCoach;

  ProgressBloc({
    required GetUserProgressUseCase              getProgress,
    required SaveSessionAndUpdateProgressUseCase saveSession,
    required GetRecentSessionsUseCase            getRecent,
    required GetWeeklyAccuracyUseCase            getWeekly,
    required GetTimingCorrectionSuggestionsUseCase getCoach,
  })  : _getProgress = getProgress,
        _saveSession  = saveSession,
        _getRecent    = getRecent,
        _getWeekly    = getWeekly,
        _getCoach     = getCoach,
        super(ProgressInitial()) {
    on<ProgressLoadRequested>(_onLoad);
    on<ProgressSessionCompleted>(_onSessionCompleted);
  }

  Future<void> _onLoad(
    ProgressLoadRequested event, Emitter<ProgressState> emit,
  ) async {
    emit(ProgressLoading());
    try {
      final results = await Future.wait([
        _getProgress(event.userId),
        _getRecent(event.userId, limit: 10),
        _getWeekly(event.userId),
      ]);

      final progress  = (results[0] as UserProgress?) ?? _defaultProgress(event.userId);
      final sessions  = results[1] as List<PerformanceSession>;
      final weekly    = results[2] as Map<DateTime, double>;

      emit(ProgressLoaded(
        progress:       progress,
        recentSessions: sessions,
        weeklyAccuracy: weekly,
      ));
    } catch (e) {
      emit(ProgressError(e.toString()));
    }
  }

  Future<void> _onSessionCompleted(
    ProgressSessionCompleted event, Emitter<ProgressState> emit,
  ) async {
    final currentState = state;

    // ── Step 1: Optimistic local update ──────────────────────────────────────
    // Immediately reflect the new session and XP in the UI without waiting for
    // Firestore. This keeps the dashboard responsive even on slow networks.
    if (currentState is ProgressLoaded) {
      final session = event.session;
      final prev    = currentState.progress;

      // Compute updated XP and level locally using the same thresholds as the
      // domain entity so the progress bar advances right away.
      final newXp    = prev.totalXp + session.xpEarned;
      final newLevel = _calcLevelLocal(newXp);
      final newBest  = Map<String, int>.from(prev.songBestScores);
      final existing = newBest[session.song.id] ?? 0;
      if (session.totalScore > existing) newBest[session.song.id] = session.totalScore;

      final optimisticProgress = prev.copyWith(
        totalXp:       newXp,
        level:         newLevel,
        songBestScores: newBest,
      );

      final updatedSessions = [session, ...currentState.recentSessions]
          .take(10)
          .toList();

      emit(currentState.copyWith(
        progress:        optimisticProgress,
        recentSessions:  updatedSessions,
        lastSuggestions: _getCoach(session),
      ));
    }

    // ── Step 2: Persist to Firestore and sync final server values ─────────────
    try {
      final serverProgress = await _saveSession(event.session, event.userId);
      final freshSessions  = await _getRecent(event.userId, limit: 10);

      // Use server XP/level as ground truth; preserve displayName from optimistic state.
      final stateAfterSave = state;
      if (stateAfterSave is ProgressLoaded) {
        emit(stateAfterSave.copyWith(
          progress: serverProgress.copyWith(
            displayName: stateAfterSave.progress.displayName,
          ),
          recentSessions: freshSessions,
        ));
      }
    } catch (e) {
      // Firestore save failed — optimistic update is still displayed.
      // Log the error for diagnostics; do not block the user flow.
      debugPrint('[ProgressBloc] Session save error: $e');
    }
  }

  /// Mirrors UserRepositoryImpl._calculateLevel so the optimistic update uses
  /// the same formula as the backend.
  static int _calcLevelLocal(int totalXp) {
    int level = 1;
    int threshold = 500;
    int xpLeft = totalXp;
    while (xpLeft >= threshold) {
      xpLeft    -= threshold;
      level++;
      threshold  = (threshold * 1.5).toInt();
    }
    return level;
  }

  UserProgress _defaultProgress(String userId) => UserProgress(
    userId:           userId,
    displayName:      'Drummer',
    totalXp:          0,
    level:            1,
    currentStreak:    0,
    maxStreak:        0,
    songBestScores:   {},
    achievements:     [],
    lastPracticeDate: null,
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// SONGS BLOC
// ═════════════════════════════════════════════════════════════════════════════

// ── Events ────────────────────────────────────────────────────────────────────
abstract class SongsEvent {}
class SongsLoadRequested extends SongsEvent {}
class SongsFilterChanged extends SongsEvent {
  final Difficulty? difficulty;
  final Genre?      genre;
  final String?     searchQuery;
  SongsFilterChanged({this.difficulty, this.genre, this.searchQuery});
}

// ── States ────────────────────────────────────────────────────────────────────
abstract class SongsState {}
class SongsInitial extends SongsState {}
class SongsLoading extends SongsState {}
class SongsLoaded extends SongsState {
  final List<Song> allSongs;
  final List<Song> filtered;
  final Difficulty? filterDifficulty;
  final Genre?      filterGenre;
  final String      searchQuery;

  SongsLoaded({
    required this.allSongs,
    required this.filtered,
    this.filterDifficulty,
    this.filterGenre,
    this.searchQuery = '',
  });
}
class SongsError extends SongsState {
  final String message;
  SongsError(this.message);
}

// ── Bloc ──────────────────────────────────────────────────────────────────────
class SongsBloc extends Bloc<SongsEvent, SongsState> {
  final GetSongsUseCase _getSongs;

  SongsBloc(this._getSongs) : super(SongsInitial()) {
    on<SongsLoadRequested>(_onLoad);
    on<SongsFilterChanged>(_onFilter);
  }

  Future<void> _onLoad(SongsLoadRequested event, Emitter<SongsState> emit) async {
    emit(SongsLoading());
    try {
      final songs = await _getSongs();
      emit(SongsLoaded(allSongs: songs, filtered: songs));
    } catch (e) {
      emit(SongsError(e.toString()));
    }
  }

  void _onFilter(SongsFilterChanged event, Emitter<SongsState> emit) {
    final current = state;
    if (current is! SongsLoaded) return;

    final difficulty = event.difficulty ?? current.filterDifficulty;
    final genre      = event.genre      ?? current.filterGenre;
    final query      = event.searchQuery?.toLowerCase() ?? current.searchQuery;

    var filtered = current.allSongs;
    if (difficulty != null) {
      filtered = filtered.where((s) => s.difficulty == difficulty).toList();
    }
    if (genre != null) {
      filtered = filtered.where((s) => s.genre == genre).toList();
    }
    if (query.isNotEmpty) {
      filtered = filtered
          .where((s) =>
              s.title.toLowerCase().contains(query) ||
              s.artist.toLowerCase().contains(query))
          .toList();
    }

    emit(SongsLoaded(
      allSongs:         current.allSongs,
      filtered:         filtered,
      filterDifficulty: difficulty,
      filterGenre:      genre,
      searchQuery:      query,
    ));
  }
}
