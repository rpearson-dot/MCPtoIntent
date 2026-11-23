import Foundation
import Network

/// One recorded event: an MCP request/response, an OAuth step, or a note. Held in memory only (never persisted), so
/// nothing sensitive is written to disk. Request and response bodies are redacted before they are stored.
struct DiagEntry: Identifiable {
    let id = UUID()
    let at: Date
    let kind: String       // "mcp" | "oauth" | "note"
    let server: String
    let summary: String    // one line, shown in the list and used as the syslog message
    let detail: String     // multi-line, redacted request/response, shown when expanded

    /// A single text line for export and for syslog.
    var line: String {
        let t = ISO8601DateFormatter().string(from: at)
        let who = server.isEmpty ? "" : " [\(server)]"
        return "\(t) \(kind.uppercased())\(who) \(summary)"
    }
}

/// In-memory capture of what the app does over the network, with a button to ship it to a syslog server for
/// diagnosis. Off by default; a ring buffer of the most recent events; tokens and secrets are redacted. It is a
/// process-wide singleton so the networking layer can record without being handed a logger.
final class Diagnostics: @unchecked Sendable {
    static let shared = Diagnostics()

    private let lock = NSLock()
    private var entries: [DiagEntry] = []
    private let maxEntries = 400
    private let d = UserDefaults.standard

    // MARK: - settings (not secret: fine in UserDefaults)

    var isEnabled: Bool {
        get { d.bool(forKey: "diag.enabled") }
        set { d.set(newValue, forKey: "diag.enabled") }
    }
    var syslogHost: String {
        get { d.string(forKey: "diag.host") ?? "" }
        set { d.set(newValue.trimmingCharacters(in: .whitespaces), forKey: "diag.host") }
    }
    var syslogPort: UInt16 {
        get { let p = d.integer(forKey: "diag.port"); return p == 0 ? 514 : UInt16(clamping: p) }
        set { d.set(Int(newValue), forKey: "diag.port") }
    }
    var useTCP: Bool {
        get { d.bool(forKey: "diag.tcp") }
        set { d.set(newValue, forKey: "diag.tcp") }
    }

    // MARK: - recording

    func snapshot() -> [DiagEntry] { lock.lock(); defer { lock.unlock() }; return entries }
    func clear() { lock.lock(); entries.removeAll(); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return entries.count }

    private func add(_ e: DiagEntry) {
        guard isEnabled else { return }
        lock.lock()
        entries.append(e)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        lock.unlock()
    }

    func note(_ server: String, _ text: String) {
        add(DiagEntry(at: Date(), kind: "note", server: server, summary: text, detail: ""))
    }

    func recordMCP(server: String, method: String, requestBody: Data?, status: Int?, responseBody: Data?,
                   error: String?, ms: Int) {
        let reqStr = requestBody.flatMap { String(data: $0, encoding: .utf8) }.map(Self.redact) ?? ""
        let respStr = responseBody.flatMap { String(data: $0, encoding: .utf8) }.map(Self.redact) ?? ""
        let tool = Self.toolName(fromRequest: reqStr)
        let what = method + (tool.map { " \($0)" } ?? "")
        let outcome = error != nil ? "ERROR" : (status.map(String.init) ?? "—")
        let summary = "\(what) → \(outcome) (\(ms) ms)"
        var detail = "→ \(Self.cap(reqStr, 1500))"
        if !respStr.isEmpty { detail += "\n← \(Self.cap(respStr, 1500))" }
        if let error { detail += "\n✗ \(Self.redact(error))" }
        add(DiagEntry(at: Date(), kind: "mcp", server: server, summary: summary, detail: detail))
    }

    func recordOAuth(server: String, step: String, ok: Bool, info: String = "", error: String? = nil) {
        let summary = "\(step): " + (error != nil ? "ERROR" : "ok") + (info.isEmpty ? "" : " — \(info)")
        add(DiagEntry(at: Date(), kind: "oauth", server: server, summary: summary,
                      detail: error.map { "✗ \(Self.redact($0))" } ?? ""))
    }

    // MARK: - export & send

    func exportText() -> String {
        let items = snapshot()
        let header = "MCP to Intent diagnostics — \(items.count) events — \(ISO8601DateFormatter().string(from: Date()))"
        return ([header, ""] + items.flatMap { e -> [String] in
            e.detail.isEmpty ? [e.line] : [e.line, e.detail.split(separator: "\n").map { "    \($0)" }.joined(separator: "\n")]
        }).joined(separator: "\n")
    }

    /// Send every captured event to the configured syslog server (RFC 3164). UDP sends one datagram per line; TCP
    /// sends them newline-framed in one go (both are accepted by World Assistant's syslog listener).
    func sendToSyslog() async -> Result<Int, String> {
        let host = syslogHost
        guard !host.isEmpty else { return .failure("Set a syslog host first.") }
        guard let port = NWEndpoint.Port(rawValue: syslogPort) else { return .failure("That port is not valid.") }
        let items = snapshot()
        guard !items.isEmpty else { return .failure("Nothing captured yet. Turn recording on, reproduce the issue, then send.") }

        let hostname = Self.deviceHost()
        let lines = items.map { Self.syslogLine($0, hostname: hostname) }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: port, using: useTCP ? .tcp : .udp)

        return await withCheckedContinuation { (cont: CheckedContinuation<Result<Int, String>, Never>) in
            var finished = false
            func finish(_ r: Result<Int, String>) {
                guard !finished else { return }
                finished = true
                conn.cancel()
                cont.resume(returning: r)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let payloads: [Data] = self.useTCP
                        ? [Data(lines.map { $0 + "\n" }.joined().utf8)]
                        : lines.map { Data($0.utf8) }
                    let group = DispatchGroup()
                    var sendError: String?
                    for p in payloads {
                        group.enter()
                        conn.send(content: p, completion: .contentProcessed { err in
                            if let err { sendError = err.localizedDescription }
                            group.leave()
                        })
                    }
                    group.notify(queue: .global()) {
                        if let sendError { finish(.failure(sendError)) } else { finish(.success(items.count)) }
                    }
                case let .failed(err): finish(.failure(err.localizedDescription))
                case let .waiting(err): finish(.failure(err.localizedDescription))  // host unreachable, etc.
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 8) { finish(.failure("Timed out reaching \(host):\(self.syslogPort).")) }
        }
    }

    // MARK: - formatting & redaction

    /// RFC 3164: `<PRI>Mmm d HH:MM:SS hostname TAG: message`. PRI = facility 1 (user) * 8 + severity (6 info, 3 err).
    static func syslogLine(_ e: DiagEntry, hostname: String) -> String {
        let severity = (e.summary.contains("ERROR")) ? 3 : 6
        let pri = 1 * 8 + severity
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d HH:mm:ss"
        let stamp = f.string(from: e.at)
        let msg = e.detail.isEmpty ? e.summary : "\(e.summary) | \(e.detail.replacingOccurrences(of: "\n", with: " "))"
        return "<\(pri)>\(stamp) \(hostname) MCPtoIntent: [\(e.server.isEmpty ? "-" : e.server)] \(Self.cap(msg, 1800))"
    }

    static func deviceHost() -> String {
        let n = ProcessInfo.processInfo.hostName.split(separator: ".").first.map(String.init) ?? "iphone"
        return n.isEmpty ? "iphone" : n
    }

    private static func toolName(fromRequest req: String) -> String? {
        guard req.contains("\"tools/call\""),
              let r = req.range(of: "\"name\""),
              let q1 = req.range(of: "\"", range: r.upperBound..<req.endIndex),
              let q2 = req.range(of: "\"", range: q1.upperBound..<req.endIndex) else { return nil }
        return String(req[q1.upperBound..<q2.lowerBound])
    }

    static func cap(_ s: String, _ n: Int) -> String { s.count <= n ? s : String(s.prefix(n)) + "…(\(s.count))" }

    /// Remove bearer tokens and common secret fields so a log is safe to share.
    static func redact(_ s: String) -> String {
        var out = s
        let jsonKeys = ["access_token", "refresh_token", "id_token", "client_secret", "code", "code_verifier",
                        "token", "password"]
        for key in jsonKeys {
            if let re = try? NSRegularExpression(pattern: "(\"\(key)\"\\s*:\\s*\")[^\"]*(\")") {
                out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out),
                                                  withTemplate: "$1***$2")
            }
        }
        // Authorization: Bearer <token>, and bare "Bearer xxx"
        if let re = try? NSRegularExpression(pattern: "(Bearer\\s+)[A-Za-z0-9._~+/\\-]+=*", options: .caseInsensitive) {
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1***")
        }
        return out
    }
}
