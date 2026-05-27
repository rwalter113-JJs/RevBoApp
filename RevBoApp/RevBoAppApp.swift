//
//  RevBoAppApp.swift
//  RevBoApp
//
//  Created by Robert Walter on 4/8/26.
//

import SwiftUI
import Contacts
import AVFoundation

@main
struct RevBoAppApp: App {

    @Environment(\.scenePhase) private var scenePhase

    private let api = RevBoAPI()

    /// UserDefaults key for the last Granola auto-sync timestamp.
    private static let lastAutoSyncKey = "revbo.granola.lastAutoSync"
    /// Minimum interval between automatic background syncs (1 hour).
    private static let autoSyncInterval: TimeInterval = 3600

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
                .task { await requestPermissions() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                maybeAutoSync()
            }
        }
    }

    // MARK: - Permissions

    /// Request microphone and contacts permissions at launch so they are
    /// already granted before the user records their first voice note.
    private func requestPermissions() async {
        // Microphone — needed for voice notes
        if AVAudioApplication.shared.recordPermission == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
        }
        // Contacts — needed for Signal 3 name attribution
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            _ = try? await CNContactStore().requestAccess(for: .contacts)
        }
    }

    // MARK: - Auto-sync

    /// Trigger a Granola background sync when the app comes to foreground,
    /// throttled to once per hour. Silently skips if no Granola key is stored.
    private func maybeAutoSync() {
        let granolaKey = AppSettings.shared.granolaAPIKey
        guard !granolaKey.isEmpty else { return }

        let lastSync = UserDefaults.standard.double(forKey: Self.lastAutoSyncKey)
        let now      = Date().timeIntervalSince1970
        guard now - lastSync >= Self.autoSyncInterval else { return }

        // Record the timestamp immediately so concurrent foreground events don't double-fire
        UserDefaults.standard.set(now, forKey: Self.lastAutoSyncKey)

        Task.detached(priority: .background) {
            do {
                let contactMap = await api.buildGranolaContactMap()
                let result     = try await api.syncGranola(contactMap: contactMap)
                if result.meetings_processed > 0 {
                    // Log success — intentionally no key reference in the message
                    print("[RevBo] Granola auto-sync: \(result.meetings_processed) meetings, \(result.entries_created) entries")
                }
            } catch {
                // Silently absorb — user will see errors if they tap Sync Now in Settings
                print("[RevBo] Granola auto-sync failed (non-fatal)")
            }
        }
    }
}
