import Combine
import EventKit
import Foundation
import SwiftUI

// MARK: - Models

struct UpcomingMeeting: Identifiable {
    let id:         String
    let title:      String
    let startDate:  Date
    let isAllDay:   Bool
    let attendees:  [MeetingAttendee]
    let calColor:   Color       // calendar dot colour
}

struct MeetingAttendee: Identifiable {
    let id:             String  // email or participant URL
    let name:           String
    let email:          String?
    let trackedContact: TrackedContact?   // nil = not yet in RevBo
    var isTracked: Bool { trackedContact != nil }
}

// MARK: - CalendarItem (lightweight model for picker)

struct CalendarItem: Identifiable {
    let id:    String       // EKCalendar.calendarIdentifier
    let title: String
    let color: Color
}

// MARK: - Service

@MainActor
final class CalendarSyncService: ObservableObject {

    static let shared = CalendarSyncService()
    private init() {
        // Restore persisted selection (empty set = all selected)
        if let saved = UserDefaults.standard.array(forKey: Self.selectedKey) as? [String] {
            _selectedCalendarIDs = Published(initialValue: Set(saved))
        }
    }

    private static let selectedKey = "revbo.selectedCalendarIDs"

    @Published var meetings:             [UpcomingMeeting] = []
    @Published var authStatus:           EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var availableCalendars:   [CalendarItem]    = []
    @Published var selectedCalendarIDs:  Set<String>       = []   // empty = show all

    private let ekStore = EKEventStore()

    // MARK: - Selection helpers

    /// Toggle a calendar on/off and re-fetch.
    func toggleCalendar(_ id: String) {
        if selectedCalendarIDs.contains(id) {
            selectedCalendarIDs.remove(id)
        } else {
            selectedCalendarIDs.insert(id)
        }
        persist()
        Task { await fetch() }
    }

    func isSelected(_ id: String) -> Bool {
        // Empty selection means "all" — treat everything as selected
        selectedCalendarIDs.isEmpty || selectedCalendarIDs.contains(id)
    }

    private func persist() {
        UserDefaults.standard.set(Array(selectedCalendarIDs), forKey: Self.selectedKey)
    }

    // MARK: - Permission + fetch

    func requestAccessAndFetch() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .authorized:
            authStatus = status
            await fetch()
        case .notDetermined:
            do {
                let granted: Bool
                if #available(iOS 17, *) {
                    granted = try await ekStore.requestFullAccessToEvents()
                } else {
                    granted = try await ekStore.requestAccess(to: .event)
                }
                authStatus = EKEventStore.authorizationStatus(for: .event)
                if granted { await fetch() }
            } catch {
                authStatus = .denied
            }
        default:
            authStatus = status
        }
    }

    func fetch() async {
        let contactStore = ContactAttributionStore.shared
        let hashSvc      = ContactHashService.shared

        // Refresh available calendars list
        let ekCals = ekStore.calendars(for: .event)
        availableCalendars = ekCals.map { cal in
            let uiCol = cal.cgColor.map { UIColor(cgColor: $0) } ?? UIColor.systemOrange
            return CalendarItem(id: cal.calendarIdentifier, title: cal.title, color: Color(uiColor: uiCol))
        }

        // Determine which EKCalendars to query
        let filteredCals: [EKCalendar]? = selectedCalendarIDs.isEmpty
            ? nil   // nil = all calendars
            : ekCals.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }

        let now      = Date()
        let horizon  = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now

        let predicate = ekStore.predicateForEvents(withStart: now, end: horizon, calendars: filteredCals)
        let raw = ekStore.events(matching: predicate)
            .filter { !$0.isAllDay }        // skip all-day blocks
            .sorted { $0.startDate < $1.startDate }
            .prefix(10)

        meetings = raw.compactMap { event -> UpcomingMeeting? in
            guard let title = event.title, !title.isEmpty else { return nil }

            // Extract attendees with emails, match to RevBo registry
            let attendees: [MeetingAttendee] = (event.attendees ?? [])
                .compactMap { participant -> MeetingAttendee? in
                    let urlStr = participant.url.absoluteString
                    let email: String? = urlStr.hasPrefix("mailto:")
                        ? String(urlStr.dropFirst("mailto:".count)).lowercased()
                        : nil
                    guard let email else { return nil }

                    let hash    = hashSvc.hash(email: email)
                    let tracked = contactStore.contact(forHash: hash)
                    return MeetingAttendee(
                        id:             email,
                        name:           participant.name ?? email,
                        email:          email,
                        trackedContact: tracked
                    )
                }
                .prefix(4)
                .map { $0 }

            // Calendar colour → SwiftUI Color
            let cgCol    = event.calendar?.cgColor
            let uiCol    = cgCol.map { UIColor(cgColor: $0) } ?? UIColor.systemOrange
            let swiftCol = Color(uiColor: uiCol)

            return UpcomingMeeting(
                id:        event.eventIdentifier ?? UUID().uuidString,
                title:     title,
                startDate: event.startDate,
                isAllDay:  event.isAllDay,
                attendees: attendees,
                calColor:  swiftCol
            )
        }
    }
}
