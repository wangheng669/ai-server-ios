import Foundation

struct LearningCatalog: Decodable, Equatable {
    let source: String
    let fetchedAt: Date
    let sections: [LearningSection]

    enum CodingKeys: String, CodingKey {
        case source, sections
        case fetchedAt = "fetched_at"
    }

    var topicCount: Int { sections.reduce(0) { $0 + $1.topics.count } }
}

struct LearningSection: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let topics: [LearningTopic]
}

struct LearningTopic: Decodable, Identifiable, Hashable {
    let id: String
    let lessonID: String
    let title: String
    let summary: String
    let category: String
    let sourceURLValue: String
    let thumbnailURLValue: String?
    let hasVideo: Bool?
    let detail: LearningDetail?

    enum CodingKeys: String, CodingKey {
        case id, title, summary, category, detail
        case lessonID = "lesson_id"
        case sourceURLValue = "source_url"
        case thumbnailURLValue = "thumbnail_url"
        case hasVideo = "has_video"
    }

    var url: URL { URL(string: sourceURLValue) ?? LearningService.sourceURL }

    func mediaURL(_ value: String?, baseURL: URL = ServerConfiguration.currentURL) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if let absolute = URL(string: value), absolute.scheme != nil { return absolute }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }
}

struct LearningDetail: Decodable, Hashable {
    let title: String
    let subtitle: String
    let views: Int
    let viewsText: String
    let updatedAt: String
    let videoURLValue: String?
    let videoPosterURLValue: String?
    let videoDuration: Int?
    let blocks: [LearningBlock]

    enum CodingKeys: String, CodingKey {
        case title, subtitle, views, blocks
        case viewsText = "views_text"
        case updatedAt = "updated_at"
        case videoURLValue = "video_url"
        case videoPosterURLValue = "video_poster_url"
        case videoDuration = "video_duration_seconds"
    }
}

struct LearningBlock: Decodable, Hashable, Identifiable {
    let type: String
    let text: String?
    let level: Int?
    let items: [String]?
    let imageURLValue: String?
    let alt: String?

    enum CodingKeys: String, CodingKey {
        case type, text, level, items, alt
        case imageURLValue = "image_url"
    }

    var id: String {
        [type, text ?? "", imageURLValue ?? "", items?.joined(separator: "|") ?? ""]
            .joined(separator: ":")
    }
}

struct LearningCatalogResponse: Decodable { let data: LearningCatalog }
struct LearningTopicResponse: Decodable { let data: LearningTopic }

struct LearningBookshelf: Decodable, Equatable {
    let source: String
    let books: [KnowledgeBook]
}

struct LearningBookshelfResponse: Decodable {
    let data: LearningBookshelf
}

struct KnowledgeBook: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let author: String
    let coverURLValue: String?
    let category: String?
    let openURLValue: String
    let isFinished: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, author, category
        case coverURLValue = "cover_url"
        case openURLValue = "open_url"
        case isFinished = "is_finished"
    }

    var coverURL: URL? {
        guard let coverURLValue else { return nil }
        return URL(string: coverURLValue)
    }

    var openURL: URL? { URL(string: openURLValue) }
}
