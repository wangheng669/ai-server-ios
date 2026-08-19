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
        entries.sort { $0.date < $1.date }
        while totalBytes > maximumBytes, !entries.isEmpty {
            let oldest = entries.removeFirst()
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

    func warm(_ posts: [Post]) {
        for post in posts {
            if post.isXueqiu {
                _ = post.xueqiuPresentation
            } else if post.isRSS {
                _ = post.htmlInlineAssetURLs
            }
        }
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
    @Published private(set) var xTranslations: [Int: String] = [:]
    @Published private(set) var xLiveDetails: [Int: XTweetDetailItem] = [:]
    @Published private(set) var rssCardTranslations: [Int: RSSCardTranslation] = [:]
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
    @Published private(set) var xueqiuDirectoryPosts: [Post] = []
    @Published var errorMessage: String?
    @Published var source: FeedSource {
        didSet { UserDefaults.standard.set(source.rawValue, forKey: "feed.source") }
    }

    private struct Snapshot { var posts: [Post]; var page: Int; var canLoadMore: Bool }
    private var cache: [FeedSource: Snapshot] = [:]
    private var pendingXTranslations: [Int: String] = [:]
    private var xTranslationPublishTask: Task<Void, Never>?
    private var pendingRSSCardTranslations: [Int: RSSCardTranslation] = [:]
    private var rssTranslationPublishTask: Task<Void, Never>?
    private var page = 1
    private let defaultPageSize = 5
    private var realtimeClient: RealtimeFeedClient?
    private var activeRefreshID: UUID?
    private let fetchPosts: (Int, Int, FeedSource) async throws -> [Post]
    private let fetchFlashPosts: (Int, Int, String?) async throws -> [Post]
    private let fetchYouTubePosts: (Int, Int, String?) async throws -> [Post]
    private let fetchXPosts: (Int, Int, String?) async throws -> [Post]
    private let fetchXFeedUsers: () async throws -> [XFeedUser]
    private let fetchXueqiuPosts: (Int, Int, Int?) async throws -> [Post]
    private let fetchXTranslation: (String) async throws -> XTranslation
    private let translateXFallback: (String) async throws -> String
    private let fetchXTweetDetail: (String) async throws -> XTweetDetailItem
    private let translateRSSCard: (String, String?) async throws -> RSSCardTranslation
    private let fetchRSSFeeds: () async throws -> [RSSFeedSource]
    private let fetchRSSFeedPosts: (Int, Int, Int) async throws -> [Post]
    private let fetchWeChatFeedPosts: (Int, Int, Int) async throws -> [Post]
    private let fetchPostDetail: (Int) async throws -> Post
    private let fetchNewYorkTimesArticle: (URL) async throws -> NewYorkTimesArticle
    private var loadingXTranslationIDs: Set<Int> = []
    private var loadingXLiveDetailIDs: Set<Int> = []
    private var loadingRSSTranslationIDs: Set<Int> = []
    private var preloadedNewYorkTimesArticles: [Int: NewYorkTimesArticle] = [:]
    private var selectedRSSPage = 1
    private let selectedRSSPageSize = 20
    private var selectedWeChatPage = 1
    private let selectedWeChatPageSize = 20
    private let serverURL: URL
    private let diskCache: FeedDiskCache
    private var restoredDiskKeys: Set<String> = []

    init(
        source initialSource: FeedSource? = nil,
        fetchPosts: ((Int, Int, FeedSource) async throws -> [Post])? = nil,
        fetchFlashPosts: ((Int, Int, String?) async throws -> [Post])? = nil,
        fetchYouTubePosts: ((Int, Int, String?) async throws -> [Post])? = nil,
        fetchXPosts: ((Int, Int, String?) async throws -> [Post])? = nil,
        fetchXFeedUsers: (() async throws -> [XFeedUser])? = nil,
        fetchXueqiuPosts: ((Int, Int, Int?) async throws -> [Post])? = nil,
        fetchXTranslation: ((String) async throws -> XTranslation)? = nil,
        translateXFallback: ((String) async throws -> String)? = nil,
        fetchXTweetDetail: ((String) async throws -> XTweetDetailItem)? = nil,
        translateRSSCard: ((String, String?) async throws -> RSSCardTranslation)? = nil,
        fetchRSSFeeds: (() async throws -> [RSSFeedSource])? = nil,
        fetchRSSFeedPosts: ((Int, Int, Int) async throws -> [Post])? = nil,
        fetchWeChatFeedPosts: ((Int, Int, Int) async throws -> [Post])? = nil,
        fetchPostDetail: ((Int) async throws -> Post)? = nil,
        fetchNewYorkTimesArticle: ((URL) async throws -> NewYorkTimesArticle)? = nil,
        diskCache: FeedDiskCache = .shared
    ) {
        #if DEBUG
        let override = ProcessInfo.processInfo.environment["AI_FEED_SOURCE"]
        let usesXFeedPreview = ProcessInfo.processInfo.arguments.contains("--x-feed-preview")
        let usesXueqiuTapPreview = ProcessInfo.processInfo.arguments.contains("--xueqiu-tap-preview")
        #else
        let override: String? = nil
        #endif
        source = initialSource
            ?? FeedSource(rawValue: override ?? UserDefaults.standard.string(forKey: "feed.source") ?? "x")
            ?? .x
        let serverURL = ServerConfiguration.currentURL
        self.serverURL = serverURL
        self.diskCache = diskCache
        let client = APIClient(baseURL: serverURL)
        self.fetchXTranslation = fetchXTranslation ?? { tweetID in
            try await client.fetchXTranslation(tweetID: tweetID)
        }
        self.translateXFallback = translateXFallback ?? { text in
            try await PersonArticleTranslationService.shared.translate(text)
        }
        self.fetchXTweetDetail = fetchXTweetDetail ?? { tweetID in
            try await client.fetchXTweetDetail(tweetID: tweetID)
        }
        self.fetchXFeedUsers = fetchXFeedUsers ?? { try await client.fetchXFeedUsers() }
        if let fetchXueqiuPosts {
            self.fetchXueqiuPosts = fetchXueqiuPosts
        } else if let fetchPosts {
            self.fetchXueqiuPosts = { page, limit, _ in try await fetchPosts(page, limit, .xueqiu) }
        } else {
            self.fetchXueqiuPosts = { page, limit, feedID in
                try await client.fetchXueqiuPosts(page: page, limit: limit, feedID: feedID)
            }
        }
        if let fetchXPosts {
            self.fetchXPosts = fetchXPosts
        } else if let fetchPosts {
            self.fetchXPosts = { page, limit, _ in try await fetchPosts(page, limit, .x) }
        } else {
            self.fetchXPosts = { page, limit, author in
                try await client.fetchPosts(page: page, limit: limit, source: .x, xUserID: author)
            }
        }
        self.translateRSSCard = translateRSSCard ?? { title, excerpt in
            let service = PersonArticleTranslationService.shared
            return try await RSSCardTranslation.translated(title: title, excerpt: excerpt) {
                try await service.translate($0)
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
        } else if usesXFeedPreview {
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

    func loadRSSFeedsIfNeeded(forceRefresh: Bool = false) async {
        guard forceRefresh || rssFeeds.isEmpty else { return }
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
            await FeedPresentationPrewarmer.shared.warm(warmedPosts)
            guard !Task.isCancelled, selectedRSSFeedID == feedID else { return }
            selectedRSSPosts = warmedPosts
            canLoadMoreRSSSelection = !result.isEmpty
            scheduleRSSCardTranslations(for: warmedPosts)
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
            await FeedPresentationPrewarmer.shared.warm(warmedPosts)
            guard !Task.isCancelled, selectedRSSFeedID == feedID else { return }
            let existingIDs = Set(selectedRSSPosts.map(\.id))
            selectedRSSPosts += warmedPosts.filter { !existingIDs.contains($0.id) }
            selectedRSSPage = nextPage
            canLoadMoreRSSSelection = !result.isEmpty
            errorMessage = nil
            scheduleRSSCardTranslations(for: warmedPosts)
        } catch is CancellationError {
            return
        } catch {
            guard selectedRSSFeedID == feedID else { return }
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
    }

    func selectWeChatFeed(_ feedID: Int?) async {
        selectedWeChatFeedID = feedID
        selectedWeChatPosts = []
        selectedWeChatPage = 1
        canLoadMoreWeChatSelection = true
        guard let feedID else {
            isLoadingWeChatSelection = false
            return
        }
        isLoadingWeChatSelection = true
        defer { if selectedWeChatFeedID == feedID { isLoadingWeChatSelection = false } }
        do {
            let result = try await fetchWeChatFeedPosts(feedID, 1, selectedWeChatPageSize)
            guard !Task.isCancelled, selectedWeChatFeedID == feedID else { return }
            selectedWeChatPosts = result
            canLoadMoreWeChatSelection = !result.isEmpty
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard selectedWeChatFeedID == feedID else { return }
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
        isLoadingMoreWeChatSelection = true
        defer { isLoadingMoreWeChatSelection = false }
        do {
            let result = try await fetchWeChatFeedPosts(feedID, nextPage, selectedWeChatPageSize)
            guard !Task.isCancelled, selectedWeChatFeedID == feedID else { return }
            let existingIDs = Set(selectedWeChatPosts.map(\.id))
            selectedWeChatPosts += result.filter { !existingIDs.contains($0.id) }
            selectedWeChatPage = nextPage
            canLoadMoreWeChatSelection = !result.isEmpty
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard selectedWeChatFeedID == feedID else { return }
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
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
    }

    func selectXUser(_ user: XFeedUser?) async {
        guard source == .x, selectedXUserID != user?.id else { return }
        selectedXUserID = user?.id
        selectedXAuthor = user?.screenName
        posts = []
        pendingRealtimePosts = []
        page = 1
        canLoadMore = true
        cache[.x] = nil
        await refresh()
    }

    func selectXueqiuFeed(_ feedID: Int?) async {
        guard source == .xueqiu, selectedXueqiuFeedID != feedID else { return }
        selectedXueqiuFeedID = feedID
        posts = []
        pendingRealtimePosts = []
        page = 1
        canLoadMore = true
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

    func postForDisplay(_ post: Post) -> Post {
        var displayed = post
        if let detail = xLiveDetails[post.id] {
            displayed = displayed.replacingXLiveDetail(with: detail)
        }
        if let translation = xTranslations[post.id] {
            displayed = displayed.replacingTranslation(with: translation)
        }
        if let translation = rssCardTranslations[post.id] ?? pendingRSSCardTranslations[post.id] {
            displayed = displayed.replacingRSSCardTranslation(
                title: translation.title,
                excerpt: translation.excerpt
            )
        }
        return displayed
    }

    func preloadedNewYorkTimesArticle(for postID: Int) -> NewYorkTimesArticle? {
        preloadedNewYorkTimesArticles[postID]
    }

    func posts(for source: FeedSource) -> [Post] {
        source == self.source ? posts : cache[source]?.posts ?? []
    }

    func translateXPostIfNeeded(_ post: Post) async {
        if post.isXRetweetWrapper {
            await loadXRetweetPresentationIfNeeded(post)
            return
        }
        guard post.needsXTranslation,
              let tweetID = post.xTweetID,
              xTranslations[post.id] == nil,
              !loadingXTranslationIDs.contains(post.id) else { return }
        loadingXTranslationIDs.insert(post.id)
        defer { loadingXTranslationIDs.remove(post.id) }
        do {
            let value = try await resolvedXTranslation(tweetID: tweetID, sourceText: post.originalDisplayContent)
            guard !Task.isCancelled else { return }
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, normalized != post.originalDisplayContent else { return }
            pendingXTranslations[post.id] = normalized
            scheduleXTranslationPublish()
        } catch is CancellationError {
            return
        } catch {
            // Translation is best-effort. Keep the original post visible on failure.
        }
    }

    func loadXEngagementIfNeeded(_ post: Post) async {
        guard !post.isXRetweetWrapper,
              post.meta?.metrics == nil,
              let tweetID = post.xTweetID,
              xLiveDetails[post.id] == nil,
              !loadingXLiveDetailIDs.contains(post.id) else { return }
        loadingXLiveDetailIDs.insert(post.id)
        defer { loadingXLiveDetailIDs.remove(post.id) }
        do {
            let detail = try await fetchXTweetDetail(tweetID)
            guard !Task.isCancelled else { return }
            xLiveDetails[post.id] = detail
        } catch is CancellationError {
            return
        } catch {
            // Engagement counts are best-effort. Keep the stored post visible on failure.
        }
    }

    private func loadXRetweetPresentationIfNeeded(_ post: Post) async {
        guard let tweetID = post.xTweetID,
              xLiveDetails[post.id] == nil,
              !loadingXTranslationIDs.contains(post.id) else { return }
        loadingXTranslationIDs.insert(post.id)
        defer { loadingXTranslationIDs.remove(post.id) }
        do {
            let detail = try await fetchXTweetDetail(tweetID)
            guard !Task.isCancelled else { return }
            xLiveDetails[post.id] = detail

            guard detail.lang?.lowercased().hasPrefix("zh") != true,
                  xTranslations[post.id] == nil else { return }
            let value = try await resolvedXTranslation(tweetID: detail.id, sourceText: detail.fullText)
            guard !Task.isCancelled else { return }
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, normalized != detail.fullText else { return }
            pendingXTranslations[post.id] = normalized
            scheduleXTranslationPublish()
        } catch is CancellationError {
            return
        } catch {
            // Keep the stored wrapper visible if live X presentation is unavailable.
        }
    }

    private func resolvedXTranslation(tweetID: String, sourceText: String) async throws -> String {
        do {
            return try await fetchXTranslation(tweetID).text
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await translateXFallback(sourceText)
        }
    }

    func translateRSSPostIfNeeded(_ post: Post) async {
        guard post.needsRSSCardTranslation,
              let title = post.rssTranslationTitle,
              rssCardTranslations[post.id] == nil,
              pendingRSSCardTranslations[post.id] == nil,
              !loadingRSSTranslationIDs.contains(post.id) else { return }
        if let cached = Self.cachedRSSCardTranslation(for: post, sourceTitle: title) {
            pendingRSSCardTranslations[post.id] = cached
            scheduleRSSTranslationPublish()
            return
        }
        loadingRSSTranslationIDs.insert(post.id)
        defer { loadingRSSTranslationIDs.remove(post.id) }
        do {
            let translation = try await translateRSSCard(title, post.rssTranslationExcerpt)
            guard !Task.isCancelled else { return }
            let translatedTitle = translation.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translatedTitle.isEmpty,
                  translatedTitle != title,
                  Self.containsHanCharacters(translatedTitle) else { return }
            let value = RSSCardTranslation(
                title: translatedTitle,
                excerpt: translation.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            pendingRSSCardTranslations[post.id] = value
            scheduleRSSTranslationPublish()
            Self.cacheRSSCardTranslation(value, for: post, sourceTitle: title)
        } catch is CancellationError {
            return
        } catch {
            // Translation is best-effort. Keep the source card visible on failure.
        }
    }

    /// Starts translation independently of SwiftUI row lifetime, so quick
    /// scrolling cannot cancel headlines that have already been fetched.
    private func scheduleRSSCardTranslations(for posts: [Post]) {
        let candidates = posts.filter(\.needsRSSCardTranslation)
        guard !candidates.isEmpty else { return }
        for post in candidates {
            Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                await translateRSSPostIfNeeded(post)
            }
        }
    }

    private func scheduleXTranslations(for posts: [Post]) {
        let candidates = posts.filter { $0.needsXTranslation || $0.isXRetweetWrapper }
        guard !candidates.isEmpty else { return }
        for post in candidates {
            Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                await translateXPostIfNeeded(post)
            }
        }
    }

    private struct CachedRSSCardTranslation: Codable {
        let sourceTitle: String
        let translatedTitle: String
        let translatedExcerpt: String?
    }

    private static func cachedRSSCardTranslation(for post: Post, sourceTitle: String) -> RSSCardTranslation? {
        guard let data = UserDefaults.standard.data(forKey: rssCardTranslationCacheKey(postID: post.id)),
              let cached = try? JSONDecoder().decode(CachedRSSCardTranslation.self, from: data),
              cached.sourceTitle == sourceTitle,
              containsHanCharacters(cached.translatedTitle) else { return nil }
        return RSSCardTranslation(title: cached.translatedTitle, excerpt: cached.translatedExcerpt)
    }

    private static func cacheRSSCardTranslation(_ value: RSSCardTranslation, for post: Post, sourceTitle: String) {
        let cached = CachedRSSCardTranslation(
            sourceTitle: sourceTitle,
            translatedTitle: value.title,
            translatedExcerpt: value.excerpt
        )
        guard let data = try? JSONEncoder().encode(cached) else { return }
        let defaults = UserDefaults.standard
        let key = rssCardTranslationCacheKey(postID: post.id)
        defaults.set(data, forKey: key)
        var keys = defaults.stringArray(forKey: rssCardTranslationCacheIndexKey) ?? []
        keys.removeAll { $0 == key }
        keys.append(key)
        if keys.count > 600 {
            for expiredKey in keys.prefix(keys.count - 600) {
                defaults.removeObject(forKey: expiredKey)
            }
            keys = Array(keys.suffix(600))
        }
        defaults.set(keys, forKey: rssCardTranslationCacheIndexKey)
    }

    private static let rssCardTranslationCacheIndexKey = "feed.rss-card-translation.v2.index"

    private static func rssCardTranslationCacheKey(postID: Int) -> String {
        "feed.rss-card-translation.v2.\(postID)"
    }

    private static func containsHanCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { (0x4E00...0x9FFF).contains(Int($0.value)) }
    }

    private func scheduleXTranslationPublish() {
        guard xTranslationPublishTask == nil else { return }
        xTranslationPublishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self else { return }
            let updates = pendingXTranslations
            pendingXTranslations.removeAll(keepingCapacity: true)
            xTranslationPublishTask = nil
            guard !updates.isEmpty else { return }
            xTranslations.merge(updates) { _, latest in latest }
        }
    }

    private func scheduleRSSTranslationPublish() {
        guard rssTranslationPublishTask == nil else { return }
        rssTranslationPublishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self else { return }
            let updates = pendingRSSCardTranslations
            pendingRSSCardTranslations.removeAll(keepingCapacity: true)
            rssTranslationPublishTask = nil
            guard !updates.isEmpty else { return }
            rssCardTranslations.merge(updates) { _, latest in latest }
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
          "meta": {"metrics": {"replies": 222, "retweets": 786, "likes": 12000, "views": 960000}}
        }]
        """#
        return (try? JSONDecoder().decode([Post].self, from: Data(json.utf8))) ?? []
    }
    #endif

    func select(_ next: FeedSource) {
        guard next != source else { return }
        pendingRealtimePosts = []
        if !isSwitchingSource, source != .youtube || selectedYouTubePerson == nil {
            cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
        }
        source = next
        let saved = cache[next]
        if let saved {
            posts = saved.posts
            if next == .xueqiu, selectedXueqiuFeedID == nil {
                xueqiuDirectoryPosts = saved.posts
            }
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
        guard !isLoading, posts.isEmpty || isSwitchingSource else { return }
        if (source != .youtube || selectedYouTubePerson == nil),
           (source != .xueqiu || selectedXueqiuFeedID == nil) {
            await restoreDiskSnapshotIfNeeded(source: source, flashCategory: selectedFlashCategory)
        }
        await refresh()
    }

    func warmSourceCache() async {
        guard let selectedIndex = FeedSource.allCases.firstIndex(of: source) else { return }
        let sources = FeedSource.allCases
            .enumerated()
            .filter { $0.element != source && abs($0.offset - selectedIndex) == 1 }
            .sorted { abs($0.offset - selectedIndex) < abs($1.offset - selectedIndex) }
            .map(\.element)

        for candidate in sources {
            guard !Task.isCancelled else { return }
            guard cache[candidate] == nil else { continue }
            do {
                let pageSize = pageSize(for: candidate)
                let result = try await fetchPage(1, limit: pageSize, source: candidate)
                await FeedPresentationPrewarmer.shared.warm(result)
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
        case .wechat, .weibo, .douyin, .baidu, .truth: 20
        case .flash: 20
        case .x: 10
        case .youtube: 10
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
        let requestedYouTubePerson = selectedYouTubePerson
        let requestedXUserID = selectedXUserID
        let requestedXueqiuFeedID = selectedXueqiuFeedID
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
                flashCategory: requestedFlashCategory,
                youtubePerson: requestedYouTubePerson,
                xAuthor: requestedXUserID,
                xueqiuFeedID: requestedXueqiuFeedID
            )
            guard source == requestedSource,
                  selectedFlashCategory == requestedFlashCategory,
                  selectedYouTubePerson == requestedYouTubePerson,
                  selectedXUserID == requestedXUserID,
                  selectedXueqiuFeedID == requestedXueqiuFeedID,
                  activeRefreshID == refreshID else { return }
            await FeedPresentationPrewarmer.shared.warm(result)
            guard source == requestedSource,
                  selectedFlashCategory == requestedFlashCategory,
                  selectedYouTubePerson == requestedYouTubePerson,
                  selectedXUserID == requestedXUserID,
                  selectedXueqiuFeedID == requestedXueqiuFeedID,
                  activeRefreshID == refreshID else { return }
            posts = result
            if requestedSource == .xueqiu, requestedXueqiuFeedID == nil {
                xueqiuDirectoryPosts = result
            }
            pendingRealtimePosts = []
            page = 1
            canLoadMore = !result.isEmpty
            if completesSourceSwitch {
                isSwitchingSource = false
            }
            cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
            persistCurrentSnapshot()
            if requestedSource == .x {
                scheduleXTranslations(for: result)
            }
            scheduleRSSCardTranslations(for: result)
        } catch is CancellationError { } catch {
            guard source == requestedSource, activeRefreshID == refreshID else { return }
            if completesSourceSwitch, posts.isEmpty {
                isSwitchingSource = false
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
        let requestedYouTubePerson = selectedYouTubePerson
        let requestedXUserID = selectedXUserID
        let requestedXueqiuFeedID = selectedXueqiuFeedID
        let pageSize = pageSize(for: requestedSource)
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await fetchPage(
                page + 1,
                limit: pageSize,
                source: requestedSource,
                flashCategory: requestedFlashCategory,
                youtubePerson: requestedYouTubePerson,
                xAuthor: requestedXUserID,
                xueqiuFeedID: requestedXueqiuFeedID
            )
            guard source == requestedSource, selectedFlashCategory == requestedFlashCategory,
                  selectedYouTubePerson == requestedYouTubePerson else { return }
            guard selectedXUserID == requestedXUserID else { return }
            guard selectedXueqiuFeedID == requestedXueqiuFeedID else { return }
            await FeedPresentationPrewarmer.shared.warm(result)
            guard source == requestedSource, selectedFlashCategory == requestedFlashCategory,
                  selectedYouTubePerson == requestedYouTubePerson else { return }
            guard selectedXUserID == requestedXUserID else { return }
            guard selectedXueqiuFeedID == requestedXueqiuFeedID else { return }
            let ids = Set(posts.map(\.id))
            posts += result.filter { !ids.contains($0.id) }
            if requestedSource == .xueqiu, requestedXueqiuFeedID == nil {
                xueqiuDirectoryPosts = posts
            }
            page += 1
            canLoadMore = !result.isEmpty
            errorMessage = nil
            cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
            persistCurrentSnapshot()
            if requestedSource == .x {
                scheduleXTranslations(for: result)
            }
            scheduleRSSCardTranslations(for: result)
        } catch is CancellationError { } catch {
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
        xueqiuFeedID: Int? = nil
    ) async throws -> [Post] {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let result: [Post]
                if source == .flash {
                    result = try await fetchFlashPosts(page, limit, flashCategory)
                } else if source == .youtube {
                    result = try await fetchYouTubePosts(page, limit, youtubePerson)
                } else if source == .x {
                    result = try await fetchXPosts(page, limit, xAuthor)
                } else if source == .xueqiu {
                    result = try await fetchXueqiuPosts(page, limit, xueqiuFeedID)
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
            Task { @MainActor [weak self] in
                await FeedPresentationPrewarmer.shared.warm([post])
                guard !Task.isCancelled else { return }
                self?.receiveRealtimePost(post)
            }
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
        if source == .x, let selectedXAuthor {
            let handle = post.user?.userScreenName?
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "@")))
                .lowercased()
            guard handle == selectedXAuthor.lowercased() else { return }
        }
        if source == .xueqiu, let selectedXueqiuFeedID {
            guard post.source?.lowercased() == "rss:\(selectedXueqiuFeedID)" else { return }
        }
        errorMessage = nil
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index] = post
        } else if let index = pendingRealtimePosts.firstIndex(where: { $0.id == post.id }) {
            pendingRealtimePosts[index] = post
        } else {
            pendingRealtimePosts.insert(post, at: 0)
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

    private func restoreDiskSnapshotIfNeeded(source: FeedSource, flashCategory: String?) async {
        let key = "\(source.rawValue)|\(flashCategory ?? "all")"
        guard restoredDiskKeys.insert(key).inserted else { return }
        guard let snapshot = await diskCache.load(
            source: source,
            flashCategory: flashCategory,
            serverURL: serverURL
        ), self.source == source, selectedFlashCategory == flashCategory else { return }
        await FeedPresentationPrewarmer.shared.warm(snapshot.posts)
        guard self.source == source, selectedFlashCategory == flashCategory else { return }
        posts = snapshot.posts
        if source == .xueqiu, selectedXueqiuFeedID == nil {
            xueqiuDirectoryPosts = snapshot.posts
        }
        page = snapshot.page
        canLoadMore = snapshot.canLoadMore
        cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
        isSwitchingSource = false
        scheduleRSSCardTranslations(for: posts)
    }

    private func persistCurrentSnapshot() {
        guard (source != .youtube || selectedYouTubePerson == nil),
              (source != .x || selectedXUserID == nil),
              (source != .xueqiu || selectedXueqiuFeedID == nil) else { return }
        let snapshot = FeedDiskSnapshot(
            schemaVersion: 1,
            savedAt: Date(),
            source: source.rawValue,
            flashCategory: selectedFlashCategory,
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
        case .newYorkTimes, .wechat: return post.source == source.rawValue
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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await fetchPosts(1, pageSize, selectedFeedID)
            guard !Task.isCancelled else { return }
            posts = result
            if selectedFeedID == nil { directoryPosts = result }
            page = 1
            canLoadMore = !result.isEmpty
        } catch is CancellationError {
            return
        } catch {
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
    }

    func selectFeed(_ feedID: Int?) async {
        guard selectedFeedID != feedID else { return }
        selectedFeedID = feedID
        posts = []
        page = 1
        canLoadMore = true
        await refresh()
    }

    func loadMoreIfNeeded(current post: Post) async {
        guard post.id == posts.last?.id,
              canLoadMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await fetchPosts(page + 1, pageSize, selectedFeedID)
            guard !Task.isCancelled else { return }
            let existingIDs = Set(posts.map(\.id))
            posts += result.filter { !existingIDs.contains($0.id) }
            if selectedFeedID == nil { directoryPosts = posts }
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
