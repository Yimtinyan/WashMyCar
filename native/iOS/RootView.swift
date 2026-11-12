import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var tab = 0
    var body: some View {
        Group {
            if store.loadFailed {
                NavigationStack {
                    ContentUnavailableView { Label("资料暂时无法读取", systemImage: "externaldrive.badge.exclamationmark") }
                    description: { Text("原资料文件已保留。你可以检查文件，或从设置恢复完整备份。") }
                    actions: { NavigationLink("打开恢复设置") { SettingsView() } }
                }
            } else {
                TabView(selection: $tab) {
                    NavigationStack { HomeView().toolbar { settings } }.tabItem { Label("洗车", systemImage: "car.side") }.tag(0)
                    NavigationStack { InventoryView().toolbar { settings } }.tabItem { Label("药剂", systemImage: "flask") }.tag(1)
                    NavigationStack { RecordsView().toolbar { settings } }.tabItem { Label("记录", systemImage: "list.clipboard") }.tag(2)
                }
            }
        }
        .alert("未能完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("知道了") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onOpenURL { url in tab = url.host == "inventory" ? 1 : url.host == "records" ? 2 : 0 }
    }
    @ToolbarContentBuilder private var settings: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { NavigationLink { SettingsView() } label: { Image(systemName: "slider.horizontal.3").accessibilityLabel("设置") } }
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showPreparation = false
    @State private var showSession = false
    private var plan: JSON { store.active ? store.state["session"]["plan"] : store.state["plan"] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(title: "留一点时间，\n给爱车。")
                if plan["vehicleModel"].text == "onvo-l60" {
                    Image("Car").resizable().scaledToFit().frame(maxHeight: 235).accessibilityLabel("银色乐道 L60，白色内饰")
                } else { Image(systemName: "car.side").font(.system(size: 100)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(30) }
                HStack {
                    Text(store.active ? "当前洗车" : "本次洗车").foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink { PlanView() } label: { Label("编辑", systemImage: "arrow.up.right") }.disabled(store.active)
                }.font(.subheadline)
                HStack(alignment: .firstTextBaseline) {
                    Menu {
                        Text("切换洗车方案")
                        ForEach(store.state["templates"].array, id: \.id) { template in
                            Button(template["name"].text) { store.perform { try store.applyTemplate(template) } }
                        }
                    } label: { Label(plan["name"].text, systemImage: "chevron.down").font(.title2) }.disabled(store.active).accessibilityHint("切换已保存的洗车方案")
                    Spacer()
                    Text("\(plan["steps"].array.count) 个步骤").font(.caption).foregroundStyle(.secondary)
                }
                if store.active { Text("本次已备液，完成后可切换方案。").font(.caption).foregroundStyle(.secondary) }
                VStack(spacing: 0) {
                    ForEach(Array(plan["steps"].array.prefix(2).enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 18) {
                            Text(String(format: "%02d", index + 1)).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(step["name"].text)
                                let products = store.active ? store.state["session"]["products"].array : store.state["products"].array
                                let product = products.first { $0.id == step["productId"].text }
                                Text(product.map { "\($0["name"].text) · \(volume(step["amount"].number ?? 0)) \(PersonalLibrary.unit($0))" } ?? step["tools"].array.map(\.text).joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.padding(.vertical, 17)
                        Divider()
                    }
                }
                PrimaryButton(title: store.active ? "继续这次洗车" : "准备这次洗车") {
                    if store.active { showSession = true } else { showPreparation = true }
                }
                Text("出发前安排好，现场抬腕确认。").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(24)
        }.background(Style.paper).navigationTitle("WashMyCar").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPreparation) { NavigationStack { PreparationView { showPreparation = false; showSession = true } } }
            .navigationDestination(isPresented: $showSession) { SessionView() }
    }
}

struct PreparationNotes: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        let notes = WashEngine.pendingNotes(store.state)
        if !notes.isEmpty {
            Section("这辆车的未处理事项") {
                ForEach(notes, id: \.id) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record["notes"].text)
                        HStack {
                            Button("已处理") { store.perform { try store.noteStatus(id: record.id, resolved: true) } }
                            Spacer()
                            Button("下次再提醒") { store.perform { try store.commit(store.state.replacing(["deferredNoteIds": .array(store.state["deferredNoteIds"].array + [.string(record.id)])])) } }
                        }.font(.caption).buttonStyle(.borderless)
                    }.padding(.vertical, 6)
                }
            }
        }
    }
}

struct PreparationView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmedLabel = false
    let onPrepared: () -> Void
    private var issue: String? { do { try WashEngine.checkPreparation(store.state); return nil } catch { return error.localizedDescription } }
    var body: some View {
        List {
            Section { Text(store.state["plan"]["name"].text).font(.title2); Text(store.state["plan"]["location"].text.isEmpty ? "未填写地点" : store.state["plan"]["location"].text).foregroundStyle(.secondary) }
            PreparationNotes()
            Section("本次原液取用") {
                ForEach(WashEngine.totals(store.state["plan"]).keys.sorted(), id: \.self) { id in
                    let product = store.state["products"].array.first { $0.id == id }
                    HStack {
                        VStack(alignment: .leading) { Text(product?["name"].text ?? "药剂不存在"); Text(product.map(WashEngine.stockText) ?? "").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text("\(volume(WashEngine.totals(store.state["plan"])[id] ?? 0)) \(product.map(PersonalLibrary.unit) ?? "mL")").monospacedDigit()
                    }
                }
            }
            Section("随行工具") { Text(Set(store.state["plan"]["steps"].array.flatMap { $0["tools"].array.map(\.text) }).sorted().joined(separator: " · ")) }
            Section {
                Text("用量来自可编辑示例。请核对本瓶标签、车辆表面与施工方式；应用不会推算化学停留时间。").font(.footnote).foregroundStyle(.secondary)
                Toggle("已核对标签，确认已经实际取用", isOn: $confirmedLabel)
                if let issue { Text(issue).foregroundStyle(.red) }
                PrimaryButton(title: "确认取用并保存准备清单") { store.perform { try store.prepare(); onPrepared() } }.disabled(!confirmedLabel || issue != nil || store.active)
                Text("确认后按同瓶汇总扣一次库存。到现场点击“开始洗车”才计时。").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("准备好，再出发。").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }
}

struct SessionView: View {
    @EnvironmentObject private var store: AppStore
    @State private var startConfirm = false
    var body: some View {
        let s = store.state["session"]
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if s == .null { ContentUnavailableView("还没有准备流程", systemImage: "car.side") }
                else if s["done"].flag {
                    Celebration(session: s)
                    if let record = store.state["washes"].array.first(where: { $0.id == s.id }) { NavigationLink { RecordDetail(recordID: record.id) } label: { Text("查看这次洗车记录").foregroundStyle(Style.onAccent) }.buttonStyle(.borderedProminent) }
                } else if s["startedAt"] == .null {
                    PageHeading(title: "准备好了，\n到现场再开始。", subtitle: "库存取用已保存，尚未计时。")
                    Label("\(s["plan"]["steps"].array.count) 个步骤 · \(s["plan"]["name"].text)", systemImage: "checkmark.circle")
                    if s["owner"].text == "watch" {
                        Label(s["transferStatus"].text == "ready" ? "手表已保存，离线可执行" : "等待手表保存确认", systemImage: "applewatch")
                        Text("在手表上点“开始洗车”。执行权已交给手表，手机会在连接后显示进度。").foregroundStyle(.secondary)
                        PrimaryButton(title: "重新发送至手表", icon: "arrow.clockwise") { store.perform { try store.sendToWatch() } }
                    } else {
                        PrimaryButton(title: "交给 Apple Watch", icon: "applewatch") { store.perform { try store.sendToWatch() } }
                        Button("使用 iPhone 开始洗车") { startConfirm = true }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                        Text("交给手表后，本次流程由手表负责，手机不能同时执行。").font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    let index = Int(s["index"].number ?? 0), steps = s["plan"]["steps"].array
                    let step = steps.indices.contains(index) ? steps[index] : .null
                    Text("\(index + 1) / \(steps.count)").font(.headline).foregroundStyle(.secondary)
                    PageHeading(title: s["paused"].flag ? "稍作停留。" : step["name"].text)
                    if let product = s["products"].array.first(where: { $0.id == step["productId"].text }) {
                        Text(product["name"].text).font(.title2)
                        Text("药剂 \(volume(step["amount"].number ?? 0)) \(PersonalLibrary.unit(product)) + 清水 \(volume(step["water"].number ?? 0)) mL").font(.headline)
                        Text(product["instructions"].text).font(.subheadline)
                    }
                    Text(step["tools"].array.map(\.text).joined(separator: " · ")).foregroundStyle(.secondary)
                    Text(step["note"].text)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack {
                            VStack { Text("洗车时长"); Text(clockText(WashEngine.wallTime(s, now: milliseconds(context.date)))).font(.title2).monospacedDigit() }
                            Spacer()
                            VStack { Text("有效用时"); Text(clockText(WashEngine.activeTime(s, now: milliseconds(context.date)))).font(.title2).monospacedDigit() }
                        }.font(.caption).padding().background(.background, in: RoundedRectangle(cornerRadius: 24))
                    }
                    if s["owner"].text == "phone" {
                        PrimaryButton(title: index == steps.count - 1 ? "完成洗车并保存记录" : "完成此步") { store.perform { try store.action("next"); UIImpactFeedbackGenerator(style: .light).impactOccurred() } }.disabled(s["paused"].flag)
                        Button(s["paused"].flag ? "继续流程" : "暂停流程") { store.perform { try store.action("pause") } }.buttonStyle(.bordered)
                    } else { Label("由手表执行 · 等待同步进度", systemImage: "applewatch") }
                    Text("暂停不会停止药剂反应，请按本瓶标签及时冲洗。").font(.footnote).foregroundStyle(.secondary)
                    if s["timingRestored"].flag { Text("旧版流程没有计时锚点，本次计时从恢复时开始。").font(.footnote).foregroundStyle(.secondary) }
                }
            }.padding(24)
        }.background(Style.paper).navigationTitle("现场引导").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("确认已到现场，使用 iPhone 开始计时？", isPresented: $startConfirm, titleVisibility: .visible) {
                Button("开始洗车") { store.perform { try store.action("start") } }
            }
    }
}
