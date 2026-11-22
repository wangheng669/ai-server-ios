import SwiftUI

enum GoogleSignalSentimentFilter: String, CaseIterable, Identifiable {
    case all, positive, negative, neutral, uncertain
    var id: Self { self }
    var queryValue: String? { self == .all ? nil : rawValue }
    var title: String {
        switch self {
        case .all: "全部相关"
        case .positive: "正面"
        case .negative: "负面"
        case .neutral: "中性"
        case .uncertain: "待判断"
        }
    }
}

struct CompanyNewsCompany: Codable, Identifiable, Equatable {
    let id: String
    let name: String
}
struct CompanyNewsPage: Codable {
    let items: [CompanyNewsItem]
    let hasMore: Bool
    let nextCursor: String
    enum CodingKeys: String, CodingKey { case items; case hasMore = "has_more"; case nextCursor = "next_cursor" }
}
struct CompanyNewsItem: Codable, Sendable, Identifiable, Equatable {
    let id: Int64
    let quoteContent: String
    let replyContent: String
    let translationPostID: Int64
    let articleID: String
    let source: String
    let sourceURL: String
    let title: String
    let originalContent: String
    let contentZH: String
    let authorName: String
    let authorHandle: String
    let publishedAt: String
    let companies: [String: String]
    let sentiment: String
    enum CodingKeys: String, CodingKey {
        case id, source, title, companies, sentiment
        case quoteContent = "quote_content", replyContent = "reply_content"
        case translationPostID = "translation_post_id", articleID = "article_id", sourceURL = "source_url"
        case originalContent = "original_content", contentZH = "content_zh", authorName = "author_name"
        case authorHandle = "author_handle", publishedAt = "published_at"
    }
    var displayTitle: String { title.isEmpty ? String(originalContent.prefix(100)) : title }
    var displayAuthor: String { authorName.isEmpty ? source : authorName }

    fileprivate var usesXBodyForTitle: Bool {
        guard source == "x", !originalContent.isEmpty else { return false }
        if title.isEmpty { return true }
        let excerpt = Self.singleLine(title)
        let prefix = String(excerpt.dropLast(excerpt.hasSuffix("…") ? 1 : 0))
        return !prefix.isEmpty && Self.singleLine(originalContent).hasPrefix(prefix)
    }

    fileprivate static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    var sentimentTitle: String { GoogleSignalSentimentFilter(rawValue: sentiment)?.title ?? "待判断" }

    fileprivate var displayContentIdentity: String? {
        guard originalContent.count >= 40 else { return nil }
        func normalize(_ value: String) -> String {
            XPostTextFormatter.simplifiedChinese(value)
                .replacingOccurrences(of: "zh.cn.nikkei.com/", with: "cn.nikkei.com/")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let author = authorHandle.isEmpty ? authorName : authorHandle
        guard !author.isEmpty else { return nil }
        return [source, author.lowercased(), String(publishedAt.prefix(10)), normalize(originalContent), normalize(quoteContent), normalize(replyContent)].joined(separator: "\u{1f}")
    }

}

struct CompanyNewsDisplayList: Sendable {
    private(set) var items: [CompanyNewsItem] = []
    private var ids = Set<Int64>()
    private var urls = Set<String>()
    private var contents = Set<String>()

    mutating func append(_ candidates: [CompanyNewsItem]) {
        for item in candidates {
            guard !ids.contains(item.id), item.sourceURL.isEmpty || !urls.contains(item.sourceURL) else { continue }
            let content = item.displayContentIdentity
            if let content, contents.contains(content) { continue }
            ids.insert(item.id)
            if !item.sourceURL.isEmpty { urls.insert(item.sourceURL) }
            if let content { contents.insert(content) }
            items.append(item)
        }
    }
    func appending(_ candidates: [CompanyNewsItem]) async -> Self {
        var updated = self
        updated.append(candidates)
        return updated
    }

}

private struct CompanyNewsEnvelope<Value: Decodable>: Decodable { let success: Bool; let data: Value }
struct GoogleSignalService {
    enum TranslationSource { case x, rss }

    private struct TranslationDocuments<Item: Decodable>: Decodable { let items: [Item] }
    private struct XTranslation: Decodable {
        struct Part: Decodable { let text: String? }
        let postId: Int64
        let status: String
        let parts: [String: Part]
    }
    private struct RSSTranslation: Decodable {
        let postId: Int64
        let status: String
        let text: String?
    }

    let baseURL: URL
    private let session: URLSession
    init(baseURL: URL = ServerConfiguration.currentURL, session: URLSession = .shared) {
        self.baseURL = baseURL; self.session = session
    }
    func newsURL(company: String, sentiment: GoogleSignalSentimentFilter, cursor: String? = nil) throws -> URL {
        var components = URLComponents(url: baseURL.appending(path: "api/ios/v1/company-news"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "company", value: company), .init(name: "limit", value: "20")]
        if let value = sentiment.queryValue { components?.queryItems?.append(.init(name: "sentiment", value: value)) }
        if let cursor, !cursor.isEmpty { components?.queryItems?.append(.init(name: "cursor", value: cursor)) }
        guard let url = components?.url else { throw APIError.invalidResponse }; return url
    }
    func fetchNews(company: String, sentiment: GoogleSignalSentimentFilter, cursor: String? = nil, refresh: Bool = false) async throws -> CompanyNewsPage {
        let url = try newsURL(company: company, sentiment: sentiment, cursor: cursor)
        if cursor == nil, session === URLSession.shared {
            return try await CompanyNewsRequestCache.shared.page(url: url, refresh: refresh) {
                try await get(url, as: CompanyNewsPage.self)
            }
        }
        return try await get(url, as: CompanyNewsPage.self)
    }
    func prepareFirstPage() async {
        do {
            let catalog = try await fetchCompanies()
            let preferred = UserDefaults.standard.string(forKey: baseURL.absoluteString + "|signal-company")
            guard !Task.isCancelled, let company = catalog.first(where: { $0.id == preferred }) ?? catalog.first else { return }
            _ = try await fetchNews(company: company.id, sentiment: .all)
        } catch {
            // The foreground view owns errors and retry.
        }
    }

    func fetchCompanies() async throws -> [CompanyNewsCompany] {
        struct Catalog: Decodable { let companies: [CompanyNewsCompany] }
        let url = baseURL.appending(path: "api/ios/v1/company-news/catalog")
        if session === URLSession.shared {
            return try await CompanyNewsRequestCache.shared.catalog(url: url) {
                try await get(url, as: Catalog.self).companies
            }
        }
        return try await get(url, as: Catalog.self).companies
    }
    func translationRequest(postID: Int64, source: TranslationSource, observe: Bool = false) throws -> URLRequest {
        let endpoint = source == .x ? "translations" : "rss-translations"
        var request = URLRequest(url: baseURL.appending(path: "api/ios/v1/company-news/\(endpoint)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["postIds": [postID], "intent": observe ? "observe" : "read", "retry": !observe]
        if source == .rss { body["part"] = "article" }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func translate(postID: Int64, source: TranslationSource) async throws -> String {
        for attempt in 0..<20 {
            try Task.checkCancellation()
            let request = try translationRequest(postID: postID, source: source, observe: attempt > 0)
            let first: (postId: Int64, status: String, text: String?)?
            switch source {
            case .x:
                let result: TranslationDocuments<XTranslation> = try await send(request)
                first = result.items.first.map { ($0.postId, $0.status, $0.parts["body"]?.text) }
            case .rss:
                let result: TranslationDocuments<RSSTranslation> = try await send(request)
                first = result.items.first.map { ($0.postId, $0.status, $0.text) }
            }
            guard let document = first, document.postId == postID else { throw APIError.invalidResponse }
            if let text = document.text, !text.isEmpty { return text }
            if document.status == "failed" || (source == .x && document.status == "expired") {
                throw APIError.invalidResponse
            }
            try await Task.sleep(for: .seconds(2))
        }
        throw APIError.invalidResponse
    }

    private func get<Value: Decodable>(_ url: URL, as _: Value.Type) async throws -> Value {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        return try await send(request)
    }

    private func send<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw APIError.invalidResponse }
        let envelope = try JSONDecoder().decode(CompanyNewsEnvelope<Value>.self, from: data)
        guard envelope.success else { throw APIError.invalidResponse }
        return envelope.data
    }
}

actor CompanyNewsRequestCache {
    static let shared = CompanyNewsRequestCache()
    private var catalogs: [URL: ([CompanyNewsCompany], Date)] = [:]
    private var catalogRequests: [URL: Task<[CompanyNewsCompany], Error>] = [:]
    private var pages: [URL: (CompanyNewsPage, Date)] = [:]
    private var pageRequests: [URL: Task<CompanyNewsPage, Error>] = [:]

    func catalog(url: URL, fetch: @escaping @Sendable () async throws -> [CompanyNewsCompany]) async throws -> [CompanyNewsCompany] {
        if let (value, date) = catalogs[url], Date().timeIntervalSince(date) < 3600 { return value }
        if let request = catalogRequests[url] { return try await request.value }
        let request = Task { try await fetch() }
        catalogRequests[url] = request
        defer { catalogRequests[url] = nil }
        let value = try await request.value
        catalogs[url] = (value, Date())
        return value
    }

    func page(url: URL, refresh: Bool, fetch: @escaping @Sendable () async throws -> CompanyNewsPage) async throws -> CompanyNewsPage {
        if !refresh, let (value, date) = pages[url], Date().timeIntervalSince(date) < 60 { return value }
        if let request = pageRequests[url] { return try await request.value }
        let request = Task { try await fetch() }
        pageRequests[url] = request
        defer { pageRequests[url] = nil }
        let value = try await request.value
        pages = pages.filter { Date().timeIntervalSince($0.value.1) < 60 }
        pages[url] = (value, Date())
        return value
    }
}

struct GoogleSignalView: View {
    private struct Filter: Hashable {
        let company: String
        let sentiment: GoogleSignalSentimentFilter
    }

    private struct RequestKey: Equatable {
        let isActive: Bool
        let filter: Filter
        let retry: Int
    }

    private struct ListSnapshot {
        let list: CompanyNewsDisplayList
        let loadedAt: Date
        let hasMore: Bool
        let cursor: String
    }

    let sentiment: GoogleSignalSentimentFilter
    @State private var snapshots: [Filter: ListSnapshot] = [:]
    @State private var companies: [CompanyNewsCompany] = []
    @State private var catalogLoaded = false
    @State private var catalogError: String?
    @State private var company = ""
    @State private var displayList = CompanyNewsDisplayList()
    @State private var selected: CompanyNewsItem?
    @State private var loadingFilter: Filter?
    @State private var loadingMore = false
    @State private var hasMore = false
    @State private var cursor = ""
    @State private var error: String?
    @State private var generation = 0
    @State private var retry = 0
    @State private var loadedFilter: Filter?
    @State private var paginationFailed = false
    @State private var loadedAt: Date?
    @State private var lastRequestRetry = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    private var filter: Filter { Filter(company: company, sentiment: sentiment) }
    private var isActive: Bool { rootTabIsActive && scenePhase == .active }
    private var requestKey: RequestKey { RequestKey(isActive: isActive, filter: filter, retry: retry) }
    private var items: [CompanyNewsItem] {
        loadedFilter == filter ? displayList.items : snapshots[filter]?.list.items ?? []
    }
    private var paginationTaskCursor: String? {
        guard isActive, loadingFilter == nil, loadedFilter == filter,
              hasMore, !paginationFailed, error == nil else { return nil }
        return cursor
    }

    var body: some View {
        VStack(spacing: 0) {
            if !companies.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(companies) { entry in
                            Button {
                                guard company != entry.id else { return }
                                error = nil
                                UserDefaults.standard.set(entry.id, forKey: companyPreference)
                                company = entry.id
                            } label: {
                                Text(entry.name)
                                    .font(.system(size: 14, weight: company == entry.id ? .semibold : .medium))
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 44)
                                    .foregroundStyle(company == entry.id ? Color.white : Color.primary)
                                    .background(company == entry.id ? InvestmentDesign.accent : Color.primary.opacity(0.04), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("signal-company-\(entry.id)")
                            .accessibilityValue(company == entry.id ? "\(items.count) 条资讯" : "")
                            .accessibilityAddTraits(company == entry.id ? .isSelected : [])
                        }
                    }.padding(.horizontal, 18)
                }
                .scrollIndicators(.hidden)
                .padding(.vertical, 8)
            }
            if error == nil && catalogError == nil && (!catalogLoaded || (!company.isEmpty && loadedFilter != filter && items.isEmpty)
                                || (loadingFilter == filter && items.isEmpty)) {
                ContentLoadingPlaceholder(title: "正在读取资讯", rowCount: 5)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let error = catalogError ?? error {
                            InlineActionNotice(message: error, retry: {
                                if paginationFailed { Task { await load(reset: false) } }
                                else { retry += 1 }
                            }) { self.error = nil; catalogError = nil }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                        }
                        if loadingFilter == filter && !items.isEmpty {
                            Text("正在更新资讯")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                        }
                        if items.isEmpty && error == nil {
                            ContentUnavailableView("暂无相关资讯", systemImage: "newspaper", description: Text("新内容完成分析后会出现在这里"))
                        }
                        ForEach(items) { item in
                            Button { selected = item } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top) {
                                        CompanyNewsTitle(item: item, isActive: isActive)
                                            .font(.body.weight(.medium))
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 8)
                                        Text(item.sentimentTitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text([item.displayAuthor, GoogleSignalDatePresentation.detail(GoogleSignalDateParser.date(from: item.publishedAt))].joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }.padding(.horizontal, 18).padding(.vertical, 14).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            .accessibilityIdentifier("signal-news-\(item.id)")
                            Divider().padding(.leading, 18)
                        }
                        if !items.isEmpty || hasMore {
                            if paginationFailed && error == nil {
                                Button(loadingMore ? "正在载入更多资讯" : "重试载入更多") {
                                    Task { await load(reset: false) }
                                }
                                .font(.caption)
                                .disabled(loadingMore)
                                .frame(maxWidth: .infinity, minHeight: 44)
                            } else {
                                Text(error != nil ? "资讯载入失败" : hasMore ? "正在载入更多资讯" : "已显示全部资讯")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .accessibilityIdentifier("signal-pagination-footer")
                                    .accessibilityValue("\(items.count)")
                                    .task(id: paginationTaskCursor) {
                                        guard paginationTaskCursor != nil else { return }
                                        await load(reset: false)
                                    }
                            }
                        }
                    }.padding(.bottom, 100)
                }
                .id(filter)
                .accessibilityIdentifier("signal-news-list")
                .refreshable { await load(reset: true, force: true) }
            }
        }
        .appSheet(item: $selected) { item in CompanyNewsDetail(item: item, companies: companies) }
        .onChange(of: sentiment) { _, _ in error = nil }
        .task(id: "\(isActive)-\(retry)") {
            guard isActive else { return }
            let service = GoogleSignalService()
            let key = service.baseURL.absoluteString + "|signal-catalog"
            async let network = service.fetchCompanies()
            if !catalogLoaded, let saved = await DisplaySnapshotCache.pages.load([CompanyNewsCompany].self, key: key, maximumAge: 86400),
               !Task.isCancelled {
                applyCatalog(saved.value)
            }
            do {
                let catalog = try await network
                guard !Task.isCancelled else { return }
                applyCatalog(catalog)
                catalogError = nil
                await DisplaySnapshotCache.pages.save(catalog, key: key, at: Date())
            } catch {
                if !Task.isCancelled { catalogError = "公司目录读取失败，请重试" }
            }
        }
        .task(id: requestKey) {
            guard isActive, !company.isEmpty else { return }
            await load(reset: true, force: retry != lastRequestRetry)
        }
    }
    private var companyPreference: String { ServerConfiguration.currentURL.absoluteString + "|signal-company" }

    private func applyCatalog(_ catalog: [CompanyNewsCompany]) {
        let preferred = company.isEmpty ? UserDefaults.standard.string(forKey: companyPreference) : company
        companies = catalog
        catalogLoaded = true
        company = catalog.first(where: { $0.id == preferred })?.id ?? catalog.first?.id ?? ""
    }

    @MainActor private func load(reset: Bool, force: Bool = false) async {
        let requestedFilter = filter
        guard isActive, !Task.isCancelled, !requestedFilter.company.isEmpty else { return }
        if reset {
            if !force, loadedFilter == requestedFilter, let loadedAt, Date().timeIntervalSince(loadedAt) < 60 { return }
            lastRequestRetry = retry
            generation += 1
            loadingFilter = requestedFilter
            loadingMore = false
            error = nil
            paginationFailed = false
            if loadedFilter != requestedFilter {
                let saved = snapshots[requestedFilter]
                displayList = saved?.list ?? CompanyNewsDisplayList()
                loadedFilter = saved == nil ? nil : requestedFilter
                loadedAt = saved?.loadedAt
                hasMore = saved?.hasMore ?? false
                cursor = saved?.cursor ?? ""
                if !force, let saved, Date().timeIntervalSince(saved.loadedAt) < 60 {
                    loadingFilter = nil
                    return
                }
            }
        } else {
            guard loadedFilter == requestedFilter, hasMore, !cursor.isEmpty,
                  loadingFilter == nil, !loadingMore else { return }
            loadingMore = true
            error = nil
        }
        let current = generation
        let requestedCursor = reset ? nil : cursor
        defer {
            if current == generation {
                if reset { loadingFilter = nil }
                else { loadingMore = false }
            }
        }
        do {
            let service = GoogleSignalService()
            let key = try service.newsURL(company: requestedFilter.company, sentiment: requestedFilter.sentiment).absoluteString
            async let network = service.fetchNews(
                company: requestedFilter.company,
                sentiment: requestedFilter.sentiment,
                cursor: requestedCursor,
                refresh: force
            )
            if reset, loadedFilter != requestedFilter,
               let saved = await DisplaySnapshotCache.pages.load(CompanyNewsPage.self, key: key, maximumAge: 86400) {
                let restored = await CompanyNewsDisplayList().appending(saved.value.items)
                guard !Task.isCancelled, isActive, current == generation, requestedFilter == filter else { return }
                displayList = restored
                loadedFilter = requestedFilter
                loadedAt = saved.savedAt
                cursor = saved.value.nextCursor
                hasMore = saved.value.hasMore && !cursor.isEmpty
            }
            let page = try await network
            guard !Task.isCancelled, isActive, current == generation, requestedFilter == filter else { return }
            let prepared = await (reset ? CompanyNewsDisplayList() : displayList).appending(page.items)
            guard !Task.isCancelled, isActive, current == generation, requestedFilter == filter else { return }
            displayList = prepared
            if #available(iOS 26.0, *) {
                let titles = page.items.prefix(12).filter { !$0.usesXBodyForTitle }.map(\.displayTitle)
                Task { await FeedTranslationCache.shared.pretranslate(titles) }
            }
            loadedFilter = requestedFilter
            if reset { loadedAt = Date() }
            paginationFailed = false
            cursor = page.nextCursor
            hasMore = page.hasMore && !cursor.isEmpty && cursor != requestedCursor
            error = nil
            if let loadedAt, reset || prepared.items.count <= 60 {
                snapshots[requestedFilter] = ListSnapshot(list: prepared, loadedAt: loadedAt, hasMore: hasMore, cursor: cursor)
                if snapshots.count > 6,
                   let oldest = snapshots.filter({ $0.key != requestedFilter }).min(by: { $0.value.loadedAt < $1.value.loadedAt }) {
                    snapshots.removeValue(forKey: oldest.key)
                }
            }
            if reset { await DisplaySnapshotCache.pages.save(page, key: key, at: Date()) }
        } catch {
            guard !Task.isCancelled, isActive, current == generation, requestedFilter == filter else { return }
            self.error = "资讯读取失败，请重试"
            paginationFailed = !reset
        }
    }
}

private struct CompanyNewsTitle: View {
    let item: CompanyNewsItem
    var isActive = true
    var detail = false

    var body: some View {
        if item.usesXBodyForTitle {
            let key = FeedTranslationCache.xKey(tweetID: item.articleID, original: item.originalContent)
            XTitle(item: item, isActive: isActive, detail: detail, key: key)
                .id(key)
        } else {
            LocalTranslatedText(original: item.displayTitle, detail: detail)
        }
    }

    private struct XTitle: View {
        let item: CompanyNewsItem
        let isActive: Bool
        let detail: Bool
        @State private var translation: FeedTranslationCache.DisplayState

        init(item: CompanyNewsItem, isActive: Bool, detail: Bool, key: String) {
            self.item = item
            self.isActive = isActive
            self.detail = detail
            _translation = State(initialValue: FeedTranslationCache.shared.displayState(for: key))
        }

        var body: some View {
            let original = item.displayTitle
            let needsTranslation = LocalTranslatedText.sourceLanguage(original) != nil
            let chinese = needsTranslation ? LocalTranslatedText.chineseText(item.contentZH) ?? translation.text : nil
            let title = chinese.map { compactTitle($0) } ?? original
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                if detail, title != original {
                    DisclosureGroup("查看原标题") { Text(original).textSelection(.enabled) }
                        .font(.callout)
                }
            }
            .task(id: isActive) {
                guard isActive, needsTranslation, chinese == nil,
                      !item.articleID.isEmpty,
                      item.articleID.utf8.allSatisfy({ (48...57).contains($0) }) else { return }
                let client = APIClient(baseURL: ServerConfiguration.currentURL)
                _ = try? await FeedTranslationCache.shared.translateXPost(
                    tweetID: item.articleID, original: item.originalContent, using: client.fetchXTranslation
                )
            }
        }

        private func compactTitle(_ text: String) -> String {
            let title = CompanyNewsItem.singleLine(text)
            return title.count <= 80 ? title : String(title.prefix(79)) + "…"
        }
    }
}

private struct CompanyNewsDetail: View {
    let item: CompanyNewsItem
    let companies: [CompanyNewsCompany]
    @State private var originalArticle: String?
    @State private var translated = ""
    @State private var translating = false
    @State private var translationError: String?
    @State private var browser: InAppBrowserDestination?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CompanyNewsTitle(item: item, detail: true).font(.title2.bold())
                    Text(item.displayAuthor).foregroundStyle(.secondary)
                    HStack { ForEach(companies.filter { item.companies[$0.id] != "unrelated" }) { company in
                        Text("\(company.name) · \(GoogleSignalSentimentFilter(rawValue: item.companies[company.id] ?? "uncertain")?.title ?? "待判断")").font(.caption)
                    } }
                    if item.source != "x" {
                        LocalTranslatedText(original: originalArticle ?? item.originalContent, serverChinese: originalArticle == nil ? item.contentZH : nil, detail: true)
                            .textSelection(.enabled)
                        if !item.quoteContent.isEmpty { LocalTranslatedText(original: item.quoteContent, detail: true) }
                        if !item.replyContent.isEmpty { LocalTranslatedText(original: item.replyContent, detail: true) }
                    } else {
                    Text(item.originalContent).textSelection(.enabled)
                    if !item.quoteContent.isEmpty { Text("引用原文").font(.headline); Text(item.quoteContent).textSelection(.enabled) }
                    if !item.replyContent.isEmpty { Text("回复上下文").font(.headline); Text(item.replyContent).textSelection(.enabled) }
                    if !item.contentZH.isEmpty || !translated.isEmpty {
                        Divider(); Text("译文").font(.headline); Text(translated.isEmpty ? item.contentZH : translated).textSelection(.enabled)
                    } else {
                        Button(translating ? "正在翻译…" : "翻译正文") { Task { await translate() } }.disabled(translating)
                    }
                    }
                    if let translationError { Text(translationError).font(.caption).foregroundStyle(.red) }
                    if let url = URL(string: item.sourceURL) { Button("阅读来源网页") { browser = InAppBrowserDestination(url: url) } }
                }.padding(20)
                    .padding(.bottom, 76)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            DetailSheetControls(closeLabel: "完成", onClose: dismiss.callAsFunction).padding(12)
        }
        .inAppBrowserCover(item: $browser)
        .task(id: item.id) {
            guard item.source != "x", let url = URL(string: item.sourceURL),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let payload = try? await APIClient(baseURL: ServerConfiguration.currentURL)
                    .fetchArticlePreview(url: url, preferRemote: true).data,
                  !Task.isCancelled else { return }
            let original = payload.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if original.count > item.originalContent.count { originalArticle = original }
        }
    }
    @MainActor private func translate() async {
        guard item.source == "x" else { return }
        translating = true; translationError = nil; defer { translating = false }
        do {
            translated = try await GoogleSignalService().translate(postID: item.translationPostID, source: .x)
        } catch { if !Task.isCancelled { translationError = "翻译暂不可用，请重试" } }
    }
}
struct GoogleSignalFilterButton: View {
    let sentiment: GoogleSignalSentimentFilter
    @Binding var showsFilters: Bool
    var body: some View {
        Button { showsFilters = true } label: { Label(sentiment.title, systemImage: "line.3.horizontal.decrease").padding(12).background(.regularMaterial, in: Capsule()) }
            .buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 12)
    }
}
struct GoogleSignalFilterOverlay: View {
    @Binding var sentiment: GoogleSignalSentimentFilter
    @Binding var isPresented: Bool
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.12).ignoresSafeArea().onTapGesture { isPresented = false }
            VStack(alignment: .leading, spacing: 12) {
                Text("公司资讯筛选").font(.headline)
                ForEach(GoogleSignalSentimentFilter.allCases) { value in
                    Button { sentiment = value; isPresented = false } label: {
                        HStack { Text(value.title); Spacer(); if sentiment == value { Image(systemName: "checkmark") } }.padding(.vertical, 6)
                    }
                }
            }.padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 18).padding(.bottom, 130)
        }.accessibilityAddTraits(.isModal)
    }
}
enum GoogleSignalDateParser {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let seconds = Date.ISO8601FormatStyle()
    static func date(from value: String) -> Date? {
        (try? fractional.parse(value)) ?? (try? seconds.parse(value))
    }
}
enum GoogleSignalDatePresentation {
    static func detail(_ date: Date?) -> String {
        guard let date else { return "时间未知" }
        return date.formatted(.dateTime.locale(Locale(identifier: "zh-Hans-CN")).month().day().hour().minute())
    }
}
