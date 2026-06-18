import SwiftUI
import UIKit

struct SettingsView: View {

    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var serverURLDraft   = ""
    @State private var saved            = false

    // Inbox email state
    @AppStorage("revbo.inboxEmail") private var cachedInboxEmail = ""
    @State private var inboxEmailLoading = false
    @State private var inboxEmailError   = false
    @State private var copyToast: String? = nil

    // Delete all data state
    @State private var showDeleteConfirm = false
    @State private var isDeleting        = false
    @State private var deleteToast: String? = nil
    @State private var missingLinksCount: Int = 0

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

                        // ── Forward to RevBo ──────────────────────────────────
                        settingsSection(title: "FORWARD TO REVBO", icon: "envelope.fill") {
                            VStack(alignment: .leading, spacing: 12) {

                                // Headline + subtitle
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Your RevBo Email Address")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.revboText)
                                    Text("Forward anything to this address — Granola meeting notes, email threads, articles, call summaries. RevBo reads it and adds it to your Brain.")
                                        .font(.caption)
                                        .foregroundStyle(Color.revboMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                // Email address box
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.revboBg)

                                    if inboxEmailLoading {
                                        HStack {
                                            ProgressView()
                                                .progressViewStyle(.circular)
                                                .scaleEffect(0.8)
                                                .tint(Color.revboMuted)
                                            Text("Fetching your address…")
                                                .font(.system(size: 13, design: .monospaced))
                                                .foregroundStyle(Color.revboMuted)
                                        }
                                        .padding(10)
                                    } else if inboxEmailError {
                                        Button {
                                            Task { await loadInboxEmail(force: true) }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "arrow.clockwise")
                                                    .font(.caption)
                                                Text("Tap to retry")
                                                    .font(.system(size: 13))
                                            }
                                            .foregroundStyle(Color.revboOrange)
                                            .padding(10)
                                        }
                                    } else {
                                        Text(cachedInboxEmail.isEmpty ? "Loading…" : cachedInboxEmail)
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundStyle(cachedInboxEmail.isEmpty ? Color.revboMuted : Color.revboText)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(10)
                                    }
                                }
                                .frame(minHeight: 40)

                                // Copy button + toast
                                HStack(spacing: 10) {
                                    Button {
                                        copyEmail()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: copyToast != nil ? "checkmark" : "doc.on.doc")
                                                .font(.system(size: 13, weight: .semibold))
                                            Text(copyToast ?? "Copy Address")
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .foregroundStyle(.black)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 36)
                                        .background(copyToast != nil ? Color.green : Color.revboOrange)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .animation(.easeInOut(duration: 0.2), value: copyToast)
                                    }
                                    .disabled(cachedInboxEmail.isEmpty || inboxEmailLoading)
                                }

                                // Works-great-for hint
                                Text("Works great for: Granola meeting notes · Email threads · Articles · Call recaps · Any text you want to remember")
                                    .font(.caption2)
                                    .foregroundStyle(Color.revboMuted)
                                    .fixedSize(horizontal: false, vertical: true)

                                // Support reference — first 8 chars of permanent user ID
                                let shortID = String(AppSettings.shared.userID.prefix(8))
                                Text("ID: \(shortID)…")
                                    .font(.caption2)
                                    .foregroundStyle(Color.revboMuted.opacity(0.6))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                        .onAppear {
                            if cachedInboxEmail.isEmpty {
                                Task { await loadInboxEmail() }
                            }
                        }

                        // ── Profile ───────────────────────────────────────────
                        settingsSection(title: "PROFILE", icon: "person.crop.circle.fill") {
                            NavigationLink {
                                ProfileSettingsView()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "briefcase.fill")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.revboOrange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Job Context & Sales Config")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Color.revboText)
                                        Text("What you sell, buyer persona, quota")
                                            .font(.caption)
                                            .foregroundStyle(Color.revboMuted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(Color.revboSubtle)
                                }
                            }
                        }

                        // ── Data Management ───────────────────────────────────
                        settingsSection(title: "DATA MANAGEMENT", icon: "folder.fill") {
                            NavigationLink {
                                MissingLinksView()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "link.circle.fill")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.revboOrange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Missing Links")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Color.revboText)
                                        Text("Connect intel to contacts")
                                            .font(.caption)
                                            .foregroundStyle(Color.revboMuted)
                                    }
                                    Spacer()
                                    if missingLinksCount > 0 {
                                        Text("\(missingLinksCount)")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.revboOrange)
                                            .clipShape(Capsule())
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(Color.revboSubtle)
                                }
                            }
                        }
                        .task {
                            await loadMissingLinksCount()
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

                        // ── Beta Feedback ─────────────────────────────────────
                        settingsSection(title: "BETA FEEDBACK", icon: "envelope.fill") {
                            Button {
                                if let url = URL(string: "mailto:feedback@revbo.ai?subject=RevBo%20Beta%20Feedback") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "envelope.fill")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.revboOrange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Send Feedback")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Color.revboText)
                                        Text("Help us improve RevBo")
                                            .font(.caption)
                                            .foregroundStyle(Color.revboMuted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.revboMuted)
                                }
                            }
                        }

                        // ── Data ──────────────────────────────────────────────
                        settingsSection(title: "Data", icon: "externaldrive.fill") {
                            VStack(spacing: 0) {
                                Button {
                                    showDeleteConfirm = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 15))
                                            .foregroundStyle(Color.red)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Delete All Brain Data")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(Color.red)
                                            Text("Permanently removes all notes and intelligence")
                                                .font(.caption)
                                                .foregroundStyle(Color.revboMuted)
                                        }
                                        Spacer()
                                        if isDeleting {
                                            ProgressView()
                                                .progressViewStyle(.circular)
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(Color.revboMuted)
                                        }
                                    }
                                }
                                .disabled(isDeleting)

                                if let toast = deleteToast {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(Color.green)
                                        Text(toast)
                                            .font(.caption)
                                            .foregroundStyle(Color.green)
                                    }
                                    .padding(.top, 10)
                                    .transition(.opacity)
                                }
                            }
                        }
                        .alert("Delete All Brain Data?", isPresented: $showDeleteConfirm) {
                            Button("Delete Everything", role: .destructive) {
                                Task { await performDeleteAll() }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This permanently deletes all your notes, voice recordings, and relationship intelligence from RevBo. This cannot be undone.")
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
            serverURLDraft = settings.serverURL
        }
    }

    // MARK: - Inbox email

    private func loadInboxEmail(force: Bool = false) async {
        guard force || cachedInboxEmail.isEmpty else { return }
        await MainActor.run {
            inboxEmailLoading = true
            inboxEmailError   = false
        }
        do {
            let response = try await api.fetchInboxEmail()
            await MainActor.run {
                cachedInboxEmail  = response.email
                inboxEmailLoading = false
            }
        } catch {
            await MainActor.run {
                inboxEmailLoading = false
                inboxEmailError   = true
            }
        }
    }

    private func copyEmail() {
        guard !cachedInboxEmail.isEmpty else { return }
        UIPasteboard.general.string = cachedInboxEmail
        withAnimation { copyToast = "Copied!" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copyToast = nil }
        }
    }

    // MARK: - Missing Links Count

    private func loadMissingLinksCount() async {
        do {
            let response = try await api.getMissingLinksCount()
            await MainActor.run {
                missingLinksCount = response.count
            }
        } catch {
            // Silent fail — count is just a badge, not critical
            print("DEBUG Failed to load missing links count: \(error)")
        }
    }

    // MARK: - Delete All

    private func performDeleteAll() async {
        isDeleting = true
        do {
            let _ = try await api.deleteAllData()
            await MainActor.run {
                isDeleting = false
                withAnimation { deleteToast = "Brain cleared" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation { deleteToast = nil }
                }
            }
        } catch {
            await MainActor.run {
                isDeleting = false
            }
        }
    }

    // MARK: - Save

    private func save() {
        let url = serverURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.serverURL = url.isEmpty ? AppSettings.defaultServerURL : url

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
