import EventKit
import SwiftUI

// MARK: - Upcoming Meetings Strip
// Compact horizontal scroll shown at the bottom of HomeView.
// Tracked RevBo contacts show as orange chips → tap for relationship brief.
// Untracked attendees show as gray chips → tap to add to RevBo.

struct UpcomingMeetingsStrip: View {

    @StateObject private var cal   = CalendarSyncService.shared
    @ObservedObject private var store = ContactAttributionStore.shared

    // Sheet state
    @State private var selectedContact:   TrackedContact?
    @State private var addAttendeeName:   String?
    @State private var showAddContact     = false
    @State private var showCalendarPicker = false
    @State private var selectedMeeting:   UpcomingMeeting?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Section header ────────────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.revboOrange)
                Text("THIS WEEK")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.revboMuted)
                    .tracking(1.2)
                Spacer()

                // Calendar filter button — only show once we have access
                if cal.authStatus == .fullAccess || cal.authStatus == .authorized {
                    Button {
                        showCalendarPicker = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 13))
                            if !cal.selectedCalendarIDs.isEmpty {
                                Text("\(cal.selectedCalendarIDs.count)")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .foregroundStyle(cal.selectedCalendarIDs.isEmpty
                                         ? Color.revboMuted
                                         : Color.revboOrange)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            // ── Content ───────────────────────────────────────────────────────
            switch cal.authStatus {
            case .notDetermined:
                permissionPrompt

            case .denied, .restricted:
                deniedPrompt

            default:
                if cal.meetings.isEmpty {
                    emptyState
                } else {
                    meetingScroll
                }
            }
        }
        .task { await cal.requestAccessAndFetch() }
        // Contact detail sheet
        .sheet(item: $selectedContact) { contact in
            NavigationStack {
                ContactDetailView(contact: contact)
            }
            .presentationDetents([.large])
        }
        // Add contact prompt sheet
        .sheet(isPresented: $showAddContact) {
            NavigationStack {
                ContactsTabView(autoOpenPicker: true)
            }
            .presentationDetents([.large])
        }
        // Calendar picker sheet
        .sheet(isPresented: $showCalendarPicker) {
            CalendarPickerSheet(service: cal)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // Meeting prep sheet
        .sheet(item: $selectedMeeting) { meeting in
            NavigationStack {
                MeetingPrepView(meeting: meeting)
                    .navigationTitle("Meeting Brief")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarColorScheme(.dark, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { selectedMeeting = nil }
                                .foregroundStyle(Color.revboOrange)
                        }
                    }
            }
            .presentationDetents([.large])
        }
    }

    // MARK: - Meeting scroll

    private var meetingScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(cal.meetings) { meeting in
                    MeetingCard(
                        meeting: meeting,
                        onMeetingTap: { tapped in
                            selectedMeeting = tapped
                        },
                        onContactTap: { contact in
                            selectedContact = contact
                        },
                        onAddTap: { name in
                            addAttendeeName = name
                            showAddContact  = true
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Permission prompt

    private var permissionPrompt: some View {
        Button {
            Task { await cal.requestAccessAndFetch() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.revboOrange)
                Text("Connect calendar to see upcoming meetings")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.revboMuted)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Color.revboSubtle)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.revboSurface2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.revboOrange.opacity(0.25), lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
    }

    private var deniedPrompt: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.gray)
            Text("Enable calendar access in Settings to see upcoming meetings")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        Text("No meetings in the next 7 days")
            .font(.caption)
            .foregroundStyle(Color.revboSubtle)
            .padding(.horizontal, 20)
    }
}

// MARK: - Calendar Picker Sheet

private struct CalendarPickerSheet: View {

    @ObservedObject var service: CalendarSyncService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(service.availableCalendars) { item in
                        Button {
                            service.toggleCalendar(item.id)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 12, height: 12)
                                Text(item.title)
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                if service.isSelected(item.id) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.revboOrange)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Showing meetings from \(activeCount) of \(service.availableCalendars.count) calendars.")
                        .font(.caption)
                }
            }
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.revboOrange)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Show All") {
                        // Clear selection → all calendars shown
                        for item in service.availableCalendars {
                            if !service.selectedCalendarIDs.isEmpty {
                                service.selectedCalendarIDs.removeAll()
                            }
                        }
                        UserDefaults.standard.removeObject(forKey: "revbo.selectedCalendarIDs")
                        Task { await service.fetch() }
                    }
                    .foregroundStyle(Color.revboMuted)
                    .disabled(service.selectedCalendarIDs.isEmpty)
                }
            }
        }
    }

    private var activeCount: Int {
        service.selectedCalendarIDs.isEmpty
            ? service.availableCalendars.count
            : service.selectedCalendarIDs.count
    }
}

// MARK: - Meeting Card

private struct MeetingCard: View {

    let meeting:        UpcomingMeeting
    let onMeetingTap:   (UpcomingMeeting) -> Void
    let onContactTap:   (TrackedContact) -> Void
    let onAddTap:       (String) -> Void

    var body: some View {
        Button {
            onMeetingTap(meeting)
        } label: {
            VStack(alignment: .leading, spacing: 6) {

                // Time
                HStack(spacing: 4) {
                    Circle()
                        .fill(meeting.calColor)
                        .frame(width: 5, height: 5)
                    Text(timeLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.revboMuted)
                }

                // Title
                Text(meeting.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.revboText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                // Attendee chips
                if meeting.attendees.isEmpty {
                    Text("No attendees")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.revboSubtle)
                } else {
                    HStack(spacing: 4) {
                        ForEach(meeting.attendees.prefix(3)) { attendee in
                            AttendeeChip(
                                attendee: attendee,
                                onContactTap: onContactTap,
                                onAddTap: onAddTap
                            )
                        }
                        if meeting.attendees.count > 3 {
                            Text("+\(meeting.attendees.count - 3)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.revboSubtle)
                        }
                    }
                }
            }
            .padding(12)
            .frame(width: 158, height: 100, alignment: .topLeading)
            .background(Color.revboSurface2)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var timeLabel: String {
        let cal = Calendar.current
        let formatter = DateFormatter()

        if cal.isDateInToday(meeting.startDate) {
            formatter.dateFormat = "'Today' h:mm a"
        } else if cal.isDateInTomorrow(meeting.startDate) {
            formatter.dateFormat = "'Tomorrow' h:mm a"
        } else {
            formatter.dateFormat = "EEE h:mm a"
        }
        return formatter.string(from: meeting.startDate)
    }
}

// MARK: - Attendee Chip

private struct AttendeeChip: View {

    let attendee:     MeetingAttendee
    let onContactTap: (TrackedContact) -> Void
    let onAddTap:     (String) -> Void

    var body: some View {
        Button {
            if let contact = attendee.trackedContact {
                onContactTap(contact)
            } else {
                onAddTap(attendee.name)
            }
        } label: {
            HStack(spacing: 3) {
                if attendee.isTracked {
                    Circle()
                        .fill(Color.revboOrange)
                        .frame(width: 5, height: 5)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.gray)
                }
                Text(firstName(attendee.name))
                    .font(.system(size: 10, weight: attendee.isTracked ? .semibold : .regular))
                    .foregroundStyle(attendee.isTracked ? Color.revboOrange : Color.revboSubtle)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                attendee.isTracked
                    ? Color.revboOrange.opacity(0.12)
                    : Color.white.opacity(0.06)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func firstName(_ name: String) -> String {
        String(name.components(separatedBy: " ").first ?? name)
    }
}
