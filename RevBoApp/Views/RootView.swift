import SwiftUI

// MARK: - Root View
// Shows onboarding interview on first launch, then HomeView

struct RootView: View {

    @StateObject private var api = RevBoAPI()
    @State private var profile: ProfileResponse?
    @State private var isLoading = true
    @State private var showOnboarding = false

    var body: some View {
        Group {
            if isLoading {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView()
                        .tint(Color.revboOrange)
                }
            } else if showOnboarding {
                OnboardingInterviewView()
            } else {
                HomeView()
            }
        }
        .task { await loadProfile() }
    }

    private func loadProfile() async {
        do {
            let loaded = try await api.getProfile()
            await MainActor.run {
                profile = loaded
                showOnboarding = !loaded.onboarding_completed
                isLoading = false
            }
        } catch {
            // Profile doesn't exist yet — show onboarding
            await MainActor.run {
                showOnboarding = true
                isLoading = false
            }
        }
    }
}
