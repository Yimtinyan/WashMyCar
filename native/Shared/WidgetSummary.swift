import Foundation
import Security

/// Resolve bundled product artwork without modifying inventory or historical snapshots.
enum BottleArtwork: Equatable {
    case verified(String)
    case noBottlePhoto
    case customURL(String)
    case original

    static func resolve(_ product: JSON, catalog: JSON) -> Self {
        guard let entry = catalog.array.first(where: {
            $0.id == product.id || ($0["name"] == product["name"] && $0["brand"] == product["brand"])
        }) else { return .original }
        let asset = product["coverAsset"].text
        let bottle = entry["cabinetBottleAsset"].text
        if !asset.isEmpty && asset != entry["coverAsset"].text && asset != bottle { return .original }
        let url = product["coverURL"].text
        if !url.isEmpty && url != entry["coverURL"].text { return .customURL(url) }
        return bottle.isEmpty ? .noBottlePhoto : .verified(bottle)
    }
}

struct CabinetBottle: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let stock: String
    let coverAsset: String
}

struct CabinetContents: Codable, Equatable {
    let bottleCount: Int
    let bottles: [CabinetBottle]
}

/// Only the values displayed by the home-screen widgets leave the app's data container.
struct WidgetSummary: Codable, Equatable {
    let lastWash: Date?
    let lastWashName: String?
    // Older summaries contain unfiltered inventory. Show the last wash until the app refreshes the shelf.
    let cabinet: CabinetContents?

    init(state: JSON, catalog: JSON, stockText: (JSON) -> String) {
        let last = state["washes"].array.max { ($0["finishedAt"].number ?? 0) < ($1["finishedAt"].number ?? 0) }
        lastWash = last?["finishedAt"].number.map { Date(timeIntervalSince1970: $0 / 1_000) }
        lastWashName = last.map { String($0["name"].text.prefix(80)) }
        var count = 0
        var bottles: [CabinetBottle] = []
        for product in state["products"].array {
            guard case .verified(let asset) = BottleArtwork.resolve(product, catalog: catalog) else { continue }
            count += 1
            if bottles.count < 8 {
                bottles.append(CabinetBottle(id: product.id, name: String(product["name"].text.prefix(48)),
                                             stock: stockText(product), coverAsset: asset))
            }
        }
        cabinet = CabinetContents(bottleCount: count, bottles: bottles)
    }

    private static func item() throws -> [String: Any] {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "WashWidgetAccessGroup") as? String,
              !group.isEmpty else { throw WashError("缺少小组件共享组配置。") }
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccessGroup as String: group,
                kSecAttrService as String: "WashMyCar.WidgetSummary",
                kSecAttrAccount as String: "summary",
                kSecUseDataProtectionKeychain as String: true]
    }

    private static func readData(_ query: [String: Any]) throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return data
    }

    static func read() throws -> WidgetSummary? {
        try readData(item()).map { try JSONDecoder().decode(WidgetSummary.self, from: $0) }
    }

    /// Ask WidgetKit for a new timeline only after the displayed values change.
    func saveIfChanged() throws -> Bool {
        let query = try Self.item()
        let previous = try Self.readData(query)
        if let previous, (try? JSONDecoder().decode(Self.self, from: previous)) == self { return false }
        let data = try JSONEncoder().encode(self)
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status: OSStatus
        if previous != nil {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return true
    }
}
