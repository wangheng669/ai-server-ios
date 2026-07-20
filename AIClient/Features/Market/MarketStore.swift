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
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var realtimeStatus: MarketRealtimeClient.Status = .stopped
    private(set) var lastRealtimeMessageAt: Date?
    private(set) var cacheSavedAt: Date?
    private(set) var isShowingCachedSnapshot = false

    private let service: MarketService
    private let realtime: MarketRealtimeClient
    private var loadedCache = false
    private var realtimeQuotes: [String: MarketQuote] = [:]
    private var pendingRealtimeUpdates: [String: MarketQuoteUpdate] = [:]
    private var realtimeFlushTask: Task<Void, Never>?
    private var isRefreshing = false
    private var lastSnapshotRefreshAt: Date?

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
        defer { realtime.stop() }
        await refresh(force: true)
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
        defer {
            isLoading = false
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
            errorMessage = value.missingSymbols.isEmpty ? nil : "部分行情暂未返回"
            MarketSnapshotCache.save(value, at: Date())
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadChart(symbol: String, range: MarketRange, force: Bool = false) async {
        let key = ChartKey(symbol: symbol, range: range)
        if !force, charts[key] != nil { return }
        guard !loadingCharts.contains(key) else { return }
        loadingCharts.insert(key)
        chartErrors[key] = nil
        defer { loadingCharts.remove(key) }
        do {
            charts[key] = try await service.chart(symbol: symbol, range: range)
            if range == .day, let quote = realtimeQuotes[symbol] { appendRealtimePoint(quote) }
        } catch is CancellationError {
            return
        } catch {
            chartErrors[key] = error.localizedDescription
        }
    }

    func preloadCharts(symbol: String) async {
        do { try await Task.sleep(for: .milliseconds(500)) }
        catch { return }
        for range in MarketRange.allCases where range.shouldPreload {
            guard !Task.isCancelled else { return }
            await loadChart(symbol: symbol, range: range)
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
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
        do {
            indexConstituents[symbol] = try await service.indexConstituents(symbol: symbol)
            constituentErrors[symbol] = nil
        } catch is CancellationError {
            return
        } catch {
            constituentErrors[symbol] = error.localizedDescription
        }
    }

    var latestQuoteDate: Date? {
        if let timestamp = dashboard?.freshness?.latestTimestamp, timestamp > 0 {
            return Date(timeIntervalSince1970: Double(timestamp) / 1000)
        }
        let quotes = (dashboard?.coreIndices ?? []) + (dashboard?.metrics ?? []) + (dashboard?.components ?? []) + (dashboard?.crypto ?? [])
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

    var realtimeIsFresh: Bool {
        guard realtimeStatus == .connected, let lastRealtimeMessageAt else { return false }
        return Date().timeIntervalSince(lastRealtimeMessageAt) < 30
    }

    var cachedSnapshotAge: TimeInterval? {
        guard isShowingCachedSnapshot, let cacheSavedAt else { return nil }
        return max(0, Date().timeIntervalSince(cacheSavedAt))
    }

    var maximumOpenMarketDelayMinutes: Int? {
        let quotes = (dashboard?.coreIndices ?? []) + (dashboard?.metrics ?? []) + (dashboard?.components ?? [])
        let seconds = quotes
            .filter { $0.marketSession == "regular" }
            .compactMap(\.delaySeconds)
            .max()
        guard let seconds, seconds > 0 else { return nil }
        return max(1, Int(ceil(Double(seconds) / 60)))
    }

    func quote(symbol: String) -> MarketQuote? {
        dashboard?.coreIndices.first(where: { $0.symbol == symbol })
            ?? dashboard?.metrics.first(where: { $0.symbol == symbol })
            ?? dashboard?.components.first(where: { $0.symbol == symbol })
            ?? dashboard?.crypto.first(where: { $0.symbol == symbol })
            ?? indexConstituents.values.lazy.flatMap(\.items).first(where: { $0.quote.symbol == symbol })?.quote
    }

    func constituent(symbol: String) -> MarketIndexConstituent? {
        indexConstituents.values.lazy.flatMap(\.items).first(where: { $0.quote.symbol == symbol })
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
            appendRealtimePoint(quote)
        }
        self.dashboard = dashboard
    }

    private func maintainFreshness(now: Date = Date()) async {
        let serverInterval = TimeInterval(dashboard?.refreshIntervalMs ?? 15_000) / 1_000
        let disconnected = realtimeStatus != .connected
        let messageIsStale = lastRealtimeMessageAt.map { now.timeIntervalSince($0) >= 30 } ?? true
        let desiredInterval = disconnected || messageIsStale ? max(15, serverInterval) : max(30, serverInterval * 2)
        guard now.timeIntervalSince(lastSnapshotRefreshAt ?? .distantPast) >= desiredInterval else { return }
        if messageIsStale, realtimeStatus == .connected { realtime.reconnect() }
        await refresh(force: false)
    }

    private func appendRealtimePoint(_ quote: MarketQuote) {
        let key = ChartKey(symbol: quote.symbol, range: .day)
        guard var chart = charts[key], let timestamp = quote.timestamp else { return }
        chart.points = marketMergingRealtimePrice(quote.price, timestamp: timestamp, into: chart.points)
        charts[key] = chart
    }
}

struct ChartKey: Hashable {
    let symbol: String
    let range: MarketRange
}

private enum MarketSnapshotCache {
    private static let key = "market.dashboard.cache.v1"

    struct Snapshot: Codable {
        let dashboard: MarketDashboard
        let savedAt: Date
    }

    static func load() -> Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) { return snapshot }
        guard let dashboard = try? JSONDecoder().decode(MarketDashboard.self, from: data) else { return nil }
        return Snapshot(dashboard: dashboard, savedAt: marketISODate(dashboard.generatedAt) ?? .distantPast)
    }

    static func save(_ dashboard: MarketDashboard, at date: Date) {
        guard let data = try? JSONEncoder().encode(Snapshot(dashboard: dashboard, savedAt: date)) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
