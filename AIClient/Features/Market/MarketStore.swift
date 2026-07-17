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

    private let service: MarketService
    private let realtime: MarketRealtimeClient
    private var loadedCache = false
    private var realtimeQuotes: [String: MarketQuote] = [:]

    init(baseURL: URL = ServerConfiguration.currentURL) {
        service = MarketService(baseURL: baseURL)
        realtime = MarketRealtimeClient(baseURL: baseURL)
    }

    func runUpdates() async {
        loadCacheIfNeeded()
        realtime.onQuote = { [weak self] update in
            guard var dashboard = self?.dashboard else { return }
            let quote = update.merging(into: self?.quote(symbol: update.symbol))
            dashboard.replace(quote)
            self?.dashboard = dashboard
            self?.mergeConstituent(update)
            if let mergedQuote = self?.quote(symbol: quote.symbol) {
                self?.realtimeQuotes[quote.symbol] = mergedQuote
                self?.appendRealtimePoint(mergedQuote)
            }
        }
        realtime.onStatus = { [weak self] status in self?.realtimeStatus = status }
        realtime.start()
        defer { realtime.stop() }
        await refresh(force: true)
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(3_600)) }
            catch { break }
        }
    }

    func refresh(force: Bool = true) async {
        if dashboard == nil { isLoading = true }
        defer { isLoading = false }
        do {
            var value = try await service.dashboard(refresh: force)
            guard !Task.isCancelled else { return }
            for quote in realtimeQuotes.values {
                let serverTimestamp = value.quote(symbol: quote.symbol)?.timestamp ?? 0
                if quote.timestamp ?? 0 >= serverTimestamp { value.replace(quote) }
            }
            dashboard = value
            errorMessage = value.missingSymbols.isEmpty ? nil : "部分行情暂未返回"
            MarketSnapshotCache.save(value)
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

    func loadIndexConstituents(symbol: String) async {
        if indexConstituents[symbol] != nil { return }
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
        dashboard = MarketSnapshotCache.load()
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

    static func load() -> MarketDashboard? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MarketDashboard.self, from: data)
    }

    static func save(_ dashboard: MarketDashboard) {
        guard let data = try? JSONEncoder().encode(dashboard) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
