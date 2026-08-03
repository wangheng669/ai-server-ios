import XCTest
@testable import AIServerClient

final class CountryGDPRankingTests: XCTestCase {
    func testGlobalRankingCategories() {
        XCTAssertEqual(
            GlobalRankingCategory.allCases.map(\.rawValue),
            ["国家 GDP", "全球资产"]
        )
    }

    func testDecodesDatabaseBackedGlobalAssetsRanking() throws {
        let json = """
        {
          "success": true,
          "data": {
            "source_name": "CoinGlass",
            "source_url": "https://www.coinglass.com/zh/global-assets",
            "unit": "USD",
            "fetched_at": "2026-07-31T12:00:00Z",
            "assets": [{
              "rank": 1,
              "symbol": "GOLD",
              "name": "黄金",
              "market_cap_usd": 28510000000000,
              "price_usd": 4100.9,
              "change_24h_percent": -1.43,
              "change_7d_percent": 1.11,
              "icon_url": "https://cdn.coinglasscdn.com/marketCap/rank/GOLD.png"
            }]
          }
        }
        """
        let payload = try JSONDecoder().decode(GlobalAssetsRankingResponse.self, from: Data(json.utf8))
        XCTAssertTrue(payload.success)
        XCTAssertEqual(payload.data.sourceName, "CoinGlass")
        XCTAssertEqual(payload.data.assets.first?.symbol, "GOLD")
        XCTAssertEqual(payload.data.assets.first?.marketCapUSD, 28_510_000_000_000)
        XCTAssertEqual(GlobalAssetsFormat.marketCap(28_510_000_000_000), "$28.51 万亿")
    }

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

    func testMergesServerMacroObservationsByYear() {
        let merged = ChinaMacroService.merge([
            .init(metricKey: "gdp_growth", period: "2024", value: 5.0),
            .init(metricKey: "unemployment", period: "2024", value: 4.6),
            .init(metricKey: "inflation", period: "2024", value: 0.2),
            .init(metricKey: "inflation", period: "2023", value: 0.1),
            .init(metricKey: "lending_rate", period: "2024", value: 4.35),
            .init(metricKey: "deposit_rate", period: "2024", value: 1.5),
            .init(metricKey: "mortgage_rate", period: "2024", value: 3.6),
            .init(metricKey: "household_leverage", period: "2024", value: 60.0),
            .init(metricKey: "debt_service_ratio", period: "2024", value: 18.8),
            .init(metricKey: "income_surplus_rate", period: "2024", value: 31.68),
            .init(metricKey: "consumer_confidence", period: "2024", value: 86.0),
            .init(metricKey: "electricity_total_growth", period: "2024", value: 6.8),
            .init(metricKey: "electricity_secondary_growth", period: "2024", value: 5.1),
            .init(metricKey: "private_credit", period: "2023", value: 194.2),
            .init(metricKey: "unknown_future_metric", period: "2025", value: 1)
        ])
        XCTAssertEqual(merged.map(\.year), [2024, 2023])
        XCTAssertEqual(merged[0].gdpGrowth, 5.0)
        XCTAssertEqual(merged[0].unemployment, 4.6)
        XCTAssertEqual(merged[0].inflation, 0.2)
        XCTAssertEqual(merged[0].lendingRate, 4.35)
        XCTAssertEqual(merged[0].depositRate, 1.5)
        XCTAssertEqual(merged[0].mortgageRate, 3.6)
        XCTAssertEqual(merged[0].householdLeverage, 60.0)
        XCTAssertEqual(merged[0].debtServiceRatio, 18.8)
        XCTAssertEqual(merged[0].incomeSurplusRate, 31.68)
        XCTAssertEqual(merged[0].consumerConfidence, 86.0)
        XCTAssertEqual(merged[0].electricityTotalGrowth, 6.8)
        XCTAssertEqual(merged[0].electricitySecondaryGrowth, 5.1)
        XCTAssertNil(merged[0].privateCredit)
        XCTAssertEqual(merged[1].privateCredit, 194.2)
    }

    func testParsesNanosecondServerTimestamp() throws {
        let date = try XCTUnwrap(ChinaMacroService.parseServerTimestamp("2026-08-03T09:19:44.326408874Z"))
        XCTAssertEqual(date.timeIntervalSince1970, 1_785_748_784.3264089, accuracy: 0.001)
    }
}
