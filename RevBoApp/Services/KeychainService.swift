import Foundation
import Security

/// Minimal wrapper around the iOS Keychain for storing small secrets (API keys).
/// Values are stored as UTF-8 strings under a fixed service name.
enum KeychainService {

    private static let service = "ai.revbo.app"

    // MARK: - Save

    @discardableResult
    static func save(key: String, value: String) -> Bool {
        let data = value.data(using: .utf8)!

        // Delete any existing item first
        delete(key: key)

        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key,
            kSecValueData:        data,
            kSecAttrAccessible:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Load

    static func load(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    // MARK: - Delete

    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
