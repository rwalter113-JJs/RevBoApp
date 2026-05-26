import SwiftUI

// MARK: - OnboardingWelcomeCard

struct OnboardingWelcomeCard: View {

    @ObservedObject var service: OnboardingService

    // MARK: - Step model

    private struct Step: Identifiable {
        let id:    Int
        let title: String
        let body:  String
    }

    private let steps: [Step] = [
        Step(id: 1,
             title: "Add your contacts",
             body:  "Import the people you're actively working with from your phone contacts. Then add the personal details you'd never put in a CRM — family, sports teams, hobbies, life events. That's the stuff that builds real relationships."),
        Step(id: 2,
             title: "Start capturing",
             body:  "After every call or meeting, tap the mic and give RevBo a quick debrief — who you talked to, what came up, what you learned. Voice notes take 30 seconds. Sensitive information like phone numbers, emails, and financial data is automatically redacted before anything is stored."),
        Step(id: 3,
             title: "Connect your calendar",
             body:  "RevBo will flag which contacts are in your upcoming meetings and prep you before each call."),
        Step(id: 4,
             title: "Ask Bo anything",
             body:  "Type a question like 'What do I know about Sarah?' or 'Who mentioned budget concerns?' and RevBo searches your memory instantly."),
    ]

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to RevBo 👋")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.revboText)

                Text("Your personal relationship memory and sales coach. Here's how to get started:")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.revboMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 20)

            // Steps
            VStack(alignment: .leading, spacing: 16) {
                ForEach(steps) { step in
                    HStack(alignment: .top, spacing: 14) {

                        // Number circle
                        ZStack {
                            Circle()
                                .fill(Color.revboOrange)
                                .frame(width: 26, height: 26)
                            Text("\(step.id)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, 1)

                        // Text
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.revboText)
                            Text(step.body)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.revboMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.bottom, 20)

            // Footer
            Text("The more you capture, the smarter your coach gets.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.revboSubtle)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 20)

            // CTA button
            Button {
                service.dismissOnboarding()
            } label: {
                Text("Got it, don't show again")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.revboOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Color.revboSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}
