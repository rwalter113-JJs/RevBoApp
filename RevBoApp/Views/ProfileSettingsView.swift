import SwiftUI

// MARK: - Profile Settings
// Edit job context and sales configuration

struct ProfileSettingsView: View {

    @StateObject private var api = RevBoAPI()
    @Environment(\.dismiss) private var dismiss

    @State private var profile: ProfileResponse?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Editable fields
    @State private var product = ""
    @State private var salesCycleDays = 60
    @State private var aov = 0
    @State private var buyerPersona = ""
    @State private var quota = 0
    @State private var attainment = 0
    @State private var biggestWin = ""
    @State private var biggestLoss = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(Color.revboOrange)
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // What you sell
                            section(title: "WHAT YOU SELL") {
                                TextField("Product/service description", text: $product, axis: .vertical)
                                    .textFieldStyle()
                                    .lineLimit(2...4)
                            }

                            // Sales cycle & deal size
                            section(title: "SALES MOTION") {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Sales cycle (days)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.gray)
                                    TextField("60", value: $salesCycleDays, format: .number)
                                        .textFieldStyle()
                                        .keyboardType(.numberPad)

                                    Text("Average deal size")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.gray)
                                    HStack {
                                        Text("$")
                                            .foregroundStyle(.gray)
                                        TextField("50000", value: $aov, format: .number)
                                            .keyboardType(.numberPad)
                                    }
                                    .textFieldStyle()
                                }
                            }

                            // Buyer persona
                            section(title: "BUYER PERSONA") {
                                TextField("Who you sell to", text: $buyerPersona, axis: .vertical)
                                    .textFieldStyle()
                                    .lineLimit(2...4)
                            }

                            // Quota & performance
                            section(title: "QUOTA & PERFORMANCE") {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Annual quota")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.gray)
                                    HStack {
                                        Text("$")
                                            .foregroundStyle(.gray)
                                        TextField("500000", value: $quota, format: .number)
                                            .keyboardType(.numberPad)
                                    }
                                    .textFieldStyle()

                                    Text("Last year attainment %")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.gray)
                                    HStack {
                                        TextField("115", value: $attainment, format: .number)
                                            .keyboardType(.numberPad)
                                        Text("%")
                                            .foregroundStyle(.gray)
                                    }
                                    .textFieldStyle()
                                }
                            }

                            // Biggest win
                            section(title: "BIGGEST WIN (LAST 6 MONTHS)") {
                                TextField("Your proudest deal...", text: $biggestWin, axis: .vertical)
                                    .textFieldStyle()
                                    .lineLimit(3...6)
                            }

                            // Biggest loss
                            section(title: "BIGGEST LOSS") {
                                TextField("Deal that got away...", text: $biggestLoss, axis: .vertical)
                                    .textFieldStyle()
                                    .lineLimit(3...6)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task { await saveProfile() }
                    }
                    .foregroundStyle(Color.revboOrange)
                    .disabled(isSaving)
                }
            }
            .task { await loadProfile() }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let msg = errorMessage {
                    Text(msg)
                }
            }
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.revboOrange)
                .tracking(1.0)
            content()
        }
    }

    private func loadProfile() async {
        do {
            let loaded = try await api.getProfile()
            await MainActor.run {
                profile = loaded
                product = loaded.sales_context.product
                salesCycleDays = loaded.sales_context.sales_cycle_days
                aov = loaded.sales_context.aov
                buyerPersona = loaded.sales_context.buyer_persona
                quota = loaded.sales_context.quota_annual
                attainment = loaded.sales_context.attainment_last_year
                biggestWin = loaded.sales_context.biggest_win
                biggestLoss = loaded.sales_context.biggest_loss
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load profile: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func saveProfile() async {
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await api.updateProfile(UpdateProfileRequest(
                current_role: nil,
                sales_context: SalesContextDict(
                    product: product,
                    sales_cycle_days: salesCycleDays,
                    aov: aov,
                    buyer_persona: buyerPersona,
                    quota_annual: quota,
                    attainment_last_year: attainment,
                    biggest_win: biggestWin,
                    biggest_loss: biggestLoss,
                    left_previous_because: ""
                ),
                work_history: nil,
                onboarding_completed: nil
            ))

            await MainActor.run {
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to save: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Text Field Style

private struct RevBoTextFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .tint(Color.revboOrange)
            .padding(12)
            .background(Color(white: 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private extension View {
    func textFieldStyle() -> some View {
        modifier(RevBoTextFieldStyle())
    }
}
