import CoreBluetooth
import Foundation

extension Notification.Name {
    /// Posted when the strap's connection changes, a reading arrives, or pairing
    /// finds a strap.
    static let heartRateMonitorDidChange = Notification.Name("HeartRateMonitorDidChange")
}

/// The rider's Bluetooth heart-rate strap: whether it is connected, and its
/// latest reading.
///
/// Separate from `RecordingController`, which only reads `latestReading` as it
/// persists a point, so a ride never waits on the strap. Bluetooth is touched
/// only once a strap is remembered or pairing starts: until then no central
/// manager exists, so riders without a strap never see the Bluetooth prompt.
///
/// Heart rate only (service 0x180D): Strava's app pairs nothing else, and riders
/// with power meters record on a bike computer.
final class HeartRateMonitor: NSObject {
    static let shared = HeartRateMonitor()

    static let serviceUUID = CBUUID(string: "180D")
    static let measurementUUID = CBUUID(string: "2A37")

    struct Strap: Equatable {
        let id: UUID
        let name: String
    }

    enum Status: Equatable {
        /// Not looking for a strap: none is remembered, or the recording screen
        /// is closed with no ride under way.
        case inactive
        case connecting
        case connected
        /// Lost after connecting. A pending connection brings it back once it is
        /// in range again, without the rider doing anything.
        case reconnecting
        /// Bluetooth is off, or the app may not use it.
        case unavailable
    }

    private(set) var status: Status = .inactive {
        didSet { if status != oldValue { notifyChange() } }
    }

    private(set) var latestReading: HeartRateReading?

    /// Straps advertising the heart-rate service since pairing began, in the order found.
    private(set) var discoveredStraps: [Strap] = []

    private(set) var rememberedStrap: Strap? {
        get {
            guard let raw = defaults.string(forKey: Self.strapIDKey), let id = UUID(uuidString: raw) else { return nil }
            return Strap(id: id, name: defaults.string(forKey: Self.strapNameKey) ?? Self.fallbackName)
        }
        set {
            defaults.set(newValue?.id.uuidString, forKey: Self.strapIDKey)
            defaults.set(newValue?.name, forKey: Self.strapNameKey)
        }
    }

    private static let strapIDKey = "recording.heartRateStrapID"
    private static let strapNameKey = "recording.heartRateStrapName"
    private static let fallbackName = "Ceinture cardio"

    private let defaults: UserDefaults
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var isActive = false
    private var isPairing = false
    private var hasConnected = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    // MARK: - Session

    /// The recording screen is up, or a ride is under way: reach the remembered
    /// strap and keep reaching for it until `deactivate()`.
    func activate() {
        guard !isActive, rememberedStrap != nil else { return }
        isActive = true
        hasConnected = false
        status = .connecting
        connectIfPossible()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        disconnect()
        status = .inactive
    }

    // MARK: - Pairing

    func startPairing() {
        isPairing = true
        discoveredStraps = []
        let central = ensureCentral()
        if central.state == .poweredOn { scan() }
        notifyChange()
    }

    func stopPairing() {
        guard isPairing else { return }
        isPairing = false
        central?.stopScan()
        // The scan may also have been looking for the remembered strap.
        if isActive, peripheral == nil { connectIfPossible() }
    }

    /// Remember `strap` in place of any previous one and connect to it.
    func pair(with strap: Strap) {
        stopPairing()
        isActive = false
        disconnect()
        rememberedStrap = strap
        activate()
    }

    func forget() {
        deactivate()
        rememberedStrap = nil
        notifyChange()
    }

    /// Whether Bluetooth can be used right now, so pairing can say why nothing shows up.
    var isBluetoothUnavailable: Bool {
        guard let state = central?.state else { return false }
        return state != .poweredOn && state != .unknown && state != .resetting
    }

    // MARK: - Connection

    private func ensureCentral() -> CBCentralManager {
        if let central { return central }
        let created = CBCentralManager(delegate: self, queue: nil)
        central = created
        return created
    }

    private func scan() {
        central?.scanForPeripherals(withServices: [Self.serviceUUID])
    }

    private func connectIfPossible() {
        guard isActive, let strap = rememberedStrap else { return }
        let central = ensureCentral()
        guard central.state == .poweredOn else {
            if isBluetoothUnavailable { status = .unavailable }
            return
        }
        let known = peripheral
            ?? central.retrievePeripherals(withIdentifiers: [strap.id]).first
            ?? discoveredPeripherals[strap.id]
        if let known {
            peripheral = known
            known.delegate = self
            // Connection requests never time out, so this one waits for the strap
            // to come into range — in the background too, thanks to the
            // `bluetooth-central` mode.
            central.connect(known)
        } else {
            // The system no longer knows it (Bluetooth was reset): find it again
            // by its advertisement.
            scan()
        }
    }

    private func disconnect() {
        latestReading = nil
        if !isPairing { central?.stopScan() }
        guard let current = peripheral else { return }
        peripheral = nil
        central?.cancelPeripheralConnection(current)
    }

    private func connectionLost(_ lost: CBPeripheral) {
        latestReading = nil
        guard isActive, lost === peripheral else { return }
        status = hasConnected ? .reconnecting : .connecting
        central?.connect(lost)
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .heartRateMonitorDidChange, object: self)
    }
}

// MARK: - CBCentralManagerDelegate

extension HeartRateMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if isPairing { scan() }
            if isActive {
                if status == .unavailable { status = hasConnected ? .reconnecting : .connecting }
                connectIfPossible()
            }
        } else if isBluetoothUnavailable {
            // Connections die with the radio; the peripheral is reconnected on power-up.
            latestReading = nil
            if isActive { status = .unavailable }
        }
        notifyChange()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        discoveredPeripherals[peripheral.identifier] = peripheral

        if isActive, self.peripheral == nil, peripheral.identifier == rememberedStrap?.id {
            if !isPairing { central.stopScan() }
            connectIfPossible()
        }

        guard isPairing, !discoveredStraps.contains(where: { $0.id == peripheral.identifier }) else { return }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? Self.fallbackName
        discoveredStraps.append(Strap(id: peripheral.identifier, name: name))
        notifyChange()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        hasConnected = true
        status = .connected
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionLost(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionLost(peripheral)
    }
}

// MARK: - CBPeripheralDelegate

extension HeartRateMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.measurementUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.measurementUUID {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral,
              characteristic.uuid == Self.measurementUUID,
              let data = characteristic.value,
              let measurement = HeartRateMeasurement(data: data) else { return }
        latestReading = measurement.isUsable ? HeartRateReading(bpm: measurement.bpm, receivedAt: Date()) : nil
        notifyChange()
    }
}
