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

    func articles(personID: String) async throws -> [PersonArticle] {
        let url = baseURL
            .appending(path: "api/v1/people")
            .appending(path: personID)
            .appending(path: "articles")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PeopleServiceError.invalidResponse
        }
        let payload = try JSONDecoder().decode(PeopleArticlesResponse.self, from: data)
        guard payload.success else { throw PeopleServiceError.invalidResponse }
        return payload.articles
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
