import Combine
import Foundation
import UserNotifications

// MARK: - OnboardingService

@MainActor
final class OnboardingService: ObservableObject {

    // MARK: - Singleton

    static let shared = OnboardingService()
    private init() { seedFirstLaunchDate() }

    // MARK: - UserDefaults keys

    private enum Keys {
        static let firstLaunchDate  = "revbo.onboarding.firstLaunchDate"
        static let hasSeenOnboarding = "revbo.onboarding.hasSeenOnboarding"
    }

    // MARK: - Published state

    @Published private(set) var hasSeenOnboarding: Bool = UserDefaults.standard.bool(forKey: Keys.hasSeenOnboarding)

    // MARK: - Computed properties

    var firstLaunchDate: Date {
        UserDefaults.standard.object(forKey: Keys.firstLaunchDate) as? Date ?? Date()
    }

    /// 1-indexed day count since first launch, capped at 10.
    var currentNudgeDay: Int {
        let elapsed = Calendar.current.dateComponents([.day], from: firstLaunchDate, to: Date()).day ?? 0
        return min(max(elapsed + 1, 1), 10)
    }

    /// True while days 1–10 after the user has dismissed the welcome card.
    var isNudgePeriodActive: Bool {
        hasSeenOnboarding && currentNudgeDay <= 10
    }

    // MARK: - Actions

    /// Called when the user taps "Got it, don't show again".
    func dismissOnboarding() {
        hasSeenOnboarding = true
        UserDefaults.standard.set(true, forKey: Keys.hasSeenOnboarding)
        Task {
            await requestNotificationPermissionAndSchedule()
        }
    }

    // MARK: - Notifications

    func scheduleNudgeNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: (1...10).map { "revbo.nudge.day\($0)" })

        let staticMessages: [Int: String] = [
            1:  "Add your first contacts — start with the 5 people you're most actively working with",
            2:  "Log your first voice note — after your next call, hit the mic and give RevBo a 30-second debrief",
            3:  "Add personal details to a contact — family, interests, hobbies. The things you'd never put in a CRM",
            4:  "Connect your calendar — RevBo will prep you before every meeting automatically",
            5:  "Capture something — upload a deck, a proposal, or a call recording and RevBo will read it and remember it against the right contact",
            6:  "Try Ask Bo — type 'What do I know about [name]?' and see what comes back",
            7:  "Fetch a LinkedIn profile — tap any contact and hit Refresh Profile for instant enrichment",
            8:  "Tap a meeting in This Week — RevBo will show you a prep brief before the call",
            9:  "You have contacts without notes — pick one and add a voice note today",
            10: "Some of your contacts are missing personal details — add a few more while they're fresh",
        ]

        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        for day in 1...10 {
            guard let message = staticMessages[day] else { continue }

            let content = UNMutableNotificationContent()
            content.title = "RevBo"
            content.body  = message
            content.sound = .default

            // Fire at 9am on the Nth day after firstLaunchDate
            guard let fireDate = calendar.date(byAdding: .day, value: day - 1, to: firstLaunchDate) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: fireDate)
            components.hour   = 9
            components.minute = 0
            components.second = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "revbo.nudge.day\(day)",
                content:    content,
                trigger:    trigger
            )

            center.add(request) { error in
                if let error { print("[OnboardingService] Failed to schedule day \(day) notification: \(error)") }
            }
        }
    }

    // MARK: - Private helpers

    private func seedFirstLaunchDate() {
        guard UserDefaults.standard.object(forKey: Keys.firstLaunchDate) == nil else { return }
        UserDefaults.standard.set(Date(), forKey: Keys.firstLaunchDate)
    }

    private func requestNotificationPermissionAndSchedule() async {
        let center = UNUserNotificationCenter.current()
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("[OnboardingService] Notification permission error: \(error)")
            return
        }
        if granted { scheduleNudgeNotifications() }
    }
}
