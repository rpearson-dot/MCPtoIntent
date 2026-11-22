import Foundation

/// The app's persistence, plain and shared: the SwiftUI views and the App Intents both read and write through here
/// (UserDefaults within the app container, plus the Keychain for tokens). No app group is needed while the App
/// Intents live in the main app target.
final class DataStore: @unchecked Sendable {
    static let shared = DataStore()
    private let defaults = UserDefaults.standard
    private let lock = NSLock()

    private enum Key {
        static let servers = "servers"
        static func tools(_ id: UUID) -> String { "tools.\(id.uuidString)" }       // cached [MCPTool]
        static func manifest(_ id: UUID) -> String { "manifest.\(id.uuidString)" }  // cached Manifest
        static func etag(_ id: UUID) -> String { "etag.\(id.uuidString)" }
        static func setting(_ toolID: String) -> String { "setting.\(toolID)" }
    }

    // MARK: - servers

    func servers() -> [ServerConfig] {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: Key.servers),
              let list = try? JSONDecoder().decode([ServerConfig].self, from: data) else { return [] }
        return list
    }

    func saveServers(_ list: [ServerConfig]) {
        lock.lock(); defer { lock.unlock() }
        defaults.set(try? JSONEncoder().encode(list), forKey: Key.servers)
    }

    func server(id: UUID) -> ServerConfig? { servers().first { $0.id == id } }

    func upsert(_ server: ServerConfig) {
        var list = servers()
        if let i = list.firstIndex(where: { $0.id == server.id }) { list[i] = server } else { list.append(server) }
        saveServers(list)
    }

    func remove(serverID: UUID) {
        saveServers(servers().filter { $0.id != serverID })
        Keychain.clear(for: serverID)
        defaults.removeObject(forKey: Key.tools(serverID))
        defaults.removeObject(forKey: Key.manifest(serverID))
        defaults.removeObject(forKey: Key.etag(serverID))
    }

    // MARK: - cached tools and manifest

    func cachedTools(_ id: UUID) -> [MCPTool] {
        guard let data = defaults.data(forKey: Key.tools(id)),
              let list = try? JSONDecoder().decode([MCPTool].self, from: data) else { return [] }
        return list
    }

    func setCachedTools(_ tools: [MCPTool], for id: UUID) {
        defaults.set(try? JSONEncoder().encode(tools), forKey: Key.tools(id))
    }

    func cachedManifest(_ id: UUID) -> Manifest? {
        guard let data = defaults.data(forKey: Key.manifest(id)) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    func setCachedManifest(_ manifest: Manifest?, for id: UUID) {
        if let manifest { defaults.set(try? JSONEncoder().encode(manifest), forKey: Key.manifest(id)) }
    }

    func etag(_ id: UUID) -> String? { defaults.string(forKey: Key.etag(id)) }
    func setEtag(_ etag: String?, for id: UUID) {
        if let etag { defaults.set(etag, forKey: Key.etag(id)) }
    }

    // MARK: - per-tool settings

    func setting(toolID: String) -> ToolSetting {
        guard let data = defaults.data(forKey: Key.setting(toolID)),
              let s = try? JSONDecoder().decode(ToolSetting.self, from: data) else { return ToolSetting() }
        return s
    }

    func saveSetting(_ s: ToolSetting, toolID: String) {
        defaults.set(try? JSONEncoder().encode(s), forKey: Key.setting(toolID))
    }

    // MARK: - the merged view both UI and intents use

    /// Every tool on a server, merged from the cached MCP tools, the manifest enrichment and the person's settings.
    func tools(for serverID: UUID) -> [ToolInfo] {
        guard let server = server(id: serverID) else { return [] }
        let manifest = cachedManifest(serverID)
        return cachedTools(serverID).map { tool in
            let cap = manifest?.intent(forTool: tool.name)
            let id = "\(serverID.uuidString)/\(tool.name)"
            let setting = setting(toolID: id)
            let manifestTitle = cap?.intent?.title ?? cap?.title
            let params = cap?.intent?.parameters ?? tool.parameterNames.map {
                Capability.Parameter(name: $0, type: nil, optional: !tool.requiredParameters.contains($0),
                                     description: nil, valuesFrom: nil)
            }
            return ToolInfo(
                serverID: serverID,
                serverName: server.name,
                name: tool.name,
                title: setting.friendlyName.isEmpty ? (manifestTitle ?? tool.name) : setting.friendlyName,
                summary: cap?.intent?.summary ?? cap?.summary ?? tool.description ?? "",
                phrases: cap?.intent?.phrases ?? [],
                siriSafe: cap?.intent?.siriSafe ?? (cap?.kind != "action"),
                parameters: params,
                setting: setting)
        }
    }

    /// Only the tools shared with Siri, across every server — what the App Intent offers.
    func enabledTools() -> [ToolInfo] {
        servers().flatMap { tools(for: $0.id) }.filter { $0.setting.enabled }
    }

    func tool(id toolID: String) -> ToolInfo? {
        guard let slash = toolID.firstIndex(of: "/"),
              let sid = UUID(uuidString: String(toolID[..<slash])) else { return nil }
        return tools(for: sid).first { $0.id == toolID }
    }
}
