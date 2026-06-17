import SwiftUI

// MARK: - Unattributed Entries View
// Shows brain entries with no contact attribution so user can assign them.

struct UnattributedEntriesView: View {

    @StateObject private var api = RevBoAPI()
    @ObservedObject private var store = ContactAttributionStore.shared

    @State private var entries: [UnattributedEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedEntry: UnattributedEntry?
    @State private var showContactPicker = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                if isLoading {
                    ProgressView()
                        .tint(Color.revboOrange)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entries.isEmpty {
                    emptyState
                } else {
                    entryList
                }
            }
        }
        .navigationTitle("Unattributed Entries")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await loadEntries() }
        .sheet(isPresented: $showContactPicker) {
            if let entry = selectedEntry {
                AttributionContactPicker(brainId: entry.id) { contact in
                    Task { await attributeEntry(entry, to: contact) }
                }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let msg = errorMessage {
                Text(msg)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.revboOrange)
            Text("All entries attributed")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text("Every brain entry is linked to a contact.")
                .font(.system(size: 14))
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Entry List

    private var entryList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(entries) { entry in
                    EntryCard(entry: entry) {
                        selectedEntry = entry
                        showContactPicker = true
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Data Loading

    private func loadEntries() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await api.queryBrain(
                "",
                filter: ["contact_hash": "unattributed"],
                n: 50
            )

            await MainActor.run {
                entries = response.results.map { result in
                    UnattributedEntry(
                        id: result.metadata["brain_id"] ?? UUID().uuidString,
                        text: result.text,
                        date: result.metadata["stored_at"] ?? "",
                        source: result.metadata["source_type"] ?? "unknown"
                    )
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load entries: \(error.localizedDescription)"
            }
        }
    }

    private func attributeEntry(_ entry: UnattributedEntry, to contact: TrackedContact) async {
        do {
            let hash = ContactHashService.shared.hash(email: contact.email ?? "")
            _ = try await api.attachContactHash(ContactAttachRequest(
                brainId: entry.id,
                contactHash: hash
            ))

            await MainActor.run {
                entries.removeAll { $0.id == entry.id }
                selectedEntry = nil
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to attribute: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Entry Card

private struct EntryCard: View {

    let entry: UnattributedEntry
    let onAssign: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sourceLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.revboOrange)
                    Text(dateLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                }
                Spacer()
                Button {
                    onAssign()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 13))
                        Text("Assign")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.revboOrange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.revboOrange.opacity(0.15))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Text(entry.text)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color(white: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var sourceLabel: String {
        switch entry.source {
        case "voice": return "Voice Note"
        case "file": return "File Upload"
        case "email": return "Email Forward"
        case "text": return "Text Note"
        default: return "Unknown Source"
        }
    }

    private var dateLabel: String {
        guard !entry.date.isEmpty else { return "Unknown date" }
        // ISO 8601 string → relative date
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: entry.date) {
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .short
            return rel.localizedString(for: date, relativeTo: Date())
        }
        return entry.date
    }
}

// MARK: - Model

struct UnattributedEntry: Identifiable {
    let id: String
    let text: String
    let date: String
    let source: String
}
