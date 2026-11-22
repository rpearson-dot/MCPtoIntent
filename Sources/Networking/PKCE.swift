import CryptoKit
import Foundation

/// PKCE (RFC 7636) helpers and URL-safe random values for the OAuth authorization-code flow.
enum PKCE {
    /// A high-entropy code verifier (43–128 chars of the unreserved set).
    static func verifier() -> String { randomURLSafe(64) }

    /// The S256 challenge for a verifier: base64url(SHA256(verifier)).
    static func challenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return base64url(Data(hash))
    }

    static func state() -> String { randomURLSafe(32) }

    static func randomURLSafe(_ byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64url(Data(bytes))
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
