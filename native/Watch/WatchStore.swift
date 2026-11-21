import Foundation
import SwiftUI
import WatchKit

@MainActor
final class WatchStore: ObservableObject {
    @Published private var document: JSON = .object(["session": .null, "retired": .array([])])
    @Published var error: String?
    var session: JSON { document["session"] }
    let connection = Connectivity()
    private let url = URL.applicationSupportDirectory.appendingPathComponent("WatchState.json")
    private var loadFailed = false

    init() {
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let stored = try JSON.read(Data(contentsOf: url))
                if stored["session"] != .null { try Backup.validateSession(stored["session"]) }
                document = stored
            } catch { self.error = "手表资料读取失败，原文件已保留。"; loadFailed = true }
        }
        connection.receive = { [weak self] kind, payload, checksum in self?.receive(kind, payload, checksum) }
        connection.available = { [weak self] in self?.sync() }
    }
    private func persist(_ next: JSON) throws {
        guard !loadFailed else { throw WashError("请先检查手表资料文件。") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try next.encoded().write(to: url, options: .atomic)
        document = next
    }
    private func receive(_ kind: String, _ incoming: JSON, _ checksum: String) {
        guard !loadFailed else { return }
        do {
            switch kind {
            case "cancel":
                guard try WatchHandoff.validReceipt(incoming, checksum: checksum) else { return }
                let next = WatchHandoff.retiring(incoming.id, in: document)
                if next != document { try persist(next) }
                try connection.send(kind: "cancelAck", payload: incoming)
            case "plan":
                let next = try WatchHandoff.receivingPlan(incoming, checksum: checksum, in: document)
                if next != document {
                    try persist(next)
                    WKInterfaceDevice.current().play(.notification)
                }
                if session.id == incoming.id { sync() }
            default: break
            }
        } catch { self.error = error.localizedDescription }
    }
    func action(_ action: String) {
        do {
            let next = try WashEngine.advance(session, action: action, actor: "watch")
            try persist(document.replacing(["session": next]))
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
