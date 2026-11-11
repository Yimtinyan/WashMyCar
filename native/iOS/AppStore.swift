import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var state: JSON = .null
    @Published var error: String?
    @Published var loadFailed = false
    let connection = Connectivity()
    private let repository: StateRepository

    init() {
        let folder = URL.applicationSupportDirectory.appendingPathComponent("WashMyCar", isDirectory: true)
        repository = StateRepository(url: folder.appendingPathComponent("State.json"))
        do {
            state = try repository.load {
                guard let url = Bundle.main.url(forResource: "Seed", withExtension: "json") else { throw WashError("缺少初始资料。") }
                return Backup.migrate(try JSON.read(Data(contentsOf: url)))
            }
        } catch { self.error = "本机资料读取失败，原文件已保留。\n\(error.localizedDescription)"; loadFailed = true }
        connection.receive = { [weak self] kind, payload, checksum in self?.receive(kind, payload, checksum) }
        writeWidget()
    }
    var active: Bool { WashEngine.isActive(state) }
    func perform(_ work: () throws -> Void) { do { try work() } catch { self.error = error.localizedDescription } }
    func commit(_ next: JSON) throws {
        guard !loadFailed else { throw WashError("原资料读取失败，请先检查或恢复备份。") }
        try repository.save(next)
        state = next
        writeWidget()
    }
    func editPlan(_ plan: JSON) throws {
        guard !active else { throw WashError("已备液流程不可修改。") }
        try commit(state.replacing(["plan": plan, "session": .null]))
    }
    func saveProduct(_ product: JSON) throws {
        var products = state["products"].array
        if let index = products.firstIndex(where: { $0.id == product.id }) { products[index] = product }
        else { products.append(product) }
        try commit(state.replacing(["products": .array(products)]))
    }
    func prepare() throws { try commit(WashEngine.prepare(state)) }
    func action(_ action: String) throws {
        let session = try WashEngine.advance(state["session"], action: action, actor: "phone")
        try commit(WashEngine.replacingSession(state, with: session))
    }
    func sendToWatch() throws {
        try connection.checkAvailability(payload: state["session"])
        try commit(WashEngine.assignWatch(state))
        try connection.send(kind: "plan", payload: state["session"])
    }
    private func receive(_ kind: String, _ incoming: JSON, _ checksum: String) {
        guard kind == "progress", !loadFailed else { return }
        perform {
            guard active, state["session"].id == incoming.id, state["session"]["owner"].text == "watch", incoming["owner"].text == "watch",
                  try WashEngine.checksum(state["session"]) == checksum,
                  try WashEngine.checksum(incoming) == checksum else { return }
            try Backup.validateSession(incoming)
            let acknowledged = state.replacing(["session": state["session"].replacing(["transferStatus": .string("ready")])])
            try commit(WashEngine.acceptWatchProgress(acknowledged, incoming: incoming))
        }
    }
    func updateNote(id: String, text: String) throws {
        let records = state["washes"].array.map { $0.id == id ? $0.replacing(["notes": .string(text), "noteStatus": .string("open"), "notesUpdatedAt": .number(milliseconds())]) : $0 }
        try commit(state.replacing(["washes": .array(records), "deferredNoteIds": .array(state["deferredNoteIds"].array.filter { $0.text != id })]))
    }
    func noteStatus(id: String, resolved: Bool) throws {
        try commit(state.replacing(["washes": .array(state["washes"].array.map { $0.id == id ? $0.replacing(["noteStatus": .string(resolved ? "resolved" : "open")]) : $0 })]))
    }
    func applyTemplate(_ template: JSON) throws {
        let current = state["plan"]
        let plan = template["plan"].replacing(["vehicle": current["vehicle"], "vehicleId": current["vehicleId"], "vehicleModel": current["vehicleModel"],
                                                "templateId": template["id"], "revision": template["revision"],
                                                "steps": .array(template["plan"]["steps"].array.map { $0.replacing(["id": .string(identifier())]) })])
        try editPlan(plan)
    }
    func saveTemplate(name: String, updating: Bool) throws {
        guard !active, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WashError("请填写方案名称，并先完成当前流程。") }
        let old = updating ? state["templates"].array.first(where: { $0.id == state["plan"]["templateId"].text }) : nil
        guard old?["builtIn"].flag != true else { throw WashError("内置原稿不可覆盖，请另存个人方案。") }
        let revision = (old?["revision"].number ?? 0) + 1
        let t: JSON = .object(["id": old?["id"] ?? .string(identifier()), "name": .string(name), "builtIn": .bool(false),
                               "revision": .number(revision), "plan": state["plan"].replacing(["name": .string(name), "revision": .number(revision)])])
        var templates = state["templates"].array
        if let index = templates.firstIndex(where: { $0.id == t.id }) { templates[index] = t } else { templates.append(t) }
        try commit(state.replacing(["templates": .array(templates), "plan": state["plan"].replacing(["templateId": t["id"], "revision": .number(revision)])]))
    }
    func restore(_ imported: JSON) throws {
        guard !active else { throw WashError("请先完成当前洗车流程，再恢复资料。") }
        try repository.restore(imported)
        state = imported; loadFailed = false; writeWidget()
    }
    private func writeWidget() {
        #if !LOCAL_DEVICE_PREVIEW
        guard state != .null, let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.yimtinyan.WashMyCar") else { return }
        let snapshot: JSON = .object(["lastWash": state["washes"].array.first?["finishedAt"] ?? .null,
                                      "planName": state["plan"]["name"], "bottles": .number(Double(state["products"].array.count))])
        do { try snapshot.encoded().write(to: group.appendingPathComponent("Widget.json"), options: .atomic); WidgetCenter.shared.reloadAllTimelines() }
        catch { /* Widget failure must not invalidate the committed inventory transaction. */ }
        #endif
    }
}
