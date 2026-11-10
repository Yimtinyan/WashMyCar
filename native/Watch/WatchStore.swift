import Foundation
import SwiftUI
import WatchKit

@MainActor
final class WatchStore: ObservableObject {
    @Published private(set) var session: JSON = .null
    @Published var error: String?
    let connection = Connectivity()
    private let url = URL.applicationSupportDirectory.appendingPathComponent("WatchState.json")
    private var retired: [JSON] = []
    private var loadFailed = false

    init() {
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let stored = try JSON.read(Data(contentsOf: url))
                if stored["session"] != .null { try Backup.validateSession(stored["session"]) }
                session = stored["session"]; retired = stored["retired"].array
            } catch { self.error = "手表资料读取失败，原文件已保留。"; loadFailed = true }
        }
        connection.receive = { [weak self] kind, payload, checksum in self?.receive(kind, payload, checksum) }
        connection.activated = { [weak self] in self?.sync() }
    }
    private func persist(_ next: JSON, retired: [JSON]) throws {
        guard !loadFailed else { throw WashError("请先检查手表资料文件。") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let document: JSON = .object(["session": next, "retired": .array(retired)])
        try document.encoded().write(to: url, options: .atomic)
        self.retired = retired; session = next
    }
    private func receive(_ kind: String, _ incoming: JSON, _ checksum: String) {
        guard kind == "plan" else { return }
        do {
            guard incoming["owner"].text == "watch", incoming["startedAt"] == .null,
                  !incoming["done"].flag, try WashEngine.checksum(incoming) == checksum else { throw WashError("方案内容核验失败。") }
            try Backup.validateSession(incoming)
            if incoming.id == session.id {
                guard try WashEngine.checksum(session) == checksum else { throw WashError("同一流程的内容发生变化。") }
                sync(); return
            }
            if retired.contains(.string(incoming.id)) { return }
            guard session == .null || session["done"].flag else { throw WashError("请先完成手表上的当前流程。") }
            var archive = retired
            if session != .null { archive.append(.string(session.id)) }
            try persist(incoming, retired: archive)
            WKInterfaceDevice.current().play(.notification)
            sync()
        } catch { self.error = error.localizedDescription }
    }
    func action(_ action: String) {
        do {
            let next = try WashEngine.advance(session, action: action, actor: "watch")
            try persist(next, retired: retired)
            WKInterfaceDevice.current().play(next["done"].flag ? .success : .click)
            sync()
        } catch { self.error = error.localizedDescription }
    }
    func sync() {
        guard session != .null else { return }
        do { try connection.send(kind: "progress", payload: session) }
        catch { self.error = "进度已存于手表；连接恢复后请点同步。\n\(error.localizedDescription)" }
    }
}
