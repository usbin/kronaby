import Foundation

// MARK: - ANCS 카테고리 (Kronaby 펌웨어 기준)

enum AncsCategory: Int, Codable, CaseIterable, Identifiable {
    case other = 0
    case incomingCall = 1
    case missedCall = 2
    case voicemail = 3
    case social = 4
    case schedule = 5
    case email = 6
    case news = 7
    case healthFitness = 8
    case businessFinance = 9
    case location = 10
    case entertainment = 11

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .other: return "기타"
        case .incomingCall: return "수신 전화"
        case .missedCall: return "부재중 전화"
        case .voicemail: return "음성 메일"
        case .social: return "소셜 미디어"
        case .schedule: return "일정"
        case .email: return "이메일"
        case .news: return "뉴스"
        case .healthFitness: return "건강/피트니스"
        case .businessFinance: return "비즈니스/금융"
        case .location: return "위치"
        case .entertainment: return "엔터테인먼트"
        }
    }

    var systemImage: String {
        switch self {
        case .other: return "app.badge.fill"
        case .incomingCall: return "phone.fill"
        case .missedCall: return "phone.arrow.down.left"
        case .voicemail: return "recordingtape"
        case .social: return "person.2.fill"
        case .schedule: return "calendar"
        case .email: return "envelope.fill"
        case .news: return "newspaper.fill"
        case .healthFitness: return "heart.fill"
        case .businessFinance: return "chart.line.uptrend.xyaxis"
        case .location: return "location.fill"
        case .entertainment: return "film"
        }
    }

    var bitmask: Int { 1 << (rawValue + 8) }
    static var allBitmask: Int { 0xFFFFFF }
}

enum VibrationPattern: Int, Codable, CaseIterable, Identifiable {
    case single = 1
    case double = 2
    case triple = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .single: return "진동 1회"
        case .double: return "진동 2회"
        case .triple: return "진동 3회"
        }
    }
}

// MARK: - 필터 타입

enum FilterType: Codable, Equatable {
    case allNotifications           // 모든 알림
    case category(AncsCategory)     // ANCS 카테고리
    case app(bundleId: String, name: String)  // 특정 앱

    var displayName: String {
        switch self {
        case .allNotifications: return "모든 알림"
        case .category(let c): return c.displayName
        case .app(_, let name): return name.isEmpty ? "앱 지정" : name
        }
    }

    var systemImage: String {
        switch self {
        case .allNotifications: return "bell.badge.fill"
        case .category(let c): return c.systemImage
        case .app: return "app.fill"
        }
    }

    // ANCS 속성 타입: 0=ApplicationId, 255=All
    var attributeType: Int {
        switch self {
        case .app: return 0
        default: return 255
        }
    }

    var searchString: String {
        switch self {
        case .app(let bundleId, _): return bundleId
        default: return ""
        }
    }

    var bitmask: Int {
        switch self {
        case .allNotifications: return AncsCategory.allBitmask
        case .category(let c): return c.bitmask
        case .app: return AncsCategory.allBitmask  // 앱 필터는 전체 카테고리
        }
    }
}

// MARK: - 필터 설정

struct NotificationFilter: Codable, Equatable, Identifiable {
    var id: String
    var filterType: FilterType
    var vibration: VibrationPattern
    var position: Int       // 시계 숫자 위치 (1~12)
    var enabled: Bool

    var displayName: String { filterType.displayName }
    var systemImage: String { filterType.systemImage }
}

// MARK: - Manager

final class NotificationMappingManager: ObservableObject {
    @Published var filters: [NotificationFilter] = []

    private static let storageKey = "kronaby_ancs_filters_v3"
    private var nextFilterIndex = 20  // 앱 필터용 인덱스 (20~34)

    init() {
        load()
        if filters.isEmpty {
            filters = [
                NotificationFilter(id: "all", filterType: .allNotifications, vibration: .single, position: 11, enabled: false),
                NotificationFilter(id: "call", filterType: .category(.incomingCall), vibration: .double, position: 12, enabled: false),
                NotificationFilter(id: "missed", filterType: .category(.missedCall), vibration: .single, position: 1, enabled: false),
                NotificationFilter(id: "social", filterType: .category(.social), vibration: .single, position: 2, enabled: false),
                NotificationFilter(id: "email", filterType: .category(.email), vibration: .single, position: 3, enabled: false),
                NotificationFilter(id: "schedule", filterType: .category(.schedule), vibration: .single, position: 4, enabled: false),
                NotificationFilter(id: "news", filterType: .category(.news), vibration: .single, position: 5, enabled: false),
                NotificationFilter(id: "entertain", filterType: .category(.entertainment), vibration: .single, position: 6, enabled: false),
                NotificationFilter(id: "other", filterType: .category(.other), vibration: .single, position: 7, enabled: false),
            ]
        }
    }

    func addAppFilter(bundleId: String, name: String) {
        let id = "app_\(bundleId)"
        guard !filters.contains(where: { $0.id == id }) else { return }
        nextFilterIndex += 1
        filters.append(NotificationFilter(
            id: id,
            filterType: .app(bundleId: bundleId, name: name),
            vibration: .single,
            position: 8,
            enabled: true
        ))
        save()
    }

    func removeFilter(id: String) {
        filters.removeAll { $0.id == id }
        save()
    }

    // MARK: - Apply to Watch

    func applyToWatch(ble: BLEManager) {
        let activeFilters = filters.filter { $0.enabled }

        // 사용할 인덱스들만 삭제 + 활성 필터 전송 (딜레이 포함)
        var delay: Double = 0

        // 1. 기존 필터 삭제 (0~12만, 딜레이 간격)
        for i in 0...12 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                ble.sendCommand(name: "ancs_filter", value: [i])
            }
            delay += 0.1
        }
        ble.log("기존 필터 삭제 예약 (0~12)")

        // 2. 활성 필터 전송 (삭제 완료 후)
        delay += 0.5
        for filter in activeFilters {
            let idx = filter.position
            let bitmask = filter.filterType.bitmask
            let attr = filter.filterType.attributeType
            let search = filter.filterType.searchString
            let vib = filter.vibration.rawValue

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                ble.sendCommand(name: "ancs_filter", value: [
                    idx, bitmask, attr, search, vib
                ] as [Any])
                ble.log("ancs_filter[\(idx)]: \(filter.displayName) → \(idx)시, vib=\(vib)")
            }
            delay += 0.3
        }
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(filters) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([NotificationFilter].self, from: data) {
            filters = decoded
        }
    }
}