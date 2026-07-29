import XCTest
@testable import AIServerClient

final class CountryGDPRankingTests: XCTestCase {
    func testDecodesRankingAndLocalizesCountry() throws {
        let json = """
        {
          "success": true,
          "data": {
            "year": 2024,
            "metric": "GDP (current US$)",
            "unit": "USD",
            "source_name": "World Bank",
            "source_url": "https://data.worldbank.org/indicator/NY.GDP.MKTP.CD",
            "updated_at": "2026-07-29T10:00:00Z",
            "countries": [{
              "rank": 2,
              "country_code": "CHN",
              "iso2_code": "CN",
              "country_name": "China",
              "gdp_current_usd": 18729668435848
            }]
          }
        }
        """
        let payload = try JSONDecoder().decode(CountryGDPRankingResponse.self, from: Data(json.utf8))
        XCTAssertTrue(payload.success)
        XCTAssertEqual(payload.data.year, 2024)
        XCTAssertEqual(payload.data.countries.first?.countryCode, "CHN")
        XCTAssertEqual(payload.data.countries.first?.localizedName, "中国")
        XCTAssertEqual(payload.data.countries.first?.flag, "🇨🇳")
    }

    func testFormatsTrillionAndBillionValues() {
        XCTAssertEqual(CountryGDPFormat.compact(29_298_013_000_000), "29.30 万亿美元")
        XCTAssertEqual(CountryGDPFormat.compact(917_767_106_146), "9178 亿美元")
    }
}
