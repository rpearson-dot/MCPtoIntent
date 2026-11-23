import SwiftUI

/// Record what the app does over the network and ship it to a syslog server for diagnosis. Everything is held in
/// memory and redacted (no tokens); nothing is sent until you tap Send.
struct DiagnosticsView: View {
    private let diag = Diagnostics.shared

    @State private var enabled = Diagnostics.shared.isEnabled
    @State private var host = Diagnostics.shared.syslogHost
    @State private var port = String(Diagnostics.shared.syslogPort)
    @State private var useTCP = Diagnostics.shared.useTCP
    @State private var entries: [DiagEntry] = []
    @State private var sending = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Toggle("Record diagnostics", isOn: $enabled)
                    .onChange(of: enabled) { _, on in diag.isEnabled = on; if on { diag.note("", "recording started") }; reload() }
            } footer: {
                Text("Captures each MCP request and response and the OAuth sign-in steps, in memory, with tokens removed. Turn on, reproduce the problem, then Send.")
            }

            Section("Syslog server") {
                TextField("Host — e.g. 100.x.y.z or server.tailnet.ts.net", text: $host)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .onChange(of: host) { _, v in diag.syslogHost = v }
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("514", text: $port).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .onChange(of: port) { _, v in if let p = UInt16(v) { diag.syslogPort = p } }
                }
                Picker("Transport", selection: $useTCP) {
                    Text("UDP").tag(false); Text("TCP").tag(true)
                }.pickerStyle(.segmented)
                .onChange(of: useTCP) { _, v in diag.useTCP = v }
            }

            Section {
                Button {
                    Task { await send() }
                } label: {
                    Label(sending ? "Sending…" : "Send to syslog", systemImage: "paperplane")
                }.disabled(sending || host.isEmpty)

                ShareLink(item: diag.exportText()) {
                    Label("Share diagnostics", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) { diag.clear(); reload() } label: {
                    Label("Clear", systemImage: "trash")
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Captured (\(entries.count))") {
                if entries.isEmpty {
                    Text(enabled ? "Nothing yet — reproduce the problem." : "Recording is off.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries.reversed()) { e in
                    DisclosureGroup {
                        if !e.detail.isEmpty {
                            Text(e.detail).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.summary).font(.subheadline)
                                .foregroundStyle(e.summary.contains("ERROR") ? .red : .primary)
                            Text("\(e.kind.uppercased()) · \(e.server.isEmpty ? "—" : e.server) · \(e.at.formatted(date: .omitted, time: .standard))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
        .toolbar { Button { reload() } label: { Image(systemName: "arrow.clockwise") } }
        .onAppear(perform: reload)
    }

    private func reload() { entries = diag.snapshot() }

    private func send() async {
        sending = true; message = nil
        switch await diag.sendToSyslog() {
        case let .sent(n): message = "Sent \(n) events to \(host):\(port) over \(useTCP ? "TCP" : "UDP")."
        case let .failed(why): message = why
        }
        sending = false
    }
}
