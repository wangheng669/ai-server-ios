import Foundation
import Combine
import CryptoKit

struct FeedDiskSnapshot: Codable {
    let schemaVersion: Int
    let savedAt: Date
    let source: String
    let flashCategory: String?
    let posts: [Post]
    let page: Int
    let canLoadMore: Bool
}

struct RSSCardTranslation: Equatable {
    let title: String
    let excerpt: String?

    static func translated(
        title: String,
        excerpt: String?,
        using translate: (String) async throws -> String
    ) async throws -> RSSCardTranslation {
        let translatedTitle = try await translate(title)
        let translatedExcerpt: String? = if let excerpt {
            try? await translate(excerpt)
        } else { nil }
        return RSSCardTranslation(title: translatedTitle, excerpt: translatedExcerpt)
    }
}

actor FeedDiskCache {
    static let shared = FeedDiskCache()

    private let directory: URL
    private let maximumBytes: Int
    private let maximumAge: TimeInterval

    init(
        directory: URL? = nil,
        maximumBytes: Int = 32 * 1024 * 1024,
        maximumAge: TimeInterval = 7 * 24 * 60 * 60
    ) {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? root.appendingPathComponent("OfflineFeedSnapshots", isDirectory: true)
        self.maximumBytes = max(1, maximumBytes)
        self.maximumAge = max(1, maximumAge)
    }

    func load(source: FeedSource, flashCategory: String?, serverURL: URL) -> FeedDiskSnapshot? {
        prepareDirectory()
        let fileURL = snapshotURL(source: source, flashCategory: flashCategory, serverURL: serverURL)
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              let snapshot = try? JSONDecoder().decode(FeedDiskSnapshot.self, from: data),
              snapshot.schemaVersion == 1,
              snapshot.source == source.rawValue,
              snapshot.flashCategory == flashCategory,
              Date().timeIntervalSince(snapshot.savedAt) <= maximumAge else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return snapshot
    }

    func save(_ snapshot: FeedDiskSnapshot, serverURL: URL) {
        guard !snapshot.posts.isEmpty else { return }
        prepareDirectory()
        let bounded = FeedDiskSnapshot(
            schemaVersion: 1,
            savedAt: snapshot.savedAt,
            source: snapshot.source,
            flashCategory: snapshot.flashCategory,
            posts: Array(snapshot.posts.prefix(100)),
            page: snapshot.page,
            canLoadMore: snapshot.canLoadMore
        )
        guard let source = FeedSource(rawValue: snapshot.source),
              let data = try? JSONEncoder().encode(bounded) else { return }
        let fileURL = snapshotURL(source: source, flashCategory: snapshot.flashCategory, serverURL: serverURL)
        do {
            try data.write(to: fileURL, options: .atomic)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = fileURL
            try? mutableURL.setResourceValues(values)
            trim()
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func remove(source: FeedSource, flashCategory: String?, serverURL: URL) {
        try? FileManager.default.removeItem(at: snapshotURL(source: source, flashCategory: flashCategory, serverURL: serverURL))
    }

    func trim() {
        prepareDirectory()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }
        let expiration = Date().addingTimeInterval(-maximumAge)
        var entries: [(url: URL, bytes: Int, date: Date)] = []
        for fileURL in files {
            guard let values = try? fileURL.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            let date = values.contentModificationDate ?? .distantPast
            if date < expiration {
                try? FileManager.default.removeItem(at: fileURL)
            } else {
                entries.append((fileURL, values.fileSize ?? 0, date))
            }
        }
        var totalBytes = entries.reduce(0) { $0 + $1.bytes }
        guard totalBytes > maximumBytes else { return }
        entries.sort { $0.date < $1.date }
        for oldest in entries {
            guard totalBytes > maximumBytes else { break }
            try? FileManager.default.removeItem(at: oldest.url)
            totalBytes -= oldest.bytes
        }
    }

    private func prepareDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = directory
        try? mutableURL.setResourceValues(values)
    }

    private func snapshotURL(source: FeedSource, flashCategory: String?, serverURL: URL) -> URL {
        let identity = [serverURL.absoluteString, source.rawValue, flashCategory ?? "all"].joined(separator: "|")
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(digest).json", isDirectory: false)
    }
}

actor FeedPresentationPrewarmer {
    static let shared = FeedPresentationPrewarmer()

    func warm(_ posts: [Post], source: FeedSource) async {
        async let warmImages: Void = ImageLoader.prefetchFeedImages(for: posts, source: source)
        for post in posts {
            if post.isXueqiu {
                _ = post.xueqiuPresentation
            } else if post.isRSS {
                _ = post.htmlInlineAssetURLs
            }
        }
        await warmImages
    }
}

@MainActor
final class NewsFeedViewModel: ObservableObject {
    @Published private(set) var posts: [Post] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = true
    @Published private(set) var isSwitchingSource = false
    @Published private(set) var pendingRealtimePosts: [Post] = []
    @Published private var xPresentations: [Int: XPresentation] = [:]
    private(set) var isXTimelineScrolling = false
    @Published private(set) var rssFeeds: [RSSFeedSource] = []
    @Published private(set) var selectedRSSFeedID: Int?
    @Published private(set) var selectedRSSPosts: [Post] = []
    @Published private(set) var isLoadingRSSSelection = false
    @Published private(set) var isLoadingMoreRSSSelection = false
    @Published private(set) var canLoadMoreRSSSelection = true
    @Published private(set) var selectedWeChatFeedID: Int?
    @Published private(set) var selectedWeChatPosts: [Post] = []
    @Published private(set) var isLoadingWeChatSelection = false
    @Published private(set) var isLoadingMoreWeChatSelection = false
    @Published private(set) var canLoadMoreWeChatSelection = true
    @Published private(set) var selectedFlashCategory: String?
    @Published private(set) var selectedYouTubePerson: String?
    @Published private(set) var xFeedUsers: [XFeedUser] = []
    @Published private(set) var selectedXUserID: String?
    @Published private(set) var selectedXAuthor: String?
    @Published private(set) var selectedXueqiuFeedID: Int?
    @Published private(set) var xueqiuFeeds: [RSSFeedSource] = []
    @Published var errorMessage: String?
    @Published private(set) var source: FeedSource {
        didSet { UserDefaults.standard.set(source.rawValue, forKey: "feed.source") }
    }

    private struct Snapshot { var posts: [Post]; var page: Int; var canLoadMore: Bool }
    private var cache: [FeedSource: Snapshot] = [:]

    private struct PreparedPage {
        let snapshot: Snapshot
        let fetchedAt: Date?

        var isFresh: Bool {
            fetchedAt.map { Date().timeIntervalSince($0) < 60 } ?? false
        }
    }

    @Published private var preparedPages: [FeedSource: PreparedPage] = [:]
    private var openingRequests: [FeedSource: (id: UUID, task: Task<Snapshot, Error>)] = [:]
    private struct XPresentation {
        var translation: String?
        var quotedTranslation: String?
        var reply: XReplyContext?
        var detail: XTweetDetailItem?
    }

    private var pendingXPresentations: [Int: XPresentation] = [:]
    private var pendingXPostUpdates: [Int: Post] = [:]
    private var xPresentationPublishTask: Task<Void, Never>?
    private var xTimelinePrefetchTask: Task<Void, Never>?
    private var xTimelinePrefetchIDs: [Int] = []
    private var isCheckingXTimelineUpdates = false
    private var page = 1
    private let defaultPageSize = 5
    private var realtimeClient: RealtimeFeedClient?
    private var requestGeneration = UUID()
    private var firstPageTask: Task<Void, Never>?
    private var rssDirectoryTask: Task<Void, Never>?
    private var xueqiuDirectoryTask: Task<Void, Never>?
    private var xueqiuDirectoryLoadedAt: Date?
    private let fetchPosts: (Int, Int, FeedSource) async throws -> [Post]
    private let fetchFlashPosts: (Int, Int, String?) async throws -> [Post]
    private let fetchYouTubePosts: (Int, Int, String?) async throws -> [Post]
    private let fetchXPosts: (Int, Int, String?, Bool) async throws -> [Post]
    private let fetchXFeedUsers: () async throws -> [XFeedUser]
    private let fetchXueqiuFeeds: () async throws -> [RSSFeedSource]
    private let fetchXTranslation: (String) async throws -> XTranslation
    private let fetchXTweetDetail: (String) async throws -> XTweetDetailItem
    private let fetchRSSFeeds: () async throws -> [RSSFeedSource]
    private let fetchRSSFeedPosts: (Int, Int, Int) async throws -> [Post]
    private let fetchWeChatFeedPosts: (Int, Int, Int) async throws -> [Post]
    private let fetchPostDetail: (Int) async throws -> Post
    private let fetchNewYorkTimesArticle: (URL) async throws -> NewYorkTimesArticle
    private var loadingXTranslationIDs: Set<Int> = []
    private var loadingXQuotedTranslationIDs: Set<Int> = []
    private var loadingXReplyContextIDs: Set<Int> = []
    private var loadingXLiveDetailIDs: Set<Int> = []
    private var preloadedNewYorkTimesArticles: [Int: NewYorkTimesArticle] = [:]
    private var newYorkTimesPrefetchTask: Task<Void, Never>?
    private var rssSelectionGeneration = UUID()
    private var weChatSelectionGeneration = UUID()
    private var selectedRSSPage = 1
    private let selectedRSSPageSize = 20
    private var selectedWeChatPage = 1
    private let selectedWeChatPageSize = 20
    private let serverURL: URL
    private let diskCache: FeedDiskCache
    #if DEBUG
    private let usesFeedUIFixture: Bool
    #endif

    init(
        source initialSource: FeedSource? = nil,
        fetchPosts injectedFetchPosts: ((Int, Int, FeedSource) async throws -> [Post])? = nil,
        fetchFlashPosts: ((Int, Int, String?) async throws -> [Post])? = nil,
        fetchYouTubePosts: ((Int, Int, String?) async throws -> [Post])? = nil,
        fetchXPosts: ((Int, Int, String?) async throws -> [Post])? = nil,
        fetchXPostsWithCachePolicy: ((Int, Int, String?, Bool) async throws -> [Post])? = nil,
        fetchXFeedUsers: (() async throws -> [XFeedUser])? = nil,
        fetchXueqiuFeeds: (() async throws -> [RSSFeedSource])? = nil,
        fetchXTranslation: ((String) async throws -> XTranslation)? = nil,
        fetchXTweetDetail: ((String) async throws -> XTweetDetailItem)? = nil,
        fetchRSSFeeds: (() async throws -> [RSSFeedSource])? = nil,
        fetchRSSFeedPosts: ((Int, Int, Int) async throws -> [Post])? = nil,
        fetchWeChatFeedPosts: ((Int, Int, Int) async throws -> [Post])? = nil,
        fetchPostDetail: ((Int) async throws -> Post)? = nil,
        fetchNewYorkTimesArticle: ((URL) async throws -> NewYorkTimesArticle)? = nil,
        diskCache: FeedDiskCache = .shared
    ) {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let override = environment["AI_FEED_SOURCE"]
        let usesXFeedPreview = ProcessInfo.processInfo.arguments.contains("--x-feed-preview")
        let usesXueqiuTapPreview = ProcessInfo.processInfo.arguments.contains("--xueqiu-tap-preview")
        let fixture = environment["AI_FEED_UI_FIXTURE"].map { payload in
            do {
                return try JSONDecoder().decode([String: [Post]].self, from: Data(payload.utf8))
            } catch {
                preconditionFailure("Invalid feed UI fixture: \(error)")
            }
        }
        usesFeedUIFixture = fixture != nil
        let fetchPosts = fixture.map { posts in
            { (page: Int, limit: Int, source: FeedSource) async throws -> [Post] in
                Array((posts[source.rawValue] ?? []).dropFirst((page - 1) * limit).prefix(limit))
            }
        } ?? injectedFetchPosts
        #else
        let override: String? = nil
        let fetchPosts = injectedFetchPosts
        #endif
        source = initialSource
            ?? FeedSource(rawValue: override ?? UserDefaults.standard.string(forKey: "feed.source") ?? "x")
            ?? .x
        let serverURL = ServerConfiguration.currentURL
        self.serverURL = serverURL
        #if DEBUG
        self.diskCache = usesFeedUIFixture
            ? FeedDiskCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("feed-ui-fixture-\(UUID())"))
            : diskCache
        #else
        self.diskCache = diskCache
        #endif
        let client = APIClient(baseURL: serverURL)
        self.fetchXTranslation = fetchXTranslation ?? { tweetID in
            try await client.fetchXTranslation(tweetID: tweetID)
        }
        self.fetchXTweetDetail = fetchXTweetDetail ?? { tweetID in
            try await client.fetchXTweetDetail(tweetID: tweetID)
        }
        self.fetchXFeedUsers = fetchXFeedUsers ?? { try await client.fetchXFeedUsers() }
        self.fetchXueqiuFeeds = fetchXueqiuFeeds ?? { try await client.fetchXueqiuFeeds() }
        if let fetchXPostsWithCachePolicy {
            self.fetchXPosts = fetchXPostsWithCachePolicy
        } else if let fetchXPosts {
            self.fetchXPosts = { page, limit, author, _ in
                try await fetchXPosts(page, limit, author)
            }
        } else if let fetchPosts {
            self.fetchXPosts = { page, limit, _, _ in try await fetchPosts(page, limit, .x) }
        } else {
            self.fetchXPosts = { page, limit, author, bypassCache in
                #if DEBUG
                if usesXFeedPreview { return page == 1 ? Self.xFeedPreviewPosts : [] }
                #endif
                return try await client.fetchPosts(
                    page: page,
                    limit: limit,
                    source: .x,
                    xUserID: author,
                    bypassCache: bypassCache
                )
            }
        }
        self.fetchRSSFeeds = fetchRSSFeeds ?? { try await client.fetchRSSFeeds() }
        self.fetchRSSFeedPosts = fetchRSSFeedPosts ?? { feedID, page, limit in
            try await client.fetchRSSFeedPosts(feedID: feedID, page: page, limit: limit)
        }
        self.fetchWeChatFeedPosts = fetchWeChatFeedPosts ?? fetchRSSFeedPosts ?? { feedID, page, limit in
            try await client.fetchRSSFeedPosts(
                feedID: feedID,
                page: page,
                limit: limit,
                includesAllScores: true
            )
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
        if let fetchYouTubePosts {
            self.fetchYouTubePosts = fetchYouTubePosts
        } else if let fetchPosts {
            self.fetchYouTubePosts = { page, limit, _ in
                try await fetchPosts(page, limit, .youtube)
            }
        } else {
            self.fetchYouTubePosts = { page, limit, person in
                try await client.fetchPosts(
                    page: page,
                    limit: limit,
                    source: .youtube,
                    youtubePerson: person
                )
            }
        }
        #if DEBUG
        if usesXueqiuTapPreview {
            self.fetchPosts = { _, _, _ in Self.xueqiuTapPreviewPosts }
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

    func loadRSSFeedsIfNeeded(forceRefresh: Bool = false) async {
        guard !Task.isCancelled else { return }
        if let rssDirectoryTask {
            await rssDirectoryTask.value
            return
        }
        guard forceRefresh || rssFeeds.isEmpty else { return }
        let task = Task {
            defer { rssDirectoryTask = nil }
            if let feeds = try? await fetchRSSFeeds() {
                rssFeeds = feeds
            }
        }
        rssDirectoryTask = task
        await task.value
    }

    func selectRSSFeed(_ feedID: Int?) async {
        let generation = UUID()
        rssSelectionGeneration = generation
        isLoadingMoreRSSSelection = false
        selectedRSSFeedID = feedID
        selectedRSSPosts = []
        selectedRSSPage = 1
        canLoadMoreRSSSelection = true
        guard let feedID else {
            isLoadingRSSSelection = false
            return
        }
        isLoadingRSSSelection = true
        defer { if rssSelectionGeneration == generation { isLoadingRSSSelection = false } }
        do {
            let key = "\(serverURL.absoluteString)|rss-account|\(feedID)"
            async let fresh = fetchRSSFeedPosts(feedID, 1, selectedRSSPageSize)
            if let saved = await DisplaySnapshotCache.pages.load([Post].self, key: key, maximumAge: 86400),
               !Task.isCancelled, rssSelectionGeneration == generation {
                selectedRSSPosts = saved.value
            }
            let result = try await fresh
            guard !Task.isCancelled, rssSelectionGeneration == generation else { return }
            selectedRSSPosts = result
            await DisplaySnapshotCache.pages.save(result, key: key, at: Date())
            guard !Task.isCancelled, rssSelectionGeneration == generation else { return }
            canLoadMoreRSSSelection = !result.isEmpty
            errorMessage = nil
            schedulePresentationPrewarm(for: result)
            scheduleSelectedRSSNewYorkTimesPrefetch(for: result, feedID: feedID)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, rssSelectionGeneration == generation else { return }
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
        let generation = rssSelectionGeneration
        isLoadingMoreRSSSelection = true
        defer { if rssSelectionGeneration == generation { isLoadingMoreRSSSelection = false } }
        do {
            let result = try await fetchRSSFeedPosts(feedID, nextPage, selectedRSSPageSize)
            guard !Task.isCancelled, rssSelectionGeneration == generation else { return }
            var existingIDs = Set(selectedRSSPosts.map(\.id))
            selectedRSSPosts += result.filter { existingIDs.insert($0.id).inserted }
            selectedRSSPage = nextPage
            canLoadMoreRSSSelection = !result.isEmpty
            errorMessage = nil
            schedulePresentationPrewarm(for: result)
            scheduleSelectedRSSNewYorkTimesPrefetch(for: result, feedID: feedID)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, rssSelectionGeneration == generation else { return }
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
    }

    func selectWeChatFeed(_ feedID: Int?) async {
        let generation = UUID()
        weChatSelectionGeneration = generation
        isLoadingMoreWeChatSelection = false
        selectedWeChatFeedID = feedID
        selectedWeChatPosts = []
        selectedWeChatPage = 1
        canLoadMoreWeChatSelection = true
        guard let feedID else {
            isLoadingWeChatSelection = false
            return
        }
        isLoadingWeChatSelection = true
        defer { if weChatSelectionGeneration == generation { isLoadingWeChatSelection = false } }
        do {
            let key = "\(serverURL.absoluteString)|weChat-account|\(feedID)"
            async let fresh = fetchWeChatFeedPosts(feedID, 1, selectedWeChatPageSize)
            if let saved = await DisplaySnapshotCache.pages.load([Post].self, key: key, maximumAge: 86400),
               !Task.isCancelled, weChatSelectionGeneration == generation {
                selectedWeChatPosts = saved.value
            }
            let result = try await fresh
            guard !Task.isCancelled, weChatSelectionGeneration == generation else { return }
            selectedWeChatPosts = result
            await DisplaySnapshotCache.pages.save(result, key: key, at: Date())
            guard !Task.isCancelled, weChatSelectionGeneration == generation else { return }
            canLoadMoreWeChatSelection = !result.isEmpty
            errorMessage = nil
            schedulePresentationPrewarm(for: result)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, weChatSelectionGeneration == generation else { return }
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
    }

    func loadMoreSelectedWeChatIfNeeded(current post: Post) async {
        guard let feedID = selectedWeChatFeedID,
              post.id == selectedWeChatPosts.last?.id,
              canLoadMoreWeChatSelection,
              !isLoadingWeChatSelection,
              !isLoadingMoreWeChatSelection else { return }
        let nextPage = selectedWeChatPage + 1
        let generation = weChatSelectionGeneration
        isLoadingMoreWeChatSelection = true
        defer { if weChatSelectionGeneration == generation { isLoadingMoreWeChatSelection = false } }
        do {
            let result = try await fetchWeChatFeedPosts(feedID, nextPage, selectedWeChatPageSize)
            guard !Task.isCancelled, weChatSelectionGeneration == generation else { return }
            var existingIDs = Set(selectedWeChatPosts.map(\.id))
            selectedWeChatPosts += result.filter { existingIDs.insert($0.id).inserted }
            selectedWeChatPage = nextPage
            canLoadMoreWeChatSelection = !result.isEmpty
            errorMessage = nil
            schedulePresentationPrewarm(for: result)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, weChatSelectionGeneration == generation else { return }
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
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

    func selectYouTubePerson(_ person: String?) async {
        let normalized = person?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selection = normalized?.isEmpty == false ? normalized : nil
        guard source == .youtube, selectedYouTubePerson != selection else { return }
        selectedYouTubePerson = selection
        posts = []
        pendingRealtimePosts = []
        page = 1
        canLoadMore = true
        cache[.youtube] = nil
        await refresh()
    }

    func loadXFeedUsersIfNeeded() async {
        guard xFeedUsers.isEmpty else { return }
        do {
            xFeedUsers = try await fetchXFeedUsers()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, source == .x else { return }
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
    }

    func selectXUser(_ user: XFeedUser?) async {
        guard source == .x, selectedXUserID != user?.id else { return }
        pendingXPostUpdates.removeAll(keepingCapacity: true)
        setXTimelineScrolling(false)
        selectedXUserID = user?.id
        selectedXAuthor = user?.screenName
        posts = []
        pendingRealtimePosts = []
        page = 1
        canLoadMore = true
        cache[.x] = nil
        await refresh()
    }

    func prepareXueqiuForOpening() async {
        async let directory: Void = loadXueqiuDirectory()
        await prepareSource(.xueqiu)
        await directory
    }

    func loadXueqiuDirectory() async {
        if let xueqiuDirectoryTask { await xueqiuDirectoryTask.value; return }
        if let xueqiuDirectoryLoadedAt, Date().timeIntervalSince(xueqiuDirectoryLoadedAt) < 300 { return }
        let task = Task {
            defer { xueqiuDirectoryTask = nil }
            do {
                let feeds = try await fetchXueqiuFeeds()
                xueqiuFeeds = feeds
                xueqiuDirectoryLoadedAt = Date()
                if let selection = selectedXueqiuFeedID, !feeds.contains(where: { $0.id == selection }) {
                    if source == .xueqiu {
                        await selectXueqiuFeed(nil)
                    } else {
                        selectedXueqiuFeedID = nil
                        cache[.xueqiu] = nil
                    }
                }
            } catch {
                if source == .xueqiu { errorMessage = NetworkErrorPresentation.message(for: error) }
            }
        }
        xueqiuDirectoryTask = task
        await task.value
    }

    func selectXueqiuFeed(_ feedID: Int?) async {
        guard source == .xueqiu, selectedXueqiuFeedID != feedID else { return }
        if let feedID, !xueqiuFeeds.contains(where: { $0.id == feedID }) { return }
        selectedXueqiuFeedID = feedID
        posts = []
        pendingRealtimePosts = []
        page = 1
        canLoadMore = false
        cache[.xueqiu] = nil
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
                    let hasStoredArticle = (detail.contentZH ?? detail.content)
                        .flatMap(NewYorkTimesArticle.storedText) != nil
                    guard let link = detail.linkURL ?? post.linkURL else {
                        guard hasStoredArticle else { throw APIError.invalidURL }
                        return (index, detail, nil)
                    }
                    do {
                        return (index, detail, try await fetchNewYorkTimesArticle(link))
                    } catch {
                        guard hasStoredArticle else { throw error }
                        return (index, detail, nil)
                    }
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

    func postForDisplay(_ post: Post, includePending: Bool = false) -> Post {
        guard let presentation = includePending ? xPresentation(for: post.id) : xPresentations[post.id] else {
            return post
        }
        var displayed = post
        if let detail = presentation.detail { displayed = displayed.replacingXLiveDetail(with: detail) }
        if let translation = presentation.translation { displayed = displayed.replacingTranslation(with: translation) }
        if let translation = presentation.quotedTranslation {
            displayed = displayed.replacingXQuotedTranslation(with: translation)
        }
        if let reply = presentation.reply { displayed = displayed.replacingXReplyContext(with: reply) }
        return displayed
    }

    private func xPresentation(for postID: Int) -> XPresentation? {
        pendingXPresentations[postID] ?? xPresentations[postID]
    }

    private func stageXPresentation(for postID: Int, update: (inout XPresentation) -> Void) {
        var presentation = xPresentation(for: postID) ?? XPresentation()
        update(&presentation)
        pendingXPresentations[postID] = presentation
        scheduleXPresentationPublish()
    }

    func preloadedNewYorkTimesArticle(for postID: Int) -> NewYorkTimesArticle? {
        preloadedNewYorkTimesArticles[postID]
    }

    func posts(for source: FeedSource) -> [Post] {
        if source == self.source { return posts }
        return cache[source]?.posts ?? preparedPage(for: source)?.snapshot.posts ?? []
    }

    func hasLoadedFirstPage(for source: FeedSource) -> Bool {
        cache[source] != nil || preparedPage(for: source)?.isFresh == true
    }

    func prepareXAuthorPost(_ post: Post) async {
        if !post.isXRetweetWrapper {
            await loadXEngagementIfNeeded(post)
        }
        guard !Task.isCancelled else { return }
        await translateXPostIfNeeded(postForDisplay(post))
    }

    func translateXPostIfNeeded(_ post: Post) async {
        if post.isXRetweetWrapper {
            await loadXRetweetPresentationIfNeeded(post)
        } else {
            await translateXMainPostIfNeeded(post)
            await translateXQuotedPostIfNeeded(post)
        }
        await loadAndTranslateXReplyContextIfNeeded(post)
    }

    private func translateXMainPostIfNeeded(_ post: Post) async {
        guard post.needsXTranslation,
              let tweetID = post.xTweetID,
              xPresentation(for: post.id)?.translation == nil,
              !loadingXTranslationIDs.contains(post.id) else { return }
        loadingXTranslationIDs.insert(post.id)
        defer { loadingXTranslationIDs.remove(post.id) }
        do {
            let value = try await resolvedXTranslation(tweetID: tweetID, sourceText: post.xStoredOriginalContent)
            guard !Task.isCancelled else { return }
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, normalized != post.originalDisplayContent, Self.containsHanCharacters(normalized) else { return }
            stageXPresentation(for: post.id) { $0.translation = normalized }
        } catch is CancellationError {
            return
        } catch {
            // Translation is best-effort. Keep the original post visible on failure.
        }
    }

    func translateXQuotedPostIfNeeded(_ post: Post) async {
        guard post.needsXQuotedTranslation,
              let quote = post.meta?.quotedTweet,
              let tweetID = quote.id,
              let sourceText = quote.originalText,
              xPresentation(for: post.id)?.quotedTranslation == nil,
              !loadingXQuotedTranslationIDs.contains(post.id) else { return }
        loadingXQuotedTranslationIDs.insert(post.id)
        defer { loadingXQuotedTranslationIDs.remove(post.id) }
        do {
            let value = try await resolvedXTranslation(tweetID: tweetID, sourceText: sourceText)
            guard !Task.isCancelled else { return }
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, normalized != sourceText, Self.containsHanCharacters(normalized) else { return }
            stageXPresentation(for: post.id) { $0.quotedTranslation = normalized }
        } catch is CancellationError {
            return
        } catch {
            // Translation is best-effort. Keep the quoted source post visible on failure.
        }
    }

    private func loadAndTranslateXReplyContextIfNeeded(_ post: Post) async {
        guard post.needsXReplyContextRefresh || post.needsXReplyContextTranslation,
              let replyID = post.meta?.inReplyToStatusID?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !replyID.isEmpty,
              xPresentation(for: post.id)?.reply == nil,
              !loadingXReplyContextIDs.contains(post.id) else { return }
        loadingXReplyContextIDs.insert(post.id)
        defer { loadingXReplyContextIDs.remove(post.id) }
        do {
            let stored = post.meta?.replyContext
            let detail: XTweetDetailItem? = if stored?.displayText == nil {
                try await fetchXTweetDetail(replyID)
            } else {
                nil
            }
            let sourceText = stored?.text ?? detail?.fullText ?? ""
            let language = detail?.lang?.lowercased()
            let translatedText: String? = if Self.containsHanCharacters(sourceText)
                || language?.hasPrefix("zh") == true {
                nil
            } else {
                try await resolvedXTranslation(tweetID: detail?.id ?? replyID, sourceText: sourceText)
            }
            guard !Task.isCancelled else { return }
            let reply = XReplyContext(
                id: detail?.id ?? stored?.id ?? replyID,
                authorName: detail?.author?.name ?? stored?.authorName,
                screenName: detail?.author?.screenName ?? stored?.screenName
                    ?? post.meta?.inReplyToScreenName,
                avatarURL: detail?.author?.profileImageURL ?? stored?.avatarURL,
                text: detail?.fullText ?? stored?.text,
                textZH: translatedText ?? stored?.textZH
            )
            stageXPresentation(for: post.id) { $0.reply = reply }
        } catch is CancellationError {
            return
        } catch {
            // Reply context is best-effort. Keep the compact reply label on failure.
        }
    }

    func loadXEngagementIfNeeded(_ post: Post) async {
        guard !post.isXRetweetWrapper,
              (post.meta?.metrics == nil || post.needsXLiveDetail),
              let tweetID = post.xTweetID,
              xPresentation(for: post.id)?.detail == nil,
              !loadingXLiveDetailIDs.contains(post.id) else { return }
        loadingXLiveDetailIDs.insert(post.id)
        defer { loadingXLiveDetailIDs.remove(post.id) }
        do {
            let detail = try await fetchXTweetDetail(tweetID)
            guard !Task.isCancelled else { return }
            XAuthorVerificationStore.shared.recordLive(handle: detail.author?.screenName, verified: detail.author?.verified)
            stageXPresentation(for: post.id) { $0.detail = detail }
        } catch is CancellationError {
            return
        } catch {
            // Engagement counts are best-effort. Keep the stored post visible on failure.
        }
    }

    private func loadXRetweetPresentationIfNeeded(_ post: Post) async {
        guard let tweetID = post.xTweetID,
              xPresentation(for: post.id)?.detail == nil,
              !loadingXTranslationIDs.contains(post.id) else { return }
        loadingXTranslationIDs.insert(post.id)
        defer { loadingXTranslationIDs.remove(post.id) }
        do {
            let detail = try await fetchXTweetDetail(tweetID)
            guard !Task.isCancelled else { return }
            XAuthorVerificationStore.shared.recordLive(handle: detail.author?.screenName, verified: detail.author?.verified)
            stageXPresentation(for: post.id) { $0.detail = detail }

            guard detail.lang?.lowercased().hasPrefix("zh") != true,
                  xPresentation(for: post.id)?.translation == nil else { return }
            let value = try await resolvedXTranslation(tweetID: detail.id, sourceText: detail.fullText)
            guard !Task.isCancelled else { return }
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, normalized != detail.fullText else { return }
            stageXPresentation(for: post.id) { $0.translation = normalized }
        } catch is CancellationError {
            return
        } catch {
            // Keep the stored wrapper visible if live X presentation is unavailable.
        }
    }

    private func resolvedXTranslation(tweetID: String, sourceText: String) async throws -> String {
        try await FeedTranslationCache.shared.translateXPost(
            tweetID: tweetID, original: sourceText, using: fetchXTranslation
        )
    }

    private static func containsHanCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { (0x4E00...0x9FFF).contains(Int($0.value)) }
    }

    func setXTimelineScrolling(_ isScrolling: Bool) {
        guard isXTimelineScrolling != isScrolling else { return }
        isXTimelineScrolling = isScrolling
        if !isScrolling { scheduleXPresentationPublish() }
    }

    private func scheduleXPresentationPublish() {
        guard !isXTimelineScrolling, xPresentationPublishTask == nil,
              !pendingXPresentations.isEmpty || !pendingXPostUpdates.isEmpty else { return }
        xPresentationPublishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self else { return }
            xPresentationPublishTask = nil
            guard !isXTimelineScrolling else { return }
            if !pendingXPresentations.isEmpty {
                xPresentations.merge(pendingXPresentations) { _, latest in latest }
                pendingXPresentations.removeAll(keepingCapacity: true)
            }
            if !pendingXPostUpdates.isEmpty {
                let changes = pendingXPostUpdates
                pendingXPostUpdates.removeAll(keepingCapacity: true)
                if source == .x {
                    posts = posts.map { changes[$0.id] ?? $0 }
                    cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
                    persistCurrentSnapshot()
                    let updatedPosts = Array(changes.values)
                    schedulePresentationPrewarm(for: updatedPosts)
                    pretranslateTimeline(updatedPosts)
                }
            }
        }
    }

    #if DEBUG
    private static var xueqiuTapPreviewPosts: [Post] {
        let json = #"""
        [{
          "id": 990001,
          "source": "xueqiu",
          "content": "这是用于验证首次点击的雪球正文，包含<a href=\"https://xueqiu.com/123456\">网页链接</a>和 $AAPL$ 标记。",
          "formatted_time": "刚刚",
          "post_link": "https://xueqiu.com/990001",
          "user": {"user_name": "模拟雪球用户", "user_screen_name": "模拟雪球用户"},
          "meta": {
            "rss_feed_name": "雪球-模拟用户",
            "rss_article_link": "https://xueqiu.com/990001",
            "metrics": {"replies": 12, "likes": 34}
          }
        }, {
          "id": 990002,
          "source": "xueqiu",
          "content": "这是带有[滴汗]表情的雪球正文，用于验证正文区域首次点击。",
          "formatted_time": "1分钟前",
          "post_link": "https://xueqiu.com/990002",
          "user": {"user_name": "表情文章用户", "user_screen_name": "表情文章用户"},
          "images": [{
            "url": "https://assets.imedao.com/ugc/images/face/emoji_13_coldsweat.png?v=1",
            "height": 24,
            "alt_text": "[滴汗]",
            "kind": "inline_emoji"
          }],
          "meta": {
            "rss_feed_name": "雪球-表情文章用户",
            "rss_article_link": "https://xueqiu.com/990002",
            "metrics": {"replies": 5, "likes": 8}
          }
        }]
        """#
        return (try? JSONDecoder().decode([Post].self, from: Data(json.utf8))) ?? []
    }

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
          "meta": {
            "metrics": {"replies": 222, "retweets": 786, "likes": 12000, "views": 960000},
            "quoted_tweet": {"id": "99", "text": "引用原帖的完整内容", "author": {"name": "引用作者", "screenName": "quoted_author"}}
          }
        }]
        """#
        return (try? JSONDecoder().decode([Post].self, from: Data(json.utf8))) ?? []
    }
    #endif

    func select(_ next: FeedSource) {
        guard next != source else { return }
        if source == .x {
            pendingXPostUpdates.removeAll(keepingCapacity: true)
            cancelXTimelinePrefetch()
            setXTimelineScrolling(false)
        }
        requestGeneration = UUID()
        firstPageTask?.cancel()
        firstPageTask = nil
        isLoading = false
        isLoadingMore = false
        pendingRealtimePosts = []
        errorMessage = nil
        source = next

        // Recheck a previously empty channel on its next visit.
        if cache[next]?.posts.isEmpty == true { cache[next] = nil }
        let prepared = preparedPage(for: next)
        if cache[next] == nil, let prepared, prepared.isFresh {
            cache[next] = prepared.snapshot
        }
        let saved = cache[next] ?? prepared?.snapshot
        posts = saved?.posts ?? []
        page = saved?.page ?? 1
        canLoadMore = saved?.canLoadMore ?? true
        isSwitchingSource = cache[next] == nil
        if let saved {
            pretranslateTimeline(saved.posts)
        }
        if prepared?.isFresh == true {
            preparedPages.removeValue(forKey: next)
            persistCurrentSnapshot()
            if next == .newYorkTimes {
                scheduleNewYorkTimesPrefetch(for: posts, cancelsPrevious: true)
            }
        }

        // Retain shared work for the new page and either direction of the next swipe.
        let nearby = Set(adjacentSources(to: next) + [next, .xueqiu, .youtube, .flash])
        for candidate in Array(openingRequests.keys) where !nearby.contains(candidate) {
            openingRequests.removeValue(forKey: candidate)?.task.cancel()
        }
    }

    func loadInitial() async {
        guard !Task.isCancelled else { return }
        if let firstPageTask {
            await firstPageTask.value
            return
        }
        guard cache[source] == nil else { return }
        if posts.isEmpty, let prepared = preparedPage(for: source) {
            showPreparedSnapshot(prepared.snapshot)
        }
        await startFirstPage(restoringSnapshot: true)
    }

    func prepareVideoAndFlashPages() async {
        async let videos: Void = prepareSource(.youtube)
        await prepareSource(.flash)
        await videos
    }

    func prepareAdjacentSources() async {
        let neighbors = adjacentSources(to: source)
        async let first: Void = prepareSource(neighbors.first)
        if neighbors.count == 2 { await prepareSource(neighbors.last) }
        await first
    }

    private func adjacentSources(to source: FeedSource) -> [FeedSource] {
        let sources = FeedSource.allCases
        guard let index = sources.firstIndex(of: source) else { return [] }
        return [index - 1, index + 1].filter(sources.indices.contains).map { sources[$0] }
    }

    private func usesDefaultFeed(_ source: FeedSource) -> Bool {
        switch source {
        case .flash: selectedFlashCategory == nil
        case .youtube: selectedYouTubePerson == nil
        case .x: selectedXUserID == nil
        case .xueqiu: selectedXueqiuFeedID == nil
        default: true
        }
    }

    private func preparedPage(for source: FeedSource) -> PreparedPage? {
        usesDefaultFeed(source) ? preparedPages[source] : nil
    }

    private func prepareSource(_ source: FeedSource?) async {
        guard !Task.isCancelled, let source, usesDefaultFeed(source), cache[source] == nil else { return }
        _ = try? await openingPage(for: source)
    }

    private func openingPage(for source: FeedSource) async throws -> Snapshot {
        if let prepared = preparedPages[source], prepared.isFresh { return prepared.snapshot }
        if let request = openingRequests[source] { return try await request.task.value }

        let id = UUID()
        let request = Task {
            defer {
                if openingRequests[source]?.id == id { openingRequests[source] = nil }
            }
            async let restoration: Void = restorePreparedPage(for: source)
            let limit = pageSize(for: source)
            do {
                let posts = try await fetchPage(1, limit: limit, source: source, bypassCache: source == .x)
                await restoration
                try Task.checkCancellation()
                let snapshot = Snapshot(posts: posts, page: 1, canLoadMore: hasMorePages(source, count: posts.count))
                if self.source != source || firstPageTask == nil {
                    preparedPages[source] = PreparedPage(snapshot: snapshot, fetchedAt: Date())
                    schedulePresentationPrewarm(for: posts, source: source)
                }
                return snapshot
            } catch {
                await restoration
                try Task.checkCancellation()
                if let apiError = error as? APIError, case .sourceUnavailable = apiError {
                    preparedPages[source] = nil
                    await diskCache.remove(source: source, flashCategory: nil, serverURL: serverURL)
                }
                throw error
            }
        }
        openingRequests[source] = (id, request)
        return try await request.value
    }

    private func restorePreparedPage(for source: FeedSource) async {
        guard preparedPages[source] == nil,
              let saved = await diskCache.load(source: source, flashCategory: nil, serverURL: serverURL),
              !Task.isCancelled, preparedPages[source] == nil else { return }
        let snapshot = Snapshot(posts: saved.posts, page: saved.page, canLoadMore: saved.canLoadMore)
        if source == self.source, posts.isEmpty, isLoading, usesDefaultFeed(source) {
            showPreparedSnapshot(snapshot)
        }
        preparedPages[source] = PreparedPage(snapshot: snapshot, fetchedAt: nil)
        schedulePresentationPrewarm(for: snapshot.posts, source: source)
    }

    private func showPreparedSnapshot(_ snapshot: Snapshot) {
        posts = snapshot.posts
        page = snapshot.page
        canLoadMore = snapshot.canLoadMore
        pretranslateTimeline(snapshot.posts)
    }

    private func hasMorePages(_ source: FeedSource, count: Int) -> Bool {
        source == .xueqiu || source == .wechat ? count == pageSize(for: source) : count > 0
    }

    private func pageSize(for source: FeedSource) -> Int {
        switch source {
        case .wechat, .weibo, .douyin, .baidu, .truth: 20
        case .flash: 20
        case .x: 10
        case .youtube: 10
        default: defaultPageSize
        }
    }

    func startRealtime() {
        #if DEBUG
        guard !usesFeedUIFixture else { return }
        #endif
        guard realtimeClient == nil else { return }
        let client = RealtimeFeedClient(baseURL: ServerConfiguration.currentURL)
        client.onEvent = { [weak self] event in self?.handleRealtime(event) }
        realtimeClient = client
        client.start()
    }

    func stopRealtime() {
        realtimeClient?.stop()
        realtimeClient = nil
    }

    func refresh() async {
        await startFirstPage(restoringSnapshot: false)
    }

    private func startFirstPage(restoringSnapshot: Bool) async {
        guard !Task.isCancelled else { return }
        let generation = UUID()
        requestGeneration = generation
        firstPageTask?.cancel()
        if !restoringSnapshot {
            if source == .x {
                pendingXPostUpdates.removeAll(keepingCapacity: true)
                cancelXTimelinePrefetch()
            }
            openingRequests.removeValue(forKey: source)?.task.cancel()
            if preparedPages[source] != nil { preparedPages[source] = nil }
        }
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        // The view and background preload share this request across tab visibility changes.
        let task = Task { await loadFirstPage(restoringSnapshot: restoringSnapshot, generation: generation) }
        firstPageTask = task
        await task.value
    }

    private func loadFirstPage(restoringSnapshot: Bool, generation: UUID) async {
        defer {
            if requestGeneration == generation {
                firstPageTask = nil
                isLoading = false
            }
        }
        guard !Task.isCancelled, requestGeneration == generation else { return }
        let requestedSource = source
        let requestedFlashCategory = requestedSource == .flash ? selectedFlashCategory : nil
        let requestedYouTubePerson = selectedYouTubePerson
        let requestedXUserID = selectedXUserID

        let sharesOpeningPage = restoringSnapshot && usesDefaultFeed(requestedSource)
        let restoresFilteredFlash = restoringSnapshot && requestedSource == .flash && !sharesOpeningPage
        async let restoration: Void = restoresFilteredFlash
            ? restoreDiskSnapshot(source: requestedSource, flashCategory: requestedFlashCategory, generation: generation)
            : ()

        do {
            let snapshot: Snapshot
            if sharesOpeningPage {
                snapshot = try await openingPage(for: requestedSource)
            } else {
                let result = try await fetchPage(
                    1,
                    limit: pageSize(for: requestedSource),
                    source: requestedSource,
                    flashCategory: requestedFlashCategory,
                    youtubePerson: requestedYouTubePerson,
                    xAuthor: requestedXUserID,
                    xueqiuFeedID: selectedXueqiuFeedID,
                    bypassCache: requestedSource == .x || !restoringSnapshot
                )
                snapshot = Snapshot(posts: result, page: 1, canLoadMore: hasMorePages(requestedSource, count: result.count))
            }
            await restoration
            guard !Task.isCancelled, requestGeneration == generation else { return }
            let result = snapshot.posts
            if requestedSource == .x, restoringSnapshot, !posts.isEmpty {
                if preparedPages[requestedSource] != nil { preparedPages[requestedSource] = nil }
                cache[requestedSource] = Snapshot(posts: posts, page: page, canLoadMore: canLoadMore)
                isSwitchingSource = false
                enqueueNewXTimelinePosts(result)
                return
            }
            if requestedSource == .x {
                pendingXPostUpdates.removeAll(keepingCapacity: true)
                pretranslateTimeline(result)
                schedulePresentationPrewarm(for: result)
            }
            posts = result
            pendingRealtimePosts = []
            page = snapshot.page
            canLoadMore = snapshot.canLoadMore
            isSwitchingSource = false
            cache[requestedSource] = snapshot
            if preparedPages[requestedSource] != nil { preparedPages[requestedSource] = nil }
            persistCurrentSnapshot()
            if requestedSource != .x { schedulePresentationPrewarm(for: result) }
            if requestedSource == .newYorkTimes {
                scheduleNewYorkTimesPrefetch(for: result, cancelsPrevious: true)
            }
        } catch is CancellationError { } catch {
            await restoration
            guard !Task.isCancelled, requestGeneration == generation else { return }
            isSwitchingSource = false
            errorMessage = NetworkErrorPresentation.message(for: error)
            if let apiError = error as? APIError, case .sourceUnavailable = apiError {
                posts = []
                pendingRealtimePosts = []
                canLoadMore = false
                cache.removeValue(forKey: requestedSource)
                if !sharesOpeningPage {
                    await diskCache.remove(source: requestedSource, flashCategory: requestedFlashCategory, serverURL: serverURL)
                }
            }
        }
    }

    func loadMoreIfNeeded(current post: Post, thresholdPostID: Int? = nil) async {
        guard !Task.isCancelled,
              !isSwitchingSource,
              post.id == (thresholdPostID ?? posts.last?.id),
              canLoadMore,
              !isLoadingMore,
              !isLoading else { return }
        let generation = requestGeneration
        let requestedSource = source
        let requestedFlashCategory = requestedSource == .flash ? selectedFlashCategory : nil
        let requestedYouTubePerson = selectedYouTubePerson
        let requestedXUserID = selectedXUserID
        let pageSize = pageSize(for: requestedSource)
        isLoadingMore = true
        defer { if requestGeneration == generation { isLoadingMore = false } }
        do {
            let result = try await fetchPage(
                page + 1,
                limit: pageSize,
                source: requestedSource,
                flashCategory: requestedFlashCategory,
                youtubePerson: requestedYouTubePerson,
                xAuthor: requestedXUserID,
                xueqiuFeedID: selectedXueqiuFeedID
            )
            guard !Task.isCancelled, requestGeneration == generation else { return }
            var ids = Set(posts.map(\.id))
            let added = result.filter { ids.insert($0.id).inserted }
            schedulePresentationPrewarm(for: added)
            pretranslateTimeline(added)
            posts += added
            page += 1
            canLoadMore = hasMorePages(requestedSource, count: result.count)
            errorMessage = nil
            cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
            persistCurrentSnapshot()
            if requestedSource == .newYorkTimes {
                scheduleNewYorkTimesPrefetch(for: result, cancelsPrevious: false)
            }
        } catch is CancellationError { } catch {
            guard !Task.isCancelled, requestGeneration == generation else { return }
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
    }

    private func fetchPage(
        _ page: Int,
        limit: Int,
        source: FeedSource,
        flashCategory: String? = nil,
        youtubePerson: String? = nil,
        xAuthor: String? = nil,
        xueqiuFeedID: Int? = nil,
        bypassCache: Bool = false
    ) async throws -> [Post] {
        let result: [Post]
        switch source {
        case .flash:
            result = try await fetchFlashPosts(page, limit, flashCategory)
        case .youtube:
            result = try await fetchYouTubePosts(page, limit, youtubePerson)
        case .x:
            result = try await fetchXPosts(page, limit, xAuthor, bypassCache)
            XAuthorVerificationStore.shared.record(posts: result)
        case .xueqiu:
            if let xueqiuFeedID {
                result = try await fetchRSSFeedPosts(xueqiuFeedID, page, limit)
            } else {
                result = try await fetchPosts(page, limit, source)
            }
        default:
            result = try await fetchPosts(page, limit, source)
        }
        return result
    }

    var xTimelineNextPage: Int { page + 1 }

    private func pretranslateTimeline(_ posts: [Post]) {
        guard source == .x, !posts.isEmpty else { return }
        let candidates = Array(posts.prefix(10))
        for post in candidates where post.needsXTranslation && xPresentation(for: post.id)?.translation == nil {
            guard let tweetID = post.xTweetID else { continue }
            if let value = FeedTranslationCache.shared.cachedXTranslation(
                tweetID: tweetID, original: post.xStoredOriginalContent
            ) {
                stageXPresentation(for: post.id) { $0.translation = value }
            }
        }
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await runWithLimitedConcurrency(candidates, maximumConcurrentRequests: 2) { post in
                await self.translateXPostIfNeeded(post)
            }
        }
    }

    func prefetchXTimelineImages(for upcoming: [Post]) {
        guard source == .x, !upcoming.isEmpty else { return }
        let ids = upcoming.map(\.id)
        guard ids != xTimelinePrefetchIDs else { return }
        xTimelinePrefetchIDs = ids
        xTimelinePrefetchTask?.cancel()
        xTimelinePrefetchTask = Task(priority: .utility) {
            await ImageLoader.prefetchXTimelineImages(for: upcoming)
        }
    }

    private func cancelXTimelinePrefetch() {
        xTimelinePrefetchTask?.cancel()
        xTimelinePrefetchTask = nil
        xTimelinePrefetchIDs.removeAll(keepingCapacity: true)
    }

    private func schedulePresentationPrewarm(for posts: [Post], source: FeedSource? = nil) {
        let page = source ?? self.source
        Task(priority: .utility) { await FeedPresentationPrewarmer.shared.warm(posts, source: page) }
        guard #available(iOS 26.0, *), [.truth, .rss, .youtube].contains(page) else { return }
        Task {
            let originals = posts.prefix(10).flatMap { post -> [String] in
                switch page {
                case .truth:
                    return LocalTranslatedText.chineseText(post.truthChineseContent) == nil ? [post.originalDisplayContent] : []
                case .rss, .youtube:
                    let title = LocalTranslatedText.chineseText(post.feedChineseTitle) == nil ? [post.feedOriginalTitle] : []
                    return page == .rss ? title + [post.rssListContent] : title
                default:
                    return []
                }
            }
            await FeedTranslationCache.shared.pretranslate(originals)
        }
    }

    private func scheduleNewYorkTimesPrefetch(for posts: [Post], cancelsPrevious: Bool) {
        if cancelsPrevious { newYorkTimesPrefetchTask?.cancel() }
        newYorkTimesPrefetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let warmed = try await self.prefetchNewYorkTimesBodies(for: posts)
                guard !Task.isCancelled, self.source == .newYorkTimes else { return }
                let warmedByID = Dictionary(uniqueKeysWithValues: warmed.map { ($0.id, $0) })
                self.posts = self.posts.map { warmedByID[$0.id] ?? $0 }
                self.cache[.newYorkTimes] = .init(
                    posts: self.posts,
                    page: self.page,
                    canLoadMore: self.canLoadMore
                )
                self.persistCurrentSnapshot()
            } catch is CancellationError {
                return
            } catch {
                // The feed cards are already usable. Detail prefetch is best-effort.
            }
        }
    }

    private func scheduleSelectedRSSNewYorkTimesPrefetch(for posts: [Post], feedID: Int) {
        guard posts.contains(where: \.isNewYorkTimes) else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let warmed = try await self.prefetchNewYorkTimesBodies(for: posts)
                guard !Task.isCancelled, self.selectedRSSFeedID == feedID else { return }
                let warmedByID = Dictionary(uniqueKeysWithValues: warmed.map { ($0.id, $0) })
                self.selectedRSSPosts = self.selectedRSSPosts.map { warmedByID[$0.id] ?? $0 }
            } catch is CancellationError {
                return
            } catch {
                // The selected RSS list remains usable without detail prefetch.
            }
        }
    }

    private func handleRealtime(_ event: RealtimeFeedClient.Event) {
        switch event {
        case .post(let post):
            Task { @MainActor [weak self] in
                self?.receiveRealtimePost(post)
            }
        case .taskCompleted(let name):
            guard task(name, updates: source) else { return }
            guard pendingRealtimePosts.isEmpty else { return }
            if source == .x, !posts.isEmpty {
                Task { await checkForXTimelineUpdates() }
            } else {
                Task { await refresh() }
            }
        case .deploymentStatus:
            break
        }
    }

    func checkForXTimelineUpdates() async {
        guard source == .x, !isCheckingXTimelineUpdates, !isLoading else { return }
        isCheckingXTimelineUpdates = true
        defer { isCheckingXTimelineUpdates = false }
        let generation = requestGeneration
        guard let latest = try? await fetchPage(
            1, limit: pageSize(for: .x), source: .x, xAuthor: selectedXUserID, bypassCache: true
        ), !Task.isCancelled, requestGeneration == generation else { return }
        enqueueNewXTimelinePosts(latest)
    }

    private func enqueueNewXTimelinePosts(_ latest: [Post]) {
        var knownIDs = Set(posts.map(\.id) + pendingRealtimePosts.map(\.id))
        let additions = latest.filter { knownIDs.insert($0.id).inserted }
        guard !additions.isEmpty else { return }
        schedulePresentationPrewarm(for: additions)
        pretranslateTimeline(additions)
        pendingRealtimePosts.insert(contentsOf: additions, at: 0)
    }

    func receiveRealtimePost(_ post: Post) {
        guard !isSwitchingSource, matchesCurrentSource(post) else { return }
        if source == .x, let selectedXAuthor {
            let handle = post.user?.userScreenName?
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "@")))
                .lowercased()
            guard handle == selectedXAuthor.lowercased() else { return }
        }
        if source == .xueqiu, let selectedXueqiuFeedID {
            guard post.source?.lowercased() == "rss:\(selectedXueqiuFeedID)" else { return }
        }
        let existingIndex = posts.firstIndex(where: { $0.id == post.id })
        if source == .x, existingIndex != nil {
            pendingXPostUpdates[post.id] = post
            scheduleXPresentationPublish()
            return
        }
        schedulePresentationPrewarm(for: [post])
        pretranslateTimeline([post])
        errorMessage = nil
        if let index = existingIndex {
            posts[index] = post
        } else if let index = pendingRealtimePosts.firstIndex(where: { $0.id == post.id }) {
            pendingRealtimePosts[index] = post
            return
        } else {
            pendingRealtimePosts.insert(post, at: 0)
            return
        }
        cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
        persistCurrentSnapshot()
    }

    func acceptPendingRealtimePosts() {
        guard !pendingRealtimePosts.isEmpty else { return }
        let existingIDs = Set(posts.map(\.id))
        posts.insert(contentsOf: pendingRealtimePosts.filter { !existingIDs.contains($0.id) }, at: 0)
        pendingRealtimePosts = []
        cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
        persistCurrentSnapshot()
    }

    private func restoreDiskSnapshot(source: FeedSource, flashCategory: String?, generation: UUID) async {
        guard let snapshot = await diskCache.load(
            source: source,
            flashCategory: flashCategory,
            serverURL: serverURL
        ), !Task.isCancelled, requestGeneration == generation else { return }
        posts = snapshot.posts
        page = snapshot.page
        canLoadMore = snapshot.canLoadMore
        cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
        isSwitchingSource = false
        schedulePresentationPrewarm(for: posts)
        pretranslateTimeline(posts)
    }

    private func persistCurrentSnapshot() {
        guard (source != .youtube || selectedYouTubePerson == nil),
              (source != .x || selectedXUserID == nil),
              (source != .xueqiu || selectedXueqiuFeedID == nil) else { return }
        let snapshot = FeedDiskSnapshot(
            schemaVersion: 1,
            savedAt: Date(),
            source: source.rawValue,
            flashCategory: source == .flash ? selectedFlashCategory : nil,
            posts: posts,
            page: page,
            canLoadMore: canLoadMore
        )
        let serverURL = serverURL
        let diskCache = diskCache
        Task { await diskCache.save(snapshot, serverURL: serverURL) }
    }

    func matchesCurrentSource(_ post: Post) -> Bool {
        switch source {
        case .newYorkTimes: return post.source == source.rawValue
        case .wechat: return APIClient.weChatFeedIDs.contains { post.source == "rss:\($0)" }
        case .x: return post.sourceName == "X"
        case .bilibili: return post.isBilibili
        case .zhihu: return post.sourceName == "知乎"
        case .truth: return post.sourceName == "Truth"
        case .xueqiu: return xueqiuFeeds.contains { post.source == "rss:\($0.id)" }
        case .rss: return post.isRSS && !post.hasDedicatedFeedTab
        case .laozhong: return post.isRSS && post.tagNames.contains("老中")
        case .youtube: return post.isRSS && post.tagNames.contains("YouTube")
        case .flash:
            guard post.isFlash else { return false }
            guard let selectedFlashCategory else { return true }
            return post.meta?.flashCategory == selectedFlashCategory
        case .weibo, .douyin, .baidu: return false
        }
    }

    private func task(_ name: String, updates source: FeedSource) -> Bool {
        switch source {
        case .newYorkTimes, .wechat: return name == "rss"
        case .x: return name == "x" || name == "x_home" || name == "x_home_following"
        case .weibo: return name == "weibo_hot"
        case .douyin: return name == "douyin_hot"
        case .baidu: return false
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
    @Published private(set) var directoryPosts: [Post] = []
    @Published private(set) var selectedFeedID: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = true
    @Published var errorMessage: String?

    private var requestGeneration = UUID()
    private var page = 1
    private let pageSize: Int
    private let fetchPosts: (Int, Int, Int?) async throws -> [Post]

    init(
        pageSize: Int = 20,
        fetchPosts: ((Int, Int, Int?) async throws -> [Post])? = nil
    ) {
        self.pageSize = pageSize
        if let fetchPosts {
            self.fetchPosts = fetchPosts
        } else {
            let client = APIClient(baseURL: ServerConfiguration.currentURL)
            self.fetchPosts = { page, limit, feedID in
                try await client.fetchWeiboFollowingPosts(page: page, limit: limit, feedID: feedID)
            }
        }
    }

    func loadInitial() async {
        guard posts.isEmpty, !isLoading else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        let generation = UUID()
        requestGeneration = generation
        isLoadingMore = false
        isLoading = true
        errorMessage = nil
        defer {
            if requestGeneration == generation { isLoading = false }
        }
        do {
            let result = try await fetchPosts(1, pageSize, selectedFeedID)
            guard !Task.isCancelled, requestGeneration == generation else { return }
            var seen = Set<Int>()
            posts = result.filter { seen.insert($0.id).inserted }
            if selectedFeedID == nil { directoryPosts = posts }
            page = 1
            canLoadMore = !result.isEmpty
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, requestGeneration == generation else { return }
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
    }

    func selectFeed(_ feedID: Int?) async {
        guard selectedFeedID != feedID else { return }
        requestGeneration = UUID()
        isLoading = false
        isLoadingMore = false
        selectedFeedID = feedID
        posts = []
        page = 1
        canLoadMore = true
        await refresh()
    }

    func loadMoreIfNeeded(current post: Post) async {
        guard post.id == posts.last?.id,
              canLoadMore, !isLoading, !isLoadingMore else { return }
        let generation = requestGeneration
        isLoadingMore = true
        defer {
            if requestGeneration == generation { isLoadingMore = false }
        }
        do {
            let result = try await fetchPosts(page + 1, pageSize, selectedFeedID)
            guard !Task.isCancelled, requestGeneration == generation else { return }
            var existingIDs = Set(posts.map(\.id))
            posts += result.filter { existingIDs.insert($0.id).inserted }
            if selectedFeedID == nil { directoryPosts = posts }
            page += 1
            canLoadMore = !result.isEmpty
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, requestGeneration == generation else { return }
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
    }
}
