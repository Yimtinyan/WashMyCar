import Foundation

/// A transaction becomes visible only after a successful atomic disk write.
public struct StateRepository: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load(seed: () throws -> JSON) throws -> JSON {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let initial = try seed()
            try save(initial)
            return initial
        }
        let input = try JSON.read(Data(contentsOf: url))
        try Backup.validate(input, requireVehicles: (input["version"].number ?? 0) >= 5)
        let state = Backup.migrate(input)
        try Backup.validate(state)
        return state
    }
    public func save(_ state: JSON) throws {
        try Backup.validate(state)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try state.encoded().write(to: url, options: .atomic)
    }
    public func restore(_ state: JSON) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try Data(contentsOf: url).write(to: url.deletingLastPathComponent().appendingPathComponent("BeforeRestore.json"), options: .atomic)
        }
        try save(state)
    }
}
