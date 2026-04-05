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

    private let findMyPhone = FindMyPhone()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.findMyPhone.stop()
        }
    }

    // MARK: - Extended Input Mode (16종)

    private func cancelExtendedMode() {
        isExtendedMode = false
        extendedBits = []
        // 진동 3회 — 취소 알림
        bleManager?.sendCommand(name: "vibrator_start", value: [150, 100, 150, 100, 150])
        bleManager?.log("확장입력모드 취소")
    }

    private func startExtendedMode() {
        isExtendedMode = true
        extendedBits = []
        // 진동 1회 — 입력 모드 시작 알림
        bleManager?.sendCommand(name: "vibrator_start", value: [150])
        bleManager?.log("확장입력모드 시작")
    }

    private func handleExtendedInput(event: Int) {
        // 1회 클릭 = 0, 2회 클릭 = 1
        let bit: Int
        switch event {
        case 1: bit = 0
        case 3: bit = 1
        default: return  // 다른 이벤트 무시
        }

        extendedBits.append(bit)
        bleManager?.log("확장입력: bit \(extendedBits.count)/4 = \(bit)")

        if extendedBits.count >= 4 {
            // 4비트 완성 → 10진 변환
            let value = extendedBits[0] * 8 + extendedBits[1] * 4 + extendedBits[2] * 2 + extendedBits[3]
            // 진동 2회 — 입력 완료 알림
            bleManager?.sendCommand(name: "vibrator_start", value: [150, 100, 150])
            bleManager?.log("확장입력 완료: \(extendedBits) = \(value)")

            // 명령 실행
            if value < extendedMappings.count {
                let action = extendedMappings[value]
                if action.type != .none {
                    executeAction(action)
                    bleManager?.log("확장입력 실행: [\(value)] \(action.type.displayName)")
                }
            }

            isExtendedMode = false
            extendedBits = []
        }
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