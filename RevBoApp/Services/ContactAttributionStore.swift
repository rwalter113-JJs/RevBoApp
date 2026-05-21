import Combine
import Foundation
import Contacts

// MARK: - TrackedContact model

/// On-device record for a tracked contact.
/// Stored as JSON in UserDefaults — never synced to iCloud or the server.
struct TrackedContact: Codable, Identifiable, Equatable {
    var id: String { hash }

    let hash:        String     // opaque SHA-256 — never the real identifier
    let displayName: String     // "John Smith" — shown in UI only, never sent to server
    let signalType:  String     // "email" | "phone" | "manual"
    let addedAt:     Date
    var recordCount: Int        // updated locally after each sync with server stats
    var lastSeen:    Date?      // pulled from server stats endpoint

    // Contact details — stored locally for display only, never transmitted
    var email:   String?        // primary email address
    var phone:   String?        // primary phone number
    var company: String?        // organisation name from CNContact

    // Apollo + Proxycurl enrichment — stored locally, never sent to server
    var enrichment: ContactEnrichment?
}

struct ContactEnrichment: Codable, Equatable {
    var title:         String?
    var linkedinUrl:   String?
    var headline:      String?
    var photoUrl:      String?
    var location:      String?
    var industry:      String?
    var seniority:     String?
    var summary:       String?
    var skills:        [String]
    var employment:    [EnrichmentJob]
    var education:     [EnrichmentEducation]
    var certifications:[String]
    var connections:   Int?
    var enrichedAt:    Date
}

struct EnrichmentJob: Codable, Equatable {
    var title:     String
    var company:   String
    var startDate: String
    var endDate:   String
    var current:   Bool
}

struct EnrichmentEducation: Codable, Equatable {
    var school:    String
    var degree:    String
    var field:     String
    var startYear: Int?
    var endYear:   Int?
}

// MARK: - On-device registry

/// JSON-backed on-device Contact Hash Registry.
///
/// Design:
///   • Stored in UserDefaults under a single JSON key — fast read, small write.
///   • NOT synced to iCloud (`standardDefaults` have no CloudKit bridge by default).
///   • The registry maps opaque hashes to display names for the UI.
///     The server never sees display names — only the hash.
///   • For a 5-person beta with modest contact lists, UserDefaults is fine.
///     A future version can migrate to Core Data for richer querying.
final class ContactAttributionStore: ObservableObject {

    static let shared = ContactAttributionStore()
    private init() { load() }

    @Published private(set) var contacts: [TrackedContact] = []

    private let defaults = UserDefaults.standard
    private let key      = "revbo.contactRegistry.v1"

    // MARK: - Queries

    func isTracked(hash: String) -> Bool {
        contacts.contains { $0.hash == hash }
    }

    func contact(forHash hash: String) -> TrackedContact? {
        contacts.first { $0.hash == hash }
    }

    // MARK: - Mutations

    /// Add a CNContact to the registry if it isn't already tracked.
    /// Returns the hash that was added (or already existed).
    @discardableResult
    func track(_ cnContact: CNContact) -> String? {
        guard let hash = ContactHashService.shared.hash(contact: cnContact) else { return nil }

        if isTracked(hash: hash) { return hash }   // already in registry

        let displayName = CNContactFormatter.string(from: cnContact, style: .fullName)
            ?? cnContact.emailAddresses.first?.value as String?
            ?? cnContact.phoneNumbers.first?.value.stringValue
            ?? "Unknown"

        let signal: String
        if cnContact.emailAddresses.first != nil { signal = "email" }
        else if cnContact.phoneNumbers.first != nil { signal = "phone" }
        else { signal = "manual" }

        let email   = cnContact.emailAddresses.first?.value as String?
        let phone   = cnContact.phoneNumbers.first?.value.stringValue
        let company = cnContact.organizationName.isEmpty ? nil : cnContact.organizationName

        let record = TrackedContact(
            hash:        hash,
            displayName: displayName,
            signalType:  signal,
            addedAt:     Date(),
            recordCount: 0,
            lastSeen:    nil,
            email:       email,
            phone:       phone,
            company:     company
        )

        contacts.append(record)
        save()
        return hash
    }

    /// Update a tracked contact's server-side stats (called after /contact/stats fetch).
    func updateStats(hash: String, recordCount: Int, lastSeen: Date?) {
        guard let idx = contacts.firstIndex(where: { $0.hash == hash }) else { return }
        contacts[idx].recordCount = recordCount
        contacts[idx].lastSeen    = lastSeen
        save()
    }

    /// Persist Apollo/Proxycurl enrichment data against a contact hash.
    func updateEnrichment(hash: String, enrichment: ContactEnrichment) {
        guard let idx = contacts.firstIndex(where: { $0.hash == hash }) else { return }
        contacts[idx].enrichment = enrichment
        save()
    }

    /// Remove a contact from the local registry (called after server-side delete).
    func remove(hash: String) {
        contacts.removeAll { $0.hash == hash }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TrackedContact].self, from: data)
        else { return }
        contacts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(contacts) else { return }
        defaults.set(data, forKey: key)
    }
}
