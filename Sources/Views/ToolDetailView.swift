import SwiftUI

struct ToolDetailView: View {
    @EnvironmentObject var model: AppModel
    let tool: ToolInfo

    @State private var friendly = ""
    @State private var pinned: [String: String] = [:]
    @State private var testInput = ""
    @State private var testOut = ""
    @State private var testing = false

    /// Always read the live merged tool, so toggles reflect what's saved.
    private var current: ToolInfo { model.tools(for: tool.serverID).first { $0.id == tool.id } ?? tool }

    var body: some View {
        Form {
            Section {
                Toggle("Share with Siri", isOn: Binding(
                    get: { current.setting.enabled },
                    set: { model.setEnabled($0, tool: current) }))
                if !current.summary.isEmpty {
                    Text(current.summary).font(.footnote).foregroundStyle(.secondary)
                }
                if !current.siriSafe {
                    Label("Changes something — Siri will ask you to confirm first.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("Tool: \(current.name) · \(current.serverName)").font(.caption2).foregroundStyle(.secondary)
            }

            Section("Friendly name") {
                TextField("What you call it", text: $friendly)
                    .onSubmit { model.setFriendlyName(friendly, tool: current) }
                Text("The name Siri and the Shortcuts app show. To set a spoken phrase in your own words, open the Shortcuts app, add the “Run a tool” action, pick this tool, and record a phrase.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !current.phrases.isEmpty {
                Section("Suggested phrases") {
                    ForEach(current.phrases, id: \.self) { Text("“\($0)”").font(.footnote) }
                }
            }

            if !current.parameters.isEmpty {
                Section("Parameters") {
                    ForEach(current.parameters, id: \.name) { p in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(p.name).font(.subheadline)
                                if p.optional == false {
                                    Text("required").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            if let d = p.description, !d.isEmpty {
                                Text(d).font(.caption).foregroundStyle(.secondary)
                            }
                            TextField("Pin a fixed value (optional)", text: Binding(
                                get: { pinned[p.name] ?? "" },
                                set: { pinned[p.name] = $0 }))
                                .onSubmit { model.setPinned(pinned[p.name] ?? "", param: p.name, tool: current) }
                                .textInputAutocapitalization(.never)
                        }
                    }
                    Text("A pinned value is always sent, so Siri needn't say it — e.g. pin a list to “Shopping”.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Try it") {
                TextField("What to pass (optional)", text: $testInput)
                Button(testing ? "Running…" : "Run now") { Task { await runTest() } }
                    .disabled(testing)
                if !testOut.isEmpty {
                    Text(testOut).font(.footnote).textSelection(.enabled)
                }
            }
        }
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            friendly = current.setting.friendlyName
            pinned = current.setting.pinnedArgs
        }
    }

    private func runTest() async {
        testing = true
        defer { testing = false }
        guard let server = model.servers.first(where: { $0.id == tool.serverID }) else {
            testOut = "That server is gone."
            return
        }
        do {
            let args = RunToolIntent.buildArguments(for: current, input: testInput)
            let token = try await AuthManager.shared.accessToken(for: server)
            let client = try MCPClient(serverURL: server.mcpURL, token: token)
            testOut = try await client.callTool(current.name, arguments: args).text
        } catch {
            testOut = error.localizedDescription
        }
    }
}
