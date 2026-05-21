import SwiftUI

struct ScanDeckView: View {

    @StateObject private var camera  = CameraManager()
    @StateObject private var api     = RevBoAPI()
    @StateObject private var whisper = WhispererService()
    @ObservedObject private var store = ContactAttributionStore.shared

    @State private var result: RevBoResult?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var suggestion: AttributionSuggestion?
    @State private var showContactPicker  = false
    @State private var pickerBrainId: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Live viewfinder ──────────────────────────────────────
                ZStack(alignment: .bottom) {
                    CameraBridge(session: camera.session)
                        .ignoresSafeArea(edges: .top)

                    // Snap button
                    if result == nil && !isProcessing {
                        Button {
                            camera.snap()
                        } label: {
                            ZStack {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 4)
                                    .frame(width: 72, height: 72)
                                Circle()
                                    .fill(Color.revboOrange)
                                    .frame(width: 58, height: 58)
                            }
                        }
                        .padding(.bottom, 24)
                    }

                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.4)
                            .padding(.bottom, 32)
                    }

                    // Content-type badge — shown once result arrives
                    if let result, !isProcessing {
                        let tag = contentTypeTag(result)
                        HStack(spacing: 6) {
                            Text(tag.icon)
                                .font(.system(size: 13))
                            Text(tag.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.top, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 16)
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                .frame(maxHeight: result == nil ? .infinity : 240)
                .animation(.easeInOut(duration: 0.35), value: result != nil)

                // ── Attribution suggestion ───────────────────────────────
                if suggestion != nil {
                    AttributionSuggestionBanner(suggestion: $suggestion)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .animation(.easeInOut(duration: 0.25), value: suggestion != nil)
                }

                // ── Result panel ─────────────────────────────────────────
                if let result {
                    ResultPanel(result: result, whisper: whisper)
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                    // Scan Again
                    Button {
                        withAnimation {
                            self.result     = nil
                            self.suggestion = nil
                            camera.capturedImageData = nil
                        }
                    } label: {
                        Label("Scan Again", systemImage: "camera.viewfinder")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.revboOrange)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear  { camera.configure() }
        .onDisappear { camera.stop() }
        // When camera captures a photo, send it to the API
        .onChange(of: camera.capturedImageData) { _, data in
            guard let data else { return }
            Task { await process(imageData: data) }
        }
        .sheet(isPresented: $showContactPicker) {
            if let id = pickerBrainId {
                AttributionContactPicker(brainId: id) { _ in }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Content-type detection

    private struct ContentTag { let icon: String; let label: String }

    /// Classifies what was scanned based on text patterns and detected fields.
    private func contentTypeTag(_ r: RevBoResult) -> ContentTag {
        let text  = r.scrubbed_text.lowercased()
        let emails = r.detected_emails ?? []
        let names  = r.detected_names  ?? []

        // Business card: name + email/phone on a compact block
        let hasPhone = text.contains(try! Regex("[0-9]{3}[.\\-\\s][0-9]{3}[.\\-\\s][0-9]{4}"))
        if !emails.isEmpty && (!names.isEmpty || hasPhone) && text.count < 800 {
            return ContentTag(icon: "📇", label: "Business Card")
        }

        // Email: classic header patterns
        if text.contains("from:") || text.contains("to:") || text.contains("subject:") {
            return ContentTag(icon: "✉️", label: "Email")
        }

        // Slide deck: lots of short lines / bullet-heavy, typical deck word density
        let lines       = r.scrubbed_text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let avgLineLen  = lines.isEmpty ? 0 : lines.map(\.count).reduce(0, +) / lines.count
        if lines.count >= 6 && avgLineLen < 60 {
            return ContentTag(icon: "📊", label: "Presentation")
        }

        // Whitepaper / report: long-form dense text
        if text.count > 1500 {
            return ContentTag(icon: "📄", label: "Document")
        }

        // Receipt / invoice
        if text.contains("total") && (text.contains("$") || text.contains("invoice") || text.contains("receipt")) {
            return ContentTag(icon: "🧾", label: "Receipt")
        }

        return ContentTag(icon: "📝", label: "Note")
    }

    // MARK: - Pipeline call

    private func process(imageData: Data) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let r = try await api.processImage(imageData)
            withAnimation { result = r }
            if whisper.isEnabled {
                whisper.speak(r.confirmation.joined(separator: ". "))
            }
            // Signal 1/2/3 — email or name detected in scanned image.
            // Fall back to manual picker if nothing matched.
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
}
