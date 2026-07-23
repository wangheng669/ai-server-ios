import XCTest
@testable import AIServerClient

final class MarketPresentationTests: XCTestCase {
    func testDecodesMarketChartQualityContract() throws {
        let data = Data(#"{"success":true,"data":{"symbol":"000001.SS","market":"CN","tradingDate":"2026-07-22","timezone":"Asia/Shanghai","session":"regular","interval":"1m","quality":{"status":"repairing","expected":120,"actual":119,"missing":[{"startTimestamp":1784691000000,"endTimestamp":1784691000000}],"freshnessSeconds":35,"isFinal":false},"quote":{"price":3883.58,"previousClose":3864.37,"change":19.21,"changePercent":0.5,"providerTimestamp":1784691000000,"receivedTimestamp":1784691005000,"source":"eastmoney"},"candles":[{"timestamp":1784683860000,"open":3839.67,"high":3845.42,"low":3839.67,"close":3845.42,"volume":18226640,"state":"confirmed","source":"eastmoney","session":"regular"}]}}"#.utf8)
        let response = try JSONDecoder().decode(MarketChartResponse.self, from: data)
        XCTAssertEqual(response.data.quality.status, .repairing)
        XCTAssertEqual(response.data.quality.missing.count, 1)
        XCTAssertEqual(response.data.candles.first?.state, "confirmed")
        XCTAssertEqual(response.data.candles.first?.session, "regular")
        XCTAssertEqual(response.data.tradingDate, "2026-07-22")
    }

    func testUnavailableEmptyStockChartRequestsAControlledRetry() throws {
        let data = Data(#"{"success":true,"data":{"symbol":"601398.SS","market":"CN","tradingDate":"2026-07-22","timezone":"Asia/Shanghai","session":"closed","interval":"1m","quality":{"status":"unavailable","expected":240,"actual":0,"missing":[],"freshnessSeconds":null,"isFinal":true},"quote":{"price":7.6,"previousClose":7.56,"change":0.04,"changePercent":0.53,"providerTimestamp":1784707014348,"receivedTimestamp":1784707014348,"source":"eastmoney"},"candles":[]}}"#.utf8)

        let response = try JSONDecoder().decode(MarketChartResponse.self, from: data)

        XCTAssertTrue(marketChartNeedsRetry(response.data))
        XCTAssertFalse(marketChartCanUseCache(response.data))
    }

    func testCryptoDisplayCodeUsesTradingPair() throws {
        let data = Data(#"{"symbol":"BINANCE:BTCUSDT","name":"比特币","price":64000}"#.utf8)
        let quote = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertEqual(quote.displayCode, "BTC/USDT")
    }

    func testShanghaiDisplayCodeUsesConsistentExchangeSuffix() throws {
        let data = Data(#"{"symbol":"000905.SS","name":"中证500","price":7000}"#.utf8)
        let quote = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertEqual(quote.displayCode, "000905.SH")
    }

    func testDashboardDecodesCryptoQuotes() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v2","generatedAt":"2026-07-16T10:00:00Z","refreshIntervalMs":15000,"coreIndices":[],"metrics":[],"components":[],"crypto":[{"symbol":"BINANCE:BTCUSDT","name":"比特币","price":79591.91,"previousClose":78000,"marketSession":"always-open","changePercent":"2.04%"}],"missingSymbols":[]}}"#.utf8)

        let response = try JSONDecoder().decode(MarketDashboardResponse.self, from: data)

        XCTAssertEqual(response.data.crypto.map(\.symbol), ["BINANCE:BTCUSDT"])
        XCTAssertEqual(response.data.quote(symbol: "BINANCE:BTCUSDT")?.name, "比特币")
        XCTAssertEqual(response.data.crypto.first?.freshnessLabel, "24小时交易")
    }

    func testDashboardDecodesPerSymbolHealthAndRegions() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v2","definitionVersion":"2026-07-21.1","generatedAt":"2026-07-21T10:00:00Z","refreshIntervalMs":15000,"coreIndices":[],"metrics":[],"components":[],"crypto":[],"missingSymbols":["JP10Y"],"expectedSymbols":["JP10Y","KR10Y"],"symbolHealth":[{"symbol":"JP10Y","status":"missing","reason":"quote_unavailable"},{"symbol":"KR10Y","status":"delayed","delaySeconds":15}],"regions":[{"id":"jp","metricSymbols":["USDJPY","JP10Y","^TOPX"]}]}}"#.utf8)

        let response = try JSONDecoder().decode(MarketDashboardResponse.self, from: data)

        XCTAssertEqual(response.data.definitionVersion, "2026-07-21.1")
        XCTAssertEqual(response.data.symbolHealth.first?.status, .missing)
        XCTAssertEqual(response.data.symbolHealth.last?.delaySeconds, 15)
        XCTAssertEqual(response.data.regions.first?.metricSymbols, ["USDJPY", "JP10Y", "^TOPX"])
    }

    func testDashboardDecodesChinaMarketStructureSignals() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v2","generatedAt":"2026-07-22T10:00:00Z","refreshIntervalMs":15000,"coreIndices":[],"metrics":[],"components":[],"crypto":[],"missingSymbols":[],"marketStructure":{"dataContract":"market_structure_v2","generatedAt":"2026-07-22T09:00:00Z","etfSubscription":{"fundCode":"588000","fundName":"科创50ETF合计","fundCount":8,"fundCodes":["588000","588080"],"asOf":"2026-07-21","status":"accelerating","latestShares":45512668200,"latestNetSubscriptionShares":423000000,"latestEstimatedNetFlowCNY":861429000,"estimatedFlowFundCount":8,"netSubscriptionShares5d":900000000,"previousNetShares5d":500000000,"positiveDays5d":4,"consecutiveDirection":"inflow","consecutiveDays":2,"points":[{"date":"2026-07-21","totalShares":45512668200,"netSubscriptionShares":423000000}]},"marginBalance":{"asOf":"2026-07-21","status":"stabilizing","financingBalance":2689521390293,"securitiesBalance":20402350759,"totalBalance":2709923741052,"latestChange":1086577120,"change3d":-1200000000,"change5d":-5100000000,"positiveDays5d":2,"financingBuyAmount":267012306205,"aShareTurnover":2960321000000,"financingBuyRatio":9.02,"activityStatus":"active","points":[{"date":"2026-07-21","financingBalance":2689521390293,"securitiesBalance":20402350759,"totalBalance":2709923741052,"dailyChange":1086577120,"financingBuyAmount":267012306205}]},"combinedSignal":{"status":"allocation_support","title":"配置资金承接，杠杆仍谨慎","summary":"ETF资金保持流入，但两融余额尚未企稳。"},"sources":[{"name":"上交所","url":"https://www.sse.com.cn/"}]}}}"#.utf8)

        let response = try JSONDecoder().decode(MarketDashboardResponse.self, from: data)

        XCTAssertEqual(response.data.marketStructure?.etfSubscription.status, "accelerating")
        XCTAssertEqual(response.data.marketStructure?.etfSubscription.consecutiveDays, 2)
        XCTAssertEqual(response.data.marketStructure?.etfSubscription.fundCount, 8)
        XCTAssertEqual(response.data.marketStructure?.etfSubscription.latestEstimatedNetFlowCNY, 861_429_000)
        XCTAssertEqual(response.data.marketStructure?.marginBalance.status, "stabilizing")
        XCTAssertEqual(response.data.marketStructure?.marginBalance.financingBuyRatio, 9.02)
        XCTAssertEqual(response.data.marketStructure?.combinedSignal?.status, "allocation_support")
        XCTAssertEqual(response.data.marketStructure?.marginBalance.points.first?.dailyChange, 1_086_577_120)
    }

    func testMarginStatusMapsToReadableLeverageRiskAppetite() {
        XCTAssertEqual(MarketLeverageRiskAppetite(status: "declining"), .weak)
        XCTAssertEqual(MarketLeverageRiskAppetite(status: "stabilizing"), .repairing)
        XCTAssertEqual(MarketLeverageRiskAppetite(status: "recovering"), .strong)
        XCTAssertEqual(MarketLeverageRiskAppetite(status: "mixed"), .uncertain)
    }

    func testDashboardDoesNotPresentStaleAShareBreadthAsCurrent() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v2","generatedAt":"2026-07-22T10:00:00Z","refreshIntervalMs":15000,"coreIndices":[],"metrics":[],"components":[],"crypto":[],"missingSymbols":[],"ashareOverview":{"breadth":{"Up":2219,"Down":3202,"Flat":94,"Total":5515},"hotSectors":[],"stale":true}}}"#.utf8)

        let response = try JSONDecoder().decode(MarketDashboardResponse.self, from: data)

        XCTAssertTrue(response.data.ashareOverview?.stale == true)
        XCTAssertNil(response.data.currentAShareBreadth)
    }

    func testDelayedOpenMarketQuoteExplainsSourceDelay() throws {
        let data = Data(#"{"symbol":"^NDX","name":"纳斯达克100","price":23000,"marketSession":"regular","delaySeconds":900}"#.utf8)
        let quote = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertEqual(quote.freshnessLabel, "延迟15分钟")
    }

    func testHealthSummaryNamesMissingSymbols() {
        let issues = [
            MarketSymbolHealth(symbol: "932000.SS", status: .missing, asOf: nil, timestamp: nil, source: nil, delaySeconds: nil, reason: "quote_unavailable"),
            MarketSymbolHealth(symbol: "THS:883418", status: .missing, asOf: nil, timestamp: nil, source: nil, delaySeconds: nil, reason: "quote_unavailable"),
            MarketSymbolHealth(symbol: "^TOPX", status: .missing, asOf: nil, timestamp: nil, source: nil, delaySeconds: nil, reason: "quote_unavailable")
        ]

        XCTAssertEqual(marketHealthSummary(issues), "部分行情暂缺：中证2000、微盘股、东证指数")
    }

    func testHealthSummaryKeepsNamesWhenThereAreMoreThanThreeIssues() {
        let issues = [
            MarketSymbolHealth(symbol: "932000.SS", status: .missing, asOf: nil, timestamp: nil, source: nil, delaySeconds: nil, reason: nil),
            MarketSymbolHealth(symbol: "THS:883418", status: .missing, asOf: nil, timestamp: nil, source: nil, delaySeconds: nil, reason: nil),
            MarketSymbolHealth(symbol: "^TOPX", status: .missing, asOf: nil, timestamp: nil, source: nil, delaySeconds: nil, reason: nil),
            MarketSymbolHealth(symbol: "JP10Y", status: .stale, asOf: nil, timestamp: nil, source: nil, delaySeconds: nil, reason: nil)
        ]

        XCTAssertEqual(marketHealthSummary(issues), "部分行情缺失或延迟：中证2000、微盘股、东证指数等 4 项")
    }

    func testPeriodTrendUsesSelectedRangeValues() {
        XCTAssertTrue(marketTrendIsUp(values: [100, 98, 104], fallbackIsUp: false))
        XCTAssertFalse(marketTrendIsUp(values: [100, 103, 97], fallbackIsUp: true))
    }

    func testPeriodTrendFallsBackWhenRangeHasNoDirection() {
        XCTAssertTrue(marketTrendIsUp(values: [], fallbackIsUp: true))
        XCTAssertFalse(marketTrendIsUp(values: [100], fallbackIsUp: false))
        XCTAssertTrue(marketTrendIsUp(values: [100, 100], fallbackIsUp: true))
    }

    func testLiveTrendAppendsDistinctPricesAndKeepsLimit() {
        XCTAssertEqual(marketAppendingLiveValue(101, to: [100, 101]), [100, 101])
        XCTAssertEqual(marketAppendingLiveValue(103, to: [100, 101, 102], limit: 3), [101, 102, 103])
    }

    func testRealtimeNightQuoteDecodesAsIncrementAndAppendsNightPrice() throws {
        let data = Data(#"{"symbol":"NVDA","name":"英伟达","price":212.5,"previousClose":211.8,"marketSession":"overnight","isNightSession":true,"sessionPrice":212.49,"sessionChangePercent":0.3257,"timestamp":1784174184396}"#.utf8)
        let update = try JSONDecoder().decode(MarketQuoteUpdate.self, from: data)
        let quote = update.merging(into: nil)

        XCTAssertEqual(quote.symbol, "NVDA")
        XCTAssertEqual(quote.sessionPrice, 212.49)
        XCTAssertEqual(quote.nightTrend, [212.49])
        XCTAssertTrue(quote.isNightSession == true)
    }

    func testRealtimeUpdatePreservesConstituentNightTrend() throws {
        let responseData = Data(#"{"indexSymbol":"^NDX","label":"主要成分股","selectionBasis":"test","asOf":"2026-07-16","generatedAt":"2026-07-16T05:00:00Z","items":[{"rank":1,"weight":null,"logoPath":null,"quote":{"symbol":"NVDA","name":"英伟达","price":212.5,"previousClose":211.8,"isNightSession":true,"sessionPrice":212.49,"timestamp":1784174184000,"trend":[210,211],"nightTrend":[212.1,212.2,212.3]}}],"missingSymbols":[]}"#.utf8)
        let updateData = Data(#"{"symbol":"NVDA","name":"英伟达","price":212.5,"previousClose":211.8,"marketSession":"overnight","isNightSession":true,"sessionPrice":212.49,"sessionChangePercent":0.3257,"timestamp":1784174184396}"#.utf8)
        var constituents = try JSONDecoder().decode(MarketIndexConstituents.self, from: responseData)
        let update = try JSONDecoder().decode(MarketQuoteUpdate.self, from: updateData)

        constituents.merge(update)

        XCTAssertEqual(constituents.items[0].quote.nightTrend, [212.1, 212.2, 212.3, 212.49])
        XCTAssertEqual(constituents.items[0].quote.trend, [210, 211, 212.5])
    }

    func testMarketRangesUseExpectedIntervalsAndLimits() {
        XCTAssertEqual(MarketRange.day.apiInterval, "1m")
        XCTAssertEqual(MarketRange.week.apiRange, "5d")
        XCTAssertEqual(MarketRange.week.apiInterval, "1d")
        XCTAssertEqual(MarketRange.week.apiLimit, 8)
        XCTAssertEqual(MarketRange.month.apiInterval, "1d")
        XCTAssertEqual(MarketRange.fiveYears.apiLimit, 600)
        XCTAssertEqual(MarketRange.maximum.apiLimit, 600)
    }

    func testAxisDigitsKeepSmallVIXMovesVisible() {
        XCTAssertEqual(marketAxisDigits(values: [15.77, 16.54]), 2)
        XCTAssertEqual(marketAxisDigits(values: [4_900, 4_950]), 0)
    }

    func testCandlesAggregateWithoutLosingOHLCBounds() {
        let points = [
            chartPoint(timestamp: 1, open: 10, high: 13, low: 9, close: 12, volume: 4),
            chartPoint(timestamp: 2, open: 12, high: 15, low: 11, close: 14, volume: 6)
        ]
        let candle = marketCandleSamples(points, maxCount: 1).first
        XCTAssertEqual(candle, MarketCandleSample(timestamp: 2, open: 10, high: 15, low: 9, close: 14, volume: 10))
    }

    private func chartPoint(
        timestamp: Int64,
        open: Double? = nil,
        high: Double? = nil,
        low: Double? = nil,
        close: Double,
        volume: Double? = nil
    ) -> MarketChartPoint {
        MarketChartPoint(
            timestamp: timestamp,
            open: open ?? close,
            high: high ?? close,
            low: low ?? close,
            close: close,
            volume: volume,
            state: "confirmed",
            source: "test",
            session: "regular"
        )
    }
}
