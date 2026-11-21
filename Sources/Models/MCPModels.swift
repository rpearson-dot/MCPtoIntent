import Foundation

/// A tool as a Model Context Protocol server lists it (`tools/list`). This is the generic backbone: every MCP server
/// provides it, whatever the server. World Assistant's `/v1/capabilities` can enrich these with nicer titles and Siri
/// phrases, but the app works from `tools/list` alone.
struct MCPTool: Codable, Identifiable, Equatable, Sendable {
    let name: String
    let description: String?
    let inputSchema: JSONValue?

    var id: String { name }

    /// The names of the tool's parameters, in the schema's order where the encoder preserved it.
    var parameterNames: [String] {
        guard case let .object(schema) = inputSchema, case let .object(props)? = schema["properties"] else { return [] }
        return Array(props.keys)
    }

    /// The parameters the schema marks as required.
    var requiredParameters: [String] {
        guard case let .object(schema) = inputSchema, case let .array(req)? = schema["required"] else { return [] }
        return req.compactMap { if case let .string(s) = $0 { return s } else { return nil } }
    }
}

/// The server's answer to `initialize`.
struct MCPServerInfo: Codable, Equatable, Sendable {
    let name: String?
    let version: String?
}

struct MCPInitializeResult: Codable, Equatable, Sendable {
    let protocolVersion: String?
    let serverInfo: MCPServerInfo?
    let instructions: String?
}

/// The result of `tools/call`: one or more content blocks (the app reads the text ones) and an error flag.
struct MCPToolResult: Codable, Equatable, Sendable {
    struct Content: Codable, Equatable, Sendable {
        let type: String
        let text: String?
    }
    let content: [Content]?
    let structuredContent: JSONValue?
    let isError: Bool?

    /// The spoken/shown answer: the text content blocks joined.
    var text: String {
        (content ?? []).compactMap { $0.type == "text" ? $0.text : nil }.joined(separator: "\n")
    }
}

// MARK: - JSON-RPC envelope

struct RPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: JSONValue?
}

struct RPCError: Decodable, Error, Equatable {
    let code: Int
    let message: String
}

/// A JSON-RPC response whose `result` is decoded to `T` on demand (results differ per method).
struct RPCResponse: Decodable {
    let id: JSONValue?
    let result: JSONValue?
    let error: RPCError?
}
