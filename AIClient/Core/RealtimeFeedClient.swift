import Foundation

@MainActor
final class RealtimeFeedClient {
    enum Event {
        case post(Post)
        case taskCompleted(String)
        case deploymentStatus(DeploymentStatusSnapshot)
    }

    private let baseURL: URL
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, Never>?
    private var isActive = false
    private var retryAttempt = 0
    var onEvent: ((Event) -> Void)?

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        connect()
    }

    func stop() {
        isActive = false
        connectionTask?.cancel()
        connectionTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func connect() {
        guard isActive, connectionTask == nil, let url = Self.webSocketURL(from: baseURL) else { return }
        connectionTask = Task { [weak self] in
            guard let self else { return }
            let task = session.webSocketTask(with: url)
            socket = task
            task.resume()

            do {
                try await task.send(.string(#"{"type":"request-task-snapshot"}"#))
                try await task.send(.string(#"{"type":"request-deployment-snapshot"}"#))
                retryAttempt = 0
                while isActive, !Task.isCancelled {
                    let message = try await task.receive()
                    handle(message)
                }
            } catch {
                // A closed socket is expected while the app is backgrounded or the server restarts.
            }

            task.cancel(with: .goingAway, reason: nil)
            if socket === task { socket = nil }
            connectionTask = nil
            await reconnectAfterDelay()
        }
    }

    private func reconnectAfterDelay() async {
        guard isActive, !Task.isCancelled else { return }
        let delay = min(8.0, 0.5 * pow(1.5, Double(retryAttempt)))
        retryAttempt += 1
        try? await Task.sleep(for: .seconds(delay))
        guard isActive, !Task.isCancelled else { return }
        connect()
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .data(let value): data = value
        case .string(let value): data = value.data(using: .utf8)
        @unknown default: data = nil
        }
        guard let data, let header = try? JSONDecoder().decode(MessageHeader.self, from: data) else { return }

        if header.type == "post", let post = try? JSONDecoder().decode(Post.self, from: data) {
            onEvent?(.post(post))
        } else if header.type == "task",
                  header.state == "idle",
                  header.skipped != true,
                  let name = header.name {
            onEvent?(.taskCompleted(name))
        } else if header.type == "deployment-status",
                  let message = try? JSONDecoder().decode(DeploymentStatusMessage.self, from: data),
                  let snapshot = DeploymentStatusSnapshot(message: message) {
            onEvent?(.deploymentStatus(snapshot))
        }
    }

    nonisolated static func webSocketURL(from baseURL: URL) -> URL? {
        guard var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        switch parts.scheme?.lowercased() {
        case "http": parts.scheme = "ws"
        case "https": parts.scheme = "wss"
        default: return nil
        }
        parts.path = "/post"
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }
}

private struct MessageHeader: Decodable {
    let type: String
    let name: String?
    let state: String?
    let skipped: Bool?
}
