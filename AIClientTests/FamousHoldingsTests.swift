import XCTest
@testable import AIServerClient

final class FamousHoldingsTests: XCTestCase {
    func testDecodesFamousHoldingsContract() throws {
        let data = Data(#"{"success":true,"data":{"generatedAt":"2026-07-16T00:00:00Z","reportDate":"2026-03-31","periodLabel":"2026 Q1","disclaimer":"公开披露数据，非实时交易","summary":{"new":1,"increased":2,"decreased":3,"exited":4},"managers":[{"key":"ark","cik":"0001697748","displayName":"凯茜·伍德","institutionName":"ARK Investment Management","reportDate":"2026-03-31","filingDate":"2026-05-12","positionsCount":182,"totalValueUsd":12859485476,"summary":{"new":1,"increased":2,"decreased":3,"exited":4},"changesCount":1,"changes":[{"symbol":"TSLA","name":"Tesla Inc","companyLogo":"/img/company-logos/tsla.png","action":"decreased","previousWeightPct":9.1,"weightPct":7.4,"weightChangePct":-1.7,"valueUsd":1000}]}]}}"#.utf8)
        let response = try JSONDecoder().decode(FamousHoldingsResponse.self, from: data)
        XCTAssertEqual(response.data.periodLabel, "2026 Q1")
        XCTAssertEqual(response.data.managers.first?.changes.first?.action, .decreased)
        XCTAssertEqual(response.data.managers.first?.changes.first?.weightPct, 7.4)
    }
}
