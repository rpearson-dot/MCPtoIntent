import Foundation

enum MCPClientError: LocalizedError {
    case badURL
    case http(Int, String)
    case rpc(RPCError)
    case malformed(String)
    case toolFailed(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "That server address is not a valid URL."
        case let .http(code, body): return "The server replied \(code)." + (body.isEmpty ? "" : " \(body)")
        case let .rpc(e): return e.message
        case let .malformed(m): return "The server's reply could not be read: \(m)"
        case let .toolFailed(m): return m
        }
    }
}

/// A generic Model Context Protocol client over "streamable HTTP": one JSON-RPC message per POST, Bearer auth. It
/// reads either a JSON reply or a text/event-stream one, so it works with World Assistant (plain JSON) and with MCP
/// servers that stream. No session state is kept; each call is a standalone POST.
struct MCPClient {
    let endpoint: URL
    let token: String
    var session: URLSession = .shared

    init(serverURL: String, token: String) throws {
        guard let url = URL(string: serverURL), url.scheme?.hasPrefix("http") == true else {
            throw MCPClientError.badURL
        }
        self.endpoint = url
        self.token = token
    }

    // MARK: - MCP methods

    @discardableResult
    func initialize() async throws -> MCPInitializeResult {
        let params = JSONValue.object([
            "protocolVersion": .string("2025-06-18"),
            "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("MCP to Intent"), "version": .string("0.1.0")]),
        ])
        let result = try await send(method: "initialize", params: params)
        // tell the server we're ready (a notification: no reply expected)
        try? await notify(method: "notifications/initialized")
        return try Self.decode(result)
    }

    func listTools() async throws -> [MCPTool] {
        let result = try await send(method: "tools/list", params: nil)
        guard case let .object(obj) = result, let tools = obj["tools"] else {
            throw MCPClientError.malformed("no tools in tools/list")
        }
        return try Self.decode(tools)
    }

    func callTool(_ name: String, arguments: [String: JSONValue]) async throws -> MCPToolResult {
        let params = JSONValue.object(["name": .string(name), "arguments": .object(arguments)])
        let result = try await send(method: "tools/call", params: params)
        let decoded: MCPToolResult = try Self.decode(result)
        if decoded.isError == true {
            throw MCPClientError.toolFailed(decoded.text.isEmpty ? "The tool reported an error." : decoded.text)
        }
        return decoded
    }

    // MARK: - transport

    private func request(body: Data) -> URLRequest {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30
        return req
    }

    private func send(method: String, params: JSONValue?) async throws -> JSONValue {
        let body = try JSONEncoder().encode(RPCRequest(id: 1, method: method, params: params))
        let (data, response) = try await session.data(for: request(body: body))
        guard let http = response as? HTTPURLResponse else { throw MCPClientError.malformed("no HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            throw MCPClientError.http(http.statusCode, String(data: data, encoding: .utf8)?.prefix(200).description ?? "")
        }
        let payload = Self.jsonPayload(data: data, contentType: http.value(forHTTPHeaderField: "Content-Type"))
        let rpc = try JSONDecoder().decode(RPCResponse.self, from: payload)
        if let error = rpc.error { throw MCPClientError.rpc(error) }
        guard let result = rpc.result else { throw MCPClientError.malformed("the reply had no result") }
        return result
    }

    private func notify(method: String) async throws {
        // a JSON-RPC notification has no id and expects no reply (the server answers 202)
        let body = try JSONEncoder().encode(["jsonrpc": "2.0", "method": method])
        _ = try? await session.data(for: request(body: body))
    }

    /// A streamable-HTTP reply may be a bare JSON object or an SSE stream whose `data:` line carries the JSON. Return
    /// the JSON bytes either way.
    static func jsonPayload(data: Data, contentType: String?) -> Data {
        guard contentType?.contains("text/event-stream") == true,
              let text = String(data: data, encoding: .utf8) else { return data }
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("data:") {
            let json = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if json.first == "{", let d = json.data(using: .utf8) { return d }  // the response message, not a ping
        }
        return data
    }

    private static func decode<T: Decodable>(_ value: JSONValue) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
        } catch {
            throw MCPClientError.malformed("\(T.self): \(error.localizedDescription)")
        }
    }
}
