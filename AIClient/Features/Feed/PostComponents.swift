import SwiftUI
import UIKit
import ImageIO
import AVFoundation
import CryptoKit
import WebKit

@MainActor
final class XAuthorVerificationStore: ObservableObject {
    static let shared = XAuthorVerificationStore()
    private struct Entry: Codable, Equatable {
        let verified: Bool
        let expiresAt: Date
    }
    @Published private var entries: [String: Entry]
    private let defaults: UserDefaults
    private let now: () -> Date
    private let key = "x.author-verification.v1"

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        entries = defaults.data(forKey: "x.author-verification.v1")
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    func isVerified(handle: String?, reported: Bool?) -> Bool {
        if let reported { return reported }
        guard let key = normalized(handle), let entry = entries[key], entry.expiresAt > now() else { return false }
        return entry.verified
    }

    func record(posts: [Post]) {
        var updated = entries
        let date = now()
        for post in posts where post.sourceName == "X" && !post.isXRetweetWrapper {
            guard let handle = normalized(post.user?.userScreenName), let verified = post.user?.verified else { continue }
            if let existing = updated[handle], existing.expiresAt > date { continue }
            updated[handle] = Entry(verified: verified, expiresAt: date.addingTimeInterval(6 * 3600))
        }
        save(updated)
    }

    func recordLive(handle: String?, verified: Bool?) {
        guard let handle = normalized(handle), let verified else { return }
        let date = now()
        if let existing = entries[handle], existing.verified == verified,
           existing.expiresAt > date.addingTimeInterval(3 * 3600) { return }
        var updated = entries
        updated[handle] = Entry(verified: verified, expiresAt: date.addingTimeInterval(6 * 3600))
        save(updated)
    }

    private func normalized(_ handle: String?) -> String? {
        guard let value = handle?.trimmingCharacters(in: CharacterSet(charactersIn: "@ \n\t")).lowercased(), !value.isEmpty else { return nil }
        return value
    }

    private func save(_ updated: [String: Entry]) {
        guard updated != entries else { return }
        let active = updated.filter { $0.value.expiresAt > now() }
        entries = Dictionary(uniqueKeysWithValues: active.sorted { $0.value.expiresAt > $1.value.expiresAt }.prefix(400).map { ($0.key, $0.value) })
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
    }
}

struct DetailSheetCloseButton: View {
    let action: () -> Void
    var accessibilityLabel = "关闭详情"

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .overlay { Circle().strokeBorder(.primary.opacity(0.1), lineWidth: 1) }
                    .frame(width: 36, height: 36)
                Image(systemName: "xmark")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .label))
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Compact modal actions for existing control rows and floating corners.
struct DetailSheetControls<Actions: View>: View {
    var closeLabel = "关闭详情"
    var closeIdentifier = "detail-sheet-close"
    let onClose: () -> Void
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            actions
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            DetailSheetCloseButton(action: onClose, accessibilityLabel: closeLabel)
                .accessibilityIdentifier(closeIdentifier)
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
    }
}

extension DetailSheetControls where Actions == EmptyView {
    init(closeLabel: String = "关闭详情", closeIdentifier: String = "detail-sheet-close", onClose: @escaping () -> Void) {
        self.closeLabel = closeLabel
        self.closeIdentifier = closeIdentifier
        self.onClose = onClose
        self.actions = EmptyView()
    }
}

extension View {
    func floatingSheetClose(
        _ label: String,
        identifier: String = "detail-sheet-close",
        isVisible: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        overlay(alignment: .bottomTrailing) {
            if isVisible {
                DetailSheetCloseButton(action: action, accessibilityLabel: label)
                    .accessibilityIdentifier(identifier)
                    .padding(16)
            }
        }
    }

    func readingSheetPresentation() -> some View {
        appPresentationDetents([.large])
            .appPresentationCornerRadius(28)
            .appPresentationScrollsWithoutExpanding()
    }

    func measureReadingSheetContent(when isReady: Bool, additionalHeight: CGFloat = 0) -> some View {
        modifier(ReadingSheetContentHeight(isReady: isReady, additionalHeight: additionalHeight))
    }
}

private struct ReadingSheetContentHeight: ViewModifier {
    let isReady: Bool
    let additionalHeight: CGFloat
    @State private var height: CGFloat?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height.rounded(.up) }) { measuredHeight in
                height = measuredHeight > 0 ? measuredHeight + additionalHeight : nil
            }
            .appReadingContentHeight(isReady ? height : nil)
    }
}

struct InAppBrowserDestination: Identifiable, Equatable {
    let url: URL
    var embeddedWebsiteSource: FeedSource?
    var xueqiuQuote: XueqiuQuoteLink?
    var id: String { (xueqiuQuote != nil ? "xueqiu-quote:" : "") + url.absoluteString }
}

struct InAppBrowserSheet: View {
    let url: URL
    @State private var title = ""
    @State private var englishArticle: EnglishWebArticleCandidate?
    @State private var translatedArticle: TranslatedWebArticle?
    @State private var isTranslating = false
    @State private var translatingIdentity: Int?
    @State private var translationFailed = false
    @State private var showsOriginal = false
    @State private var translatedBlocks: [String: String] = [:]
    @State private var translatedTitle = ""
    @State private var translatedTitleSource = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.knowledgeReading) private var knowledgeReading

    var body: some View {
        VStack(spacing: 0) {
            if knowledgeReading { referenceHeader }
            if ExternalAccessPolicy.requiresServerRelay(url) {
                ServerArticleReaderView(url: url) { title = $0 }
            } else {
                ZStack {
                    MinimalInAppWebView(
                        url: url,
                        title: $title,
                        englishArticleLoaded: { englishArticle = $0 }
                    )
                    .opacity(translatedArticle != nil && !showsOriginal ? 0 : 1)
                    .allowsHitTesting(translatedArticle == nil || showsOriginal)

                    if let translatedArticle, !showsOriginal {
                        TranslatedWebArticleView(article: translatedArticle, sourceURL: url)
                    }
                }
            }
            if knowledgeReading { referenceFooter }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((knowledgeReading ? KnowledgePagePalette.surface : Color(uiColor: .systemBackground)).ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            if !knowledgeReading {
                DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭网页详情")
                    .padding(16)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !knowledgeReading { translationControl.padding(16) }
        }
        .accessibilityIdentifier("in-app-browser")
        .accessibilityAction(.escape) { dismiss() }
        .task(id: englishArticle?.identity) {
            guard let englishArticle else { return }
            await translate(englishArticle)
        }
    }

    private var referenceHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.headline)
                .foregroundStyle(KnowledgePagePalette.accent)
                .frame(width: 36, height: 36)
                .background(KnowledgePagePalette.accent.opacity(0.09), in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "网页" : title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Text(url.host ?? url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var referenceFooter: some View {
        HStack(spacing: 6) {
            translationControl
            Spacer(minLength: 0)
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("分享网页链接")
            DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭网页详情")
        }
        .tint(KnowledgePagePalette.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var translationControl: some View {
        if translatedArticle != nil {
            Button {
                showsOriginal.toggle()
                title = showsOriginal ? (englishArticle?.title ?? title) : (translatedArticle?.title ?? title)
            } label: {
                Label(showsOriginal ? "查看中文" : "查看原文", systemImage: "character.book.closed")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        } else if isTranslating {
            HStack(spacing: 8) {
                ProgressView()
                Text("正在翻译为中文…")
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(.regularMaterial, in: Capsule())
        } else if translationFailed, let englishArticle {
            Button("重试翻译") {
                Task { await translate(englishArticle) }
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(.regularMaterial, in: Capsule())
            .buttonStyle(.plain)
        }
    }

    @MainActor
    private func translate(_ article: EnglishWebArticleCandidate) async {
        guard translatedArticle?.sourceIdentity != article.identity || translatedArticle?.isComplete == false else { return }
        translatingIdentity = article.identity
        isTranslating = true
        translationFailed = false
        defer {
            if translatingIdentity == article.identity {
                isTranslating = false
                translatingIdentity = nil
            }
        }
        do {
            let pending = article.blocks.filter { translatedBlocks[$0.id] == nil }
            if let first = pending.sorted(by: EnglishWebArticleBlock.translationPriority).first {
                translatedBlocks[first.id] = try await PersonArticleTranslationService.shared.translate(first.text)
                guard !Task.isCancelled, englishArticle?.identity == article.identity else { return }
                publishTranslation(for: article)
            } else {
                publishTranslation(for: article)
            }

            if translatedTitleSource != article.title {
                let value = try await PersonArticleTranslationService.shared.translate(article.title)
                guard !Task.isCancelled, englishArticle?.identity == article.identity else { return }
                translatedTitle = value.isEmpty ? article.title : value
                translatedTitleSource = article.title
                publishTranslation(for: article)
            }

            let remaining = article.blocks.filter { translatedBlocks[$0.id] == nil }
                .sorted(by: EnglishWebArticleBlock.translationPriority)
            await withTaskGroup(of: (String, String?).self) { group in
                var iterator = remaining.makeIterator()
                for _ in 0..<3 {
                    guard let block = iterator.next() else { break }
                    group.addTask {
                        let value = try? await PersonArticleTranslationService.shared.translate(block.text)
                        return (block.id, value)
                    }
                }
                for await (id, value) in group {
                    guard !Task.isCancelled, englishArticle?.identity == article.identity else {
                        group.cancelAll()
                        return
                    }
                    if let value, !value.isEmpty {
                        translatedBlocks[id] = value
                        publishTranslation(for: article)
                    }
                    if let block = iterator.next() {
                        group.addTask {
                            let value = try? await PersonArticleTranslationService.shared.translate(block.text)
                            return (block.id, value)
                        }
                    }
                }
            }
            guard !Task.isCancelled, englishArticle?.identity == article.identity else { return }
            publishTranslation(for: article)
        } catch is CancellationError {
            return
        } catch {
            if translatingIdentity == article.identity {
                translationFailed = true
            }
        }
    }

    @MainActor
    private func publishTranslation(for article: EnglishWebArticleCandidate) {
        let blocks = article.blocks.map { block in
            TranslatedWebArticleBlock(
                id: block.id,
                text: translatedBlocks[block.id]
            )
        }
        translatedArticle = TranslatedWebArticle(
            title: translatedTitle.isEmpty ? article.title : translatedTitle,
            blocks: blocks,
            sourceIdentity: article.identity,
            isComplete: blocks.allSatisfy { $0.text != nil }
        )
        title = translatedArticle?.title ?? title
        showsOriginal = false
    }
}

struct EnglishWebArticleCandidate: Equatable {
    let title: String
    let pageURL: String
    let blocks: [EnglishWebArticleBlock]

    var text: String { blocks.map(\.text).joined(separator: "\n\n") }
    var identity: Int { [pageURL, title, blocks.map(\.id).joined(separator: "|")].hashValue }

    init(title: String, text: String) {
        self.title = title
        pageURL = ""
        blocks = text.components(separatedBy: "\n\n").enumerated().compactMap { index, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : EnglishWebArticleBlock(
                id: "\(index):\(trimmed.hashValue)",
                text: trimmed,
                isVisible: index < 2
            )
        }
    }

    init(title: String, pageURL: String, blocks: [EnglishWebArticleBlock]) {
        self.title = title
        self.pageURL = pageURL
        self.blocks = blocks
    }

    static func shouldTranslate(language: String, text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 120 else { return false }
        let normalizedLanguage = language.lowercased()
        if normalizedLanguage.hasPrefix("zh") { return false }

        var latinLetters = 0
        var hanCharacters = 0
        for scalar in value.unicodeScalars.prefix(4_000) {
            switch scalar.value {
            case 65...90, 97...122:
                latinLetters += 1
            case 0x4E00...0x9FFF:
                hanCharacters += 1
            default:
                break
            }
        }
        return normalizedLanguage.hasPrefix("en") || latinLetters >= max(80, hanCharacters * 4)
    }
}

struct EnglishWebArticleBlock: Equatable {
    let id: String
    let text: String
    let isVisible: Bool

    static func translationPriority(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.isVisible != rhs.isVisible { return lhs.isVisible }
        return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
    }
}

private struct TranslatedWebArticle: Equatable {
    let title: String
    let blocks: [TranslatedWebArticleBlock]
    let sourceIdentity: Int
    let isComplete: Bool
}

private struct TranslatedWebArticleBlock: Identifiable, Equatable {
    let id: String
    let text: String?
}

private struct TranslatedWebArticleView: View {
    let article: TranslatedWebArticle
    let sourceURL: URL
    @Environment(\.knowledgeReading) private var knowledgeReading

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if knowledgeReading {
                    VStack(alignment: .leading, spacing: 7) {
                        Label(sourceURL.host ?? "中文译文", systemImage: "character.book.closed")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(KnowledgePagePalette.accent)
                        Text(article.title)
                            .font(.largeTitle.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(KnowledgePagePalette.accent.opacity(0.07), in: .rect(cornerRadius: 14))
                } else {
                    Text(article.title)
                        .font(.system(size: 25, weight: .bold, design: .serif))
                        .lineSpacing(4)
                    Text(sourceURL.host ?? "英文网页")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(article.blocks) { block in
                    if let text = block.text {
                        Text(text)
                            .font(knowledgeReading ? .body : .system(size: 17, design: .serif))
                            .lineSpacing(knowledgeReading ? 8 : 7)
                            .textSelection(.enabled)
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在翻译这一段…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: knowledgeReading ? 650 : .infinity, alignment: .leading)
            .padding(20)
            .padding(.bottom, knowledgeReading ? 18 : 64)
            .frame(maxWidth: .infinity)
        }
        .background(knowledgeReading ? KnowledgePagePalette.surface : Color(uiColor: .systemBackground))
        .accessibilityIdentifier("translated-web-article")
    }
}

enum ExternalAccessPolicy {
    private static let directHostSuffixes = [
        "wanghengai.xin", "bilibili.com", "b23.tv", "weibo.com", "weibo.cn",
        "sina.com.cn", "sina.cn", "zhihu.com", "xueqiu.com", "futunn.com",
        "douyin.com", "toutiao.com", "baidu.com", "qq.com", "weixin.qq.com",
        "163.com", "sohu.com", "ifeng.com", "cctv.com", "cctv.cn", "12371.cn",
        "nytimes.com", "nyt.com",
    ]

    static func requiresServerRelay(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else { return false }
        return !directHostSuffixes.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
    }
}

enum NewYorkTimesLocalePolicy {
    static func trustedChineseAlternate(_ value: String, from sourceValue: String) -> URL? {
        guard let source = URL(string: sourceValue),
              let sourceHost = source.host?.lowercased(),
              sourceHost == "nytimes.com" || sourceHost.hasSuffix(".nytimes.com"),
              let target = URL(string: value),
              target.scheme?.lowercased() == "https",
              target.host?.lowercased() == "cn.nytimes.com" else { return nil }
        return target
    }
}

struct ServerArticleReaderView: View {
    let url: URL
    var titleChanged: ((String) -> Void)?
    @State private var payload: ArticlePreviewResponse.Payload?
    @State private var loadError: String?
    @Environment(\.knowledgeReading) private var knowledgeReading

    init(url: URL, titleChanged: ((String) -> Void)? = nil) {
        self.url = url
        self.titleChanged = titleChanged
    }

    var body: some View {
        Group {
            if let payload {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if knowledgeReading {
                            VStack(alignment: .leading, spacing: 8) {
                                sourceLine(payload)
                                Text(displayTitle(payload))
                                    .font(.largeTitle.weight(.bold))
                                    .accessibilityAddTraits(.isHeader)
                                    .lineSpacing(3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(KnowledgePagePalette.accent.opacity(0.07), in: .rect(cornerRadius: 14))
                        } else {
                            Text(displayTitle(payload))
                                .font(.system(size: 25, weight: .bold, design: .serif))
                                .lineSpacing(4)
                            sourceLine(payload)
                        }

                        ForEach(imageURLs(payload), id: \.self) { imageURL in
                            RemoteImage(url: imageURL, height: 220, cornerRadius: 12, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                        }

                        Text(displayText(payload))
                            .font(knowledgeReading ? .body : .system(size: 17, design: .serif))
                            .lineSpacing(knowledgeReading ? 8 : 7)
                            .textSelection(.enabled)

                        ShareLink(item: url) {
                            Label("分享原始链接", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: knowledgeReading ? 650 : .infinity, alignment: .leading)
                    .padding(20)
                    .padding(.bottom, knowledgeReading ? 56 : 0)
                    .frame(maxWidth: .infinity, alignment: knowledgeReading ? .center : .leading)
                }
            } else if let loadError {
                ContentUnavailableView {
                    Label("正文载入失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("重试") { Task { await load() } }
                }
            } else {
                ContentLoadingPlaceholder(title: "正在载入正文", layout: .article, rowCount: 4)
            }
        }
        .background(knowledgeReading ? KnowledgePagePalette.surface : Color(uiColor: .systemBackground))
        .task(id: url) { await load() }
    }

    private func sourceLine(_ payload: ArticlePreviewResponse.Payload) -> some View {
        let siteName = payload.siteName.isEmpty ? (url.host ?? "网页") : payload.siteName
        return Text([siteName, payload.byline].filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func load() async {
        loadError = nil
        do {
            let next = try await ServerArticlePreviewCache.shared.payload(for: url)
            payload = next
            titleChanged?(displayTitle(next))
        } catch {
            payload = nil
            loadError = NetworkErrorPresentation.message(for: error)
        }
    }

    private func displayTitle(_ payload: ArticlePreviewResponse.Payload) -> String {
        let value = payload.titleZH.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? payload.title : value
    }

    private func displayText(_ payload: ArticlePreviewResponse.Payload) -> String {
        let translated = payload.textContentZH.trimmingCharacters(in: .whitespacesAndNewlines)
        if !translated.isEmpty { return translated }
        let original = payload.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return original.isEmpty ? payload.excerpt : original
    }

    private func imageURLs(_ payload: ArticlePreviewResponse.Payload) -> [URL] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\b(?:src|data-src)\s*=\s*[\"']([^\"']+)[\"']"#
        ) else { return [] }
        let html = payload.contentZH.isEmpty ? payload.content : payload.contentZH
        let source = html as NSString
        var seen = Set<URL>()
        return regex.matches(in: html, range: NSRange(location: 0, length: source.length))
            .compactMap { match -> URL? in
                guard match.numberOfRanges > 1 else { return nil }
                let raw = source.substring(with: match.range(at: 1))
                let normalized = raw.hasPrefix("//") ? "https:\(raw)" : raw
                guard let absolute = URL(string: normalized, relativeTo: url)?.absoluteURL,
                      let relayed = MediaURL.image(absolute.absoluteString),
                      seen.insert(relayed).inserted else { return nil }
                return relayed
            }
            .prefix(8)
            .map { $0 }
    }
}

@MainActor
final class ServerArticlePreviewCache {
    static let shared = ServerArticlePreviewCache()

    private var payloads: [URL: ArticlePreviewResponse.Payload] = [:]
    private var payloadOrder: [URL] = []
    private var loadingTasks: [URL: Task<ArticlePreviewResponse.Payload, Error>] = [:]

    func payload(for url: URL) async throws -> ArticlePreviewResponse.Payload {
        if let payload = payloads[url] { return payload }
        if let task = loadingTasks[url] { return try await task.value }

        let task = Task {
            try await APIClient(baseURL: ServerConfiguration.currentURL)
                .fetchArticlePreview(url: url)
                .data
        }
        loadingTasks[url] = task
        do {
            let payload = try await task.value
            store(payload, for: url)
            loadingTasks[url] = nil
            return payload
        } catch {
            loadingTasks[url] = nil
            throw error
        }
    }

    func prefetch(_ urls: [URL], limit: Int = 6) {
        var seen = Set<URL>()
        let pending = urls.filter { url in
            guard seen.insert(url).inserted,
                  seen.count <= limit else { return false }
            return payloads[url] == nil && loadingTasks[url] == nil
        }
        Task {
            for url in pending {
                _ = try? await payload(for: url)
            }
        }
    }

    private func store(_ payload: ArticlePreviewResponse.Payload, for url: URL) {
        if payloads[url] == nil { payloadOrder.append(url) }
        payloads[url] = payload
        while payloadOrder.count > 24 {
            payloads[payloadOrder.removeFirst()] = nil
        }
    }
}

private struct InAppBrowserCoverModifier: ViewModifier {
    @Binding var destination: InAppBrowserDestination?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ViewBuilder
    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content.appFullScreenCover(item: $destination) { destination in
                browser(for: destination)
            }
        } else {
            content.appSheet(item: $destination) { destination in
                browser(for: destination)
                .appPresentationDetents([.large])
                .appPresentationCornerRadius(28)
            }
        }
    }

    @ViewBuilder
    private func browser(for destination: InAppBrowserDestination) -> some View {
        if let quote = destination.xueqiuQuote {
            XueqiuQuotedPostBrowser(quote: quote)
        } else if let source = destination.embeddedWebsiteSource {
            EmbeddedWebPage(url: destination.url, source: source)
        } else {
            InAppBrowserSheet(url: destination.url)
        }
    }
}

extension View {
    func inAppBrowserCover(item: Binding<InAppBrowserDestination?>) -> some View {
        modifier(InAppBrowserCoverModifier(destination: item))
    }
}

@MainActor
final class XueqiuQuoteLink: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    enum State {
        case loading, resolved(URL), failed
    }

    let parentURL: URL
    @Published private(set) var state: State = .loading
    private var webView: WKWebView?
    private var timeout: Task<Void, Never>?

    private static let messageName = "xueqiuQuoteLink"
    private static let linkScript = #"""
    (() => {
      const observer = new MutationObserver(findQuote);
      function findQuote() {
        const quote = document.querySelector('a[class*="article__retweeted__anchor"]');
        if (!quote) return;
        observer.disconnect();
        window.webkit.messageHandlers.xueqiuQuoteLink.postMessage(quote.href);
      }
      observer.observe(document, { childList: true, subtree: true });
      findQuote();
    })();
    """#

    init(parentURL: URL) {
        self.parentURL = parentURL
    }

    static func postURL(_ url: URL) -> URL? {
        guard url.scheme == "https",
              url.host == "xueqiu.com" || url.host == "www.xueqiu.com",
              url.path.range(of: #"^/[0-9]+/[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        // Both hosts serve the same post. The bare host redirects web requests to www.
        return URL(string: "https://www.xueqiu.com\(url.path)")
    }

    func prepare() {
        guard webView == nil else { return }
        if case .resolved = state { return }

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        let content = configuration.userContentController
        content.add(self, contentWorld: .defaultClient, name: Self.messageName)
        content.addUserScript(WKUserScript(
            source: Self.linkScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .defaultClient
        ))
        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.navigationDelegate = self
        webView = browser
        state = .loading
        browser.load(URLRequest(url: parentURL, timeoutInterval: 12))
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            self?.finish(.failed)
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView, message.webView === webView,
              message.name == Self.messageName, message.frameInfo.isMainFrame,
              let source = message.frameInfo.request.url, Self.postURL(source) == parentURL,
              let href = message.body as? String, let url = URL(string: href),
              let original = Self.postURL(url), original != parentURL else { return }
        finish(.resolved(original))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame,
           let response = navigationResponse.response as? HTTPURLResponse,
           Self.postURL(response.url ?? parentURL) != parentURL || !(200..<300).contains(response.statusCode) {
            decisionHandler(.cancel)
            finish(.failed)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { finish(.failed) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { finish(.failed) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failed)
    }

    private func finish(_ result: State) {
        guard let webView else { return }
        timeout?.cancel()
        timeout = nil
        self.webView = nil
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.messageName,
            contentWorld: .defaultClient
        )
        webView.stopLoading()
        state = result
    }
}

private struct XueqiuQuotedPostBrowser: View {
    @ObservedObject var quote: XueqiuQuoteLink
    @Environment(\.dismiss) private var dismiss
    @State private var page = Page.loading
    @State private var attempt = 0

    private enum Page {
        case loading, visible, failed
    }

    var body: some View {
        Group {
            switch quote.state {
            case .loading:
                loading
            case .failed:
                failure { quote.prepare() }
            case .resolved(let url):
                ZStack {
                    if page != .failed {
                        XueqiuOriginalWebView(url: url) { loaded in
                            page = loaded ? .visible : .failed
                        }
                        .id(attempt)
                        .opacity(page == .visible ? 1 : 0)
                        .allowsHitTesting(page == .visible)
                        .accessibilityHidden(page != .visible)
                    }
                    if page == .loading {
                        loading
                    } else if page == .failed {
                        failure {
                            attempt += 1
                            page = .loading
                        }
                    }
                }
                .task(id: attempt) {
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    if page == .loading { page = .failed }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .floatingSheetClose("关闭网页详情", action: dismiss.callAsFunction)
        .onAppear { quote.prepare() }
    }

    private var loading: some View {
        ProgressView("正在打开雪球原帖")
    }

    private func failure(retry: @escaping () -> Void) -> some View {
        ContentUnavailableView {
            Label("无法打开雪球原帖", systemImage: "link")
        } actions: {
            Button("重试", action: retry)
        }
    }
}

private struct XueqiuOriginalWebView: UIViewRepresentable {
    let url: URL
    let onLoad: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(url: url, onLoad: onLoad) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsLinkPreview = false
        context.coordinator.initialNavigation = webView.load(URLRequest(url: url, timeoutInterval: 15))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let url: URL
        let onLoad: (Bool) -> Void
        var initialNavigation: WKNavigation?
        private var didShowOriginal = false

        init(url: URL, onLoad: @escaping (Bool) -> Void) {
            self.url = url
            self.onLoad = onLoad
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let scheme = navigationAction.request.url?.scheme
            decisionHandler(scheme == "https" || scheme == "http" ? .allow : .cancel)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if !didShowOriginal, navigationResponse.isForMainFrame,
               let response = navigationResponse.response as? HTTPURLResponse,
               XueqiuQuoteLink.postURL(response.url ?? url) != url || !(200..<300).contains(response.statusCode) {
                decisionHandler(.cancel)
                onLoad(false)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            guard !didShowOriginal, let current = webView.url, XueqiuQuoteLink.postURL(current) == url else { return }
            didShowOriginal = true
            onLoad(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if navigation == initialNavigation { initialNavigation = nil }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if !didShowOriginal, (error as NSError).code != NSURLErrorCancelled { onLoad(false) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if navigation == initialNavigation, (error as NSError).code != NSURLErrorCancelled { onLoad(false) }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            onLoad(false)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if didShowOriginal { webView.load(navigationAction.request) }
            return nil
        }
    }
}

private struct MinimalInAppWebView: UIViewRepresentable {
    let url: URL
    @Binding var title: String
    var englishArticleLoaded: ((EnglishWebArticleCandidate) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(title: $title, englishArticleLoaded: englishArticleLoaded)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: Coordinator.articleMessageName)
        configuration.userContentController.addUserScript(WKUserScript(
            source: Coordinator.articleObservationScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        if Self.isWeChatURL(url) {
            configuration.userContentController.addUserScript(WKUserScript(
                source: Self.weChatRevealScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private static func isWeChatURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "mp.weixin.qq.com" || host.hasSuffix(".mp.weixin.qq.com")
    }

    private static let weChatRevealScript = #"""
    (() => {
      const reveal = () => {
        const content = document.getElementById('js_content');
        if (content) {
          const style = getComputedStyle(content);
          if (style.visibility !== 'visible') content.style.setProperty('visibility', 'visible', 'important');
          if (style.opacity !== '1') content.style.setProperty('opacity', '1', 'important');
          if (style.display === 'none') content.style.setProperty('display', 'block', 'important');
        }
        document.querySelectorAll('img[data-src]').forEach((image) => {
          if (!image.getAttribute('src')) image.setAttribute('src', image.getAttribute('data-src'));
        });
        const articleTitle = document.getElementById('activity-name')?.textContent?.trim();
        if (articleTitle && (!document.title.trim() || document.title === '微信公众平台')) {
          document.title = articleTitle;
        }
      };
      reveal();
      new MutationObserver(reveal).observe(document.documentElement, {
        attributes: true,
        childList: true,
        subtree: true
      });
      setTimeout(reveal, 300);
      setTimeout(reveal, 1200);
    })();
    """#

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        static let articleMessageName = "codexArticleContent"
        @Binding private var title: String
        private let englishArticleLoaded: ((EnglishWebArticleCandidate) -> Void)?
        private var lastArticleIdentity: Int?
        private var attemptedChineseAlternates: Set<URL> = []

        init(
            title: Binding<String>,
            englishArticleLoaded: ((EnglishWebArticleCandidate) -> Void)?
        ) {
            _title = title
            self.englishArticleLoaded = englishArticleLoaded
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            updateTitle(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateTitle(from: webView)
            extractEnglishArticle(from: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.articleMessageName else { return }
            acceptArticleValues(message.body, webView: message.webView)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let requestURL = navigationAction.request.url {
                webView.load(URLRequest(url: requestURL))
            }
            return nil
        }

        private func updateTitle(from webView: WKWebView) {
            let value = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty, value != "微信公众平台" {
                title = value
                return
            }
            webView.evaluateJavaScript("document.getElementById('activity-name')?.textContent?.trim() || ''") { [weak self] result, _ in
                guard let self, let value = result as? String, !value.isEmpty else { return }
                self.title = value
            }
        }

        private func extractEnglishArticle(from webView: WKWebView) {
            guard englishArticleLoaded != nil else { return }
            webView.evaluateJavaScript("window.__codexExtractArticle?.()") { [weak self] result, _ in
                self?.acceptArticleValues(result, webView: webView)
            }
        }

        private func acceptArticleValues(_ result: Any?, webView: WKWebView?) {
            guard let values = result as? [String: Any] else { return }
            let pageURL = values["url"] as? String ?? ""
            if let alternateValue = values["chineseURL"] as? String,
               let alternate = NewYorkTimesLocalePolicy.trustedChineseAlternate(alternateValue, from: pageURL),
               !attemptedChineseAlternates.contains(alternate) {
                attemptedChineseAlternates.insert(alternate)
                webView?.load(URLRequest(url: alternate))
                return
            }
            guard
                  let rawBlocks = values["blocks"] as? [[String: Any]],
                  let language = values["language"] as? String else { return }
            let blocks = rawBlocks.compactMap { value -> EnglishWebArticleBlock? in
                guard let id = value["id"] as? String,
                      let text = value["text"] as? String,
                      !text.isEmpty else { return nil }
                return EnglishWebArticleBlock(
                    id: id,
                    text: text,
                    isVisible: value["visible"] as? Bool ?? false
                )
            }
            let text = blocks.map(\.text).joined(separator: "\n\n")
            guard EnglishWebArticleCandidate.shouldTranslate(language: language, text: text) else { return }
            let title = (values["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let candidate = EnglishWebArticleCandidate(title: title, pageURL: pageURL, blocks: blocks)
            guard candidate.identity != lastArticleIdentity else { return }
            lastArticleIdentity = candidate.identity
            DispatchQueue.main.async { [weak self] in
                self?.englishArticleLoaded?(candidate)
            }
        }

        static let articleObservationScript = #"""
        (() => {
          if (window.__codexArticleObserverInstalled) return;
          window.__codexArticleObserverInstalled = true;
          let lastSignature = '';
          let timer = 0;
          window.__codexExtractArticle = () => {
            const root = document.querySelector('section[name="articleBody"]')
              || document.querySelector('article')
              || document.querySelector('main');
            const chineseURL = Array.from(document.querySelectorAll('link[rel="alternate"][hreflang]'))
              .find((link) => (link.hreflang || '').toLowerCase().startsWith('zh'))?.href || '';
            if (!root) return {
              title: '', url: location.href, chineseURL, blocks: [], language: document.documentElement.lang || ''
            };
            const nodes = Array.from(root.querySelectorAll('h2,h3,p,blockquote,li,figcaption'));
            let total = 0;
            const blocks = [];
            nodes.forEach((node, index) => {
              if (total >= 100000 || blocks.length >= 400) return;
              const text = (node.innerText || '').replace(/\s+/g, ' ').trim();
              if (text.length < 2) return;
              const rect = node.getBoundingClientRect();
              const visible = rect.bottom >= -120 && rect.top <= window.innerHeight + 240;
              total += text.length;
              blocks.push({
                id: location.href + '#' + index + ':' + text.length + ':' + text.slice(0, 48),
                text,
                visible
              });
            });
            if (blocks.length === 0) {
              const text = (root.innerText || '').trim().slice(0, 100000);
              if (text.length > 0) blocks.push({ id: location.href + '#fallback', text, visible: true });
            }
            return {
              title: (document.querySelector('h1')?.innerText || document.title || '').trim(),
              url: location.href,
              chineseURL,
              blocks,
              language: document.documentElement.lang || root.lang || ''
            };
          };
          const post = () => {
            const value = window.__codexExtractArticle();
            const signature = value.blocks.map((block) => block.id + ':' + block.visible).join('|');
            if (signature === lastSignature) return;
            lastSignature = signature;
            window.webkit.messageHandlers.codexArticleContent.postMessage(value);
          };
          const schedule = () => {
            clearTimeout(timer);
            timer = setTimeout(post, 180);
          };
          new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
          addEventListener('scroll', schedule, { passive: true });
          post();
          setTimeout(post, 700);
          setTimeout(post, 2200);
        })();
        """#
    }
}

struct PostAuthorHeader: View {
    let post: Post
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            AvatarView(url: post.avatarURL, name: post.authorName, size: compact ? 34 : 42)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(post.authorName).font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold)).lineLimit(1)
                    if post.sourceName == "X" { Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.blue) }
                }
                HStack(spacing: 5) {
                    if let handle = post.authorHandle { Text(handle) }
                    if let time = post.formattedTime { Text(time) }
                    if post.isRSS { Text("来自\(post.sourceName)") }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let score = post.score, score > 0 {
                Text(score.formatted(.number.precision(.fractionLength(1))))
                    .font(.caption2.weight(.semibold)).foregroundStyle(score >= 8 ? .green : .secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.09), in: Capsule())
            }
            Image(systemName: "ellipsis").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AvatarView: View {
    let url: URL?
    let name: String
    let size: CGFloat
    var assetName: String? = nil
    var cornerRadius: CGFloat? = nil
    var rejectsUpscaledImages = false
    var placeholderSymbol: String? = nil
    @State private var loadedAvatar: (request: ImageLoader.Request, image: UIImage)?

    private var resolvedCornerRadius: CGFloat { cornerRadius ?? size / 2 }
    private var imageBackground: Color {
        name == "观点网"
            ? Color(red: 0.20, green: 0.22, blue: 0.24)
            : Color.clear
    }

    var body: some View {
        let request = assetName == nil ? ImageLoader.avatarRequest(url, size: size) : nil
        let image = request.flatMap(avatarImage(for:))

        return Group {
            if let assetName { Image(assetName).resizable().scaledToFill() }
            else if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
            }
            else {
                RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                    .fill(placeholderSymbol == nil ? Color.blue.opacity(0.11) : Color(uiColor: .secondarySystemBackground))
                    .overlay {
                        if let placeholderSymbol {
                            Image(systemName: placeholderSymbol)
                                .font(.system(size: size * 0.42, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(name.prefix(1)).font(.caption.bold()).foregroundStyle(.blue)
                        }
                    }
            }
        }
        .frame(width: size, height: size)
        .background(imageBackground)
        .clipShape(RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous))
        .task(id: request) {
            guard let request,
                  let image = await ImageLoader.shared.image(for: request),
                  !Task.isCancelled else { return }
            loadedAvatar = (request, image)
        }
    }

    private func avatarImage(for request: ImageLoader.Request) -> UIImage? {
        let image = loadedAvatar?.request == request
            ? loadedAvatar?.image
            : ImageLoader.shared.cachedImage(for: request)
        if rejectsUpscaledImages,
           let cgImage = image?.cgImage,
           min(cgImage.width, cgImage.height) < Int(size * request.scale * 0.9) {
            return nil
        }
        return image
    }
}

extension EnvironmentValues {
    @Entry var preparedReadingMedia: [URL: UIImage]? = nil
}

struct RemoteImage: View {
    let url: URL
    var targetWidth: CGFloat? = nil
    var height: CGFloat? = nil
    var cornerRadius: CGFloat = 0
    var contentMode: ContentMode = .fill
    var onImageLoaded: ((UIImage) -> Void)? = nil
    var usesTimelinePlaceholder = false
    var decodingSize: CGSize? = nil
    @State private var result: (request: ImageLoader.Request, image: UIImage?)?
    @Environment(\.preparedReadingMedia) private var preparedReadingMedia

    var body: some View {
        let screen = UIScreen.main
        let size = decodingSize ?? CGSize(width: targetWidth ?? screen.bounds.width, height: height ?? screen.bounds.height)
        let request = ImageLoader.request(
            for: url, targetSize: size, scale: screen.scale, isTimelinePreview: usesTimelinePlaceholder
        )
        let image = if let preparedReadingMedia {
            preparedReadingMedia[url]
        } else {
            (result?.request == request ? result?.image : nil) ?? ImageLoader.shared.cachedImage(for: request)
        }
        ZStack {
            usesTimelinePlaceholder ? Color(uiColor: .secondarySystemBackground) : Color.clear
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if preparedReadingMedia != nil || result?.request == request {
                Image(systemName: "photo").foregroundStyle(.secondary)
                    .accessibilityLabel("图片加载失败")
            } else if usesTimelinePlaceholder {
                Image(systemName: "photo").foregroundStyle(.tertiary)
                    .accessibilityLabel("图片加载中")
            } else {
                ProgressView().foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped().clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .task(id: request) {
            guard preparedReadingMedia == nil else { return }
            let loadedImage = await ImageLoader.shared.image(for: request)
            guard !Task.isCancelled else { return }
            result = (request, loadedImage)
            if let loadedImage { onImageLoaded?(loadedImage) }
        }
    }

}

struct InlineEmojiImage: View {
    let url: URL
    let accessibilityText: String
    var size: CGFloat = 28
    @State private var image: UIImage?
    @State private var finished = false

    init(emoji: WeiboInlineEmoji, size: CGFloat = 28) {
        url = emoji.url
        accessibilityText = emoji.token
        self.size = size
    }

    init(url: URL, accessibilityText: String = "表情", size: CGFloat = 24) {
        self.url = url
        self.accessibilityText = accessibilityText
        self.size = size
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if finished {
                Text(accessibilityText)
                    .font(.system(size: size * 0.72))
            } else {
                ProgressView()
            }
        }
        .frame(width: size, height: size, alignment: .leading)
        .accessibilityLabel(accessibilityText)
        .task(id: url) {
            finished = false
            image = await ImageLoader.load(
                url,
                targetSize: CGSize(width: size, height: size)
            )
            finished = true
        }
    }
}

struct InlineEmojiText: View {
    let text: String
    let emojis: [WeiboInlineEmoji]
    var fontSize: CGFloat = 17
    var lineSpacing: CGFloat = 5
    var maximumNumberOfLines = 0
    var textColor: UIColor = .label
    var allowsTextSelection = true
    @State private var images: [URL: UIImage] = [:]

    var body: some View {
        InlineEmojiTextView(
            text: text,
            emojis: emojis,
            images: images,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            maximumNumberOfLines: maximumNumberOfLines,
            textColor: textColor,
            allowsTextSelection: allowsTextSelection
        )
        .task(id: emojis) {
            let urls = Set(emojis.map(\.url))
            var loaded: [URL: UIImage] = [:]
            await withTaskGroup(of: (URL, UIImage?).self) { group in
                for url in urls {
                    group.addTask {
                        (url, await ImageLoader.load(url, targetSize: CGSize(width: 24, height: 24)))
                    }
                }
                for await (url, image) in group {
                    if let image { loaded[url] = image }
                }
            }
            images = loaded
        }
    }
}

private struct InlineEmojiTextView: UIViewRepresentable {
    let text: String
    let emojis: [WeiboInlineEmoji]
    let images: [URL: UIImage]
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let maximumNumberOfLines: Int
    let textColor: UIColor
    let allowsTextSelection: Bool

    final class Coordinator {
        var text: String?
        var emojis: [WeiboInlineEmoji] = []
        var imageURLs: Set<URL> = []
        var fontSize: CGFloat?
        var lineSpacing: CGFloat?
        var maximumNumberOfLines: Int?
        var textColor: UIColor?
        var allowsTextSelection: Bool?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isScrollEnabled = false
        view.isSelectable = allowsTextSelection
        view.isUserInteractionEnabled = allowsTextSelection
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let imageURLs = Set(images.keys)
        let coordinator = context.coordinator
        let needsUpdate = coordinator.text != text
            || coordinator.emojis != emojis
            || coordinator.imageURLs != imageURLs
            || coordinator.fontSize != fontSize
            || coordinator.lineSpacing != lineSpacing
            || coordinator.maximumNumberOfLines != maximumNumberOfLines
            || coordinator.textColor != textColor
            || coordinator.allowsTextSelection != allowsTextSelection
        guard needsUpdate else { return }

        view.isSelectable = allowsTextSelection
        view.isUserInteractionEnabled = allowsTextSelection
        view.textContainer.maximumNumberOfLines = maximumNumberOfLines
        view.textContainer.lineBreakMode = maximumNumberOfLines > 0 ? .byTruncatingTail : .byWordWrapping
        view.attributedText = attributedText
        view.accessibilityLabel = text

        coordinator.text = text
        coordinator.emojis = emojis
        coordinator.imageURLs = imageURLs
        coordinator.fontSize = fontSize
        coordinator.lineSpacing = lineSpacing
        coordinator.maximumNumberOfLines = maximumNumberOfLines
        coordinator.textColor = textColor
        coordinator.allowsTextSelection = allowsTextSelection
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private var attributedText: NSAttributedString {
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: fontSize))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ])

        for emoji in emojis {
            guard let image = images[emoji.url] else { continue }
            let ranges = (result.string as NSString).inlineEmojiRanges(of: emoji.token)
            for range in ranges.reversed() {
                let attachment = NSTextAttachment()
                attachment.image = image
                let size = font.lineHeight
                attachment.bounds = CGRect(x: 0, y: font.descender, width: size, height: size)
                result.replaceCharacters(in: range, with: NSAttributedString(attachment: attachment))
            }
        }
        return result
    }
}

private extension NSString {
    func inlineEmojiRanges(of value: String) -> [NSRange] {
        guard !value.isEmpty else { return [] }
        var result: [NSRange] = []
        var searchRange = NSRange(location: 0, length: length)
        while searchRange.length > 0 {
            let range = range(of: value, options: [], range: searchRange)
            guard range.location != NSNotFound else { break }
            result.append(range)
            let nextLocation = NSMaxRange(range)
            searchRange = NSRange(location: nextLocation, length: length - nextLocation)
        }
        return result
    }
}

actor ImageLoader {
    static let shared = ImageLoader()

    struct Request: Hashable, Sendable {
        let url: URL
        let pixelLimit: CGFloat?
        let scale: CGFloat
        let isAvatar: Bool

        init(url: URL, pixelLimit: CGFloat?, scale: CGFloat, isAvatar: Bool = false) {
            self.url = url
            self.pixelLimit = pixelLimit
            self.scale = scale
            self.isAvatar = isAvatar
        }

        fileprivate var cacheKey: String {
            "\(url.absoluteString)|\(Int(pixelLimit ?? 0))|\(scale)|\(isAvatar)"
        }
    }

    private struct Download {
        let id: UUID
        let task: Task<Data?, Never>
    }

    private struct PrefetchRequest: Hashable {
        let url: URL
        let width: CGFloat
        let height: CGFloat
        let prefersCompactXAvatar: Bool
        var isTimelinePreview = false
    }

    // NSCache synchronizes its own access, so views can read decoded images during rendering.
    nonisolated(unsafe) private let cache = NSCache<NSString, UIImage>()
    nonisolated(unsafe) private let avatarCache = NSCache<NSString, UIImage>()
    private let dataCache = NSCache<NSURL, NSData>()
    private let avatarDataCache = NSCache<NSURL, NSData>()
    private var downloads: [URL: Download] = [:]
    private var imageTasks: [String: Task<UIImage?, Never>] = [:]

    private let imageDataLoader: @Sendable (URL) async -> Data?

    init(imageDataLoader: (@Sendable (URL) async -> Data?)? = nil) {
        self.imageDataLoader = imageDataLoader ?? { await Self.download($0) }
        cache.totalCostLimit = 48 * 1024 * 1024
        cache.countLimit = 120
        avatarCache.totalCostLimit = 24 * 1024 * 1024
        avatarCache.countLimit = 200
        dataCache.totalCostLimit = 12 * 1024 * 1024
        dataCache.countLimit = 80
        avatarDataCache.totalCostLimit = 4 * 1024 * 1024
        avatarDataCache.countLimit = 120
    }

    func removeCachedImages() {
        cache.removeAllObjects()
        avatarCache.removeAllObjects()
        dataCache.removeAllObjects()
        avatarDataCache.removeAllObjects()
    }

    static func load(
        _ url: URL?,
        targetSize: CGSize? = nil
    ) async -> UIImage? {
        guard let url else { return nil }
        return await shared.image(for: request(for: url, targetSize: targetSize, scale: UIScreen.main.scale))
    }

    static func request(
        for url: URL, targetSize: CGSize?, scale: CGFloat, isTimelinePreview: Bool = false
    ) -> Request {
        let source = highResolutionAvatarURL(sourceImageURL(from: url))
        let relay = MediaURL.image(source.absoluteString) ?? source
        // A timeline rendition is already bounded. Prewarming and every card layout
        // can share one decoded image, including while the download is in flight.
        let limit = MediaURL.feedPhotoSize(for: source)?.maxPixels
            ?? (isTimelinePreview ? MediaURL.XPhotoSize.single.maxPixels : cachePixelLimit(targetSize: targetSize, scale: scale))
        return Request(url: relay, pixelLimit: limit, scale: scale)
    }

    @MainActor
    static func avatarRequest(_ url: URL?, size: CGFloat) -> Request? {
        guard let url, let source = compactAvatarCandidateURLs(url).first else { return nil }
        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: size, height: size)
        // Standard avatar sizes share a decoded thumbnail up to the compact X image size.
        let pixelLimit = size * scale <= 200 ? 200 : cachePixelLimit(targetSize: targetSize, scale: scale)
        return Request(url: MediaURL.image(source.absoluteString) ?? source, pixelLimit: pixelLimit, scale: scale, isAvatar: true)
    }

    static func youtubeCardCoverSize(screenWidth: CGFloat) -> CGSize {
        CGSize(width: max((screenWidth - 24) / 2, 120), height: max((screenWidth - 44) / 2, 120) * 9 / 16)
    }

    static let weChatCardCoverSize = CGSize(width: 98, height: 86)

    static func newYorkTimesCoverSize(screenWidth: CGFloat) -> CGSize {
        CGSize(width: min(screenWidth, 680), height: 245)
    }

    static func prefetchFeedImages(for posts: [Post], source: FeedSource) async {
        if source == .x {
            await prefetchXTimelineImages(for: posts)
            return
        }

        let visiblePosts = posts.prefix(12)
        guard !visiblePosts.isEmpty else { return }

        var requests: [PrefetchRequest] = []
        let authors = visiblePosts.compactMap { post in
            post.isRSS ? post.rssCardAvatarURL : post.zhihuAnswerAvatarURL
        }
        let quotedAuthors = visiblePosts.compactMap { $0.xQuotedPost?.author?.profileImageURL.flatMap(URL.init(string:)) }

        async let avatarWarmup: Void = prefetchAvatars(authors + quotedAuthors)
        let screenWidth = await MainActor.run { UIScreen.main.bounds.width }

        let socialTimeline = visiblePosts.first.map { $0.source == "x" || $0.source == "truth" } ?? false
        for post in visiblePosts.prefix(socialTimeline ? 12 : 4) {
            guard requests.count < 8 else { break }
            let mediaURLs: [URL]
            var targetSize = CGSize(width: screenWidth, height: 260)
            if source == .youtube {
                mediaURLs = [post.youtubeCoverURL].compactMap { $0 }
                targetSize = youtubeCardCoverSize(screenWidth: screenWidth)
            } else if source == .wechat {
                mediaURLs = [post.weChatCardPreviewURL].compactMap { $0 }
                targetSize = weChatCardCoverSize
            } else if post.isNewYorkTimes {
                mediaURLs = Array(post.imageURLs.prefix(1))
                targetSize = newYorkTimesCoverSize(screenWidth: screenWidth)
            } else if socialTimeline, post.videoURLs.isEmpty {
                mediaURLs = Array(post.feedImageURLs.prefix(4))
            } else {
                mediaURLs = [post.source == "x" ? post.xFeedVideoPoster : post.previewURL].compactMap { $0 }
            }
            for mediaURL in mediaURLs.prefix(8 - requests.count) {
                requests.append(.init(
                    url: mediaURL,
                    width: targetSize.width,
                    height: targetSize.height,
                    prefersCompactXAvatar: false
                ))
            }
            let quoteURLs = (post.xQuotedPost?.media ?? []).compactMap(\.feedDisplayURL)
            for quoteImageURL in quoteURLs.prefix(8 - requests.count) {
                requests.append(.init(
                    url: quoteImageURL,
                    width: max(screenWidth - 102, 220),
                    height: 220,
                    prefersCompactXAvatar: false
                ))
            }
        }

        var seen = Set<URL>()
        let uniqueRequests = requests.filter { seen.insert($0.url).inserted }
        await prefetch(uniqueRequests, maximumConcurrentLoads: 4)
        await avatarWarmup
    }

    static func prefetchXTimelineImages(for posts: [Post]) async {
        let upcomingPosts = posts.prefix(7)
        async let avatarWarmup: Void = prefetchAvatars(
            upcomingPosts.compactMap(\.avatarURL),
            maximumConcurrentLoads: 2
        )

        var mediaRequests: [PrefetchRequest] = []
        for post in upcomingPosts {
            let media: [URL]
            if post.feedPlaybackURL != nil {
                media = [post.xFeedVideoPoster].compactMap { $0 }
            } else {
                let photos = post.feedImageURLs
                media = photos.isEmpty ? [post.previewURL].compactMap { $0 } : Array(photos.prefix(4))
            }
            let quotedMedia = post.xQuotedPost?.media?.compactMap(\.feedDisplayURL) ?? []
            mediaRequests += (media + quotedMedia).map {
                .init(url: $0, width: 0, height: 0, prefersCompactXAvatar: false, isTimelinePreview: true)
            }
        }
        var seen = Set<PrefetchRequest>()
        await prefetch(mediaRequests.filter { seen.insert($0).inserted }, maximumConcurrentLoads: 2)
        await avatarWarmup
    }

    static func prefetchAvatars(
        _ urls: [URL],
        maximumCount: Int = 12,
        maximumConcurrentLoads: Int = 4
    ) async {
        var seen = Set<URL>()
        let requests = urls.filter { seen.insert($0).inserted }.prefix(maximumCount).map {
            PrefetchRequest(url: $0, width: 44, height: 44, prefersCompactXAvatar: true)
        }
        await prefetch(requests, maximumConcurrentLoads: maximumConcurrentLoads)
    }

    /// Finishes the initial reading snapshot even if a remote image is slow.
    static func prepareReadingImages<Key: Hashable & Sendable>(
        _ requests: [(Key, Request)]
    ) async -> [Key: UIImage] {
        guard !requests.isEmpty else { return [:] }
        let (images, output) = AsyncStream.makeStream(of: (Key, UIImage).self)
        let worker = Task {
            await withTaskGroup(of: Void.self) { group in
                var pending = requests.makeIterator()
                for _ in 0..<min(requests.count, 8) {
                    guard let (key, request) = pending.next() else { break }
                    group.addTask { await prepareImage(key, request: request, output: output) }
                }
                while await group.next() != nil {
                    guard !Task.isCancelled, let (key, request) = pending.next() else { continue }
                    group.addTask { await prepareImage(key, request: request, output: output) }
                }
            }
            output.finish()
        }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { output.finish() }
        }
        defer {
            worker.cancel()
            deadline.cancel()
        }

        var prepared: [Key: UIImage] = [:]
        for await (key, image) in images {
            prepared[key] = image
        }
        return prepared
    }

    private static func prepareImage<Key: Sendable>(
        _ key: Key, request: Request, output: AsyncStream<(Key, UIImage)>.Continuation
    ) async {
        guard !Task.isCancelled else { return }
        if let image = await shared.image(for: request), !Task.isCancelled {
            output.yield((key, image))
        }
    }

    static func compactAvatarCandidateURLs(_ url: URL) -> [URL] {
        let sourceURL = sourceImageURL(from: url)
        let upgradedURL = highResolutionAvatarURL(sourceURL)
        guard let host = upgradedURL.host?.lowercased(),
              (host == "pbs.twimg.com" || host.hasSuffix(".twimg.com")),
              upgradedURL.path.contains("/profile_images/") else {
            return [upgradedURL]
        }

        var components = URLComponents(url: upgradedURL, resolvingAgainstBaseURL: false)
        components?.path = upgradedURL.path
            .replacingOccurrences(of: "_bigger.", with: "_200x200.")
            .replacingOccurrences(of: "_mini.", with: "_200x200.")
            .replacingOccurrences(of: "_400x400.", with: "_200x200.")
        let compactURL = components?.url ?? upgradedURL
        return [compactURL]
    }

    static func sourceImageURL(from url: URL) -> URL {
        guard url.path.hasSuffix("/image-proxy"),
              let originalValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "url" })?
                .value,
              let originalURL = URL(string: originalValue) else { return url }
        return originalURL
    }

    static func highResolutionAvatarURL(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(),
              host == "pbs.twimg.com" || host.hasSuffix(".twimg.com"),
              url.path.contains("/profile_images/") else { return url }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let upgradedPath = url.path
            .replacingOccurrences(of: "_40_normal.", with: "_200x200.")
            .replacingOccurrences(of: "_normal.", with: "_200x200.")
        components?.path = upgradedPath
        return components?.url ?? url
    }

    func image(for url: URL, targetSize: CGSize?, scale: CGFloat) async -> UIImage? {
        let request = Request(url: url, pixelLimit: Self.cachePixelLimit(targetSize: targetSize, scale: scale), scale: scale)
        return await image(for: request)
    }

    nonisolated func cachedImage(for request: Request) -> UIImage? {
        let decodedCache = request.isAvatar ? avatarCache : cache
        return decodedCache.object(forKey: request.cacheKey as NSString)
    }

    func image(for request: Request) async -> UIImage? {
        if let cached = cachedImage(for: request) { return cached }
        let key = request.cacheKey
        if let existing = imageTasks[key] { return await existing.value }

        let task = Task { await self.loadImage(for: request) }
        imageTasks[key] = task
        let image = await task.value
        imageTasks[key] = nil
        return image
    }

    // Small layout differences should reuse the same decoded thumbnail.
    static func cachePixelLimit(targetSize: CGSize?, scale: CGFloat) -> CGFloat? {
        guard let targetSize else { return nil }
        let pixels = max(targetSize.width, targetSize.height) * scale
        guard pixels.isFinite, pixels > 0 else { return nil }
        return ceil(pixels / 128) * 128
    }

    private func loadImage(for request: Request) async -> UIImage? {
        let url = request.url
        let rawCache = request.isAvatar ? avatarDataCache : dataCache
        let diskCache = request.isAvatar ? ImageDiskCache.avatars : ImageDiskCache.shared
        let decodedCache = request.isAvatar ? avatarCache : cache
        let data: Data?
        var downloadedData = false
        var loadedFromDisk = false
        if let cachedData = rawCache.object(forKey: url as NSURL) {
            data = cachedData as Data
        } else if let cachedData = await diskCache.data(for: url) {
            data = cachedData
            loadedFromDisk = true
            rawCache.setObject(cachedData as NSData, forKey: url as NSURL, cost: cachedData.count)
        } else {
            let download: Download
            if let existing = downloads[url] {
                download = existing
            } else {
                let created = Download(id: UUID(), task: Task { await imageDataLoader(url) })
                downloads[url] = created
                download = created
            }

            data = await download.task.value
            if downloads[url]?.id == download.id { downloads[url] = nil }
            if let data {
                downloadedData = true
                rawCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
            }
        }

        guard let data else { return nil }

        // Visible cells await this work; do not seed ImageIO's worker queues at Utility QoS.
        let decodedImage = await Task.detached(priority: .userInitiated) {
            Self.decode(data, pixelLimit: request.pixelLimit, scale: request.scale)
        }.value
        guard let decodedImage else {
            rawCache.removeObject(forKey: url as NSURL)
            if loadedFromDisk {
                await diskCache.removeData(for: url)
                return await loadImage(for: request)
            }
            return nil
        }
        let cost = max(1, decodedImage.cgImage.map { $0.bytesPerRow * $0.height } ?? Int(decodedImage.size.width * decodedImage.size.height * request.scale * request.scale * 4))
        decodedCache.setObject(decodedImage, forKey: request.cacheKey as NSString, cost: cost)
        if downloadedData {
            Task(priority: .utility) {
                await diskCache.store(data, for: url)
            }
        }
        return decodedImage
    }

    private static func prefetch(
        _ requests: [PrefetchRequest],
        maximumConcurrentLoads: Int
    ) async {
        guard !requests.isEmpty, !Task.isCancelled else { return }
        await withTaskGroup(of: Void.self) { group in
            var iterator = requests.makeIterator()
            let limit = min(max(1, maximumConcurrentLoads), requests.count)
            for _ in 0..<limit {
                guard let request = iterator.next() else { break }
                group.addTask { await load(request) }
            }
            while await group.next() != nil {
                guard !Task.isCancelled, let request = iterator.next() else { continue }
                group.addTask { await load(request) }
            }
        }
    }

    @MainActor
    private static func load(_ request: PrefetchRequest) async {
        guard !Task.isCancelled else { return }
        let imageRequest: Request
        if request.prefersCompactXAvatar {
            guard let avatar = avatarRequest(request.url, size: request.width) else { return }
            imageRequest = avatar
        } else {
            imageRequest = Self.request(
                for: request.url,
                targetSize: CGSize(width: request.width, height: request.height),
                scale: UIScreen.main.scale,
                isTimelinePreview: request.isTimelinePreview
            )
        }
        _ = await shared.image(for: imageRequest)
    }

    private static func download(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              http.mimeType?.lowercased() != "image/svg+xml",
              !data.isEmpty else { return nil }
        return data
    }

    private static func decode(_ data: Data, pixelLimit: CGFloat?, scale: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any]
        if let pixelLimit, pixelLimit > 0 {
            options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, Int(pixelLimit)),
                kCGImageSourceShouldCacheImmediately: true
            ]
        } else {
            options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ]
        }
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        return image.size.width > 1 && image.size.height > 1 ? image : nil
    }
}

actor ImageDiskCache {
    static let shared = ImageDiskCache(
        directory: ImageDiskCache.directory(named: "FeedImageCache"),
        maxBytes: 256 * 1024 * 1024,
        maxFileCount: 1_200
    )
    static let avatars = ImageDiskCache(
        directory: ImageDiskCache.directory(named: "AvatarCache"),
        maxBytes: 64 * 1024 * 1024,
        maxFileCount: 1_800
    )

    private let directory: URL
    private let maxBytes: Int
    private let maxFileCount: Int
    private var isPrepared = false
    private var writesSinceTrim = 0
    private var trimTask: Task<Void, Never>?

    init(directory: URL, maxBytes: Int, maxFileCount: Int) {
        self.directory = directory
        self.maxBytes = max(1, maxBytes)
        self.maxFileCount = max(1, maxFileCount)
    }

    func data(for url: URL) -> Data? {
        prepareIfNeeded()
        let fileURL = cachedFileURL(for: url)
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe), !data.isEmpty else {
            return nil
        }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return data
    }

    func store(_ data: Data, for url: URL) {
        guard !data.isEmpty else { return }
        prepareIfNeeded()
        let fileURL = cachedFileURL(for: url)
        do {
            try data.write(to: fileURL, options: .atomic)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableFileURL = fileURL
            try? mutableFileURL.setResourceValues(resourceValues)
            writesSinceTrim += 1
            if writesSinceTrim >= 24 {
                scheduleTrim()
            }
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func removeData(for url: URL) {
        prepareIfNeeded()
        try? FileManager.default.removeItem(at: cachedFileURL(for: url))
    }

    func trim() {
        prepareIfNeeded()
        trimTask?.cancel()
        trimTask = nil
        writesSinceTrim = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }

        var entries = files.compactMap { fileURL -> (url: URL, size: Int, date: Date)? in
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }
            return (fileURL, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var totalBytes = entries.reduce(0) { $0 + $1.size }
        guard totalBytes > maxBytes || entries.count > maxFileCount else { return }

        entries.sort { $0.date < $1.date }
        var remainingCount = entries.count
        for oldest in entries {
            guard totalBytes > maxBytes || remainingCount > maxFileCount else { break }
            do {
                try FileManager.default.removeItem(at: oldest.url)
                totalBytes -= oldest.size
                remainingCount -= 1
            } catch {
                continue
            }
        }
    }

    private func prepareIfNeeded() {
        guard !isPrepared else { return }
        isPrepared = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        scheduleTrim()
    }

    private func scheduleTrim() {
        guard trimTask == nil else { return }
        trimTask = Task(priority: .utility) { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) }
            catch { return }
            await self?.trim()
        }
    }

    private func cachedFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(filename, isDirectory: false)
    }

    private static func directory(named name: String) -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent(name, isDirectory: true)
    }
}

enum XueqiuMediaDisplayPolicy {
    static func shouldDisplay(_ url: URL, post: Post, usesExplicitPlacement: Bool) -> Bool {
        guard post.isXueqiu, usesExplicitPlacement else { return true }

        let serverURL = ServerConfiguration.currentURL
        let isServerOrigin = url.scheme?.lowercased() == serverURL.scheme?.lowercased()
            && url.host?.lowercased() == serverURL.host?.lowercased()
            && url.port == serverURL.port
        guard isServerOrigin else { return true }

        // Xueqiu image sources are absolute CDN URLs. A non-proxy URL resolved
        // against our API origin is malformed HTML (for example `src=" title="`).
        return url.path.hasSuffix("/image-proxy")
    }
}

struct PostMediaGrid: View {
    let post: Post
    var imageURLs: [URL]? = nil
    var usesFeedSizedImages = false
    var singleImageHeight: CGFloat? = nil
    var singleImageMaxHeight: CGFloat? = nil
    var singleImageContentMode: ContentMode = .fit
    var multiImageHeight: CGFloat = 132
    var availableWidth: CGFloat? = nil
    var cornerRadius: CGFloat = 8
    var videoContentMode: ContentMode = .fit
    var videoMaxHeight: CGFloat? = nil
    var displaysVideoPlayer = true
    var onImageTap: (() -> Void)? = nil
    var imageTapLabel: String? = nil
    @State private var gallerySelection: ImageGallerySelection?
    @State private var compactImageURLs: Set<URL> = []
    @State private var loadedSingleImageAspectRatio: CGFloat?
    @State private var loadedVideoAspectRatio: CGFloat?

    private var isXTimelinePreview: Bool { usesFeedSizedImages && post.source == "x" }

    private var knownCompactImageURLs: Set<URL> {
        guard post.isRSS else { return [] }
        let knownURLs = Set((post.images ?? []).filter(\.isKnownInlineAsset).compactMap { MediaURL.image($0.url) })
        return knownURLs.union(post.htmlInlineAssetURLs)
    }

    private var allContentImageURLs: [URL] {
        (imageURLs ?? (usesFeedSizedImages ? post.feedImageURLs : post.imageURLs))
            .filter { !knownCompactImageURLs.contains($0) && !compactImageURLs.contains($0) }
            .filter {
                XueqiuMediaDisplayPolicy.shouldDisplay(
                    $0,
                    post: post,
                    usesExplicitPlacement: imageURLs != nil
                )
            }
    }

    private var allGalleryImageURLs: [URL] {
        guard imageURLs == nil else { return allContentImageURLs }
        let originals = post.originalImageURLs
        return originals.count == allContentImageURLs.count ? originals : allContentImageURLs
    }

    private var contentImageURLs: [URL] {
        Array(allContentImageURLs.prefix(4))
    }

    private var imageAccessibilityLabel: String {
        imageTapLabel ?? (onImageTap == nil ? "查看图片" : "查看文章详情")
    }

    private func coverDecodingSize(for url: URL) -> CGSize? {
        guard post.isNewYorkTimes, post.imageURLs.first == url else { return nil }
        return ImageLoader.newYorkTimesCoverSize(screenWidth: UIScreen.main.bounds.width)
    }

    private var resolvedSingleImageHeight: CGFloat {
        if let singleImageHeight { return singleImageHeight }
        let resolvedWidth = availableWidth ?? UIScreen.main.bounds.width - 28
        if let loadedSingleImageAspectRatio, loadedSingleImageAspectRatio > 0 {
            return min(resolvedWidth / loadedSingleImageAspectRatio, singleImageMaxHeight ?? 560)
        }
        guard let image = post.images?.first(where: { !post.isRSS || !$0.isKnownInlineAsset }),
              let width = image.width,
              let height = image.height,
              width > 0,
              height > 0 else {
            return min(210, singleImageMaxHeight ?? 210)
        }
        return min(resolvedWidth * CGFloat(height) / CGFloat(width), singleImageMaxHeight ?? 560)
    }

    private var resolvedVideoAspectRatio: CGFloat {
        if let loadedVideoAspectRatio, loadedVideoAspectRatio > 0 {
            return loadedVideoAspectRatio
        }
        if let video = post.videos?.first,
           let width = video.width,
           let height = video.height,
           width > 0,
           height > 0 {
            return CGFloat(width) / CGFloat(height)
        }
        return 16 / 9
    }

    private var resolvedVideoSize: CGSize {
        let resolvedWidth = availableWidth ?? UIScreen.main.bounds.width - 28
        if let singleImageHeight {
            return CGSize(width: resolvedWidth, height: singleImageHeight)
        }
        let widthForHeightLimit = videoMaxHeight.map { $0 * resolvedVideoAspectRatio } ?? resolvedWidth
        let width = min(resolvedWidth, widthForHeightLimit)
        return CGSize(width: width, height: width / resolvedVideoAspectRatio)
    }

    private func recordLoadedImage(_ image: UIImage, at url: URL, isSingleImage: Bool) {
        if isSingleImage, !isXTimelinePreview, image.size.width > 0, image.size.height > 0 {
            loadedSingleImageAspectRatio = image.size.width / image.size.height
        }

        guard post.isRSS, let cgImage = image.cgImage else { return }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return }

        let aspectRatio = width / height
        let isSmallIcon = max(width, height) <= 192 && (0.5...2).contains(aspectRatio)
        let isShortBadge = height <= 96 && width <= 360 && aspectRatio > 2
        guard isSmallIcon || isShortBadge else { return }

        compactImageURLs.insert(url)
    }

    private func showGallery(startingAt url: URL, urls: [URL]) {
        let galleryURLs = urls.isEmpty ? [url] : urls
        let initialIndex = galleryURLs.firstIndex(of: url) ?? 0
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            gallerySelection = ImageGallerySelection(urls: galleryURLs, initialIndex: initialIndex)
        }
    }

    private func handleImageTap(at url: URL, urls: [URL]) {
        if let onImageTap {
            onImageTap()
        } else {
            let index = urls.firstIndex(of: url) ?? 0
            let galleryURLs = allGalleryImageURLs
            let galleryURL = galleryURLs.indices.contains(index) ? galleryURLs[index] : url
            showGallery(startingAt: galleryURL, urls: galleryURLs)
        }
    }

    @MainActor
    private func loadVideoAspectRatio(for url: URL) async {
        guard let aspectRatio = await videoTrackAspectRatio(for: url) else { return }
        loadedVideoAspectRatio = aspectRatio
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let urls = contentImageURLs
            if displaysVideoPlayer, let videoURL = post.feedPlaybackURL {
                XVideoPlayerView(
                    url: videoURL,
                    fallbackURL: post.feedPlaybackFallbackURL,
                    thumbnailURL: post.previewURL,
                    contentMode: videoContentMode,
                    reportsPlaybackEvents: post.sourceName == "X",
                    observationSurface: "feed-grid"
                )
                    .id(videoURL)
                    .frame(width: resolvedVideoSize.width, height: resolvedVideoSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if urls.count == 1, let url = urls.first {
                Button { handleImageTap(at: url, urls: allContentImageURLs) } label: {
                    RemoteImage(
                        url: url,
                        targetWidth: availableWidth,
                        height: resolvedSingleImageHeight,
                        cornerRadius: cornerRadius,
                        contentMode: singleImageContentMode,
                        onImageLoaded: isXTimelinePreview ? nil : { recordLoadedImage($0, at: url, isSingleImage: true) },
                        usesTimelinePlaceholder: isXTimelinePreview,
                        decodingSize: coverDecodingSize(for: url)
                    )
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
                .accessibilityLabel(imageAccessibilityLabel)
            } else if !urls.isEmpty {
                LazyVGrid(columns: [.init(.flexible(), spacing: 3), .init(.flexible(), spacing: 3)], spacing: 3) {
                    ForEach(urls, id: \.self) { url in
                        Button { handleImageTap(at: url, urls: allContentImageURLs) } label: {
                            RemoteImage(
                                url: url,
                                targetWidth: ((availableWidth ?? UIScreen.main.bounds.width) - 3) / 2,
                                height: multiImageHeight,
                                cornerRadius: 6,
                                contentMode: .fit,
                                onImageLoaded: isXTimelinePreview ? nil : { recordLoadedImage($0, at: url, isSingleImage: false) },
                                usesTimelinePlaceholder: isXTimelinePreview,
                                decodingSize: coverDecodingSize(for: url)
                            )
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(imageAccessibilityLabel)
                    }
                }
            } else if let preview = post.previewURL {
                Button { handleImageTap(at: preview, urls: [preview]) } label: {
                    RemoteImage(
                        url: preview,
                        targetWidth: availableWidth,
                        height: resolvedSingleImageHeight,
                        cornerRadius: cornerRadius,
                        contentMode: singleImageContentMode,
                        usesTimelinePlaceholder: isXTimelinePreview,
                        decodingSize: coverDecodingSize(for: preview)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(imageAccessibilityLabel)
            }
        }
        .frame(maxWidth: availableWidth ?? .infinity, alignment: .leading)
        .clipped()
        .task(id: displaysVideoPlayer ? post.videoURLs.first : nil) {
            guard displaysVideoPlayer else { return }
            if let video = post.videos?.first,
               let width = video.width,
               let height = video.height,
               width > 0,
               height > 0 {
                return
            }
            guard let videoURL = post.videoURLs.first else { return }
            await loadVideoAspectRatio(for: videoURL)
        }
        .imageGallery(item: $gallerySelection)
    }
}

private extension Post {
    var feedPlaybackURL: URL? {
        videoURLs.first
    }

    var feedPlaybackFallbackURL: URL? {
        nil
    }
}

struct ImageGallerySelection: Identifiable {
    let id = UUID()
    let urls: [URL]
    let initialIndex: Int
}

enum XTimelineTextLayout {
    static let fontSize: CGFloat = 16
    static let lineSpacing: CGFloat = 3
    static let lineLimit = 8

    private static let cache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 400
        return cache
    }()

    static func needsExpansion(_ text: String, width: CGFloat) -> Bool {
        let width = max(1, width)
        let key = "\(width)|\(text)" as NSString
        if let cached = cache.object(forKey: key) { return cached.boolValue }
        let font = UIFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let height = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph],
            context: nil
        ).height
        let collapsedHeight = font.lineHeight * CGFloat(lineLimit) + lineSpacing * CGFloat(lineLimit - 1)
        let expanded = height > collapsedHeight + 0.5
        cache.setObject(NSNumber(value: expanded), forKey: key)
        return expanded
    }
}

struct XFeedMediaView: View {
    let post: Post
    var timelineWidth: CGFloat? = nil
    var showsQuotedPost = true
    var onOpenQuote: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let videoURL = post.feedPlaybackURL {
                XVideoPlayerView(
                    url: videoURL,
                    fallbackURL: post.feedPlaybackFallbackURL,
                    thumbnailURL: post.xFeedVideoPoster,
                    usesTimelinePoster: timelineWidth != nil,
                    generatesThumbnailWhenMissing: timelineWidth == nil,
                    reportsPlaybackEvents: true,
                    observationSurface: "x-feed"
                )
                .id(videoURL)
                .frame(height: videoHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                PostMediaGrid(
                    post: post,
                    usesFeedSizedImages: true,
                    singleImageMaxHeight: timelineWidth == nil ? 420 : 280,
                    availableWidth: availableWidth,
                    cornerRadius: 12
                )
            }

            if showsQuotedPost, let quote = post.xQuotedPost {
                XFeedQuotedPostCard(quote: quote, availableWidth: availableWidth)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenQuote?() }
            }
        }
    }

    private var availableWidth: CGFloat {
        max(timelineWidth ?? (UIScreen.main.bounds.width - 78), 1)
    }

    private var videoHeight: CGFloat {
        guard let video = post.videos?.first,
              let width = video.width,
              let height = video.height,
              width > 0,
              height > 0 else {
            return availableWidth * 9 / 16
        }
        return min(availableWidth * CGFloat(height) / CGFloat(width), 440)
    }
}

/// Shared reading typography for quoted and replied-to posts in the detail sheet.
struct XDetailContextText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(XPostTextFormatter.paragraphs(text).enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.system(size: 16))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.primary)
        .multilineTextAlignment(.leading)
    }
}

struct XFeedQuotedPostCard: View {
    let quote: XQuotedPost
    let availableWidth: CGFloat
    var enablesTextSelection = false
    var isDetail = false
    var showsTranslationOnly = false
    var isTranslationActive = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                if let avatarURL = quote.author?.profileImageURL.flatMap(URL.init(string:)) {
                    AvatarView(
                        url: avatarURL,
                        name: quote.author?.name ?? "引用动态",
                        size: 28
                    )
                }

                Text(quote.author?.name ?? "引用动态")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                if let handle = quote.author?.handle {
                    Text(handle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if showsTranslationOnly {
                FeedReaderTranslationText(
                    original: quote.originalText, chinese: quote.textZH, field: .quote, isActive: isTranslationActive
                )
                .font(.system(size: 16))
                .lineSpacing(3)
                .textSelection(.enabled)
            } else if let text = quote.displayText {
                quotedText(text)
            }

            ForEach(Array((quote.media ?? []).enumerated()), id: \.offset) { _, media in
                quotedMedia(media)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            Color(uiColor: isDetail ? .systemBackground : .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func quotedText(_ text: String) -> some View {
        if isDetail {
            XDetailContextText(text: text)
                .textSelection(.enabled)
        } else if enablesTextSelection {
            Text(text)
                .font(.system(size: 15))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(.system(size: 15))
                .lineSpacing(2)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func quotedMedia(_ media: XQuotedMedia) -> some View {
        if let videoURL = media.playbackURL {
            XVideoPlayerView(
                url: videoURL,
                fallbackURL: nil,
                thumbnailURL: isDetail ? media.previewURL : media.feedDisplayURL,
                usesTimelinePoster: !isDetail,
                generatesThumbnailWhenMissing: false,
                reportsPlaybackEvents: true,
                observationSurface: "x-quoted"
            )
            .frame(height: quotedMediaHeight(media))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if let imageURL = media.feedDisplayURL {
            RemoteImage(
                url: imageURL,
                targetWidth: availableWidth - 24,
                height: quotedMediaHeight(media),
                cornerRadius: 8,
                contentMode: .fit,
                usesTimelinePlaceholder: !isDetail
            )
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .clipped()
        }
    }

    private func quotedMediaHeight(_ media: XQuotedMedia) -> CGFloat {
        guard let mediaWidth = media.width,
              let mediaHeight = media.height,
              mediaWidth > 0,
              mediaHeight > 0 else { return 190 }
        return min(max(1, availableWidth - 24) * CGFloat(mediaHeight) / CGFloat(mediaWidth), 460)
    }
}

@MainActor
private final class XVideoPlaybackSession {
    static let shared = XVideoPlaybackSession()

    private weak var activePlayer: AVPlayer?
    private var activeURL: URL?
    private var positions: [URL: CMTime] = [:]

    func play(_ player: AVPlayer, url: URL, restoringPosition: Bool = false) {
        if let activePlayer, activePlayer !== player {
            savePosition(of: activePlayer, url: activeURL)
            activePlayer.pause()
        }
        activePlayer = player
        activeURL = url
        if restoringPosition, let position = positions[url], position.seconds > 0.25 {
            player.seek(
                to: position,
                toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: 600),
                toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: 600)
            )
        }
        player.playImmediately(atRate: 1)
    }

    func pause(_ player: AVPlayer, url: URL) {
        player.pause()
        guard activePlayer === player else { return }
        savePosition(of: player, url: url)
    }

    func finish(_ player: AVPlayer, url: URL) {
        positions[url] = nil
        if activePlayer === player {
            activePlayer = nil
            activeURL = nil
        }
    }

    private func savePosition(of player: AVPlayer, url: URL?) {
        guard let url else { return }
        let position = player.currentTime()
        guard position.isNumeric else { return }
        positions[url] = position
    }
}

enum XVideoPlayerChromeStyle {
    case standard
    case minimal
}

struct XVideoPlayerView: View {
    private static let directFirstFrameTimeout: Duration = .seconds(3)

    private enum PlaybackState {
        case idle
        case preparing
        case ready
        case failed
    }

    private static let thumbnailCache = NSCache<NSURL, UIImage>()

    @State private var player: AVPlayer?
    @State private var thumbnail: UIImage?
    @State private var preparedAsset: AVURLAsset?
    @State private var playbackState: PlaybackState = .idle
    @State private var playbackURL: URL
    @State private var hasUsedFallback = false
    @State private var isPlaying = false
    @State private var hasReachedEnd = false
    @State private var isMuted = true
    @State private var thumbnailFailed = false
    @State private var isFullscreenPresented = false
    @State private var showsFullscreenControls = true
    @State private var playbackFallbackTask: Task<Void, Never>?
    @State private var observationSessionID: String?
    @State private var observationStartedAt: Date?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.preparedReadingMedia) private var preparedReadingMedia
    private let fallbackURL: URL?
    private let thumbnailURL: URL?
    private let fallbackThumbnailURL: URL?
    private let contentMode: ContentMode
    private let chromeStyle: XVideoPlayerChromeStyle
    private let isPlaybackActive: Bool
    private let usesTimelinePoster: Bool
    private let generatesThumbnailWhenMissing: Bool
    private let reportsPlaybackEvents: Bool
    private let onAspectRatioResolved: ((CGFloat) -> Void)?
    private let observationSurface: String

    private var hasPosterSource: Bool {
        preparedReadingMedia == nil &&
            (thumbnailURL != nil || fallbackThumbnailURL != nil || generatesThumbnailWhenMissing)
    }

    private var displayedThumbnail: UIImage? {
        if let preparedReadingMedia {
            return thumbnailURL.flatMap { preparedReadingMedia[$0] }
        }
        return thumbnail
    }

    private var cachedTimelinePoster: UIImage? {
        guard usesTimelinePoster, let thumbnailURL else { return nil }
        return ImageLoader.shared.cachedImage(for: posterRequest(for: thumbnailURL))
    }

    private func posterRequest(for url: URL) -> ImageLoader.Request {
        let screen = UIScreen.main
        return ImageLoader.request(
            for: url,
            targetSize: CGSize(width: screen.bounds.width, height: min(screen.bounds.height, 440)),
            scale: screen.scale,
            isTimelinePreview: usesTimelinePoster
        )
    }

    init(
        url: URL,
        fallbackURL: URL? = nil,
        thumbnailURL: URL? = nil,
        fallbackThumbnailURL: URL? = nil,
        usesTimelinePoster: Bool = false,
        contentMode: ContentMode = .fit,
        chromeStyle: XVideoPlayerChromeStyle = .standard,
        isPlaybackActive: Bool = true,
        generatesThumbnailWhenMissing: Bool = true,
        reportsPlaybackEvents: Bool = false,
        observationSurface: String = "x-video",
        onAspectRatioResolved: ((CGFloat) -> Void)? = nil
    ) {
        _playbackURL = State(initialValue: url)
        self.fallbackURL = fallbackURL == url ? nil : fallbackURL
        self.thumbnailURL = thumbnailURL
        self.usesTimelinePoster = usesTimelinePoster
        self.fallbackThumbnailURL = fallbackThumbnailURL == thumbnailURL ? nil : fallbackThumbnailURL
        self.contentMode = contentMode
        self.chromeStyle = chromeStyle
        self.isPlaybackActive = isPlaybackActive
        self.generatesThumbnailWhenMissing = generatesThumbnailWhenMissing
        self.reportsPlaybackEvents = reportsPlaybackEvents
        self.observationSurface = observationSurface
        self.onAspectRatioResolved = onAspectRatioResolved
    }

    var body: some View {
        playbackSurface(fullscreen: false)
            .frame(maxWidth: .infinity)
            .clipped()
            .task(id: playbackURL) {
                if onAspectRatioResolved != nil {
                    async let thumbnailLoad: Void = loadThumbnail()
                    async let aspectRatioLoad: Void = loadVideoAspectRatio()
                    _ = await (thumbnailLoad, aspectRatioLoad)
                } else {
                    await loadThumbnail()
                }
            }
            .task(id: "\(isPlaybackActive):\(playbackURL.absoluteString)") {
                guard chromeStyle == .minimal, isPlaybackActive else { return }
                await preparePlaybackAsset()
            }
            .onDisappear {
                if !isFullscreenPresented { stopPlayback() }
            }
            .onChange(of: isPlaybackActive) { _, isActive in
                guard !isActive else { return }
                isFullscreenPresented = false
                stopPlayback()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { pausePlayback() }
            }
            .appFullScreenCover(isPresented: $isFullscreenPresented) {
                playbackSurface(fullscreen: true)
                    .statusBarHidden()
                    .appPresentationBackground(.black)
            }
    }

    private func playbackSurface(fullscreen: Bool) -> some View {
        ZStack {
            Color.black.ignoresSafeArea(fullscreen ? .container : [])

            if playbackState != .ready, let displayedThumbnail {
                Image(uiImage: displayedThumbnail)
                    .resizable()
                    .aspectRatio(contentMode: fullscreen ? .fit : contentMode)
                    .accessibilityHidden(true)
            } else if !fullscreen, hasPosterSource, playbackState == .idle, !thumbnailFailed, chromeStyle == .standard {
                ProgressView().tint(.white)
            }

            if let player, fullscreen == isFullscreenPresented {
                playerLayer(for: player, fullscreen: fullscreen)
            }

            switch playbackState {
            case .idle, .failed:
                VideoStartControls(
                    isRetry: playbackState == .failed,
                    onPlay: startPlayback,
                    onFullscreen: fullscreen ? nil : presentFullscreen
                )
            case .preparing:
                Button(action: pausePlayback) {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 48, height: 48)
                        .background(.black.opacity(0.56), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消加载视频")
            case .ready:
                if let player {
                    playbackControls(for: player, fullscreen: fullscreen)
                }
            }

            if fullscreen {
                VideoControlButton(
                    symbol: "xmark",
                    label: "退出全屏",
                    action: { isFullscreenPresented = false }
                )
                .background(.black.opacity(0.56), in: Circle())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 16)
            } else if hasPosterSource, thumbnailFailed, playbackState == .idle, chromeStyle == .standard {
                Button {
                    thumbnailFailed = false
                    Task { await loadThumbnail(ignoringCache: true) }
                } label: {
                    Label("重试封面", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.62), in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)
            }
        }
    }

    private func playerLayer(for player: AVPlayer, fullscreen: Bool) -> some View {
        XPlayerLayerView(
            player: player,
            videoGravity: fullscreen || contentMode == .fit ? .resizeAspect : .resizeAspectFill,
            onReadyForDisplay: {
                if self.player === player { markVideoReady() }
            },
            onFailure: { error in
                if self.player === player { markPlaybackFailed(error) }
            }
        )
        .id(ObjectIdentifier(player))
        .opacity(playbackState == .ready ? 1 : 0.001)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(player.publisher(for: \.timeControlStatus).receive(on: DispatchQueue.main)) { _ in
            guard self.player === player else { return }
            isPlaying = player.timeControlStatus != .paused && !hasReachedEnd
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)
                .receive(on: DispatchQueue.main)
        ) { notification in
            guard self.player === player,
                  let item = notification.object as? AVPlayerItem, item === player.currentItem else { return }
            hasReachedEnd = true
            isPlaying = false
            XVideoPlaybackSession.shared.finish(player, url: playbackURL)
        }
    }

    private func playbackControls(for player: AVPlayer, fullscreen: Bool) -> some View {
        ZStack(alignment: .bottom) {
            if fullscreen {
                HStack(spacing: 0) {
                    fullscreenTapArea(skip: -5)
                    fullscreenTapArea(skip: 5)
                }
            } else {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: presentFullscreen)
                    .accessibilityHidden(true)
            }

            if !fullscreen || showsFullscreenControls || !isPlaying {
                VideoPlaybackControls(
                    player: player,
                    isPlaying: isPlaying,
                    isMuted: isMuted,
                    hasReachedEnd: hasReachedEnd,
                    onTogglePlayback: {
                        if isPlaying { pausePlayback() }
                        else { startPlayback() }
                    },
                    onToggleMute: {
                        isMuted.toggle()
                        player.isMuted = isMuted
                    },
                    onSeek: seek(to:),
                    onFullscreen: fullscreen ? nil : presentFullscreen
                )
            }
        }
        .onChange(of: isPlaying) { _, playing in
            if fullscreen, !playing { showsFullscreenControls = true }
        }
    }

    private func fullscreenTapArea(skip seconds: Double) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { skip(by: seconds) }
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.16)) {
                    showsFullscreenControls.toggle()
                }
            }
            .accessibilityHidden(true)
    }

    private func skip(by seconds: Double) {
        guard let currentTime = player?.currentTime().seconds, currentTime.isFinite else { return }
        seek(to: currentTime + seconds)
    }

    private func seek(to seconds: Double) {
        guard let player, let duration = player.currentItem?.duration.seconds,
              duration.isFinite, duration > 0 else { return }
        let target = min(max(seconds, 0), duration)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        if target < duration { hasReachedEnd = false }
    }

    private func presentFullscreen() {
        guard isPlaybackActive else { return }
        if player == nil { startPlayback() }
        showsFullscreenControls = true
        isFullscreenPresented = true
    }

    private func startPlayback() {
        guard isPlaybackActive else { return }
        if let player {
            if hasReachedEnd {
                player.seek(to: .zero)
                hasReachedEnd = false
            }
            XVideoPlaybackSession.shared.play(player, url: playbackURL)
        } else {
            beginPlayback(with: playbackURL)
        }
    }

    private func pausePlayback() {
        if playbackState == .preparing {
            stopPlayback()
        } else if let player {
            XVideoPlaybackSession.shared.pause(player, url: playbackURL)
            isPlaying = false
        }
    }

    private func beginPlayback(with sourceURL: URL) {
        guard isPlaybackActive else { return }
        if reportsPlaybackEvents, observationSessionID == nil {
            observationSessionID = UUID().uuidString
            observationStartedAt = Date()
            reportPlaybackEvent("started", route: playbackRoute(for: sourceURL))
        }
        let asset = preparedAsset ?? AVURLAsset(url: sourceURL)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 1
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.isMuted = isMuted
        self.player = player
        hasReachedEnd = false
        isPlaying = true
        playbackState = .preparing
        XVideoPlaybackSession.shared.play(player, url: sourceURL, restoringPosition: true)
        scheduleFallbackIfNeeded(from: sourceURL)
    }

    @MainActor
    private func preparePlaybackAsset() async {
        guard preparedAsset == nil else { return }
        let asset = AVURLAsset(
            url: playbackURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        do {
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable, !Task.isCancelled, isPlaybackActive else { return }
            preparedAsset = asset
        } catch {
            // Playback remains available through the normal tap-to-load path.
        }
    }

    private func stopPlayback(resetObservation: Bool = true) {
        playbackFallbackTask?.cancel()
        playbackFallbackTask = nil
        if let player {
            XVideoPlaybackSession.shared.pause(player, url: playbackURL)
        }
        self.player = nil
        isPlaying = false
        hasReachedEnd = false
        playbackState = .idle
        if resetObservation {
            isMuted = true
            observationSessionID = nil
            observationStartedAt = nil
        }
    }

    private func markVideoReady() {
        guard playbackState == .preparing else { return }
        reportPlaybackEvent("first_frame", route: playbackRoute(for: playbackURL))
        playbackFallbackTask?.cancel()
        playbackFallbackTask = nil
        withAnimation(.easeOut(duration: 0.15)) {
            playbackState = .ready
        }
    }

    private func markPlaybackFailed(_ error: Error?) {
        guard playbackState == .preparing || playbackState == .ready else { return }
        reportPlaybackEvent(
            "failed",
            route: playbackRoute(for: playbackURL),
            message: Self.playbackFailureMessage(error)
        )
        if let fallbackURL, !hasUsedFallback, playbackURL != fallbackURL {
            switchToFallback(fallbackURL)
            return
        }
        stopPlayback()
        playbackState = .failed
    }

    private static func playbackFailureMessage(_ error: Error?) -> String {
        guard let error else { return "AVPlayer failed（未提供底层错误）" }
        var messages: [String] = []
        var current: NSError? = error as NSError
        while let item = current, messages.count < 3 {
            var message = "\(item.domain) \(item.code): \(item.localizedDescription)"
            if let reason = item.localizedFailureReason, reason != item.localizedDescription {
                message += "（\(reason)）"
            }
            messages.append(message)
            current = item.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return messages.joined(separator: " ← ").prefix(480).description
    }

    private func scheduleFallbackIfNeeded(from sourceURL: URL) {
        playbackFallbackTask?.cancel()
        guard let fallbackURL, !hasUsedFallback, sourceURL != fallbackURL else { return }
        playbackFallbackTask = Task { @MainActor in
            try? await Task.sleep(for: Self.directFirstFrameTimeout)
            guard !Task.isCancelled, playbackState == .preparing else { return }
            reportPlaybackEvent("fallback_timeout", route: "direct", message: "首帧等待超过 3 秒")
            switchToFallback(fallbackURL)
        }
    }

    private func switchToFallback(_ fallbackURL: URL) {
        stopPlayback(resetObservation: false)
        preparedAsset = nil
        hasUsedFallback = true
        playbackURL = fallbackURL
        reportPlaybackEvent("fallback_started", route: "proxy")
        beginPlayback(with: fallbackURL)
    }

    private func playbackRoute(for url: URL) -> String {
        url.path.hasSuffix("/media-proxy") || url == fallbackURL ? "proxy" : "direct"
    }

    private func reportPlaybackEvent(_ phase: String, route: String, message: String? = nil) {
        guard let sessionID = observationSessionID,
              let startedAt = observationStartedAt else { return }
        let event = XVideoPlaybackEvent(
            sessionID: sessionID,
            phase: phase,
            surface: observationSurface,
            route: route,
            videoURL: playbackURL.absoluteString,
            elapsedMS: max(0, Int(Date().timeIntervalSince(startedAt) * 1000)),
            message: message,
            occurredAt: ISO8601DateFormatter().string(from: Date())
        )
        Task {
            try? await APIClient(baseURL: ServerConfiguration.currentURL).reportXVideoPlaybackEvent(event)
        }
    }

    @MainActor
    private func loadThumbnail(ignoringCache: Bool = false) async {
        guard hasPosterSource, thumbnail == nil else { return }
        if !ignoringCache, let cached = Self.thumbnailCache.object(forKey: playbackURL as NSURL) {
            thumbnail = cached
            return
        }
        let resolvedThumbnailURL = thumbnailURL ?? (generatesThumbnailWhenMissing ? MediaURL.videoThumbnail(for: playbackURL) : nil)
        let thumbnailURLs = [resolvedThumbnailURL, fallbackThumbnailURL]
            .compactMap { $0 }
            .reduce(into: [URL]()) { result, url in
                if !result.contains(url) { result.append(url) }
            }
        for thumbnailURL in thumbnailURLs {
            guard !Task.isCancelled else { return }
            guard let remoteThumbnail = await ImageLoader.shared.image(for: posterRequest(for: thumbnailURL)) else { continue }
            guard !Task.isCancelled else { return }
            Self.thumbnailCache.setObject(remoteThumbnail, forKey: playbackURL as NSURL)
            thumbnail = remoteThumbnail
            thumbnailFailed = false
            return
        }
        guard generatesThumbnailWhenMissing else {
            thumbnailFailed = true
            return
        }
        guard !Task.isCancelled else { return }
        let asset = AVURLAsset(url: playbackURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_200, height: 1_200)
        do {
            let (image, _) = try await generator.image(at: .zero)
            guard !Task.isCancelled else { return }
            let result = UIImage(cgImage: image)
            Self.thumbnailCache.setObject(result, forKey: playbackURL as NSURL)
            thumbnail = result
            thumbnailFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            thumbnailFailed = true
        }
    }

    @MainActor
    private func loadVideoAspectRatio() async {
        guard let aspectRatio = await videoTrackAspectRatio(for: playbackURL) else { return }
        onAspectRatioResolved?(aspectRatio)
    }
}

private struct VideoStartControls: View {
    let isRetry: Bool
    let onPlay: () -> Void
    let onFullscreen: (() -> Void)?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button(action: onPlay) {
                Image(systemName: isRetry ? "arrow.clockwise" : "play.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.56), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRetry ? "重试播放视频" : "播放视频")

            if let onFullscreen {
                VideoControlButton(
                    symbol: "arrow.up.left.and.arrow.down.right",
                    label: "全屏播放",
                    action: onFullscreen
                )
                .background(.black.opacity(0.56), in: Circle())
                .padding(8)
            }
        }
    }
}

private struct VideoControlButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct VideoPlaybackControls: View {
    let player: AVPlayer
    let isPlaying: Bool
    let isMuted: Bool
    let hasReachedEnd: Bool
    let onTogglePlayback: () -> Void
    let onToggleMute: () -> Void
    let onSeek: (Double) -> Void
    let onFullscreen: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            VideoSeekBar(player: player, onSeek: onSeek)
                .padding(.horizontal, 12)

            HStack(spacing: 0) {
                VideoControlButton(
                    symbol: hasReachedEnd ? "arrow.counterclockwise" : (isPlaying ? "pause.fill" : "play.fill"),
                    label: hasReachedEnd ? "重新播放视频" : (isPlaying ? "暂停视频" : "继续播放视频"),
                    action: onTogglePlayback
                )
                Spacer()
                VideoControlButton(
                    symbol: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    label: isMuted ? "打开声音" : "静音",
                    action: onToggleMute
                )

                if let onFullscreen {
                    VideoControlButton(
                        symbol: "arrow.up.left.and.arrow.down.right",
                        label: "全屏播放",
                        action: onFullscreen
                    )
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 12)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }
}

private struct VideoSeekBar: View {
    let player: AVPlayer
    let onSeek: (Double) -> Void
    @State private var scrubTime: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            if let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 {
                let currentTime = player.currentTime().seconds
                let position = currentTime.isFinite ? min(max(currentTime, 0), duration) : 0
                HStack(spacing: 8) {
                    timeLabel(scrubTime ?? position)
                    Slider(
                        value: Binding(
                            get: { scrubTime ?? position },
                            set: { time in
                                if scrubTime == nil { onSeek(time) }
                                else { scrubTime = time }
                            }
                        ),
                        in: 0...duration,
                        onEditingChanged: { editing in
                            if editing {
                                scrubTime = position
                            } else if let time = scrubTime {
                                onSeek(time)
                                scrubTime = nil
                            }
                        }
                    )
                    .tint(.white)
                    .environment(\.colorScheme, .dark)
                    .accessibilityLabel("播放进度")
                    .accessibilityValue(Duration.seconds(scrubTime ?? position).formatted(.time(pattern: .minuteSecond)))
                    timeLabel(duration)
                }
            }
        }
    }

    private func timeLabel(_ seconds: Double) -> some View {
        Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .accessibilityHidden(true)
    }
}

private struct XPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?
    let videoGravity: AVLayerVideoGravity
    let onReadyForDisplay: () -> Void
    let onFailure: (Error?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onReadyForDisplay: onReadyForDisplay,
            onFailure: onFailure
        )
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        context.coordinator.observe(player: player, layer: view.playerLayer)
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        view.playerLayer.player = nil
        coordinator.stopObserving()
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    final class Coordinator {
        private let onReadyForDisplay: () -> Void
        private let onFailure: (Error?) -> Void
        private weak var observedPlayer: AVPlayer?
        private var readyObservation: NSKeyValueObservation?
        private var statusObservation: NSKeyValueObservation?
        private var failureObserver: NSObjectProtocol?

        init(
            onReadyForDisplay: @escaping () -> Void,
            onFailure: @escaping (Error?) -> Void
        ) {
            self.onReadyForDisplay = onReadyForDisplay
            self.onFailure = onFailure
        }

        func observe(player: AVPlayer?, layer: AVPlayerLayer) {
            guard observedPlayer !== player else { return }
            stopObserving()
            observedPlayer = player
            guard let player, let item = player.currentItem else { return }

            readyObservation = layer.observe(
                \.isReadyForDisplay,
                options: [.initial, .new]
            ) { [weak self] layer, _ in
                guard layer.isReadyForDisplay else { return }
                DispatchQueue.main.async {
                    self?.onReadyForDisplay()
                }
            }
            statusObservation = item.observe(
                \.status,
                options: [.initial, .new]
            ) { [weak self] item, _ in
                guard item.status == .failed else { return }
                DispatchQueue.main.async {
                    self?.onFailure(item.error)
                }
            }
            failureObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                    ?? item.error
                self?.onFailure(error)
            }
        }

        func stopObserving() {
            readyObservation = nil
            statusObservation = nil
            if let failureObserver {
                NotificationCenter.default.removeObserver(failureObserver)
            }
            failureObserver = nil
            observedPlayer = nil
        }

        deinit {
            stopObserving()
        }
    }
}

struct FeedEngagementRow: View {
    let post: Post
    var showsOnlyLikeAndBookmark = false
    var showsDetailActions = false
    var showsTimelineActions = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var isBookmarking = false
    @State private var isBookmarked = false
    @State private var bookmarkError: String?

    init(post: Post, showsOnlyLikeAndBookmark: Bool = false, showsDetailActions: Bool = false, showsTimelineActions: Bool = false) {
        self.post = post
        self.showsOnlyLikeAndBookmark = showsOnlyLikeAndBookmark
        self.showsDetailActions = showsDetailActions
        self.showsTimelineActions = showsTimelineActions
        _isBookmarked = State(initialValue: post.xTweetID.map(XBookmarkStore.contains) ?? false)
    }

    var body: some View {
        VStack(spacing: 6) {
            engagementActions
            if let bookmarkError {
                InlineActionNotice(message: bookmarkError, retry: saveBookmark) { self.bookmarkError = nil }
            }
        }
    }

    private var engagementActions: some View {
        HStack(spacing: showsTimelineActions ? 4 : 12) {
            if showsDetailActions || showsTimelineActions {
                metric("bubble", post.meta?.metrics?.replies, label: "回复")
                Spacer(minLength: 0)
                metric("arrow.2.squarepath", post.meta?.metrics?.retweets, label: "转帖")
            }
            Spacer(minLength: 0)
            metric("heart", post.meta?.metrics?.likes, label: "喜欢")
            if showsDetailActions || showsTimelineActions { Spacer(minLength: 0) }
            bookmarkButton
            if showsDetailActions || showsTimelineActions, let link = post.linkURL {
                Spacer(minLength: 0)
                ShareLink(item: link) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: showsTimelineActions ? 14 : 17))
                        .frame(width: showsTimelineActions ? 24 : 36, height: showsTimelineActions ? 32 : 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("分享帖子")
            }
        }
        .foregroundStyle(xToolbarColor)
        .frame(height: showsOnlyLikeAndBookmark ? 44 : 32)
        .contentShape(Rectangle())
        .sensoryFeedback(.success, trigger: isBookmarked)
    }

    private var bookmarkButton: some View {
        Button { saveBookmark() } label: {
            Group {
                if isBookmarking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14, weight: .regular))
                }
            }
            .frame(
                minHeight: showsOnlyLikeAndBookmark ? 44 : 32,
                alignment: .center
            )
            .frame(width: showsOnlyLikeAndBookmark ? 44 : 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isBookmarked ? xAccentColor : xToolbarColor)
        .disabled(isBookmarking || isBookmarked || post.xTweetID == nil)
        .accessibilityLabel(isBookmarked ? "已加入书签" : "加入书签")
    }

    private func saveBookmark() {
        guard let tweetID = post.xTweetID, !isBookmarking, !isBookmarked else { return }
        isBookmarking = true
        bookmarkError = nil
        Task {
            defer { isBookmarking = false }
            do {
                let result = try await APIClient(baseURL: ServerConfiguration.currentURL).bookmarkXPost(tweetID: tweetID)
                guard result.bookmarked else { throw APIError.invalidResponse }
                XBookmarkStore.insert(tweetID)
                isBookmarked = true
            } catch {
                bookmarkError = error.localizedDescription
            }
        }
    }

    private func metric(_ icon: String, _ value: Int?, label: String? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .frame(width: 18, height: 18)
            if let value, value > 0 {
                Text(compactCount(value))
                    .font(.system(size: 13, weight: .regular))
            }
        }
        .frame(
            minHeight: showsOnlyLikeAndBookmark ? 44 : 32,
            alignment: .leading
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "互动数据")
        .accessibilityValue(value.map(compactCount) ?? "0")
    }

    private var xToolbarColor: Color {
        colorScheme == .dark
            ? Color(red: 113 / 255, green: 118 / 255, blue: 123 / 255)
            : Color(red: 83 / 255, green: 100 / 255, blue: 113 / 255)
    }

    private var xAccentColor: Color {
        Color(red: 29 / 255, green: 155 / 255, blue: 240 / 255)
    }

    private func compactCount(_ value: Int) -> String {
        if value >= 10_000 {
            return String(format: "%.1f万", Double(value) / 10_000)
                .replacingOccurrences(of: ".0万", with: "万")
        }
        return String(value)
    }
}

private enum XBookmarkStore {
    private static let key = "x.bookmarkedTweetIDs"

    static func contains(_ tweetID: String) -> Bool {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? []).contains(tweetID)
    }

    static func insert(_ tweetID: String) {
        var values = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        values.insert(tweetID)
        UserDefaults.standard.set(values.sorted(), forKey: key)
    }
}

extension View {
    func imageGallery(item: Binding<ImageGallerySelection?>) -> some View {
        modifier(ImageGalleryPresentationModifier(selection: item))
    }
}

private struct ImageGalleryPresentationModifier: ViewModifier {
    @Binding var selection: ImageGallerySelection?

    func body(content: Content) -> some View {
        content.background {
            if selection != nil {
                ImageGalleryPresentationBridge(selection: $selection)
                    .frame(width: 0, height: 0)
            }
        }
    }
}

private struct ImageGalleryPresentationBridge: UIViewControllerRepresentable {
    @Binding var selection: ImageGallerySelection?
    @Environment(\.knowledgeReading) private var knowledgeReading

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.knowledgeReading = knowledgeReading
        guard let selection else {
            context.coordinator.dismiss(animated: false)
            return
        }
        context.coordinator.present(selection, from: controller)
    }

    static func dismantleUIViewController(
        _ controller: UIViewController,
        coordinator: Coordinator
    ) {
        coordinator.dismiss(animated: false)
    }

    @MainActor
    final class Coordinator {
        var selection: Binding<ImageGallerySelection?>
        var knowledgeReading = false
        private var hostingController: UIViewController?
        private var presentedSelectionID: UUID?
        private var pendingSelectionID: UUID?
        private var isDismissing = false

        init(selection: Binding<ImageGallerySelection?>) {
            self.selection = selection
        }

        func present(_ selection: ImageGallerySelection, from controller: UIViewController) {
            guard presentedSelectionID != selection.id, hostingController == nil else { return }
            guard controller.viewIfLoaded?.window != nil else {
                guard pendingSelectionID != selection.id else { return }
                pendingSelectionID = selection.id
                DispatchQueue.main.async { [weak self, weak controller] in
                    guard let self, let controller else { return }
                    self.pendingSelectionID = nil
                    guard controller.viewIfLoaded?.window != nil,
                          let selection = self.selection.wrappedValue else { return }
                    self.present(selection, from: controller)
                }
                return
            }

            pendingSelectionID = nil
            presentedSelectionID = selection.id
            let gallery = ImageGalleryView(
                urls: selection.urls,
                initialIndex: selection.initialIndex,
                knowledgeReading: knowledgeReading
            ) { [weak self] in
                self?.dismiss(animated: true)
            }
            let hostingController = UIHostingController(rootView: gallery)
            hostingController.view.backgroundColor = .clear
            hostingController.modalPresentationStyle = .overFullScreen
            hostingController.modalTransitionStyle = .crossDissolve
            self.hostingController = hostingController
            controller.present(hostingController, animated: true)
        }

        func dismiss(animated: Bool) {
            guard !isDismissing else { return }
            guard let hostingController else {
                presentedSelectionID = nil
                return
            }

            isDismissing = true
            let dismissedSelectionID = presentedSelectionID
            hostingController.dismiss(animated: animated) { [weak self] in
                guard let self else { return }
                self.hostingController = nil
                self.presentedSelectionID = nil
                self.isDismissing = false
                // UIKit can finish synchronously while SwiftUI is dismantling the bridge.
                Task { @MainActor [weak self] in
                    guard let self, self.selection.wrappedValue?.id == dismissedSelectionID else { return }
                    self.selection.wrappedValue = nil
                }
            }
        }
    }
}

struct ImageGalleryView: View {
    let urls: [URL]
    private let onDismiss: (() -> Void)?
    private let knowledgeReading: Bool
    @Environment(\.dismiss) private var environmentDismiss
    @State private var selectedIndex: Int

    init(
        urls: [URL],
        initialIndex: Int = 0,
        knowledgeReading: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) {
        let requestedURL = urls.indices.contains(initialIndex) ? urls[initialIndex] : urls.first
        var seen: Set<URL> = []
        let uniqueURLs = urls.filter { seen.insert($0).inserted }
        self.urls = uniqueURLs
        self.onDismiss = onDismiss
        self.knowledgeReading = knowledgeReading
        _selectedIndex = State(
            initialValue: requestedURL.flatMap(uniqueURLs.firstIndex(of:)) ?? 0
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if urls.isEmpty {
                ContentUnavailableView(
                    "图片不可用",
                    systemImage: "photo",
                    description: Text("没有可预览的图片")
                )
                .foregroundStyle(.white)
            } else {
                TabView(selection: $selectedIndex) {
                    ForEach(urls.indices, id: \.self) { index in
                        GalleryImagePage(
                            url: urls[index],
                            isActive: selectedIndex == index,
                            position: index + 1,
                            count: urls.count,
                            onBackgroundTap: requestDismiss
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            if urls.count > 1 && !knowledgeReading {
                Text("\(selectedIndex + 1) / \(urls.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(.black.opacity(0.56), in: Capsule())
                    .accessibilityLabel("第 \(selectedIndex + 1) 张，共 \(urls.count) 张")
                    .padding(.top, 10)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if knowledgeReading {
                galleryToolbar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                galleryControl("关闭图片", symbol: "xmark", action: requestDismiss)
                    .background(.black.opacity(0.56), in: Circle())
                    .padding(16)
            }
        }
        .statusBarHidden()
        .interactiveDismissDisabled()
        .accessibilityAction(.escape, requestDismiss)
    }

    private var galleryToolbar: some View {
        HStack(spacing: 5) {
            if !urls.isEmpty {
                galleryControl("上一张", symbol: "chevron.left") { selectedIndex -= 1 }
                    .disabled(selectedIndex <= 0)
                Text("\(selectedIndex + 1) / \(urls.count)")
                    .font(.subheadline.monospacedDigit())
                    .accessibilityLabel("第 \(selectedIndex + 1) 张，共 \(urls.count) 张")
                galleryControl("下一张", symbol: "chevron.right") { selectedIndex += 1 }
                    .disabled(selectedIndex + 1 >= urls.count)
            }
            Spacer(minLength: 4)
            if urls.indices.contains(selectedIndex) {
                ShareLink(item: urls[selectedIndex]) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("分享图片链接")
            }
            galleryControl("关闭图片", symbol: "xmark", action: requestDismiss)
        }
        .foregroundStyle(.white)
        .padding(4)
        .background(Color(red: 0.12, green: 0.15, blue: 0.20), in: .rect(cornerRadius: 16))
        .frame(maxWidth: 530)
        .frame(maxWidth: .infinity)
    }

    private func galleryControl(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }

    private func requestDismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            environmentDismiss()
        }
    }
}

private struct GalleryImagePage: View {
    let url: URL
    let isActive: Bool
    let position: Int
    let count: Int
    let onBackgroundTap: () -> Void
    @State private var image: UIImage?
    @State private var didFail = false
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onBackgroundTap)

                if let image {
                    let imageSize = fittedImageSize(image, in: proxy.size)
                    Image(uiImage: image)
                        .resizable()
                        .frame(
                            width: imageSize.width,
                            height: imageSize.height
                        )
                        .scaleEffect(scale)
                        .offset(offset)
                        .contentShape(Rectangle())
                        .gesture(
                            dragGesture(in: proxy.size),
                            including: scale > 1 ? .all : .none
                        )
                        .simultaneousGesture(magnificationGesture(in: proxy.size))
                        .onTapGesture(count: 2) {
                            toggleZoom(in: proxy.size)
                        }
                } else if didFail {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                        Text("图片加载失败")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .task(id: url) {
            didFail = false
            image = await ImageLoader.load(url)
            didFail = image == nil
            resetZoom()
        }
        .onChange(of: isActive) { _, active in
            if !active { resetZoom() }
        }
        .accessibilityLabel("第 \(position) 张图片，共 \(count) 张")
        .accessibilityHint(count > 1 ? "左右滑动切换，双击或捏合缩放" : "双击或捏合缩放")
    }

    private func magnificationGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(settledScale * value.magnification, 1), 5)
                offset = clamped(offset, in: size, at: scale)
            }
            .onEnded { _ in
                settledScale = scale
                if scale <= 1 {
                    resetZoom()
                } else {
                    offset = clamped(offset, in: size, at: scale)
                    settledOffset = offset
                }
            }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                let proposed = CGSize(
                    width: settledOffset.width + value.translation.width,
                    height: settledOffset.height + value.translation.height
                )
                offset = clamped(proposed, in: size, at: scale)
            }
            .onEnded { _ in
                settledOffset = clamped(offset, in: size, at: scale)
                offset = settledOffset
            }
    }

    private func clamped(_ value: CGSize, in size: CGSize, at scale: CGFloat) -> CGSize {
        guard scale > 1, let image else { return .zero }
        let fittedSize = fittedImageSize(image, in: size)
        let maximumX = max(0, (fittedSize.width * scale - size.width) / 2)
        let maximumY = max(0, (fittedSize.height * scale - size.height) / 2)
        return CGSize(
            width: min(max(value.width, -maximumX), maximumX),
            height: min(max(value.height, -maximumY), maximumY)
        )
    }

    private func fittedImageSize(_ image: UIImage, in containerSize: CGSize) -> CGSize {
        guard image.size.width > 0,
              image.size.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return containerSize
        }
        let fitScale = min(
            containerSize.width / image.size.width,
            containerSize.height / image.size.height
        )
        return CGSize(
            width: image.size.width * fitScale,
            height: image.size.height * fitScale
        )
    }

    private func toggleZoom(in size: CGSize) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            if scale > 1 {
                resetZoom()
            } else {
                scale = 2
                settledScale = 2
                offset = clamped(offset, in: size, at: 2)
                settledOffset = offset
            }
        }
    }

    private func resetZoom() {
        scale = 1
        settledScale = 1
        offset = .zero
        settledOffset = .zero
    }
}

struct PostActionRow: View {
    let post: Post
    var body: some View {
        HStack {
            action("arrowshape.turn.up.left", "回复")
            Spacer(); action("arrow.2.squarepath", "转发")
            Spacer(); action("heart", "赞")
            Spacer(); Image(systemName: "bookmark").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func action(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.caption).foregroundStyle(.secondary)
    }
}

func videoTrackAspectRatio(for url: URL) async -> CGFloat? {
    let asset = AVURLAsset(url: url)
    guard let track = try? await asset.loadTracks(withMediaType: .video).first,
          let naturalSize = try? await track.load(.naturalSize),
          let preferredTransform = try? await track.load(.preferredTransform),
          !Task.isCancelled else { return nil }
    let displayedSize = naturalSize.applying(preferredTransform)
    let width = abs(displayedSize.width)
    let height = abs(displayedSize.height)
    guard width > 0, height > 0 else { return nil }
    return width / height
}
