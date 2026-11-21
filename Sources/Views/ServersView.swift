import SwiftUI

struct ServersView: View {
    @EnvironmentObject var model: AppModel
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                if model.servers.isEmpty {
                    ContentUnavailableView("No servers yet", systemImage: "server.rack",
                                           description: Text("Add an MCP server to share its tools with Siri."))
                }
                ForEach(model.servers) { server in
                    NavigationLink(value: server.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name).font(.headline)
                            Text(server.mcpURL).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if let st = model.status[server.id] {
                                Text(st).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { idx in idx.map { model.servers[$0] }.forEach(model.remove) }
            }
            .navigationTitle("MCP servers")
            .navigationDestination(for: UUID.self) { id in
                if let server = model.servers.first(where: { $0.id == id }) {
                    ServerDetailView(server: server)
                }
            }
            .toolbar {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add a server")
            }
            .sheet(isPresented: $adding) { AddServerView() }
        }
    }
}

struct AddServerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name", text: $name)
                    TextField("MCP URL — e.g. https://host/mcp", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("API token", text: $token)
                }
                Section {
                    Text("World Assistant: use https://<your server>/mcp and your API token. Any other MCP server works too — the tools load from its standard tool list.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let s = model.addServer(name: name.isEmpty ? url : name, url: url, token: token)
                        Task { await model.refresh(s) }
                        dismiss()
                    }
                    .disabled(url.isEmpty)
                }
            }
        }
    }
}
