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
        var projection = await Task.detached(priority: .userInitiated) {
            var projection = TodayBriefProjection(edition: snapshot.edition)
            projection.addSources(snapshot.sourcePosts)
            return projection
        }.value
        await projection.prepareImages()
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
                try await prepareEdition(edition, baseURL: baseURL, retryImages: force)
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

    private func prepareEdition(_ edition: TodayPublishedEdition, baseURL: URL, retryImages: Bool) async throws {
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
        guard current == nil || !fetchedPosts.isEmpty || retryImages else { return }

        if !fetchedPosts.isEmpty {
            projection = await Task.detached(priority: .userInitiated) { [projection] in
                var prepared = projection
                prepared.addSources(fetchedPosts)
                return prepared
            }.value
        }
        await projection.prepareImages()
        try Task.checkCancellation()
        let sourcePostsChanged = current == nil || !fetchedPosts.isEmpty
        if sourcePostsChanged || current?.preparedImageCount != projection.preparedImageCount {
            displayedEdition = edition
            brief = projection
        }

        if usesPublishedSnapshots, sourcePostsChanged {
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
    return decoded.posts.filter { $0.contentZH != nil || $0.content != nil || $0.text != nil || $0.summary != nil }
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
            GeometryReader { viewport in
                pageContent(viewport: viewport.size)
            }
            .background(TodayBriefStyle.surface)
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

    private func pageContent(viewport: CGSize) -> some View {
        let readingHeight = max(0, viewport.height - bottomChromeHeight - 8)
        let topInset = store.brief == nil ? 0 : min(32, max(0, (readingHeight - 480) / 6))
        return ScrollView {
            VStack(spacing: TodayBriefStyle.toolsSpacing) {
                toolsButton
                if let brief = store.brief {
                    TodayBriefOverviewView(
                        brief: brief,
                        viewport: CGSize(width: viewport.width, height: readingHeight - topInset),
                        isRefreshing: store.isLoading,
                        retryReport: { await store.loadReport(force: true) }
                    )
                    .id(brief.date)
                } else {
                    emptyReportView
                }
            }
            .padding(.top, topInset)
            .frame(maxWidth: .infinity, minHeight: readingHeight, alignment: .top)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .padding(.bottom, bottomChromeHeight + 8)
    }

    private var toolsButton: some View {
        TodayToolsButton(
            waitingForRechargeReturn: $waitingForRechargeReturn,
            balance: store.balance,
            dailyCosts: store.dailyCosts,
            isLoading: store.isLoadingBalance,
            needsRetry: store.balanceNeedsRetry,
            retry: { await store.loadBalance(force: true) },
            editionNotice: editionNotice,
            isRefreshingReport: store.isLoading,
            retryReport: { await store.loadReport(force: true) }
        )
        .frame(maxWidth: TodayBriefStyle.maximumCardWidth, alignment: .trailing)
        .frame(height: TodayBriefStyle.toolsRowHeight)
        .padding(.horizontal, TodayBriefStyle.horizontalInset)
    }

    private func loadReport() async {
        let refresh = waitingForRechargeReturn
        waitingForRechargeReturn = false
        await store.load(force: refresh)
    }

    private var emptyReportView: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text(reportStatusTitle)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                if let reason = reportStatusReason, !reason.isEmpty {
                    Text(reason).font(.subheadline).foregroundStyle(.secondary).lineSpacing(3)
                }
                if let report = store.report {
                    TodayBriefStyle.rule.frame(height: 1)
                    HStack(spacing: 24) {
                        reportMetric(report.postCount, "条动态")
                        reportMetric(report.sourceCount, "个信息源")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
        .padding(.horizontal, TodayBriefStyle.horizontalInset)
        .padding(.vertical, 18)
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
            return "生成暂时无法继续。"
        }
        return nil
    }

    private var cachedEditionStatus: String? {
        guard let report = store.report else { return nil }
        if report.admission?.reason_codes.contains("edition_cost_limit") == true,
           report.admission?.state == "paused" {
            return "本期生成已达预算上限，正在查看上期日报"
        }
        return "\(reportStatusTitle)，正在查看上期日报"
    }

    private var editionNotice: TodayEditionNotice? {
        guard let brief = store.brief else { return nil }
        let error = store.errorMessage.map { "\($0)。正在查看上次加载的日报。" }
        let message = error ?? (store.isShowingCachedEdition ? cachedEditionStatus : nil)
        guard message != nil || brief.isPartial else { return nil }
        return TodayEditionNotice(message: message, isPartial: brief.isPartial, canRetry: error != nil)
    }
}

func todayWorldSourceAvatarURL(_ key: String) -> URL? {
    let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
    return MediaURL.image("/api/ios/v1/today-world/avatars/\(encoded)?v=2")
}

// Reading content stays tied to explicit report references; facts are not inferred to be separate events.
struct TodayReadingEvent: Identifiable, Sendable {
    let id: String
    let text: String
    let sourceLabel: String
    let companySystemKey: String?
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
        let systemKeys = Set(item.systemKeys)
        return Self(id: item.id, text: item.text,
                    sourceLabel: unique(related.map { todayBriefSystemName($0.systemName) }).joined(separator: " · "),
                    companySystemKey: systemKeys.count == 1 ? systemKeys.first : nil,
                    postIDs: sourceIDs.sorted())
    }
}

struct TodaySourcePresentation: Identifiable, Sendable {
    let post: Post
    let originalText: String
    let chineseText: String?
    let reply: String?
    let quote: XQuotedPost?
    let author: String
    let avatarURL: URL?
    let quoteAvatarURL: URL?
    let time: String?
    let hasMedia: Bool
    let previewURLs: [URL]

    var id: Int { post.id }

    init(post: Post) {
        self.post = post
        originalText = XPostTextFormatter.simplifiedChinese(post.xStoredOriginalContent)
        chineseText = post.hasTranslation
            ? LocalTranslatedText.chineseText(post.displayContent).map(XPostTextFormatter.simplifiedChinese)
            : nil
        reply = post.xReplyContext?.displayText
        let sourceQuote = post.xQuotedPost
        quote = sourceQuote
        author = post.authorName
        avatarURL = post.avatarURL
        quoteAvatarURL = sourceQuote?.author?.profileImageURL.flatMap(URL.init(string:))
        time = post.formattedTime
        hasMedia = post.previewURL != nil || !post.videoURLs.isEmpty
        let mainPreviews = if !post.videoURLs.isEmpty {
            [post.xFeedVideoPoster].compactMap { $0 }
        } else {
            post.feedImageURLs + [post.previewURL].compactMap { $0 }
        }
        let quotedPreviews = sourceQuote?.media?.compactMap { media in
            media.playbackURL == nil ? media.feedDisplayURL : media.previewURL
        } ?? []
        previewURLs = mainPreviews + quotedPreviews
    }
}

struct TodaySourceAuthorView: View {
    let source: TodaySourcePresentation
    let image: UIImage?

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(url: nil, name: source.author, size: 30, loadingPolicy: .prepared(image))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(source.author).font(.subheadline.weight(.semibold))
                if let time = source.time {
                    Text(time).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TodayInlineSourceView: View {
    let source: TodaySourcePresentation
    let quoteAvatar: UIImage?
    let width: CGFloat
    let allowsLocalTranslation: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !source.originalText.isEmpty || source.chineseText != nil {
                Group {
                    if let chineseText = source.chineseText {
                        Text(chineseText)
                    } else {
                        LocalTranslatedText(
                            original: source.originalText,
                            detail: true,
                            enabled: allowsLocalTranslation && source.post.sourceName == "X"
                        )
                    }
                }
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
            }
            if let reply = source.reply, !reply.isEmpty {
                Text("回复：\(reply)")
                    .font(.subheadline).lineSpacing(4).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if source.hasMedia {
                XFeedMediaView(post: source.post, timelineWidth: width, showsQuotedPost: false)
            }
            if let quote = source.quote {
                XFeedQuotedPostCard(
                    quote: quote,
                    availableWidth: width,
                    isDetail: true,
                    avatarLoadingPolicy: .prepared(quoteAvatar)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-source-\(source.id)")
    }
}
