import SwiftUI

/// Bottom sheet shown after a pipeline result arrives with no auto-attribution.
/// Lets the user manually link the stored Brain record to one of their tracked contacts.
struct AttributionContactPicker: View {

    let brainId:  String
    /// Called (on main thread) when the user successfully links a contact.
    let onLinked: (TrackedContact) -> Void

    @Environment(\.dismiss)  private var dismiss
    @ObservedObject private var store = ContactAttributionStore.shared
    @StateObject    private var api   = RevBoAPI()

    @State private var searchText    = ""
    @State private var isLinking     = false
    @State private var linkedContact: TrackedContact?
    @State private var errorMessage:  String?

    private var filtered: [TrackedContact] {
        guard !searchText.isEmpty else { return store.contacts }
        return store.contacts.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            ($0.company ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.revboBg.ignoresSafeArea()

                if store.contacts.isEmpty {
                    emptyState
                } else {
                    contactList
                }
            }
            .navigationTitle("Who was this about?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Skip") { dismiss() }
                        .foregroundStyle(Color.revboMuted)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.revboBg)
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Contact list

    private var contactList: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.revboMuted)
                    .font(.system(size: 14))
                TextField("Search contacts…", text: $searchText)
                    .foregroundStyle(Color.revboText)
                    .tint(Color.revboOrange)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.revboMuted)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.revboSurface2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if filtered.isEmpty {
                Text("No contacts match \"\(searchText)\"")
                    .font(.subheadline)
                    .foregroundStyle(Color.revboMuted)
                    .padding(.top, 48)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, contact in
                            contactRow(contact)
                            if idx < filtered.count - 1 {
                                Divider()
                                    .background(Color.white.opacity(0.06))
                                    .padding(.leading, 66)
                            }
                        }
                    }
                    .background(Color.revboSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    @ViewBuilder
    private func contactRow(_ contact: TrackedContact) -> some View {
        let isLinked  = linkedContact?.id == contact.id
        let isSpinner = isLinking && linkedContact == nil

        Button {
            guard !isLinking else { return }
            Task { await link(contact) }
        } label: {
            HStack(spacing: 14) {
                // Initials avatar
                ZStack {
                    Circle()
                        .fill(Color.revboBlue.opacity(0.22))
                        .frame(width: 42, height: 42)
                    Text(initials(contact.displayName))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.revboBlue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.revboText)
                    if let company = contact.company, !company.isEmpty {
                        Text(company)
                            .font(.caption)
                            .foregroundStyle(Color.revboMuted)
                    }
                }

                Spacer()

                if isLinked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.revboOrange)
                        .font(.title3)
                        .transition(.scale.combined(with: .opacity))
                } else if isSpinner {
                    ProgressView().tint(Color.revboOrange).scaleEffect(0.75)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.revboMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 52))
                .foregroundStyle(Color.revboMuted)
            Text("No contacts yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.revboText)
            Text("Add contacts in the My Contacts tab,\nthen try linking from here.")
                .font(.subheadline)
                .foregroundStyle(Color.revboMuted)
                .multilineTextAlignment(.center)
            Button("Skip for now") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.revboOrange)
                .padding(.top, 8)
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Link action

    private func link(_ contact: TrackedContact) async {
        isLinking = true
        defer { isLinking = false }
        do {
            let req = ContactAttachRequest(
                brainId:     brainId,
                contactHash: contact.hash,
                method:      "manual",
                confidence:  "confirmed"
            )
            _ = try await api.attachContactHash(req)
            withAnimation(.spring(response: 0.3)) { linkedContact = contact }
            onLinked(contact)
            try? await Task.sleep(nanoseconds: 700_000_000)   // brief success flash
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first.map { String($0) } }
        return letters.joined().uppercased()
    }
}
