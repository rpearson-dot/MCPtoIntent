import AppIntents

/// One tool shared with Siri, as an App Intents entity. Its identifier is "<serverID>/<toolName>", and its display
/// name is the friendly name the person set — so Siri and the Shortcuts app show what they called it. The set is
/// dynamic: it comes from whatever is enabled in the app, across every server.
struct ToolEntity: AppEntity {
    let id: String
    let title: String
    let summary: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Tool" }
    static var defaultQuery = ToolEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: summary.isEmpty ? nil : "\(summary)")
    }

    init(id: String, title: String, summary: String) {
        self.id = id
        self.title = title
        self.summary = summary
    }

    init(_ info: ToolInfo) {
        self.id = info.id
        self.title = info.title
        self.summary = info.summary
    }
}

struct ToolEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ToolEntity] {
        identifiers.compactMap { DataStore.shared.tool(id: $0).map(ToolEntity.init) }
    }

    /// What Siri and the Shortcuts app offer: every enabled tool.
    func suggestedEntities() async throws -> [ToolEntity] {
        DataStore.shared.enabledTools().map(ToolEntity.init)
    }
}
