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
        let delay: TimeInterval = entry.summary?.cabinet == nil ? 15 * 60 : 60 * 60
        completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(delay))))
    }
    private func read() -> WashEntry { WashEntry(date: .now, summary: try? WidgetSummary.read()) }
}

struct LastWashView: View {
    let entry: WashEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("距上次洗车", systemImage: "car.side")
                .font(.caption.weight(.semibold)).widgetAccentable()
            Spacer(minLength: 0)
            if let summary = entry.summary {
                if let last = summary.lastWash {
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
        .widgetURL(URL(string: "washmycar://records"))
    }
}

struct CabinetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: WashEntry

    private var columns: Int { family == .systemSmall ? 2 : 4 }
    private var rows: Int { family == .systemLarge ? 2 : 1 }
    private var dark: Bool { scheme == .dark }
    private var ink: Color { dark ? .white : Color(red: 0.10, green: 0.19, blue: 0.16) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("药剂柜").font(.system(size: 19, weight: .bold, design: .rounded))
                Spacer(minLength: 3)
                if let count = entry.summary?.cabinet?.bottleCount {
                    Text("\(count) 款瓶装").font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit().widgetAccentable()
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 5)
            .accessibilityElement(children: .combine)

            VStack(spacing: 2) {
                ForEach(0..<rows, id: \.self) { row in
                    let bottles = entry.summary?.cabinet?.bottles ?? []
                    let contents = Array(bottles.dropFirst(row * columns).prefix(columns))
                    let emptyMessage = row == 0 && contents.isEmpty
                        ? (entry.summary?.cabinet == nil ? "打开 App 同步" : "暂无可展示的瓶装药剂") : nil
                    CabinetShelf(bottles: contents, columns: columns, emptyMessage: emptyMessage)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(ink.opacity(0.18), lineWidth: 0.7))
        }
        .padding(.horizontal, 9)
        .padding(.top, 11)
        .padding(.bottom, 8)
        .containerBackground(for: .widget) {
            (dark ? Color(red: 0.11, green: 0.17, blue: 0.15) : Color(red: 0.94, green: 0.95, blue: 0.91))
        }
        .widgetURL(URL(string: "washmycar://inventory"))
    }
}

private struct CabinetShelf: View {
    @Environment(\.colorScheme) private var scheme
    let bottles: [CabinetBottle]
    let columns: Int
    let emptyMessage: String?

    private var dark: Bool { scheme == .dark }
    private var panel: Color {
        dark ? Color(red: 0.20, green: 0.30, blue: 0.26) : Color(red: 0.83, green: 0.87, blue: 0.81)
    }
    private var labelBackground: Color {
        dark ? Color(red: 0.14, green: 0.22, blue: 0.19) : Color(red: 0.91, green: 0.93, blue: 0.89)
    }
    private var rail: Color {
        dark ? Color(red: 0.42, green: 0.46, blue: 0.40) : Color(red: 0.60, green: 0.66, blue: 0.57)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [panel.opacity(0.78), panel, panel.opacity(0.85)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // Peg holes sit on the cabinet uprights, outside the bottle display area.
                HStack {
                    pegHoles
                    Spacer()
                    pegHoles
                }.padding(.horizontal, 4)

                if let emptyMessage {
                    Text(emptyMessage)
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 0) {
                        ForEach(0..<columns, id: \.self) { index in
                            ZStack(alignment: .bottom) {
                                if index < bottles.count { CabinetPhoto(bottle: bottles[index]) }
                            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.top, 5)
                }
            }
            HStack(spacing: 0) {
                ForEach(0..<columns, id: \.self) { index in
                    VStack(spacing: 1) {
                        if index < bottles.count {
                            let bottle = bottles[index]
                            Text(CabinetProduct.label(for: bottle))
                                .accessibilityLabel(bottle.name)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.80)
                            Text(bottle.stock)
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.80)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 2)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 32)
            .background(labelBackground)
            .overlay(alignment: .top) {
                Rectangle().fill(.black.opacity(0.12)).frame(height: 1)
            }
            .overlay(alignment: .top) {
                LinearGradient(colors: [.white.opacity(0.8), rail, rail.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 4).offset(y: -4)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var pegHoles: some View {
        VStack(spacing: 7) {
            ForEach(0..<3) { _ in Circle().fill(.primary.opacity(0.22)).frame(width: 2, height: 2) }
        }.accessibilityHidden(true)
    }
}

private struct CabinetProduct: Decodable {
    let id: String
    let name: String
    let shelfName: String?

    private static let catalog: [String: CabinetProduct] = {
        guard let url = Bundle.main.url(forResource: "OwnedProducts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let products = try? JSONDecoder().decode([CabinetProduct].self, from: data) else { return [:] }
        return Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }()

    static func label(for bottle: CabinetBottle) -> String {
        guard let original = catalog[bottle.id], original.name == bottle.name else { return bottle.name }
        return original.shelfName ?? bottle.name
    }
}

private struct CabinetPhoto: View {
    let bottle: CabinetBottle

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse().fill(.black.opacity(0.15))
                .frame(maxWidth: 28, maxHeight: 3).offset(y: -3)
            if let photo = UIImage(named: bottle.coverAsset) {
                let image = Image(uiImage: photo)
                if #available(iOS 18.0, *) {
                    image.resizable().widgetAccentedRenderingMode(.fullColor).scaledToFit()
                } else {
                    image.resizable().scaledToFit()
                }
            }
        }
        .padding(.horizontal, 3)
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }
}

struct LastWashWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LastWash", provider: WashProvider()) { LastWashView(entry: $0) }
            .configurationDisplayName("距上次洗车").description("查看距离上次洗车的时间和当时的方案。").supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct InventoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Inventory", provider: WashProvider()) { CabinetView(entry: $0) }
            .configurationDisplayName("瓶装药剂柜").description("陈列在库药剂的单瓶实拍、名称和余量。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
            .contentMarginsDisabled()
    }
}

@main
struct WashWidgetBundle: WidgetBundle {
    var body: some Widget {
        InventoryWidget()
        LastWashWidget()
    }
}
