// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — App Strings (ES / EN)
//
// Usage:
//   S.of(context).navSongs          // from any Widget
//   S.current.navSongs              // from non-widget code
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/widgets.dart';
import '../core/locale_controller.dart';

class S {
  final bool _isEn;
  const S._(this._isEn);

  // ── Factory ───────────────────────────────────────────────────────────────

  static S of(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return S._(locale.languageCode == 'en');
  }

  static S get current {
    final code = LocaleController.instance.languageCode;
    return S._(code == 'en');
  }

  // ── Bottom navigation ─────────────────────────────────────────────────────

  String get navSongs    => _isEn ? 'SONGS'    : 'CANCIONES';
  String get navProgress => _isEn ? 'PROGRESS' : 'PROGRESO';
  String get navSettings => _isEn ? 'SETTINGS' : 'AJUSTES';

  // ── Auth screen ───────────────────────────────────────────────────────────

  String get authWelcome       => _isEn ? 'Welcome back' : 'Bienvenido';
  String get authSubtitle      => _isEn ? 'Log in to continue your progress'
                                        : 'Inicia sesión para continuar tu progreso';
  String get authEmail         => _isEn ? 'Email'        : 'Correo electrónico';
  String get authPassword      => _isEn ? 'Password'     : 'Contraseña';
  String get authLogin         => _isEn ? 'LOG IN'       : 'INICIAR SESIÓN';
  String get authRegister      => _isEn ? 'REGISTER'     : 'REGISTRARSE';
  String get authGoogle        => _isEn ? 'Continue with Google' : 'Continuar con Google';
  String get authGuest         => _isEn ? 'Continue as guest'    : 'Continuar sin cuenta';
  String get authRememberMe    => _isEn ? 'Remember session'     : 'Recordar sesión';
  String get authNoAccount     => _isEn ? "Don't have an account?"   : '¿No tienes cuenta?';
  String get authHaveAccount   => _isEn ? 'Already have an account?' : '¿Ya tienes cuenta?';
  String get authName          => _isEn ? 'Name'         : 'Nombre';
  String get authConfirmPass   => _isEn ? 'Confirm password' : 'Confirmar contraseña';

  // ── Dashboard ─────────────────────────────────────────────────────────────

  String get dashHello         => _isEn ? 'Hello'         : 'Hola';
  String get dashStreak        => _isEn ? 'day streak'    : 'días de racha';
  String get dashLevel         => _isEn ? 'LEVEL'         : 'NIVEL';
  String get dashTotalXp       => _isEn ? 'TOTAL XP'      : 'XP TOTAL';
  String get dashToNext        => _isEn ? 'to next level' : 'para el siguiente nivel';
  String get dashWeeklyAcc     => _isEn ? 'ACCURACY THIS WEEK' : 'PRECISIÓN ESTA SEMANA';
  String get dashAchievements  => _isEn ? 'ACHIEVEMENTS'  : 'LOGROS';
  String get dashRecentSessions=> _isEn ? 'RECENT SESSIONS' : 'SESIONES RECIENTES';
  String get dashStreak2       => _isEn ? 'STREAK'        : 'RACHA';
  String get dashBestCombo     => _isEn ? 'BEST COMBO'    : 'MEJOR COMBO';
  String get dashSongs         => _isEn ? 'SONGS'         : 'CANCIONES';

  // ── Settings ──────────────────────────────────────────────────────────────

  String get settingsTitle        => _isEn ? 'Settings'           : 'Ajustes';
  String get settingsAccount      => _isEn ? 'ACCOUNT'            : 'CUENTA';
  String get settingsPreferences  => _isEn ? 'PREFERENCES'        : 'PREFERENCIAS';
  String get settingsLanguage     => _isEn ? 'Language'           : 'Idioma';
  String get settingsRememberMe   => _isEn ? 'Remember session'   : 'Recordar sesión';
  String get settingsNotifications=> _isEn ? 'Push notifications' : 'Notificaciones';
  String get settingsDevice       => _isEn ? 'MIDI device'        : 'Dispositivo MIDI';
  String get settingsCalibration  => _isEn ? 'Latency calibration': 'Calibración de latencia';
  String get settingsLogout       => _isEn ? 'Log out'            : 'Cerrar sesión';
  String get settingsLogoutConfirm=> _isEn ? 'Log out?'           : 'Cerrar sesión';
  String get settingsLogoutMsg    => _isEn ? 'Are you sure you want to log out?'
                                           : '¿Seguro que quieres cerrar sesión?';
  String get settingsCancel       => _isEn ? 'Cancel'  : 'Cancelar';
  String get settingsConfirm      => _isEn ? 'Log out' : 'Salir';
  String get settingsVersion      => _isEn ? 'Version' : 'Versión';
  String get settingsPrivacy      => _isEn ? 'Privacy policy' : 'Política de privacidad';
  String get settingsTerms        => _isEn ? 'Terms of service' : 'Términos de uso';

  // ── Song library ──────────────────────────────────────────────────────────

  String get libraryTitle    => _isEn ? 'Song Library'    : 'Catálogo';
  String get librarySearch   => _isEn ? 'Search songs…'   : 'Buscar canciones…';
  String get libraryDownload => _isEn ? 'DOWNLOAD'        : 'DESCARGAR';
  String get libraryPlay     => _isEn ? 'PLAY'            : 'TOCAR';
  String get libraryLocked   => _isEn ? 'Locked'          : 'Bloqueada';
  String get libraryAll      => _isEn ? 'All'             : 'Todos';

  // ── Practice screen ───────────────────────────────────────────────────────

  String get practiceExitTitle   => _isEn ? 'Exit session?'         : '¿Salir de la sesión?';
  String get practiceExitMsg     => _isEn ? 'Your progress in this session will not be saved.'
                                           : 'Tu progreso en esta sesión\nno se guardará.';
  String get practiceKeepPlaying => _isEn ? 'KEEP PLAYING' : 'CONTINUAR';
  String get practiceExit        => _isEn ? 'EXIT'          : 'SALIR';
  String get practiceLoading     => _isEn ? 'Loading song…' : 'Cargando canción…';
  String get practiceLoadError   => _isEn ? 'Could not load song'  : 'No se pudo cargar la canción';
  String get practiceRetry       => _isEn ? 'RETRY'  : 'REINTENTAR';
  String get practiceBack        => _isEn ? 'BACK'   : 'VOLVER';
  String get practiceSettings    => _isEn ? 'SETTINGS'  : 'AJUSTES';
  String get practiceTempo       => _isEn ? 'TEMPO'     : 'TEMPO';
  String get practiceTrack       => _isEn ? 'TRACK'     : 'PISTA';
  String get practiceDrums       => _isEn ? 'DRUMS'     : 'BATERÍA';
  String get practiceLoopOn      => _isEn ? 'Loop ON'   : 'Loop ACTIVADO';
  String get practiceLoopOff     => _isEn ? 'Loop off'  : 'Loop desactivado';
  String get practiceModeGame    => _isEn ? 'Mode: Falling notes' : 'Modo: Notas cayendo';
  String get practiceModeSheet   => _isEn ? 'Mode: Sheet music'   : 'Modo: Partitura';

  // ── Session summary ───────────────────────────────────────────────────────

  String get summaryCoach     => _isEn ? '🧠 COACH SAYS'        : '🧠 COACH DICE';
  String get summaryByDrum    => _isEn ? '🥁 BY INSTRUMENT'     : '🥁 POR INSTRUMENTO';
  String get summaryPractice  => _isEn ? '📚 PRACTICE THIS'     : '📚 PRACTICA ESTO';
  String get summaryRetry     => _isEn ? 'RETRY'                : 'REINTENTAR';
  String get summaryExit      => _isEn ? 'EXIT'                 : 'SALIR';
  String get summarySkills    => _isEn ? 'SKILLS'               : 'HABILIDADES';
  String get summaryTiming    => _isEn ? 'TIMING'               : 'TIMING';
  String get summaryAccuracy  => _isEn ? 'ACCURACY'             : 'PRECISIÓN';
  String get summaryConsist   => _isEn ? 'CONSISTENCY'          : 'CONSISTENCIA';
  String get summaryDynamics  => _isEn ? 'DYNAMICS'             : 'DINÁMICA';

  // ── Paywall ───────────────────────────────────────────────────────────────

  String get paywallTitle       => _isEn ? 'NavaDrummer Pro'  : 'NavaDrummer Pro';
  String get paywallSubtitle    => _isEn ? 'Full catalog · AI Coach · No limits'
                                         : 'Catálogo completo · Coach de IA · Sin límites';
  String get paywallTrialBtn    => _isEn ? 'Try FREE for 7 days'    : 'Probar 7 días GRATIS';
  String get paywallTrialSub    => _isEn ? 'No charge until it expires' : 'Sin cargo hasta que venza';
  String get paywallMonthlyLbl  => _isEn ? 'Monthly'    : 'Mensual';
  String get paywallYearlyLbl   => _isEn ? 'Annual'     : 'Anual';
  String get paywallBestValue   => _isEn ? 'BEST VALUE' : 'MEJOR VALOR';
  String get paywallRestore     => _isEn ? 'Restore purchase'  : 'Restaurar compra';
  String get paywallNotNow      => _isEn ? 'Not now'           : 'Ahora no';
  String get paywallLegal       => _isEn
      ? 'Subscription renews automatically. Cancel any time.'
      : 'La suscripción se renueva automáticamente. Cancela en cualquier momento.';

  // ── Generic ───────────────────────────────────────────────────────────────

  String get ok      => _isEn ? 'OK'      : 'OK';
  String get cancel  => _isEn ? 'Cancel'  : 'Cancelar';
  String get save    => _isEn ? 'Save'    : 'Guardar';
  String get close   => _isEn ? 'Close'   : 'Cerrar';
  String get loading => _isEn ? 'Loading…': 'Cargando…';
  String get error   => _isEn ? 'Error'   : 'Error';
  String get retry   => _isEn ? 'Retry'   : 'Reintentar';
}
