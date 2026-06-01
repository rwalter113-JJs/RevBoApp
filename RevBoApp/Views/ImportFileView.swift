import SwiftUI

struct ImportFileView: View {

    @StateObject private var api     = RevBoAPI()
    @StateObject private var whisper = WhispererService()
    @ObservedObject private var store = ContactAttributionStore.shared

    @State private var showPicker        = false
    @State private var showFolderPicker  = false
    @State private var selectedFile: URL?
    @State private var progress: Double  = 0
    @State private var stage: String     = ""
    @State private var result: RevBoResult?
    @State private var isProcessing      = false
    @State private var errorMessage: String?
    @State private var suggestion: AttributionSuggestion?
    @State private var showContactPicker = false
    @State private var pickerBrainId: String?

    // Batch state
    @State private var batchFiles:     [URL] = []
    @State private var batchIndex:     Int   = 0
    @State private var batchSucceeded: Int   = 0
    @State private var batchFailed:    Int   = 0
    @State private var isBatchDone     = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                if result == nil && !isProcessing && !isBatchDone && batchFiles.isEmpty {
                    // ── Single file ───────────────────────────────────────────
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
                        .padding(.vertical, 40)
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

                    // ── Folder import ─────────────────────────────────────────
                    Button { showFolderPicker = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill.badge.plus")
                                .font(.system(size: 22))
                                .foregroundStyle(Color.revboOrange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Import entire folder")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("All supported files processed at once")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.revboSubtle)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(Color(white: 0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
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

                // ── Single file progress ──────────────────────────────────────
                if isProcessing && batchFiles.isEmpty {
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

                // ── Batch / folder progress ───────────────────────────────────
                if !batchFiles.isEmpty || isBatchDone {
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.revboOrange)
                            Text(isBatchDone ? "Folder import complete" : "Importing folder…")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer()
                        }

                        if !isBatchDone {
                            ProgressView(value: Double(batchIndex), total: Double(batchFiles.count))
                                .progressViewStyle(.linear)
                                .tint(Color.revboOrange)
                            if let file = batchFiles[safe: batchIndex] {
                                Text(file.lastPathComponent)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.gray)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Text("\(batchIndex) of \(batchFiles.count) files")
                                .font(.caption)
                                .foregroundStyle(Color.revboMuted)
                        }

                        if isBatchDone {
                            HStack(spacing: 20) {
                                Label("\(batchSucceeded) stored", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 13, weight: .medium))
                                if batchFailed > 0 {
                                    Label("\(batchFailed) failed", systemImage: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                        .font(.system(size: 13, weight: .medium))
                                }
                            }
                            Button {
                                withAnimation {
                                    batchFiles   = []
                                    batchIndex   = 0
                                    batchSucceeded = 0
                                    batchFailed  = 0
                                    isBatchDone  = false
                                }
                            } label: {
                                Label("Import Another Folder", systemImage: "folder.badge.plus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.revboOrange)
                            }
                        }
                    }
                    .padding(20)
                    .background(Color(white: 0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
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
        .sheet(isPresented: $showFolderPicker) {
            FolderPicker { urls in
                guard !urls.isEmpty else { return }
                batchFiles     = urls
                batchIndex     = 0
                batchSucceeded = 0
                batchFailed    = 0
                isBatchDone    = false
                Task { await processBatch(urls) }
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

    private func processBatch(_ urls: [URL]) async {
        for (idx, url) in urls.enumerated() {
            await MainActor.run { batchIndex = idx }
            do {
                _ = try await api.upload(fileURL: url) { _ in }
                await MainActor.run { batchSucceeded += 1 }
            } catch {
                await MainActor.run { batchFailed += 1 }
            }
            // Small pause so progress feels tangible
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        await MainActor.run {
            batchIndex  = urls.count
            isBatchDone = true
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
