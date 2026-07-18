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
    private static let ignoredChineseTerms: Set<String> = [
        "一个", "一些", "一种", "这个", "这些", "那个", "那些", "其中", "以及", "因为", "所以", "但是", "然而",
        "如果", "已经", "没有", "可能", "目前", "今天", "表示", "认为", "进行", "成为", "需要", "问题", "时候",
        "我们", "他们", "她们", "你们", "自己", "记者", "报道", "文章", "内容", "市场", "公司"
    ]
    private static let commonChineseEntities = [
        "美国", "中国", "英国", "法国", "德国", "日本", "韩国", "印度", "俄罗斯", "加拿大", "澳大利亚",
        "欧洲", "亚洲", "非洲", "欧盟", "联合国", "华尔街", "纽约时报", "微软", "英伟达", "苹果", "谷歌",
        "亚马逊", "特斯拉", "脸书", "人工智能"
    ]

    static func candidates(in paragraphs: [String], limit: Int = 24) -> [String] {
        var results: [String] = []
        var seen = Set<String>()

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

        // Name recognition requires optional on-device linguistic assets on some
        // iOS versions. Word tokenization is available more broadly, so use it as
        // a conservative fallback and let Wikipedia validate every candidate.
        if results.count < limit {
            for paragraph in paragraphs {
                for entity in commonChineseEntities where paragraph.contains(entity) {
                    append(entity, to: &results, seen: &seen, limit: limit)
                }

                let tokenizer = NLTokenizer(unit: .word)
                tokenizer.string = paragraph
                tokenizer.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
                    let token = String(paragraph[range])
                    if isUsefulChineseToken(token) {
                        append(token, to: &results, seen: &seen, limit: limit)
                    }
                    return results.count < limit
                }
                if results.count == limit { break }
            }
        }
        return results
    }

    private static func isUsefulChineseToken(_ value: String) -> Bool {
        guard (2...8).contains(value.count), !ignoredChineseTerms.contains(value) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            (0x3400...0x4DBF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value)
        }
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
            let fetched = (try? await fetch(titles: uncached, language: "zh")) ?? [:]
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
    @StateObject private var browser = WikipediaBrowserModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                Spacer()
                Text("维基百科").font(.headline)
                Spacer()
                ShareLink(item: entity.url) {
                    Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 6)

            if browser.isLoading {
                ProgressView(value: browser.progress).progressViewStyle(.linear)
            } else {
                Divider()
            }

            Button { dismiss() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                    Text("返回纽约时报文章")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold())
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()

            WikipediaWebView(url: entity.url, model: browser)

            Divider()
            HStack {
                browserButton("chevron.left", enabled: browser.canGoBack) { browser.goBack() }
                Spacer()
                browserButton("chevron.right", enabled: browser.canGoForward) { browser.goForward() }
                Spacer()
                Menu {
                    Button("较小文字") { browser.adjustTextSize(by: -10) }
                    Button("较大文字") { browser.adjustTextSize(by: 10) }
                } label: {
                    Image(systemName: "textformat.size").frame(width: 44, height: 44)
                }
                Spacer()
                browserButton("arrow.clockwise", enabled: true) { browser.reload() }
                Spacer()
                Menu {
                    ShareLink(item: entity.url) { Label("分享词条", systemImage: "square.and.arrow.up") }
                    Button { UIPasteboard.general.url = entity.url } label: {
                        Label("复制链接", systemImage: "doc.on.doc")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            Text(entity.url.host ?? "wikipedia.org")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 5)
        }
        .background(Color(uiColor: .systemBackground))
        .interactiveDismissDisabled(browser.isLoading)
    }

    private func browserButton(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: systemName).frame(width: 44, height: 44) }
            .disabled(!enabled)
    }
}

@MainActor
final class WikipediaBrowserModel: ObservableObject {
    @Published var isLoading = true
    @Published var progress = 0.05
    @Published var canGoBack = false
    @Published var canGoForward = false
    fileprivate weak var webView: WKWebView?
    private var textSize = 100

    func attach(_ webView: WKWebView) {
        self.webView = webView
        update(from: webView)
    }

    func update(from webView: WKWebView) {
        isLoading = webView.isLoading
        progress = max(webView.estimatedProgress, 0.05)
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func adjustTextSize(by amount: Int) {
        textSize = min(160, max(70, textSize + amount))
        webView?.evaluateJavaScript("document.documentElement.style.webkitTextSizeAdjust='\(textSize)%'")
    }
}

private struct WikipediaWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var model: WikipediaBrowserModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
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
        private var progressObservation: NSKeyValueObservation?

        init(model: WikipediaBrowserModel) { self.model = model }

        func observe(_ webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self, weak webView] _, _ in
                guard let self, let webView else { return }
                Task { @MainActor in self.model.update(from: webView) }
            }
        }

        func stopObserving() { progressObservation?.invalidate() }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { model.update(from: webView) }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { model.update(from: webView) }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { model.update(from: webView) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { model.update(from: webView) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { model.update(from: webView) }
    }
}
