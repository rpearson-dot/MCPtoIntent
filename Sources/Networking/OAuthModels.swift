import Foundation

/// OAuth 2.0 / MCP authorization metadata and token shapes (RFC 8414 authorization-server metadata, RFC 9728
/// protected-resource metadata, RFC 7591 dynamic client registration, RFC 6749 token response).

struct ProtectedResourceMetadata: Codable {
    let authorizationServers: [String]?
    enum CodingKeys: String, CodingKey { case authorizationServers = "authorization_servers" }
}

struct AuthServerMetadata: Codable {
    let issuer: String?
    let authorizationEndpoint: String
    let tokenEndpoint: String
    let registrationEndpoint: String?
    let codeChallengeMethodsSupported: [String]?
    let scopesSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case scopesSupported = "scopes_supported"
    }
}

struct ClientRegistrationResponse: Codable {
    let clientID: String
    let clientSecret: String?
    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String?
    let expiresIn: Double?
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

/// What the app stores for an OAuth-protected server: the endpoints and client id needed to refresh, and the tokens.
/// Secret, so it lives in the Keychain.
struct OAuthSession: Codable {
    var authorizationEndpoint: String
    var tokenEndpoint: String
    var registrationEndpoint: String?
    var clientID: String
    var scope: String?
    var resource: String          // the MCP endpoint (RFC 8707 audience)
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?

    var isFresh: Bool {
        guard let expiresAt else { return true }           // no expiry given: assume usable
        return expiresAt.timeIntervalSinceNow > 60         // a minute's margin
    }
}

enum OAuthError: LocalizedError {
    case discoveryFailed
    case noAuthorizationServer
    case registrationUnavailable
    case authorizationCancelled
    case authorizationFailed(String)
    case stateMismatch
    case tokenExchangeFailed(String)
    case needsSignIn

    var errorDescription: String? {
        switch self {
        case .discoveryFailed: return "Couldn't find this server's sign-in details."
        case .noAuthorizationServer: return "This server didn't name an authorization server."
        case .registrationUnavailable: return "This server doesn't support automatic app registration."
        case .authorizationCancelled: return "Sign-in was cancelled."
        case let .authorizationFailed(m): return "Sign-in failed: \(m)"
        case .stateMismatch: return "Sign-in response didn't match the request."
        case let .tokenExchangeFailed(m): return "Couldn't get a token: \(m)"
        case .needsSignIn: return "Please open the app and sign in to this server again."
        }
    }
}
