import CryptoKit
import Contacts
import Foundation

/// Generates opaque SHA-256 contact hashes and detects contact signals in raw text.
///
/// Hash formula:  SHA-256(salt_bytes + canonical_identifier_utf8)
///
/// Canonical rules (must match any future platform):
///   email  → lowercase, whitespace-trimmed
///   phone  → digits only, E.164-style (strip +, spaces, dashes, parens)
///
/// The salt comes from KeychainSaltManager — it never leaves the device.
struct ContactHashService {

    static let shared = ContactHashService()
    private init() {}

    // MARK: - Public hashing

    /// Hash an email address.
    func hash(email: String) -> String {
        let canonical = email.lowercased().trimmingCharacters(in: .whitespaces)
        return _hash("email:" + canonical)
    }

    /// Hash a phone number.
    func hash(phone: String) -> String {
        // Keep digits only — strips +, spaces, dashes, parentheses
        let digits = phone.filter(\.isNumber)
        return _hash("phone:" + digits)
    }

    /// Hash a CNContact using the best available identifier.
    /// Prefers primary email; falls back to primary phone.
    func hash(contact: CNContact) -> String? {
        if let email = contact.emailAddresses.first?.value as? String, !email.isEmpty {
            return hash(email: email)
        }
        if let phone = contact.phoneNumbers.first?.value.stringValue, !phone.isEmpty {
            return hash(phone: phone)
        }
        return nil  // no usable identifier
    }

    // MARK: - Auto-detection (Signal 1: email in raw text)

    /// Scan raw text for email addresses and return a list of contact hashes
    /// for any that exist in the on-device registry.
    ///
    /// Used at ingest time so the pipeline can attach a contact hash without
    /// the user having to do anything.
    func detectContactHashes(in text: String, registry: ContactAttributionStore) -> [String] {
        let emails = extractEmails(from: text)
        return emails
            .map { hash(email: $0) }
            .filter { registry.isTracked(hash: $0) }
    }

    /// Extract all RFC-5322-ish email addresses from a string using NSDataDetector.
    func extractEmails(from text: String) -> [String] {
        // NSDataDetector doesn't have an email type — use a simple regex
        let pattern = #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range   = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match -> String? in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange]).lowercased()
        }
    }

    // MARK: - Private

    private func _hash(_ value: String) -> String {
        let salt        = KeychainSaltManager.shared.salt()
        let valueBytes  = Data(value.utf8)
        var combined    = salt
        combined.append(valueBytes)
        let digest = SHA256.hash(data: combined)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
