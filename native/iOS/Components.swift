import SwiftUI
import CryptoKit

enum Style {
    static let green = Color("AccentColor")
    static let onAccent = Color("OnAccentColor")
    static let paper = Color(uiColor: .systemGroupedBackground)
}
struct PrimaryButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    var icon: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { if let icon { Image(systemName: icon) }; Text(title).fontWeight(.semibold) }
                .foregroundStyle(Style.onAccent)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
        }.buttonStyle(.plain).background(Style.green.opacity(0.19), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Style.green.opacity(0.15))).opacity(isEnabled ? 1 : 0.45)
    }
}
struct PageHeading: View {
    let title: String
    var subtitle = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(.largeTitle, design: .rounded, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 18)
    }
}
struct BottleView: View {
    let product: JSON
    var body: some View {
        Group {
            if !product["coverAsset"].text.isEmpty, let cover = UIImage(named: product["coverAsset"].text) {
                Image(uiImage: cover).resizable().scaledToFit()
            } else if !product["coverURL"].text.isEmpty {
                CachedProductCover(url: product["coverURL"].text)
            } else if product["coverPending"].flag {
                VStack { Image(systemName: "photo"); Text("封面待补充").font(.caption2) }.foregroundStyle(.secondary)
            } else if product.id == "gsf" || product.id == "hydro" {
                Image(product.id == "gsf" ? "GSF" : "Hydro").resizable().scaledToFit()
            } else {
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3).fill(.gray).frame(width: 19, height: 12)
                    RoundedRectangle(cornerRadius: 9).fill(Style.green.opacity(0.85))
                        .overlay { Text(product["brand"].text).font(.system(size: 8, weight: .bold)).foregroundStyle(.white).minimumScaleFactor(0.5).padding(4) }
                        .frame(width: 43, height: 75)
                }
            }
        }.accessibilityHidden(true)
    }
}
struct ProductSummary: View {
    let product: JSON
    var body: some View {
        HStack(spacing: 18) {
            BottleView(product: product).frame(width: 66, height: 96)
            VStack(alignment: .leading, spacing: 7) {
                Text(product["brand"].text).font(.caption).foregroundStyle(.secondary)
                Text(product["name"].text).font(.headline)
                Text(WashEngine.stockText(product)).font(.subheadline).foregroundStyle(.secondary)
                if WashEngine.stockKind(product) != "unknown" {
                    ProgressView(value: product["remaining"].number ?? 0, total: max(1, product["capacity"].number ?? 1)).tint(Style.green)
                }
            }
        }.padding(.vertical, 5)
    }
}
struct Celebration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: AppStore
    @State private var appeared = false
    let session: JSON
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: session["egg"].text == "stars" ? "sparkles" : session["egg"].text == "halo" ? "sun.max" : "checkmark.seal")
                .font(.system(size: 52)).foregroundStyle(Style.green)
                .scaleEffect(appeared ? 1 : 0.75)
            Text("又亮了一点。").font(.largeTitle)
            Text("每一份用心，都有回响。").foregroundStyle(.secondary)
            Text("洗车时长 \(clockText(WashEngine.wallTime(session)))").monospacedDigit()
        }.frame(maxWidth: .infinity).padding(.vertical, 28)
            .onAppear {
                if reduceMotion || store.state["settings"]["reducedMotion"].flag { appeared = true }
                else { withAnimation(.spring(duration: 0.7)) { appeared = true } }
            }
    }
}

struct CachedProductCover: View {
    let url: String
    @State private var photo: UIImage?
    var body: some View {
        Group {
            if let photo { Image(uiImage: photo).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }.task(id: url) {
            photo = nil
            guard let remote = URL(string: url), remote.scheme == "https" else { return }
            let folder = URL.applicationSupportDirectory.appendingPathComponent("ProductCovers")
            let key = SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
            let file = folder.appendingPathComponent(key)
            if let data = try? Data(contentsOf: file), let image = UIImage(data: data) { photo = image; return }
            do {
                let (data, response) = try await URLSession.shared.data(from: remote)
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 12 * 1024 * 1024,
                      let image = UIImage(data: data), !Task.isCancelled else { return }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic); photo = image
            } catch { /* Keep a clear placeholder and retry on next appearance. */ }
        }
    }
}
