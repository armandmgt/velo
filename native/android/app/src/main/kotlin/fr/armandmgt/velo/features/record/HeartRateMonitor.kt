package fr.armandmgt.velo.features.record

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.core.content.ContextCompat
import fr.armandmgt.velo.R
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.util.UUID

enum class HeartRateStatus {
    /** Not looking for a strap: none is remembered, or the recording screen is closed with no ride under way. */
    INACTIVE,
    CONNECTING,
    CONNECTED,

    /** Lost after connecting. An auto-connect brings it back once it is in range again, without the rider doing anything. */
    RECONNECTING,

    /** Bluetooth is off, or the app may not use it. */
    UNAVAILABLE,
}

data class HeartRateStrap(val address: String, val name: String)

data class HeartRateUiState(
    val strap: HeartRateStrap? = null,
    val status: HeartRateStatus = HeartRateStatus.INACTIVE,
    val reading: HeartRateReading? = null,
    /** Straps advertising the heart-rate service since pairing began, in the order found. */
    val discoveredStraps: List<HeartRateStrap> = emptyList(),
    /** Pairing can't scan, so it can say why nothing shows up. */
    val bluetoothUnavailable: Boolean = false,
)

/**
 * The rider's Bluetooth heart-rate strap: whether it is connected, and its latest
 * reading.
 *
 * Separate from [RecordingService], which only reads [latestReading] as it
 * persists a point, so a ride never waits on the strap. Bluetooth is touched only
 * once a strap is remembered or pairing starts, and the runtime permissions are
 * asked for at that moment, so riders without a strap never see them.
 *
 * Heart rate only (service 0x180D): Strava's app pairs nothing else, and riders
 * with power meters record on a bike computer. Mirrors the iOS `HeartRateMonitor`.
 */
// Every Bluetooth call sits behind hasConnectPermission / hasScanPermission.
@SuppressLint("MissingPermission")
class HeartRateMonitor private constructor(private val context: Context) {
    private val _state = MutableStateFlow(HeartRateUiState(strap = loadStrap()))
    val state: StateFlow<HeartRateUiState> = _state.asStateFlow()

    val latestReading: HeartRateReading? get() = _state.value.reading

    private val adapter: BluetoothAdapter?
        get() = context.getSystemService(BluetoothManager::class.java)?.adapter

    // Bluetooth callbacks arrive on binder threads; all state changes happen on main.
    private val main = Handler(Looper.getMainLooper())
    private var gatt: BluetoothGatt? = null
    private var active = false
    private var pairing = false
    private var hasConnected = false
    private var receiverRegistered = false

    // region Session

    /**
     * The recording screen is up, or a ride is under way: reach the remembered
     * strap and keep reaching for it until [deactivate].
     */
    fun activate() {
        if (active || _state.value.strap == null) return
        active = true
        hasConnected = false
        registerBluetoothStateReceiver()
        connect(autoConnect = false)
    }

    fun deactivate() {
        if (!active) return
        active = false
        unregisterBluetoothStateReceiver()
        closeGatt()
        _state.update { it.copy(status = HeartRateStatus.INACTIVE, reading = null) }
    }

    // endregion

    // region Pairing

    fun startPairing() {
        pairing = true
        val scanner = adapter?.takeIf { it.isEnabled }?.bluetoothLeScanner?.takeIf { hasScanPermission() }
        _state.update { it.copy(discoveredStraps = emptyList(), bluetoothUnavailable = scanner == null) }
        scanner?.startScan(
            listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE_UUID)).build()),
            ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),
            scanCallback,
        )
    }

    fun stopPairing() {
        if (!pairing) return
        pairing = false
        if (hasScanPermission()) adapter?.bluetoothLeScanner?.stopScan(scanCallback)
    }

    /** Remember [strap] in place of any previous one and connect to it. */
    fun pair(strap: HeartRateStrap) {
        stopPairing()
        deactivate()
        saveStrap(strap)
        _state.update { it.copy(strap = strap) }
        activate()
    }

    fun forget() {
        deactivate()
        saveStrap(null)
        _state.update { it.copy(strap = null) }
    }

    // endregion

    // region Connection

    private fun connect(autoConnect: Boolean) {
        val strap = _state.value.strap ?: return
        val adapter = adapter
        if (adapter == null || !adapter.isEnabled || !hasConnectPermission()) {
            _state.update { it.copy(status = HeartRateStatus.UNAVAILABLE, reading = null) }
            return
        }
        val device = runCatching { adapter.getRemoteDevice(strap.address) }.getOrNull() ?: return
        _state.update {
            it.copy(status = if (hasConnected) HeartRateStatus.RECONNECTING else HeartRateStatus.CONNECTING)
        }
        gatt = device.connectGatt(context, autoConnect, gattCallback, BluetoothDevice.TRANSPORT_LE)
    }

    private fun connectionLost(lost: BluetoothGatt) {
        lost.close()
        gatt = null
        _state.update { it.copy(reading = null) }
        // Auto-connect waits for the strap to come back in range, however long that takes.
        if (active) connect(autoConnect = true)
    }

    private fun closeGatt() {
        gatt?.let {
            it.disconnect()
            it.close()
        }
        gatt = null
    }

    private fun subscribe(gatt: BluetoothGatt) {
        val characteristic = gatt.getService(SERVICE_UUID)?.getCharacteristic(MEASUREMENT_UUID) ?: return
        gatt.setCharacteristicNotification(characteristic, true)
        val descriptor = characteristic.getDescriptor(CLIENT_CONFIG_UUID) ?: return
        val enable = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeDescriptor(descriptor, enable)
        } else {
            @Suppress("DEPRECATION")
            descriptor.value = enable
            @Suppress("DEPRECATION")
            gatt.writeDescriptor(descriptor)
        }
    }

    private fun onMeasurement(source: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
        if (characteristic.uuid != MEASUREMENT_UUID) return
        val measurement = HeartRateMeasurement.parse(value) ?: return
        val reading = if (measurement.isUsable) HeartRateReading(measurement.bpm, System.currentTimeMillis()) else null
        main.post {
            if (source == gatt) _state.update { it.copy(reading = reading) }
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(source: BluetoothGatt, status: Int, newState: Int) {
            main.post {
                if (source != gatt) return@post
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        hasConnected = true
                        _state.update { it.copy(status = HeartRateStatus.CONNECTED) }
                        source.discoverServices()
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> connectionLost(source)
                }
            }
        }

        override fun onServicesDiscovered(source: BluetoothGatt, status: Int) {
            main.post { if (source == gatt) subscribe(source) }
        }

        override fun onCharacteristicChanged(
            source: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) = onMeasurement(source, characteristic, value)

        // Before API 33 only this variant is called.
        @Deprecated("Replaced by the ByteArray overload on API 33")
        override fun onCharacteristicChanged(source: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
            @Suppress("DEPRECATION")
            onMeasurement(source, characteristic, characteristic.value ?: return)
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val address = result.device.address
            val name = result.scanRecord?.deviceName
                ?: runCatching { result.device.name }.getOrNull()
                ?: context.getString(R.string.heart_rate_strap_default_name)
            main.post {
                if (!pairing || _state.value.discoveredStraps.any { it.address == address }) return@post
                _state.update { it.copy(discoveredStraps = it.discoveredStraps + HeartRateStrap(address, name)) }
            }
        }
    }

    /** Connections die with the radio; reconnect when it comes back. */
    private val bluetoothStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(receiverContext: Context, intent: Intent) {
            when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)) {
                BluetoothAdapter.STATE_ON -> if (active && gatt == null) connect(autoConnect = true)
                BluetoothAdapter.STATE_OFF -> {
                    closeGatt()
                    if (active) _state.update { it.copy(status = HeartRateStatus.UNAVAILABLE, reading = null) }
                }
            }
        }
    }

    private fun registerBluetoothStateReceiver() {
        if (receiverRegistered) return
        ContextCompat.registerReceiver(
            context,
            bluetoothStateReceiver,
            IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        receiverRegistered = true
    }

    private fun unregisterBluetoothStateReceiver() {
        if (!receiverRegistered) return
        context.unregisterReceiver(bluetoothStateReceiver)
        receiverRegistered = false
    }

    // endregion

    // region Permissions & storage

    private fun hasConnectPermission() =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || granted(Manifest.permission.BLUETOOTH_CONNECT)

    private fun hasScanPermission() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            granted(Manifest.permission.BLUETOOTH_SCAN)
        } else {
            granted(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun granted(permission: String) =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    private fun loadStrap(): HeartRateStrap? {
        val prefs = prefs()
        val address = prefs.getString(STRAP_ADDRESS_KEY, null) ?: return null
        val name = prefs.getString(STRAP_NAME_KEY, null) ?: context.getString(R.string.heart_rate_strap_default_name)
        return HeartRateStrap(address, name)
    }

    private fun saveStrap(strap: HeartRateStrap?) {
        prefs().edit()
            .putString(STRAP_ADDRESS_KEY, strap?.address)
            .putString(STRAP_NAME_KEY, strap?.name)
            .apply()
    }

    private fun prefs() = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // endregion

    companion object {
        val SERVICE_UUID: UUID = UUID.fromString("0000180d-0000-1000-8000-00805f9b34fb")
        val MEASUREMENT_UUID: UUID = UUID.fromString("00002a37-0000-1000-8000-00805f9b34fb")
        private val CLIENT_CONFIG_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        private const val PREFS = "recording_prefs"
        private const val STRAP_ADDRESS_KEY = "recording.heartRateStrapAddress"
        private const val STRAP_NAME_KEY = "recording.heartRateStrapName"

        @Volatile
        private var instance: HeartRateMonitor? = null

        fun get(context: Context): HeartRateMonitor =
            instance ?: synchronized(this) {
                instance ?: HeartRateMonitor(context.applicationContext).also { instance = it }
            }

        /**
         * What pairing must ask for first. Runtime Bluetooth permissions exist from
         * API 31; on API 30 the manifest grants Bluetooth and scanning rides on the
         * fine location the recording already holds.
         */
        val pairingPermissions: Array<String> =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
            } else {
                emptyArray()
            }
    }
}
