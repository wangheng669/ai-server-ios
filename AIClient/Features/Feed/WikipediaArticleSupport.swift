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
        var components = URLComponents(string: "https://\(language).wikipedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "titles", value: titles.joined(separator: "|")),
            .init(name: "redirects", value: "1"),
            .init(name: "prop", value: "extracts|info"),
            .init(name: "inprop", value: "url"),
            .init(name: "exintro", value: "1"),
            .init(name: "explaintext", value: "1"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2")
        ]
        guard let url = components.url else { return [:] }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
        request.setValue("AIServerClient/1.0 (iOS encyclopedia links)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [:] }
        let payload = try JSONDecoder().decode(WikipediaQueryResponse.self, from: data)
        guard let query = payload.query else { return [:] }

        var aliases: [String: String] = [:]
        for item in (query.normalized ?? []) + (query.redirects ?? []) { aliases[item.from] = item.to }
        let pages = (query.pages ?? []).filter { $0.missing == nil && $0.pageid != nil }

        var result: [String: WikipediaEntity] = [:]
        for candidate in titles {
            var resolvedTitle = candidate
            var visited = Set<String>()
            while let next = aliases[resolvedTitle], visited.insert(resolvedTitle).inserted { resolvedTitle = next }
            guard let page = pages.first(where: {
                $0.title.compare(resolvedTitle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }), let pageID = page.pageid else { continue }
            let trimmedSummary = page.extract?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let summary = trimmedSummary.isEmpty ? "查看维基百科中的完整词条。" : trimmedSummary
            let pageURL = page.fullurl.flatMap(URL.init(string:))
                ?? URL(string: "https://\(language).wikipedia.org/wiki/\(page.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? page.title)")!
            result[candidate] = WikipediaEntity(
                id: "\(language)-\(pageID)",
                term: candidate,
                title: page.title,
                summary: String(summary.prefix(120)),
                url: pageURL
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

    var body: some View {
        VStack(spacing: 0) {
            readerHeader

            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    WikipediaWebView(url: entity.url, model: browser) {
                        presentedLink = $0
                    }

                    readerToolbar
                        .padding(.horizontal, 18)
                        .padding(.bottom, max(12, proxy.safeAreaInsets.bottom))
                }
            }
        }
        .background(archivePaper.ignoresSafeArea())
        .sheet(item: $presentedLink) { linkedEntity in
            AnyView(
                WikipediaReaderView(entity: linkedEntity)
                    .wikipediaReaderPresentation()
            )
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
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(archiveAccent)
                            .frame(width: 40, height: 40)
                            .background(archiveAccent.opacity(0.07), in: Circle())
                    }
                    .accessibilityLabel(entity.url.isWikipediaURL ? "关闭维基百科" : "关闭网页")
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
            readerToolbarButton("返回", systemImage: "chevron.left") {
                browser.goBack()
            }
            .disabled(!browser.canGoBack)

            Divider().frame(height: 24)

            readerToolbarButton("目录", systemImage: "list.bullet") {
                browser.toggleTableOfContents()
            }
            .disabled(!entity.url.isWikipediaURL)

            Divider().frame(height: 24)

            readerToolbarButton("原站打开", systemImage: "arrow.up.right.square") {
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
        browser.isLoading ? browser.progress : max(0.02, browser.scrollProgress)
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

    func toggleTableOfContents() {
        webView?.evaluateJavaScript("window.__aiserverToggleTOC?.()")
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
            .presentationDragIndicator(.visible)
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

      installReaderStyle();
      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", () => setTimeout(installTableOfContents, 120));
      } else {
        setTimeout(installTableOfContents, 120);
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
    @ObservedObject var model: WikipediaBrowserModel
    let openLink: (WikipediaEntity) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, openLink: openLink)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
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
        context.coordinator.observe(webView)
        model.attach(webView)
        webView.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url == nil else { return }
        webView.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20))
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
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

            if destinationURL.isWikipediaURL {
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
