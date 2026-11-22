import SwiftUI
import WidgetKit

struct WashEntry: TimelineEntry {
    let date: Date
    let summary: WidgetSummary?
}

struct WashProvider: TimelineProvider {
    func placeholder(in context: Context) -> WashEntry { WashEntry(date: .now, summary: nil) }
    func getSnapshot(in context: Context, completion: @escaping (WashEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WashEntry>) -> Void) {
        let entry = read()
        // A device restarted before first unlock can retry once its keychain becomes available.
        let delay: TimeInterval = entry.summary == nil ? 15 * 60 : 60 * 60
        completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(delay))))
    }
    private func read() -> WashEntry { WashEntry(date: .now, summary: try? WidgetSummary.read()) }
}

struct WashWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WashEntry
    let inventory: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(inventory ? "我的药剂库" : "距上次洗车", systemImage: inventory ? "flask" : "car.side")
                .font(.caption.weight(.semibold)).widgetAccentable()
            Spacer(minLength: 0)
            if let summary = entry.summary {
                if inventory {
                    Text("\(summary.bottleCount) 瓶").font(.largeTitle.weight(.medium))
                    ForEach(Array(summary.bottleLines.prefix(family == .systemMedium ? 2 : 1).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else if let last = summary.lastWash {
                    Text(last, style: .relative).font(.title.weight(.medium)).minimumScaleFactor(0.7)
                    if let name = summary.lastWashName {
                        Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                } else {
                    Text("暂无洗车记录").font(.headline)
                }
            } else {
                Text("打开 App 同步").font(.headline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: inventory ? "washmycar://inventory" : "washmycar://records"))
    }
}

struct LastWashWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LastWash", provider: WashProvider()) { WashWidgetView(entry: $0, inventory: false) }
            .configurationDisplayName("距上次洗车").description("查看距离上次洗车的时间和当时的方案。").supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct InventoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Inventory", provider: WashProvider()) { WashWidgetView(entry: $0, inventory: true) }
            .configurationDisplayName("药剂库").description("查看在库瓶数及余量。").supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct WashWidgetBundle: WidgetBundle {
    var body: some Widget { LastWashWidget(); InventoryWidget() }
}
