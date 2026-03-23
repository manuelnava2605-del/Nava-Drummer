import 'package:flutter/material.dart';
import '../../core/global_timing_controller.dart';
import '../theme/nava_theme.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  double _offsetMs = 0;

  @override
  void initState() {
    super.initState();
    _offsetMs = GlobalTimingController.instance.userOffsetMs;
  }

  void _updateOffset(double value) {
    setState(() => _offsetMs = value);
    GlobalTimingController.instance.setUserOffsetMs(value);
  }

  void _reset() {
    setState(() => _offsetMs = 0);
    GlobalTimingController.instance.setUserOffsetMs(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavaTheme.background,
      appBar: AppBar(
        title: const Text('CALIBRATION'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AUDIO / INPUT OFFSET',
              style: TextStyle(
                fontFamily: 'DrummerDisplay',
                fontSize: 16,
                color: NavaTheme.textPrimary,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Adjust until your hits feel perfectly in sync with the music.',
              style: TextStyle(
                fontFamily: 'DrummerBody',
                fontSize: 13,
                color: NavaTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                '${_offsetMs.toStringAsFixed(0)} ms',
                style: TextStyle(
                  fontFamily: 'DrummerDisplay',
                  fontSize: 36,
                  color: _offsetMs == 0
                      ? NavaTheme.textPrimary
                      : NavaTheme.neonCyan,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Slider(
              min: -100,
              max: 100,
              divisions: 200,
              value: _offsetMs,
              onChanged: _updateOffset,
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('-100 ms', style: TextStyle(color: NavaTheme.textMuted)),
                Text('0', style: TextStyle(color: NavaTheme.textMuted)),
                Text('+100 ms', style: TextStyle(color: NavaTheme.textMuted)),
              ],
            ),
            const SizedBox(height: 40),
            const Text(
              'HOW TO CALIBRATE',
              style: TextStyle(
                fontFamily: 'DrummerDisplay',
                fontSize: 12,
                color: NavaTheme.textPrimary,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '• If you hear the sound BEFORE you hit -> move slider LEFT\n'
              '• If you hear the sound AFTER you hit -> move slider RIGHT\n'
              '• Goal: hits feel perfectly aligned with music',
              style: TextStyle(
                fontFamily: 'DrummerBody',
                fontSize: 13,
                color: NavaTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reset,
                    child: const Text('RESET'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('DONE'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
