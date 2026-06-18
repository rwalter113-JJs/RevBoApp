import SwiftUI

// MARK: - Cloud Storage Setup Guide
// Shows users how to connect Google Drive/Dropbox/OneDrive to iOS Files app

struct CloudStorageGuideView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {

                        // Header
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "cloud.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(Color.revboOrange)
                                Spacer()
                            }

                            Text("Connect Cloud Storage")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)

                            Text("Import decks, docs, and files directly from Google Drive, Dropbox, or OneDrive.")
                                .font(.system(size: 15))
                                .foregroundStyle(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, 8)

                        // How it works
                        InfoBox(
                            icon: "info.circle.fill",
                            title: "How It Works",
                            description: "RevBo uses your iPhone's Files app to access cloud storage. Once connected, you can browse and import files directly from Drive, Dropbox, or OneDrive."
                        )

                        // Google Drive
                        ProviderCard(
                            name: "Google Drive",
                            icon: "g.circle.fill",
                            color: .blue,
                            steps: [
                                "Download the Google Drive app from the App Store",
                                "Open the Google Drive app and sign in",
                                "Tap your profile picture → Settings",
                                "Scroll down and enable 'Show Google Drive in Files app'",
                                "Open RevBo → Import → Tap folder icon",
                                "Google Drive will appear under 'Locations'"
                            ]
                        )

                        // Dropbox
                        ProviderCard(
                            name: "Dropbox",
                            icon: "square.and.arrow.down.fill",
                            color: Color(red: 0.0, green: 0.47, blue: 0.95),
                            steps: [
                                "Download the Dropbox app from the App Store",
                                "Open the Dropbox app and sign in",
                                "Tap 'Files' tab at the bottom",
                                "Dropbox is automatically available in Files app",
                                "Open RevBo → Import → Tap folder icon",
                                "Dropbox will appear under 'Locations'"
                            ]
                        )

                        // OneDrive
                        ProviderCard(
                            name: "OneDrive",
                            icon: "cloud.fill",
                            color: Color(red: 0.0, green: 0.46, blue: 0.74),
                            steps: [
                                "Download the OneDrive app from the App Store",
                                "Open the OneDrive app and sign in with Microsoft account",
                                "OneDrive is automatically available in Files app",
                                "Open RevBo → Import → Tap folder icon",
                                "OneDrive will appear under 'Locations'"
                            ]
                        )

                        // Quick tip
                        InfoBox(
                            icon: "lightbulb.fill",
                            title: "Quick Tip",
                            description: "After connecting, you can also use the iOS Files app directly to browse your cloud storage, then share files to RevBo using the share button."
                        )

                        // CTA
                        VStack(spacing: 16) {
                            Text("Ready to import?")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)

                            Button {
                                dismiss()
                            } label: {
                                Text("Got It")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color.revboOrange)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Cloud Storage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.gray)
                    }
                }
            }
        }
    }
}

// MARK: - Provider Card

private struct ProviderCard: View {
    let name: String
    let icon: String
    let color: Color
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(color)

                Text(name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()
            }

            // Steps
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 24, height: 24)
                            .background(color)
                            .clipShape(Circle())

                        Text(step)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Info Box

private struct InfoBox: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.revboOrange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.revboOrange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.revboOrange.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    CloudStorageGuideView()
}
