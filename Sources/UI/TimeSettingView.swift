import SwiftUI
import CoreLocation

struct TimeSettingView: View {
    @EnvironmentObject var ble: BLEManager
    @Binding var isPresented: Bool
    @State private var selectedTimeZone: TimeZone = .current
    @State private var showTimeZonePicker = false

    var body: some View {
        VStack(spacing: 24) {
            Text("시각 설정")
                .font(.title2)
                .bold()

            VStack(spacing: 8) {
                Text("현재 타임존")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    showTimeZonePicker = true
                } label: {
                    HStack {
                        Text(timeZoneDisplayName)
                            .font(.headline)
                        Text(utcOffsetString)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                .foregroundStyle(.primary)
            }

            VStack(spacing: 8) {
                Text("설정될 시각")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(currentTimeString)
                    .font(.system(size: 48, weight: .light, design: .monospaced))
            }

            Button("시각 동기화") {
                syncTime()
                isPresented = false
            }
            .buttonStyle(.borderedProminent)

            Button("건너뛰기") {
                isPresented = false
            }
            .foregroundStyle(.secondary)
        }
        .padding()
        .sheet(isPresented: $showTimeZonePicker) {
            TimeZonePickerView(selected: $selectedTimeZone)
        }
    }

    private var timeZoneDisplayName: String {
        selectedTimeZone.localizedName(for: .standard, locale: .current)
            ?? selectedTimeZone.identifier
    }

    private var utcOffsetString: String {
        let seconds = selectedTimeZone.secondsFromGMT()
        let hours = seconds / 3600
        let minutes = abs(seconds % 3600) / 60
        if minutes == 0 {
            return "UTC\(hours >= 0 ? "+" : "")\(hours)"
        }
        return "UTC\(hours >= 0 ? "+" : "")\(hours):\(String(format: "%02d", minutes))"
    }

    private var currentTimeString: String {
        let formatter = DateFormatter()
        formatter.timeZone = selectedTimeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    private func syncTime() {
        let now = Date()
        var tzCal = Calendar.current
        tzCal.timeZone = selectedTimeZone

        let comps = tzCal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .weekday], from: now
        )

        // Kronaby day mapping: Tue=0, Wed=1, Thu=2, Fri=3, Sat=4, Sun=5, Mon=6
        let kronabyDay: Int
        switch comps.weekday! {
        case 1: kronabyDay = 5  // Sunday
        case 2: kronabyDay = 6  // Monday
        case 3: kronabyDay = 0  // Tuesday
        case 4: kronabyDay = 1  // Wednesday
        case 5: kronabyDay = 2  // Thursday
        case 6: kronabyDay = 3  // Friday
        case 7: kronabyDay = 4  // Saturday
        default: kronabyDay = 0
        }

        ble.sendCommand(name: "datetime", value: [
            comps.year!, comps.month!, comps.day!,
            comps.hour!, comps.minute!, comps.second!,
            kronabyDay
        ])

        // Timezone offset
        let offsetSeconds = selectedTimeZone.secondsFromGMT()
        let tzHours = offsetSeconds / 3600
        let tzMinutes = abs(offsetSeconds % 3600) / 60
        ble.sendCommand(name: "timezone", value: [tzHours, tzMinutes])

        ble.log("시각 동기화: \(comps.hour!):\(comps.minute!):\(comps.second!) TZ=\(utcOffsetString)")
    }
}

struct TimeZonePickerView: View {
    @Binding var selected: TimeZone
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""

    private var filteredZones: [TimeZone] {
        let allIDs = TimeZone.knownTimeZoneIdentifiers.sorted()
        if searchText.isEmpty { return allIDs.compactMap { TimeZone(identifier: $0) } }
        let query = searchText.lowercased()
        return allIDs
            .filter { $0.lowercased().contains(query) }
            .compactMap { TimeZone(identifier: $0) }
    }

    var body: some View {
        NavigationStack {
            List(filteredZones, id: \.identifier) { tz in
                Button {
                    selected = tz
                    dismiss()
                } label: {
                    HStack {
                        Text(tz.identifier.replacingOccurrences(of: "_", with: " "))
                        Spacer()
                        let secs = tz.secondsFromGMT()
                        let h = secs / 3600
                        let m = abs(secs % 3600) / 60
                        Text(m == 0 ? "UTC\(h >= 0 ? "+" : "")\(h)"
                             : "UTC\(h >= 0 ? "+" : "")\(h):\(String(format: "%02d", m))")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        if tz.identifier == selected.identifier {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .searchable(text: $searchText, prompt: "타임존 검색 (예: Seoul, Tokyo)")
            .navigationTitle("타임존 선택")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
