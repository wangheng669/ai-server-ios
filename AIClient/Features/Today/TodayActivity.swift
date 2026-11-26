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
    var summary: String {
        let content = post.isRSS ? post.displayTitle : post.displayContent
        return content.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

private struct TodayActivitySnapshot: Equatable {
    let source: TodayActivitySource
    let dayStart: Date
    var items: [TodayActivityItem] = []
    var refreshFailed = false
}

@MainActor @Observable
final class TodayActivityStore {
    private var snapshot: TodayActivitySnapshot?

    func items(for source: TodayActivitySource?) -> [TodayActivityItem] {
        current(for: source)?.items ?? []
    }

    func refreshFailed(for source: TodayActivitySource?) -> Bool {
        current(for: source)?.refreshFailed ?? false
    }

    private func current(for source: TodayActivitySource?) -> TodayActivitySnapshot? {
        guard let snapshot, snapshot.source == source,
              snapshot.dayStart == TodayBriefDate.shanghaiCalendar.startOfDay(for: .now) else { return nil }
        return snapshot
    }

    func observe(source: TodayActivitySource, client: APIClient) async {
        let (updates, trigger) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let realtime = RealtimeFeedClient(baseURL: client.baseURL)
        realtime.onEvent = { event in
            if source.shouldRefresh(for: event) { trigger.yield() }
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
                if let snapshot, snapshot.source == source, current(for: source) == nil {
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
            if current(for: source) == nil {
                snapshot = TodayActivitySnapshot(source: source, dayStart: day.start)
            }
            do {
                let items = try await Self.fetchToday(source: source, day: day, client: client)
                guard !Task.isCancelled else { return }
                guard current(for: source)?.dayStart == day.start else { continue }
                let updated = TodayActivitySnapshot(source: source, dayStart: day.start, items: items)
                if snapshot != updated { snapshot = updated }
            } catch {
                guard !Task.isCancelled else { return }
                if let current = current(for: source), current.dayStart == day.start, !current.refreshFailed {
                    snapshot?.refreshFailed = true
                }
            }
        }
    }

    private static func fetchToday(
        source: TodayActivitySource, day: DateInterval, client: APIClient
    ) async throws -> [TodayActivityItem] {
        let pageSize = 12
        var page = 1
        var items: [TodayActivityItem] = []
        var seen = Set<Int>()
        while items.count < 2 {
            try Task.checkCancellation()
            let posts = try await source.fetchPage(page, limit: pageSize, client: client)
            let newPosts = posts.filter { seen.insert($0.id).inserted }
            let dated = newPosts.compactMap { post -> TodayActivityItem? in
                guard let publishedAt = post.articlePostAt.flatMap(TodayBriefDate.parseTimestamp) else { return nil }
                return TodayActivityItem(post: post, publishedAt: publishedAt)
            }
            items.append(contentsOf: dated.filter {
                $0.publishedAt >= day.start && $0.publishedAt < day.end && $0.publishedAt <= .now
                    && TodayActivitySource(post: $0.post) == source && !$0.post.isXRetweetWrapper
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
                        Text(item.summary)
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
