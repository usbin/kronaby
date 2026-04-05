import SwiftUI

struct LocationHistoryView: View {
    @EnvironmentObject var recorder: LocationRecorder
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()
    @State private var showDeleteAllConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 지도 앱 선택
                Picker("지도 앱", selection: Binding(
                    get: { recorder.preferredMap },
                    set: { recorder.setPreferredMap($0) }
                )) {
                    ForEach(LocationRecorder.MapApp.allCases) { app in
                        Text(app.displayName).tag(app)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if recorder.savedLocations.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "mappin.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("저장된 위치가 없습니다")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    List(selection: $selection) {
                        ForEach(recorder.savedLocations) { loc in
                            Button {
                                if editMode == .inactive {
                                    recorder.openInMap(loc)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(loc.placeName.isEmpty ? loc.coordinateString : loc.placeName)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    HStack {
                                        Text(loc.timeString)
                                        Spacer()
                                        Text(loc.coordinateString)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("위치 기록")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, $editMode)
            .navigationBarItems(
                leading: editButton,
                trailing: deleteButtons
            )
            .alert("전체 삭제", isPresented: $showDeleteAllConfirm) {
                Button("전체 삭제", role: .destructive) {
                    recorder.deleteAll()
                    editMode = .inactive
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("저장된 모든 위치가 삭제됩니다.")
            }
        }
    }

    @ViewBuilder
    private var editButton: some View {
        if !recorder.savedLocations.isEmpty {
            Button(editMode == .active ? "완료" : "편집") {
                if editMode == .active {
                    editMode = .inactive
                    selection.removeAll()
                } else {
                    editMode = .active
                }
            }
        }
    }

    @ViewBuilder
    private var deleteButtons: some View {
        if editMode == .active {
            HStack(spacing: 12) {
                if !selection.isEmpty {
                    Button("선택 삭제") {
                        recorder.deleteByIDs(selection)
                        selection.removeAll()
                        if recorder.savedLocations.isEmpty {
                            editMode = .inactive
                        }
                    }
                    .foregroundStyle(.red)
                }
                Button("전체 삭제") {
                    showDeleteAllConfirm = true
                }
                .foregroundStyle(.red)
            }
        }
    }
}