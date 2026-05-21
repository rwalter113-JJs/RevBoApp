import SwiftUI

// Shown from ImportFileView — lets user pick and import a Granola meeting
private struct GranolaSection: View {
    @StateObject private var api = RevBoAPI()
    @State private var meetings: [GranolaMeeting] = []
    @State private var isLoading  = false
    @State private var configured = false
    @State private var errorMessage: String?
    let onResult: (RevBoResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.revboBlue)
                Text("Import from Granola")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.revboText)
                Spacer()
                if isLoading { ProgressView().tint(Color.revboBlue).scaleEffect(0.8) }
            }

            if !configured && !isLoading {
                Text("Add your GRANOLA_API_KEY to the RevBo server to connect your meeting notes.")
                    .font(.caption)
                    .foregroundStyle(Color.revboMuted)
            } else if meetings.isEmpty && !isLoading {
                Text("No recent meetings found.")
                    .font(.caption)
                    .foregroundStyle(Color.revboMuted)
            } else {
                ForEach(meetings) { meeting in
                    GranolaMeetingRow(meeting: meeting, api: api, onResult: onResult)
                }
            }
        }
        .padding(16)
        .background(Color.revboSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.revboBlue.opacity(0.18), lineWidth: 1)
        )
        .task { await load() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let r = try await api.granolaListMeetings()
            configured = r.configured
            meetings   = r.meetings
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct GranolaMeetingRow: View {
    let meeting:  GranolaMeeting
    let api:      RevBoAPI
    let onResult: (RevBoResult) -> Void
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.revboText)
                    .lineLimit(1)
                if !meeting.date.isEmpty {
                    Text(meeting.shortDate)
                        .font(.caption2)
                        .foregroundStyle(Color.revboMuted)
                }
            }
            Spacer()
            if isImporting {
                ProgressView().tint(Color.revboBlue).scaleEffect(0.75)
            } else {
                Button {
                    Task { await importMeeting() }
                } label: {
                    Text("Import")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.revboBlue)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func importMeeting() async {
        isImporting = true
        defer { isImporting = false }
        do {
            let result = try await api.granolaImportMeeting(meetingId: meeting.id)
            onResult(result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GranolaMeeting: Identifiable, Decodable {
    let id:               String
    let title:            String
    let date:             String
    let duration_minutes: Int?
    let participants:     [String]

    var shortDate: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: date) ?? ISO8601DateFormatter().date(from: date) {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f.string(from: d)
        }
        return date
    }
}

struct ImportFileView: View {

    @StateObject private var api     = RevBoAPI()
    @StateObject private var whisper = WhispererService()
    @ObservedObject private var store = ContactAttributionStore.shared

    @State private var showPicker     = false
    @State private var selectedFile: URL?
    @State private var progress: Double = 0
    @State private var stage: String  = ""
    @State private var result: RevBoResult?
    @State private var isProcessing   = false
    @State private var errorMessage: String?
    @State private var suggestion: AttributionSuggestion?
    @State private var showContactPicker  = false
    @State private var pickerBrainId: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                if result == nil && !isProcessing {
                    Button { showPicker = true } label: {
                        VStack(spacing: 16) {
                            Image(systemName: "arrow.up.doc.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(Color.revboOrange)
                            Text("Tap to import a file")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("PDF · DOCX · PPTX · TXT · MD\nMP4 · MOV · WAV · M4A · VTT · SRT")
                                .font(.caption)
                                .foregroundStyle(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                        .background(Color(white: 0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(
                                    Color.revboOrange.opacity(0.4),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)

                    // ── Granola integration ───────────────────────────────────
                    GranolaSection { importedResult in
                        withAnimation {
                            progress = 1.0
                            stage    = "Stored in Brain ✓"
                            result   = importedResult
                        }
                        // Run attribution detection for Granola imports too
                        Task {
                            let s = await AttributionDetector.detect(
                                detectedEmails: importedResult.detected_emails ?? [],
                                detectedNames:  importedResult.detected_names  ?? [],
                                store:          store,
                                brainId:        importedResult.audit.brain_id
                            )
                            await MainActor.run {
                                suggestion = s
                                if s == nil {
                                    pickerBrainId    = importedResult.audit.brain_id
                                    showContactPicker = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // ── Connected services hint ───────────────────────────────
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.gray)
                        Text("Dropbox, Google Drive, iCloud and OneDrive appear in the Files sheet — just open the app and sign in first. Use Granola below to import call transcripts directly.")
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 32)
                }

                if isProcessing {
                    VStack(spacing: 18) {
                        if let file = selectedFile {
                            Label(file.lastPathComponent, systemImage: fileIcon(for: file))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(Color.revboOrange)
                        Text(stage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.revboOrange)
                            .animation(.easeInOut, value: stage)
                    }
                    .padding(24)
                    .background(Color(white: 0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 24)
                    .transition(.opacity)
                }

                if let result {
                    // Attribution suggestion (email or name match)
                    AttributionSuggestionBanner(suggestion: $suggestion)
                        .padding(.horizontal, 24)
                        .animation(.easeInOut(duration: 0.25), value: suggestion != nil)

                    ResultPanel(result: result, whisper: whisper)
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                    Button {
                        withAnimation {
                            self.result      = nil
                            self.progress    = 0
                            self.stage       = ""
                            self.selectedFile = nil
                        }
                    } label: {
                        Label("Import Another", systemImage: "plus.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.revboOrange)
                    }
                    .padding(.bottom, 8)
                }

                Spacer()
            }
        }
        .navigationTitle("Import File")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showPicker) {
            DocumentPicker { url in
                selectedFile = url
                Task { await process(url) }
            }
        }
        .sheet(isPresented: $showContactPicker) {
            if let id = pickerBrainId {
                AttributionContactPicker(brainId: id) { _ in }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func process(_ url: URL) async {
        isProcessing = true
        defer { isProcessing = false }

        async let animTask: Void = animateProgress()
        _ = await animTask

        do {
            let r = try await api.upload(fileURL: url) { p in
                Task { @MainActor in self.progress = p }
            }
            withAnimation {
                progress = 1.0
                stage    = "Stored in Brain ✓"
                result   = r
            }
            if whisper.isEnabled {
                whisper.speak(r.confirmation.joined(separator: ". "))
            }
            // Signal 1/2/3 — email or name detected in imported file.
            // Fall back to manual picker if nothing auto-matched.
            suggestion = await AttributionDetector.detect(
                detectedEmails: r.detected_emails ?? [],
                detectedNames:  r.detected_names  ?? [],
                store:          store,
                brainId:        r.audit.brain_id
            )
            if suggestion == nil {
                pickerBrainId    = r.audit.brain_id
                showContactPicker = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func animateProgress() async {
        let stages: [(Double, String)] = [
            (0.15, "Reading file…"),
            (0.35, "Extracting text…"),
            (0.55, "Scrubbing PII…"),
            (0.72, "Enriching firmographics…"),
            (0.88, "Hardcoding into Brain…"),
        ]
        for (target, label) in stages {
            withAnimation(.easeInOut(duration: 0.6)) {
                progress = target
                stage    = label
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }

    private func fileIcon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":                        return "doc.fill"
        case "pptx", "ppt":               return "play.rectangle.fill"
        case "docx", "doc":               return "doc.richtext.fill"
        case "mp4", "mov":                return "video.fill"
        case "wav", "m4a", "mp3", "aac":  return "waveform"
        case "vtt", "srt":                return "captions.bubble.fill"
        case "txt", "md", "csv":          return "doc.text.fill"
        case "eml":                        return "envelope.fill"
        default:                           return "doc.fill"
        }
    }
}
