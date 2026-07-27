import Foundation

struct SpecialPeopleResponse: Decodable {
    let success: Bool
    let categories: [PeopleCategory]?
    let users: [SpecialPerson]
}

struct PeopleCategory: Decodable, Identifiable {
    let id: String
    let title: String
    let sortOrder: Int

    var topic: PeopleTopic? { PeopleTopic(apiValue: id) }

    enum CodingKeys: String, CodingKey {
        case id, title
        case sortOrder = "sort_order"
    }
}

struct SpecialPerson: Decodable, Identifiable, Hashable {
    let userID: String
    let userName: String?
    let userScreenName: String?
    let userDescription: String?
    let avatarPath: String?
    let todayCount: Int
    let totalCount: Int
    let lastPostTime: String?
    private let topicValue: String?
    private let organizationNameValue: String?
    private let avatarAssetNameValue: String?
    private let discussionKeywordsValue: [String]?
    private let hasOwnPostSourceValue: Bool?
    private let focusTagsValue: [String]?
    private let rolesValue: [PersonRole]?
    private let milestonesValue: [PersonMilestone]?
    private let relatedPeopleValue: [RelatedPerson]?
    private let profileUpdatedAtValue: String?

    var id: String { userID }
    var isCurated: Bool { userID.hasPrefix("curated:") }
    var isIndustryPerson: Bool { topic == .technology }
    var hasOwnPostSource: Bool { hasOwnPostSourceValue ?? !isCurated }
    var hasXSource: Bool { hasOwnPostSource && userID.allSatisfy(\.isNumber) }
    var isOrganizationAccount: Bool { false }
    var name: String { nonempty(userName) ?? nonempty(userScreenName) ?? "未知用户" }
    var handle: String? { nonempty(userScreenName).map { $0.hasPrefix("@") ? $0 : "@\($0)" } }
    var secondaryLabel: String? { isCurated ? nonempty(userScreenName) : handle }
    var organizationName: String? {
        nonempty(organizationNameValue) ?? (isCurated ? nonempty(userScreenName) : nil)
    }
    var avatarAssetName: String? { nonempty(avatarAssetNameValue) }
    var discussionKeywords: [String] {
        guard let keywords = discussionKeywordsValue?.filter({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }), !keywords.isEmpty else {
            return [name]
        }
        return keywords
    }
    var focusTags: [String] {
        let tags = focusTagsValue?.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
        return tags.isEmpty ? Array(discussionKeywords.prefix(4)) : Array(tags.prefix(4))
    }
    var roles: [PersonRole] {
        if let rolesValue, !rolesValue.isEmpty { return rolesValue }
        return [PersonRole(organization: organizationName ?? topic.rawValue, title: secondaryLabel ?? "人物")]
    }
    var milestones: [PersonMilestone] { milestonesValue ?? [] }
    var relatedPeople: [RelatedPerson] { relatedPeopleValue ?? [] }
    var profileUpdatedAt: String? { nonempty(profileUpdatedAtValue) }
    var summary: String {
        if let description = nonempty(userDescription),
           !description.contains("127.0.0.1"), !description.contains("localhost") {
            return description
        }
        return todayCount > 0 ? "今天有 \(todayCount) 条新动态" : "暂无个人简介"
    }
    var topic: PeopleTopic {
        topicValue.flatMap(PeopleTopic.init(apiValue:)) ?? .technology
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case userName = "user_name"
        case userScreenName = "user_screen_name"
        case userDescription = "user_desc"
        case avatarPath = "avatar_url"
        case todayCount = "today_count"
        case totalCount = "total_count"
        case lastPostTime = "last_post_time"
        case topicValue = "topic"
        case organizationNameValue = "organization_name"
        case avatarAssetNameValue = "avatar_asset_name"
        case discussionKeywordsValue = "discussion_keywords"
        case hasOwnPostSourceValue = "has_own_post_source"
        case focusTagsValue = "focus_tags"
        case rolesValue = "roles"
        case milestonesValue = "milestones"
        case relatedPeopleValue = "related_people"
        case profileUpdatedAtValue = "profile_updated_at"
    }

    init(
        id: String,
        name: String,
        organization: String,
        summary: String,
        avatarURL: String? = nil,
        xUserID: String? = nil,
        xScreenName: String? = nil
    ) {
        userID = xUserID ?? "curated:\(id)"
        userName = name
        userScreenName = xScreenName
        userDescription = summary
        avatarPath = avatarURL
        todayCount = 0
        totalCount = 0
        lastPostTime = nil
        topicValue = nil
        organizationNameValue = organization
        avatarAssetNameValue = nil
        discussionKeywordsValue = [name]
        hasOwnPostSourceValue = xUserID != nil
        focusTagsValue = nil
        rolesValue = nil
        milestonesValue = nil
        relatedPeopleValue = nil
        profileUpdatedAtValue = nil
    }

    func avatarURL(baseURL: URL) -> URL? {
        guard let path = nonempty(avatarPath) else { return nil }
        if let url = URL(string: path), url.scheme != nil {
            let upgraded = path
                .replacingOccurrences(of: "_normal.", with: "_200x200.")
                .replacingOccurrences(of: "_40_normal.", with: "_200x200.")
            return MediaURL.image(upgraded) ?? url
        }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    var relativeTime: String {
        guard let value = nonempty(lastPostTime), let date = Self.dateFormatter.date(from: value) else {
            return "暂无更新"
        }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "刚刚" }
        if seconds < 3_600 { return "\(seconds / 60) 分钟前" }
        if seconds < 86_400 { return "\(seconds / 3_600) 小时前" }
        if seconds < 604_800 { return "\(seconds / 86_400) 天前" }
        return date.formatted(.dateTime.month().day())
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter
    }()
}

struct PersonRole: Decodable, Hashable {
    let organization: String
    let title: String
}

struct PersonMilestone: Decodable, Hashable {
    let year: String
    let title: String
}

struct PeopleVideosResponse: Decodable {
    let success: Bool
    let personID: String
    let videos: [PersonVideo]

    enum CodingKeys: String, CodingKey {
        case success, videos
        case personID = "person_id"
    }
}

struct PersonVideo: Decodable, Identifiable, Hashable {
    let id: Int64
    let personID: String
    let platform: String
    let platformVideoID: String
    let title: String
    let titleZH: String
    let description: String?
    let channelName: String
    let publishedAt: String?
    let durationSeconds: Int
    let coverURLValue: String
    let canonicalURLValue: String
    let relevanceScore: Double
    let videoType: String
    let isFeatured: Bool

    enum CodingKeys: String, CodingKey {
        case id, platform, title, description
        case titleZH = "title_zh"
        case personID = "person_id"
        case platformVideoID = "platform_video_id"
        case channelName = "channel_name"
        case publishedAt = "published_at"
        case durationSeconds = "duration_seconds"
        case coverURLValue = "cover_url"
        case canonicalURLValue = "canonical_url"
        case relevanceScore = "relevance_score"
        case videoType = "video_type"
        case isFeatured = "is_featured"
    }

    var coverURL: URL? { MediaURL.image(coverURLValue) ?? URL(string: coverURLValue) }
    var canonicalURL: URL? { URL(string: canonicalURLValue) }
    var displayTitle: String {
        nonempty(titleZH) ?? title
    }
    var publishedDateLabel: String? {
        guard let publishedAt,
              let date = ISO8601DateFormatter().date(from: publishedAt) else { return nil }
        return date.formatted(
            .dateTime
                .year()
                .month()
                .day()
                .locale(Locale(identifier: "zh_CN"))
        )
    }
    var durationLabel: String {
        guard durationSeconds > 0 else { return "" }
        let hours = durationSeconds / 3_600
        let minutes = (durationSeconds % 3_600) / 60
        let seconds = durationSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

struct PersonVideoSubtitlesResponse: Decodable {
    let success: Bool
    let videoID: Int64
    let language: String
    let status: String
    let cues: [PersonVideoSubtitleCue]

    enum CodingKeys: String, CodingKey {
        case success, language, status, cues
        case videoID = "video_id"
    }
}

struct PersonVideoSubtitleCue: Decodable, Identifiable, Hashable {
    let startMS: Int64
    let endMS: Int64
    let text: String

    var id: Int64 { startMS }

    enum CodingKeys: String, CodingKey {
        case text
        case startMS = "start_ms"
        case endMS = "end_ms"
    }
}

struct RelatedPerson: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let relationship: String
    let avatarURLValue: String?
    let avatarAssetName: String?

    enum CodingKeys: String, CodingKey {
        case id, name, relationship
        case avatarURLValue = "avatar_url"
        case avatarAssetName = "avatar_asset_name"
    }

    func avatarURL(baseURL: URL) -> URL? {
        guard let value = nonempty(avatarURLValue) else { return nil }
        if let url = URL(string: value), url.scheme != nil {
            return MediaURL.image(value) ?? url
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }
}

private func nonempty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

enum PeopleTopic: String, CaseIterable, Identifiable {
    case technology = "科技"
    case business = "商业"
    case investment = "投资"
    case politics = "政治"
    case history = "历史"

    var id: Self { self }

    init?(apiValue: String) {
        switch apiValue {
        case "technology": self = .technology
        case "business": self = .business
        case "investment": self = .investment
        case "politics": self = .politics
        case "history": self = .history
        default: return nil
        }
    }
}
