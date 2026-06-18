import SwiftUI

// MARK: - Onboarding Interview
// Conversational flow to capture user's job context after first login.
// Shown once, then sets profile.onboarding_completed = true.

struct OnboardingInterviewView: View {

    @StateObject private var api = RevBoAPI()
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep = 0
    @State private var isLoading = false
    @State private var errorMessage: String?

    // LinkedIn enrichment
    @State private var linkedInURL = ""
    @State private var skipLinkedIn = false
    @State private var isEnriching = false

    // Profile fields
    @State private var product = ""
    @State private var salesCycleDays = 60
    @State private var aov = 0
    @State private var buyerPersona = ""
    @State private var quota = 0
    @State private var attainment = 0
    @State private var biggestWin = ""
    @State private var biggestLoss = ""
    @State private var whyLeft = ""

    let salesCycleOptions = [
        ("0-30 days", 15),
        ("30-60 days", 45),
        ("60-90 days", 75),
        ("90+ days", 120)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress bar
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.revboOrange)
                            .frame(width: geo.size.width * progressFraction, height: 3)
                            .animation(.easeInOut, value: currentStep)
                    }
                    .frame(height: 3)

                    ScrollView {
                        VStack(spacing: 32) {
                            // Step content
                            stepView
                        }
                        .padding(24)
                    }

                    // Navigation buttons
                    HStack(spacing: 16) {
                        if currentStep > 0 {
                            Button {
                                withAnimation { currentStep -= 1 }
                            } label: {
                                HStack {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.gray)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color(white: 0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            if currentStep == 1 && !skipLinkedIn && !linkedInURL.isEmpty {
                                // LinkedIn enrichment step
                                Task { await enrichFromLinkedIn() }
                            } else if currentStep < 7 {
                                withAnimation { currentStep += 1 }
                            } else {
                                Task { await completeOnboarding() }
                            }
                        } label: {
                            HStack {
                                if currentStep == 1 && !skipLinkedIn && !linkedInURL.isEmpty && isEnriching {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.black)
                                    Text("Enriching...")
                                } else {
                                    Text(currentStep < 7 ? "Next" : "Finish")
                                    if currentStep == 7 {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(isNextEnabled ? Color.revboOrange : Color.gray.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!isNextEnabled || isLoading)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Color.black.opacity(0.95))
                }
            }
            .navigationTitle("Tell us about yourself")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let msg = errorMessage {
                    Text(msg)
                }
            }
        }
    }

    // MARK: - Step Views

    @ViewBuilder
    private var stepView: some View {
        switch currentStep {
        case 0: welcomeStep
        case 1: linkedInStep
        case 2: productStep
        case 3: salesCycleStep
        case 4: buyerStep
        case 5: quotaStep
        case 6: winsStep
        case 7: lossesStep
        default: EmptyView()
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.revboOrange)

            Text("Welcome to RevBo")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            Text("We'll ask a few questions about your role and what you sell. This helps RevBo give you better coaching and prep briefs tailored to your deals.")
                .font(.system(size: 16))
                .foregroundStyle(.gray)
                .fixedSize(horizontal: false, vertical: true)

            Text("Takes about 2 minutes")
                .font(.system(size: 14))
                .foregroundStyle(Color.revboOrange)
        }
    }

    private var linkedInStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color(red: 0.0, green: 0.47, blue: 0.71)) // LinkedIn blue

            Text("Connect your LinkedIn")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("We'll auto-fill your work history and current role. Your profile stays private—we only use it to personalize coaching.")
                .font(.system(size: 15))
                .foregroundStyle(.gray)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                TextField("Paste your LinkedIn profile URL", text: $linkedInURL)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .tint(Color.revboOrange)
                    .padding(14)
                    .background(Color(white: 0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                Text("Example: linkedin.com/in/yourname")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
            }

            Button {
                skipLinkedIn = true
                withAnimation { currentStep += 1 }
            } label: {
                Text("Skip for now")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.revboOrange)
            }
            .padding(.top, 8)
        }
    }

    private var productStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What do you sell?")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("Describe your product or service in a few words")
                .font(.system(size: 14))
                .foregroundStyle(.gray)

            TextField("e.g. B2B SaaS CRM, Enterprise Security Software...", text: $product, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(Color.revboOrange)
                .padding(14)
                .background(Color(white: 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .lineLimit(3...5)
        }
    }

    private var salesCycleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What's your typical sales cycle?")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("From first touch to closed-won")
                .font(.system(size: 14))
                .foregroundStyle(.gray)

            VStack(spacing: 12) {
                ForEach(salesCycleOptions, id: \.0) { option in
                    Button {
                        salesCycleDays = option.1
                    } label: {
                        HStack {
                            Text(option.0)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                            Spacer()
                            if salesCycleDays == option.1 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.revboOrange)
                            } else {
                                Circle()
                                    .stroke(Color.gray, lineWidth: 2)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .padding(16)
                        .background(salesCycleDays == option.1 ? Color.revboOrange.opacity(0.15) : Color(white: 0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(salesCycleDays == option.1 ? Color.revboOrange : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var buyerStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Who do you typically sell to?")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("Buyer title, company size, industry — whatever helps")
                .font(.system(size: 14))
                .foregroundStyle(.gray)

            TextField("e.g. VP Sales, 50-500 employees, Tech/SaaS", text: $buyerPersona, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(Color.revboOrange)
                .padding(14)
                .background(Color(white: 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .lineLimit(2...4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Average deal size")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                HStack {
                    Text("$")
                        .font(.system(size: 15))
                        .foregroundStyle(.gray)
                    TextField("50000", value: $aov, format: .number)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .tint(Color.revboOrange)
                        .keyboardType(.numberPad)
                }
                .padding(14)
                .background(Color(white: 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var quotaStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What's your annual quota?")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("Optional — helps RevBo understand your goals")
                .font(.system(size: 14))
                .foregroundStyle(.gray)

            HStack {
                Text("$")
                    .font(.system(size: 15))
                    .foregroundStyle(.gray)
                TextField("500000", value: $quota, format: .number)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .tint(Color.revboOrange)
                    .keyboardType(.numberPad)
            }
            .padding(14)
            .background(Color(white: 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Last year's attainment %")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                HStack {
                    TextField("115", value: $attainment, format: .number)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .tint(Color.revboOrange)
                        .keyboardType(.numberPad)
                    Text("%")
                        .font(.system(size: 15))
                        .foregroundStyle(.gray)
                }
                .padding(14)
                .background(Color(white: 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var winsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What's your biggest win in the last 6 months?")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("A deal you're proud of — the story behind it")
                .font(.system(size: 14))
                .foregroundStyle(.gray)

            TextField("e.g. Closed Fortune 500 account after 9-month cycle...", text: $biggestWin, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(Color.revboOrange)
                .padding(14)
                .background(Color(white: 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .lineLimit(4...8)
        }
    }

    private var lossesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What deal did you lose that still stings?")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("Learning from losses makes you better")
                .font(.system(size: 14))
                .foregroundStyle(.gray)

            TextField("e.g. Lost to competitor because we didn't engage executive sponsor early enough...", text: $biggestLoss, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(Color.revboOrange)
                .padding(14)
                .background(Color(white: 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .lineLimit(4...8)
        }
    }

    // MARK: - Helpers

    private var progressFraction: CGFloat {
        CGFloat(currentStep + 1) / 8.0
    }

    private var isNextEnabled: Bool {
        switch currentStep {
        case 0: return true  // Welcome
        case 1: return true  // LinkedIn optional (can skip)
        case 2: return !product.isEmpty
        case 3: return true  // salesCycleDays has default
        case 4: return !buyerPersona.isEmpty || aov > 0
        case 5: return true  // quota optional
        case 6: return !biggestWin.isEmpty
        case 7: return !biggestLoss.isEmpty
        default: return false
        }
    }

    private func enrichFromLinkedIn() async {
        isEnriching = true
        defer { isEnriching = false }

        do {
            let revboAPI = RevBoAPI()
            let enriched = try await revboAPI.enrichProfileFromLinkedIn(linkedInURL: linkedInURL)

            // Auto-populate fields from LinkedIn data
            await MainActor.run {
                let role = enriched.current_role
                if !role.title.isEmpty && product.isEmpty {
                    product = role.title
                }
                if !role.company.isEmpty && buyerPersona.isEmpty {
                    buyerPersona = "Decision makers at companies like \(role.company)"
                }

                // Move to next step
                withAnimation { currentStep += 1 }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Could not enrich from LinkedIn. You can continue manually."
                // Still proceed to next step
                withAnimation { currentStep += 1 }
            }
        }
    }

    private func completeOnboarding() async {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await api.updateProfile(UpdateProfileRequest(
                current_role: nil,  // User can add this later in Profile settings
                sales_context: SalesContextDict(
                    product: product,
                    sales_cycle_days: salesCycleDays,
                    aov: aov,
                    buyer_persona: buyerPersona,
                    quota_annual: quota,
                    attainment_last_year: attainment,
                    biggest_win: biggestWin,
                    biggest_loss: biggestLoss,
                    left_previous_because: whyLeft
                ),
                work_history: nil,
                onboarding_completed: true
            ))

            await MainActor.run {
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to save profile: \(error.localizedDescription)"
            }
        }
    }
}
