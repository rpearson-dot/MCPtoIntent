import Foundation

/// Resolves a usable access token for a server, and runs the interactive OAuth sign-in. Token resolution (refresh) is
/// silent and works from an App Intent; the interactive sign-in needs the app (it shows a web sheet).
final class AuthManager: @unchecked Sendable {
    static let shared = AuthManager()

    /// A Bearer token for a server. Token-mode returns the stored static token. OAuth-mode returns the access token,
    /// refreshing silently via the refresh token when it has expired; if there's no session or refresh fails, it asks
    /// the person to sign in again.
    func accessToken(for server: ServerConfig) async throws -> String {
        switch server.authMode {
        case .token:
            return Keychain.token(for: server.id)
        case .oauth:
            guard var session = Keychain.session(for: server.id) else { throw OAuthError.needsSignIn }
            if session.isFresh { return session.accessToken }
            guard let refresh = session.refreshToken, let url = URL(string: server.mcpURL) else {
                throw OAuthError.needsSignIn
            }
            let tok = try await OAuthClient(mcpURL: url).refresh(
                tokenEndpoint: session.tokenEndpoint, clientID: session.clientID, refreshToken: refresh)
            session.accessToken = tok.accessToken
            if let rt = tok.refreshToken { session.refreshToken = rt }
            session.expiresAt = tok.expiresIn.map { Date().addingTimeInterval($0) }
            Keychain.setSession(session, for: server.id)
            return session.accessToken
        }
    }

    /// Discover, register, authorize (PKCE) and exchange — storing the OAuth session. Must run on the main actor
    /// because it presents a web sheet.
    @MainActor
    func signIn(server: ServerConfig) async throws {
        guard let url = URL(string: server.mcpURL) else { throw MCPClientError.badURL }
        let client = OAuthClient(mcpURL: url)
        let meta = try await client.discover()
        let clientID = try await client.register(meta)
        let scope = meta.scopesSupported?.joined(separator: " ")
        let (code, verifier) = try await client.authorize(meta: meta, clientID: clientID, scope: scope)
        let tok = try await client.exchange(meta: meta, clientID: clientID, code: code, verifier: verifier)
        let session = OAuthSession(
            authorizationEndpoint: meta.authorizationEndpoint,
            tokenEndpoint: meta.tokenEndpoint,
            registrationEndpoint: meta.registrationEndpoint,
            clientID: clientID,
            scope: scope,
            resource: server.mcpURL,
            accessToken: tok.accessToken,
            refreshToken: tok.refreshToken,
            expiresAt: tok.expiresIn.map { Date().addingTimeInterval($0) })
        Keychain.setSession(session, for: server.id)
    }

    func hasSession(_ server: ServerConfig) -> Bool { Keychain.session(for: server.id) != nil }
    func signOut(_ server: ServerConfig) { Keychain.setSession(nil, for: server.id) }
}
