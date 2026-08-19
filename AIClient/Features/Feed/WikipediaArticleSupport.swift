import NaturalLanguage
import SwiftUI
import WebKit

struct WikipediaEntity: Identifiable, Hashable {
    let id: String
    let term: String
    let title: String
    let summary: String
    let url: URL
}

struct WikipediaSelection: Identifiable {
    let paragraphIndex: Int
    let entity: WikipediaEntity

    var id: String { "\(paragraphIndex)-\(entity.id)" }
}

enum WikipediaEntityCandidateExtractor {
    private static let englishNameRegex = try! NSRegularExpression(
        pattern: #"\b(?:[A-Z][A-Za-z0-9&.'-]*|[A-Z]{2,})(?:\s+(?:[A-Z][A-Za-z0-9&.'-]*|[A-Z]{2,})){0,3}\b"#
    )
    private static let ignoredEnglishTerms: Set<String> = [
        "A", "An", "And", "As", "At", "But", "For", "From", "In", "New", "Of", "On", "Or", "The", "To", "With"
    ]
    private static let commonChineseEntities = [
        "美国", "中国", "英国", "法国", "德国", "日本", "韩国", "印度", "俄罗斯", "加拿大", "澳大利亚",
        "欧洲", "亚洲", "非洲", "欧盟", "联合国", "华尔街", "纽约时报", "微软", "英伟达", "苹果", "谷歌",
        "亚马逊", "特斯拉", "脸书", "人工智能"
    ]

    static func candidates(in paragraphs: [String], limit: Int = 96) -> [String] {
        var results: [String] = []
        var seen = Set<String>()

        // Reserve space for high-signal entities across the whole article before
        // early paragraphs can consume the candidate budget.
        for paragraph in paragraphs {
            for entity in commonChineseEntities where paragraph.contains(entity) {
                append(entity, to: &results, seen: &seen, limit: limit)
            }
        }

        for paragraph in paragraphs {
            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = paragraph
            let fullRange = paragraph.startIndex..<paragraph.endIndex
            tagger.enumerateTags(
                in: fullRange,
                unit: .word,
                scheme: .nameType,
                options: [.joinNames, .omitWhitespace, .omitPunctuation]
            ) { tag, range in
                guard [.personalName, .placeName, .organizationName].contains(tag) else { return true }
                append(String(paragraph[range]), to: &results, seen: &seen, limit: limit)
                return results.count < limit
            }

            let nsRange = NSRange(paragraph.startIndex..<paragraph.endIndex, in: paragraph)
            for match in englishNameRegex.matches(in: paragraph, range: nsRange) {
                guard let range = Range(match.range, in: paragraph) else { continue }
                let value = String(paragraph[range])
                guard !ignoredEnglishTerms.contains(value) else { continue }
                append(value, to: &results, seen: &seen, limit: limit)
                if results.count == limit { break }
            }

            if results.count == limit { break }
        }

        return results
    }

    private static func append(_ raw: String, to results: inout [String], seen: inout Set<String>, limit: Int) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard results.count < limit,
              value.count >= 2,
              value.count <= 40,
              value.rangeOfCharacter(from: .letters) != nil else { return }
        let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard seen.insert(key).inserted else { return }
        results.append(value)
    }
}

actor WikipediaEntityResolver {
    static let shared = WikipediaEntityResolver()

    private enum CacheEntry { case found(WikipediaEntity), missing }
    private var cache: [String: CacheEntry] = [:]

    func resolve(paragraphs: [String]) async -> [Int: [WikipediaEntity]] {
        let candidates = WikipediaEntityCandidateExtractor.candidates(in: paragraphs)
        guard !candidates.isEmpty else { return [:] }

        var resolved: [String: WikipediaEntity] = [:]
        var uncached: [String] = []
        for candidate in candidates {
            let key = cacheKey(candidate, language: "zh")
            switch cache[key] {
            case .found(let entity): resolved[candidate] = entity
            case .missing: break
            case nil: uncached.append(candidate)
            }
        }

        if !uncached.isEmpty {
            var fetched: [String: WikipediaEntity] = [:]
            for start in stride(from: 0, to: uncached.count, by: 40) {
                let end = min(start + 40, uncached.count)
                let batch = Array(uncached[start..<end])
                let batchResult = (try? await fetch(titles: batch, language: "zh")) ?? [:]
                fetched.merge(batchResult) { _, latest in latest }
            }
            for candidate in uncached {
                let key = cacheKey(candidate, language: "zh")
                if let entity = fetched[candidate] {
                    cache[key] = .found(entity)
                    resolved[candidate] = entity
                } else {
                    cache[key] = .missing
                }
            }
        }

        var result: [Int: [WikipediaEntity]] = [:]
        for (index, paragraph) in paragraphs.enumerated() {
            let entities = candidates.compactMap { candidate -> WikipediaEntity? in
                guard paragraph.range(of: candidate, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { return nil }
                return resolved[candidate]
            }
            if !entities.isEmpty { result[index] = entities }
        }
        return result
    }

    private func fetch(titles: [String], language: String) async throws -> [String: WikipediaEntity] {
        let pages = try await APIClient(baseURL: ServerConfiguration.currentURL)
            .fetchWikipediaEntities(titles: titles, language: language)
        var result: [String: WikipediaEntity] = [:]
        for page in pages {
            let trimmedSummary = page.extract?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let summary = trimmedSummary.isEmpty ? "查看维基百科中的完整词条。" : trimmedSummary
            result[page.query] = WikipediaEntity(
                id: "\(page.language)-\(page.pageID)",
                term: page.query,
                title: page.title,
                summary: String(summary.prefix(120)),
                url: page.articleURL
            )
        }
        return result
    }

    private func cacheKey(_ title: String, language: String) -> String {
        "\(language):\(title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))"
    }
}

private struct WikipediaQueryResponse: Decodable {
    let query: Query?

    struct Query: Decodable {
        let normalized: [Alias]?
        let redirects: [Alias]?
        let pages: [Page]?
    }

    struct Alias: Decodable { let from: String; let to: String }
    struct Page: Decodable {
        let pageid: Int?
        let title: String
        let extract: String?
        let fullurl: String?
        let missing: Bool?
    }
}

struct WikipediaLinkedParagraph: View {
    let text: String
    let entities: [WikipediaEntity]
    let select: (WikipediaEntity) -> Void

    var body: some View {
        Text(attributedText)
            .font(.system(size: 18, weight: .regular, design: .serif))
            .lineSpacing(8)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "aiserver-wikipedia",
                      let entity = entities.first(where: { $0.id == url.host }) else { return .systemAction }
                select(entity)
                return .handled
            })
    }

    private var attributedText: AttributedString {
        var value = AttributedString(text)
        for entity in entities {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(
                    of: entity.term,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchStart..<text.endIndex
                  ) {
                if let lower = AttributedString.Index(range.lowerBound, within: value),
                   let upper = AttributedString.Index(range.upperBound, within: value) {
                    let attributedRange = lower..<upper
                    value[attributedRange].link = URL(string: "aiserver-wikipedia://\(entity.id)")
                    value[attributedRange].underlineStyle = Text.LineStyle(pattern: .dot, color: .accentColor)
                    value[attributedRange].foregroundColor = .primary
                }
                searchStart = range.upperBound
            }
        }
        return value
    }
}

struct WikipediaEntityCard: View {
    let entity: WikipediaEntity
    let open: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("W")
                    .font(.system(size: 28, weight: .medium, design: .serif))
                    .frame(width: 48, height: 48)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    Text(entity.title).font(.headline)
                    Text(entity.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭词条卡片")
            }

            Divider()
            Button(action: open) {
                HStack {
                    Text("查看维基百科")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .font(.system(size: 16, weight: .medium))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.16)))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
    }
}

struct WikipediaReaderView: View {
    let entity: WikipediaEntity
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var browser = WikipediaBrowserModel()
    @State private var presentedLink: WikipediaEntity?
    @State private var article: WikipediaRelayArticle?
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            readerHeader

            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    if let article {
                        WikipediaWebView(
                            url: article.articleURL,
                            html: WikipediaRelayedHTML.document(
                                article.html,
                                title: article.title,
                                baseURL: article.articleURL
                            ),
                            model: browser
                        ) {
                            presentedLink = $0
                        }
                        .id(article.pageID)
                    } else if let loadError {
                        ContentUnavailableView {
                            Label("百科内容载入失败", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(loadError)
                        } actions: {
                            Button("重试") { Task { await loadArticle() } }
                        }
                    } else {
                        ProgressView("正在通过服务器载入百科…")
                    }

                    readerToolbar
                        .padding(.horizontal, 18)
                        .padding(.bottom, max(12, proxy.safeAreaInsets.bottom))
                }
            }
        }
        .background(archivePaper.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            DetailSheetCloseButton(
                action: dismiss.callAsFunction,
                accessibilityLabel: entity.url.isWikipediaURL ? "关闭维基百科" : "关闭网页"
            )
            .padding(.trailing, 16)
            .padding(.bottom, 76)
        }
        .task(id: entity.url) { await loadArticle() }
        .sheet(item: $presentedLink) { linkedEntity in
            if linkedEntity.url.isWikipediaURL {
                WikipediaReaderView(entity: linkedEntity)
                    .wikipediaReaderPresentation()
            } else {
                ServerArticleReaderView(url: linkedEntity.url)
                    .overlay(alignment: .bottomTrailing) {
                        DetailSheetCloseButton(
                            action: { presentedLink = nil },
                            accessibilityLabel: "关闭网页详情"
                        )
                        .padding(16)
                    }
            }
        }
    }

    private func loadArticle() async {
        loadError = nil
        do {
            let language = entity.url.host?.lowercased().hasPrefix("en.") == true ? "en" : "zh"
            article = try await APIClient(baseURL: ServerConfiguration.currentURL)
                .fetchWikipediaArticle(title: entity.title, language: language)
        } catch {
            article = nil
            loadError = NetworkErrorPresentation.message(for: error)
        }
    }

    private var readerHeader: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(browser.currentTitle ?? entity.title)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(archiveAccent)
                    .lineLimit(1)
                    .padding(.horizontal, 112)

                HStack {
                    Text(entity.url.isWikipediaURL ? "WIKIPEDIA · 中文" : (entity.url.host ?? "网页"))
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .tracking(0.8)
                        .foregroundStyle(.primary.opacity(0.72))
                    Spacer()
                    if !browser.isOriginalMode, browser.pageCount > 1 {
                        Text(String(format: "%02d / %02d", browser.pageIndex + 1, browser.pageCount))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                    }
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 62)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.10))
                    Rectangle()
                        .fill(archiveAccent)
                        .frame(width: proxy.size.width * CGFloat(displayedProgress))
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 18)
        }
    }

    private var readerToolbar: some View {
        HStack(spacing: 0) {
            readerToolbarButton("上一页", systemImage: "chevron.left") {
                browser.goToPreviousPage()
            }
            .disabled(!browser.canGoToPreviousPage)

            Divider().frame(height: 24)

            readerToolbarButton("目录", systemImage: "list.bullet") {
                browser.toggleTableOfContents()
            }
            .disabled(!entity.url.isWikipediaURL)

            Divider().frame(height: 24)

            readerToolbarButton(
                browser.isOriginalMode ? "幻灯片" : "原文",
                systemImage: browser.isOriginalMode ? "rectangle.on.rectangle" : "doc.text"
            ) {
                browser.toggleOriginalMode()
            }

            Divider().frame(height: 24)

            readerToolbarButton("原站", systemImage: "arrow.up.right.square") {
                openURL(browser.currentURL ?? entity.url)
            }
        }
        .frame(height: 58)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }

    private func readerToolbarButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(archiveAccent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var displayedProgress: Double {
        if browser.isLoading { return browser.progress }
        if browser.isOriginalMode { return max(0.02, browser.scrollProgress) }
        return min(1, max(0.02, Double(browser.pageIndex + 1) / Double(max(1, browser.pageCount))))
    }

    private var archivePaper: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.105, blue: 0.095, alpha: 1)
                : UIColor(red: 0.985, green: 0.969, blue: 0.925, alpha: 1)
        })
    }

    private var archiveAccent: Color { Color(red: 0.55, green: 0.25, blue: 0.16) }
}

@MainActor
final class WikipediaBrowserModel: ObservableObject {
    @Published var isLoading = true
    @Published var progress = 0.05
    @Published var scrollProgress = 0.0
    @Published var canGoBack = false
    @Published var currentTitle: String?
    @Published var currentURL: URL?
    @Published var pageIndex = 0
    @Published var pageCount = 1
    @Published var isOriginalMode = false
    fileprivate weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
        update(from: webView)
    }

    func update(from webView: WKWebView) {
        isLoading = webView.isLoading
        progress = max(webView.estimatedProgress, 0.05)
        canGoBack = webView.canGoBack
        currentURL = webView.url
        updateScrollProgress(from: webView.scrollView)
    }

    func goBack() { webView?.goBack() }

    var canGoToPreviousPage: Bool {
        isOriginalMode ? canGoBack : (pageIndex > 0 || canGoBack)
    }

    func goToPreviousPage() {
        if pageIndex > 0 && !isOriginalMode {
            webView?.evaluateJavaScript("window.__aiserverDeckPrevious?.()")
        } else if canGoBack {
            webView?.goBack()
        }
    }

    func toggleTableOfContents() {
        webView?.evaluateJavaScript("window.__aiserverToggleTOC?.()")
    }

    func toggleOriginalMode() {
        webView?.evaluateJavaScript("window.__aiserverToggleOriginal?.()")
    }

    func updateDeckState(pageIndex: Int, pageCount: Int, isOriginalMode: Bool) {
        self.pageIndex = min(max(0, pageIndex), max(0, pageCount - 1))
        self.pageCount = max(1, pageCount)
        self.isOriginalMode = isOriginalMode
    }

    func updateScrollProgress(from scrollView: UIScrollView) {
        let scrollableHeight = max(1, scrollView.contentSize.height - scrollView.bounds.height)
        scrollProgress = min(1, max(0, scrollView.contentOffset.y / scrollableHeight))
    }

    func updateTitle(_ title: String?) {
        let cleaned = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        currentTitle = cleaned.isEmpty ? nil : cleaned
    }
}

extension View {
    func wikipediaReaderPresentation() -> some View {
        presentationDetents([.fraction(0.82), .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
    }
}

enum WikipediaReaderStyle {
    static let script = #"""
    (() => {
      if (!/(^|\.)wikipedia\.org$/i.test(window.location.hostname)) return;

      const styleID = "aiserver-wikipedia-reader-style";

      const installReaderStyle = () => {
        if (!document.documentElement || document.getElementById(styleID)) {
          if (!document.documentElement) requestAnimationFrame(installReaderStyle);
          return;
        }

        const style = document.createElement("style");
        style.id = styleID;
        style.textContent = `
          :root {
            color-scheme: light !important;
            --aiserver-paper: #fbf7ed;
            --aiserver-card: #f3ecdf;
            --aiserver-ink: #27231f;
            --aiserver-muted: #746d64;
            --aiserver-accent: #8c4029;
            --aiserver-link: #745344;
            --aiserver-rule: rgba(109, 72, 52, 0.22);
          }

          html, body {
            background: var(--aiserver-paper) !important;
            color: var(--aiserver-ink) !important;
            font-family: "Songti SC", Georgia, "Times New Roman", serif !important;
            font-size: 18px !important;
            line-height: 1.76 !important;
            margin: 0 !important;
            padding: 0 !important;
            overflow-x: hidden !important;
          }

          header, footer,
          .mw-header, .minerva-header, .vector-header-container,
          .vector-page-toolbar, .page-actions-menu, .page-actions-menu__list,
          .mw-footer-container, .minerva-footer, #footer,
          #p-lang-btn, #p-lang, .mw-portlet-lang, .uls-language-list,
          .mw-indicators, .mw-editsection, .mw-jump-link,
          .vector-toc, .sidebar-toc, .toc, #toc,
          .shortdescription, .noprint, .nomobile,
          .banner-container, .centralNotice, #siteNotice,
          .post-content, .printfooter, .catlinks,
          #mw-mf-page-center__mask, #mw-mf-page-left,
          .vector-sticky-header, .vector-column-start,
          .vector-column-end, .vector-page-tools {
            display: none !important;
          }

          .mw-page-container,
          .mw-page-container-inner,
          .mw-content-container,
          .mw-body,
          .mw-body-content,
          main,
          #content {
            background: var(--aiserver-paper) !important;
            border: 0 !important;
            box-shadow: none !important;
            display: block !important;
            float: none !important;
            grid-area: auto !important;
            margin: 0 !important;
            max-width: none !important;
            min-width: 0 !important;
            padding-left: 0 !important;
            padding-right: 0 !important;
            width: auto !important;
          }

          #content, .mw-body {
            padding: 22px 22px 132px !important;
          }

          #firstHeading {
            border-bottom: 1px solid var(--aiserver-rule) !important;
            color: var(--aiserver-accent) !important;
            font-family: "Songti SC", Georgia, "Times New Roman", serif !important;
            font-size: 2.25rem !important;
            font-weight: 700 !important;
            letter-spacing: -0.02em !important;
            line-height: 1.16 !important;
            margin: 0 0 24px !important;
            padding: 0 0 20px !important;
          }

          #firstHeading::before {
            color: var(--aiserver-muted);
            content: "来自维基百科，自由的百科全书";
            display: block;
            font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif;
            font-size: 0.64rem;
            font-weight: 600;
            letter-spacing: 0.08em;
            line-height: 1.4;
            margin-bottom: 14px;
          }

          .mw-parser-output {
            color: var(--aiserver-ink) !important;
            font-size: 1rem !important;
            line-height: 1.76 !important;
          }

          .mw-parser-output p {
            margin: 0 0 1.15em !important;
          }

          .mw-parser-output h2 {
            border-bottom: 1px solid var(--aiserver-rule) !important;
            color: var(--aiserver-accent) !important;
            font-family: "Songti SC", Georgia, "Times New Roman", serif !important;
            font-size: 1.55rem !important;
            font-weight: 700 !important;
            line-height: 1.3 !important;
            margin: 1.65em 0 0.8em !important;
            padding-bottom: 0.35em !important;
          }

          .mw-parser-output h3,
          .mw-parser-output h4 {
            color: var(--aiserver-ink) !important;
            font-family: "Songti SC", Georgia, "Times New Roman", serif !important;
            font-weight: 650 !important;
            line-height: 1.35 !important;
            margin: 1.45em 0 0.65em !important;
          }

          a, a:visited {
            color: var(--aiserver-link) !important;
            text-decoration-color: rgba(116, 83, 68, 0.35) !important;
            text-decoration-thickness: 1px !important;
            text-underline-offset: 3px !important;
          }

          figure, .thumb, .thumbinner, .mw-halign-right, .mw-halign-left {
            background: transparent !important;
            border: 0 !important;
            box-sizing: border-box !important;
            float: none !important;
            margin: 1.2em 0 !important;
            max-width: 100% !important;
            padding: 0 !important;
            width: 100% !important;
          }

          figure img, .thumb img, img.mw-file-element {
            border: 0 !important;
            border-radius: 12px !important;
            box-sizing: border-box !important;
            height: auto !important;
            max-width: 100% !important;
          }

          figcaption, .thumbcaption {
            color: var(--aiserver-muted) !important;
            font-size: 0.78rem !important;
            line-height: 1.45 !important;
            padding: 8px 2px 0 !important;
          }

          table {
            border-collapse: collapse !important;
            display: block !important;
            font-size: 0.88rem !important;
            max-width: 100% !important;
            overflow-x: auto !important;
            -webkit-overflow-scrolling: touch;
          }

          .infobox {
            background: var(--aiserver-card) !important;
            border: 1px solid var(--aiserver-rule) !important;
            border-radius: 14px !important;
            box-sizing: border-box !important;
            float: none !important;
            margin: 1.25em 0 !important;
            padding: 12px !important;
            width: 100% !important;
          }

          .hatnote, .dablink, .rellink {
            background: var(--aiserver-card) !important;
            border: 1px solid var(--aiserver-rule) !important;
            border-radius: 12px !important;
            box-sizing: border-box !important;
            color: var(--aiserver-muted) !important;
            font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif !important;
            font-size: 0.88rem !important;
            margin: 0 0 1.2em !important;
            padding: 11px 13px !important;
          }

          table.ambox {
            background: var(--aiserver-card) !important;
            border: 1px solid var(--aiserver-rule) !important;
            border-left: 3px solid var(--aiserver-accent) !important;
            border-radius: 10px !important;
            color: var(--aiserver-muted) !important;
            display: table !important;
            font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif !important;
            font-size: 0.82rem !important;
            margin: 0 0 1.2em !important;
            overflow: hidden !important;
            width: 100% !important;
          }

          table.ambox td {
            border: 0 !important;
            padding: 9px 10px !important;
          }

          table.ambox .mbox-image {
            filter: grayscale(1) sepia(0.45);
            opacity: 0.62;
            width: 34px !important;
          }

          blockquote {
            border-left: 3px solid var(--aiserver-accent) !important;
            color: var(--aiserver-muted) !important;
            margin: 1.2em 0 !important;
            padding: 0.1em 0 0.1em 1em !important;
          }

          sup.reference {
            font-size: 0.7em !important;
            line-height: 0 !important;
          }

          #aiserver-archive-toc {
            -webkit-backdrop-filter: blur(22px);
            backdrop-filter: blur(22px);
            background: rgba(251, 247, 237, 0.96);
            border: 1px solid var(--aiserver-rule);
            border-radius: 22px;
            box-shadow: 0 22px 64px rgba(58, 39, 27, 0.22);
            box-sizing: border-box;
            color: var(--aiserver-ink);
            left: 16px;
            max-height: min(68vh, 560px);
            opacity: 1;
            overflow: hidden;
            position: fixed;
            right: 16px;
            top: 18px;
            transform: translateY(0);
            transition: opacity 180ms ease, transform 180ms ease, visibility 180ms;
            visibility: visible;
            z-index: 2147483647;
          }

          #aiserver-archive-toc.aiserver-hidden {
            opacity: 0;
            pointer-events: none;
            transform: translateY(-10px);
            visibility: hidden;
          }

          .aiserver-toc-header {
            align-items: center;
            border-bottom: 1px solid var(--aiserver-rule);
            display: flex;
            justify-content: space-between;
            padding: 17px 18px 14px;
          }

          .aiserver-toc-title {
            color: var(--aiserver-accent);
            font-size: 1.18rem;
            font-weight: 700;
          }

          .aiserver-toc-close {
            appearance: none;
            background: rgba(140, 64, 41, 0.08);
            border: 0;
            border-radius: 50%;
            color: var(--aiserver-accent);
            font-size: 1.3rem;
            height: 32px;
            line-height: 1;
            width: 32px;
          }

          .aiserver-toc-list {
            box-sizing: border-box;
            max-height: calc(min(68vh, 560px) - 66px);
            overflow-y: auto;
            padding: 8px 18px 18px;
          }

          .aiserver-toc-item {
            appearance: none;
            background: transparent;
            border: 0;
            border-bottom: 1px solid rgba(109, 72, 52, 0.10);
            color: var(--aiserver-ink);
            display: block;
            font-family: "Songti SC", Georgia, serif;
            font-size: 0.98rem;
            padding: 12px 2px;
            text-align: left;
            width: 100%;
          }

          .aiserver-toc-item.aiserver-toc-subitem {
            color: var(--aiserver-muted);
            font-size: 0.88rem;
            padding-left: 16px;
          }

          body.aiserver-deck-mode {
            height: 100vh !important;
            overflow: hidden !important;
          }

          body.aiserver-deck-mode > :not(#aiserver-deck-root):not(#aiserver-deck-toc) {
            display: none !important;
          }

          #aiserver-deck-root {
            background: var(--aiserver-paper);
            display: flex;
            height: 100vh;
            inset: 0;
            overflow-x: auto;
            overflow-y: hidden;
            position: fixed;
            scroll-behavior: smooth;
            scroll-snap-type: x mandatory;
            scrollbar-width: none;
            width: 100vw;
            z-index: 2147483000;
          }

          #aiserver-deck-root::-webkit-scrollbar { display: none; }

          #aiserver-deck-root.aiserver-hidden { display: none; }

          .aiserver-deck-slide {
            background: var(--aiserver-paper);
            box-sizing: border-box;
            flex: 0 0 100vw;
            height: 100vh;
            overflow: hidden;
            padding: 25px 22px 112px;
            position: relative;
            scroll-snap-align: start;
            scroll-snap-stop: always;
            width: 100vw;
          }

          .aiserver-deck-slide::after {
            bottom: 86px;
            color: var(--aiserver-muted);
            content: attr(data-page-label);
            font-family: -apple-system, BlinkMacSystemFont, "SF Mono", monospace;
            font-size: 0.62rem;
            letter-spacing: 0.08em;
            position: absolute;
            right: 22px;
          }

          .aiserver-deck-cover {
            align-items: flex-end;
            background: #181512;
            color: #fff;
            display: flex;
            padding: 0 0 112px;
          }

          .aiserver-deck-cover-image {
            height: 100%;
            inset: 0;
            object-fit: cover;
            object-position: center top;
            opacity: 0.72;
            position: absolute;
            width: 100%;
          }

          .aiserver-deck-cover-shade {
            background: linear-gradient(180deg, rgba(10, 8, 6, 0.05) 22%, rgba(10, 8, 6, 0.94) 100%);
            inset: 0;
            position: absolute;
          }

          .aiserver-deck-cover-copy {
            padding: 26px 24px;
            position: relative;
            width: 100%;
            z-index: 1;
          }

          .aiserver-deck-kicker {
            color: var(--aiserver-accent);
            font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif;
            font-size: 0.66rem;
            font-weight: 700;
            letter-spacing: 0.12em;
            margin-bottom: 13px;
            text-transform: uppercase;
          }

          .aiserver-deck-cover .aiserver-deck-kicker { color: #e3c1ad; }

          .aiserver-deck-cover-title {
            color: inherit;
            font-family: "Songti SC", Georgia, serif;
            font-size: clamp(2.65rem, 12vw, 4.4rem);
            font-weight: 700;
            letter-spacing: -0.035em;
            line-height: 1.02;
            margin: 0;
          }

          .aiserver-deck-cover-description {
            color: rgba(255, 255, 255, 0.74);
            font-size: 0.82rem;
            line-height: 1.55;
            margin: 16px 0 0;
            max-width: 92%;
          }

          .aiserver-deck-section {
            align-items: flex-end;
            background: var(--aiserver-accent);
            color: #fff8ed;
            display: flex;
            padding-bottom: 134px;
          }

          .aiserver-deck-section-number {
            color: rgba(255, 248, 237, 0.62);
            font-family: Georgia, serif;
            font-size: 1rem;
            left: 24px;
            position: absolute;
            top: 26px;
          }

          .aiserver-deck-section-title {
            color: inherit;
            font-family: "Songti SC", Georgia, serif;
            font-size: clamp(3rem, 14vw, 5.1rem);
            font-weight: 700;
            letter-spacing: -0.04em;
            line-height: 1.05;
            margin: 0;
          }

          .aiserver-deck-section-rule {
            background: currentColor;
            height: 2px;
            margin: 20px 0 0;
            opacity: 0.7;
            width: 52px;
          }

          .aiserver-deck-content {
            display: flex;
            flex-direction: column;
          }

          .aiserver-deck-slide-title {
            border-bottom: 1px solid var(--aiserver-rule);
            color: var(--aiserver-accent);
            font-family: "Songti SC", Georgia, serif;
            font-size: 1.75rem;
            font-weight: 700;
            line-height: 1.2;
            margin: 0 0 18px;
            padding: 0 0 14px;
          }

          .aiserver-deck-body {
            color: var(--aiserver-ink);
            font-family: "Songti SC", Georgia, serif;
            font-size: clamp(1rem, 4.5vw, 1.2rem);
            line-height: 1.78;
            min-height: 0;
            overflow-y: auto;
            overscroll-behavior: contain;
            padding-right: 3px;
          }

          .aiserver-deck-body p { margin: 0 0 1em !important; }
          .aiserver-deck-body p:last-child { margin-bottom: 0 !important; }
          .aiserver-deck-body a { color: var(--aiserver-link) !important; }

          .aiserver-deck-media {
            display: flex;
            flex-direction: column;
          }

          .aiserver-deck-media-frame {
            flex: 1;
            min-height: 0;
            overflow: hidden;
            position: relative;
          }

          .aiserver-deck-media-frame img {
            border-radius: 0 !important;
            height: 100% !important;
            object-fit: contain !important;
            object-position: center top !important;
            width: 100% !important;
          }

          .aiserver-deck-caption {
            color: var(--aiserver-muted);
            font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif;
            font-size: 0.72rem;
            line-height: 1.5;
            padding: 10px 2px 0;
          }

          .aiserver-deck-data .aiserver-deck-body {
            background: var(--aiserver-card);
            border: 1px solid var(--aiserver-rule);
            border-radius: 14px;
            padding: 12px;
          }

          .aiserver-deck-data table,
          .aiserver-deck-data .infobox {
            background: transparent !important;
            border: 0 !important;
            display: table !important;
            font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif !important;
            margin: 0 !important;
            padding: 0 !important;
            width: 100% !important;
          }

          .aiserver-deck-data th,
          .aiserver-deck-data td {
            border-bottom: 1px solid var(--aiserver-rule) !important;
            padding: 9px 7px !important;
          }

          #aiserver-deck-toc {
            background: rgba(251, 247, 237, 0.98);
            inset: 0;
            overflow-y: auto;
            padding: 26px 22px 110px;
            position: fixed;
            transform: translateY(0);
            transition: opacity 180ms ease, transform 180ms ease, visibility 180ms;
            z-index: 2147483647;
          }

          #aiserver-deck-toc.aiserver-hidden {
            opacity: 0;
            pointer-events: none;
            transform: translateY(14px);
            visibility: hidden;
          }

          .aiserver-deck-toc-top {
            align-items: center;
            display: flex;
            justify-content: space-between;
            margin-bottom: 20px;
          }

          .aiserver-deck-toc-heading {
            color: var(--aiserver-accent);
            font-family: "Songti SC", Georgia, serif;
            font-size: 2rem;
            font-weight: 700;
          }

          .aiserver-deck-toc-list button {
            align-items: center;
            appearance: none;
            background: transparent;
            border: 0;
            border-bottom: 1px solid var(--aiserver-rule);
            color: var(--aiserver-ink);
            display: flex;
            font-family: "Songti SC", Georgia, serif;
            font-size: 1.05rem;
            gap: 16px;
            padding: 15px 0;
            text-align: left;
            width: 100%;
          }

          .aiserver-deck-toc-index {
            color: var(--aiserver-accent);
            font-family: Georgia, serif;
            font-size: 0.82rem;
            min-width: 30px;
          }
        `;

        document.documentElement.appendChild(style);
      };

      const installTableOfContents = () => {
        if (!document.body || document.getElementById("aiserver-archive-toc")) return;

        const headings = Array.from(document.querySelectorAll(".mw-parser-output h2, .mw-parser-output h3"))
          .filter((heading) => heading.textContent.trim().length > 0);
        if (!headings.length) return;

        const panel = document.createElement("section");
        panel.id = "aiserver-archive-toc";
        panel.className = "aiserver-hidden";
        panel.setAttribute("aria-label", "本文目录");

        const header = document.createElement("div");
        header.className = "aiserver-toc-header";
        const title = document.createElement("div");
        title.className = "aiserver-toc-title";
        title.textContent = "本文目录";
        const close = document.createElement("button");
        close.className = "aiserver-toc-close";
        close.type = "button";
        close.setAttribute("aria-label", "关闭目录");
        close.textContent = "×";
        header.append(title, close);

        const list = document.createElement("div");
        list.className = "aiserver-toc-list";
        headings.forEach((heading, index) => {
          const button = document.createElement("button");
          button.type = "button";
          button.className = `aiserver-toc-item${heading.tagName === "H3" ? " aiserver-toc-subitem" : ""}`;
          button.textContent = heading.textContent.trim();
          button.addEventListener("click", () => {
            heading.scrollIntoView({ behavior: "smooth", block: "start" });
            panel.classList.add("aiserver-hidden");
          });
          list.appendChild(button);
        });

        close.addEventListener("click", () => panel.classList.add("aiserver-hidden"));
        panel.append(header, list);
        document.body.appendChild(panel);
        window.__aiserverToggleTOC = () => panel.classList.toggle("aiserver-hidden");
      };

      const installDeck = () => {
        if (!document.body || document.getElementById("aiserver-deck-root")) return;
        let article = document.querySelector(".mw-parser-output");
        const heading = document.getElementById("firstHeading");
        if (!article || !heading) return;
        while (article.querySelector(":scope > .mw-parser-output")) {
          article = article.querySelector(":scope > .mw-parser-output");
        }

        const titleText = (
          heading.querySelector(".mw-page-title-main")?.textContent ||
          Array.from(heading.childNodes).find((node) => node.nodeType === Node.TEXT_NODE)?.textContent ||
          heading.textContent
        ).replace(/\s*编辑\s*$/, "").trim();
        const description = document.querySelector("meta[name='description']")?.content?.trim() || "";
        let slides = [];
        let sectionEntries = [];
        let currentSection = titleText;
        let currentSubsection = "";
        let sectionNumber = 0;
        let paragraphBuffer = [];
        let paragraphLength = 0;

        const textOf = (node) => (node?.textContent || "").replace(/\s+/g, " ").trim();
        const bestImageSource = (image) => {
          const largestSource = (image?.getAttribute("srcset") || image?.dataset.srcset || "")
            .split(",")
            .map((candidate) => candidate.trim().split(/\s+/)[0])
            .filter(Boolean)
            .pop();
          const source = largestSource || image?.dataset.src || image?.currentSrc || image?.src || "";
          return /^data:image\/(?:svg\+xml|gif)/i.test(source) ? "" : source;
        };
        const cloneClean = (node) => {
          const clone = node.cloneNode(true);
          clone.querySelectorAll(".mw-editsection, .mw-empty-elt, style, script, template, .noprint, .nomobile, .navbox, .navbar, .metadata, [hidden], [aria-hidden='true']").forEach((item) => item.remove());
          clone.querySelectorAll("[id]").forEach((item) => item.removeAttribute("id"));
          Array.from(clone.querySelectorAll("img")).forEach((image) => {
            const source = bestImageSource(image);
            if (!source) {
              image.remove();
              return;
            }
            image.src = source;
            image.removeAttribute("srcset");
            image.removeAttribute("loading");
          });
          return clone;
        };
        const makeSlide = (type, slideTitle) => {
          const slide = document.createElement("section");
          slide.className = `aiserver-deck-slide ${type}`;
          if (slideTitle) slide.dataset.title = slideTitle;
          slides.push(slide);
          return slide;
        };
        const appendHeader = (slide, kicker, slideTitle) => {
          const kickerNode = document.createElement("div");
          kickerNode.className = "aiserver-deck-kicker";
          kickerNode.textContent = kicker;
          const titleNode = document.createElement("h2");
          titleNode.className = "aiserver-deck-slide-title";
          titleNode.textContent = slideTitle;
          slide.append(kickerNode, titleNode);
        };
        const flushParagraphs = () => {
          if (!paragraphBuffer.length) return;
          const slide = makeSlide("aiserver-deck-content", currentSection);
          appendHeader(slide, currentSubsection ? currentSection : "WIKIPEDIA · 中文", currentSubsection || currentSection);
          const body = document.createElement("div");
          body.className = "aiserver-deck-body";
          paragraphBuffer.forEach((paragraph) => body.appendChild(cloneClean(paragraph)));
          slide.appendChild(body);
          paragraphBuffer = [];
          paragraphLength = 0;
        };
        const addParagraph = (paragraph) => {
          const length = textOf(paragraph).length;
          if (!length) return;
          if (paragraphBuffer.length && paragraphLength + length > 560) flushParagraphs();
          paragraphBuffer.push(paragraph);
          paragraphLength += length;
          if (paragraphLength >= 560) flushParagraphs();
        };
        const firstUsefulImage = () => {
          const candidates = Array.from(article.querySelectorAll(".infobox img, figure img, .thumb img, img.mw-file-element"));
          return candidates.find((image) => {
            const width = Number(image.getAttribute("width") || image.naturalWidth || 0);
            const height = Number(image.getAttribute("height") || image.naturalHeight || 0);
            return width >= 180 && height >= 160 && !/icon|logo|symbol|question_book/i.test(image.src);
          }) || candidates[0];
        };

        const cover = makeSlide("aiserver-deck-cover", titleText);
        const coverImage = firstUsefulImage();
        if (coverImage) {
          const image = coverImage.cloneNode(true);
          image.className = "aiserver-deck-cover-image";
          const largestSource = (coverImage.getAttribute("srcset") || "")
            .split(",")
            .map((candidate) => candidate.trim().split(/\s+/)[0])
            .filter(Boolean)
            .pop();
          image.src = largestSource || coverImage.currentSrc || coverImage.src;
          image.removeAttribute("srcset");
          image.removeAttribute("width");
          image.removeAttribute("height");
          cover.appendChild(image);
        }
        const coverShade = document.createElement("div");
        coverShade.className = "aiserver-deck-cover-shade";
        const coverCopy = document.createElement("div");
        coverCopy.className = "aiserver-deck-cover-copy";
        const coverKicker = document.createElement("div");
        coverKicker.className = "aiserver-deck-kicker";
        coverKicker.textContent = "WIKIPEDIA · 中文";
        const coverTitle = document.createElement("h1");
        coverTitle.className = "aiserver-deck-cover-title";
        coverTitle.textContent = titleText;
        coverCopy.append(coverKicker, coverTitle);
        if (description) {
          const coverDescription = document.createElement("p");
          coverDescription.className = "aiserver-deck-cover-description";
          coverDescription.textContent = description;
          coverCopy.appendChild(coverDescription);
        }
        cover.append(coverShade, coverCopy);
        sectionEntries.push({ title: "封面", slideIndex: 0 });

        const infobox = article.querySelector(".infobox, table.infobox");

        const skipNode = (node) => {
          if (!(node instanceof HTMLElement)) return true;
          if (node === infobox || infobox?.contains(node)) return true;
          return node.matches("style, script, .mw-empty-elt, .hatnote, .dablink, .shortdescription, .navbox, .vertical-navbox, .sistersitebox, .metadata, .noprint");
        };
        const addMediaSlide = (node) => {
          const image = node.matches("img") ? node : node.querySelector("img");
          if (!image) return false;
          const imageSource = bestImageSource(image);
          if (!imageSource) return false;
          const width = Number(image.getAttribute("width") || image.naturalWidth || 0);
          const height = Number(image.getAttribute("height") || image.naturalHeight || 0);
          if (width && height && width < 140 && height < 140) return false;
          flushParagraphs();
          const slide = makeSlide("aiserver-deck-media", currentSection);
          appendHeader(slide, "WIKIPEDIA · 中文", currentSubsection || currentSection);
          const frame = document.createElement("div");
          frame.className = "aiserver-deck-media-frame";
          const clonedImage = image.cloneNode(true);
          clonedImage.src = imageSource;
          clonedImage.removeAttribute("srcset");
          clonedImage.removeAttribute("loading");
          clonedImage.removeAttribute("width");
          clonedImage.removeAttribute("height");
          frame.appendChild(clonedImage);
          const captionText = textOf(node.querySelector("figcaption, .thumbcaption"));
          slide.appendChild(frame);
          if (captionText) {
            const caption = document.createElement("div");
            caption.className = "aiserver-deck-caption";
            caption.textContent = captionText;
            slide.appendChild(caption);
          }
          return true;
        };
        const addStructuredSlide = (node) => {
          flushParagraphs();
          const slide = makeSlide("aiserver-deck-content aiserver-deck-data", currentSection);
          appendHeader(slide, "WIKIPEDIA · 中文", currentSubsection || currentSection);
          const body = document.createElement("div");
          body.className = "aiserver-deck-body";
          body.appendChild(cloneClean(node));
          slide.appendChild(body);
        };

        const articleNodes = [];
        const collectArticleNodes = (container) => {
          Array.from(container.children).forEach((node) => {
            if (node.tagName === "SECTION" || node.matches(".mw-parser-output")) {
              collectArticleNodes(node);
            } else {
              articleNodes.push(node);
            }
          });
        };
        collectArticleNodes(article);

        articleNodes.forEach((node) => {
          if (skipNode(node)) return;
          const tagName = node.tagName;
          const wrappedHeading = node.matches(".mw-heading2, .mw-heading3, .mw-heading4")
            ? node.querySelector("h2, h3, h4")
            : null;
          const effectiveHeading = wrappedHeading || node;
          const effectiveTagName = effectiveHeading.tagName;
          if (effectiveTagName === "H2") {
            flushParagraphs();
            currentSection = textOf(effectiveHeading.querySelector(".mw-headline")) || textOf(effectiveHeading);
            currentSubsection = "";
            if (!currentSection || /^(参见|参考资料|参考文献|外部链接|注释|脚注)$/i.test(currentSection)) return;
            sectionNumber += 1;
            const divider = makeSlide("aiserver-deck-section", currentSection);
            const number = document.createElement("div");
            number.className = "aiserver-deck-section-number";
            number.textContent = String(sectionNumber).padStart(2, "0");
            const copy = document.createElement("div");
            const sectionTitle = document.createElement("h2");
            sectionTitle.className = "aiserver-deck-section-title";
            sectionTitle.textContent = currentSection;
            const rule = document.createElement("div");
            rule.className = "aiserver-deck-section-rule";
            copy.append(sectionTitle, rule);
            divider.append(number, copy);
            sectionEntries.push({ title: currentSection, slideIndex: slides.length - 1 });
            return;
          }
          if (effectiveTagName === "H3" || effectiveTagName === "H4") {
            flushParagraphs();
            currentSubsection = textOf(effectiveHeading.querySelector(".mw-headline")) || textOf(effectiveHeading);
            return;
          }
          if (tagName === "P") {
            addParagraph(node);
            return;
          }
          const isStructuredCollection = tagName === "TABLE" || tagName === "UL" || tagName === "OL";
          const isMediaContainer = node.matches("figure, .thumb, .gallery, .gallerybox") ||
            (!isStructuredCollection && node.querySelector("img"));
          if (isMediaContainer) {
            addMediaSlide(node);
            return;
          }
          if (tagName === "UL" || tagName === "OL") {
            addStructuredSlide(node);
            return;
          }
          if (tagName === "TABLE") {
            addStructuredSlide(node);
            return;
          }
          if (tagName === "BLOCKQUOTE" || tagName === "PRE" || node.matches(".poem, .quotebox")) {
            addStructuredSlide(node);
            return;
          }
          if (textOf(node).length > 20 && node.children.length <= 2) addStructuredSlide(node);
        });
        flushParagraphs();

        const sourceSlides = slides;
        const validSlides = sourceSlides.filter((slide, index) => {
          if (index === 0 || slide.classList.contains("aiserver-deck-section")) {
            return textOf(slide).length > 0;
          }
          if (slide.classList.contains("aiserver-deck-media")) {
            const image = slide.querySelector("img");
            return Boolean(image?.getAttribute("src"));
          }
          const body = slide.querySelector(".aiserver-deck-body");
          if (!body) return false;
          return textOf(body).length > 0 || Boolean(body.querySelector("img, table, svg, video"));
        });
        sectionEntries = sectionEntries.map((entry) => {
          const sourceSlide = sourceSlides[entry.slideIndex];
          return { ...entry, slideIndex: validSlides.indexOf(sourceSlide) };
        }).filter((entry) => entry.slideIndex >= 0);
        slides = validSlides;

        const root = document.createElement("div");
        root.id = "aiserver-deck-root";
        slides.forEach((slide, index) => {
          slide.dataset.pageIndex = String(index);
          slide.dataset.pageLabel = `${String(index + 1).padStart(2, "0")} / ${String(slides.length).padStart(2, "0")}`;
          root.appendChild(slide);
        });

        const toc = document.createElement("aside");
        toc.id = "aiserver-deck-toc";
        toc.className = "aiserver-hidden";
        const tocTop = document.createElement("div");
        tocTop.className = "aiserver-deck-toc-top";
        const tocHeading = document.createElement("div");
        tocHeading.className = "aiserver-deck-toc-heading";
        tocHeading.textContent = "目录";
        const tocClose = document.createElement("button");
        tocClose.className = "aiserver-toc-close";
        tocClose.type = "button";
        tocClose.textContent = "×";
        tocClose.setAttribute("aria-label", "关闭目录");
        tocTop.append(tocHeading, tocClose);
        const tocList = document.createElement("div");
        tocList.className = "aiserver-deck-toc-list";
        sectionEntries.forEach((entry, index) => {
          const button = document.createElement("button");
          button.type = "button";
          const number = document.createElement("span");
          number.className = "aiserver-deck-toc-index";
          number.textContent = String(index + 1).padStart(2, "0");
          const title = document.createElement("span");
          title.textContent = entry.title;
          button.append(number, title);
          button.addEventListener("click", () => {
            goToPage(entry.slideIndex);
            toc.classList.add("aiserver-hidden");
          });
          tocList.appendChild(button);
        });
        toc.append(tocTop, tocList);
        document.body.append(root, toc);
        document.body.classList.add("aiserver-deck-mode");

        let currentIndex = 0;
        let scrollTimer;
        const postState = () => {
          window.webkit?.messageHandlers?.wikipediaDeck?.postMessage({
            pageIndex: currentIndex,
            pageCount: slides.length,
            isOriginalMode: !document.body.classList.contains("aiserver-deck-mode")
          });
        };
        const goToPage = (pageIndex) => {
          if (!document.body.classList.contains("aiserver-deck-mode")) return;
          currentIndex = Math.min(slides.length - 1, Math.max(0, pageIndex));
          root.scrollTo({ left: currentIndex * root.clientWidth, behavior: "smooth" });
          postState();
        };
        root.addEventListener("scroll", () => {
          clearTimeout(scrollTimer);
          scrollTimer = setTimeout(() => {
            currentIndex = Math.min(slides.length - 1, Math.max(0, Math.round(root.scrollLeft / root.clientWidth)));
            postState();
          }, 90);
        }, { passive: true });
        tocClose.addEventListener("click", () => toc.classList.add("aiserver-hidden"));
        window.__aiserverDeckPrevious = () => goToPage(currentIndex - 1);
        window.__aiserverDeckNext = () => goToPage(currentIndex + 1);
        window.__aiserverToggleTOC = () => toc.classList.toggle("aiserver-hidden");
        window.__aiserverToggleOriginal = () => {
          const deckMode = document.body.classList.toggle("aiserver-deck-mode");
          root.classList.toggle("aiserver-hidden", !deckMode);
          toc.classList.add("aiserver-hidden");
          postState();
        };
        postState();
      };

      installReaderStyle();
      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", () => setTimeout(installDeck, 180));
      } else {
        setTimeout(installDeck, 180);
      }
    })();
    """#
}

extension URL {
    var isWikipediaURL: Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "wikipedia.org" || host.hasSuffix(".wikipedia.org")
    }
}

enum WikipediaLinkPresentation {
    static func entity(for destinationURL: URL, currentURL: URL?) -> WikipediaEntity? {
        guard ["http", "https"].contains(destinationURL.scheme?.lowercased() ?? "") else {
            return nil
        }
        guard !isSameDocument(destinationURL, currentURL) else { return nil }

        let encodedPathTitle = destinationURL.path
            .split(separator: "/")
            .last
            .map(String.init)
        let decodedPathTitle = encodedPathTitle?.removingPercentEncoding ?? encodedPathTitle ?? ""
        let pathTitle = decodedPathTitle
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (pathTitle.isEmpty ? nil : pathTitle)
            ?? destinationURL.host
            ?? "链接"

        return WikipediaEntity(
            id: destinationURL.absoluteString,
            term: title,
            title: title,
            summary: "",
            url: destinationURL
        )
    }

    private static func isSameDocument(_ destinationURL: URL, _ currentURL: URL?) -> Bool {
        guard let currentURL else { return false }
        var destination = URLComponents(url: destinationURL, resolvingAgainstBaseURL: false)
        var current = URLComponents(url: currentURL, resolvingAgainstBaseURL: false)
        destination?.fragment = nil
        current?.fragment = nil
        return destination?.url == current?.url
    }
}

private struct WikipediaWebView: UIViewRepresentable {
    let url: URL
    let html: String
    @ObservedObject var model: WikipediaBrowserModel
    let openLink: (WikipediaEntity) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, openLink: openLink)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.add(context.coordinator, name: "wikipediaDeck")
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: WikipediaReaderStyle.script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        let previousPageGesture = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDeckSwipe(_:))
        )
        previousPageGesture.direction = .right
        previousPageGesture.delegate = context.coordinator
        webView.addGestureRecognizer(previousPageGesture)
        let nextPageGesture = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDeckSwipe(_:))
        )
        nextPageGesture.direction = .left
        nextPageGesture.delegate = context.coordinator
        webView.addGestureRecognizer(nextPageGesture)
        context.coordinator.observe(webView)
        model.attach(webView)
        webView.loadHTMLString(html, baseURL: url)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "wikipediaDeck")
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIGestureRecognizerDelegate {
        private let model: WikipediaBrowserModel
        private let openLink: (WikipediaEntity) -> Void
        private var progressObservation: NSKeyValueObservation?
        private var contentOffsetObservation: NSKeyValueObservation?

        init(model: WikipediaBrowserModel, openLink: @escaping (WikipediaEntity) -> Void) {
            self.model = model
            self.openLink = openLink
        }

        func observe(_ webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self, weak webView] _, _ in
                guard let self, let webView else { return }
                Task { @MainActor in self.model.update(from: webView) }
            }
            contentOffsetObservation = webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self, weak webView] _, _ in
                guard let self, let webView else { return }
                Task { @MainActor in self.model.updateScrollProgress(from: webView.scrollView) }
            }
        }

        func stopObserving() {
            progressObservation?.invalidate()
            contentOffsetObservation?.invalidate()
        }

        @objc func handleDeckSwipe(_ gesture: UISwipeGestureRecognizer) {
            guard let webView = gesture.view as? WKWebView else { return }
            switch gesture.direction {
            case .left:
                webView.evaluateJavaScript("window.__aiserverDeckNext?.()")
            case .right:
                webView.evaluateJavaScript("window.__aiserverDeckPrevious?.()")
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "wikipediaDeck",
                  let state = message.body as? [String: Any] else { return }
            let pageIndex = state["pageIndex"] as? Int ?? 0
            let pageCount = state["pageCount"] as? Int ?? 1
            let isOriginalMode = state["isOriginalMode"] as? Bool ?? false
            Task { @MainActor in
                self.model.updateDeckState(
                    pageIndex: pageIndex,
                    pageCount: pageCount,
                    isOriginalMode: isOriginalMode
                )
            }
        }
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let destinationURL = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            guard let entity = WikipediaLinkPresentation.entity(
                    for: destinationURL,
                    currentURL: webView.url
                  ) else {
                decisionHandler(.allow)
                return
            }

            openLink(entity)
            decisionHandler(.cancel)
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { model.update(from: webView) }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { model.update(from: webView) }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.update(from: webView)
            webView.evaluateJavaScript(
                "document.getElementById('firstHeading')?.textContent || document.title"
            ) { [weak self] value, _ in
                guard let self else { return }
                Task { @MainActor in self.model.updateTitle(value as? String) }
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { model.update(from: webView) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { model.update(from: webView) }
    }
}

enum WikipediaRelayedHTML {
    private static let imageAttributeRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(src|data-src)\s*=\s*([\"'])([^\"']+)\2"#
    )

    static func document(_ fragment: String, title: String, baseURL: URL) -> String {
        let relayed = relayImages(in: fragment, baseURL: baseURL)
        return """
        <!doctype html>
        <html lang="zh">
          <head>
            <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
            <base href="\(escape(baseURL.absoluteString))">
            <title>\(escape(title))</title>
          </head>
          <body>
            <h1 id="firstHeading">\(escape(title))</h1>
            \(relayed)
          </body>
        </html>
        """
    }

    private static func relayImages(in html: String, baseURL: URL) -> String {
        let mutable = NSMutableString(string: html)
        let matches = imageAttributeRegex.matches(
            in: html,
            range: NSRange(location: 0, length: (html as NSString).length)
        )
        for match in matches.reversed() {
            let raw = (html as NSString).substring(with: match.range(at: 3))
            let absoluteValue = raw.hasPrefix("//") ? "https:\(raw)" : raw
            guard let absolute = URL(string: absoluteValue, relativeTo: baseURL)?.absoluteURL,
                  let relayed = MediaURL.image(absolute.absoluteString) else { continue }
            mutable.replaceCharacters(in: match.range(at: 3), with: escape(relayed.absoluteString))
        }
        return mutable as String
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
