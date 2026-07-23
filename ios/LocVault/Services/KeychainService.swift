import Foundation
import Security

enum KeychainService {
    private static let service = "com.locvault.app"
    private static let tokenAccount = "auth_token"
    private static let userAccount = "auth_user"
    private static let apiURLAccount = "api_base_url"

    static let defaultAPIBaseURL = "http://127.0.0.1:3001"

    static func saveToken(_ token: String) throws {
        try save(token, account: tokenAccount)
    }

    static func loadToken() -> String? {
        load(account: tokenAccount)
    }

    static func deleteToken() {
        delete(account: tokenAccount)
    }

    static func saveUser(_ user: User) throws {
        let data = try JSONEncoder().encode(user)
        try save(data, account: userAccount)
    }

    static func loadUser() -> User? {
        guard let data = loadData(account: userAccount) else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }

    static func deleteUser() {
        delete(account: userAccount)
    }

    static func saveAPIBaseURL(_ url: String) throws {
        try save(url, account: apiURLAccount)
    }

    static func loadAPIBaseURL() -> String {
        load(account: apiURLAccount) ?? defaultAPIBaseURL
    }

    static func clearSession() {
        deleteToken()
        deleteUser()
    }

    // MARK: - Private

    private static func save(_ string: String, account: String) throws {
        guard let data = string.data(using: .utf8) else { return }
        try save(data, account: account)
    }

    private static func save(_ data: Data, account: String) throws {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LocVaultError.server("Keychain write failed (\(status)).")
        }
    }

    private static func load(account: String) -> String? {
        guard let data = loadData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func loadData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
