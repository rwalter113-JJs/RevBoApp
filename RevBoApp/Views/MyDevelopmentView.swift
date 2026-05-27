import SwiftUI
import UniformTypeIdentifiers

// MARK: - My Development View
//
// Shows a user's personal coaching documents (performance reviews, 1:1 notes,
// coaching sessions) and lets them upload new ones or ask questions answered
// from their own development history.

struct MyDevelopmentView: View {

    @StateObject private var api      = RevBoAPI()
    @State private var docs:          [CoachingDoc] = []
    @State private var isLoading      = true
    @State private var showAddSheet   = false
    @State private var askQuery       = ""
    @State private var askResponse:   CoachingAskResponse?
    @State private var isAsking       = false
    @State private var answerExpanded = false
    @State private var successToast:  String?
    @State private var errorMessage:  String?
    @FocusState private var askFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ── Section header: My Documents ──────────────────────────
                    sectionHeader(icon: "person.fill.checkmark", label: "MY DOCUMENTS")
                        .padding(.top, 20)
                        .padding(.horizontal, 20)

                    // ── Documents list ────────────────────────────────────────
                    if isLoading {
                        ProgressView()
                            .tint(Color.revboOrange)
                            .padding(.vertical, 32)
                    } else if docs.isEmpty {
                        emptyDocsState
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(docs) { doc in
                                CoachingDocRow(doc: doc) {
                                    Task { await deleteDoc(doc) }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    }

                    // ── Add document button ───────────────────────────────────
                    Button {
                        showAddSheet = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Add Document", systemImage: "plus.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.black)
                            Spacer()
                        }
                        .frame(height: 48)
                        .background(Color.revboOrange)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                    // ── Divider ───────────────────────────────────────────────
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                        .padding(.top, 28)

                    // ── Section header: Ask Your Coach ────────────────────────
                    sectionHeader(icon: "sparkles", label: "ASK YOUR COACH")
                        .padding(.top, 20)
                        .padding(.horizontal, 20)

                    // ── Ask bar ───────────────────────────────────────────────
                    askBar
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                    // ── Answer card ───────────────────────────────────────────
                    if let resp = askResponse {
                        answerCard(resp)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Spacer(minLength: 60)
                }
            }

            // ── Toast overlay ─────────────────────────────────────────────────
            if let toast = successToast {
                toastBanner(toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(99)
            }
        }
        .navigationTitle("My Development")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .animation(.easeInOut(duration: 0.3), value: successToast)
        .animation(.easeInOut(duration: 0.3), value: askResponse != nil)
        .sheet(isPresented: $showAddSheet) {
            AddCoachingDocSheet { uploadedTitle in
                successToast = "Uploaded \u{201C}\(uploadedTitle)\u{201D}"
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    await MainActor.run { successToast = nil }
                }
                Task { await loadDocs() }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.revboSurface2)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .task { await loadDocs() }
    }

    // MARK: - Section header

    private func sectionHeader(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.revboOrange)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.revboMuted)
                .tracking(1.2)
            Spacer()
        }
    }

    // MARK: - Empty state

    private var emptyDocsState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.fill.checkmark")
                .font(.system(size: 40))
                .foregroundStyle(Color.revboOrange.opacity(0.35))
            Text("No documents yet")
                .font(.headline)
                .foregroundStyle(Color.revboText)
            Text("Upload a performance review or 1:1 notes to get started")
                .font(.callout)
                .foregroundStyle(Color.revboMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(Color.revboSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - Ask bar

    private var askBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your development...", text: $askQuery)
                .foregroundStyle(Color.revboText)
                .tint(Color.revboOrange)
                .focused($askFocused)
                .submitLabel(.send)
                .onSubmit { Task { await sendAsk() } }

            Button {
                Task { await sendAsk() }
            } label: {
                if isAsking {
                    ProgressView()
                        .tint(Color.revboOrange)
                        .frame(width: 36, height: 36)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(askQuery.isEmpty ? Color.revboSubtle : Color.revboOrange)
                        .frame(width: 36, height: 36)
                }
            }
            .disabled(askQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAsking)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color.revboSurface3)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1.5)
        )
    }

    // MARK: - Answer card

    private func answerCard(_ resp: CoachingAskResponse) -> some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(6)
                    .background(Color.revboOrange)
                    .clipShape(Circle())
                Text("COACHING ANSWER")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.revboOrange)
                    .tracking(1.1)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { answerExpanded.toggle() }
                } label: {
                    Image(systemName: answerExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.revboMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().background(Color.revboOrange.opacity(0.2))

            // Answer text
            Text(resp.answer)
                .font(.system(size: 14))
                .foregroundStyle(Color.revboText.opacity(0.88))
                .lineSpacing(3)
                .lineLimit(answerExpanded ? nil : 4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            // Sources
            if !resp.sources.isEmpty {
                Divider().background(Color.white.opacity(0.07))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(resp.sources.enumerated()), id: \.offset) { _, source in
                            SourceTag(source: source)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(Color.revboSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.revboOrange.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Toast banner

    private func toastBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.revboOrange)
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.revboText)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.revboSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.revboOrange.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .padding(.top, 56)
        .padding(.horizontal, 20)
    }

    // MARK: - Data loading

    private func loadDocs() async {
        isLoading = true
        defer { isLoading = false }
        if let response = try? await api.fetchCoachingDocs() {
            await MainActor.run { docs = response.docs }
        }
    }

    private func deleteDoc(_ doc: CoachingDoc) async {
        do {
            try await api.deleteCoachingDoc(docId: doc.doc_id)
            await MainActor.run {
                docs.removeAll { $0.doc_id == doc.doc_id }
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func sendAsk() async {
        let q = askQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isAsking else { return }
        isAsking   = true
        askFocused = false
        defer { isAsking = false }
        do {
            let resp = try await api.askCoaching(query: q)
            withAnimation { askResponse = resp; answerExpanded = false }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Source tag

private struct SourceTag: View {
    let source: CoachingSource

    private var icon: String {
        switch source.doc_type {
        case "review":           return "person.fill.checkmark"
        case "one_on_one":       return "person.2.fill"
        case "coaching_session": return "lightbulb.fill"
        default:                 return "doc.fill"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Color.revboOrange)
            Text(source.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.revboMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.revboOrange.opacity(0.08))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.revboOrange.opacity(0.20), lineWidth: 1))
    }
}

// MARK: - Coaching doc row

private struct CoachingDocRow: View {
    let doc:      CoachingDoc
    let onDelete: () -> Void

    private var icon: String {
        switch doc.doc_type {
        case "review":           return "person.fill.checkmark"
        case "one_on_one":       return "person.2.fill"
        case "coaching_session": return "lightbulb.fill"
        default:                 return "doc.fill"
        }
    }

    var body: some View {
        HStack(spacing: 14) {

            // Doc type icon
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.revboOrange)
                .frame(width: 36, height: 36)
                .background(Color.revboOrange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Title + preview
            VStack(alignment: .leading, spacing: 3) {
                Text(doc.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.revboText)
                    .lineLimit(1)
                if !doc.preview.isEmpty {
                    Text(doc.preview)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.revboMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // Chunk count badge
            Text("\(doc.chunk_count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.revboOrange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.revboOrange.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.revboSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add Coaching Doc Sheet

struct AddCoachingDocSheet: View {

    let onSuccess: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var api = RevBoAPI()

    // Form state
    @State private var title        = ""
    @State private var docType      = "review"
    @State private var bodyText     = ""
    @State private var isUploading  = false
    @State private var showImporter = false
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    private let docTypes: [(value: String, label: String)] = [
        ("review",           "Performance Review"),
        ("one_on_one",       "1:1 Notes"),
        ("coaching_session", "Coaching Session"),
        ("other",            "Other"),
    ]

    var canUpload: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.revboSurface2.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // ── Title field ───────────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            label("TITLE")
                            TextField("e.g. Q4 2024 Performance Review", text: $title)
                                .foregroundStyle(Color.revboText)
                                .tint(Color.revboOrange)
                                .focused($titleFocused)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .background(Color.revboSurface3)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                                )
                        }

                        // ── Doc type picker ───────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            label("DOCUMENT TYPE")
                            Menu {
                                ForEach(docTypes, id: \.value) { option in
                                    Button(option.label) { docType = option.value }
                                }
                            } label: {
                                HStack {
                                    Text(docTypes.first { $0.value == docType }?.label ?? "")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.revboText)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.revboMuted)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .background(Color.revboSurface3)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                                )
                            }
                        }

                        // ── Text editor ───────────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            label("CONTENT")
                            ZStack(alignment: .topLeading) {
                                if bodyText.isEmpty {
                                    Text("Paste or type the document content here…")
                                        .foregroundStyle(Color.revboSubtle)
                                        .font(.system(size: 14))
                                        .padding(.horizontal, 16)
                                        .padding(.top, 14)
                                        .allowsHitTesting(false)
                                }
                                TextEditor(text: $bodyText)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .foregroundStyle(Color.revboText)
                                    .font(.system(size: 14))
                                    .tint(Color.revboOrange)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                            }
                            .frame(minHeight: 200)
                            .background(Color.revboSurface3)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
                            )

                            // Char count
                            HStack {
                                Spacer()
                                Text("\(bodyText.count) chars")
                                    .font(.caption2)
                                    .foregroundStyle(Color.revboSubtle)
                            }
                        }

                        // ── File import button ────────────────────────────────
                        Button {
                            showImporter = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Import from Files (PDF / TXT)", systemImage: "arrow.up.doc")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.revboOrange)
                                Spacer()
                            }
                            .frame(height: 44)
                            .background(Color.revboOrange.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.revboOrange.opacity(0.30), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        // ── Upload button ─────────────────────────────────────
                        Button {
                            Task { await upload() }
                        } label: {
                            HStack {
                                Spacer()
                                if isUploading {
                                    ProgressView().tint(.black)
                                } else {
                                    Label("Upload to My Development", systemImage: "arrow.up.circle.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.black)
                                }
                                Spacer()
                            }
                            .frame(height: 52)
                            .background(canUpload ? Color.revboOrange : Color.gray)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(!canUpload || isUploading)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Add Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.revboOrange)
                        .disabled(isUploading)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf, .plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .onAppear { titleFocused = true }
        }
    }

    // MARK: - Helper label

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.revboMuted)
            .tracking(1.2)
    }

    // MARK: - File import handler

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else {
                errorMessage = "Couldn't read file."
                return
            }
            // Try UTF-8 first; fall back to lossy conversion.
            // The backend OCR pipeline handles raw PDF bytes too.
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? String(bytes: data, encoding: .ascii)
                ?? "(binary file — backend will OCR)"
            if bodyText.isEmpty {
                bodyText = text
            } else {
                bodyText += "\n\n" + text
            }
            // Auto-fill title from filename if blank
            if title.isEmpty {
                let name = url.deletingPathExtension().lastPathComponent
                title = name
            }
        }
    }

    // MARK: - Upload

    private func upload() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody  = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedBody.isEmpty, !isUploading else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            let req = CoachingDocUploadRequest(
                text:     trimmedBody,
                doc_type: docType,
                title:    trimmedTitle
            )
            _ = try await api.uploadCoachingDoc(req)
            dismiss()
            onSuccess(trimmedTitle)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
