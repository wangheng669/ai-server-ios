import Foundation
import Observation

@MainActor
@Observable
final class FamousHoldingsStore {
    private(set) var holdings: FamousHoldings?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var managerDetails: [String: FamousHoldingsManager] = [:]
    private(set) var loadingManagerKeys: Set<String> = []

    private let service: MarketService
    private var hasLoadedFromNetwork = false

    init(baseURL: URL = ServerConfiguration.currentURL) {
        service = MarketService(baseURL: baseURL)
        holdings = FamousHoldingsCache.load()
    }

    func load(force: Bool = false) async {
        if !force, hasLoadedFromNetwork { return }
        if !force, holdings != nil, FamousHoldingsCache.isFreshForNetworkRefresh() { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let value = try await service.famousHoldings()
            holdings = value
            hasLoadedFromNetwork = true
            FamousHoldingsCache.save(value)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadDetail(managerKey: String) async {
        guard managerDetails[managerKey] == nil, !loadingManagerKeys.contains(managerKey) else { return }
        loadingManagerKeys.insert(managerKey)
        defer { loadingManagerKeys.remove(managerKey) }
        do {
            let payload = try await service.famousHoldings(managerKey: managerKey)
            if let manager = payload.managers.first { managerDetails[managerKey] = manager }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum FamousHoldingsCache {
    private static let payloadKey = "market.famous-holdings.cache.v1"
    private static let savedAtKey = "market.famous-holdings.cache.saved-at.v1"
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    private static let networkRefreshInterval: TimeInterval = 6 * 60 * 60

    static func isFreshForNetworkRefresh() -> Bool {
        let savedAt = UserDefaults.standard.double(forKey: savedAtKey)
        return savedAt > 0 && Date().timeIntervalSince1970 - savedAt <= networkRefreshInterval
    }

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
