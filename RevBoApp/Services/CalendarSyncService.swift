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

// MARK: - Service

@MainActor
final class CalendarSyncService: ObservableObject {

    static let shared = CalendarSyncService()
    private init() {}

    @Published var meetings:    [UpcomingMeeting] = []
    @Published var authStatus:  EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    private let ekStore = EKEventStore()

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

        let now      = Date()
        let horizon  = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now

        let predicate = ekStore.predicateForEvents(withStart: now, end: horizon, calendars: nil)
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
            let cal = event.calendar
            let cgCol = cal.cgColor
            let uiCol = cgCol.map { UIColor(cgColor: $0) } ?? UIColor.systemOrange
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
