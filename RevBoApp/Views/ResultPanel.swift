import SwiftUI

/// Shared result panel shown at the bottom of ScanDeckView and QuickDictateView.
struct ResultPanel: View {
    let result: RevBoResult
    @ObservedObject var whisper: WhispererService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Whisperer toggle
                HStack {
                    Label("Whisper via AirPods", systemImage: "airpodspro")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Spacer()
                    Toggle("", isOn: $whisper.isEnabled)
                        .tint(Color.revboOrange)
                        .onChange(of: whisper.isEnabled) { _, on in
                            if on { whisper.speak(result.confirmation.joined(separator: ". ")) }
                        }
                }

                Divider().background(Color.gray.opacity(0.3))

                // Confirmation checklist
                ForEach(result.confirmation, id: \.self) { message in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.revboOrange)
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                Divider().background(Color.gray.opacity(0.3))

                // Scrubbed text preview
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scrubbed Text")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Text(result.scrubbed_text)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.revboOrange.opacity(0.9))
                }

                // Brain ID
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(Color.revboOrange)
                    Text("Brain ID: \(result.audit.brain_id.prefix(8))…")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
            .padding(20)
        }
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}
