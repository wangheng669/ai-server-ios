import XCTest
@testable import AIServerClient

final class MarketPresentationTests: XCTestCase {
    func testCryptoDisplayCodeUsesTradingPair() throws {
        let data = Data(#"{"symbol":"BINANCE:BTCUSDT","name":"比特币","price":64000}"#.utf8)
        let quote = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertEqual(quote.displayCode, "BTC/USDT")
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
        XCTAssertEqual(MarketRange.fiveYears.apiLimit, 1_000)
        XCTAssertEqual(MarketRange.maximum.apiLimit, 1_000)
        XCTAssertTrue(MarketRange.year.shouldPreload)
        XCTAssertTrue(MarketRange.fiveYears.shouldPreload)
        XCTAssertTrue(MarketRange.maximum.shouldPreload)
    }

    func testDayRangeKeepsOnlyLatestTradingSession() {
        let hour: Int64 = 60 * 60 * 1_000
        let points = [
            chartPoint(timestamp: 1, close: 100),
            chartPoint(timestamp: 1 + hour, close: 101),
            chartPoint(timestamp: 8 * hour, close: 102),
            chartPoint(timestamp: 9 * hour, close: 103)
        ]
        XCTAssertEqual(marketPointsForRange(points, range: .day).map(\.timestamp), [8 * hour, 9 * hour])
    }

    func testDayRangePrefersLatestSessionEvenWhenItHasFewerPoints() {
        let hour: Int64 = 60 * 60 * 1_000
        let historical = (0..<20).map { chartPoint(timestamp: Int64($0) * 60_000, close: Double($0)) }
        let realtimeTail = [
            chartPoint(timestamp: 8 * hour, close: 100),
            chartPoint(timestamp: 8 * hour + 60_000, close: 101)
        ]
        XCTAssertEqual(marketPointsForRange(historical + realtimeTail, range: .day), realtimeTail)
    }

    func testAxisDigitsKeepSmallVIXMovesVisible() {
        XCTAssertEqual(marketAxisDigits(values: [15.77, 16.54]), 2)
        XCTAssertEqual(marketAxisDigits(values: [4_900, 4_950]), 0)
    }

    func testDayChartUsesQuoteTrendWhenLatestSessionHasOnlyOneMinute() {
        let timestamp: Int64 = 10 * 60_000
        let point = chartPoint(timestamp: timestamp, close: 16.11)

        let result = marketDisplayPoints(
            [point],
            range: .day,
            fallbackValues: [15.82, 16.30, 16.11],
            fallbackTimestamp: timestamp
        )

        XCTAssertEqual(result.map(\.displayValue), [15.82, 16.30, 16.11])
        XCTAssertEqual(result.map(\.timestamp), [8 * 60_000, 9 * 60_000, 10 * 60_000])
    }

    func testDayChartUsesSameQuoteTrendAsMarketCardEvenWithCurrentChartPoints() {
        let points = [
            chartPoint(timestamp: 9 * 60_000, close: 16.08),
            chartPoint(timestamp: 10 * 60_000, close: 16.11)
        ]

        let result = marketDisplayPoints(
            points,
            range: .day,
            fallbackValues: [15.82, 16.30],
            fallbackTimestamp: 10 * 60_000
        )

        XCTAssertEqual(result.map(\.displayValue), [15.82, 16.30])
        XCTAssertEqual(result.map(\.timestamp), [9 * 60_000, 10 * 60_000])
    }

    func testDayChartUsesQuoteTrendWhenTimestampedChartIsFromPreviousSession() {
        let hour: Int64 = 60 * 60 * 1_000
        let stalePoints = [
            chartPoint(timestamp: hour, close: 16.40),
            chartPoint(timestamp: 2 * hour, close: 16.07)
        ]

        let result = marketDisplayPoints(
            stalePoints,
            range: .day,
            fallbackValues: [16.50, 16.20, 16.07],
            fallbackTimestamp: 8 * hour
        )

        XCTAssertEqual(result.map(\.displayValue), [16.50, 16.20, 16.07])
        XCTAssertEqual(result.last?.timestamp, 8 * hour)
    }

    func testDayChartDoesNotSubstituteAnotherSourceWhenCardTrendIsUnavailable() {
        let chartPoints = [
            chartPoint(timestamp: 9 * 60_000, close: 16.08),
            chartPoint(timestamp: 10 * 60_000, close: 16.11)
        ]

        XCTAssertTrue(marketDisplayPoints(
            chartPoints,
            range: .day,
            fallbackValues: [],
            fallbackTimestamp: nil
        ).isEmpty)
        XCTAssertTrue(marketDisplayPoints(
            chartPoints,
            range: .day,
            fallbackValues: [16.11],
            fallbackTimestamp: 10 * 60_000
        ).isEmpty)
    }

    func testWeekRangeKeepsFiveLatestTradingDays() {
        let day: Int64 = 24 * 60 * 60 * 1_000
        let points = (1...7).map { chartPoint(timestamp: Int64($0) * day, close: Double($0)) }
        XCTAssertEqual(marketPointsForRange(points, range: .week).map(\.timestamp), (3...7).map { Int64($0) * day })
    }

    func testCandlesAggregateWithoutLosingOHLCBounds() {
        let points = [
            chartPoint(timestamp: 1, open: 10, high: 13, low: 9, close: 12, volume: 4),
            chartPoint(timestamp: 2, open: 12, high: 15, low: 11, close: 14, volume: 6)
        ]
        let candle = marketCandleSamples(points, maxCount: 1).first
        XCTAssertEqual(candle, MarketCandleSample(timestamp: 2, open: 10, high: 15, low: 9, close: 14, volume: 10))
    }

    func testRealtimePricesMergeIntoCurrentMinuteCandle() {
        var points = marketMergingRealtimePrice(100, timestamp: 61_000, into: [])
        points = marketMergingRealtimePrice(103, timestamp: 75_000, into: points)
        points = marketMergingRealtimePrice(98, timestamp: 119_000, into: points)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].timestamp, 60_000)
        XCTAssertEqual(points[0].open, 100)
        XCTAssertEqual(points[0].high, 103)
        XCTAssertEqual(points[0].low, 98)
        XCTAssertEqual(points[0].close, 98)

        points = marketMergingRealtimePrice(101, timestamp: 120_000, into: points)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.last?.open, 101)
    }

    private func chartPoint(
        timestamp: Int64,
        open: Double? = nil,
        high: Double? = nil,
        low: Double? = nil,
        close: Double,
        volume: Double? = nil
    ) -> MarketChartPoint {
        MarketChartPoint(timestamp: timestamp, value: close, open: open, high: high, low: low, close: close, volume: volume)
    }
}
