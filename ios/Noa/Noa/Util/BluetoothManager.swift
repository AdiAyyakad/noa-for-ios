//
//  BluetoothManager.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 7/20/23.
//
//  After initialization, callers must ensure that methods are called on the same queue that was
//  provided. BluetoothManager will not dispatch its own calls. Likewise, all published properties
//  will adhere to Combine's thread safety rules but objects they pass along should not be accessed
//  outside of the Bluetooth queue.
//
//  Resources
//  ---------
//  - "The Ultimate Guide to Apple's Core Bluetooth"
//    https://punchthrough.com/core-bluetooth-basics/
//

import AVFoundation
import CoreBluetooth
import OSLog

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    /// Nearby peripherals matching our peripheral name sorted in desceding order of RSSI. This is updated only while not connected.
    @Published private(set) var discoveredDevices: [(deviceID: UUID, rssi: Float)] = []

    @Published private(set) var isConnected = false

    @Published private(set) var connectedPeripheralID: UUID?

    /// Data received on a subscribed characteristic
    @Published private(set) var dataReceived: (characteristic: CBUUID, value: Data)?

    /// Sets the device ID to automatically connect to. This is kept separate from
    /// connectedDeviceID to avoid an infinite publishing loop from here -> Settings -> here when
    /// auto-connecting by proximity.
    @Published var selectedDeviceID: UUID? {
        didSet {
            if let connectedPeripheral = _connectedPeripheral {
                // We have a connected peripheral. See if desired device ID changed and if so,
                // disconnect.
                if selectedDeviceID != connectedPeripheral.identifier {
                    _manager.cancelPeripheralConnection(connectedPeripheral)    // should cause disconnect event
                }
            }
        }
    }

    var maximumDataLength: Int? {
        _connectedPeripheral?.maximumWriteValueLength(for: .withoutResponse)
    }

    /// Enables/disables the Bluetooth connectivity. Disconnects from connected peripheral (but
    /// does not unpair it) and stops scanning when set to false. When set to true, will try to
    /// immediately begin scanning.
    var enabled = false {
        didSet {
            Logger.bluetoothManager.log("[BluetoothManager] \(self.enabled ? "Enabled" : "Disabled")")
            if enabled && _manager.state == .poweredOn {
                startScanIfEnabled()
            } else {
                // Do not attempt to scan anymore
                if _manager.state == .poweredOn {
                    _manager.stopScan()
                }

                // Disconnect
                if let connectedPeripheral = _connectedPeripheral {
                    // This will cause a disconnect that in turn will cause the peripheral to be
                    // forgotten
                    _manager.cancelPeripheralConnection(connectedPeripheral)
                }
            }
        }
    }

    var connectedPeripheral: CBPeripheral? {
        _connectedPeripheral
    }

    /// RSSI threshold used for proximity-based auto-pairing. The relative signal strength must be greater than or equal to this value.
    static let rssiThreshold: Float = -70

    private let _peripheralName: String
    private let _serviceUUIDs: [CBUUID]
    private let _receiveCharacteristicUUIDs: [CBUUID]   // characteristics on which we receive data
    private let _transmitCharacteristicUUIDs: [CBUUID]  // characteristics on which we transmit data
    private let _characteristicNameByID: [CBUUID: String]

    private let _queue: DispatchQueue

    private lazy var _manager = CBCentralManager(delegate: self, queue: _queue)
    private var _started = false

    private let _allowAutoConnectByProximity: Bool

    private var _discoveredPeripherals: [(peripheral: CBPeripheral, rssi: Float, timeout: TimeInterval)] = []
    private var _discoveryTimer: Timer?

    private var _connectedPeripheral: CBPeripheral? {
        didSet {
            isConnected = _connectedPeripheral != nil

            // If we auto-connected and selectedDeviceID was nil, set the selected ID
            if selectedDeviceID == nil, let _connectedPeripheral {
                selectedDeviceID = _connectedPeripheral.identifier
            }
        }
    }

    private var _characteristicByID: [CBUUID: CBCharacteristic] = [:]

    private var _didSendConnectedEvent = false

    init(
        autoConnectByProximity: Bool,
        peripheralName: String,
        services: [CBUUID: String],
        receiveCharacteristics: [CBUUID: String],
        transmitCharacteristics: [CBUUID: String],
        queue: DispatchQueue
    ) {
        _peripheralName = peripheralName
        _serviceUUIDs = Array(services.keys)
        _receiveCharacteristicUUIDs = Array(receiveCharacteristics.keys)
        _transmitCharacteristicUUIDs = Array(transmitCharacteristics.keys)
        _allowAutoConnectByProximity = autoConnectByProximity
        _characteristicNameByID = receiveCharacteristics.merging(transmitCharacteristics, uniquingKeysWith: { $1 })
        _queue = queue
        super.init()
    }

    /// Start the Bluetooth manager. Must be called once and only once after init(). As with other
    /// methods and properties, must be called on the Bluetooth queue.
    public func start() {
        precondition(!_started)

        // Ensure manager is instantiated; all logic will then be driven by centralManagerDidUpdateState()
        _ = _manager
        _started = true
    }

    public func send(data: Data, on id: CBUUID, response: Bool = false) {
        guard let characteristic = _characteristicByID[id] else {
            Logger.bluetoothManager.log("[BluetoothManager] Failed to send because characteristic is not available: UUID=\(id)")
            return
        }

        guard let connectedPeripheral = _connectedPeripheral else {
            Logger.bluetoothManager.log("[BluetoothManager] Failed to send because no peripheral is connected")
            return
        }

        writeData(data, on: characteristic, peripheral: connectedPeripheral, response: response)
        Logger.bluetoothManager.log("[BluetoothManager] Sent \(data.count) bytes on \(self.toString(characteristic))")
    }

    public func send(text str: String, on id: CBUUID) {
        guard let data = str.data(using: .utf8) else { return }
        send(data: data, on: id)
    }

    private func startScanIfEnabled() {
        guard enabled else { return }
        if _manager.isScanning {
            Logger.bluetoothManager.log("[BluetoothManager] Internal error: Already scanning")
        }

        _manager.scanForPeripherals(withServices: _serviceUUIDs, options: [ CBCentralManagerScanOptionAllowDuplicatesKey: true ])
        Logger.bluetoothManager.log("[BluetoothManager] Scan initiated")

        // Create a timer to update discoved peripheral list
        _discoveryTimer?.invalidate()
        _discoveryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] (timer: Timer) in
            self?.updateDiscoveredPeripherals()
        }
    }

    private func connectPeripheral(_ peripheral: CBPeripheral) {
        precondition(_connectedPeripheral == nil)
        _manager.connect(peripheral)
        _connectedPeripheral = peripheral
        forgetCharacteristics()

        // No need to continue scanning
        _manager.stopScan()

        // We do not send the connection event just yet here. We wait for all characteristics to be
        // obtained before doing so
        _didSendConnectedEvent = false
    }

    private func forgetPeripheral() {
        _connectedPeripheral?.delegate = nil
        _connectedPeripheral = nil
        forgetCharacteristics()

        connectedPeripheralID = nil
        _didSendConnectedEvent = false
    }

    private func forgetCharacteristics() {
        _characteristicByID = [:]
    }

    private func updateDiscoveredPeripherals(with peripheral: CBPeripheral? = nil, rssi: Float = -.infinity) {
        let numPeripheralsBefore = _discoveredPeripherals.count
        var didChange = false

        // Delete anything that has timed out
        let now = Date.timeIntervalSinceReferenceDate
        _discoveredPeripherals.removeAll { $0.timeout >= now }
        if numPeripheralsBefore != _discoveredPeripherals.count {
            didChange = true
        }

        // If we are adding a peripheral, remove dupes first
        if let peripheral {
            _discoveredPeripherals.removeAll { $0.peripheral.isEqual(peripheral) }
            _discoveredPeripherals.append((peripheral: peripheral, rssi: rssi, timeout: now + 10))  // timeout after 10 seconds
            didChange = true
        }

        // Update device list and log it
        // Publish sorted in descending order by RSSI
        let devices = _discoveredPeripherals
            .map { (deviceID: $0.peripheral.identifier, rssi: $0.rssi) }
            .sorted { $0 .rssi < $1.rssi }
        discoveredDevices = devices
        if didChange {
            let peripheralsDescription = _discoveredPeripherals
                .map { "\tname=\($0.peripheral.name ?? "<no name>") id=\($0.peripheral.identifier) rssi=\($0.rssi)" }
                .joined(separator: "\n")
            Logger.bluetoothManager.log("[BluetoothManager] Discovered peripherals:\n\(peripheralsDescription)")
        }
    }

    private func printServices() {
        guard let _connectedPeripheral else { return }

        guard let services = _connectedPeripheral.services else {
            Logger.bluetoothManager.log("[BluetoothManager] No services for peripheral UUID=\(_connectedPeripheral.identifier)")
            return
        }
        let servicesDescription = services
            .map { "\tService: UUID=\($0.uuid), description=\($0.description)" }
            .joined(separator: "\n")
        Logger.bluetoothManager.log("[BluetoothManager] Listing services for peripheral: name=\(_connectedPeripheral.name ?? ""), UUID=\(_connectedPeripheral.identifier)\n\(servicesDescription)")
    }

    private func discoverCharacteristics() {
        guard let _connectedPeripheral, let services = _connectedPeripheral.services else { return }
        forgetCharacteristics()
        services.forEach(curry(_connectedPeripheral.discoverCharacteristics)(_receiveCharacteristicUUIDs + _transmitCharacteristicUUIDs))
    }

    private func printCharacteristics(of service: CBService) {
        guard let characteristics = service.characteristics else {
            Logger.bluetoothManager.log("[BluetoothManager] No characteristics for service UUID=\(service.uuid)")
            return
        }
        let characteristicsDescription = characteristics
            .map { "\tCharacteristic: description=\($0.description), UUID=\($0.uuid)" }
            .joined(separator: "\n")
        Logger.bluetoothManager.log("[BluetoothManager] Listing characteristics for service: description=\(service.description), UUID=\(service.uuid)\n\(characteristicsDescription)")
    }

    private func saveCharacteristics(of service: CBService) {
        guard let peripheral = _connectedPeripheral else { return }

        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                let id = characteristic.uuid

                if _receiveCharacteristicUUIDs.contains(id) {
                    _characteristicByID[id] = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    Logger.bluetoothManager.log("[BluetoothManager] Obtained characteristic: \(self.toString(characteristic))")
                } else if _transmitCharacteristicUUIDs.contains(id) {
                    _characteristicByID[id] = characteristic
                    Logger.bluetoothManager.log("[BluetoothManager] Obtained characteristic: \(self.toString(characteristic))")
                } else {
                    Logger.bluetoothManager.log("[BluetoothManager] Tossed characteristic: \(self.toString(characteristic))")
                }
            }
        }

        // Send connection event when all characteristics obtained
        guard
            _characteristicByID.count == Set(_receiveCharacteristicUUIDs + _transmitCharacteristicUUIDs).count, // create set because transmit and receive characteristics may be shared
            !_didSendConnectedEvent
        else { return }
        self.connectedPeripheralID = peripheral.identifier
        _didSendConnectedEvent = true
    }

    // MARK: Helpers

    private func writeData(_ data: Data, on characteristic: CBCharacteristic, peripheral: CBPeripheral, response: Bool = false) {
        let chunkSize = peripheral.maximumWriteValueLength(for: .withoutResponse)
        var idx = 0
        while idx < data.count {
            let endIdx = min(idx + chunkSize, data.count)
            peripheral.writeValue(data.subdata(in: idx..<endIdx), for: characteristic, type: response ? .withResponse : .withoutResponse)
            idx = endIdx
        }
    }

    private func toString(_ characteristic: CBCharacteristic) -> String {
        _characteristicNameByID[characteristic.uuid] ?? "UUID=\(characteristic.uuid)"
    }

    // MARK: CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScanIfEnabled()
        case .poweredOff:
            // Alert user to turn on Bluetooth
            Logger.bluetoothManager.log("[BluetoothManager] Bluetooth is powered off")
        case .unauthorized:
            // Alert user to enable Bluetooth permission in app Settings
            Logger.bluetoothManager.log("[BluetoothManager] Authorization missing!")
        case .unsupported:
            // Alert user their device does not support Bluetooth and app will not work as expected
            Logger.bluetoothManager.log("[BluetoothManager] Bluetooth not supported on this device!")
        case .resetting:
            Logger.bluetoothManager.log("[BluetoothManager] Bluetooth is resetting")
        case .unknown: fallthrough
        default:
            break
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? ""
        Logger.bluetoothManager.log("[BluetoothManager] Discovered peripheral: name=\(name), UUID=\(peripheral.identifier), RSSI=\(RSSI)")

        guard name == _peripheralName else {
            updateDiscoveredPeripherals()
            return
        }

        updateDiscoveredPeripherals(with: peripheral, rssi: RSSI.floatValue)

        guard _connectedPeripheral == nil else { return } // Already connected

        // If this is the peripheral we are "paired" to and looking for, connect
        var shouldConnect = peripheral.identifier == selectedDeviceID

        // Otherwise, auto-connect to first device whose RSSI meets the threshold and auto-connect enabled
        if _allowAutoConnectByProximity && RSSI.floatValue >= Self.rssiThreshold {
            shouldConnect = true
        }

        // Connect
        guard shouldConnect else { return }
        Logger.bluetoothManager.log("[BluetoothManager] Connecting to peripheral: name=\(name), UUID=\(peripheral.identifier)")
        connectPeripheral(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral == _connectedPeripheral else {
            Logger.bluetoothManager.log("[BluetoothManager] Internal error: Connected to an unexpected peripheral")
            return
        }

        Logger.bluetoothManager.log("[BluetoothManager] Connected to peripheral: name=\(peripheral.name ?? ""), UUID=\(peripheral.identifier)")
        peripheral.delegate = self
        peripheral.discoverServices(_serviceUUIDs)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral == _connectedPeripheral else {
            Logger.bluetoothManager.log("[BluetoothManager] Internal error: Failed to connect to an unexpected peripheral")
            return
        }

        Logger.bluetoothManager.log("[BluetoothManager] Error: Failed to connect to peripheral: \(error?.localizedDescription ?? "unspecified error")")
        forgetPeripheral()
        updateDiscoveredPeripherals()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == _connectedPeripheral else {
            Logger.bluetoothManager.log("[BluetoothManager] Internal error: Disconnected from an unexpected peripheral")
            return
        }

        Logger.bluetoothManager.log("[BluetoothManager] Error: Disconnected from peripheral: \(error?.localizedDescription ?? "unspecified error")")
        forgetPeripheral()
        startScanIfEnabled()
        updateDiscoveredPeripherals()
    }

    // MARK: CBPeripheralDelegate

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral != _connectedPeripheral else {
            Logger.bluetoothManager.log("[BluetoothManager] Internal error: peripheral(_:, didDiscoverServices:) called unexpectedly")
            return
        }

        guard error == nil else {
            Logger.bluetoothManager.log("[BluetoothManager] Error discovering services on peripheral UUID=\(peripheral.identifier): \(error!.localizedDescription)")
            return
        }

        printServices()
        discoverCharacteristics()
    }

    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard peripheral == _connectedPeripheral else {
            Logger.bluetoothManager.log("[BluetoothManager] Internal error: peripheral(_:, didModifyServices:) called unexpectedly")
            return
        }

        Logger.bluetoothManager.log("[BluetoothManager] didModifyServices")
        for service in invalidatedServices {
            Logger.bluetoothManager.log("  descr=\(service.description) uuid=\(service.uuid)")
        }

        // If any service is invalidated, forget them all and then rediscover. This is probably over-agressive.
        if invalidatedServices.contains(where: { _serviceUUIDs.contains($0.uuid) }) {
            forgetCharacteristics()
        }

        peripheral.discoverServices(_serviceUUIDs)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral == _connectedPeripheral else {
            Logger.bluetoothManager.log("[BluetoothManager] Internal error: peripheral(_:, didDiscoverCharacteristicsFor:, error:) called unexpectedly")
            return
        }

        printCharacteristics(of: service)
        saveCharacteristics(of: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            Logger.bluetoothManager.log("[BluetoothManager] Error: Value update for \(self.toString(characteristic)) failed: \(error!.localizedDescription)")
            return
        }

        let id = characteristic.uuid
        guard _receiveCharacteristicUUIDs.contains(id), let value = characteristic.value else { return }
        // We have received something
        dataReceived = (characteristic: id, value: value)
    }
}

extension Logger {
    static let bluetoothManager = Logger(subsystem: "Util", category: "BluetoothManager")
}
