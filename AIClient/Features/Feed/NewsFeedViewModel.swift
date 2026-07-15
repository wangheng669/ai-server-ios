import Foundation
import Combine

@MainActor
final class NewsFeedViewModel: ObservableObject {
    @Published private(set) var posts: [Post] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = true
    @Published private(set) var isSwitchingSource = false
    @Published private(set) var sourceContentRevision = 0
    @Published var errorMessage: String?
    @Published var source: FeedSource {
        didSet { UserDefaults.standard.set(source.rawValue, forKey: "feed.source") }
    }

    private struct Snapshot { var posts: [Post]; var page: Int; var canLoadMore: Bool }
    private var cache: [FeedSource: Snapshot] = [:]
    private var page = 1
    private let pageSize = 20
    private var realtimeClient: RealtimeFeedClient?

    init() {
        #if DEBUG
        let override = ProcessInfo.processInfo.environment["AI_FEED_SOURCE"]
        #else
        let override: String? = nil
        #endif
        source = FeedSource(rawValue: override ?? UserDefaults.standard.string(forKey: "feed.source") ?? "x") ?? .x
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
            sourceContentRevision += 1
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
        guard !isLoading else { return }
        let requestedSource = source
        let completesSourceSwitch = isSwitchingSource
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await client.fetchPosts(page: 1, limit: pageSize, source: requestedSource)
            guard source == requestedSource else { return }
            posts = result
            page = 1
            canLoadMore = result.count >= pageSize
            if completesSourceSwitch {
                isSwitchingSource = false
                sourceContentRevision += 1
            }
            cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
        } catch is CancellationError { } catch {
            guard source == requestedSource else { return }
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
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await client.fetchPosts(page: page + 1, limit: pageSize, source: requestedSource)
            guard source == requestedSource else { return }
            let ids = Set(posts.map(\.id))
            posts += result.filter { !ids.contains($0.id) }
            page += 1
            canLoadMore = result.count >= pageSize
            cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
        } catch is CancellationError { } catch { errorMessage = error.localizedDescription }
    }

    private var client: APIClient { APIClient(baseURL: ServerConfiguration.currentURL) }

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
