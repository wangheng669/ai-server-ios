import Foundation
import Observation

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
    let companyExamples: [LearningCompanyExample]?
    let videoReferences: [LearningVideoReference]?

    enum CodingKeys: String, CodingKey {
        case title, subtitle, views, blocks
        case viewsText = "views_text"
        case updatedAt = "updated_at"
        case videoURLValue = "video_url"
        case videoPosterURLValue = "video_poster_url"
        case videoDuration = "video_duration_seconds"
        case companyExamples = "company_examples"
        case videoReferences = "video_references"
    }
}

struct LearningVideoReference: Decodable, Hashable, Identifiable {
    let id: Int
    let platform: String
    let creator: String
    let title: String
    let externalID: String?
    let watchURLValue: String
    let coverURLValue: String?
    let durationSeconds: Int?
    let startSeconds: Int?
    let endSeconds: Int?
    let recommendation: String?

    enum CodingKeys: String, CodingKey {
        case id, platform, creator, title, recommendation
        case externalID = "external_id"
        case watchURLValue = "watch_url"
        case coverURLValue = "cover_url"
        case durationSeconds = "duration_seconds"
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
    }

    var watchURL: URL? {
        guard var components = URLComponents(string: watchURLValue) else { return nil }
        if let startSeconds, startSeconds > 0 {
            var items = components.queryItems ?? []
            items.removeAll { $0.name == "t" }
            items.append(URLQueryItem(name: "t", value: String(startSeconds)))
            components.queryItems = items
        }
        return components.url
    }

    var coverURL: URL? {
        guard let coverURLValue else { return nil }
        return URL(string: coverURLValue)
    }

    var clipDurationText: String {
        let seconds: Int
        if let startSeconds, let endSeconds, endSeconds > startSeconds {
            seconds = endSeconds - startSeconds
        } else {
            seconds = durationSeconds ?? 0
        }
        guard seconds > 0 else { return "精选讲解" }
        return "\(max(1, Int(ceil(Double(seconds) / 60)))) 分钟"
    }

    var recommendationItems: [String] {
        recommendation?
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty } ?? []
    }
}

struct LearningCompanyExample: Decodable, Hashable, Identifiable {
    let company: String
    let ticker: String?
    let situation: String
    let connection: String
    let caution: String

    var id: String { "\(company)-\(ticker ?? "")-\(situation)" }
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

struct LearningVideoLibrary: Decodable, Equatable {
    let lessons: [LearningVideoLesson]
}

struct LearningVideoLibraryResponse: Decodable {
    let data: LearningVideoLibrary
}

struct LearningVideoLessonResponse: Decodable {
    let data: LearningVideoLesson
}

struct LearningVideoLesson: Decodable, Identifiable, Hashable {
    let id: String
    let platform: String
    let creator: String
    let title: String
    let summary: String
    let externalID: String?
    let watchURLValue: String
    let coverURLValue: String?
    let durationSeconds: Int?
    let description: String
    let watchPoints: [String]
    let chapters: [LearningVideoChapter]
    let relatedTopics: [LearningVideoRelatedTopic]

    enum CodingKeys: String, CodingKey {
        case id, platform, creator, title, summary, description, chapters
        case externalID = "external_id"
        case watchURLValue = "watch_url"
        case coverURLValue = "cover_url"
        case durationSeconds = "duration_seconds"
        case watchPoints = "watch_points"
        case relatedTopics = "related_topics"
    }

    var coverURL: URL? {
        guard let coverURLValue else { return nil }
        return URL(string: coverURLValue)
    }

    var durationText: String {
        guard let durationSeconds, durationSeconds > 0 else { return "视频课" }
        return "\(max(1, Int(ceil(Double(durationSeconds) / 60)))) 分钟"
    }

    func watchURL(at seconds: Int = 0) -> URL? {
        guard var components = URLComponents(string: watchURLValue) else { return nil }
        if seconds > 0 {
            var items = components.queryItems ?? []
            items.removeAll { $0.name == "t" }
            items.append(URLQueryItem(name: "t", value: String(seconds)))
            components.queryItems = items
        }
        return components.url
    }
}

struct LearningVideoChapter: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let startSeconds: Int
    let endSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case id, title
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
    }

    var timestampText: String {
        String(format: "%d:%02d", startSeconds / 60, startSeconds % 60)
    }
}

struct LearningVideoRelatedTopic: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let category: String
}

@MainActor
@Observable
final class LearningProgressStore {
    private(set) var completedAt: [String: Date]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "learning.completedTopics.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        if let stored = defaults.dictionary(forKey: storageKey) as? [String: TimeInterval] {
            completedAt = stored.mapValues(Date.init(timeIntervalSince1970:))
        } else {
            completedAt = [:]
        }
    }

    func isCompleted(_ topicID: String) -> Bool {
        completedAt[topicID] != nil
    }

    func completedCount(in topics: [LearningTopic]) -> Int {
        topics.reduce(into: 0) { count, topic in
            if isCompleted(topic.id) { count += 1 }
        }
    }

    func markCompleted(_ topicID: String, at date: Date = .now) {
        completedAt[topicID] = date
        persist()
    }

    func studyDays(inWeekContaining date: Date = .now, calendar: Calendar = .current) -> Set<Int> {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return Set(
            completedAt.values.compactMap { completedDate in
                guard interval.contains(completedDate) else { return nil }
                let weekday = calendar.component(.weekday, from: completedDate)
                return (weekday + 5) % 7
            }
        )
    }

    private func persist() {
        defaults.set(
            completedAt.mapValues(\.timeIntervalSince1970),
            forKey: storageKey
        )
    }
}

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
