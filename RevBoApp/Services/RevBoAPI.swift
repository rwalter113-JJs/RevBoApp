import Foundation
import Combine

final class RevBoAPI: ObservableObject {

    /// Reads from AppSettings — configurable in Settings screen, defaults to Railway URL.
    private var baseURL: String { AppSettings.shared.serverURL }

    // MARK: - Process image (Vision pipeline)

    func processImage(_ imageData: Data) async throws -> RevBoResult {
        let url = try endpoint("/v1/process-image")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(data: imageData,
                                         mimeType: "image/jpeg",
                                         filename: "snap.jpg",
                                         boundary: boundary)
        return try await send(request)
    }

    // MARK: - Listen (Voice pipeline)

    func listen(
        audioURL: URL,
        contactHash: String? = nil,
        attributionMethod: String = "auto_email"
    ) async throws -> (transcript: String, result: RevBoResult?) {
        // Pass attribution as URL query params — much simpler and unambiguous
        // compared to multipart form fields, which some parsers handle inconsistently.
        var components = URLComponents(string: baseURL + "/v1/listen")!
        if let hash = contactHash {
            components.queryItems = [
                URLQueryItem(name: "contact_hash",       value: hash),
                URLQueryItem(name: "attribution_method", value: attributionMethod),
            ]
        }
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let audioData = try Data(contentsOf: audioURL)
        let boundary  = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        // Body is audio-only — no form fields needed (attribution is in the URL)
        request.httpBody = multipartAudioBody(audioData: audioData, boundary: boundary)

        let response: ListenResult = try await send(request)
        return (response.transcript, response.result)
    }

    /// Builds a minimal multipart body containing only the audio file.
    /// Attribution params are passed as URL query parameters instead.
    private func multipartAudioBody(audioData: Data, boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n"
        body.append("--\(boundary)\(crlf)")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\(crlf)")
        body.append("Content-Type: audio/m4a\(crlf)\(crlf)")
        body.append(audioData)
        body.append("\(crlf)--\(boundary)--\(crlf)")
        return body
    }

    // MARK: - Upload file (Personal Cloud Connector)

    func upload(fileURL: URL, onProgress: @escaping (Double) -> Void) async throws -> RevBoResult {
        let url  = try endpoint("/v1/upload")
        let mime = mimeType(for: fileURL)

        // Security-scoped access required for files picked from Files / iCloud
        _ = fileURL.startAccessingSecurityScopedResource()
        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            fileURL.stopAccessingSecurityScopedResource()
            throw error
        }
        fileURL.stopAccessingSecurityScopedResource()
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        let body = multipartBody(data: fileData,
                                  mimeType: mime,
                                  filename: fileURL.lastPathComponent,
                                  boundary: boundary)

        let (data, response) = try await URLSession.shared.upload(
            for: request,
            from: body,
            delegate: ProgressDelegate(onProgress: onProgress)
        )
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RevBoAPIError.serverError(msg)
        }
        return try JSONDecoder().decode(RevBoResult.self, from: data)
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":  return "application/pdf"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "ppt":  return "application/vnd.ms-powerpoint"
        case "mp4":  return "video/mp4"
        case "wav":  return "audio/wav"
        case "m4a":  return "audio/m4a"
        case "mp3":  return "audio/mpeg"
        default:     return "application/octet-stream"
        }
    }

    // MARK: - Process text (main pipeline)

    func processText(
        _ text: String,
        contactHash: String? = nil,
        attributionMethod: String = "auto_email"
    ) async throws -> RevBoResult {
        let url = try endpoint("/v1/process")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct ProcessRequest: Encodable {
            let raw_text: String
            let contact_hash: String?
            let attribution_method: String
        }

        request.httpBody = try JSONEncoder().encode(
            ProcessRequest(
                raw_text: text,
                contact_hash: contactHash,
                attribution_method: attributionMethod
            )
        )
        return try await send(request)
    }

    // MARK: - Brain query (raw notes)

    func queryBrain(_ text: String, filter: [String: String]? = nil, n: Int = 10) async throws -> BrainQueryResponse {
        let url = try endpoint("/v1/brain/query")
        var request = URLRequest(url: url)
        request.httpMethod  = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = BrainQueryRequest(query_text: text, filter_metadata: filter, n_results: n)
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    // MARK: - Brain ask (synthesised coaching brief)

    func askBrain(_ text: String, filter: [String: String]? = nil) async throws -> BrainSynthesis {
        let url = try endpoint("/v1/brain/ask")
        var request = URLRequest(url: url)
        request.httpMethod  = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = BrainAskRequest(query_text: text, filter_metadata: filter, n_results: 10)
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    // MARK: - Contact Attribution  (PRD 3)

    /// Attach a contact hash to an already-stored record (post-hoc manual attribution).
    func attachContactHash(_ req: ContactAttachRequest) async throws -> ContactAttachResponse {
        let url = try endpoint("/v1/brain/contact/attach")
        var request = URLRequest(url: url)
        request.httpMethod  = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody    = try JSONEncoder().encode(req)
        return try await send(request)
    }

    /// Generate a longitudinal relationship brief for a contact hash.
    func contactSummary(_ req: ContactSummaryRequest) async throws -> ContactSummaryResponse {
        let url = try endpoint("/v1/brain/contact/summary")
        var request = URLRequest(url: url)
        request.httpMethod  = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody    = try JSONEncoder().encode(req)
        return try await send(request)
    }

    /// Fetch aggregate stats for a contact hash (record count, first/last seen, etc.).
    func contactStats(hash: String) async throws -> ContactStatsResponse {
        let url = try endpoint("/v1/brain/contact/stats/\(hash)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await send(request)
    }

    /// Permanently delete all records attributed to a contact hash.
    func deleteContactRecords(hash: String) async throws -> ContactDeleteResponse {
        let url = try endpoint("/v1/brain/contact/records")
        var request = URLRequest(url: url)
        request.httpMethod  = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody    = try JSONEncoder().encode(ContactDeleteRequest(contact_hash: hash))
        return try await send(request)
    }

    /// Generate a pre-meeting prep brief (contact snapshots + MEDDIC/BANT + questions).
    func meetingPrep(_ request: MeetingPrepRequest) async throws -> MeetingPrepResponse {
        let url = try endpoint("/v1/meeting/prep")
        var req = URLRequest(url: url)
        req.httpMethod  = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody    = try JSONEncoder().encode(request)
        return try await send(req)
    }

    /// Fetch recent public signals (LinkedIn posts, news, Twitter) for a contact.
    func fetchSignals(name: String, linkedInUrl: String?, company: String?) async throws -> ContactSignals {
        let url = try endpoint("/v1/contact/signals")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct SignalsRequest: Encodable {
            let name: String
            let linkedin_url: String?
            let company: String?
        }
        request.httpBody = try JSONEncoder().encode(
            SignalsRequest(name: name, linkedin_url: linkedInUrl, company: company)
        )
        return try await send(request)
    }

    /// Enrich a contact via Apollo + Proxycurl (backend call — keys stay server-side).
    func enrichContact(name: String, email: String?, company: String?) async throws -> ContactEnrichment? {
        let url = try endpoint("/v1/contact/enrich")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct EnrichRequest: Encodable {
            let name: String
            let email: String?
            let company: String?
        }
        request.httpBody = try JSONEncoder().encode(EnrichRequest(name: name, email: email, company: company))

        struct EnrichResponse: Decodable {
            let title: String?
            let linkedin_url: String?
            let headline: String?
            let photo_url: String?
            let location: String?
            let industry: String?
            let seniority: String?
            let summary: String?
            let skills: [String]?
            let connections: Int?
            let employment_history: [JobResponse]?
            let education: [EduResponse]?
            let certifications: [String]?

            struct JobResponse: Decodable {
                let title: String
                let company: String
                let start_date: String?
                let end_date: String?
                let current: Bool?
            }
            struct EduResponse: Decodable {
                let school: String?
                let degree: String?
                let field: String?
                let start_year: Int?
                let end_year: Int?
            }
        }

        let r: EnrichResponse = try await send(request)

        // Return nil if Apollo found nothing useful
        guard r.title != nil || r.linkedin_url != nil || r.headline != nil else { return nil }

        return ContactEnrichment(
            title:          r.title,
            linkedinUrl:    r.linkedin_url,
            headline:       r.headline,
            photoUrl:       r.photo_url,
            location:       r.location,
            industry:       r.industry,
            seniority:      r.seniority,
            summary:        r.summary,
            skills:         r.skills ?? [],
            employment:     (r.employment_history ?? []).map {
                EnrichmentJob(
                    title:     $0.title,
                    company:   $0.company,
                    startDate: $0.start_date ?? "",
                    endDate:   $0.end_date ?? "",
                    current:   $0.current ?? false
                )
            },
            education:      (r.education ?? []).map {
                EnrichmentEducation(
                    school:    $0.school ?? "",
                    degree:    $0.degree ?? "",
                    field:     $0.field ?? "",
                    startYear: $0.start_year,
                    endYear:   $0.end_year
                )
            },
            certifications: r.certifications ?? [],
            connections:    r.connections,
            enrichedAt:     Date()
        )
    }

    // MARK: - My Development  (/v1/self/*)

    /// Upload a personal coaching document (review, 1:1, coaching session).
    func uploadCoachingDoc(_ request: CoachingDocUploadRequest) async throws -> CoachingDocUploadResponse {
        let url = try endpoint("/v1/self/ingest")
        var req = URLRequest(url: url)
        req.httpMethod  = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody    = try JSONEncoder().encode(request)
        return try await send(req)
    }

    /// Fetch all uploaded coaching documents.
    func fetchCoachingDocs() async throws -> CoachingDocsResponse {
        let url = try endpoint("/v1/self/docs")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        return try await send(req)
    }

    /// Delete a coaching document by ID.
    func deleteCoachingDoc(docId: String) async throws {
        let url = try endpoint("/v1/self/docs/\(docId)")
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        // Generic send returns Decodable — use a throwaway wrapper
        struct Empty: Decodable {}
        let _: Empty = try await send(req)
    }

    /// Ask a question answered using personal coaching documents.
    func askCoaching(query: String) async throws -> CoachingAskResponse {
        let url = try endpoint("/v1/self/ask")
        var req = URLRequest(url: url)
        req.httpMethod  = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody    = try JSONEncoder().encode(CoachingAskRequest(query: query))
        return try await send(req)
    }

    // MARK: - Granola integration

    struct GranolaMeetingsResponse: Decodable {
        let configured: Bool
        let meetings:   [GranolaMeeting]
    }

    /// Bulk-sync recent Granola meetings into the RevBo Brain.
    ///
    /// Builds `contactMap` from the on-device contact registry (every tracked
    /// contact that has an email), posts to `/v1/granola/sync`, and reads the
    /// Granola API key from the iOS Keychain via AppSettings. The key is placed
    /// in `X-Granola-Key` and never stored server-side.
    func syncGranola(contactMap: [[String: String]]) async throws -> GranolaSyncResponse {
        let url = try endpoint("/v1/granola/sync")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Attach the per-user Granola key from Keychain
        let granolaKey = AppSettings.shared.granolaAPIKey
        guard !granolaKey.isEmpty else {
            throw RevBoAPIError.serverError("Granola API key not set — add it in Settings")
        }
        request.setValue(granolaKey, forHTTPHeaderField: "X-Granola-Key")

        struct SyncBody: Encodable {
            let since_days:  Int
            let contact_map: [[String: String]]
        }
        request.httpBody = try JSONEncoder().encode(SyncBody(since_days: 7, contact_map: contactMap))
        return try await send(request)
    }

    /// Build the contact map from the on-device registry for Granola sync.
    /// Returns an array of {"email": "...", "contact_hash": "..."} dicts.
    func buildGranolaContactMap() -> [[String: String]] {
        ContactAttributionStore.shared.contacts.compactMap { contact in
            guard let email = contact.email, !email.isEmpty else { return nil }
            return ["email": email.lowercased(), "contact_hash": contact.hash]
        }
    }

    func granolaListMeetings() async throws -> GranolaMeetingsResponse {
        let url = try endpoint("/v1/integrations/granola/meetings")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let key = AppSettings.shared.granolaAPIKey
        if !key.isEmpty { request.setValue(key, forHTTPHeaderField: "X-Granola-Key") }
        return try await send(request)
    }

    func granolaImportMeeting(meetingId: String) async throws -> RevBoResult {
        let url = try endpoint("/v1/integrations/granola/import")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = AppSettings.shared.granolaAPIKey
        if !key.isEmpty { request.setValue(key, forHTTPHeaderField: "X-Granola-Key") }
        struct Body: Encodable { let meeting_id: String }
        request.httpBody = try JSONEncoder().encode(Body(meeting_id: meetingId))
        return try await send(request)
    }

    // MARK: - Helpers

    private func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else {
            throw URLError(.badURL)
        }
        return url
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        var req = request
        // Attach the shared app API key so the server can authenticate the request
        req.setValue(AppSettings.revboAPIKey, forHTTPHeaderField: "X-RevBo-Key")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RevBoAPIError.serverError(body)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func multipartBody(data: Data,
                                mimeType: String,
                                filename: String,
                                boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n"
        body.append("--\(boundary)\(crlf)")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\(crlf)")
        body.append("Content-Type: \(mimeType)\(crlf)\(crlf)")
        body.append(data)
        body.append("\(crlf)--\(boundary)--\(crlf)")
        return body
    }
}

// MARK: - Upload progress delegate

private final class ProgressDelegate: NSObject, URLSessionTaskDelegate {
    let onProgress: (Double) -> Void
    init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend) * 0.4)
    }
}

// MARK: - Error type

enum RevBoAPIError: LocalizedError {
    case serverError(String)
    var errorDescription: String? {
        if case .serverError(let msg) = self { return msg }
        return nil
    }
}

// MARK: - Data helper

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
