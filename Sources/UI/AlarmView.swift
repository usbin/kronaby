import SwiftUI

struct AlarmView: View {
    @EnvironmentObject var ble: BLEManager
    @StateObject private var alarmManager = AlarmManager()
    @State private var applied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("무음 알람 — 시계 진동으로 알려줍니다.\n스누즈: 크라운 짧게 (10분)\n해제: 크라운 길게")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("알람 (\(alarmManager.alarms.count)/\(AlarmManager.maxAlarms))") {
                    ForEach(alarmManager.alarms.indices, id: \.self) { index in
                        AlarmRow(alarm: $alarmManager.alarms[index])
                    }

                    if alarmManager.alarms.count < AlarmManager.maxAlarms {
                        Button {
                            alarmManager.addAlarm()
                        } label: {
                            Label("알람 추가", systemImage: "plus.circle")
                        }
                    }
                }

                Section {
                    Button("시계에 적용") {
                        alarmManager.save()
                        alarmManager.applyToWatch(ble: ble)
                        applied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { applied = false }
                    }
                    .frame(maxWidth: .infinity)

                    Button("전체 삭제") {
                        alarmManager.alarms.removeAll()
                        alarmManager.save()
                        // 시계에도 빈 배열 전송
                        ble.sendCommand(name: "alarm", value: [] as [Any])
                        ble.log("alarm 전체 삭제")
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)

                    if applied {
                        Text("적용 완료!")
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                    }
                }
                Section("디버그") {
                    Button("alarm 현재값 읽기") {
                        if let cmdId = ble.commandMap["alarm"] {
                            for batch in 0...2 {
                                let delay = Double(batch) * 2.0
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    let data = KronabyProtocol().encodeArray([cmdId, batch])
                                    if let c = ble.commandChar {
                                        ble.peripheral?.writeValue(data, for: c, type: .withResponse)
                                        ble.log("alarm read[\(batch)]: \(data.map { String(format: "%02X", $0) }.joined())")
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
                }
            }
            .navigationTitle("무음 알람")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct AlarmRow: View {
    @Binding var alarm: WatchAlarm
    @State private var showTimePicker = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    showTimePicker.toggle()
                } label: {
                    Text(alarm.timeString)
                        .font(.system(size: 32, weight: .light, design: .monospaced))
                        .foregroundStyle(alarm.enabled ? .primary : .secondary)
                }

                Spacer()

                Toggle("", isOn: $alarm.enabled)
                    .labelsHidden()
            }

            if showTimePicker {
                HStack {
                    Picker("시", selection: $alarm.hour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text("\(h)시").tag(h)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100, height: 100)
                    .clipped()

                    Picker("분", selection: $alarm.minute) {
                        ForEach(0..<60, id: \.self) { m in
                            Text(String(format: "%02d분", m)).tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100, height: 100)
                    .clipped()
                }
            }

            // 요일 필터링은 현재 미지원 (펌웨어 명령 형식 미확인)
            // DayPicker(days: $alarm.days)

            Text("매일 반복")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct DayPicker: View {
    @Binding var days: Set<Int>
    private let labels = ["월", "화", "수", "목", "금", "토", "일"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                DayButton(day: day, label: labels[day - 1], days: $days)
            }
        }
    }
}

struct DayButton: View {
    let day: Int
    let label: String
    @Binding var days: Set<Int>

    private var isSelected: Bool { days.contains(day) }

    var body: some View {
        Button {
            if isSelected {
                days.remove(day)
            } else {
                days.insert(day)
            }
        } label: {
            Text(label)
                .font(.caption2)
                .bold(isSelected)
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}
