import SwiftUI

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

                    // ── Connected services hint ───────────────────────────────
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.gray)
                        Text("Dropbox, Google Drive, iCloud and OneDrive appear in the Files sheet — just open the app and sign in first. You can also forward Granola notes to your RevBo email address (see Settings).")
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
