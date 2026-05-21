import Foundation
import Security

/// Manages the per-device salt stored in the iOS Keychain.
///
/// The salt is a 32-byte cryptographically random value generated once on first
/// launch and stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
///
/// - It never leaves the device.
/// - Backups are excluded (`kSecAttrSynchronizable = false` is the default).
/// - If the user deletes and reinstalls the app the salt is re-generated,
///   making all existing server-side hashes unresolvable. This is intentional —
///   it prevents cross-installation correlation (PRD 3 §4).
final class KeychainSaltManager {

    static let shared = KeychainSaltManager()
    private init() {}

    private let service  = "ai.revbo.contactsalt"
    private let account  = "per_device_salt"

    // MARK: - Public

    /// Returns the existing salt or generates and stores a new one.
    func salt() -> Data {
        if let existing = loadSalt() { return existing }
        let new = generateSalt()
        saveSalt(new)
        return new
    }

    // MARK: - Private

    private func loadSalt() -> Data? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private func saveSalt(_ salt: Data) {
        let attrs: [CFString: Any] = [
            kSecClass:                   kSecClassGenericPassword,
            kSecAttrService:             service,
            kSecAttrAccount:             account,
            kSecValueData:               salt,
            kSecAttrAccessible:          kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable:      false,
        ]
        // Delete any stale entry first (handles reinstall race)
        SecItemDelete(attrs as CFDictionary)
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private func generateSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}
