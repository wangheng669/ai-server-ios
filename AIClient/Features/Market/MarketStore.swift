import Foundation
import Observation

@MainActor
@Observable
final class MarketStore {
    private static let realtimeUIFlushInterval = Duration.milliseconds(750)

    private(set) var dashboard: MarketDashboard?
    private(set) var ashareIndustryQuotes: MarketAShareIndustryQuotes?
    private(set) var industryQuotesUnavailable = false
    private(set) var isRefreshingIndustryQuotes = false
    @ObservationIgnored private var industryQuoteLoadTask: Task<Void, Never>?
    @ObservationIgnored private var industryQuoteLoadedAt: Date?
    private var chartSnapshots: [ChartKey: MarketChartSnapshot] = [:]
    private var chartLoadTasks: [ChartKey: Task<Void, Never>] = [:]
    private(set) var chartErrors: [ChartKey: String] = [:]
    private(set) var indexConstituents: [String: MarketIndexConstituents] = [:]
    private(set) var constituentErrors: [String: String] = [:]
    private(set) var companyLogoPaths: [String: String] = [:]
    private(set) var isLoading = false
    private(set) var isRetrying = false
    private(set) var errorMessage: String?
    private(set) var realtimeStatus: MarketRealtimeClient.Status = .stopped
    private(set) var trendFallbacks: [String: [Double]] = [:]
    private(set) var lastRealtimeMessageAt: Date?
    private(set) var cacheSavedAt: Date?
    private(set) var isShowingCachedSnapshot = false

    private let service: MarketService
    private let realtime: MarketRealtimeClient
    let stockQuotes: MarketStockQuoteStore
    @ObservationIgnored private var cacheLoadTask: Task<Void, Never>?
    private var latestRealtimeUpdates: [String: MarketQuoteUpdate] = [:]
    private var loadingTrendFallbacks: Set<String> = []
    private var pendingRealtimeUpdates: [String: MarketQuoteUpdate] = [:]
    private var realtimeFlushTask: Task<Void, Never>?
    @ObservationIgnored private var dashboardLoadTask: Task<Void, Never>?
    private var lastSnapshotRefreshAt: Date?
    private var constituentRetryTasks: [String: Task<Void, Never>] = [:]
    private var chartRetryTasks: [ChartKey: Task<Void, Never>] = [:]
    private var chartRetryAttempts: [ChartKey: Int] = [:]
    private var loadingConstituentSymbols: Set<String> = []
    private var loadingCompanyLogoSymbols: Set<String> = []
    private var companyLogoCacheSaveTask: Task<Void, Never>?
    private var trendBackfillTask: Task<Void, Never>?
    @ObservationIgnored private var dashboardQuotesBySymbol: [String: MarketQuote] = [:]
    @ObservationIgnored private var constituentsBySymbol: [String: MarketIndexConstituent] = [:]
    init(baseURL: URL = ServerConfiguration.currentURL, session: URLSession? = nil) {
        let service = MarketService(baseURL: baseURL, session: session)
        self.service = service
        stockQuotes = MarketStockQuoteStore(service: service)
        realtime = MarketRealtimeClient(baseURL: baseURL)
    }

    func runUpdates() async {
        await loadCacheIfNeeded()
        guard !Task.isCancelled else { return }
        realtime.onQuote = { [weak self] update in
            self?.enqueueRealtimeUpdate(update)
        }
        realtime.onStatus = { [weak self] status in
            guard let self, realtimeStatus != status else { return }
            realtimeStatus = status
        }
        realtime.start()
        defer {
            realtime.stop()
            trendBackfillTask?.cancel()
            trendBackfillTask = nil
        }
        scheduleMissingTrendBackfill()
        startDashboardRefresh(force: false)
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(5)) }
            catch { break }
            maintainFreshness()
        }
    }

    func resumeUpdates() async {
        realtime.reconnect()
        await refresh(force: false)
    }

    func refresh(force: Bool = true) async {
        await startDashboardRefresh(force: force)?.value
    }

    func refreshAShareIndustryQuotes(force: Bool = false) async {
        guard !Task.isCancelled else { return }
        if let industryQuoteLoadTask {
            await industryQuoteLoadTask.value
            return
        }
        if !force, let industryQuoteLoadedAt, Date().timeIntervalSince(industryQuoteLoadedAt) < 45 {
            return
        }

        isRefreshingIndustryQuotes = true
        let task = Task {
            defer {
                isRefreshingIndustryQuotes = false
                industryQuoteLoadTask = nil
            }
            do {
                ashareIndustryQuotes = try await service.ashareIndustryQuotes()
                industryQuoteLoadedAt = Date()
                industryQuotesUnavailable = false
            } catch is CancellationError {
                return
            } catch {
                ashareIndustryQuotes = nil
                industryQuoteLoadedAt = nil
                industryQuotesUnavailable = true
            }
        }
        industryQuoteLoadTask = task
        await task.value
    }

    func preloadDashboard() async {
        await loadCacheIfNeeded()
        await refresh(force: false)
    }

    @discardableResult
    private func startDashboardRefresh(force: Bool) -> Task<Void, Never>? {
        guard !Task.isCancelled else { return nil }
        if let dashboardLoadTask { return dashboardLoadTask }
        if !force,
           let lastSnapshotRefreshAt,
           Date().timeIntervalSince(lastSnapshotRefreshAt) < 5,
           dashboard != nil {
            return nil
        }
        if dashboard == nil { isLoading = true }
        if force { isRetrying = true }
        // Prefetch and the visible tab share one request across navigation.
        let task = Task { await fetchDashboard(force: force) }
        dashboardLoadTask = task
        return task
    }

    private func fetchDashboard(force: Bool) async {
        defer {
            isLoading = false
            isRetrying = false
            dashboardLoadTask = nil
        }
        do {
            var value = try await service.dashboard(refresh: force)
            guard !Task.isCancelled else { return }
            for update in latestRealtimeUpdates.values {
                value.merge(update)
            }
            dashboardQuotesBySymbol = Self.quoteIndex(for: value)
            dashboard = value
            lastSnapshotRefreshAt = Date()
            isShowingCachedSnapshot = false
            cacheSavedAt = nil
            errorMessage = nil
            await MarketSnapshotCache.shared.save(value, at: Date())
            if realtimeStatus != .stopped { scheduleMissingTrendBackfill() }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func preloadListCharts(symbols: [String]) async {
        var seen = Set<String>()
        let uniqueSymbols = symbols.filter { seen.insert($0).inserted }
        await runWithLimitedConcurrency(uniqueSymbols, maximumConcurrentRequests: 6) { symbol in
            await self.loadChart(symbol: symbol, range: .day)
        }
    }

    func preloadStockCharts(symbol: String, ranges: [MarketRange]) async {
        await runWithLimitedConcurrency(ranges, maximumConcurrentRequests: ranges.count) { range in
            await self.loadChart(symbol: symbol, range: range)
        }
    }

    func loadChart(symbol: String, range: MarketRange, force: Bool = false) async {
        guard !Task.isCancelled else { return }
        let key = ChartKey(symbol: symbol, range: range)
        if !force, let snapshot = chartSnapshots[key], !snapshot.isRestored,
           (marketChartCanUseCache(snapshot.chart, loadedAt: snapshot.loadedAt)
            || chartRetryTasks[key] != nil) { return }
        if let task = chartLoadTasks[key] {
            await task.value
            return
        }

        // Keep the request alive when navigation cancels the view that started it.
        let task = Task { await fetchChart(for: key, force: force) }
        chartLoadTasks[key] = task
        await task.value
    }

    func isLoadingChart(symbol: String, range: MarketRange) -> Bool {
        chartLoadTasks[ChartKey(symbol: symbol, range: range)] != nil
    }

    private func fetchChart(for key: ChartKey, force: Bool) async {
        chartErrors[key] = nil
        defer { chartLoadTasks[key] = nil }
        let cacheKey = "\(service.baseURL.absoluteString)|\(key.symbol)|\(key.range.apiRange)|\(key.range.apiInterval)"
        async let response = service.chart(symbol: key.symbol, range: key.range, refresh: force)
        do {
            if chartSnapshots[key] == nil,
               let entry = await DisplaySnapshotCache.charts.load(MarketChart.self, key: cacheKey, maximumAge: 7 * 24 * 60 * 60),
               entry.value.symbol == key.symbol, entry.value.interval == key.range.apiInterval {
                let artifacts = try await marketChartArtifacts(for: entry.value, range: key.range)
                try Task.checkCancellation()
                rememberChart(MarketChartSnapshot(chart: entry.value, artifacts: artifacts,
                                                  loadedAt: entry.savedAt, isRestored: true), for: key)
            }

            let value = try await response
            let artifacts = try await marketChartArtifacts(for: value, range: key.range)
            guard !Task.isCancelled else { return }
            let loadedAt = Date()
            rememberChart(MarketChartSnapshot(chart: value, artifacts: artifacts,
                                              loadedAt: loadedAt, isRestored: false), for: key)
            if marketChartNeedsRetry(value) {
                scheduleChartRetry(symbol: key.symbol, range: key.range, key: key)
            } else {
                chartRetryTasks[key]?.cancel()
                chartRetryTasks[key] = nil
                chartRetryAttempts[key] = nil
            }
            if !artifacts.hasDisplayPoints {
                await DisplaySnapshotCache.charts.remove(key: cacheKey)
            } else {
                await DisplaySnapshotCache.charts.save(value, key: cacheKey, at: loadedAt, minimumInterval: 90)
            }
        } catch is CancellationError {
            return
        } catch {
            chartErrors[key] = error.localizedDescription
        }
    }

    private func rememberChart(_ snapshot: MarketChartSnapshot, for key: ChartKey) {
        chartSnapshots[key] = snapshot
        guard key.range == .fiveYears || key.range == .maximum else { return }
        // Opening multiple details should not retain every long history in memory.
        let otherHistories = chartSnapshots.filter { $0.key.range == key.range && $0.key != key }
        for entry in otherHistories.sorted(by: { $0.value.loadedAt > $1.value.loadedAt }).dropFirst(7) {
            chartSnapshots.removeValue(forKey: entry.key)
        }
    }

    private func scheduleChartRetry(symbol: String, range: MarketRange, key: ChartKey) {
        guard chartRetryTasks[key] == nil else { return }
        let attempt = chartRetryAttempts[key, default: 0]
        guard attempt < 3 else { return }
        chartRetryAttempts[key] = attempt + 1
        let delay = [1.5, 3.0, 5.0][attempt]
        chartRetryTasks[key] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch {
                self?.chartRetryTasks[key] = nil
                return
            }
            guard !Task.isCancelled else {
                self?.chartRetryTasks[key] = nil
                return
            }
            self?.chartRetryTasks[key] = nil
            await self?.loadChart(symbol: symbol, range: range, force: true)
        }
    }

    func chartSnapshot(symbol: String, range: MarketRange) -> MarketChartSnapshot? {
        chartSnapshots[ChartKey(symbol: symbol, range: range)]
    }

    func chart(symbol: String, range: MarketRange) -> MarketChart? {
        chartSnapshot(symbol: symbol, range: range)?.chart
    }

    func chartError(symbol: String, range: MarketRange) -> String? {
        chartErrors[ChartKey(symbol: symbol, range: range)]
    }

    func loadIndexConstituents(symbol: String, force: Bool = false) async {
        if !force, indexConstituents[symbol] != nil { return }
        guard loadingConstituentSymbols.insert(symbol).inserted else { return }
        constituentErrors[symbol] = nil
        defer { loadingConstituentSymbols.remove(symbol) }
        do {
            let value = try await service.indexConstituents(symbol: symbol, refresh: force)
            indexConstituents[symbol] = value
            rebuildConstituentIndex()
            constituentErrors[symbol] = nil
            scheduleConstituentRetryIfNeeded(symbol: symbol, pendingSymbols: value.symbolsPendingRefresh)
        } catch is CancellationError {
            return
        } catch {
            constituentErrors[symbol] = error.localizedDescription
        }
    }

    func isLoadingIndexConstituents(symbol: String) -> Bool {
        loadingConstituentSymbols.contains(symbol)
    }

    private func scheduleConstituentRetryIfNeeded(symbol: String, pendingSymbols: [String]) {
        guard !pendingSymbols.isEmpty, constituentRetryTasks[symbol] == nil else { return }
        constituentRetryTasks[symbol] = Task { [weak self] in
            defer { self?.constituentRetryTasks[symbol] = nil }
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
            guard !Task.isCancelled else { return }
            // One controlled retry closes the async refresh loop without polling forever.
            await self?.loadIndexConstituents(symbol: symbol, force: true)
        }
    }

    var latestQuoteDate: Date? {
        if let timestamp = dashboard?.freshness?.latestTimestamp, timestamp > 0 {
            return Date(timeIntervalSince1970: Double(timestamp) / 1000)
        }
        let quotes = (dashboard?.coreIndices ?? []) + (dashboard?.referenceIndices ?? []) + (dashboard?.metrics ?? [])
            + (dashboard?.allRegionalComponents ?? []) + (dashboard?.crypto ?? []) + (dashboard?.commodities ?? [])
        guard let timestamp = quotes.compactMap(\.timestamp).max() else { return nil }
        return Date(timeIntervalSince1970: Double(timestamp) / 1000)
    }

    var componentsLatestQuoteDate: Date? {
        guard let timestamp = dashboard?.allRegionalComponents.compactMap(\.timestamp).max() else { return nil }
        return Date(timeIntervalSince1970: Double(timestamp) / 1000)
    }

    var hasOpenMarket: Bool {
        dashboard?.freshness?.hasOpenMarket
            ?? ((dashboard?.coreIndices ?? []) + (dashboard?.metrics ?? [])).contains { $0.marketSession != "closed" }
    }

    /// 非正常交易时段服务端可能不下发日内 trend，这里用 5 日图表中最近一个交易日的数据兜底。
    func trendValues(for quote: MarketQuote?) -> [Double] {
        guard let quote else { return [] }
        let snapshotValues = quote.trend.count > 1 || quote.liveTrendValue != nil
            ? quote.trend
            : trendFallbacks[quote.symbol] ?? []
        guard !isShowingCachedSnapshot, let liveTrendValue = quote.liveTrendValue else { return snapshotValues }
        return marketAppendingLiveValue(liveTrendValue, to: snapshotValues, limit: 40)
    }

    func listTrendValues(for quote: MarketQuote?) -> [Double] {
        guard let quote else { return [] }
        return marketListChartTrend(
            chartValues: chartSnapshot(symbol: quote.symbol, range: .day)?.artifacts.listTrend
        )
    }

    private func backfillMissingTrends() async {
        guard let dashboard else { return }
        for symbol in marketTrendBackfillSymbols(for: dashboard) {
            guard !Task.isCancelled else { return }
            await loadTrendFallback(symbol: symbol)
        }
    }

    private func scheduleMissingTrendBackfill() {
        guard dashboard != nil, trendBackfillTask == nil else { return }
        trendBackfillTask = Task { [weak self] in
            await self?.backfillMissingTrends()
            guard !Task.isCancelled else { return }
            self?.trendBackfillTask = nil
        }
    }

    private func loadTrendFallback(symbol: String) async {
        guard trendFallbacks[symbol] == nil, !loadingTrendFallbacks.contains(symbol) else { return }
        loadingTrendFallbacks.insert(symbol)
        defer { loadingTrendFallbacks.remove(symbol) }
        do {
            let chart = try await service.recentIntradayChart(symbol: symbol)
            let values = chart.candles.sorted { $0.timestamp < $1.timestamp }.map(\.close)
            guard values.count > 1, values.allSatisfy(\.isFinite) else { return }
            trendFallbacks[symbol] = values
        } catch is CancellationError {
            return
        } catch { }
    }

    var realtimeIsFresh: Bool {
        guard realtimeStatus == .connected, let lastRealtimeMessageAt else { return false }
        return Date().timeIntervalSince(lastRealtimeMessageAt) < 30
    }

    var cachedSnapshotAge: TimeInterval? {
        guard isShowingCachedSnapshot, let cacheSavedAt else { return nil }
        return max(0, Date().timeIntervalSince(cacheSavedAt))
    }

    var maximumOpenMarketDelayMinutes: Int? {
        let quotes = (dashboard?.coreIndices ?? []) + (dashboard?.referenceIndices ?? [])
            + (dashboard?.metrics ?? []) + (dashboard?.allRegionalComponents ?? []) + (dashboard?.commodities ?? [])
        return quotes
            .filter { $0.marketSession == "regular" }
            .compactMap(\.visibleDelayMinutes)
            .max()
    }

    var quoteIssueMessage: String? {
        guard let dashboard else { return nil }
        let issues = dashboard.symbolHealth.filter { health in
            health.status == .missing ||
                (health.status == .stale && health.lastSessionTrade == nil &&
                 dashboard.quote(symbol: health.symbol)?.stale != false)
        }
        let unavailableSymbols = Set(issues.compactMap { health in
            dashboard.unavailableMetric(symbol: health.symbol) == nil ? nil : health.symbol
        })
        return marketHealthSummary(issues, unavailableSymbols: unavailableSymbols)
    }

    func lastSessionTrade(for quote: MarketQuote) -> MarketLastSessionTrade? {
        guard quote.stale == true else { return nil }
        return lastSessionTrade(symbol: quote.symbol, asOf: quote.quality?.asOfTimestamp)
    }

    func lastSessionTrade(symbol: String, asOf: Int64?) -> MarketLastSessionTrade? {
        guard !isShowingCachedSnapshot,
              let trade = dashboard?.symbolHealth.first(where: { $0.symbol == symbol })?.lastSessionTrade,
              trade.timestamp == asOf else { return nil }
        return trade
    }

    func quote(symbol: String) -> MarketQuote? {
        _ = dashboard
        _ = indexConstituents.count
        return dashboardQuotesBySymbol[symbol] ?? constituentsBySymbol[symbol]?.quote
    }

    func constituent(symbol: String) -> MarketIndexConstituent? {
        _ = indexConstituents.count
        return constituentsBySymbol[symbol]
    }

    func loadCompanyLogo(symbol: String, name: String) async {
        guard companyLogoPaths[symbol] == nil else { return }
        guard loadingCompanyLogoSymbols.insert(symbol).inserted else { return }
        defer { loadingCompanyLogoSymbols.remove(symbol) }
        if let path = try? await service.companyLogo(symbol: symbol, name: name) {
            companyLogoPaths[symbol] = path
            scheduleCompanyLogoCacheSave()
        }
    }

    private func scheduleCompanyLogoCacheSave() {
        companyLogoCacheSaveTask?.cancel()
        let paths = companyLogoPaths
        companyLogoCacheSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            await MarketCompanyLogoPathCache.saveOffMain(paths)
            guard !Task.isCancelled else { return }
            self?.companyLogoCacheSaveTask = nil
        }
    }

    private func mergeConstituent(_ update: MarketQuoteUpdate) {
        for key in indexConstituents.keys {
            indexConstituents[key]?.merge(update)
        }
    }

    private func loadCacheIfNeeded() async {
        let task = cacheLoadTask ?? Task { await restoreCache() }
        cacheLoadTask = task
        await task.value
    }

    private func restoreCache() async {
        if let snapshot = await MarketSnapshotCache.shared.load(), dashboard == nil {
            dashboardQuotesBySymbol = Self.quoteIndex(for: snapshot.dashboard)
            cacheSavedAt = snapshot.savedAt
            isShowingCachedSnapshot = true
            dashboard = snapshot.dashboard
        }
        let paths = await MarketCompanyLogoPathCache.loadOffMain()
        if companyLogoPaths.isEmpty { companyLogoPaths = paths }
    }

    private func enqueueRealtimeUpdate(_ update: MarketQuoteUpdate) {
        lastRealtimeMessageAt = Date()
        guard marketRealtimeUpdateIsCurrent(
            update,
            current: quote(symbol: update.symbol),
            cached: latestRealtimeUpdates[update.symbol]
        ) else { return }
        let incomingSession = MarketTradingSession(rawValue: update.marketSession)
        if incomingSession != .unknown,
           let currentSession = quote(symbol: update.symbol)?.tradingSession,
           currentSession != incomingSession {
            lastSnapshotRefreshAt = nil
        }
        latestRealtimeUpdates[update.symbol] = update
        pendingRealtimeUpdates[update.symbol] = update
        guard realtimeFlushTask == nil else { return }
        realtimeFlushTask = Task { [weak self] in
            // Keep receiving every quote, but bound expensive dashboard-driven view updates.
            try? await Task.sleep(for: Self.realtimeUIFlushInterval)
            guard !Task.isCancelled else { return }
            self?.flushRealtimeUpdates()
        }
    }

    private func flushRealtimeUpdates() {
        realtimeFlushTask = nil
        guard var dashboard, !pendingRealtimeUpdates.isEmpty else {
            pendingRealtimeUpdates.removeAll()
            return
        }
        let updates = pendingRealtimeUpdates.values
        pendingRealtimeUpdates.removeAll(keepingCapacity: true)
        guard !isShowingCachedSnapshot else { return }
        for update in updates {
            dashboard.merge(update)
            mergeConstituent(update)
            if let current = dashboardQuotesBySymbol[update.symbol],
               marketRealtimeUpdateIsCurrent(update, current: current) {
                dashboardQuotesBySymbol[update.symbol] = update.merging(into: current)
            }
            if var constituent = constituentsBySymbol[update.symbol],
               marketRealtimeUpdateIsCurrent(update, current: constituent.quote) {
                constituent.quote = update.merging(into: constituent.quote)
                constituentsBySymbol[update.symbol] = constituent
            }
        }
        self.dashboard = dashboard
    }

    private static func quoteIndex(for dashboard: MarketDashboard) -> [String: MarketQuote] {
        let quotes = dashboard.coreIndices
            + dashboard.referenceIndices
            + dashboard.metrics
            + dashboard.allRegionalComponents
            + dashboard.crypto
            + dashboard.commodities
            + (dashboard.indexSessions.map { Array($0.values) } ?? [])
        return Dictionary(quotes.map { ($0.symbol, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func rebuildConstituentIndex() {
        constituentsBySymbol = Dictionary(
            indexConstituents.values.flatMap(\.items).map { ($0.quote.symbol, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func maintainFreshness(now: Date = Date()) {
        guard dashboardLoadTask == nil else { return }
        let serverInterval = TimeInterval(dashboard?.refreshIntervalMs ?? 15_000) / 1_000
        let disconnected = realtimeStatus != .connected
        let messageIsStale = lastRealtimeMessageAt.map { now.timeIntervalSince($0) >= 30 } ?? true
        let desiredInterval = disconnected || messageIsStale ? max(15, serverInterval) : max(120, serverInterval * 4)
        guard now.timeIntervalSince(lastSnapshotRefreshAt ?? .distantPast) >= desiredInterval else { return }
        if messageIsStale, realtimeStatus == .connected { realtime.reconnect() }
        startDashboardRefresh(force: false)
    }

}

func marketListChartTrend(chartValues: [Double]?) -> [Double] {
    // Dashboard trends cover only the latest minutes, not the chart's session.
    // Leave a placeholder until session data arrives instead of changing windows.
    chartValues ?? []
}

func marketPinnedListTrend(current: [Double], incoming: [Double]) -> [Double] {
    // Accept the full-session chart and subsequent corrections, even when the
    // point count is unchanged (or a new trading session has fewer points).
    // Keep the existing shape only while the incoming response is a placeholder.
    guard incoming.count >= 3 else {
        return current.count >= incoming.count ? current : incoming
    }
    return incoming
}

enum MarketCompanyLogoPathCache {
    private static let defaultsKey = "market.companyLogoPaths.v1"
    private static let savedAtKey = "market.companyLogoPaths.savedAt.v1"
    private static let maximumAge: TimeInterval = 30 * 24 * 60 * 60

    static func load(defaults: UserDefaults = .standard, now: Date = Date()) -> [String: String] {
        guard let savedAt = defaults.object(forKey: savedAtKey) as? Date,
              now.timeIntervalSince(savedAt) < maximumAge else { return [:] }
        return defaults.dictionary(forKey: defaultsKey)?.reduce(into: [:]) { result, item in
            guard let path = item.value as? String, !path.isEmpty else { return }
            result[item.key] = path
        } ?? [:]
    }

    static func save(_ paths: [String: String], defaults: UserDefaults = .standard) {
        defaults.set(paths, forKey: defaultsKey)
        defaults.set(Date(), forKey: savedAtKey)
    }

    static func loadOffMain() async -> [String: String] { load() }

    static func saveOffMain(_ paths: [String: String]) async {
        save(paths)
    }
}

func marketQuoteNeedsTrendBackfill(_ quote: MarketQuote) -> Bool {
    quote.trend.count <= 1 && quote.tradingSession != .regular && quote.tradingSession != .alwaysOpen
}

func marketTrendBackfillSymbols(for dashboard: MarketDashboard, limit: Int = 24) -> [String] {
    guard limit > 0 else { return [] }
    var seen: Set<String> = []
    var symbols: [String] = []
    // Regional lead indices drive both the hero and index rows, so protect them from the bounded
    // queue before filling gaps in the larger stock lists.
    let quotes = dashboard.coreIndices
        + (dashboard.regionalStockEntries["us"] ?? []).compactMap(\.quote)
        + dashboard.allRegionalComponents
        + dashboard.referenceIndices
        + dashboard.metrics
        + dashboard.commodities
    for quote in quotes
    where marketQuoteNeedsTrendBackfill(quote) && seen.insert(quote.symbol).inserted {
        symbols.append(quote.symbol)
        if symbols.count >= limit { break }
    }
    return symbols
}

func marketChartNeedsRetry(_ chart: MarketChart) -> Bool {
    let quality = chart.quality
    return quality.status == .repairing
        || quality.status == .partial
        || !quality.missing.isEmpty
        || (chart.candles.isEmpty && quality.status != .complete)
}

func marketChartCanUseCache(_ chart: MarketChart, loadedAt: Date, now: Date = Date()) -> Bool {
    guard !marketChartNeedsRetry(chart) else { return false }
    let maximumAge: TimeInterval
    switch chart.interval {
    case "1m", "15m": maximumAge = 30
    case "1d": maximumAge = 5 * 60
    default: return false
    }
    return now.timeIntervalSince(loadedAt) < maximumAge
}

func marketHealthSummary(_ issues: [MarketSymbolHealth], unavailableSymbols: Set<String>) -> String? {
    guard !issues.isEmpty else { return nil }
    let names = issues.prefix(3).map { marketSymbolDisplayName($0.symbol) }
    let listedNames = names.joined(separator: "、")
    let suffix = issues.count > names.count ? "\(listedNames)等 \(issues.count) 项" : listedNames
    let staleCount = issues.filter { $0.status == .stale && !unavailableSymbols.contains($0.symbol) }.count
    let missingCount = issues.count - staleCount
    if missingCount > 0, staleCount > 0 { return "部分行情缺失或延迟：\(suffix)" }
    if missingCount > 0 { return "部分行情暂缺：\(suffix)" }
    return "部分行情更新延迟：\(suffix)"
}

func marketSymbolDisplayName(_ symbol: String) -> String {
    switch symbol {
    case "932000.SS": "中证2000"
    case "THS:883418": "微盘股"
    case "^TOPX": "东证指数"
    case "JP10Y": "日本10年国债"
    case "KR10Y": "韩国10年国债"
    default: symbol
    }
}

struct ChartKey: Hashable {
    let symbol: String
    let range: MarketRange
}

struct MarketChartSnapshot {
    let chart: MarketChart
    let artifacts: MarketChartArtifacts
    let loadedAt: Date
    let isRestored: Bool
}

private actor MarketSnapshotCache {
    static let shared = MarketSnapshotCache()
    private let key = "market.dashboard.cache.v1"
    private let maximumDisplayAge: TimeInterval = 24 * 60 * 60

    struct Snapshot: Codable {
        let dashboard: MarketDashboard
        let savedAt: Date
    }

    func load() -> Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              Date().timeIntervalSince(snapshot.savedAt) <= maximumDisplayAge else { return nil }
        return snapshot
    }

    func save(_ dashboard: MarketDashboard, at date: Date) {
        guard let data = try? JSONEncoder().encode(Snapshot(dashboard: dashboard, savedAt: date)) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
