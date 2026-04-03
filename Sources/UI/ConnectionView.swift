import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Connection status
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                    Text(ble.connectionState.rawValue)
                        .font(.headline)
                }
                .padding()

                // Last button event
                if let event = ble.lastButtonEvent {
                    VStack {
                        Text("마지막 버튼 이벤트")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(event.buttonName) — \(event.eventName)")
                            .font(.title3)
                            .bold()
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                Spacer()

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
                default:
                    ProgressView()
                }
            }
            .padding()
            .navigationTitle("Kronaby")
        }
    }

    private var statusColor: Color {
        switch ble.connectionState {
        case .connected: return .green
        case .scanning, .connecting, .handshaking: return .orange
        case .disconnected: return .red
        }
    }
}
