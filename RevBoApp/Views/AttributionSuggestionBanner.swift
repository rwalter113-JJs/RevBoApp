import SwiftUI
import Contacts

// MARK: - Attribution Suggestion

struct AttributionSuggestion {
    let displayName: String
    let reason:      String
    let brainId:     String
    /// Non-nil if the contact is already tracked in RevBo.
    let tracked:     TrackedContact?
    /// Non-nil if the contact was found in the phone but not yet tracked in RevBo.
    let cnContact:   CNContact?
}

// MARK: - Attribution Suggestion Banner

struct AttributionSuggestionBanner: View {

    @Binding var suggestion: AttributionSuggestion?

    @StateObject private var api   = RevBoAPI()
    @ObservedObject private var store = ContactAttributionStore.shared

    @State private var isBusy   = false
    @State private var done     = false

    var body: some View {
        if let s = suggestion, !done {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.plus")
                    .font(.callout)
                    .foregroundStyle(Color.revboOrange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(s.tracked != nil
                         ? "Attribute to \(s.displayName)?"
                         : "Link note to \(s.displayName)?")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(s.reason)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }

                Spacer()

                if isBusy {
                    ProgressView().tint(Color.revboOrange).scaleEffect(0.8)
                } else {
                    Button(s.tracked != nil ? "Link" : "Add & Link") {
                        Task { await confirm(s) }
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.revboOrange)
                    .clipShape(Capsule())

                    Button { withAnimation { suggestion = nil } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.revboOrange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.revboOrange.opacity(0.30), lineWidth: 1)
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Confirm

    private func confirm(_ s: AttributionSuggestion) async {
        isBusy = true
        defer { isBusy = false }

        // If the contact isn't tracked yet, track it first
        let hash: String?
        if let tracked = s.tracked {
            hash = tracked.hash
        } else if let cn = s.cnContact {
            hash = store.track(cn)
        } else {
            hash = nil
        }

        guard let hash else { withAnimation { done = true; suggestion = nil }; return }

        // Attach the stored record to this contact
        _ = try? await api.attachContactHash(
            ContactAttachRequest(
                brainId:    s.brainId,
                contactHash: hash,
                method:     "auto_name",
                confidence: "confirmed"
            )
        )

        // Refresh the contact's record count
        if let stats = try? await api.contactStats(hash: hash) {
            await MainActor.run {
                store.updateStats(hash: hash, recordCount: stats.record_count, lastSeen: nil)
            }
        }

        withAnimation { done = true; suggestion = nil }
    }
}

// MARK: - Attribution Detector

enum AttributionDetector {

    /// Full detection pipeline — runs synchronously against tracked contacts,
    /// then falls back to searching the iOS Contacts app.
    /// Call from a Task since the CNContacts lookup is async.
    static func detect(
        detectedEmails: [String],
        detectedNames:  [String],
        store:          ContactAttributionStore,
        brainId:        String,
        skipHash:       String? = nil
    ) async -> AttributionSuggestion? {

        print("[AttributionDetector] detect() — emails:\(detectedEmails) names:\(detectedNames) brainId:\(brainId)")

        // ── Signal 1: email match against tracked contacts ───────────────────
        for email in detectedEmails {
            let h = ContactHashService.shared.hash(email: email)
            guard h != skipHash else { continue }
            if let contact = store.contact(forHash: h) {
                print("[AttributionDetector] Signal 1 match → \(contact.displayName)")
                return AttributionSuggestion(
                    displayName: contact.displayName,
                    reason:      "Email detected · will link automatically",
                    brainId:     brainId,
                    tracked:     contact,
                    cnContact:   nil
                )
            }
        }

        // ── Signal 2: name match against tracked contacts (fuzzy word match) ──
        for name in detectedNames {
            guard name.count >= 4 else { continue }
            if let contact = store.contacts.first(where: {
                $0.hash != skipHash && namesSimilar(name, $0.displayName)
            }) {
                print("[AttributionDetector] Signal 2 match → \(contact.displayName)")
                return AttributionSuggestion(
                    displayName: contact.displayName,
                    reason:      "Name mentioned · tap to confirm",
                    brainId:     brainId,
                    tracked:     contact,
                    cnContact:   nil
                )
            }
        }

        // ── Signal 3: name match against iOS Contacts (not yet tracked) ──────
        let cnStore = CNContactStore()
        var contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
        print("[AttributionDetector] Signal 3 — contacts auth status: \(contactsStatus.rawValue), names: \(detectedNames)")

        // Request access if we haven't asked yet
        if contactsStatus == .notDetermined {
            let granted = (try? await cnStore.requestAccess(for: .contacts)) ?? false
            contactsStatus = granted ? .authorized : .denied
            print("[AttributionDetector] Signal 3 — requested access, granted: \(granted)")
        }

        guard (contactsStatus == .authorized || contactsStatus == .limited),
              !detectedNames.isEmpty else {
            print("[AttributionDetector] Signal 3 guard failed — status:\(contactsStatus.rawValue) namesEmpty:\(detectedNames.isEmpty)")
            return nil
        }
        // CNContactFormatter requires its own descriptor (includes middleName, prefix, suffix, etc.)
        // Without it, track(cn) → CNContactFormatter crashes with CNPropertyNotFetchedException.
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey   as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
        ]

        for name in detectedNames {
            guard name.count >= 4 else { continue }
            // Search by full name via predicate
            let parts     = name.split(separator: " ").map(String.init)
            let firstName = parts.first ?? name
            let lastName  = parts.dropFirst().joined(separator: " ")

            let predicate = lastName.isEmpty
                ? CNContact.predicateForContacts(matchingName: firstName)
                : CNContact.predicateForContacts(matchingName: name)

            print("[AttributionDetector] Signal 3 searching for '\(name)'")
            if let matches = try? cnStore.unifiedContacts(matching: predicate,
                                                           keysToFetch: keysToFetch) {
                print("[AttributionDetector] Signal 3 '\(name)' → \(matches.count) match(es)")
                if let cn = matches.first {
                    // Make sure this CNContact isn't already tracked under a different name
                    let existingHash = ContactHashService.shared.hash(contact: cn)
                    if existingHash == skipHash { continue }

                    let displayName = "\(cn.givenName) \(cn.familyName)".trimmingCharacters(in: .whitespaces)
                    print("[AttributionDetector] Signal 3 match → \(displayName)")
                    return AttributionSuggestion(
                        displayName: displayName,
                        reason:      "Found in your Contacts · tap to add & link",
                        brainId:     brainId,
                        tracked:     nil,      // not tracked in RevBo yet
                        cnContact:   cn
                    )
                }
            } else {
                print("[AttributionDetector] Signal 3 '\(name)' — unifiedContacts threw an error")
            }
        }

        print("[AttributionDetector] No match found — returning nil")
        return nil
    }

    // ── Fuzzy name comparison ────────────────────────────────────────────────
    // Splits both names into words and checks whether enough words share a
    // common prefix. Handles Whisper transcription drift like "Harrow"→"Haro".
    private static func namesSimilar(_ a: String, _ b: String) -> Bool {
        let aWords = a.lowercased().split(separator: " ").map(String.init).filter { $0.count >= 3 }
        let bWords = b.lowercased().split(separator: " ").map(String.init).filter { $0.count >= 3 }
        guard !aWords.isEmpty, !bWords.isEmpty else { return false }

        var matches = 0
        for aw in aWords {
            if bWords.contains(where: { $0.hasPrefix(aw) || aw.hasPrefix($0) }) {
                matches += 1
            }
        }
        // Require matching at least ceil(half) of the shorter name's words
        let required = max(1, (min(aWords.count, bWords.count) + 1) / 2)
        return matches >= required
    }
}
