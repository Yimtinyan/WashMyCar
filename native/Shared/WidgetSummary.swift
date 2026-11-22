import Foundation
import Security

/// Only the values displayed by the home-screen widgets leave the app's data container.
struct WidgetSummary: Codable, Equatable {
    let lastWash: Date?
    let lastWashName: String?
    let bottleCount: Int
    let bottleLines: [String]

    init(state: JSON, stockText: (JSON) -> String) {
        let last = state["washes"].array.max { ($0["finishedAt"].number ?? 0) < ($1["finishedAt"].number ?? 0) }
        lastWash = last?["finishedAt"].number.map { Date(timeIntervalSince1970: $0 / 1_000) }
        lastWashName = last.map { String($0["name"].text.prefix(80)) }
        let bottles = state["products"].array
        bottleCount = bottles.count
        bottleLines = bottles.prefix(2).map { "\($0["name"].text.prefix(48)) · \(stockText($0))" }
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
