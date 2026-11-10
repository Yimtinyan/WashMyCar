import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var exporting = false
    @State private var importing = false
    @State private var document = BackupDocument(data: Data())
    @State private var pending: JSON = .null
    @State private var preview = false
    @State private var backupStatus = ""
    private func setting(_ key: String, value: JSON) {
        store.perform { try store.commit(store.state.replacing(["settings": store.state["settings"].replacing([key: value])])) }
    }
    var body: some View {
        Form {
            Section {
                PageHeading(title: "按你的习惯。", subtitle: "让每次洗护，都更顺手。")
                Picker("外观", selection: Binding(get: { store.state["settings"]["theme"].text }, set: { setting("theme", value: .string($0)) })) {
                    Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
                }
                Toggle("减少动态效果", isOn: Binding(get: { store.state["settings"]["reducedMotion"].flag }, set: { setting("reducedMotion", value: .bool($0)) }))
                Text("同时遵循系统的减少动态效果设置。").font(.caption).foregroundStyle(.secondary)
            }.disabled(store.loadFailed)
            Section("资料备份") {
                Button("导出完整 JSON 备份", systemImage: "square.and.arrow.up") { store.perform { document = BackupDocument(data: try Backup.encode(store.state)); exporting = true } }.disabled(store.loadFailed)
                Button("从备份恢复", systemImage: "square.and.arrow.down") { importing = true }.disabled(store.active)
                Text("兼容 Demo v2—v5 的 WashMyCarBackup；包含车辆、库存、购买资料、方案、取用履历与洗车记录。恢复前先预览，确认后替换本机资料，并保存一份本机回退副本。不包含健康明细与附件。").font(.caption).foregroundStyle(.secondary)
                if !backupStatus.isEmpty { Text(backupStatus).font(.footnote) }
            }
            Section("Apple Watch") {
                ConnectionStatus(connection: store.connection)
                Text("iPhone 和 Watch 使用相同签名团队安装并配对。交接后以手表为唯一执行端；手表离线进度保存于本机，连接恢复后重试同步。").font(.caption).foregroundStyle(.secondary)
            }
            Section("系统入口") {
                Text("可在快捷指令或操作按钮设置中选择“打开洗车流程”；小组件提供距上次洗车时间和药剂瓶数。")
                Text("当前原生版本尚未接入 HealthKit、相机拍摄与 Camera Control。车辆与药瓶沿用现有图片示意。").font(.caption).foregroundStyle(.secondary)
            }
            Section { Text("WashMyCar · 原生 v0.1\n好好洗车，慢慢生活。").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "WashMyCar-Backup") { result in
                switch result { case .success: backupStatus = "备份已导出。"; case .failure(let e): store.error = e.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                store.perform {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= Backup.maxBytes else { throw WashError("备份超过 12 MB。") }
                    pending = try Backup.decode(Data(contentsOf: url)); preview = true
                }
            }
            .sheet(isPresented: $preview) {
                NavigationStack {
                    Form {
                        Section("将恢复以下资料") {
                            LabeledContent("车辆", value: "\(pending["vehicles"].array.count)")
                            LabeledContent("药剂", value: "\(pending["products"].array.count)")
                            LabeledContent("洗车记录", value: "\(pending["washes"].array.count)")
                            LabeledContent("使用履历", value: "\(pending["history"].array.count)")
                            LabeledContent("已存方案", value: "\(pending["templates"].array.count)")
                        }
                        Section {
                            Text("这会替换本机全部资料，不进行合并。当前资料会先保存为 BeforeRestore.json 回退副本。")
                            Button("确认替换本机资料", role: .destructive) { store.perform { try store.restore(pending); preview = false; backupStatus = "资料已恢复。" } }
                        }
                    }.navigationTitle("恢复预览").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { preview = false; pending = .null } } }
                }
            }
    }
}

struct ConnectionStatus: View {
    @ObservedObject var connection: Connectivity
    var body: some View { LabeledContent("连接状态", value: connection.status) }
}
