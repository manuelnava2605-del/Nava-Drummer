import 'package:flutter/material.dart';
import '../../domain/entities/entities.dart';
import 'package:google_fonts/google_fonts.dart';

class NavaTheme {
  // ── Color Palette ──────────────────────────────────────────────────────────
  static const Color background     = Color(0xFF080C14);
  static const Color surface        = Color(0xFF0D1422);
  static const Color surfaceElevated= Color(0xFF131C2E);
  static const Color surfaceCard    = Color(0xFF1A2440);

  // Neon accents
  static const Color neonCyan       = Color(0xFF00F5FF);
  static const Color neonMagenta    = Color(0xFFFF006E);
  static const Color neonGold       = Color(0xFFFFD60A);
  static const Color neonGreen      = Color(0xFF39FF14);
  static const Color neonPurple     = Color(0xFFBF5AF2);

  // Hit classifications
  static const Color hitPerfect     = Color(0xFF00F5FF);
  static const Color hitGood        = Color(0xFFFFD60A);
  static const Color hitMiss        = Color(0xFFFF3B30);

  // Drum pad colors
  static const Color kick           = Color(0xFFFF6B35);
  static const Color snare          = Color(0xFF00F5FF);
  static const Color hihat          = Color(0xFFFFD60A);
  static const Color crash          = Color(0xFFFF006E);
  static const Color ride           = Color(0xFF39FF14);
  static const Color tom1           = Color(0xFFBF5AF2);
  static const Color tom2           = Color(0xFF5AC8FA);
  static const Color tom3           = Color(0xFFFF9500);
  static const Color floorTom       = Color(0xFFFF2D55);

  // Text
  static const Color textPrimary    = Color(0xFFEEF2FF);
  static const Color textSecondary  = Color(0xFF8896B3);
  static const Color textMuted      = Color(0xFF4A5568);

  // ── Gradients ──────────────────────────────────────────────────────────────
  static const LinearGradient neonGradient = LinearGradient(
    colors: [neonCyan, neonPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF080C14), Color(0xFF0D1422), Color(0xFF080C14)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient scorePerfect = LinearGradient(
    colors: [Color(0xFF00F5FF), Color(0xFF0080FF)],
  );

  static const LinearGradient scoreGood = LinearGradient(
    colors: [Color(0xFFFFD60A), Color(0xFFFF9500)],
  );

  // ── Glow Effects ───────────────────────────────────────────────────────────
  static List<BoxShadow> neonGlow(Color color, {double radius = 12}) => [
    BoxShadow(color: color.withOpacity(0.6), blurRadius: radius, spreadRadius: 1),
    BoxShadow(color: color.withOpacity(0.3), blurRadius: radius * 2),
  ];

  static List<BoxShadow> get cyanGlow => neonGlow(neonCyan);
  static List<BoxShadow> get goldGlow => neonGlow(neonGold);
  static List<BoxShadow> get magentaGlow => neonGlow(neonMagenta);

  // ── Typography ─────────────────────────────────────────────────────────────
  static TextTheme get textTheme => TextTheme(
    displayLarge: _displayFont(size: 48, weight: FontWeight.w700, color: textPrimary),
    displayMedium: _displayFont(size: 36, weight: FontWeight.w700, color: textPrimary),
    displaySmall: _displayFont(size: 28, weight: FontWeight.w700, color: textPrimary),
    headlineLarge: _displayFont(size: 24, weight: FontWeight.w700, color: textPrimary),
    headlineMedium: _displayFont(size: 20, weight: FontWeight.w600, color: textPrimary),
    headlineSmall: _displayFont(size: 18, weight: FontWeight.w600, color: textPrimary),
    titleLarge: _bodyFont(size: 16, weight: FontWeight.w600, color: textPrimary),
    titleMedium: _bodyFont(size: 14, weight: FontWeight.w600, color: textPrimary),
    titleSmall: _bodyFont(size: 12, weight: FontWeight.w600, color: textPrimary),
    bodyLarge: _bodyFont(size: 16, color: textSecondary),
    bodyMedium: _bodyFont(size: 14, color: textSecondary),
    bodySmall: _bodyFont(size: 12, color: textMuted),
    labelLarge: _bodyFont(size: 14, weight: FontWeight.w600, color: textPrimary),
    labelMedium: _bodyFont(size: 12, weight: FontWeight.w500, color: textSecondary),
    labelSmall: _bodyFont(size: 10, weight: FontWeight.w500, color: textMuted, spacing: 1.2),
  );

  static TextStyle _displayFont({
    required double size,
    FontWeight weight = FontWeight.w400,
    Color color = textPrimary,
  }) => GoogleFonts.orbitron(fontSize: size, fontWeight: weight, color: color, letterSpacing: 0.5);

  static TextStyle _bodyFont({
    required double size,
    FontWeight weight = FontWeight.w400,
    Color color = textPrimary,
    double spacing = 0,
  }) => GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing);

  // ── Theme Data ──────────────────────────────────────────────────────────────
  static Color padColor(DrumPad pad) {
    switch (pad) {
      case DrumPad.kick:                                    return kick;
      case DrumPad.snare:
      case DrumPad.rimshot:
      case DrumPad.crossstick:                              return snare;
      case DrumPad.hihatClosed:
      case DrumPad.hihatOpen:
      case DrumPad.hihatPedal:                              return hihat;
      case DrumPad.crash1:
      case DrumPad.crash2:                                  return crash;
      case DrumPad.ride:
      case DrumPad.rideBell:                                return ride;
      case DrumPad.tom1:                                    return tom1;
      case DrumPad.tom2:                                    return tom2;
      case DrumPad.tom3:                                    return tom3;
      case DrumPad.floorTom:                                return floorTom;
    }
  }

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      background: background,
      surface: surface,
      primary: neonCyan,
      secondary: neonMagenta,
      tertiary: neonGold,
      onBackground: textPrimary,
      onSurface: textPrimary,
      onPrimary: background,
      error: hitMiss,
    ),
    scaffoldBackgroundColor: background,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: _displayFont(size: 18, weight: FontWeight.w700, color: textPrimary),
      iconTheme: const IconThemeData(color: textPrimary),
    ),
    cardTheme: CardTheme(
      color: surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: neonCyan.withOpacity(0.15), width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: neonCyan,
        foregroundColor: background,
        textStyle: _displayFont(size: 14, weight: FontWeight.w700, color: background),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: neonCyan,
        side: const BorderSide(color: neonCyan, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: neonCyan.withOpacity(0.1),
      thickness: 1,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: neonCyan,
      inactiveTrackColor: surfaceCard,
      thumbColor: neonCyan,
      overlayColor: neonCyan.withOpacity(0.2),
      valueIndicatorColor: neonCyan,
      valueIndicatorTextStyle: _bodyFont(size: 12, color: background),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.resolveWith((states) =>
          states.contains(MaterialState.selected) ? neonCyan : textMuted),
      trackColor: MaterialStateProperty.resolveWith((states) =>
          states.contains(MaterialState.selected) ? neonCyan.withOpacity(0.4) : surfaceCard),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: neonCyan,
      unselectedItemColor: textMuted,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

// ── Semantic Color Extensions ──────────────────────────────────────────────
extension HitColorExtension on String {
  Color get hitColor {
    switch (this) {
      case 'perfect': return NavaTheme.hitPerfect;
      case 'good':    return NavaTheme.hitGood;
      case 'miss':    return NavaTheme.hitMiss;
      default:        return NavaTheme.textMuted;
    }
  }
}

// ── padColor extension (added for Fase 2) ─────────────────────────────────
