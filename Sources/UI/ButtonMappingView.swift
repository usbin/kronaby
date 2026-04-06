import SwiftUI

struct ButtonMappingView: View {
    @EnvironmentObject var actionManager: ButtonActionManager
    @State private var editingKey: ButtonKey?
    @State private var editingExtendedIndex: Int?

    var body: some View {
        NavigationStack {
            List {
                // IFTTT Key
                Section("IFTTT 설정") {
                    HStack {
                        Text("Webhook Key")
                            .foregroundStyle(.secondary)
                        TextField("IFTTT Key 입력", text: $actionManager.iftttKey)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                // Top button
                Section("상단 버튼") {
                    ForEach(ButtonActionManager.allButtons.filter { $0.button == 0 }, id: \.storageKey) { key in
                        buttonRow(key: key)
                    }
                }

                // Bottom button
                Section("하단 버튼") {
                    ForEach(ButtonActionManager.allButtons.filter { $0.button == 2 }, id: \.storageKey) { key in
                        buttonRow(key: key)
                    }
                    // 하단 길게 누름 — 확장입력모드 (고정)
                    HStack {
                        Text("길게 누름")
                        Spacer()
                        Text("확장입력모드 (고정)")
                            .foregroundStyle(.orange)
                    }
                }

                // 확장입력모드 위치기록 안내
                Section {
                    Text("위치 기록 사용 시: 설정 → 개인정보 보호 및 보안 → 위치 서비스 → Keepnaby → '항상'으로 변경해주세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 확장입력모드 할당 (0~15)
                Section("확장입력모드 할당 (0~15)") {
                    Text("하단 길게 → 진동 1회 → 하단 1회=0, 2회=1\n4자리 입력 → 진동 2회 → 명령 실행")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(0..<16, id: \.self) { index in
                        let action = actionManager.extendedMappings[index]
                        let binary = String(index, radix: 2).leftPadded(to: 4)
                        Button {
                            editingExtendedIndex = index
                        } label: {
                            HStack {
                                Text("\(index)")
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 25, alignment: .trailing)
                                Text("(\(binary))")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50)
                                Spacer()
                                Text(actionSummary(action))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("버튼 매핑")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingKey) { key in
                ActionEditView(key: key)
                    .environmentObject(actionManager)
            }
            .sheet(item: $editingExtendedIndex) { index in
                ExtendedActionEditView(index: index)
                    .environmentObject(actionManager)
            }
        }
    }

    private func buttonRow(key: ButtonKey) -> some View {
        let action = actionManager.getAction(for: key)
        return Button {
            editingKey = key
        } label: {
            HStack {
                Text(key.displayEvent)
                Spacer()
                Text(actionSummary(action))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }

    private func actionSummary(_ action: ButtonAction) -> String {
        switch action.type {
        case .none: return "없음"
        case .findPhone: return "폰 찾기"
        case .showDate: return "날짜 확인"
        case .showBattery: return "배터리"
        case .showSteps: return "걸음수"
        case .musicPlayPause: return "재생/일시정지"
        case .musicNext: return "다음 곡"
        case .musicPrevious: return "이전 곡"
        case .recordLocation: return "위치 기록"
        case .iftttWebhook: return "IFTTT: \(action.iftttEventName)"
        case .shortcut: return "단축어: \(action.shortcutName)"
        case .urlRequest: return "URL"
        }
    }
}

extension ButtonKey: Identifiable {
    var id: String { storageKey }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

extension String {
    func leftPadded(to length: Int, with char: Character = "0") -> String {
        String(repeating: char, count: max(0, length - count)) + self
    }
}

// MARK: - Action Edit (일반 버튼)

struct ActionEditView: View {
    let key: ButtonKey
    @EnvironmentObject var actionManager: ButtonActionManager
    @Environment(\.dismiss) var dismiss
    @State private var action: ButtonAction = ButtonAction()

    var body: some View {
        NavigationStack {
            Form {
                Section("\(key.displayButton) — \(key.displayEvent)") {
                    actionPicker(selection: $action)
                }
                actionDetail(action: $action)
            }
            .navigationTitle("동작 설정")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("취소") { dismiss() },
                trailing: Button("저장") {
                    actionManager.setAction(for: key, action: action)
                    dismiss()
                }
            )
            .onAppear {
                action = actionManager.getAction(for: key)
            }
        }
    }
}

// MARK: - Action Edit (확장입력모드)

struct ExtendedActionEditView: View {
    let index: Int
    @EnvironmentObject var actionManager: ButtonActionManager
    @Environment(\.dismiss) var dismiss
    @State private var action: ButtonAction = ButtonAction()

    var body: some View {
        NavigationStack {
            Form {
                let binary = String(index, radix: 2).leftPadded(to: 4)
                Section("확장입력 \(index) (\(binary))") {
                    actionPicker(selection: $action)
                }
                actionDetail(action: $action)
            }
            .navigationTitle("확장입력 \(index)")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("취소") { dismiss() },
                trailing: Button("저장") {
                    actionManager.extendedMappings[index] = action
                    actionManager.saveExtended()
                    dismiss()
                }
            )
            .onAppear {
                action = actionManager.extendedMappings[index]
            }
        }
    }
}

// MARK: - Shared Picker & Detail

@ViewBuilder
func actionPicker(selection: Binding<ButtonAction>) -> some View {
    Picker("동작", selection: selection.type) {
        Text("없음").tag(ButtonActionType.none)
        Section("기본") {
            Text("폰 찾기").tag(ButtonActionType.findPhone)
        }
        Section("음악") {
            Text("재생/일시정지").tag(ButtonActionType.musicPlayPause)
            Text("다음 곡").tag(ButtonActionType.musicNext)
            Text("이전 곡").tag(ButtonActionType.musicPrevious)
        }
        Section("위치") {
            Text("위치 기록").tag(ButtonActionType.recordLocation)
        }
        Section("고급") {
            Text("IFTTT Webhook").tag(ButtonActionType.iftttWebhook)
            Text("단축어 실행 (앱 열림)").tag(ButtonActionType.shortcut)
            Text("URL 요청").tag(ButtonActionType.urlRequest)
        }
    }
}

@ViewBuilder
func actionDetail(action: Binding<ButtonAction>) -> some View {
    switch action.wrappedValue.type {
    case .findPhone:
        Section("폰 찾기 옵션") {
            Toggle("시스템 볼륨 최대화 (작동 후 복원 안 됨)", isOn: Binding(
                get: { FindMyPhone.maxVolumeEnabled },
                set: { FindMyPhone.maxVolumeEnabled = $0 }
            ))
        }
    case .iftttWebhook:
        Section("IFTTT 이벤트") {
            TextField("이벤트 이름", text: action.iftttEventName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    case .shortcut:
        Section("단축어") {
            TextField("단축어 이름 (정확히 입력)", text: action.shortcutName)
                .autocorrectionDisabled()
        }
    case .urlRequest:
        Section("URL") {
            TextField("https://...", text: action.urlString)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        }
    default:
        EmptyView()
    }
}