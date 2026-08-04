import XCTest
@testable import AIServerClient

final class MarketPresentationTests: XCTestCase {
    func testDecodesCompanyNetIncomeTTM() throws {
        let data = Data(#"{"success":true,"data":{"symbol":"AAPL","netIncomeTTM":122575000000,"currency":"USD","period":"TTM","fiscalYear":"2025","dataSource":"TradingView Scanner"}}"#.utf8)

        let response = try JSONDecoder().decode(MarketCompanyFinancialsResponse.self, from: data)

        XCTAssertEqual(response.data.symbol, "AAPL")
        XCTAssertEqual(response.data.netIncomeTTM, 122_575_000_000)
        XCTAssertEqual(response.data.currency, "USD")
        XCTAssertEqual(response.data.period, "TTM")
        XCTAssertEqual(response.data.fiscalYear, "2025")
    }

    func testFormatsCompanyNetIncomeWithChineseUnits() {
        XCTAssertEqual(marketFinancialAmount(159_600_000_000, currency: "USD"), "1,596 亿美元")
        XCTAssertEqual(marketFinancialAmount(12_340_000_000, currency: "CNY"), "123.4 亿元")
        XCTAssertEqual(marketFinancialAmount(-850_000_000, currency: "HKD"), "-8.5 亿港元")
    }

    func testDecodesHongKongValuationHistory() throws {
        let data = Data(#"{"date":["2026-07-22","2026-07-23"],"pe":[13.79,13.97],"close":[25635.28,25950.93]}"#.utf8)
        let history = try JSONDecoder().decode(MarketHKValuationHistory.self, from: data)

        XCTAssertEqual(history.date.last, "2026-07-23")
        XCTAssertEqual(history.pe.last, 13.97)
    }

    func testDecodesBackendValuationHistoryContract() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_valuation_history_v1","market":"united-states","date":[],"pe":[28.85,25.43],"source":"multpl","fetchedAt":"2026-07-29T10:00:00Z","cached":true,"stale":false}}"#.utf8)
        let response = try JSONDecoder().decode(MarketValuationHistoryResponse.self, from: data)

        XCTAssertEqual(response.data.dataContract, "market_valuation_history_v1")
        XCTAssertEqual(response.data.market, "united-states")
        XCTAssertEqual(response.data.pe, [28.85, 25.43])
        XCTAssertEqual(response.data.source, "multpl")
        XCTAssertTrue(response.data.cached)
        XCTAssertFalse(response.data.stale)
    }

    func testParsesSP500PEHistoryTable() {
        let html = #"""
        <table id="datatable">
        <tr class="odd"><td>Jul 22, 2026</td><td><abbr title="Estimate">†</abbr>28.85</td></tr>
        <tr class="even"><td>Jun 1, 2026</td><td>&#x2002;25.43</td></tr>
        </table>
        """#

        XCTAssertEqual(marketParseSP500PEHistory(html), [28.85, 25.43])
    }

    func testDecodesAShareTemperatureContract() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_ashare_temperature_v3","days":90,"latest":{"ai_server":{"composite_temperature":{"value":84.55,"label":"偏热","tradeDate":"2026-07-23","fetchedAt":"2026-07-23T08:04:36Z"},"valuation_percentile":{"value":82.35,"label":"偏热","tradeDate":"2026-07-23","fetchedAt":"2026-07-23T08:04:36Z"},"sentiment_percentile":{"value":86.75,"label":"偏热","tradeDate":"2026-07-23","fetchedAt":"2026-07-23T08:04:36Z"},"advancer_share":{"value":0.7759,"label":"","tradeDate":"2026-07-23","fetchedAt":"2026-07-23T08:04:36Z"}}}}}"#.utf8)

        let response = try JSONDecoder().decode(MarketAShareTemperatureResponse.self, from: data)

        XCTAssertEqual(response.data.dataContract, "market_ashare_temperature_v3")
        XCTAssertEqual(response.data.latest.aiServer?.compositeTemperature?.value, 84.55)
        XCTAssertEqual(response.data.latest.aiServer?.valuationPercentile?.value, 82.35)
        XCTAssertEqual(response.data.latest.aiServer?.sentimentPercentile?.value, 86.75)
        XCTAssertEqual(response.data.latest.aiServer?.advancerShare?.value, 0.7759)
    }

    func testDecodesKoreaLeverageContract() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_korea_leverage_v1","asOf":"20260730","generatedAt":"2026-08-01T21:31:00+08:00","fetchedAt":"2026-08-02T06:25:00Z","leverageThermometer":{"value":51.64,"weighted":51.64,"unit":"percent","anchor":"20240102","note":"ratio"},"r2FinancingRatio":{"value":30.72,"percentile10Y":16.4,"unit":"percent","note":"credit / deposits"},"forcedLiquidation":{"unsettledBillionKRW":1.725,"fiveDayAverageBillionKRW":419,"percentile10Y":94},"indices":{"kospi":5593.56,"spx":7437.63},"alert":{"level":"critical","value":51.64,"message":"高位报警","thresholds":{"warning":40,"critical":45}},"freshness":{"staleDays":2,"dailyFullRefreshBeijing":"14:16","recommendedPoll":"after 14:20"},"source":{"name":"KOFIA + KSD","url":"https://kimpremium.com/","docs":"https://kimpremium.com/api"},"disclaimer":"not investment advice"}}"#.utf8)

        let response = try JSONDecoder().decode(MarketKoreaLeverageResponse.self, from: data)

        XCTAssertEqual(response.data.dataContract, "market_korea_leverage_v1")
        XCTAssertEqual(response.data.alert.level, "critical")
        XCTAssertEqual(response.data.leverageThermometer.value, 51.64)
        XCTAssertEqual(response.data.forcedLiquidation.fiveDayAverageBillionKRW, 419)
        XCTAssertEqual(response.data.freshness.staleDays, 2)
    }

    func testDecodesInvestorMoodPublicVideoSamples() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_investor_mood_v1","generatedAt":"2026-07-23T04:00:00Z","methodology":"public-video-sample","disclaimer":"观点样本来自公开视频，不代表整体市场情绪，不构成投资建议。","items":[{"nickname":"王小雨","awemeId":"123","description":"今天继续观察","url":"https://www.douyin.com/video/123","coverUrl":"https://example.com/cover.jpg","videoUrl":"https://video.example.com/123.mp4","createdAt":"2026-07-23T03:00:00Z","label":"观望","reasons":["等待方向"],"transcriptStatus":"字幕成功","analysis":"情绪保持中性。","evidence":["继续观察"],"analysisSource":"qwen","model":"qwen-vl","stale":false,"ageHours":1.0}]}}"#.utf8)
        let response = try JSONDecoder().decode(InvestorMoodResponse.self, from: data)
        XCTAssertEqual(response.data.dataContract, "market_investor_mood_v1")
        XCTAssertEqual(response.data.methodology, "public-video-sample")
        XCTAssertEqual(response.data.items.first?.nickname, "王小雨")
        XCTAssertEqual(response.data.items.first?.label, "观望")
        XCTAssertEqual(response.data.items.first?.analysis, "情绪保持中性。")
        XCTAssertEqual(response.data.items.first?.videoUrl, "https://video.example.com/123.mp4")
        XCTAssertEqual(response.data.items.first?.directPlaybackURL?.absoluteString, "https://video.example.com/123.mp4")
        XCTAssertTrue(response.data.items.first?.playbackURL?.absoluteString.contains("/api/v1/media-proxy?") == true)
        XCTAssertTrue(response.data.items.first?.coverPlaybackURL?.absoluteString.contains("/api/v1/media-proxy?") == true)
        XCTAssertEqual(response.data.items.first?.stale, false)
    }

    func testDecodesHistoricalInvestorMoodWithoutAIFields() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_investor_mood_v1","generatedAt":"2026-07-23T04:00:00Z","methodology":"public-video-sample","disclaimer":"仅为公开样本","items":[{"nickname":"大曾子和酥妻","awemeId":"456","description":"最近一次公开视频","url":"https://www.douyin.com/video/456","coverUrl":"","createdAt":"2026-07-21T05:33:13Z","label":"中性","stale":true,"ageHours":46.8}]}}"#.utf8)

        let response = try JSONDecoder().decode(InvestorMoodResponse.self, from: data)

        XCTAssertEqual(response.data.items.first?.nickname, "大曾子和酥妻")
        XCTAssertEqual(response.data.items.first?.analysis, "")
        XCTAssertEqual(response.data.items.first?.reasons, [])
        XCTAssertEqual(response.data.items.first?.stale, true)
    }

    func testDecodesInvestorVideoInterpretation() throws {
        let data = Data(#"{"success":true,"source_id":"123","status":"ready","provider":"bigmodel","model":"glm-4.6v","cached":false,"estimated_cost_cny":0.036,"interpretation":{"overview":"作者认为短线仍需谨慎。","visual_findings":["画面显示上证指数分时图"],"timeline":[{"time":"00:18","title":"提出观点","detail":"作者判断市场仍在震荡。"}],"creator_notes":["观点主要依据短期走势，未讨论仓位风险。"]}}"#.utf8)

        let response = try JSONDecoder().decode(InvestorVideoInterpretationResponse.self, from: data)

        XCTAssertEqual(response.sourceID, "123")
        XCTAssertEqual(response.model, "glm-4.6v")
        XCTAssertEqual(response.interpretation.timeline.first?.time, "00:18")
        XCTAssertEqual(response.estimatedCostCNY, 0.036)
        XCTAssertFalse(response.cached)
    }

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

    func testDashboardQuoteDecodesTradingDateQuality() throws {
        let data = Data(#"{"symbol":"SPY","name":"标普500","price":747.03,"timestamp":1785661401902,"quality":{"status":"delayed","reason":"official_close","asOfTimestamp":1785660501902,"tradingDate":"2026-07-31","fallbackUsed":false}}"#.utf8)
        let quote = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertEqual(quote.quality?.tradingDate, "2026-07-31")
        XCTAssertEqual(quote.marketAsOfTimestamp, 1785660501902)
    }

    func testPreMarketStockRequestsTrendFallback() throws {
        let preMarket = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":180,"marketSession":"pre","trend":[]}"#.utf8)
        )
        let regular = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":180,"marketSession":"regular","trend":[]}"#.utf8)
        )

        XCTAssertTrue(marketQuoteNeedsTrendBackfill(preMarket))
        XCTAssertFalse(marketQuoteNeedsTrendBackfill(regular))
    }

    func testTradingSessionUsesExplicitSessionBeforeLegacyNightFlag() {
        XCTAssertEqual(MarketTradingSession(rawValue: "pre", legacyIsNightSession: true), .premarket)
        XCTAssertEqual(MarketTradingSession(rawValue: "after"), .postmarket)
        XCTAssertEqual(MarketTradingSession(rawValue: nil, legacyIsNightSession: true), .overnight)
        XCTAssertEqual(MarketTradingSession(rawValue: "closed"), .closed)
        XCTAssertEqual(MarketTradingSession(rawValue: "pre").displayLabel, "盘前")
    }

    func testDashboardReplacementDoesNotFabricateSingleNightTrendPoint() throws {
        var dashboard = try JSONDecoder().decode(
            MarketDashboardResponse.self,
            from: Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v3","generatedAt":"2026-08-03T08:00:00Z","refreshIntervalMs":30000,"coreIndices":[],"referenceIndices":[],"realtimeProxies":[],"metrics":[],"components":[{"symbol":"NVDA","name":"英伟达","price":200,"marketSession":"pre","sessionPrice":201,"trend":[198,200],"nightTrend":[]}],"componentsByRegion":{"us":[{"symbol":"NVDA","name":"英伟达","price":200,"marketSession":"pre","sessionPrice":201,"trend":[198,200],"nightTrend":[]}]},"crypto":[],"missingSymbols":[],"expectedSymbols":[],"symbolHealth":[],"regions":[]}}"#.utf8)
        ).data
        let replacement = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":200.5,"marketSession":"pre","sessionPrice":201.5,"trend":[198,200.5],"nightTrend":[]}"#.utf8)
        )

        dashboard.replace(replacement)

        XCTAssertEqual(dashboard.componentsByRegion["us"]?.first?.nightTrend, [])
    }

    func testSinglePremarketPointDoesNotReuseRegularSessionSparkline() throws {
        let quote = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":200.75,"previousClose":195.04,"marketSession":"pre","sessionPrice":200.84,"sessionChangePercent":2.97,"trend":[194,196,198,200],"nightTrend":[200.84]}"#.utf8)
        )

        XCTAssertEqual(marketExtendedSessionTrend(for: quote, fallback: quote.trend), [])
        XCTAssertEqual(quote.sessionPrice, 200.84)
        XCTAssertTrue(quote.hasActiveExtendedSessionQuote)
    }

    func testMultiplePremarketPointsUsePremarketSparkline() throws {
        let quote = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":200.75,"marketSession":"pre","sessionPrice":200.84,"trend":[194,196,198,200],"nightTrend":[200.2,200.84]}"#.utf8)
        )

        XCTAssertEqual(marketExtendedSessionTrend(for: quote, fallback: quote.trend), [200.2, 200.84])
    }

    func testPremarketPriceDoesNotFabricateTrendWhenFeedsAreEmpty() throws {
        let quote = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":200.75,"previousClose":195.04,"marketSession":"pre","sessionPrice":200.84,"sessionChangePercent":2.97,"trend":[],"nightTrend":[]}"#.utf8)
        )

        XCTAssertEqual(marketExtendedSessionTrend(for: quote, fallback: []), [])
        XCTAssertEqual(quote.formattedSessionPercent, "+2.97%")
    }

    func testClosedIndexFutureDoesNotReplaceCashProxy() throws {
        let data = Data(#"{"symbol":"ES1!","name":"标普500 E-mini期货","price":7519.25,"marketSession":"closed"}"#.utf8)
        let future = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertNil(marketActiveIndexSession(future))
    }

    func testActiveIndexFutureCanReplaceCashProxy() throws {
        let data = Data(#"{"symbol":"ES1!","name":"标普500 E-mini期货","price":7519.25,"marketSession":"regular"}"#.utf8)
        let future = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertEqual(marketActiveIndexSession(future)?.symbol, "ES1!")
    }

    func testSuspiciousMajorIndexMoveIsFlaggedForReview() throws {
        let data = Data(#"{"symbol":"^KS11","name":"韩国KOSPI","price":6595.45,"previousClose":5593.56,"changePercent":"17.91%"}"#.utf8)
        let quote = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertTrue(quote.hasSuspiciousIndexMove)
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

    func testDashboardDecodesV3RealtimeProxyContract() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v3","definitionVersion":"2026-07-29.2","generatedAt":"2026-07-30T07:26:57Z","refreshIntervalMs":30000,"coreIndices":[{"symbol":"SPY","name":"标普500实时代理（SPY）","displayName":"标普500实时代理（SPY）","instrumentType":"realtime-proxy-etf","proxyFor":"^GSPC","referenceSymbol":"^GSPC","historicalSymbol":"^GSPC","price":729.46}],"referenceIndices":[{"symbol":"^GSPC","name":"标普500","instrumentType":"reference-index","displayMode":"historical-reference","price":7316.15}],"realtimeProxies":[{"symbol":"SPY","referenceSymbol":"^GSPC","historicalSymbol":"^GSPC","displayName":"标普500实时代理（SPY）"}],"metrics":[],"components":[],"crypto":[],"indexSessions":{},"missingSymbols":[],"expectedSymbols":["SPY","^GSPC"],"symbolHealth":[],"regions":[]}}"#.utf8)

        let response = try JSONDecoder().decode(MarketDashboardResponse.self, from: data)
        let proxy = try XCTUnwrap(response.data.coreIndices.first)

        XCTAssertEqual(response.data.dataContract, "market_dashboard_v3")
        XCTAssertEqual(proxy.symbol, "SPY")
        XCTAssertEqual(proxy.presentationName, "标普500实时代理（SPY）")
        XCTAssertEqual(proxy.instrumentType, "realtime-proxy-etf")
        XCTAssertEqual(proxy.proxyFor, "^GSPC")
        XCTAssertEqual(proxy.historicalSymbol, "^GSPC")
        XCTAssertEqual(response.data.referenceIndices.first?.symbol, "^GSPC")
        XCTAssertEqual(response.data.realtimeProxies.first?.symbol, "SPY")
        XCTAssertEqual(response.data.quote(symbol: "^GSPC")?.displayMode, "historical-reference")
    }

    func testDashboardDecodesRegionalCoreStocksIncludingGoogle() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v3","definitionVersion":"2026-08-03.1","generatedAt":"2026-08-03T08:00:00Z","refreshIntervalMs":30000,"coreIndices":[],"referenceIndices":[],"realtimeProxies":[],"metrics":[],"components":[{"symbol":"GOOGL","name":"谷歌","price":201}],"componentsByRegion":{"us":[{"symbol":"NVDA","name":"英伟达","price":180},{"symbol":"GOOGL","name":"谷歌","price":201}],"jp":[{"symbol":"7203.T","name":"丰田汽车","price":3200}]},"crypto":[],"missingSymbols":[],"expectedSymbols":[],"symbolHealth":[],"regions":[]}}"#.utf8)

        let dashboard = try JSONDecoder().decode(MarketDashboardResponse.self, from: data).data

        XCTAssertEqual(dashboard.componentsByRegion["us"]?.map(\.symbol), ["NVDA", "GOOGL"])
        XCTAssertEqual(dashboard.componentsByRegion["jp"]?.map(\.symbol), ["7203.T"])
        XCTAssertEqual(dashboard.quote(symbol: "GOOGL")?.presentationName, "谷歌")
    }

    func testDashboardSkipsQuotesWithNullPriceWithoutDroppingValidData() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v3","generatedAt":"2026-08-02T08:09:10Z","refreshIntervalMs":30000,"coreIndices":[{"symbol":"SPY","name":"标普500实时代理","price":632.08}],"referenceIndices":[],"metrics":[{"symbol":"USDJPY","name":"美元兑日元","price":null,"lastKnownPrice":157.4,"stale":true},{"symbol":"^VIX","name":"波动率指数","price":16.72}],"components":[],"crypto":[],"indexSessions":{"SPY":{"symbol":"SPY","name":"标普500盘后","price":null,"stale":true}},"missingSymbols":[],"expectedSymbols":["SPY","USDJPY","^VIX"],"symbolHealth":[{"symbol":"USDJPY","status":"stale","reason":"quote_stale"}],"regions":[]}}"#.utf8)

        let response = try JSONDecoder().decode(MarketDashboardResponse.self, from: data)

        XCTAssertEqual(response.data.coreIndices.map(\.symbol), ["SPY"])
        XCTAssertEqual(response.data.metrics.map(\.symbol), ["^VIX"])
        XCTAssertEqual(response.data.indexSessions, [:])
        XCTAssertEqual(response.data.symbolHealth.first?.symbol, "USDJPY")
        XCTAssertEqual(response.data.symbolHealth.first?.status, .stale)
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

    func testExtendedSessionDisplayFallsBackToMarketSession() throws {
        let data = Data(#"{"symbol":"NVDA","name":"英伟达","price":196.51,"previousClose":206.84,"marketSession":"overnight","isNightSession":false,"sessionPrice":196.54,"sessionChangePercent":-4.98}"#.utf8)
        let quote = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertTrue(quote.hasActiveExtendedSessionQuote)
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

    func testDailyChartPointsRemainInOneDrawableSegment() {
        let previous = MarketChartPoint(timestamp: 1_000, open: 10, high: 11, low: 9, close: 10, volume: nil, state: "confirmed", source: "eastmoney", session: nil)
        let nextDay = MarketChartPoint(timestamp: 1_000 + 24 * 60 * 60 * 1_000, open: 11, high: 12, low: 10, close: 11, volume: nil, state: "confirmed", source: "eastmoney", session: nil)

        XCTAssertFalse(marketChartShouldSplitSegment(previous: previous, current: nextDay, interval: "1d"))
        XCTAssertTrue(marketChartShouldSplitSegment(previous: previous, current: nextDay, interval: "1m"))
    }

    func testChartXFractionUsesTimestampScale() {
        XCTAssertEqual(marketChartXFraction(timestamp: 1_000, firstTimestamp: 1_000, lastTimestamp: 5_000), 0)
        XCTAssertEqual(marketChartXFraction(timestamp: 2_000, firstTimestamp: 1_000, lastTimestamp: 5_000), 0.25)
        XCTAssertEqual(marketChartXFraction(timestamp: 5_000, firstTimestamp: 1_000, lastTimestamp: 5_000), 1)
    }

    func testIntradayChartCompressesLongMissingSessionGap() {
        let minute = Int64(60 * 1_000)
        let fractions = marketChartXFractions(
            timestamps: [0, minute, 482 * minute],
            interval: "1m"
        )

        XCTAssertEqual(fractions[0], 0)
        XCTAssertEqual(fractions[1], 1.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(fractions[2], 1)
    }

    func testChinaIntradayChartRecognizesLunchBreakWithoutMislabelingOtherGaps() {
        let timezone = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        func timestamp(hour: Int, minute: Int) -> Int64 {
            let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: hour, minute: minute))!
            return Int64(date.timeIntervalSince1970 * 1_000)
        }
        func point(hour: Int, minute: Int) -> MarketChartPoint {
            MarketChartPoint(timestamp: timestamp(hour: hour, minute: minute), open: 10, high: 10, low: 10, close: 10, volume: 1, state: "confirmed", source: "eastmoney", session: "regular")
        }

        let lunchBreak = marketChartLunchBreak(
            points: [point(hour: 11, minute: 30), point(hour: 13, minute: 0)],
            market: "CN",
            interval: "1m",
            timezone: "Asia/Shanghai"
        )
        XCTAssertEqual(lunchBreak?.label, "午间休市")
        XCTAssertNil(marketChartLunchBreak(
            points: [point(hour: 10, minute: 0), point(hour: 11, minute: 5)],
            market: "CN",
            interval: "1m",
            timezone: "Asia/Shanghai"
        ))
        XCTAssertNil(marketChartLunchBreak(
            points: [point(hour: 11, minute: 30), point(hour: 13, minute: 0)],
            market: "US",
            interval: "1m",
            timezone: "America/New_York"
        ))
    }

    func testDailyChartKeepsCalendarTimeScale() {
        let day = Int64(24 * 60 * 60 * 1_000)
        let fractions = marketChartXFractions(timestamps: [0, day, 3 * day], interval: "1d")

        XCTAssertEqual(fractions[1], 1.0 / 3.0, accuracy: 0.0001)
    }

    func testSingleOvernightBoundaryPointDoesNotClaimNightCoverage() {
        let points = [
            MarketChartPoint(timestamp: 1, open: 10, high: 10, low: 10, close: 10, volume: 1, state: "confirmed", source: "tradingview", session: "post"),
            MarketChartPoint(timestamp: 2, open: 10, high: 10, low: 10, close: 10, volume: 1, state: "confirmed", source: "tradingview", session: "overnight"),
            MarketChartPoint(timestamp: 3, open: 10, high: 10, low: 10, close: 10, volume: 1, state: "confirmed", source: "tradingview", session: "pre")
        ]

        XCTAssertEqual(marketChartExtendedSessionLabel(points), "含盘前盘后")
    }

    func testVolumeBarsRemainFullyInsideChartBounds() {
        XCTAssertEqual(marketVolumeBarX(fraction: 0, width: 300, barWidth: 8), 4)
        XCTAssertEqual(marketVolumeBarX(fraction: 0.5, width: 300, barWidth: 8), 150)
        XCTAssertEqual(marketVolumeBarX(fraction: 1, width: 300, barWidth: 8), 296)
    }

    func testChartDropsProvisionalExtendedQuoteSnapshots() throws {
        let data = Data(#"""
        [
          {"timestamp":1,"open":206.93,"high":206.93,"low":206.93,"close":206.93,"volume":114836805,"state":"provisional","source":"tradingview","session":"pre"},
          {"timestamp":2,"open":207,"high":208,"low":206,"close":207.5,"volume":120000,"state":"confirmed","source":"eastmoney","session":"regular"},
          {"timestamp":3,"open":196.54,"high":196.54,"low":196.54,"close":196.54,"volume":154353698,"state":"provisional","source":"tradingview","session":"overnight"}
        ]
        """#.utf8)
        let points = try JSONDecoder().decode([MarketChartPoint].self, from: data)

        XCTAssertEqual(marketChartDisplayPoints(points).map(\.timestamp), [2])
    }

    func testVolumeScaleUsesRobustPercentileCeiling() throws {
        let rows = (1...20).map { index in
            #"{"timestamp":\#(index),"open":10,"high":11,"low":9,"close":10,"volume":\#(index * 100),"state":"confirmed","source":"test","session":"regular"}"#
        } + [
            #"{"timestamp":21,"open":10,"high":11,"low":9,"close":10,"volume":999999999,"state":"confirmed","source":"test","session":"regular"}"#
        ]
        let points = try JSONDecoder().decode([MarketChartPoint].self, from: Data("[\(rows.joined(separator: ","))]".utf8))

        XCTAssertEqual(marketChartVolumeCeiling(points), 2_000)
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
