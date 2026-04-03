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
    @Published var debugLog: [String] = []

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?

    private let protocol_ = KronabyProtocol()
    private var pendingScan = false
    private var handshakeStep = 0
    private var handshakeResponseCount = 0

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
        log("BLEManager 초기화")
    }

    func log(_ msg: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        debugLog.append("[\(time)] \(msg)")
        // Keep last 50 entries
        if debugLog.count > 50 { debugLog.removeFirst() }
    }

    // MARK: - Public API

    func startScan() {
        log("startScan() — BLE state: \(centralManager.state.rawValue)")
        guard centralManager.state == .poweredOn else {
            pendingScan = true
            if centralManager.state == .poweredOff {
                connectionState = .bluetoothOff
            }
            log("BLE not ready, queued scan")
            return
        }
        pendingScan = false
        discoveredPeripherals = []
        connectionState = .scanning

        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        log("스캔 시작됨 (all devices)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.connectionState == .scanning else { return }
            self.log("스캔 30초 타임아웃")
            self.stopScan()
        }
    }

    func stopScan() {
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
        log("스캔 중지")
    }

    func connect(to peripheral: CBPeripheral) {
        stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        log("연결 시도: \(peripheral.name ?? "unknown") (\(peripheral.identifier))")
        centralManager.connect(peripheral, options: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.connectionState == .connecting else { return }
            self.log("연결 15초 타임아웃 — 취소")
            self.disconnect()
        }
    }

    func disconnect() {
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
            log("연결 해제 요청")
        }
    }

    func sendCommand(name: String, value: Any) {
        guard let char = commandChar,
              let cmdId = commandMap[name] else {
            log("sendCommand 실패: \(name) (char=\(commandChar != nil), cmdId=\(commandMap[name] ?? -1))")
            return
        }
        let data = protocol_.encode(commandId: cmdId, value: value)
        peripheral?.writeValue(data, for: char, type: .withResponse)
        log("CMD: \(name)(\(cmdId)) → \(data.map { String(format: "%02X", $0) }.joined())")
    }

    // MARK: - Connection Sequence

    private func performHandshake() {
        connectionState = .handshaking
        handshakeStep = 0
        handshakeResponseCount = 0
        log("핸드셰이크 시작")
        sendNextHandshakeStep()
    }

    private var waitingForRead = false

    private func sendNextHandshakeStep() {
        guard handshakeStep <= 2 else {
            log("핸드셰이크 3단계 전송 완료")
            return
        }
        guard let char = commandChar else {
            log("핸드셰이크 실패: commandChar 없음")
            return
        }
        let step = handshakeStep
        // 올바른 인코딩: [0, step] (Array), withoutResponse
        let data = protocol_.encodeArray([0, step])
        waitingForRead = false
        peripheral?.writeValue(data, for: char, type: .withoutResponse)
        log("map_cmd(\(step)) → \(data.map { String(format: "%02X", $0) }.joined())")

        // write 후 read로 응답 받기
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, let p = self.peripheral, let c = self.commandChar else { return }
            self.waitingForRead = true
            p.readValue(for: c)
            self.log("map_cmd(\(step)) read 요청")
        }
    }

    private func completeSetup() {
        log("핸드셰이크 완료 — commandMap: \(commandMap)")
        sendCommand(name: "onboarding_done", value: 1)

        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: now)

        let weekday = comps.weekday!
        let kronabyDay: Int
        switch weekday {
        case 1: kronabyDay = 5
        case 2: kronabyDay = 6
        case 3: kronabyDay = 0
        case 4: kronabyDay = 1
        case 5: kronabyDay = 2
        case 6: kronabyDay = 3
        case 7: kronabyDay = 4
        default: kronabyDay = 0
        }

        sendCommand(name: "datetime", value: [
            comps.year!, comps.month!, comps.day!,
            comps.hour!, comps.minute!, comps.second!,
            kronabyDay
        ])

        connectionState = .connected
        log("설정 완료 — 연결됨!")
    }

    // MARK: - Filtering

    private func isKronabyDevice(_ peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            let uuidStrings = serviceUUIDs.map { $0.uuidString.uppercased() }
            if uuidStrings.contains("F431") || uuidStrings.contains("0000F431-0000-1000-8000-00805F9B34FB") {
                return true
            }
        }
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
        log("BLE state → \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            if pendingScan { startScan() }
        case .poweredOff:
            connectionState = .bluetoothOff
        default:
            connectionState = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard isKronabyDevice(peripheral, advertisementData: advertisementData) else { return }
        log("발견: \(peripheral.name ?? "?") RSSI:\(RSSI)")
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals = discoveredPeripherals + [peripheral]
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("BLE 연결됨 — 서비스 검색 시작")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("연결 실패: \(error?.localizedDescription ?? "unknown")")
        connectionState = .disconnected
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("연결 끊김: \(error?.localizedDescription ?? "정상")")
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
        if let error = error {
            log("서비스 검색 에러: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services else {
            log("서비스 없음")
            return
        }
        log("서비스 발견: \(services.map { $0.uuid.uuidString })")
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            log("특성 검색 에러 (\(service.uuid)): \(error.localizedDescription)")
            return
        }
        guard let chars = service.characteristics else { return }
        log("특성 [\(service.uuid)]: \(chars.map { $0.uuid.uuidString })")

        for char in chars {
            switch char.uuid {
            case BLEConstants.commandCharUUID:
                commandChar = char
                peripheral.setNotifyValue(true, for: char)
                log("→ commandChar 획득")
            case BLEConstants.notifyCharUUID:
                notifyChar = char
                peripheral.setNotifyValue(true, for: char)
                log("→ notifyChar 획득")
            default:
                break
            }
        }

        if commandChar != nil && notifyChar != nil && connectionState == .connecting {
            performHandshake()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("쓰기 에러 [\(characteristic.uuid)]: \(error.localizedDescription)")
        } else {
            log("쓰기 성공 [\(characteristic.uuid)]")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("값 수신 에러: \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }
        let hex = data.map { String(format: "%02X", $0) }.joined()
        log("수신 [\(characteristic.uuid)]: \(hex)")

        let decoded = protocol_.decode(data: data)

        if connectionState == .handshaking {
            let isFromCommandChar = characteristic.uuid == BLEConstants.commandCharUUID
            var foundMap = false

            // Case 1: response is directly {string: int}
            if let map = decoded as? [String: Int] {
                commandMap.merge(map) { _, new in new }
                log("맵(직접): \(commandMap.count)개")
                foundMap = true
            }
            // Case 2: response is {int: {string: int}} — wrapped with command ID
            else if let outer = decoded as? [Int: Any] {
                for (key, value) in outer {
                    if let innerMap = value as? [String: Int] {
                        commandMap.merge(innerMap) { _, new in new }
                        log("맵(래핑 key=\(key)): \(commandMap.count)개")
                        foundMap = true
                    }
                }
            }

            if !foundMap {
                log("응답(맵 아님) [\(isFromCommandChar ? "cmd" : "ntf")]: \(String(describing: decoded))")
            }

            // command 특성에서 read 응답이 온 경우 → 다음 step 진행
            if isFromCommandChar {
                handshakeStep += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self, self.connectionState == .handshaking else { return }
                    if self.handshakeStep <= 2 {
                        self.sendNextHandshakeStep()
                    } else {
                        self.log("commandMap 전체: \(self.commandMap)")
                        self.log("핸드셰이크 완료 — \(self.commandMap.count)개")
                        self.completeSetup()
                    }
                }
            }
        } else if connectionState == .connected {
            if let event = protocol_.parseButtonEvent(decoded, commandMap: commandMap) {
                lastButtonEvent = event
                log("버튼: \(event.buttonName) \(event.eventName)")
            }
        }
    }
}
