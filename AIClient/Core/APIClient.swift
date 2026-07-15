import Foundation

struct APIClient {
    let baseURL: URL
    private let session: URLSession
    init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session { self.session = session } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.urlCache = .shared
            self.session = URLSession(configuration: config)
        }
    }

    func checkHealth() async throws { let _: HealthResponse = try await get(baseURL.appending(path: "health")) }

    func fetchPosts(page: Int, limit: Int = 20, source: FeedSource) async throws -> [Post] {
        switch source {
        case .weibo, .douyin:
            return try await fetchHotTopics(page: page, limit: limit, source: source).map { .hotTopic($0, source: source) }
        case .flash:
            return try await fetchFlash(page: page, limit: limit).map(Post.flash)
        default:
            return try await fetchRegularPosts(page: page, limit: limit, source: source)
        }
    }

    private func fetchRegularPosts(page: Int, limit: Int, source: FeedSource) async throws -> [Post] {
        var components = URLComponents(url: baseURL.appending(path: "api/v1/post/list"), resolvingAgainstBaseURL: false)
        let isSpecialRSS = source == .laozhong || source == .youtube
        components?.queryItems = [
            .init(name: "page", value: String(page)), .init(name: "limit", value: String(limit)),
            .init(name: "sort", value: "time_desc"),
            .init(name: "group_similar", value: "1"), .init(name: "group_threshold", value: "70"),
            .init(name: "source", value: isSpecialRSS ? "rss" : source.rawValue),
            .init(name: "include_zero_score", value: source == .newYorkTimes ? "true" : "false")
        ]
        if source != .newYorkTimes {
            components?.queryItems?.append(.init(name: "final_score", value: String(Post.minimumFeedScore)))
        }
        if isSpecialRSS {
            let name = source == .laozhong ? "老中" : "YouTube"
            components?.queryItems?.append(.init(name: "categoryId", value: String(try await categoryID(named: name))))
        }
        if source == .x { components?.queryItems?.append(.init(name: "x_feed_view", value: "tracked")) }
        guard let url = components?.url else { throw APIError.invalidURL }
        let response: PostListResponse = try await get(url)
        return response.data
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

    private func fetchFlash(page: Int, limit: Int) async throws -> [FlashItem] {
        var parts = URLComponents(url: baseURL.appending(path: "api/v1/market/flash/live"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [
            .init(name: "limit", value: String(limit)), .init(name: "offset", value: String((page - 1) * limit)),
            .init(name: "source", value: "all"), .init(name: "include_options", value: "0")
        ]
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
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        guard let html = String(data: data, encoding: .utf8),
              let article = NewYorkTimesArticleParser.extract(from: html) else {
            throw APIError.decoding(NYTimesArticleError.bodyMissing)
        }
        return article
    }

    private func get<Response: Decodable>(_ url: URL) async throws -> Response {
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                if [500, 502, 503, 504].contains(http.statusCode), attempt < 2 {
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
            } catch let error as URLError where error.code != .cancelled && attempt < 2 {
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
               let url = URL(string: decoded) {
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

private struct HealthResponse: Decodable { let status: String }
private struct XBookmarkRequest: Encodable {
    let articleID: String
    enum CodingKeys: String, CodingKey { case articleID = "article_id" }
}
private struct XBookmarkResponse: Decodable { let success: Bool; let data: XBookmarkResult }
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
