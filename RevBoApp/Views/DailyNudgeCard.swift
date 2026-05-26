import SwiftUI

// MARK: - DailyNudgeCard

struct DailyNudgeCard: View {

    @ObservedObject var service: OnboardingService
    @ObservedObject private var store = ContactAttributionStore.shared

    @State private var isDismissedForToday: Bool = {
        let dismissedDay = UserDefaults.standard.integer(forKey: "revbo.nudge.dismissedDay")
        return dismissedDay == OnboardingService.shared.currentNudgeDay
    }()

    // MARK: - Body

    var body: some View {
        if !isDismissedForToday {
            cardContent
        }
    }

    // MARK: - Card content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Top row: day label + dismiss button
            HStack(alignment: .center) {

                // "DAY X OF 10"
                Text("DAY \(service.currentNudgeDay) OF 10")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.revboOrange)
                    .tracking(1.2)

                Spacer()

                // Dismiss X
                Button {
                    UserDefaults.standard.set(service.currentNudgeDay, forKey: "revbo.nudge.dismissedDay")
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDismissedForToday = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.revboSubtle)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.revboOrange)
                        .frame(width: geo.size.width * CGFloat(service.currentNudgeDay) / 10.0, height: 4)
                }
            }
            .frame(height: 4)

            // Nudge message
            Text(nudgeMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.revboText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(16)
        .background(Color.revboSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - Dynamic nudge message

    private var nudgeMessage: String {
        let day = service.currentNudgeDay

        switch day {
        case 9:
            let contacts = store.contacts
            guard !contacts.isEmpty else {
                return "You have contacts without notes — pick one and add a voice note today"
            }
            let total     = contacts.count
            let withNotes = contacts.filter { $0.recordCount > 0 }.count
            return "You have \(total) contacts but only \(withNotes) have notes logged — pick one and add a voice note"

        case 10:
            let contacts = store.contacts
            guard !contacts.isEmpty else {
                return "Some of your contacts are missing personal details — add a few more while they're fresh"
            }
            let total     = contacts.count
            // A contact "has personal details" when it has Apollo enrichment with at least a title or headline
            let withDetails = contacts.filter {
                let e = $0.enrichment
                return e?.title != nil || e?.headline != nil || e?.summary != nil
            }.count
            return "Only \(withDetails) of your \(total) contacts have personal details — add a few more while they're fresh"

        default:
            return staticMessage(for: day)
        }
    }

    // MARK: - Static messages

    private func staticMessage(for day: Int) -> String {
        switch day {
        case 1:  return "Add your first contacts — start with the 5 people you're most actively working with"
        case 2:  return "Log your first voice note — after your next call, hit the mic and give RevBo a 30-second debrief"
        case 3:  return "Add personal details to a contact — family, interests, hobbies. The things you'd never put in a CRM"
        case 4:  return "Connect your calendar — RevBo will prep you before every meeting automatically"
        case 5:  return "Capture something — upload a deck, a proposal, or a call recording and RevBo will read it and remember it against the right contact"
        case 6:  return "Try Ask Bo — type 'What do I know about [name]?' and see what comes back"
        case 7:  return "Fetch a LinkedIn profile — tap any contact and hit Refresh Profile for instant enrichment"
        case 8:  return "Tap a meeting in This Week — RevBo will show you a prep brief before the call"
        default: return "Keep capturing — every note makes RevBo smarter"
        }
    }
}
