import SwiftUI

struct NotificationMappingView: View {
    @EnvironmentObject var mappingManager: NotificationMappingManager
    @EnvironmentObject var ble: BLEManager
    @State private var applied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("알림이 오면 시계 바늘이 숫자를 가리키고 진동합니다.\n위치 = 진동 횟수 (1시=1회, 2시=2회, 3시=3회)\n설정은 시계에 저장되어 앱 없이도 동작합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach($mappingManager.slots) { $slot in
                    Section {
                        HStack {
                            Text(slot.positionName)
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: $slot.enabled)
                                .labelsHidden()
                        }

                        if slot.enabled {
                            ForEach(AncsCategory.allCases) { cat in
                                HStack {
                                    Image(systemName: cat.systemImage)
                                        .foregroundStyle(slot.hasCategory(cat) ? .blue : .gray)
                                        .frame(width: 24)
                                    Text(cat.displayName)
                                    Spacer()
                                    if slot.hasCategory(cat) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    slot.toggleCategory(cat)
                                    mappingManager.save()
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("시계에 적용") {
                        mappingManager.save()
                        mappingManager.applyToWatch(ble: ble)
                        applied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { applied = false }
                    }
                    .frame(maxWidth: .infinity)

                    if applied {
                        Text("적용 완료!")
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                    }
                }
                Section("디버그") {
                    Button("alert_assign 읽기") {
                        if let cmdId = ble.commandMap["alert_assign"] {
                            for batch in 0...2 {
                                let delay = Double(batch) * 2.0
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    let data = KronabyProtocol().encodeArray([cmdId, batch])
                                    if let c = ble.commandChar {
                                        ble.peripheral?.writeValue(data, for: c, type: .withResponse)
                                        ble.log("alert_assign read[\(batch)]")
                                    }
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.0) {
                                    if let p = ble.peripheral, let c = ble.commandChar {
                                        p.readValue(for: c)
                                    }
                                }
                            }
                        }
                    }
                    Button("alert_assign {1:0} 전송") {
                        ble.sendCommand(name: "alert_assign", value: [1: 0] as [Int: Int])
                        ble.log("alert_assign({1: 0})")
                    }
                    Button("alert_assign {1:2} 전송") {
                        ble.sendCommand(name: "alert_assign", value: [1: 2] as [Int: Int])
                        ble.log("alert_assign({1: 2})")
                    }
                    Button("alert_assign {1:3} 전송") {
                        ble.sendCommand(name: "alert_assign", value: [1: 3] as [Int: Int])
                        ble.log("alert_assign({1: 3})")
                    }
                    Button("공식 앱 설정 전체 읽기") {
                        // alert_assign, config_base, settings, ancs_filter 읽기
                        let cmds = ["alert_assign", "config_base", "settings", "ancs_filter", "complications"]
                        var delay: Double = 0
                        for name in cmds {
                            if let cmdId = ble.commandMap[name] {
                                for batch in 0...2 {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                        let data = KronabyProtocol().encodeArray([cmdId, batch])
                                        if let c = ble.commandChar {
                                            ble.peripheral?.writeValue(data, for: c, type: .withResponse)
                                            ble.log("\(name)[\(batch)] 요청")
                                        }
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.8) {
                                        if let p = ble.peripheral, let c = ble.commandChar {
                                            p.readValue(for: c)
                                        }
                                    }
                                    delay += 1.5
                                }
                            }
                        }
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("알림 매핑")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
