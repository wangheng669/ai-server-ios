import XCTest
@testable import AIServerClient

final class RetailSentimentRefreshTests: XCTestCase {
    private func board(stale: Bool? = nil) throws -> InvestorMoodBoard {
        let items: [[String: Any]] = stale.map { [["nickname": "样本账号", "awemeId": "123", "description": "股票观点", "stale": $0]] } ?? []
        let data = try JSONSerialization.data(withJSONObject: [
            "dataContract": "market_investor_mood_v1", "generatedAt": "2026-09-07T07:00:00Z",
            "methodology": "public-video-sample", "disclaimer": "公开视频样本", "items": items
        ])
        return try JSONDecoder().decode(InvestorMoodBoard.self, from: data)
    }

    @MainActor
    func testEmptyAndStaleResultsCanRecoverWithoutRestart() async throws {
        for previous in [try board(), try board(stale: true)] {
            let fresh = try board(stale: false)
            var requests = 0
            let store = RetailSentimentStore(investorMoodLoader: {
                requests += 1
                return requests == 1 ? previous : fresh
            })
            await store.refreshInvestorMood()
            await store.refreshInvestorMood()
            XCTAssertEqual(requests, 2)
            XCTAssertEqual(store.investorMood?.items.first?.stale, false)
        }
    }

    @MainActor
    func testFreshResultsAreThrottledButManualRefreshIsAllowed() async throws {
        let fresh = try board(stale: false)
        var requests = 0
        let store = RetailSentimentStore(investorMoodLoader: { requests += 1; return fresh })
        await store.refreshInvestorMood()
        await store.refreshInvestorMood()
        XCTAssertEqual(requests, 1)
        await store.refreshInvestorMood(force: true)
        XCTAssertEqual(requests, 2)
    }

    @MainActor
    func testRequestFailureDoesNotPermanentlyCacheAnEmptyState() async throws {
        let fresh = try board(stale: false)
        var requests = 0
        let store = RetailSentimentStore(investorMoodLoader: {
            requests += 1
            if requests == 1 { throw URLError(.notConnectedToInternet) }
            return fresh
        })
        await store.refreshInvestorMood()
        XCTAssertNotNil(store.investorMoodErrorMessage)
        XCTAssertFalse(store.isLoadingInvestorMood)
        await store.refreshInvestorMood()
        XCTAssertEqual(store.investorMood?.items.count, 1)
        XCTAssertNil(store.investorMoodErrorMessage)
    }

    @MainActor
    func testFailedRefreshPreservesPreviouslyLoadedSamples() async throws {
        let fresh = try board(stale: false)
        var requests = 0
        let store = RetailSentimentStore(investorMoodLoader: {
            requests += 1
            if requests > 1 { throw URLError(.timedOut) }
            return fresh
        })
        await store.refreshInvestorMood()
        await store.refreshInvestorMood(force: true)
        XCTAssertEqual(store.investorMood?.items.count, 1)
        XCTAssertNotNil(store.investorMoodErrorMessage)
    }
}
