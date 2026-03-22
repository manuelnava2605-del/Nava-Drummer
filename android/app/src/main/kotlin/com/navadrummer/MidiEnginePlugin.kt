package com.navadrummer

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.media.midi.MidiDevice
import android.media.midi.MidiDeviceInfo
import android.media.midi.MidiManager
import android.media.midi.MidiOutputPort
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.ParcelUuid
import android.os.SystemClock
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

@RequiresApi(Build.VERSION_CODES.M)
class MidiEnginePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private var midiEventSink: EventChannel.EventSink? = null
    private var deviceListSink: EventChannel.EventSink? = null

    private var midiManager: MidiManager? = null
    private val openDevices = ConcurrentHashMap<String, MidiDevice>()
    private val openPorts = ConcurrentHashMap<String, MidiOutputPort>()
    private val deviceInfoCache = ConcurrentHashMap<String, NavaMidiDevice>()

    private val midiThread = HandlerThread("NavaDrummer-MIDI", android.os.Process.THREAD_PRIORITY_AUDIO)
    private lateinit var midiHandler: Handler

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var scanCallback: ScanCallback? = null
    private val isScanning = AtomicBoolean(false)
    private var latencyOffsetMicros: Long = 0L
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        private const val BLE_MIDI_SERVICE_UUID = "03B80E5A-EDE8-4B33-A751-6CE34EC4C700"
    }

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, "com.navadrummer/midi_engine")
        methodChannel.setMethodCallHandler(this)

        EventChannel(binding.binaryMessenger, "com.navadrummer/midi_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) { midiEventSink = sink }
                override fun onCancel(args: Any?) { midiEventSink = null }
            })

        EventChannel(binding.binaryMessenger, "com.navadrummer/midi_devices")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    deviceListSink = sink
                    broadcastDeviceList()
                }
                override fun onCancel(args: Any?) { deviceListSink = null }
            })

        midiThread.start()
        midiHandler = Handler(midiThread.looper)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        stopEngine()
        midiThread.quitSafely()
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
        when (call.method) {
            "startEngine"         -> startEngine(result)
            "stopEngine"          -> stopEngine(result)
            "getConnectedDevices" -> getConnectedDevices(result)
            "connectDevice"       -> connectDevice(call.argument<String>("deviceId")!!, result)
            "disconnectDevice"    -> disconnectDevice(call.argument<String>("deviceId")!!, result)
            "startBluetoothScan"  -> startBluetoothScan(result)
            "stopBluetoothScan"   -> stopBluetoothScan(result)
            "measureLatency"      -> measureLatency(result)
            "setLatencyOffset"    -> {
                latencyOffsetMicros = call.argument<Int>("offsetMicros")!!.toLong()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startEngine(result: MethodChannel.Result) {
        midiHandler.post {
            try {
                midiManager = context.getSystemService(Context.MIDI_SERVICE) as MidiManager
                midiManager?.registerDeviceCallback(deviceCallback, midiHandler)
                midiManager?.devices?.forEach { info -> registerDevice(info) }

                val btManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                bluetoothAdapter = btManager?.adapter

                mainHandler.post { result.success(null) }
            } catch (e: Exception) {
                mainHandler.post { result.error("MIDI_ERROR", e.message, null) }
            }
        }
    }

    private fun stopEngine(result: MethodChannel.Result? = null) {
        openPorts.values.forEach { runCatching { it.close() } }
        openDevices.values.forEach { runCatching { it.close() } }
        openPorts.clear()
        openDevices.clear()
        midiManager?.unregisterDeviceCallback(deviceCallback)
        result?.let { mainHandler.post { it.success(null) } }
    }

    private val deviceCallback = object : MidiManager.DeviceCallback() {
        override fun onDeviceAdded(device: MidiDeviceInfo) {
            midiHandler.post {
                registerDevice(device)
                broadcastDeviceList()
            }
        }
        override fun onDeviceRemoved(device: MidiDeviceInfo) {
            midiHandler.post {
                val id = deviceKey(device)
                runCatching { openPorts[id]?.close() }
                runCatching { openDevices[id]?.close() }
                openPorts.remove(id)
                openDevices.remove(id)
                deviceInfoCache.remove(id)
                broadcastDeviceList()
            }
        }
    }

    private fun registerDevice(info: MidiDeviceInfo) {
        val id   = deviceKey(info)
        val props: Bundle = info.properties
        val name         = props.getString(MidiDeviceInfo.PROPERTY_NAME) ?: "MIDI Device"
        val manufacturer = props.getString(MidiDeviceInfo.PROPERTY_MANUFACTURER) ?: ""
        val product      = props.getString(MidiDeviceInfo.PROPERTY_PRODUCT) ?: ""
        val transport    = if (info.type == MidiDeviceInfo.TYPE_BLUETOOTH) "bluetooth" else "usb"

        deviceInfoCache[id] = NavaMidiDevice(
            id = id, name = name, manufacturer = manufacturer,
            transport = transport, brand = detectBrand(name, manufacturer, product),
            isConnected = false
        )
    }

    private fun connectDevice(deviceId: String, result: MethodChannel.Result) {
        val info = midiManager?.devices?.find { deviceKey(it) == deviceId }
        if (info == null) {
            mainHandler.post { result.error("NOT_FOUND", "Device not found: $deviceId", null) }
            return
        }

        midiManager?.openDevice(info, { device ->
            if (device == null) {
                mainHandler.post { result.error("CONNECT_FAILED", "Could not open device", null) }
                return@openDevice
            }
            openDevices[deviceId] = device

            info.ports.forEach { portInfo ->
                if (portInfo.type == MidiDeviceInfo.PortInfo.TYPE_OUTPUT) {
                    device.openOutputPort(portInfo.portNumber)?.let { port ->
                        openPorts[deviceId] = port
                        port.connect(NavaMidiReceiver(deviceId))
                    }
                }
            }

            deviceInfoCache[deviceId]?.isConnected = true
            broadcastDeviceList()
            mainHandler.post { result.success(null) }
        }, midiHandler)
    }

    private fun disconnectDevice(deviceId: String, result: MethodChannel.Result) {
        runCatching { openPorts[deviceId]?.close() }
        runCatching { openDevices[deviceId]?.close() }
        openPorts.remove(deviceId)
        openDevices.remove(deviceId)
        deviceInfoCache[deviceId]?.isConnected = false
        broadcastDeviceList()
        mainHandler.post { result.success(null) }
    }

    private fun getConnectedDevices(result: MethodChannel.Result) {
        val devices = deviceInfoCache.values.map { it.toMap() }
        mainHandler.post { result.success(devices) }
    }

    inner class NavaMidiReceiver(private val deviceId: String) : android.media.midi.MidiReceiver() {
        override fun onSend(msg: ByteArray, offset: Int, count: Int, timestamp: Long) {
            val nowNanos     = System.nanoTime()
            val eventNanos   = if (timestamp == 0L) nowNanos else timestamp
            val tsMicros     = (eventNanos / 1000L) + latencyOffsetMicros

            var i = offset
            while (i < offset + count) {
                val status  = msg[i].toInt() and 0xFF
                val msgType = status and 0xF0
                val channel = status and 0x0F

                when (msgType) {
                    0x80, 0x90 -> {
                        if (i + 2 < offset + count) {
                            val note     = msg[i + 1].toInt() and 0x7F
                            val velocity = msg[i + 2].toInt() and 0x7F
                            sendEvent(msgType, channel, note, velocity, tsMicros)
                            i += 3
                        } else i++
                    }
                    0xB0 -> {
                        if (i + 2 < offset + count) {
                            sendEvent(0xB0, channel, msg[i+1].toInt() and 0x7F, msg[i+2].toInt() and 0x7F, tsMicros)
                            i += 3
                        } else i++
                    }
                    else -> i++
                }
            }
        }

        private fun sendEvent(type: Int, channel: Int, note: Int, velocity: Int, tsMicros: Long) {
            val map = hashMapOf<String, Any>(
                "type" to type, "channel" to channel, "note" to note,
                "velocity" to velocity, "timestampMicros" to tsMicros, "deviceId" to deviceId
            )
            mainHandler.post { midiEventSink?.success(map) }
        }
    }

    private fun startBluetoothScan(result: MethodChannel.Result) {
        if (bluetoothAdapter?.isEnabled != true) {
            mainHandler.post { result.error("BT_UNAVAILABLE", "Bluetooth not available", null) }
            return
        }
        val filter   = ScanFilter.Builder().setServiceUuid(ParcelUuid.fromString(BLE_MIDI_SERVICE_UUID)).build()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()

        scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, scanResult: ScanResult) {
                handleBleDevice(scanResult.device)
            }
        }
        bluetoothAdapter?.bluetoothLeScanner?.startScan(listOf(filter), settings, scanCallback!!)
        isScanning.set(true)
        mainHandler.post { result.success(null) }
    }

    private fun stopBluetoothScan(result: MethodChannel.Result) {
        scanCallback?.let { bluetoothAdapter?.bluetoothLeScanner?.stopScan(it) }
        scanCallback = null
        isScanning.set(false)
        mainHandler.post { result.success(null) }
    }

    private fun handleBleDevice(device: BluetoothDevice) {
        val id   = "ble_${device.address}"
        if (deviceInfoCache.containsKey(id)) return
        val name = device.name ?: "BLE MIDI Device"
        deviceInfoCache[id] = NavaMidiDevice(
            id = id, name = name, manufacturer = "",
            transport = "bluetooth", brand = detectBrand(name, "", ""), isConnected = false
        )
        broadcastDeviceList()
    }

    private fun measureLatency(result: MethodChannel.Result) {
        midiHandler.post {
            val start = SystemClock.elapsedRealtimeNanos()
            mainHandler.post {
                val end = SystemClock.elapsedRealtimeNanos()
                result.success(((end - start) / 1000).toInt())
            }
        }
    }

    private fun deviceKey(info: MidiDeviceInfo): String = "android_${info.id}"

    private fun detectBrand(name: String, manufacturer: String, product: String): String {
        val s = "$name $manufacturer $product".lowercase()
        return when {
            "roland" in s || "td-" in s -> "roland"
            "alesis" in s               -> "alesis"
            "yamaha" in s || "dtx" in s -> "yamaha"
            else                        -> "generic"
        }
    }

    private fun broadcastDeviceList() {
        val list = deviceInfoCache.values.map { it.toMap() }
        mainHandler.post { deviceListSink?.success(list) }
    }

    private data class NavaMidiDevice(
        val id: String, val name: String, val manufacturer: String,
        val transport: String, val brand: String, var isConnected: Boolean
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "id" to id, "name" to name, "manufacturer" to manufacturer,
            "transport" to transport, "brand" to brand, "isConnected" to isConnected
        )
    }
}
