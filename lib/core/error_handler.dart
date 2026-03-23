// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Error Handling & Connectivity
// Global error handler, offline mode, user-facing error widget
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../presentation/theme/nava_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ConnectivityService
// ─────────────────────────────────────────────────────────────────────────────
class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._();
  ConnectivityService._();

  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get onlineStream => _controller.stream;
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  StreamSubscription? _sub;

  void init() {
    _sub = Connectivity().onConnectivityChanged.listen((result) {
      final online = result != ConnectivityResult.none;
      if (online != _isOnline) {
        _isOnline = online;
        _controller.add(online);
      }
    });
    // Check initial state
    Connectivity().checkConnectivity().then((result) {
      _isOnline = result != ConnectivityResult.none;
    });
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ErrorHandler — wraps Crashlytics and provides user-friendly messages
// ─────────────────────────────────────────────────────────────────────────────
class ErrorHandler {
  static void recordError(Object error, StackTrace? stack,
      {String? context, bool fatal = false}) {
    try {
      FirebaseCrashlytics.instance.recordError(
        error, stack,
        reason:    context,
        fatal:     fatal,
        printDetails: true,
      );
    } catch (_) {
      // Crashlytics not initialized — just print
      debugPrint('ERROR [$context]: $error');
    }
  }

  static String userMessage(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('network') || msg.contains('socket')) {
      return 'Sin conexión a internet. Comprueba tu red e intenta de nuevo.';
    }
    if (msg.contains('permission')) {
      return 'Permiso denegado. Verifica los permisos en Ajustes.';
    }
    if (msg.contains('not found') || msg.contains('404')) {
      return 'Contenido no encontrado. Intenta de nuevo más tarde.';
    }
    if (msg.contains('midi') || msg.contains('bluetooth')) {
      return 'Error de conexión MIDI. Desconecta y vuelve a conectar tu batería.';
    }
    if (msg.contains('firebase') || msg.contains('firestore')) {
      return 'Error de sincronización. Los datos locales se guardaron.';
    }
    return 'Algo salió mal. Por favor intenta de nuevo.';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummerApp wrapper with global error boundary
// ─────────────────────────────────────────────────────────────────────────────
class AppErrorBoundary extends StatefulWidget {
  final Widget child;
  const AppErrorBoundary({super.key, required this.child});

  @override
  State<AppErrorBoundary> createState() => _AppErrorBoundaryState();
}

class _AppErrorBoundaryState extends State<AppErrorBoundary> {
  Object?     _error;
  // ignore: unused_field
  StackTrace? _stack;

  @override
  void initState() {
    super.initState();
    FlutterError.onError = (details) {
      ErrorHandler.recordError(
          details.exception, details.stack,
          context: 'FlutterError', fatal: false);
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: NavaTheme.background,
          body: Center(child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('🥁', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 20),
              const Text('NavaDrummer encontró un problema',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'DrummerDisplay',
                    fontSize: 18, color: NavaTheme.textPrimary)),
              const SizedBox(height: 12),
              Text(ErrorHandler.userMessage(_error!),
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'DrummerBody',
                    fontSize: 13, color: NavaTheme.textSecondary, height: 1.5)),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: () => setState(() { _error = null; _stack = null; }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NavaTheme.neonCyan,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('REINICIAR', style: TextStyle(
                    fontFamily: 'DrummerDisplay', color: NavaTheme.background,
                    letterSpacing: 2)),
              ),
            ]),
          )),
        ),
      );
    }
    return widget.child;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OfflineBanner — shown when device goes offline
// ─────────────────────────────────────────────────────────────────────────────
class OfflineBanner extends StatefulWidget {
  final Widget child;
  const OfflineBanner({super.key, required this.child});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _offline = false;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ConnectivityService.instance.onlineStream.listen((online) {
      if (mounted) setState(() => _offline = !online);
    });
    _offline = !ConnectivityService.instance.isOnline;
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (_offline) _buildBanner(),
      Expanded(child: widget.child),
    ]);
  }

  Widget _buildBanner() => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    color:   NavaTheme.neonGold.withOpacity(0.15),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child:   Row(children: [
      const Text('📡', style: TextStyle(fontSize: 14)),
      const SizedBox(width: 8),
      const Expanded(child: Text(
        'Sin conexión — funcionalidad limitada',
        style: TextStyle(fontFamily: 'DrummerBody', fontSize: 11,
            color: NavaTheme.neonGold),
      )),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading shimmer widget (reusable)
// ─────────────────────────────────────────────────────────────────────────────
class ShimmerCard extends StatelessWidget {
  final double height;
  final double? width;
  const ShimmerCard({super.key, this.height = 80, this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  width,
      height: height,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color:        NavaTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(
            color: NavaTheme.neonCyan.withOpacity(0.06)),
      ),
    );
  }
}
