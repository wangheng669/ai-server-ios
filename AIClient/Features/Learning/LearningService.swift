import Foundation
import Observation

struct LearningResponse<Content: Decodable>: Decodable {
    let data: Content
}

struct LearningService {
    static let sourceURL = URL(string: "https://www.futunn.com/learn/wiki")!
    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.urlCache = .shared
        return URLSession(configuration: configuration)
    }()

    let baseURL: URL
    private let session: URLSession
    private let allowsSnapshots: Bool
    private var learningURL: URL { baseURL.appending(path: "api/ios/v1/learning") }

    init(baseURL: URL = ServerConfiguration.currentURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.session = session ?? Self.defaultSession
        allowsSnapshots = session == nil
    }

    func fetchCatalog(onCached: (@MainActor (LearningCatalog) -> Void)? = nil) async throws -> LearningCatalog {
        try await fetch(learningURL.appending(path: "catalog"), onCached: onCached)
    }

    func fetchTopic(id: String) async throws -> LearningTopic {
        try await fetch(learningURL.appending(path: "topics").appending(path: id))
    }

    func fetchBookshelf(onCached: (@MainActor (LearningBookshelf) -> Void)? = nil) async throws -> LearningBookshelf {
        try await fetch(
            learningURL.appending(path: "bookshelf"),
            cachePolicy: .reloadIgnoringLocalCacheData,
            onCached: onCached
        )
    }

    func fetchConcepts(onCached: (@MainActor (KnowledgeConceptLibrary) -> Void)? = nil) async throws -> KnowledgeConceptLibrary {
        try await fetch(learningURL.appending(path: "concepts"), onCached: onCached)
    }

    func fetchVideoLessons(onCached: (@MainActor (LearningVideoLibrary) -> Void)? = nil) async throws -> LearningVideoLibrary {
        try await fetch(learningURL.appending(path: "video-lessons"), onCached: onCached)
    }

    func fetchVideoLesson(id: String) async throws -> LearningVideoLesson {
        try await fetch(learningURL.appending(path: "video-lessons").appending(path: id))
    }

    private func fetch<Value: Decodable>(
        _ url: URL,
        cachePolicy: URLRequest.CachePolicy = .reloadRevalidatingCacheData,
        onCached: (@MainActor (Value) -> Void)? = nil
    ) async throws -> Value {
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let key = url.absoluteString
        let usesSnapshot = allowsSnapshots && onCached != nil
        let preparedRequest = request
        async let reply = session.data(for: preparedRequest)
        if usesSnapshot, let onCached,
           let saved = await DisplaySnapshotCache.knowledge.load(Data.self, key: key, maximumAge: 7 * 86_400),
           let cached: Value = try? decode(saved.value) {
            try Task.checkCancellation()
            await onCached(cached)
        }
        let (data, response) = try await reply
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LearningError.invalidResponse
        }
        let value: Value = try decode(data)
        if usesSnapshot {
            await DisplaySnapshotCache.knowledge.save(data, key: key, at: Date(), minimumInterval: 300)
        }
        return value
    }

    private func decode<Value: Decodable>(_ data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LearningResponse<Value>.self, from: data).data
    }
}

@MainActor
@Observable
final class LearningContentRepository {
    private var topics: [String: LearningTopic] = [:]
    private(set) var errorMessages: [String: String] = [:]
    private let service: LearningService
    @ObservationIgnored private var requests: [String: Task<Void, Never>] = [:]

    init(service: LearningService = LearningService()) {
        self.service = service
    }

    func topic(id: String) -> LearningTopic? {
        topics[id]
    }

    func load(id: String) async {
        guard !Task.isCancelled, topics[id] == nil else { return }
        if let request = requests[id] {
            await request.value
            return
        }
        errorMessages[id] = nil
        let request = Task {
            defer { requests[id] = nil }
            do {
                topics[id] = try await service.fetchTopic(id: id)
            } catch is CancellationError {
                return
            } catch {
                errorMessages[id] = error.localizedDescription
            }
        }
        requests[id] = request
        await request.value
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
    private enum OverviewSection { case catalog, bookshelf, concepts, videos }
    private var restoredSections: Set<OverviewSection> = []
    private(set) var catalog: LearningCatalog?
    private(set) var bookshelf: LearningBookshelf? {
        didSet {
            let covers = bookshelf?.books.prefix(3).compactMap(\.coverURL) ?? []
            if covers != oldValue?.books.prefix(3).compactMap(\.coverURL) {
                prepareCovers(covers, size: CGSize(width: 120, height: 128))
            }
        }
    }
    private(set) var conceptLibrary: KnowledgeConceptLibrary? {
        didSet {
            if let cover = conceptLibrary?.concepts.first?.coverURL, cover != oldValue?.concepts.first?.coverURL {
                prepareCovers([cover], size: CGSize(width: 68, height: 68))
            }
        }
    }
    private(set) var videoLibrary: LearningVideoLibrary? {
        didSet {
            if let cover = videoLibrary?.lessons.first?.coverURL, cover != oldValue?.lessons.first?.coverURL {
                prepareCovers([cover], size: CGSize(width: 112, height: 74))
            }
        }
    }
    private(set) var isLoading = false
    private(set) var isBookshelfLoading = false
    private(set) var isConceptLibraryLoading = false
    private(set) var isVideoLibraryLoading = false
    private(set) var errorMessage: String?
    private(set) var bookshelfErrorMessage: String?
    private(set) var bookshelfFetchedAt: Date?
    private(set) var conceptLibraryErrorMessage: String?
    private(set) var videoLibraryErrorMessage: String?
    private(set) var hasLoadedOverview = false
    private var overviewTask: Task<Void, Never>?
    private var overviewLoadedAt: Date?
    private let service: LearningService

    init(service: LearningService = LearningService()) { self.service = service }

    var hasOverviewContent: Bool {
        catalog != nil || bookshelf != nil || conceptLibrary != nil || videoLibrary != nil
    }

    var savedContentNotice: String? {
        guard !restoredSections.isEmpty else { return nil }
        let isRefreshing = isLoading || isBookshelfLoading || isConceptLibraryLoading || isVideoLibraryLoading
        return isRefreshing ? "已显示上次保存的内容 · 正在更新" : "部分内容暂未更新"
    }

    func loadOverview(force: Bool = false) async {
        if let overviewTask {
            await overviewTask.value
            return
        }
        if !force, let overviewLoadedAt, Date().timeIntervalSince(overviewLoadedAt) < 300 { return }
        let refresh = force || hasLoadedOverview
        let task = Task {
            async let catalogRequest: Void = load(force: refresh)
            async let booksRequest: Void = loadBookshelf(force: refresh)
            async let conceptsRequest: Void = loadConceptLibrary(force: refresh)
            async let videosRequest: Void = loadVideoLibrary(force: refresh)
            _ = await (catalogRequest, booksRequest, conceptsRequest, videosRequest)
            hasLoadedOverview = true
            if catalog != nil, bookshelf != nil, conceptLibrary != nil, videoLibrary != nil,
               errorMessage == nil, bookshelfErrorMessage == nil,
               conceptLibraryErrorMessage == nil, videoLibraryErrorMessage == nil {
                overviewLoadedAt = Date()
            } else {
                overviewLoadedAt = nil
            }
        }
        overviewTask = task
        await task.value
        overviewTask = nil
    }

    private func prepareCovers(_ urls: [URL], size: CGSize) {
        guard !urls.isEmpty else { return }
        Task(priority: .utility) {
            await runWithLimitedConcurrency(urls, maximumConcurrentRequests: 2) { url in
                _ = await ImageLoader.load(url, targetSize: size)
            }
        }
    }

    func load(force: Bool = false) async {
        guard !isLoading, force || catalog == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            catalog = try await service.fetchCatalog { cached in
                guard self.catalog == nil else { return }
                self.catalog = cached
                self.restoredSections.insert(.catalog)
            }
            restoredSections.remove(.catalog)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadBookshelf(force: Bool = false) async {
        let isStale = bookshelfFetchedAt.map { Date().timeIntervalSince($0) >= 300 } ?? true
        guard !isBookshelfLoading, force || bookshelf == nil || isStale else { return }
        isBookshelfLoading = true
        bookshelfErrorMessage = nil
        defer { isBookshelfLoading = false }
        do {
            bookshelf = try await service.fetchBookshelf { cached in
                guard self.bookshelf == nil else { return }
                self.bookshelf = cached
                self.restoredSections.insert(.bookshelf)
            }
            restoredSections.remove(.bookshelf)
            bookshelfFetchedAt = .now
        } catch is CancellationError {
            return
        } catch {
            bookshelfErrorMessage = error.localizedDescription
        }
    }

    func loadConceptLibrary(force: Bool = false) async {
        guard !isConceptLibraryLoading, force || conceptLibrary == nil else { return }
        isConceptLibraryLoading = true
        conceptLibraryErrorMessage = nil
        defer { isConceptLibraryLoading = false }
        do {
            conceptLibrary = try await service.fetchConcepts { cached in
                guard self.conceptLibrary == nil else { return }
                self.conceptLibrary = cached
                self.restoredSections.insert(.concepts)
            }
            restoredSections.remove(.concepts)
        } catch is CancellationError {
            return
        } catch {
            conceptLibraryErrorMessage = error.localizedDescription
        }
    }

    func loadVideoLibrary(force: Bool = false) async {
        guard !isVideoLibraryLoading, force || videoLibrary == nil else { return }
        isVideoLibraryLoading = true
        videoLibraryErrorMessage = nil
        defer { isVideoLibraryLoading = false }
        do {
            videoLibrary = try await service.fetchVideoLessons { cached in
                guard self.videoLibrary == nil else { return }
                self.videoLibrary = cached
                self.restoredSections.insert(.videos)
            }
            restoredSections.remove(.videos)
        } catch is CancellationError {
            return
        } catch {
            videoLibraryErrorMessage = error.localizedDescription
        }
    }
}

enum LearningError: LocalizedError {
    case invalidResponse

    var errorDescription: String? { "知识内容暂时无法访问" }
}
