import Foundation
import Combine

@MainActor
final class NewsFeedViewModel: ObservableObject {
    @Published private(set) var posts: [Post] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = true
    @Published private(set) var isSwitchingSource = false
    @Published private(set) var pendingRealtimePosts: [Post] = []
    @Published private(set) var xTranslations: [Int: String] = [:]
    @Published private(set) var rssFeeds: [RSSFeedSource] = []
    @Published private(set) var selectedRSSFeedID: Int?
    @Published private(set) var selectedRSSPosts: [Post] = []
    @Published private(set) var isLoadingRSSSelection = false
    @Published private(set) var isLoadingMoreRSSSelection = false
    @Published private(set) var canLoadMoreRSSSelection = true
    @Published private(set) var selectedFlashCategory: String?
    @Published var errorMessage: String?
    @Published var source: FeedSource {
        didSet { UserDefaults.standard.set(source.rawValue, forKey: "feed.source") }
    }

    private struct Snapshot { var posts: [Post]; var page: Int; var canLoadMore: Bool }
    @Published private var cache: [FeedSource: Snapshot] = [:]
    private var page = 1
    private let defaultPageSize = 5
    private var realtimeClient: RealtimeFeedClient?
    private var activeRefreshID: UUID?
    private let fetchPosts: (Int, Int, FeedSource) async throws -> [Post]
    private let fetchFlashPosts: (Int, Int, String?) async throws -> [Post]
    private let fetchXTranslation: (String) async throws -> XTranslation
    private let fetchRSSFeeds: () async throws -> [RSSFeedSource]
    private let fetchRSSFeedPosts: (Int, Int, Int) async throws -> [Post]
    private let fetchPostDetail: (Int) async throws -> Post
    private let fetchNewYorkTimesArticle: (URL) async throws -> NewYorkTimesArticle
    private var loadingXTranslationIDs: Set<Int> = []
    private var preloadedNewYorkTimesArticles: [Int: NewYorkTimesArticle] = [:]
    private var selectedRSSPage = 1
    private let selectedRSSPageSize = 20

    init(
        source initialSource: FeedSource? = nil,
        fetchPosts: ((Int, Int, FeedSource) async throws -> [Post])? = nil,
        fetchFlashPosts: ((Int, Int, String?) async throws -> [Post])? = nil,
        fetchXTranslation: ((String) async throws -> XTranslation)? = nil,
        fetchRSSFeedPosts: ((Int, Int, Int) async throws -> [Post])? = nil,
        fetchPostDetail: ((Int) async throws -> Post)? = nil,
        fetchNewYorkTimesArticle: ((URL) async throws -> NewYorkTimesArticle)? = nil
    ) {
        #if DEBUG
        let override = ProcessInfo.processInfo.environment["AI_FEED_SOURCE"]
        let usesXFeedPreview = ProcessInfo.processInfo.arguments.contains("--x-feed-preview")
        #else
        let override: String? = nil
        #endif
        source = initialSource
            ?? FeedSource(rawValue: override ?? UserDefaults.standard.string(forKey: "feed.source") ?? "x")
            ?? .x
        let client = APIClient(baseURL: ServerConfiguration.currentURL)
        self.fetchXTranslation = fetchXTranslation ?? { tweetID in
            try await client.fetchXTranslation(tweetID: tweetID)
        }
        self.fetchRSSFeeds = { try await client.fetchRSSFeeds() }
        self.fetchRSSFeedPosts = fetchRSSFeedPosts ?? { feedID, page, limit in
            try await client.fetchRSSFeedPosts(feedID: feedID, page: page, limit: limit)
        }
        self.fetchPostDetail = fetchPostDetail ?? { postID in
            try await client.fetchPost(id: postID)
        }
        self.fetchNewYorkTimesArticle = fetchNewYorkTimesArticle ?? { url in
            try await client.fetchNewYorkTimesArticle(url: url)
        }
        if let fetchFlashPosts {
            self.fetchFlashPosts = fetchFlashPosts
        } else if let fetchPosts {
            self.fetchFlashPosts = { page, limit, _ in
                try await fetchPosts(page, limit, .flash)
            }
        } else {
            self.fetchFlashPosts = { page, limit, category in
                try await client.fetchPosts(
                    page: page,
                    limit: limit,
                    source: .flash,
                    flashCategory: category
                )
            }
        }
        #if DEBUG
        if usesXFeedPreview {
            self.fetchPosts = { _, _, _ in Self.xFeedPreviewPosts }
        } else if let fetchPosts {
            self.fetchPosts = fetchPosts
        } else {
            self.fetchPosts = { page, limit, source in
                try await client.fetchPosts(page: page, limit: limit, source: source)
            }
        }
        #else
        if let fetchPosts {
            self.fetchPosts = fetchPosts
        } else {
            self.fetchPosts = { page, limit, source in
                try await client.fetchPosts(page: page, limit: limit, source: source)
            }
        }
        #endif
    }

    func loadRSSFeedsIfNeeded() async {
        guard rssFeeds.isEmpty else { return }
        do {
            rssFeeds = try await fetchRSSFeeds()
        } catch is CancellationError {
            return
        } catch {
            // The normal RSS feed remains usable if the source directory is unavailable.
        }
    }

    func selectRSSFeed(_ feedID: Int?) async {
        selectedRSSFeedID = feedID
        selectedRSSPosts = []
        selectedRSSPage = 1
        canLoadMoreRSSSelection = true
        guard let feedID else {
            isLoadingRSSSelection = false
            return
        }
        isLoadingRSSSelection = true
        defer { if selectedRSSFeedID == feedID { isLoadingRSSSelection = false } }
        do {
            let result = try await fetchRSSFeedPosts(feedID, 1, selectedRSSPageSize)
            guard !Task.isCancelled, selectedRSSFeedID == feedID else { return }
            let warmedPosts = try await warmNewYorkTimesPostsIfNeeded(result)
            guard !Task.isCancelled, selectedRSSFeedID == feedID else { return }
            selectedRSSPosts = warmedPosts
            canLoadMoreRSSSelection = !result.isEmpty
        } catch is CancellationError {
            return
        } catch {
            guard selectedRSSFeedID == feedID else { return }
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
    }

    func loadMoreSelectedRSSIfNeeded(current post: Post) async {
        guard let feedID = selectedRSSFeedID,
              post.id == selectedRSSPosts.last?.id,
              canLoadMoreRSSSelection,
              !isLoadingRSSSelection,
              !isLoadingMoreRSSSelection else { return }
        let nextPage = selectedRSSPage + 1
        isLoadingMoreRSSSelection = true
        defer { isLoadingMoreRSSSelection = false }
        do {
            let result = try await fetchRSSFeedPosts(feedID, nextPage, selectedRSSPageSize)
            guard !Task.isCancelled, selectedRSSFeedID == feedID else { return }
            let warmedPosts = try await warmNewYorkTimesPostsIfNeeded(result)
            guard !Task.isCancelled, selectedRSSFeedID == feedID else { return }
            let existingIDs = Set(selectedRSSPosts.map(\.id))
            selectedRSSPosts += warmedPosts.filter { !existingIDs.contains($0.id) }
            selectedRSSPage = nextPage
            canLoadMoreRSSSelection = !result.isEmpty
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard selectedRSSFeedID == feedID else { return }
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
    }

    private func warmNewYorkTimesPostsIfNeeded(_ posts: [Post]) async throws -> [Post] {
        guard posts.contains(where: \.isNewYorkTimes) else { return posts }
        return try await prefetchNewYorkTimesBodies(for: posts)
    }

    func selectFlashCategory(_ category: String?) async {
        guard source == .flash, selectedFlashCategory != category else { return }
        selectedFlashCategory = category
        posts = []
        page = 1
        canLoadMore = true
        cache[.flash] = nil
        await refresh()
    }

    private func prefetchNewYorkTimesBodies(for posts: [Post]) async throws -> [Post] {
        try await withThrowingTaskGroup(of: (Int, Post, NewYorkTimesArticle?).self, returning: [Post].self) { group in
            for (index, post) in posts.enumerated() {
                group.addTask { [fetchPostDetail, fetchNewYorkTimesArticle] in
                    guard post.isNewYorkTimes else { return (index, post, nil) }

                    // The list endpoint intentionally truncates content. Always
                    // read the raw database row before publishing a tappable card.
                    let detail = try await fetchPostDetail(post.id)
                    if let article = (detail.contentZH ?? detail.content).flatMap(NewYorkTimesArticle.storedText) {
                        return (index, detail, article)
                    }
                    guard let link = detail.linkURL ?? post.linkURL else { throw APIError.invalidURL }
                    let article = try await fetchNewYorkTimesArticle(link)
                    return (index, detail, article)
                }
            }

            var warmed = posts
            for try await (index, post, article) in group {
                warmed[index] = post
                if let article {
                    preloadedNewYorkTimesArticles[post.id] = article
                }
            }
            return warmed
        }
    }

    func postForDisplay(_ post: Post) -> Post {
        guard let translation = xTranslations[post.id] else { return post }
        return post.replacingTranslation(with: translation)
    }

    func preloadedNewYorkTimesArticle(for postID: Int) -> NewYorkTimesArticle? {
        preloadedNewYorkTimesArticles[postID]
    }

    func posts(for source: FeedSource) -> [Post] {
        source == self.source ? posts : cache[source]?.posts ?? []
    }

    func translateXPostIfNeeded(_ post: Post) async {
        guard post.needsXTranslation,
              let tweetID = post.xTweetID,
              xTranslations[post.id] == nil,
              !loadingXTranslationIDs.contains(post.id) else { return }
        loadingXTranslationIDs.insert(post.id)
        defer { loadingXTranslationIDs.remove(post.id) }
        do {
            let result = try await fetchXTranslation(tweetID)
            guard !Task.isCancelled else { return }
            let value = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value != post.originalDisplayContent else { return }
            xTranslations[post.id] = value
        } catch is CancellationError {
            return
        } catch {
            // Translation is best-effort. Keep the original post visible on failure.
        }
    }

    #if DEBUG
    private static var xFeedPreviewPosts: [Post] {
        let json = #"""
        [{
          "id": 2423252,
          "source": "x",
          "content": "今日AI美股信息差： 1. 血洗半导体！美股平均跌幅-4.2%，A股-8.5%，2倍3倍 ETF $SNXX $RAM $SOXL 暴跌17-27%，白毛股神：底部已到！ 2. $SPCX 暴跌7%到$124！星舰测试发动机无法点火，很尴尬，流通股29%都是空头，马斯克，这么多人做空你，你能忍？ 3. Kimi K3发布！一跃成为第三强，仅次于Claude Fable 5、GPT-5.6 Sol，国产AI竞争力说起就起 4. $AAPL 再涨2%创新高！苹果本地化接入了千问、百度AI，中国终于可以用苹果 AI 了 5. $GOOGL 暴跌4.5%，Gemini 3.5 Pro 发布推迟，写代码方面遥遥落后，相比 Codex、Claude、Cursor拿不出手",
          "formatted_time": "45分钟",
          "post_link": "https://x.com/web3annie/status/2077964813930799525",
          "user": {"user_name": "Annie 所长", "user_screen_name": "web3annie"},
          "videos": [{"url": "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4", "width": 1920, "height": 1080}],
          "meta": {"metrics": {"replies": 222, "retweets": 786, "likes": 12000, "views": 960000}}
        }]
        """#
        return (try? JSONDecoder().decode([Post].self, from: Data(json.utf8))) ?? []
    }
    #endif

    func select(_ next: FeedSource) {
        guard next != source else { return }
        pendingRealtimePosts = []
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
            // Do not render the previous channel while this channel's first page is loading.
            // Keeping it here makes the loading state source-safe for every feed type.
            posts = []
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
        // Returning to a cached channel must preserve the exact feed snapshot.
        // Pull-to-refresh remains available when the user wants fresh content.
        guard posts.isEmpty || isSwitchingSource else { return }
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
                let result = try await fetchPage(1, limit: pageSize, source: candidate)
                guard !Task.isCancelled, cache[candidate] == nil else { continue }
                cache[candidate] = .init(
                    posts: result,
                    page: 1,
                    canLoadMore: !result.isEmpty
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
        case .flash: 20
        case .x: 10
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
        let requestedFlashCategory = selectedFlashCategory
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
            let result = try await fetchPage(
                1,
                limit: pageSize,
                source: requestedSource,
                flashCategory: requestedFlashCategory
            )
            guard source == requestedSource,
                  selectedFlashCategory == requestedFlashCategory,
                  activeRefreshID == refreshID else { return }
            posts = result
            pendingRealtimePosts = []
            page = 1
            canLoadMore = !result.isEmpty
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
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
    }

    func loadMoreIfNeeded(current post: Post, thresholdPostID: Int? = nil) async {
        guard !isSwitchingSource,
              post.id == (thresholdPostID ?? posts.last?.id),
              canLoadMore,
              !isLoadingMore,
              !isLoading else { return }
        let requestedSource = source
        let requestedFlashCategory = selectedFlashCategory
        let pageSize = pageSize(for: requestedSource)
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await fetchPage(
                page + 1,
                limit: pageSize,
                source: requestedSource,
                flashCategory: requestedFlashCategory
            )
            guard source == requestedSource, selectedFlashCategory == requestedFlashCategory else { return }
            let ids = Set(posts.map(\.id))
            posts += result.filter { !ids.contains($0.id) }
            page += 1
            canLoadMore = !result.isEmpty
            errorMessage = nil
            cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
        } catch is CancellationError { } catch {
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
    }

    private func fetchPage(
        _ page: Int,
        limit: Int,
        source: FeedSource,
        flashCategory: String? = nil
    ) async throws -> [Post] {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let result: [Post]
                if source == .flash {
                    result = try await fetchFlashPosts(page, limit, flashCategory)
                } else {
                    result = try await fetchPosts(page, limit, source)
                }
                if source == .newYorkTimes {
                    return try await prefetchNewYorkTimesBodies(for: result)
                }
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard attempt == 0 else { break }
                try await Task.sleep(for: .milliseconds(450))
            }
        }
        throw lastError ?? APIError.invalidResponse
    }

    private func handleRealtime(_ event: RealtimeFeedClient.Event) {
        switch event {
        case .post(let post):
            receiveRealtimePost(post)
        case .taskCompleted(let name):
            guard task(name, updates: source) else { return }
            guard pendingRealtimePosts.isEmpty else { return }
            Task { await refresh() }
        case .deploymentStatus:
            break
        }
    }

    func receiveRealtimePost(_ post: Post) {
        guard !isSwitchingSource, matchesCurrentSource(post) else { return }
        errorMessage = nil
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index] = post
        } else if let index = pendingRealtimePosts.firstIndex(where: { $0.id == post.id }) {
            pendingRealtimePosts[index] = post
        } else {
            pendingRealtimePosts.insert(post, at: 0)
        }
        cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
    }

    func acceptPendingRealtimePosts() {
        guard !pendingRealtimePosts.isEmpty else { return }
        let existingIDs = Set(posts.map(\.id))
        posts.insert(contentsOf: pendingRealtimePosts.filter { !existingIDs.contains($0.id) }, at: 0)
        pendingRealtimePosts = []
        cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
    }

    func matchesCurrentSource(_ post: Post) -> Bool {
        switch source {
        case .newYorkTimes: return post.source == FeedSource.newYorkTimes.rawValue
        case .x: return post.sourceName == "X"
        case .bilibili: return post.isBilibili
        case .zhihu: return post.sourceName == "知乎"
        case .truth: return post.sourceName == "Truth"
        case .xueqiu: return post.isXueqiu
        case .rss: return post.isRSS && !post.hasDedicatedFeedTab
        case .laozhong: return post.isRSS && post.tagNames.contains("老中")
        case .youtube: return post.isRSS && post.tagNames.contains("YouTube")
        case .flash:
            guard post.isFlash else { return false }
            guard let selectedFlashCategory else { return true }
            return post.meta?.flashCategory == selectedFlashCategory
        case .weibo, .douyin: return false
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
        case .xueqiu: return name == "rss"
        case .rss, .laozhong, .youtube: return name == "rss"
        case .flash: return name.contains("flash")
        }
    }
}

@MainActor
final class WeiboFollowingFeedModel: ObservableObject {
    @Published private(set) var posts: [Post] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = true
    @Published var errorMessage: String?

    private var page = 1
    private let pageSize: Int
    private let fetchPosts: (Int, Int) async throws -> [Post]

    init(
        pageSize: Int = 20,
        fetchPosts: ((Int, Int) async throws -> [Post])? = nil
    ) {
        self.pageSize = pageSize
        if let fetchPosts {
            self.fetchPosts = fetchPosts
        } else {
            let client = APIClient(baseURL: ServerConfiguration.currentURL)
            self.fetchPosts = { page, limit in
                try await client.fetchWeiboFollowingPosts(page: page, limit: limit)
            }
        }
    }

    func loadInitial() async {
        guard posts.isEmpty, !isLoading else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await fetchPosts(1, pageSize)
            guard !Task.isCancelled else { return }
            posts = result
            page = 1
            canLoadMore = !result.isEmpty
        } catch is CancellationError {
            return
        } catch {
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
    }

    func loadMoreIfNeeded(current post: Post) async {
        guard post.id == posts.last?.id, canLoadMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await fetchPosts(page + 1, pageSize)
            guard !Task.isCancelled else { return }
            let existingIDs = Set(posts.map(\.id))
            posts += result.filter { !existingIDs.contains($0.id) }
            page += 1
            canLoadMore = !result.isEmpty
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
    }
}
