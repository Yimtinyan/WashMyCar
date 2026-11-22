import SwiftUI

struct RecordsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var recordToDelete: JSON?
    var body: some View {
        let washes = store.state["washes"].array
        List {
            Section { PageHeading(title: "把用心，\n留成记录。", subtitle: "时间、地点与用量，都在这里。") }
            Section {
                if washes.isEmpty {
                    ContentUnavailableView("下一次洗护，会成为第一篇。", systemImage: "list.clipboard", description: Text("完成一次洗车，记录会自动保存在这里。"))
                }
                ForEach(washes, id: \.id) { w in
                    NavigationLink { RecordDetail(snapshot: w) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(w["name"].text).font(.headline)
                            Text(Date(timeIntervalSince1970: (w["finishedAt"].number ?? 0) / 1000), format: .dateTime.year().month().day().hour().minute()).font(.subheadline)
                            Text("\(w["location"].text) · \(clockText(w["durationMs"].number ?? 0))").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 7)
                    }
                    // Destructive swipe roles remove the row optimistically. Only the confirmation may do that.
                    .swipeActions(allowsFullSwipe: false) {
                        Button("删除") { recordToDelete = w }.tint(.red)
                    }
                    .contextMenu { Button("删除记录") { recordToDelete = w } }
                }
            } header: {
                if !washes.isEmpty { Text("\(washes.count) 次认真洗护") }
            }
            if !store.state["deletedWashes"].array.isEmpty {
                NavigationLink("已删除的记录（\(store.state["deletedWashes"].array.count)）") { DeletedRecordsView() }
            }
        }.modifier(RecordDeletion(record: $recordToDelete))
            .navigationTitle("记录").navigationBarTitleDisplayMode(.inline)
    }
}

struct RecordDetail: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let snapshot: JSON
    private var recordID: String { snapshot.id }
    @State private var note = ""
    @State private var loaded = false
    @State private var recordToDelete: JSON?
    // Keep the visible detail intact while the confirmed deletion pops this screen.
    private var record: JSON { store.state["washes"].array.first { $0.id == recordID } ?? snapshot }
    var body: some View {
        List {
            Section {
                Text(record["name"].text).font(.title)
                Text(record["vehicle"].text).font(.caption).foregroundStyle(.secondary)
                if record["vehicleModel"].text == "onvo-l60" { Image("Car").resizable().scaledToFit().frame(height: 180) }
                LabeledContent("地点", value: record["location"].text)
                LabeledContent("洗车时长", value: clockText(record["durationMs"].number ?? 0))
                LabeledContent("有效用时", value: clockText(record["activeMs"].number ?? 0))
                LabeledContent("暂停", value: clockText(record["pausedMs"].number ?? 0))
            }
            Section("药剂使用汇总 · 当时的快照") {
                ForEach(record["amounts"].object.keys.sorted(), id: \.self) { id in
                    if let p = record["products"].array.first(where: { $0.id == id }) {
                        NavigationLink { ProductDetail(productID: id, snapshot: p) } label: {
                            HStack { VStack(alignment: .leading) { Text(p["name"].text); Text(p["brand"].text).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(volume(record["amounts"][id].number ?? 0)) \(PersonalLibrary.unit(p))") }
                        }
                    }
                }
            }
            Section("洗后注意事项") {
                TextField("下次要留意的地方", text: $note, axis: .vertical).lineLimit(3...10)
                Button("保存备注") { store.perform { try store.updateNote(id: recordID, text: note) } }
                Toggle("这条事项已处理", isOn: Binding(get: { record["noteStatus"].text == "resolved" }, set: { resolved in store.perform { try store.noteStatus(id: recordID, resolved: resolved) } }))
                Text("未处理事项会在这辆车下次准备时提醒。修改并保存备注后，会重新列入待处理。").font(.caption).foregroundStyle(.secondary)
            }
            Section("完成的步骤") { ForEach(record["steps"].array, id: \.id) { s in Label(s["name"].text, systemImage: "checkmark") } }
            WashEnergySection(record: record)
        }.navigationTitle("洗车详情").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("删除记录", role: .destructive) { recordToDelete = record }
                }
            }
            .modifier(RecordDeletion(record: $recordToDelete) { dismiss() })
            .onAppear { if !loaded { note = record["notes"].text; loaded = true } }
    }
}

private struct RecordDeletion: ViewModifier {
    @EnvironmentObject private var store: AppStore
    @Binding var record: JSON?
    var onDelete: () -> Void = {}

    func body(content: Content) -> some View {
        content.confirmationDialog("删除这条洗车记录？", isPresented: Binding(
            get: { record != nil }, set: { if !$0 { record = nil } }
        ), titleVisibility: .visible, presenting: record) { selected in
            Button("删除记录", role: .destructive) {
                store.perform {
                    try store.commit(PersonalLibrary.removeRecord(store.state, id: selected.id))
                    onDelete()
                }
            }
            Button("保留", role: .cancel) {}
        } message: { selected in
            Text("“\(selected["name"].text)”将移至「已删除的记录」，可随时恢复。已取用的药剂保留在使用履历中。")
        }
    }
}

struct DeletedRecordsView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            if store.state["deletedWashes"].array.isEmpty { ContentUnavailableView("暂无已删除记录", systemImage: "trash") }
            ForEach(store.state["deletedWashes"].array, id: \.id) { record in
                VStack(alignment: .leading, spacing: 8) {
                    Text(record["name"].text).font(.headline)
                    Text(Date(timeIntervalSince1970: (record["finishedAt"].number ?? 0) / 1000), format: .dateTime.year().month().day().hour().minute()).font(.subheadline)
                    Text(record["location"].text).font(.caption).foregroundStyle(.secondary)
                    Text(record["notes"].text).font(.caption).foregroundStyle(.secondary)
                    Button("恢复记录") { store.perform { try store.commit(PersonalLibrary.restoreRecord(store.state, id: record.id)) } }
                }
            }
        }.navigationTitle("已删除的记录")
    }
}
