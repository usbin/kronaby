import SwiftUI
import UserNotifications

@main
struct KeepnabyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var bleManager = BLEManager()
    @StateObject private var actionManager = ButtonActionManager()
    @StateObject private var locationRecorder = LocationRecorder()
    @StateObject private var notificationMappingManager = NotificationMappingManager()

    var body: some Scene {
        WindowGroup {
            ConnectionView()
                .environmentObject(bleManager)
                .environmentObject(actionManager)
                .environmentObject(locationRecorder)
                .environmentObject(notificationMappingManager)
                .onAppear {
                    actionManager.locationRecorder = locationRecorder
                    actionManager.bleManager = bleManager
                    locationRecorder.onRecorded = { [weak bleManager] in
                        bleManager?.sendCommand(name: "vibrator_start", value: [150])
                    }
                    // 10분 주기 keepAlive — ANCS 설정 재전송
                    bleManager.onKeepAlive = { [weak bleManager, weak notificationMappingManager] in
                        guard let ble = bleManager else { return }
                        let crownMode = UserDefaults.standard.integer(forKey: "kronaby_crown_mode")
                        ble.sendCommand(name: "complications", value: [5, crownMode, 18])
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            notificationMappingManager?.applyToWatch(ble: ble)
                        }
                    }
                    // 연결 완료 시 모든 설정 자동 재전송
                    bleManager.onConnected = { [weak bleManager, weak notificationMappingManager] in
                        guard let ble = bleManager else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            // 1. vibrator_config — 진동 패턴 (펌웨어가 ANCS 알림 시 사용)
                            ble.sendCommand(name: "vibrator_config", value: [8, 50, 25, 80, 25, 35, 25, 35, 25, 40, 25, 90])
                            ble.sendCommand(name: "vibrator_config", value: [9, 31, 30, 61, 30, 110, 300, 31, 30, 61, 30, 110])
                            ble.sendCommand(name: "vibrator_config", value: [10, 31, 30, 190, 300, 50, 30, 90, 300, 50, 30, 90])
                            ble.log("재전송: vibrator_config 패턴 8/9/10")

                            // 2. 크라운 + ANCS 바늘 활성화 (세 번째 값 18이 핵심!)
                            let crownMode = UserDefaults.standard.integer(forKey: "kronaby_crown_mode")
                            ble.sendCommand(name: "complications", value: [5, crownMode, 18])
                            ble.log("재전송: complications([5, \(crownMode), 18])")

                            // 2.5. settings — 공식 앱이 초기 설정 시 전송 (BLE 캡처에서 발견)
                            ble.sendCommand(name: "settings", value: [154: true, 176: 1, 178: 70, 174: false, 160: 1100] as [Int: Any])
                            ble.log("재전송: settings")

                            // 3. 걸음수 목표
                            let stepGoal = UserDefaults.standard.integer(forKey: "kronaby_step_goal_v2")
                            if stepGoal > 0 {
                                ble.sendCommand(name: "steps_target", value: stepGoal)
                                ble.sendCommand(name: "config_base", value: [1, 1])
                                ble.log("재전송: steps_target=\(stepGoal)")
                            }

                            // 4. ANCS 필터 + alert_assign + remote_data
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                notificationMappingManager?.applyToWatch(ble: ble)
                                ble.log("재전송: vibrator_config + alert_assign + ANCS 필터 + remote_data")
                            }
                        }
                    }
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                }
                .onReceive(bleManager.$lastButtonEvent) { event in
                    guard let event = event else { return }
                    // 크라운 3초 홀드(코드 11)는 Nord에서 미동작 — 무시
                    if event.eventType == 11 { return }
                    actionManager.handleButtonEvent(button: event.button, event: event.eventType)
                }
        }
    }
}

// MARK: - AppDelegate (앱 종료 감지)

class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        // 앱 종료 시 로컬 알림 예약
        let content = UNMutableNotificationContent()
        content.title = "Keepnaby 연결 끊김"
        content.body = "앱이 종료되어 시계 연결이 끊겼습니다. 탭하여 앱을 다시 실행하세요."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "app_terminated", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
