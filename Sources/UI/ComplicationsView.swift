import SwiftUI
import HealthKit

// 크라운 complication 모드 (실기기 검증 완료)
// complications([5, mode, 18]) 형식으로 전송
enum CrownMode: Int, CaseIterable, Identifiable {
    case date = 0         // 날짜 — 검증 완료
    case secondTime = 1   // 세계시간 — 검증 완료
    case steps = 4        // 걸음수 — 검증 완료
    case stopwatch = 14   // 스톱워치 — 검증 완료
    case none = 15        // 없음

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .date: return "날짜 확인"
        case .secondTime: return "세계시간"
        case .steps: return "걸음수"
        case .stopwatch: return "스톱워치"
        case .none: return "없음"
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

                Section {
                    Text("세계시간은 시계 설정에서 UTC 오프셋을 지정하세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

                // commandMap 로그 비활성화 (글자수 제한 문제)
            }
        }
    }

    private func apply() {
        let mode = crownMode.rawValue

        // 검증된 형식: complications([5, mode, 18])
        ble.sendCommand(name: "complications", value: [5, mode, 18])
        UserDefaults.standard.set(mode, forKey: Self.savedKey)
        saved = true
        ble.log("크라운 설정: \(crownMode.displayName) → complications([5, \(mode), 18])")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
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
