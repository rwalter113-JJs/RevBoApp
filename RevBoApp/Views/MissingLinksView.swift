import SwiftUI

// MARK: - Missing Links View
// Shows unattributed brain entries with smart filtering and AI summaries

struct MissingLinksView: View {

    @StateObject private var api = RevBoAPI()
    @ObservedObject private var store = ContactAttributionStore.shared

    @State private var entries: [MissingLinkEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedEntry: MissingLinkEntry?
    @State private var showContactPicker = false
    @State private var showAllEntries = false  // Toggle for ≥30% filter

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                if isLoading {
                    ProgressView()
                        .tint(Color.revboOrange)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredEntries.isEmpty {
                    emptyState
                } else {
                    entryList
                }
            }
        }
        .navigationTitle("Missing Links")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Toggle(isOn: $showAllEntries) {
                        Label("Show All Entries", systemImage: "line.3.horizontal.decrease.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.revboOrange)
                }
            }
        }
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

    // MARK: - Filtered Entries

    private var filteredEntries: [MissingLinkEntry] {
        if showAllEntries {
            return entries
        } else {
            // Only show entries with ≥30% attribution probability
            return entries.filter { $0.attributionProbability >= 0.30 }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.revboOrange)
            Text(showAllEntries ? "All entries attributed" : "No high-priority links")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text(showAllEntries
                 ? "Every brain entry is linked to a contact."
                 : "High-confidence entries are already linked. Tap ••• to show all.")
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
                ForEach(filteredEntries) { entry in
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
            // Fetch all unattributed entries (no client-side probability filter here)
            let response = try await api.queryBrain(
                "",
                filter: ["contact_hash": "unattributed"],
                n: 50
            )

            // Convert to MissingLinkEntry and sort by probability (high → low)
            let unsortedEntries = response.results.map { result in
                let probString = result.metadataString("attribution_probability")
                let prob = Double(probString) ?? 0.0

                return MissingLinkEntry(
                    id: result.metadataString("brain_id").isEmpty ? UUID().uuidString : result.metadataString("brain_id"),
                    text: result.text,
                    date: result.metadataString("stored_at"),
                    source: result.metadataString("source_type").isEmpty ? "unknown" : result.metadataString("source_type"),
                    attributionProbability: prob,
                    humanSummary: nil  // Will be fetched on-demand per card
                )
            }

            await MainActor.run {
                entries = unsortedEntries.sorted { $0.attributionProbability > $1.attributionProbability }
            }
        } catch {
            print("DEBUG MissingLinksView error: \(error)")
            await MainActor.run {
                errorMessage = "Failed to load entries: \(error.localizedDescription)"
            }
        }
    }

    private func attributeEntry(_ entry: MissingLinkEntry, to contact: TrackedContact) async {
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

    let entry: MissingLinkEntry
    let onAssign: () -> Void

    @State private var humanSummary: String = ""
    @State private var isLoadingSummary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(sourceLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.revboOrange)
                        confidenceBadge
                    }
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

            if isLoadingSummary {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.gray)
                    Text("Analyzing...")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else if !humanSummary.isEmpty {
                Text(humanSummary)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Fallback to redacted preview
                Text(entry.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color(white: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .task {
            if humanSummary.isEmpty {
                await fetchSummary()
            }
        }
    }

    private var sourceLabel: String {
        switch entry.source {
        case "voice": return "Voice Note"
        case "text": return "Text Note"
        case "email": return "Email"
        case "file": return "Document"
        case "deck": return "Deck"
        default: return "Entry"
        }
    }

    private var confidenceBadge: some View {
        let prob = entry.attributionProbability
        let color: Color
        let label: String

        if prob >= 0.70 {
            color = .green
            label = "High"
        } else if prob >= 0.50 {
            color = .orange
            label = "Med"
        } else if prob >= 0.30 {
            color = .yellow
            label = "Low"
        } else {
            color = .gray
            label = "Very Low"
        }

        return Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .clipShape(Capsule())
    }

    private var dateLabel: String {
        guard !entry.date.isEmpty else { return "Unknown date" }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: entry.date) {
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .short
            return rel.localizedString(for: date, relativeTo: Date())
        }
        return entry.date
    }

    private func fetchSummary() async {
        isLoadingSummary = true
        defer { isLoadingSummary = false }

        do {
            let api = RevBoAPI()
            let response = try await api.getMissingLinkSummary(brainId: entry.id)
            await MainActor.run {
                humanSummary = response.human_summary
            }
        } catch {
            print("DEBUG Failed to fetch summary for \(entry.id): \(error)")
            // On error, keep fallback text (entry.text preview)
        }
    }
}

// MARK: - Model

struct MissingLinkEntry: Identifiable {
    let id: String
    let text: String
    let date: String
    let source: String
    let attributionProbability: Double  // 0.0-1.0
    var humanSummary: String?  // AI-generated summary (fetched on-demand)
}
