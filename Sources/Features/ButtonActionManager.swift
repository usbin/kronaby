import Foundation
import UIKit

// MARK: - Action Types

enum ButtonActionType: String, Codable, CaseIterable {
    case none = "none"
    case findPhone = "find_phone"
    case musicPlayPause = "music_play_pause"
    case musicNext = "music_next"
    case musicPrevious = "music_previous"
    case recordLocation = "record_location"
    case iftttWebhook = "ifttt_webhook"
    case shortcut = "shortcut"
    case urlRequest = "url_request"

    var displayName: String {
        switch self {
        case .none: return "없음"
        case .findPhone: return "폰 찾기"
        case .musicPlayPause: return "음악: 재생/일시정지"
        case .musicNext: return "음악: 다음 곡"
        case .musicPrevious: return "음악: 이전 곡"
        case .recordLocation: return "위치 기록"
        case .iftttWebhook: return "IFTTT Webhook"
        case .shortcut: return "단축어 실행 (앱 열림)"
        case .urlRequest: return "URL 요청"
        }
    }

    var category: String {
        switch self {
        case .none: return ""
        case .findPhone: return "기본"
        case .musicPlayPause, .musicNext, .musicPrevious: return "음악"
        case .recordLocation: return "위치"
        case .iftttWebhook, .shortcut, .urlRequest: return "고급"
        }
    }
}

struct ButtonAction: Codable, Equatable {
    var type: ButtonActionType = .none
    var iftttEventName: String = ""
    var shortcutName: String = ""
    var urlString: String = ""
}

struct ButtonKey: Hashable, Codable {
    let button: Int   // 0=top, 2=bottom
    let event: Int    // 1=single, 2=long, 3=double, 4=triple, 5=quad

    var displayButton: String {
        button == 0 ? "상단" : "하단"
    }

    var displayEvent: String {
        switch event {
        case 1: return "1회 클릭"
        case 2: return "길게 누름"
        case 3: return "2회 클릭"
        case 4: return "3회 클릭"
        case 5: return "4회 클릭"
        default: return "코드 \(event)"
        }
    }

    var storageKey: String { "\(button)_\(event)" }
}

// MARK: - Manager

final class ButtonActionManager: ObservableObject {
    @Published var mappings: [String: ButtonAction] = [:]
    @Published var iftttKey: String = ""

    // 확장입력모드 (0~15)
    @Published var extendedMappings: [ButtonAction] = Array(repeating: ButtonAction(), count: 16)
    @Published var isExtendedMode = false
    @Published var extendedBits: [Int] = []  // 입력 중인 비트

    let findMyPhone = FindMyPhone()
    @Published var isFindMyPhonePlaying = false
    private let musicController = MusicController()
    var locationRecorder: LocationRecorder?
    var bleManager: BLEManager?

    private static let mappingsKey = "button_mappings"
    private static let iftttKeyKey = "ifttt_webhook_key"
    private static let extendedKey = "extended_mappings"

    // 상단 전체 + 하단 1회/2회/3회/4회 (길게 누름 제외)
    static let allButtons: [ButtonKey] = {
        var keys: [ButtonKey] = []
        for event in [1, 3, 4, 5, 2] {
            keys.append(ButtonKey(button: 0, event: event))
        }
        // 하단: 길게 누름(2) 제외
        for event in [1, 3, 4, 5] {
            keys.append(ButtonKey(button: 2, event: event))
        }
        return keys
    }()

    init() {
        load()
    }

    func getAction(for key: ButtonKey) -> ButtonAction {
        mappings[key.storageKey] ?? ButtonAction()
    }

    func setAction(for key: ButtonKey, action: ButtonAction) {
        mappings[key.storageKey] = action
        save()
    }

    // MARK: - Execute

    func handleButtonEvent(button: Int, event: Int) {
        // 하단 길게 누름 → 확장입력모드 진입 또는 취소
        if button == 2 && event == 2 {
            if isExtendedMode {
                cancelExtendedMode()
            } else {
                startExtendedMode()
            }
            return
        }

        // 확장입력모드 중 — 하단 버튼만 입력 받음
        if isExtendedMode && button == 2 {
            handleExtendedInput(event: event)
            return
        }

        // 일반 모드
        let key = ButtonKey(button: button, event: event)
        let action = getAction(for: key)
        executeAction(action)
    }

    func executeAction(_ action: ButtonAction) {
        switch action.type {
        case .none:
            break
        case .findPhone:
            handleFindMyPhone()
        case .musicPlayPause:
            musicController.playPause()
        case .musicNext:
            musicController.nextTrack()
        case .musicPrevious:
            musicController.previousTrack()
        case .recordLocation:
            locationRecorder?.recordCurrentLocation()
        case .iftttWebhook:
            fireIFTTT(eventName: action.iftttEventName)
        case .shortcut:
            runShortcut(name: action.shortcutName)
        case .urlRequest:
            fireURL(urlString: action.urlString)
        }
    }

    func handleFindMyPhone() {
        findMyPhone.play()
        isFindMyPhonePlaying = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.stopFindMyPhone()
        }
    }

    func stopFindMyPhone() {
        findMyPhone.stop()
        isFindMyPhonePlaying = false
    }

    // MARK: - Extended Input Mode (16종)

    private func cancelExtendedMode() {
        isExtendedMode = false
        extendedBits = []
        // 진동 3회 — 취소
        bleManager?.sendCommand(name: "vibrator_start", value: [150, 100, 150, 100, 150])
        // 캘리브레이션 모드 종료 → datetime 복귀
        exitRecalibrateAndSyncTime()
        bleManager?.log("확장입력모드 취소")
    }

    private func startExtendedMode() {
        isExtendedMode = true
        extendedBits = []
        // 진동 1회
        bleManager?.sendCommand(name: "vibrator_start", value: [150])
        // 캘리브레이션 모드 진입 → 펌웨어가 datetime으로 자동 복귀하지 않음
        // recalibrate(true) 시 펌웨어가 바늘을 0(12시)으로 이동 → 안정 후 55로 전송
        bleManager?.sendCommand(name: "recalibrate", value: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.moveHands(to: 55)
        }
        bleManager?.log("확장입력모드 시작 → 11시 (recalibrate)")
    }

    /// recalibrate(false) 후 datetime 전송 — 공식 앱과 동일한 플로우
    private func exitRecalibrateAndSyncTime() {
        bleManager?.sendCommand(name: "recalibrate", value: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.sendCurrentDatetime()
        }
    }

    private func handleExtendedInput(event: Int) {
        let bit: Int
        switch event {
        case 1: bit = 0
        case 3: bit = 1
        default: return
        }

        extendedBits.append(bit)
        bleManager?.log("확장입력: bit \(extendedBits.count)/4 = \(bit)")

        if extendedBits.count >= 4 {
            let value = extendedBits[0] * 8 + extendedBits[1] * 4 + extendedBits[2] * 2 + extendedBits[3]
            // 진동 2회
            bleManager?.sendCommand(name: "vibrator_start", value: [150, 100, 150])
            bleManager?.log("확장입력 완료: \(extendedBits) = \(value)")

            // 바늘 애니메이션: 0분부터 1분씩 이동 → 최종 위치
            animateHands(to: value) { [weak self] in
                guard let self else { return }
                // 애니메이션 완료 후 명령 실행
                if value < self.extendedMappings.count {
                    let action = self.extendedMappings[value]
                    if action.type != .none {
                        self.executeAction(action)
                        self.bleManager?.log("확장입력 실행: [\(value)] \(action.type.displayName)")
                    }
                }
            }

            isExtendedMode = false
            extendedBits = []
        }
    }

    // MARK: - Hand Animation

    private func moveHands(to position: Int) {
        // 시침 + 분침 이동 (BLE 특성이 withoutResponse 미지원 → withResponse 사용)
        bleManager?.sendCommand(name: "stepper_goto", value: [0, position])
        bleManager?.sendCommand(name: "stepper_goto", value: [1, position])
    }

    private func animateHands(to target: Int, completion: @escaping () -> Void) {
        // 1분부터 째깍째깍 target까지 (position 0은 stepper에서 무시됨)
        var currentStep = 1

        func nextStep() {
            if currentStep > target {
                // 최종 위치에서 3초 유지 후 recalibrate 종료 → datetime 복귀
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    self?.exitRecalibrateAndSyncTime()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        completion()
                    }
                }
                return
            }

            moveHands(to: currentStep)
            currentStep += 1

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                nextStep()
            }
        }

        // 55분(11시)에서 1분으로 이동하는 물리적 시간 확보 후 째깍 시작
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            nextStep()
        }
    }

    private func sendCurrentDatetime() {
        let now = Date()
        var cal = Calendar.current
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: now)
        let kronabyDay: Int
        switch c.weekday! {
        case 1: kronabyDay = 5
        case 2: kronabyDay = 6
        case 3: kronabyDay = 0
        case 4: kronabyDay = 1
        case 5: kronabyDay = 2
        case 6: kronabyDay = 3
        case 7: kronabyDay = 4
        default: kronabyDay = 0
        }
        bleManager?.sendCommand(name: "datetime", value: [c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, kronabyDay])
    }

    // MARK: - IFTTT

    private func fireIFTTT(eventName: String) {
        guard !iftttKey.isEmpty, !eventName.isEmpty else { return }
        let urlStr = "https://maker.ifttt.com/trigger/\(eventName)/with/key/\(iftttKey)"
        guard let url = URL(string: urlStr) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request).resume()
    }

    // MARK: - Shortcuts

    private func runShortcut(name: String) {
        guard !name.isEmpty else { return }
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        if let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)") {
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - URL Request

    private func fireURL(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        URLSession.shared.dataTask(with: request).resume()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: Self.mappingsKey)
        }
        UserDefaults.standard.set(iftttKey, forKey: Self.iftttKeyKey)
        if let data = try? JSONEncoder().encode(extendedMappings) {
            UserDefaults.standard.set(data, forKey: Self.extendedKey)
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: Self.mappingsKey),
           let decoded = try? JSONDecoder().decode([String: ButtonAction].self, from: data) {
            mappings = decoded
        }
        iftttKey = UserDefaults.standard.string(forKey: Self.iftttKeyKey) ?? ""
        if let data = UserDefaults.standard.data(forKey: Self.extendedKey),
           let decoded = try? JSONDecoder().decode([ButtonAction].self, from: data) {
            extendedMappings = decoded
        }
    }

    func saveExtended() {
        if let data = try? JSONEncoder().encode(extendedMappings) {
            UserDefaults.standard.set(data, forKey: Self.extendedKey)
        }
    }
}