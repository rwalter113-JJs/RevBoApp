import SwiftUI

struct SettingsView: View {

    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var serverURLDraft   = ""
    @State private var granolaKeyDraft  = ""
    @State private var showGranolaKey   = false
    @State private var saved            = false

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

                        // ── Integrations ──────────────────────────────────────
                        settingsSection(title: "Integrations", icon: "puzzlepiece.extension.fill") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Granola API Key")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.revboMuted)
                                    Spacer()
                                    Button {
                                        showGranolaKey.toggle()
                                    } label: {
                                        Image(systemName: showGranolaKey ? "eye.slash" : "eye")
                                            .font(.caption)
                                            .foregroundStyle(Color.revboMuted)
                                    }
                                }

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

                                Link("Get your key at granola.ai →",
                                     destination: URL(string: "https://granola.ai")!)
                                    .font(.caption2)
                                    .foregroundStyle(Color.revboBlue)
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

    // MARK: - Save

    private func save() {
        // Trim whitespace — easy paste errors
        let url = serverURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = granolaKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        settings.serverURL    = url.isEmpty ? AppSettings.defaultServerURL : url
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
