import SwiftUI

struct TodayPublishedEdition: Codable, Sendable {
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

@MainActor
final class TodayWorldStore: ObservableObject {
    @Published private(set) var report: TodayWorldYesterdayReportPayload?
    @Published private(set) var balance: AliyunAccountBalance?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var checkedAt: Date?
    @Published private(set) var brief: TodayBriefProjection?
    @Published private(set) var isShowingCachedEdition = false
    @Published private(set) var dailyCosts: DisplaySnapshotCache.Entry<AIUsageDailyCosts>?
    @Published private(set) var balanceNeedsRetry = false
    @Published private var balanceRequest: (task: Task<Void, Never>, forced: Bool)?
    var isLoadingBalance: Bool { balanceRequest != nil }
    private var balanceKey: String?
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
        restoreEdition()
    }

    private func restoreEdition() {
        guard usesPublishedSnapshots,
              let saved = DisplaySnapshotCache.editions.read(
                TodayPublishedEdition.self, key: ServerConfiguration.currentURL.absoluteString, maximumAge: 48 * 60 * 60
              ),
              (Self.billingDate(daysAgo: 2)...Self.billingDate(daysAgo: 1)).contains(saved.value.date),
              let cachedBrief = TodayBriefProjection(edition: saved.value) else { return }
        brief = cachedBrief
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
        errorMessage = nil
        defer { isLoading = false }
        let snapshotKey = ServerConfiguration.currentURL.absoluteString

        do {
            let loadedReport = try await fetchReport()
            guard !Task.isCancelled else { return }
            let edition = TodayPublishedEdition(payload: loadedReport)
            if let edition {
                if loadedReport != report || isShowingCachedEdition {
                    brief = TodayBriefProjection(edition: edition)
                }
                isShowingCachedEdition = false
            } else if let brief, brief.date < loadedReport.date {
                isShowingCachedEdition = true
            } else {
                brief = nil
                isShowingCachedEdition = false
            }
            if loadedReport != report { report = loadedReport }
            checkedAt = Date()
            if usesPublishedSnapshots {
                if let edition {
                    await DisplaySnapshotCache.editions.save(edition, key: snapshotKey, at: Date())
                } else if !isShowingCachedEdition {
                    await DisplaySnapshotCache.editions.remove(key: snapshotKey)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
            errorMessage = NetworkErrorPresentation.message(for: error)
            checkedAt = Date()
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

private actor TodayWorldPostCache {
    static let shared = TodayWorldPostCache()

    private struct Entry {
        let post: Post
        let loadedAt: Date
    }

    private let lifetime: TimeInterval = 6 * 60 * 60
    private var entries: [String: Entry] = [:]

    func cachedPosts(ids: [Int], baseURL: URL) async -> [Post] {
        discardExpiredEntries()
        for id in ids where entries[key(id: id, baseURL: baseURL)] == nil {
            let cacheKey = key(id: id, baseURL: baseURL)
            if let saved = await DisplaySnapshotCache.pages.load(Post.self, key: cacheKey, maximumAge: lifetime),
               entries[cacheKey] == nil {
                entries[cacheKey] = Entry(post: saved.value, loadedAt: saved.savedAt)
            }
        }
        return ids.compactMap { entries[key(id: $0, baseURL: baseURL)]?.post }
    }

    func store(posts: [Post], baseURL: URL) async {
        let loadedAt = Date()
        for post in posts {
            let cacheKey = key(id: post.id, baseURL: baseURL)
            entries[cacheKey] = Entry(post: post, loadedAt: loadedAt)
            await DisplaySnapshotCache.pages.save(post, key: cacheKey, at: loadedAt)
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
                TodayHeaderView(
                    waitingForRechargeReturn: $waitingForRechargeReturn,
                    balance: store.balance,
                    dailyCosts: store.dailyCosts, isLoading: store.isLoadingBalance,
                    needsRetry: store.balanceNeedsRetry, retry: { await store.loadBalance(force: true) },
                    reportDate: store.brief?.date ?? store.report?.date
                )
                Group {
                    if let brief = store.brief {
                        if let error = store.errorMessage {
                            Button {
                                Task { await store.load(force: true) }
                            } label: {
                                Label("已显示上次日报 · \(error) · 重试", systemImage: "arrow.clockwise")
                            }
                            .font(.caption2)
                            .padding(.bottom, 5)
                        } else if store.isShowingCachedEdition {
                            Text(store.report == nil ? "已显示上次日报" : "已显示上次日报 · \(reportStatusTitle)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 5)
                                .accessibilityIdentifier("today-cached-edition")
                        }
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
        .task(id: preparation, priority: .utility) {
            await TodayChinesePreparation.preloadPosts(ids: preparation.ids, baseURL: preparation.baseURL)
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

    private var preparationIDs: [Int] {
        guard rootTabIsActive, scenePhase == .active, !store.isShowingCachedEdition, store.errorMessage == nil else { return [] }
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
        .refreshable { await store.load(force: true) }
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

    @ViewBuilder
    private func briefSheet(_ route: BriefSheet) -> some View {
        switch route {
        case .system(let system, let date, let highlights):
            TodayWorldReportSourcesView(system: system, reportDate: date, highlights: highlights)
        case .highlight(let event):
            TodayEventDetailView(event: event)
        }
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
        let cached = await TodayWorldPostCache.shared.cachedPosts(ids: event.postIDs, baseURL: url)
        for post in cached { loaded[post.id] = post }
        posts = event.postIDs.compactMap { loaded[$0] }
        let missing = event.postIDs.filter { loaded[$0] == nil }
        for start in stride(from: 0, to: missing.count, by: 50) {
            guard !Task.isCancelled else { return }
            let ids = Array(missing[start..<min(start + 50, missing.count)])
            do {
                let batch = try await fetchTodayWorldPostBatch(ids: ids, baseURL: url)
                await TodayWorldPostCache.shared.store(posts: batch, baseURL: url)
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

    static func preloadPosts(ids: [Int], baseURL: URL) async {
        guard !ids.isEmpty, !Task.isCancelled else { return }
        let cached = await TodayWorldPostCache.shared.cachedPosts(ids: ids, baseURL: baseURL)
        let cachedIDs = Set(cached.map(\.id))
        let missing = ids.filter { !cachedIDs.contains($0) }
        guard !missing.isEmpty, !Task.isCancelled,
              let fetched = try? await fetchTodayWorldPostBatch(ids: missing, baseURL: baseURL) else { return }
        await TodayWorldPostCache.shared.store(posts: fetched, baseURL: baseURL)
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
