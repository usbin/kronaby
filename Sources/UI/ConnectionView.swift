import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var actionManager: ButtonActionManager
    @EnvironmentObject var locationRecorder: LocationRecorder
    @EnvironmentObject var notificationMappingManager: NotificationMappingManager
    @State private var showHelp = false
    @State private var showLog = false
    @State private var showForgetConfirm = false
    @State private var showCalibration = false
    @State private var showTimeSetting = false
    @State private var showButtonMapping = false
    @State private var showComplications = false
    @State private var showLocationHistory = false
    @State private var showNotificationMapping = false
    @State private var showAlarm = false
    @State private var showWatchSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // MARK: - 상태바 (연결 + 배터리 + 걸음수)
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                    Text(ble.connectionState.rawValue)
                        .font(.headline)
                    Spacer()
                    if let steps = ble.stepsInfo {
                        Image(systemName: "figure.walk")
                            .font(.caption)
                        Text("\(steps[0])")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let bat = ble.batteryInfo {
                        Image(systemName: batteryIcon(bat[0]))
                            .foregroundStyle(bat[0] <= 15 ? .red : .green)
                        Text("\(bat[0])%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 마지막 버튼 이벤트
                if let event = ble.lastButtonEvent {
                    Text("\(event.buttonName) — \(event.eventName)")
                        .font(.title3)
                        .bold()
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

                if ble.connectionState == .connected {
                    ScrollView {
                        VStack(spacing: 16) {
                            // MARK: - 자주 사용 (알람 + 위치)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("자주 사용")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    menuButton("무음 알람", icon: "alarm") { showAlarm = true }
                                    menuButton("위치 기록", icon: "mappin.and.ellipse") { showLocationHistory = true }
                                }
                            }

                            // MARK: - 입출력 매핑
                            VStack(alignment: .leading, spacing: 6) {
                                Text("입출력 매핑")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    menuButton("크라운", icon: "crown") { showComplications = true }
                                    menuButton("버튼", icon: "hand.tap") { showButtonMapping = true }
                                    menuButton("알림", icon: "bell.badge") { showNotificationMapping = true }
                                }
                            }

                            // MARK: - 정보
                            VStack(alignment: .leading, spacing: 6) {
                                Text("정보")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    menuButton("배터리", icon: "battery.100") { ble.requestBattery() }
                                    menuButton("걸음수", icon: "figure.walk") { ble.requestSteps() }
                                }
                            }

                            // MARK: - 설정 (접힘)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("설정")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    menuButton("시계 설정", icon: "gearshape") { showWatchSettings = true }
                                    menuButton("영점 조정", icon: "dial.low") { showCalibration = true }
                                    menuButton("시각 설정", icon: "clock") { showTimeSetting = true }
                                }
                            }
                        }
                    }
                }

                // 스캔 결과
                if !ble.discoveredPeripherals.isEmpty && ble.connectionState != .connected {
                    List(ble.discoveredPeripherals, id: \.identifier) { peripheral in
                        Button {
                            ble.connect(to: peripheral)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(peripheral.name ?? "알 수 없는 기기")
                                    .font(.body)
                                Text(peripheral.identifier.uuidString)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: 150)
                }

                // 디버그 로그
                if showLog {
                    VStack(spacing: 4) {
                        HStack {
                            Text("디버그 로그")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("복사") {
                                UIPasteboard.general.string = ble.debugLog.joined(separator: "\n")
                            }
                            .font(.caption)
                            Button("지우기") {
                                ble.debugLog.removeAll()
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 8)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(ble.debugLog.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                        .frame(maxHeight: 200)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }

                Spacer()

                // 하단 액션
                switch ble.connectionState {
                case .disconnected:
                    Button("스캔 시작") { ble.startScan() }
                        .buttonStyle(.borderedProminent)
                case .scanning:
                    Button("스캔 중지") { ble.stopScan() }
                        .buttonStyle(.bordered)
                case .connected:
                    EmptyView()
                case .bluetoothOff:
                    Text("블루투스를 켜주세요")
                        .foregroundStyle(.red)
                case .connecting, .handshaking:
                    VStack(spacing: 8) {
                        ProgressView()
                        Button("취소") { ble.disconnect() }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .navigationTitle("Kronaby")
            .navigationBarItems(
                leading: Button(action: { showLog.toggle() }) {
                    Image(systemName: showLog ? "terminal.fill" : "terminal")
                },
                trailing: Menu {
                    Button { showHelp = true } label: {
                        Label("페어링 도움말", systemImage: "questionmark.circle")
                    }
                    if ble.connectionState == .connected {
                        Divider()
                        Button { ble.disconnect() } label: {
                            Label("연결 해제", systemImage: "wifi.slash")
                        }
                        Button(role: .destructive) { showForgetConfirm = true } label: {
                            Label("기기 삭제", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            )
            .alert("시계 페어링 초기화", isPresented: $showHelp) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("시계가 검색되지 않으면 기존 페어링을 먼저 삭제해야 합니다.\n\n1. iPhone 설정 → 블루투스 → Kronaby 옆 (i) → 이 기기 지우기\n2. 시계 상단 + 하단 푸셔를 동시에 길게 누름 → 3회 진동 후 바늘이 회전하면 페어링 모드\n3. 앱에서 스캔 시작")
            }
            .alert("기기 삭제", isPresented: $showForgetConfirm) {
                Button("삭제", role: .destructive) { ble.forgetDevice() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("저장된 연결 정보가 모두 삭제됩니다.\n다시 연결하려면 시계를 페어링 모드로 전환 후 스캔해야 합니다.")
            }
            .sheet(isPresented: $showCalibration) {
                CalibrationView(isPresented: $showCalibration)
                    .environmentObject(ble)
            }
            .sheet(isPresented: $showTimeSetting) {
                TimeSettingView(isPresented: $showTimeSetting)
                    .environmentObject(ble)
            }
            .sheet(isPresented: $showButtonMapping) {
                ButtonMappingView()
                    .environmentObject(actionManager)
            }
            .sheet(isPresented: $showComplications) {
                ComplicationsView()
                    .environmentObject(ble)
            }
            .sheet(isPresented: $showLocationHistory) {
                LocationHistoryView()
                    .environmentObject(locationRecorder)
            }
            .sheet(isPresented: $showNotificationMapping) {
                NotificationMappingView()
                    .environmentObject(notificationMappingManager)
                    .environmentObject(ble)
            }
            .sheet(isPresented: $showAlarm) {
                AlarmView()
                    .environmentObject(ble)
            }
            .sheet(isPresented: $showWatchSettings) {
                WatchSettingsView()
                    .environmentObject(ble)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func menuButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .foregroundStyle(.primary)
    }

    private var statusColor: Color {
        switch ble.connectionState {
        case .connected: return .green
        case .scanning, .connecting, .handshaking: return .orange
        case .disconnected: return .red
        case .bluetoothOff: return .gray
        }
    }

    private func batteryIcon(_ percent: Int) -> String {
        if percent > 75 { return "battery.100" }
        if percent > 50 { return "battery.75" }
        if percent > 25 { return "battery.50" }
        if percent > 10 { return "battery.25" }
        return "battery.0"
    }
}
