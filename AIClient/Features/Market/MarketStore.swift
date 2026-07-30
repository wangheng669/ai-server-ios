import Foundation
import Observation

@MainActor
@Observable
final class MarketStore {
    private(set) var dashboard: MarketDashboard?
    private(set) var charts: [ChartKey: MarketChart] = [:]
    private(set) var loadingCharts: Set<ChartKey> = []
    private(set) var chartErrors: [ChartKey: String] = [:]
    private(set) var indexConstituents: [String: MarketIndexConstituents] = [:]
    private(set) var constituentErrors: [String: String] = [:]
    private(set) var companyLogoPaths: [String: String] = [:]
    private(set) var companyFinancials: [String: MarketCompanyFinancials] = [:]
    private(set) var companyFinancialErrors: [String: String] = [:]
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
    private var realtimeQuotes: [String: MarketQuote] = [:]
    private var loadingTrendFallbacks: Set<String> = []
    private var loadingCompanyFinancials: Set<String> = []
    private var pendingRealtimeUpdates: [String: MarketQuoteUpdate] = [:]
    private var realtimeFlushTask: Task<Void, Never>?
    private var isRefreshing = false
    private var lastSnapshotRefreshAt: Date?
    private var constituentRetryTasks: [String: Task<Void, Never>] = [:]
    private var chartRetryTasks: [ChartKey: Task<Void, Never>] = [:]
    private var chartRetryAttempts: [ChartKey: Int] = [:]
    private var loadingConstituentSymbols: Set<String> = []
    private var trendBackfillTask: Task<Void, Never>?

    init(baseURL: URL = ServerConfiguration.currentURL) {
        service = MarketService(baseURL: baseURL)
        realtime = MarketRealtimeClient(baseURL: baseURL)
    }

    func runUpdates() async {
        loadCacheIfNeeded()
        realtime.onQuote = { [weak self] update in
            self?.enqueueRealtimeUpdate(update)
        }
        realtime.onStatus = { [weak self] status in self?.realtimeStatus = status }
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
            for quote in realtimeQuotes.values {
                let serverTimestamp = value.quote(symbol: quote.symbol)?.timestamp ?? 0
                if quote.timestamp ?? 0 >= serverTimestamp { value.replace(quote) }
            }
            dashboard = value
            lastSnapshotRefreshAt = Date()
            isShowingCachedSnapshot = false
            cacheSavedAt = nil
            errorMessage = marketHealthMessage(for: value)
            MarketSnapshotCache.save(value, at: Date())
            scheduleClosedTrendBackfill()
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
            charts[key] = value
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

    func chartError(symbol: String, range: MarketRange) -> String? {
        chartErrors[ChartKey(symbol: symbol, range: range)]
    }

    func loadIndexConstituents(symbol: String, force: Bool = false) async {
        if !force, indexConstituents[symbol] != nil { return }
        guard loadingConstituentSymbols.insert(symbol).inserted else { return }
        defer { loadingConstituentSymbols.remove(symbol) }
        do {
            let value = try await service.indexConstituents(symbol: symbol, refresh: force)
            indexConstituents[symbol] = value
            constituentErrors[symbol] = nil
            scheduleConstituentRetryIfNeeded(symbol: symbol, pendingSymbols: value.symbolsPendingRefresh)
        } catch is CancellationError {
            return
        } catch {
            constituentErrors[symbol] = error.localizedDescription
        }
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
            + (dashboard?.components ?? []) + (dashboard?.crypto ?? [])
        guard let timestamp = quotes.compactMap(\.timestamp).max() else { return nil }
        return Date(timeIntervalSince1970: Double(timestamp) / 1000)
    }

    var componentsLatestQuoteDate: Date? {
        guard let timestamp = dashboard?.components.compactMap(\.timestamp).max() else { return nil }
        return Date(timeIntervalSince1970: Double(timestamp) / 1000)
    }

    var hasOpenMarket: Bool {
        dashboard?.freshness?.hasOpenMarket
            ?? ((dashboard?.coreIndices ?? []) + (dashboard?.metrics ?? [])).contains { $0.marketSession != "closed" }
    }

    /// 收盘后服务端不再下发日内 trend，这里用 5 日图表中最近一个交易日的数据兜底。
    func trendValues(for quote: MarketQuote?) -> [Double] {
        guard let quote else { return [] }
        if quote.trend.count > 1 { return quote.trend }
        return trendFallbacks[quote.symbol] ?? []
    }

    private func backfillClosedTrends() async {
        guard let dashboard else { return }
        var seen: Set<String> = []
        var symbols: [String] = []
        for quote in dashboard.coreIndices + dashboard.referenceIndices + dashboard.metrics + dashboard.components
        where quote.trend.count <= 1 && quote.marketSession == "closed" && seen.insert(quote.symbol).inserted {
            symbols.append(quote.symbol)
            if symbols.count >= 12 { break }
        }
        for symbol in symbols {
            guard !Task.isCancelled else { return }
            await loadTrendFallback(symbol: symbol)
        }
    }

    private func scheduleClosedTrendBackfill() {
        guard trendBackfillTask == nil else { return }
        trendBackfillTask = Task { [weak self] in
            await self?.backfillClosedTrends()
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
            + (dashboard?.metrics ?? []) + (dashboard?.components ?? [])
        let seconds = quotes
            .filter { $0.marketSession == "regular" }
            .compactMap(\.delaySeconds)
            .max()
        guard let seconds, seconds > 0 else { return nil }
        return max(1, Int(ceil(Double(seconds) / 60)))
    }

    var healthIssues: [MarketSymbolHealth] {
        guard let dashboard else { return [] }
        if !dashboard.symbolHealth.isEmpty {
            return dashboard.symbolHealth.filter { $0.status == .missing || $0.status == .stale }
        }
        return dashboard.missingSymbols.map {
            MarketSymbolHealth(symbol: $0, status: .missing, asOf: nil, timestamp: nil, source: nil, delaySeconds: nil, reason: "quote_unavailable")
        }
    }

    func quote(symbol: String) -> MarketQuote? {
        if let quote = dashboard?.coreIndices.first(where: { $0.symbol == symbol }) { return quote }
        if let quote = dashboard?.referenceIndices.first(where: { $0.symbol == symbol }) { return quote }
        if let quote = dashboard?.metrics.first(where: { $0.symbol == symbol }) { return quote }
        if let quote = dashboard?.components.first(where: { $0.symbol == symbol }) { return quote }
        if let quote = dashboard?.crypto.first(where: { $0.symbol == symbol }) { return quote }
        if let quote = dashboard?.indexSessions?.values.first(where: { $0.symbol == symbol }) { return quote }
        return indexConstituents.values.lazy
            .flatMap(\.items)
            .first(where: { $0.quote.symbol == symbol })?
            .quote
    }

    func constituent(symbol: String) -> MarketIndexConstituent? {
        indexConstituents.values.lazy.flatMap(\.items).first(where: { $0.quote.symbol == symbol })
    }

    func loadCompanyLogo(symbol: String, name: String) async {
        guard companyLogoPaths[symbol] == nil else { return }
        if let path = try? await service.companyLogo(symbol: symbol, name: name) {
            companyLogoPaths[symbol] = path
        }
    }

    func loadCompanyFinancials(symbol: String, force: Bool = false) async {
        if !force, companyFinancials[symbol] != nil { return }
        guard !loadingCompanyFinancials.contains(symbol) else { return }
        loadingCompanyFinancials.insert(symbol)
        companyFinancialErrors[symbol] = nil
        defer { loadingCompanyFinancials.remove(symbol) }
        do {
            companyFinancials[symbol] = try await service.companyFinancials(symbol: symbol)
        } catch is CancellationError {
            return
        } catch {
            companyFinancialErrors[symbol] = error.localizedDescription
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
        dashboard = snapshot.dashboard
        cacheSavedAt = snapshot.savedAt
        isShowingCachedSnapshot = true
    }

    private func enqueueRealtimeUpdate(_ update: MarketQuoteUpdate) {
        lastRealtimeMessageAt = Date()
        pendingRealtimeUpdates[update.symbol] = update
        guard realtimeFlushTask == nil else { return }
        realtimeFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
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
        for update in updates {
            let quote = update.merging(into: self.quote(symbol: update.symbol))
            dashboard.replace(quote)
            mergeConstituent(update)
            realtimeQuotes[quote.symbol] = quote
        }
        self.dashboard = dashboard
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
    // Compatibility with servers that predate per-symbol health metadata.
    return dashboard.missingSymbols.isEmpty ? nil : "\(dashboard.missingSymbols.count) 项行情暂未返回"
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
