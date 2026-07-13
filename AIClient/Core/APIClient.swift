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
            .init(name: "final_score", value: String(Post.minimumFeedScore)), .init(name: "sort", value: "time_desc"),
            .init(name: "group_similar", value: "1"), .init(name: "group_threshold", value: "70"),
            .init(name: "source", value: isSpecialRSS ? "rss" : source.rawValue), .init(name: "include_zero_score", value: "false")
        ]
        if isSpecialRSS {
            let name = source == .laozhong ? "老中" : "YouTube"
            components?.queryItems?.append(.init(name: "categoryId", value: String(try await categoryID(named: name))))
        }
        if source == .x { components?.queryItems?.append(.init(name: "x_feed_view", value: "tracked")) }
        guard let url = components?.url else { throw APIError.invalidURL }
        let response: PostListResponse = try await get(url)
        return response.data.filter(\.meetsMinimumFeedScore)
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

private struct HealthResponse: Decodable { let status: String }
enum APIError: LocalizedError {
    case invalidURL, invalidResponse, httpStatus(Int), decoding(Error), missingCategory(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: "服务器地址无效"
        case .invalidResponse: "服务器响应无效"
        case .httpStatus(let code): "服务器返回错误（\(code)）"
        case .decoding: "新闻数据格式暂时无法识别"
        case .missingCategory(let name): "找不到 \(name) 数据分类"
        }
    }
}
