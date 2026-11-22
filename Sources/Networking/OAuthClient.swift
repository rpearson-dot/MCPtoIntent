import AuthenticationServices
import Foundation
import UIKit

/// The OAuth 2.0 authorization-code + PKCE flow for an MCP server, with discovery (RFC 8414 / 9728) and dynamic
/// client registration (RFC 7591). Used for servers like Home Assistant that protect their MCP endpoint with OAuth.
/// A class, because it must retain the web-auth session and its presentation anchor for the duration of sign-in.
final class OAuthClient: NSObject {
    let mcpURL: URL
    let redirectScheme = "mcptointent"
    var redirectURI: String { "\(redirectScheme)://oauth-callback" }

    private var session: URLSession { .shared }
    private var webAuth: ASWebAuthenticationSession?

    init(mcpURL: URL) {
        self.mcpURL = mcpURL
        super.init()
    }

    // MARK: - discovery

    /// Find the authorization server's metadata for this MCP endpoint: from the 401's resource-metadata pointer, then
    /// the well-known protected-resource document, then the origin's own authorization-server metadata.
    func discover() async throws -> AuthServerMetadata {
        var authServerBase: String?

        // 1) the resource-metadata URL named in a 401 WWW-Authenticate header
        if let rm = try? await resourceMetadataURLFrom401(), let md: ProtectedResourceMetadata = try? await getJSON(rm) {
            authServerBase = md.authorizationServers?.first
        }
        // 2) the well-known protected-resource document at the origin
        if authServerBase == nil, let origin = originURL() {
            let prmURL = origin.appendingPathComponent(".well-known/oauth-protected-resource")
            if let md: ProtectedResourceMetadata = try? await getJSON(prmURL) {
                authServerBase = md.authorizationServers?.first
            }
        }
        // 3) fall back to treating the origin itself as the authorization server
        let base = authServerBase ?? originURL()?.absoluteString
        guard let base, let baseURL = URL(string: base) else { throw OAuthError.noAuthorizationServer }

        for path in [".well-known/oauth-authorization-server", ".well-known/openid-configuration"] {
            if let md: AuthServerMetadata = try? await getJSON(baseURL.appendingPathComponent(path)) {
                return md
            }
        }
        throw OAuthError.discoveryFailed
    }

    private func resourceMetadataURLFrom401() async throws -> URL? {
        var req = URLRequest(url: mcpURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(RPCRequest(id: 1, method: "ping", params: nil))
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 401,
              let header = http.value(forHTTPHeaderField: "WWW-Authenticate") else { return nil }
        // WWW-Authenticate: Bearer resource_metadata="https://.../.well-known/oauth-protected-resource"
        guard let range = header.range(of: "resource_metadata=") else { return nil }
        let tail = header[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        let value = tail.split(separator: "\"").first.map(String.init) ?? tail.split(separator: ",").first.map(String.init) ?? tail
        return URL(string: value)
    }

    private func originURL() -> URL? {
        guard var comps = URLComponents(url: mcpURL, resolvingAgainstBaseURL: false) else { return nil }
        comps.path = ""
        comps.query = nil
        comps.fragment = nil
        return comps.url
    }

    private func getJSON<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OAuthError.discoveryFailed
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - dynamic client registration

    func register(_ meta: AuthServerMetadata) async throws -> String {
        guard let endpoint = meta.registrationEndpoint, let url = URL(string: endpoint) else {
            throw OAuthError.registrationUnavailable
        }
        let body: [String: Any] = [
            "client_name": "MCP to Intent",
            "redirect_uris": [redirectURI],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none",
            "application_type": "native",
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OAuthError.registrationUnavailable
        }
        return try JSONDecoder().decode(ClientRegistrationResponse.self, from: data).clientID
    }

    // MARK: - authorization (interactive)

    @MainActor
    func authorize(meta: AuthServerMetadata, clientID: String, scope: String?) async throws -> (code: String, verifier: String) {
        let verifier = PKCE.verifier()
        let challenge = PKCE.challenge(for: verifier)
        let state = PKCE.state()

        guard var comps = URLComponents(string: meta.authorizationEndpoint) else {
            throw OAuthError.authorizationFailed("bad authorization endpoint")
        }
        var items = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "resource", value: mcpURL.absoluteString),
        ]
        if let scope { items.append(URLQueryItem(name: "scope", value: scope)) }
        comps.queryItems = (comps.queryItems ?? []) + items
        guard let authURL = comps.url else { throw OAuthError.authorizationFailed("couldn't build the sign-in URL") }

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let auth = ASWebAuthenticationSession(url: authURL, callbackURLScheme: redirectScheme) { url, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    cont.resume(throwing: OAuthError.authorizationCancelled)
                } else if let error {
                    cont.resume(throwing: error)
                } else if let url {
                    cont.resume(returning: url)
                } else {
                    cont.resume(throwing: OAuthError.authorizationFailed("no callback"))
                }
            }
            auth.presentationContextProvider = self
            auth.prefersEphemeralWebBrowserSession = false
            self.webAuth = auth
            if !auth.start() {
                cont.resume(throwing: OAuthError.authorizationFailed("couldn't start sign-in"))
            }
        }
        self.webAuth = nil

        let returned = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = returned.first(where: { $0.name == "error" })?.value {
            throw OAuthError.authorizationFailed(err)
        }
        guard returned.first(where: { $0.name == "state" })?.value == state else { throw OAuthError.stateMismatch }
        guard let code = returned.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.authorizationFailed("no code returned")
        }
        return (code, verifier)
    }

    // MARK: - token endpoint

    func exchange(meta: AuthServerMetadata, clientID: String, code: String, verifier: String) async throws -> TokenResponse {
        try await token(meta.tokenEndpoint, params: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
            "resource": mcpURL.absoluteString,
        ])
    }

    func refresh(tokenEndpoint: String, clientID: String, refreshToken: String) async throws -> TokenResponse {
        try await token(tokenEndpoint, params: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "resource": mcpURL.absoluteString,
        ])
    }

    private func token(_ endpoint: String, params: [String: String]) async throws -> TokenResponse {
        guard let url = URL(string: endpoint) else { throw OAuthError.tokenExchangeFailed("bad token endpoint") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formEncoded(params)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)?.prefix(200).description ?? ""
            throw OAuthError.tokenExchangeFailed(body)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func formEncoded(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = params.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=" +
            "\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }
}

extension OAuthClient: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
