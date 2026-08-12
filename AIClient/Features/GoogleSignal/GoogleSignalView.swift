import SwiftUI

enum GoogleSignalSection: String, CaseIterable, Identifiable {
    case highlights
    case latest
    case progress

    var id: Self { self }

    var title: String {
        switch self {
        case .highlights: "今日重点"
        case .latest: "最新事件"
        case .progress: "最新进展"
        }
    }

    var emptyTitle: String {
        switch self {
        case .highlights: "暂无今日重点"
        case .latest: "暂无相关事件"
        case .progress: "暂无最新进展"
        }
    }
}

enum GoogleSignalSentimentFilter: String, CaseIterable, Identifiable {
    case all
    case positive
    case negative
    case neutral

    var id: Self { self }
    var queryValue: String? { self == .all ? nil : rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .positive: "利好"
        case .negative: "利空"
        case .neutral: "中性"
        }
    }
}

struct GoogleSignalEventPage: Decodable, Equatable {
    let items: [GoogleSignalEvent]
    let hasMore: Bool
    let nextCursor: String

    enum CodingKeys: String, CodingKey {
        case items
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

struct GoogleSignalEvent: Decodable, Equatable, Identifiable {
    let id: Int64
    let representativeID: Int64
    let representativePostID: Int64
    let memberCount: Int
    let sourceCount: Int
    let firstSeenAt: String
    let latestSeenAt: String
    let title: String
    let content: String
    let originalContent: String
    let contentZH: String?
    let language: String
    let representativeAuthorName: String
    let representativeAuthor: String
    let representativeAvatarURL: String
    let representativeSourceURL: String
    let sentiment: String
    let confidence: Double
    let reason: String
    let factStatus: String
    let companyTerms: [String]
    let classifiedAt: String
    let publishedAt: String?
    let timeline: [GoogleSignalTimelineItem]
    let priorityScore: Int?
    let priorityReasons: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, content, language, sentiment, confidence, reason, timeline
        case representativeID = "representative_id"
        case representativePostID = "representative_post_id"
        case memberCount = "member_count"
        case sourceCount = "source_count"
        case firstSeenAt = "first_seen_at"
        case latestSeenAt = "latest_seen_at"
        case originalContent = "original_content"
        case contentZH = "content_zh"
        case representativeAuthorName = "representative_author_name"
        case representativeAuthor = "representative_author"
        case representativeAvatarURL = "representative_avatar_url"
        case representativeSourceURL = "representative_source_url"
        case factStatus = "fact_status"
        case companyTerms = "company_terms"
        case classifiedAt = "classified_at"
        case publishedAt = "published_at"
        case priorityScore = "priority_score"
        case priorityReasons = "priority_reasons"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        representativeID = try values.decode(Int64.self, forKey: .representativeID)
        representativePostID = try values.decode(Int64.self, forKey: .representativePostID)
        memberCount = try values.decode(Int.self, forKey: .memberCount)
        sourceCount = try values.decode(Int.self, forKey: .sourceCount)
        firstSeenAt = try values.decode(String.self, forKey: .firstSeenAt)
        latestSeenAt = try values.decode(String.self, forKey: .latestSeenAt)
        title = try values.decode(String.self, forKey: .title)
        content = try values.decode(String.self, forKey: .content)
        originalContent = try values.decode(String.self, forKey: .originalContent)
        contentZH = try values.decodeIfPresent(String.self, forKey: .contentZH)
        language = try values.decode(String.self, forKey: .language)
        representativeAuthorName = try values.decode(String.self, forKey: .representativeAuthorName)
        representativeAuthor = try values.decode(String.self, forKey: .representativeAuthor)
        representativeAvatarURL = try values.decode(String.self, forKey: .representativeAvatarURL)
        representativeSourceURL = try values.decode(String.self, forKey: .representativeSourceURL)
        sentiment = try values.decode(String.self, forKey: .sentiment)
        confidence = try values.decode(Double.self, forKey: .confidence)
        reason = try values.decode(String.self, forKey: .reason)
        factStatus = try values.decode(String.self, forKey: .factStatus)
        companyTerms = try values.decodeIfPresent([String].self, forKey: .companyTerms) ?? []
        classifiedAt = try values.decode(String.self, forKey: .classifiedAt)
        publishedAt = try values.decodeIfPresent(String.self, forKey: .publishedAt)
        timeline = try values.decodeIfPresent([GoogleSignalTimelineItem].self, forKey: .timeline) ?? []
        priorityScore = try values.decodeIfPresent(Int.self, forKey: .priorityScore)
        priorityReasons = try values.decodeIfPresent([String].self, forKey: .priorityReasons) ?? []
    }

    var factStatusTitle: String {
        switch factStatus {
        case "unverified": "未证实"
        case "planned": "计划中"
        case "ongoing": "进行中"
        case "confirmed": "已确认"
        case "completed": "已完成"
        case "delayed": "已延期"
        case "cancelled": "已取消"
        case "opinion": "观点"
        default: "状态未知"
        }
    }

    var factStatusColor: Color {
        switch factStatus {
        case "confirmed", "completed": .green
        case "unverified": .orange
        case "delayed", "cancelled": .red
        case "planned", "ongoing": .blue
        default: .secondary
        }
    }

    var sentimentTitle: String {
        switch sentiment {
        case "positive": "利好"
        case "negative": "利空"
        default: "中性"
        }
    }

    var sentimentColor: Color {
        switch sentiment {
        case "positive": .green
        case "negative": .red
        default: .secondary
        }
    }

    var firstSeenDate: Date? { GoogleSignalDateParser.date(from: firstSeenAt) }
    var latestSeenDate: Date? { GoogleSignalDateParser.date(from: latestSeenAt) }
}

struct GoogleSignalTimelineItem: Decodable, Equatable, Identifiable {
    let eventID: Int64
    let relation: String
    let direction: String
    let title: String
    let factStatus: String
    let memberCount: Int
    let sourceCount: Int
    let firstSeenAt: String
    let latestSeenAt: String

    var id: Int64 { eventID }

    enum CodingKeys: String, CodingKey {
        case relation, direction, title
        case eventID = "event_id"
        case factStatus = "fact_status"
        case memberCount = "member_count"
        case sourceCount = "source_count"
        case firstSeenAt = "first_seen_at"
        case latestSeenAt = "latest_seen_at"
    }

    var date: Date? { GoogleSignalDateParser.date(from: firstSeenAt) }
}

struct GoogleSignalEvidencePage: Decodable, Equatable {
    let items: [GoogleSignalEvidence]
    let hasMore: Bool
    let nextCursor: String

    enum CodingKeys: String, CodingKey {
        case items
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

struct GoogleSignalEvidence: Decodable, Equatable, Identifiable {
    let id: Int64
    let postID: Int64
    let articleID: String
    let title: String
    let content: String
    let language: String
    let authorName: String
    let authorHandle: String
    let avatarURL: String
    let sourceURL: String
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, content, language
        case postID = "post_id"
        case articleID = "article_id"
        case authorName = "author_name"
        case authorHandle = "author_handle"
        case avatarURL = "avatar_url"
        case sourceURL = "source_url"
        case publishedAt = "published_at"
    }

    var previewPost: Post? {
        guard let postID = Int(exactly: postID) else { return nil }
        return Post(
            id: postID,
            title: title,
            text: content,
            summary: nil,
            content: content,
            contentZH: language.lowercased().hasPrefix("zh") ? content : nil,
            source: "x",
            formattedTime: publishedAt.flatMap {
                GoogleSignalDateParser.date(from: $0)?.formatted(.relative(presentation: .named))
            },
            weightReason: nil,
            finalScore: nil,
            weight: nil,
            postLink: sourceURL,
            articlePostAt: publishedAt,
            user: PostUser(
                userName: authorName,
                userScreenName: authorHandle,
                avatarURL: avatarURL,
                userDesc: nil
            ),
            postTags: [],
            images: [],
            videos: [],
            feedRank: nil,
            meta: nil
        )
    }
}

enum GoogleSignalDateParser {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter = ISO8601DateFormatter()

    static func date(from value: String) -> Date? {
        fractionalFormatter.date(from: value) ?? standardFormatter.date(from: value)
    }
}

private struct GoogleSignalAPIEnvelope<Value: Decodable>: Decodable {
    let success: Bool
    let data: Value
}

private enum GoogleSignalServiceError: Error {
    case invalidURL
    case invalidResponse
}

struct GoogleSignalService {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = ServerConfiguration.currentURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetchEvents(
        section: GoogleSignalSection,
        sentiment: GoogleSignalSentimentFilter,
        cursor: String? = nil,
        limit: Int = 20
    ) async throws -> GoogleSignalEventPage {
        var components = URLComponents(
            url: baseURL.appending(path: "api/ios/v1/google-noise/events"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [
            URLQueryItem(name: "view", value: section.rawValue),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50))),
        ]
        if let sentiment = sentiment.queryValue {
            queryItems.append(.init(name: "sentiment", value: sentiment))
        }
        if let cursor, !cursor.isEmpty, section == .latest {
            queryItems.append(.init(name: "cursor", value: cursor))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw GoogleSignalServiceError.invalidURL }
        return try await get(url, as: GoogleSignalEventPage.self)
    }

    func fetchEvidence(
        eventID: Int64,
        cursor: String? = nil,
        limit: Int = 20
    ) async throws -> GoogleSignalEvidencePage {
        var components = URLComponents(
            url: baseURL.appending(path: "api/ios/v1/google-noise/events/\(eventID)/articles"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))]
        if let cursor, !cursor.isEmpty {
            queryItems.append(.init(name: "cursor", value: cursor))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw GoogleSignalServiceError.invalidURL }
        return try await get(url, as: GoogleSignalEvidencePage.self)
    }

    private func get<Value: Decodable>(_ url: URL, as type: Value.Type) async throws -> Value {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw GoogleSignalServiceError.invalidResponse
        }
        let envelope = try JSONDecoder().decode(GoogleSignalAPIEnvelope<Value>.self, from: data)
        guard envelope.success else { throw GoogleSignalServiceError.invalidResponse }
        return envelope.data
    }
}

@MainActor
private final class GoogleSignalStore: ObservableObject {
    @Published private(set) var events: [GoogleSignalEvent] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    private let service: GoogleSignalService
    private var hasMore = false
    private var nextCursor = ""
    private var generation = 0

    init(service: GoogleSignalService = GoogleSignalService()) {
        self.service = service
    }

    func load(
        section: GoogleSignalSection,
        sentiment: GoogleSignalSentimentFilter,
        reset: Bool
    ) async {
        if reset {
            generation += 1
            isLoading = true
            isLoadingMore = false
            errorMessage = nil
        } else {
            guard section == .latest, hasMore, !isLoading, !isLoadingMore else { return }
            isLoadingMore = true
        }
        let activeGeneration = generation
        defer {
            if generation == activeGeneration {
                isLoading = false
                isLoadingMore = false
            }
        }
        do {
            let page = try await service.fetchEvents(
                section: section,
                sentiment: sentiment,
                cursor: reset ? nil : nextCursor
            )
            guard generation == activeGeneration, !Task.isCancelled else { return }
            events = reset ? page.items : events + page.items.filter { next in
                !events.contains(where: { $0.id == next.id })
            }
            hasMore = page.hasMore
            nextCursor = page.nextCursor
            lastUpdated = Date()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == activeGeneration else { return }
            if reset { events = [] }
            errorMessage = "暂时无法读取 Google 信号，请稍后重试"
        }
    }

    func loadMoreIfNeeded(
        after event: GoogleSignalEvent,
        section: GoogleSignalSection,
        sentiment: GoogleSignalSentimentFilter
    ) async {
        guard event.id == events.last?.id else { return }
        await load(section: section, sentiment: sentiment, reset: false)
    }
}

struct GoogleSignalView: View {
    @StateObject private var store = GoogleSignalStore()
    @State private var section: GoogleSignalSection = .highlights
    @State private var sentiment: GoogleSignalSentimentFilter = .all
    @State private var selectedEvent: GoogleSignalEvent?
    @Environment(\.scenePhase) private var scenePhase

    private var requestKey: String { "\(section.rawValue)-\(sentiment.rawValue)" }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                content
            }
            .navigationTitle("Google 信号")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await store.load(section: section, sentiment: sentiment, reset: true)
            }
        }
        .sheet(item: $selectedEvent) { event in
            GoogleSignalEventDetailView(event: event)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .task(id: requestKey) {
            await store.load(section: section, sentiment: sentiment, reset: true)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.load(section: section, sentiment: sentiment, reset: true) }
        }
    }

    @ViewBuilder private var content: some View {
        if store.isLoading && store.events.isEmpty {
            ProgressView("正在整理 Google 信号…")
        } else if let errorMessage = store.errorMessage, store.events.isEmpty {
            ContentUnavailableView {
                Label("信号暂不可用", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("重新加载") {
                    Task { await store.load(section: section, sentiment: sentiment, reset: true) }
                }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    header
                    sectionPicker
                    sentimentFilters

                    if store.events.isEmpty {
                        ContentUnavailableView(
                            section.emptyTitle,
                            systemImage: "waveform.path.ecg",
                            description: Text("后台识别到符合条件的新事件后会自动出现")
                        )
                        .padding(.top, 42)
                    } else {
                        ForEach(store.events) { event in
                            GoogleSignalEventCard(event: event) {
                                selectedEvent = event
                            }
                            .task {
                                await store.loadMoreIfNeeded(
                                    after: event,
                                    section: section,
                                    sentiment: sentiment
                                )
                            }
                        }
                    }

                    if store.isLoadingMore {
                        ProgressView().padding(.vertical, 16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Google 事件雷达")
                        .font(.title2.bold())
                    Text("从 X 动态中提炼事件、证据与后续进展")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Label("实时", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            if let lastUpdated = store.lastUpdated {
                Text("更新于 \(lastUpdated.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.7)
        }
    }

    private var sectionPicker: some View {
        Picker("信号视图", selection: $section) {
            ForEach(GoogleSignalSection.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private var sentimentFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(GoogleSignalSentimentFilter.allCases) { item in
                    Button {
                        sentiment = item
                    } label: {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(sentiment == item ? Color.white : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                sentiment == item ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct GoogleSignalEventCard: View {
    let event: GoogleSignalEvent
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    signalBadge(event.factStatusTitle, color: event.factStatusColor)
                    signalBadge(event.sentimentTitle, color: event.sentimentColor)
                    Spacer()
                    if !event.timeline.isEmpty {
                        Label("有新进展", systemImage: "arrow.trianglehead.branch")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }

                Text(event.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !event.reason.isEmpty {
                    Text(event.reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !event.priorityReasons.isEmpty {
                    Text(event.priorityReasons.prefix(3).joined(separator: " · "))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                }

                HStack(spacing: 12) {
                    Label(relativeTime, systemImage: "clock")
                    Label("\(event.memberCount) 条动态", systemImage: "text.bubble")
                    Label("\(event.sourceCount) 个 X 账号", systemImage: "person.2")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("查看事件进展和相关动态")
    }

    private var relativeTime: String {
        event.firstSeenDate?.formatted(.relative(presentation: .named)) ?? "时间未知"
    }
}

private func signalBadge(_ title: String, color: Color) -> some View {
    Text(title)
        .font(.caption.weight(.bold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.11), in: Capsule())
}

@MainActor
private final class GoogleSignalEvidenceStore: ObservableObject {
    @Published private(set) var items: [GoogleSignalEvidence] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?

    private let eventID: Int64
    private let service: GoogleSignalService
    private var hasMore = false
    private var nextCursor = ""

    init(eventID: Int64, service: GoogleSignalService = GoogleSignalService()) {
        self.eventID = eventID
        self.service = service
    }

    func load(reset: Bool) async {
        if reset {
            guard !isLoading else { return }
            isLoading = true
            errorMessage = nil
        } else {
            guard hasMore, !isLoading, !isLoadingMore else { return }
            isLoadingMore = true
        }
        defer {
            isLoading = false
            isLoadingMore = false
        }
        do {
            let page = try await service.fetchEvidence(
                eventID: eventID,
                cursor: reset ? nil : nextCursor
            )
            guard !Task.isCancelled else { return }
            items = reset ? page.items : items + page.items.filter { next in
                !items.contains(where: { $0.id == next.id })
            }
            hasMore = page.hasMore
            nextCursor = page.nextCursor
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            if reset { items = [] }
            errorMessage = "相关动态暂时无法读取"
        }
    }

    func loadMoreIfNeeded(after item: GoogleSignalEvidence) async {
        guard item.id == items.last?.id else { return }
        await load(reset: false)
    }
}

private struct GoogleSignalEventDetailView: View {
    let event: GoogleSignalEvent
    @StateObject private var evidenceStore: GoogleSignalEvidenceStore
    @Environment(\.dismiss) private var dismiss

    init(event: GoogleSignalEvent) {
        self.event = event
        _evidenceStore = StateObject(wrappedValue: GoogleSignalEvidenceStore(eventID: event.id))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    overview
                    if !event.timeline.isEmpty { timeline }
                    representativeEvidence
                    evidenceList
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("信号详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await evidenceStore.load(reset: true) }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                signalBadge(event.factStatusTitle, color: event.factStatusColor)
                signalBadge(event.sentimentTitle, color: event.sentimentColor)
            }

            Text(event.title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)

            if !event.reason.isEmpty {
                Text(event.reason)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                detailRow("首次发现", value: formattedDate(event.firstSeenDate))
                detailRow("最后更新", value: formattedDate(event.latestSeenDate))
                detailRow("相关动态", value: "\(event.memberCount) 条")
                detailRow("涉及账号", value: "\(event.sourceCount) 个 X 账号")
            }

            if !event.companyTerms.isEmpty {
                Text(event.companyTerms.prefix(6).map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func detailRow(_ title: String, value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("事件进展", icon: "arrow.trianglehead.branch")
            ForEach(event.timeline) { item in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(item.direction == "previous" ? Color.secondary : Color.blue)
                            .frame(width: 9, height: 9)
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 1, height: 54)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.direction == "previous" ? "此前" : "后续")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(formattedDate(item.date))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var representativeEvidence: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("代表性动态", icon: "quote.bubble")
            HStack(spacing: 10) {
                AvatarView(
                    url: URL(string: event.representativeAvatarURL),
                    name: event.representativeAuthorName,
                    size: 38,
                    cornerRadius: 19
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.representativeAuthorName.isEmpty ? "X 来源" : event.representativeAuthorName)
                        .font(.subheadline.weight(.semibold))
                    if !event.representativeAuthor.isEmpty {
                        Text("@\(event.representativeAuthor.trimmingCharacters(in: CharacterSet(charactersIn: "@")))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(representativeContent)
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if let url = URL(string: event.representativeSourceURL), !event.representativeSourceURL.isEmpty {
                Link(destination: url) {
                    Label("查看原始动态", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var representativeContent: String {
        let translated = event.contentZH?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let translated, !translated.isEmpty { return translated }
        return event.content
    }

    private var evidenceList: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("相关动态", icon: "text.bubble")

            if evidenceStore.isLoading && evidenceStore.items.isEmpty {
                ProgressView("正在读取证据…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else if let errorMessage = evidenceStore.errorMessage, evidenceStore.items.isEmpty {
                VStack(spacing: 10) {
                    Text(errorMessage).foregroundStyle(.secondary)
                    Button("重新加载") { Task { await evidenceStore.load(reset: true) } }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                ForEach(evidenceStore.items) { item in
                    if let post = item.previewPost {
                        NavigationLink {
                            PostDetailView(post: post, presentedAsSheet: false)
                        } label: {
                            GoogleSignalEvidenceRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .task { await evidenceStore.loadMoreIfNeeded(after: item) }
                    }
                }
                if evidenceStore.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 10)
                }
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "时间未知" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct GoogleSignalEvidenceRow: View {
    let item: GoogleSignalEvidence

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(
                url: URL(string: item.avatarURL),
                name: item.authorName,
                size: 36,
                cornerRadius: 18
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.authorName.isEmpty ? item.authorHandle : item.authorName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(item.content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                if let value = item.publishedAt,
                   let date = GoogleSignalDateParser.date(from: value) {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
