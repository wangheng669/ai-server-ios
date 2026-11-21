import Foundation
import Observation

@MainActor
@Observable
final class FamousHoldingsStore {
    private(set) var holdings: FamousHoldings?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var managerDetails: [FamousHoldingsReportIdentity: FamousHoldingsManager] = [:]
    private var detailErrors: [FamousHoldingsReportIdentity: String] = [:]
    @ObservationIgnored private var detailTasks: [FamousHoldingsReportIdentity: Task<Void, Never>] = [:]

    private let service: MarketService
    private var lastLoadedAt: Date?
    private var hasLoadedCache = false
    @ObservationIgnored private var overviewTask: Task<Void, Never>?

    init(baseURL: URL = ServerConfiguration.currentURL, session: URLSession? = nil) {
        service = MarketService(baseURL: baseURL, session: session)
    }

    func load(force: Bool = false) async {
        if let overviewTask {
            await overviewTask.value
            return
        }
        if !force, holdings != nil,
           let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < 5 * 60 { return }
        let task = Task { await refreshOverview() }
        overviewTask = task
        await task.value
    }

    private func refreshOverview() async {
        isLoading = true
        defer {
            isLoading = false
            overviewTask = nil
        }
        if !hasLoadedCache {
            let cached = await Task.detached(priority: .userInitiated) {
                FamousHoldingsCache.load()
            }.value
            guard !Task.isCancelled else { return }
            holdings = cached
            hasLoadedCache = true
        }
        do {
            let value = try await service.famousHoldings()
            guard !Task.isCancelled else { return }
            holdings = value
            lastLoadedAt = Date()
            await Task.detached(priority: .utility) { FamousHoldingsCache.save(value) }.value
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func detail(for manager: FamousHoldingsManager) -> FamousHoldingsManager? {
        managerDetails[manager.reportIdentity] ?? (manager.hasCompletePositions ? manager : nil)
    }

    func detailError(for manager: FamousHoldingsManager) -> String? {
        detailErrors[manager.reportIdentity]
    }

    func loadDetail(for manager: FamousHoldingsManager) async {
        let requested = manager.reportIdentity
        guard !Task.isCancelled, detail(for: manager) == nil else { return }
        if let task = detailTasks[requested] {
            await task.value
            return
        }
        detailErrors[requested] = nil
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetchDetail(requested)
        }
        detailTasks[requested] = task
        await task.value
    }

    private func fetchDetail(_ requested: FamousHoldingsReportIdentity) async {
        defer { detailTasks[requested] = nil }
        do {
            let payload = try await service.famousHoldings(managerKey: requested.managerKey)
            guard !Task.isCancelled else { return }
            guard let detail = payload.managers.first(where: { $0.reportIdentity.covers(requested) }),
                  detail.hasCompletePositions else {
                detailErrors[requested] = "完整持仓暂未返回"
                return
            }
            managerDetails[requested] = detail
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            detailErrors[requested] = NetworkErrorPresentation.message(for: error)
        }
    }
}

private enum FamousHoldingsCache {
    private static let payloadKey = "market.famous-holdings.cache.v3"
    private static let savedAtKey = "market.famous-holdings.cache.saved-at.v3"
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    static func load() -> FamousHoldings? {
        let defaults = UserDefaults.standard
        let savedAt = defaults.double(forKey: savedAtKey)
        guard savedAt > 0, Date().timeIntervalSince1970 - savedAt <= maxAge,
              let data = defaults.data(forKey: payloadKey) else { return nil }
        return try? JSONDecoder().decode(FamousHoldings.self, from: data)
    }

    static func save(_ holdings: FamousHoldings) {
        guard let data = try? JSONEncoder().encode(holdings) else { return }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: payloadKey)
        defaults.set(Date().timeIntervalSince1970, forKey: savedAtKey)
    }
}
