import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private var imageData: Data?
    private let uploadLabel = UILabel()
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        extractImage()
    }

    private func setupUI() {
        view.backgroundColor = .black

        // RevBo branding
        let logoLabel = UILabel()
        logoLabel.text = "RevBo"
        logoLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        logoLabel.textColor = UIColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0) // revboOrange
        logoLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logoLabel)

        uploadLabel.text = "Uploading image..."
        uploadLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        uploadLabel.textColor = .white
        uploadLabel.textAlignment = .center
        uploadLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(uploadLabel)

        statusLabel.text = ""
        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.textColor = .gray
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        activityIndicator.color = UIColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            logoLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 40),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),

            uploadLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            uploadLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 20),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: uploadLabel.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
        ])

        activityIndicator.startAnimating()
    }

    private func extractImage() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            showError("No image found")
            return
        }

        // Try to load image data
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] (item, error) in
                guard let self = self else { return }

                if let error = error {
                    DispatchQueue.main.async {
                        self.showError("Failed to load image: \(error.localizedDescription)")
                    }
                    return
                }

                var data: Data?

                if let url = item as? URL {
                    data = try? Data(contentsOf: url)
                } else if let image = item as? UIImage {
                    data = image.jpegData(compressionQuality: 0.9)
                } else if let imageData = item as? Data {
                    data = imageData
                }

                if let imageData = data {
                    DispatchQueue.main.async {
                        self.imageData = imageData
                        self.uploadImage(imageData)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.showError("Unsupported image format")
                    }
                }
            }
        } else {
            showError("Item is not an image")
        }
    }

    private func uploadImage(_ data: Data) {
        // Access shared AppSettings via App Group
        let userDefaults = UserDefaults(suiteName: "group.com.robwalter.revbo")
        let serverURL = userDefaults?.string(forKey: "revbo.serverURL") ?? "https://revbo-engine-production.up.railway.app"
        let apiKey = "B49116A8-A5AF-457D-8376-F18806C07E4A"
        let userID = userDefaults?.string(forKey: "revbo.userID") ?? "default"

        guard let url = URL(string: "\(serverURL)/v1/process-image") else {
            showError("Invalid server URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-RevBo-Key")
        request.setValue(userID, forHTTPHeaderField: "X-RevBo-User-ID")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"share.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()

                if let error = error {
                    self.showError("Upload failed: \(error.localizedDescription)")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        self.uploadLabel.text = "✓ Uploaded to RevBo"
                        self.statusLabel.text = "Image processed and added to your brain"
                        self.statusLabel.textColor = UIColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 1.0)

                        // Auto-dismiss after 1.5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                        }
                    } else {
                        self.showError("Upload failed with status \(httpResponse.statusCode)")
                    }
                } else {
                    self.showError("Invalid response from server")
                }
            }
        }

        task.resume()
    }

    private func showError(_ message: String) {
        activityIndicator.stopAnimating()
        uploadLabel.text = "Upload failed"
        statusLabel.text = message
        statusLabel.textColor = .red

        // Auto-dismiss after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
