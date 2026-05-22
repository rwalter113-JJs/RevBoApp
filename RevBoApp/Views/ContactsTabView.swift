import SwiftUI
import Contacts
import ContactsUI

// MARK: - My Contacts Tab

/// Entry point for the Contact Attribution feature.
/// Lists all tracked contacts and provides:
///   • "Add contact" via CNContacts picker
///   • Per-contact coaching summary (tap → ContactDetailView)
///   • Record count badges (pulled from server stats on appear)
struct ContactsTabView: View {

    /// When true the CNContact picker opens automatically on appear —
    /// used when the user says "add [name]" in the Ask Bo bar.
    var autoOpenPicker: Bool = false

    @StateObject private var store = ContactAttributionStore.shared
    @StateObject private var api   = RevBoAPI()

    @State private var showPicker     = false
    @State private var isRefreshing   = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Subtitle bar ─────────────────────────────────────────────
                HStack {
                    Text("Relationship intelligence, anonymised")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 10)

                Divider().background(Color.white.opacity(0.08))

                if store.contacts.isEmpty {
                    // ── Empty state ──────────────────────────────────────────
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.circle")
                            .font(.system(size: 52))
                            .foregroundStyle(Color.revboOrange.opacity(0.35))
                        Text("No contacts tracked yet")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Tap + to add a contact from your address book.\nRevBo will link your anonymised notes to them.")
                            .font(.callout)
                            .foregroundStyle(.gray)
                            .multilineTextAlignment(.center)
                        Button {
                            showPicker = true
                        } label: {
                            Label("Add Contact", systemImage: "person.badge.plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.revboOrange)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 32)
                    Spacer()
                } else {
                    // ── Contact list ─────────────────────────────────────────
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.contacts) { contact in
                                NavigationLink {
                                    ContactDetailView(contact: contact)
                                } label: {
                                    ContactRowCard(contact: contact)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .refreshable {
                        await refreshAllStats()
                    }
                }
            }
        }
        .navigationTitle("My Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showPicker = true } label: {
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(Color.revboOrange)
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            ContactPickerSheet { cnContact in
                addContact(cnContact)
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .task {
            await refreshAllStats()
            if autoOpenPicker { showPicker = true }
        }
    }

    // MARK: - Actions

    private func addContact(_ cnContact: CNContact) {
        guard let hash = store.track(cnContact) else {
            errorMessage = "This contact has no email or phone number — can't create a hash."
            return
        }
        Task {
            // Stats + enrichment run in parallel
            async let statsTask = api.contactStats(hash: hash)
            async let enrichTask = api.enrichContact(
                name:    CNContactFormatter.string(from: cnContact, style: .fullName) ?? "",
                email:   cnContact.emailAddresses.first?.value as String?,
                company: cnContact.organizationName.isEmpty ? nil : cnContact.organizationName
            )

            if let stats = try? await statsTask {
                let lastDate = stats.last_seen.flatMap { parseISO($0) }
                store.updateStats(hash: hash, recordCount: stats.record_count, lastSeen: lastDate)
            }
            if let enrichment = try? await enrichTask {
                store.updateEnrichment(hash: hash, enrichment: enrichment)
            }
        }
    }

    private func refreshAllStats() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await withTaskGroup(of: Void.self) { group in
            for contact in store.contacts {
                group.addTask {
                    // ── Stats refresh ────────────────────────────────────────
                    if let stats = try? await api.contactStats(hash: contact.hash) {
                        let lastDate = stats.last_seen.flatMap { parseISO($0) }
                        await MainActor.run {
                            store.updateStats(
                                hash: contact.hash,
                                recordCount: stats.record_count,
                                lastSeen: lastDate
                            )
                        }
                    }

                    // ── Apollo re-enrichment (stale after 7 days) ────────────
                    let enrichmentAge = contact.enrichment.map {
                        Date().timeIntervalSince($0.enrichedAt)
                    } ?? .infinity
                    let sevenDays: TimeInterval = 7 * 86_400
                    if enrichmentAge > sevenDays {
                        if let enrichment = try? await api.enrichContact(
                            name:    contact.displayName,
                            email:   contact.email,
                            company: contact.company
                        ) {
                            await MainActor.run {
                                store.updateEnrichment(hash: contact.hash, enrichment: enrichment)
                            }
                        }
                    }
                }
            }
        }
    }

}

// File-level helper — nonisolated so it can be called from task groups / async contexts.
private func parseISO(_ s: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: s) ?? ISO8601DateFormatter().date(from: s)
}

// MARK: - Contact Row Card

private struct ContactRowCard: View {
    let contact: TrackedContact

    private var initials: String {
        let parts = contact.displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first.map { String($0) } }
        return letters.joined().uppercased()
    }

    private var confidenceColor: Color {
        switch contact.recordCount {
        case 5...: return .green
        case 2...4: return .yellow
        default:    return .gray
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(Color.revboOrange.opacity(0.15))
                    .frame(width: 46, height: 46)
                Text(initials.isEmpty ? "?" : initials)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.revboOrange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                // Show enriched title + company if available, else signal label
                if let title = contact.enrichment?.title, !title.isEmpty {
                    let company = contact.enrichment?.employment
                        .first(where: { $0.current })?.company
                        ?? contact.enrichment?.employment.first?.company
                    if let company, !company.isEmpty {
                        Text("\(title) · \(company)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    } else {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: signalIcon)
                            .font(.caption2)
                            .foregroundStyle(.gray)
                        Text(signalLabel)
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
            }

            Spacer()

            // Record count badge
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(contact.recordCount)")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(confidenceColor)
                Text("records")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.gray.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(white: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var signalIcon: String {
        switch contact.signalType {
        case "email":  return "envelope"
        case "phone":  return "phone"
        default:       return "hand.tap"
        }
    }

    private var signalLabel: String {
        switch contact.signalType {
        case "email":  return "tracked via email"
        case "phone":  return "tracked via phone"
        default:       return "manually added"
        }
    }
}

// MARK: - CNContacts Picker wrapper

/// Wraps CNContactPickerViewController in a SwiftUI sheet.
struct ContactPickerSheet: UIViewControllerRepresentable {
    let onSelect: (CNContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(
            format: "emailAddresses.@count > 0 OR phoneNumbers.@count > 0"
        )
        return picker
    }

    func updateUIViewController(_ vc: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (CNContact) -> Void
        init(onSelect: @escaping (CNContact) -> Void) { self.onSelect = onSelect }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelect(contact)
        }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {}
    }
}


// MARK: - Contact Detail View

/// Per-contact view showing stats, relationship synthesis, and deletion.
struct ContactDetailView: View {

    let contact: TrackedContact

    @StateObject private var store = ContactAttributionStore.shared
    @StateObject private var api   = RevBoAPI()

    @State private var synthesis:        ContactSummaryResponse?
    @State private var isLoading         = false
    @State private var isEnriching       = false
    @State private var showDeleteConfirm = false
    @State private var deleteInProgress  = false
    @State private var showNewNote       = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var currentContact: TrackedContact {
        store.contact(forHash: contact.hash) ?? contact
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {

                    // ── Contact hero ─────────────────────────────────────────
                    ContactHeroCard(contact: currentContact)

                    // ── Log a note for this contact ──────────────────────────
                    Button {
                        showNewNote = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Log a Note", systemImage: "square.and.pencil")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.revboOrange)
                            Spacer()
                        }
                        .frame(height: 44)
                        .background(Color.revboOrange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.revboOrange.opacity(0.35), lineWidth: 1)
                        )
                    }

                    // ── Ask My Brain about this contact ──────────────────────
                    Button {
                        Task { await loadSynthesis() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView().tint(.black)
                            } else {
                                Label(
                                    synthesis == nil ? "Ask My Brain About This Person" : "Refresh Briefing",
                                    systemImage: "brain.head.profile"
                                )
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.black)
                            }
                            Spacer()
                        }
                        .frame(height: 48)
                        .background(isLoading ? Color.gray : Color.revboOrange)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(isLoading || currentContact.recordCount == 0)

                    // ── Refresh LinkedIn profile ─────────────────────────────
                    Button {
                        Task { await reEnrichContact() }
                    } label: {
                        HStack {
                            Spacer()
                            if isEnriching {
                                ProgressView().tint(Color(hex: "#4B9CD3"))
                            } else {
                                Label(
                                    currentContact.enrichment == nil
                                        ? "Fetch LinkedIn Profile"
                                        : "Refresh LinkedIn Profile",
                                    systemImage: "person.crop.square.filled.and.at.rectangle"
                                )
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: "#4B9CD3"))
                            }
                            Spacer()
                        }
                        .frame(height: 44)
                        .background(Color(hex: "#4B9CD3").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(hex: "#4B9CD3").opacity(0.35), lineWidth: 1)
                        )
                    }
                    .disabled(isEnriching)

                    // ── LinkedIn enrichment card ─────────────────────────────
                    if let enrichment = currentContact.enrichment {
                        EnrichmentCard(enrichment: enrichment)
                    }

                    // ── Synthesis cards ──────────────────────────────────────
                    if let synthesis {
                        ContactInsightCard(synthesis: synthesis)
                        ContactNarrativeCard(synthesis: synthesis)
                    } else if currentContact.recordCount == 0 {
                        NoRecordsCard()
                    }

                    Spacer(minLength: 32)

                    // ── Delete button ────────────────────────────────────────
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Remove & Delete All Records")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .navigationTitle(currentContact.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .confirmationDialog(
            "Delete all records for \(currentContact.displayName)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete \(currentContact.recordCount) Records", role: .destructive) {
                Task { await deleteContact() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all anonymised notes attributed to this contact from the server. It cannot be undone.")
        }
        .sheet(isPresented: $showNewNote) {
            NavigationStack {
                NewNoteView(preAttributedContact: contact)
            }
            .presentationDetents([.large])
        }
        .onChange(of: showNewNote) { _, isShowing in
            // When sheet fully closes, refresh stats so record count badge updates
            if !isShowing {
                Task { await refreshStats() }
            }
        }
        .task {
            // Always refresh stats on appear so count is never stale
            await refreshStats()
            if currentContact.recordCount > 0 {
                await loadSynthesis()
            }
        }
    }

    private func refreshStats() async {
        if let stats = try? await api.contactStats(hash: contact.hash) {
            let lastDate = stats.last_seen.flatMap { s -> Date? in
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
            }
            await MainActor.run {
                store.updateStats(hash: contact.hash, recordCount: stats.record_count, lastSeen: lastDate)
            }
        }
    }

    // MARK: - Actions

    private func loadSynthesis() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            synthesis = try await api.contactSummary(
                ContactSummaryRequest(
                    contactHash: contact.hash,
                    displayName: currentContact.displayName,
                    enrichment:  currentContact.enrichment
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteContact() async {
        deleteInProgress = true
        defer { deleteInProgress = false }
        do {
            _ = try await api.deleteContactRecords(hash: contact.hash)
            store.remove(hash: contact.hash)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Re-fetch Apollo + Proxycurl enrichment on demand (also called automatically
    /// from ContactsTabView.refreshAllStats() when enrichment is > 7 days old).
    private func reEnrichContact() async {
        guard !isEnriching else { return }
        isEnriching = true
        defer { isEnriching = false }
        if let enrichment = try? await api.enrichContact(
            name:    currentContact.displayName,
            email:   currentContact.email,
            company: currentContact.company
        ) {
            store.updateEnrichment(hash: contact.hash, enrichment: enrichment)
        }
    }
}

// MARK: - Sub-views

private struct ContactHeroCard: View {
    let contact: TrackedContact

    private var initials: String {
        let parts = contact.displayName.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first.map { String($0) } }.joined().uppercased()
    }

    private var confidenceLabel: String {
        switch contact.recordCount {
        case 5...: return "High"
        case 2...4: return "Medium"
        default:    return "Low"
        }
    }

    private var confidenceColor: Color {
        switch contact.recordCount {
        case 5...: return .green
        case 2...4: return .yellow
        default:    return .gray
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.revboOrange.opacity(0.15))
                    .frame(width: 64, height: 64)
                Text(initials.isEmpty ? "?" : initials)
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(Color.revboOrange)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(contact.displayName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                // Enriched title + company (preferred over address book if available)
                if let title = contact.enrichment?.title, !title.isEmpty {
                    let currentCompany = contact.enrichment?.employment
                        .first(where: { $0.current })?.company
                        ?? contact.enrichment?.employment.first?.company
                        ?? contact.company
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        if let company = currentCompany, !company.isEmpty {
                            Label(company, systemImage: "building.2")
                                .font(.caption)
                                .foregroundStyle(Color.revboOrange.opacity(0.8))
                        }
                    }
                } else {
                    // Fall back to address book details
                    VStack(alignment: .leading, spacing: 3) {
                        if let company = contact.company {
                            Label(company, systemImage: "building.2")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                        if let email = contact.email {
                            Label(email, systemImage: "envelope")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                        if let phone = contact.phone {
                            Label(phone, systemImage: "phone")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                    }
                }

                // Stats pills
                HStack(spacing: 8) {
                    StatPill(
                        icon: "doc.text",
                        label: "\(contact.recordCount) records",
                        color: Color.revboOrange
                    )
                    StatPill(
                        icon: "chart.bar",
                        label: confidenceLabel + " confidence",
                        color: confidenceColor
                    )
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color(white: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.revboOrange.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct StatPill: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct ContactInsightCard: View {
    let synthesis: ContactSummaryResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Part 1: Personal ─────────────────────────────────────────────
            PersonalContextCard(synthesis: synthesis)

            // ── Part 2: Professional ─────────────────────────────────────────
            ProfessionalBriefCard(synthesis: synthesis)
        }
    }
}

// MARK: - Personal Context Card

private struct PersonalContextCard: View {
    let synthesis: ContactSummaryResponse

    private var hasPersonal: Bool {
        !synthesis.personal_highlights.isEmpty ||
        synthesis.personal_summary != "No personal context captured yet."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "person.fill.checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(6)
                    .background(Color(hex: "#4B9CD3"))
                    .clipShape(Circle())
                Text("PERSONAL")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(hex: "#4B9CD3"))
                    .tracking(1.2)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().background(Color(hex: "#4B9CD3").opacity(0.2))

            if hasPersonal {
                VStack(alignment: .leading, spacing: 10) {
                    // Bullet highlights
                    if !synthesis.personal_highlights.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(synthesis.personal_highlights, id: \.self) { fact in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(Color(hex: "#4B9CD3"))
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 6)
                                    Text(fact)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.88))
                                }
                            }
                        }
                    }
                    // Rapport summary
                    if !synthesis.personal_summary.isEmpty {
                        Text(synthesis.personal_summary)
                            .font(.system(size: 13))
                            .italic()
                            .foregroundStyle(.gray)
                    }
                }
                .padding(14)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Text("No personal context logged yet — note a sports team, family detail or personal interest next time.")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                .padding(14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "#4B9CD3").opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(hex: "#4B9CD3").opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Professional Brief Card

private struct ProfessionalBriefCard: View {
    let synthesis: ContactSummaryResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(6)
                    .background(Color.revboOrange)
                    .clipShape(Circle())
                Text("PROFESSIONAL")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.revboOrange)
                    .tracking(1.2)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().background(Color.revboOrange.opacity(0.25))

            // Professional summary
            if !synthesis.professional_summary.isEmpty {
                Text(synthesis.professional_summary)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider().background(Color.revboOrange.opacity(0.15))
            }

            // Patterns
            if !synthesis.patterns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Relationship Patterns", systemImage: "waveform.path.ecg")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.gray)
                    ForEach(Array(synthesis.patterns.enumerated()), id: \.offset) { _, p in
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(Color.revboOrange).frame(width: 5, height: 5).padding(.top, 6)
                            Text(p).font(.system(size: 14)).foregroundStyle(.white.opacity(0.88))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().background(Color.revboOrange.opacity(0.15))
            }

            // Tips
            if !synthesis.tips.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Your Next Moves", systemImage: "checklist")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.gray)
                    ForEach(synthesis.tips) { tip in
                        ContactTipRow(tip: tip)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.revboOrange.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.revboOrange.opacity(0.30), lineWidth: 1)
                )
        )
    }
}

private struct ContactTipRow: View {
    let tip: CoachingTip

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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

struct ContactNarrativeCard: View {
    let synthesis: ContactSummaryResponse

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

// MARK: - Enrichment card

private struct EnrichmentCard: View {
    let enrichment: ContactEnrichment
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            HStack(spacing: 10) {
                Image(systemName: "person.crop.square.filled.and.at.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "#4B9CD3"))
                Text("LinkedIn Profile")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button { withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() } } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.gray)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().background(Color.white.opacity(0.07))

            // ── Always-visible: title + location ──────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                if let title = enrichment.title {
                    Label(title, systemImage: "briefcase.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                }
                if let location = enrichment.location {
                    Label(location, systemImage: "mappin.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.gray)
                }
                if let headline = enrichment.headline {
                    Text(headline)
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                        .lineLimit(expanded ? nil : 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // ── Expanded: career + skills ─────────────────────────────────
            if expanded {
                Divider().background(Color.white.opacity(0.07))

                VStack(alignment: .leading, spacing: 14) {

                    // Career history
                    if !enrichment.employment.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Experience")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(hex: "#4B9CD3"))
                            ForEach(enrichment.employment.prefix(4), id: \.title) { job in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(job.current ? Color.revboOrange : Color.gray.opacity(0.4))
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(job.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Text(job.company)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.gray)
                                        if !job.startDate.isEmpty {
                                            Text(job.current ? "\(job.startDate) – Present" : "\(job.startDate) – \(job.endDate)")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Color.gray.opacity(0.6))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Education
                    if !enrichment.education.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Education")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(hex: "#4B9CD3"))
                            ForEach(enrichment.education.prefix(2), id: \.school) { edu in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(edu.school)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                    if !edu.degree.isEmpty {
                                        Text([edu.degree, edu.field].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.system(size: 12))
                                            .foregroundStyle(.gray)
                                    }
                                }
                            }
                        }
                    }

                    // Skills
                    if !enrichment.skills.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Skills")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(hex: "#4B9CD3"))
                            FlowLayout(items: Array(enrichment.skills.prefix(10))) { skill in
                                Text(skill)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.07))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    // LinkedIn link
                    if let url = enrichment.linkedinUrl, let link = URL(string: url) {
                        Link(destination: link) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.right.square")
                                Text("View on LinkedIn")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "#4B9CD3"))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .background(Color(white: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: "#4B9CD3").opacity(0.20), lineWidth: 1)
        )
    }
}

// Simple wrapping pill row — splits items into rows of 3
private struct FlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: 3).map {
            Array(items[$0 ..< min($0 + 3, items.count)])
        }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { content($0) }
                }
            }
        }
    }
}

private struct NoRecordsCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(Color.revboOrange.opacity(0.35))
            Text("No records attributed yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("The next time you process a note, email, or call that involves this contact, RevBo will link it automatically if their email is detected.")
                .font(.callout)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(Color(white: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
