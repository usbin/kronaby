import SwiftUI

struct NotificationMappingView: View {
    @EnvironmentObject var mappingManager: NotificationMappingManager
    @EnvironmentObject var ble: BLEManager
    @State private var applied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("알림 카테고리를 시계 숫자(1~12)에 할당합니다.\n해당 알림이 오면 시계 바늘이 할당된 숫자를 가리킨 후 돌아갑니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("알림 매핑") {
                    ForEach(NotificationCategory.allCases) { category in
                        NotificationMappingRow(
                            category: category,
                            mappingManager: mappingManager
                        )
                    }
                }

                Section("현재 설정") {
                    let active = mappingManager.activeMappings()
                    if active.isEmpty {
                        Text("활성화된 매핑 없음")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(active, id: \.category) { mapping in
                            HStack {
                                Image(systemName: mapping.category.systemImage)
                                    .foregroundStyle(.blue)
                                    .frame(width: 24)
                                Text(mapping.category.displayName)
                                Spacer()
                                Text("→ \(mapping.position)")
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }

                Section {
                    Button("시계에 적용") {
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

                Section("참고") {
                    Text("ancs_filter(cmd 4)와 alert_assign(cmd 3)으로 시계에 전송됩니다.\n시계 펌웨어가 ANCS로 iPhone 알림을 감지하면 바늘이 할당된 숫자를 가리킵니다.\n\n정확한 파라미터 형식은 실기기 테스트로 확인이 필요합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("알림 매핑")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 개별 카테고리 매핑 행

struct NotificationMappingRow: View {
    let category: NotificationCategory
    @ObservedObject var mappingManager: NotificationMappingManager

    private var mapping: NotificationMapping {
        mappingManager.getMapping(for: category)
    }

    var body: some View {
        HStack {
            Image(systemName: category.systemImage)
                .foregroundStyle(mapping.enabled ? .blue : .gray)
                .frame(width: 24)

            Text(category.displayName)

            Spacer()

            if mapping.enabled {
                Picker("", selection: Binding(
                    get: { mapping.position },
                    set: { newPos in
                        mappingManager.setMapping(for: category, position: newPos, enabled: true)
                    }
                )) {
                    ForEach(1...12, id: \.self) { num in
                        Text("\(num)").tag(num)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 60)
            }

            Toggle("", isOn: Binding(
                get: { mapping.enabled },
                set: { newVal in
                    let pos = mapping.position > 0 ? mapping.position : 1
                    mappingManager.setMapping(for: category, position: pos, enabled: newVal)
                }
            ))
            .labelsHidden()
        }
    }
}
