import Foundation

struct PostListResponse: Decodable { let data: [Post] }
struct RSSFeedPostsResponse: Decodable {
    let data: Payload
    struct Payload: Decodable { let posts: [Post] }
}
struct RSSFeedsResponse: Decodable {
    let data: Payload
    struct Payload: Decodable { let feeds: [RSSFeedSource] }
}

struct RSSFeedSource: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let feedURL: String?
    let icon: String?
    let avatar: String?
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

struct XCommentsResponse: Decodable {
    let success: Bool
    let data: Payload

    struct Payload: Decodable {
        let items: [XComment]
        let nextCursor: String?
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

    var fullText: String {
        [noteText, text, shortText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .max(by: { $0.count < $1.count }) ?? text
    }
}

enum XPostTextFormatter {
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
    var newYorkTimesFeedExcerpt: String {
        let raw = clean(summary) ?? clean(text) ?? clean(contentZH) ?? clean(content) ?? displayTitle
        let boundedRaw = String(raw.prefix(600))
        let normalized = (htmlText(boundedRaw) ?? boundedRaw)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = String(normalized.prefix(280))
        return excerpt + (normalized.count > excerpt.count || raw.count > boundedRaw.count ? "…" : "")
    }
    var displayContent: String { htmlText(contentZH) ?? originalDisplayContent }
    var originalDisplayContent: String { htmlText(content) ?? clean(text) ?? clean(summary) ?? displayTitle }
    var xStoredOriginalContent: String {
        [meta?.noteText, meta?.rawText, originalDisplayContent]
            .compactMap(clean)
            .max(by: { $0.count < $1.count }) ?? originalDisplayContent
    }
    var isChineseXSource: Bool {
        sourceName == "X" && meta?.lang?.lowercased().hasPrefix("zh") == true
    }
    var hasTranslation: Bool { clean(contentZH) != nil && clean(contentZH) != clean(content) }
    var needsXTranslation: Bool {
        guard sourceName == "X", !hasTranslation, xTweetID != nil else { return false }
        guard let language = meta?.lang?.lowercased() else { return false }
        return !language.hasPrefix("zh")
    }

    func replacingTranslation(with translation: String) -> Post {
        Post(
            id: id, title: title, text: text, summary: summary, content: content,
            contentZH: translation, source: source, formattedTime: formattedTime,
            weightReason: weightReason, finalScore: finalScore, weight: weight,
            postLink: postLink, articlePostAt: articlePostAt, user: user,
            postTags: postTags, images: images, videos: videos, feedRank: feedRank, meta: meta
        )
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
        user?.resolvedCanonicalName ?? clean(user?.userName) ?? clean(user?.userScreenName) ?? sourceName
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
    var isXueqiu: Bool {
        meta?.rssFeedName?.contains("雪球") == true ||
        meta?.rssArticleLink?.localizedCaseInsensitiveContains("xueqiu.com") == true ||
        linkURL?.host()?.localizedCaseInsensitiveContains("xueqiu.com") == true
    }
    var xueqiuBodyContent: String {
        guard let raw = clean(content),
              let quoteStart = raw.range(of: "<blockquote", options: .caseInsensitive) else {
            return displayContent
        }
        return htmlText(String(raw[..<quoteStart.lowerBound])) ?? displayContent
    }
    var xueqiuQuoteContent: String? {
        guard let raw = clean(content),
              let quoteStart = raw.range(of: "<blockquote", options: .caseInsensitive) else { return nil }
        return htmlText(String(raw[quoteStart.lowerBound...]))
    }
    var xueqiuQuoteAuthor: String? {
        guard let quote = xueqiuQuoteContent,
              let separator = quote.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return nil }
        let author = quote[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        return author.isEmpty ? nil : author
    }
    var xueqiuQuoteBody: String? {
        guard let quote = xueqiuQuoteContent else { return nil }
        guard let separator = quote.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return quote }
        let body = quote[quote.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }
    var xueqiuStockTag: String? {
        let text = displayContent as NSString
        guard let match = try? NSRegularExpression(pattern: #"\$[^$\n]{2,40}\$"#)
            .firstMatch(in: displayContent, range: NSRange(location: 0, length: text.length)) else { return nil }
        return text.substring(with: match.range)
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
        (images ?? [])
            .filter { !$0.isKnownInlineAsset }
            .compactMap { MediaURL.image($0.url) }
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

        for rawHTML in [contentZH, content].compactMap({ $0 }) {
            for tag in htmlImageTags(in: rawHTML) {
                guard let token = htmlAttribute("alt", in: tag) ?? htmlAttribute("title", in: tag),
                      let rawURL = htmlAttribute("src", in: tag),
                      let url = MediaURL.image(rawURL),
                      seenTokens.insert(token).inserted else { continue }
                result.append(.init(token: token, url: url))
            }
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
        let source = content as NSString
        guard let tagRegex = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: .caseInsensitive),
              let srcRegex = try? NSRegularExpression(
                pattern: #"\bsrc\s*=\s*["']([^"']+)["']"#,
                options: .caseInsensitive
              ) else { return [] }

        var urls = Set<URL>()
        let fullRange = NSRange(location: 0, length: source.length)
        for match in tagRegex.matches(in: content, range: fullRange) {
            let tag = source.substring(with: match.range)
            let loweredTag = tag.lowercased()
            guard loweredTag.contains("emoji") || loweredTag.contains("emoticon") else { continue }

            let tagSource = tag as NSString
            let tagRange = NSRange(location: 0, length: tagSource.length)
            guard let srcMatch = srcRegex.firstMatch(in: tag, range: tagRange),
                  srcMatch.numberOfRanges > 1 else { continue }
            let rawURL = tagSource.substring(with: srcMatch.range(at: 1))
                .replacingOccurrences(of: "&amp;", with: "&")
            if let url = MediaURL.image(rawURL) { urls.insert(url) }
        }
        return urls
    }
    var videoURLs: [URL] { (videos ?? []).compactMap { $0.playURL ?? $0.url }.compactMap(MediaURL.video) }
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
    var hasDedicatedFeedTab: Bool {
        source == FeedSource.newYorkTimes.rawValue || source == "rss:79"
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
        return clean(text)
    }

    private func weiboText(_ value: String?) -> String? {
        guard var value = clean(value) else { return nil }
        let source = value as NSString
        guard let regex = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: .caseInsensitive) else {
            return htmlText(value) ?? value
        }
        for match in regex.matches(in: value, range: NSRange(location: 0, length: source.length)).reversed() {
            let tag = source.substring(with: match.range)
            let replacement = htmlAttribute("alt", in: tag) ?? htmlAttribute("title", in: tag) ?? ""
            guard let range = Range(match.range, in: value) else { continue }
            value.replaceSubrange(range, with: replacement)
        }
        return htmlText(value) ?? clean(value)
    }

    private func htmlImageTags(in value: String) -> [String] {
        let source = value as NSString
        guard let regex = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: .caseInsensitive) else {
            return []
        }
        return regex.matches(in: value, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range) }
    }

    private func htmlAttribute(_ name: String, in tag: String) -> String? {
        let source = tag as NSString
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: #"\b"# + escapedName + #"\s*=\s*["']([^"']+)["']"#,
            options: .caseInsensitive
        ), let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: source.length)),
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
        let pattern = #"&#(?:x([0-9A-Fa-f]+)|([0-9]+));"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let source = value as NSString
        var result = value
        for match in regex.matches(in: value, range: NSRange(location: 0, length: source.length)).reversed() {
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

struct PostMeta: Decodable, Hashable {
    let metrics: PostMetrics?
    let lang: String?
    let urls: [String]?
    let rawText: String?
    let noteText: String?
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
            quotedTweet: nil, photoCredit: nil,
            zhihuRank: nil, zhihuHeat: nil, zhihuAnswers: nil, zhihuFollowerCount: nil,
            zhihuQuestionID: nil, zhihuURL: nil, zhihuAnswerExcerpt: nil,
            zhihuAnswerContent: nil, zhihuAnswerAuthor: nil,
            zhihuAnswerVoteupCount: nil, zhihuAnswerCommentCount: nil,
            rssFeedName: nil, rssArticleLink: nil,
            flashCategory: category,
            flashSimilarityGroupId: similarityGroupId,
            flashSimilarityScore: similarityScore,
            flashSimilarCount: similarCount,
            flashPlatformCount: platformCount,
            flashPlatforms: platforms
        )
    }
}

struct XQuotedPost: Decodable, Hashable {
    let id: String?
    let text: String?
    let textZH: String?
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

struct XQuotedAuthor: Decodable, Hashable {
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

struct XQuotedMedia: Decodable, Hashable {
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
}

private func xNonempty(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
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

struct PostTag: Decodable, Hashable { let id: Int; let name: String }
struct PostImage: Decodable, Hashable {
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
struct PostVideo: Decodable, Hashable {
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
    private static let imageHostSuffixes = ["twimg.com", "hdslb.com", "biliimg.com", "sinaimg.cn", "sina.com.cn", "ytimg.com", "ggpht.com", "truthsocial.com", "nyt.com", "nytimes.com"]

    static func image(_ raw: String) -> URL? { resolved(raw, proxy: "image-proxy", hosts: imageHostSuffixes) }
    static func video(_ raw: String) -> URL? {
        let value = raw.hasPrefix("//") ? "https:\(raw)" : raw
        guard let direct = URL(string: value, relativeTo: ServerConfiguration.currentURL)?.absoluteURL else { return nil }
        if let bvid = bilibiliBVID(from: direct) {
            return ServerConfiguration.currentURL
                .appending(path: "api/v1/bilibili/hls")
                .appending(path: bvid)
                .appending(path: "video.mp4")
        }
        return resolved(value, proxy: "media-proxy", hosts: ["video.twimg.com", "truthsocial.com"])
    }

    static func videoThumbnail(for videoURL: URL) -> URL? {
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
            url: ServerConfiguration.currentURL.appending(path: "api/v1/video-thumbnail"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [.init(name: "url", value: originalURL.absoluteString)]
        return components?.url
    }

    private static func bilibiliBVID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), host == "bilibili.com" || host.hasSuffix(".bilibili.com") else { return nil }
        return url.pathComponents.first { $0.range(of: #"^BV[0-9A-Za-z]{10}$"#, options: .regularExpression) != nil }
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
    case bilibili, zhihu, xueqiu, truth, rss, laozhong, youtube, flash

    var id: String { rawValue }
    var title: String {
        switch self {
        case .newYorkTimes: "纽约时报"
        case .x: "X"
        case .weibo: "微博"
        case .douyin: "抖音"
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
}
