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
    @State private var authMode: AuthMode = .token
    @State private var working = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name", text: $name)
                    TextField("MCP URL — e.g. https://host/mcp", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section("Sign in") {
                    Picker("Authentication", selection: $authMode) {
                        Text("API token").tag(AuthMode.token)
                        Text("Sign in (OAuth)").tag(AuthMode.oauth)
                    }
                    .pickerStyle(.segmented)
                    if authMode == .token {
                        SecureField("API token", text: $token)
                    } else {
                        Text("You'll sign in through a secure web sheet after tapping Add.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("World Assistant uses an API token (https://<your server>/mcp). Home Assistant and other OAuth-protected servers use Sign in.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !error.isEmpty {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(working) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(working ? "…" : "Add") { add() }
                        .disabled(url.isEmpty || working)
                }
            }
        }
    }

    private func add() {
        working = true
        error = ""
        let server = model.addServer(name: name.isEmpty ? url : name, url: url, token: token, authMode: authMode)
        Task {
            var ok = true
            if authMode == .oauth { ok = await model.signIn(server) }
            if ok {
                await model.refresh(server)
                dismiss()
            } else {
                error = model.status[server.id] ?? "Sign-in failed."
                model.remove(server)                 // sign-in failed/cancelled: don't leave a dead server
            }
            working = false
        }
    }
}
