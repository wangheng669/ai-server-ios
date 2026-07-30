import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var imageTask: URLSessionDataTask?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttemptContent = content

        guard let value = content.userInfo["image_url"] as? String,
              let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            finish(with: content)
            return
        }

        var urlRequest = URLRequest(url: url, timeoutInterval: 12)
        urlRequest.cachePolicy = .returnCacheDataElseLoad
        imageTask = URLSession.shared.dataTask(with: urlRequest) { [weak self] data, response, _ in
            guard let self, let data, !data.isEmpty else {
                self?.finish(with: content)
                return
            }
            let fileExtension = (response?.mimeType == "image/png") ? "png" : "jpg"
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            do {
                try data.write(to: fileURL, options: .atomic)
                let attachment = try UNNotificationAttachment(
                    identifier: "person-avatar",
                    url: fileURL
                )
                content.attachments = [attachment]
            } catch {
                // The text notification remains useful when an image is unavailable.
            }
            self.finish(with: content)
        }
        imageTask?.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        imageTask?.cancel()
        if let bestAttemptContent {
            finish(with: bestAttemptContent)
        }
    }

    private func finish(with content: UNNotificationContent) {
        guard let contentHandler else { return }
        self.contentHandler = nil
        contentHandler(content)
    }
}
