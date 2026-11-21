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
    func addServer(name: String, url: String, token: String) -> ServerConfig {
        let s = ServerConfig(name: name, mcpURL: url)
        store.upsert(s)
        s.token = token
        reload()
        return s
    }

    func update(_ server: ServerConfig, token: String?) {
        store.upsert(server)
        if let token { server.token = token }
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
