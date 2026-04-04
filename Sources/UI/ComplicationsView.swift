import SwiftUI

// APK 디컴파일 기준 크라운 complication 모드값
// set_complication_mode: [slotId=8(crown), mode]
enum CrownMode: Int, CaseIterable, Identifiable {
    case date = 0
    case timer = 1
    case stopwatch = 2
    case remote = 3
    case dice = 4
    case stoptime = 5
    case none = 6

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .date: return "날짜 확인"
        case .timer: return "타이머"
        case .stopwatch: return "스톱워치"
        case .remote: return "리모트"
        case .dice: return "주사위"
        case .stoptime: return "스톱타임"
        case .none: return "없음"
        }
    }
}

struct ComplicationsView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var crownMode: CrownMode = .date
    @State private var saved = false

    private static let savedKey = "kronaby_crown_mode"
    private static let crownSlotId = 8 // Slot.MagicKey

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
                    .buttonStyle(.borderedProminent)
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
        // set_complication_mode: [slotId, mode]
        ble.sendCommand(name: "set_complication_mode", value: [Self.crownSlotId, crownMode.rawValue])
        UserDefaults.standard.set(crownMode.rawValue, forKey: Self.savedKey)
        saved = true
        ble.log("크라운 설정: \(crownMode.displayName) → set_complication_mode([\(Self.crownSlotId), \(crownMode.rawValue)])")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }
}
