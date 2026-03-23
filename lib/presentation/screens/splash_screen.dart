// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Splash Screen
// Se muestra en cada arranque (~2 s) antes de pasar al flujo principal.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/nava_theme.dart';

class SplashScreen extends StatefulWidget {
  /// Llamado cuando el splash termina su animación.
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Espera 2.6 s y luego pasa al siguiente flujo
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavaTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Ícono principal ────────────────────────────────────────
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NavaTheme.surface,
                border: Border.all(
                  color: NavaTheme.neonCyan,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: NavaTheme.neonCyan.withOpacity(0.35),
                    blurRadius: 40,
                    spreadRadius: 4,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/icon/app_icon.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.album_outlined,
                  color: NavaTheme.neonCyan,
                  size: 56,
                ),
              ),
            )
                .animate()
                .scale(
                  begin: const Offset(0.4, 0.4),
                  end: const Offset(1.0, 1.0),
                  duration: 600.ms,
                  curve: Curves.elasticOut,
                )
                .fadeIn(duration: 400.ms),

            const SizedBox(height: 32),

            // ── Nombre de la app ──────────────────────────────────────
            const Text(
              'NAVA',
              style: TextStyle(
                fontFamily: 'DrummerDisplay',
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: NavaTheme.textPrimary,
                letterSpacing: 8,
              ),
            )
                .animate(delay: 300.ms)
                .fadeIn(duration: 500.ms)
                .slideY(begin: 0.3, end: 0),

            const Text(
              'DRUMMER',
              style: TextStyle(
                fontFamily: 'DrummerDisplay',
                fontSize: 18,
                color: NavaTheme.neonCyan,
                letterSpacing: 12,
              ),
            )
                .animate(delay: 500.ms)
                .fadeIn(duration: 500.ms)
                .slideY(begin: 0.3, end: 0),

            const SizedBox(height: 60),

            // ── Tagline ───────────────────────────────────────────────
            const Text(
              'Aprende a tocar la batería',
              style: TextStyle(
                fontFamily: 'DrummerBody',
                fontSize: 13,
                color: NavaTheme.textMuted,
                letterSpacing: 1,
              ),
            )
                .animate(delay: 800.ms)
                .fadeIn(duration: 600.ms),

            const SizedBox(height: 48),

            // ── Indicador de carga ────────────────────────────────────
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                backgroundColor: NavaTheme.surface,
                color: NavaTheme.neonCyan,
                minHeight: 2,
              ),
            )
                .animate(delay: 1000.ms)
                .fadeIn(duration: 400.ms),
          ],
        ),
      ),
    );
  }
}
