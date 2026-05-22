import SwiftUI

// MARK: - Main View

struct AskMyBrainView: View {

    /// Pre-populate the query field (e.g. from the home bar).
    var initialQuery: String = ""

    @StateObject private var api     = RevBoAPI()
    @StateObject private var whisper = WhispererService()

    @State private var queryText          = ""

    // ── General brain result ─────────────────────────────────────────────────
    @State private var synthesis: BrainSynthesis?
    @State private var sourceNotes: [BrainResult] = []
    @State private var showSourceNotes    = false
    @State private var sourceNotesLoaded  = false
    @State private var isLoadingNotes     = false

    // ── Contact-specific result (detected name in query) ─────────────────────
    @State private var contactSummary: ContactSummaryResponse?
    @State private var matchedContact: TrackedContact?

    @State private var isQuerying         = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    // Snapshot the query text used for the current result
    // so the source-notes fetch uses the same string
    @State private var lastQuery = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Search bar ───────────────────────────────────────────────
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.revboOrange)

                    TextField("e.g. What's the latest with John Smith?", text: $queryText)
                        .foregroundStyle(.white)
                        .tint(Color.revboOrange)
                        .focused($fieldFocused)
                        .submitLabel(.search)
                        .onSubmit { Task { await ask() } }

                    if !queryText.isEmpty {
                        Button { queryText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.gray)
                        }
                    }
                }
                .padding(14)
                .background(Color(white: 0.13))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // ── Whisper toggle ───────────────────────────────────────────
                HStack {
                    Spacer()
                    Toggle(isOn: $whisper.isEnabled) {
                        Label("Whisper results", systemImage: "airpodspro")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                    .toggleStyle(.switch)
                    .tint(Color.revboOrange)
                    .fixedSize()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // ── Ask button ───────────────────────────────────────────────
                Button { Task { await ask() } } label: {
                    HStack {
                        Spacer()
                        if isQuerying {
                            ProgressView().tint(.black)
                        } else {
                            Label("Ask My Brain", systemImage: "brain.head.profile")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.black)
                        }
                        Spacer()
                    }
                    .frame(height: 48)
                    .background(queryText.isEmpty ? Color.gray : Color.revboOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(queryText.isEmpty || isQuerying)
                .padding(.horizontal, 16)
                .padding(.top, 10)

                // ── Content area ─────────────────────────────────────────────
                if let contact = matchedContact, let summary = contactSummary {
                    // ── Contact-specific brief ───────────────────────────────
                    ScrollView {
                        VStack(spacing: 16) {
                            ContactResultBanner(contact: contact, recordCount: summary.record_count)
                            ContactInsightCard(synthesis: summary)
                            ContactNarrativeCard(synthesis: summary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if let synthesis {
                    // ── General brain brief ──────────────────────────────────
                    ScrollView {
                        VStack(spacing: 16) {
                            StatChipsRow(synthesis: synthesis)
                            CoachInsightCard(synthesis: synthesis)
                            NarrativeCard(
                                synthesis: synthesis,
                                whisper: whisper
                            )
                            SourceNotesToggle(
                                synthesis: synthesis,
                                queryText: lastQuery,
                                api: api,
                                sourceNotes: $sourceNotes,
                                showSourceNotes: $showSourceNotes,
                                sourceNotesLoaded: $sourceNotesLoaded,
                                isLoadingNotes: $isLoadingNotes
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if !isQuerying {
                    Spacer()
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.revboOrange.opacity(0.35))
                    Text("Ask a question to get a coaching brief.\nMention a contact by name for their\nrelationship summary.")
                        .font(.callout)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                    Spacer()
                }
            }
        }
        .navigationTitle("Ask My Brain")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .animation(.easeInOut(duration: 0.35), value: synthesis != nil)
        .animation(.easeInOut(duration: 0.35), value: contactSummary != nil)
        .onAppear {
            if !initialQuery.isEmpty {
                queryText    = initialQuery
                fieldFocused = false
                Task { await ask() }
            }
        }
    }

    // MARK: - Ask

    private func ask() async {
        guard !queryText.isEmpty else { return }
        fieldFocused = false
        isQuerying = true
        lastQuery = queryText

        // Clear previous results
        synthesis      = nil
        contactSummary = nil
        matchedContact = nil
        sourceNotes      = []
        sourceNotesLoaded = false
        showSourceNotes   = false

        defer { isQuerying = false }
        do {
            if let contact = detectContact(in: queryText) {
                // ── Route to per-contact brief ────────────────────────────
                let result = try await api.contactSummary(
                    ContactSummaryRequest(
                        contactHash: contact.hash,
                        displayName: contact.displayName,
                        enrichment:  contact.enrichment
                    )
                )
                withAnimation {
                    matchedContact = contact
                    contactSummary = result
                }
                if whisper.isEnabled { whisper.speak(result.coaching_response) }
            } else {
                // ── Route to general brain ask ────────────────────────────
                let result = try await api.askBrain(queryText)
                withAnimation { synthesis = result }
                if whisper.isEnabled { whisper.speak(result.coaching_response) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Contact detection

    /// Scans the query for any tracked contact's full name (case-insensitive).
    /// Sorts by name length descending so "John Smith Jr" beats "John Smith".
    private func detectContact(in text: String) -> TrackedContact? {
        let lower = text.lowercased()
        return ContactAttributionStore.shared.contacts
            .sorted { $0.displayName.count > $1.displayName.count }
            .first { contact in
                let name  = contact.displayName.lowercased()
                // Full-name substring match
                if lower.contains(name) { return true }
                // Both first and last name appear anywhere in the query
                let parts = name
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                guard parts.count >= 2 else { return false }
                return parts.allSatisfy { lower.contains($0) }
            }
    }
}

// MARK: - Stat chips row

private struct StatChipsRow: View {
    let synthesis: BrainSynthesis

    private var topIndustry: String {
        synthesis.industry_breakdown
            .filter { $0.key != "unknown" }
            .max(by: { $0.value < $1.value })?.key ?? "General"
    }

    private var confidenceColor: Color {
        switch synthesis.data_confidence {
        case "High":   return .green
        case "Medium": return .yellow
        default:       return .gray
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(
                    icon: "doc.text.magnifyingglass",
                    label: "\(synthesis.total_relevant_count) matches",
                    color: Color.revboOrange
                )
                Chip(
                    icon: "building.2",
                    label: topIndustry,
                    color: .white.opacity(0.7)
                )
                Chip(
                    icon: "chart.bar.fill",
                    label: synthesis.data_confidence + " confidence",
                    color: confidenceColor
                )
                Chip(
                    icon: "eye.slash",
                    label: "\(synthesis.sources_used) notes analysed",
                    color: .white.opacity(0.5)
                )
            }
        }
    }
}

private struct Chip: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Coach's Insight card

private struct CoachInsightCard: View {
    let synthesis: BrainSynthesis

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Card header
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(6)
                    .background(Color.revboOrange)
                    .clipShape(Circle())
                Text("COACH'S INSIGHT")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.revboOrange)
                    .tracking(1.2)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Authority statement
            Text(synthesis.experience_summary)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.revboOrange)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

            Divider().background(Color.revboOrange.opacity(0.25))

            // Patterns section
            if !synthesis.patterns.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Patterns Detected", systemImage: "waveform.path.ecg")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.gray)

                    ForEach(Array(synthesis.patterns.enumerated()), id: \.offset) { _, pattern in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Color.revboOrange)
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            Text(pattern)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
                .padding(16)

                Divider().background(Color.revboOrange.opacity(0.25))
            }

            // Tips section
            if !synthesis.tips.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Your Playbook", systemImage: "checklist")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.gray)

                    ForEach(synthesis.tips) { tip in
                        TipRow(tip: tip)
                    }
                }
                .padding(16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.revboOrange.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.revboOrange.opacity(0.30), lineWidth: 1)
                )
        )
    }
}

private struct TipRow: View {
    let tip: CoachingTip

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Number badge
            Text("\(tip.number)")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.black)
                .frame(width: 26, height: 26)
                .background(Color.revboOrange)
                .clipShape(Circle())
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(tip.tip)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(tip.rationale)
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
            }
        }
    }
}

// MARK: - Narrative card (TTS-ready coaching response)

private struct NarrativeCard: View {
    let synthesis: BrainSynthesis
    let whisper: WhispererService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "airpodspro")
                    .font(.subheadline)
                    .foregroundStyle(Color.revboOrange)
                Text("Coach's Narrative")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.gray)
                Spacer()
                // Replay TTS button
                Button {
                    whisper.speak(synthesis.coaching_response)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.revboOrange)
                }
            }

            Text(synthesis.coaching_response)
                .font(.system(size: 14))
                .italic()
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(4)
        }
        .padding(16)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Source Notes toggle (lazy-loaded fact-check section)

private struct SourceNotesToggle: View {
    let synthesis: BrainSynthesis
    let queryText: String
    let api: RevBoAPI

    @Binding var sourceNotes: [BrainResult]
    @Binding var showSourceNotes: Bool
    @Binding var sourceNotesLoaded: Bool
    @Binding var isLoadingNotes: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toggle header button
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showSourceNotes.toggle()
                }
                if showSourceNotes && !sourceNotesLoaded {
                    Task { await loadNotes() }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: showSourceNotes ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.gray)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Text("Source Notes (\(synthesis.sources_used) records)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.gray)
                    Spacer()
                    Text("fact-check")
                        .font(.caption2)
                        .foregroundStyle(Color.revboOrange.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(white: 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Expanded notes
            if showSourceNotes {
                VStack(spacing: 10) {
                    if isLoadingNotes {
                        HStack {
                            Spacer()
                            ProgressView().tint(Color.revboOrange)
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    } else if sourceNotes.isEmpty {
                        Text("No source notes available.")
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .padding()
                    } else {
                        ForEach(sourceNotes) { note in
                            SourceNoteCard(note: note)
                        }
                    }
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showSourceNotes)
    }

    private func loadNotes() async {
        guard !sourceNotesLoaded else { return }
        isLoadingNotes = true
        defer { isLoadingNotes = false }
        do {
            let response = try await api.queryBrain(queryText, n: synthesis.sources_used)
            sourceNotes = response.results
            sourceNotesLoaded = true
        } catch {
            // Silently fail — source notes are optional fact-checking
            sourceNotes = []
            sourceNotesLoaded = true
        }
    }
}

private struct SourceNoteCard: View {
    let note: BrainResult

    private var bucketLabel: String? { note.metadata["bucket"] }
    private var industryLabel: String? { note.metadata["industry"] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Redacted note text
            Text(note.text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
                .lineSpacing(3)

            HStack(spacing: 6) {
                if let bucket = bucketLabel {
                    TagPill(text: bucket, color: Color.revboOrange)
                }
                if let industry = industryLabel, industry != "unknown" {
                    TagPill(text: industry, color: .white.opacity(0.5))
                }
                Spacer()
                Text("\(Int(note.relevance_score * 100))% match")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
        }
        .padding(14)
        .background(Color(white: 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct TagPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Contact result banner (shown when Ask Bo detects a contact name)

private struct ContactResultBanner: View {
    let contact: TrackedContact
    let recordCount: Int

    private var initials: String {
        contact.displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map { String($0) } }
            .joined()
            .uppercased()
    }

    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.revboOrange.opacity(0.18))
                    .frame(width: 46, height: 46)
                Text(initials.isEmpty ? "?" : initials)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.revboOrange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption2)
                        .foregroundStyle(Color.revboOrange)
                    Text("Relationship brief · \(recordCount) records")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }

            Spacer()

            Image(systemName: "person.fill.checkmark")
                .font(.system(size: 18))
                .foregroundStyle(Color.revboOrange.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.revboOrange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.revboOrange.opacity(0.25), lineWidth: 1)
        )
    }
}
