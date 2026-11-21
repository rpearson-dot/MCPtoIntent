import Foundation

/// Fetches World Assistant's `/v1/capabilities` manifest to enrich the tool list, with ETag support so a sync is a
/// cheap 304 when nothing changed. Optional: a server that is not World Assistant simply has no such endpoint, and the
/// app carries on from `tools/list`.
struct CapabilitiesClient {
    let url: URL
    let token: String
    var session: URLSession = .shared

    /// Derive the capabilities URL from an MCP endpoint that ends in `/mcp` (World Assistant). Returns nil otherwise.
    init?(mcpURL: String, token: String) {
        guard let u = URL(string: mcpURL), mcpURL.hasSuffix("/mcp") else { return nil }
        let base = mcpURL.dropLast("/mcp".count)
        guard let caps = URL(string: base + "/v1/capabilities") else { return nil }
        _ = u
        self.url = caps
        self.token = token
    }

    struct Result {
        let manifest: Manifest?   // nil when the server replied 304 Not Modified
        let etag: String?
        let changed: Bool
    }

    /// Fetch the manifest. Pass the previously stored ETag to let the server answer 304 when nothing changed.
    func fetch(ifNoneMatch etag: String?) async throws -> Result {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        req.timeoutInterval = 20
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw MCPClientError.malformed("no HTTP response") }
        let newTag = http.value(forHTTPHeaderField: "ETag") ?? etag
        if http.statusCode == 304 { return Result(manifest: nil, etag: newTag, changed: false) }
        guard (200..<300).contains(http.statusCode) else {
            throw MCPClientError.http(http.statusCode, "")
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        return Result(manifest: manifest, etag: newTag, changed: true)
    }
}
