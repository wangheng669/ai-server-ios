import Foundation
import CryptoKit

struct XueqiuTextLink: Equatable {
    let label: String
    let url: URL
}

struct XueqiuPresentation {
    let bodyContent: String
    let bodyLinks: [XueqiuTextLink]
    let bodyInlineEmojis: [WeiboInlineEmoji]
    let standaloneInlineEmoji: WeiboInlineEmoji?
    let bodyImageURLs: [URL]
    let quoteContent: String?
    let quoteAuthor: String?
    let quoteBody: String?
    let quoteLinks: [XueqiuTextLink]
    let quoteImageURLs: [URL]
    let unplacedImageURLs: [URL]
    let stockTag: String?
}

private final class XueqiuPresentationBox: NSObject {
    let value: XueqiuPresentation
    private let title: String?
    private let text: String?
    private let summary: String?
    private let content: String?
    private let contentZH: String?
    private let images: [PostImage]?

    init(post: Post, value: XueqiuPresentation) {
        self.value = value
        title = post.title
        text = post.text
        summary = post.summary
        content = post.content
        contentZH = post.contentZH
        images = post.images
    }

    func matches(_ post: Post) -> Bool {
        title == post.title
            && text == post.text
            && summary == post.summary
            && content == post.content
            && contentZH == post.contentZH
            && images == post.images
    }
}

private final class RSSInlineAssetURLsBox: NSObject {
    let content: String
    let value: Set<URL>

    init(content: String, value: Set<URL>) {
        self.content = content
        self.value = value
    }
}

struct PostListResponse: Decodable { let data: [Post] }

struct XFeedUser: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let screenName: String
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, name
        case screenName = "screen_name"
        case avatarURL = "avatar_url"
    }
}

struct XFeedUsersResponse: Decodable {
    let data: [XFeedUser]
}
struct RSSFeedPostsResponse: Decodable {
    let data: Payload
    struct Payload: Decodable { let posts: [Post] }
}
struct RSSFeedsResponse: Decodable {
    let data: Payload
    let meta: Meta?
    struct Payload: Decodable { let feeds: [RSSFeedSource] }
    struct Meta: Decodable {
        let pagination: Pagination?
        struct Pagination: Decodable {
            let page: Int
            let size: Int
            let total: Int
        }
    }
}

struct RSSFeedSource: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let feedURL: String?
    let icon: String?
    let avatar: String?
    let avatarStatus: String?
    let updatedAt: String?
    let isEnabled: Bool
    let foloMeta: FoloMeta?

    struct FoloMeta: Decodable, Equatable {
        let rawFeedURL: String?

        enum CodingKeys: String, CodingKey {
            case rawFeedURL = "raw_feed_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon
        case feedURL = "feed_url"
        case avatar = "avatar_url"
        case avatarStatus = "avatar_status"
        case updatedAt = "updated_at"
        case isEnabled = "is_enabled"
        case foloMeta = "folo_meta"
    }

    var isWeiboFeed: Bool {
        [feedURL, foloMeta?.rawFeedURL]
            .compactMap { $0?.lowercased() }
            .contains { value in
                value.range(of: #"(?:^|/)weibo/user/\d+(?:/|$)"#, options: .regularExpression) != nil
            }
    }

    var iconURL: URL? {
        guard let icon, !icon.isEmpty else { return nil }
        guard let resolved = URL(string: icon, relativeTo: ServerConfiguration.currentURL)?.absoluteURL else { return nil }
        guard icon.hasPrefix("/img/rss-feed-icons/"), let updatedAt, !updatedAt.isEmpty,
              var parts = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else { return resolved }
        parts.queryItems = (parts.queryItems ?? []) + [.init(name: "v", value: updatedAt)]
        return parts.url
    }

    var preferredAvatarURL: URL? {
        guard avatarStatus?.lowercased() != "fallback" else { return nil }
        if let avatar, !avatar.isEmpty,
           let url = URL(string: avatar, relativeTo: ServerConfiguration.currentURL)?.absoluteURL {
            return url
        }
        return iconURL
    }

    var hasManagedAvatar: Bool {
        guard let avatar, !avatar.isEmpty,
              let url = URL(string: avatar, relativeTo: ServerConfiguration.currentURL)?.absoluteURL else {
            return false
        }
        return url.path.hasSuffix("/avatar")
    }
}
struct PostDetailResponse: Decodable { let post: Post }

struct WeiboInlineEmoji: Hashable {
    let token: String
    let url: URL
}

enum RSSArticleBlock: Hashable {
    case paragraph(text: String, emojis: [WeiboInlineEmoji])
    case image(URL)
}

enum QbitAIArticleParser {
    static func extractBodyHTML(from html: String) -> String? {
        guard let articleStart = html.range(
            of: #"<div\b[^>]*\bclass\s*=\s*[\"'][^\"']*\barticle\b[^\"']*[\"'][^>]*>"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }

        let articleRemainder = String(html[articleStart.upperBound...])
        let endMarkers = ["<!--版权声明-->", "<div class=\"line_font\"", "<div class='line_font'"]
        let end = endMarkers.compactMap {
            articleRemainder.range(of: $0, options: .caseInsensitive)?.lowerBound
        }.min() ?? articleRemainder.endIndex
        var body = String(articleRemainder[..<end])

        let chromePatterns = [
            #"<h1\b[^>]*>[\s\S]*?</h1>"#,
            #"<div\b[^>]*\bclass\s*=\s*[\"'][^\"']*\barticle_info\b[^\"']*[\"'][^>]*>[\s\S]*?</div>"#,
            #"<div\b[^>]*\bclass\s*=\s*[\"'][^\"']*\bzhaiyao\b[^\"']*[\"'][^>]*>[\s\S]*?</div>"#,
        ]
        for pattern in chromePatterns {
            body = body.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }
}

struct XCommentsResponse: Decodable {
    let success: Bool
    let data: Payload

    struct Payload: Decodable {
        let items: [XComment]
        let nextCursor: String?
    }
}

struct WeiboCommentsResponse: Decodable {
    let success: Bool
    let data: Payload

    struct Payload: Decodable, Equatable {
        let items: [WeiboComment]
        let commentCount: Int?
    }
}

struct WeiboComment: Decodable, Identifiable, Equatable {
    let commentID: String
    let text: String
    let createdAt: String?
    let likeCount: Int?
    let replyCount: Int?
    let authorName: String
    let authorAvatar: String?
    let replyToAuthorName: String?
    let replies: [WeiboComment]

    var id: String { commentID }
    var avatarURL: URL? { authorAvatar.flatMap(MediaURL.image) }

    enum CodingKeys: String, CodingKey {
        case text, createdAt, likeCount, replyCount, authorName, authorAvatar, replyToAuthorName, replies
        case commentID = "commentId"
    }
}

struct XTweetDetailResponse: Decodable {
    let success: Bool
    let data: Payload

    struct Payload: Decodable {
        let item: XTweetDetailItem
    }
}

struct XTweetDetailItem: Decodable, Equatable {
    let id: String
    let text: String
    let noteText: String?
    let shortText: String?
    let author: Author?
    let media: [Media]?
    let createdAt: String?
    let metrics: PostMetrics?
    let lang: String?

    struct Author: Decodable, Equatable {
        let name: String?
        let screenName: String?
        let profileImageURL: String?
        let verified: Bool?

        enum CodingKeys: String, CodingKey {
            case name, screenName, verified
            case profileImageURL = "profileImageUrl"
        }
    }

    struct Media: Decodable, Equatable {
        let type: String?
        let url: String?
        let thumbnailURL: String?
        let width: Int?
        let height: Int?

        enum CodingKeys: String, CodingKey {
            case type, url, width, height
            case thumbnailURL = "thumbnail_url"
        }

        var isVideo: Bool {
            ["video", "animated_gif", "gif"].contains(type?.lowercased() ?? "")
        }

        var displayURL: URL? {
            (thumbnailURL ?? url).flatMap(MediaURL.image)
        }
    }

    var fullText: String {
        [noteText, text, shortText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .max(by: { $0.count < $1.count }) ?? text
    }

    var videoMedia: Media? {
        media?.first(where: \.isVideo)
    }

    var videoURL: URL? {
        videoMedia?.url.flatMap(MediaURL.video)
    }

    var directVideoURL: URL? {
        videoMedia?.url.flatMap(MediaURL.directVideo)
    }

    var videoPreviewURL: URL? {
        videoMedia?.thumbnailURL.flatMap(MediaURL.image)
    }

    var imageMedia: [Media] {
        (media ?? []).filter { !$0.isVideo && $0.displayURL != nil }
    }

    var imageURLs: [URL] {
        imageMedia.compactMap(\.displayURL)
    }
}

enum XPostTextFormatter {
    static func commentText(_ text: String, replyingTo screenName: String?) -> String {
        guard let screenName = screenName?
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .nilIfEmpty else { return text }
        return text.replacingOccurrences(
            of: "^@\(NSRegularExpression.escapedPattern(for: screenName))\\s*",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    static func shouldWaitForFullText(_ value: String) -> Bool {
        isTruncated(detailText(value))
    }

    static func shouldShowExternalURL(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return !["t.co", "x.com", "twitter.com", "www.x.com", "www.twitter.com"].contains(host)
    }

    static func longestText(_ values: String?...) -> String? {
        values
            .compactMap { value in
                value?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
            }
            .max(by: { $0.count < $1.count })
    }

    static func detailText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(
                of: #"[ \t]+\*(?=\S)"#,
                with: "\n• ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(^|\n)[ \t]*\*(?=\S)"#,
                with: "$1• ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func paragraphs(_ value: String) -> [String] {
        detailText(value)
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func isTruncated(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("…") || trimmed.hasSuffix("...")
    }

    static func containsUntranslatedEnglishPassage(_ value: String) -> Bool {
        let pattern = #"(?i)(?:\b[a-z][a-z'’.-]*\b(?:\s+|[,;:()]+\s*)){8,}\b[a-z][a-z'’.-]*\b"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    static func shouldPreferFullOriginal(displayed: String, fullOriginal: String) -> Bool {
        let displayed = detailText(displayed)
        let fullOriginal = detailText(fullOriginal)
        return isTruncated(displayed)
            && !isTruncated(fullOriginal)
            && fullOriginal.count > displayed.count
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
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
        let bookmarks, likes, quotes, replies, retweets, views: Int?
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

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let text = try? container.decodeIfPresent(String.self, forKey: .heat) {
                heat = text
            } else if let number = try? container.decode(Double.self, forKey: .heat) {
                heat = String(Int(number))
            } else {
                heat = nil
            }
            hotValue = try? container.decodeIfPresent(Double.self, forKey: .hotValue)
        }
    }
    enum CodingKeys: String, CodingKey {
        case id, keyword, summary, reason, meta
        case searchLink = "search_link"
        case latestRank = "latest_rank"
        case latestHeat = "latest_heat"
        case rankChange = "rank_change"
    }

    var resolvedHeat: Double? {
        latestHeat
            ?? meta?.lastPayload?.hotValue
            ?? meta?.lastPayload?.heat.flatMap(Double.init)
    }
}

struct FlashResponse: Decodable {
    let success: Bool
    let data: DataPayload
    struct DataPayload: Decodable { let items: [FlashItem]; let hasMore: Bool? }
}

struct FlashItem: Decodable {
    let id, time, text, source, linkURL, avatarURL: String?
    let category: String?
    let isImportant: Bool?
    let finalScore: Double?
    let similarityGroupId: Int64?
    let similarityScore: Double?
    let similarCount: Int?
    let platformCount: Int?
    let platforms: [String]?
    enum CodingKeys: String, CodingKey {
        case id, time, text, source, category, isImportant, finalScore
        case similarityGroupId, similarityScore, similarCount, platformCount, platforms
        case linkURL = "linkUrl"
        case avatarURL = "avatarUrl"
    }
}

struct CategoryResponse: Decodable {
    let success: Bool
    let categories: [FeedCategory]
}
struct FeedCategory: Decodable { let id: Int; let name: String }

struct Post: Codable, Identifiable, Hashable {
    static let minimumFeedScore = 5
    static let importantFlashScore = 7.0
    private static let htmlTextCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 1_200
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()
    private static let xueqiuPresentationCache: NSCache<NSString, XueqiuPresentationBox> = {
        let cache = NSCache<NSString, XueqiuPresentationBox>()
        cache.countLimit = 800
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()
    private static let rssInlineAssetURLsCache: NSCache<NSString, RSSInlineAssetURLsBox> = {
        let cache = NSCache<NSString, RSSInlineAssetURLsBox>()
        cache.countLimit = 800
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()
    private static let htmlImageTagRegex = try! NSRegularExpression(
        pattern: #"<img\b[^>]*>"#,
        options: .caseInsensitive
    )
    private static let xueqiuTextLinkRegex = try! NSRegularExpression(
        pattern: #"<a\b[^>]*\bhref\s*=\s*([\"'])(.*?)\1[^>]*>(.*?)</a>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let xueqiuStockTagRegex = try! NSRegularExpression(pattern: #"\$[^$\n]{2,40}\$"#)
    private static let htmlAttributeRegexes: [String: NSRegularExpression] = Dictionary(
        uniqueKeysWithValues: ["src", "data-src", "data-original", "alt", "title", "href"].map { name in
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            return (name, try! NSRegularExpression(
                pattern: #"\b"# + escapedName + #"\s*=\s*[\"']([^\"']+)[\"']"#,
                options: .caseInsensitive
            ))
        }
    )
    private static let htmlNumericAttributeRegexes: [String: NSRegularExpression] = Dictionary(
        uniqueKeysWithValues: ["width", "height", "data-w", "data-h"].map { name in
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            return (name, try! NSRegularExpression(
                pattern: #"\b"# + escapedName + #"\s*=\s*[\"']?(\d+)"#,
                options: .caseInsensitive
            ))
        }
    )
    private static let numericHTMLEntityRegex = try! NSRegularExpression(
        pattern: #"&#(?:x([0-9A-Fa-f]+)|([0-9]+));"#
    )

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
    // Runtime-only card translations. The backend payload and offline cache remain unchanged.
    var rssTitleZH: String? = nil
    var rssExcerptZH: String? = nil
    // Runtime-only translation for an embedded quoted X post.
    var xQuotedTextZH: String? = nil
    // Runtime-only reply context loaded or translated after the feed payload arrives.
    var xReplyContextOverride: XReplyContext? = nil
    // Runtime-only attribution retained when an X repost wrapper is replaced by its live original.
    var xReposterName: String? = nil

    var displayTitle: String {
        clean(rssTitleZH)
            ?? rssServerLocalizedTitle
            ?? clean(contentZH)
            ?? clean(title)
            ?? clean(summary)
            ?? clean(text)
            ?? "无标题"
    }
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
    var bilibiliListContent: String {
        let body = displayContent
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = bilibiliTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body != title else { return title }
        if body.count < 24 { return title }
        if body.localizedCaseInsensitiveContains(title) { return body }
        return title + "\n" + body
    }
    var displaySummary: String? {
        let value = clean(summary) ?? clean(text)
        return value == displayTitle ? nil : value
    }
    var newYorkTimesFeedExcerpt: String {
        let raw = clean(summary) ?? clean(text) ?? clean(contentZH) ?? clean(content) ?? displayTitle
        let boundedRaw = String(raw.prefix(600))
        let normalized = (htmlText(boundedRaw) ?? boundedRaw)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = String(normalized.prefix(280))
        return excerpt + (normalized.count > excerpt.count || raw.count > boundedRaw.count ? "…" : "")
    }
    var newYorkTimesLead: String? {
        guard var lead = clean(summary)?
            .split(separator: "<", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !lead.isEmpty else { return nil }
        let credits = ([meta?.photoCredit] + (images ?? []).map(\.altText))
            .compactMap { clean($0) }
            .sorted { $0.count > $1.count }
        for credit in credits {
            if lead.localizedCaseInsensitiveCompare(credit) == .orderedSame { return nil }
            guard lead.lowercased().hasSuffix(credit.lowercased()) else { continue }
            lead.removeLast(credit.count)
            lead = lead.trimmingCharacters(
                in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "·•|—-"))
            )
            break
        }
        return lead.isEmpty ? nil : lead
    }
    var displayContent: String { htmlText(contentZH) ?? originalDisplayContent }
    var originalDisplayContent: String { htmlText(content) ?? clean(text) ?? clean(summary) ?? displayTitle }
    var xStoredOriginalContent: String {
        [meta?.noteText, meta?.rawText, isChineseXSource ? contentZH : nil, originalDisplayContent]
            .compactMap(clean)
            .max(by: { $0.count < $1.count }) ?? originalDisplayContent
    }
    var isChineseXSource: Bool {
        sourceName == "X" && meta?.lang?.lowercased().hasPrefix("zh") == true
    }
    var hasTranslation: Bool { clean(contentZH) != nil && clean(contentZH) != clean(content) }
    var needsXTranslation: Bool {
        guard sourceName == "X", xTweetID != nil else { return false }
        let language = meta?.lang?.lowercased()
        guard language?.hasPrefix("zh") != true else { return false }
        guard language != nil || !Self.containsHanCharacters(xStoredOriginalContent) else { return false }
        guard hasTranslation else { return true }
        let translation = displayContent
        if XPostTextFormatter.isTruncated(translation) { return true }
        if XPostTextFormatter.containsUntranslatedEnglishPassage(translation) { return true }
        return xStoredOriginalContent.count >= 600
            && XPostTextFormatter.paragraphs(xStoredOriginalContent).count >= 3
            && XPostTextFormatter.paragraphs(translation).count == 1
    }
    var needsXLiveDetail: Bool {
        sourceName == "X"
            && xTweetID != nil
            && XPostTextFormatter.shouldWaitForFullText(xStoredOriginalContent)
    }
    var needsXStoredDetailRefresh: Bool {
        needsXLiveDetail || needsXTranslation || needsXReplyContextRefresh
    }
    var needsXReplyContextRefresh: Bool {
        sourceName == "X"
            && clean(meta?.inReplyToStatusID) != nil
            && meta?.replyContext?.displayText == nil
    }

    var needsXReplyContextTranslation: Bool {
        guard sourceName == "X",
              clean(meta?.inReplyToStatusID) != nil,
              let reply = meta?.replyContext,
              xNonempty(reply.textZH) == nil,
              let original = xNonempty(reply.text) else { return false }
        return !Self.containsHanCharacters(original)
    }

    var xReplyContext: XReplyContext? {
        xReplyContextOverride ?? meta?.replyContext
    }

    func replacingXReplyContext(with reply: XReplyContext) -> Post {
        var replaced = self
        replaced.xReplyContextOverride = reply
        return replaced
    }

    var isXRetweetWrapper: Bool {
        guard sourceName == "X" else { return false }
        return originalDisplayContent.range(
            of: #"^\s*RT\s+@[A-Za-z0-9_]{1,15}\s*:"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    var xRepostAttributionText: String? {
        clean(xReposterName).map { "\($0) 已转帖" }
    }

    var xQuotedPost: XQuotedPost? {
        guard sourceName == "X", var quote = meta?.quotedTweet else { return nil }
        if let xQuotedTextZH { quote.textZH = xQuotedTextZH }
        return quote
    }

    var needsXQuotedTranslation: Bool {
        guard sourceName == "X",
              let quote = meta?.quotedTweet,
              xNonempty(quote.id) != nil,
              let original = quote.originalText,
              xNonempty(quote.textZH) == nil else { return false }
        return !Self.containsHanCharacters(original)
    }

    func replacingXQuotedTranslation(with translation: String) -> Post {
        var translated = self
        translated.xQuotedTextZH = translation
        return translated
    }

    func replacingTranslation(with translation: String) -> Post {
        var replaced = Post(
            id: id, title: title, text: text, summary: summary, content: content,
            contentZH: translation, source: source, formattedTime: formattedTime,
            weightReason: weightReason, finalScore: finalScore, weight: weight,
            postLink: postLink, articlePostAt: articlePostAt, user: user,
            postTags: postTags, images: images, videos: videos, feedRank: feedRank, meta: meta
        )
        replaced.xReposterName = xReposterName
        return replaced
    }

    func replacingXLiveDetail(with detail: XTweetDetailItem) -> Post {
        let liveImages = detail.imageMedia.compactMap { media -> PostImage? in
            guard let url = media.thumbnailURL ?? media.url else { return nil }
            return PostImage(url: url, width: media.width, height: media.height)
        }
        let liveVideos = (detail.media ?? []).filter(\.isVideo).compactMap { media -> PostVideo? in
            guard let url = media.url else { return nil }
            return PostVideo(
                url: url,
                playURL: url,
                coverURL: media.thumbnailURL,
                previewImageURL: media.thumbnailURL,
                preview: media.thumbnailURL,
                width: media.width,
                height: media.height
            )
        }
        let liveAuthor = detail.author.map { author in
            PostUser(
                userID: user?.userID,
                personID: user?.personID,
                userName: author.name,
                userScreenName: author.screenName,
                avatarURL: author.profileImageURL,
                userDesc: user?.userDesc,
                platform: user?.platform,
                verified: author.verified,
                verifiedType: user?.verifiedType
            )
        } ?? user

        var replaced = Post(
            id: id, title: title, text: text, summary: summary, content: detail.fullText,
            contentZH: contentZH, source: source, formattedTime: formattedTime,
            weightReason: weightReason, finalScore: finalScore, weight: weight,
            postLink: postLink, articlePostAt: articlePostAt, user: liveAuthor,
            postTags: postTags,
            images: liveImages.isEmpty ? images : liveImages,
            videos: liveVideos.isEmpty ? videos : liveVideos,
            feedRank: feedRank,
            meta: meta?.replacingXLiveDetail(with: detail)
                ?? PostMeta.xLiveDetail(detail)
        )
        replaced.xReposterName = xReposterName ?? (isXRetweetWrapper ? authorName : nil)
        return replaced
    }
    func replacingRSSCardTranslation(title: String, excerpt: String?) -> Post {
        var translated = self
        translated.rssTitleZH = clean(title)
        translated.rssExcerptZH = clean(excerpt)
        return translated
    }

    var needsRSSCardTranslation: Bool {
        guard isRSS, clean(rssTitleZH) == nil, rssServerLocalizedTitle == nil, clean(contentZH) == nil,
              let title = rssTranslationTitle else { return false }
        return !Self.containsHanCharacters(title)
    }

    /// The RSS localization pipeline stores its Chinese card headline in `summary`.
    /// Prefer it immediately when the source title is still English.
    var rssServerLocalizedTitle: String? {
        guard isRSS,
              let title = clean(title),
              !Self.containsHanCharacters(title),
              let summary = clean(summary),
              Self.containsHanCharacters(summary) else { return nil }
        let normalized = (htmlText(summary) ?? summary)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    var rssTranslationTitle: String? {
        clean(title) ?? clean(summary) ?? clean(text)
    }

    var rssTranslationExcerpt: String? {
        let raw = clean(summary) ?? clean(text) ?? clean(content)
        guard let raw else { return nil }
        let normalized = (htmlText(String(raw.prefix(700))) ?? String(raw.prefix(700)))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !Self.isRSSPlaceholder(normalized) else { return nil }
        let excerpt = String(normalized.prefix(420))
        return excerpt + (normalized.count > excerpt.count || raw.count > 700 ? "…" : "")
    }

    private static func containsHanCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { (0x4E00...0x9FFF).contains(Int($0.value)) }
    }

    private static func isRSSPlaceholder(_ value: String) -> Bool {
        let normalized = value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return ["in this article", "comments", "comment"].contains(normalized)
    }
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
    var authorName: String {
        if isRSS,
           let storedName = clean(user?.userName),
           URL(string: storedName)?.scheme != nil {
            return clean(user?.userScreenName) ?? clean(meta?.rssFeedName) ?? sourceName
        }
        return user?.resolvedCanonicalName ?? clean(user?.userName) ?? clean(user?.userScreenName) ?? sourceName
    }
    var rssCardSourceName: String {
        guard isRSS else { return authorName }
        return clean(meta?.rssFeedName) ?? clean(user?.userScreenName) ?? authorName
    }
    var rssCardAvatarURL: URL? {
        guard isRSS,
              let rawSource = source?.lowercased(),
              rawSource.hasPrefix("rss:"),
              let feedID = Int(rawSource.dropFirst(4)),
              let feedName = clean(meta?.rssFeedName),
              let icon = clean(meta?.rssFeedIcon) else { return avatarURL }
        let identity = "\(feedID)\0\(feedName)\0\(icon)"
        let digest = SHA256.hash(data: Data(identity.utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
        return URL(
            string: "/api/ios/v1/rss/feeds/\(feedID)/avatar?v=\(digest)",
            relativeTo: ServerConfiguration.currentURL
        )?.absoluteURL
    }
    var authorHandle: String? {
        if let accountLabel = user?.resolvedAccountLabel {
            return accountLabel
        }
        guard let handle = clean(user?.userScreenName), handle != authorName else { return nil }
        return handle.hasPrefix("@") ? handle : "@\(handle)"
    }
    var sourceName: String {
        let value = (source ?? "").lowercased()
        if isXueqiu { return "雪球" }
        if isBilibili { return "B站" }
        if value.hasPrefix("rss:") { return "RSS" }
        if value.contains("weibo") { return "微博" }
        if value.contains("douyin") { return "抖音" }
        if value.contains("zhihu") { return "知乎" }
        if value.contains("truth") { return "Truth" }
        if value == "flash" { return "快讯" }
        if value.hasPrefix("x") || value.contains("twitter") { return "X" }
        return value.isEmpty ? "信息流" : value
    }
    var normalizedSource: String { sourceName }
    var isXueqiu: Bool {
        meta?.rssFeedName?.contains("雪球") == true ||
        meta?.rssArticleLink?.localizedCaseInsensitiveContains("xueqiu.com") == true ||
        linkURL?.host()?.localizedCaseInsensitiveContains("xueqiu.com") == true
    }
    var xueqiuPresentation: XueqiuPresentation {
        let cacheKey = NSString(string: String(id))
        if let cached = Self.xueqiuPresentationCache.object(forKey: cacheKey), cached.matches(self) {
            return cached.value
        }

        let raw = clean(content)
        let quoteStart = raw?.range(of: "<blockquote", options: .caseInsensitive)
        let bodyHTML = raw.map { value in
            quoteStart.map { String(value[..<$0.lowerBound]) } ?? value
        }
        let quoteHTML = raw.flatMap { value in
            quoteStart.map { String(value[$0.lowerBound...]) }
        }

        let bodyContent: String
        if quoteStart != nil {
            bodyContent = xueqiuText(bodyHTML) ?? ""
        } else {
            bodyContent = xueqiuText(content) ?? displayContent
        }
        let bodyLinks = bodyHTML.map(xueqiuTextLinks) ?? []
        let quoteContent = quoteHTML.flatMap(xueqiuText)
        let quoteLinks = quoteHTML.map(xueqiuTextLinks) ?? []

        let serverEmojis = (images ?? []).compactMap { image -> WeiboInlineEmoji? in
            guard image.isKnownInlineAsset,
                  let token = clean(image.altText),
                  let url = MediaURL.image(image.url) else { return nil }
            return .init(token: token, url: url)
        }
        let bodyInlineEmojis = serverEmojis.isEmpty
            ? bodyHTML.map { inlineEmojis(in: [$0]) } ?? []
            : serverEmojis
        let standaloneInlineEmoji = bodyInlineEmojis.count == 1
            && bodyContent.trimmingCharacters(in: .whitespacesAndNewlines) == bodyInlineEmojis[0].token
            ? bodyInlineEmojis[0]
            : nil

        let quoteSeparator = quoteContent?.firstIndex(where: { $0 == ":" || $0 == "：" })
        let quoteAuthor = quoteContent.flatMap { quote -> String? in
            guard let quoteSeparator else { return nil }
            let author = quote[..<quoteSeparator].trimmingCharacters(in: .whitespacesAndNewlines)
            return author.isEmpty ? nil : author
        }
        let quoteBody = quoteContent.flatMap { quote -> String? in
            guard let quoteSeparator else { return quote }
            let body = quote[quote.index(after: quoteSeparator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : body
        }
        let bodyImageURLs = bodyHTML.map(xueqiuImageURLs) ?? []
        let quoteImageURLs = quoteHTML.map(xueqiuImageURLs) ?? []
        let placedImageURLs = Set(bodyImageURLs + quoteImageURLs)
        let unplacedImageURLs = imageURLs.filter { !placedImageURLs.contains($0) }
        let renderedContent = displayContent
        let renderedContentSource = renderedContent as NSString
        let stockTag = Self.xueqiuStockTagRegex
            .firstMatch(
                in: renderedContent,
                range: NSRange(location: 0, length: renderedContentSource.length)
            )
            .map { renderedContentSource.substring(with: $0.range) }

        let presentation = XueqiuPresentation(
            bodyContent: bodyContent,
            bodyLinks: bodyLinks,
            bodyInlineEmojis: bodyInlineEmojis,
            standaloneInlineEmoji: standaloneInlineEmoji,
            bodyImageURLs: bodyImageURLs,
            quoteContent: quoteContent,
            quoteAuthor: quoteAuthor,
            quoteBody: quoteBody,
            quoteLinks: quoteLinks,
            quoteImageURLs: quoteImageURLs,
            unplacedImageURLs: unplacedImageURLs,
            stockTag: stockTag
        )
        let estimatedCost = bodyContent.utf8.count
            + (quoteContent?.utf8.count ?? 0)
            + (bodyLinks.count + quoteLinks.count) * 96
            + (bodyImageURLs.count + quoteImageURLs.count + unplacedImageURLs.count) * 128
        Self.xueqiuPresentationCache.setObject(
            XueqiuPresentationBox(post: self, value: presentation),
            forKey: cacheKey,
            cost: max(1, estimatedCost)
        )
        return presentation
    }
    var xueqiuBodyContent: String {
        xueqiuPresentation.bodyContent
    }
    var xueqiuBodyLinks: [XueqiuTextLink] {
        xueqiuPresentation.bodyLinks
    }
    var xueqiuQuoteContent: String? {
        xueqiuPresentation.quoteContent
    }
    var xueqiuQuoteLinks: [XueqiuTextLink] {
        xueqiuPresentation.quoteLinks
    }
    var xueqiuBodyInlineEmojis: [WeiboInlineEmoji] {
        xueqiuPresentation.bodyInlineEmojis
    }
    var xueqiuStandaloneInlineEmoji: WeiboInlineEmoji? {
        xueqiuPresentation.standaloneInlineEmoji
    }
    var xueqiuQuoteAuthor: String? {
        xueqiuPresentation.quoteAuthor
    }
    var xueqiuQuoteBody: String? {
        xueqiuPresentation.quoteBody
    }
    var xueqiuBodyImageURLs: [URL] {
        xueqiuPresentation.bodyImageURLs
    }
    var xueqiuQuoteImageURLs: [URL] {
        xueqiuPresentation.quoteImageURLs
    }
    var xueqiuUnplacedImageURLs: [URL] {
        xueqiuPresentation.unplacedImageURLs
    }
    var xueqiuStockTag: String? {
        xueqiuPresentation.stockTag
    }
    var hasXueqiuFeedMedia: Bool {
        (images ?? []).contains { image in
            let value = image.url.lowercased()
            return !value.contains("/face/") &&
                !value.contains("emoji_") &&
                !value.contains("emoticon")
        } || !(videos ?? []).isEmpty
    }
    var score: Double? { finalScore ?? weight }
    var imageURLs: [URL] {
        feedContentImages.compactMap { MediaURL.image($0.url) }
    }
    var feedImageURLs: [URL] {
        let variant = feedContentImages.count == 1 ? "medium" : "small"
        return feedContentImages.compactMap { MediaURL.feedImage($0.url, variant: variant) }
    }
    private var feedContentImages: [PostImage] {
        (images ?? [])
            .filter { !$0.isKnownInlineAsset }
    }
    var originalImageURLs: [URL] {
        imageURLs
    }

    private func xueqiuImageURLs(in html: String) -> [URL] {
        var seen = Set<URL>()
        return htmlImageTags(in: html).compactMap { tag in
            guard let rawURL = htmlAttribute("src", in: tag),
                  let url = MediaURL.image(rawURL),
                  seen.insert(url).inserted else { return nil }
            return url
        }
    }

    private func xueqiuTextLinks(in html: String) -> [XueqiuTextLink] {
        let source = html as NSString
        return Self.xueqiuTextLinkRegex
            .matches(in: html, range: NSRange(location: 0, length: source.length))
            .compactMap { match in
            guard match.numberOfRanges == 4 else { return nil }
            let href = source.substring(with: match.range(at: 2))
                .replacingOccurrences(of: "&amp;", with: "&")
            let labelHTML = source.substring(with: match.range(at: 3))
            guard let label = xueqiuText(labelHTML),
                  let url = URL(string: href, relativeTo: URL(string: "https://xueqiu.com"))?.absoluteURL,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return XueqiuTextLink(label: label, url: url)
        }
    }
    var rssArticleBlocks: [RSSArticleBlock] {
        rssArticleBlocks(overridingContent: nil)
    }

    func rssArticleBlocks(overridingContent: String?) -> [RSSArticleBlock] {
        let preferredContent = clean(overridingContent) ?? clean(contentZH) ?? clean(content)
        guard let preferredContent else {
            return [.paragraph(text: displayContent, emojis: [])]
        }

        let source = preferredContent as NSString
        let matches = Self.htmlImageTagRegex.matches(
            in: preferredContent,
            range: NSRange(location: 0, length: source.length)
        )
        var blocks: [RSSArticleBlock] = []
        var pendingHTML = ""
        var pendingEmojis: [WeiboInlineEmoji] = []
        var cursor = 0

        func appendHTML(_ range: NSRange) {
            guard range.length > 0 else { return }
            pendingHTML += source.substring(with: range)
        }

        func flushParagraphs() {
            let text = htmlText(pendingHTML)?
                .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let text, !text.isEmpty {
                let paragraphs = text.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                for paragraph in paragraphs {
                    let emojis = pendingEmojis.filter { paragraph.contains($0.token) }
                    let remainingText = emojis.reduce(paragraph) { text, emoji in
                        text.replacingOccurrences(of: emoji.token, with: "")
                    }.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !emojis.isEmpty,
                       remainingText.isEmpty,
                       case .paragraph(let previousText, let previousEmojis) = blocks.last {
                        blocks[blocks.count - 1] = .paragraph(
                            text: previousText + paragraph,
                            emojis: previousEmojis + emojis
                        )
                    } else {
                        blocks.append(.paragraph(text: paragraph, emojis: emojis))
                    }
                }
            }
            pendingHTML = ""
            pendingEmojis = []
        }

        for match in matches {
            appendHTML(NSRange(location: cursor, length: match.range.location - cursor))
            let tag = source.substring(with: match.range)
            if let rawURL = rssImageSource(in: tag),
               let url = MediaURL.image(rawURL.replacingOccurrences(of: "&amp;", with: "&")) {
                if isIgnoredRSSImageTag(tag, rawURL: rawURL) {
                    // Tracking pixels, favicons and badges are not article content.
                } else if (
                    tag.localizedCaseInsensitiveContains("wxw-img")
                        && tag.localizedCaseInsensitiveContains("display:inline")
                ) || isInlineEmojiTag(tag, rawURL: rawURL) {
                    let token = htmlAttribute("alt", in: tag)
                        ?? htmlAttribute("title", in: tag)
                        ?? "[表情]"
                    pendingHTML += token
                    pendingEmojis.append(.init(token: token, url: url))
                } else {
                    flushParagraphs()
                    blocks.append(.image(url))
                }
            }
            cursor = NSMaxRange(match.range)
        }
        appendHTML(NSRange(location: cursor, length: source.length - cursor))
        flushParagraphs()

        if !blocks.contains(where: { if case .image = $0 { true } else { false } }) {
            blocks.insert(
                contentsOf: imageURLs.map(RSSArticleBlock.image),
                at: 0
            )
        }

        return blocks.isEmpty ? [.paragraph(text: displayContent, emojis: [])] : blocks
    }

    var rssListContent: String {
        if clean(rssExcerptZH) == nil, rssServerLocalizedTitle != nil {
            return displayTitle
        }
        let value = clean(rssExcerptZH)
            ?? htmlTextPreservingRSSInlineEmoji(contentZH)
            ?? htmlTextPreservingRSSInlineEmoji(content)
            ?? displayContent
        let normalized = value.replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
        return Self.isRSSPlaceholder(normalized) ? displayTitle : normalized
    }

    private func isInlineEmojiTag(_ tag: String, rawURL: String) -> Bool {
        var decodedURL = rawURL
        for _ in 0..<2 {
            guard let decoded = decodedURL.removingPercentEncoding, decoded != decodedURL else { break }
            decodedURL = decoded
        }
        let value = "\(tag) \(decodedURL)".lowercased()
        return value.contains("wp-smiley")
            || value.contains("class=\"emoji")
            || value.contains("class='emoji")
            || value.contains("emoticon")
            || value.contains("/we-emoji/")
            || value.contains("/images/core/emoji/")
            || value.contains("/images/emoji/")
            || value.contains("/face/emoji_")
            || value.contains("/twemoji/")
            || value.contains("height: 1em")
            || value.contains("height:1em")
            || (value.contains("wxw-img") && value.contains("data-w=\"20\""))
            || (value.contains("display:inline")
                && (htmlNumericAttribute("data-w", in: tag).map { $0 <= 64 } == true
                    || value.contains("width:20px")))
    }

    private func isIgnoredRSSImageTag(_ tag: String, rawURL: String) -> Bool {
        let value = "\(tag) \(rawURL)".lowercased()
        if value.contains("aria-hidden=\"true\"")
            || value.contains("aria-hidden='true'")
            || value.contains("rss-track")
            || value.contains("1px.")
            || value.contains("icons.duckduckgo.com/ip3/")
            || value.contains("img.shields.io/") {
            return true
        }
        let width = htmlNumericAttribute("width", in: tag)
        let height = htmlNumericAttribute("height", in: tag)
        return width.map { $0 <= 2 } == true && height.map { $0 <= 2 } == true
    }

    private func htmlNumericAttribute(_ name: String, in tag: String) -> Int? {
        let source = tag as NSString
        let regex = Self.htmlNumericAttributeRegexes[name] ?? {
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            return try! NSRegularExpression(
                pattern: #"\b"# + escapedName + #"\s*=\s*[\"']?(\d+)"#,
                options: .caseInsensitive
            )
        }()
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: source.length)),
           match.numberOfRanges > 1 else { return nil }
        return Int(source.substring(with: match.range(at: 1)))
    }

    private func htmlTextPreservingRSSInlineEmoji(_ input: String?) -> String? {
        guard var value = clean(input) else { return nil }
        let source = value as NSString
        for match in Self.htmlImageTagRegex.matches(
            in: value,
            range: NSRange(location: 0, length: source.length)
        ).reversed() {
            let tag = source.substring(with: match.range)
            let rawURL = rssImageSource(in: tag) ?? ""
            let replacement = isInlineEmojiTag(tag, rawURL: rawURL)
                ? (htmlAttribute("alt", in: tag) ?? htmlAttribute("title", in: tag) ?? "[表情]")
                : ""
            guard let range = Range(match.range, in: value) else { continue }
            value.replaceSubrange(range, with: replacement)
        }
        return htmlText(value)
    }

    private func rssImageSource(in tag: String) -> String? {
        htmlAttribute("src", in: tag)
            ?? htmlAttribute("data-src", in: tag)
            ?? htmlAttribute("data-original", in: tag)
    }
    var weiboFollowingImageURLs: [URL] {
        imageURLs.filter { url in
            let sourceURL: URL
            if url.path.hasSuffix("/image-proxy"),
               let rawSource = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "url" })?
                .value,
               let proxiedSource = URL(string: rawSource) {
                sourceURL = proxiedSource
            } else {
                sourceURL = url
            }
            guard sourceURL.host()?.lowercased() == "h5.sinaimg.cn" else { return true }
            let filename = sourceURL.lastPathComponent.lowercased()
            return filename != "timeline_card_small_video_default.png" &&
                filename != "timeline_card_small_web_default.png"
        }
    }
    var weiboDetailImageURLs: [URL] {
        guard !videoURLs.isEmpty else { return weiboFollowingImageURLs }
        let galleryURLs = Set((images ?? []).compactMap { image -> URL? in
            guard let width = image.width,
                  let height = image.height,
                  width > 0,
                  height > 0 else { return nil }
            return MediaURL.image(image.url)
        })
        return weiboFollowingImageURLs.filter(galleryURLs.contains)
    }
    func weiboImageAspectRatio(for url: URL) -> CGFloat? {
        guard let image = (images ?? []).first(where: { MediaURL.image($0.url) == url }),
              let width = image.width,
              let height = image.height,
              width > 0,
              height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }
    var isWeiboRSS: Bool {
        guard isRSS else { return false }
        let candidates = [postLink, meta?.rssArticleLink, meta?.rssFeedName, user?.userDesc]
            .compactMap { $0?.lowercased() }
        return candidates.contains { value in
            value.contains("weibo.com") || value.contains("weibo.cn") || value.contains("/weibo/user/")
        }
    }
    var weiboDetailContent: String {
        let value = weiboText(contentZH) ?? weiboText(content) ?? clean(text) ?? clean(summary) ?? displayContent
        let inlineTokens = Set(weiboInlineEmojis.map(\.token))
        var normalized = value
            .replacingOccurrences(of: "[图片]", with: "")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for (token, fallback) in Self.weiboEmojiFallbacks where !inlineTokens.contains(token) {
            normalized = normalized.replacingOccurrences(of: token, with: fallback)
        }
        return normalized
    }
    var weiboInlineEmojis: [WeiboInlineEmoji] {
        var result: [WeiboInlineEmoji] = []
        var seenTokens = Set<String>()

        for image in images ?? [] where image.isKnownInlineAsset {
            guard let token = clean(image.altText),
                  let url = MediaURL.image(image.url),
                  seenTokens.insert(token).inserted else { continue }
            result.append(.init(token: token, url: url))
        }

        for emoji in inlineEmojis(in: [contentZH, content].compactMap { $0 })
        where seenTokens.insert(emoji.token).inserted {
            result.append(emoji)
        }
        return result
    }
    var weiboFollowingListContent: String {
        let candidates = [htmlText(content), clean(title), clean(text), clean(summary)]
            .compactMap { $0 }
            .map {
                $0.replacingOccurrences(of: "[图片]", with: "")
                    .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        return candidates.max(by: { $0.count < $1.count }) ?? displayContent
    }
    var hasWeiboVideoReference: Bool {
        guard isWeiboRSS else { return false }
        let raw = [content, text, summary, postLink].compactMap { $0 }.joined(separator: " ").lowercased()
        return raw.contains("<video") || raw.contains("video.weibo.com") || raw.contains("微博视频")
    }
    var htmlInlineAssetURLs: Set<URL> {
        guard isRSS, let content, !content.isEmpty else { return [] }
        let cacheKey = NSString(string: String(id))
        if let cached = Self.rssInlineAssetURLsCache.object(forKey: cacheKey),
           cached.content == content {
            return cached.value
        }

        let source = content as NSString
        var urls = Set<URL>()
        let fullRange = NSRange(location: 0, length: source.length)
        for match in Self.htmlImageTagRegex.matches(in: content, range: fullRange) {
            let tag = source.substring(with: match.range)
            let loweredTag = tag.lowercased()
            guard loweredTag.contains("emoji") || loweredTag.contains("emoticon") else { continue }
            guard let rawURL = htmlAttribute("src", in: tag) else { continue }
            if let url = MediaURL.image(rawURL) { urls.insert(url) }
        }
        Self.rssInlineAssetURLsCache.setObject(
            RSSInlineAssetURLsBox(content: content, value: urls),
            forKey: cacheKey,
            cost: max(1, content.utf8.count + urls.count * 128)
        )
        return urls
    }
    var videoURLs: [URL] { (videos ?? []).compactMap { $0.playURL ?? $0.url }.compactMap(MediaURL.video) }
    var directVideoURLs: [URL] { (videos ?? []).compactMap { $0.playURL ?? $0.url }.compactMap(MediaURL.directVideo) }
    var bilibiliPlaybackPageURL: URL? {
        (videos ?? [])
            .compactMap { $0.playURL ?? $0.url }
            .map { $0.hasPrefix("//") ? "https:\($0)" : $0 }
            .compactMap(URL.init(string:))
            .first { url in
                url.absoluteString.range(of: #"BV[0-9A-Za-z]{10}"#, options: .regularExpression) != nil
            }
            ?? linkURL
    }
    var previewURL: URL? {
        imageURLs.first ?? (videos ?? []).compactMap { $0.coverURL ?? $0.previewImageURL ?? $0.preview }.compactMap(MediaURL.image).first
    }
    var youtubeCoverURL: URL? {
        if let previewURL { return previewURL }
        guard let videoID = youtubeVideoID else { return nil }
        return MediaURL.image("https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
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
    var avatarURL: URL? {
        guard let url = clean(user?.avatarURL).flatMap(MediaURL.image) else { return nil }
        guard isRSS, clean(meta?.rssFeedIcon) == nil else { return url }
        let path = url.path.lowercased()
        return path.contains("/rss/feeds/") && path.hasSuffix("/avatar") ? nil : url
    }
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
    var isBilibili: Bool {
        let sourceValue = (source ?? "").lowercased()
        if sourceValue.contains("bilibili") { return true }
        if meta?.rssFeedName?.localizedCaseInsensitiveContains("哔哩哔哩") == true ||
            meta?.rssFeedName?.localizedCaseInsensitiveContains("bilibili") == true {
            return true
        }

        return [postLink, meta?.rssArticleLink].compactMap { $0 }.contains { value in
            guard let host = URL(string: value)?.host()?.lowercased() else { return false }
            return host == "bilibili.com" || host.hasSuffix(".bilibili.com") || host == "b23.tv"
        }
    }
    var isRSS: Bool { (source ?? "").hasPrefix("rss:") }
    var isQbitAIArticle: Bool {
        if source == "rss:19" { return true }
        return [postLink, meta?.rssArticleLink].compactMap { $0 }.contains { value in
            guard let host = URL(string: value)?.host()?.lowercased() else { return false }
            return host == "qbitai.com" || host.hasSuffix(".qbitai.com")
        }
    }
    var hasDedicatedFeedTab: Bool {
        source == FeedSource.newYorkTimes.rawValue ||
            source == FeedSource.wechat.rawValue ||
            source == "rss:79"
    }
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
    var isHotTopic: Bool { source == "weibo" || source == "douyin-hot" || source == "baidu" }
    var isFlash: Bool { source == "flash" }
    var isSynthetic: Bool { isHotTopic || isFlash }
    var isSocial: Bool { !isRSS && !isBilibili }

    private func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
    private func htmlText(_ value: String?) -> String? {
        guard let value = clean(value) else { return nil }
        let containsHTMLEntity = ["&amp;", "&lt;", "&gt;", "&quot;", "&apos;", "&nbsp;", "&#"]
            .contains(where: value.contains)
        guard value.contains("<") || containsHTMLEntity else { return value }
        let cacheKey = value as NSString
        if let cached = Self.htmlTextCache.object(forKey: cacheKey) {
            return cached as String
        }
        let decoded = decodeNumericHTMLEntities(value)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let stripped = decoded
            .replacingOccurrences(of: "<br\\s*/?>|</p>|</div>|</blockquote>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]*$", with: "", options: .regularExpression)
        let text = String(String.UnicodeScalarView(stripped.unicodeScalars.filter { scalar in
            let value = scalar.value
            return !(0xE000...0xF8FF).contains(value) && value != 0xFFFD
        }))
        guard let cleaned = clean(text) else { return nil }
        Self.htmlTextCache.setObject(cleaned as NSString, forKey: cacheKey, cost: cleaned.utf8.count)
        return cleaned
    }

    private func weiboText(_ value: String?) -> String? {
        htmlTextPreservingInlineImages(value)
    }

    private func xueqiuText(_ value: String?) -> String? {
        htmlTextPreservingInlineImages(value)
    }

    private func htmlTextPreservingInlineImages(_ input: String?) -> String? {
        guard var value = clean(input) else { return nil }
        let source = value as NSString
        for match in Self.htmlImageTagRegex
            .matches(in: value, range: NSRange(location: 0, length: source.length))
            .reversed() {
            let tag = source.substring(with: match.range)
            let replacement = htmlAttribute("alt", in: tag) ?? htmlAttribute("title", in: tag) ?? ""
            guard let range = Range(match.range, in: value) else { continue }
            value.replaceSubrange(range, with: replacement)
        }
        return htmlText(value) ?? clean(value)
    }

    private func inlineEmojis(in values: [String]) -> [WeiboInlineEmoji] {
        var result: [WeiboInlineEmoji] = []
        var seenTokens = Set<String>()
        for value in values {
            for tag in htmlImageTags(in: value) {
                guard let token = htmlAttribute("alt", in: tag) ?? htmlAttribute("title", in: tag),
                      let rawURL = htmlAttribute("src", in: tag),
                      let url = MediaURL.image(rawURL),
                      seenTokens.insert(token).inserted else { continue }
                result.append(.init(token: token, url: url))
            }
        }
        return result
    }

    private func htmlImageTags(in value: String) -> [String] {
        let source = value as NSString
        return Self.htmlImageTagRegex.matches(in: value, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range) }
    }

    private func htmlAttribute(_ name: String, in tag: String) -> String? {
        let source = tag as NSString
        let regex = Self.htmlAttributeRegexes[name] ?? {
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            return try! NSRegularExpression(
                pattern: #"\b"# + escapedName + #"\s*=\s*["']([^"']+)["']"#,
                options: .caseInsensitive
            )
        }()
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: source.length)),
           match.numberOfRanges > 1 else { return nil }
        let value = source.substring(with: match.range(at: 1))
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static let weiboEmojiFallbacks: [String: String] = [
        "[挖鼻]": "😏",
        "[心]": "❤️",
        "[鲜花]": "🌹",
        "[捂嘴哭]": "🥹",
        "[并不简单]": "😏",
        "[笑cry]": "😂",
        "[允悲]": "😂",
        "[泪]": "😢",
        "[哈哈]": "😄",
        "[爱你]": "🥰",
        "[赞]": "👍",
        "[鼓掌]": "👏",
        "[抱拳]": "🙏",
        "[doge]": "🐶",
        "[吃瓜]": "🍉",
        "[微笑]": "🙂",
        "[怒]": "😠",
        "[晕]": "😵",
        "[惊讶]": "😮",
        "[害羞]": "😊",
        "[馋嘴]": "😋",
        "[可怜]": "🥺",
        "[思考]": "🤔",
        "[摊手]": "🤷",
        "[裂开]": "😵‍💫",
        "[白眼]": "🙄",
        "[打call]": "📣",
        "[加油]": "💪",
        "[比心]": "🫰",
        "[握手]": "🤝",
        "[ok]": "👌",
        "[拜拜]": "👋",
        "[作揖]": "🙏",
        "[嘻嘻]": "😁",
        "[偷笑]": "🤭",
        "[闭嘴]": "🤐",
        "[抓狂]": "😫",
        "[吐]": "🤮",
        "[酷]": "😎",
        "[亲亲]": "😘",
        "[生病]": "🤒",
        "[失望]": "😞",
        "[黑线]": "😓",
        "[困]": "😴",
        "[疑问]": "❓"
    ]

    private func decodeNumericHTMLEntities(_ value: String) -> String {
        let source = value as NSString
        var result = value
        for match in Self.numericHTMLEntityRegex
            .matches(in: value, range: NSRange(location: 0, length: source.length))
            .reversed() {
            let hexRange = match.range(at: 1)
            let decimalRange = match.range(at: 2)
            let number: UInt32?
            if hexRange.location != NSNotFound {
                number = UInt32(source.substring(with: hexRange), radix: 16)
            } else if decimalRange.location != NSNotFound {
                number = UInt32(source.substring(with: decimalRange), radix: 10)
            } else {
                number = nil
            }
            guard let number, let scalar = UnicodeScalar(number),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: String(scalar))
        }
        return result
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

    static func hotTopic(_ topic: HotTopic, source: FeedSource, displayRank: Int? = nil) -> Post {
        let rank = displayRank ?? topic.latestRank
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
        let isImportant = item.isImportant ?? item.finalScore.map { $0 >= importantFlashScore } ?? false
        return Post(
            id: syntheticID("flash:\(item.similarityGroupId.map(String.init) ?? item.id ?? ""):\(item.text ?? "")"),
            title: nil, text: item.text, summary: nil, content: item.text, contentZH: nil,
            source: "flash", formattedTime: item.time, weightReason: nil, finalScore: item.finalScore, weight: nil,
            postLink: item.linkURL, articlePostAt: nil,
            user: .init(userName: nil, userScreenName: flashSourceName(item.source), avatarURL: item.avatarURL, userDesc: nil),
            postTags: isImportant ? [.init(id: 0, name: "重要")] : [],
            images: [], videos: [], feedRank: nil,
            meta: .flash(
                category: item.category,
                similarityGroupId: item.similarityGroupId,
                similarityScore: item.similarityScore,
                similarCount: item.similarCount,
                platformCount: item.platformCount,
                platforms: item.platforms
            )
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

struct PostMeta: Codable, Hashable {
    let metrics: PostMetrics?
    let lang: String?
    let urls: [String]?
    let rawText: String?
    let noteText: String?
    let inReplyToScreenName: String?
    let inReplyToStatusID: String?
    let replyContext: XReplyContext?
    let quotedTweet: XQuotedPost?
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
    let rssFeedName: String?
    let rssFeedIcon: String?
    let rssArticleLink: String?
    let flashCategory: String?
    let flashSimilarityGroupId: Int64?
    let flashSimilarityScore: Double?
    let flashSimilarCount: Int?
    let flashPlatformCount: Int?
    let flashPlatforms: [String]?
    enum CodingKeys: String, CodingKey {
        case metrics, lang, urls
        case rawText = "raw_text"
        case noteText = "note_text"
        case inReplyToScreenName = "in_reply_to_screen_name"
        case inReplyToStatusID = "in_reply_to_status_id"
        case replyContext = "reply_context"
        case quotedTweet = "quoted_tweet"
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
        case rssFeedName = "rss_feed_name"
        case rssFeedIcon = "rss_feed_icon"
        case rssArticleLink = "rss_article_link"
        case flashCategory, flashSimilarityGroupId, flashSimilarityScore, flashSimilarCount, flashPlatformCount, flashPlatforms
    }

    static func flash(
        category: String?,
        similarityGroupId: Int64?,
        similarityScore: Double?,
        similarCount: Int?,
        platformCount: Int?,
        platforms: [String]?
    ) -> PostMeta {
        PostMeta(
            metrics: nil, lang: nil, urls: nil, rawText: nil, noteText: nil,
            inReplyToScreenName: nil, inReplyToStatusID: nil,
            replyContext: nil,
            quotedTweet: nil, photoCredit: nil,
            zhihuRank: nil, zhihuHeat: nil, zhihuAnswers: nil, zhihuFollowerCount: nil,
            zhihuQuestionID: nil, zhihuURL: nil, zhihuAnswerExcerpt: nil,
            zhihuAnswerContent: nil, zhihuAnswerAuthor: nil,
            zhihuAnswerVoteupCount: nil, zhihuAnswerCommentCount: nil,
            rssFeedName: nil, rssFeedIcon: nil, rssArticleLink: nil,
            flashCategory: category,
            flashSimilarityGroupId: similarityGroupId,
            flashSimilarityScore: similarityScore,
            flashSimilarCount: similarCount,
            flashPlatformCount: platformCount,
            flashPlatforms: platforms
        )
    }

    static func xLiveDetail(_ detail: XTweetDetailItem) -> PostMeta {
        PostMeta(
            metrics: detail.metrics, lang: detail.lang, urls: nil,
            rawText: detail.fullText, noteText: detail.noteText,
            inReplyToScreenName: nil, inReplyToStatusID: nil,
            replyContext: nil, quotedTweet: nil, photoCredit: nil,
            zhihuRank: nil, zhihuHeat: nil, zhihuAnswers: nil, zhihuFollowerCount: nil,
            zhihuQuestionID: nil, zhihuURL: nil, zhihuAnswerExcerpt: nil,
            zhihuAnswerContent: nil, zhihuAnswerAuthor: nil,
            zhihuAnswerVoteupCount: nil, zhihuAnswerCommentCount: nil,
            rssFeedName: nil, rssFeedIcon: nil, rssArticleLink: nil,
            flashCategory: nil, flashSimilarityGroupId: nil, flashSimilarityScore: nil,
            flashSimilarCount: nil, flashPlatformCount: nil, flashPlatforms: nil
        )
    }

    func replacingXLiveDetail(with detail: XTweetDetailItem) -> PostMeta {
        PostMeta(
            metrics: detail.metrics ?? metrics,
            lang: detail.lang ?? lang,
            urls: urls,
            rawText: detail.fullText,
            noteText: detail.noteText ?? noteText,
            inReplyToScreenName: inReplyToScreenName,
            inReplyToStatusID: inReplyToStatusID,
            replyContext: replyContext,
            quotedTweet: quotedTweet,
            photoCredit: photoCredit,
            zhihuRank: zhihuRank, zhihuHeat: zhihuHeat, zhihuAnswers: zhihuAnswers,
            zhihuFollowerCount: zhihuFollowerCount, zhihuQuestionID: zhihuQuestionID,
            zhihuURL: zhihuURL, zhihuAnswerExcerpt: zhihuAnswerExcerpt,
            zhihuAnswerContent: zhihuAnswerContent, zhihuAnswerAuthor: zhihuAnswerAuthor,
            zhihuAnswerVoteupCount: zhihuAnswerVoteupCount,
            zhihuAnswerCommentCount: zhihuAnswerCommentCount,
            rssFeedName: rssFeedName, rssFeedIcon: rssFeedIcon,
            rssArticleLink: rssArticleLink, flashCategory: flashCategory,
            flashSimilarityGroupId: flashSimilarityGroupId,
            flashSimilarityScore: flashSimilarityScore,
            flashSimilarCount: flashSimilarCount,
            flashPlatformCount: flashPlatformCount,
            flashPlatforms: flashPlatforms
        )
    }
}

struct XReplyContext: Codable, Hashable {
    let id: String?
    let authorName: String?
    let screenName: String?
    let avatarURL: String?
    let text: String?
    let textZH: String?

    enum CodingKeys: String, CodingKey {
        case id, text
        case authorName = "author_name"
        case screenName = "screen_name"
        case avatarURL = "avatar_url"
        case textZH = "text_zh"
    }

    var displayText: String? { xNonempty(textZH) ?? xNonempty(text) }
    var handle: String? {
        guard let screenName = xNonempty(screenName) else { return nil }
        return screenName.hasPrefix("@") ? screenName : "@\(screenName)"
    }
}

struct XQuotedPost: Codable, Hashable {
    let id: String?
    let text: String?
    var textZH: String?
    let createdAt: String?
    let author: XQuotedAuthor?
    let media: [XQuotedMedia]?

    enum CodingKeys: String, CodingKey {
        case id, text, author, media
        case textZH = "text_zh"
        case createdAt
    }

    var displayText: String? { xNonempty(textZH) ?? xNonempty(text) }
    var originalText: String? { xNonempty(text) }
}

struct XQuotedAuthor: Codable, Hashable {
    let name: String?
    let screenName: String?
    let profileImageURL: String?

    enum CodingKeys: String, CodingKey {
        case name, screenName
        case profileImageURL = "profileImageUrl"
    }

    var handle: String? {
        guard let screenName = xNonempty(screenName) else { return nil }
        return screenName.hasPrefix("@") ? screenName : "@\(screenName)"
    }
}

struct XQuotedMedia: Codable, Hashable {
    let type: String?
    let url: String?
    let thumbnailURL: String?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case type, url, width, height
        case thumbnailURL = "thumbnail_url"
    }

    var displayURL: URL? { (thumbnailURL ?? url).flatMap(MediaURL.image) }
    var feedDisplayURL: URL? {
        (thumbnailURL ?? url).flatMap { MediaURL.feedImage($0, variant: "medium") }
    }
    var isVideo: Bool {
        ["video", "animated_gif", "gif"].contains(type?.lowercased() ?? "")
    }
    var directPlaybackURL: URL? { isVideo ? url.flatMap(MediaURL.directVideo) : nil }
    var playbackURL: URL? { isVideo ? url.flatMap(MediaURL.video) : nil }
    var previewURL: URL? { thumbnailURL.flatMap(MediaURL.image) }
}

private func xNonempty(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
}

struct ZhihuAnswerAuthor: Codable, Hashable {
    let name, headline, avatarURL: String?
    enum CodingKeys: String, CodingKey {
        case name, headline
        case avatarURL = "avatar_url"
    }
}

struct PostMetrics: Codable, Hashable {
    let bookmarks, likes, quotes, replies, retweets, views: Int?
}

struct PostUser: Codable, Hashable {
    let userID, personID: String?
    let userName, userScreenName, avatarURL, userDesc: String?
    let canonicalName, platformDisplayName, identityStatus, platform: String?
    let verified: Bool?
    let verifiedType: String?

    init(
        userID: String? = nil,
        personID: String? = nil,
        userName: String?,
        userScreenName: String?,
        avatarURL: String?,
        userDesc: String?,
        canonicalName: String? = nil,
        platformDisplayName: String? = nil,
        identityStatus: String? = nil,
        platform: String? = nil,
        verified: Bool? = nil,
        verifiedType: String? = nil
    ) {
        self.userID = userID
        self.personID = personID
        self.userName = userName
        self.userScreenName = userScreenName
        self.avatarURL = avatarURL
        self.userDesc = userDesc
        self.canonicalName = canonicalName
        self.platformDisplayName = platformDisplayName
        self.identityStatus = identityStatus
        self.platform = platform
        self.verified = verified
        self.verifiedType = verifiedType
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case personID = "person_id"
        case userName = "user_name"
        case userScreenName = "user_screen_name"
        case avatarURL = "avatar_url"
        case userDesc = "user_desc"
        case canonicalName = "canonical_name"
        case platformDisplayName = "platform_display_name"
        case identityStatus = "identity_status"
        case platform
        case verified
        case isVerified = "is_verified"
        case verifiedType = "verified_type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        personID = try container.decodeIfPresent(String.self, forKey: .personID)
        userName = try container.decodeIfPresent(String.self, forKey: .userName)
        userScreenName = try container.decodeIfPresent(String.self, forKey: .userScreenName)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        userDesc = try container.decodeIfPresent(String.self, forKey: .userDesc)
        canonicalName = try container.decodeIfPresent(String.self, forKey: .canonicalName)
        platformDisplayName = try container.decodeIfPresent(String.self, forKey: .platformDisplayName)
        identityStatus = try container.decodeIfPresent(String.self, forKey: .identityStatus)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        verified = try container.decodeIfPresent(Bool.self, forKey: .verified)
            ?? container.decodeIfPresent(Bool.self, forKey: .isVerified)
        verifiedType = try container.decodeIfPresent(String.self, forKey: .verifiedType)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(userID, forKey: .userID)
        try container.encodeIfPresent(personID, forKey: .personID)
        try container.encodeIfPresent(userName, forKey: .userName)
        try container.encodeIfPresent(userScreenName, forKey: .userScreenName)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try container.encodeIfPresent(userDesc, forKey: .userDesc)
        try container.encodeIfPresent(canonicalName, forKey: .canonicalName)
        try container.encodeIfPresent(platformDisplayName, forKey: .platformDisplayName)
        try container.encodeIfPresent(identityStatus, forKey: .identityStatus)
        try container.encodeIfPresent(platform, forKey: .platform)
        try container.encodeIfPresent(verified, forKey: .verified)
        try container.encodeIfPresent(verifiedType, forKey: .verifiedType)
    }

    var resolvedCanonicalName: String? {
        if let identity = AccountIdentityResolver.knownIdentity(userID: personID ?? userID) {
            return identity.canonicalName
        }
        let confirmedStatuses = ["confirmed", "manual", "official", "verified"]
        guard let status = identityStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              confirmedStatuses.contains(status) else {
            return nil
        }
        return normalizedIdentityText(canonicalName)
    }

    var resolvedAccountLabel: String? {
        if let identity = AccountIdentityResolver.knownIdentity(userID: personID ?? userID) {
            return identity.accountLabel
        }
        guard resolvedCanonicalName != nil else { return nil }
        let accountName = normalizedIdentityText(platformDisplayName)
            ?? normalizedIdentityText(userName)
            ?? normalizedIdentityText(userScreenName)
        guard let accountName, accountName != resolvedCanonicalName else { return nil }
        guard let platform = normalizedIdentityText(platform) else {
            return accountName
        }
        return "\(platform) · \(accountName)"
    }

    private func normalizedIdentityText(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

struct PostTag: Codable, Hashable { let id: Int; let name: String }
struct PostImage: Codable, Hashable {
    let url: String
    let width, height: Int?
    let altText: String?
    let kind: String?

    var isLikelyInlineEmoji: Bool {
        guard let width, let height, width > 0, height > 0 else { return false }
        let aspectRatio = Double(width) / Double(height)
        return max(width, height) <= 128 && (0.75...1.33).contains(aspectRatio)
    }

    var isKnownInlineAsset: Bool {
        let value = url.lowercased()
        return kind == "inline_emoji"
            || value.contains("/images/emoji/")
            || value.contains("/face/emoji_")
            || value.contains("/emoji/")
            || isSinaTimelinePlaceholder
            || isLikelyInlineEmoji
    }

    private var isSinaTimelinePlaceholder: Bool {
        guard let sourceURL = URL(string: url),
              let host = sourceURL.host()?.lowercased(),
              host == "sinaimg.cn" || host.hasSuffix(".sinaimg.cn") else {
            return false
        }
        let filename = sourceURL.lastPathComponent.lowercased()
        return filename.hasPrefix("timeline_card_small_") && filename.contains("_default.")
    }

    enum CodingKeys: String, CodingKey {
        case url, width, height, kind
        case altText = "alt_text"
    }

    init(url: String, width: Int?, height: Int?, altText: String? = nil, kind: String? = nil) {
        self.url = url
        self.width = width
        self.height = height
        self.altText = altText
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        width = Self.decodeDimension(.width, from: container)
        height = Self.decodeDimension(.height, from: container)
        altText = try container.decodeIfPresent(String.self, forKey: .altText)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
    }

    private static func decodeDimension(
        _ key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(String.self, forKey: key) { return Int(value) }
        return nil
    }
}
struct PostVideo: Codable, Hashable {
    let url, playURL, coverURL, previewImageURL, preview: String?
    let width, height: Int?
    enum CodingKeys: String, CodingKey {
        case url, preview, width, height
        case playURL = "play_url"
        case coverURL = "cover_url"
        case previewImageURL = "preview_image_url"
    }
}

enum MediaURL {
    static func image(_ raw: String) -> URL? {
        let decoded = highResolutionXueqiuImageURL(
            raw.replacingOccurrences(of: "&amp;", with: "&")
        )
        return resolvedImage(decoded)
    }

    static func feedImage(_ raw: String, variant: String = "small") -> URL? {
        let decoded = feedSizedXMediaURL(highResolutionXueqiuImageURL(
            raw.replacingOccurrences(of: "&amp;", with: "&")
        ), variant: variant)
        return resolvedImage(decoded)
    }

    private static func resolvedImage(_ decoded: String) -> URL? {
        if let proxyURL = URL(string: decoded),
           proxyURL.host?.lowercased() == "wechat2rss.xlab.app",
           proxyURL.path.hasSuffix("/img-proxy"),
           let original = URLComponents(url: proxyURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "u" })?.value,
           let originalURL = URL(string: original),
           originalURL.host?.lowercased().hasSuffix("qpic.cn") == true {
            var parts = URLComponents(
                url: ServerConfiguration.currentURL.appending(path: "api/ios/v1/image-proxy"),
                resolvingAgainstBaseURL: false
            )
            parts?.queryItems = [
                .init(name: "url", value: originalURL.absoluteString),
                .init(name: "soft", value: "1"),
                .init(name: "context", value: "ios-feed")
            ]
            return parts?.url
        }
        return resolved(decoded, proxy: "image-proxy")
    }

    private static func feedSizedXMediaURL(_ raw: String, variant: String) -> String {
        guard var components = URLComponents(string: raw),
              components.host?.lowercased() == "pbs.twimg.com",
              components.path.hasPrefix("/media/") else { return raw }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name.caseInsensitiveCompare("name") == .orderedSame }
        queryItems.append(URLQueryItem(name: "name", value: variant == "medium" ? "medium" : "small"))
        components.queryItems = queryItems
        return components.string ?? raw
    }

    private static func highResolutionXueqiuImageURL(_ raw: String) -> String {
        guard var components = URLComponents(string: raw),
              components.host?.lowercased() == "xqimg.imedao.com" else { return raw }

        let suffixes = ["!custom.jpg", "!custom.jpeg", "!custom.png", "!custom.webp"]
        guard let suffix = suffixes.first(where: { components.path.lowercased().hasSuffix($0) }) else {
            return raw
        }
        components.path.removeLast(suffix.count)
        return components.string ?? raw
    }
    static func directVideo(_ raw: String) -> URL? {
        let value = raw.hasPrefix("//") ? "https:\(raw)" : raw
        guard let direct = URL(string: value, relativeTo: ServerConfiguration.currentURL)?.absoluteURL else { return nil }
        if direct.path.hasSuffix("/media-proxy"),
           let originalValue = URLComponents(url: direct, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "url" })?
            .value,
           let originalURL = URL(string: originalValue),
           ["video.twimg.com", "truthsocial.com"].contains(originalURL.host?.lowercased() ?? "") {
            return originalURL
        }
        if let bvid = bilibiliBVID(from: direct) {
            return ServerConfiguration.currentURL
                .appending(path: "api/ios/v1/bilibili/hls")
                .appending(path: bvid)
                .appending(path: "video.mp4")
        }
        return direct
    }

    static func video(_ raw: String) -> URL? {
        guard let direct = directVideo(raw) else { return nil }
        return resolved(direct.absoluteString, proxy: "media-proxy")
    }

    static func videoThumbnail(for videoURL: URL, at seconds: Double = 0) -> URL? {
        let originalURL: URL
        if videoURL.path.hasSuffix("/media-proxy"),
           let proxiedURL = URLComponents(url: videoURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "url" })?
            .value,
           let resolvedURL = URL(string: proxiedURL) {
            originalURL = resolvedURL
        } else {
            originalURL = videoURL
        }

        var components = URLComponents(
            url: ServerConfiguration.currentURL.appending(path: "api/ios/v1/video-thumbnail"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            .init(name: "url", value: originalURL.absoluteString),
            .init(name: "at", value: seconds > 0 ? seconds.formatted(.number.precision(.fractionLength(0...2))) : nil)
        ].filter { $0.value != nil }
        return components?.url
    }

    private static func bilibiliBVID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), host == "bilibili.com" || host.hasSuffix(".bilibili.com") else { return nil }
        return url.pathComponents.first { $0.range(of: #"^BV[0-9A-Za-z]{10}$"#, options: .regularExpression) != nil }
    }

    private static func resolved(_ raw: String, proxy: String, hosts: [String]? = nil) -> URL? {
        let value = raw.hasPrefix("//") ? "https:\(raw)" : raw
        guard let direct = URL(string: value, relativeTo: ServerConfiguration.currentURL)?.absoluteURL else { return nil }
        guard let scheme = direct.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return direct }
        guard let host = direct.host?.lowercased() else { return direct }
        if host == ServerConfiguration.currentURL.host?.lowercased() { return direct }
        if let hosts,
           !hosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return direct
        }
        var parts = URLComponents(url: ServerConfiguration.currentURL.appending(path: "api/ios/v1/\(proxy)"), resolvingAgainstBaseURL: false)
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
    case wechat = "rss:57"
    case x, weibo, baidu
    case douyin = "douyin-hot"
    case bilibili, zhihu, xueqiu, truth, rss, laozhong, youtube, flash

    var id: String { rawValue }
    var title: String {
        switch self {
        case .newYorkTimes: "纽约时报"
        case .wechat: "微信"
        case .x: "X"
        case .weibo: "微博"
        case .douyin: "抖音"
        case .baidu: "百度"
        case .bilibili: "B站"
        case .zhihu: "知乎"
        case .xueqiu: "雪球"
        case .truth: "Truth"
        case .rss: "RSS"
        case .laozhong: "老中"
        case .youtube: "YouTube"
        case .flash: "快讯"
        }
    }

    var hotTopicPageTitle: String {
        switch self {
        case .weibo: "微博热搜"
        case .douyin: "抖音热榜"
        case .baidu: "百度热搜"
        default: title
        }
    }

    var hotTopicMarkAssetName: String {
        switch self {
        case .weibo: "WeiboMark"
        case .douyin: "TikTokMark"
        case .baidu: "BaiduMark"
        default: ""
        }
    }
}
