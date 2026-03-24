import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../domain/entities/entities.dart';
import '../../data/datasources/local/midi_engine.dart';
import '../../l10n/strings.dart';
import '../theme/nava_theme.dart';

class DeviceSetupScreen extends StatefulWidget {
  final MidiEngine midiEngine;
  final void Function(MidiDevice device, DrumMapping mapping) onDeviceSelected;

  const DeviceSetupScreen({
    super.key,
    required this.midiEngine,
    required this.onDeviceSelected,
  });

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  List<MidiDevice> _devices = [];
  MidiDevice? _selectedDevice;
  bool _isScanning = false;
  SetupStep _step = SetupStep.selectDevice;

  // Pad mapping — note (MIDI number) → DrumPad
  // Seeded from brand defaults in _proceedToMapping(); updated live as user hits pads.
  Map<int, DrumPad> _customNoteMap = {};
  DrumPad? _awaitingPad;
  StreamSubscription? _mappingSub;
  StreamSubscription? _deviceListSub;

  // ── MIDI monitor (shows last received event so user can confirm signal) ────
  StreamSubscription? _monitorSub;
  String _midiStatus = 'Esperando señal MIDI…';
  int    _midiEventCount = 0;

  @override
  void initState() {
    super.initState();
    _startEngine();
  }

  Future<void> _startEngine() async {
    await widget.midiEngine.start();
    final devices = await widget.midiEngine.getConnectedDevices();
    if (mounted) setState(() => _devices = devices);

    _deviceListSub = widget.midiEngine.deviceList.listen((devices) {
      if (mounted) setState(() => _devices = devices);
    });
  }

  @override
  void dispose() {
    _mappingSub?.cancel();
    _monitorSub?.cancel();
    _deviceListSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavaTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _step == SetupStep.selectDevice
                  ? _buildDeviceList()
                  : _buildPadMapping(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Logo / brand
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: NavaTheme.neonGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: NavaTheme.cyanGlow,
                ),
                child: const Icon(Icons.music_note, color: NavaTheme.background, size: 24),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NAVA', style: TextStyle(
                    fontFamily: 'DrummerDisplay', fontSize: 22,
                    color: NavaTheme.neonCyan, fontWeight: FontWeight.bold, letterSpacing: 4,
                  )),
                  Text('DRUMMER', style: TextStyle(
                    fontFamily: 'DrummerDisplay', fontSize: 10,
                    color: NavaTheme.textSecondary, letterSpacing: 6,
                  )),
                ],
              ),
            ],
          ).animate().fadeIn(duration: 600.ms).slideX(begin: -0.2),

          const SizedBox(height: 28),

          // Step indicator
          _StepIndicator(currentStep: _step),
        ],
      ),
    );
  }

  // ── Device List ───────────────────────────────────────────────────────────
  Widget _buildDeviceList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(S.of(context).deviceTitle, style: const TextStyle(
                fontFamily: 'DrummerDisplay', fontSize: 14,
                color: NavaTheme.textPrimary, letterSpacing: 2,
              )),
              _ScanButton(
                isScanning: _isScanning,
                onTap: _toggleScan,
              ),
            ],
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 8),
          Text(S.of(context).deviceSubtitle, style: const TextStyle(
            fontFamily: 'DrummerBody', fontSize: 13, color: NavaTheme.textSecondary,
          )).animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 24),

          Expanded(
            child: _devices.isEmpty
                ? _buildEmptyDevices()
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (_, i) => _buildDeviceCard(_devices[i], i),
                  ),
          ),

          // Continue button
          if (_selectedDevice != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _proceedToMapping,
                child: Text(S.of(context).deviceConfigPads),
              ),
            ).animate().slideY(begin: 0.3, duration: 300.ms),
          ],

          // Skip (use virtual / acoustic)
          TextButton(
            onPressed: _skipToApp,
            child: Text(S.of(context).deviceSkip, style: const TextStyle(
              fontFamily: 'DrummerBody', fontSize: 13, color: NavaTheme.textMuted,
            )),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(MidiDevice device, int index) {
    final isSelected = _selectedDevice?.id == device.id;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedDevice = device);
        widget.midiEngine.connectDevice(device.id);
      },
      child: AnimatedContainer(
        duration: 200.ms,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? NavaTheme.neonCyan.withValues(alpha: 0.12) : NavaTheme.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? NavaTheme.neonCyan : NavaTheme.neonCyan.withValues(alpha: 0.15),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? NavaTheme.cyanGlow : null,
        ),
        child: Row(
          children: [
            // Brand icon
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: _brandColor(device.brand).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  _brandEmoji(device.brand),
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.name, style: const TextStyle(
                    fontFamily: 'DrummerBody', fontSize: 14,
                    color: NavaTheme.textPrimary, fontWeight: FontWeight.bold,
                  )),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _TransportBadge(transport: device.transport),
                      const SizedBox(width: 6),
                      _BrandBadge(brand: device.brand),
                    ],
                  ),
                ],
              ),
            ),

            // Selected indicator
            if (isSelected)
              const Icon(Icons.check_circle, color: NavaTheme.neonCyan, size: 22),
          ],
        ),
      ).animate().fadeIn(delay: Duration(milliseconds: 100 * index)).slideX(begin: 0.2),
    );
  }

  Widget _buildEmptyDevices() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🥁', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          const Text('No MIDI devices detected', style: TextStyle(
            fontFamily: 'DrummerDisplay', fontSize: 16, color: NavaTheme.textSecondary,
          )),
          const SizedBox(height: 8),
          const Text('Connect your drum kit via USB or enable Bluetooth',
            style: TextStyle(fontFamily: 'DrummerBody', fontSize: 13, color: NavaTheme.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (_isScanning)
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(
                  color: NavaTheme.neonCyan, strokeWidth: 2,
                )),
                SizedBox(width: 8),
                Text('Scanning for Bluetooth MIDI...', style: TextStyle(
                  fontFamily: 'DrummerBody', fontSize: 12, color: NavaTheme.neonCyan,
                )),
              ],
            ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms);
  }

  // ── Pad Mapping ───────────────────────────────────────────────────────────
  Widget _buildPadMapping() {
    final pads = [
      DrumPad.kick, DrumPad.snare, DrumPad.hihatClosed,
      DrumPad.hihatOpen, DrumPad.tom1, DrumPad.tom2,
      DrumPad.floorTom, DrumPad.crash1, DrumPad.ride,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PAD MAPPING', style: TextStyle(
            fontFamily: 'DrummerDisplay', fontSize: 14,
            color: NavaTheme.textPrimary, letterSpacing: 2,
          )),
          const SizedBox(height: 6),
          Text(
            _selectedDevice?.brand == DrumKitBrand.generic
                ? 'Tap each pad on your kit to assign it'
                : 'Auto-mapped for ${_selectedDevice?.brand.name.toUpperCase()}. Tap to override.',
            style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 13, color: NavaTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          // ── MIDI signal monitor ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _midiEventCount > 0
                  ? NavaTheme.neonGreen.withValues(alpha: 0.08)
                  : NavaTheme.neonMagenta.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _midiEventCount > 0
                    ? NavaTheme.neonGreen.withValues(alpha: 0.4)
                    : NavaTheme.neonMagenta.withValues(alpha: 0.3),
              ),
            ),
            child: Row(children: [
              Icon(
                _midiEventCount > 0 ? Icons.sensors : Icons.sensors_off,
                size: 14,
                color: _midiEventCount > 0 ? NavaTheme.neonGreen : NavaTheme.neonMagenta,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(
                _midiStatus,
                style: TextStyle(
                  fontFamily: 'DrummerBody',
                  fontSize: 12,
                  color: _midiStatus.startsWith('✓')
                      ? const Color(0xFF00E676)
                      : _midiStatus.startsWith('⚠')
                          ? const Color(0xFFFFAB40)
                          : NavaTheme.textSecondary,
                ),
              )),
            ]),
          ),
          const SizedBox(height: 14),

          Expanded(
            child: ListView.builder(
              itemCount: pads.length,
              itemBuilder: (_, i) => _buildPadRow(pads[i]),
            ),
          ),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                // _selectedDevice should never be null here (guarded by
                // _proceedToMapping) but fall back to a virtual device so the
                // button is never silently disabled.
                final device = _selectedDevice ?? const MidiDevice(
                  id: 'none', name: 'No Device',
                  transport: DeviceTransport.virtual,
                );
                final mapping = DrumMapping(
                  deviceId: device.id,
                  noteMap:  _customNoteMap.isNotEmpty
                      ? _customNoteMap
                      : StandardDrumMaps.generalMidi,
                );
                widget.onDeviceSelected(device, mapping);
              },
              child: const Text('START PLAYING →'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPadRow(DrumPad pad) {
    final isAwaiting   = _awaitingPad == pad;
    // Find MIDI note currently assigned to this pad in the live custom map.
    final assignedNote = _customNoteMap.entries
        .where((e) => e.value == pad)
        .map((e) => e.key)
        .firstOrNull;

    return GestureDetector(
      onTap: () => _startMapping(pad),
      child: AnimatedContainer(
        duration: 200.ms,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isAwaiting ? NavaTheme.neonMagenta.withValues(alpha: 0.1) : NavaTheme.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isAwaiting ? NavaTheme.neonMagenta : NavaTheme.neonCyan.withValues(alpha: 0.15),
            width: isAwaiting ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _padColor(pad).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(pad.shortName, style: TextStyle(
                  fontFamily: 'DrummerDisplay', fontSize: 11,
                  color: _padColor(pad), fontWeight: FontWeight.bold,
                )),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(pad.displayName, style: const TextStyle(
                fontFamily: 'DrummerBody', fontSize: 13, color: NavaTheme.textPrimary,
              )),
            ),
            if (isAwaiting)
              const Text('HIT NOW', style: TextStyle(
                fontFamily: 'DrummerDisplay', fontSize: 11, color: NavaTheme.neonMagenta,
              ))
            else if (assignedNote != null)
              Text('Note $assignedNote', style: const TextStyle(
                fontFamily: 'DrummerBody', fontSize: 11, color: NavaTheme.textSecondary,
              ))
            else
              const Text('Tap to map', style: TextStyle(
                fontFamily: 'DrummerBody', fontSize: 11, color: NavaTheme.textMuted,
              )),
          ],
        ),
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  Future<void> _toggleScan() async {
    if (_isScanning) {
      await widget.midiEngine.stopBluetoothScan();
      if (mounted) setState(() => _isScanning = false);
      return;
    }

    // Request runtime BT permissions (Android 12+ needs BLUETOOTH_SCAN +
    // BLUETOOTH_CONNECT; older versions need location).
    final granted = await _requestBluetoothPermissions();
    if (!granted) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: NavaTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(S.of(context).deviceBtPermTitle,
              style: const TextStyle(fontFamily: 'DrummerDisplay',
                  fontSize: 15, color: NavaTheme.textPrimary)),
          content: Text(S.of(context).deviceBtPermMsg,
              style: const TextStyle(fontFamily: 'DrummerBody',
                  fontSize: 13, color: NavaTheme.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(S.of(context).ok,
                  style: const TextStyle(color: NavaTheme.neonCyan)),
            ),
            TextButton(
              onPressed: () { Navigator.pop(context); openAppSettings(); },
              child: const Text('Open settings',
                  style: TextStyle(color: NavaTheme.neonMagenta,
                      fontFamily: 'DrummerBody')),
            ),
          ],
        ),
      );
      return;
    }

    await widget.midiEngine.startBluetoothScan();
    if (mounted) setState(() => _isScanning = true);
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && _isScanning) {
        widget.midiEngine.stopBluetoothScan();
        setState(() => _isScanning = false);
      }
    });
  }

  Future<bool> _requestBluetoothPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    return statuses.values.every(
      (s) => s.isGranted || s.isLimited || s.isPermanentlyDenied == false,
    );
  }

  Future<void> _proceedToMapping() async {
    // Seed the custom map with brand defaults so known pads already show notes.
    final brand = _selectedDevice?.brand ?? DrumKitBrand.generic;
    _customNoteMap = Map.of(StandardDrumMaps.forBrand(brand));

    // Re-issue connectDevice so the native layer (re-)routes events from BT
    // devices to the event channel before the monitor subscription starts.
    if (_selectedDevice != null && _selectedDevice!.id != 'none') {
      try {
        await widget.midiEngine.connectDevice(_selectedDevice!.id);
      } catch (_) {}
    }

    if (mounted) setState(() => _step = SetupStep.mapPads);
    _startMidiMonitor();
  }

  /// Passive listener that shows raw MIDI events so the user can confirm
  /// that the kit is actually sending data before mapping.
  /// Also retries connectDevice after 5 s if no events received (BT routing fix).
  void _startMidiMonitor() {
    _monitorSub?.cancel();
    _midiEventCount = 0;
    _midiStatus = 'Buscando señal MIDI...';

    // BT retry: if no events in 5 s, re-issue connectDevice to force routing.
    Timer? retryTimer;
    if (_selectedDevice != null && _selectedDevice!.id != 'none') {
      retryTimer = Timer(const Duration(seconds: 5), () async {
        if (_midiEventCount == 0 && mounted) {
          setState(() => _midiStatus = 'Reintentando conexión...');
          try {
            await widget.midiEngine.connectDevice(_selectedDevice!.id);
          } catch (_) {}
          if (mounted && _midiEventCount == 0) {
            setState(() => _midiStatus =
                '⚠ Sin señal MIDI. Verifica que el dispositivo está en modo MIDI y enviando notas.');
          }
        }
      });
    }

    _monitorSub = widget.midiEngine.midiEvents.listen((e) {
      if (!mounted) return;
      retryTimer?.cancel();
      setState(() {
        _midiEventCount++;
        _midiStatus =
            '✓ Señal recibida — ch${e.channel} nota ${e.note} vel ${e.velocity}  '
            '($_midiEventCount eventos)';
      });
    });
  }

  void _skipToApp() {
    final genericMapping = DrumMapping(
      deviceId: 'none',
      noteMap: StandardDrumMaps.generalMidi,
    );
    widget.onDeviceSelected(
      const MidiDevice(
        id: 'none',
        name: 'No Device',
        transport: DeviceTransport.virtual,
      ),
      genericMapping,
    );
  }

  void _startMapping(DrumPad pad) {
    setState(() => _awaitingPad = pad);
    _mappingSub?.cancel();
    // Accept any event with velocity > 0 — covers kits that send NoteOff with
    // non-zero velocity, or whose status byte isn't decoded as 0x90 by the
    // native layer but still carries a valid note + velocity payload.
    _mappingSub = widget.midiEngine.midiEvents
        .where((e) => e.velocity > 0)
        .first
        .asStream()
        .listen((event) {
          if (mounted) {
            setState(() {
              // Remove any previous assignment for this pad, then store the new note.
              _customNoteMap.removeWhere((_, v) => v == pad);
              _customNoteMap[event.note] = pad;
              _awaitingPad = null;
            });
          }
        });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Color _brandColor(DrumKitBrand brand) {
    switch (brand) {
      case DrumKitBrand.roland:  return const Color(0xFFFF0000);
      case DrumKitBrand.alesis:  return const Color(0xFF0055FF);
      case DrumKitBrand.yamaha:  return const Color(0xFF000080);
      default:                return NavaTheme.neonCyan;
    }
  }

  String _brandEmoji(DrumKitBrand brand) {
    switch (brand) {
      case DrumKitBrand.roland:  return '🔴';
      case DrumKitBrand.alesis:  return '🔵';
      case DrumKitBrand.yamaha:  return '🟤';
      case DrumKitBrand.ddrum:   return '🟠';
      default:                return '🥁';
    }
  }

  Color _padColor(DrumPad pad) {
    switch (pad) {
      case DrumPad.kick:        return NavaTheme.kick;
      case DrumPad.snare:       return NavaTheme.snare;
      case DrumPad.hihatClosed:
      case DrumPad.hihatOpen:   return NavaTheme.hihat;
      case DrumPad.crash1:
      case DrumPad.crash2:      return NavaTheme.crash;
      case DrumPad.ride:        return NavaTheme.ride;
      case DrumPad.tom1:        return NavaTheme.tom1;
      case DrumPad.tom2:        return NavaTheme.tom2;
      case DrumPad.floorTom:    return NavaTheme.floorTom;
      default:                   return NavaTheme.neonCyan;
    }
  }
}

// ── Enums & Widgets ───────────────────────────────────────────────────────
enum SetupStep { selectDevice, mapPads }

class _StepIndicator extends StatelessWidget {
  final SetupStep currentStep;
  const _StepIndicator({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Dot(label: '1  CONNECT', active: currentStep == SetupStep.selectDevice),
        Expanded(child: Container(height: 1, color: NavaTheme.neonCyan.withValues(alpha: 0.2))),
        _Dot(label: '2  CALIBRATE', active: currentStep == SetupStep.mapPads),
        Expanded(child: Container(height: 1, color: NavaTheme.neonCyan.withValues(alpha: 0.2))),
        const _Dot(label: '3  PLAY', active: false),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final String label;
  final bool active;
  const _Dot({required this.label, required this.active});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 10, height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? NavaTheme.neonCyan : NavaTheme.textMuted,
          boxShadow: active ? NavaTheme.cyanGlow : null,
        ),
      ),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(
        fontFamily: 'DrummerBody', fontSize: 9, letterSpacing: 1,
        color: active ? NavaTheme.neonCyan : NavaTheme.textMuted,
      )),
    ],
  );
}

class _ScanButton extends StatelessWidget {
  final bool isScanning;
  final VoidCallback onTap;
  const _ScanButton({required this.isScanning, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isScanning ? NavaTheme.neonCyan.withValues(alpha: 0.15) : NavaTheme.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isScanning ? NavaTheme.neonCyan : NavaTheme.neonCyan.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isScanning) ...[
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(
              color: NavaTheme.neonCyan, strokeWidth: 2,
            )),
            const SizedBox(width: 6),
          ],
          Icon(isScanning ? Icons.bluetooth_searching : Icons.bluetooth,
            color: NavaTheme.neonCyan, size: 16),
          const SizedBox(width: 4),
          Text(isScanning ? 'Scanning...' : 'Scan BLE',
            style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 11, color: NavaTheme.neonCyan)),
        ],
      ),
    ),
  );
}

class _TransportBadge extends StatelessWidget {
  final DeviceTransport transport;
  const _TransportBadge({required this.transport});

  @override
  Widget build(BuildContext context) {
    final label = transport == DeviceTransport.bluetooth ? 'BLE' : 'USB';
    final color = transport == DeviceTransport.bluetooth ? NavaTheme.neonPurple : NavaTheme.neonGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: TextStyle(
        fontFamily: 'DrummerBody', fontSize: 9, color: color, fontWeight: FontWeight.bold,
      )),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  final DrumKitBrand brand;
  const _BrandBadge({required this.brand});

  @override
  Widget build(BuildContext context) {
    if (brand == DrumKitBrand.generic) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: NavaTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(brand.name.toUpperCase(), style: const TextStyle(
        fontFamily: 'DrummerBody', fontSize: 9, color: NavaTheme.textSecondary,
      )),
    );
  }
}
