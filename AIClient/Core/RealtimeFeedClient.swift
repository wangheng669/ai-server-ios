import Foundation

@MainActor
final class RealtimeFeedClient {
    enum Scope: Equatable { case feed, deployment }

    enum Event {
        case post(Post)
        case taskCompleted(String)
        case deploymentStatus(DeploymentStatusSnapshot)
    }

    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    private var socket: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, Never>?
    var onEvent: ((Event) -> Void)?

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    deinit {
        connectionTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
    }

    func start(scope: Scope = .feed) {
        guard connectionTask == nil, let url = Self.webSocketURL(from: baseURL) else { return }
        connectionTask = Task { [weak self, session] in
            var reconnectDelay = 0.5
            while !Task.isCancelled, self != nil {
                let task = session.webSocketTask(with: url)
                self?.socket = task
                task.resume()

                do {
                    if scope == .deployment {
                        // The server subscribes to live updates after sending its initial snapshot.
                        try await task.send(.string(#"{"type":"request-deployment-snapshot"}"#))
                    }
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        guard !Task.isCancelled, let self else { break }
                        reconnectDelay = 0.5
                        self.handle(message, scope: scope)
                    }
                } catch {
                    // A closed socket is expected while the app is backgrounded or the server restarts.
                }

                task.cancel(with: .goingAway, reason: nil)
                if self?.socket === task { self?.socket = nil }
                guard !Task.isCancelled, self != nil else { return }
                try? await Task.sleep(for: .seconds(reconnectDelay))
                reconnectDelay = min(8, reconnectDelay * 1.5)
            }
        }
    }

    func stop() {
        connectionTask?.cancel()
        connectionTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func handle(_ message: URLSessionWebSocketTask.Message, scope: Scope) {
        let data: Data?
        switch message {
        case .data(let value): data = value
        case .string(let value): data = value.data(using: .utf8)
        @unknown default: data = nil
        }
        guard let data, let header = try? decoder.decode(MessageHeader.self, from: data) else { return }

        switch (scope, header.type) {
        case (.feed, "post"):
            if let post = try? decoder.decode(Post.self, from: data) { onEvent?(.post(post)) }
        case (.feed, "task"):
            if header.state == "idle", header.skipped != true, let name = header.name {
                onEvent?(.taskCompleted(name))
            }
        case (.deployment, "deployment-status"):
            if let message = try? decoder.decode(DeploymentStatusMessage.self, from: data),
               let snapshot = DeploymentStatusSnapshot(message: message) {
                onEvent?(.deploymentStatus(snapshot))
            }
        default:
            break
        }
    }

    nonisolated static func webSocketURL(from baseURL: URL) -> URL? {
        guard var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https" else { return nil }
        parts.scheme = "wss"
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
