import Foundation

struct KnownAccountIdentity: Hashable {
    let canonicalName: String
    let platform: String
    let accountName: String
    let aliases: [String]

    var accountLabel: String { "\(platform) · \(accountName)" }
}

enum AccountIdentityResolver {
    // Curated identities are keyed only by stable server/platform IDs. Never infer a
    // real person from a mutable nickname, because unrelated accounts may share it.
    private static let identitiesByUserID: [String: KnownAccountIdentity] = [
        "rss:14": KnownAccountIdentity(
            canonicalName: "段永平",
            platform: "雪球",
            accountName: "大道无形我有型",
            aliases: ["段永平", "大道无形我有型"]
        )
    ]

    static func knownIdentity(userID: String?) -> KnownAccountIdentity? {
        guard let userID = nonempty(userID) else { return nil }
        return identitiesByUserID[userID.lowercased()]
    }
}

struct SpecialPeopleResponse: Decodable {
    let success: Bool
    let categories: [PeopleCategory]?
    let users: [SpecialPerson]
}

struct XPeopleSearchResponse: Decodable {
    let success: Bool
    let results: [XPersonSearchResult]
}

struct XPersonImportResponse: Decodable {
    let success: Bool
    let added: Bool
    let person: SpecialPerson
}

struct WikipediaPeopleSearchResponse: Decodable {
    let success: Bool
    let results: [WikipediaPersonSearchResult]
}

struct WikipediaPersonImportResponse: Decodable {
    let success: Bool
    let added: Bool
    let person: SpecialPerson
}

struct WikipediaPersonSearchResult: Decodable, Identifiable, Hashable {
    let id: String
    let pageID: Int64
    let language: String
    let title: String
    let description: String?
    let extract: String?
    let avatarURLValue: String?
    let articleURLValue: String
    let alreadyInDirectory: Bool
    let personID: String?

    var name: String { title }
    var avatarURL: URL? { avatarURLValue.flatMap(MediaURL.image) }
    var articleURL: URL? { URL(string: articleURLValue) }
    var sourceLabel: String { language == "en" ? "英文维基百科" : "中文维基百科" }

    enum CodingKeys: String, CodingKey {
        case id, language, title, description, extract
        case pageID = "page_id"
        case avatarURLValue = "avatar_url"
        case articleURLValue = "article_url"
        case alreadyInDirectory = "already_in_directory"
        case personID = "person_id"
    }
}

struct XPersonSearchResult: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let screenName: String
    let description: String?
    let avatarURLValue: String?
    let verified: Bool
    let followersCount: Int64
    let followingCount: Int64
    let alreadyInDirectory: Bool
    let personID: String?

    var handle: String { screenName.hasPrefix("@") ? screenName : "@\(screenName)" }
    var avatarURL: URL? { avatarURLValue.flatMap(MediaURL.image) }

    enum CodingKeys: String, CodingKey {
        case id, name, description, verified
        case screenName = "screen_name"
        case avatarURLValue = "avatar_url"
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case alreadyInDirectory = "already_in_directory"
        case personID = "person_id"
    }
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
    let xUserID: String?
    let xScreenName: String?
    private let topicValue: String?
    private let organizationNameValue: String?
    private let avatarAssetNameValue: String?
    private let discussionKeywordsValue: [String]?
    private let hasOwnPostSourceValue: Bool?
    private let focusTagsValue: [String]?
    private let rolesValue: [PersonRole]?
    private let milestonesValue: [PersonMilestone]?
    private let relatedPeopleValue: [RelatedPerson]?
    private let photosValue: [PersonPhoto]?
    private let socialAccountsValue: [PersonSocialAccount]?
    private let profileUpdatedAtValue: String?
    private let lifeYearsValue: String?

    var id: String { userID }
    var isCurated: Bool { userID.hasPrefix("curated:") }
    var isIndustryPerson: Bool { topic == .technology }
    var hasOwnPostSource: Bool { hasOwnPostSourceValue ?? !isCurated }
    var hasXSource: Bool { nonempty(xScreenName) != nil }
    var isOrganizationAccount: Bool { false }
    private var knownIdentity: KnownAccountIdentity? {
        AccountIdentityResolver.knownIdentity(userID: userID)
    }
    var name: String {
        knownIdentity?.canonicalName ?? nonempty(userName) ?? nonempty(userScreenName) ?? "未知用户"
    }
    var xHandle: String? {
        nonempty(xScreenName).map { $0.hasPrefix("@") ? $0 : "@\($0)" }
    }
    var handle: String? {
        xHandle ?? nonempty(userScreenName).map { $0.hasPrefix("@") ? $0 : "@\($0)" }
    }
    var xProfileURL: URL? {
        guard let screenName = nonempty(xScreenName)?.trimmingCharacters(in: CharacterSet(charactersIn: "@")) else {
            return nil
        }
        return URL(string: "https://x.com")?.appending(path: screenName)
    }
    var secondaryLabel: String? {
        knownIdentity?.accountLabel ?? (isCurated ? nonempty(userScreenName) : handle)
    }
    var organizationName: String? {
        nonempty(organizationNameValue) ?? (isCurated ? nonempty(userScreenName) : nil)
    }
    var avatarAssetName: String? {
        if userID.localizedCaseInsensitiveContains("elon-musk") ||
            name.localizedCaseInsensitiveContains("Elon Musk") {
            return "ElonMuskAvatar"
        }
        return nonempty(avatarAssetNameValue)
    }
    var discussionKeywords: [String] {
        let serverKeywords = discussionKeywordsValue?.filter({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) ?? []
        let identityKeywords = knownIdentity?.aliases ?? []
        let keywords = (serverKeywords + identityKeywords).reduce(into: [String]()) { result, keyword in
            guard !result.contains(keyword) else { return }
            result.append(keyword)
        }
        return keywords.isEmpty ? [name] : keywords
    }
    var focusTags: [String] {
        let tags = focusTagsValue?.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
        return tags.isEmpty ? Array(discussionKeywords.prefix(4)) : Array(tags.prefix(4))
    }
    var displayFocusTags: [String] {
        focusTags.map { tag in
            switch tag {
            case "忠臣": "赢"
            case "反贼": "输"
            default: tag
            }
        }
    }
    var roles: [PersonRole] {
        if let rolesValue, !rolesValue.isEmpty { return rolesValue }
        return [PersonRole(organization: organizationName ?? topic.rawValue, title: secondaryLabel ?? "人物")]
    }
    var milestones: [PersonMilestone] { milestonesValue ?? [] }
    var relatedPeople: [RelatedPerson] { relatedPeopleValue ?? [] }
    var photos: [PersonPhoto] { photosValue ?? [] }
    var socialAccounts: [PersonSocialAccount] {
        var accounts = socialAccountsValue?.filter { $0.profileURL != nil } ?? []
        if let xProfileURL,
           !accounts.contains(where: { $0.profileURL == xProfileURL }) {
            accounts.append(
                PersonSocialAccount(
                    platform: "X",
                    handle: xHandle ?? "X",
                    profileURLValue: xProfileURL.absoluteString
                )
            )
        }
        return accounts
    }
    var profileUpdatedAt: String? { nonempty(profileUpdatedAtValue) }
    var lifeYears: String? { nonempty(lifeYearsValue) }
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
        case xUserID = "x_user_id"
        case xScreenName = "x_screen_name"
        case topicValue = "topic"
        case organizationNameValue = "organization_name"
        case avatarAssetNameValue = "avatar_asset_name"
        case discussionKeywordsValue = "discussion_keywords"
        case hasOwnPostSourceValue = "has_own_post_source"
        case focusTagsValue = "focus_tags"
        case rolesValue = "roles"
        case milestonesValue = "milestones"
        case relatedPeopleValue = "related_people"
        case photosValue = "photos"
        case socialAccountsValue = "social_accounts"
        case profileUpdatedAtValue = "profile_updated_at"
        case lifeYearsValue = "life_years"
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
        self.xUserID = xUserID
        self.xScreenName = xScreenName
        topicValue = nil
        organizationNameValue = organization
        avatarAssetNameValue = nil
        discussionKeywordsValue = [name]
        hasOwnPostSourceValue = xUserID != nil
        focusTagsValue = nil
        rolesValue = nil
        milestonesValue = nil
        relatedPeopleValue = nil
        photosValue = nil
        socialAccountsValue = nil
        profileUpdatedAtValue = nil
        lifeYearsValue = nil
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

struct PersonSocialAccount: Decodable, Hashable, Identifiable {
    let platform: String
    let handle: String
    let profileURLValue: String

    var id: String { "\(platform)|\(profileURLValue)" }
    var profileURL: URL? { URL(string: profileURLValue) }
    var displayHandle: String {
        handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? platform : handle
    }

    enum CodingKeys: String, CodingKey {
        case platform, handle
        case profileURLValue = "profile_url"
    }
}

struct PeopleArticlesResponse: Decodable {
    let success: Bool
    let personID: String
    let articles: [PersonArticle]
    let queryApplied: Bool?

    enum CodingKeys: String, CodingKey {
        case success, articles
        case personID = "person_id"
        case queryApplied = "query_applied"
    }
}

struct PersonArticleDetailResponse: Decodable {
    let success: Bool
    let article: PersonArticle
}

struct PersonArticle: Decodable, Identifiable, Hashable {
    let id: Int64
    let personID: String
    let sourceName: String
    let sourceURLValue: String
    let title: String
    let titleZH: String
    let summary: String
    let summaryZH: String?
    let content: String?
    let contentZH: String?
    let canonicalURLValue: String
    let publishedAt: String?
    let readingMinutes: Int
    let language: String

    enum CodingKeys: String, CodingKey {
        case id, title, summary, content, language
        case personID = "person_id"
        case sourceName = "source_name"
        case sourceURLValue = "source_url"
        case titleZH = "title_zh"
        case summaryZH = "summary_zh"
        case contentZH = "content_zh"
        case canonicalURLValue = "canonical_url"
        case publishedAt = "published_at"
        case readingMinutes = "reading_minutes"
    }

    var displayTitle: String { nonempty(titleZH) ?? title }
    var displaySummary: String { nonempty(summaryZH) ?? summary }
    var displayContent: String { nonempty(contentZH) ?? nonempty(content) ?? "" }
    var canonicalURL: URL? { URL(string: canonicalURLValue) }
    var publishedDateLabel: String? {
        guard let publishedAt,
              let date = ISO8601DateFormatter().date(from: publishedAt) else { return nil }
        return date.formatted(
            .dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))
        )
    }
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

struct BilibiliSubtitlesResponse: Decodable {
    let success: Bool
    let bvid: String
    let language: String
    let status: String
    let cues: [PersonVideoSubtitleCue]
}

struct BilibiliSummaryResponse: Decodable {
    let success: Bool
    let bvid: String
    let status: String
    let summary: BilibiliVideoSummary
    let provider: String
    let model: String
    let cached: Bool
}

struct BilibiliVideoSummary: Decodable, Hashable {
    let overview: String
    let keyPoints: [String]

    enum CodingKeys: String, CodingKey {
        case overview
        case keyPoints = "key_points"
    }
}

struct BilibiliInterpretationResponse: Decodable {
    let success: Bool
    let bvid: String
    let status: String
    let interpretation: BilibiliVideoInterpretation
    let provider: String
    let model: String
    let cached: Bool
    let estimatedCostCNY: Double
    let pricingNote: String

    enum CodingKeys: String, CodingKey {
        case success, bvid, status, interpretation, provider, model, cached
        case estimatedCostCNY = "estimated_cost_cny"
        case pricingNote = "pricing_note"
    }
}

struct BilibiliVideoInterpretation: Decodable, Hashable {
    let overview: String
    let visualFindings: [String]
    let timeline: [BilibiliInterpretationEvent]
    let creatorNotes: [String]

    enum CodingKeys: String, CodingKey {
        case overview, timeline
        case visualFindings = "visual_findings"
        case creatorNotes = "creator_notes"
    }
}

struct BilibiliInterpretationEvent: Decodable, Hashable {
    let time: String
    let title: String
    let detail: String
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

struct PeopleRelationshipLens: Identifiable, Equatable {
    let title: String
    let memberCount: Int

    var id: String { title }
}

struct PeopleRelationshipMember: Identifiable, Hashable {
    let id: String
    let name: String
    let relationship: String
    let person: SpecialPerson?
    let avatarURLValue: String?
    let avatarAssetName: String?

    func avatarURL(baseURL: URL) -> URL? {
        if let person {
            return person.avatarURL(baseURL: baseURL)
        }
        guard let avatarURLValue = nonempty(avatarURLValue) else { return nil }
        if let url = URL(string: avatarURLValue), url.scheme != nil {
            return MediaURL.image(avatarURLValue) ?? url
        }
        return URL(string: avatarURLValue, relativeTo: baseURL)?.absoluteURL
    }
}

struct PeopleRelationshipCluster: Identifiable, Hashable {
    let id: String
    let title: String
    let members: [PeopleRelationshipMember]

    var memberCount: Int { members.count }
}

enum PeopleRelationshipPlanner {
    static func lenses(for people: [SpecialPerson], limit: Int = 6) -> [PeopleRelationshipLens] {
        let counts = Dictionary(grouping: people) { primaryOrganization(for: $0) }
            .mapValues(\.count)
        return counts
            .map { PeopleRelationshipLens(title: $0.key, memberCount: $0.value) }
            .sorted {
                if $0.memberCount != $1.memberCount {
                    return $0.memberCount > $1.memberCount
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    static func visiblePeople(
        topicPeople: [SpecialPerson],
        allPeople: [SpecialPerson],
        focusedPersonID: String?,
        organization: String?,
        limit: Int = 8
    ) -> [SpecialPerson] {
        guard limit > 0 else { return [] }
        let peopleByID = allPeople.reduce(into: [String: SpecialPerson]()) { result, person in
            result[person.id] = person
        }

        if let focusedPersonID, let focused = peopleByID[focusedPersonID] {
            var result: [SpecialPerson] = []
            var seen = Set([focused.id])

            func append(_ person: SpecialPerson?) {
                guard let person, seen.insert(person.id).inserted else { return }
                result.append(person)
            }

            for related in focused.relatedPeople {
                append(peopleByID[related.id])
            }
            for person in allPeople where person.relatedPeople.contains(where: { $0.id == focused.id }) {
                append(person)
            }
            return Array(result.prefix(limit))
        }

        let candidates: [SpecialPerson]
        if let organization {
            candidates = ranked(
                topicPeople.filter { primaryOrganization(for: $0) == organization }
            )
        } else {
            candidates = ranked(topicPeople)
        }
        return Array(candidates.prefix(limit))
    }

    static func relationshipLabel(from center: SpecialPerson, to other: SpecialPerson) -> String {
        if let relation = center.relatedPeople.first(where: { $0.id == other.id })?.relationship {
            return relation
        }
        if let relation = other.relatedPeople.first(where: { $0.id == center.id })?.relationship {
            return relation
        }
        return "暂无已核实关系"
    }

    static func clusters(
        around center: SpecialPerson,
        allPeople: [SpecialPerson],
        maximumClusters: Int = 5
    ) -> [PeopleRelationshipCluster] {
        guard maximumClusters > 0 else { return [] }
        let peopleByID = allPeople.reduce(into: [String: SpecialPerson]()) { result, person in
            result[person.id] = person
        }
        var membersByID: [String: PeopleRelationshipMember] = [:]

        for related in center.relatedPeople {
            let person = peopleByID[related.id]
            membersByID[related.id] = PeopleRelationshipMember(
                id: related.id,
                name: related.name,
                relationship: related.relationship,
                person: person,
                avatarURLValue: related.avatarURLValue,
                avatarAssetName: related.avatarAssetName
            )
        }

        for person in allPeople where person.id != center.id {
            guard let inbound = person.relatedPeople.first(where: { $0.id == center.id }) else { continue }
            if membersByID[person.id] == nil {
                membersByID[person.id] = PeopleRelationshipMember(
                    id: person.id,
                    name: person.name,
                    relationship: inbound.relationship,
                    person: person,
                    avatarURLValue: person.avatarPath,
                    avatarAssetName: person.avatarAssetName
                )
            }
        }

        let grouped = Dictionary(grouping: membersByID.values) {
            relationshipClusterTitle(
                relationship: $0.relationship,
                center: center,
                other: $0.person
            )
        }
        var clusters = grouped.map { title, members in
            PeopleRelationshipCluster(
                id: title,
                title: title,
                members: members.sorted {
                    if ($0.person?.todayCount ?? 0) != ($1.person?.todayCount ?? 0) {
                        return ($0.person?.todayCount ?? 0) > ($1.person?.todayCount ?? 0)
                    }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            )
        }
        .sorted {
            if $0.memberCount != $1.memberCount {
                return $0.memberCount > $1.memberCount
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }

        guard clusters.count > maximumClusters else { return clusters }
        let retainedCount = max(0, maximumClusters - 1)
        let retained = Array(clusters.prefix(retainedCount))
        let remainingMembers = clusters.dropFirst(retainedCount).flatMap(\.members)
        let other = PeopleRelationshipCluster(
            id: "other-relations",
            title: "其他关联",
            members: remainingMembers
        )
        clusters = retained + [other]
        return clusters
    }

    static func primaryOrganization(for person: SpecialPerson) -> String {
        let raw = person.roles.first?.organization
            ?? person.organizationName
            ?? person.focusTags.first
            ?? person.topic.rawValue
        return compactOrganizationName(raw, fallback: person.topic.rawValue)
    }

    private static func relationshipClusterTitle(
        relationship: String,
        center: SpecialPerson,
        other: SpecialPerson?
    ) -> String {
        let value = relationship.trimmingCharacters(in: .whitespacesAndNewlines)
        let mappings: [(title: String, keywords: [String])] = [
            ("竞争", ["竞争", "对手", "竞品"]),
            ("访谈", ["访谈", "播客", "受访"]),
            ("投资", ["投资", "股东", "资本", "基金", "出资"]),
            ("合作", ["合作", "伙伴", "客户", "供应", "生态", "联盟"]),
            ("同事", ["同事", "团队", "任职", "高管", "下属", "创始"]),
            ("学术", ["学术", "教授", "研究"]),
            ("历史关联", ["历史", "国共", "革命", "改革开放", "国家建设"]),
            ("行业同行", ["同行", "同业"]),
            ("师友", ["导师", "学生", "师生", "前辈", "好友", "朋友"]),
            ("家庭", ["家人", "家庭", "夫妻", "父亲", "母亲", "兄弟", "姐妹", "亲属"])
        ]
        if let mapping = mappings.first(where: { item in
            item.keywords.contains { value.localizedCaseInsensitiveContains($0) }
        }) {
            return mapping.title
        }
        if let other {
            let centerOrganization = primaryOrganization(for: center)
            let otherOrganization = primaryOrganization(for: other)
            if centerOrganization == otherOrganization {
                return centerOrganization.count <= 8 ? centerOrganization : "同一机构"
            }
        }
        if !value.isEmpty, value.count <= 6 {
            return value
        }
        return "行业关联"
    }

    private static func ranked(_ people: [SpecialPerson]) -> [SpecialPerson] {
        people.sorted {
            let lhs = ($0.relatedPeople.count, $0.todayCount, $0.totalCount)
            let rhs = ($1.relatedPeople.count, $1.todayCount, $1.totalCount)
            if lhs.0 != rhs.0 { return lhs.0 > rhs.0 }
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func compactOrganizationName(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        let roleMarkers = [
            "联合创始人", "创始人", "董事长", "首席", "CEO", "总裁",
            "负责人", "政治人物", "历史人物", "投资作者", "内容作者"
        ]
        let cut = roleMarkers
            .compactMap { trimmed.range(of: $0)?.lowerBound }
            .min()
        let compact = cut.map {
            String(trimmed[..<$0]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let compact, !compact.isEmpty {
            return compact
        }
        return trimmed
    }
}

struct PersonPhoto: Decodable, Identifiable, Hashable {
    let id: String
    let imageURLValue: String
    let title: String
    let caption: String?
    let date: String?
    let source: String
    let sourceURLValue: String
    let author: String?
    let license: String?

    enum CodingKeys: String, CodingKey {
        case id, title, caption, date, source, author, license
        case imageURLValue = "image_url"
        case sourceURLValue = "source_url"
    }

    func imageURL(baseURL: URL) -> URL? {
        if let url = URL(string: imageURLValue), url.scheme != nil {
            return MediaURL.image(imageURLValue) ?? url
        }
        return URL(string: imageURLValue, relativeTo: baseURL)?.absoluteURL
    }

    var sourceURL: URL? { URL(string: sourceURLValue) }
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
    case ideology = "意识形态"
    case history = "历史"

    var id: Self { self }

    init?(apiValue: String) {
        switch apiValue {
        case "technology": self = .technology
        case "business": self = .business
        case "investment": self = .investment
        case "politics": self = .politics
        case "ideology": self = .ideology
        case "history": self = .history
        default: return nil
        }
    }
}
