import AppIntents
import SwiftUI

struct ServersView: View {
    @EnvironmentObject var model: AppModel
    @State private var adding = false
    @State private var editing: ServerConfig?
    @State private var registered = false

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
                    .swipeActions(edge: .leading) {
                        Button { editing = server } label: { Label("Edit", systemImage: "pencil") }
                            .tint(.blue)
                    }
                }
                .onDelete { idx in idx.map { model.servers[$0] }.forEach(model.remove) }

                Section {
                    Button {
                        MCPShortcuts.updateAppShortcutParameters()
                        registered = true
                    } label: {
                        Label("Register Siri shortcuts", systemImage: "arrow.triangle.2.circlepath")
                    }
                } footer: {
                    Text("If “Run a tool” doesn’t show in the Shortcuts app, tap this and reopen Shortcuts. A fresh sideloaded install can take a minute to index.")
                }
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
            .sheet(isPresented: $adding) { ServerFormView() }
            .sheet(item: $editing) { server in ServerFormView(editing: server) }
            .alert("Shortcuts registered", isPresented: $registered) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Open the Shortcuts app and search “MCP to Intent”, or ask Siri. It can take a moment to appear the first time.")
            }
        }
    }
}

/// Add a new server, or edit an existing one. `editing` is nil when adding.
struct ServerFormView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let editing: ServerConfig?

    @State private var name = ""
    @State private var url = ""
    @State private var token = ""
    @State private var authMode: AuthMode = .token
    @State private var working = false
    @State private var error = ""

    init(editing: ServerConfig? = nil) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _url = State(initialValue: editing?.mcpURL ?? "")
        _authMode = State(initialValue: editing?.authMode ?? .token)
        // The stored token is never pre-filled into the field — a blank field keeps it.
    }

    private var isEditing: Bool { editing != nil }
    private var confirmLabel: String { isEditing ? "Save" : "Add" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name", text: $name)
                    TextField("MCP URL — e.g. host, or https://host/mcp", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Text("Just the host is enough — defaults to https:// and /mcp.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Sign in") {
                    Picker("Authentication", selection: $authMode) {
                        Text("API token").tag(AuthMode.token)
                        Text("Sign in (OAuth)").tag(AuthMode.oauth)
                    }
                    .pickerStyle(.segmented)
                    if authMode == .token {
                        SecureField(isEditing ? "API token — leave blank to keep current" : "API token", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else if isEditing {
                        Text("Use “Sign in again” on the server screen to refresh the OAuth session.")
                            .font(.footnote).foregroundStyle(.secondary)
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
            .navigationTitle(isEditing ? "Edit server" : "Add server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(working) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(working ? "…" : confirmLabel) { submit() }
                        .disabled(url.isEmpty || working)
                }
            }
        }
    }

    private func submit() {
        if let existing = editing { save(existing) } else { add() }
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

    private func save(_ existing: ServerConfig) {
        working = true
        error = ""
        let switchedToOAuth = authMode == .oauth && existing.authMode != .oauth
        model.editServer(existing, name: name, url: url, token: token, authMode: authMode)
        guard let updated = model.servers.first(where: { $0.id == existing.id }) else { dismiss(); return }
        Task {
            // Changing the token or URL means the cached tools may no longer be valid — re-sync. If the person just
            // switched this server to OAuth, send them through sign-in first.
            if switchedToOAuth, !(await model.signIn(updated)) {
                error = model.status[updated.id] ?? "Sign-in failed."
                working = false
                return
            }
            await model.refresh(updated)
            dismiss()
        }
    }
}
