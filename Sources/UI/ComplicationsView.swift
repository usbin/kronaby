import SwiftUI

// APK 디컴파일 기준 크라운 deviceComplicationMode 값
// set_complication_mode: [slotId=4(crown), mode]
enum CrownMode: Int, CaseIterable, Identifiable {
    case date = 0
    case time = 1
    case remote = 3
    case steps = 4
    case stoptime = 6
    case dice = 9
    case timer = 14
    case none = 15
    case stopwatch = 23
    case dayOfWeek = 28
    case battery = 46

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .date: return "날짜 확인"
        case .time: return "시간"
        case .remote: return "리모트"
        case .steps: return "걸음 수"
        case .stoptime: return "스톱타임"
        case .dice: return "주사위"
        case .timer: return "타이머"
        case .none: return "없음"
        case .stopwatch: return "스톱워치"
        case .dayOfWeek: return "요일"
        case .battery: return "배터리"
        }
    }
}

struct ComplicationsView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var crownMode: CrownMode = .date
    @State private var saved = false

    private static let savedKey = "kronaby_crown_mode"
    private static let crownSlotId = 4 // Slot.TopPusher (Crown)

    var body: some View {
        NavigationStack {
            Form {
                Section("크라운 1회 클릭 시 기능") {
                    Picker("기능", selection: $crownMode) {
                        ForEach(CrownMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section {
                    Text("크라운을 클릭하면 시침과 분침이 이동하여\n선택한 정보를 표시한 후 원래 위치로 돌아갑니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("시계에 적용") {
                        apply()
                    }
                    .frame(maxWidth: .infinity)

                    if saved {
                        Text("적용 완료!")
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("크라운 설정")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let raw = UserDefaults.standard.integer(forKey: Self.savedKey)
                crownMode = CrownMode(rawValue: raw) ?? .date
            }
        }
    }

    private func apply() {
        let mode = crownMode.rawValue

        // 후보 슬롯 전부 시도
        for slot in [3, 4, 7, 8] {
            ble.sendCommand(name: "set_complication_mode", value: [slot, mode])
        }

        // complications 배치 명령도 시도 (6개 슬롯 전체)
        ble.sendCommand(name: "complications", value: [mode, mode, mode, mode, mode, mode])

        UserDefaults.standard.set(mode, forKey: Self.savedKey)
        saved = true
        ble.log("크라운 설정: \(crownMode.displayName) (mode=\(mode)) → 슬롯 3,4,7,8 + complications 전송")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }
}
