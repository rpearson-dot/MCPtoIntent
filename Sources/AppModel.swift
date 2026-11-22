import Foundation
import SwiftUI

/// The view model over `DataStore` and `SyncService`. App Intents read `DataStore` directly; the UI goes through here
/// so changes publish to SwiftUI.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var servers: [ServerConfig] = []
    @Published var status: [UUID: String] = [:]
    @Published var busy: Set<UUID> = []

    private let store = DataStore.shared
    private let sync = SyncService()

    init() { servers = store.servers() }

    func reload() { servers = store.servers() }

    @discardableResult
    func addServer(name: String, url: String, token: String, authMode: AuthMode) -> ServerConfig {
        let s = ServerConfig(name: name, mcpURL: Self.normalizedMCPURL(url), authMode: authMode)
        store.upsert(s)
        if authMode == .token { s.token = token }
        reload()
        return s
    }

    /// Fill in the parts of an MCP URL people usually leave off: a missing scheme becomes `https://`, and a bare host
    /// with no path gets `/mcp`. An explicit scheme (e.g. `http://` for local testing) or an explicit path is kept as
    /// typed, so `host`, `host/mcp`, `https://host` and `http://host:8010/custom` all do the sensible thing.
    static func normalizedMCPURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return s }
        if !s.contains("://") { s = "https://" + s }          // prepend first, so "host:8010" isn't read as a scheme
        guard var comp = URLComponents(string: s) else { return s }
        if comp.scheme == nil || comp.scheme!.isEmpty { comp.scheme = "https" }
        if comp.path.isEmpty || comp.path == "/" { comp.path = "/mcp" }
        return comp.string ?? s
    }

    /// Run the interactive OAuth sign-in for a server; returns whether it succeeded.
    @MainActor
    func signIn(_ server: ServerConfig) async -> Bool {
        do {
            try await AuthManager.shared.signIn(server: server)
            status[server.id] = "Signed in"
            objectWillChange.send()
            return true
        } catch {
            status[server.id] = error.localizedDescription
            return false
        }
    }

    func update(_ server: ServerConfig, token: String?) {
        store.upsert(server)
        if let token { server.token = token }
        reload()
    }

    /// Apply edits to an existing server. A blank `token` in token mode leaves the stored token untouched, so the
    /// person can change the name or URL without re-entering the secret.
    func editServer(_ server: ServerConfig, name: String, url: String, token: String, authMode: AuthMode) {
        var s = server
        let cleanURL = Self.normalizedMCPURL(url)
        s.name = name.isEmpty ? cleanURL : name
        s.mcpURL = cleanURL
        s.authMode = authMode
        store.upsert(s)
        if authMode == .token, !token.isEmpty { s.token = token }
        reload()
    }

    func remove(_ server: ServerConfig) {
        store.remove(serverID: server.id)
        status[server.id] = nil
        reload()
    }

    func tools(for serverID: UUID) -> [ToolInfo] { store.tools(for: serverID) }

    func refresh(_ server: ServerConfig) async {
        busy.insert(server.id)
        defer { busy.remove(server.id) }
        do {
            let s = try await sync.refresh(server)
            status[server.id] = "\(s.toolCount) tools" + (s.manifestChanged ? " · manifest updated" : "")
        } catch {
            status[server.id] = error.localizedDescription
        }
        objectWillChange.send()
    }

    // MARK: - per-tool settings

    func setEnabled(_ on: Bool, tool: ToolInfo) { mutate(tool) { $0.enabled = on } }
    func setFriendlyName(_ name: String, tool: ToolInfo) { mutate(tool) { $0.friendlyName = name } }
    func setPinned(_ value: String, param: String, tool: ToolInfo) {
        mutate(tool) { $0.pinnedArgs[param] = value.isEmpty ? nil : value }
    }

    private func mutate(_ tool: ToolInfo, _ change: (inout ToolSetting) -> Void) {
        var s = tool.setting
        change(&s)
        store.saveSetting(s, toolID: tool.id)
        objectWillChange.send()
    }
}
