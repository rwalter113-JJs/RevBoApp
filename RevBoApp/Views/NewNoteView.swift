import SwiftUI
import AVFoundation

// MARK: - New Note View
// Unified note creation: Type or Voice, with optional pre-attributed contact.
// Signal 1 auto-attribution fires on the text path when a tracked email is detected.

struct NewNoteView: View {

    /// Optional contact passed from ContactDetailView — record will be
    /// attributed to this contact regardless of input mode.
    var preAttributedContact: TrackedContact? = nil

    /// Pre-populate the text field — used when the user dictates a note
    /// via the Ask Bo bar, e.g. "note I met with Anna about renewal".
    var initialText: String = ""

    @StateObject private var api      = RevBoAPI()
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var whisper  = WhispererService()
    @ObservedObject private var store = ContactAttributionStore.shared
    @Environment(\.dismiss) private var dismiss

    enum InputMode { case type, voice }
    @State private var mode: InputMode = .type

    // Text-mode state
    @State private var noteText = ""
    @FocusState private var fieldFocused: Bool

    // Voice-mode state
    @State private var transcript: String?
    @State private var isUploading = false

    // Shared state
    @State private var result: RevBoResult?
    @State private var errorMessage: String?

    // Auto-attribution (Signal 1 — text mode only; pre-set contact overrides)
    @State private var detectedHash:     String?
    @State private var detectedContact:  TrackedContact?
    @State private var showAttribBanner  = false

    // Post-result attribution suggestion (voice mode — Signal 1 email + Signal 2 name)
    @State private var suggestion: AttributionSuggestion?
    @State private var showContactPicker  = false
    @State private var pickerBrainId: String?

    // ── Resolved attribution ──────────────────────────────────────────────────
    // Pre-attributed contact always wins; Signal 1 detection fills in otherwise.
    private var resolvedHash: String? { preAttributedContact?.hash ?? detectedHash }
    private var resolvedMethod: String {
        if preAttributedContact != nil { return "manual" }    // user opened from contact page
        if detectedHash != nil { return "auto_email" }        // Signal 1 fired
        return "manual"
    }
    private var resolvedContact: TrackedContact? { preAttributedContact ?? detectedContact }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Mode picker ──────────────────────────────────────────────
                Picker("Input mode", selection: $mode) {
                    Label("Type", systemImage: "keyboard").tag(InputMode.type)
                    Label("Voice", systemImage: "mic.fill").tag(InputMode.voice)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .onChange(of: mode) { _, _ in
                    // Reset result when switching modes
                    result     = nil
                    transcript = nil
                    noteText   = ""
                    fieldFocused = false
                }

                // ── Attribution banner ───────────────────────────────────────
                if let contact = resolvedContact, result == nil {
                    attributionBanner(contact: contact, isPre: preAttributedContact != nil)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // ── Content ──────────────────────────────────────────────────
                if result == nil {
                    switch mode {
                    case .type:  typePanel
                    case .voice: voicePanel
                    }
                } else {
                    resultView
                }

                Spacer(minLength: 0)
            }
        }
        .navigationTitle(preAttributedContact != nil
                         ? "Note for \(preAttributedContact!.displayName)"
                         : "New Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            // Done button — only shown when presented as a sheet (preAttributedContact set).
            // Disabled while a voice upload is in-flight so the sheet can't close before
            // the note is stored, which would make refreshStats() miss the new record.
            if preAttributedContact != nil {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(isUploading ? Color.gray : Color.revboOrange)
                        .disabled(isUploading)
                }
            }
            if !noteText.isEmpty && result == nil && mode == .type {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") { clearText() }
                        .foregroundStyle(Color.revboOrange)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showAttribBanner)
        .animation(.easeInOut(duration: 0.25), value: mode)
        .animation(.easeInOut(duration: 0.35), value: result != nil)
        .sheet(isPresented: $showContactPicker) {
            if let id = pickerBrainId {
                AttributionContactPicker(brainId: id) { _ in }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onAppear {
            if !initialText.isEmpty { noteText = initialText }
            if mode == .type { fieldFocused = true }
        }
    }

    // MARK: - Type panel

    private var typePanel: some View {
        VStack(spacing: 0) {
            // Text editor
            ZStack(alignment: .topLeading) {
                if noteText.isEmpty {
                    Text("Paste or type a note, email, call log…")
                        .foregroundStyle(.gray.opacity(0.5))
                        .font(.system(size: 15))
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $noteText)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .foregroundStyle(.white)
                    .font(.system(size: 15))
                    .tint(Color.revboOrange)
                    .focused($fieldFocused)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .onChange(of: noteText) { _, v in
                        if preAttributedContact == nil { runSignal1(v) }
                    }
            }
            .frame(minHeight: 180)
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Char count
            HStack {
                Spacer()
                Text("\(noteText.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

            // Store button
            storeButton(
                label: "Scrub & Store in Brain",
                icon: "brain.head.profile",
                disabled: noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                loading: false
            ) {
                Task { await storeText() }
            }
        }
    }

    // MARK: - Voice panel

    private var voicePanel: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 20)

            Text(voiceStatusLabel)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.gray)
                .animation(.easeInOut, value: recorder.isRecording)

            // Record button
            Button {
                if recorder.isRecording {
                    recorder.stop { url in Task { await uploadVoice(url) } }
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

            Text(recorder.isRecording ? "Tap to stop & store" : "Tap to start recording")
                .font(.caption)
                .foregroundStyle(.gray)

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

            Spacer(minLength: 0)
        }
    }

    // MARK: - Result view

    private var resultView: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Attribution confirmation (shown after store)
                if let contact = resolvedContact {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color.revboOrange)
                            .font(.callout)
                        Text("Attributed to \(contact.displayName)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.revboOrange.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.revboOrange.opacity(0.30), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                }

                // Attribution suggestion for voice notes (no pre-set contact)
                if suggestion != nil {
                    AttributionSuggestionBanner(suggestion: $suggestion)
                        .padding(.horizontal, 16)
                        .animation(.easeInOut(duration: 0.25), value: suggestion != nil)
                }

                if let result {
                    ResultPanel(result: result, whisper: whisper)
                }

                // Log another
                storeButton(
                    label: "Log Another Note",
                    icon: "plus",
                    disabled: false,
                    loading: false
                ) {
                    result     = nil
                    transcript = nil
                    noteText   = ""
                    if mode == .type { fieldFocused = true }
                }
                .padding(.horizontal, 0)
            }
            .padding(.top, 12)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Shared store button

    private func storeButton(
        label: String,
        icon: String,
        disabled: Bool,
        loading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                if loading {
                    ProgressView().tint(.black)
                } else {
                    Label(label, systemImage: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                }
                Spacer()
            }
            .frame(height: 50)
            .background(disabled ? Color.gray : Color.revboOrange)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(disabled || loading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - Attribution banner

    @ViewBuilder
    private func attributionBanner(contact: TrackedContact, isPre: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isPre ? "person.fill.checkmark" : "person.fill.checkmark")
                .font(.caption)
                .foregroundStyle(Color.revboOrange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Attributed to \(contact.displayName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text(isPre
                     ? "This note will be linked to this contact"
                     : "Email detected · will be linked automatically")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            Spacer()
            if !isPre {
                Button {
                    detectedHash    = nil
                    detectedContact = nil
                    showAttribBanner = false
                } label: {
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
    }

    // MARK: - Signal 1: email auto-detection (text mode only)

    private func runSignal1(_ text: String) {
        let hashes = ContactHashService.shared.detectContactHashes(in: text, registry: store)
        if let firstHash = hashes.first, let contact = store.contact(forHash: firstHash) {
            detectedHash    = firstHash
            detectedContact = contact
            showAttribBanner = true
        } else {
            detectedHash    = nil
            detectedContact = nil
            showAttribBanner = false
        }
    }

    // MARK: - Store (text)

    private func storeText() async {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        fieldFocused = false
        do {
            let r = try await api.processText(
                trimmed,
                contactHash: resolvedHash,
                attributionMethod: resolvedMethod
            )
            withAnimation { result = r; noteText = "" }
            if whisper.isEnabled {
                whisper.speak(r.confirmation.joined(separator: ". "))
            }
            // If no pre-attribution and Signal 1 (email) didn't fire, offer manual picker
            if resolvedHash == nil {
                pickerBrainId    = r.audit.brain_id
                showContactPicker = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Store (voice)

    private func uploadVoice(_ url: URL?) async {
        guard let url else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            let (t, r) = try await api.listen(
                audioURL: url,
                contactHash: resolvedHash,
                attributionMethod: resolvedMethod
            )
            withAnimation { transcript = t; result = r }
            if whisper.isEnabled, let r {
                whisper.speak(r.confirmation.joined(separator: ". "))
            }
            // Signal 1/2/3 — only when not already pre-attributed.
            // Fall back to manual picker if nothing matched.
            if preAttributedContact == nil, let r {
                suggestion = await AttributionDetector.detect(
                    detectedEmails: r.detected_emails ?? [],
                    detectedNames:  r.detected_names  ?? [],
                    store:          store,
                    brainId:        r.audit.brain_id
                )
                if suggestion == nil && resolvedHash == nil {
                    pickerBrainId    = r.audit.brain_id
                    showContactPicker = true
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private var voiceStatusLabel: String {
        if recorder.isRecording { return "Listening…" }
        if isUploading           { return "Processing…" }
        if result != nil         { return "Stored in Brain ✓" }
        return "Ready to record"
    }

    private func clearText() {
        noteText         = ""
        detectedHash     = nil
        detectedContact  = nil
        showAttribBanner = false
    }
}
