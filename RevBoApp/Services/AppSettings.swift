import Foundation
import Combine

/// Singleton that owns all user-configurable settings.
///
/// - `serverURL`     — stored in UserDefaults; defaults to the Railway production URL.
///                     Can be overridden in Settings for local dev or self-hosting.
/// - `granolaAPIKey` — stored in the iOS Keychain; per-user Granola API key.
/// - `revboAPIKey`   — bundled compile-time constant; not user-configurable.
///                     Must match REVBO_API_KEY on the Railway server.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    // ── Compile-time constants ────────────────────────────────────────────────
    /// Must match the REVBO_API_KEY environment variable on Railway.
    /// Change this before distributing a build to beta testers.
    static let revboAPIKey = "B49116A8-A5AF-457D-8376-F18806C07E4A"

    /// Default production server. Overridable in Settings.
    static let defaultServerURL = "https://revbo-engine-production.up.railway.app"

    // ── Persisted settings ────────────────────────────────────────────────────

    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: Keys.serverURL) }
    }

    @Published var granolaAPIKey: String {
        didSet { KeychainService.save(key: Keys.granolaKey, value: granolaAPIKey) }
    }

    // MARK: - Init

    private init() {
        serverURL    = UserDefaults.standard.string(forKey: Keys.serverURL)
                       ?? AppSettings.defaultServerURL
        granolaAPIKey = KeychainService.load(key: Keys.granolaKey) ?? ""
    }

    // MARK: - Helpers

    func resetServerURL() {
        serverURL = AppSettings.defaultServerURL
    }

    // MARK: - Keys

    private enum Keys {
        static let serverURL  = "revbo_server_url"
        static let granolaKey = "granola_api_key"
    }
}
