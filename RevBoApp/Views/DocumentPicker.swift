import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FolderPicker: UIViewControllerRepresentable {

    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let folderURL = urls.first else { return }
            guard folderURL.startAccessingSecurityScopedResource() else { return }
            defer { folderURL.stopAccessingSecurityScopedResource() }

            let supported: Set<String> = [
                "pdf","docx","doc","pptx","ppt","txt","md","csv","vtt","srt","eml",
                "mp4","mov","wav","m4a","mp3","aac"
            ]
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return }

            var files: [URL] = []
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                if supported.contains(ext) {
                    // Copy to temp so access survives picker dismissal
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(ext)
                    try? fm.copyItem(at: fileURL, to: tmp)
                    files.append(tmp)
                }
            }
            onPick(files)
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {

    let onPick: (URL) -> Void

    // All file types the RevBo backend can handle
    private let supportedTypes: [UTType] = [
        // Documents
        .pdf,
        .presentation,          // .pptx
        .spreadsheet,           // .csv
        UTType("com.microsoft.word.doc")   ?? .data,   // .docx
        UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
        // Plain text / transcripts / notes / email
        .plainText,             // .txt
        .text,
        UTType("net.daringfireball.markdown") ?? .plainText,  // .md
        UTType("public.vtt")    ?? .plainText,  // WebVTT transcripts
        UTType("public.srt")    ?? .plainText,  // SRT transcripts
        UTType("com.apple.mail.emlx") ?? .data, // .eml
        // Audio
        .audio,
        .wav,
        .mpeg4Audio,            // .m4a
        UTType("public.mp3")    ?? .audio,
        UTType("com.apple.coreaudio-format") ?? .audio,  // .aac
        // Video
        .mpeg4Movie,            // .mp4
        .movie,                 // .mov
        .video,
    ]

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: supportedTypes,
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController,
                                context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
