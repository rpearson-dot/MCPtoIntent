import Foundation

/// One configured MCP server. The token lives in the Keychain (keyed by `id`), never here.
struct ServerConfig: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var mcpURL: String

    var token: String {
        get { Keychain.token(for: id) }
        nonmutating set { Keychain.setToken(newValue, for: id) }
    }
}

/// What the person has chosen for one tool on one server: whether to share it with Siri, the name they call it, and
/// any parameters they have pinned to a fixed value (e.g. list = "Shopping"). Keyed by "<serverID>/<toolName>".
struct ToolSetting: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var friendlyName: String = ""
    var pinnedArgs: [String: String] = [:]
}

/// A tool ready to show and run: the MCP tool merged with any manifest enrichment and the person's settings. This is
/// what both the list UI and the App Intent work from.
struct ToolInfo: Identifiable, Equatable, Sendable {
    let serverID: UUID
    let serverName: String
    let name: String
    let title: String        // friendly name if set, else the manifest title, else the tool name
    let summary: String      // one line of what it does
    let phrases: [String]
    let siriSafe: Bool
    let parameters: [Capability.Parameter]
    var setting: ToolSetting

    var id: String { "\(serverID.uuidString)/\(name)" }

    /// The free-text parameter a single spoken phrase maps to: the first required string parameter that isn't pinned,
    /// else the first string parameter. nil when the tool takes no text.
    var primaryTextParameter: String? {
        let unpinned = parameters.filter { setting.pinnedArgs[$0.name] == nil }
        let strings = unpinned.filter { ($0.type ?? "string") == "string" || ($0.type ?? "") == "array" }
        return strings.first { $0.optional == false }?.name ?? strings.first?.name
    }
}
