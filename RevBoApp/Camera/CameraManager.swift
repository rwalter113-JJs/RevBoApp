import AVFoundation
import UIKit
import Combine

final class CameraManager: NSObject, ObservableObject {

    let session = AVCaptureSession()

    @Published var capturedImageData: Data?
    @Published var error: String?

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.revbo.camera.session")

    // MARK: - Setup

    func configure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                     for: .video,
                                                     position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                DispatchQueue.main.async { self.error = "Camera unavailable." }
                return
            }

            self.session.addInput(input)

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: - Capture

    func snap() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            DispatchQueue.main.async { self.error = error.localizedDescription }
            return
        }
        // Convert to JPEG and resize — physical iPhones capture in HEIC at
        // 12 MP+, which the backend Tesseract OCR cannot decode. We normalise
        // to JPEG ≤ 1920 px on the long edge before sending.
        guard let cgImage = photo.cgImageRepresentation() else { return }
        let uiImage  = UIImage(cgImage: cgImage,
                               scale: 1.0,
                               orientation: photoOrientation(photo))
        let resized  = uiImage.resizedToMaxDimension(1920)
        guard let jpegData = resized.jpegData(compressionQuality: 0.85) else { return }
        DispatchQueue.main.async { self.capturedImageData = jpegData }
    }

    /// Maps AVCapturePhoto metadata orientation to UIImage orientation so the
    /// image appears upright when the phone is held in portrait.
    private func photoOrientation(_ photo: AVCapturePhoto) -> UIImage.Orientation {
        guard
            let raw = photo.metadata[String(kCGImagePropertyOrientation)] as? UInt32,
            let cgOrient = CGImagePropertyOrientation(rawValue: raw)
        else { return .right }   // default portrait
        switch cgOrient {
        case .up:            return .up
        case .upMirrored:    return .upMirrored
        case .down:          return .down
        case .downMirrored:  return .downMirrored
        case .left:          return .left
        case .leftMirrored:  return .leftMirrored
        case .right:         return .right
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .right
        }
    }
}

// MARK: - UIImage resize helper

private extension UIImage {
    /// Returns a copy scaled so the longest edge is at most `maxDim` points.
    /// If the image already fits, returns self unchanged.
    func resizedToMaxDimension(_ maxDim: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDim else { return self }
        let scale   = maxDim / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
