import Foundation
import Combine

@MainActor
final class NewsFeedViewModel: ObservableObject {
    @Published private(set) var posts: [Post] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = true
    @Published private(set) var isSwitchingSource = false
    @Published var errorMessage: String?
    @Published var source: FeedSource {
        didSet { UserDefaults.standard.set(source.rawValue, forKey: "feed.source") }
    }

    private struct Snapshot { var posts: [Post]; var page: Int; var canLoadMore: Bool }
    private var cache: [FeedSource: Snapshot] = [:]
    private var page = 1
    private let defaultPageSize = 5
    private var realtimeClient: RealtimeFeedClient?
    private var activeRefreshID: UUID?
    private let fetchPosts: (Int, Int, FeedSource) async throws -> [Post]

    init(
        source initialSource: FeedSource? = nil,
        fetchPosts: ((Int, Int, FeedSource) async throws -> [Post])? = nil
    ) {
        #if DEBUG
        let override = ProcessInfo.processInfo.environment["AI_FEED_SOURCE"]
        #else
        let override: String? = nil
        #endif
        source = initialSource
            ?? FeedSource(rawValue: override ?? UserDefaults.standard.string(forKey: "feed.source") ?? "x")
            ?? .x
        if let fetchPosts {
            self.fetchPosts = fetchPosts
        } else {
            let client = APIClient(baseURL: ServerConfiguration.currentURL)
            self.fetchPosts = { page, limit, source in
                try await client.fetchPosts(page: page, limit: limit, source: source)
            }
        }
    }

    func select(_ next: FeedSource) {
        guard next != source else { return }
        if !isSwitchingSource {
            cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
        }
        source = next
        let saved = cache[next]
        if let saved {
            posts = saved.posts
            page = saved.page
            canLoadMore = saved.canLoadMore
            isSwitchingSource = false
        } else {
            page = 1
            canLoadMore = true
            isSwitchingSource = true
        }
        errorMessage = nil
    }

    func selectAdjacent(offset: Int) {
        let sources = FeedSource.allCases
        guard let current = sources.firstIndex(of: source) else { return }
        let next = current + offset
        guard sources.indices.contains(next) else { return }
        select(sources[next])
    }

    func loadInitial() async {
        // Keep cached posts visible, but always revalidate the selected source so
        // returning to a channel never leaves an old snapshot on screen indefinitely.
        await refresh()
    }

    func warmSourceCache() async {
        guard let selectedIndex = FeedSource.allCases.firstIndex(of: source) else { return }
        let sources = FeedSource.allCases
            .enumerated()
            .filter { $0.element != source }
            .sorted { abs($0.offset - selectedIndex) < abs($1.offset - selectedIndex) }
            .map(\.element)

        for candidate in sources {
            guard !Task.isCancelled else { return }
            guard cache[candidate] == nil else { continue }
            do {
                let pageSize = pageSize(for: candidate)
                let result = try await fetchPosts(1, pageSize, candidate)
                guard !Task.isCancelled, cache[candidate] == nil else { continue }
                cache[candidate] = .init(
                    posts: result,
                    page: 1,
                    canLoadMore: result.count >= pageSize
                )
            } catch is CancellationError {
                return
            } catch {
                // Cache warming is best-effort. Selecting the channel still performs
                // the normal foreground request and presents any resulting error.
            }
        }
    }

    private func pageSize(for source: FeedSource) -> Int {
        switch source {
        case .weibo, .douyin, .truth: 20
        default: defaultPageSize
        }
    }

    func startRealtime() {
        let client = RealtimeFeedClient(baseURL: ServerConfiguration.currentURL)
        client.onEvent = { [weak self] event in self?.handleRealtime(event) }
        realtimeClient?.stop()
        realtimeClient = client
        client.start()
    }

    func stopRealtime() {
        realtimeClient?.stop()
        realtimeClient = nil
    }

    func refresh() async {
        let refreshID = UUID()
        let requestedSource = source
        let completesSourceSwitch = isSwitchingSource
        activeRefreshID = refreshID
        isLoading = true
        errorMessage = nil
        defer {
            if activeRefreshID == refreshID {
                activeRefreshID = nil
                isLoading = false
            }
        }
        do {
            let pageSize = pageSize(for: requestedSource)
            let result = try await fetchPosts(1, pageSize, requestedSource)
            guard source == requestedSource, activeRefreshID == refreshID else { return }
            posts = result
            page = 1
            canLoadMore = result.count >= pageSize
            if completesSourceSwitch {
                isSwitchingSource = false
            }
            cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
        } catch is CancellationError { } catch {
            guard source == requestedSource, activeRefreshID == refreshID else { return }
            if completesSourceSwitch {
                isSwitchingSource = false
                posts = []
            }
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(current post: Post) async {
        guard !isSwitchingSource,
              post.id == posts.last?.id,
              canLoadMore,
              !isLoadingMore,
              !isLoading else { return }
        let requestedSource = source
        let pageSize = pageSize(for: requestedSource)
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await fetchPosts(page + 1, pageSize, requestedSource)
            guard source == requestedSource else { return }
            let ids = Set(posts.map(\.id))
            posts += result.filter { !ids.contains($0.id) }
            page += 1
            canLoadMore = result.count >= pageSize
            cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
        } catch is CancellationError { } catch { errorMessage = error.localizedDescription }
    }

    private func handleRealtime(_ event: RealtimeFeedClient.Event) {
        switch event {
        case .post(let post):
            guard !isSwitchingSource, matchesCurrentSource(post) else { return }
            errorMessage = nil
            if let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index] = post
            } else {
                posts.insert(post, at: 0)
            }
            cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
        case .taskCompleted(let name):
            guard task(name, updates: source) else { return }
            Task { await refresh() }
        }
    }

    private func matchesCurrentSource(_ post: Post) -> Bool {
        switch source {
        case .newYorkTimes: return post.source == FeedSource.newYorkTimes.rawValue
        case .x: return post.sourceName == "X"
        case .bilibili: return post.isBilibili
        case .zhihu: return post.sourceName == "知乎"
        case .truth: return post.sourceName == "Truth"
        case .rss: return post.isRSS
        case .laozhong: return post.isRSS && post.tagNames.contains("老中")
        case .youtube: return post.isRSS && post.tagNames.contains("YouTube")
        case .weibo, .douyin, .flash: return false
        }
    }

    private func task(_ name: String, updates source: FeedSource) -> Bool {
        switch source {
        case .newYorkTimes: return name == "rss"
        case .x: return name == "x" || name == "x_home" || name == "x_home_following"
        case .weibo: return name == "weibo_hot"
        case .douyin: return name == "douyin_hot"
        case .bilibili: return name == "bilibili"
        case .zhihu: return name == "zhihu"
        case .truth: return name == "truth"
        case .rss, .laozhong, .youtube: return name == "rss"
        case .flash: return name.contains("flash")
        }
    }
}
