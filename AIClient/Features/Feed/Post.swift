import Foundation

struct PostListResponse: Decodable { let data: [Post] }
struct PostDetailResponse: Decodable { let post: Post }

struct HotTopicsResponse: Decodable {
    let success: Bool
    let data: DataPayload
    struct DataPayload: Decodable { let topics: [HotTopic] }
}

struct HotTopic: Decodable {
    let id: Int?
    let keyword, summary, reason, searchLink: String?
    let latestRank: Int?
    let latestHeat: Double?
    let rankChange: Int?
    let meta: Meta?

    struct Meta: Decodable {
        let lastPayload: Payload?
        enum CodingKeys: String, CodingKey { case lastPayload = "last_payload" }
    }
    struct Payload: Decodable {
        let heat: String?
        let hotValue: Double?
        enum CodingKeys: String, CodingKey { case heat; case hotValue = "hot_value" }
    }
    enum CodingKeys: String, CodingKey {
        case id, keyword, summary, reason, meta
        case searchLink = "search_link"
        case latestRank = "latest_rank"
        case latestHeat = "latest_heat"
        case rankChange = "rank_change"
    }
}

struct FlashResponse: Decodable {
    let success: Bool
    let data: DataPayload
    struct DataPayload: Decodable { let items: [FlashItem]; let hasMore: Bool? }
}

struct FlashItem: Decodable {
    let id, time, text, source, linkURL, avatarURL: String?
    let isImportant: Bool?
    enum CodingKeys: String, CodingKey {
        case id, time, text, source, isImportant
        case linkURL = "linkUrl"
        case avatarURL = "avatarUrl"
    }
}

struct CategoryResponse: Decodable {
    let success: Bool
    let categories: [FeedCategory]
}
struct FeedCategory: Decodable { let id: Int; let name: String }

struct Post: Decodable, Identifiable, Hashable {
    static let minimumFeedScore = 5.0

    let id: Int
    let title, text, summary, content, source, formattedTime: String?
    let finalScore, weight: Double?
    let postLink, articlePostAt: String?
    let user: PostUser?
    let postTags: [PostTag]?
    let images: [PostImage]?
    let videos: [PostVideo]?
    let feedRank: Int?
    let meta: PostMeta?

    var displayTitle: String { clean(title) ?? clean(summary) ?? clean(text) ?? "无标题" }
    var displaySummary: String? {
        let value = clean(summary) ?? clean(text)
        return value == displayTitle ? nil : value
    }
    var displayContent: String { htmlText(content) ?? clean(text) ?? clean(summary) ?? displayTitle }
    var authorName: String { clean(user?.userScreenName) ?? clean(user?.userName) ?? sourceName }
    var authorHandle: String? {
        guard let handle = clean(user?.userName), handle != authorName else { return nil }
        return handle.hasPrefix("@") ? handle : "@\(handle)"
    }
    var sourceName: String {
        let value = (source ?? "").lowercased()
        if value.hasPrefix("rss:") { return "RSS" }
        if value.contains("weibo") { return "微博" }
        if value.contains("douyin") { return "抖音" }
        if value.contains("bilibili") { return "B站" }
        if value.contains("zhihu") { return "知乎" }
        if value.contains("truth") { return "Truth" }
        if value == "flash" { return "快讯" }
        if value.hasPrefix("x") || value.contains("twitter") { return "X" }
        return value.isEmpty ? "信息流" : value
    }
    var normalizedSource: String { sourceName }
    var score: Double? { finalScore ?? weight }
    var meetsMinimumFeedScore: Bool { score.map { $0 >= Self.minimumFeedScore } ?? false }
    var imageURLs: [URL] { (images ?? []).compactMap { MediaURL.image($0.url) } }
    var videoURLs: [URL] { (videos ?? []).compactMap { $0.url ?? $0.playURL }.compactMap(MediaURL.video) }
    var previewURL: URL? {
        imageURLs.first ?? (videos ?? []).compactMap { $0.coverURL ?? $0.previewImageURL }.compactMap(MediaURL.image).first
    }
    var linkURL: URL? { clean(postLink).flatMap(URL.init(string:)) }
    var avatarURL: URL? { clean(user?.avatarURL).flatMap(MediaURL.image) }
    var tagNames: [String] { (postTags ?? []).map(\.name) }
    var isBilibili: Bool { sourceName == "B站" }
    var isRSS: Bool { (source ?? "").hasPrefix("rss:") }
    var isHotTopic: Bool { source == "weibo" || source == "douyin-hot" }
    var isFlash: Bool { source == "flash" }
    var isSynthetic: Bool { isHotTopic || isFlash }
    var isSocial: Bool { !isRSS && !isBilibili }

    private func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
    private func htmlText(_ value: String?) -> String? {
        guard let value = clean(value) else { return nil }
        guard value.contains("<") || value.contains("&lt;") || value.contains("&amp;lt;") else { return value }
        let decoded = value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let text = decoded
            .replacingOccurrences(of: "<br\\s*/?>|</p>|</div>|</blockquote>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return clean(text)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, text, summary, content, source, weight, user, images, videos, feedRank, meta
        case formattedTime = "formatted_time"
        case finalScore = "final_score"
        case postLink = "post_link"
        case articlePostAt = "article_post_at"
        case postTags
    }

    static func hotTopic(_ topic: HotTopic, source: FeedSource) -> Post {
        let rank = topic.latestRank
        let heat = topic.latestHeat.map { String(Int($0)) } ?? topic.meta?.lastPayload?.heat ?? topic.meta?.lastPayload?.hotValue.map { String(Int($0)) }
        let meta = [rank.map { "第 \($0) 名" }, heat.map { "热度 \($0)" }].compactMap { $0 }.joined(separator: " · ")
        return Post(
            id: syntheticID("\(source.rawValue):\(topic.id ?? 0):\(topic.keyword ?? "")"),
            title: topic.keyword, text: nil, summary: topic.summary, content: topic.summary?.isEmpty == false ? topic.summary : topic.reason,
            source: source.rawValue, formattedTime: meta, finalScore: nil, weight: nil,
            postLink: topic.searchLink, articlePostAt: nil,
            user: .init(userName: nil, userScreenName: source.title + "热榜", avatarURL: nil, userDesc: nil),
            postTags: topic.rankChange.map { $0 > 0 ? [.init(id: 0, name: "上升 \($0)")] : [] } ?? [],
            images: [], videos: [], feedRank: rank, meta: nil
        )
    }

    static func flash(_ item: FlashItem) -> Post {
        Post(
            id: syntheticID("flash:\(item.id ?? ""):\(item.text ?? "")"),
            title: nil, text: item.text, summary: nil, content: item.text,
            source: "flash", formattedTime: item.time, finalScore: nil, weight: nil,
            postLink: item.linkURL, articlePostAt: nil,
            user: .init(userName: nil, userScreenName: flashSourceName(item.source), avatarURL: item.avatarURL, userDesc: nil),
            postTags: item.isImportant == true ? [.init(id: 0, name: "重要")] : [],
            images: [], videos: [], feedRank: nil, meta: nil
        )
    }

    private static func syntheticID(_ key: String) -> Int {
        let hash = key.utf8.reduce(UInt64(1_469_598_103_934_665_603)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        return -Int(hash & 0x3fff_ffff) - 1
    }

    private static func flashSourceName(_ value: String?) -> String {
        let source = (value ?? "").lowercased()
        if source.contains("jin10") { return "金十数据" }
        if source.contains("cls") { return "财联社" }
        if source.contains("sina") { return "新浪快讯" }
        if source.contains("eastmoney") { return "东方财富" }
        return "快讯"
    }
}

struct PostMeta: Decodable, Hashable {
    let metrics: PostMetrics?
}

struct PostMetrics: Decodable, Hashable {
    let bookmarks, likes, quotes, replies, retweets, views: Int?
}

struct PostUser: Decodable, Hashable {
    let userName, userScreenName, avatarURL, userDesc: String?
    enum CodingKeys: String, CodingKey {
        case userName = "user_name"
        case userScreenName = "user_screen_name"
        case avatarURL = "avatar_url"
        case userDesc = "user_desc"
    }
}

struct PostTag: Decodable, Hashable { let id: Int; let name: String }
struct PostImage: Decodable, Hashable { let url: String }
struct PostVideo: Decodable, Hashable {
    let url, playURL, coverURL, previewImageURL: String?
    enum CodingKeys: String, CodingKey {
        case url
        case playURL = "play_url"
        case coverURL = "cover_url"
        case previewImageURL = "preview_image_url"
    }
}

enum MediaURL {
    private static let imageHostSuffixes = ["twimg.com", "hdslb.com", "biliimg.com", "sinaimg.cn", "sina.com.cn", "ytimg.com", "ggpht.com", "truthsocial.com"]

    static func image(_ raw: String) -> URL? { resolved(raw, proxy: "image-proxy", hosts: imageHostSuffixes) }
    static func video(_ raw: String) -> URL? { resolved(raw, proxy: "media-proxy", hosts: ["video.twimg.com", "truthsocial.com"]) }

    private static func resolved(_ raw: String, proxy: String, hosts: [String]) -> URL? {
        let value = raw.hasPrefix("//") ? "https:\(raw)" : raw
        guard let direct = URL(string: value, relativeTo: ServerConfiguration.currentURL)?.absoluteURL else { return nil }
        guard let host = direct.host?.lowercased(), hosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else { return direct }
        var parts = URLComponents(url: ServerConfiguration.currentURL.appending(path: "api/v1/\(proxy)"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [.init(name: "url", value: direct.absoluteString), .init(name: "soft", value: "1"), .init(name: "context", value: "ios-feed")]
        return parts?.url
    }
}

enum FeedSource: String, CaseIterable, Identifiable {
    case x, weibo
    case douyin = "douyin-hot"
    case bilibili, zhihu, truth, rss, laozhong, youtube, flash

    var id: String { rawValue }
    var title: String {
        switch self {
        case .x: "X"
        case .weibo: "微博"
        case .douyin: "抖音"
        case .bilibili: "B站"
        case .zhihu: "知乎"
        case .truth: "Truth"
        case .rss: "RSS"
        case .laozhong: "老中"
        case .youtube: "YouTube"
        case .flash: "快讯"
        }
    }
}
