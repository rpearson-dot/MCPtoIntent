import AppIntents
import Foundation

/// Run one enabled tool and speak the result. The chosen tool carries its server and settings; `input` is whatever
/// the person said ("bread, milk and eggs"), mapped to the tool's main free-text parameter. Pinned parameters (e.g.
/// list = "Shopping") are filled in automatically. An action that isn't safe for Siri asks for confirmation first.
struct RunToolIntent: AppIntent {
    static var title: LocalizedStringResource = "Run a tool"
    static var description = IntentDescription("Ask one of your MCP servers' tools and hear the answer.")
    static var openAppWhenRun = false

    @Parameter(title: "Tool")
    var tool: ToolEntity

    @Parameter(title: "Input", description: "What to pass — e.g. the place, or the items to add.")
    var input: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$tool) with \(\.$input)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let info = DataStore.shared.tool(id: tool.id) else {
            throw AppError.message("That tool is no longer set up.")
        }
        guard let server = DataStore.shared.server(id: info.serverID) else {
            throw AppError.message("That tool's server is gone.")
        }
        if !info.siriSafe {
            try await requestConfirmation(result: .result(dialog: "\(info.title) will change something. Go ahead?"))
        }

        let args = Self.buildArguments(for: info, input: input)
        let client = try MCPClient(serverURL: server.mcpURL, token: server.token)
        let result = try await client.callTool(info.name, arguments: args)
        let spoken = result.text.isEmpty ? "Done." : result.text
        return .result(dialog: IntentDialog(stringLiteral: spoken))
    }

    /// Pinned parameters as fixed values, plus the spoken `input` mapped to the tool's main text parameter (split into
    /// a list when that parameter takes an array, so "bread, milk and eggs" becomes three items).
    static func buildArguments(for info: ToolInfo, input: String?) -> [String: JSONValue] {
        var args: [String: JSONValue] = [:]
        for (name, value) in info.setting.pinnedArgs where !value.isEmpty {
            args[name] = .string(value)
        }
        if let input, !input.trimmingCharacters(in: .whitespaces).isEmpty, let param = info.primaryTextParameter {
            let type = info.parameters.first { $0.name == param }?.type
            if type == "array" {
                args[param] = .array(splitList(input).map(JSONValue.string))
            } else {
                args[param] = .string(input)
            }
        }
        return args
    }

    /// "bread, milk and eggs" → ["bread", "milk", "eggs"].
    static func splitList(_ text: String) -> [String] {
        text.replacingOccurrences(of: " and ", with: ", ")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(m) = self { return m } else { return nil } }
}
