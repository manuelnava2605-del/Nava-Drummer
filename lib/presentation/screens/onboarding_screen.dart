// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Onboarding Screen  (Fase 4)
// Quick Start · Demo Mode · Tutorial · Auto-detección · Celebración
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../domain/entities/entities.dart';
import '../../core/practice_engine.dart';
import '../../data/datasources/local/midi_engine.dart';
import '../theme/nava_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Onboarding Flow  (4 pages)
// ═══════════════════════════════════════════════════════════════════════════
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardPage(
      emoji:    '🥁',
      title:    'Bienvenido a\nNavaDrummer',
      subtitle: 'Aprende batería con notas cayendo,\nfeedback en tiempo real y un catálogo\nde canciones reales.',
      cta:      'COMENZAR',
    ),
    _OnboardPage(
      emoji:    '🎮',
      title:    'Como un\nvideojuego',
      subtitle: 'Las notas caen hacia la línea de golpe.\nToca en el momento exacto para conseguir\nPERFECT y construir combo.',
      cta:      'SIGUIENTE',
    ),
    _OnboardPage(
      emoji:    '🎛️',
      title:    'MIDI o\nmicrófono',
      subtitle: 'Conecta tu batería electrónica por USB\no Bluetooth. Si no tienes kit, usa el\nmodo demostración.',
      cta:      'SIGUIENTE',
    ),
    _OnboardPage(
      emoji:    '✝️',
      title:    'Canciones\nreales',
      subtitle: 'Aprende desde himnos de adoración\nhasta rock clásico, funk y metal.\nDe principiante a experto.',
      cta:      'EMPEZAR A TOCAR',
    ),
  ];

  void _next() {
    if (_page < _pages.length - 1) {
      _pageCtrl.nextPage(duration: 300.ms, curve: Curves.easeInOut);
      setState(() => _page++);
    } else {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavaTheme.background,
      body: Stack(children: [
        // Animated background grid
        const _AnimatedGrid(),

        Column(children: [
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              onPageChanged: (i) => setState(() => _page = i),
              itemCount: _pages.length,
              itemBuilder: (_, i) => _OnboardPageView(page: _pages[i]),
            ),
          ),

          // Dots
          Row(mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pages.length, (i) => AnimatedContainer(
              duration: 200.ms,
              width:  _page == i ? 24 : 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: _page == i ? NavaTheme.neonCyan : NavaTheme.textMuted.withOpacity(0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ))),

          const SizedBox(height: 24),

          // CTA button
          Padding(
            padding: EdgeInsets.fromLTRB(32, 0, 32,
                MediaQuery.of(context).padding.bottom + 24),
            child: GestureDetector(
              onTap: _next,
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [NavaTheme.neonCyan, NavaTheme.neonPurple],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: NavaTheme.cyanGlow,
                ),
                child: Center(child: Text(_pages[_page].cta,
                  style: const TextStyle(fontFamily: 'DrummerDisplay',
                      fontSize: 14, letterSpacing: 2, color: NavaTheme.background,
                      fontWeight: FontWeight.bold))),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _OnboardPage {
  final String emoji, title, subtitle, cta;
  const _OnboardPage({required this.emoji, required this.title,
      required this.subtitle, required this.cta});
}

class _OnboardPageView extends StatelessWidget {
  final _OnboardPage page;
  const _OnboardPageView({super.key, required this.page});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(32, MediaQuery.of(context).padding.top + 48, 32, 0),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(page.emoji, style: const TextStyle(fontSize: 72))
          .animate().scale(duration: 500.ms, curve: Curves.elasticOut),
      const SizedBox(height: 32),
      Text(page.title, textAlign: TextAlign.center,
        style: const TextStyle(fontFamily: 'DrummerDisplay', fontSize: 32,
            color: NavaTheme.textPrimary, fontWeight: FontWeight.bold, height: 1.2))
          .animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.2),
      const SizedBox(height: 16),
      Text(page.subtitle, textAlign: TextAlign.center,
        style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 15,
            color: NavaTheme.textSecondary, height: 1.6))
          .animate().fadeIn(delay: 200.ms, duration: 400.ms),
    ]),
  );
}

class _AnimatedGrid extends StatelessWidget {
  const _AnimatedGrid();
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: 0.04,
    child: GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
      itemCount: 200,
      itemBuilder: (_, i) => Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          border: Border.all(color: NavaTheme.neonCyan, width: 0.5),
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Demo Mode  —  simula golpes automáticos desde el MIDI cargado
// ═══════════════════════════════════════════════════════════════════════════
class DemoModeController {
  final PracticeEngine engine;
  final MidiEngine     midiEngine;
  bool _running = false;
  Timer? _timer;

  DemoModeController({required this.engine, required this.midiEngine});

  /// Empieza el demo: inyecta hits perfectos desde [notes] con timing real.
  void start(List<NoteEvent> notes) {
    if (_running || notes.isEmpty) return;
    _running = true;

    final startTime = DateTime.now();
    for (final note in notes) {
      final delayMs = (note.timeSeconds * 1000).round();
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (!_running) return;
        // Inject a fake perfect hit via the MIDI stream
        midiEngine.injectSyntheticEvent(MidiEvent(
          type:            MidiEventType.noteOn,
          channel:         9,
          note:            note.midiNote,
          velocity:        note.velocity,
          timestampMicros: startTime
              .add(Duration(milliseconds: delayMs))
              .microsecondsSinceEpoch,
        ));
      });
    }
  }

  void stop() {
    _running = false;
    _timer?.cancel();
  }

  void dispose() => stop();
}

// ═══════════════════════════════════════════════════════════════════════════
// Quick Start Banner  (shown on SongLibraryScreen if first session)
// ═══════════════════════════════════════════════════════════════════════════
class QuickStartBanner extends StatelessWidget {
  final VoidCallback onDemo;
  final VoidCallback onDismiss;

  const QuickStartBanner({super.key, required this.onDemo, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [NavaTheme.neonCyan.withOpacity(0.12),
                   NavaTheme.neonPurple.withOpacity(0.08)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NavaTheme.neonCyan.withOpacity(0.3)),
      ),
      child: Row(children: [
        const Text('🎮', style: TextStyle(fontSize: 28)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('¿Primera vez?', style: TextStyle(fontFamily: 'DrummerDisplay',
              fontSize: 13, color: NavaTheme.textPrimary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          const Text('Prueba el modo demo — no necesitas batería.',
            style: TextStyle(fontFamily: 'DrummerBody', fontSize: 11,
                color: NavaTheme.textSecondary)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onDemo,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: NavaTheme.neonCyan,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('VER DEMO', style: TextStyle(fontFamily: 'DrummerDisplay',
                  fontSize: 11, color: NavaTheme.background, letterSpacing: 1)),
            ),
          ),
        ])),
        GestureDetector(
          onTap: onDismiss,
          child: const Icon(Icons.close, color: NavaTheme.textMuted, size: 18),
        ),
      ]),
    ).animate().slideY(begin: -0.3, duration: 400.ms, curve: Curves.easeOut)
     .fadeIn(duration: 400.ms);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// First Success Celebration overlay
// ═══════════════════════════════════════════════════════════════════════════
class FirstSuccessCelebration extends StatefulWidget {
  final VoidCallback onDismiss;
  const FirstSuccessCelebration({super.key, required this.onDismiss});

  @override
  State<FirstSuccessCelebration> createState() => _FirstSuccessCelebrationState();
}

class _FirstSuccessCelebrationState extends State<FirstSuccessCelebration>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: 3.seconds)..forward();
    Future.delayed(4.seconds, () { if (mounted) widget.onDismiss(); });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        color: Colors.black.withOpacity(0.75),
        child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('🎉', style: const TextStyle(fontSize: 80))
              .animate().scale(duration: 500.ms, curve: Curves.elasticOut),
          const SizedBox(height: 20),
          const Text('¡PRIMER GOLPE!', style: TextStyle(fontFamily: 'DrummerDisplay',
              fontSize: 32, color: NavaTheme.neonGold, fontWeight: FontWeight.bold,
              letterSpacing: 3))
              .animate().fadeIn(delay: 300.ms).slideY(begin: 0.3),
          const SizedBox(height: 10),
          const Text('Acabas de dar tu primer golpe perfecto.\n¡Sigue así!',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'DrummerBody', fontSize: 15,
                color: NavaTheme.textSecondary, height: 1.5))
              .animate().fadeIn(delay: 500.ms),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: widget.onDismiss,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                color: NavaTheme.neonGold,
                borderRadius: BorderRadius.circular(12),
                boxShadow: NavaTheme.goldGlow,
              ),
              child: const Text('¡CONTINUAR!', style: TextStyle(
                  fontFamily: 'DrummerDisplay', fontSize: 14,
                  color: NavaTheme.background, letterSpacing: 2)),
            ),
          ).animate().fadeIn(delay: 800.ms),
        ])),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// In-app Tutorial Overlay  (4 steps, shown on first PracticeScreen open)
// ═══════════════════════════════════════════════════════════════════════════
class TutorialOverlay extends StatefulWidget {
  final VoidCallback onDone;
  const TutorialOverlay({super.key, required this.onDone});

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  int _step = 0;

  static const _steps = [
    _TutStep(
      icon:    Icons.arrow_downward,
      title:   'Las notas caen',
      body:    'Cada nota cae hacia la línea blanca.\nToca el pad correcto cuando llegue.',
      align:   Alignment.center,
    ),
    _TutStep(
      icon:    Icons.my_location,
      title:   'Línea de golpe',
      body:    'Los círculos en la línea indican qué\npad tocar. Cada color = un instrumento.',
      align:   Alignment(0, 0.7),
    ),
    _TutStep(
      icon:    Icons.star,
      title:   'Calificación',
      body:    'PERFECT < 30ms · GOOD < 80ms\nMISS > 150ms. ¡Construye tu combo!',
      align:   Alignment(0.8, -0.3),
    ),
    _TutStep(
      icon:    Icons.speed,
      title:   'Ajusta el tempo',
      body:    'Usa el botón ⚙️ para bajar el tempo\nal 50% mientras aprendes.',
      align:   Alignment(0.8, -0.8),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    return GestureDetector(
      onTap: () {
        if (_step < _steps.length - 1) setState(() => _step++);
        else widget.onDone();
      },
      child: Container(
        color: Colors.black.withOpacity(0.72),
        child: Stack(children: [
          Align(
            alignment: step.align,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: NavaTheme.neonCyan.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: NavaTheme.neonCyan, width: 2),
                  ),
                  child: Icon(step.icon, color: NavaTheme.neonCyan, size: 28),
                ),
                const SizedBox(height: 14),
                Text(step.title, style: const TextStyle(fontFamily: 'DrummerDisplay',
                    fontSize: 20, color: NavaTheme.textPrimary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(step.body, textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 14,
                      color: NavaTheme.textSecondary, height: 1.5)),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: NavaTheme.neonCyan,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_step < _steps.length-1 ? 'SIGUIENTE →' : 'ENTENDIDO ✓',
                    style: const TextStyle(fontFamily: 'DrummerDisplay', fontSize: 12,
                        color: NavaTheme.background, letterSpacing: 1)),
                ),
              ]),
            ).animate().fadeIn(duration: 250.ms).scale(begin: const Offset(0.9,0.9)),
          ),

          // Step indicator
          Positioned(
            bottom: 40, left: 0, right: 0,
            child: Row(mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_steps.length, (i) => AnimatedContainer(
                duration: 200.ms, width: _step==i ? 20 : 7, height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: _step==i ? NavaTheme.neonCyan : NavaTheme.textMuted.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(4)),
              ))),
          ),
        ]),
      ),
    );
  }
}

class _TutStep {
  final IconData icon;
  final String   title, body;
  final Alignment align;
  const _TutStep({required this.icon, required this.title,
      required this.body, required this.align});
}
