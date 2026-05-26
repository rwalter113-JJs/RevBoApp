import SwiftUI

// MARK: - Meeting Prep View
//
// Full-screen coaching brief shown when the user taps a meeting card.
// Loads from /v1/meeting/prep and shows:
//   • Personal + professional snapshots for tracked contacts
//   • MEDDIC/BANT coverage grid with status indicators
//   • Suggested questions (lightbulb-prefixed)
//   • "Not in RevBo" section for any untracked attendees

struct MeetingPrepView: View {

    let meeting: UpcomingMeeting

    @StateObject private var api = RevBoAPI()

    @State private var prepData:      MeetingPrepResponse?
    @State private var isLoading      = true
    @State private var errorMessage:  String?
    @State private var showAddContact = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                loadingState
            } else if let error = errorMessage {
                errorState(error)
            } else if let prep = prepData {
                prepContent(prep)
            }
        }
        .task { await loadPrep() }
        // Sheet for adding an untracked attendee
        .sheet(isPresented: $showAddContact) {
            NavigationStack {
                ContactsTabView(autoOpenPicker: true)
            }
            .presentationDetents([.large])
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: 18) {
            ProgressView()
                .tint(Color.revboOrange)
                .scaleEffect(1.4)
            Text("Preparing your brief…")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.revboMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error state

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.revboOrange.opacity(0.6))
            Text("Couldn't load brief")
                .font(.headline)
                .foregroundStyle(Color.revboText)
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.revboMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task { await loadPrep() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.revboOrange)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.revboOrange.opacity(0.12))
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main prep content

    private func prepContent(_ prep: MeetingPrepResponse) -> some View {
        ScrollView {
            VStack(spacing: 16) {

                // ── Header ──────────────────────────────────────────────────
                PrepHeaderCard(meeting: meeting, title: prep.meeting_title)

                // ── Tracked contacts ─────────────────────────────────────────
                if prep.tracked_contacts.isEmpty {
                    noTrackedContactsCard
                } else {
                    ForEach(prep.tracked_contacts) { contact in
                        TrackedContactPrepCard(contact: contact)
                    }
                }

                // ── Untracked contacts ────────────────────────────────────────
                if !prep.untracked_names.isEmpty {
                    UntrackedContactsCard(
                        names: prep.untracked_names,
                        onAdd: { showAddContact = true }
                    )
                }

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    private var noTrackedContactsCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundStyle(Color.revboOrange.opacity(0.35))
            Text("No RevBo contacts in this meeting")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.revboText)
            Text("Add attendees to RevBo and log notes to unlock coaching briefs before your next call.")
                .font(.callout)
                .foregroundStyle(Color.revboMuted)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.revboSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - Data loading

    private func loadPrep() async {
        isLoading     = true
        errorMessage  = nil
        defer { isLoading = false }

        let attendees = meeting.attendees.map { attendee in
            MeetingPrepRequest.AttendeeInput(
                contact_hash: attendee.trackedContact?.hash,
                name:         attendee.name,
                is_tracked:   attendee.isTracked
            )
        }

        let req = MeetingPrepRequest(
            meeting_title: meeting.title,
            attendees:     attendees
        )

        do {
            prepData = try await api.meetingPrep(req)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Header Card

private struct PrepHeaderCard: View {

    let meeting: UpcomingMeeting
    let title:   String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            HStack(spacing: 6) {
                Circle()
                    .fill(meeting.calColor)
                    .frame(width: 8, height: 8)
                Text(timeLabel.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.revboMuted)
                    .tracking(1.2)
            }

            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.revboText)

            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundStyle(Color.revboOrange)
                Text("RevBo Meeting Brief")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.revboOrange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.revboSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.revboOrange.opacity(0.25), lineWidth: 1)
        )
    }

    private var timeLabel: String {
        let cal = Calendar.current
        let fmt = DateFormatter()
        if cal.isDateInToday(meeting.startDate) {
            fmt.dateFormat = "'Today' h:mm a"
        } else if cal.isDateInTomorrow(meeting.startDate) {
            fmt.dateFormat = "'Tomorrow' h:mm a"
        } else {
            fmt.dateFormat = "EEEE h:mm a"
        }
        return fmt.string(from: meeting.startDate)
    }
}

// MARK: - Tracked Contact Prep Card

private struct TrackedContactPrepCard: View {

    let contact: TrackedContactPrep
    @State private var expanded = true

    private var initials: String {
        let parts = contact.name.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first.map { String($0) } }.joined().uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Contact header row ───────────────────────────────────────────
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(Color.revboOrange.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Text(initials.isEmpty ? "?" : initials)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(Color.revboOrange)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(contact.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.revboText)
                        if !contact.has_brain_data {
                            Label("No notes yet", systemImage: "tray")
                                .font(.caption)
                                .foregroundStyle(Color.revboSubtle)
                        }
                    }

                    Spacer()

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.revboSubtle)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().background(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 16) {

                    // ── Personal snapshot ────────────────────────────────────
                    if !contact.personal_snapshot.isEmpty {
                        SnapshotRow(
                            icon: "person.fill.checkmark",
                            iconColor: Color(hex: "#4B9CD3"),
                            label: "PERSONAL",
                            text: contact.personal_snapshot
                        )
                    }

                    // ── Professional snapshot ────────────────────────────────
                    if !contact.professional_snapshot.isEmpty {
                        SnapshotRow(
                            icon: "bolt.fill",
                            iconColor: Color.revboOrange,
                            label: "PROFESSIONAL",
                            text: contact.professional_snapshot
                        )
                    }

                    // ── No-data empty state ──────────────────────────────────
                    if !contact.has_brain_data {
                        HStack(spacing: 10) {
                            Image(systemName: "tray")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.revboSubtle)
                            Text("No brain data yet — add a note after this call")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.revboSubtle)
                                .italic()
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    // ── MEDDIC/BANT grid ─────────────────────────────────────
                    MeddicBantGrid(meddic: contact.meddic)

                    // ── Suggested questions ──────────────────────────────────
                    if !contact.suggested_questions.isEmpty {
                        SuggestedQuestionsSection(questions: contact.suggested_questions)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .padding(.top, 12)
            }
        }
        .background(Color.revboSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

// MARK: - Snapshot Row

private struct SnapshotRow: View {
    let icon:       String
    let iconColor:  Color
    let label:      String
    let text:       String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(5)
                    .background(iconColor)
                    .clipShape(Circle())
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(iconColor)
                    .tracking(1.1)
            }
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color.revboText.opacity(0.88))
                .lineSpacing(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(iconColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(iconColor.opacity(0.22), lineWidth: 1)
        )
    }
}

// MARK: - MEDDIC/BANT Grid

private struct MeddicBantGrid: View {

    let meddic: MeddicBant

    private var items: [(label: String, item: MeddicItem)] {
        [
            ("Metrics",        meddic.metrics),
            ("Econ. Buyer",    meddic.economic_buyer),
            ("Decision Crit.", meddic.decision_criteria),
            ("Decision Proc.", meddic.decision_process),
            ("Identify Pain",  meddic.identify_pain),
            ("Champion",       meddic.champion),
            ("Budget",         meddic.budget),
            ("Timeline",       meddic.timeline),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.revboMuted)
                Text("MEDDIC / BANT")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.revboMuted)
                    .tracking(1.1)
            }

            // 2-column grid
            let rows = stride(from: 0, to: items.count, by: 2).map {
                Array(items[$0 ..< min($0 + 2, items.count)])
            }
            VStack(spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, pair in
                            MeddicCell(label: pair.label, item: pair.item)
                        }
                        // Pad last row if only one item
                        if row.count == 1 { Spacer().frame(maxWidth: .infinity) }
                    }
                }
            }
        }
    }
}

private struct MeddicCell: View {

    let label: String
    let item:  MeddicItem

    private var statusColor: Color {
        switch item.status {
        case "found":   return .green
        case "partial": return .yellow
        default:        return .red.opacity(0.8)
        }
    }

    private var statusIcon: String {
        switch item.status {
        case "found":   return "checkmark.circle.fill"
        case "partial": return "exclamationmark.circle.fill"
        default:        return "xmark.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: statusIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.revboText)
            }
            if let notes = item.notes, !notes.isEmpty, item.status != "missing" {
                Text(notes)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.revboMuted)
                    .lineLimit(2)
            } else if item.status == "missing" {
                Text("Not captured")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.revboSubtle)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(statusColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(statusColor.opacity(0.20), lineWidth: 1)
        )
    }
}

// MARK: - Suggested Questions

private struct SuggestedQuestionsSection: View {

    let questions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.yellow)
                Text("QUESTIONS TO ASK")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.revboMuted)
                    .tracking(1.1)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(questions.enumerated()), id: \.offset) { _, q in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.yellow.opacity(0.7))
                            .padding(.top, 2)
                        Text(q)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.revboText.opacity(0.9))
                            .lineSpacing(2)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.yellow.opacity(0.15), lineWidth: 1)
            )
        }
    }
}

// MARK: - Untracked Contacts Card

private struct UntrackedContactsCard: View {

    let names: [String]
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.revboMuted)
                Text("NOT IN REVBO")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.revboMuted)
                    .tracking(1.2)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().background(Color.white.opacity(0.07))

            VStack(spacing: 0) {
                ForEach(Array(names.enumerated()), id: \.offset) { idx, name in
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.gray.opacity(0.5))
                        Text(name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.revboText)
                        Spacer()
                        Button {
                            onAdd()
                        } label: {
                            Text("Add")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.revboOrange)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if idx < names.count - 1 {
                        Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                    }
                }
            }
        }
        .background(Color.revboSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}
