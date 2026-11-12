import Foundation

public enum Backup {
    public static let maxBytes = 12 * 1024 * 1024

    public static func decode(_ data: Data) throws -> JSON {
        guard data.count <= maxBytes else { throw WashError("备份超过 12 MB。") }
        let b = try JSON.read(data)
        guard b["format"].text == "WashMyCarBackup", b["schemaVersion"].number == 1,
              let version = b["appVersion"].number, (2...6).contains(version),
              b["volumeUnit"].text == "mL", b["healthDataIncluded"] == .bool(false),
              b["attachments"] == .array([]) else { throw WashError("备份格式、版本或单位不兼容。") }
        try validate(b["data"], requireVehicles: (b["data"]["version"].number ?? 0) >= 5)
        let state = migrate(b["data"])
        try validate(state)
        // A restored snapshot must not create a second executor for a live Watch session.
        if WashEngine.isActive(state) && state["session"]["owner"].text == "watch" {
            throw WashError("此备份含由手表执行的未完成流程。请先在原设备完成并同步，再导出备份。")
        }
        return state
    }

    public static func encode(_ state: JSON) throws -> Data {
        try validate(state)
        var sanitized = state
        for key in ["washes", "deletedWashes"] { sanitized[key] = .array(state[key].array.map { $0.removing(["health", "heartRateSamples"]) }) }
        if sanitized["session"] != .null { sanitized["session"] = sanitized["session"].removing(["health", "heartRateSamples"]) }
        let b: JSON = .object(["format": .string("WashMyCarBackup"), "schemaVersion": .number(1), "appVersion": .number(6),
                               "volumeUnit": .string("mL"), "healthDataIncluded": .bool(false), "attachments": .array([]),
                               "createdAt": .string(isoDate(milliseconds())), "data": sanitized])
        let data = try b.encoded()
        guard data.count <= maxBytes else { throw WashError("备份超过 12 MB。") }
        return data
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw WashError(message) }
    }
    private static func text(_ x: JSON, _ label: String, max: Int = 4000) throws {
        guard case .string(let value) = x, value.count <= max else { throw WashError("\(label)格式不正确。") }
    }
    private static func number(_ x: JSON, _ label: String, min: Double = 0, max: Double = 9_007_199_254_740_991) throws {
        guard let n = x.number, n.isFinite, n >= min, n <= max else { throw WashError("\(label)不是有效数值。") }
    }
    private static func list(_ x: JSON, _ label: String) throws -> [JSON] {
        guard case .array(let items) = x, items.count <= 20_000 else { throw WashError("\(label)列表不正确。") }
        return items
    }
    private static func entries(_ x: JSON, _ label: String) throws -> [JSON] {
        let items = try list(x, label)
        var ids = Set<String>()
        for item in items {
            try text(item["id"], "\(label) ID", max: 200)
            try require(!item.id.isEmpty && ids.insert(item.id).inserted, "\(label)存在空白或重复 ID。")
        }
        return items
    }
    public static func validateProducts(_ x: JSON) throws {
        for p in try entries(x, "药剂") {
            try text(p["name"], "名称", max: 200); try text(p["brand"], "品牌", max: 200)
            if p["quantityUnit"] != .null { try require(["mL", "g"].contains(p["quantityUnit"].text), "药剂计量单位不正确。") }
            if p["uses"] != .null { for use in try list(p["uses"], "药剂用途") { try text(use, "用途", max: 200) } }
            if p["capacity"] != .null { try number(p["capacity"], "容量", min: 0.01) }
            else { try require(p["stockStatus"].text == "unknown" && p["remaining"] == .null, "容量未知时余量必须为未知。") }
            let kind = p["stockStatus"]
            try require(kind == .null || ["unknown", "exact", "estimated"].contains(kind.text), "库存可信度不正确。")
            if kind.text != "unknown" || p["remaining"] != .null { try number(p["remaining"], "余量", max: p["capacity"].number ?? 0) }
            if p["price"] != .null && p["price"] != .string("") { try number(p["price"], "价格") }
            for key in ["date", "place", "use", "instructions", "shape", "color", "label", "code"] where p[key] != .null { try text(p[key], key) }
            if p["ph"] != .null {
                try require(!p["ph"].object.isEmpty, "pH 格式不正确。")
                if p["ph"]["value"] != .null && p["ph"]["value"] != .string("") { try number(p["ph"]["value"], "pH", max: 14) }
                for key in ["medium", "source"] where p["ph"][key] != .null { try text(p["ph"][key], key) }
            }
        }
    }
    public static func validatePlan(_ p: JSON, products: JSON) throws {
        try text(p["name"], "方案名称", max: 200); try text(p["vehicle"], "车辆名称", max: 200)
        if p["location"] != .null { try text(p["location"], "地点") }
        let steps = try entries(p["steps"], "步骤"), ids = Set(products.array.map(\.id))
        try require(!steps.isEmpty, "方案至少需要一个步骤。")
        for s in steps {
            try text(s["name"], "步骤名称", max: 200); try text(s["productId"], "药剂关联", max: 200)
            try require(s["productId"].text.isEmpty || ids.contains(s["productId"].text), "方案关联了不存在的药剂。")
            for key in ["amount", "water"] where s[key] != .string("") { try number(s[key], "用量") }
            for tool in try list(s["tools"], "工具") { try text(tool, "工具", max: 200) }
            if s["note"] != .null { try text(s["note"], "步骤备注") }
        }
    }
    public static func validateSession(_ s: JSON, strictTiming: Bool = true) throws {
        try text(s["id"], "流程 ID", max: 200)
        try require(!s.id.isEmpty, "流程 ID 为空。")
        try validateProducts(s["products"]); try validatePlan(s["plan"], products: s["products"])
        try WashEngine.checkPreparation(.object(["plan": s["plan"], "products": s["products"]]))
        try number(s["index"], "步骤序号", max: Double(s["plan"]["steps"].array.count - 1))
        try require(s["index"].number!.rounded() == s["index"].number, "步骤序号不正确。")
        try require([.bool(true), .bool(false)].contains(s["done"]) && [.bool(true), .bool(false)].contains(s["paused"]), "流程状态不正确。")
        for key in ["preparedAt", "startedAt", "resumedAt", "finishedAt", "activeMs", "revision"] where s[key] != .null { try number(s[key], "流程时间或版本") }
        if let revision = s["revision"].number { try require(revision.rounded() == revision, "流程版本不正确。") }
        if s["owner"] != .null { try require(["unassigned", "phone", "watch"].contains(s["owner"].text), "执行设备不正确。") }
        if !strictTiming { return }
        if let start = s["startedAt"].number {
            try require(start >= (s["preparedAt"].number ?? 0), "流程开始时间早于备液时间。")
            if s["done"].flag {
                try require((s["finishedAt"].number ?? -1) >= start && s["status"].text == "completed", "流程完成时间不正确。")
                try require(Int(s["index"].number!) == s["plan"]["steps"].array.count - 1, "完成流程缺少步骤。")
                try require((s["activeMs"].number ?? 0) <= WashEngine.wallTime(s), "有效用时不正确。")
            } else {
                try require(s["status"].text == "washing", "进行中的流程状态不正确。")
                if !s["paused"].flag { try require((s["resumedAt"].number ?? -1) >= start, "恢复时间不正确。") }
            }
        } else {
            let legacyCompletion = s["done"].flag && s["timingUnavailable"].flag && s["status"].text == "completed"
            try require(legacyCompletion || (!s["done"].flag && !s["paused"].flag), "未开始流程的状态不正确。")
        }
    }
    public static func validate(_ state: JSON, requireVehicles: Bool = true) throws {
        try require([2.0, 3, 4, 5, 6].contains(state["version"].number ?? 0), "不支持此资料版本。")
        try validateProducts(state["products"]); try validatePlan(state["plan"], products: state["products"])
        let visible = try entries(state["washes"] == .null ? .array([]) : state["washes"], "记录")
        let archived = try entries(state["deletedWashes"] == .null ? .array([]) : state["deletedWashes"], "已删除记录")
        let washes = visible + archived
        try require(Set(washes.map(\.id)).count == washes.count, "记录与已删除记录 ID 重复。")
        let templates = try entries(state["templates"] == .null ? .array([]) : state["templates"], "已存方案")
        let vehicles = try entries(state["vehicles"] == .null ? .array([]) : state["vehicles"], "车辆")
        for v in vehicles { try text(v["name"], "车辆名称", max: 200) }
        for t in templates { try text(t["name"], "方案名称", max: 200); try validatePlan(t["plan"], products: state["products"]) }
        for w in washes {
            try validateProducts(w["products"]); try validatePlan(w, products: w["products"])
            try number(w["durationMs"], "洗车时长"); try number(w["finishedAt"], "完成时间")
            guard case .object(let amounts) = w["amounts"] else { throw WashError("记录用量格式不正确。") }
            for (id, n) in amounts { try require(w["products"].array.contains(where: { $0.id == id }), "记录快照不完整。") ; try number(n, "取用量") }
            if w["notes"] != .null { try text(w["notes"], "备注") }
            if w["noteStatus"] != .null { try require(["open", "resolved"].contains(w["noteStatus"].text), "备注状态不正确。") }
        }
        for h in try entries(state["history"] == .null ? .array([]) : state["history"], "使用履历") {
            try text(h["date"], "履历时间", max: 100)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try require(formatter.date(from: h["date"].text) != nil || ISO8601DateFormatter().date(from: h["date"].text) != nil, "履历时间不正确。")
            for n in h["amounts"].object.values { try number(n, "取用量") }
            if h["amount"] != .null { try number(h["amount"], "取用量") }
        }
        if state["session"] != .null { try validateSession(state["session"], strictTiming: (state["version"].number ?? 0) >= 5) }
        if requireVehicles {
            var associated = [state["plan"]] + washes + templates.map { $0["plan"] }
            if state["session"] != .null { associated.append(state["session"]["plan"]) }
            for p in associated { try require(vehicles.contains(where: { $0.id == p["vehicleId"].text && $0["name"] == p["vehicle"] }), "车辆关联不完整。") }
        }
        if state["settings"] != .null {
            guard case .object = state["settings"] else { throw WashError("偏好格式不正确。") }
            try require(["system", "light", "dark"].contains(state["settings"]["theme"].text), "外观设置不正确。")
        }
    }

    public static func migrate(_ input: JSON, now: Double = milliseconds()) -> JSON {
        var state = input, vehicles = input["vehicles"].array
        func associate(_ p: JSON) -> JSON {
            let name = p["vehicle"].text.isEmpty ? "我的爱车" : p["vehicle"].text
            let vehicle: JSON
            if let existing = vehicles.first(where: { $0.id == p["vehicleId"].text || $0["name"].text == name }) { vehicle = existing }
            else {
                vehicle = .object(["id": .string(identifier()), "name": .string(name), "modelKey": name.contains("乐道 L60") ? .string("onvo-l60") : .null])
                vehicles.append(vehicle)
            }
            return p.replacing(["vehicle": vehicle["name"], "vehicleId": vehicle["id"], "vehicleModel": p["vehicleModel"] == .null ? vehicle["modelKey"] : p["vehicleModel"]])
        }
        state["plan"] = associate(input["plan"])
        state["washes"] = .array(input["washes"].array.map { associate($0).replacing(["noteStatus": $0["noteStatus"] == .null ? .string("open") : $0["noteStatus"]]) })
        state["deletedWashes"] = .array(input["deletedWashes"].array.map { associate($0) })
        state["templates"] = .array(input["templates"].array.map { $0.replacing(["plan": associate($0["plan"]), "builtIn": .bool($0["builtIn"].flag || $0.id.hasPrefix("preset-"))]) })
        state["products"] = .array(input["products"].array.map { $0.replacing(["stockStatus": .string(WashEngine.stockKind($0))]) })
        state["history"] = .array(input["history"].array)
        state["deferredNoteIds"] = .array(input["deferredNoteIds"].array)
        state["settings"] = input["settings"].replacing(["theme": input["settings"]["theme"] == .null ? .string("system") : input["settings"]["theme"], "easterEggs": .bool(true)])
        if input["session"] != .null {
            var s = input["session"].replacing(["plan": associate(input["session"]["plan"])])
            if !s["done"].flag {
                if s["status"].text == "prepared" || (s["preparedAt"].number != nil && s["startedAt"] == .null) {
                    s = s.replacing(["status": .string("prepared"), "startedAt": .null, "resumedAt": .null, "activeMs": .number(0), "paused": .bool(false)])
                } else if s["startedAt"].number != nil {
                    s["status"] = .string("washing")
                } else {
                    // v2 did not store timer anchors. Continue from restoration without inventing past duration.
                    s = s.replacing(["status": .string("washing"), "startedAt": .number(now),
                                     "resumedAt": s["paused"].flag ? .null : .number(now),
                                     "activeMs": .number(0), "timingRestored": .bool(true)])
                }
            } else if s["startedAt"] == .null {
                s = s.replacing(["status": .string("completed"), "timingUnavailable": .bool(true)])
            }
            if s["owner"] == .null {
                s["owner"] = .string(s["startedAt"] == .null ? "unassigned" : "phone")
                s["revision"] = .number(0)
                s = s.removing(["watchPackage"])
            }
            if s["location"] == .null { s["location"] = .string(s["plan"]["location"].text.isEmpty ? "未填写地点" : s["plan"]["location"].text) }
            if s["planSnapshotId"] == .null { s["planSnapshotId"] = .string("\(s.id):plan") }
            state["session"] = s
        }
        state["vehicles"] = .array(vehicles)
        state["version"] = .number(6)
        return state
    }
}
