import XCTest
@testable import AIServerClient

final class CountryGDPRankingTests: XCTestCase {
    func testDecodesRankingAndLocalizesCountry() throws {
        let json = """
        {
          "success": true,
          "data": {
            "year": 2024,
            "previous_year": 2023,
            "metric": "GDP (current US$)",
            "unit": "USD",
            "source_name": "World Bank",
            "source_url": "https://data.worldbank.org/indicator/NY.GDP.MKTP.CD",
            "updated_at": "2026-07-29T10:00:00Z",
            "countries": [{
              "rank": 2,
              "previous_rank": 3,
              "rank_change": 1,
              "country_code": "CHN",
              "iso2_code": "CN",
              "country_name": "China",
              "gdp_current_usd": 18729668435848,
              "previous_gdp_current_usd": 17729668435848,
              "gdp_growth_percent": 5.64
            }]
          }
        }
        """
        let payload = try JSONDecoder().decode(CountryGDPRankingResponse.self, from: Data(json.utf8))
        XCTAssertTrue(payload.success)
        XCTAssertEqual(payload.data.year, 2024)
        XCTAssertEqual(payload.data.previousYear, 2023)
        XCTAssertEqual(payload.data.countries.first?.countryCode, "CHN")
        XCTAssertEqual(payload.data.countries.first?.localizedName, "中国")
        XCTAssertEqual(payload.data.countries.first?.flag, "🇨🇳")
        XCTAssertEqual(payload.data.countries.first?.rankChange, 1)
        XCTAssertEqual(payload.data.countries.first?.gdpGrowthPercent, 5.64)
    }

    func testFormatsTrillionAndBillionValues() {
        XCTAssertEqual(CountryGDPFormat.compact(29_298_013_000_000), "29.30 万亿美元")
        XCTAssertEqual(CountryGDPFormat.compact(917_767_106_146), "9178 亿美元")
    }

    func testDecodesCountryHistory() throws {
        let json = """
        {
          "success": true,
          "data": {
            "country_code": "CHN",
            "iso2_code": "CN",
            "country_name": "China",
            "metric": "GDP (current US$)",
            "unit": "USD",
            "source_name": "World Bank",
            "source_url": "https://data.worldbank.org/indicator/NY.GDP.MKTP.CD",
            "updated_at": "2026-07-29T10:00:00Z",
            "points": [
              {"year": 2023, "rank": 2, "gdp_current_usd": 17729668435848},
              {"year": 2024, "rank": 2, "gdp_current_usd": 18729668435848}
            ]
          }
        }
        """
        let payload = try JSONDecoder().decode(CountryGDPHistoryResponse.self, from: Data(json.utf8))
        XCTAssertEqual(payload.data.countryCode, "CHN")
        XCTAssertEqual(payload.data.points.count, 2)
        XCTAssertEqual(payload.data.points.last?.rank, 2)
    }

    func testChartDragMapsToNearestYearAndClampsEdges() {
        XCTAssertNil(CountryGDPChartInteraction.nearestIndex(progress: 0.5, count: 0))
        XCTAssertEqual(CountryGDPChartInteraction.nearestIndex(progress: -0.2, count: 12), 0)
        XCTAssertEqual(CountryGDPChartInteraction.nearestIndex(progress: 0, count: 12), 0)
        XCTAssertEqual(CountryGDPChartInteraction.nearestIndex(progress: 0.49, count: 12), 5)
        XCTAssertEqual(CountryGDPChartInteraction.nearestIndex(progress: 0.51, count: 12), 6)
        XCTAssertEqual(CountryGDPChartInteraction.nearestIndex(progress: 1, count: 12), 11)
        XCTAssertEqual(CountryGDPChartInteraction.nearestIndex(progress: 1.2, count: 12), 11)
    }
}
