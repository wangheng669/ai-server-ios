import Foundation
import Observation

protocol LearningServing {
    func fetchCatalog() async throws -> LearningCatalog
    func fetchTopic(id: String) async throws -> LearningTopic
    func fetchVideoLessons() async throws -> LearningVideoLibrary
    func fetchVideoLesson(id: String) async throws -> LearningVideoLesson
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
            baseURL.appending(path: "api/ios/v1/learning/catalog")
        )
        return response.data
    }

    func fetchTopic(id: String) async throws -> LearningTopic {
        let response: LearningTopicResponse = try await fetch(
            baseURL.appending(path: "api/ios/v1/learning/topics").appending(path: id),
            cachePolicy: .reloadRevalidatingCacheData
        )
        return response.data
    }

    func fetchBookshelf() async throws -> LearningBookshelf {
        let response: LearningBookshelfResponse = try await fetch(
            baseURL.appending(path: "api/ios/v1/learning/bookshelf"),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        return response.data
    }

    func fetchConcepts() async throws -> KnowledgeConceptLibrary {
        let response: KnowledgeConceptLibraryResponse = try await fetch(
            baseURL.appending(path: "api/ios/v1/learning/concepts")
        )
        return response.data
    }

    func fetchConcept(id: String) async throws -> KnowledgeConceptDetail {
        let response: KnowledgeConceptDetailResponse = try await fetch(
            baseURL.appending(path: "api/ios/v1/learning/concepts").appending(path: id),
            cachePolicy: .reloadRevalidatingCacheData
        )
        return response.data
    }

    func fetchVideoLessons() async throws -> LearningVideoLibrary {
        let response: LearningVideoLibraryResponse = try await fetch(
            baseURL.appending(path: "api/ios/v1/learning/video-lessons")
        )
        return response.data
    }

    func fetchVideoLesson(id: String) async throws -> LearningVideoLesson {
        let response: LearningVideoLessonResponse = try await fetch(
            baseURL.appending(path: "api/ios/v1/learning/video-lessons").appending(path: id),
            cachePolicy: .reloadRevalidatingCacheData
        )
        return response.data
    }

    private func fetch<Value: Decodable>(
        _ url: URL,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> Value {
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
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
    private(set) var bookshelf: LearningBookshelf?
    private(set) var conceptLibrary: KnowledgeConceptLibrary?
    private(set) var videoLibrary: LearningVideoLibrary?
    private(set) var isLoading = false
    private(set) var isBookshelfLoading = false
    private(set) var isConceptLibraryLoading = false
    private(set) var isVideoLibraryLoading = false
    private(set) var errorMessage: String?
    private(set) var bookshelfErrorMessage: String?
    private(set) var conceptLibraryErrorMessage: String?
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

    func loadBookshelf(force: Bool = false) async {
        guard force || bookshelf == nil else { return }
        isBookshelfLoading = true
        bookshelfErrorMessage = nil
        defer { isBookshelfLoading = false }
        do {
            bookshelf = try await service.fetchBookshelf()
        } catch is CancellationError {
            return
        } catch {
            bookshelfErrorMessage = error.localizedDescription
        }
    }

    func loadConceptLibrary(force: Bool = false) async {
        guard force || conceptLibrary == nil else { return }
        isConceptLibraryLoading = true
        conceptLibraryErrorMessage = nil
        defer { isConceptLibraryLoading = false }
        do {
            conceptLibrary = try await service.fetchConcepts()
        } catch is CancellationError {
            return
        } catch {
            conceptLibraryErrorMessage = error.localizedDescription
        }
    }

    func loadVideoLibrary(force: Bool = false) async {
        guard force || videoLibrary == nil else { return }
        isVideoLibraryLoading = true
        defer { isVideoLibraryLoading = false }
        do {
            videoLibrary = try await service.fetchVideoLessons()
        } catch is CancellationError {
            return
        } catch {
            // Investment articles remain usable when the optional video shelf is offline.
        }
    }
}

enum LearningError: LocalizedError {
    case invalidResponse

    var errorDescription: String? { "知识内容暂时无法访问" }
}
