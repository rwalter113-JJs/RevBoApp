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

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .task { await requestPermissions() }
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
}
