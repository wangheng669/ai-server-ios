import SwiftUI

@MainActor
final class TodayWorldStore: ObservableObject {
    @Published private(set) var report: TodayWorldYesterdayReportPayload?
    @Published private(set) var balance: AliyunAccountBalance?
    @Published private(set) var isLoading = false
    @Published private(set) var checkedAt: Date?
    private(set) var brief: TodayBriefProjection?
    private let fetchReport: () async throws -> TodayWorldYesterdayReportPayload
    private let fetchBalance: (Bool) async throws -> AliyunAccountBalance

    init(fetchBalance: @escaping (Bool) async throws -> AliyunAccountBalance = { refresh in
        try await APIClient(baseURL: ServerConfiguration.currentURL).fetchAliyunBalance(refresh: refresh)
    }, fetchReport: @escaping () async throws -> TodayWorldYesterdayReportPayload = {
        try await APIClient(baseURL: ServerConfiguration.currentURL).fetchTodayWorldYesterdayReport()
    }) {
        #if DEBUG
        if let fixture = ProcessInfo.processInfo.environment["TODAY_BALANCE_TEST_RESPONSE"] {
            self.fetchBalance = { _ in try JSONDecoder().decode(AliyunAccountBalance.self, from: Data(fixture.utf8)) }
        } else {
            self.fetchBalance = fetchBalance
        }
        if let fixture = ProcessInfo.processInfo.environment["TODAY_REPORT_TEST_RESPONSE"] {
            self.fetchReport = { try JSONDecoder().decode(TodayWorldYesterdayReportPayload.self, from: Data(fixture.utf8)) }
            return
        }
        if ProcessInfo.processInfo.environment["TODAY_REPORT_TEST_OFFLINE"] == "1" {
            self.fetchReport = { throw URLError(.notConnectedToInternet) }
            return
        }
        #else
        self.fetchBalance = fetchBalance
        #endif
        self.fetchReport = fetchReport
    }

    func load(force: Bool = false) async {
        let isStale = checkedAt.map { Date().timeIntervalSince($0) >= 60 } ?? true
        guard !isLoading, force || report == nil || isStale else { return }
        isLoading = true
        defer { isLoading = false }
        async let balanceRequest: Void = loadBalance(force: force)

        do {
            let loadedReport = try await fetchReport()
            guard !Task.isCancelled else { return }
            brief = TodayBriefProjection(payload: loadedReport)
            report = loadedReport
            checkedAt = Date()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
            checkedAt = Date()
        }
        await balanceRequest
    }

    private func loadBalance(force: Bool) async {
        do {
            let loadedBalance = try await fetchBalance(force)
            guard !Task.isCancelled else { return }
            balance = loadedBalance
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
            balance = nil
        }
    }

}

private actor TodayWorldPostMemoryCache {
    static let shared = TodayWorldPostMemoryCache()

    private struct Entry {
        let post: Post
        let loadedAt: Date
    }

    private let lifetime: TimeInterval = 6 * 60 * 60
    private var entries: [String: Entry] = [:]

    func cachedPosts(ids: [Int], baseURL: URL) -> [Post] {
        discardExpiredEntries()
        return ids.compactMap { entries[key(id: $0, baseURL: baseURL)]?.post }
    }

    func store(posts: [Post], baseURL: URL) {
        let loadedAt = Date()
        for post in posts {
            entries[key(id: post.id, baseURL: baseURL)] = Entry(post: post, loadedAt: loadedAt)
        }
    }

    private func key(id: Int, baseURL: URL) -> String {
        "\(baseURL.absoluteString)|\(id)"
    }

    private func discardExpiredEntries() {
        let cutoff = Date().addingTimeInterval(-lifetime)
        entries = entries.filter { $0.value.loadedAt >= cutoff }
    }
}

private struct TodayWorldPostBatchResponse: Decodable {
    let success: Bool
    let posts: [Post]
}

private func fetchTodayWorldPostBatch(ids: [Int], baseURL: URL) async throws -> [Post] {
    var seen = Set<Int>()
    let requestedIDs = ids.filter { $0 > 0 && seen.insert($0).inserted }.prefix(50)
    guard !requestedIDs.isEmpty else { return [] }

    var components = URLComponents(
        url: baseURL.appending(path: "api/ios/v1/post/batch"),
        resolvingAgainstBaseURL: false
    )
    components?.queryItems = [
        .init(name: "ids", value: requestedIDs.map(String.init).joined(separator: ",")),
        .init(name: "full", value: "1")
    ]
    guard let url = components?.url else { throw APIError.invalidURL }

    let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else { throw APIError.httpStatus(http.statusCode) }
    let decoded = try JSONDecoder().decode(TodayWorldPostBatchResponse.self, from: data)
    guard decoded.success else { throw APIError.invalidResponse }
    guard decoded.posts.allSatisfy({ $0.content != nil || $0.text != nil || $0.summary != nil }) else {
        throw APIError.invalidResponse
    }
    return decoded.posts
}

struct TodayWorldView: View {
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @Environment(\.rootBottomChromeHeight) private var bottomChromeHeight
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: TodayWorldStore
    @State private var selectedSectionKey: String?
    @State private var activeBriefSheet: BriefSheet?
    @State private var waitingForRechargeReturn = false

    init(store: TodayWorldStore) {
        _store = StateObject(wrappedValue: store)
    }

    private enum BriefSheet: Identifiable {
        case highlight(TodayReadingEvent)
        case system(TodayWorldFinalReportSystem, date: String, highlights: [TodayWorldFinalReportOverviewItem])
        var id: String {
            switch self {
            case .highlight(let item): return "highlight-" + item.id
            case .system(let system, _, _): return "system-" + system.id
            }
        }
    }

    private struct PreparationRequest: Equatable {
        let ids: [Int]
        let baseURL: URL
    }

    var body: some View {
        let preparation = PreparationRequest(ids: preparationIDs, baseURL: ServerConfiguration.currentURL)
        NavigationStack {
            VStack(spacing: 0) {
                balanceView
                Group {
                    if let brief = store.brief {
                        reportView(brief)
                    } else {
                        emptyReportView
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $activeBriefSheet) { route in
            TodayDetailSheet(title: "事件详情", detents: [.large]) {
                briefSheet(route)
            }
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await loadReport()
        }
        .task(id: preparation) {
            await TodayChinesePreparation.warm(ids: preparation.ids, baseURL: preparation.baseURL)
        }
        .onChange(of: scenePhase) { _, phase in
            guard rootTabIsActive, phase == .active else { return }
            Task { await loadReport() }
        }
    }

    private func loadReport() async {
        let refresh = waitingForRechargeReturn
        waitingForRechargeReturn = false
        await store.load(force: refresh)
    }

    private var preparationIDs: [Int] {
        guard rootTabIsActive, scenePhase == .active else { return [] }
        return store.brief?.preparationIDs(sectionKey: selectedSectionKey) ?? []
    }

    private func reportView(_ brief: TodayBriefProjection) -> some View {
        TodayBriefOverviewView(
            brief: brief,
            bottomInset: bottomChromeHeight,
            selectedSectionKey: $selectedSectionKey,
            onRefresh: { await store.load(force: true) },
            onOpenHighlight: { item in
                activeBriefSheet = .highlight(TodayReadingEvent.highlight(item, systems: brief.systems, date: brief.date))
            },
            onOpenSystem: { activeBriefSheet = .system($0, date: brief.date, highlights: brief.highlights) }
        )
    }

    private var emptyReportView: some View {
        ScrollView {
            Color.clear.frame(height: 1)
        }
        .refreshable { await store.load(force: true) }
        .accessibilityIdentifier("today-status-scroll")
    }

    @ViewBuilder
    private func briefSheet(_ route: BriefSheet) -> some View {
        switch route {
        case .system(let system, let date, let highlights):
            TodayWorldReportSourcesView(system: system, reportDate: date, highlights: highlights)
        case .highlight(let event):
            TodayEventDetailView(event: event)
        }
    }

    private var balanceView: some View {
        TodayAliyunBalanceView(
            waitingForRechargeReturn: $waitingForRechargeReturn,
            balance: store.balance,
            isLoading: store.isLoading
        )
    }
}

func todayWorldSourceAvatarURL(_ key: String) -> URL? {
    let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
    return MediaURL.image("/api/ios/v1/today-world/avatars/\(encoded)?v=2")
}

// Reading content stays tied to explicit report references; facts are not inferred to be separate events.
struct TodayReadingEvent: Identifiable {
    let id: String
    let title: String
    let summary: String
    let sourceLabel: String
    let date: String
    let details: [String]
    let watchItems: [String]
    let postIDs: [Int]

    static func canonical(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { !$0.isWhitespace }
            .trimmingCharacters(in: CharacterSet(charactersIn: "。！？!?，,；;：:."))
    }

    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter {
            let key = canonical($0)
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    // Exact sentence matching only: never collapse different numbers, negations or qualifications.
    static func additionalDetails(_ values: [String], excluding existing: [String]) -> [String] {
        func sentences(_ text: String) -> [String] {
            var result: [String] = []
            var current = ""
            for character in text {
                current.append(character)
                if "。！？\n".contains(character) {
                    result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    current = ""
                }
            }
            if !current.isEmpty { result.append(current.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return result
        }
        var seen = Set(existing.flatMap { sentences($0).map(canonical) })
        return values.compactMap { value in
            let fresh = sentences(value).filter {
                let key = canonical($0)
                return !key.isEmpty && seen.insert(key).inserted
            }.joined()
            return fresh.isEmpty ? nil : fresh
        }
    }

    static func highlight(_ item: TodayWorldFinalReportOverviewItem, systems: [TodayWorldFinalReportSystem], date: String) -> Self {
        let itemPostIDs = Set(item.postIDs)
        let related = systems.filter {
            item.systemKeys.contains($0.systemKey) || !itemPostIDs.isDisjoint(with: $0.postIDs)
        }
        let ids = item.postIDs.isEmpty ? related.flatMap(\.postIDs) : item.postIDs
        let sourceIDs = Set(ids.filter { $0 > 0 })
        let title = item.title?.isEmpty == false ? item.title! : "事件详情"
        let summary = additionalDetails([item.context, item.text].compactMap { $0 }, excluding: [title]).joined(separator: "\n")
        let facts = related.flatMap(\.facts).filter {
            !$0.postIDs.isEmpty && Set($0.postIDs).isSubset(of: sourceIDs)
        }
        return Self(id: item.id, title: title,
                    summary: summary, sourceLabel: unique(related.map(\.systemName)).joined(separator: " · "),
                    date: date, details: additionalDetails(facts.map(\.text), excluding: [title, summary]),
                    watchItems: [], postIDs: sourceIDs.sorted())
    }

    static func system(_ system: TodayWorldFinalReportSystem, date: String) -> Self {
        let paragraphs = additionalDetails(system.facts.map(\.text), excluding: [system.headline])
        return Self(id: system.id, title: system.headline, summary: paragraphs.first ?? "",
                    sourceLabel: system.systemName, date: date, details: Array(paragraphs.dropFirst()),
                    watchItems: unique([system.watchItem].compactMap { $0 }),
                    postIDs: Array(Set(system.postIDs.filter { $0 > 0 })).sorted())
    }
}

private struct TodayWorldReportSourcesView: View {
    let system: TodayWorldFinalReportSystem
    let reportDate: String
    var highlights: [TodayWorldFinalReportOverviewItem] = []
    @State private var selectedEvent: TodayReadingEvent?

    private var events: [TodayReadingEvent] {
        let matches = highlights.filter {
            $0.systemKeys.contains(system.systemKey) || !Set($0.postIDs).isDisjoint(with: system.postIDs)
        }
        // A company report may contain additional material beyond the selected highlights.
        // Only use a directory when multiple explicit events cover all of its cited sources.
        let covered = Set(matches.flatMap(\.postIDs))
        guard matches.count > 1, Set(system.postIDs).isSubset(of: covered) else {
            return [.system(system, date: reportDate)]
        }
        return matches.map { .highlight($0, systems: [system], date: reportDate) }
    }

    var body: some View {
        Group {
            if events.count == 1, let event = events.first {
                TodayEventDetailView(event: event)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(system.systemName).font(.title2.weight(.semibold))
                        Text(reportDate).font(.subheadline).foregroundStyle(.secondary).padding(.top, 6).padding(.bottom, 20)
                        ForEach(events) { event in
                            Button { selectedEvent = event } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(event.title).font(.headline).foregroundStyle(.primary)
                                        Text(event.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .multilineTextAlignment(.leading).padding(.vertical, 18)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                        if let watch = system.watchItem, !watch.isEmpty {
                            Text("后续关注").font(.headline).padding(.top, 24)
                            Text(watch).foregroundStyle(.secondary).padding(.top, 8)
                        }
                    }.padding(20)
                        .padding(.bottom, 76)
                }
                .todayDetailTitle("公司动态")
            }
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(item: $selectedEvent) { event in
            TodayDetailSheet { TodayEventDetailView(event: event) }
        }
    }
}

private struct TodayEventDetailView: View {
    let event: TodayReadingEvent
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var failedIDs: [Int] = []
    @State private var expandedPostID: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Text([event.sourceLabel, event.date].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(event.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                    if !event.summary.isEmpty {
                        Text(event.summary).font(.body).lineSpacing(5).textSelection(.enabled)
                    }
                }
                if !event.details.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("具体进展").font(.headline)
                        ForEach(event.details, id: \.self) { text in
                            Text(text).lineSpacing(5).textSelection(.enabled)
                        }
                    }
                }
                if !event.watchItems.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("后续关注").font(.headline)
                        ForEach(event.watchItems, id: \.self) { Text($0).foregroundStyle(.secondary).lineSpacing(4) }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    Text("消息来源").font(.headline).padding(.bottom, 12)
                    if event.postIDs.isEmpty {
                        Text("本条简报暂未提供原文引用")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                    }
                    ForEach(posts) { post in
                        TodayInlineSourceView(post: post, isExpanded: expandedPostID == post.id) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedPostID = expandedPostID == post.id ? nil : post.id
                            }
                        }
                        Divider()
                    }
                    if isLoading {
                        ProgressView("正在载入来源").font(.caption).padding(.vertical, 16)
                    }
                    if !failedIDs.isEmpty && !isLoading {
                        HStack {
                            Text(posts.isEmpty ? "暂时无法载入来源" : "部分来源暂未载入").foregroundStyle(.secondary)
                            Spacer()
                            Button("重试") { Task { await loadSources() } }
                        }.font(.subheadline).padding(.vertical, 16)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 76)
        }
        .background(Color(uiColor: .systemBackground))
        .todayDetailTitle("事件详情")
        .task(id: event.id) { await loadSources() }
    }

    @MainActor private func loadSources() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let url = ServerConfiguration.currentURL
        var loaded = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
        let cached = await TodayWorldPostMemoryCache.shared.cachedPosts(ids: event.postIDs, baseURL: url)
        for post in cached { loaded[post.id] = post }
        posts = event.postIDs.compactMap { loaded[$0] }
        let missing = event.postIDs.filter { loaded[$0] == nil }
        for start in stride(from: 0, to: missing.count, by: 50) {
            guard !Task.isCancelled else { return }
            let ids = Array(missing[start..<min(start + 50, missing.count)])
            do {
                let batch = try await fetchTodayWorldPostBatch(ids: ids, baseURL: url)
                await TodayWorldPostMemoryCache.shared.store(posts: batch, baseURL: url)
                for post in batch where event.postIDs.contains(post.id) { loaded[post.id] = post }
                guard !Task.isCancelled else { return }
                posts = event.postIDs.compactMap { loaded[$0] }
            } catch is CancellationError {
                return
            } catch {
                // Keep successful batches visible and let the user retry the missing sources.
            }
        }
        guard !Task.isCancelled else { return }
        posts = event.postIDs.compactMap { loaded[$0] }
        failedIDs = event.postIDs.filter { loaded[$0] == nil }
    }
}

enum TodayChinesePreparation {
    static func prioritizedIDs(highlights: [Int], visible: [Int]) -> [Int] {
        var seen = Set<Int>()
        return Array((highlights + visible).filter { $0 > 0 && seen.insert($0).inserted }.prefix(12))
    }

    static func isChinese(_ text: String) -> Bool {
        text.range(of: "[\\p{Han}]", options: .regularExpression) != nil
            && !XPostTextFormatter.containsUntranslatedEnglishPassage(text)
    }

    static func texts(_ post: Post) -> [String] {
        TodayReadingEvent.unique([
            post.hasTranslation ? post.displayContent : post.xStoredOriginalContent,
            post.meta?.replyContext?.displayText, post.meta?.quotedTweet?.displayText
        ].compactMap { $0 })
    }

    static func warm(ids: [Int], baseURL: URL) async {
        guard !ids.isEmpty, !Task.isCancelled else { return }
        let cached = await TodayWorldPostMemoryCache.shared.cachedPosts(ids: ids, baseURL: baseURL)
        var posts = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        let missing = ids.filter { posts[$0] == nil }
        if !missing.isEmpty, let fetched = try? await fetchTodayWorldPostBatch(ids: missing, baseURL: baseURL) {
            await TodayWorldPostMemoryCache.shared.store(posts: fetched, baseURL: baseURL)
            for post in fetched { posts[post.id] = post }
        }
        for id in ids {
            guard !Task.isCancelled else { return }
            guard let post = posts[id] else { continue }
            let candidates = texts(post)
            for text in candidates where !isChinese(text) {
                guard !Task.isCancelled else { return }
                _ = try? await TodayChineseTextCache.shared.text(text, tweetID: text == candidates.first ? post.xTweetID : nil, baseURL: baseURL)
            }
        }
    }
}

private actor TodayChineseTextCache {
    static let shared = TodayChineseTextCache()
    private var values: [String: String] = [:]
    private var inFlight: [String: Task<String, Error>] = [:]
    private var insertionOrder: [String] = []
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func acquireSlot() async {
        if activeCount < 2 { activeCount += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func releaseSlot() {
        if waiters.isEmpty { activeCount -= 1 } else { waiters.removeFirst().resume() }
    }

    func text(_ source: String, tweetID: String?, baseURL: URL) async throws -> String {
        if TodayChinesePreparation.isChinese(source) { return source }
        let key = baseURL.absoluteString + "|" + (tweetID ?? "") + "|" + source
        if let value = values[key] { return value }
        if let pending = inFlight[key] { return try await pending.value }
        let task = Task<String, Error> {
            await acquireSlot()
            defer { releaseSlot() }
            let result: String
            if let tweetID {
                result = try await APIClient(baseURL: baseURL).fetchXTranslation(tweetID: tweetID).text
            } else {
                result = try await PersonArticleTranslationService.shared.translate(source)
            }
            guard TodayChinesePreparation.isChinese(result) else { throw APIError.invalidResponse }
            return result
        }
        inFlight[key] = task
        do {
            let value = try await task.value
            inFlight[key] = nil
            values[key] = value
            insertionOrder.append(key)
            while insertionOrder.count > 128 { values.removeValue(forKey: insertionOrder.removeFirst()) }
            return value
        } catch {
            inFlight[key] = nil
            throw error
        }
    }
}

private struct TodayInlineSourceView: View {
    let post: Post
    let isExpanded: Bool
    let toggle: () -> Void
    @State private var translations: [String: String] = [:]
    @State private var translating = false
    @State private var translationFailed = false

    private var sourceText: String { post.hasTranslation ? post.displayContent : post.xStoredOriginalContent }
    private func chineseText(_ text: String) -> String? {
        if let translated = translations[text] { return translated }
        return TodayChinesePreparation.isChinese(text) ? text : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 10) {
                    AvatarView(url: post.avatarURL, name: post.authorName, size: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(post.authorName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        if let time = post.formattedTime { Text(time).font(.caption).foregroundStyle(.secondary) }
                        if !isExpanded {
                            Text(chineseText(sourceText) ?? "展开阅读中文内容")
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today-source-\(post.id)")
            .accessibilityValue(isExpanded ? "已展开" : "已收起")
            if isExpanded {
                if let text = chineseText(sourceText) {
                    Text(text).font(.body).lineSpacing(5).textSelection(.enabled)
                }
                if let reply = post.meta?.replyContext?.displayText, let text = chineseText(reply) {
                    Text("回复：\(text)").font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let quote = post.meta?.quotedTweet, let original = quote.displayText, let text = chineseText(original) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(quote.author?.name ?? "引用内容").font(.caption.weight(.semibold))
                        Text(text).font(.subheadline).textSelection(.enabled)
                    }.padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 2) }
                }
                if post.previewURL != nil || !post.videoURLs.isEmpty { XFeedMediaView(post: post) }
                if translating { ProgressView("正在载入中文内容").font(.caption) }
                if translationFailed {
                    Text("部分中文内容暂不可用，请稍后重新展开")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 16)
        .task(id: post.id) { await prepareChinese() }
        .task(id: isExpanded) {
            if isExpanded && translationFailed { await prepareChinese() }
        }
    }

    @MainActor private func prepareChinese() async {
        guard !translating else { return }
        translationFailed = false
        translating = true
        defer { translating = false }
        let baseURL = ServerConfiguration.currentURL
        for text in TodayChinesePreparation.texts(post) where chineseText(text) == nil {
            guard !Task.isCancelled else { return }
            do {
                let translated = try await TodayChineseTextCache.shared.text(
                    text, tweetID: text == sourceText ? post.xTweetID : nil, baseURL: baseURL
                )
                guard !Task.isCancelled else { return }
                translations[text] = translated
            } catch {
                if !Task.isCancelled { translationFailed = true }
            }
        }
    }
}
