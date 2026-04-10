import BackgroundTasks
import UIKit

/// BGAppRefreshTask로 백그라운드에서 주기적 BLE sync를 실행.
/// Timer는 앱이 suspended되면 동작하지 않으므로, 이 스케줄러가 보완.
final class BackgroundSyncScheduler {
    static let shared = BackgroundSyncScheduler()
    static let taskIdentifier = "com.usbin.kronaby.sync"

    private init() {}

    /// AppDelegate.didFinishLaunching에서 호출 — BGTask 핸들러 등록
    func registerTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handleAppRefresh(refreshTask)
        }
    }

    /// 다음 BGAppRefreshTask 스케줄 (iOS가 적절한 시점에 실행)
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        // 최소 30분 후 (iOS가 실제 실행 시점은 시스템이 결정)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BackgroundSync] 스케줄 실패: \(error)")
        }
    }

    private func handleAppRefresh(_ task: BGAppRefreshTask) {
        // BLEManager는 메인스레드에서 접근
        DispatchQueue.main.async {
            // BLEManager 인스턴스를 NotificationCenter로 알림
            NotificationCenter.default.post(name: .backgroundSyncRequested, object: nil)
        }
        task.setTaskCompleted(success: true)
    }
}

extension Notification.Name {
    static let backgroundSyncRequested = Notification.Name("backgroundSyncRequested")
}
