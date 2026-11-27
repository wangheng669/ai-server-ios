import Foundation
import libxml2

struct APIClient {
    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = .shared
        return URLSession(configuration: configuration)
    }()

    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.session = session ?? Self.defaultSession
    }

    func checkHealth() async throws { let _: HealthResponse = try await get(baseURL.appending(path: "health")) }

    func fetchAliyunBalance(refresh: Bool = false) async throws -> AliyunAccountBalance {
        var components = URLComponents(url: baseURL.appending(path: "api/ios/v1/settings/aliyun-balance"), resolvingAgainstBaseURL: false)
        if refresh { components?.queryItems = [URLQueryItem(name: "refresh", value: "1")] }
        guard let url = components?.url else { throw APIError.invalidURL }
        let response: AliyunBalanceResponse = try await get(
            url, retriesTransientFailures: false,
            cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20
        )
        guard response.success else { throw APIError.invalidResponse }
        return response.data
    }

    func fetchTodayWorldYesterdayReport() async throws -> TodayWorldYesterdayReportPayload {
        let response: TodayWorldYesterdayReportResponse = try await get(
            baseURL.appending(path: "api/ios/v1/today-world/yesterday-report").appending(queryItems: [.init(name: "view", value: "edition")]),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 8,
            retryableNetworkErrors: [.timedOut, .networkConnectionLost]
        )
        guard response.success else { throw APIError.invalidResponse }
        return response.data
    }

    func fetchPosts(
        page: Int,
        limit: Int = 20,
        source: FeedSource,
        flashCategory: String? = nil,
        youtubePerson: String? = nil,
        xUserID: String? = nil,
        bypassCache: Bool = false
    ) async throws -> [Post] {
        switch source {
        case .zhihu:
            return try await fetchZhihuTopics(page: page, limit: limit)
        case .weibo, .douyin, .baidu:
            return Self.hotTopicPostsForDisplay(
                try await fetchHotTopics(page: page, limit: limit, source: source),
                page: page,
                limit: limit,
                source: source
            )
        case .flash:
            return try await fetchFlash(
                page: page,
                limit: limit,
                category: flashCategory,
                importantOnly: flashCategory == nil
            ).map(Post.flash)
        case .wechat, .xueqiu:
            let url = baseURL.appending(path: "api/ios/v1/post/list").appending(queryItems: [
                .init(name: "page", value: String(page)), .init(name: "limit", value: String(limit)),
                .init(name: "source", value: "rss"), .init(name: "rss_platform", value: source == .wechat ? "wechat" : "xueqiu"),
                .init(name: "sort", value: "time_desc"), .init(name: "include_zero_score", value: "true")
            ])
            let response: PostListResponse = try await get(url)
            return response.data
        case .youtube:
            return try await fetchYouTubePosts(page: page, limit: limit, person: youtubePerson)
        default:
            return try await fetchRegularPosts(
                page: page,
                limit: limit,
                source: source,
                xUserID: xUserID,
                bypassCache: bypassCache
            )
        }
    }

    static func xAuthorPostQueryItems(page: Int, limit: Int, screenName: String) -> [URLQueryItem] {
        let handle = screenName.trimmingCharacters(in: CharacterSet(charactersIn: "@ \n\t"))
        return [
            .init(name: "page", value: String(page)), .init(name: "limit", value: String(limit)),
            .init(name: "source", value: "x"), .init(name: "x_author", value: handle),
            .init(name: "sort", value: "time_desc"), .init(name: "include_zero_score", value: "true"),
            .init(name: "group_similar", value: "0"),
            .init(name: "x_feed_view", value: "all"),
            .init(name: "include_disliked", value: "true")
        ]
    }

    func fetchXAuthorPosts(page: Int, limit: Int, screenName: String, bypassCache: Bool) async throws -> [Post] {
        var components = URLComponents(url: baseURL.appending(path: "api/ios/v1/post/list"), resolvingAgainstBaseURL: false)
        components?.queryItems = Self.xAuthorPostQueryItems(page: page, limit: limit, screenName: screenName)
        guard let url = components?.url else { throw APIError.invalidURL }
        let response: PostListResponse = try await get(url, cachePolicy: bypassCache ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy)
        return response.data
    }

    func fetchXFeedUsers() async throws -> [XFeedUser] {
        let response: XFeedUsersResponse = try await get(
            baseURL.appending(path: "api/ios/v1/x/users")
        )
        return response.data
    }

    func fetchRSSFeeds() async throws -> [RSSFeedSource] {
        func fetchPage(_ page: Int) async throws -> RSSFeedsResponse {
            try await fetchRSSFeedsPage(page, query: [
                .init(name: "exclude_social", value: "true")
            ])
        }

        let firstPage = try await fetchPage(1)
        let pagination = firstPage.meta.pagination
        guard pagination.size > 0, pagination.total >= 0 else { throw APIError.invalidResponse }
        let totalPages = min(10, (max(pagination.total, 1) - 1) / pagination.size + 1)
        var pages = [[RSSFeedSource]](repeating: [], count: totalPages)
        pages[0] = firstPage.data.feeds

        try await withThrowingTaskGroup(of: (Int, [RSSFeedSource]).self) { group in
            for index in 1..<totalPages {
                group.addTask {
                    let response = try await fetchPage(index + 1)
                    return (index, response.data.feeds)
                }
            }
            for try await (index, feeds) in group { pages[index] = feeds }
        }

        var seen = Set<Int>()
        return pages.joined().filter { $0.isEnabled && seen.insert($0.id).inserted }
    }

    func fetchXueqiuFeeds() async throws -> [RSSFeedSource] {
        let query: [URLQueryItem] = [
            .init(name: "q", value: "/xueqiu/user/"),
            .init(name: "enabled", value: "true"),
            .init(name: "size", value: "100")
        ]
        var page = 1
        var feeds: [RSSFeedSource] = []
        var seen = Set<Int>()
        while true {
            let response = try await fetchRSSFeedsPage(page, query: query, cachePolicy: .reloadIgnoringLocalCacheData)
            let pagination = response.meta.pagination
            guard pagination.page == page, pagination.size > 0, pagination.total >= 0 else {
                throw APIError.invalidResponse
            }
            feeds += response.data.feeds.filter { $0.isEnabled && $0.isXueqiuUserFeed && seen.insert($0.id).inserted }
            if page >= (max(pagination.total, 1) - 1) / pagination.size + 1 {
                return feeds.sorted { $0.id < $1.id }
            }
            page += 1
        }
    }

    private func fetchRSSFeedsPage(
        _ page: Int,
        query: [URLQueryItem],
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> RSSFeedsResponse {
        var parts = URLComponents(url: baseURL.appending(path: "api/ios/v1/rss/feeds"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [.init(name: "page", value: String(page))] + query
        guard let url = parts?.url else { throw APIError.invalidURL }
        return try await get(url, cachePolicy: cachePolicy)
    }

    func fetchRSSFeedPosts(
        feedID: Int,
        page: Int = 1,
        limit: Int = 20,
        includesAllScores: Bool = true,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> [Post] {
        var parts = URLComponents(
            url: baseURL.appending(path: "api/ios/v1/rss/feeds/\(feedID)/posts"),
            resolvingAgainstBaseURL: false
        )
        parts?.queryItems = Self.rssFeedPostQueryItems(
            page: page,
            limit: limit,
            includesAllScores: includesAllScores
        )
        guard let url = parts?.url else { throw APIError.invalidURL }
        let response: RSSFeedPostsResponse = try await get(url, cachePolicy: cachePolicy)
        return response.data.posts
    }

    static func rssFeedPostQueryItems(
        page: Int,
        limit: Int,
        includesAllScores: Bool = true
    ) -> [URLQueryItem] {
        var queryItems: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "limit", value: String(limit)),
            .init(name: "sort", value: "time_desc"),
            .init(name: "include_zero_score", value: includesAllScores ? "true" : "false")
        ]
        if !includesAllScores {
            queryItems.append(.init(name: "final_score", value: String(Post.minimumFeedScore)))
        }
        return queryItems
    }

    func fetchWeiboFollowingPosts(
        page: Int,
        limit: Int = 20,
        feedID: Int? = nil
    ) async throws -> [Post] {
        if let feedID {
            return try await fetchRSSFeedPosts(
                feedID: feedID,
                page: page,
                limit: limit,
                includesAllScores: true
            )
        }
        var components = URLComponents(url: baseURL.appending(path: "api/ios/v1/post/list"), resolvingAgainstBaseURL: false)
        components?.queryItems = Self.weiboFollowingQueryItems(page: page, limit: limit)
        guard let url = components?.url else { throw APIError.invalidURL }
        let response: PostListResponse = try await get(url)
        return response.data
    }

    static func weiboFollowingQueryItems(page: Int, limit: Int) -> [URLQueryItem] {
        [
            .init(name: "source", value: "rss"),
            .init(name: "rss_platform", value: "weibo"),
            .init(name: "page", value: String(page)),
            .init(name: "limit", value: String(limit)),
            .init(name: "sort", value: "time_desc"),
            .init(name: "include_zero_score", value: "true")
        ]
    }

    func fetchWeiboComments(postURL: URL, limit: Int = 20) async throws -> WeiboCommentsResponse.Payload {
        var components = URLComponents(
            url: baseURL.appending(path: "api/ios/v1/weibo/comments"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = Self.weiboCommentsQueryItems(postURL: postURL, limit: limit)
        guard let url = components?.url else { throw APIError.invalidURL }
        let response: WeiboCommentsResponse = try await get(url)
        guard response.success else { throw APIError.invalidResponse }
        return response.data
    }

    static func weiboCommentsQueryItems(postURL: URL, limit: Int, replyLimit: Int = 3) -> [URLQueryItem] {
        [
            .init(name: "url", value: postURL.absoluteString),
            .init(name: "limit", value: String(min(max(limit, 1), 20))),
            .init(name: "reply_limit", value: String(min(max(replyLimit, 1), 20)))
        ]
    }

    static let weChatFeedIDs = [57, 2373, 19]

    private func fetchRegularPosts(
        page: Int,
        limit: Int,
        source: FeedSource,
        xUserID: String? = nil,
        bypassCache: Bool = false
    ) async throws -> [Post] {
        var components = URLComponents(url: baseURL.appending(path: "api/ios/v1/post/list"), resolvingAgainstBaseURL: false)
        let isSpecialRSS = source == .laozhong || source == .youtube
        var queryItems = Self.regularPostQueryItems(
            page: page,
            limit: limit,
            source: source,
            xUserID: xUserID
        )
        if isSpecialRSS {
            let name = source == .laozhong ? "老中" : "YouTube"
            queryItems.append(.init(name: "categoryId", value: String(try await categoryID(named: name))))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw APIError.invalidURL }
        let response: PostListResponse = try await get(
            url,
            cachePolicy: (bypassCache || source == .truth) ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        )
        return response.data
    }

    private func fetchYouTubePosts(page: Int, limit: Int, person: String? = nil) async throws -> [Post] {
        var components = URLComponents(url: baseURL.appending(path: "api/ios/v1/youtube/videos"), resolvingAgainstBaseURL: false)
        components?.queryItems = Self.youtubeVideoQueryItems(page: page, limit: limit, person: person)
        guard let url = components?.url else { throw APIError.invalidURL }
        let response: PostListResponse = try await get(url)
        return response.data
    }

    static func youtubeVideoQueryItems(page: Int, limit: Int, person: String? = nil) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let person = person?.trimmingCharacters(in: .whitespacesAndNewlines), !person.isEmpty {
            items.append(.init(name: "person", value: person))
        }
        return items
    }

    static func regularPostQueryItems(
        page: Int,
        limit: Int,
        source: FeedSource,
        xUserID: String? = nil
    ) -> [URLQueryItem] {
        let isSpecialRSS = source == .laozhong || source == .youtube
        let includesAllScores = source == .newYorkTimes || source == .wechat || source == .youtube || source == .bilibili || source == .truth
        let normalizedXUserID = source == .x
            ? xUserID?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let filtersXUser = normalizedXUserID?.isEmpty == false
        var queryItems: [URLQueryItem] = [
            .init(name: "page", value: String(page)), .init(name: "limit", value: String(limit)),
            .init(name: "sort", value: "time_desc"),
            .init(name: "group_similar", value: "1"), .init(name: "group_threshold", value: "70"),
            .init(name: "source", value: isSpecialRSS ? "rss" : source.rawValue),
            .init(name: "include_zero_score", value: includesAllScores || filtersXUser ? "true" : "false")
        ]
        if source == .truth {
            // Browsing Truth is a chronological source feed, not a scored notification feed.
            queryItems.append(.init(name: "final_score", value: "0"))
        } else if !includesAllScores && !filtersXUser {
            let minimumScore = source == .rss ? 6 : Post.minimumFeedScore
            queryItems.append(.init(name: "final_score", value: String(minimumScore)))
        }
        if source == .x { queryItems.append(.init(name: "x_feed_view", value: "tracked")) }
        if let normalizedXUserID, !normalizedXUserID.isEmpty {
            queryItems.append(.init(name: "x_user_id", value: normalizedXUserID))
        }
        return queryItems
    }

    private func fetchHotTopics(page: Int, limit: Int, source: FeedSource) async throws -> [HotTopic] {
        let platform = switch source {
        case .weibo: "weibo"
        case .douyin: "douyin"
        case .baidu: "baidu"
        default: source.rawValue
        }
        let path = "api/ios/v1/\(platform)/hot/topics"
        var parts = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        parts?.queryItems = [.init(name: "page", value: String(page)), .init(name: "size", value: String(limit)), .init(name: "sort", value: "rank")]
        guard let url = parts?.url else { throw APIError.invalidURL }
        let response: HotTopicsResponse = try await get(url)
        guard response.success else { throw APIError.invalidResponse }
        return response.data.topics
    }

    private func fetchZhihuTopics(page: Int, limit: Int) async throws -> [Post] {
        var parts = URLComponents(url: baseURL.appending(path: "api/ios/v1/zhihu/hot/topics"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [.init(name: "page", value: String(page)), .init(name: "size", value: String(limit))]
        guard let url = parts?.url else { throw APIError.invalidURL }
        let (data, response) = try await session.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let failure = try JSONDecoder().decode(FeedSourceFailure.self, from: data)
            throw APIError.sourceUnavailable(failure.message)
        }
        let envelope = try JSONDecoder().decode(ZhihuHotTopicsResponse.self, from: data)
        guard envelope.success else { throw APIError.invalidResponse }
        return envelope.data.topics.map(Post.zhihuTopic)
    }

    static func hotTopicPostsForDisplay(
        _ topics: [HotTopic],
        page: Int,
        limit: Int,
        source: FeedSource
    ) -> [Post] {
        topics.enumerated()
            .sorted { lhs, rhs in
                let leftRank = lhs.element.latestRank ?? Int.max
                let rightRank = rhs.element.latestRank ?? Int.max
                if leftRank != rightRank { return leftRank < rightRank }

                let leftHeat = lhs.element.resolvedHeat ?? -.infinity
                let rightHeat = rhs.element.resolvedHeat ?? -.infinity
                if leftHeat != rightHeat { return leftHeat > rightHeat }

                return lhs.offset < rhs.offset
            }
            .enumerated()
            .map { offset, item in
                .hotTopic(
                    item.element,
                    source: source,
                    displayRank: max(page - 1, 0) * limit + offset + 1
                )
            }
    }

    static func flashQueryItems(
        page: Int,
        limit: Int,
        category: String?,
        importantOnly: Bool
    ) -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String((page - 1) * limit)),
            .init(name: "source", value: "all"),
            .init(name: "include_options", value: "0")
        ]
        if let category, !category.isEmpty {
            items.append(.init(name: "category", value: category))
        }
        if importantOnly {
            items.append(.init(name: "important_only", value: "1"))
        }
        return items
    }

    private func fetchFlash(
        page: Int,
        limit: Int,
        category: String?,
        importantOnly: Bool
    ) async throws -> [FlashItem] {
        var parts = URLComponents(url: baseURL.appending(path: "api/ios/v1/market/flash/live"), resolvingAgainstBaseURL: false)
        parts?.queryItems = Self.flashQueryItems(
            page: page,
            limit: limit,
            category: category,
            importantOnly: importantOnly
        )
        guard let url = parts?.url else { throw APIError.invalidURL }
        let response: FlashResponse = try await get(url)
        guard response.success else { throw APIError.invalidResponse }
        return response.data.items
    }

    private func categoryID(named name: String) async throws -> Int {
        let key = "rss.category.\(name)"
        let cached = UserDefaults.standard.integer(forKey: key)
        if cached > 0 { return cached }
        var parts = URLComponents(url: baseURL.appending(path: "api/ios/v1/categories"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [.init(name: "compact", value: "1"), .init(name: "q", value: name)]
        guard let url = parts?.url else { throw APIError.invalidURL }
        let response: CategoryResponse = try await get(url)
        guard response.success, let category = response.categories.first(where: { $0.name == name }) ?? response.categories.first else {
            throw APIError.missingCategory(name)
        }
        UserDefaults.standard.set(category.id, forKey: key)
        return category.id
    }

    func fetchPost(id: Int) async throws -> Post {
        let response: PostDetailResponse = try await get(baseURL.appending(path: "api/ios/v1/post/\(id)/raw"))
        return response.post
    }

    func fetchPushNotification(id: UUID) async throws -> PushNotificationDetails {
        try await get(
            baseURL.appending(path: "api/ios/v1/ios/push/detail"),
            cachePolicy: .reloadIgnoringLocalCacheData,
            authorization: "Bearer \(id.uuidString.lowercased())"
        )
    }

    func fetchBilibiliSubtitles(bvid: String) async throws -> BilibiliSubtitlesResponse {
        var components = URLComponents(
            url: baseURL.appending(path: "api/ios/v1/bilibili/subtitles"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [.init(name: "bvid", value: bvid)]
        guard let url = components?.url else { throw APIError.invalidURL }
        return try await get(url)
    }

    func fetchYouTubeSubtitles(videoID: String) async throws -> YouTubeSubtitlesResponse {
        var components = URLComponents(
            url: baseURL.appending(path: "api/ios/v1/youtube/subtitles"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [.init(name: "video_id", value: videoID)]
        guard let url = components?.url else { throw APIError.invalidURL }
        return try await get(url)
    }

    func fetchBilibiliSummary(bvid: String, title: String) async throws -> BilibiliSummaryResponse {
        var components = URLComponents(
            url: baseURL.appending(path: "api/ios/v1/bilibili/summary"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            .init(name: "bvid", value: bvid),
            .init(name: "title", value: title)
        ]
        guard let url = components?.url else { throw APIError.invalidURL }
        return try await get(url, retriesTransientFailures: false, timeoutInterval: 90)
    }

    func interpretBilibiliVideo(bvid: String, title: String) async throws -> BilibiliInterpretationResponse {
        try await requestBilibiliInterpretation(bvid: bvid, title: title, method: "POST")
    }

    func fetchBilibiliInterpretationStatus(bvid: String, title: String) async throws -> BilibiliInterpretationResponse {
        try await requestBilibiliInterpretation(bvid: bvid, title: title, method: "GET")
    }

    private func requestBilibiliInterpretation(bvid: String, title: String, method: String) async throws -> BilibiliInterpretationResponse {
        var components = URLComponents(
            url: baseURL.appending(path: "api/ios/v1/bilibili/interpretation"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            .init(name: "bvid", value: bvid),
            .init(name: "title", value: title),
            .init(name: "async", value: "1")
        ]
        guard let url = components?.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.httpStatus(http.statusCode) }
        do { return try JSONDecoder().decode(BilibiliInterpretationResponse.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    func fetchXComments(tweetID: String, limit: Int = 30) async throws -> [XComment] {
        var parts = URLComponents(url: baseURL.appending(path: "api/ios/v1/x/comments"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [
            .init(name: "tweet_id", value: tweetID),
            .init(name: "limit", value: String(limit))
        ]
        guard let url = parts?.url else { throw APIError.invalidURL }
        let response: XCommentsResponse = try await get(url)
        guard response.success else { throw APIError.invalidResponse }
        return response.data.items
    }

    func fetchXTweetDetail(tweetID: String) async throws -> XTweetDetailItem {
        var parts = URLComponents(url: baseURL.appending(path: "api/ios/v1/x/tweet"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [.init(name: "tweet_id", value: tweetID)]
        guard let url = parts?.url else { throw APIError.invalidURL }
        let response: XTweetDetailResponse = try await get(url)
        guard response.success else { throw APIError.invalidResponse }
        return response.data.item
    }

    func fetchXTranslation(tweetID: String) async throws -> XTranslation {
        var parts = URLComponents(url: baseURL.appending(path: "api/ios/v1/x/translation"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [
            .init(name: "tweet_id", value: tweetID),
            .init(name: "to", value: "zh")
        ]
        guard let url = parts?.url else { throw APIError.invalidURL }
        let response: XTranslationResponse = try await get(
            url, retriesTransientFailures: false, mapHTTPError: { XTranslationDeferral($0) }
        )
        guard response.success else { throw APIError.invalidResponse }
        return response.data
    }

    func resolveYouTubePlayback(url: URL, title: String) async throws -> VideoPlaybackSource {
        try await resolveVideoPlayback(url: url, title: title, formatID: "")
    }

    func resolveBilibiliPlayback(url: URL, title: String) async throws -> VideoPlaybackSource {
        try await resolveVideoPlayback(url: url, title: title, formatID: "18")
    }

    private func resolveVideoPlayback(url: URL, title: String, formatID: String) async throws -> VideoPlaybackSource {
        var request = URLRequest(url: baseURL.appending(path: "api/ios/v1/post/video-playback/source"))
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            VideoPlaybackRequest(url: url.absoluteString, title: title, formatID: formatID)
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.httpStatus(http.statusCode) }
        let payload = try JSONDecoder().decode(VideoPlaybackResponse.self, from: data)
        guard payload.success,
              let source = Self.playbackURL(from: payload.data.sourceURL, baseURL: baseURL) else {
            throw APIError.invalidURL
        }
        return VideoPlaybackSource(url: source, label: payload.data.label, httpHeaders: payload.data.httpHeaders ?? [:])
    }

    static func playbackURL(from value: String, baseURL: URL) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil { return absolute }
        if trimmed.hasPrefix("/post/") {
            return URL(string: "api/ios/v1" + trimmed, relativeTo: baseURL)?.absoluteURL
        }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    func bookmarkXPost(tweetID: String) async throws -> XBookmarkResult {
        let value = tweetID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.allSatisfy(\.isNumber) else { throw APIError.invalidXPostID }
        var request = URLRequest(url: baseURL.appending(path: "api/ios/v1/x/bookmark"))
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(XBookmarkRequest(articleID: value))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.httpStatus(http.statusCode) }
        do { return try JSONDecoder().decode(XBookmarkResponse.self, from: data).data }
        catch { throw APIError.decoding(error) }
    }

    func reportXVideoPlaybackEvent(_ event: XVideoPlaybackEvent) async throws {
        var request = URLRequest(url: baseURL.appending(path: "api/ios/v1/x/video-playback/events"))
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(event)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { throw APIError.invalidResponse }
    }

    func fetchNewYorkTimesArticle(url: URL) async throws -> NewYorkTimesArticle {
        let response = try await fetchArticlePreview(url: url, preferRemote: true)
        guard let article = NewYorkTimesArticleParser.extract(from: response.data.content, baseURL: url) else {
            throw NewYorkTimesArticleError.bodyMissing
        }
        return article
    }

    func fetchArticlePreview(url: URL, preferRemote: Bool = false) async throws -> ArticlePreviewResponse {
        guard let previewURL = Self.articlePreviewURL(
            for: url,
            baseURL: baseURL,
            preferRemote: preferRemote
        ) else { throw APIError.invalidURL }
        return try await get(previewURL)
    }

    func fetchWikipediaEntities(titles: [String], language: String = "zh") async throws -> [WikipediaRelayEntity] {
        var parts = URLComponents(
            url: baseURL.appending(path: "api/ios/v1/wikipedia/entities"),
            resolvingAgainstBaseURL: false
        )
        parts?.queryItems = [
            .init(name: "language", value: language),
            .init(name: "titles", value: titles.joined(separator: "|")),
        ]
        guard let url = parts?.url else { throw APIError.invalidURL }
        let response: WikipediaRelayEntitiesResponse = try await get(url)
        guard response.success else { throw APIError.invalidResponse }
        return response.entities
    }

    func fetchWikipediaArticle(title: String, language: String = "zh") async throws -> WikipediaRelayArticle {
        var parts = URLComponents(
            url: baseURL.appending(path: "api/ios/v1/wikipedia/article"),
            resolvingAgainstBaseURL: false
        )
        parts?.queryItems = [
            .init(name: "language", value: language),
            .init(name: "title", value: title),
        ]
        guard let url = parts?.url else { throw APIError.invalidURL }
        let response: WikipediaRelayArticleResponse = try await get(url)
        guard response.success else { throw APIError.invalidResponse }
        return response.article
    }

    static func articlePreviewURL(
        for articleURL: URL,
        baseURL: URL,
        preferRemote: Bool = false
    ) -> URL? {
        var parts = URLComponents(url: baseURL.appending(path: "api/ios/v1/post/preview"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = [
            .init(name: "url", value: articleURL.absoluteString),
        ]
        if preferRemote {
            queryItems.append(.init(name: "prefer_remote", value: "true"))
        }
        parts?.queryItems = queryItems
        return parts?.url
    }

    private func get<Response: Decodable>(
        _ url: URL,
        retriesTransientFailures: Bool = true,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        timeoutInterval: TimeInterval = 30,
        authorization: String? = nil,
        retryableNetworkErrors: Set<URLError.Code>? = nil,
        mapHTTPError: ((HTTPURLResponse) -> Error?)? = nil
    ) async throws -> Response {
        let attempts = retriesTransientFailures ? 2 : 1
        for attempt in 0..<attempts {
            do {
                var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
                request.setValue(authorization, forHTTPHeaderField: "Authorization")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                if [500, 502, 503, 504].contains(http.statusCode), attempt + 1 < attempts {
                    try await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
                    continue
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw mapHTTPError?(http) ?? APIError.httpStatus(http.statusCode)
                }
                do { return try JSONDecoder().decode(Response.self, from: data) }
                catch {
                    #if DEBUG
                    print("Feed request decoding failed: \(url.absoluteString) — \(error)")
                    #endif
                    throw APIError.decoding(error)
                }
            } catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                guard attempt + 1 < attempts,
                      retryableNetworkErrors?.contains(error.code) ?? true else { throw error }
                #if DEBUG
                print("Feed request failed (attempt \(attempt + 1)): \(url.absoluteString) — \(error)")
                #endif
                try await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
            }
        }
        throw APIError.invalidResponse
    }
}

struct XVideoPlaybackEvent: Encodable {
    let sessionID: String
    let phase: String
    let surface: String
    let route: String
    let videoURL: String
    let elapsedMS: Int
    let message: String?
    let occurredAt: String

    enum CodingKeys: String, CodingKey {
        case phase, surface, route, message
        case sessionID = "sessionId"
        case videoURL = "videoUrl"
        case elapsedMS = "elapsedMs"
        case occurredAt
    }
}

struct NewYorkTimesArticle: Equatable {
    let blocks: [NewYorkTimesArticleBlock]
    let cover: NewYorkTimesArticlePhoto?

    init?(storedPost post: Post) {
        let excerpt = post.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        for body in [post.content, post.contentZH].compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            if body != excerpt, let article = Self.storedText(body) {
                self = article
                return
            }
        }
        return nil
    }

    private init(blocks: [NewYorkTimesArticleBlock], cover: NewYorkTimesArticlePhoto? = nil) {
        self.blocks = blocks
        self.cover = cover
    }

    static func structured(blocks: [NewYorkTimesArticleBlock], cover: NewYorkTimesArticlePhoto?) -> Self? {
        guard blocks.contains(where: { $0.paragraphText != nil }) else { return nil }
        return Self(blocks: blocks, cover: cover)
    }

    // Keep the complete stored article if the webpage returns a shorter or different body.
    func containsStoredBody(_ stored: Self) -> Bool {
        let sourceText = blocks.flatMap { block in
            switch block {
            case .paragraph(let text), .linkedParagraph(let text, _): [text]
            case .image(let photo): [photo.caption, photo.credit].compactMap { $0 }
            }
        }.joined().filter { !$0.isWhitespace }
        var remaining = sourceText[...]
        for paragraph in stored.blocks.compactMap(\.paragraphText) {
            let text = paragraph.filter { !$0.isWhitespace }
            guard let range = remaining.range(of: text) else { return false }
            remaining = remaining[range.upperBound...]
        }
        return true
    }

    private static func storedText(_ text: String) -> NewYorkTimesArticle? {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let paragraphNormalized = normalized.replacingOccurrences(
            of: #"\n[ \t]*\n+"#,
            with: "\u{2029}",
            options: .regularExpression
        )
        let rawParagraphs = paragraphNormalized
            .components(separatedBy: "\u{2029}")
            .map(normalizedChineseSpacing)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if rawParagraphs.count > 1 {
            return NewYorkTimesArticle(blocks: rawParagraphs.map(NewYorkTimesArticleBlock.paragraph))
        }

        let sentenceNormalized = normalized.replacingOccurrences(
            of: #"(?<=[。！？])\s+"#,
            with: "\n",
            options: .regularExpression
        )
        let sentences = sentenceNormalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .map(normalizedChineseSpacing)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !sentences.isEmpty else { return nil }
        var paragraphs: [NewYorkTimesArticleBlock] = []
        var current = ""
        for sentence in sentences {
            current = current.isEmpty ? sentence : normalizedChineseSpacing(current + " " + sentence)
            if current.count >= 180 {
                paragraphs.append(.paragraph(current))
                current = ""
            }
        }
        if !current.isEmpty { paragraphs.append(.paragraph(current)) }
        return NewYorkTimesArticle(blocks: paragraphs)
    }

    private static func normalizedChineseSpacing(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"([\u3400-\u9FFF，。！？；：、“”‘’（）《》])[ \t\u00A0]+(?=[\u3400-\u9FFF，。！？；：、“”‘’（）《》])"#,
            with: "$1",
            options: .regularExpression
        )
    }

}

struct NewYorkTimesArticlePhoto: Equatable {
    let url: URL
    var caption: String? = nil
    var credit: String? = nil

    func matches(_ other: URL) -> Bool {
        let source = ImageLoader.sourceImageURL(from: url)
        let otherSource = ImageLoader.sourceImageURL(from: other)
        if source == otherSource { return true }
        guard source.host == otherSource.host,
              source.host?.hasSuffix(".nyt.com") == true else { return false }
        return Self.assetPath(for: source) == Self.assetPath(for: otherSource)
    }

    private static func assetPath(for url: URL) -> String {
        // Strip the rendition while retaining any revision of the source photo.
        url.deletingPathExtension().path.replacingOccurrences(
            of: #"-(?:article[A-Za-z]+|videoLarge|master[0-9]+|thumb[A-Za-z]+|superJumbo|jumbo)(?=(?:-v[0-9]+)?$)"#,
            with: "",
            options: .regularExpression
        )
    }
}

enum NewYorkTimesArticleBlock: Equatable {
    case paragraph(String)
    case linkedParagraph(String, links: [NewYorkTimesArticleLink])
    case image(NewYorkTimesArticlePhoto)

    var paragraphText: String? {
        switch self {
        case .paragraph(let text), .linkedParagraph(let text, _): text
        case .image: nil
        }
    }
}

struct NewYorkTimesArticleLink: Equatable {
    let label: String
    let url: URL
}

enum NewYorkTimesArticleError: Error {
    case bodyMissing
}

enum NewYorkTimesArticleParser {
    private typealias Node = xmlNodePtr
    private static let ignoredTags: Set<String> = ["aside", "button", "figcaption", "footer", "form", "nav", "noscript", "script", "style", "svg"]
    private static let ignoredClasses: Set<String> = ["article-body-aside", "big_ad"]
    private static let blockTags: Set<String> = ["blockquote", "div", "figure", "h2", "h3", "h4", "h5", "h6", "li", "p", "section"]

    static func extract(from html: String, baseURL: URL) -> NewYorkTimesArticle? {
        let length = html.utf8.count
        guard length > 0, let byteCount = Int32(exactly: length) else { return nil }
        let options = HTML_PARSE_NONET.rawValue | HTML_PARSE_NOERROR.rawValue | HTML_PARSE_NOWARNING.rawValue
        guard let document = html.withCString({
            htmlReadMemory($0, byteCount, nil, "UTF-8", Int32(options))
        }) else { return nil }
        defer { xmlFreeDoc(document) }

        guard let article = firstElement(in: xmlDocGetRootElement(document), matching: { tag($0) == "article" && classes($0).contains("article-content") }),
              let body = firstElement(in: article.pointee.children, matching: { classes($0).contains("article-body") }) else { return nil }

        let cover = firstElement(in: article.pointee.children, matching: { classes($0).contains("article-span-photo") })
            .flatMap { figure in
                firstElement(in: figure.pointee.children, matching: { tag($0) == "img" })
                    .flatMap { photo($0, figure: figure, baseURL: baseURL) }
            }
        var reader = Reader(baseURL: baseURL)
        reader.visitSiblings(body.pointee.children)
        reader.flushText()
        return .structured(blocks: reader.blocks, cover: cover)
    }

    private struct Reader {
        let baseURL: URL
        var blocks: [NewYorkTimesArticleBlock] = []
        private var text = ""
        private var links: [NewYorkTimesArticleLink] = []

        init(baseURL: URL) { self.baseURL = baseURL }

        mutating func visitSiblings(_ first: Node?, figure: Node? = nil) {
            var current = first
            while let node = current {
                visit(node, figure: figure)
                current = node.pointee.next
            }
        }

        private mutating func visit(_ node: Node, figure: Node?) {
            if node.pointee.type == XML_TEXT_NODE, let value = node.pointee.content {
                text += String(cString: value)
                return
            }
            guard node.pointee.type == XML_ELEMENT_NODE else { return }
            let name = tag(node)
            guard !ignoredTags.contains(name), classes(node).isDisjoint(with: ignoredClasses) else { return }
            switch name {
            case "br":
                text += "\n"
            case "img":
                guard let photo = photo(node, figure: figure, baseURL: baseURL) else { return }
                flushText()
                blocks.append(.image(photo))
            case "a":
                let label = normalizedText(textContent(node))
                if !label.isEmpty, let url = resolvedURL(attribute("href", of: node), relativeTo: baseURL) {
                    links.append(.init(label: label, url: url))
                }
                visitSiblings(node.pointee.children, figure: figure)
            default:
                let separatesText = blockTags.contains(name)
                if separatesText { flushText() }
                visitSiblings(node.pointee.children, figure: name == "figure" ? node : figure)
                if separatesText { flushText() }
            }
        }

        mutating func flushText() {
            let paragraph = normalizedText(text)
            if !paragraph.isEmpty {
                blocks.append(links.isEmpty ? .paragraph(paragraph) : .linkedParagraph(paragraph, links: links))
            }
            text = ""
            links.removeAll(keepingCapacity: true)
        }
    }

    private static func photo(_ image: Node, figure: Node?, baseURL: URL) -> NewYorkTimesArticlePhoto? {
        guard let source = resolvedURL(attribute("data-src", of: image), relativeTo: baseURL)
                ?? resolvedURL(attribute("src", of: image), relativeTo: baseURL),
              let url = MediaURL.image(source.absoluteString) else { return nil }
        let caption = firstElement(in: figure?.pointee.children, matching: { tag($0) == "figcaption" })
        let credit = firstElement(in: caption?.pointee.children, matching: { tag($0) == "cite" })
        return NewYorkTimesArticlePhoto(
            url: url,
            caption: caption.flatMap { nonEmptyText(textContent($0, omitting: "cite")) }
                ?? attribute("alt", of: image).flatMap(nonEmptyText),
            credit: credit.flatMap { nonEmptyText(textContent($0)) }
        )
    }

    private static func firstElement(in first: Node?, matching: (Node) -> Bool) -> Node? {
        var current = first
        while let node = current {
            if node.pointee.type == XML_ELEMENT_NODE {
                if matching(node) { return node }
                if let found = firstElement(in: node.pointee.children, matching: matching) { return found }
            }
            current = node.pointee.next
        }
        return nil
    }

    private static func textContent(_ node: Node, omitting skippedTag: String? = nil) -> String {
        if node.pointee.type == XML_TEXT_NODE, let value = node.pointee.content { return String(cString: value) }
        guard node.pointee.type == XML_ELEMENT_NODE, tag(node) != skippedTag else { return "" }
        var result = ""
        var current = node.pointee.children
        while let child = current {
            result += textContent(child, omitting: skippedTag)
            current = child.pointee.next
        }
        return result
    }

    private static func tag(_ node: Node) -> String {
        String(cString: node.pointee.name)
    }

    private static func classes(_ node: Node) -> Set<String> {
        Set((attribute("class", of: node) ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
    }

    private static func attribute(_ name: String, of node: Node) -> String? {
        guard let value = name.utf8CString.withUnsafeBufferPointer({ buffer in
            buffer.baseAddress?.withMemoryRebound(to: UInt8.self, capacity: buffer.count) { xmlGetProp(node, $0) }
        }) else { return nil }
        defer { xmlFree(value) }
        return String(cString: value)
    }

    private static func normalizedText(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func nonEmptyText(_ text: String) -> String? {
        let value = normalizedText(text)
        return value.isEmpty ? nil : value
    }

    private static func resolvedURL(_ value: String?, relativeTo baseURL: URL) -> URL? {
        guard let value, !value.isEmpty, !value.hasPrefix("#"),
              let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return url
    }
}

struct ArticlePreviewResponse: Decodable {
    let data: Payload
    struct Payload: Decodable {
        let title: String
        let byline: String
        let excerpt: String
        let siteName: String
        let content: String
        let textContent: String
        let titleZH: String
        let contentZH: String
        let textContentZH: String

        enum CodingKeys: String, CodingKey {
            case title, byline, excerpt, siteName, content, textContent
            case titleZH = "titleZh"
            case contentZH = "contentZh"
            case textContentZH = "textContentZh"
        }
    }
}

struct WikipediaRelayEntity: Decodable, Equatable {
    let query: String
    let id: String
    let pageID: Int64
    let language: String
    let title: String
    let extract: String?
    let articleURL: URL

    enum CodingKeys: String, CodingKey {
        case query, id, language, title, extract
        case pageID = "page_id"
        case articleURL = "article_url"
    }
}

private struct WikipediaRelayEntitiesResponse: Decodable {
    let success: Bool
    let entities: [WikipediaRelayEntity]
}

struct WikipediaRelayArticle: Decodable, Equatable {
    let language: String
    let pageID: Int64
    let title: String
    let displayTitle: String
    let html: String
    let articleURL: URL

    enum CodingKeys: String, CodingKey {
        case language, title, html
        case pageID = "page_id"
        case displayTitle = "display_title"
        case articleURL = "article_url"
    }
}

private struct WikipediaRelayArticleResponse: Decodable {
    let success: Bool
    let article: WikipediaRelayArticle
}

private struct AliyunBalanceResponse: Decodable {
    let success: Bool
    let data: AliyunAccountBalance
}

struct AliyunAccountBalance: Codable, Equatable {
    let ok: Bool
    let currency: String
    let availableAmount: String?
    let usage: AIUsageDailyCosts

    var hasMissingFigures: Bool {
        formattedAmount == nil || usage.todayCostCNY == nil || usage.yesterdayCostCNY == nil
    }

    var formattedAmount: String? {
        guard ok, let availableAmount,
              let amount = Decimal(string: availableAmount, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return amount.formatted(.currency(code: currency).locale(Locale(identifier: "zh_CN")))
    }
}

struct AIUsageDailyCosts: Codable, Equatable, Sendable {
    let date: String
    let yesterdayDate: String
    let timezone: String
    let todayCostCNY: Double?
    let yesterdayCostCNY: Double?

    enum CodingKeys: String, CodingKey {
        case date, yesterdayDate, timezone
        case todayCostCNY = "todayCostCny"
        case yesterdayCostCNY = "yesterdayCostCny"
    }

    static func formattedCost(_ amount: Double?) -> String? {
        guard let amount, amount.isFinite else { return nil }
        return amount.formatted(.currency(code: "CNY")
            .precision(.fractionLength(2...6))
            .locale(Locale(identifier: "zh_CN")))
    }
}

private struct HealthResponse: Decodable { let status: String }

struct TodayWorldYesterdayReportResponse: Decodable {
    let success: Bool
    let data: TodayWorldYesterdayReportPayload
}

struct TodayWorldYesterdayReportPayload: Decodable, Equatable {
    let date: String
    let timezone: String
    let status: String
    let stage: String
    let progress: Int
    let sourceCount: Int
    let postCount: Int
    struct Admission: Decodable, Equatable {
        let state: String
        let reason_codes: [String]
        let reason: String?
    }
    let admission: Admission?
    let report: TodayWorldYesterdayReportContent
    let model: String?
    let totalTokens: Int
    let costCNY: Double
    let completedAt: String?

    struct Diagnostic: Decodable, Equatable {
        let scope: String
        let itemID: String
        let systemName: String?
        let reasonCode: String
        let reason: String

        enum CodingKeys: String, CodingKey {
            case scope, reason
            case itemID = "item_id"
            case systemName = "system_name"
            case reasonCode = "reason_code"
        }
    }

    struct Generation: Decodable, Equatable {
        let unfinishedIssueCount: Int?

        enum CodingKeys: String, CodingKey {
            case unfinishedIssueCount = "unfinished_issue_count"
        }
    }

    let diagnostics: [Diagnostic]?
    let generation: Generation?

    enum CodingKeys: String, CodingKey {
        case date, timezone, status, stage, progress, report, model, admission, diagnostics, generation
        case sourceCount = "source_count"
        case postCount = "post_count"
        case totalTokens = "total_tokens"
        case costCNY = "cost_cny"
        case completedAt = "completed_at"
    }

    var isGenerating: Bool {
        status == "running" || status == "queued"
            || report.final?.status == "running" || report.final?.status == "queued"
    }
}

struct TodayWorldYesterdayReportContent: Decodable, Equatable {
    struct SourceSection: Decodable, Equatable {
        struct Group: Decodable, Equatable {
            struct System: Decodable, Equatable {
                struct Account: Decodable, Equatable {
                    let post_ids: [Int]
                }
                let accounts: [Account]
            }
            let group_name: String
            let systems: [System]
        }
        let section_key: String
        let section_name: String
        let groups: [Group]

        var postCount: Int {
            Set(groups.flatMap(\.systems).flatMap(\.accounts).flatMap(\.post_ids)).count
        }
    }
    let sections: [SourceSection]?
    let final: TodayWorldFinalReport?
}

struct TodayWorldFinalReport: Codable, Sendable, Equatable {
    struct FailedItem: Codable, Sendable, Equatable {
        let itemID: String

        enum CodingKeys: String, CodingKey {
            case itemID = "item_id"
        }
    }

    let status: String
    let stage: String?
    let error: String?
    let completenessStatus: String?
    let failedItems: [FailedItem]?
    let sections: [TodayWorldFinalReportSection]
    let sectionCount: Int
    let groupCount: Int
    let systemCount: Int
    let sourceCharCount: Int
    let charCount: Int
    let compressionRatio: Double?
    let model: String?
    let totalTokens: Int?
    let costCNY: Double?
    let completedAt: String?
    let overview: TodayWorldFinalReportOverview

    enum CodingKeys: String, CodingKey {
        case status, stage, error, sections, model, overview
        case completenessStatus = "completeness_status"
        case failedItems = "failed_items"
        case sectionCount = "section_count"
        case groupCount = "group_count"
        case systemCount = "system_count"
        case sourceCharCount = "source_char_count"
        case charCount = "char_count"
        case compressionRatio = "compression_ratio"
        case totalTokens = "total_tokens"
        case costCNY = "cost_cny"
        case completedAt = "completed_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        stage = try container.decodeIfPresent(String.self, forKey: .stage)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        completenessStatus = try container.decodeIfPresent(String.self, forKey: .completenessStatus)
        failedItems = try container.decodeIfPresent([FailedItem].self, forKey: .failedItems)
        let decodedSections = try container.decodeIfPresent([TodayWorldFinalReportSection].self, forKey: .sections) ?? []
        sections = decodedSections
        sectionCount = try container.decodeIfPresent(Int.self, forKey: .sectionCount) ?? decodedSections.count
        groupCount = try container.decodeIfPresent(Int.self, forKey: .groupCount) ?? decodedSections.reduce(0) { $0 + $1.groups.count }
        systemCount = try container.decodeIfPresent(Int.self, forKey: .systemCount) ?? decodedSections.reduce(0) { $0 + $1.systems.count }
        sourceCharCount = try container.decodeIfPresent(Int.self, forKey: .sourceCharCount) ?? 0
        charCount = try container.decodeIfPresent(Int.self, forKey: .charCount) ?? 0
        compressionRatio = try container.decodeIfPresent(Double.self, forKey: .compressionRatio)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
        costCNY = try container.decodeIfPresent(Double.self, forKey: .costCNY)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        if status == "succeeded" {
            guard !decodedSections.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .sections, in: container, debugDescription: "最终版日报缺少 sections")
            }
            overview = try container.decode(TodayWorldFinalReportOverview.self, forKey: .overview)
        } else {
            overview = try container.decodeIfPresent(TodayWorldFinalReportOverview.self, forKey: .overview) ?? .empty
        }
    }

    var systems: [TodayWorldFinalReportSystem] {
        sections.flatMap(\.systems)
    }
}

struct TodayWorldFinalReportSection: Codable, Sendable, Equatable, Identifiable {
    let sectionKey: String
    let sectionName: String
    let groups: [TodayWorldFinalReportGroup]
    var id: String { sectionKey }

    var systems: [TodayWorldFinalReportSystem] {
        groups.flatMap(\.systems)
    }

    enum CodingKeys: String, CodingKey {
        case groups
        case sectionKey = "section_key"
        case sectionName = "section_name"
    }
}

struct TodayWorldFinalReportGroup: Codable, Sendable, Equatable, Identifiable {
    let groupKey: String
    let groupName: String
    let systems: [TodayWorldFinalReportSystem]
    var id: String { groupKey }

    enum CodingKeys: String, CodingKey {
        case systems
        case groupKey = "group_key"
        case groupName = "group_name"
    }
}

struct TodayWorldFinalReportSystem: Codable, Sendable, Equatable, Identifiable {
    let systemKey: String
    let systemName: String
    let headline: String
    let signalLevel: String
    let facts: [TodayWorldFinalReportFact]
    let watchItem: String?
    let sourceKeys: [String]
    let sourceNames: [String]
    let postIDs: [Int]
    var id: String { systemKey }

    enum CodingKeys: String, CodingKey {
        case headline, facts
        case signalLevel = "signal_level"
        case watchItem = "watch_item"
        case systemKey = "system_key"
        case systemName = "system_name"
        case sourceKeys = "source_keys"
        case sourceNames = "source_names"
        case postIDs = "post_ids"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        systemKey = try container.decode(String.self, forKey: .systemKey)
        systemName = try container.decode(String.self, forKey: .systemName)
        headline = try container.decode(String.self, forKey: .headline)
        signalLevel = try container.decode(String.self, forKey: .signalLevel)
        facts = try container.decode([TodayWorldFinalReportFact].self, forKey: .facts)
        watchItem = try container.decodeIfPresent(String.self, forKey: .watchItem)
        sourceKeys = try container.decode([String].self, forKey: .sourceKeys)
        sourceNames = try container.decode([String].self, forKey: .sourceNames)
        postIDs = try container.decode([Int].self, forKey: .postIDs)
    }
}

struct TodayWorldFinalReportOverview: Codable, Sendable, Equatable {
    let headline: String
    let highlights: [TodayWorldFinalReportOverviewItem]
    let watchItems: [TodayWorldFinalReportOverviewItem]

    static let empty = TodayWorldFinalReportOverview(headline: "", highlights: [], watchItems: [])

    enum CodingKeys: String, CodingKey {
        case headline, highlights
        case watchItems = "watch_items"
    }
}

struct TodayWorldFinalReportOverviewItem: Codable, Sendable, Equatable, Identifiable {
    let title: String?
    let text: String
    let context: String?
    let systemKeys: [String]
    let postIDs: [Int]
    var id: String { ([title, text].compactMap { $0 } + postIDs.map(String.init)).joined(separator: "|") }

    init(title: String?, text: String, systemKeys: [String], postIDs: [Int], context: String? = nil) {
        self.title = title
        self.text = text
        self.systemKeys = systemKeys
        self.postIDs = postIDs
        self.context = context
    }

    enum CodingKeys: String, CodingKey {
        case title, text, context
        case systemKeys = "system_keys"
        case postIDs = "post_ids"
    }
}

struct TodayWorldFinalReportFact: Codable, Sendable, Equatable, Identifiable {
    let category: String
    let text: String
    let sourceKeys: [String]
    let postIDs: [Int]
    var id: String { "\(category)|\(text)|\(postIDs.map(String.init).joined(separator: ","))" }

    enum CodingKeys: String, CodingKey {
        case category, text
        case sourceKeys = "source_keys"
        case postIDs = "post_ids"
    }
}

private struct XBookmarkRequest: Encodable {
    let articleID: String
    enum CodingKeys: String, CodingKey { case articleID = "article_id" }
}
private struct XBookmarkResponse: Decodable { let success: Bool; let data: XBookmarkResult }
private struct VideoPlaybackRequest: Encodable {
    let url, title, formatID: String
    enum CodingKeys: String, CodingKey { case url, title; case formatID = "formatId" }
}
private struct VideoPlaybackResponse: Decodable {
    let success: Bool
    let data: Payload
    struct Payload: Decodable {
        let sourceURL: String
        let label: String?
        let httpHeaders: [String: String]?
        enum CodingKeys: String, CodingKey { case label, httpHeaders; case sourceURL = "sourceUrl" }
    }
}
struct VideoPlaybackSource: Equatable {
    let url: URL
    let label: String?
    let httpHeaders: [String: String]
}
struct XBookmarkResult: Decodable, Equatable {
    let articleID: String
    let bookmarked: Bool
    let url, savedAt: String?
    enum CodingKeys: String, CodingKey {
        case bookmarked, url
        case articleID = "article_id"
        case savedAt = "saved_at"
    }
}
struct XTranslationDeferral: Error {
    let seconds: Int
    let isPostSpecific: Bool

    init?(_ response: HTTPURLResponse) {
        guard response.statusCode == 429,
              let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Int(raw), seconds > 0 else { return nil }
        self.seconds = seconds
        isPostSpecific = response.value(forHTTPHeaderField: "X-Translation-Reason") == "in_flight"
    }
}

enum APIError: LocalizedError {
    case invalidURL, invalidResponse, httpStatus(Int), decoding(Error), missingCategory(String), invalidXPostID, sourceUnavailable(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: "服务器地址无效"
        case .invalidResponse: "服务器响应无效"
        case .httpStatus(let code): "服务器返回错误（\(code)）"
        case .sourceUnavailable(let message): message
        case .decoding: "新闻数据格式暂时无法识别"
        case .missingCategory(let name): "找不到 \(name) 数据分类"
        case .invalidXPostID: "这条内容缺少有效的 X 帖子 ID"
        }
    }
}

private struct FeedSourceFailure: Decodable { let message: String }
