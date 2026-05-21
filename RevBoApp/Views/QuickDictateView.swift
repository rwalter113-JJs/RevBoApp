import SwiftUI
import AVFoundation

struct QuickDictateView: View {

    @StateObject private var recorder = AudioRecorder()
    @StateObject private var api      = RevBoAPI()
    @StateObject private var whisper  = WhispererService()
    @ObservedObject private var store = ContactAttributionStore.shared

    @State private var result: RevBoResult?
    @State private var transcript: String?
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var suggestion: AttributionSuggestion?
    @State private var showContactPicker = false
    @State private var pickerBrainId: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {

                Spacer()

                // ── Status label ─────────────────────────────────────────
                Text(statusLabel)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.gray)
                    .animation(.easeInOut, value: recorder.isRecording)

                // ── Tap-to-toggle button ──────────────────────────────────
                Button {
                    if recorder.isRecording {
                        recorder.stop { url in
                            Task { await upload(url) }
                        }
                    } else {
                        result     = nil
                        transcript = nil
                        recorder.start()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(recorder.isRecording ? Color.revboOrange : Color(white: 0.18))
                            .frame(width: 120, height: 120)
                            .scaleEffect(recorder.isRecording ? 1.12 : 1.0)
                            .animation(.spring(response: 0.3), value: recorder.isRecording)

                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isUploading)

                Text(recorder.isRecording ? "Tap to stop & send" : "Tap to start recording")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .animation(.easeInOut, value: recorder.isRecording)

                // ── Transcript ───────────────────────────────────────────
                if let transcript {
                    Text("\u{201C}\(transcript)\u{201D}")
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .transition(.opacity)
                }

                if isUploading {
                    ProgressView().tint(Color.revboOrange)
                }

                // ── Attribution suggestion ───────────────────────────────
                AttributionSuggestionBanner(suggestion: $suggestion)
                    .padding(.horizontal, 24)
                    .animation(.easeInOut(duration: 0.25), value: suggestion != nil)

                // ── Result panel ─────────────────────────────────────────
                if let result {
                    ResultPanel(result: result, whisper: whisper)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer()
            }
        }
        .navigationTitle("Listen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showContactPicker) {
            if let id = pickerBrainId {
                AttributionContactPicker(brainId: id) { _ in }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Helpers

    private var statusLabel: String {
        if recorder.isRecording { return "Listening…" }
        if isUploading           { return "Processing…" }
        if result != nil         { return "Stored in Brain ✓" }
        return "Ready"
    }

    private func upload(_ url: URL?) async {
        guard let url else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            let (t, r) = try await api.listen(audioURL: url)
            withAnimation {
                transcript = t
                result     = r
            }
            if whisper.isEnabled, let r {
                whisper.speak(r.confirmation.joined(separator: ". "))
            }
            // Signal 1/2/3 — suggest attribution if a contact matches.
            // If nothing matched, slide up the manual contact picker.
            if let r {
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
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
