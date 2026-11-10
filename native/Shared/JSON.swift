import Foundation

/// Lossless JSON storage keeps purchase metadata and fields from older Demo versions.
public enum JSON: Codable, Equatable, Sendable {
    case object([String: JSON]), array([JSON]), string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let x = try? c.decode(Bool.self) { self = .bool(x) }
        else if let x = try? c.decode(Double.self) { self = .number(x) }
        else if let x = try? c.decode(String.self) { self = .string(x) }
        else if let x = try? c.decode([JSON].self) { self = .array(x) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let x): try c.encode(x)
        case .array(let x): try c.encode(x)
        case .string(let x): try c.encode(x)
        case .number(let x): try c.encode(x)
        case .bool(let x): try c.encode(x)
        case .null: try c.encodeNil()
        }
    }

    public subscript(_ key: String) -> JSON {
        get { object[key] ?? .null }
        set { var x = object; x[key] = newValue; self = .object(x) }
    }
    public var object: [String: JSON] { if case .object(let x) = self { return x }; return [:] }
    public var array: [JSON] { if case .array(let x) = self { return x }; return [] }
    public var text: String { if case .string(let x) = self { return x }; return "" }
    public var number: Double? { if case .number(let x) = self { return x }; return nil }
    public var flag: Bool { if case .bool(let x) = self { return x }; return false }
    public var id: String { self["id"].text }
    public func replacing(_ fields: [String: JSON]) -> JSON { .object(object.merging(fields) { _, new in new }) }
    public func removing(_ keys: [String]) -> JSON { .object(object.filter { !keys.contains($0.key) }) }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    public static func read(_ data: Data) throws -> JSON { try JSONDecoder().decode(JSON.self, from: data) }
}

public struct WashError: LocalizedError, Equatable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public func milliseconds(_ date: Date = Date()) -> Double { date.timeIntervalSince1970 * 1_000 }
public func identifier() -> String { UUID().uuidString }
public func isoDate(_ ms: Double) -> String { ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: ms / 1_000)) }
public func volume(_ n: Double) -> String { n.formatted(.number.precision(.fractionLength(0...2))) }
public func clockText(_ ms: Double) -> String {
    let seconds = Int(max(0, ms) / 1_000)
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}
