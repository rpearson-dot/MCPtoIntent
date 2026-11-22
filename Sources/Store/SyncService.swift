import Foundation

/// Refreshes what the app knows about a server: the MCP tool list (always) and World Assistant's capability manifest
/// (when offered), caching both. The ETag makes a repeat sync cheap. Seeds a default setting for any new tool so it
/// shows up ready to enable.
struct SyncService {
    let store: DataStore

    init(store: DataStore = .shared) { self.store = store }

    struct Summary {
        let toolCount: Int
        let manifestChanged: Bool
        let serverName: String?
    }

    @discardableResult
    func refresh(_ server: ServerConfig) async throws -> Summary {
        let token = try await AuthManager.shared.accessToken(for: server)
        let client = try MCPClient(serverURL: server.mcpURL, token: token)
        let info = try await client.initialize()
        let tools = try await client.listTools()
        store.setCachedTools(tools, for: server.id)

        var manifestChanged = false
        if let caps = CapabilitiesClient(mcpURL: server.mcpURL, token: token) {
            if let result = try? await caps.fetch(ifNoneMatch: store.etag(server.id)) {
                store.setEtag(result.etag, for: server.id)
                if result.changed, let manifest = result.manifest {
                    store.setCachedManifest(manifest, for: server.id)
                    manifestChanged = true
                }
            }
        }

        // seed a setting for any tool we haven't seen, defaulting the friendly name to its title
        let merged = store.tools(for: server.id)
        for t in merged where store.defaults_hasNoSetting(toolID: t.id) {
            var s = t.setting
            if s.friendlyName.isEmpty { s.friendlyName = t.title }
            store.saveSetting(s, toolID: t.id)
        }
        return Summary(toolCount: tools.count, manifestChanged: manifestChanged, serverName: info.serverInfo?.name)
    }
}

extension DataStore {
    /// True when a tool has no stored setting yet (so sync can seed one).
    func defaults_hasNoSetting(toolID: String) -> Bool {
        UserDefaults.standard.data(forKey: "setting.\(toolID)") == nil
    }
}
