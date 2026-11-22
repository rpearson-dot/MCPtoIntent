import SwiftUI

struct ServerDetailView: View {
    @EnvironmentObject var model: AppModel
    let server: ServerConfig
    @State private var editing = false

    var body: some View {
        let tools = model.tools(for: server.id)
        return List {
            Section {
                Button {
                    Task { await model.refresh(server) }
                } label: {
                    Label(model.busy.contains(server.id) ? "Syncing…" : "Sync", systemImage: "arrow.clockwise")
                }
                .disabled(model.busy.contains(server.id))
                if server.authMode == .oauth {
                    Button {
                        Task { if await model.signIn(server) { await model.refresh(server) } }
                    } label: {
                        Label("Sign in again", systemImage: "person.badge.key")
                    }
                }
                if let st = model.status[server.id] {
                    Text(st).font(.caption).foregroundStyle(.secondary)
                }
            }

            if tools.isEmpty {
                Text("No tools yet — Sync to load them.").foregroundStyle(.secondary)
            } else {
                Section("Tools (\(tools.filter { $0.setting.enabled }.count) shared with Siri)") {
                    ForEach(tools) { tool in
                        NavigationLink {
                            ToolDetailView(tool: tool)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(tool.title).font(.headline)
                                    Spacer()
                                    if tool.setting.enabled {
                                        Image(systemName: "mic.fill").foregroundStyle(.tint).font(.caption)
                                    }
                                    if !tool.siriSafe {
                                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                                    }
                                }
                                if !tool.summary.isEmpty {
                                    Text(tool.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(server.name)
        .toolbar {
            Button { editing = true } label: { Image(systemName: "pencil") }
                .accessibilityLabel("Edit server")
        }
        .sheet(isPresented: $editing) {
            ServerFormView(editing: model.servers.first(where: { $0.id == server.id }) ?? server)
        }
        .task { if model.tools(for: server.id).isEmpty { await model.refresh(server) } }
    }
}
