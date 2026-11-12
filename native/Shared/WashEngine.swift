import Foundation
import CryptoKit

public enum WashEngine {
    public static func isActive(_ state: JSON) -> Bool { state["session"] != .null && !state["session"]["done"].flag }
    public static func stockKind(_ product: JSON) -> String {
        if product["stockStatus"].text == "unknown" || product["remaining"] == .null { return "unknown" }
        return product["stockStatus"].text == "exact" ? "exact" : "estimated"
    }
    public static func stockText(_ product: JSON) -> String {
        let kind = stockKind(product)
        return kind == "unknown" ? "余量未知" : "\(kind == "estimated" ? "约 " : "")\(volume(product["remaining"].number ?? 0)) \(PersonalLibrary.unit(product))"
    }
    public static func totals(_ plan: JSON) -> [String: Double] {
        plan["steps"].array.reduce(into: [:]) { result, step in
            let id = step["productId"].text
            if !id.isEmpty { result[id, default: 0] += step["amount"].number ?? 0 }
        }
    }
    public static func checkPreparation(_ state: JSON) throws {
        let plan = state["plan"]
        guard !plan["name"].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !plan["steps"].array.isEmpty else { throw WashError("请填写方案名称，至少保留一个步骤。") }
        for step in plan["steps"].array {
            guard !step["name"].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let water = step["water"].number, water.isFinite, water >= 0 else { throw WashError("请核对步骤名称与清水用量。") }
            if !step["productId"].text.isEmpty {
                guard let amount = step["amount"].number, amount.isFinite, amount > 0 else { throw WashError("请填写有效的药剂取用量。") }
            }
        }
        for (id, amount) in totals(plan) {
            guard let p = state["products"].array.first(where: { $0.id == id }) else { throw WashError("方案关联的药剂不存在。") }
            guard stockKind(p) != "unknown", let remaining = p["remaining"].number else { throw WashError("\(p["name"].text) 余量未知，请先核对。") }
            guard amount <= remaining else { throw WashError("\(p["name"].text) 库存不足，还差 \(volume(amount - remaining)) \(PersonalLibrary.unit(p))。") }
        }
    }

    public static func prepare(_ state: JSON, now: Double = milliseconds(), id: String = identifier()) throws -> JSON {
        if isActive(state) { return state }
        try checkPreparation(state)
        let plan = state["plan"], amounts = totals(plan)
        let ledgerID = "prepare:\(id)"
        guard !state["history"].array.contains(where: { $0.id == ledgerID }) else { return state }
        let session: JSON = .object([
            "id": .string(id), "plan": plan, "products": state["products"], "index": .number(0),
            "status": .string("prepared"), "paused": .bool(false), "done": .bool(false),
            "preparedAt": .number(now), "startedAt": .null, "resumedAt": .null, "activeMs": .number(0),
            "location": .string(plan["location"].text.isEmpty ? "未填写地点" : plan["location"].text),
            "snapshotVersion": .number(1), "planSnapshotId": .string("\(id):plan"),
            "owner": .string("unassigned"), "revision": .number(0),
            "egg": .string(["glow", "stars", "halo"].randomElement()!)
        ])
        let products = state["products"].array.map { p -> JSON in
            guard let n = amounts[p.id] else { return p }
            return p.replacing(["remaining": .number(((p["remaining"].number! - n) * 100).rounded() / 100), "stockStatus": .string("estimated")])
        }
        let usage: JSON = .object(["id": .string(ledgerID), "sessionId": .string(id), "kind": .string("preparation"),
                                   "date": .string(isoDate(now)), "plan": plan["name"], "vehicle": plan["vehicle"],
                                   "location": session["location"], "amounts": .object(amounts.mapValues(JSON.number))])
        return state.replacing(["session": session, "products": .array(products), "history": .array([usage] + state["history"].array)])
    }

    /// Hash only immutable payload, never progress. Used for transfer integrity, not identity/authentication.
    public static func checksum(_ session: JSON) throws -> String {
        let payload: JSON = .object(["version": .number(1), "id": session["id"], "plan": session["plan"], "products": session["products"]])
        return SHA256.hash(data: try payload.encoded()).map { String(format: "%02x", $0) }.joined()
    }

    public static func assignWatch(_ state: JSON) throws -> JSON {
        guard isActive(state), state["session"]["startedAt"] == .null,
              ["unassigned", "watch"].contains(state["session"]["owner"].text) else { throw WashError("当前流程不能交给手表。") }
        // Persist ownership before sending. No phone takeover without a future explicit two-device handshake.
        let s = state["session"].replacing(["owner": .string("watch"), "transferStatus": .string("pending")])
        return state.replacing(["session": s])
    }

    public static func advance(_ original: JSON, action: String, actor: String, now: Double = milliseconds()) throws -> JSON {
        var s = original
        guard s != .null, !s["done"].flag else { return s }
        let owner = s["owner"].text
        guard owner == actor || (owner == "unassigned" && actor == "phone") else { throw WashError("请在当前负责执行的设备上操作。") }
        switch action {
        case "start":
            guard s["startedAt"] == .null else { return s }
            s = s.replacing(["owner": .string(actor), "startedAt": .number(now), "resumedAt": .number(now), "status": .string("washing")])
        case "pause":
            guard s["startedAt"].number != nil else { return s }
            if s["paused"].flag { s = s.replacing(["paused": .bool(false), "resumedAt": .number(now)]) }
            else { s = s.replacing(["paused": .bool(true), "activeMs": .number(activeTime(s, now: now)), "resumedAt": .null]) }
        case "next":
            guard s["startedAt"].number != nil, !s["paused"].flag else { return s }
            let index = Int(s["index"].number ?? 0)
            if index + 1 < s["plan"]["steps"].array.count { s["index"] = .number(Double(index + 1)) }
            else { s = s.replacing(["done": .bool(true), "status": .string("completed"), "finishedAt": .number(now),
                                   "activeMs": .number(activeTime(s, now: now)), "resumedAt": .null]) }
        default: throw WashError("不支持的流程操作。")
        }
        s["revision"] = .number((s["revision"].number ?? 0) + 1)
        return s
    }

    public static func wallTime(_ s: JSON, now: Double = milliseconds()) -> Double {
        guard let start = s["startedAt"].number else { return 0 }
        return max(0, (s["finishedAt"].number ?? now) - start)
    }
    public static func activeTime(_ s: JSON, now: Double = milliseconds()) -> Double {
        let extra = !s["paused"].flag && !s["done"].flag ? max(0, now - (s["resumedAt"].number ?? now)) : 0
        return min(wallTime(s, now: now), max(0, (s["activeMs"].number ?? 0) + extra))
    }

    public static func replacingSession(_ state: JSON, with s: JSON) -> JSON {
        var next = state.replacing(["session": s])
        if s["done"].flag && !(state["washes"].array + state["deletedWashes"].array).contains(where: { $0.id == s.id }) {
            let duration = wallTime(s)
            let record = s["plan"].replacing([
                "id": s["id"], "date": .string(isoDate(s["finishedAt"].number ?? milliseconds())),
                "preparedAt": s["preparedAt"], "startedAt": s["startedAt"], "finishedAt": s["finishedAt"],
                "durationMs": .number(duration), "activeMs": s["activeMs"], "pausedMs": .number(max(0, duration - (s["activeMs"].number ?? 0))),
                "snapshotVersion": .number(1), "planSnapshotId": s["planSnapshotId"], "products": s["products"],
                "amounts": .object(totals(s["plan"]).mapValues(JSON.number)), "location": s["location"],
                "egg": s["egg"], "notes": .string(""), "noteStatus": .string("open")
            ])
            next["washes"] = .array([record] + state["washes"].array)
            next["deferredNoteIds"] = .array([])
        }
        return next
    }

    public static func acceptWatchProgress(_ state: JSON, incoming: JSON) throws -> JSON {
        let old = state["session"]
        guard isActive(state), old["owner"].text == "watch", incoming.id == old.id,
              incoming["owner"].text == "watch", try checksum(incoming) == checksum(old) else { return state }
        guard let revision = incoming["revision"].number, revision > (old["revision"].number ?? 0), revision.rounded() == revision else { return state }
        try Backup.validateSession(incoming)
        guard (incoming["index"].number ?? -1) >= (old["index"].number ?? 0),
              incoming["preparedAt"] == old["preparedAt"], incoming["location"] == old["location"],
              incoming["planSnapshotId"] == old["planSnapshotId"],
              old["startedAt"] == .null || incoming["startedAt"] == old["startedAt"] else { throw WashError("手表进度与当前流程不一致。") }
        return replacingSession(state, with: incoming.replacing(["transferStatus": .string("ready")]))
    }

    public static func manualUsage(_ state: JSON, productID: String, amount: Double, location: String, now: Double = milliseconds()) throws -> JSON {
        guard amount.isFinite, amount > 0, let p = state["products"].array.first(where: { $0.id == productID }),
              stockKind(p) != "unknown", let remaining = p["remaining"].number, amount <= remaining else { throw WashError("请核对取用量和库存。") }
        let products = state["products"].array.map { $0.id == productID ? $0.replacing(["remaining": .number(((remaining - amount) * 100).rounded() / 100), "stockStatus": .string("estimated")]) : $0 }
        let usage: JSON = .object(["id": .string(identifier()), "kind": .string("usage"), "productId": .string(productID),
                                   "amount": .number(amount), "location": .string(location), "date": .string(isoDate(now))])
        return state.replacing(["products": .array(products), "history": .array([usage] + state["history"].array)])
    }

    public static func pendingNotes(_ state: JSON) -> [JSON] {
        state["washes"].array.filter { $0["vehicleId"] == state["plan"]["vehicleId"] && !$0["notes"].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0["noteStatus"].text != "resolved" && !state["deferredNoteIds"].array.contains(.string($0.id)) }
    }
}
