import Foundation
import Security

/// A tiny Keychain wrapper. Secrets — static tokens and OAuth sessions — live here, not in UserDefaults.
enum Keychain {
    private static let service = "com.mcptointent.secrets"

    // MARK: - generic data by account

    static func set(_ data: Data?, account: String) {
        delete(account: account)
        guard let data, !data.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func data(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - convenience: a server's static token

    static func setToken(_ token: String, for id: UUID) {
        set(token.data(using: .utf8), account: "token.\(id.uuidString)")
    }

    static func token(for id: UUID) -> String {
        data(account: "token.\(id.uuidString)").flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    // MARK: - convenience: a server's OAuth session

    static func setSession(_ session: OAuthSession?, for id: UUID) {
        set(session.flatMap { try? JSONEncoder().encode($0) }, account: "oauth.\(id.uuidString)")
    }

    static func session(for id: UUID) -> OAuthSession? {
        data(account: "oauth.\(id.uuidString)").flatMap { try? JSONDecoder().decode(OAuthSession.self, from: $0) }
    }

    static func clear(for id: UUID) {
        delete(account: "token.\(id.uuidString)")
        delete(account: "oauth.\(id.uuidString)")
    }
}
