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

    init(baseURL: URL = ServerConfiguration.currentURL) {
        service = MarketService(baseURL: baseURL)
    }

    func load(force: Bool = false) async {
        if !force, holdings != nil { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            holdings = try await service.famousHoldings()
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
