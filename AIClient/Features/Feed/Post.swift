import Foundation

struct PostListResponse: Decodable { let data: [Post] }
struct PostDetailResponse: Decodable { let post: Post }

struct XCommentsResponse: Decodable {
    let success: Bool
    let data: Payload

    struct Payload: Decodable {
        let items: [XComment]
        let nextCursor: String?
    }
}

struct XComment: Decodable, Identifiable, Equatable {
    let id: String
    let text: String
    let author: Author
    let metrics: Metrics?
    let createdAt: String?
    let inReplyToScreenName: String?
    let lang: String?

    struct Author: Decodable, Equatable {
        let name: String
        let screenName: String
        let profileImageUrl: String?
        let verified: Bool?

        var handle: String { screenName.hasPrefix("@") ? screenName : "@\(screenName)" }
        var avatarURL: URL? { profileImageUrl.flatMap(MediaURL.image) }
    }

    struct Metrics: Decodable, Equatable {
        let likes, retweets, replies: Int?
    }
}

struct XTranslationResponse: Decodable {
    let success: Bool
    let data: XTranslation
}

struct XTranslation: Decodable, Equatable {
    let tweetId: String
    let text: String
    let sourceLanguage: String?
    let destinationLanguage: String?
}

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
    let finalScore: Double?
    enum CodingKeys: String, CodingKey {
        case id, time, text, source, isImportant, finalScore
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
    static let minimumFeedScore = 5
    static let importantFlashScore = 7.0

    let id: Int
    let title, text, summary, content, contentZH, source, formattedTime, weightReason: String?
    let finalScore, weight: Double?
    let postLink, articlePostAt: String?
    let user: PostUser?
    let postTags: [PostTag]?
    let images: [PostImage]?
    let videos: [PostVideo]?
    let feedRank: Int?
    let meta: PostMeta?

    var displayTitle: String { clean(contentZH) ?? clean(title) ?? clean(summary) ?? clean(text) ?? "无标题" }
    var bilibiliTitle: String {
        if let title = clean(title), title.count <= 120 { return title }
        if let summary = clean(summary), summary.count <= 120 { return summary }
        let content = displayContent.replacingOccurrences(of: "\n", with: " ")
        if let sentenceEnd = content.firstIndex(where: { "。！？".contains($0) }) {
            let sentence = String(content[...sentenceEnd])
            if sentence.count <= 120 { return sentence }
        }
        return String(content.prefix(72)) + (content.count > 72 ? "…" : "")
    }
    var displaySummary: String? {
        let value = clean(summary) ?? clean(text)
        return value == displayTitle ? nil : value
    }
    var displayContent: String { htmlText(contentZH) ?? originalDisplayContent }
    var originalDisplayContent: String { htmlText(content) ?? clean(text) ?? clean(summary) ?? displayTitle }
    var hasTranslation: Bool { clean(contentZH) != nil && clean(contentZH) != clean(content) }
    var truthFeedContent: String {
        guard let translated = htmlText(contentZH) else { return "翻译处理中" }
        let markers = ["https://", "http://", "https：//", "http：//"]
        let firstLink = markers.compactMap { translated.range(of: $0, options: .caseInsensitive) }.min { $0.lowerBound < $1.lowerBound }
        guard let firstLink else { return translated }
        let text = String(translated[..<firstLink.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":：")))
        return text.isEmpty ? "分享了一则链接" : text
    }
    var truthRelevanceLabel: String? {
        guard let score else { return nil }
        if score >= 7 { return "高度相关" }
        if score >= 5.8 { return "中度相关" }
        return nil
    }
    var truthImpactText: String? {
        guard let reason = clean(weightReason) else { return nil }
        let unavailableMarkers = ["正式模型失败", "缺乏", "未阐述", "无法评估", "未提供", "信息不足"]
        guard !unavailableMarkers.contains(where: reason.contains) else { return nil }

        let prefixes = ["可能影响：", "可能影响:", "影响：", "影响:"]
        guard let match = prefixes.compactMap({ prefix in
            reason.range(of: prefix).map { ($0, prefix) }
        }).min(by: { $0.0.lowerBound < $1.0.lowerBound }) else { return nil }

        let impact = String(reason[match.0.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !impact.isEmpty else { return nil }
        let firstSentence = impact.split(whereSeparator: { "。！？\n".contains($0) }).first.map(String.init) ?? impact
        return firstSentence.count > 66 ? String(firstSentence.prefix(66)) + "…" : firstSentence
    }
    var authorName: String { clean(user?.userName) ?? clean(user?.userScreenName) ?? sourceName }
    var authorHandle: String? {
        guard let handle = clean(user?.userScreenName), handle != authorName else { return nil }
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
    var imageURLs: [URL] { (images ?? []).compactMap { MediaURL.image($0.url) } }
    var videoURLs: [URL] { (videos ?? []).compactMap { $0.playURL ?? $0.url }.compactMap(MediaURL.video) }
    var previewURL: URL? {
        imageURLs.first ?? (videos ?? []).compactMap { $0.coverURL ?? $0.previewImageURL ?? $0.preview }.compactMap(MediaURL.image).first
    }
    var youtubeCoverURL: URL? {
        if let previewURL { return previewURL }
        guard let videoID = youtubeVideoID else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }
    var youtubeVideoID: String? {
        guard isYouTube, let linkURL else { return nil }
        if linkURL.host()?.contains("youtu.be") == true {
            return linkURL.pathComponents.last
        } else if linkURL.path.hasPrefix("/shorts/") {
            return linkURL.pathComponents.dropFirst().dropFirst().first
        } else {
            return URLComponents(url: linkURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "v" })?.value
        }
    }
    var linkURL: URL? { clean(postLink).flatMap(URL.init(string:)) }
    var xTweetID: String? {
        guard sourceName == "X", let linkURL else { return nil }
        let parts = linkURL.pathComponents
        guard let statusIndex = parts.firstIndex(of: "status"), parts.indices.contains(statusIndex + 1) else { return nil }
        let value = parts[statusIndex + 1]
        return !value.isEmpty && value.allSatisfy(\.isNumber) ? value : nil
    }
    var avatarURL: URL? { clean(user?.avatarURL).flatMap(MediaURL.image) }
    var tagNames: [String] { (postTags ?? []).map(\.name) }
    var photoCredit: String? { clean(meta?.photoCredit) ?? (images ?? []).compactMap(\.altText).first(where: { !$0.isEmpty }) }
    var externalURL: URL? { (meta?.urls ?? []).compactMap(URL.init(string:)).first }
    var zhihuQuestionTitle: String { clean(title) ?? displayTitle }
    var zhihuTopicLabel: String? {
        let value = zhihuQuestionTitle.lowercased()
        let categories: [(keywords: [String], label: String)] = [
            (["codex", "windows", "wsl", "开发者"], "软件与开发者体验"),
            (["芯片", "半导体", "存储", "长鑫"], "半导体与产业"),
            (["gpt", "openai", "人工智能", "大模型", "agent"], "人工智能"),
            (["id software", "游戏", "微软"], "游戏与科技"),
            (["苹果", "商业", "产业"], "科技商业")
        ]
        if let category = categories.first(where: { item in
            item.keywords.contains { value.localizedCaseInsensitiveContains($0) }
        }) {
            return category.label
        }
        let stableLabels = Set(["技术", "人工智能", "科技", "商业", "金融", "互联网", "职场"])
        return tagNames.first(where: stableLabels.contains)
    }
    var zhihuHeat: String? { clean(meta?.zhihuHeat) ?? metadataLine(named: "热度") }
    var zhihuAnswerCount: Int? {
        if let value = meta?.zhihuAnswers, value > 0 { return value }
        return metadataLine(named: "回答数").flatMap(Int.init)
    }
    var zhihuAnswerPreview: String {
        if let excerpt = clean(meta?.zhihuAnswerExcerpt), excerpt != zhihuQuestionTitle {
            return excerpt
        }
        if let heat = zhihuHeat {
            return "当前热度 \(heat)。打开查看高赞回答与完整讨论。"
        }
        if let answers = zhihuAnswerCount {
            return "已有 \(answers) 个回答。打开查看高赞回答与完整讨论。"
        }
        return "打开查看高赞回答与完整讨论。"
    }
    var zhihuAnswerBody: String {
        clean(meta?.zhihuAnswerContent) ?? zhihuAnswerPreview
    }
    var hasFullZhihuAnswer: Bool {
        clean(meta?.zhihuAnswerContent) != nil
    }
    var zhihuCompactAnswerPreview: String {
        zhihuAnswerPreview
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var hasZhihuAnswer: Bool {
        guard let excerpt = clean(meta?.zhihuAnswerExcerpt) else { return false }
        return excerpt != zhihuQuestionTitle
    }
    var zhihuHotMeta: String? {
        let values = [
            meta?.zhihuRank.map { "热榜 #\($0)" },
            zhihuHeat
        ].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }
    var zhihuAnswerAuthorName: String { clean(meta?.zhihuAnswerAuthor?.name) ?? authorName }
    var zhihuAnswerAuthorHeadline: String? {
        clean(meta?.zhihuAnswerAuthor?.headline) ?? (meta?.zhihuAnswerAuthor == nil ? "今日热榜" : nil)
    }
    var zhihuAnswerAvatarURL: URL? {
        if meta?.zhihuAnswerAuthor != nil {
            return clean(meta?.zhihuAnswerAuthor?.avatarURL).flatMap(MediaURL.image)
        }
        return avatarURL
    }
    var zhihuAnswerVoteupCount: Int { max(meta?.zhihuAnswerVoteupCount ?? 0, 0) }
    var zhihuAnswerCommentCount: Int { max(meta?.zhihuAnswerCommentCount ?? 0, 0) }
    var zhihuReadingMinutes: Int {
        max(1, Int(ceil(Double(zhihuAnswerBody.count) / 350.0)))
    }
    var zhihuArticleParagraphs: [String] {
        let normalized = zhihuAnswerBody
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let explicit = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if explicit.count > 1 { return explicit }

        let sentences = normalized
            .replacingOccurrences(of: #"(?<=[。！？])\s*"#, with: "\n", options: .regularExpression)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard sentences.count > 2 else { return [normalized] }

        var paragraphs: [String] = []
        var current = ""
        for sentence in sentences {
            if !current.isEmpty { current += " " }
            current += sentence
            if current.count >= 72 {
                paragraphs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs
    }
    var zhihuEditorialDeck: String {
        let first = zhihuAnswerPreview
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return first.count > 72 ? String(first.prefix(72)) + "…" : first
    }
    var isBilibili: Bool { sourceName == "B站" }
    var isRSS: Bool { (source ?? "").hasPrefix("rss:") }
    var isYouTube: Bool {
        guard isRSS else { return false }
        if tagNames.contains("YouTube") { return true }
        let links = [postLink] + (videos ?? []).flatMap { [$0.url, $0.playURL] }
        return links.compactMap { $0 }.contains { value in
            guard let host = URL(string: value)?.host()?.lowercased() else { return false }
            return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
        }
    }
    var isNewYorkTimes: Bool { source == FeedSource.newYorkTimes.rawValue }
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
            .replacingOccurrences(of: "<[^>]*$", with: "", options: .regularExpression)
        return clean(text)
    }

    private func metadataLine(named name: String) -> String? {
        let prefix = "\(name):"
        return originalDisplayContent
            .split(separator: "\n")
            .map(String.init)
            .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap(clean)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, text, summary, content, source, weight, user, images, videos, feedRank, meta
        case contentZH = "content_zh"
        case formattedTime = "formatted_time"
        case weightReason = "weight_reason"
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
            title: topic.keyword, text: nil, summary: topic.summary, content: topic.summary?.isEmpty == false ? topic.summary : topic.reason, contentZH: nil,
            source: source.rawValue, formattedTime: meta, weightReason: nil, finalScore: nil, weight: nil,
            postLink: topic.searchLink, articlePostAt: nil,
            user: .init(userName: nil, userScreenName: source.title + "热榜", avatarURL: nil, userDesc: nil),
            postTags: topic.rankChange.map { $0 > 0 ? [.init(id: 0, name: "上升 \($0)")] : [] } ?? [],
            images: [], videos: [], feedRank: rank, meta: nil
        )
    }

    static func flash(_ item: FlashItem) -> Post {
        let isImportant = item.finalScore.map { $0 >= importantFlashScore } ?? (item.isImportant == true)
        return Post(
            id: syntheticID("flash:\(item.id ?? ""):\(item.text ?? "")"),
            title: nil, text: item.text, summary: nil, content: item.text, contentZH: nil,
            source: "flash", formattedTime: item.time, weightReason: nil, finalScore: item.finalScore, weight: nil,
            postLink: item.linkURL, articlePostAt: nil,
            user: .init(userName: nil, userScreenName: flashSourceName(item.source), avatarURL: item.avatarURL, userDesc: nil),
            postTags: isImportant ? [.init(id: 0, name: "重要")] : [],
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
    let lang: String?
    let urls: [String]?
    let photoCredit: String?
    let zhihuRank: Int?
    let zhihuHeat: String?
    let zhihuAnswers: Int?
    let zhihuFollowerCount: Int?
    let zhihuQuestionID: String?
    let zhihuURL: String?
    let zhihuAnswerExcerpt: String?
    let zhihuAnswerContent: String?
    let zhihuAnswerAuthor: ZhihuAnswerAuthor?
    let zhihuAnswerVoteupCount: Int?
    let zhihuAnswerCommentCount: Int?
    enum CodingKeys: String, CodingKey {
        case metrics, lang, urls
        case photoCredit = "photo_credit"
        case zhihuRank = "zhihu_rank"
        case zhihuHeat = "zhihu_heat"
        case zhihuAnswers = "zhihu_answers"
        case zhihuFollowerCount = "zhihu_follower_count"
        case zhihuQuestionID = "zhihu_question_id"
        case zhihuURL = "zhihu_url"
        case zhihuAnswerExcerpt = "zhihu_answer_excerpt"
        case zhihuAnswerContent = "zhihu_answer_content"
        case zhihuAnswerAuthor = "zhihu_answer_author"
        case zhihuAnswerVoteupCount = "zhihu_answer_voteup_count"
        case zhihuAnswerCommentCount = "zhihu_answer_comment_count"
    }
}

struct ZhihuAnswerAuthor: Decodable, Hashable {
    let name, headline, avatarURL: String?
    enum CodingKeys: String, CodingKey {
        case name, headline
        case avatarURL = "avatar_url"
    }
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
struct PostImage: Decodable, Hashable {
    let url: String
    let width, height: Int?
    let altText: String?
    enum CodingKeys: String, CodingKey {
        case url, width, height
        case altText = "alt_text"
    }
}
struct PostVideo: Decodable, Hashable {
    let url, playURL, coverURL, previewImageURL, preview: String?
    enum CodingKeys: String, CodingKey {
        case url, preview
        case playURL = "play_url"
        case coverURL = "cover_url"
        case previewImageURL = "preview_image_url"
    }
}

enum MediaURL {
    private static let imageHostSuffixes = ["twimg.com", "hdslb.com", "biliimg.com", "sinaimg.cn", "sina.com.cn", "ytimg.com", "ggpht.com", "truthsocial.com", "nyt.com", "nytimes.com"]

    static func image(_ raw: String) -> URL? { resolved(raw, proxy: "image-proxy", hosts: imageHostSuffixes) }
    static func video(_ raw: String) -> URL? {
        let value = raw.hasPrefix("//") ? "https:\(raw)" : raw
        guard let direct = URL(string: value, relativeTo: ServerConfiguration.currentURL)?.absoluteURL else { return nil }
        if isBilibiliVideoPage(direct) {
            var parts = URLComponents(url: ServerConfiguration.currentURL.appending(path: "api/v1/bilibili/play"), resolvingAgainstBaseURL: false)
            parts?.queryItems = [.init(name: "url", value: direct.absoluteString)]
            return parts?.url
        }
        return resolved(value, proxy: "media-proxy", hosts: ["video.twimg.com", "truthsocial.com"])
    }

    private static func isBilibiliVideoPage(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), host == "bilibili.com" || host.hasSuffix(".bilibili.com") else { return false }
        return url.pathComponents.contains { $0.range(of: #"^BV[0-9A-Za-z]{10}$"#, options: .regularExpression) != nil }
    }

    private static func resolved(_ raw: String, proxy: String, hosts: [String]) -> URL? {
        let value = raw.hasPrefix("//") ? "https:\(raw)" : raw
        guard let direct = URL(string: value, relativeTo: ServerConfiguration.currentURL)?.absoluteURL else { return nil }
        guard let host = direct.host?.lowercased(), hosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else { return direct }
        var parts = URLComponents(url: ServerConfiguration.currentURL.appending(path: "api/v1/\(proxy)"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [.init(name: "url", value: direct.absoluteString), .init(name: "soft", value: "1"), .init(name: "context", value: "ios-feed")]
        return parts?.url
    }
}

extension Int {
    var formattedFeedCount: String {
        switch self {
        case 10_000...:
            return (Double(self) / 10_000).formatted(.number.precision(.fractionLength(1))) + "万"
        default:
            return formatted()
        }
    }
}

enum FeedSource: String, CaseIterable, Identifiable {
    case newYorkTimes = "rss:47"
    case x, weibo
    case douyin = "douyin-hot"
    case bilibili, zhihu, truth, rss, laozhong, youtube, flash

    var id: String { rawValue }
    var title: String {
        switch self {
        case .newYorkTimes: "纽约时报"
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
