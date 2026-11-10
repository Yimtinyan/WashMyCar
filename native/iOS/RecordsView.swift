import SwiftUI

struct RecordsView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            Section { PageHeading(title: "把用心，\n留成记录。", subtitle: "时间、地点与用量，都在这里。") }
            if store.state["washes"].array.isEmpty {
                ContentUnavailableView("下一次洗护，会成为第一篇。", systemImage: "list.clipboard", description: Text("完成一次洗车，记录会自动保存在这里。"))
            } else {
                Section("\(store.state["washes"].array.count) 次认真洗护") {
                    ForEach(store.state["washes"].array, id: \.id) { w in
                        NavigationLink { RecordDetail(recordID: w.id) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(w["name"].text).font(.headline)
                                Text(Date(timeIntervalSince1970: (w["finishedAt"].number ?? 0) / 1000), format: .dateTime.year().month().day().hour().minute()).font(.subheadline)
                                Text("\(w["location"].text) · \(clockText(w["durationMs"].number ?? 0))").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 7)
                        }
                    }
                }
            }
        }.navigationTitle("记录").navigationBarTitleDisplayMode(.inline)
    }
}

struct RecordDetail: View {
    @EnvironmentObject private var store: AppStore
    let recordID: String
    @State private var note = ""
    @State private var loaded = false
    private var record: JSON { store.state["washes"].array.first { $0.id == recordID } ?? .null }
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
                            HStack { VStack(alignment: .leading) { Text(p["name"].text); Text(p["brand"].text).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(volume(record["amounts"][id].number ?? 0)) mL") }
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
            Section("同期活动能量与心率") { Text("尚未接入 HealthKit，暂无健康样本。").foregroundStyle(.secondary) }
        }.navigationTitle("洗车详情").navigationBarTitleDisplayMode(.inline)
            .onAppear { if !loaded { note = record["notes"].text; loaded = true } }
    }
}
