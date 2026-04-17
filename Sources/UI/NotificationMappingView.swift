import SwiftUI

struct NotificationMappingView: View {
    @EnvironmentObject var mappingManager: NotificationMappingManager
    @EnvironmentObject var ble: BLEManager
    @State private var applied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("알림이 오면 시계 바늘이 숫자를 가리키고 진동합니다.\n위치 = 진동 횟수 (1시=1회, 2시=2회, 3시=3회)\n앱별로 알림을 할당하세요. 설정은 시계에 저장됩니다.")
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
                            // 할당된 앱 목록
                            let assignedApps = mappingManager.allApps.filter { slot.appIds.contains($0.id) }
                            ForEach(assignedApps) { app in
                                HStack {
                                    Image(systemName: app.systemImage)
                                        .foregroundStyle(.blue)
                                        .frame(width: 24)
                                    VStack(alignment: .leading) {
                                        Text(app.displayName)
                                        Text(app.bundleIdPrefix)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        slot.appIds.remove(app.id)
                                        mappingManager.save()
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                }
                            }

                            if assignedApps.isEmpty {
                                Text("앱을 추가하세요")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }

                            // 앱 추가 링크
                            NavigationLink {
                                AppPickerView(slot: $slot, mappingManager: mappingManager)
                            } label: {
                                Label("앱 추가", systemImage: "plus.circle")
                            }

                            // 필터 수 경고
                            let totalFilters = mappingManager.slots.reduce(0) { $0 + $1.appIds.count }
                            if totalFilters > 30 {
                                Text("필터 \(totalFilters)/35개 — 최대 35개까지 설정 가능")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
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

                // MARK: - 사용자 정의 앱
                Section("사용자 정의 앱") {
                    CustomAppEntryView(mappingManager: mappingManager)

                    ForEach(mappingManager.customApps) { app in
                        HStack {
                            Image(systemName: "app.fill")
                                .foregroundStyle(.purple)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(app.displayName)
                                Text(app.bundleIdPrefix)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                mappingManager.removeCustomApp(id: app.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        }
                    }
                }

                #if DEBUG
                Section("디버그") {
                    ForEach([1, 2, 3], id: \.self) { val in
                        Button("alert(\(val)) → 바늘 테스트") {
                            ble.sendCommand(name: "alert", value: val)
                            ble.log("alert(\(val))")
                        }
                        .font(.caption)
                    }
                    Button("alert_assign [0,0,0]") {
                        ble.sendCommand(name: "alert_assign", value: [0, 0, 0])
                        ble.log("alert_assign([0, 0, 0])")
                    }
                    .font(.caption)
                }
                #endif
            }
            .navigationTitle("알림 매핑")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 앱 피커

struct AppPickerView: View {
    @Binding var slot: NotificationSlot
    @ObservedObject var mappingManager: NotificationMappingManager
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var filteredApps: [NotificationApp] {
        let apps = mappingManager.allApps
        if searchText.isEmpty { return apps }
        let query = searchText.lowercased()
        return apps.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.bundleIdPrefix.lowercased().contains(query)
        }
    }

    private var groupedApps: [(NotificationApp.AppCategory, [NotificationApp])] {
        let grouped = Dictionary(grouping: filteredApps) { $0.category }
        return NotificationApp.AppCategory.allCases.compactMap { cat in
            guard let apps = grouped[cat], !apps.isEmpty else { return nil }
            return (cat, apps)
        }
    }

    var body: some View {
        List {
            ForEach(groupedApps, id: \.0) { category, apps in
                Section(category.rawValue) {
                    ForEach(apps) { app in
                        Button {
                            toggleApp(app)
                        } label: {
                            HStack {
                                Image(systemName: app.systemImage)
                                    .foregroundStyle(slot.appIds.contains(app.id) ? .blue : .gray)
                                    .frame(width: 24)
                                VStack(alignment: .leading) {
                                    Text(app.displayName)
                                        .foregroundStyle(.primary)
                                    Text(app.truncatedPrefix)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if slot.appIds.contains(app.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                } else {
                                    // 다른 슬롯에 이미 할당된 경우 표시
                                    if let otherSlot = mappingManager.slots.first(where: { $0.id != slot.id && $0.appIds.contains(app.id) }) {
                                        Text("\(otherSlot.id)시에 할당됨")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "앱 이름 또는 번들 ID 검색")
        .navigationTitle("\(slot.id)시 — 앱 선택")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggleApp(_ app: NotificationApp) {
        if slot.appIds.contains(app.id) {
            slot.appIds.remove(app.id)
        } else {
            // 다른 슬롯에서 제거 후 이 슬롯에 추가
            for i in mappingManager.slots.indices where mappingManager.slots[i].id != slot.id {
                mappingManager.slots[i].appIds.remove(app.id)
            }
            slot.appIds.insert(app.id)
        }
        mappingManager.save()
    }
}

// MARK: - 커스텀 앱 입력

struct CustomAppEntryView: View {
    @ObservedObject var mappingManager: NotificationMappingManager
    @State private var bundleId = ""
    @State private var displayName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("번들 ID (예: com.example.app)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("com.example.app", text: $bundleId)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            TextField("앱 이름", text: $displayName)
            Button("추가") {
                guard !bundleId.isEmpty else { return }
                let name = displayName.isEmpty ? bundleId : displayName
                mappingManager.addCustomApp(bundleIdPrefix: bundleId, displayName: name)
                bundleId = ""
                displayName = ""
            }
            .disabled(bundleId.isEmpty)
            .font(.caption)
        }
    }
}
