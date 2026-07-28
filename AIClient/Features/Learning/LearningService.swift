import Foundation
import Observation

protocol LearningServing {
    func fetchCatalog() async throws -> LearningCatalog
    func fetchTopic(id: String) async throws -> LearningTopic
}

struct LearningService: LearningServing {
    static let sourceURL = URL(string: "https://www.futunn.com/learn/wiki")!

    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = ServerConfiguration.currentURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 20
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            configuration.urlCache = .shared
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetchCatalog() async throws -> LearningCatalog {
        let response: LearningCatalogResponse = try await fetch(
            baseURL.appending(path: "api/v1/learning/catalog")
        )
        return response.data
    }

    func fetchTopic(id: String) async throws -> LearningTopic {
        let response: LearningTopicResponse = try await fetch(
            baseURL.appending(path: "api/v1/learning/topics").appending(path: id)
        )
        return response.data
    }

    private func fetch<Value: Decodable>(_ url: URL) async throws -> Value {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LearningError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Value.self, from: data)
    }
}

@MainActor
@Observable
final class LearningContentRepository {
    private(set) var topics: [String: LearningTopic] = [:]
    private(set) var loadingIDs: Set<String> = []
    private(set) var errorMessages: [String: String] = [:]
    @ObservationIgnored private let service: any LearningServing
    @ObservationIgnored private var requests: [String: Task<LearningTopic, Error>] = [:]

    init(service: any LearningServing = LearningService()) {
        self.service = service
    }

    func topic(id: String) -> LearningTopic? {
        topics[id]
    }

    func load(id: String) async {
        guard topics[id] == nil else { return }
        errorMessages[id] = nil
        loadingIDs.insert(id)

        let request: Task<LearningTopic, Error>
        if let existing = requests[id] {
            request = existing
        } else {
            let service = service
            request = Task { try await service.fetchTopic(id: id) }
            requests[id] = request
        }
        defer {
            requests[id] = nil
            loadingIDs.remove(id)
        }

        do {
            topics[id] = try await request.value
        } catch is CancellationError {
            return
        } catch {
            errorMessages[id] = error.localizedDescription
        }
    }

    func prefetch(_ topics: ArraySlice<LearningTopic>) async {
        await withTaskGroup(of: Void.self) { group in
            for topic in topics where self.topics[topic.id] == nil {
                group.addTask { await self.load(id: topic.id) }
            }
        }
    }
}

@MainActor
@Observable
final class LearningStore {
    private(set) var catalog: LearningCatalog?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let service: LearningService

    init(service: LearningService = LearningService()) { self.service = service }

    func load(force: Bool = false) async {
        guard force || catalog == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            catalog = try await service.fetchCatalog()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum LearningError: LocalizedError {
    case invalidResponse

    var errorDescription: String? { "学习内容暂时无法访问" }
}
