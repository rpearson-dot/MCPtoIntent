import Foundation

/// A value of arbitrary JSON shape. MCP tool arguments, input schemas and structured results are free-form JSON, so
/// the app carries them as this rather than fixed types.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unrepresentable JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(b): try c.encode(b)
        case let .number(n): try c.encode(n)
        case let .string(s): try c.encode(s)
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        }
    }

    /// A plain Swift value, handy when building arguments from user input.
    var any: Any {
        switch self {
        case .null: return NSNull()
        case let .bool(b): return b
        case let .number(n): return n
        case let .string(s): return s
        case let .array(a): return a.map(\.any)
        case let .object(o): return o.mapValues(\.any)
        }
    }

    /// A short, human-readable rendering for showing a result in the app.
    var displayText: String {
        switch self {
        case .null: return ""
        case let .bool(b): return b ? "yes" : "no"
        case let .number(n): return n == n.rounded() ? String(Int(n)) : String(n)
        case let .string(s): return s
        case let .array(a): return a.map(\.displayText).joined(separator: ", ")
        case let .object(o): return o.map { "\($0): \($1.displayText)" }.joined(separator: "\n")
        }
    }
}
