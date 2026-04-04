import SwiftUI

struct NotificationMappingView: View {
    @EnvironmentObject var mappingManager: NotificationMappingManager
    @EnvironmentObject var ble: BLEManager
    @State private var applied = false
    @State private var showAddApp = false
    @State private var newAppBundleId = ""
    @State private var newAppName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("알림 카테고리 또는 특정 앱의 알림을 시계에서 받습니다.\n바늘이 지정한 숫자를 가리키고 진동합니다.\n설정은 시계에 저장되어 앱 없이도 동작합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 모든 알림 + 카테고리 필터
                Section("알림 필터") {
                    ForEach($mappingManager.filters) { $filter in
                        if case .app = filter.filterType { } else {
                            filterRow(filter: $filter, deletable: false)
                        }
                    }
                }

                // 앱 지정 필터
                Section("앱 지정 필터") {
                    ForEach($mappingManager.filters) { $filter in
                        if case .app = filter.filterType {
                            filterRow(filter: $filter, deletable: true)
                        }
                    }

                    Button {
                        showAddApp = true
                    } label: {
                        Label("앱 추가", systemImage: "plus.circle")
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

                Section("자주 쓰는 Bundle ID") {
                    ForEach(commonApps, id: \.bundleId) { app in
                        Button {
                            mappingManager.addAppFilter(bundleId: app.bundleId, name: app.name)
                        } label: {
                            HStack {
                                Text(app.name)
                                Spacer()
                                Text(app.bundleId)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("알림 매핑")
            .navigationBarTitleDisplayMode(.inline)
            .alert("앱 필터 추가", isPresented: $showAddApp) {
                TextField("Bundle ID (예: com.example.app)", text: $newAppBundleId)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("앱 이름 (표시용)", text: $newAppName)
                Button("추가") {
                    if !newAppBundleId.isEmpty {
                        mappingManager.addAppFilter(
                            bundleId: newAppBundleId,
                            name: newAppName.isEmpty ? newAppBundleId : newAppName
                        )
                        newAppBundleId = ""
                        newAppName = ""
                    }
                }
                Button("취소", role: .cancel) {
                    newAppBundleId = ""
                    newAppName = ""
                }
            }
        }
    }

    @ViewBuilder
    private func filterRow(filter: Binding<NotificationFilter>, deletable: Bool) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: filter.wrappedValue.systemImage)
                    .foregroundStyle(filter.wrappedValue.enabled ? .blue : .gray)
                    .frame(width: 24)

                Text(filter.wrappedValue.displayName)

                Spacer()

                if deletable {
                    Button {
                        mappingManager.removeFilter(id: filter.wrappedValue.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Toggle("", isOn: filter.enabled)
                    .labelsHidden()
            }

            if filter.wrappedValue.enabled {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("위치", selection: filter.position) {
                            ForEach(1...12, id: \.self) { num in
                                Text("\(num)시").tag(num)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Picker("진동", selection: filter.vibration) {
                        ForEach(VibrationPattern.allCases) { pattern in
                            Text(pattern.displayName).tag(pattern)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 자주 쓰는 앱 목록

    private var commonApps: [(name: String, bundleId: String)] {
        [
            ("카카오톡", "com.iwilab.KakaoTalk"),
            ("라인", "jp.naver.line"),
            ("텔레그램", "ph.telegra.Telegraph"),
            ("왓츠앱", "net.whatsapp.WhatsApp"),
            ("인스타그램", "com.burbn.instagram"),
            ("Outlook", "com.microsoft.Office.Outlook"),
            ("Gmail", "com.google.Gmail"),
            ("슬랙", "com.tinyspeck.chatlyio"),
            ("디스코드", "com.hammerandchisel.discord"),
            ("유튜브", "com.google.ios.youtube"),
        ]
    }
}