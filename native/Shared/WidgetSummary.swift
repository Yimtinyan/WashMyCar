import Foundation
import Security

struct CabinetBottle: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let stock: String
    let coverAsset: String?
}

/// Only the values displayed by the home-screen widgets leave the app's data container.
struct WidgetSummary: Codable, Equatable {
    let lastWash: Date?
    let lastWashName: String?
    let bottleCount: Int
    let bottles: [CabinetBottle]

    init(state: JSON, stockText: (JSON) -> String) {
        let last = state["washes"].array.max { ($0["finishedAt"].number ?? 0) < ($1["finishedAt"].number ?? 0) }
        lastWash = last?["finishedAt"].number.map { Date(timeIntervalSince1970: $0 / 1_000) }
        lastWashName = last.map { String($0["name"].text.prefix(80)) }
        let products = state["products"].array
        bottleCount = products.count
        bottles = products.prefix(8).map { product in
            let cover = product["coverAsset"].text
            let localCover = cover.hasPrefix("Product-") && cover.utf8.count <= 96 ? cover : nil
            return CabinetBottle(id: product.id, name: String(product["name"].text.prefix(48)),
                                 stock: stockText(product), coverAsset: localCover)
        }
    }

    init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        lastWash = try data.decodeIfPresent(Date.self, forKey: .lastWash)
        lastWashName = try data.decodeIfPresent(String.self, forKey: .lastWashName)
        bottleCount = try data.decode(Int.self, forKey: .bottleCount)
        if let entries = try data.decodeIfPresent([CabinetBottle].self, forKey: .bottles) {
            bottles = entries
        } else {
            // Build 7 widgets can be refreshed before the updated phone app first opens.
            enum LegacyKeys: String, CodingKey { case bottleLines }
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let lines = try legacy.decode([String].self, forKey: .bottleLines)
            bottles = lines.enumerated().map { offset, line in
                let parts = line.range(of: " · ", options: .backwards)
                return CabinetBottle(id: "legacy-\(offset)", name: parts.map { String(line[..<$0.lowerBound]) } ?? line,
                                     stock: parts.map { String(line[$0.upperBound...]) } ?? "", coverAsset: nil)
            }
        }
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
