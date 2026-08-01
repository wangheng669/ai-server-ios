import Foundation

struct PeopleService {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = ServerConfiguration.currentURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.session = session ?? .shared
    }

    func specialPeople() async throws -> SpecialPeopleResponse {
        let url = baseURL.appending(path: "api/v1/people/directory")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PeopleServiceError.invalidResponse
        }
        let payload = try JSONDecoder().decode(SpecialPeopleResponse.self, from: data)
        guard payload.success else { throw PeopleServiceError.invalidResponse }
        return payload
    }

    func searchXPeople(query: String, limit: Int = 8) async throws -> [XPersonSearchResult] {
        let endpoint = baseURL.appending(path: "api/v1/people/x/search")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "query", value: query),
            .init(name: "limit", value: String(limit))
        ]
        guard let url = components?.url else { throw PeopleServiceError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PeopleServiceError.invalidResponse
        }
        let payload = try JSONDecoder().decode(XPeopleSearchResponse.self, from: data)
        guard payload.success else { throw PeopleServiceError.invalidResponse }
        return payload.results
    }

    func importXPerson(screenName: String) async throws -> XPersonImportResponse {
        let url = baseURL.appending(path: "api/v1/people/x/import")
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["screen_name": screenName])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PeopleServiceError.invalidResponse
        }
        let payload = try JSONDecoder().decode(XPersonImportResponse.self, from: data)
        guard payload.success else { throw PeopleServiceError.invalidResponse }
        return payload
    }

    func searchWikipediaPeople(query: String, limit: Int = 8) async throws -> [WikipediaPersonSearchResult] {
        let endpoint = baseURL.appending(path: "api/v1/people/wikipedia/search")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "query", value: query),
            .init(name: "limit", value: String(limit))
        ]
        guard let url = components?.url else { throw PeopleServiceError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PeopleServiceError.invalidResponse
        }
        let payload = try JSONDecoder().decode(WikipediaPeopleSearchResponse.self, from: data)
        guard payload.success else { throw PeopleServiceError.invalidResponse }
        return payload.results
    }

    func importWikipediaPerson(_ result: WikipediaPersonSearchResult) async throws -> WikipediaPersonImportResponse {
        let url = baseURL.appending(path: "api/v1/people/wikipedia/import")
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "language": result.language,
            "title": result.title,
            "wikidata_id": result.id
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PeopleServiceError.invalidResponse
        }
        let payload = try JSONDecoder().decode(WikipediaPersonImportResponse.self, from: data)
        guard payload.success else { throw PeopleServiceError.invalidResponse }
        return payload
    }

    func latestPost(userID: String) async throws -> Post? {
        try await posts(userID: userID, limit: 1).first
    }

    func posts(userID: String, page: Int = 1, limit: Int = 12) async throws -> [Post] {
        let endpoint = baseURL
            .appending(path: "api/v1/post/user")
            .appending(path: userID)
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "page", value: String(page)),
            .init(name: "limit", value: String(limit)),
            .init(name: "sort", value: "time_desc")
        ]
        guard let url = components?.url else { throw PeopleServiceError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PeopleServiceError.invalidResponse
        }
        return try JSONDecoder().decode(PostListResponse.self, from: data).data
    }

    func relatedDiscussions(for person: SpecialPerson, limit: Int = 12) async throws -> [Post] {
        var components = URLComponents(url: baseURL.appending(path: "api/v1/people/discussions"), resolvingAgainstBaseURL: false)
        var queryItems = person.discussionKeywords.map { URLQueryItem(name: "alias", value: $0) }
        queryItems.append(.init(name: "limit", value: String(limit)))
        if let handle = person.handle?.dropFirst() {
            queryItems.append(.init(name: "exclude_handle", value: String(handle)))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw PeopleServiceError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PeopleServiceError.invalidResponse
        }
        return try JSONDecoder().decode(PostListResponse.self, from: data).data
    }

    func relatedVideos(personID: String) async throws -> [PersonVideo] {
        let url = baseURL
            .appending(path: "api/v1/people")
            .appending(path: personID)
            .appending(path: "videos")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PeopleServiceError.invalidResponse
        }
        let payload = try JSONDecoder().decode(PeopleVideosResponse.self, from: data)
        guard payload.success else { throw PeopleServiceError.invalidResponse }
        return payload.videos
    }

    func articles(personID: String, query: String? = nil) async throws -> [PersonArticle] {
        let endpoint = baseURL
            .appending(path: "api/v1/people")
            .appending(path: personID)
            .appending(path: "articles")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        if let query, !query.isEmpty {
            components?.queryItems = [.init(name: "q", value: query)]
        }
        guard let url = components?.url else { throw PeopleServiceError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PeopleServiceError.invalidResponse
        }
        let payload = try JSONDecoder().decode(PeopleArticlesResponse.self, from: data)
        guard payload.success else { throw PeopleServiceError.invalidResponse }
        if let query, !query.isEmpty, payload.queryApplied != true {
            throw PeopleServiceError.invalidResponse
        }
        return payload.articles
    }

    func article(id: Int64) async throws -> PersonArticle {
        let url = baseURL
            .appending(path: "api/v1/people/articles")
            .appending(path: String(id))
        var request = URLRequest(url: url, timeoutInterval: 180)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PeopleServiceError.invalidResponse
        }
        let payload = try JSONDecoder().decode(PersonArticleDetailResponse.self, from: data)
        guard payload.success else { throw PeopleServiceError.invalidResponse }
        return payload.article
    }

    func subtitles(videoID: Int64) async throws -> PersonVideoSubtitlesResponse {
        let url = baseURL
            .appending(path: "api/v1/people/videos")
            .appending(path: String(videoID))
            .appending(path: "subtitles")
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PeopleServiceError.invalidResponse
        }
        let payload = try JSONDecoder().decode(PersonVideoSubtitlesResponse.self, from: data)
        guard payload.success else { throw PeopleServiceError.invalidResponse }
        return payload
    }

    func latestPosts(for people: [SpecialPerson]) async -> [String: Post] {
        await withTaskGroup(of: (String, Post?).self, returning: [String: Post].self) { group in
            for person in people {
                group.addTask {
                    let post = try? await latestPost(userID: person.userID)
                    return (person.id, post)
                }
            }

            var posts: [String: Post] = [:]
            for await (personID, post) in group {
                if let post { posts[personID] = post }
            }
            return posts
        }
    }
}

actor PersonArticleTranslationService {
    static let shared = PersonArticleTranslationService()

    private let endpoint = URL(string: "https://translate.googleapis.com/translate_a/single")!
    private let session: URLSession
    private var memoryCache: [String: String] = [:]
    private var nextRequestAt = Date.distantPast

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translate(_ text: String) async throws -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "" }
        if source.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains(Int($0.value)) }) {
            return source
        }
        if let cached = memoryCache[source] { return cached }

        let chunks = Self.chunks(from: source, maximumCharacters: 1_800)
        var translatedChunks: [String] = []
        for chunk in chunks {
            guard !Task.isCancelled else { throw CancellationError() }
            await reserveRequestSlot()
            translatedChunks.append(try await translateChunk(chunk))
        }
        let translated = Self.preserveProductNames(
            in: translatedChunks.joined(separator: "\n"),
            original: source
        )
        memoryCache[source] = translated
        return translated
    }

    private func reserveRequestSlot() async {
        let now = Date()
        let scheduled = max(now, nextRequestAt)
        nextRequestAt = scheduled.addingTimeInterval(0.4)
        let delay = scheduled.timeIntervalSince(now)
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func translateChunk(_ text: String) async throws -> String {
        for attempt in 0..<3 {
            var request = URLRequest(url: endpoint, timeoutInterval: 30)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            var form = URLComponents()
            form.queryItems = [
                .init(name: "client", value: "gtx"),
                .init(name: "sl", value: "auto"),
                .init(name: "tl", value: "zh-CN"),
                .init(name: "dt", value: "t"),
                .init(name: "q", value: text)
            ]
            request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PeopleServiceError.invalidResponse
            }
            if http.statusCode == 429 || (500..<600).contains(http.statusCode) {
                guard attempt < 2 else { throw PeopleServiceError.invalidResponse }
                try await Task.sleep(for: .milliseconds(700 * (attempt + 1)))
                continue
            }
            guard (200..<300).contains(http.statusCode) else {
                throw PeopleServiceError.invalidResponse
            }
            guard let payload = try JSONSerialization.jsonObject(with: data) as? [Any],
                  let segments = payload.first as? [Any] else {
                throw PeopleServiceError.invalidResponse
            }
            let translated = segments.compactMap { segment -> String? in
                guard let values = segment as? [Any], let value = values.first as? String else { return nil }
                return value
            }.joined()
            guard !translated.isEmpty else { throw PeopleServiceError.invalidResponse }
            return translated
        }
        throw PeopleServiceError.invalidResponse
    }

    nonisolated static func chunks(from text: String, maximumCharacters: Int) -> [String] {
        guard text.count > maximumCharacters else { return [text] }
        var chunks: [String] = []
        var current = ""
        let paragraphs = text.components(separatedBy: "\n")
        for paragraph in paragraphs {
            if current.count + paragraph.count + 1 <= maximumCharacters {
                current += current.isEmpty ? paragraph : "\n" + paragraph
                continue
            }
            if !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            var remainder = paragraph
            while remainder.count > maximumCharacters {
                let split = remainder.index(remainder.startIndex, offsetBy: maximumCharacters)
                chunks.append(String(remainder[..<split]))
                remainder = String(remainder[split...])
            }
            current = remainder
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    nonisolated static func preserveProductNames(in translation: String, original: String) -> String {
        var result = translation
        let protectedTerms: [(term: String, mistranslations: [String])] = [
            ("OpenAI", ["开放人工智能", "开放AI"]),
            ("ChatGPT", ["聊天GPT"]),
            ("Sora", ["索拉", "姐姐"]),
            ("GPT", ["生成式预训练变换器"])
        ]
        for item in protectedTerms where original.localizedCaseInsensitiveContains(item.term) {
            for mistranslation in item.mistranslations {
                result = result.replacingOccurrences(of: mistranslation, with: item.term)
            }
        }
        return result
    }
}

enum PeopleServiceError: LocalizedError {
    case invalidURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: "人物服务地址无效"
        case .invalidResponse: "人物服务暂不可用"
        }
    }
}
