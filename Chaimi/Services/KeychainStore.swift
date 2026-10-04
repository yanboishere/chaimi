import Foundation
import Security

/// 本机钥匙串存取(kSecClassGenericPassword)
enum KeychainStore {
    private static let service = "ng.yanbowa.chaimi"
    static let apiKeyAccount = "anthropic_api_key"
    static let appleUserAccount = "apple_user_id"

    private static func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        SecItemDelete(baseQuery(account: account) as CFDictionary) == errSecSuccess
    }

    // MARK: Anthropic API Key 便捷封装(保持旧调用点不变)

    @discardableResult
    static func saveAPIKey(_ key: String) -> Bool { save(key, account: apiKeyAccount) }
    static func loadAPIKey() -> String? { load(account: apiKeyAccount) }
    @discardableResult
    static func deleteAPIKey() -> Bool { delete(account: apiKeyAccount) }
    static var hasKey: Bool { loadAPIKey() != nil }
}
