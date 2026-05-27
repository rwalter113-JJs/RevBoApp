import Foundation

// MARK: - Pipeline Response (mirrors Python RevBoResult)

struct RevBoResult: Codable {
    let scrubbed_text:   String
    let firmographics:   [[String: String]]
    let confirmation:    [String]
    let audit:           PipelineAudit
    // Emails detected pre-scrub — returned so the client can hash locally
    // and match against the on-device contact registry (Signal 1).
    let detected_emails: [String]?   // raw emails for client-side hash matching
    let detected_names:  [String]?   // PERSON names from Presidio NER for client-side matching
}

struct PipelineAudit: Codable {
    let pii_detected: [String]
    let pii_removed: Bool
    let firmographics_enriched: Bool
    let brain_id: String
    let raw_data_purged: Bool
}

// MARK: - Brain Query (raw notes — /v1/brain/query)

struct BrainQueryRequest: Codable {
    let query_text: String
    let filter_metadata: [String: String]?
    let n_results: Int
}

struct BrainQueryResponse: Codable {
    let results: [BrainResult]
    let count: Int
}

struct BrainResult: Codable, Identifiable {
    var id: String { text }
    let text: String
    let metadata: [String: String]
    let relevance_score: Double
}

// MARK: - Brain Ask (synthesised coaching — /v1/brain/ask)

struct BrainAskRequest: Codable {
    let query_text: String
    let filter_metadata: [String: String]?
    let n_results: Int
}

struct CoachingTip: Codable, Identifiable {
    var id: Int { number }
    let number: Int
    let tip: String
    let rationale: String
}

struct BrainSynthesis: Codable {
    let experience_summary:   String
    let patterns:             [String]
    let tips:                 [CoachingTip]
    let coaching_response:    String
    let data_confidence:      String          // "High" | "Medium" | "Low"
    let sources_used:         Int
    let sources_found:        Int
    let total_relevant_count: Int
    let industry_breakdown:   [String: Int]
}

// MARK: - Listen Response

struct ListenResult: Codable {
    let transcript: String
    let result: RevBoResult?
}

// MARK: - Contact Attribution  (PRD 3)

/// Apollo enrichment snapshot sent with each contact summary request.
/// Lets the backend produce Apollo-aware tips without storing PII server-side.
struct ApolloProfilePayload: Codable {
    let title:      String?
    let company:    String?
    let seniority:  String?
    let location:   String?
    let employment: [ApolloJobPayload]

    struct ApolloJobPayload: Codable {
        let title:      String
        let company:    String
        let start_date: String
        let end_date:   String
        let current:    Bool
    }
}

struct ContactSummaryRequest: Codable {
    let contact_hash:   String
    let display_name:   String?
    let n_results:      Int
    let apollo_profile: ApolloProfilePayload?

    init(contactHash: String,
         displayName: String? = nil,
         nResults: Int = 20,
         enrichment: ContactEnrichment? = nil) {
        self.contact_hash = contactHash
        self.display_name = displayName
        self.n_results    = nResults
        if let e = enrichment {
            self.apollo_profile = ApolloProfilePayload(
                title:      e.title,
                company:    e.employment.first(where: { $0.current })?.company
                            ?? e.employment.first?.company,
                seniority:  e.seniority,
                location:   e.location,
                employment: e.employment.prefix(5).map {
                    ApolloProfilePayload.ApolloJobPayload(
                        title:      $0.title,
                        company:    $0.company,
                        start_date: $0.startDate,
                        end_date:   $0.endDate,
                        current:    $0.current
                    )
                }
            )
        } else {
            self.apollo_profile = nil
        }
    }
}

/// Server response for /v1/brain/contact/summary
struct ContactSummaryResponse: Codable {
    let experience_summary:   String
    let personal_highlights:  [String]  // bullet facts: family, sports, hobbies
    let personal_summary:     String    // 1-2 sentence personal rapport narrative
    let professional_summary: String    // career + deal recap (Apollo-informed)
    let patterns:             [String]
    let tips:                 [CoachingTip]
    let coaching_response:    String
    let data_confidence:      String
    let sources_used:         Int
    let sources_found:        Int
    let total_relevant_count: Int
    let industry_breakdown:   [String: Int]
    let record_count:         Int
}

/// Server response for GET /v1/brain/contact/stats/{hash}
struct ContactStatsResponse: Codable {
    let contact_hash:        String
    let record_count:        Int
    let first_seen:          String?    // ISO-8601
    let last_seen:           String?    // ISO-8601
    let industry_breakdown:  [String: Int]
    let bucket_breakdown:    [String: Int]
    let data_confidence:     String
}

struct ContactAttachRequest: Codable {
    let brain_id:               String
    let contact_hash:           String
    let attribution_method:     String
    let attribution_confidence: String

    init(brainId: String, contactHash: String,
         method: String = "manual", confidence: String = "confirmed") {
        self.brain_id               = brainId
        self.contact_hash           = contactHash
        self.attribution_method     = method
        self.attribution_confidence = confidence
    }
}

struct ContactAttachResponse: Codable {
    let brain_id: String
    let status:   String    // "attached" | "not_found"
}

struct ContactDeleteRequest: Codable {
    let contact_hash: String
}

struct ContactDeleteResponse: Codable {
    let contact_hash:    String
    let records_deleted: Int
    let status:          String   // "deleted" | "not_found"
}

// MARK: - Public Signals  (/v1/contact/signals)

struct ContactSignals: Codable {
    let linkedin_posts: [SignalPost]
    let news:           [NewsItem]
    let twitter:        [TweetItem]
    let fetched_at:     String

    var isEmpty: Bool { linkedin_posts.isEmpty && news.isEmpty && twitter.isEmpty }
}

struct SignalPost: Codable, Identifiable {
    var id: String { url.isEmpty ? text : url }
    let text:     String
    let date:     String
    let url:      String
    let likes:    Int
    let comments: Int
}

struct NewsItem: Codable, Identifiable {
    var id: String { url }
    let title:        String
    let source:       String
    let url:          String
    let published_at: String
    let description:  String
}

struct TweetItem: Codable, Identifiable {
    var id: String { url.isEmpty ? text : url }
    let text:       String
    let created_at: String
    let url:        String
    let likes:      Int
    let retweets:   Int
}

// MARK: - Meeting Prep  (/v1/meeting/prep)

struct MeddicItem: Codable {
    let status: String   // "found" | "partial" | "missing"
    let notes: String?
}

struct MeddicBant: Codable {
    let metrics: MeddicItem
    let economic_buyer: MeddicItem
    let decision_criteria: MeddicItem
    let decision_process: MeddicItem
    let identify_pain: MeddicItem
    let champion: MeddicItem
    let budget: MeddicItem
    let timeline: MeddicItem
}

struct TrackedContactPrep: Codable, Identifiable {
    var id: String { contact_hash }
    let contact_hash: String
    let name: String
    let personal_snapshot: String
    let professional_snapshot: String
    let meddic: MeddicBant
    let suggested_questions: [String]
    let has_brain_data: Bool
}

struct MeetingPrepResponse: Codable {
    let meeting_title: String
    let tracked_contacts: [TrackedContactPrep]
    let untracked_names: [String]
}

struct MeetingPrepRequest: Codable {
    struct AttendeeInput: Codable {
        let contact_hash: String?
        let name: String
        let is_tracked: Bool
    }
    let meeting_title: String
    let attendees: [AttendeeInput]
}

// MARK: - Granola Sync  (/v1/granola/sync)

struct GranolaSyncResponse: Codable {
    let meetings_processed: Int
    let entries_created:    Int
    let meeting_titles:     [String]
    let last_sync:          String   // ISO-8601
}
