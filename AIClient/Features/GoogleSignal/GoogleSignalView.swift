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
    var sentimentTitle: String { GoogleSignalSentimentFilter(rawValue: sentiment)?.title ?? "待判断" }
}

private struct CompanyNewsEnvelope<Value: Decodable>: Decodable { let success: Bool; let data: Value }
struct GoogleSignalService {
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
    func fetchNews(company: String, sentiment: GoogleSignalSentimentFilter, cursor: String? = nil) async throws -> CompanyNewsPage {
        try await get(newsURL(company: company, sentiment: sentiment, cursor: cursor), as: CompanyNewsPage.self)
    }
    func fetchCompanies() async throws -> [CompanyNewsCompany] {
        struct Catalog: Decodable { let companies: [CompanyNewsCompany] }
        return try await get(baseURL.appending(path: "api/ios/v1/company-news/catalog"), as: Catalog.self).companies
    }
    func translateRSS(postID: Int64) async throws -> String {
        struct Document: Decodable { let postId: Int64; let status: String; let text: String? }
        struct Documents: Decodable { let items: [Document] }
        for attempt in 0..<20 {
            try Task.checkCancellation()
            var request = URLRequest(url: baseURL.appending(path: "api/ios/v1/company-news/rss-translations"))
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["postIds": [postID], "part": "article", "intent": attempt == 0 ? "read" : "observe", "retry": attempt == 0])
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError.invalidResponse }
            let output = try JSONDecoder().decode(CompanyNewsEnvelope<Documents>.self, from: data)
            guard output.success, let document = output.data.items.first, document.postId == postID else { throw APIError.invalidResponse }
            if let text = document.text, !text.isEmpty { return text }
            if document.status == "failed" { throw APIError.invalidResponse }
            try await Task.sleep(for: .seconds(2))
        }
        throw APIError.invalidResponse
    }
    private func get<Value: Decodable>(_ url: URL, as type: Value.Type) async throws -> Value {
        var request = URLRequest(url: url); request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw APIError.invalidResponse }
        let envelope = try JSONDecoder().decode(CompanyNewsEnvelope<Value>.self, from: data)
        guard envelope.success else { throw APIError.invalidResponse }; return envelope.data
    }
}

struct GoogleSignalView: View {
    @Binding var sentiment: GoogleSignalSentimentFilter
    @State private var companies: [CompanyNewsCompany] = []
    @State private var company = ""
    @State private var items: [CompanyNewsItem] = []
    @State private var selected: CompanyNewsItem?
    @State private var loading = false
    @State private var loadingMore = false
    @State private var hasMore = false
    @State private var cursor = ""
    @State private var error: String?
    @State private var generation = 0
    @State private var retry = 0
    @Environment(\.scenePhase) private var scenePhase
    private var requestKey: String { "\(company)|\(sentiment.rawValue)|\(retry)" }

    var body: some View {
        VStack(spacing: 0) {
            if !companies.isEmpty {
                Picker("公司", selection: $company) {
                    ForEach(companies) { Text($0.name).tag($0.id) }
                }.pickerStyle(.segmented).padding()
            }
            if loading && items.isEmpty { ProgressView("正在读取资讯…").frame(maxHeight: .infinity) }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let error {
                            VStack(spacing: 8) { Text(error); Button("重试") { retry += 1 } }.frame(maxWidth: .infinity).padding()
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
                                    Text([item.authorName.isEmpty ? item.source : item.authorName, GoogleSignalDatePresentation.detail(GoogleSignalDateParser.date(from: item.publishedAt))].joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }.padding(.horizontal, 18).padding(.vertical, 14).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider().padding(.leading, 18)
                        }
                        if hasMore { Button(loadingMore ? "正在加载…" : "加载更多") { Task { await load(reset: false) } }.disabled(loadingMore).padding() }
                    }.padding(.bottom, 100)
                }.refreshable { await load(reset: true) }
            }
        }
        .sheet(item: $selected) { item in CompanyNewsDetail(item: item, companies: companies) }
        .task(id: requestKey) {
            if companies.isEmpty {
                do { companies = try await GoogleSignalService().fetchCompanies(); company = companies.first?.id ?? "" }
                catch { self.error = "公司目录读取失败，请重试" }
            }
            guard !company.isEmpty else { return }; await load(reset: true)
        }
        .onChange(of: scenePhase) { _, value in if value == .active { retry += 1 } }
    }
    @MainActor private func load(reset: Bool) async {
        if reset { generation += 1; loading = true; loadingMore = false; error = nil }
        else { guard hasMore && !loading && !loadingMore else { return }; loadingMore = true }
        let current = generation
        defer { if current == generation { loading = false; loadingMore = false } }
        do {
            let page = try await GoogleSignalService().fetchNews(company: company, sentiment: sentiment, cursor: reset ? nil : cursor)
            guard !Task.isCancelled, current == generation else { return }
            items = reset ? page.items : items + page.items.filter { next in !items.contains { $0.id == next.id } }
            cursor = page.nextCursor; hasMore = page.hasMore; error = nil
        } catch {
            guard !Task.isCancelled, current == generation else { return }
            self.error = "资讯读取失败，请重试"
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(item.displayTitle).font(.title2.bold())
                    Text(item.authorName.isEmpty ? item.source : item.authorName).foregroundStyle(.secondary)
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
            }.navigationTitle("公司资讯").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.inAppBrowserCover(item: $browser)
    }
    @MainActor private func translate() async {
        translating = true; translationError = nil; defer { translating = false }
        do {
            if item.source == "x" && !item.articleID.isEmpty {
                translated = try await APIClient(baseURL: ServerConfiguration.currentURL).fetchXTranslation(tweetID: item.articleID).text
            } else { translated = try await GoogleSignalService().translateRSS(postID: item.translationPostID) }
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
    static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
enum GoogleSignalDatePresentation {
    static func detail(_ date: Date?) -> String {
        guard let date else { return "时间未知" }
        return date.formatted(.dateTime.locale(Locale(identifier: "zh-Hans-CN")).month().day().hour().minute())
    }
}
