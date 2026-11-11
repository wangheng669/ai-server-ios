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

struct CompanyNewsCompany: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
}
struct CompanyNewsPage: Decodable {
    let items: [CompanyNewsItem]
    let hasMore: Bool
    let nextCursor: String
    enum CodingKeys: String, CodingKey { case items; case hasMore = "has_more"; case nextCursor = "next_cursor" }
}
struct CompanyNewsItem: Decodable, Identifiable, Equatable {
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

struct CompanyNewsDisplayList {
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
    private struct Filter: Equatable {
        let company: String
        let sentiment: GoogleSignalSentimentFilter
    }

    private struct RequestKey: Equatable {
        let isActive: Bool
        let filter: Filter
        let retry: Int
    }

    let sentiment: GoogleSignalSentimentFilter
    @State private var companies: [CompanyNewsCompany] = []
    @State private var catalogLoaded = false
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
    private var items: [CompanyNewsItem] { displayList.items }
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
                            Button { company = entry.id } label: {
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
            if (!catalogLoaded && error == nil) || (loadingFilter != nil && items.isEmpty) {
                ContentLoadingPlaceholder(title: "正在读取资讯", rowCount: 5)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let error {
                            InlineActionNotice(message: error, retry: {
                                if paginationFailed { Task { await load(reset: false) } }
                                else { retry += 1 }
                            }) { self.error = nil }
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
                                        Text(item.displayTitle).font(.body.weight(.medium)).multilineTextAlignment(.leading)
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
                .accessibilityIdentifier("signal-news-list")
                .refreshable { await load(reset: true, force: true) }
            }
        }
        .appSheet(item: $selected) { item in CompanyNewsDetail(item: item, companies: companies) }
        .task(id: requestKey) {
            guard isActive, !Task.isCancelled else { return }
            if !catalogLoaded {
                do {
                    let catalog = try await GoogleSignalService().fetchCompanies()
                    guard !Task.isCancelled else { return }
                    companies = catalog
                    catalogLoaded = true
                    company = catalog.first?.id ?? ""
                    error = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = "公司目录读取失败，请重试"
                }
                return
            }
            guard !company.isEmpty else { return }
            await load(reset: true, force: retry != lastRequestRetry)
        }
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
                displayList = CompanyNewsDisplayList()
                loadedFilter = nil
                hasMore = false
                cursor = ""
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
            let page = try await GoogleSignalService().fetchNews(
                company: requestedFilter.company,
                sentiment: requestedFilter.sentiment,
                cursor: requestedCursor,
                refresh: force
            )
            guard !Task.isCancelled, isActive, current == generation, requestedFilter == filter else { return }
            if reset { displayList = CompanyNewsDisplayList() }
            displayList.append(page.items)
            loadedFilter = requestedFilter
            if reset { loadedAt = Date() }
            paginationFailed = false
            cursor = page.nextCursor
            hasMore = page.hasMore && !cursor.isEmpty && cursor != requestedCursor
            error = nil
        } catch {
            guard !Task.isCancelled, isActive, current == generation, requestedFilter == filter else { return }
            self.error = "资讯读取失败，请重试"
            paginationFailed = !reset
        }
    }
}

private struct CompanyNewsDetail: View {
    let item: CompanyNewsItem
    let companies: [CompanyNewsCompany]
    @State private var translated = ""
    @State private var translating = false
    @State private var translationError: String?
    @State private var browser: InAppBrowserDestination?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(item.displayTitle).font(.title2.bold())
                    Text(item.displayAuthor).foregroundStyle(.secondary)
                    HStack { ForEach(companies.filter { item.companies[$0.id] != "unrelated" }) { company in
                        Text("\(company.name) · \(GoogleSignalSentimentFilter(rawValue: item.companies[company.id] ?? "uncertain")?.title ?? "待判断")").font(.caption)
                    } }
                    Text(item.originalContent).textSelection(.enabled)
                    if !item.quoteContent.isEmpty { Text("引用原文").font(.headline); Text(item.quoteContent).textSelection(.enabled) }
                    if !item.replyContent.isEmpty { Text("回复上下文").font(.headline); Text(item.replyContent).textSelection(.enabled) }
                    if !item.contentZH.isEmpty || !translated.isEmpty {
                        Divider(); Text("译文").font(.headline); Text(translated.isEmpty ? item.contentZH : translated).textSelection(.enabled)
                    } else {
                        Button(translating ? "正在翻译…" : "翻译正文") { Task { await translate() } }.disabled(translating)
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
    }
    @MainActor private func translate() async {
        translating = true; translationError = nil; defer { translating = false }
        do {
            translated = try await GoogleSignalService().translate(postID: item.translationPostID, source: item.source == "x" ? .x : .rss)
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
