import Foundation

/// World Assistant's capability manifest (`GET /v1/capabilities`). Optional enrichment: when a server offers it, the
/// app uses the titles, summaries, sample phrases and `siri_safe` flags to pre-fill good defaults for each tool. A
/// server without it (any other MCP server) still works from `tools/list`.
struct Manifest: Codable, Equatable, Sendable {
    let version: String
    let generatedAt: String?
    let modules: [ModuleCaps]

    enum CodingKeys: String, CodingKey {
        case version
        case generatedAt = "generated_at"
        case modules
    }

    /// Every query/action capability across all modules, which is what maps to a callable tool.
    var toolCapabilities: [Capability] {
        modules.flatMap(\.capabilities).filter { $0.kind == "query" || $0.kind == "action" }
    }

    /// The intent metadata for a tool by name, if the manifest describes it.
    func intent(forTool name: String) -> Capability? {
        toolCapabilities.first { $0.name == name }
    }
}

struct ModuleCaps: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let category: String?
    let capabilities: [Capability]
}

struct Capability: Codable, Equatable, Sendable {
    let kind: String          // query | action | page | feed
    let name: String?         // the MCP tool name, for query/action
    let title: String?
    let summary: String?
    let consume: Consume?
    let intent: IntentDescriptor?

    struct Consume: Codable, Equatable, Sendable {
        let mcpTool: String?
        let ask: String?
        let pageUrl: String?
        let ha: String?

        enum CodingKeys: String, CodingKey {
            case mcpTool = "mcp_tool"
            case ask
            case pageUrl = "page_url"
            case ha
        }
    }

    struct IntentDescriptor: Codable, Equatable, Sendable {
        let title: String?
        let summary: String?
        let parameters: [Parameter]?
        let result: String?
        let phrases: [String]?
        let siriSafe: Bool?

        enum CodingKeys: String, CodingKey {
            case title, summary, parameters, result, phrases
            case siriSafe = "siri_safe"
        }
    }

    struct Parameter: Codable, Equatable, Sendable {
        let name: String
        let type: String?
        let optional: Bool?
        let description: String?
        let valuesFrom: String?

        enum CodingKeys: String, CodingKey {
            case name, type, optional, description
            case valuesFrom = "values_from"
        }
    }
}
