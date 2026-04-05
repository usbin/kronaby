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
                    applyButton(id: "trigger") {
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
                    applyButton(id: "dnd") {
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
                    applyButton(id: "tz2") {
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
                    applyButton(id: "vib") {
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
                    applyButton(id: "steps") {
                        ble.sendCommand(name: "steps_target", value: stepGoal)
                        ble.sendCommand(name: "config_base", value: [1, 1])
                        save(Self.stepGoalKey, stepGoal)
                        ble.log("steps_target: \(stepGoal)")
                    }
                }
                // MARK: - stepper_goto 테스트
                Section("stepper_goto 테스트") {
                    Text("모터 0=시침, 1=분침 (추정)\n위치값과 시계 눈금의 매핑을 확인하세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("모터")
                        Picker("", selection: $testMotor) {
                            Text("0 (시침?)").tag(0)
                            Text("1 (분침?)").tag(1)
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack {
                        Text("위치: \(testPosition)")
                        Slider(value: Binding(
                            get: { Double(testPosition) },
                            set: { testPosition = Int($0) }
                        ), in: 0...180, step: 1)
                    }

                    HStack(spacing: 8) {
                        Button("이동") {
                            ble.sendCommand(name: "stepper_goto", value: [testMotor, testPosition])
                            ble.log("stepper_goto([\(testMotor), \(testPosition)])")
                        }
                        Button("0") {
                            testPosition = 0
                            ble.sendCommand(name: "stepper_goto", value: [testMotor, 0])
                            ble.log("stepper_goto([\(testMotor), 0])")
                        }
                        Button("15") {
                            testPosition = 15
                            ble.sendCommand(name: "stepper_goto", value: [testMotor, 15])
                            ble.log("stepper_goto([\(testMotor), 15])")
                        }
                        Button("30") {
                            testPosition = 30
                            ble.sendCommand(name: "stepper_goto", value: [testMotor, 30])
                            ble.log("stepper_goto([\(testMotor), 30])")
                        }
                        Button("60") {
                            testPosition = 60
                            ble.sendCommand(name: "stepper_goto", value: [testMotor, 60])
                            ble.log("stepper_goto([\(testMotor), 60])")
                        }
                    }
                    .font(.caption)

                    Button("datetime로 복귀") {
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
                        ble.sendCommand(name: "datetime", value: [c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, kronabyDay])
                        ble.log("datetime 복귀")
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("시계 설정")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadSettings() }
        }
    }

    @State private var testMotor = 0
    @State private var testPosition = 0

    // MARK: - Helpers

    @State private var lastApplied: String?

    @ViewBuilder
    private func applyButton(id: String = UUID().uuidString, action: @escaping () -> Void) -> some View {
        HStack {
            if lastApplied == id {
                Text("✓")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            Button("적용") {
                action()
                // 시계 진동 피드백
                ble.sendCommand(name: "vibrator_start", value: [150])
                // UI 피드백
                lastApplied = id
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if lastApplied == id { lastApplied = nil }
                }
            }
            .font(.caption)
        }
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
