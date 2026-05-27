import SwiftUI

struct SettingsView: View {

    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var serverURLDraft   = ""
    @State private var granolaKeyDraft  = ""
    @State private var showGranolaKey   = false
    @State private var saved            = false

    // Granola sync state
    @State private var isSyncing        = false
    @State private var syncToast: String? = nil
    @State private var syncToastIsError = false

    private let api = RevBoAPI()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.revboBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // ── Server ────────────────────────────────────────────
                        settingsSection(title: "Server", icon: "server.rack") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Backend URL")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.revboMuted)

                                TextField("https://…", text: $serverURLDraft)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(Color.revboText)
                                    .tint(Color.revboOrange)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    .padding(10)
                                    .background(Color.revboBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                HStack {
                                    Text("Default: \(AppSettings.defaultServerURL)")
                                        .font(.caption2)
                                        .foregroundStyle(Color.revboMuted)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    if serverURLDraft != AppSettings.defaultServerURL {
                                        Button("Reset") {
                                            serverURLDraft = AppSettings.defaultServerURL
                                        }
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.revboOrange)
                                    }
                                }
                            }
                        }

                        // ── Granola ───────────────────────────────────────────
                        settingsSection(title: "Granola", icon: "puzzlepiece.extension.fill") {
                            VStack(alignment: .leading, spacing: 12) {

                                // Status row
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(granolaConnected ? Color.green : Color.gray)
                                        .frame(width: 8, height: 8)
                                    Text(granolaConnected ? "Connected" : "Not connected")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(granolaConnected ? Color.green : Color.revboMuted)
                                    Spacer()
                                    Button {
                                        showGranolaKey.toggle()
                                    } label: {
                                        Image(systemName: showGranolaKey ? "eye.slash" : "eye")
                                            .font(.caption)
                                            .foregroundStyle(Color.revboMuted)
                                    }
                                }

                                // API key field
                                Group {
                                    if showGranolaKey {
                                        TextField("Paste your Granola API key…", text: $granolaKeyDraft)
                                    } else {
                                        SecureField("Paste your Granola API key…", text: $granolaKeyDraft)
                                    }
                                }
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(Color.revboText)
                                .tint(Color.revboOrange)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(10)
                                .background(Color.revboBg)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                // Helper link
                                Link("Find your API key at app.granola.ai/settings →",
                                     destination: URL(string: "https://app.granola.ai/settings")!)
                                    .font(.caption2)
                                    .foregroundStyle(Color.revboBlue)

                                // Sync Now button (only when connected)
                                if granolaConnected {
                                    Button {
                                        triggerSync()
                                    } label: {
                                        HStack(spacing: 8) {
                                            if isSyncing {
                                                ProgressView()
                                                    .progressViewStyle(.circular)
                                                    .scaleEffect(0.8)
                                                    .tint(.black)
                                                Text("Syncing…")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(.black)
                                            } else {
                                                Image(systemName: "arrow.clockwise")
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(.black)
                                                Text("Sync Now")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(.black)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 40)
                                        .background(isSyncing ? Color.gray : Color.revboOrange)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .animation(.easeInOut(duration: 0.2), value: isSyncing)
                                    }
                                    .disabled(isSyncing)

                                    // Toast
                                    if let toast = syncToast {
                                        HStack(spacing: 6) {
                                            Image(systemName: syncToastIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(syncToastIsError ? Color.red : Color.green)
                                            Text(toast)
                                                .font(.caption)
                                                .foregroundStyle(syncToastIsError ? Color.red : Color.green)
                                        }
                                        .transition(.opacity)
                                    }
                                }
                            }
                        }

                        // ── About ─────────────────────────────────────────────
                        settingsSection(title: "About", icon: "info.circle") {
                            VStack(alignment: .leading, spacing: 6) {
                                infoRow(label: "Version",
                                        value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                                infoRow(label: "Build",
                                        value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                            }
                        }

                        // ── Save ──────────────────────────────────────────────
                        Button {
                            save()
                        } label: {
                            HStack {
                                Spacer()
                                if saved {
                                    Label("Saved", systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.black)
                                } else {
                                    Text("Save Settings")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.black)
                                }
                                Spacer()
                            }
                            .frame(height: 50)
                            .background(saved ? Color.green : Color.revboOrange)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .animation(.easeInOut(duration: 0.2), value: saved)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.revboOrange)
                }
            }
        }
        .onAppear {
            serverURLDraft  = settings.serverURL
            granolaKeyDraft = settings.granolaAPIKey
        }
    }

    // MARK: - Computed

    private var granolaConnected: Bool {
        !settings.granolaAPIKey.isEmpty
    }

    // MARK: - Sync

    private func triggerSync() {
        guard !isSyncing else { return }
        isSyncing = true
        syncToast = nil

        Task {
            do {
                let contactMap = api.buildGranolaContactMap()
                let result     = try await api.syncGranola(contactMap: contactMap)
                await MainActor.run {
                    isSyncing = false
                    let count = result.meetings_processed
                    syncToast = count == 0
                        ? "No new meetings to import"
                        : "\(count) meeting\(count == 1 ? "" : "s") imported (\(result.entries_created) entries)"
                    syncToastIsError = false
                    dismissToastAfterDelay()
                }
            } catch RevBoAPIError.serverError(let msg) {
                await MainActor.run {
                    isSyncing = false
                    if msg.contains("Invalid Granola") || msg.contains("401") {
                        syncToast = "Invalid Granola API key — check Settings"
                    } else {
                        syncToast = "Sync failed — try again"
                    }
                    syncToastIsError = true
                    dismissToastAfterDelay()
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    syncToast = "Sync failed — try again"
                    syncToastIsError = true
                    dismissToastAfterDelay()
                }
            }
        }
    }

    private func dismissToastAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { syncToast = nil }
        }
    }

    // MARK: - Save

    private func save() {
        // Trim whitespace — easy paste errors
        let url = serverURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = granolaKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        settings.serverURL     = url.isEmpty ? AppSettings.defaultServerURL : url
        settings.granolaAPIKey = key

        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { saved = false }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.revboOrange)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.revboText)
            }
            content()
        }
        .padding(16)
        .background(Color.revboSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.revboMuted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.revboText)
        }
    }
}
