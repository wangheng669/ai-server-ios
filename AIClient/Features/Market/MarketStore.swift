import Foundation
import Observation

@MainActor
@Observable
final class MarketStore {
    private static let realtimeUIFlushInterval = Duration.milliseconds(750)

    private(set) var dashboard: MarketDashboard?
    private(set) var charts: [ChartKey: MarketChart] = [:]
    private(set) var chartPresentations: [ChartKey: MarketChartPresentation] = [:]
    private(set) var listTrendPresentations: [ChartKey: [Double]] = [:]
    private(set) var loadingCharts: Set<ChartKey> = []
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
    private var loadedCache = false
    private var latestRealtimeUpdates: [String: MarketQuoteUpdate] = [:]
    private var loadingTrendFallbacks: Set<String> = []
    private var pendingRealtimeUpdates: [String: MarketQuoteUpdate] = [:]
    private var realtimeFlushTask: Task<Void, Never>?
    private var isRefreshing = false
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

    init(baseURL: URL = ServerConfiguration.currentURL) {
        service = MarketService(baseURL: baseURL)
        realtime = MarketRealtimeClient(baseURL: baseURL)
        companyLogoPaths = MarketCompanyLogoPathCache.load()
    }

    func runUpdates() async {
        loadCacheIfNeeded()
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
        await refresh(force: false)
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(5)) }
            catch { break }
            await maintainFreshness()
        }
    }

    func resumeUpdates() async {
        realtime.reconnect()
        await refresh(force: false)
    }

    func refresh(force: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        if dashboard == nil { isLoading = true }
        else if force { isRetrying = true }
        defer {
            isLoading = false
            isRetrying = false
            isRefreshing = false
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
            errorMessage = marketHealthMessage(for: value)
            MarketSnapshotCache.save(value, at: Date())
            scheduleMissingTrendBackfill()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadChart(symbol: String, range: MarketRange, force: Bool = false) async {
        let key = ChartKey(symbol: symbol, range: range)
        if !force, let cached = charts[key], marketChartCanUseCache(cached) { return }
        guard !loadingCharts.contains(key) else { return }
        loadingCharts.insert(key)
        chartErrors[key] = nil
        defer { loadingCharts.remove(key) }
        do {
            let value = try await service.chart(symbol: symbol, range: range, refresh: force)
            let artifacts = try await marketChartArtifacts(for: value)
            guard !Task.isCancelled else { return }
            charts[key] = value
            chartPresentations[key] = artifacts.presentation
            listTrendPresentations[key] = artifacts.listTrend
            if marketChartNeedsRetry(value) {
                scheduleChartRetry(symbol: symbol, range: range, key: key)
            } else {
                chartRetryTasks[key]?.cancel()
                chartRetryTasks[key] = nil
                chartRetryAttempts[key] = nil
            }
        } catch is CancellationError {
            return
        } catch {
            chartErrors[key] = error.localizedDescription
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

    func chart(symbol: String, range: MarketRange) -> MarketChart? {
        charts[ChartKey(symbol: symbol, range: range)]
    }

    func chartPresentation(symbol: String, range: MarketRange) -> MarketChartPresentation? {
        chartPresentations[ChartKey(symbol: symbol, range: range)]
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
        return marketPreferredListTrend(
            chartValues: listTrendPresentations[ChartKey(symbol: quote.symbol, range: .day)],
            snapshotValues: trendValues(for: quote)
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
        guard trendBackfillTask == nil else { return }
        trendBackfillTask = Task { [weak self] in
            await self?.backfillMissingTrends()
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

    var healthIssues: [MarketSymbolHealth] {
        guard let dashboard else { return [] }
        return dashboard.symbolHealth.filter { $0.status == .missing || $0.status == .stale }
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

    private func loadCacheIfNeeded() {
        guard !loadedCache else { return }
        loadedCache = true
        guard let snapshot = MarketSnapshotCache.load() else { return }
        dashboardQuotesBySymbol = Self.quoteIndex(for: snapshot.dashboard)
        dashboard = snapshot.dashboard
        cacheSavedAt = snapshot.savedAt
        isShowingCachedSnapshot = true
        scheduleMissingTrendBackfill()
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

    private func maintainFreshness(now: Date = Date()) async {
        let serverInterval = TimeInterval(dashboard?.refreshIntervalMs ?? 15_000) / 1_000
        let disconnected = realtimeStatus != .connected
        let messageIsStale = lastRealtimeMessageAt.map { now.timeIntervalSince($0) >= 30 } ?? true
        let desiredInterval = disconnected || messageIsStale ? max(15, serverInterval) : max(120, serverInterval * 4)
        guard now.timeIntervalSince(lastSnapshotRefreshAt ?? .distantPast) >= desiredInterval else { return }
        if messageIsStale, realtimeStatus == .connected { realtime.reconnect() }
        await refresh(force: false)
    }

}

func marketPreferredListTrend(chartValues: [Double]?, snapshotValues: [Double]) -> [Double] {
    guard let chartValues, !chartValues.isEmpty else { return snapshotValues }
    // A two-point intraday response only describes its endpoints and renders as a
    // misleading diagonal. Keep the richer dashboard trend until the chart has shape.
    if chartValues.count < 3, snapshotValues.count >= 3 { return snapshotValues }
    return chartValues
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
        + (dashboard.componentsByRegion["us"] ?? [])
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
    chart.candles.isEmpty && chart.quality.status != .complete
}

func marketChartCanUseCache(_ chart: MarketChart) -> Bool {
    !marketChartNeedsRetry(chart)
}

private func marketHealthMessage(for dashboard: MarketDashboard) -> String? {
    let missing = dashboard.symbolHealth.filter { $0.status == .missing }
    let stale = dashboard.symbolHealth.filter { $0.status == .stale }
    if !missing.isEmpty {
        return "\(missing.count) 项行情暂未返回"
    }
    if !stale.isEmpty {
        return "\(stale.count) 项行情更新延迟"
    }
    return nil
}

func marketHealthSummary(_ issues: [MarketSymbolHealth]) -> String? {
    guard !issues.isEmpty else { return nil }
    let names = issues.prefix(3).map { marketSymbolDisplayName($0.symbol) }
    let listedNames = names.joined(separator: "、")
    let suffix = issues.count > names.count ? "\(listedNames)等 \(issues.count) 项" : listedNames
    let staleCount = issues.filter { $0.status == .stale }.count
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
    default: symbol
    }
}

struct ChartKey: Hashable {
    let symbol: String
    let range: MarketRange
}

private enum MarketSnapshotCache {
    private static let key = "market.dashboard.cache.v1"
    private static let maximumDisplayAge: TimeInterval = 24 * 60 * 60

    struct Snapshot: Codable {
        let dashboard: MarketDashboard
        let savedAt: Date
    }

    static func load() -> Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            return Date().timeIntervalSince(snapshot.savedAt) <= maximumDisplayAge ? snapshot : nil
        }
        guard let dashboard = try? JSONDecoder().decode(MarketDashboard.self, from: data) else { return nil }
        let savedAt = marketISODate(dashboard.generatedAt) ?? .distantPast
        guard Date().timeIntervalSince(savedAt) <= maximumDisplayAge else { return nil }
        return Snapshot(dashboard: dashboard, savedAt: savedAt)
    }

    static func save(_ dashboard: MarketDashboard, at date: Date) {
        guard let data = try? JSONEncoder().encode(Snapshot(dashboard: dashboard, savedAt: date)) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
