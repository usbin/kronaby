import CoreBluetooth
import Combine

enum ConnectionState: String {
    case disconnected = "연결 끊김"
    case scanning = "스캔 중..."
    case connecting = "연결 중..."
    case handshaking = "핸드셰이크 중..."
    case connected = "연결됨"
    case bluetoothOff = "블루투스 꺼짐"
}

final class BLEManager: NSObject, ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var commandMap: [String: Int] = [:]
    @Published var lastButtonEvent: ButtonEvent?

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?

    private let protocol_ = KronabyProtocol()
    private var pendingScan = false

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    func startScan() {
        guard centralManager.state == .poweredOn else {
            // BLE not ready yet — queue scan for when it becomes ready
            pendingScan = true
            if centralManager.state == .poweredOff {
                connectionState = .bluetoothOff
            }
            return
        }
        pendingScan = false
        discoveredPeripherals = []
        connectionState = .scanning

        // Scan with nil services to find all BLE devices first,
        // then filter by name/advertisement data.
        // Some Kronaby models may not advertise F431 in the ad packet.
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // Auto-stop after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.connectionState == .scanning else { return }
            self.stopScan()
        }
    }

    func stopScan() {
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    func connect(to peripheral: CBPeripheral) {
        stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        centralManager.connect(peripheral, options: nil)

        // Timeout: if still connecting after 15 seconds, cancel
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.connectionState == .connecting else { return }
            self.disconnect()
        }
    }

    func disconnect() {
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    func sendCommand(name: String, value: Any) {
        guard let char = commandChar,
              let cmdId = commandMap[name] else { return }
        let data = protocol_.encode(commandId: cmdId, value: value)
        peripheral?.writeValue(data, for: char, type: .withResponse)
    }

    // MARK: - Connection Sequence

    private func performHandshake() {
        connectionState = .handshaking
        guard let char = commandChar else { return }

        for i in 0...2 {
            let data = protocol_.encode(commandId: 0, value: i)
            peripheral?.writeValue(data, for: char, type: .withResponse)
        }
    }

    private func completeSetup() {
        sendCommand(name: "onboarding_done", value: 1)

        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: now)

        // Kronaby day mapping: Tue=0, Wed=1, Thu=2, Fri=3, Sat=4, Sun=5, Mon=6
        let weekday = comps.weekday! // Sunday=1, Monday=2, ...
        let kronabyDay: Int
        switch weekday {
        case 1: kronabyDay = 5  // Sunday
        case 2: kronabyDay = 6  // Monday
        case 3: kronabyDay = 0  // Tuesday
        case 4: kronabyDay = 1  // Wednesday
        case 5: kronabyDay = 2  // Thursday
        case 6: kronabyDay = 3  // Friday
        case 7: kronabyDay = 4  // Saturday
        default: kronabyDay = 0
        }

        sendCommand(name: "datetime", value: [
            comps.year!, comps.month!, comps.day!,
            comps.hour!, comps.minute!, comps.second!,
            kronabyDay
        ])

        connectionState = .connected
    }

    // MARK: - Filtering

    private func isKronabyDevice(_ peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        // Check by advertised service UUIDs
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            let uuidStrings = serviceUUIDs.map { $0.uuidString.uppercased() }
            if uuidStrings.contains("F431") || uuidStrings.contains("0000F431-0000-1000-8000-00805F9B34FB") {
                return true
            }
        }
        // Fallback: check device name
        if let name = peripheral.name?.lowercased() {
            if name.contains("kronaby") || name.contains("anima") {
                return true
            }
        }
        return false
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if pendingScan {
                startScan()
            }
        case .poweredOff:
            connectionState = .bluetoothOff
        default:
            connectionState = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard isKronabyDevice(peripheral, advertisementData: advertisementData) else { return }
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals = discoveredPeripherals + [peripheral]
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([
            BLEConstants.animaServiceUUID,
            BLEConstants.deviceInfoServiceUUID
        ])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        self.peripheral = nil
        commandChar = nil
        notifyChar = nil
        commandMap.removeAll()
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            switch char.uuid {
            case BLEConstants.commandCharUUID:
                commandChar = char
                peripheral.setNotifyValue(true, for: char)
            case BLEConstants.notifyCharUUID:
                notifyChar = char
                peripheral.setNotifyValue(true, for: char)
            default:
                break
            }
        }

        if commandChar != nil && notifyChar != nil {
            performHandshake()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let decoded = protocol_.decode(data: data)

        if connectionState == .handshaking {
            if let map = decoded as? [String: Int] {
                commandMap.merge(map) { _, new in new }
            }
            if commandMap.count >= 10 {
                completeSetup()
            }
        } else if connectionState == .connected {
            if let event = protocol_.parseButtonEvent(decoded, commandMap: commandMap) {
                lastButtonEvent = event
            }
        }
    }
}
