import Foundation
import UserNotifications

// MARK: - 알림 카테고리 (원본 Kronaby 앱 기준)

enum NotificationCategory: String, Codable, CaseIterable, Identifiable {
    case phone = "phone"
    case sms = "sms"
    case email = "email"
    case calendar = "calendar"
    case social = "social"
    case news = "news"
    case ifttt = "ifttt"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .phone: return "전화"
        case .sms: return "문자"
        case .email: return "이메일"
        case .calendar: return "캘린더"
        case .social: return "소셜 미디어"
        case .news: return "뉴스"
        case .ifttt: return "IFTTT"
        case .other: return "기타"
        }
    }

    var systemImage: String {
        switch self {
        case .phone: return "phone.fill"
        case .sms: return "message.fill"
        case .email: return "envelope.fill"
        case .calendar: return "calendar"
        case .social: return "person.2.fill"
        case .news: return "newspaper.fill"
        case .ifttt: return "bolt.fill"
        case .other: return "app.badge.fill"
        }
    }

    // 해당 카테고리에 매칭되는 앱 Bundle ID 패턴
    var bundlePatterns: [String] {
        switch self {
        case .phone: return ["com.apple.mobilephone", "com.apple.InCallService"]
        case .sms: return ["com.apple.MobileSMS", "com.apple.Messages"]
        case .email: return ["com.apple.mobilemail", "com.google.Gmail", "com.microsoft.Office.Outlook"]
        case .calendar: return ["com.apple.mobilecal", "com.google.calendar"]
        case .social: return ["com.facebook", "com.instagram", "com.twitter", "com.tencent", "net.daum.kakao", "com.linecorp"]
        case .news: return ["com.apple.news"]
        case .ifttt: return ["com.ifttt.ifttt"]
        case .other: return []
        }
    }
}

// MARK: - 알림 매핑 (카테고리 → 시계 숫자)

struct NotificationMapping: Codable, Equatable {
    var category: NotificationCategory
    var position: Int  // 0 = 비활성, 1-12 = 시계 숫자 위치
    var enabled: Bool

    static func defaultMappings() -> [NotificationMapping] {
        NotificationCategory.allCases.map {
            NotificationMapping(category: $0, position: 0, enabled: false)
        }
    }
}

// MARK: - Manager

final class NotificationMappingManager: ObservableObject {
    @Published var mappings: [NotificationMapping] = NotificationMapping.defaultMappings()

    private static let storageKey = "kronaby_notification_mappings"

    init() {
        load()
    }

    func getMapping(for category: NotificationCategory) -> NotificationMapping {
        mappings.first(where: { $0.category == category }) ?? NotificationMapping(category: category, position: 0, enabled: false)
    }

    func setMapping(for category: NotificationCategory, position: Int, enabled: Bool) {
        if let index = mappings.firstIndex(where: { $0.category == category }) {
            mappings[index].position = position
            mappings[index].enabled = enabled
        }
        save()
    }

    /// 활성화된 매핑만 반환
    func activeMappings() -> [NotificationMapping] {
        mappings.filter { $0.enabled && $0.position > 0 }
    }

    /// 알림 카테고리에 해당하는 시계 위치 반환 (0이면 매핑 없음)
    func positionForBundleID(_ bundleID: String) -> Int {
        for mapping in activeMappings() {
            if mapping.category.bundlePatterns.contains(where: { bundleID.hasPrefix($0) }) {
                return mapping.position
            }
        }
        // other 카테고리가 활성화되어 있으면 기타로 처리
        let otherMapping = getMapping(for: .other)
        if otherMapping.enabled && otherMapping.position > 0 {
            return otherMapping.position
        }
        return 0
    }

    /// 시계에 알림 필터 설정 전송
    func applyToWatch(ble: BLEManager) {
        // ancs_filter (cmd 4) — ANCS 알림 필터 설정
        // 활성화된 카테고리의 위치값 배열 전송
        let positionArray = NotificationCategory.allCases.map { category -> Int in
            let mapping = getMapping(for: category)
            return mapping.enabled ? mapping.position : 0
        }

        ble.sendCommand(name: "ancs_filter", value: positionArray)
        ble.log("ancs_filter 전송: \(positionArray)")

        // alert_assign (cmd 3) — 알림 타입별 동작 비트마스크 설정
        // 활성화된 카테고리에 대해 비트마스크 구성
        var bitmask0 = 0, bitmask1 = 0, bitmask2 = 0
        for (index, category) in NotificationCategory.allCases.enumerated() {
            let mapping = getMapping(for: category)
            if mapping.enabled && mapping.position > 0 {
                if index < 8 { bitmask0 |= (1 << index) }
                else if index < 16 { bitmask1 |= (1 << (index - 8)) }
                else { bitmask2 |= (1 << (index - 16)) }
            }
        }
        ble.sendCommand(name: "alert_assign", value: [bitmask0, bitmask1, bitmask2])
        ble.log("alert_assign 전송: [\(bitmask0), \(bitmask1), \(bitmask2)]")
    }

    /// 알림 수신 시 시계 바늘 이동 명령 전송
    func handleNotification(bundleID: String, ble: BLEManager) {
        let position = positionForBundleID(bundleID)
        guard position > 0 else { return }

        // alert (cmd 2) — 알림 표시 (시계 바늘이 해당 위치로 이동)
        ble.sendCommand(name: "alert", value: position)
        ble.log("alert 전송: \(bundleID) → 위치 \(position)")
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([NotificationMapping].self, from: data) {
            // 기존 저장된 매핑 복원 + 새로 추가된 카테고리 보충
            var restored = decoded
            for category in NotificationCategory.allCases {
                if !restored.contains(where: { $0.category == category }) {
                    restored.append(NotificationMapping(category: category, position: 0, enabled: false))
                }
            }
            mappings = restored
        }
    }
}
