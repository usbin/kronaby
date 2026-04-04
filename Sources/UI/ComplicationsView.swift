import SwiftUI
import HealthKit

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
    @State private var stepGoal: Int = 10000
    @State private var stepLength: Int = 75 // cm
    @State private var todaySteps: Int = 0
    @State private var healthKitAuthorized = false
    @State private var stepGoalSaved = false

    private static let savedKey = "kronaby_crown_mode"
    private static let stepGoalKey = "kronaby_step_goal"
    private static let stepLengthKey = "kronaby_step_length"
    private static let crownSlotId = 4 // Slot.TopPusher (Crown)

    private let healthStore = HKHealthStore()

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

                // MARK: - 걸음수 목표
                Section("걸음수 목표") {
                    Stepper("목표: \(stepGoal.formatted()) 걸음", value: $stepGoal, in: 1000...50000, step: 1000)

                    Stepper("보폭: \(stepLength) cm", value: $stepLength, in: 40...120, step: 5)

                    Button("목표 시계에 전송") {
                        applyStepGoal()
                    }
                    .frame(maxWidth: .infinity)

                    if stepGoalSaved {
                        Text("목표 전송 완료!")
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                    }
                }

                // MARK: - 오늘 걸음수 달성률
                Section("오늘 걸음수") {
                    if healthKitAuthorized {
                        HStack {
                            Text("걸음수")
                            Spacer()
                            Text("\(todaySteps.formatted()) / \(stepGoal.formatted())")
                                .foregroundStyle(.secondary)
                        }

                        let progress = stepGoal > 0 ? min(1.0, Double(todaySteps) / Double(stepGoal)) : 0
                        ProgressView(value: progress)
                            .tint(progress >= 1.0 ? .green : .blue)

                        HStack {
                            Text("달성률")
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(.headline)
                                .foregroundStyle(progress >= 1.0 ? .green : .primary)
                        }

                        Button("새로고침") {
                            fetchTodaySteps()
                        }
                        .font(.caption)
                    } else {
                        Button("건강 데이터 접근 허용") {
                            requestHealthKit()
                        }
                        Text("HealthKit 권한이 필요합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("디버그") {
                    Button("map_settings (Array 인코딩)") {
                        // map_cmd처럼 Array [cmd_id, batch] 로 전송
                        if let cmdId = ble.commandMap["map_settings"] {
                            let data = KronabyProtocol().encodeArray([cmdId, 0])
                            if let c = ble.commandChar {
                                ble.peripheral?.writeValue(data, for: c, type: .withResponse)
                                ble.log("map_settings Array: \(data.map { String(format: "%02X", $0) }.joined())")
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if let p = ble.peripheral, let c = ble.commandChar {
                                    p.readValue(for: c)
                                    ble.log("map_settings read")
                                }
                            }
                        }
                    }
                    Button("settings read (공식앱 설정 후)") {
                        // 공식 앱이 설정한 후 settings 값을 읽기
                        if let cmdId = ble.commandMap["settings"] {
                            let data = KronabyProtocol().encodeArray([cmdId, 0])
                            if let c = ble.commandChar {
                                ble.peripheral?.writeValue(data, for: c, type: .withResponse)
                                ble.log("settings Array: \(data.map { String(format: "%02X", $0) }.joined())")
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if let p = ble.peripheral, let c = ble.commandChar {
                                    p.readValue(for: c)
                                    ble.log("settings read")
                                }
                            }
                        }
                    }
                    Button("ComplicationId로 시도") {
                        // ComplicationId: 0=Invalid, 3=Date, 5=Steps, 6=Battery
                        let cid = 3 // Date
                        // complications 배치 (ComplicationId)
                        ble.sendCommand(name: "complications", value: [cid])
                        ble.log("complications([\(cid)]) 전송")

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            ble.sendCommand(name: "complications", value: [cid, 0, 0, 0, 0, 0])
                            ble.log("complications([\(cid),0,0,0,0,0]) 전송")
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            // set_complication_mode도 ComplicationId로
                            for slot in [3, 4, 7, 8] {
                                ble.sendCommand(name: "set_complication_mode", value: [slot, cid])
                            }
                            ble.log("set_complication_mode slots 3,4,7,8 with cid=\(cid)")
                        }
                    }
                    Button("단일 정수로 시도") {
                        // set_complication_mode이 배열이 아니라 단일 int일 수도
                        ble.sendCommand(name: "set_complication_mode", value: 0)
                        ble.log("set_complication_mode(0) 단일 int")

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            ble.sendCommand(name: "set_complication_mode", value: 3)
                            ble.log("set_complication_mode(3) 단일 int")
                        }
                    }
                }
            }
            .navigationTitle("크라운 설정")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let raw = UserDefaults.standard.integer(forKey: Self.savedKey)
                crownMode = CrownMode(rawValue: raw) ?? .date

                let savedGoal = UserDefaults.standard.integer(forKey: Self.stepGoalKey)
                if savedGoal > 0 { stepGoal = savedGoal }
                let savedLength = UserDefaults.standard.integer(forKey: Self.stepLengthKey)
                if savedLength > 0 { stepLength = savedLength }

                // HealthKit 상태 확인 및 걸음수 조회
                checkHealthKitAuth()

                // comp 관련 명령 검색
                let compCmds = ble.commandMap.filter { $0.key.contains("comp") || $0.key.contains("face") || $0.key.contains("dash") || $0.key.contains("crown") || $0.key.contains("magic") }
                ble.log("comp 관련 명령: \(compCmds)")
                ble.log("전체 commandMap (\(ble.commandMap.count)개): \(ble.commandMap.sorted(by: { $0.value < $1.value }).map { "\($0.value):\($0.key)" })")
            }
        }
    }

    private func apply() {
        let mode = crownMode.rawValue

        // 1. config_base — 펌웨어에 기본 설정 전달 (complication 모드 전환 전제조건)
        ble.sendCommand(name: "config_base", value: [1, 0])
        ble.log("config_base([1, 0]) 전송")

        // 2. 약간의 딜레이 후 complication 명령 전송
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            // complications 배치 (6슬롯 전체)
            ble.sendCommand(name: "complications", value: [mode, mode, mode, mode, mode, mode])

            // set_complication_mode 개별 슬롯
            for slot in [3, 4, 7, 8] {
                ble.sendCommand(name: "set_complication_mode", value: [slot, mode])
            }

            UserDefaults.standard.set(mode, forKey: Self.savedKey)
            saved = true
            ble.log("크라운 설정: \(crownMode.displayName) (mode=\(mode))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
        }
    }

    // MARK: - Step Goal

    private func applyStepGoal() {
        UserDefaults.standard.set(stepGoal, forKey: Self.stepGoalKey)
        UserDefaults.standard.set(stepLength, forKey: Self.stepLengthKey)

        // steps_target (cmd 58) — 걸음수 목표 전송
        ble.sendCommand(name: "steps_target", value: stepGoal)
        ble.log("steps_target(\(stepGoal)) 전송")

        // config_base — [시간해상도(분), 만보기활성화(1)]
        ble.sendCommand(name: "config_base", value: [1, 1])
        ble.log("config_base([1, 1]) — 만보기 활성화")

        stepGoalSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { stepGoalSaved = false }
    }

    // MARK: - HealthKit

    private func checkHealthKitAuth() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let status = healthStore.authorizationStatus(for: stepType)
        if status == .sharingAuthorized {
            healthKitAuthorized = true
            fetchTodaySteps()
        }
    }

    private func requestHealthKit() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        healthStore.requestAuthorization(toShare: nil, read: [stepType]) { success, _ in
            DispatchQueue.main.async {
                // HealthKit은 read 권한 거부해도 success=true 반환할 수 있음
                // 실제 데이터 조회로 확인
                healthKitAuthorized = true
                fetchTodaySteps()
            }
        }
    }

    private func fetchTodaySteps() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            DispatchQueue.main.async {
                let steps = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                todaySteps = Int(steps)
            }
        }
        healthStore.execute(query)
    }
}
