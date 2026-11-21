/// The phone persists cancellation before unlocking the plan editor. A replacement
/// handoff waits until the Watch has retired the old ID on disk.
enum WatchHandoff {
    static func cancel(_ state: JSON, sessionID: String) -> JSON {
        var next = WashEngine.cancel(state, sessionID: sessionID)
        guard next != state, state["session"]["owner"].text == "watch" else { return next }
        let id = JSON.string(sessionID)
        let pending = state["pendingWatchCancellations"].array
        if !pending.contains(id) { next["pendingWatchCancellations"] = .array(pending + [id]) }
        return next
    }

    static func nextTransfer(_ state: JSON) -> (kind: String, payload: JSON)? {
        if let first = state["pendingWatchCancellations"].array.first {
            return ("cancel", .object(["id": first]))
        }
        let session = state["session"]
        guard WashEngine.isActive(state), session["owner"].text == "watch",
              session["startedAt"] == .null, session["transferStatus"].text == "pending" else { return nil }
        return ("plan", session)
    }

    static func acknowledge(_ state: JSON, sessionID: String) -> JSON {
        let pending = state["pendingWatchCancellations"].array
        guard pending.contains(.string(sessionID)) else { return state }
        let remaining = pending.filter { $0 != .string(sessionID) }
        return remaining.isEmpty ? state.removing(["pendingWatchCancellations"])
            : state.replacing(["pendingWatchCancellations": .array(remaining)])
    }

    // A cancellation can arrive before its original plan, or again after a new
    // plan is running. Retire only its ID and never clear an unrelated session.
    static func retiring(_ id: String, in document: JSON) -> JSON {
        let previous = document["retired"].array
        let key = JSON.string(id)
        var next = document
        if !previous.contains(key) { next["retired"] = .array(previous + [key]) }
        if document["session"].id == id { next["session"] = .null }
        return next
    }

    static func receivingPlan(_ incoming: JSON, checksum: String, in document: JSON) throws -> JSON {
        guard incoming["owner"].text == "watch", incoming["startedAt"] == .null,
              !incoming["done"].flag, try WashEngine.checksum(incoming) == checksum else { throw WashError("方案内容核验失败。") }
        try Backup.validateSession(incoming)
        if document["retired"].array.contains(.string(incoming.id)) { return document }
        let current = document["session"]
        if incoming.id == current.id {
            guard try WashEngine.checksum(current) == checksum else { throw WashError("同一流程的内容发生变化。") }
            return document
        }
        guard current == .null || current["done"].flag else { throw WashError("请先在 iPhone 取消或在手表完成当前流程。") }
        let next = current == .null ? document : retiring(current.id, in: document)
        return next.replacing(["session": incoming])
    }

    static func validReceipt(_ payload: JSON, checksum: String) throws -> Bool {
        guard !payload.id.isEmpty, payload.id.count <= 200,
              payload == .object(["id": .string(payload.id)]) else { return false }
        return try WashEngine.checksum(payload) == checksum
    }
}
