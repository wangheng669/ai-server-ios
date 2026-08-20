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

    var previewPost: Post? { previewPost(translation: nil) }

    func previewPost(translation: String?) -> Post? {
        guard let postID = Int(exactly: postID) else { return nil }
        let cleanTranslation = translation?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Post(
            id: postID,
            title: title,
            text: content,
            summary: nil,
            content: content,
            contentZH: language.lowercased().hasPrefix("zh") ? content : cleanTranslation,
            source: "x",
            formattedTime: publishedAt.flatMap {
                GoogleSignalDatePresentation.relative(GoogleSignalDateParser.date(from: $0))
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
            meta: .googleSignalX(language: language, rawText: content)
        )
    }
}

private extension PostMeta {
    static func googleSignalX(language: String, rawText: String) -> PostMeta {
        PostMeta(
            metrics: nil,
            lang: language,
            urls: nil,
            rawText: rawText,
            noteText: nil,
            inReplyToScreenName: nil,
            inReplyToStatusID: nil,
            replyContext: nil,
            quotedTweet: nil,
            photoCredit: nil,
            zhihuRank: nil,
            zhihuHeat: nil,
            zhihuAnswers: nil,
            zhihuFollowerCount: nil,
            zhihuQuestionID: nil,
            zhihuURL: nil,
            zhihuAnswerExcerpt: nil,
            zhihuAnswerContent: nil,
            zhihuAnswerAuthor: nil,
            zhihuAnswerVoteupCount: nil,
            zhihuAnswerCommentCount: nil,
            rssFeedName: nil,
            rssFeedIcon: nil,
            rssArticleLink: nil,
            flashCategory: nil,
            flashSimilarityGroupId: nil,
            flashSimilarityScore: nil,
            flashSimilarCount: nil,
            flashPlatformCount: nil,
            flashPlatforms: nil
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

enum GoogleSignalDatePresentation {
    private static let chineseLocale = Locale(identifier: "zh-Hans-CN")

    static func relative(_ date: Date?) -> String? {
        date?.formatted(
            Date.RelativeFormatStyle(
                presentation: .named,
                locale: chineseLocale
            )
        )
    }

    static func detail(_ date: Date?) -> String {
        guard let date else { return "时间未知" }
        return date.formatted(
            .dateTime
                .locale(chineseLocale)
                .month()
                .day()
                .hour()
                .minute()
        )
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
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == activeGeneration else { return }
            if reset { events = [] }
            errorMessage = "暂时无法读取信号，请稍后重试"
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
    @Binding var section: GoogleSignalSection
    @Binding var sentiment: GoogleSignalSentimentFilter
    @State private var selectedEvent: GoogleSignalEvent?
    @Environment(\.scenePhase) private var scenePhase

    private var requestKey: String { "\(section.rawValue)-\(sentiment.rawValue)" }

    var body: some View {
        NavigationStack {
            content
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $selectedEvent) { event in
            GoogleSignalEventDetailView(event: event)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
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
            ProgressView("正在整理信号…")
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
                LazyVStack(spacing: 0) {
                    if store.events.isEmpty {
                        ContentUnavailableView(
                            section.emptyTitle,
                            systemImage: "waveform.path.ecg",
                            description: Text("后台识别到符合条件的新事件后会自动出现")
                        )
                        .padding(.top, 42)
                    } else {
                        ForEach(Array(store.events.enumerated()), id: \.element.id) { index, event in
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
                            if index < store.events.count - 1 {
                                Divider()
                                    .padding(.leading, 18)
                            }
                        }
                    }

                    if store.isLoadingMore {
                        ProgressView().padding(.vertical, 16)
                    }
                }
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct GoogleSignalFilterButton: View {
    let section: GoogleSignalSection
    let sentiment: GoogleSignalSentimentFilter
    @Binding var showsFilters: Bool

    var body: some View {
        Button {
            showsFilters = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal.decrease")
                Text(filterSummary)
                Image(systemName: "chevron.up")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 15)
            .frame(height: 42)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 12)
        .accessibilityLabel("筛选，当前为\(filterSummary)")
    }

    private var filterSummary: String {
        sentiment == .all ? section.title : "\(section.title) · \(sentiment.title)"
    }
}

struct GoogleSignalFilterOverlay: View {
    @Binding var section: GoogleSignalSection
    @Binding var sentiment: GoogleSignalSentimentFilter
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 16) {
                header
                filterGroup(
                    "内容",
                    items: GoogleSignalSection.allCases,
                    selection: $section,
                    title: \.title
                )
                filterGroup(
                    "倾向",
                    items: GoogleSignalSentimentFilter.allCases,
                    selection: $sentiment,
                    title: \.title
                )
            }
            .padding(14)
            .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(InvestmentDesign.divider, lineWidth: 0.5)
            }
            .overlay(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(InvestmentDesign.surface)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(45))
                    .offset(x: -48, y: 6)
            }
            .shadow(color: .black.opacity(0.14), radius: 22, y: 9)
            .padding(.horizontal, 18)
            .padding(.bottom, 130)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, dismiss)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.caption.weight(.bold))
                .foregroundStyle(InvestmentDesign.accent)
            Text("信号筛选")
                .font(.subheadline.weight(.bold))

            Spacer(minLength: 8)

            if section != .highlights || sentiment != .all {
                Button("重置") {
                    withAnimation(filterAnimation) {
                        section = .highlights
                        sentiment = .all
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(InvestmentDesign.accent)
            }
        }
    }

    private var filterAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.2, extraBounce: 0)
    }

    private func dismiss() {
        withAnimation(filterAnimation) {
            isPresented = false
        }
    }

    private func filterGroup<Item: Identifiable & Hashable>(
        _ groupTitle: String,
        items: [Item],
        selection: Binding<Item>,
        title: KeyPath<Item, String>
    ) -> some View where Item.ID == Item {
        VStack(alignment: .leading, spacing: 8) {
            Text(groupTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(items) { item in
                    Button {
                        withAnimation(filterAnimation) {
                            selection.wrappedValue = item
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if selection.wrappedValue == item {
                                Circle()
                                    .fill(InvestmentDesign.accent)
                                    .frame(width: 5, height: 5)
                            }
                            Text(item[keyPath: title])
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            selection.wrappedValue == item ? InvestmentDesign.accent : Color.primary
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            selection.wrappedValue == item
                                ? InvestmentDesign.accentSoft
                                : InvestmentDesign.secondarySurface,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    selection.wrappedValue == item
                                        ? InvestmentDesign.accent.opacity(0.24)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection.wrappedValue == item ? .isSelected : [])
                }
            }
        }
    }
}

private struct GoogleSignalEventCard: View {
    let event: GoogleSignalEvent
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(event.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                signalBadge(event.sentimentTitle, color: event.sentimentColor)
                    .fixedSize()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("查看事件进展和相关动态")
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

@MainActor
private final class GoogleSignalXTranslationStore: ObservableObject {
    @Published private(set) var translations: [String: String] = [:]
    @Published private(set) var loadingTweetIDs: Set<String> = []

    private let client: APIClient
    private var failedTweetIDs: Set<String> = []

    init(client: APIClient = APIClient(baseURL: ServerConfiguration.currentURL)) {
        self.client = client
    }

    func translation(for sourceURL: String) -> String? {
        guard let tweetID = Self.tweetID(from: sourceURL) else { return nil }
        return translations[tweetID]
    }

    func isLoading(_ sourceURL: String) -> Bool {
        guard let tweetID = Self.tweetID(from: sourceURL) else { return false }
        return loadingTweetIDs.contains(tweetID)
    }

    func translateIfNeeded(sourceURL: String, language: String, original: String) async {
        guard !language.lowercased().hasPrefix("zh"),
              let tweetID = Self.tweetID(from: sourceURL),
              translations[tweetID] == nil,
              !loadingTweetIDs.contains(tweetID),
              !failedTweetIDs.contains(tweetID) else { return }

        loadingTweetIDs.insert(tweetID)
        defer { loadingTweetIDs.remove(tweetID) }
        do {
            let response = try await client.fetchXTranslation(tweetID: tweetID)
            guard !Task.isCancelled else { return }
            let value = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value != original else { return }
            translations[tweetID] = value
        } catch is CancellationError {
            return
        } catch {
            failedTweetIDs.insert(tweetID)
        }
    }

    nonisolated static func tweetID(from sourceURL: String) -> String? {
        guard let url = URL(string: sourceURL) else { return nil }
        let components = url.pathComponents
        guard let statusIndex = components.firstIndex(of: "status"),
              components.indices.contains(statusIndex + 1) else { return nil }
        let value = components[statusIndex + 1]
        return !value.isEmpty && value.allSatisfy(\.isNumber) ? value : nil
    }
}

private struct GoogleSignalEventDetailView: View {
    let event: GoogleSignalEvent
    @StateObject private var evidenceStore: GoogleSignalEvidenceStore
    @StateObject private var translationStore = GoogleSignalXTranslationStore()
    @Environment(\.dismiss) private var dismiss
    @State private var representativeExpanded = false

    init(event: GoogleSignalEvent) {
        self.event = event
        _evidenceStore = StateObject(wrappedValue: GoogleSignalEvidenceStore(eventID: event.id))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    overview
                    sectionDivider
                    representativeEvidence
                    if !event.timeline.isEmpty {
                        sectionDivider
                        timeline
                    }
                    sectionDivider
                    evidenceList
                }
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("信号详情")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottomTrailing) {
                DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭信号详情")
                    .padding(16)
            }
            .task { await evidenceStore.load(reset: true) }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            Text("更新于 \(formattedDate(event.latestSeenDate)) · \(event.sourceCount) 个来源 · \(event.memberCount) 条动态")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if !event.companyTerms.isEmpty {
                Text(event.companyTerms.prefix(4).map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("事件进展", icon: "arrow.trianglehead.branch")
            ForEach(event.timeline) { item in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(item.direction == "previous" ? Color.secondary : Color.blue)
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(item.direction == "previous" ? "此前" : "后续") · \(formattedDate(item.date))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
    }

    private var representativeEvidence: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("核心动态", icon: "quote.bubble")
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
                Spacer(minLength: 8)
                if let url = URL(string: event.representativeSourceURL), !event.representativeSourceURL.isEmpty {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .background(Color.secondary.opacity(0.1), in: Circle())
                    }
                    .accessibilityLabel("查看原始动态")
                }
            }

            if representativeTranslation == nil,
               translationStore.isLoading(event.representativeSourceURL) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("正在翻译为中文")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(representativeContent)
                .font(.body)
                .lineSpacing(3)
                .lineLimit(representativeExpanded ? nil : 8)
                .fixedSize(horizontal: false, vertical: true)

            if representativeContent.count > 420 {
                Button(representativeExpanded ? "收起" : "展开全文") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        representativeExpanded.toggle()
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
    }

    private var storedRepresentativeTranslation: String? {
        guard let value = event.contentZH?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private var representativeTranslation: String? {
        storedRepresentativeTranslation ?? translationStore.translation(for: event.representativeSourceURL)
    }

    private var representativeContent: String {
        if let representativeTranslation {
            return representativeTranslation
        }
        let original = event.originalContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return original.isEmpty ? event.content : original
    }

    private var evidenceList: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                ForEach(Array(evidenceStore.items.enumerated()), id: \.element.id) { index, item in
                    let translation = translationStore.translation(for: item.sourceURL)
                    if let post = item.previewPost(translation: translation) {
                        NavigationLink {
                            PostDetailView(post: post, presentedAsSheet: false)
                        } label: {
                            GoogleSignalEvidenceRow(
                                item: item,
                                text: translation ?? item.content,
                                isTranslated: translation != nil
                            )
                        }
                        .buttonStyle(.plain)
                        .task {
                            await evidenceStore.loadMoreIfNeeded(after: item)
                        }
                        if index < evidenceStore.items.count - 1 {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
                if evidenceStore.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 10)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.08))
            .frame(height: 8)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }

    private func formattedDate(_ date: Date?) -> String {
        GoogleSignalDatePresentation.detail(date)
    }
}

private struct GoogleSignalEvidenceRow: View {
    let item: GoogleSignalEvidence
    let text: String
    let isTranslated: Bool

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
                    if isTranslated {
                        Image(systemName: "character.bubble")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("X 自动翻译")
                    }
                }
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                if let value = item.publishedAt,
                   let date = GoogleSignalDateParser.date(from: value) {
                    HStack(spacing: 4) {
                        if !item.authorHandle.isEmpty {
                            Text("@\(item.authorHandle.trimmingCharacters(in: CharacterSet(charactersIn: "@")))")
                            Text("·")
                        }
                        Text(GoogleSignalDatePresentation.relative(date) ?? "时间未知")
                    }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
