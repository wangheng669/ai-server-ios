import Foundation

struct APIClient {
    let baseURL: URL
    private let session: URLSession
    init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session { self.session = session } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.requestCachePolicy = .useProtocolCachePolicy
            config.urlCache = .shared
            self.session = URLSession(configuration: config)
        }
    }

    func checkHealth() async throws { let _: HealthResponse = try await get(baseURL.appending(path: "health")) }

    func fetchTodayWorld(limit: Int = 3, page: Int = 1, systemKey: String? = nil) async throws -> TodayWorldPayload {
        var components = URLComponents(
            url: baseURL.appending(path: "api/ios/v1/today-world"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            .init(name: "limit", value: String(min(max(limit, 1), 20))),
            .init(name: "page", value: String(max(page, 1)))
        ]
        if let systemKey, !systemKey.isEmpty {
            components?.queryItems?.append(.init(name: "system_key", value: systemKey))
        }
        guard let url = components?.url else { throw APIError.invalidURL }
        let response: TodayWorldResponse = try await get(
            url,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.success else { throw APIError.invalidResponse }
        return response.data
    }

    func fetchTodayWorldYesterdayReport() async throws -> TodayWorldYesterdayReportPayload {
        let response: TodayWorldYesterdayReportResponse = try await get(
            baseURL.appending(path: "api/ios/v1/today-world/yesterday-report"),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.success else { throw APIError.invalidResponse }
        return response.data
    }

    func fetchGoogleNoise(sentiment: String? = nil, limit: Int = 60) async throws -> GoogleNoiseSnapshot {
        var components = URLComponents(
            url: baseURL.appending(path: "api/ios/v1/google-noise"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [.init(name: "limit", value: String(min(max(limit, 1), 100)))]
        if let sentiment, sentiment == "positive" || sentiment == "negative" || sentiment == "neutral" {
            components?.queryItems?.append(.init(name: "sentiment", value: sentiment))
        }
        guard let url = components?.url else { throw APIError.invalidURL }
        let response: GoogleNoiseResponse = try await get(url, cachePolicy: .reloadIgnoringLocalCacheData)
        guard response.success else { throw APIError.invalidResponse }
        return response.data.snapshot
    }

    func fetchPosts(
        page: Int,
        limit: Int = 20,
        source: FeedSource,
        flashCategory: String? = nil
    ) async throws -> [Post] {
        switch source {
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
        case .xueqiu:
            return try await fetchXueqiuPosts(page: page, limit: limit)
        case .wechat:
            return try await fetchWeChatPosts(page: page, limit: limit)
        default:
            return try await fetchRegularPosts(page: page, limit: limit, source: source)
        }
    }

    func fetchRSSFeeds() async throws -> [RSSFeedSource] {
        let pageSize = 20
        func fetchPage(_ page: Int) async throws -> RSSFeedsResponse {
            var parts = URLComponents(url: baseURL.appending(path: "api/ios/v1/rss/feeds"), resolvingAgainstBaseURL: false)
            parts?.queryItems = [
                .init(name: "page", value: String(page)),
                .init(name: "exclude_social", value: "true")
            ]
            guard let url = parts?.url else { throw APIError.invalidURL }
            return try await get(url)
        }

        let firstPage = try await fetchPage(1)
        var pages: [(number: Int, feeds: [RSSFeedSource])] = [(1, firstPage.data.feeds)]
        if let pagination = firstPage.meta?.pagination {
            let totalPages = min(10, max(1, Int(ceil(Double(pagination.total) / Double(max(pagination.size, 1))))))
            if totalPages > 1 {
                let remaining = try await withThrowingTaskGroup(
                    of: (Int, [RSSFeedSource]).self,
                    returning: [(Int, [RSSFeedSource])].self
                ) { group in
                    for page in 2...totalPages {
                        group.addTask {
                            let response = try await fetchPage(page)
                            return (page, response.data.feeds)
                        }
                    }
                    var result: [(Int, [RSSFeedSource])] = []
                    for try await page in group { result.append(page) }
                    return result
                }
                pages += remaining
            }
        } else if firstPage.data.feeds.count == pageSize {
            for page in 2...10 {
                let response = try await fetchPage(page)
                pages.append((page, response.data.feeds))
                if response.data.feeds.count < pageSize { break }
            }
        }

        let feeds = pages.sorted { $0.number < $1.number }
            .flatMap(\.feeds)
            .filter(\.isEnabled)
        var seen = Set<Int>()
        return feeds.filter { seen.insert($0.id).inserted }
    }

    func fetchRSSFeedPosts(
        feedID: Int,
        page: Int = 1,
        limit: Int = 20,
        includesAllScores: Bool = false
    ) async throws -> [Post] {
        var parts = URLComponents(
            url: baseURL.appending(path: "api/ios/v1/rss/feeds/\(feedID)/posts"),
            resolvingAgainstBaseURL: false
        )
        var queryItems: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "limit", value: String(limit)),
            .init(name: "sort", value: "time_desc"),
            .init(name: "include_zero_score", value: includesAllScores ? "true" : "false")
        ]
        if !includesAllScores {
            queryItems.append(.init(name: "final_score", value: String(Post.minimumFeedScore)))
        }
        parts?.queryItems = queryItems
        guard let url = parts?.url else { throw APIError.invalidURL }
        let response: RSSFeedPostsResponse = try await get(url)
        return response.data.posts
    }

    func fetchWeiboFollowingPosts(page: Int, limit: Int = 20) async throws -> [Post] {
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

    static let weChatFeedIDs = [57, 2373]

    private func fetchWeChatPosts(page: Int, limit: Int) async throws -> [Post] {
        let requestedCount = page * limit
        let posts = try await withThrowingTaskGroup(of: [Post].self) { group in
            for feedID in Self.weChatFeedIDs {
                group.addTask {
                    try await self.fetchRSSFeedPosts(
                        feedID: feedID,
                        page: 1,
                        limit: requestedCount,
                        includesAllScores: true
                    )
                }
            }

            var posts: [Post] = []
            for try await result in group { posts += result }
            return posts
        }
        let merged = Self.mergeWeChatPosts(posts)
        let start = (page - 1) * limit
        guard start < merged.count else { return [] }
        return Array(merged.dropFirst(start).prefix(limit))
    }

    static func mergeWeChatPosts(_ posts: [Post]) -> [Post] {
        var seen = Set<Int>()
        return posts
            .sorted { ($0.articlePostAt ?? "") > ($1.articlePostAt ?? "") }
            .filter { seen.insert($0.id).inserted }
    }

    private func fetchXueqiuPosts(page: Int, limit: Int) async throws -> [Post] {
        try await withThrowingTaskGroup(of: [Post].self) { group in
            for feedID in [14, 16] {
                group.addTask {
                    var parts = URLComponents(
                        url: baseURL.appending(path: "api/ios/v1/rss/feeds/\(feedID)/posts"),
                        resolvingAgainstBaseURL: false
                    )
                    parts?.queryItems = [
                        .init(name: "page", value: String(page)),
                        .init(name: "limit", value: String(limit)),
                        .init(name: "sort", value: "time_desc"),
                        .init(name: "include_zero_score", value: "true")
                    ]
                    guard let url = parts?.url else { throw APIError.invalidURL }
                    let response: RSSFeedPostsResponse = try await get(url)
                    return response.data.posts
                }
            }

            var posts: [Post] = []
            for try await result in group { posts += result }
            var seen = Set<Int>()
            return posts
                .sorted { ($0.articlePostAt ?? "") > ($1.articlePostAt ?? "") }
                .filter { seen.insert($0.id).inserted }
                .prefix(limit)
                .map { $0 }
        }
    }

    private func fetchRegularPosts(page: Int, limit: Int, source: FeedSource) async throws -> [Post] {
        var components = URLComponents(url: baseURL.appending(path: "api/ios/v1/post/list"), resolvingAgainstBaseURL: false)
        let isSpecialRSS = source == .laozhong || source == .youtube
        var queryItems = Self.regularPostQueryItems(page: page, limit: limit, source: source)
        if isSpecialRSS {
            let name = source == .laozhong ? "老中" : "YouTube"
            queryItems.append(.init(name: "categoryId", value: String(try await categoryID(named: name))))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw APIError.invalidURL }
        let response: PostListResponse = try await get(url)
        return response.data
    }

    static func regularPostQueryItems(page: Int, limit: Int, source: FeedSource) -> [URLQueryItem] {
        let isSpecialRSS = source == .laozhong || source == .youtube
        let includesAllScores = source == .newYorkTimes || source == .wechat || source == .youtube
        var queryItems: [URLQueryItem] = [
            .init(name: "page", value: String(page)), .init(name: "limit", value: String(limit)),
            .init(name: "sort", value: "time_desc"),
            .init(name: "group_similar", value: "1"), .init(name: "group_threshold", value: "70"),
            .init(name: "source", value: isSpecialRSS ? "rss" : source.rawValue),
            .init(name: "include_zero_score", value: includesAllScores ? "true" : "false")
        ]
        if !includesAllScores {
            let minimumScore = source == .rss ? 6 : Post.minimumFeedScore
            queryItems.append(.init(name: "final_score", value: String(minimumScore)))
        }
        if source == .x { queryItems.append(.init(name: "x_feed_view", value: "tracked")) }
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
        return try await get(url)
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
        let response: XTranslationResponse = try await get(url, retriesTransientFailures: false)
        guard response.success else { throw APIError.invalidResponse }
        return response.data
    }

    func synthesizeSpeech(text: String) async throws -> URL {
        var request = URLRequest(url: baseURL.appending(path: "api/ios/v1/audio/speech"))
        request.httpMethod = "POST"
        request.timeoutInterval = 130
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(TextToSpeechRequest(text: text))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.httpStatus(http.statusCode) }
        let payload = try JSONDecoder().decode(TextToSpeechResponse.self, from: data)
        guard payload.success, let url = URL(string: payload.data.audioUrl) else { throw APIError.invalidURL }
        return url
    }

    func resolveYouTubePlayback(url: URL, title: String) async throws -> VideoPlaybackSource {
        try await resolveVideoPlayback(url: url, title: title, formatID: "18")
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
        let response = try await fetchArticlePreview(url: url)
        if let article = NewYorkTimesArticleParser.extract(from: response.data.content) { return article }
        let paragraphs = response.data.textContent
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(NewYorkTimesArticleBlock.paragraph)
        guard !paragraphs.isEmpty else { throw APIError.decoding(NYTimesArticleError.bodyMissing) }
        return NewYorkTimesArticle(blocks: paragraphs)
    }

    func fetchArticlePreview(url: URL) async throws -> ArticlePreviewResponse {
        guard let previewURL = Self.articlePreviewURL(for: url, baseURL: baseURL) else { throw APIError.invalidURL }
        return try await get(previewURL)
    }

    static func articlePreviewURL(for articleURL: URL, baseURL: URL) -> URL? {
        var parts = URLComponents(url: baseURL.appending(path: "api/ios/v1/post/preview"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [
            .init(name: "url", value: articleURL.absoluteString),
        ]
        return parts?.url
    }

    private func get<Response: Decodable>(
        _ url: URL,
        retriesTransientFailures: Bool = true,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> Response {
        let attempts = retriesTransientFailures ? 2 : 1
        for attempt in 0..<attempts {
            do {
                let request = URLRequest(url: url, cachePolicy: cachePolicy)
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                if [500, 502, 503, 504].contains(http.statusCode), attempt + 1 < attempts {
                    try await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
                    continue
                }
                guard (200..<300).contains(http.statusCode) else { throw APIError.httpStatus(http.statusCode) }
                do { return try JSONDecoder().decode(Response.self, from: data) }
                catch {
                    #if DEBUG
                    print("Feed request decoding failed: \(url.absoluteString) — \(error)")
                    #endif
                    throw APIError.decoding(error)
                }
            } catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                guard attempt + 1 < attempts else { throw error }
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

private struct TextToSpeechRequest: Encodable {
    let text: String
}

private struct TextToSpeechResponse: Decodable {
    let success: Bool
    let data: TextToSpeechData
}

private struct TextToSpeechData: Decodable {
    let audioUrl: String
}

struct NewYorkTimesArticle: Equatable {
    let blocks: [NewYorkTimesArticleBlock]

    static func storedText(_ text: String) -> NewYorkTimesArticle? {
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

    static func isSameImageAsset(_ lhs: URL, _ rhs: URL?) -> Bool {
        guard let rhs, let lhsKey = imageAssetKey(lhs), let rhsKey = imageAssetKey(rhs) else { return lhs == rhs }
        return lhsKey == rhsKey
    }

    private static func imageAssetKey(_ url: URL) -> String? {
        let original = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "url" })?
            .value
            .flatMap(URL.init(string:)) ?? url
        let components = original.path.split(separator: "/")
        guard let imagesIndex = components.firstIndex(of: "images"), imagesIndex + 1 < components.endIndex else { return nil }
        let assetPath = components[(imagesIndex + 1)..<components.endIndex].dropLast().map(String.init)
        return ([original.host ?? ""] + assetPath).joined(separator: "/")
    }
}

enum NewYorkTimesArticleBlock: Equatable {
    case paragraph(String)
    case image(url: URL, caption: String?, credit: String?)
}

enum NewYorkTimesArticleParser {
    private static let paragraphOpeningRegex = try! NSRegularExpression(
        pattern: #"<div\b[^>]*\bclass=["'][^"']*\barticle-paragraph\b[^"']*["'][^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let divTokenRegex = try! NSRegularExpression(
        pattern: #"</?div\b[^>]*>"#,
        options: [.caseInsensitive]
    )

    static func extract(from html: String) -> NewYorkTimesArticle? {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let blocks = paragraphOpeningRegex.matches(in: html, range: range).compactMap { match -> NewYorkTimesArticleBlock? in
            guard let fragment = balancedContent(for: match, in: html) else { return nil }
            if let url = imageURL(in: fragment) {
                return .image(
                    url: url,
                    caption: attribute(named: "alt", in: fragment).flatMap(decodeHTML),
                    credit: element(named: "cite", in: fragment).flatMap(decodeHTML)
                )
            }
            guard let paragraph = decodeHTML(fragment), !paragraph.isEmpty else { return nil }
            return .paragraph(paragraph)
        }
        return blocks.isEmpty ? nil : NewYorkTimesArticle(blocks: blocks)
    }

    private static func balancedContent(for opening: NSTextCheckingResult, in html: String) -> String? {
        let contentLocation = opening.range.location + opening.range.length
        let searchRange = NSRange(location: contentLocation, length: (html as NSString).length - contentLocation)
        var depth = 1
        for token in divTokenRegex.matches(in: html, range: searchRange) {
            let value = (html as NSString).substring(with: token.range).lowercased()
            if value.hasPrefix("</div") { depth -= 1 } else { depth += 1 }
            if depth == 0 {
                return (html as NSString).substring(
                    with: NSRange(location: contentLocation, length: token.range.location - contentLocation)
                )
            }
        }
        return nil
    }

    private static func imageURL(in fragment: String) -> URL? {
        for attributeName in ["data-src", "src"] {
            if let value = attribute(named: attributeName, in: fragment),
               let decoded = decodeHTML(value),
               let url = MediaURL.image(decoded) {
                return url
            }
        }
        return nil
    }

    private static func attribute(named name: String, in fragment: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: #"\b"# + escaped + #"\s*=\s*["']([^"']+)["']"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(fragment.startIndex..<fragment.endIndex, in: fragment)
        guard let match = regex.firstMatch(in: fragment, range: range),
              let valueRange = Range(match.range(at: 1), in: fragment) else { return nil }
        return String(fragment[valueRange])
    }

    private static func element(named name: String, in fragment: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: #"<"# + escaped + #"\b[^>]*>(.*?)</"# + escaped + #"\s*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(fragment.startIndex..<fragment.endIndex, in: fragment)
        guard let match = regex.firstMatch(in: fragment, range: range),
              let valueRange = Range(match.range(at: 1), in: fragment) else { return nil }
        return String(fragment[valueRange])
    }

    private static func decodeHTML(_ fragment: String) -> String? {
        guard let data = ("<span>\(fragment)</span>").data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else { return nil }
        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum NYTimesArticleError: Error { case bodyMissing }

struct ArticlePreviewResponse: Decodable {
    let data: Payload
    struct Payload: Decodable {
        let title: String
        let content: String
        let textContent: String
        let titleZH: String
        let textContentZH: String

        enum CodingKeys: String, CodingKey {
            case title, content, textContent
            case titleZH = "titleZh"
            case textContentZH = "textContentZh"
        }
    }
}

private struct HealthResponse: Decodable { let status: String }

struct TodayWorldResponse: Decodable {
    let success: Bool
    let data: TodayWorldPayload
}

struct GoogleNoiseResponse: Decodable {
    let success: Bool
    let data: Payload

    struct Payload: Decodable { let snapshot: GoogleNoiseSnapshot }
}

struct GoogleNoiseSnapshot: Decodable, Equatable {
    let generatedAt: String
    let stats: GoogleNoiseStats
    let items: [GoogleNoiseItem]

    enum CodingKeys: String, CodingKey {
        case stats, items
        case generatedAt = "generated_at"
    }
}

struct GoogleNoiseStats: Decodable, Equatable {
    let scanned: Int
    let relevant: Int
    let positive: Int
    let negative: Int
    let neutral: Int
}

struct GoogleNoiseItem: Decodable, Equatable, Identifiable {
    let id: Int64
    let postID: Int64
    let articleID: String
    let title: String
    let content: String
    let originalContent: String
    let contentZH: String?
    let language: String
    let authorName: String
    let authorHandle: String
    let avatarURL: String
    let sourceURL: String
    let sentiment: String
    let score: Int
    let companyTerms: [String]
    let sentimentTerms: [String]
    let publishedAt: String?
    let classifiedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, content, sentiment, score, language
        case postID = "post_id"
        case articleID = "article_id"
        case originalContent = "original_content"
        case contentZH = "content_zh"
        case authorName = "author_name"
        case authorHandle = "author_handle"
        case avatarURL = "avatar_url"
        case sourceURL = "source_url"
        case companyTerms = "company_terms"
        case sentimentTerms = "sentiment_terms"
        case publishedAt = "published_at"
        case classifiedAt = "classified_at"
    }

    var previewPost: Post? {
        guard let postID = Int(exactly: postID) else { return nil }
        let translated = contentZH?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Post(
            id: postID,
            title: title,
            text: originalContent,
            summary: nil,
            content: originalContent,
            contentZH: translated?.isEmpty == false ? translated : nil,
            source: "x",
            formattedTime: publishedAt.flatMap(Self.relativeTime),
            weightReason: nil,
            finalScore: nil,
            weight: nil,
            postLink: sourceURL,
            articlePostAt: publishedAt,
            user: PostUser(
                userName: authorName,
                userScreenName: authorHandle,
                avatarURL: avatarURL,
                userDesc: nil
            ),
            postTags: [],
            images: [],
            videos: [],
            feedRank: nil,
            meta: nil
        )
    }

    var needsTranslation: Bool {
        contentZH?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            && !language.lowercased().hasPrefix("zh")
    }

    private static func relativeTime(_ value: String) -> String? {
        guard let date = ISO8601DateFormatter().date(from: value) else { return nil }
        return date.formatted(.relative(presentation: .named))
    }
}

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
    let report: TodayWorldYesterdayReportContent
    let model: String?
    let totalTokens: Int
    let costCNY: Double
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case date, timezone, status, stage, progress, report, model
        case sourceCount = "source_count"
        case postCount = "post_count"
        case totalTokens = "total_tokens"
        case costCNY = "cost_cny"
        case completedAt = "completed_at"
    }
}

struct TodayWorldYesterdayReportContent: Decodable, Equatable {
    let systems: [TodayWorldYesterdayReportSystem]

    enum CodingKeys: String, CodingKey {
        case systems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        systems = try container.decodeIfPresent([TodayWorldYesterdayReportSystem].self, forKey: .systems) ?? []
    }
}

struct TodayWorldYesterdayReportSystem: Decodable, Equatable, Identifiable {
    let systemKey: String
    let systemName: String
    let accounts: [TodayWorldYesterdayReportAccount]
    var id: String { systemKey }

    enum CodingKeys: String, CodingKey {
        case accounts
        case systemKey = "system_key"
        case systemName = "system_name"
    }
}

struct TodayWorldYesterdayReportAccount: Decodable, Equatable, Identifiable {
    let sourceKey: String
    let name: String
    let sourceType: String?
    let summary: String
    let postIDs: [Int]
    var id: String { sourceKey }

    enum CodingKeys: String, CodingKey {
        case name, summary
        case sourceKey = "source_key"
        case sourceType = "source_type"
        case postIDs = "post_ids"
    }
}

struct TodayWorldPayload: Decodable, Equatable {
    let schemaVersion: String
    let date: String
    let timezone: String
    let generatedAt: String
    let sections: [TodayWorldSection]

    enum CodingKeys: String, CodingKey {
        case date, timezone, sections
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
    }
}

struct TodayWorldSection: Decodable, Identifiable, Equatable {
    let id: String
    let kind: String
    let title: String
    let subtitle: String?
    let layout: String
    let entity: TodayWorldEntity?
    let source: TodayWorldSource?
    let items: [Post]
    let itemCount: Int
    let hasMore: Bool
    let latestAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, subtitle, layout, entity, source, items
        case itemCount = "item_count"
        case hasMore = "has_more"
        case latestAt = "latest_at"
    }
}

struct TodayWorldEntity: Decodable, Equatable {
    let key: String
    let name: String
    let type: String
    let avatarURL: String?
    let xHandle: String?
    let companyKey: String?
    let companyName: String?

    enum CodingKeys: String, CodingKey {
        case key, name, type
        case avatarURL = "avatar_url"
        case xHandle = "x_handle"
        case companyKey = "company_key"
        case companyName = "company_name"
    }
}

struct TodayWorldSource: Decodable, Equatable {
    let type: String
    let platform: String?
    let account: String?
    let feedView: String?
    let homeFeedType: String?

    enum CodingKeys: String, CodingKey {
        case type, platform, account
        case feedView = "feed_view"
        case homeFeedType = "home_feed_type"
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
enum APIError: LocalizedError {
    case invalidURL, invalidResponse, httpStatus(Int), decoding(Error), missingCategory(String), invalidXPostID
    var errorDescription: String? {
        switch self {
        case .invalidURL: "服务器地址无效"
        case .invalidResponse: "服务器响应无效"
        case .httpStatus(let code): "服务器返回错误（\(code)）"
        case .decoding: "新闻数据格式暂时无法识别"
        case .missingCategory(let name): "找不到 \(name) 数据分类"
        case .invalidXPostID: "这条内容缺少有效的 X 帖子 ID"
        }
    }
}
