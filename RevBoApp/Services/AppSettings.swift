import Foundation
import Combine
import Security

/// Singleton that owns all user-configurable settings.
///
/// - `serverURL`   — stored in UserDefaults; defaults to the Railway production URL.
///                   Can be overridden in Settings for local dev or self-hosting.
/// - `revboAPIKey` — bundled compile-time constant; not user-configurable.
///                   Must match REVBO_API_KEY on the Railway server.
/// - `userID`      — permanent UUID stored in Keychain; generated once on first access.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    // ── Compile-time constants ────────────────────────────────────────────────
    /// Must match the REVBO_API_KEY environment variable on Railway.
    /// Change this before distributing a build to beta testers.
    static let revboAPIKey = "B49116A8-A5AF-457D-8376-F18806C07E4A"

    /// Default production server. Overridable in Settings.
    static let defaultServerURL = "https://revbo-engine-production.up.railway.app"

    // ── Persisted settings ────────────────────────────────────────────────────
    // Use App Group for sharing with Share Extension
    private static let appGroupDefaults = UserDefaults(suiteName: "group.com.robwalter.revbo")

    @Published var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: Keys.serverURL)
            AppSettings.appGroupDefaults?.set(serverURL, forKey: "revbo.serverURL")
        }
    }

    // MARK: - Permanent User Identity

    /// The user's permanent brain identity. Generated once on first access and
    /// stored in the Keychain — never changes across app launches or reinstalls
    /// (as long as the Keychain item persists).
    var userID: String {
        if let existing = readKeychain(Keys.userID) {
            // Also sync to App Group for Share Extension
            AppSettings.appGroupDefaults?.set(existing, forKey: "revbo.userID")
            return existing
        }
        let newID = UUID().uuidString
        saveKeychain(Keys.userID, value: newID)
        AppSettings.appGroupDefaults?.set(newID, forKey: "revbo.userID")
        return newID
    }

    // MARK: - Init

    private init() {
        serverURL = UserDefaults.standard.string(forKey: Keys.serverURL)
                    ?? AppSettings.defaultServerURL
        // Sync to App Group on init
        AppSettings.appGroupDefaults?.set(serverURL, forKey: "revbo.serverURL")
        // Ensure userID is synced
        _ = userID
    }

    // MARK: - Helpers

    func resetServerURL() {
        serverURL = AppSettings.defaultServerURL
    }

    // MARK: - Keychain

    private func readKeychain(_ key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private func saveKeychain(_ key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        // Delete any existing item first, then add the new one.
        let deleteQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrAccount:      key,
            kSecValueData:        data,
            kSecAttrAccessible:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    // MARK: - Keys

    private enum Keys {
        static let serverURL = "revbo_server_url"
        static let userID    = "revbo.user_id"
    }
}
