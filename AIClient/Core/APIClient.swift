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

    func fetchPosts(
        page: Int,
        limit: Int = 20,
        source: FeedSource,
        flashCategory: String? = nil
    ) async throws -> [Post] {
        switch source {
        case .weibo, .douyin:
            return try await fetchHotTopics(page: page, limit: limit, source: source).map { .hotTopic($0, source: source) }
        case .flash:
            return try await fetchFlash(page: page, limit: limit, category: flashCategory).map(Post.flash)
        case .xueqiu:
            return try await fetchXueqiuPosts(page: page, limit: limit)
        default:
            return try await fetchRegularPosts(page: page, limit: limit, source: source)
        }
    }

    func fetchRSSFeeds() async throws -> [RSSFeedSource] {
        let pageSize = 20
        var feeds: [RSSFeedSource] = []
        for page in 1...10 {
            var parts = URLComponents(url: baseURL.appending(path: "api/v1/rss/feeds"), resolvingAgainstBaseURL: false)
            parts?.queryItems = [
                .init(name: "page", value: String(page)),
                .init(name: "exclude_social", value: "true")
            ]
            guard let url = parts?.url else { throw APIError.invalidURL }
            let response: RSSFeedsResponse = try await get(url)
            feeds += response.data.feeds.filter(\.isEnabled)
            if response.data.feeds.count < pageSize { break }
        }
        var seen = Set<Int>()
        return feeds.filter { seen.insert($0.id).inserted }
    }

    func fetchRSSFeedPosts(feedID: Int, page: Int = 1, limit: Int = 20) async throws -> [Post] {
        var parts = URLComponents(
            url: baseURL.appending(path: "api/v1/rss/feeds/\(feedID)/posts"),
            resolvingAgainstBaseURL: false
        )
        parts?.queryItems = [
            .init(name: "page", value: String(page)),
            .init(name: "limit", value: String(limit)),
            .init(name: "sort", value: "time_desc"),
            .init(name: "include_zero_score", value: "false"),
            .init(name: "final_score", value: String(Post.minimumFeedScore))
        ]
        guard let url = parts?.url else { throw APIError.invalidURL }
        let response: RSSFeedPostsResponse = try await get(url)
        return response.data.posts
    }

    func fetchWeiboFollowingPosts(page: Int, limit: Int = 20) async throws -> [Post] {
        var components = URLComponents(url: baseURL.appending(path: "api/v1/post/list"), resolvingAgainstBaseURL: false)
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

    private func fetchXueqiuPosts(page: Int, limit: Int) async throws -> [Post] {
        try await withThrowingTaskGroup(of: [Post].self) { group in
            for feedID in [14, 16] {
                group.addTask {
                    var parts = URLComponents(
                        url: baseURL.appending(path: "api/v1/rss/feeds/\(feedID)/posts"),
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
        var components = URLComponents(url: baseURL.appending(path: "api/v1/post/list"), resolvingAgainstBaseURL: false)
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
        let includesAllScores = source == .newYorkTimes || source == .youtube
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
        let path = source == .weibo ? "api/v1/weibo/hot/topics" : "api/v1/douyin/hot/topics"
        var parts = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        parts?.queryItems = [.init(name: "page", value: String(page)), .init(name: "size", value: String(limit)), .init(name: "sort", value: "rank")]
        guard let url = parts?.url else { throw APIError.invalidURL }
        let response: HotTopicsResponse = try await get(url)
        guard response.success else { throw APIError.invalidResponse }
        return response.data.topics
    }

    static func flashQueryItems(page: Int, limit: Int, category: String?) -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String((page - 1) * limit)),
            .init(name: "source", value: "all"),
            .init(name: "include_options", value: "0")
        ]
        if let category, !category.isEmpty {
            items.append(.init(name: "category", value: category))
        }
        return items
    }

    private func fetchFlash(page: Int, limit: Int, category: String?) async throws -> [FlashItem] {
        var parts = URLComponents(url: baseURL.appending(path: "api/v1/market/flash/live"), resolvingAgainstBaseURL: false)
        parts?.queryItems = Self.flashQueryItems(page: page, limit: limit, category: category)
        guard let url = parts?.url else { throw APIError.invalidURL }
        let response: FlashResponse = try await get(url)
        guard response.success else { throw APIError.invalidResponse }
        return response.data.items
    }

    private func categoryID(named name: String) async throws -> Int {
        let key = "rss.category.\(name)"
        let cached = UserDefaults.standard.integer(forKey: key)
        if cached > 0 { return cached }
        var parts = URLComponents(url: baseURL.appending(path: "api/v1/categories"), resolvingAgainstBaseURL: false)
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
        let response: PostDetailResponse = try await get(baseURL.appending(path: "api/v1/post/\(id)/raw"))
        return response.post
    }

    func fetchXComments(tweetID: String, limit: Int = 30) async throws -> [XComment] {
        var parts = URLComponents(url: baseURL.appending(path: "api/v1/x/comments"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [
            .init(name: "tweet_id", value: tweetID),
            .init(name: "limit", value: String(limit))
        ]
        guard let url = parts?.url else { throw APIError.invalidURL }
        let response: XCommentsResponse = try await get(url)
        guard response.success else { throw APIError.invalidResponse }
        return response.data.items
    }

    func fetchXTranslation(tweetID: String) async throws -> XTranslation {
        var parts = URLComponents(url: baseURL.appending(path: "api/v1/x/translation"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [
            .init(name: "tweet_id", value: tweetID),
            .init(name: "to", value: "zh")
        ]
        guard let url = parts?.url else { throw APIError.invalidURL }
        let response: XTranslationResponse = try await get(url, retriesTransientFailures: false)
        guard response.success else { throw APIError.invalidResponse }
        return response.data
    }

    func resolveYouTubePlayback(url: URL, title: String) async throws -> VideoPlaybackSource {
        try await resolveVideoPlayback(url: url, title: title, formatID: "18")
    }

    func resolveBilibiliPlayback(url: URL, title: String) async throws -> VideoPlaybackSource {
        try await resolveVideoPlayback(url: url, title: title, formatID: "18")
    }

    private func resolveVideoPlayback(url: URL, title: String, formatID: String) async throws -> VideoPlaybackSource {
        var request = URLRequest(url: baseURL.appending(path: "api/v1/post/video-playback/source"))
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
            return URL(string: "api/v1" + trimmed, relativeTo: baseURL)?.absoluteURL
        }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    func bookmarkXPost(tweetID: String) async throws -> XBookmarkResult {
        let value = tweetID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.allSatisfy(\.isNumber) else { throw APIError.invalidXPostID }
        var request = URLRequest(url: baseURL.appending(path: "api/v1/x/bookmark"))
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
        var parts = URLComponents(url: baseURL.appending(path: "api/v1/post/preview"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [
            .init(name: "url", value: articleURL.absoluteString),
        ]
        return parts?.url
    }

    private func get<Response: Decodable>(
        _ url: URL,
        retriesTransientFailures: Bool = true
    ) async throws -> Response {
        let attempts = retriesTransientFailures ? 2 : 1
        for attempt in 0..<attempts {
            do {
                let (data, response) = try await session.data(from: url)
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

struct NewYorkTimesArticle: Equatable {
    let blocks: [NewYorkTimesArticleBlock]

    static func storedText(_ text: String) -> NewYorkTimesArticle? {
        let normalized = text.replacingOccurrences(
            of: #"(?<=[。！？])\s+"#,
            with: "\n",
            options: .regularExpression
        )
        let sentences = normalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !sentences.isEmpty else { return nil }
        var paragraphs: [NewYorkTimesArticleBlock] = []
        var current = ""
        for sentence in sentences {
            current = current.isEmpty ? sentence : current + " " + sentence
            if current.count >= 180 {
                paragraphs.append(.paragraph(current))
                current = ""
            }
        }
        if !current.isEmpty { paragraphs.append(.paragraph(current)) }
        return NewYorkTimesArticle(blocks: paragraphs)
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
