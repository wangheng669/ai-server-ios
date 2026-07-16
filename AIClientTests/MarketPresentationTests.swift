import XCTest
@testable import AIServerClient

final class MarketPresentationTests: XCTestCase {
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

    func testMarketRangesUseExpectedIntervalsAndLimits() {
        XCTAssertEqual(MarketRange.day.apiInterval, "1m")
        XCTAssertEqual(MarketRange.week.apiRange, "5d")
        XCTAssertEqual(MarketRange.week.apiInterval, "1d")
        XCTAssertEqual(MarketRange.week.apiLimit, 8)
        XCTAssertEqual(MarketRange.month.apiInterval, "1d")
        XCTAssertEqual(MarketRange.maximum.apiLimit, 10_000)
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
