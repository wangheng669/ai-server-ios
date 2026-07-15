import Foundation
import Observation

@MainActor
@Observable
final class MarketStore {
    private(set) var dashboard: MarketDashboard?
    private(set) var charts: [ChartKey: MarketChart] = [:]
    private(set) var loadingCharts: Set<ChartKey> = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdatedAt: Date?

    private let service: MarketService
    private let realtime: MarketRealtimeClient
    private var loadedCache = false

    init(baseURL: URL = ServerConfiguration.currentURL) {
        service = MarketService(baseURL: baseURL)
        realtime = MarketRealtimeClient(baseURL: baseURL)
    }

    func runUpdates() async {
        loadCacheIfNeeded()
        realtime.onQuote = { [weak self] quote in
            guard var dashboard = self?.dashboard else { return }
            dashboard.replace(quote)
            self?.dashboard = dashboard
            self?.lastUpdatedAt = Date()
        }
        realtime.start()
        defer { realtime.stop() }

        var firstLoad = true
        while !Task.isCancelled {
            await refresh(force: firstLoad)
            firstLoad = false
            let milliseconds = max(dashboard?.refreshIntervalMs ?? 15_000, 5_000)
            try? await Task.sleep(for: .milliseconds(milliseconds))
        }
    }

    func refresh(force: Bool = true) async {
        if dashboard == nil { isLoading = true }
        defer { isLoading = false }
        do {
            let value = try await service.dashboard(refresh: force)
            guard !Task.isCancelled else { return }
            dashboard = value
            lastUpdatedAt = Date()
            errorMessage = value.missingSymbols.isEmpty ? nil : "部分行情暂未返回"
            MarketSnapshotCache.save(value)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadChart(symbol: String, range: MarketRange) async {
        let key = ChartKey(symbol: symbol, range: range)
        guard !loadingCharts.contains(key) else { return }
        loadingCharts.insert(key)
        defer { loadingCharts.remove(key) }
        do {
            charts[key] = try await service.chart(symbol: symbol, range: range)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chart(symbol: String, range: MarketRange) -> MarketChart? {
        charts[ChartKey(symbol: symbol, range: range)]
    }

    func quote(symbol: String) -> MarketQuote? {
        dashboard?.coreIndices.first(where: { $0.symbol == symbol })
            ?? dashboard?.metrics.first(where: { $0.symbol == symbol })
            ?? dashboard?.components.first(where: { $0.symbol == symbol })
    }

    private func loadCacheIfNeeded() {
        guard !loadedCache else { return }
        loadedCache = true
        dashboard = MarketSnapshotCache.load()
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
