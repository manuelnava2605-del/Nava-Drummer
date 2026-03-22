// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Latency Calibration Screen
// Allows users to measure and adjust audio/MIDI latency offset.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/global_timing_controller.dart';
import '../theme/nava_theme.dart';

// ── Device Latency Profile ────────────────────────────────────────────────────
class DeviceLatencyProfile {
  final String deviceId;
  final String deviceName;
  final int    offsetMs;   // positive = notes hit early, negative = late

  const DeviceLatencyProfile({
    required this.deviceId,
    required this.deviceName,
    required this.offsetMs,
  });

  Map<String, dynamic> toJson() => {
    'deviceId':   deviceId,
    'deviceName': deviceName,
    'offsetMs':   offsetMs,
  };

  factory DeviceLatencyProfile.fromJson(Map<String, dynamic> j) =>
    DeviceLatencyProfile(
      deviceId:   j['deviceId'] as String,
      deviceName: j['deviceName'] as String,
      offsetMs:   j['offsetMs'] as int,
    );
}

// ── Calibration Repository ────────────────────────────────────────────────────
class CalibrationRepository {
  static const _keyOffset = 'latency_offset_ms';

  static Future<int> loadOffset() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyOffset) ?? 0;
  }

  static Future<void> saveOffset(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyOffset, ms);
    // Apply immediately to the global timing controller
    GlobalTimingController.instance.applySyncOffset(ms * 1000);
  }
}

// ── Calibration Screen ────────────────────────────────────────────────────────
class LatencyCalibrationScreen extends StatefulWidget {
  const LatencyCalibrationScreen({super.key});

  @override
  State<LatencyCalibrationScreen> createState() => _LatencyCalibrationScreenState();
}

class _LatencyCalibrationScreenState extends State<LatencyCalibrationScreen>
    with SingleTickerProviderStateMixin {

  int    _offsetMs      = 0;
  bool   _metronomeOn   = false;
  int    _beatCount     = 0;
  Timer? _metroTimer;
  late AnimationController _beatCtrl;

  // Tap tempo measurement
  final List<int> _tapTimes = [];
  int?            _measuredOffset;

  @override
  void initState() {
    super.initState();
    _beatCtrl = AnimationController(vsync: this, duration: 120.ms);
    _loadOffset();
  }

  Future<void> _loadOffset() async {
    final v = await CalibrationRepository.loadOffset();
    if (mounted) setState(() => _offsetMs = v);
  }

  void _startMetronome() {
    setState(() { _metronomeOn = true; _beatCount = 0; });
    _metroTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _beatCount++);
      _beatCtrl.forward(from: 0);
    });
  }

  void _stopMetronome() {
    _metroTimer?.cancel();
    setState(() { _metronomeOn = false; _beatCount = 0; });
  }

  void _onTap() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _tapTimes.add(now);
    if (_tapTimes.length > 8) _tapTimes.removeAt(0);

    if (_tapTimes.length >= 2 && _metronomeOn) {
      // Estimate offset: difference between tap and nearest expected beat
      // Beat period = 500ms (120 BPM), measure phase offset
      final lastTap = _tapTimes.last;
      final phase = lastTap % 500;
      final offset = phase > 250 ? phase - 500 : phase;
      setState(() => _measuredOffset = offset);
    }
  }

  void _applyMeasured() {
    if (_measuredOffset != null) {
      setState(() => _offsetMs = _measuredOffset!);
      _measuredOffset = null;
    }
  }

  Future<void> _saveAndClose() async {
    await CalibrationRepository.saveOffset(_offsetMs);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Latencia guardada: ${_offsetMs}ms',
              style: const TextStyle(fontFamily: 'DrummerBody')),
          backgroundColor: NavaTheme.neonGreen.withOpacity(0.8),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _metroTimer?.cancel();
    _beatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavaTheme.background,
      appBar: AppBar(
        backgroundColor: NavaTheme.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: NavaTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('CALIBRACIÓN', style: TextStyle(
            fontFamily: 'DrummerDisplay', fontSize: 16,
            color: NavaTheme.textPrimary, letterSpacing: 2)),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Explanation
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NavaTheme.surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NavaTheme.neonCyan.withOpacity(0.15)),
              ),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('¿QUÉ ES LA LATENCIA?', style: TextStyle(
                    fontFamily: 'DrummerDisplay', fontSize: 12,
                    color: NavaTheme.neonCyan, letterSpacing: 1)),
                SizedBox(height: 8),
                Text(
                  'Si sientes que los golpes se califican muy temprano o muy tarde, '
                  'ajusta el offset. Valor positivo = compensar retraso del sistema. '
                  'Valor negativo = compensar anticipación.',
                  style: TextStyle(fontFamily: 'DrummerBody', fontSize: 12,
                      color: NavaTheme.textSecondary, height: 1.5),
                ),
              ]),
            ).animate().fadeIn(duration: 300.ms),

            const SizedBox(height: 28),

            // Current offset display
            Center(child: Column(children: [
              const Text('OFFSET ACTUAL', style: TextStyle(
                  fontFamily: 'DrummerBody', fontSize: 10,
                  letterSpacing: 2, color: NavaTheme.textMuted)),
              const SizedBox(height: 8),
              Text(
                '${_offsetMs > 0 ? "+" : ""}$_offsetMs ms',
                style: TextStyle(
                  fontFamily: 'DrummerDisplay', fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: _offsetMs == 0
                      ? NavaTheme.neonCyan
                      : _offsetMs > 0
                          ? NavaTheme.neonGold
                          : NavaTheme.neonPurple,
                ),
              ),
            ])).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 24),

            // Slider
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor:   NavaTheme.neonCyan,
                thumbColor:         NavaTheme.neonCyan,
                inactiveTrackColor: NavaTheme.surfaceCard,
                overlayColor:       NavaTheme.neonCyan.withOpacity(0.15),
                trackHeight:        4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              ),
              child: Slider(
                value:     _offsetMs.toDouble(),
                min:       -200, max: 200, divisions: 80,
                onChanged: (v) => setState(() => _offsetMs = v.round()),
              ),
            ),

            // Fine controls
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _StepBtn(label: '−20ms', onTap: () => setState(() => _offsetMs = (_offsetMs - 20).clamp(-200, 200))),
              const SizedBox(width: 8),
              _StepBtn(label: '−5ms',  onTap: () => setState(() => _offsetMs = (_offsetMs - 5).clamp(-200, 200))),
              const SizedBox(width: 8),
              _StepBtn(label: 'RESET', color: NavaTheme.textMuted,
                onTap: () => setState(() => _offsetMs = 0)),
              const SizedBox(width: 8),
              _StepBtn(label: '+5ms',  onTap: () => setState(() => _offsetMs = (_offsetMs + 5).clamp(-200, 200))),
              const SizedBox(width: 8),
              _StepBtn(label: '+20ms', onTap: () => setState(() => _offsetMs = (_offsetMs + 20).clamp(-200, 200))),
            ]).animate().fadeIn(delay: 150.ms),

            const SizedBox(height: 32),

            // Metronome tap test
            const Text('TEST DE TAP', style: TextStyle(fontFamily: 'DrummerBody',
                fontSize: 10, letterSpacing: 2, color: NavaTheme.textMuted)),
            const SizedBox(height: 12),

            Row(children: [
              // Metronome toggle
              GestureDetector(
                onTap: _metronomeOn ? _stopMetronome : _startMetronome,
                child: AnimatedContainer(
                  duration: 200.ms,
                  width:  56, height: 56,
                  decoration: BoxDecoration(
                    color: _metronomeOn
                        ? NavaTheme.neonCyan.withOpacity(0.15)
                        : NavaTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: NavaTheme.neonCyan.withOpacity(0.4)),
                  ),
                  child: Icon(
                    _metronomeOn ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    color: NavaTheme.neonCyan, size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Tap button
              Expanded(child: GestureDetector(
                onTap: _onTap,
                child: AnimatedBuilder(
                  animation: _beatCtrl,
                  builder: (_, __) => Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        NavaTheme.neonPurple.withOpacity(0.08),
                        NavaTheme.neonPurple.withOpacity(0.30),
                        _metronomeOn ? (1 - _beatCtrl.value) : 0,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: NavaTheme.neonPurple.withOpacity(0.5)),
                    ),
                    child: Center(child: Text(
                      'TOCAR AQUÍ AL RITMO',
                      style: TextStyle(fontFamily: 'DrummerDisplay', fontSize: 12,
                          letterSpacing: 1,
                          color: NavaTheme.neonPurple.withOpacity(0.9)),
                    )),
                  ),
                ),
              )),
            ]),

            if (_measuredOffset != null) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _applyMeasured,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: NavaTheme.neonGold.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: NavaTheme.neonGold.withOpacity(0.4)),
                  ),
                  child: Center(child: Text(
                    'Aplicar offset medido: ${_measuredOffset! > 0 ? "+" : ""}${_measuredOffset}ms',
                    style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 12,
                        color: NavaTheme.neonGold),
                  )),
                ),
              ).animate().fadeIn(duration: 200.ms),
            ],

            const SizedBox(height: 32),

            // Save button
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _saveAndClose,
              style: ElevatedButton.styleFrom(
                backgroundColor: NavaTheme.neonCyan,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('GUARDAR', style: TextStyle(fontFamily: 'DrummerDisplay',
                  fontSize: 14, color: NavaTheme.background,
                  fontWeight: FontWeight.bold, letterSpacing: 2)),
            )).animate().fadeIn(delay: 200.ms),
          ]),
        ),
      ),
    );
  }
}

// ── Step button ───────────────────────────────────────────────────────────────
class _StepBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _StepBtn({required this.label, required this.onTap,
    this.color = NavaTheme.neonCyan});
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(fontFamily: 'DrummerBody',
          fontSize: 9, color: color, letterSpacing: 0.5)),
    ),
  );
}
