import SwiftUI

enum TodayActivitySource: Hashable {
    case x(String)
    case rss(Int)

    init?(post: Post) {
        if post.source == "x", let name = post.user?.userScreenName {
            let handle = name.trimmingCharacters(in: CharacterSet(charactersIn: "@ \t\n")).lowercased()
            guard !handle.isEmpty else { return nil }
            self = .x(handle)
        } else if let source = post.source, source.hasPrefix("rss:"),
                  let id = Int(source.dropFirst(4)), id > 0 {
            self = .rss(id)
        } else {
            return nil
        }
    }

    func fetchPage(_ page: Int, limit: Int, client: APIClient) async throws -> [Post] {
        switch self {
        case let .x(handle):
            return try await client.fetchXAuthorPosts(page: page, limit: limit, screenName: handle, bypassCache: true)
        case let .rss(id):
            return try await client.fetchRSSFeedPosts(
                feedID: id, page: page, limit: limit, cachePolicy: .reloadIgnoringLocalCacheData
            )
        }
    }

    @MainActor
    func shouldRefresh(for event: RealtimeFeedClient.Event) -> Bool {
        switch event {
        case let .post(post):
            return Self(post: post) == self
        case let .taskCompleted(name):
            switch self {
            case .x: return name == "x" || name == "x_home" || name == "x_home_following"
            case .rss: return name == "rss"
            }
        case .deploymentStatus:
            return false
        }
    }
}

struct TodayActivityItem: Identifiable, Equatable {
    let post: Post
    let publishedAt: Date

    var id: Int { post.id }
    var sourceLabel: String { post.isRSS ? post.rssCardSourceName : "X · \(post.authorName)" }
    var originalSummary: String { post.isRSS ? post.feedOriginalTitle : post.xStoredOriginalContent }
    var sourceLanguageHint: String? {
        post.source == "x" ? XDeviceTranslation.declaredLanguage(post.meta?.lang) : nil
    }

    @MainActor
    var chineseSummary: String? {
        let translated: String?
        if post.isRSS {
            translated = LocalTranslatedText.chineseText(post.displayTitle)
        } else {
            let serverText = post.hasTranslation && !post.needsXTranslation
                ? LocalTranslatedText.chineseText(post.displayContent) : nil
            translated = serverText ?? post.xTweetID.flatMap {
                FeedTranslationCache.shared.cachedXTranslation(tweetID: $0, original: originalSummary)
            }
        }
        let originalChinese = sourceLanguageHint == nil ? LocalTranslatedText.chineseText(originalSummary) : nil
        return (translated ?? originalChinese)?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

struct TodayActivityReportReferences: Equatable, Sendable {
    private let postIDs: Set<Int>
    private var textKeys: Set<String>

    init(postIDs: [Int], cardTexts: [String]) {
        self.postIDs = Set(postIDs)
        textKeys = Set(cardTexts.compactMap(Self.textKey))
    }

    mutating func include(_ source: TodaySourcePresentation) {
        guard postIDs.contains(source.id) else { return }
        if let original = Self.textKey(source.originalText) { textKeys.insert(original) }
        if let chinese = source.chineseText.flatMap(Self.textKey) { textKeys.insert(chinese) }
    }

    func contains(_ post: Post) -> Bool {
        postIDs.contains(post.id) || Self.textKey(post.xStoredOriginalContent).map(textKeys.contains) == true
    }

    private static func textKey(_ text: String) -> String? {
        let key = TodayReadingEvent.canonical(text)
        guard !key.isEmpty, key != "无标题" else { return nil }
        return key
    }
}

struct TodayActivityQuery: Equatable {
    let source: TodayActivitySource
    let reportReferences: TodayActivityReportReferences
}

private struct TodayActivitySnapshot: Equatable {
    let query: TodayActivityQuery
    let dayStart: Date
    var items: [TodayActivityItem] = []
    var refreshFailed = false
}

@MainActor @Observable
final class TodayActivityStore {
    private var snapshot: TodayActivitySnapshot?

    func items(for query: TodayActivityQuery?) -> [TodayActivityItem] {
        current(for: query)?.items ?? []
    }

    func refreshFailed(for query: TodayActivityQuery?) -> Bool {
        current(for: query)?.refreshFailed ?? false
    }

    private func current(for query: TodayActivityQuery?) -> TodayActivitySnapshot? {
        guard let snapshot, snapshot.query == query,
              snapshot.dayStart == TodayBriefDate.shanghaiCalendar.startOfDay(for: .now) else { return nil }
        return snapshot
    }

    func observe(query: TodayActivityQuery, client: APIClient) async {
        let (updates, trigger) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let realtime = RealtimeFeedClient(baseURL: client.baseURL)
        realtime.onEvent = { event in
            if query.source.shouldRefresh(for: event) { trigger.yield() }
        }
        realtime.start()
        trigger.yield()
        let periodic = Task {
            while !Task.isCancelled {
                let now = Date.now
                let endOfDay = TodayBriefDate.shanghaiCalendar.dateInterval(of: .day, for: now)?.end
                let seconds = endOfDay.map { min(30, $0.timeIntervalSince(now)) } ?? 30
                do { try await Task.sleep(for: .seconds(seconds)) }
                catch { return }
                guard !Task.isCancelled else { return }
                if let snapshot, snapshot.query == query, current(for: query) == nil {
                    self.snapshot = nil
                }
                trigger.yield()
            }
        }
        defer {
            periodic.cancel()
            realtime.stop()
            trigger.finish()
        }

        for await _ in updates {
            guard !Task.isCancelled,
                  let day = TodayBriefDate.shanghaiCalendar.dateInterval(of: .day, for: .now) else { return }
            if current(for: query) == nil {
                snapshot = TodayActivitySnapshot(query: query, dayStart: day.start)
            }
            do {
                let items = try await Self.fetchToday(query: query, day: day, client: client)
                guard !Task.isCancelled else { return }
                guard current(for: query)?.dayStart == day.start else { continue }
                let updated = TodayActivitySnapshot(query: query, dayStart: day.start, items: items)
                if snapshot != updated { snapshot = updated }
            } catch {
                guard !Task.isCancelled else { return }
                if let current = current(for: query), current.dayStart == day.start, !current.refreshFailed {
                    snapshot?.refreshFailed = true
                }
            }
        }
    }

    private static func fetchToday(
        query: TodayActivityQuery, day: DateInterval, client: APIClient
    ) async throws -> [TodayActivityItem] {
        let pageSize = 12
        var page = 1
        var items: [TodayActivityItem] = []
        var seen = Set<Int>()
        while items.count < 2 {
            try Task.checkCancellation()
            let posts = try await query.source.fetchPage(page, limit: pageSize, client: client)
            let newPosts = posts.filter { seen.insert($0.id).inserted }
            let dated = newPosts.compactMap { post -> TodayActivityItem? in
                guard let publishedAt = post.articlePostAt.flatMap(TodayBriefDate.parseTimestamp) else { return nil }
                return TodayActivityItem(post: post, publishedAt: publishedAt)
            }
            items.append(contentsOf: dated.filter {
                $0.publishedAt >= day.start && $0.publishedAt < day.end && $0.publishedAt <= .now
                    && TodayActivitySource(post: $0.post) == query.source && !$0.post.isXRetweetWrapper
                    && !query.reportReferences.contains($0.post)
            })
            if posts.count < pageSize || newPosts.isEmpty || dated.contains(where: { $0.publishedAt < day.start }) { break }
            page += 1
        }
        return Array(items.sorted {
            ($0.publishedAt, $0.id) > ($1.publishedAt, $1.id)
        }.prefix(2))
    }
}

struct TodayActivityRows: View {
    let items: [TodayActivityItem]
    let refreshFailed: Bool
    let open: (Post) -> Void

    private let shape = RoundedRectangle(cornerRadius: 16)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                if item.id != items.first?.id {
                    separator
                }
                Button {
                    open(item.post)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(TodayBriefDate.activityTime(item.publishedAt)) · \(item.sourceLabel)")
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(TodayBriefStyle.accent)
                        TodayActivitySummary(item: item)
                            .font(.body)
                            .foregroundStyle(TodayBriefStyle.ink)
                            .lineSpacing(3)
                            .lineLimit(3)
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today-activity-\(item.id)")
            }
            if refreshFailed {
                if !items.isEmpty { separator }
                Text("动态暂未更新")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
            }
        }
        .background(TodayBriefStyle.accent.opacity(0.035), in: shape)
        .overlay {
            shape.strokeBorder(TodayBriefStyle.surfaceOutline)
                .allowsHitTesting(false)
        }
    }

    private var separator: some View {
        TodayBriefStyle.rule.frame(height: 1)
            .padding(.horizontal, 14)
    }
}

private struct TodayActivitySummary: View {
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @Environment(\.scenePhase) private var scenePhase
    @State private var resolvedXText: (key: String, text: String)?

    let item: TodayActivityItem

    var body: some View {
        let input = item.post.xBodyTranslationInput
        let translated = resolvedXText.flatMap { value in
            value.key == input?.key ? value.text : nil
        }
        let chinese = item.chineseSummary ?? translated
        let isActive = rootTabIsActive && scenePhase == .active
        let request = isActive && chinese == nil ? input : nil
        FeedReaderTranslationText(
            original: item.originalSummary, chinese: chinese, field: .summary,
            isActive: isActive, showsTranslationControls: false, sourceLanguageHint: item.sourceLanguageHint
        )
        .task(id: request?.key) {
            guard let request else { return }
            let client = APIClient(baseURL: ServerConfiguration.currentURL)
            guard let translation = try? await FeedTranslationCache.shared.translateXPost(
                tweetID: request.tweetID, original: request.original, sourceLanguage: request.sourceLanguage,
                replyContext: request.replyContext, using: client.fetchXTranslation
            ), !Task.isCancelled else { return }
            resolvedXText = (request.key, translation)
        }
    }
}
