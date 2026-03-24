import 'dart:async';
import 'package:flutter/services.dart';
import '../../../domain/entities/entities.dart';

/// High-level MIDI engine that communicates with native iOS/Android MIDI layers.
/// All MIDI processing happens on native threads; events arrive via EventChannel.
class MidiEngine {
  static const _methodChannel = MethodChannel('com.navadrummer/midi_engine');
  static const _eventChannel  = EventChannel('com.navadrummer/midi_events');
  static const _deviceChannel = EventChannel('com.navadrummer/midi_devices');

  StreamSubscription? _eventSub;
  StreamSubscription? _deviceSub;

  final _midiEventController  = StreamController<MidiEvent>.broadcast();
  final _deviceListController = StreamController<List<MidiDevice>>.broadcast();

  Stream<MidiEvent>       get midiEvents  => _midiEventController.stream;
  Stream<List<MidiDevice>> get deviceList => _deviceListController.stream;

  bool _isStarted = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  Future<void> start() async {
    if (_isStarted) return;
    try {
      await _methodChannel.invokeMethod('startEngine');
      _listenToMidiEvents();
      _listenToDeviceChanges();
      _isStarted = true;
    } on PlatformException catch (e) {
      throw MidiEngineException('Failed to start MIDI engine: ${e.message}');
    }
  }

  Future<void> stop() async {
    if (!_isStarted) return;
    await _eventSub?.cancel();
    await _deviceSub?.cancel();
    await _methodChannel.invokeMethod('stopEngine');
    _isStarted = false;
  }

  void dispose() {
    stop();
    _midiEventController.close();
    _deviceListController.close();
  }
  /// Injects a synthetic MIDI event — used by Demo Mode to simulate hits.
  void injectSyntheticEvent(MidiEvent event) {
    _midiEventController.add(event);
  }


  // ── Device Management ──────────────────────────────────────────────────────
  Future<List<MidiDevice>> getConnectedDevices() async {
    final List<dynamic> raw = await _methodChannel.invokeMethod('getConnectedDevices');
    return raw.map((d) => _parseDevice(d as Map)).toList();
  }

  Future<void> connectDevice(String deviceId) async {
    await _methodChannel.invokeMethod('connectDevice', {'deviceId': deviceId});
  }

  Future<void> disconnectDevice(String deviceId) async {
    await _methodChannel.invokeMethod('disconnectDevice', {'deviceId': deviceId});
  }

  Future<void> startBluetoothScan() async {
    await _methodChannel.invokeMethod('startBluetoothScan');
  }

  Future<void> stopBluetoothScan() async {
    await _methodChannel.invokeMethod('stopBluetoothScan');
  }

  // ── Latency Calibration ────────────────────────────────────────────────────
  /// Returns measured round-trip latency in microseconds.
  Future<int> measureLatency() async {
    final int latencyUs = await _methodChannel.invokeMethod('measureLatency');
    return latencyUs;
  }

  Future<void> setLatencyOffset(int offsetMicros) async {
    await _methodChannel.invokeMethod('setLatencyOffset', {'offsetMicros': offsetMicros});
  }

  // ── Event Streams ──────────────────────────────────────────────────────────
  void _listenToMidiEvents() {
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (dynamic raw) {
        try {
          final event = _parseMidiEvent(raw as Map);
          if (!_midiEventController.isClosed) {
            _midiEventController.add(event);
          }
        } catch (e) {
          // Log parse errors but don't crash
        }
      },
      onError: (error) => _midiEventController.addError(error),
    );
  }

  void _listenToDeviceChanges() {
    _deviceSub = _deviceChannel.receiveBroadcastStream().listen(
      (dynamic raw) {
        try {
          final List<dynamic> devices = raw as List;
          final parsed = devices.map((d) => _parseDevice(d as Map)).toList();
          if (!_deviceListController.isClosed) {
            _deviceListController.add(parsed);
          }
        } catch (e) {
          // Log parse errors
        }
      },
    );
  }

  // ── Parsing ────────────────────────────────────────────────────────────────
  MidiEvent _parseMidiEvent(Map raw) {
    // Use null-safe casts so that BT devices sending integers as a different
    // numeric type (e.g. long/double from native) don't silently drop events.
    int _i(Object? v) => (v is int) ? v : (v is num ? v.toInt() : 0);

    final typeInt = _i(raw['type']);
    return MidiEvent(
      type:            _parseMidiEventType(typeInt),
      channel:         _i(raw['channel']),
      note:            _i(raw['note']),
      velocity:        _i(raw['velocity']),
      timestampMicros: _i(raw['timestampMicros']),
      deviceId:        raw['deviceId'] as String?,
    );
  }

  MidiEventType _parseMidiEventType(int type) {
    // MIDI status byte upper nibble
    switch (type) {
      case 0x80: return MidiEventType.noteOff;
      case 0x90: return MidiEventType.noteOn;
      case 0xB0: return MidiEventType.controlChange;
      case 0xC0: return MidiEventType.programChange;
      default:   return MidiEventType.noteOn;
    }
  }

  MidiDevice _parseDevice(Map raw) {
    final transportStr = raw['transport'] as String? ?? 'usb';
    final brandStr     = raw['brand'] as String? ?? 'generic';
    return MidiDevice(
      id:         raw['id'] as String,
      name:       raw['name'] as String,
      vendorId:   raw['vendorId'] as int?,
      productId:  raw['productId'] as int?,
      transport:  _parseTransport(transportStr),
      brand:      _parseBrand(brandStr),
      isConnected: raw['isConnected'] as bool? ?? false,
    );
  }

  DeviceTransport _parseTransport(String s) {
    switch (s) {
      case 'bluetooth': return DeviceTransport.bluetooth;
      case 'virtual':   return DeviceTransport.virtual;
      default:          return DeviceTransport.usb;
    }
  }

  DrumKitBrand _parseBrand(String s) {
    switch (s.toLowerCase()) {
      case 'roland':  return DrumKitBrand.roland;
      case 'alesis':  return DrumKitBrand.alesis;
      case 'yamaha':  return DrumKitBrand.yamaha;
      case 'ddrum':   return DrumKitBrand.ddrum;
      case 'pearl':   return DrumKitBrand.pearl;
      default:        return DrumKitBrand.generic;
    }
  }
}

class MidiEngineException implements Exception {
  final String message;
  const MidiEngineException(this.message);
  @override String toString() => 'MidiEngineException: $message';
}
