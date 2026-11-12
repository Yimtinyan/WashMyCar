import SwiftUI

@main
struct WashMyCarWatchApp: App {
    @StateObject private var store = WatchStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            WatchView().environmentObject(store).tint(.mint)
                .onChange(of: phase) { _, next in if next == .active { store.connection.checkConnection(); store.sync() } }
        }
    }
}

struct WatchView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        let s = store.session
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if s == .null {
                        Image(systemName: "car.side").font(.largeTitle).frame(maxWidth: .infinity)
                        Text("从容开始。").font(.title2)
                        Text("先在 iPhone 准备流程，再发送到手表。").font(.footnote).foregroundStyle(.secondary)
                    } else if s["done"].flag {
                        Image(systemName: s["egg"].text == "stars" ? "sparkles" : s["egg"].text == "halo" ? "sun.max" : "checkmark.seal.fill")
                            .font(.system(size: 44)).foregroundStyle(.mint).frame(maxWidth: .infinity)
                            .scaleEffect(appeared ? 1 : 0.7)
                            .onAppear { if reduceMotion { appeared = true } else { withAnimation(.spring(duration: 0.6)) { appeared = true } } }
                        Text("又亮了一点。").font(.title2)
                        Text("每一份用心，都有回响。").font(.footnote).foregroundStyle(.secondary)
                        Text("本次 \(clockText(WashEngine.wallTime(s)))").monospacedDigit()
                        Button("同步完成记录") { store.sync() }.buttonStyle(.borderedProminent)
                    } else if s["startedAt"] == .null {
                        Label("方案已保存", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.mint)
                        Text("准备好了。").font(.title2)
                        Text("\(s["plan"]["steps"].array.count) 个步骤 · 离线可执行").font(.footnote)
                        Text(s["plan"]["name"].text).font(.footnote).foregroundStyle(.secondary)
                        Button("开始洗车") { store.action("start") }.buttonStyle(.borderedProminent).controlSize(.large)
                    } else {
                        let index = Int(s["index"].number ?? 0), steps = s["plan"]["steps"].array
                        let step = steps.indices.contains(index) ? steps[index] : .null
                        HStack {
                            Text("\(index + 1) / \(steps.count)")
                            Spacer()
                            Button { store.action("pause") } label: { Image(systemName: s["paused"].flag ? "play.fill" : "pause.fill").frame(minWidth: 36, minHeight: 36) }
                                .accessibilityLabel(s["paused"].flag ? "恢复流程" : "暂停流程")
                        }.font(.caption)
                        Text(s["paused"].flag ? "稍作停留。" : step["name"].text).font(.title3)
                        if let product = s["products"].array.first(where: { $0.id == step["productId"].text }) {
                            Text(product["name"].text).font(.footnote).foregroundStyle(.secondary)
                            Text("\(volume(step["amount"].number ?? 0)) \(PersonalLibrary.unit(product)) 取用量").font(.headline)
                            if (step["water"].number ?? 0) > 0 { Text("另加 \(volume(step["water"].number ?? 0)) mL 清水").font(.caption) }
                        }
                        Text(step["tools"].array.map(\.text).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        Text(step["note"].text).font(.footnote)
                        Button(index == steps.count - 1 ? "完成洗车" : "完成此步") { store.action("next") }.buttonStyle(.borderedProminent).controlSize(.large).disabled(s["paused"].flag)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("有效用时 \(clockText(WashEngine.activeTime(s, now: milliseconds(context.date))))").monospacedDigit().font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("暂停不停止药剂反应，请及时冲洗。").font(.caption2).foregroundStyle(.secondary)
                    }
                    if s != .null && !s["done"].flag { Button("同步至 iPhone") { store.sync() }.font(.caption) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }.navigationTitle("WashMyCar")
        }.alert("提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("知道了") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}
