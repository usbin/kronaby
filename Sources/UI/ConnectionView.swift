import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var showHelp = false
    @State private var showLog = true

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

                // Scan results
                if !ble.discoveredPeripherals.isEmpty {
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
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(ble.debugLog.enumerated()), id: \.offset) { i, line in
                                    Text(line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .id(i)
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                        .frame(maxHeight: 250)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .onChange(of: ble.debugLog.count) {
                            if let last = ble.debugLog.indices.last {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
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
                    Button("연결 해제") { ble.disconnect() }
                        .buttonStyle(.bordered)
                        .tint(.red)
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
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showLog.toggle() } label: {
                        Image(systemName: showLog ? "terminal.fill" : "terminal")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showHelp = true } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
            }
            .alert("시계 페어링 초기화", isPresented: $showHelp) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("시계가 검색되지 않으면 기존 페어링을 먼저 삭제해야 합니다.\n\n상단 + 하단 푸셔를 동시에 길게 누르면 시계가 3회 진동하며 페어링이 초기화됩니다.\n\n초기화 후 다시 스캔하세요.")
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
