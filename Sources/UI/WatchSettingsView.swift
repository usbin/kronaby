import SwiftUI

enum TriggerValue: Int, CaseIterable, Identifiable {
    case none = 0
    case camera = 1
    case mediaControl = 2
    case mute = 3

    var id: Int { rawValue }
    var displayName: String {
        switch self {
        case .none: return "없음"
        case .camera: return "카메라"
        case .mediaControl: return "미디어 제어"
        case .mute: return "음소거"
        }
    }
}

struct WatchSettingsView: View {
    @EnvironmentObject var ble: BLEManager

    @State private var topTrigger: TriggerValue = .none
    @State private var bottomTrigger: TriggerValue = .none
    @State private var dndEnabled = false
    @State private var dndStartHour = 22
    @State private var dndStartMin = 0
    @State private var dndEndHour = 7
    @State private var dndEndMin = 0
    @State private var worldTimeHour = 0
    @State private var worldTimeMin = 0
    @State private var vibStrength: Int = 0
    @State private var stepGoal: Int = 4000

    private static let triggerTopKey = "kronaby_trigger_top"
    private static let triggerBottomKey = "kronaby_trigger_bottom"
    private static let dndEnabledKey = "kronaby_dnd_enabled"
    private static let dndStartHKey = "kronaby_dnd_start_h"
    private static let dndStartMKey = "kronaby_dnd_start_m"
    private static let dndEndHKey = "kronaby_dnd_end_h"
    private static let dndEndMKey = "kronaby_dnd_end_m"
    private static let worldTimeHKey = "kronaby_wt_hour"
    private static let worldTimeMKey = "kronaby_wt_min"
    private static let vibStrengthKey = "kronaby_vib_strength"
    private static let stepGoalKey = "kronaby_step_goal_v2"

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - HID 트리거
                Section("HID 트리거") {
                    Picker("상단 버튼", selection: $topTrigger) {
                        ForEach(TriggerValue.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("하단 버튼", selection: $bottomTrigger) {
                        ForEach(TriggerValue.allCases) { Text($0.displayName).tag($0) }
                    }
                    applyButton {
                        ble.sendCommand(name: "triggers", value: [topTrigger.rawValue, bottomTrigger.rawValue])
                        save(Self.triggerTopKey, topTrigger.rawValue)
                        save(Self.triggerBottomKey, bottomTrigger.rawValue)
                        ble.log("triggers: [\(topTrigger.displayName), \(bottomTrigger.displayName)]")
                    }
                    Text("버튼 매핑의 앱 액션과 별개로 작동합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: - 방해금지
                Section("방해금지 (DND)") {
                    Toggle("활성화", isOn: $dndEnabled)

                    if dndEnabled {
                        HStack {
                            Text("시작")
                            Spacer()
                            Picker("시", selection: $dndStartHour) {
                                ForEach(0..<24, id: \.self) { Text("\($0)시") }
                            }.pickerStyle(.menu)
                            Picker("분", selection: $dndStartMin) {
                                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d분", $0)) }
                            }.pickerStyle(.menu)
                        }
                        HStack {
                            Text("종료")
                            Spacer()
                            Picker("시", selection: $dndEndHour) {
                                ForEach(0..<24, id: \.self) { Text("\($0)시") }
                            }.pickerStyle(.menu)
                            Picker("분", selection: $dndEndMin) {
                                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d분", $0)) }
                            }.pickerStyle(.menu)
                        }
                    }
                    applyButton {
                        ble.sendCommand(name: "stillness", value: [
                            dndEnabled ? 1 : 0, dndStartHour, dndStartMin, dndEndHour, dndEndMin
                        ])
                        save(Self.dndEnabledKey, dndEnabled)
                        save(Self.dndStartHKey, dndStartHour)
                        save(Self.dndStartMKey, dndStartMin)
                        save(Self.dndEndHKey, dndEndHour)
                        save(Self.dndEndMKey, dndEndMin)
                        ble.log("DND: \(dndEnabled ? "ON" : "OFF") \(dndStartHour):\(String(format: "%02d", dndStartMin))~\(dndEndHour):\(String(format: "%02d", dndEndMin))")
                    }
                }

                // MARK: - 세계시간
                Section("세계시간 (2nd Timezone)") {
                    HStack {
                        Text("UTC 오프셋")
                        Spacer()
                        Picker("시", selection: $worldTimeHour) {
                            ForEach(-12...14, id: \.self) { h in
                                Text("\(h >= 0 ? "+" : "")\(h)시간").tag(h)
                            }
                        }.pickerStyle(.menu)
                        Picker("분", selection: $worldTimeMin) {
                            ForEach([0, 30, 45], id: \.self) { m in
                                Text("\(m)분").tag(m)
                            }
                        }.pickerStyle(.menu)
                    }
                    applyButton {
                        ble.sendCommand(name: "timezone2", value: [worldTimeHour, worldTimeMin])
                        save(Self.worldTimeHKey, worldTimeHour)
                        save(Self.worldTimeMKey, worldTimeMin)
                        ble.log("timezone2: UTC\(worldTimeHour >= 0 ? "+" : "")\(worldTimeHour):\(String(format: "%02d", worldTimeMin))")
                    }
                }

                // MARK: - 진동 세기
                Section("진동 세기") {
                    Picker("세기", selection: $vibStrength) {
                        Text("일반").tag(0)
                        Text("강하게").tag(1)
                    }
                    .pickerStyle(.segmented)
                    applyButton {
                        if vibStrength == 1 {
                            ble.sendCommand(name: "vibrator_config", value: [8, 600])
                        } else {
                            ble.sendCommand(name: "vibrator_config", value: [8, 150])
                        }
                        save(Self.vibStrengthKey, vibStrength)
                        ble.log("vibrator_config: \(vibStrength == 1 ? "강하게" : "일반")")
                    }
                }

                // MARK: - 걸음수
                Section("걸음수") {
                    HStack {
                        Text("현재")
                        Spacer()
                        if let steps = ble.stepsInfo {
                            Text("\(steps[0])걸음")
                                .font(.headline)
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }
                        Button("새로고침") { ble.requestSteps() }
                            .font(.caption)
                    }
                    Stepper("목표: \(stepGoal.formatted())걸음", value: $stepGoal, in: 1000...50000, step: 1000)
                    applyButton {
                        ble.sendCommand(name: "steps_target", value: stepGoal)
                        ble.sendCommand(name: "config_base", value: [1, 1])
                        save(Self.stepGoalKey, stepGoal)
                        ble.log("steps_target: \(stepGoal)")
                    }
                }
            }
            .navigationTitle("시계 설정")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadSettings() }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func applyButton(action: @escaping () -> Void) -> some View {
        Button("적용") { action() }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func loadSettings() {
        topTrigger = TriggerValue(rawValue: UserDefaults.standard.integer(forKey: Self.triggerTopKey)) ?? .none
        bottomTrigger = TriggerValue(rawValue: UserDefaults.standard.integer(forKey: Self.triggerBottomKey)) ?? .none
        dndEnabled = UserDefaults.standard.bool(forKey: Self.dndEnabledKey)
        dndStartHour = UserDefaults.standard.object(forKey: Self.dndStartHKey) as? Int ?? 22
        dndStartMin = UserDefaults.standard.integer(forKey: Self.dndStartMKey)
        dndEndHour = UserDefaults.standard.object(forKey: Self.dndEndHKey) as? Int ?? 7
        dndEndMin = UserDefaults.standard.integer(forKey: Self.dndEndMKey)
        worldTimeHour = UserDefaults.standard.integer(forKey: Self.worldTimeHKey)
        worldTimeMin = UserDefaults.standard.integer(forKey: Self.worldTimeMKey)
        vibStrength = UserDefaults.standard.integer(forKey: Self.vibStrengthKey)
        let savedGoal = UserDefaults.standard.integer(forKey: Self.stepGoalKey)
        if savedGoal > 0 { stepGoal = savedGoal }
    }
}
