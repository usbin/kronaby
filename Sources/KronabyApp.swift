import SwiftUI

@main
struct KronabyApp: App {
    @StateObject private var bleManager = BLEManager()
    @StateObject private var actionManager = ButtonActionManager()
    @StateObject private var locationRecorder = LocationRecorder()

    var body: some Scene {
        WindowGroup {
            ConnectionView()
                .environmentObject(bleManager)
                .environmentObject(actionManager)
                .environmentObject(locationRecorder)
                .onAppear {
                    actionManager.locationRecorder = locationRecorder
                    locationRecorder.onRecorded = { [weak bleManager] in
                        bleManager?.sendCommand(name: "vibrator_start", value: [150])
                    }
                }
                .onReceive(bleManager.$lastButtonEvent) { event in
                    guard let event = event else { return }
                    if event.eventType == 11 {
                        actionManager.handleFindMyPhone()
                    } else {
                        actionManager.handleButtonEvent(button: event.button, event: event.eventType)
                    }
                }
        }
    }
}
