import Foundation

public enum PersonalLibrary {
    public static let categories = ["全部用途", "预洗", "正洗", "轮毂", "轮胎清洁", "去虫胶", "玻璃清洁", "脱脂", "油膜清洁", "柏油清洁", "内饰清洁", "内饰养护", "轮胎养护", "QD", "镀晶", "保护", "内饰"]
    public static func unit(_ p: JSON) -> String { p["quantityUnit"].text == "g" ? "g" : "mL" }
    public static func uses(_ p: JSON) -> [String] {
        p["uses"].array.isEmpty ? (p["use"].text.isEmpty ? [] : [p["use"].text]) : p["uses"].array.map(\.text)
    }
    /// User-requested additions are applied once; stock, purchases and snapshots are never replaced.
    public static func importOwned(_ state: JSON, catalog: JSON) -> JSON {
        let token = "20261112-01"
        guard !state["catalogImports"].array.contains(.string(token)) else { return state }
        var products = state["products"].array
        for item in catalog.array {
            if let i = products.firstIndex(where: { $0.id == item.id || ($0["brand"] == item["brand"] && $0["name"] == item["name"]) }) {
                let union = Array(Set(uses(products[i]) + uses(item))).sorted()
                products[i] = products[i].replacing(["uses": .array(union.map(JSON.string)), "searchTerms": item["searchTerms"], "coverAsset": item["coverAsset"], "coverURL": item["coverURL"], "coverPending": item["coverPending"], "coverSource": item["coverSource"], "referenceURL": item["referenceURL"]])
            } else { products.append(item) }
        }
        return state.replacing(["products": .array(products), "catalogImports": .array(state["catalogImports"].array + [.string(token)])])
    }
    public static func removeRecord(_ state: JSON, id: String) -> JSON {
        guard let record = state["washes"].array.first(where: { $0.id == id }) else { return state }
        return state.replacing(["washes": .array(state["washes"].array.filter { $0.id != id }),
                                "deletedWashes": .array([record] + state["deletedWashes"].array),
                                "deferredNoteIds": .array(state["deferredNoteIds"].array.filter { $0.text != id })])
    }
    public static func restoreRecord(_ state: JSON, id: String) -> JSON {
        guard let record = state["deletedWashes"].array.first(where: { $0.id == id }) else { return state }
        return state.replacing(["washes": .array(([record] + state["washes"].array).sorted { ($0["finishedAt"].number ?? 0) > ($1["finishedAt"].number ?? 0) }),
                                "deletedWashes": .array(state["deletedWashes"].array.filter { $0.id != id })])
    }
}
