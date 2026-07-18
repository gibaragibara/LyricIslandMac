import Foundation
import Security

enum KeychainStore {
    private static let service = "com.gibaragibara.LyricIslandMac"

    static func string(forKey account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, forKey account: String) {
        let trimmed = value
        if trimmed.isEmpty {
            delete(forKey: account)
            return
        }

        guard let data = trimmed.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
            return
        }
    }

    static func delete(forKey account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Load from Keychain, migrating a legacy UserDefaults value once if present.
    static func loadMigrating(account: String, legacyUserDefaultsKey: String) -> String {
        if let stored = string(forKey: account), !stored.isEmpty {
            return stored
        }

        guard let legacy = UserDefaults.standard.string(forKey: legacyUserDefaultsKey), !legacy.isEmpty else {
            return ""
        }

        set(legacy, forKey: account)
        UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
        return legacy
    }
}
