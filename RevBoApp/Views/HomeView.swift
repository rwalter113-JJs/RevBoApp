import SwiftUI
import AVFoundation

struct HomeView: View {

    // ── Navigation ────────────────────────────────────────────────────────────
    @State private var navPath      = NavigationPath()

    // ── Input bar state ───────────────────────────────────────────────────────
    @State private var barText      = ""
    @FocusState private var barFocused: Bool

    // ── Sheets / tips ─────────────────────────────────────────────────────────
    @State private var showAddToBrain  = false
    @State private var showTips        = false
    @State private var showSettings    = false

    // ── Recorder (voice query from home bar) ──────────────────────────────────
    @StateObject private var recorder  = AudioRecorder()

    // ── Onboarding ────────────────────────────────────────────────────────────
    @StateObject private var onboarding = OnboardingService.shared

    // ── My Development sheet ──────────────────────────────────────────────────
    @State private var showMyDevelopment = false

    // ── Routes ────────────────────────────────────────────────────────────────
    enum Route: Hashable {
        case contacts
        case addContact
        case ask(String)
        case note(String)
        case scan, listen, importFile
    }

    // ── Brand gradient (Orange → Amber → Carolina Blue) ───────────────────────
    static let brandGradient = LinearGradient(
        colors: [.revboOrange, .revboAmber, .revboBlue],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack {
                Color.revboBg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        // ── Wordmark + settings gear ──────────────────────────
                        ZStack(alignment: .topTrailing) {
                            VStack(spacing: 6) {
                                Text("RevBo")
                                    .font(.system(size: 44, weight: .black, design: .rounded))
                                    .foregroundStyle(HomeView.brandGradient)
                                Text("Your relationships & experience, in AI")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.revboMuted)
                            }
                            .frame(maxWidth: .infinity)

                            Button { showSettings = true } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.revboMuted)
                                    .padding(8)
                            }
                            .padding(.trailing, 20)
                            .padding(.top, 8)
                        }
                        .padding(.top, 48)
                        .padding(.bottom, 24)

                        // ── Ask Bo bar ────────────────────────────────────────
                        askBar
                            .padding(.horizontal, 20)

                        // ── Instruction strip ─────────────────────────────────
                        instructionStrip
                            .padding(.horizontal, 20)
                            .padding(.top, 10)

                        // ── Onboarding welcome card ───────────────────────────
                        if !onboarding.hasSeenOnboarding {
                            OnboardingWelcomeCard(service: onboarding)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                        }

                        // ── Daily nudge card ──────────────────────────────────
                        if onboarding.isNudgePeriodActive {
                            DailyNudgeCard(service: onboarding)
                                .padding(.horizontal, 20)
                                .padding(.top, onboarding.hasSeenOnboarding ? 8 : 0)
                        }

                        // ── Primary cards ─────────────────────────────────────
                        HStack(spacing: 14) {
                            HomeCard(symbol: "person.2.fill",  label: "My Contacts") {
                                navPath.append(Route.contacts)
                            }
                            HomeCard(symbol: "plus.circle.fill", label: "Add to Brain") {
                                showAddToBrain = true
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 28)

                        // ── My Development card ───────────────────────────────
                        HomeCard(symbol: "person.fill.checkmark", label: "My Development") {
                            showMyDevelopment = true
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                        // ── Quick-capture strip ───────────────────────────────
                        HStack(spacing: 24) {
                            QuickCaptureButton(symbol: "camera.viewfinder", label: "Scan")   { navPath.append(Route.scan) }
                            QuickCaptureButton(symbol: "mic.fill",          label: "Listen") { navPath.append(Route.listen) }
                        }
                        .padding(.top, 24)

                        // ── Upcoming meetings ─────────────────────────────────
                        UpcomingMeetingsStrip()
                            .padding(.top, 28)

                        Spacer(minLength: 48)
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .contacts:       ContactsTabView()
                case .addContact:     ContactsTabView(autoOpenPicker: true)
                case .ask(let q):     AskMyBrainView(initialQuery: q)
                case .note(let text): NewNoteView(initialText: text)
                case .scan:           ScanDeckView()
                case .listen:         QuickDictateView()
                case .importFile:     ImportFileView()
                }
            }
        }
        // ── Add to Brain sheet ────────────────────────────────────────────────
        .sheet(isPresented: $showAddToBrain) {
            AddToBrainSheet { route in
                showAddToBrain = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    navPath.append(route)
                }
            }
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.revboSurface2)
        }
        // ── Tips sheet ────────────────────────────────────────────────────────
        .sheet(isPresented: $showTips) {
            TipsSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.revboSurface2)
        }
        // ── Settings sheet ────────────────────────────────────────────────────
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        // ── My Development sheet ──────────────────────────────────────────────
        .sheet(isPresented: $showMyDevelopment) {
            NavigationStack {
                MyDevelopmentView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Ask bar

    private var askBar: some View {
        HStack(spacing: 10) {
            TextField("Ask Bo…", text: $barText)
                .foregroundStyle(Color.revboText)
                .tint(Color.revboOrange)
                .focused($barFocused)
                .submitLabel(.search)
                .onSubmit { commitQuery() }

            Button {
                barText.isEmpty ? toggleRecording() : commitQuery()
            } label: {
                Image(systemName: barText.isEmpty
                      ? (recorder.isRecording ? "stop.fill" : "mic.fill")
                      : "arrow.up.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(recorder.isRecording ? .white : Color.revboOrange)
                    .frame(width: 36, height: 36)
                    .background(recorder.isRecording ? Color.revboOrange : Color.clear)
                    .clipShape(Circle())
                    .animation(.spring(response: 0.25), value: recorder.isRecording)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color.revboSurface3)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    recorder.isRecording
                        ? Color.revboOrange.opacity(0.6)
                        : Color.white.opacity(0.07),
                    lineWidth: 1.5
                )
        )
        .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
    }

    // MARK: - Instruction strip

    private var instructionStrip: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(Color.revboBlue.opacity(0.8))
            Text("Try: ")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.revboMuted)
            +
            Text("\"What do I know about Nike?\"  ·  \"add Anna Haro\"  ·  \"note met with CMO\"")
                .font(.caption2)
                .foregroundStyle(Color.revboSubtle)

            Spacer(minLength: 4)

            Button { showTips = true } label: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Color.revboBlue.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.revboSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.revboBlue.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func commitQuery() {
        let q = barText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        barText    = ""
        barFocused = false
        navPath.append(parseIntent(q))
    }

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stop { url in
                Task { await MainActor.run { navPath.append(Route.ask("")) } }
            }
        } else {
            recorder.start()
        }
    }

    // ── Intent parser ─────────────────────────────────────────────────────────
    private func parseIntent(_ raw: String) -> Route {
        let t     = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased()

        // Add contact
        for prefix in ["add contact ", "add ", "track ", "new contact "] {
            if lower.hasPrefix(prefix) { return .addContact }
        }
        if ["new contact", "add contact"].contains(lower) { return .addContact }

        // Note / log
        for prefix in ["note ", "jot ", "log "] {
            if lower.hasPrefix(prefix) { return .note(String(t.dropFirst(prefix.count))) }
        }

        // Input shortcuts
        if ["scan","camera","scan a card","photo"].contains(lower) || lower.hasPrefix("scan ") { return .scan }
        if ["record","listen","voice","voice note","dictate"].contains(lower) || lower.hasPrefix("record ") { return .listen }

        // Import
        let importKW = ["import","upload","attach","bring in","load"]
        if importKW.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.contains(" " + $0 + " ") }) {
            return .importFile
        }

        if ["contacts","my contacts"].contains(lower) { return .contacts }

        return .ask(t)
    }
}

// MARK: - Tips sheet

private struct TipsSheet: View {

    private struct Tip: Identifiable {
        let id   = UUID()
        let icon:  String
        let color: Color
        let title: String
        let examples: [String]
    }

    private let tips: [Tip] = [
        Tip(icon: "brain.head.profile", color: .revboOrange,
            title: "Ask your Brain",
            examples: [
                "\"What do I know about SaaS pricing objections?\"",
                "\"Summarize successful calls with Fortune 500 retail companies\"",
                "\"How have I handled security concerns at banks?\""
            ]),
        Tip(icon: "person.badge.plus", color: .revboBlue,
            title: "Add a contact",
            examples: [
                "\"add Anna Haro\"",
                "\"track John Smith\"",
                "\"new contact\""
            ]),
        Tip(icon: "note.text", color: .revboAmber,
            title: "Log a note",
            examples: [
                "\"note met with CMO about Q3 budget\"",
                "\"log call with Nike — positive on pricing\"",
                "\"jot follow up with Kate re: pilot\""
            ]),
        Tip(icon: "arrow.up.doc.fill", color: .revboOrange,
            title: "Import a file",
            examples: [
                "\"import files from Dropbox\"",
                "\"upload the deck from iCloud\"",
                "\"import\" — then pick from Files"
            ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("How to use Bo")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.revboText)
                Spacer()
                Image(systemName: "sparkles")
                    .foregroundStyle(LinearGradient(
                        colors: [.revboOrange, .revboAmber, .revboBlue],
                        startPoint: .leading, endPoint: .trailing))
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider().background(Color.white.opacity(0.06))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    ForEach(tips) { tip in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: tip.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(tip.color)
                                    .frame(width: 28)
                                Text(tip.title)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.revboText)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(tip.examples, id: \.self) { ex in
                                    Text(ex)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.revboMuted)
                                        .padding(.leading, 38)
                                }
                            }
                        }
                        .padding(.horizontal, 24)

                        if tip.id != tips.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.05))
                                .padding(.horizontal, 24)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
        }
    }
}

// MARK: - Home card

private struct HomeCard: View {
    let symbol: String
    let label:  String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.revboOrange)
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.revboText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .background(Color.revboSurface2)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick capture button

private struct QuickCaptureButton: View {
    let symbol: String
    let label:  String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.revboSurface3)
                        .frame(width: 58, height: 58)
                        .overlay(Circle().stroke(Color.white.opacity(0.07), lineWidth: 1))
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.revboOrange)
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.revboMuted)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add to Brain sheet

private struct AddToBrainSheet: View {
    let onSelect: (HomeView.Route) -> Void

    private let options: [(String, String, HomeView.Route)] = [
        ("note.text",         "Note",   .note("")),
        ("camera.viewfinder", "Scan",   .scan),
        ("mic.fill",          "Listen", .listen),
        ("arrow.up.doc.fill", "Import", .importFile),
    ]

    var body: some View {
        VStack(spacing: 20) {
            Text("Add to Brain")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.revboText)
                .padding(.top, 8)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(options, id: \.1) { symbol, label, route in
                    Button { onSelect(route) } label: {
                        VStack(spacing: 10) {
                            Image(systemName: symbol)
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(Color.revboOrange)
                            Text(label)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.revboText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .background(Color.revboSurface3)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.07), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }
}

// MARK: - Brand colour system
// Source: revbo.ai/brand

extension Color {

    // Primary
    static let revboOrange = Color(hex: "#F97316")   // primary CTA / brand
    static let revboAmber  = Color(hex: "#FBBF24")   // gradient mid-stop
    static let revboBlue   = Color(hex: "#4B9CD3")   // Carolina Blue — secondary accent

    // Backgrounds
    static let revboBg       = Color(hex: "#0A0A0F")  // near-black canvas
    static let revboSurface  = Color(hex: "#111118")  // lowest surface
    static let revboSurface2 = Color(hex: "#18181F")  // cards, sheets
    static let revboSurface3 = Color(hex: "#1E1E28")  // inputs, inner surfaces

    // Typography
    static let revboText   = Color(hex: "#F0F0F5")   // primary text
    static let revboMuted  = Color(hex: "#8888A0")   // secondary text
    static let revboSubtle = Color(hex: "#55556A")   // placeholder / hints

    /// Initialise from a CSS hex string, e.g. "#F97316" or "F97316".
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        let val = UInt64(h, radix: 16) ?? 0
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >>  8) & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}
