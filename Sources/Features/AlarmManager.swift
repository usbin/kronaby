import Foundation

struct WatchAlarm: Codable, Identifiable, Equatable {
    var id: Int          // 1~8
    var hour: Int        // 0~23
    var minute: Int      // 0~59
    var enabled: Bool
    var days: Set<Int>   // 1=월, 2=화, 3=수, 4=목, 5=금, 6=토, 7=일 (ISO)

    var timeString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var daysString: String {
        if days.count == 7 { return "매일" }
        if days.isEmpty { return "반복 없음" }
        let names = ["", "월", "화", "수", "목", "금", "토", "일"]
        return days.sorted().map { names[$0] }.joined(separator: " ")
    }

    // 알람 config byte
    // bit 0 = 1회성 알람 (요일 없을 때)
    // bits 1-7 = Kronaby 요일 순서 (화=bit1, 수=bit2, 목=bit3, 금=bit4, 토=bit5, 일=bit6, 월=bit7)
    // ISO day → Kronaby bitmask bit: 월→7, 화→1, 수→2, 목→3, 금→4, 토→5, 일→6
    private static let dayToBit: [Int: Int] = [
        1: 7,  // 월 → bit 7
        2: 1,  // 화 → bit 1
        3: 2,  // 수 → bit 2
        4: 3,  // 목 → bit 3
        5: 4,  // 금 → bit 4
        6: 5,  // 토 → bit 5
        7: 6,  // 일 → bit 6
    ]

    var configByte: UInt8 {
        if !enabled { return 0 }
        if days.isEmpty { return 1 }  // 1회성
        var mask = 0
        for day in days {
            if let bit = Self.dayToBit[day] {
                mask |= (1 << bit)
            }
        }
        return UInt8(mask & 0xFF)
    }

    // 13바이트 바이너리 인코딩
    func encode() -> Data {
        var data = Data(count: 13)

        // ID (4 bytes, little-endian)
        let idLE = UInt32(id).littleEndian
        withUnsafeBytes(of: idLE) { data.replaceSubrange(0..<4, with: $0) }

        // Last Modified (4 bytes, little-endian)
        let timestamp = UInt32(Date().timeIntervalSince1970)
        let tsLE = timestamp.littleEndian
        withUnsafeBytes(of: tsLE) { data.replaceSubrange(4..<8, with: $0) }

        // Hour, Minute
        data[8] = UInt8(hour)
        data[9] = UInt8(minute)

        // Reserved (2 bytes)
        data[10] = 0
        data[11] = 0

        // Config byte
        data[12] = configByte

        return data
    }
}

final class AlarmManager: ObservableObject {
    @Published var alarms: [WatchAlarm] = []
    @Published var alarmSlot: Int = 1  // 전체 알람의 바늘 위치 (1~3)

    private static let storageKey = "kronaby_alarms"
    private static let slotKey = "kronaby_alarm_slot"
    static let maxAlarms = 8

    init() {
        load()
        let saved = UserDefaults.standard.integer(forKey: Self.slotKey)
        if saved > 0 { alarmSlot = saved }
    }

    func addAlarm() {
        guard alarms.count < Self.maxAlarms else { return }
        let newId = (alarms.map(\.id).max() ?? 0) + 1
        alarms.append(WatchAlarm(id: newId, hour: 7, minute: 0, enabled: false, days: []))
        save()
    }

    func removeAlarm(at offsets: IndexSet) {
        alarms.remove(atOffsets: offsets)
        save()
    }

    func applyToWatch(ble: BLEManager) {
        let activeAlarms: [[Int]] = alarms
            .filter { $0.enabled }
            .map { [$0.hour, $0.minute, Int($0.configByte)] }

        // 1. alert_assign — Array 형식 [pos1, pos2, pos3]
        // ANCS 활성 슬롯도 함께 포함해야 덮어쓰지 않음
        var assignArray = [0, 0, 0]
        if !activeAlarms.isEmpty && self.alarmSlot >= 1 && self.alarmSlot <= 3 {
            assignArray[self.alarmSlot - 1] = 1
        }
        // ANCS 슬롯 정보 읽어서 병합
        if let data = UserDefaults.standard.data(forKey: "kronaby_ancs_slots_v5"),
           let slots = try? JSONDecoder().decode([NotificationSlot].self, from: data) {
            for slot in slots where slot.enabled && !slot.categories.isEmpty {
                if slot.id >= 1 && slot.id <= 3 {
                    assignArray[slot.id - 1] = 1
                }
            }
        }
        ble.sendCommand(name: "alert_assign", value: assignArray)
        ble.log("alert_assign(\(assignArray))")

        // 2. 알람 데이터 전송
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ble.sendCommand(name: "alarm", value: activeAlarms)
            ble.log("alarm 전송: \(activeAlarms) → 위치 \(self.alarmSlot)")
        }

        UserDefaults.standard.set(alarmSlot, forKey: Self.slotKey)
    }

    private func encodeBinary() -> Data {
        var data = Data()
        // 헤더: version(2B LE) + count(1B) + reserved(1B)
        data.append(contentsOf: [0x01, 0x00])  // version 1
        data.append(UInt8(alarms.count))
        data.append(0x00)

        for alarm in alarms {
            // ID (4B LE)
            var id = UInt32(alarm.id).littleEndian
            data.append(Data(bytes: &id, count: 4))
            // Timestamp (4B LE)
            var ts = UInt32(Date().timeIntervalSince1970).littleEndian
            data.append(Data(bytes: &ts, count: 4))
            // Hour, Minute
            data.append(UInt8(alarm.hour))
            data.append(UInt8(alarm.minute))
            // Reserved (2B)
            data.append(contentsOf: [0x00, 0x00])
            // Config: bit0=enabled, bits1-7=days
            data.append(alarm.configByte)
        }
        return data
    }

    func save() {
        if let data = try? JSONEncoder().encode(alarms) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([WatchAlarm].self, from: data) {
            alarms = decoded
        }
    }
}