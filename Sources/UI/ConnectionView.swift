import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var showHelp = false
    @State private var showLog = true
    @State private var showCalibration = false
    @State private var showTimeSetting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Connection status
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                    Text(ble.connectionState.rawValue)
                        .font(.headline)
                }

                // Last button event
                if let event = ble.lastButtonEvent {
                    Text("\(event.buttonName) — \(event.eventName)")
                        .font(.title3)
                        .bold()
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

                // Connected: show tools
                if ble.connectionState == .connected {
                    HStack(spacing: 12) {
                        Button {
                            showCalibration = true
                        } label: {
                            Label("영점 조정", systemImage: "dial.low")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            showTimeSetting = true
                        } label: {
                            Label("시각 설정", systemImage: "clock")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Scan results
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

                // Debug log
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

                // Action buttons
                switch ble.connectionState {
                case .disconnected:
                    Button("스캔 시작") { ble.startScan() }
                        .buttonStyle(.borderedProminent)
                case .scanning:
                    Button("스캔 중지") { ble.stopScan() }
                        .buttonStyle(.bordered)
                case .connected:
                    HStack {
                        Button("연결 해제") { ble.disconnect() }
                            .buttonStyle(.bordered)
                        Button("기기 삭제") { ble.forgetDevice() }
                            .buttonStyle(.bordered)
                            .tint(.red)
                    }
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
                trailing: Button(action: { showHelp = true }) {
                    Image(systemName: "questionmark.circle")
                }
            )
            .alert("시계 페어링 초기화", isPresented: $showHelp) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("시계가 검색되지 않으면 기존 페어링을 먼저 삭제해야 합니다.\n\n상단 + 하단 푸셔를 동시에 길게 누르면 시계가 3회 진동하며 페어링이 초기화됩니다.\n\n초기화 후 다시 스캔하세요.")
            }
            .sheet(isPresented: $showCalibration) {
                CalibrationView(isPresented: $showCalibration)
                    .environmentObject(ble)
            }
            .sheet(isPresented: $showTimeSetting) {
                TimeSettingView(isPresented: $showTimeSetting)
                    .environmentObject(ble)
            }
        }
    }

    private var statusColor: Color {
        switch ble.connectionState {
        case .connected: return .green
        case .scanning, .connecting, .handshaking: return .orange
        case .disconnected: return .red
        case .bluetoothOff: return .gray
        }
    }
}
