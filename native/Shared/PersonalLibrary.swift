import Foundation

public enum PersonalLibrary {
    public static let categories = ["全部用途", "预洗", "正洗", "轮毂", "轮胎清洁", "去虫胶", "玻璃清洁", "脱脂", "油膜清洁", "柏油清洁", "内饰清洁", "内饰养护", "轮胎养护", "QD", "镀晶", "保护", "内饰"]
    public static func unit(_ p: JSON) -> String { p["quantityUnit"].text == "g" ? "g" : "mL" }
    public static func uses(_ p: JSON) -> [String] {
        p["uses"].array.isEmpty ? (p["use"].text.isEmpty ? [] : [p["use"].text]) : p["uses"].array.map(\.text)
    }
    /// Each catalog change runs once, leaving later inventory edits and restores alone.
    public static func importOwned(_ state: JSON, catalog: JSON) -> JSON {
        let addition = JSON.string("20261112-01"), cleanup = JSON.string("20261122-owned-library")
        var imports = state["catalogImports"].array
        guard !catalog.array.isEmpty, !imports.contains(cleanup) else { return state }
        var products = state["products"].array
        var deleted = state["deletedProducts"].array
        func matches(_ product: JSON, _ item: JSON) -> Bool {
            product.id == item.id || (product["brand"] == item["brand"] && product["name"] == item["name"])
        }
        if !imports.contains(addition) {
            for item in catalog.array {
                if let i = products.firstIndex(where: { matches($0, item) }) {
                    let union = Array(Set(uses(products[i]) + uses(item))).sorted()
                    products[i] = products[i].replacing(["uses": .array(union.map(JSON.string)), "searchTerms": item["searchTerms"], "coverAsset": item["coverAsset"], "coverURL": item["coverURL"], "coverPending": item["coverPending"], "coverSource": item["coverSource"], "referenceURL": item["referenceURL"]])
                } else if !deleted.contains(where: { matches($0, item) }) {
                    products.append(item)
                }
            }
            imports.append(addition)
        }
        // Move complete bottles, including purchase metadata, without editing any historical snapshot.
        products.removeAll { product in
            guard !catalog.array.contains(where: { matches(product, $0) }) else { return false }
            deleted.append(product)
            return true
        }
        return state.replacing(["products": .array(products), "deletedProducts": .array(deleted), "catalogImports": .array(imports + [cleanup])])
    }
    public static func removeProduct(_ state: JSON, id: String) -> JSON {
        guard let product = state["products"].array.first(where: { $0.id == id }) else { return state }
        return state.replacing(["products": .array(state["products"].array.filter { $0.id != id }),
                                "deletedProducts": .array([product] + state["deletedProducts"].array)])
    }
    public static func restoreProduct(_ state: JSON, id: String) -> JSON {
        guard let product = state["deletedProducts"].array.first(where: { $0.id == id }) else { return state }
        return state.replacing(["products": .array(state["products"].array + [product]),
                                "deletedProducts": .array(state["deletedProducts"].array.filter { $0.id != id })])
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
