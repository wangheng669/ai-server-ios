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
    var stockTopics: [LearningTopic] { sections.first { $0.name == "股票" }?.topics ?? [] }
}

struct LearningSection: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let topics: [LearningTopic]
}

struct LearningMilestone: Identifiable {
    let title: String
    let topic: LearningTopic

    var id: String { "\(title)-\(topic.id)" }

    static func plan(from topics: [LearningTopic]) -> [LearningMilestone] {
        let definitions: [(String, [String])] = [
            ("基础概念", ["净收入", "净资产"]),
            ("读懂财报", ["资产负债", "现金流", "财报"]),
            ("估值方法", ["市盈率", "估值"]),
            ("风险管理", ["风险", "安全边际"])
        ]

        var usedIDs = Set<String>()
        return definitions.compactMap { title, keywords in
            guard let topic = topics.first(where: { topic in
                !usedIDs.contains(topic.id) && keywords.contains(where: topic.title.contains)
            }) else { return nil }
            usedIDs.insert(topic.id)
            return LearningMilestone(title: title, topic: topic)
        }
    }
}

struct LearningLessonPosition: Hashable {
    let title: String
    let number: Int
    let count: Int

    var progress: CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(min(max(number, 0), count)) / CGFloat(count)
    }

    var text: String {
        let position = "第 \(number)/\(count) 节"
        return title.isEmpty ? position : "\(position) · \(title)"
    }
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
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    func imageURL(_ value: String?, baseURL: URL = ServerConfiguration.currentURL) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if let absolute = URL(string: value), absolute.scheme != nil {
            return MediaURL.image(absolute.absoluteString) ?? absolute
        }
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

    /// Only identical cases are duplicates; distinct explanations for a company remain visible.
    var uniqueCompanyExamples: [LearningCompanyExample] {
        var seen = Set<LearningCompanyExample>()
        return (companyExamples ?? []).filter { seen.insert($0).inserted }
    }

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
        return MediaURL.image(coverURLValue) ?? URL(string: coverURLValue)
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

    var id: Self { self }
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


struct LearningVideoLibrary: Decodable, Equatable {
    let lessons: [LearningVideoLesson]
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
        return MediaURL.image(coverURLValue) ?? URL(string: coverURLValue)
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
    let todayReadingSeconds: Int64?
    let yesterdayReadingSeconds: Int64?
    let books: [KnowledgeBook]

    enum CodingKeys: String, CodingKey {
        case source, books
        case todayReadingSeconds = "today_reading_seconds"
        case yesterdayReadingSeconds = "yesterday_reading_seconds"
    }

    var todayReadingText: String {
        Self.durationText(seconds: todayReadingSeconds ?? 0, empty: "今天还没开始")
    }

    var yesterdayReadingText: String {
        Self.durationText(seconds: yesterdayReadingSeconds ?? 0, empty: "昨日未阅读")
    }

    private static func durationText(seconds: Int64, empty: String) -> String {
        guard seconds >= 60 else { return empty }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) 小时" : "\(hours) 小时 \(remainder) 分钟"
    }
}

struct KnowledgeBook: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let author: String
    let coverURLValue: String?
    let category: String?
    let openURLValue: String
    let isFinished: Bool
    let readingProgress: Int?
    let recordReadingSeconds: Int64?
    let estimatedRemainingSeconds: Int64?
    let readUpdateTime: Int64?

    enum CodingKeys: String, CodingKey {
        case id, title, author, category
        case coverURLValue = "cover_url"
        case openURLValue = "open_url"
        case isFinished = "is_finished"
        case readingProgress = "reading_progress"
        case recordReadingSeconds = "record_reading_seconds"
        case estimatedRemainingSeconds = "estimated_remaining_seconds"
        case readUpdateTime = "read_update_time"
    }

    var coverURL: URL? {
        guard let coverURLValue else { return nil }
        return MediaURL.image(coverURLValue) ?? URL(string: coverURLValue)
    }

    var openURL: URL? { URL(string: openURLValue) }

    var displayReadingProgress: Int? {
        if isFinished { return 100 }
        guard let readingProgress else { return nil }
        return min(max(readingProgress, 0), 100)
    }

    var readingDurationText: String? {
        guard let seconds = recordReadingSeconds, seconds >= 60 else { return nil }
        let minutes = seconds / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return remainingMinutes == 0 ? "累计阅读 \(hours) 小时" : "累计阅读 \(hours) 小时 \(remainingMinutes) 分钟"
        }
        return "累计阅读 \(minutes) 分钟"
    }

    var estimatedRemainingText: String? {
        guard !isFinished,
              let seconds = estimatedRemainingSeconds,
              seconds >= 60 else { return isFinished ? "已读完" : nil }
        let minutes = seconds / 60
        if minutes < 60 { return "预计还需 \(minutes) 分钟" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0
            ? "预计还需 \(hours) 小时"
            : "预计还需 \(hours) 小时 \(remainder) 分钟"
    }

    var lastReadText: String? {
        guard let timestamp = readUpdateTime, timestamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天读过" }
        if calendar.isDateInYesterday(date) { return "昨天读过" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日读过"
        return formatter.string(from: date)
    }
}

struct KnowledgeConceptLibrary: Decodable, Equatable {
    let concepts: [KnowledgeConceptCard]
}

enum KnowledgeConceptKind: String, Decodable, Hashable {
    case event
    case person
    case concept

    var title: String {
        switch self {
        case .event: "事件"
        case .person: "人物"
        case .concept: "概念"
        }
    }
}

struct KnowledgeConceptCard: Identifiable, Decodable, Hashable {
    let id: String
    let kind: KnowledgeConceptKind
    let title: String
    let subtitle: String
    let summary: String
    let importance: String
    let coverURLValue: String?
    let imageAttribution: String
    let wikipediaLanguage: String
    let wikipediaTitle: String
    let wikipediaURLValue: String
    let keyPeople: [String]

    enum CodingKeys: String, CodingKey {
        case id, kind, title, subtitle, summary, importance
        case coverURLValue = "cover_url"
        case imageAttribution = "image_attribution"
        case wikipediaLanguage = "wikipedia_language"
        case wikipediaTitle = "wikipedia_title"
        case wikipediaURLValue = "wikipedia_url"
        case keyPeople = "key_people"
    }

    var coverURL: URL? {
        KnowledgeConceptImageURL.optimized(coverURLValue)
    }

    var wikipediaURL: URL? { URL(string: wikipediaURLValue) }
}

enum KnowledgeConceptImageURL {
    private static let thumbnailWidth = "960"
    private static let commonsPathPrefix = "/wikipedia/commons/"

    static func optimized(_ rawValue: String?) -> URL? {
        guard let rawValue, let url = URL(string: rawValue) else { return nil }
        guard let host = url.host?.lowercased() else { return url }

        let optimizedURL: URL

        if host == "upload.wikimedia.org",
           url.path.hasPrefix(commonsPathPrefix),
           !url.path.hasPrefix("\(commonsPathPrefix)thumb/"),
           isRasterImage(url) {
            let relativePath = String(url.path.dropFirst(commonsPathPrefix.count))
            let filename = url.lastPathComponent
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.path = "\(commonsPathPrefix)thumb/\(relativePath)/\(thumbnailWidth)px-\(filename)"
            components?.query = nil
            optimizedURL = components?.url ?? url
        } else if host == "commons.wikimedia.org",
           url.path.hasPrefix("/wiki/Special:Redirect/file/") {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var queryItems = components?.queryItems?.filter { $0.name != "width" } ?? []
            queryItems.append(URLQueryItem(name: "width", value: thumbnailWidth))
            components?.queryItems = queryItems
            optimizedURL = components?.url ?? url
        } else {
            optimizedURL = url
        }
        return MediaURL.image(optimizedURL.absoluteString) ?? optimizedURL
    }

    private static func isRasterImage(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "webp"].contains(url.pathExtension.lowercased())
    }
}
