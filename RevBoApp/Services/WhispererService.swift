import AVFoundation
import Combine

final class WhispererService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    @Published var isEnabled: Bool = false
    @Published var isSpeaking: Bool = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Speak

    func speak(_ text: String) {
        guard isEnabled, !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate       = AVSpeechUtteranceDefaultSpeechRate * 0.92  // slightly slower
        utterance.pitchMultiplier = 0.95
        utterance.volume     = 0.9
        // Prefer a natural English voice (works well through AirPods)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.allowBluetoothHFP, .allowAirPlay]   // routes to AirPods automatically
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("WhispererService audio session error: \(error)")
        }

        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                            didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                            didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}
