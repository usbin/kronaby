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
                    // 연결 완료 시 모든 설정 자동 재전송
                    bleManager.onConnected = { [weak bleManager, weak notificationMappingManager] in
                        guard let ble = bleManager else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            // 1. 크라운 설정
                            let crownMode = UserDefaults.standard.integer(forKey: "kronaby_crown_mode")
                            ble.sendCommand(name: "complications", value: [5, crownMode, 18])
                            ble.log("재전송: 크라운 mode=\(crownMode)")

                            // 2. 걸음수 목표
                            let stepGoal = UserDefaults.standard.integer(forKey: "kronaby_step_goal_v2")
                            if stepGoal > 0 {
                                ble.sendCommand(name: "steps_target", value: stepGoal)
                                ble.sendCommand(name: "config_base", value: [1, 1])
                                ble.log("재전송: steps_target=\(stepGoal)")
                            }

                            // 3. ANCS 알림 필터 (alert_assign 없이)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                notificationMappingManager?.applyToWatch(ble: ble)
                                ble.log("재전송: ANCS 필터")

                                // 4. 알람 슬롯만 설정 (ANCS 필터 후)
                                let alarmSlot = UserDefaults.standard.integer(forKey: "kronaby_alarm_slot")
                                if alarmSlot > 0 {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        ble.sendCommand(name: "alert_assign", value: [alarmSlot: 1] as [Int: Int])
                                        ble.log("재전송: alert_assign slot=\(alarmSlot)")
                                    }
                                }
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
