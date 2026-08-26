import Foundation
import SwiftUI

struct VolatilityResearchResponse: Decodable {
    let data: VolatilityResearchPayload
}

struct VolatilityResearchPayload: Decodable {
    let generatedAt: Date
    let lookbackDays: Int
    let summary: String
    let items: [VolatilityResearchInstrument]
    let isStale: Bool
}

struct VolatilityResearchInstrument: Decodable, Identifiable, Hashable {
    let id: String
    let market: String
    let name: String
    let shortName: String
    let value: Double
    let previousClose: Double
    let dailyChangePercent: Double
    let peakValue: Double
    let peakDate: String
    let drawdownFromPeakPercent: Double
    let asOf: String
    let regime: String
    let interpretation: String
    let history: [VolatilityResearchPoint]
    let source: VolatilityResearchSource
}

struct VolatilityResearchPoint: Decodable, Hashable, Identifiable {
    let date: String
    let value: Double

    var id: String { date }
}

struct VolatilityResearchSource: Decodable, Hashable {
    let title: String
    let url: URL
}

struct VolatilityResearchService {
    var baseURL: URL = ServerConfiguration.currentURL
    var session: URLSession = .shared

    func fetch() async throws -> VolatilityResearchPayload {
        let url = baseURL.appending(path: "api/ios/v1/market/volatility-research")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VolatilityResearchResponse.self, from: data).data
    }
}

@MainActor
final class VolatilityResearchStore: ObservableObject {
    @Published private(set) var payload: VolatilityResearchPayload?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let fetch: () async throws -> VolatilityResearchPayload

    init(service: VolatilityResearchService = VolatilityResearchService()) {
        fetch = { try await service.fetch() }
    }

    init(fetch: @escaping () async throws -> VolatilityResearchPayload) {
        self.fetch = fetch
    }

    func load(force: Bool = false) async {
        guard !isLoading, force || payload == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            payload = try await fetch()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "波动率数据暂时无法载入"
        }
    }
}
