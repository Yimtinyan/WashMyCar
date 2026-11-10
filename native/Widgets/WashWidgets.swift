import SwiftUI
import WidgetKit

struct WashEntry: TimelineEntry {
    let date: Date
    let lastWash: Date?
    let bottles: Int?
    let name: String
}
struct WashProvider: TimelineProvider {
    func placeholder(in context: Context) -> WashEntry { WashEntry(date: .now, lastWash: nil, bottles: nil, name: "准备下一次洗车") }
    func getSnapshot(in context: Context, completion: @escaping (WashEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WashEntry>) -> Void) { completion(Timeline(entries: [read()], policy: .after(.now.addingTimeInterval(3600)))) }
    private func read() -> WashEntry {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.yimtinyan.WashMyCar")?.appendingPathComponent("Widget.json"),
              let data = try? Data(contentsOf: url), let json = try? JSON.read(data) else {
            return WashEntry(date: .now, lastWash: nil, bottles: nil, name: "打开 App 同步资料")
        }
        return WashEntry(date: .now, lastWash: json["lastWash"].number.map { Date(timeIntervalSince1970: $0 / 1000) }, bottles: json["bottles"].number.map(Int.init), name: json["planName"].text)
    }
}
struct WashWidgetView: View {
    let entry: WashEntry
    let inventory: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(inventory ? "我的药剂库" : "上次认真洗护", systemImage: inventory ? "flask" : "car.side").font(.caption)
            Spacer(minLength: 0)
            if inventory {
                if let bottles = entry.bottles { Text("\(bottles) 瓶").font(.largeTitle).fontWeight(.medium) }
                else { Text("等待同步").font(.title3) }
            } else if let last = entry.lastWash { Text(last, style: .relative).font(.title2).fontWeight(.medium) }
            else { Text("留一点时间，\n给爱车。").font(.title3) }
            Text(inventory ? "核对余量，再从容出发。" : entry.name).font(.caption2).lineLimit(2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(Color(red: 0.08, green: 0.27, blue: 0.25).gradient, for: .widget).foregroundStyle(.white)
            .widgetURL(URL(string: inventory ? "washmycar://inventory" : "washmycar://records"))
    }
}
struct LastWashWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LastWash", provider: WashProvider()) { WashWidgetView(entry: $0, inventory: false) }
            .configurationDisplayName("距上次洗车").description("留一点时间，给爱车。").supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct InventoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Inventory", provider: WashProvider()) { WashWidgetView(entry: $0, inventory: true) }
            .configurationDisplayName("药剂库").description("随时查看药剂瓶数。").supportedFamilies([.systemSmall, .systemMedium])
    }
}
@main
struct WashWidgetBundle: WidgetBundle {
    var body: some Widget { LastWashWidget(); InventoryWidget() }
}
