import SwiftUI

struct TodayPublishedEdition: Codable, Sendable, Equatable {
    let date: String
    let postCount: Int
    let sourceCount: Int
    let report: TodayWorldFinalReport

    init?(payload: TodayWorldYesterdayReportPayload) {
        guard let report = payload.report.final, report.status == "succeeded", !report.systems.isEmpty else { return nil }
        date = payload.date
        postCount = payload.postCount
        sourceCount = payload.sourceCount
        self.report = report
    }
}

private struct TodayEditionSnapshot: Codable, Sendable {
    let edition: TodayPublishedEdition
    let sourcePosts: [Int: Post]
}

@MainActor
final class TodayWorldStore: ObservableObject {
    @Published private(set) var report: TodayWorldYesterdayReportPayload?
    @Published private(set) var balance: AliyunAccountBalance?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var brief: TodayBriefProjection?
    @Published private(set) var isShowingCachedEdition = false
    @Published private(set) var dailyCosts: DisplaySnapshotCache.Entry<AIUsageDailyCosts>?
    @Published private(set) var balanceNeedsRetry = false
    @Published private var balanceRequest: (task: Task<Void, Never>, forced: Bool)?
    var isLoadingBalance: Bool { balanceRequest != nil }
    private var balanceKey: String?
    private var checkedAt: Date?
    private var displayedEdition: TodayPublishedEdition?
    private let usesCostSnapshots: Bool
    private let usesPublishedSnapshots: Bool
    private let fetchReport: () async throws -> TodayWorldYesterdayReportPayload
    private let fetchBalance: (Bool) async throws -> AliyunAccountBalance

    init(fetchBalance: ((Bool) async throws -> AliyunAccountBalance)? = nil,
         fetchReport: (() async throws -> TodayWorldYesterdayReportPayload)? = nil) {
        let networkBalance = fetchBalance ?? { refresh in
            try await APIClient(baseURL: ServerConfiguration.currentURL).fetchAliyunBalance(refresh: refresh)
        }
        #if DEBUG
        if let fixture = ProcessInfo.processInfo.environment["TODAY_BALANCE_TEST_RESPONSE"] {
            usesCostSnapshots = false
            self.fetchBalance = { _ in try JSONDecoder().decode(AliyunAccountBalance.self, from: Data(fixture.utf8)) }
        } else {
            usesCostSnapshots = fetchBalance == nil
            self.fetchBalance = networkBalance
        }
        if let fixture = ProcessInfo.processInfo.environment["TODAY_REPORT_TEST_RESPONSE"] {
            usesPublishedSnapshots = false
            self.fetchReport = { try JSONDecoder().decode(TodayWorldYesterdayReportPayload.self, from: Data(fixture.utf8)) }
        } else if ProcessInfo.processInfo.environment["TODAY_REPORT_TEST_OFFLINE"] == "1" {
            usesPublishedSnapshots = false
            self.fetchReport = { throw URLError(.notConnectedToInternet) }
        } else {
            usesPublishedSnapshots = fetchReport == nil
            self.fetchReport = fetchReport ?? Self.fetchCurrentReport
        }
        #else
        usesCostSnapshots = fetchBalance == nil
        self.fetchBalance = networkBalance
        usesPublishedSnapshots = fetchReport == nil
        self.fetchReport = fetchReport ?? Self.fetchCurrentReport
        #endif
        restoreBalanceIfNeeded()
    }

    private func restoreEdition(key: String) async {
        guard usesPublishedSnapshots, brief == nil,
              let saved = await DisplaySnapshotCache.editions.load(
                TodayEditionSnapshot.self, key: key, maximumAge: 48 * 60 * 60
              ),
              (Self.billingDate(daysAgo: 2)...Self.billingDate(daysAgo: 1)).contains(saved.value.edition.date) else { return }
        let snapshot = saved.value
        let projection = await Task.detached(priority: .userInitiated) {
            var projection = TodayBriefProjection(edition: snapshot.edition)
            projection.addSources(snapshot.sourcePosts)
            return projection
        }.value
        guard !Task.isCancelled else { return }
        displayedEdition = snapshot.edition
        brief = projection
        isShowingCachedEdition = true
    }

    private static func fetchCurrentReport() async throws -> TodayWorldYesterdayReportPayload {
        try await APIClient(baseURL: ServerConfiguration.currentURL).fetchTodayWorldYesterdayReport()
    }

    func load(force: Bool = false) async {
        async let balanceRequest: Void = loadBalance(force: force)
        await loadReport(force: force)
        await balanceRequest
    }

    func loadReport(force: Bool = false) async {
        let isStale = checkedAt.map { Date().timeIntervalSince($0) >= 60 } ?? true
        guard !Task.isCancelled, !isLoading, force || report == nil || isStale else { return }
        isLoading = true
        if errorMessage != nil { errorMessage = nil }
        defer { isLoading = false }
        let baseURL = ServerConfiguration.currentURL
        let snapshotKey = baseURL.absoluteString

        do {
            async let networkReport = fetchReport()
            await restoreEdition(key: snapshotKey)
            let loadedReport = try await networkReport
            guard !Task.isCancelled else { return }
            if let edition = TodayPublishedEdition(payload: loadedReport) {
                try await prepareEdition(edition, baseURL: baseURL)
                if isShowingCachedEdition { isShowingCachedEdition = false }
            } else if let brief, brief.date < loadedReport.date {
                if !isShowingCachedEdition { isShowingCachedEdition = true }
            } else {
                displayedEdition = nil
                if brief != nil { brief = nil }
                if isShowingCachedEdition { isShowingCachedEdition = false }
            }
            if loadedReport != report { report = loadedReport }
            checkedAt = Date()
            if usesPublishedSnapshots, displayedEdition == nil {
                await DisplaySnapshotCache.editions.remove(key: snapshotKey)
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
            errorMessage = NetworkErrorPresentation.message(for: error)
            checkedAt = Date()
        }
    }

    private func prepareEdition(_ edition: TodayPublishedEdition, baseURL: URL) async throws {
        let current = displayedEdition == edition ? brief : nil
        var projection: TodayBriefProjection
        if let current {
            projection = current
        } else {
            projection = await Task.detached(priority: .userInitiated) {
                TodayBriefProjection(edition: edition)
            }.value
        }
        try Task.checkCancellation()

        let missingIDs = projection.sourceIDs.filter { projection.sources[$0] == nil }
        let fetchedPosts = try await fetchTodayEditionSources(ids: missingIDs, baseURL: baseURL)
        try Task.checkCancellation()
        guard current == nil || !fetchedPosts.isEmpty else { return }

        projection = await Task.detached(priority: .userInitiated) { [projection] in
            var prepared = projection
            prepared.addSources(fetchedPosts)
            return prepared
        }.value
        try Task.checkCancellation()
        displayedEdition = edition
        brief = projection

        if usesPublishedSnapshots {
            let snapshot = TodayEditionSnapshot(edition: edition, sourcePosts: projection.sources.mapValues(\.post))
            await DisplaySnapshotCache.editions.save(snapshot, key: baseURL.absoluteString, at: Date())
        }
    }

    private static func billingDate(daysAgo: Int = 0) -> String {
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    @discardableResult
    private func restoreBalanceIfNeeded() -> String {
        let date = Self.billingDate()
        let key = ServerConfiguration.currentURL.absoluteString + "|" + date
        guard balanceKey != key else { return key }
        balanceRequest?.task.cancel()
        balanceRequest = nil
        balanceKey = key
        let saved = usesCostSnapshots
            ? DisplaySnapshotCache.billing.read(AliyunAccountBalance.self, key: key, maximumAge: 86400)
            : nil
        if let saved, saved.value.usage.date == date,
           saved.value.usage.yesterdayDate == Self.billingDate(daysAgo: 1) {
            balance = saved.value
            dailyCosts = .init(value: saved.value.usage, savedAt: saved.savedAt)
            balanceNeedsRetry = saved.value.hasMissingFigures
        } else {
            balance = nil
            dailyCosts = nil
            balanceNeedsRetry = false
        }
        return key
    }

    func loadBalance(force: Bool = false) async {
        let key = restoreBalanceIfNeeded()
        if let request = balanceRequest {
            await request.task.value
            if force && !request.forced { await loadBalance(force: true) }
            return
        }
        if !force, !balanceNeedsRetry, let savedAt = dailyCosts?.savedAt, balance != nil,
           Date().timeIntervalSince(savedAt) < 60 { return }
        let task = Task { await queryBalance(key: key, force: force) }
        balanceRequest = (task, force)
        await task.value
    }

    private func queryBalance(key: String, force: Bool) async {
        defer { if balanceKey == key && !Task.isCancelled { balanceRequest = nil } }
        do {
            let loaded = try await fetchBalance(force)
            guard !Task.isCancelled else { return }
            guard loaded.usage.date == Self.billingDate(),
                  loaded.usage.yesterdayDate == Self.billingDate(daysAgo: 1) else { throw APIError.invalidResponse }
            let receivedAt = Date()
            balance = loaded
            dailyCosts = .init(value: loaded.usage, savedAt: receivedAt)
            balanceNeedsRetry = loaded.hasMissingFigures
            if usesCostSnapshots { await DisplaySnapshotCache.billing.save(loaded, key: key, at: receivedAt) }
        } catch {
            guard !Task.isCancelled else { return }
            if dailyCosts?.value.date != Self.billingDate() {
                dailyCosts = nil
                balance = nil
            }
            balanceNeedsRetry = true
        }
    }

}

private func fetchTodayEditionSources(ids: [Int], baseURL: URL) async throws -> [Int: Post] {
    let batchSize = 50
    var loaded: [Int: Post] = [:]
    for start in stride(from: 0, to: ids.count, by: batchSize) {
        try Task.checkCancellation()
        let batch = ids[start..<min(start + batchSize, ids.count)]
        let requestedIDs = Set(batch)
        do {
            let posts = try await fetchTodayWorldPostBatch(ids: batch, baseURL: baseURL)
            for post in posts where requestedIDs.contains(post.id) {
                loaded[post.id] = post
            }
        } catch {
            try Task.checkCancellation()
            // Keep successful batches and let the reader retry the missing sources.
        }
    }
    return loaded
}

private struct TodayWorldPostBatchResponse: Decodable {
    let success: Bool
    let posts: [Post]
}

private func fetchTodayWorldPostBatch(ids: ArraySlice<Int>, baseURL: URL) async throws -> [Post] {
    var components = URLComponents(
        url: baseURL.appending(path: "api/ios/v1/post/batch"),
        resolvingAgainstBaseURL: false
    )
    components?.queryItems = [
        .init(name: "ids", value: ids.map(String.init).joined(separator: ",")),
        .init(name: "full", value: "1")
    ]
    guard let url = components?.url else { throw APIError.invalidURL }

    let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 8)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else { throw APIError.httpStatus(http.statusCode) }
    let decoded = try JSONDecoder().decode(TodayWorldPostBatchResponse.self, from: data)
    guard decoded.success else { throw APIError.invalidResponse }
    return decoded.posts.filter { $0.content != nil || $0.text != nil || $0.summary != nil }
}

struct TodayWorldView: View {
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @Environment(\.rootBottomChromeHeight) private var bottomChromeHeight
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: TodayWorldStore
    @State private var waitingForRechargeReturn = false

    init(store: TodayWorldStore) {
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TodayHeaderView(
                    waitingForRechargeReturn: $waitingForRechargeReturn,
                    balance: store.balance,
                    dailyCosts: store.dailyCosts, isLoading: store.isLoadingBalance,
                    needsRetry: store.balanceNeedsRetry, retry: { await store.loadBalance(force: true) }
                )
                Group {
                    if let brief = store.brief {
                        TodayBriefOverviewView(
                            brief: brief,
                            cachedEditionMessage: store.isShowingCachedEdition ? cachedEditionStatus : nil,
                            reportError: store.errorMessage,
                            isRefreshing: store.isLoading,
                            retryReport: { await store.loadReport(force: true) }
                        )
                        .id(brief.date)
                    } else {
                        emptyReportView
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await loadReport()
        }
        .task(id: rootTabIsActive && scenePhase == .active) {
            guard rootTabIsActive, scenePhase == .active else { return }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            while let day = calendar.dateInterval(of: .day, for: Date()) {
                do { try await Task.sleep(for: .seconds(max(0, day.end.timeIntervalSinceNow))) }
                catch { return }
                await store.loadBalance()
            }
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

    private var emptyReportView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("本期日报", systemImage: "newspaper")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.82))
                    Text(reportStatusTitle)
                        .font(.system(.title, design: .serif, weight: .bold))
                    if let reason = reportStatusReason, !reason.isEmpty {
                        Text(reason).font(.subheadline).lineSpacing(3)
                    }
                    if let report = store.report {
                        Divider().overlay(.white.opacity(0.3))
                        HStack(spacing: 24) {
                            reportMetric(report.postCount, "条动态")
                            reportMetric(report.sourceCount, "个信息源")
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(TodayBriefStyle.ink, in: RoundedRectangle(cornerRadius: 18))

                if let sections = store.report?.report.sections, !sections.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("栏目收录").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                            .padding(.bottom, 6)
                        ForEach(sections, id: \.section_key) { section in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(section.section_name).font(.headline)
                                    Spacer()
                                    Text("\(section.postCount) 条").font(.subheadline.monospacedDigit())
                                        .foregroundStyle(TodayBriefStyle.accent)
                                }
                                Text(section.groups.map(\.group_name).joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 12)
                            Divider()
                        }
                    }
                }
                Button {
                    Task { await store.load(force: true) }
                } label: {
                    Label(store.isLoading ? "刷新中…" : "刷新日报", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }
                .disabled(store.isLoading)
                .tint(TodayBriefStyle.accent)
            }
            .padding(.horizontal, 20).padding(.top, 6)
            .padding(.bottom, bottomChromeHeight + 12)
        }
        .accessibilityIdentifier("today-status-scroll")
    }

    private func reportMetric(_ count: Int, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(count)").font(.title2.monospacedDigit().weight(.semibold))
            Text(unit).font(.caption)
        }
        .accessibilityElement(children: .combine)
    }

    private var reportStatusTitle: String {
        if store.errorMessage != nil { return "日报加载失败" }
        guard let report = store.report else { return store.isLoading ? "正在加载日报" : "暂无日报" }
        if report.admission?.state == "paused" { return "生成已暂停" }
        if report.report.final?.status == "failed" { return "日报生成失败" }
        if report.isGenerating { return "正在生成日报" }
        return "本期日报尚未发布"
    }

    private var reportStatusReason: String? {
        if let error = store.errorMessage { return error }
        if let admission = store.report?.admission, admission.state == "paused" {
            if admission.reason_codes.contains("edition_cost_limit") {
                return "预计生成费用超出本期预算。"
            }
            return admission.reason
        }
        return store.report?.report.final?.error
    }

    private var cachedEditionStatus: String {
        guard let report = store.report else { return "已显示上次日报" }
        var parts = ["已显示上次日报", reportStatusTitle]
        if let reason = reportStatusReason, !reason.isEmpty { parts.append(reason) }
        if report.admission?.state == "paused" {
            parts.append("本期已收录 \(report.postCount) 条动态")
        }
        return parts.joined(separator: " · ")
    }
}

func todayWorldSourceAvatarURL(_ key: String) -> URL? {
    let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
    return MediaURL.image("/api/ios/v1/today-world/avatars/\(encoded)?v=2")
}

// Reading content stays tied to explicit report references; facts are not inferred to be separate events.
struct TodayReadingEvent: Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let sourceLabel: String
    let details: [String]
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

    static func highlight(_ item: TodayWorldFinalReportOverviewItem, systems: [TodayWorldFinalReportSystem]) -> Self {
        let itemPostIDs = Set(item.postIDs)
        let related = systems.filter {
            item.systemKeys.contains($0.systemKey) || !itemPostIDs.isDisjoint(with: $0.postIDs)
        }
        let ids = item.postIDs.isEmpty ? related.flatMap(\.postIDs) : item.postIDs
        let sourceIDs = Set(ids.filter { $0 > 0 })
        let title = item.title.flatMap { $0.isEmpty ? nil : $0 } ?? item.text
        let summary = additionalDetails([item.context, item.text].compactMap { $0 }, excluding: [title]).joined(separator: "\n")
        let facts = related.flatMap(\.facts).filter {
            !$0.postIDs.isEmpty && Set($0.postIDs).isSubset(of: sourceIDs)
        }
        return Self(id: item.id, title: title, summary: summary,
                    sourceLabel: unique(related.map(\.systemName)).joined(separator: " · "),
                    details: additionalDetails(facts.map(\.text), excluding: [title, summary]),
                    postIDs: sourceIDs.sorted())
    }
}

struct TodaySourcePresentation: Identifiable, Sendable {
    let post: Post
    let text: String
    let reply: String?
    let quote: String?
    let quoteAuthor: String?
    let author: String
    let avatarURL: URL?
    let time: String?
    let hasMedia: Bool
    let untranslatedTexts: [String]

    var id: Int { post.id }

    init(post: Post) {
        self.post = post
        text = post.hasTranslation ? post.displayContent : post.xStoredOriginalContent
        reply = post.meta?.replyContext?.displayText
        quote = post.meta?.quotedTweet?.displayText
        quoteAuthor = post.meta?.quotedTweet?.author?.name
        author = post.authorName
        avatarURL = post.avatarURL
        time = post.formattedTime
        hasMedia = post.previewURL != nil || !post.videoURLs.isEmpty
        untranslatedTexts = TodayReadingEvent.unique([text, reply, quote].compactMap { $0 })
            .filter { !TodayChinesePreparation.isChinese($0) }
    }
}

private enum TodayChinesePreparation {
    static func isChinese(_ text: String) -> Bool {
        text.range(of: "[\\p{Han}]", options: .regularExpression) != nil
            && !XPostTextFormatter.containsUntranslatedEnglishPassage(text)
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

struct TodayInlineSourceView: View {
    let source: TodaySourcePresentation
    @State private var translations: [String: String] = [:]
    @State private var translating = false
    @State private var translationFailed = false

    private var textsNeedingTranslation: [String] {
        source.untranslatedTexts.filter { translations[$0] == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                AvatarView(url: source.avatarURL, name: source.author, size: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.author).font(.subheadline.weight(.semibold))
                    if let time = source.time {
                        Text(time).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !source.text.isEmpty {
                Text(translations[source.text] ?? source.text)
                    .font(.subheadline).lineSpacing(4).textSelection(.enabled)
            }
            if let reply = source.reply {
                Text("回复：\(translations[reply] ?? reply)")
                    .font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let original = source.quote {
                VStack(alignment: .leading, spacing: 6) {
                    Text(source.quoteAuthor ?? "引用内容").font(.caption.weight(.semibold))
                    Text(translations[original] ?? original).font(.subheadline).textSelection(.enabled)
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(TodayBriefStyle.accent.opacity(0.25)).frame(width: 2) }
            }
            if source.hasMedia { XFeedMediaView(post: source.post) }
            if translating {
                ProgressView("正在翻译").font(.caption)
            } else if !textsNeedingTranslation.isEmpty {
                Button(translationFailed ? "翻译暂不可用 · 重试" : "译成中文") {
                    Task { await prepareChinese() }
                }
                .font(.subheadline)
                .foregroundStyle(TodayBriefStyle.accent)
                .frame(minHeight: 44)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-source-\(source.id)")
    }

    @MainActor private func prepareChinese() async {
        guard !translating else { return }
        translationFailed = false
        translating = true
        defer { translating = false }
        let baseURL = ServerConfiguration.currentURL
        for text in textsNeedingTranslation {
            guard !Task.isCancelled else { return }
            do {
                let translated = try await TodayChineseTextCache.shared.text(
                    text, tweetID: text == source.text ? source.post.xTweetID : nil, baseURL: baseURL
                )
                guard !Task.isCancelled else { return }
                translations[text] = translated
            } catch {
                if !Task.isCancelled { translationFailed = true }
            }
        }
    }
}
