import Foundation
import Observation

struct LearningService {
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

@MainActor
@Observable
final class LearningDetailStore {
    private(set) var topic: LearningTopic?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let service: LearningService

    init(service: LearningService = LearningService()) { self.service = service }

    func load(id: String) async {
        guard topic?.id != id else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            topic = try await service.fetchTopic(id: id)
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
