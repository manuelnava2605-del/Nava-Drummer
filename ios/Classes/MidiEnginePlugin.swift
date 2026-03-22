import CoreMIDI
import CoreBluetooth
import Flutter
import Foundation
import os.log

// MARK: - NavaDrummer MIDI Engine Plugin (iOS)
// Uses CoreMIDI for USB/network MIDI and CoreBluetooth for BLE MIDI
// All MIDI processing runs on a dedicated high-priority queue

@objc public class MidiEnginePlugin: NSObject, FlutterPlugin {

    // Flutter channels
    private var methodChannel: FlutterMethodChannel?
    private var eventSink: FlutterEventSink?
    private var deviceSink: FlutterEventSink?

    // CoreMIDI
    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var virtualSource: MIDIEndpointRef = 0

    // BLE MIDI
    private var centralManager: CBCentralManager?
    private var peripherals: [CBPeripheral] = []
    private var bleDeviceMap: [String: CBPeripheral] = [:]

    // High-priority processing queue (NOT main thread)
    private let midiQueue = DispatchQueue(
        label: "com.navadrummer.midi",
        qos: .userInteractive,
        attributes: [],
        autoreleaseFrequency: .workItem
    )

    // Latency compensation
    private var latencyOffsetMicros: Int64 = 0
    private var connectedDeviceIds: Set<String> = []

    // Device catalog
    private var knownDevices: [String: MidiDeviceInfo] = [:]

    private let log = OSLog(subsystem: "com.navadrummer", category: "MIDIEngine")

    // MARK: - Registration
    public static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = MidiEnginePlugin()

        let methodCh = FlutterMethodChannel(
            name: "com.navadrummer/midi_engine",
            binaryMessenger: registrar.messenger()
        )
        let eventCh = FlutterEventChannel(
            name: "com.navadrummer/midi_events",
            binaryMessenger: registrar.messenger()
        )
        let deviceCh = FlutterEventChannel(
            name: "com.navadrummer/midi_devices",
            binaryMessenger: registrar.messenger()
        )

        plugin.methodChannel = methodCh
        registrar.addMethodCallDelegate(plugin, channel: methodCh)
        eventCh.setStreamHandler(plugin.midiEventHandler)
        deviceCh.setStreamHandler(plugin.deviceListHandler)
    }

    // MARK: - Stream Handlers
    private lazy var midiEventHandler = BlockStreamHandler(
        onListen: { [weak self] _, sink in self?.eventSink = sink },
        onCancel: { [weak self] _ in self?.eventSink = nil }
    )

    private lazy var deviceListHandler = BlockStreamHandler(
        onListen: { [weak self] _, sink in
            self?.deviceSink = sink
            self?.broadcastDeviceList()
        },
        onCancel: { [weak self] _ in self?.deviceSink = nil }
    )

    // MARK: - Method Channel
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startEngine":
            startEngine(result: result)
        case "stopEngine":
            stopEngine(result: result)
        case "getConnectedDevices":
            getConnectedDevices(result: result)
        case "connectDevice":
            if let args = call.arguments as? [String: Any],
               let deviceId = args["deviceId"] as? String {
                connectDevice(deviceId: deviceId, result: result)
            }
        case "disconnectDevice":
            if let args = call.arguments as? [String: Any],
               let deviceId = args["deviceId"] as? String {
                disconnectDevice(deviceId: deviceId, result: result)
            }
        case "startBluetoothScan":
            startBluetoothScan(result: result)
        case "stopBluetoothScan":
            stopBluetoothScan(result: result)
        case "measureLatency":
            measureLatency(result: result)
        case "setLatencyOffset":
            if let args = call.arguments as? [String: Any],
               let offset = args["offsetMicros"] as? Int {
                latencyOffsetMicros = Int64(offset)
                result(nil)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Engine Lifecycle
    private func startEngine(result: @escaping FlutterResult) {
        midiQueue.async { [weak self] in
            guard let self = self else { return }

            // Create MIDI client
            let clientStatus = MIDIClientCreateWithBlock(
                "NavaDrummer" as CFString,
                &self.midiClient
            ) { [weak self] notification in
                self?.handleMIDINotification(notification)
            }

            guard clientStatus == noErr else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "MIDI_ERROR",
                                        message: "Failed to create MIDI client: \(clientStatus)",
                                        details: nil))
                }
                return
            }

            // Create input port with block-based callback (high precision)
            let portStatus = MIDIInputPortCreateWithProtocol(
                self.midiClient,
                "NavaDrummerInput" as CFString,
                MIDIProtocolID._1_0,
                &self.inputPort
            ) { [weak self] eventList, srcConnRefCon in
                self?.handleMIDIEventList(eventList, srcRef: srcConnRefCon)
            }

            guard portStatus == noErr else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "MIDI_ERROR",
                                        message: "Failed to create input port: \(portStatus)",
                                        details: nil))
                }
                return
            }

            // Connect all existing sources
            self.connectAllSources()

            // Initialize BLE central manager
            self.centralManager = CBCentralManager(
                delegate: self,
                queue: self.midiQueue,
                options: [CBCentralManagerOptionShowPowerAlertKey: true]
            )

            os_log("MIDI Engine started", log: self.log, type: .info)

            DispatchQueue.main.async { result(nil) }
        }
    }

    private func stopEngine(result: @escaping FlutterResult) {
        midiQueue.async { [weak self] in
            guard let self = self else { return }
            MIDIPortDispose(self.inputPort)
            MIDIClientDispose(self.midiClient)
            self.midiClient = 0
            self.inputPort = 0
            DispatchQueue.main.async { result(nil) }
        }
    }

    // MARK: - MIDI Event Processing
    /// Called on MIDI I/O thread — must be lock-free and non-blocking
    private func handleMIDIEventList(
        _ eventList: UnsafePointer<MIDIEventList>,
        srcRef: UnsafeRawPointer?
    ) {
        let now = AudioGetCurrentHostTime()
        let nowMicros = Int64(AudioConvertHostTimeToNanos(now) / 1000) + latencyOffsetMicros

        var packet = eventList.pointee.packet
        for _ in 0..<eventList.pointee.numPackets {
            processUniversalPacket(&packet, timestampMicros: nowMicros)
            packet = MIDIEventPacketNext(&packet).pointee
        }
    }

    private func processUniversalPacket(
        _ packet: inout MIDIEventPacket,
        timestampMicros: Int64
    ) {
        // Parse MIDI 1.0 messages from Universal MIDI Packet words
        let wordCount = Int(packet.wordCount)
        withUnsafeBytes(of: packet.words) { ptr in
            let words = ptr.bindMemory(to: UInt32.self)
            for i in 0..<wordCount {
                let word = words[i].bigEndian
                let messageType = (word >> 28) & 0xF
                guard messageType == 0x2 else { continue } // MIDI 1.0 channel voice

                let status   = UInt8((word >> 16) & 0xFF)
                let note     = UInt8((word >> 8) & 0x7F)
                let velocity = UInt8(word & 0x7F)
                let channel  = Int(status & 0x0F)
                let type     = Int(status & 0xF0)

                sendMidiEvent(
                    type: type,
                    channel: channel,
                    note: Int(note),
                    velocity: Int(velocity),
                    timestampMicros: timestampMicros
                )
            }
        }
    }

    private func sendMidiEvent(
        type: Int, channel: Int, note: Int,
        velocity: Int, timestampMicros: Int64
    ) {
        let eventMap: [String: Any] = [
            "type":             type,
            "channel":          channel,
            "note":             note,
            "velocity":         velocity,
            "timestampMicros":  timestampMicros,
        ]

        // Must dispatch to main thread for Flutter event sink
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(eventMap)
        }
    }

    // MARK: - MIDI Notifications (Device Connect/Disconnect)
    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        let msg = notification.pointee
        switch msg.messageID {
        case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved:
            midiQueue.async { [weak self] in
                self?.connectAllSources()
                self?.broadcastDeviceList()
            }
        default:
            break
        }
    }

    // MARK: - Device Management
    private func connectAllSources() {
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let src = MIDIGetSource(i)
            MIDIPortConnectSource(inputPort, src, nil)
            registerDevice(from: src)
        }
    }

    private func registerDevice(from endpoint: MIDIEndpointRef) {
        var nameStr: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &nameStr)
        let name = (nameStr?.takeRetainedValue() as String?) ?? "Unknown Device"

        var manufacturer: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyManufacturer, &manufacturer)
        let mfr = (manufacturer?.takeRetainedValue() as String?) ?? ""

        var uniqueId: Int32 = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueId)

        let deviceId = "ios_\(uniqueId)"
        let brand = detectBrand(name: name, manufacturer: mfr)

        knownDevices[deviceId] = MidiDeviceInfo(
            id: deviceId,
            name: name,
            manufacturer: mfr,
            transport: "usb",
            brand: brand.rawValue,
            isConnected: true
        )
    }

    private func detectBrand(name: String, manufacturer: String) -> DrumBrandId {
        let combined = (name + " " + manufacturer).lowercased()
        if combined.contains("roland") || combined.contains("td-") { return .roland }
        if combined.contains("alesis") { return .alesis }
        if combined.contains("yamaha") || combined.contains("dtx") { return .yamaha }
        return .generic
    }

    private func getConnectedDevices(result: @escaping FlutterResult) {
        let devices = knownDevices.values.map { $0.toMap() }
        result(devices)
    }

    private func connectDevice(deviceId: String, result: @escaping FlutterResult) {
        connectedDeviceIds.insert(deviceId)
        result(nil)
    }

    private func disconnectDevice(deviceId: String, result: @escaping FlutterResult) {
        connectedDeviceIds.remove(deviceId)
        result(nil)
    }

    private func broadcastDeviceList() {
        let devices = knownDevices.values.map { $0.toMap() }
        DispatchQueue.main.async { [weak self] in
            self?.deviceSink?(devices)
        }
    }

    // MARK: - Bluetooth Scan
    private func startBluetoothScan(result: @escaping FlutterResult) {
        centralManager?.scanForPeripherals(
            withServices: [CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")], // BLE MIDI
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        result(nil)
    }

    private func stopBluetoothScan(result: @escaping FlutterResult) {
        centralManager?.stopScan()
        result(nil)
    }

    // MARK: - Latency Measurement
    private func measureLatency(result: @escaping FlutterResult) {
        // Measure round-trip using AudioGetCurrentHostTime
        let start = AudioGetCurrentHostTime()
        midiQueue.async {
            let end = AudioGetCurrentHostTime()
            let nanos = AudioConvertHostTimeToNanos(end - start)
            let micros = Int(nanos / 1000)
            DispatchQueue.main.async { result(micros) }
        }
    }
}

// MARK: - CBCentralManagerDelegate (BLE MIDI)
extension MidiEnginePlugin: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {}

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard !peripherals.contains(where: { $0.identifier == peripheral.identifier }) else { return }
        peripherals.append(peripheral)

        let deviceId = "ble_\(peripheral.identifier.uuidString)"
        knownDevices[deviceId] = MidiDeviceInfo(
            id: deviceId,
            name: peripheral.name ?? "BLE MIDI Device",
            manufacturer: "",
            transport: "bluetooth",
            brand: detectBrand(name: peripheral.name ?? "", manufacturer: "").rawValue,
            isConnected: false
        )
        broadcastDeviceList()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        let deviceId = "ble_\(peripheral.identifier.uuidString)"
        knownDevices[deviceId]?.isConnected = true
        broadcastDeviceList()
    }
}

// MARK: - Helper Types
private enum DrumBrandId: String {
    case roland, alesis, yamaha, generic
}

private struct MidiDeviceInfo {
    var id: String
    var name: String
    var manufacturer: String
    var transport: String
    var brand: String
    var isConnected: Bool

    func toMap() -> [String: Any] {
        return [
            "id": id,
            "name": name,
            "manufacturer": manufacturer,
            "transport": transport,
            "brand": brand,
            "isConnected": isConnected,
        ]
    }
}

// MARK: - Stream Handler Helper
private class BlockStreamHandler: NSObject, FlutterStreamHandler {
    let onListenBlock: (Any?, @escaping FlutterEventSink) -> FlutterError?
    let onCancelBlock: (Any?) -> FlutterError?

    init(
        onListen: @escaping (Any?, @escaping FlutterEventSink) -> Void,
        onCancel: @escaping (Any?) -> Void
    ) {
        onListenBlock = { args, sink in onListen(args, sink); return nil }
        onCancelBlock = { args in onCancel(args); return nil }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListenBlock(arguments, events)
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onCancelBlock(arguments)
    }
}
