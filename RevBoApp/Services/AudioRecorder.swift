import AVFoundation
import Combine

final class AudioRecorder: NSObject, ObservableObject {

    @Published var isRecording = false

    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private var completion: ((URL?) -> Void)?

    // MARK: - Start

    func start() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey:         Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey:       16_000,          // 16 kHz — optimal for speech recognition
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
            try AVAudioSession.sharedInstance().setActive(true)
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.record()
            outputURL = url
            DispatchQueue.main.async { self.isRecording = true }
        } catch {
            print("AudioRecorder start error: \(error)")
        }
    }

    // MARK: - Stop

    func stop(completion: @escaping (URL?) -> Void) {
        self.completion = completion
        recorder?.stop()
        DispatchQueue.main.async { self.isRecording = false }
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder,
                                          successfully flag: Bool) {
        completion?(flag ? outputURL : nil)
        completion = nil
    }
}
