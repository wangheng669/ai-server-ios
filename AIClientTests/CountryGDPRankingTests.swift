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

    func testDecodesWorldBankIndicatorAndPreservesMissingYears() throws {
        let json = """
        [
          {"page":1,"pages":1,"per_page":100,"total":2},
          [
            {"date":"2025","value":0.0595646916565403},
            {"date":"2024","value":null}
          ]
        ]
        """
        let response = try JSONDecoder().decode(WorldBankIndicatorResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.points.count, 2)
        XCTAssertEqual(response.points[0].year, 2025)
        XCTAssertEqual(response.points[0].value, 0.0595646916565403)
        XCTAssertNil(response.points[1].value)
    }

    func testMergesChinaMacroSeriesByYear() throws {
        func points(_ json: String) throws -> [WorldBankIndicatorPoint] {
            try JSONDecoder().decode(
                WorldBankIndicatorResponse.self,
                from: Data("[{\"page\":1},\(json)]".utf8)
            ).points
        }
        let merged = ChinaMacroService.merge(
            inflation: try points("[{\"date\":\"2024\",\"value\":0.2},{\"date\":\"2023\",\"value\":0.1}]"),
            lendingRate: try points("[{\"date\":\"2024\",\"value\":4.35}]"),
            depositRate: try points("[{\"date\":\"2024\",\"value\":1.5}]"),
            mortgageRate: try points("[{\"date\":\"2024\",\"value\":3.6}]"),
            privateCredit: try points("[{\"date\":\"2023\",\"value\":194.2}]")
        )
        XCTAssertEqual(merged.map(\.year), [2024, 2023])
        XCTAssertEqual(merged[0].inflation, 0.2)
        XCTAssertEqual(merged[0].lendingRate, 4.35)
        XCTAssertEqual(merged[0].depositRate, 1.5)
        XCTAssertEqual(merged[0].mortgageRate, 3.6)
        XCTAssertNil(merged[0].privateCredit)
        XCTAssertEqual(merged[1].privateCredit, 194.2)
    }

    func testParsesPBCLPRAnnouncementsAndFiveYearRate() throws {
        let listing = """
        <a href="/rates/20260720/index.html" title="2026年7月20日全国银行间同业拆借中心受权公布贷款市场报价利率（LPR）公告">公告</a>
        <a href='/rates/20260622/index.html' title='2026年6月22日全国银行间同业拆借中心受权公布贷款市场报价利率（LPR）公告'>公告</a>
        """
        let root = try XCTUnwrap(URL(string: "https://www.pbc.gov.cn"))
        let announcements = ChinaMacroService.parsePBCLPRAnnouncements(html: listing, rootURL: root)
        XCTAssertEqual(announcements.count, 2)
        XCTAssertEqual(announcements[0].dateKey, 20260720)
        XCTAssertEqual(announcements[0].url.absoluteString, "https://www.pbc.gov.cn/rates/20260720/index.html")

        let detail = "1年期LPR为3.0%，5年期以上LPR为3.5%。以上LPR在下一次发布LPR之前有效。"
        XCTAssertEqual(ChinaMacroService.parseFiveYearLPR(html: detail), 3.5)
    }

    func testAddsMortgageRatesWithoutDiscardingLoadedMacroData() {
        let base = [ChinaMacroYear(
            year: 2026,
            inflation: 0.4,
            lendingRate: 3.1,
            depositRate: 1.2,
            mortgageRate: nil,
            privateCredit: 180
        )]
        let result = ChinaMacroService.mergingMortgage(
            [WorldBankIndicatorPoint(year: 2026, value: 3.5)],
            into: base
        )
        XCTAssertEqual(result[0].inflation, 0.4)
        XCTAssertEqual(result[0].depositRate, 1.2)
        XCTAssertEqual(result[0].mortgageRate, 3.5)
    }
}
