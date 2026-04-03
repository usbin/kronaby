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
    private var lastReadHex = ""
    private var readRetryCount = 0

    private static let savedPeripheralKey = "kronaby_peripheral_uuid"
    private static let savedCommandMapKey = "kronaby_command_map"

    private func savePeripheralID(_ uuid: UUID) {
        UserDefaults.standard.set(uuid.uuidString, forKey: Self.savedPeripheralKey)
    }

    private func loadSavedPeripheralID() -> UUID? {
        guard let str = UserDefaults.standard.string(forKey: Self.savedPeripheralKey) else { return nil }
        return UUID(uuidString: str)
    }

    private func saveCommandMap() {
        UserDefaults.standard.set(commandMap, forKey: Self.savedCommandMapKey)
        log("commandMap 저장 (\(commandMap.count)개)")
    }

    private func loadSavedCommandMap() -> [String: Int]? {
        return UserDefaults.standard.dictionary(forKey: Self.savedCommandMapKey) as? [String: Int]
    }

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

        // F431 서비스 UUID로 필터 — 페어링 모드 시계만 검색
        centralManager.scanForPeripherals(
            withServices: [BLEConstants.kronabyAdvertisementUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        log("스캔 시작됨 (F431 필터)")

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

        // 30초 연결 타임아웃
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.connectionState == .connecting else { return }
            self.log("연결 타임아웃 — 실패")
            self.disconnect()
        }
    }

    func disconnect() {
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
            log("연결 해제 요청")
        }
    }

    func forgetDevice() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: Self.savedPeripheralKey)
        UserDefaults.standard.removeObject(forKey: Self.savedCommandMapKey)
        commandMap.removeAll()
        log("저장된 기기 정보 삭제")
    }

    func sendCommand(name: String, value: Any) {
        guard let char = commandChar,
              let cmdId = commandMap[name] else {
            log("sendCommand 실패: \(name) (char=\(commandChar != nil), map=\(commandMap[name] as Any))")
            return
        }
        let data = protocol_.encode(commandId: cmdId, value: value)
        let hex = data.map { String(format: "%02X", $0) }.joined()
        log("CMD: \(name)(\(cmdId)) → \(hex)")
        peripheral?.writeValue(data, for: char, type: .withResponse)
    }

    // MARK: - Connection Sequence

    private func performHandshake() {
        connectionState = .handshaking
        handshakeStep = 0
        handshakeResponseCount = 0
        lastReadHex = ""
        readRetryCount = 0
        commandMap.removeAll()
        log("핸드셰이크 시작")
        sendNextHandshakeStep()
    }

    private var pendingHandshakeRead = false

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
        let data = protocol_.encodeArray([0, step])
        pendingHandshakeRead = true
        // withResponse로 전송 — didWriteValueFor 콜백에서 read
        peripheral?.writeValue(data, for: char, type: .withResponse)
        log("map_cmd(\(step)) → \(data.map { String(format: "%02X", $0) }.joined())")
    }

    private func completeSetup() {
        log("핸드셰이크 완료 — commandMap \(commandMap.count)개")

        // 검증: commandMap에 필수 키가 있어야 함
        guard commandMap.count >= 10,
              commandMap["onboarding_done"] != nil,
              commandMap["datetime"] != nil else {
            log("핸드셰이크 실패 — commandMap 불완전 (\(commandMap.count)개)")
            disconnect()
            return
        }

        saveCommandMap()
        connectionState = .connected
        // 핸드셰이크 write/read 완료 후 충분히 대기 → onboarding_done 전송
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.sendCommand(name: "onboarding_done", value: 1)
            self.log("연결됨! 영점 조정 → 시각 설정 순서로 진행하세요.")
        }
    }

    // MARK: - Filtering

    // isKronabyDevice 불필요 — F431 서비스 필터로 스캔하므로 didDiscover에 오는 건 모두 Kronaby
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("BLE state → \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            // 저장된 페리퍼럴이 이미 연결 상태인 경우만 복원
            if let savedID = loadSavedPeripheralID() {
                let peripherals = central.retrievePeripherals(withIdentifiers: [savedID])
                if let existing = peripherals.first, existing.state == .connected {
                    log("기존 연결 복원: \(existing.name ?? "?")")
                    self.peripheral = existing
                    existing.delegate = self
                    connectionState = .connecting
                    existing.discoverServices(nil)
                    return
                }
                // 연결 안 되어 있으면 수동 스캔 대기 (자동 재연결 안 함)
                log("저장된 기기 미연결 — 스캔 필요")
            }
            if pendingScan { startScan() }
        case .poweredOff:
            connectionState = .bluetoothOff
        default:
            connectionState = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // F431 서비스 필터로 이미 페어링 모드 시계만 들어옴
        log("발견: \(peripheral.name ?? "?") RSSI:\(RSSI)")
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals = discoveredPeripherals + [peripheral]
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("BLE 연결됨 — 서비스 검색 시작")
        savePeripheralID(peripheral.identifier)
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
            // 저장된 commandMap이 있으면 핸드셰이크 스킵
            if let savedMap = loadSavedCommandMap(), !savedMap.isEmpty {
                commandMap = savedMap
                log("저장된 commandMap 복원 (\(savedMap.count)개)")
                sendCommand(name: "onboarding_done", value: 1)
                connectionState = .connected
                log("재연결 완료!")
            } else {
                performHandshake()
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("쓰기 에러 [\(characteristic.uuid)]: \(error.localizedDescription)")
        } else {
            log("쓰기 성공 [\(characteristic.uuid)]")
            // 핸드셰이크 중 write 성공 → read로 응답 받기
            if pendingHandshakeRead && characteristic.uuid == BLEConstants.commandCharUUID {
                pendingHandshakeRead = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, let p = self.peripheral, let c = self.commandChar else { return }
                    p.readValue(for: c)
                    self.log("map_cmd(\(self.handshakeStep)) read 요청")
                }
            }
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
            // Case 2: response is {int: {string: int}} — wrapped
            else if let outer = decoded as? [Int: Any] {
                for (key, value) in outer {
                    // {0: {string_name: int_id}} — name→id
                    if let innerMap = value as? [String: Int] {
                        commandMap.merge(innerMap) { _, new in new }
                        log("맵(name→id key=\(key)): \(commandMap.count)개")
                        foundMap = true
                    }
                    // {0: {int_id: string_name}} — id→name (실제 Kronaby 형식)
                    else if let innerMap = value as? [Int: Any] {
                        for (id, name) in innerMap {
                            if let nameStr = name as? String {
                                commandMap[nameStr] = id
                            }
                        }
                        if !innerMap.isEmpty {
                            log("맵(id→name key=\(key)): \(commandMap.count)개")
                            foundMap = true
                        }
                    }
                }
            }

            if !foundMap {
                log("응답(맵 아님) [\(isFromCommandChar ? "cmd" : "ntf")]: \(String(describing: decoded))")
            }

            // command 특성에서 read 응답이 온 경우 → 다음 step 진행
            if isFromCommandChar {
                // 이전과 같은 데이터면 write 재전송 (최대 10회)
                if hex == lastReadHex && handshakeStep > 0 {
                    readRetryCount += 1
                    if readRetryCount > 10 {
                        log("핸드셰이크 실패 — step \(handshakeStep) 응답 없음")
                        disconnect()
                        return
                    }
                    log("같은 데이터 — \(readRetryCount)회 재시도")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        guard let self, self.connectionState == .handshaking else { return }
                        self.sendNextHandshakeStep()
                    }
                    return
                }
                lastReadHex = hex
                readRetryCount = 0
                handshakeStep += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, self.connectionState == .handshaking else { return }
                    if self.handshakeStep <= 2 {
                        self.sendNextHandshakeStep()
                    } else {
                        self.log("핸드셰이크 완료 — commandMap \(self.commandMap.count)개")
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
