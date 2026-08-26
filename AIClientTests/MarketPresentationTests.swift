import XCTest
@testable import AIServerClient

private actor MarketConcurrencyProbe {
    private var active = 0
    private var maximumActive = 0
    private var completed: [Int] = []

    func start() {
        active += 1
        maximumActive = max(maximumActive, active)
    }

    func finish(_ value: Int) {
        active -= 1
        completed.append(value)
    }

    func result() -> (maximumActive: Int, completed: [Int]) {
        (maximumActive, completed)
    }
}

final class MarketPresentationTests: XCTestCase {
    func testDecodesServerBackedVolatilityResearch() throws {
        let data = Data(#"{"data":{"generatedAt":"2026-08-26T04:00:00Z","lookbackDays":90,"summary":"VIX 与日经波动率均已回落。","isStale":false,"items":[{"id":"nikkei225-vi","market":"日本","name":"日经平均波动率指数","shortName":"Nikkei 225 VI","value":32.0,"previousClose":34.0,"dailyChangePercent":-5.88,"peakValue":40.0,"peakDate":"2026-07-20","drawdownFromPeakPercent":-20.0,"asOf":"2026-08-26","regime":"偏高","interpretation":"较峰值明显回落。","history":[{"date":"2026-08-25","value":34.0},{"date":"2026-08-26","value":32.0}],"source":{"title":"Nikkei Indexes 官方日线","url":"https://indexes.nikkei.co.jp/en/nkave/index/profile?idx=nk225vi"}}]}}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(VolatilityResearchResponse.self, from: data).data

        XCTAssertEqual(payload.lookbackDays, 90)
        XCTAssertEqual(payload.items.first?.shortName, "Nikkei 225 VI")
        XCTAssertEqual(payload.items.first?.drawdownFromPeakPercent, -20)
        XCTAssertEqual(payload.items.first?.history.count, 2)
        XCTAssertFalse(payload.isStale)
    }

    @MainActor
    func testVolatilityResearchStoreForceReloadReplacesPayload() async {
        var fetchCount = 0
        let store = VolatilityResearchStore {
            fetchCount += 1
            return VolatilityResearchPayload(
                generatedAt: Date(timeIntervalSince1970: TimeInterval(fetchCount)),
                lookbackDays: 90,
                summary: "第\(fetchCount)次",
                items: [],
                isStale: false
            )
        }
        await store.load()
        await store.load(force: true)
        XCTAssertEqual(store.payload?.summary, "第2次")
    }

    func testCompactResearchDateUsesChineseMonthAndDay() {
        XCTAssertEqual(marketCompactResearchDate("2026-07-22"), "7月22日")
        XCTAssertEqual(marketCompactResearchDate("unknown"), "unknown")
    }

    func testMarketDecodingDiagnosticIncludesMissingFieldPath() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v4","generatedAt":"2026-08-24T10:00:00Z","refreshIntervalMs":30000}}"#.utf8)

        do {
            _ = try JSONDecoder().decode(MarketDashboardResponse.self, from: data)
            XCTFail("Expected dashboard decoding to fail")
        } catch {
            let diagnostic = marketDecodingDiagnostic(error)
            XCTAssertEqual(diagnostic.category, "keyNotFound")
            XCTAssertEqual(diagnostic.path, "$.data.componentsByRegion")
            XCTAssertNil(diagnostic.expectedType)
            XCTAssertFalse(diagnostic.detail.isEmpty)
        }
    }

    func testMarketDecodingDiagnosticIncludesTypeMismatchPath() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v4","generatedAt":"2026-08-24T10:00:00Z","refreshIntervalMs":"30000","componentsByRegion":{}}}"#.utf8)

        do {
            _ = try JSONDecoder().decode(MarketDashboardResponse.self, from: data)
            XCTFail("Expected dashboard decoding to fail")
        } catch {
            let diagnostic = marketDecodingDiagnostic(error)
            XCTAssertEqual(diagnostic.category, "typeMismatch")
            XCTAssertEqual(diagnostic.path, "$.data.refreshIntervalMs")
            XCTAssertEqual(diagnostic.expectedType, "Swift.Int")
            XCTAssertEqual(
                marketDecodingActualValue(in: data, error: error),
                MarketDecodingActualValue(type: "string", preview: "string(length=5)")
            )
        }
    }

    func testMarketDecodingActualValueDoesNotIncludeRawStringContent() throws {
        let data = Data(#"{"value":"private-market-value"}"#.utf8)
        struct Payload: Decodable { let value: Int }

        do {
            _ = try JSONDecoder().decode(Payload.self, from: data)
            XCTFail("Expected payload decoding to fail")
        } catch {
            let actual = marketDecodingActualValue(in: data, error: error)
            XCTAssertEqual(actual?.type, "string")
            XCTAssertEqual(actual?.preview, "string(length=20)")
            XCTAssertFalse(actual?.preview?.contains("private-market-value") == true)
        }
    }

    func testXueqiuStockURLUsesMarketSpecificCodes() {
        XCTAssertEqual(marketXueqiuURL(for: "NVDA")?.absoluteString, "https://xueqiu.com/S/NVDA")
        XCTAssertEqual(marketXueqiuURL(for: "601398.SS")?.absoluteString, "https://xueqiu.com/S/SH601398")
        XCTAssertEqual(marketXueqiuURL(for: "000001.SZ")?.absoluteString, "https://xueqiu.com/S/SZ000001")
        XCTAssertEqual(marketXueqiuURL(for: "1211.HK")?.absoluteString, "https://xueqiu.com/S/01211")
        XCTAssertEqual(marketXueqiuURL(for: "00700.HK")?.absoluteString, "https://xueqiu.com/S/00700")
    }

    func testXueqiuStockURLRejectsUnsupportedInstrumentFormats() {
        for symbol in ["^GSPC", "BINANCE:BTCUSDT", "GC1!", "7203.T", "005930.KS", ""] {
            XCTAssertNil(marketXueqiuURL(for: symbol), symbol)
        }
    }

    func testMarketSentimentOverviewUsesRequestedMarketOrder() {
        XCTAssertEqual(
            SentimentMarket.marketOverviewOrder,
            [.china, .hongKong, .korea, .unitedStates]
        )
        XCTAssertEqual(SentimentMarket.marketOverviewOrder.map(\.title), ["A 股", "港股", "韩股", "美股"])
    }

    func testSentimentLabelsCoverOverviewTemperatureScale() {
        XCTAssertEqual(SentimentSnapshot.label(for: 25), "偏冷")
        XCTAssertEqual(SentimentSnapshot.label(for: 50), "正常")
        XCTAssertEqual(SentimentSnapshot.label(for: 79), "偏热")
        XCTAssertEqual(SentimentSnapshot.displayLabel(for: "critical"), "高风险")
        XCTAssertEqual(SentimentSnapshot.displayLabel(for: "warning"), "预警")
    }

    func testMarketRegionSwipeAcceptsOnlyDeliberateHorizontalGestures() {
        XCTAssertEqual(
            marketRegionSwipeOffset(
                horizontalDistance: -60,
                verticalDistance: 8,
                projectedHorizontalDistance: -75
            ),
            1
        )
        XCTAssertEqual(
            marketRegionSwipeOffset(
                horizontalDistance: 20,
                verticalDistance: 4,
                projectedHorizontalDistance: 95
            ),
            -1
        )
        XCTAssertNil(
            marketRegionSwipeOffset(
                horizontalDistance: 35,
                verticalDistance: 70,
                projectedHorizontalDistance: 120
            )
        )
        XCTAssertNil(
            marketRegionSwipeOffset(
                horizontalDistance: -30,
                verticalDistance: 5,
                projectedHorizontalDistance: -60
            )
        )
        XCTAssertTrue(marketRegionSwipeBlocksSelection(horizontalDistance: 14, verticalDistance: 2))
        XCTAssertFalse(marketRegionSwipeBlocksSelection(horizontalDistance: 8, verticalDistance: 1))
        XCTAssertFalse(marketRegionSwipeBlocksSelection(horizontalDistance: 18, verticalDistance: 20))
    }

    func testMarketRegionSwipeStopsAtRegionBoundaries() {
        XCTAssertEqual(marketAdjacentRegion(from: .unitedStates, offset: 1), .china)
        XCTAssertEqual(marketAdjacentRegion(from: .china, offset: -1), .unitedStates)
        XCTAssertNil(marketAdjacentRegion(from: .unitedStates, offset: -1))
        XCTAssertNil(marketAdjacentRegion(from: .crypto, offset: 1))
    }

    func testCompanyLogoPathsSurviveMarketStoreRecreation() throws {
        let suiteName = "MarketPresentationTests.companyLogoPaths.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let paths = ["AAPL": "/img/company-logos/aapl.png", "MSFT": "/img/company-logos/msft.png"]

        MarketCompanyLogoPathCache.save(paths, defaults: defaults)

        XCTAssertEqual(MarketCompanyLogoPathCache.load(defaults: defaults), paths)
        XCTAssertTrue(
            MarketCompanyLogoPathCache.load(
                defaults: defaults,
                now: Date(timeIntervalSinceNow: 31 * 24 * 60 * 60)
            ).isEmpty
        )
    }

    func testChartFallsBackOnlyWhenPrimaryHasNoDrawableLine() {
        let primary = [chartPoint(timestamp: 1, close: 10)]
        let fallback = [chartPoint(timestamp: 1, close: 10), chartPoint(timestamp: 2, close: 11)]

        XCTAssertTrue(marketShouldUseFallbackChart(primaryPoints: primary, fallbackPoints: fallback))
        XCTAssertFalse(marketShouldUseFallbackChart(primaryPoints: fallback, fallbackPoints: fallback))
        XCTAssertFalse(marketShouldUseFallbackChart(primaryPoints: primary, fallbackPoints: primary))
    }

    func testRealtimeProxyUsesClearDetailAndCompactMarketNames() throws {
        let data = Data(#"{"symbol":"QQQ","name":"纳斯达克100实时代理（QQQ）","displayName":"纳斯达克100实时代理（QQQ）","instrumentType":"realtime-proxy-etf","price":718.45}"#.utf8)
        let quote = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertEqual(quote.detailPresentationName, "纳斯达克100 ETF")
        XCTAssertEqual(quote.detailInstrumentLabel, "QQQ · 指数代理 ETF")
        XCTAssertEqual(quote.compactMarketName, "纳指100")
    }

    func testCompactMarketNameRemovesFuturesNoise() throws {
        let data = Data(#"{"symbol":"NQ1!","name":"纳斯达克 100 E-mini 期货","price":29740}"#.utf8)
        let quote = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertEqual(quote.compactMarketName, "纳指 100 期货")
    }

    func testMarketAuxiliaryRequestsKeepConcurrencySlotsFullWithoutExceedingLimit() async {
        let probe = MarketConcurrencyProbe()

        await marketRunWithLimitedConcurrency(Array(0..<10), maximumConcurrentRequests: 3) { value in
            await probe.start()
            try? await Task.sleep(for: .milliseconds(value.isMultiple(of: 3) ? 12 : 3))
            await probe.finish(value)
        }

        let result = await probe.result()
        XCTAssertEqual(result.completed.sorted(), Array(0..<10))
        XCTAssertEqual(result.maximumActive, 3)
    }

    func testSentimentSnapshotCachePolicyUsesAvailableCacheOnWeakNetworks() {
        XCTAssertEqual(
            marketRequestCachePolicy(bypassCache: false, useCachedResponseWhenAvailable: true),
            .returnCacheDataElseLoad
        )
        XCTAssertEqual(
            marketRequestCachePolicy(bypassCache: true, useCachedResponseWhenAvailable: true),
            .reloadIgnoringLocalCacheData
        )
        XCTAssertEqual(
            marketRequestCachePolicy(bypassCache: false, useCachedResponseWhenAvailable: false),
            .useProtocolCachePolicy
        )
    }

    func testDecodesCachedSentimentSnapshot() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_sentiment_snapshot_v1","market":"hong-kong","score":66.67,"label":"正常","valuationPercentile":83.33,"sentimentPercentile":50,"advancerShare":50,"breadth":{"up":4,"down":5,"flat":1},"fetchedAt":"2026-08-12T02:00:00Z","cached":true,"stale":false}}"#.utf8)

        let snapshot = try JSONDecoder().decode(MarketSentimentSnapshotResponse.self, from: data).data

        XCTAssertEqual(snapshot.dataContract, "market_sentiment_snapshot_v1")
        XCTAssertEqual(snapshot.score, 66.67, accuracy: 0.001)
        XCTAssertEqual(snapshot.valuationPercentile, 83.33)
        XCTAssertEqual(snapshot.breadth?.up, 4)
        XCTAssertTrue(snapshot.cached)
        XCTAssertFalse(snapshot.stale)
    }

    func testDecodesMarketBootstrapFirstScreenContract() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_bootstrap_v1","generatedAt":"2026-08-24T01:00:00Z","dashboard":{"dataContract":"market_dashboard_v4","definitionVersion":"test","generatedAt":"2026-08-24T01:00:00Z","refreshIntervalMs":30000,"coreIndices":[],"referenceIndices":[],"realtimeProxies":[],"metrics":[],"componentsByRegion":{},"crypto":[],"commodities":[],"missingSymbols":[],"expectedSymbols":[],"symbolHealth":[],"regions":[]},"temperature":{"dataContract":"market_ashare_temperature_v3","days":90,"latest":{"ai_server":{"composite_temperature":{"value":48,"label":"正常","tradeDate":"2026-08-22","fetchedAt":"2026-08-22T07:00:00Z"}}}},"sentimentSnapshots":{"hong-kong":{"dataContract":"market_sentiment_snapshot_v1","market":"hong-kong","score":52,"label":"正常","fetchedAt":"2026-08-24T01:00:00Z","cached":true,"stale":false}},"errors":{"korea":"delayed"}}}"#.utf8)

        let bootstrap = try JSONDecoder().decode(MarketBootstrapResponse.self, from: data).data

        XCTAssertEqual(bootstrap.dataContract, "market_bootstrap_v1")
        XCTAssertEqual(bootstrap.dashboard.dataContract, "market_dashboard_v4")
        XCTAssertEqual(bootstrap.temperature?.latest.aiServer?.compositeTemperature?.value, 48)
        XCTAssertEqual(bootstrap.sentimentSnapshots["hong-kong"]?.score, 52)
        XCTAssertEqual(bootstrap.errors?["korea"], "delayed")
    }

    func testDecodesServerBackedInstitutionResearch() throws {
        let data = Data(#"{"data":{"institutionsCount":3,"items":[{"id":"morgan-stanley-more-stocks-join-bull-market","institution":"Morgan Stanley","institutionShortName":"MS","title":"更多股票加入牛市","originalTitle":"More Stocks Join the Bull Market","summary":"市场领导力正在扩散。","publishedOn":"2026-07-22","sourceType":"官方播客文字稿","categories":["美股","市场广度"],"metrics":[],"source":{"title":"More Stocks Join the Bull Market","url":"https://www.morganstanley.com/insights/example"},"isSystemSummary":true,"presentation":"lead"},{"id":"goldman-sp500-forecast-2026","institution":"Goldman Sachs","institutionShortName":"GS","title":"盈利增长推动美股上行","originalTitle":"The S&P 500 Is Forecast to Climb as Earnings Growth Powers Stocks Higher","summary":"盈利预测上调。","publishedOn":"2026-05-28","sourceType":"官方研究文章","categories":["美股"],"metrics":[{"label":"2026 EPS","value":"$340"}],"targetRevision":{"label":"标普500年末目标","previousValue":"7,600","currentValue":"8,000"},"source":{"title":"The S&P 500 Is Forecast to Climb as Earnings Growth Powers Stocks Higher","url":"https://www.goldmansachs.com/insights/example"},"isSystemSummary":true,"presentation":"revision"}],"updatedAt":"2026-08-10T00:00:00Z"}}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let payload = try decoder.decode(InstitutionResearchResponse.self, from: data).data

        XCTAssertEqual(payload.institutionsCount, 3)
        XCTAssertEqual(payload.items.first?.presentation, .lead)
        XCTAssertEqual(payload.items.last?.targetRevision?.currentValue, "8,000")
        XCTAssertEqual(payload.items.last?.metrics.first?.value, "$340")
        XCTAssertTrue(payload.items.first?.isSystemSummary == true)
    }

    @MainActor
    func testInstitutionResearchStoreForceReloadReplacesPayload() async {
        var fetchCount = 0
        let store = InstitutionResearchStore(fetch: {
            fetchCount += 1
            return InstitutionResearchPayload(institutionsCount: fetchCount, items: [], updatedAt: nil)
        })

        await store.load()
        await store.load()
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(store.payload?.institutionsCount, 1)

        await store.load(force: true)
        XCTAssertEqual(fetchCount, 2)
        XCTAssertEqual(store.payload?.institutionsCount, 2)
    }

    func testDecodesServerBackedCompanyConsensusExpectation() throws {
        let data = Data(#"{"data":{"companies":[{"id":"nvidia","name":"NVIDIA Corporation","shortName":"英伟达","logoUrl":"/img/company-logos/nvidia.png","ticker":"NVDA","exchange":"纳斯达克证券交易所","industry":"半导体","location":"美国","tagline":"AI","thesis":"持续跟踪","metrics":[],"highlights":[],"moats":[],"risks":[],"questions":[],"sources":[],"buyback":{"status":"持续执行","asOfDate":"2026-01-25","shares":"--","amount":"--","percentage":"--","priceRange":"--","purpose":"--","progressNote":"--","source":{"title":"公告","url":"https://example.com"}},"nextReport":{"reportType":"季度业绩","expectedDate":"2026-08-26","dateStatus":"预计窗口","note":"--","source":{"title":"日历","url":"https://example.com"}},"consensus":{"period":"2027财年第二季度","asOfDate":"2026-08-05","status":"财报前更新","metrics":[{"label":"营业收入","value":"910亿美元","note":"分析师平均值"}],"note":"不同数据商的样本可能不同。","source":{"title":"市场一致预期","url":"https://example.com"}},"financials":{"unit":"亿美元","years":[],"source":{"title":"年报","url":"https://example.com"}},"updatedAt":"2026-08-05T00:00:00Z"}],"updatedAt":"2026-08-05T00:00:00Z"}}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try decoder.decode(CompanyResearchResponse.self, from: data)

        XCTAssertEqual(response.data.companies.first?.consensus?.period, "2027财年第二季度")
        XCTAssertEqual(response.data.companies.first?.consensus?.metrics.first?.value, "910亿美元")
    }

    func testDecodesServerBackedCompanyResearchFramework() throws {
        let data = Data(#"{"data":{"companies":[{"id":"kweichow-moutai","name":"贵州茅台酒股份有限公司","shortName":"贵州茅台","logoUrl":"/img/company-logos/kweichow-moutai.png","ticker":"600519.SH","exchange":"上海证券交易所","industry":"白酒","location":"中国贵州","tagline":"高端白酒龙头","thesis":"持续跟踪","metrics":[],"highlights":[],"moats":[],"risks":[],"questions":[],"sources":[],"buyback":{"status":"已完成","asOfDate":"2026-08-08","shares":"--","amount":"--","percentage":"--","priceRange":"--","purpose":"--","progressNote":"--","source":{"title":"公告","url":"https://example.com"}},"nextReport":{"reportType":"半年度报告","expectedDate":"2026-08-15","dateStatus":"已公告","note":"--","source":{"title":"公告","url":"https://example.com"}},"framework":{"businessSummary":"品牌与稀缺产能驱动","revenueModel":"茅台酒与系列酒","customers":"经销商和消费者","pricingPower":"强","competitivePosition":"行业领先","capitalAllocation":"分红与回购","financialQuality":"现金流质量较高","currentChanges":[{"label":"渠道","detail":"直营占比变化"}],"falsificationConditions":["批价长期弱于出厂价"]},"business":[{"key":"production","title":"生产","detail":"基酒酿造"}],"indicators":[{"key":"wholesale_price","label":"批价","value":"待补充","status":"待验证","trend":"待验证","note":"观察渠道景气","asOfDate":"2026-08-08"}],"updates":[{"key":"annual_report","occurredOn":"2026-04-02","category":"财报","title":"年度报告","status":"已披露","summary":"收入利润保持增长","impact":"验证经营质量"}],"financials":{"unit":"亿元","years":[],"source":{"title":"年报","url":"https://example.com"}},"updatedAt":"2026-08-08T00:00:00Z"}],"updatedAt":"2026-08-08T00:00:00Z"}}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let company = try decoder.decode(CompanyResearchResponse.self, from: data).data.companies[0]

        XCTAssertEqual(company.framework?.businessSummary, "品牌与稀缺产能驱动")
        XCTAssertEqual(company.framework?.currentChanges.first?.detail, "直营占比变化")
        XCTAssertEqual(company.business?.first?.key, "production")
        XCTAssertEqual(company.indicators?.first?.value, "待补充")
        XCTAssertEqual(company.updates?.first?.category, "财报")
    }

    @MainActor
    func testCompanyResearchStoreForceReloadReplacesExistingCompanies() async {
        let source = CompanyResearchSource(title: "测试", url: URL(string: "https://example.com")!)
        func payload(pe: Double?) -> CompanyResearchPayload {
            CompanyResearchPayload(
                companies: [CompanyResearchProfile(
                    id: "nvidia",
                    name: "NVIDIA Corporation",
                    shortName: "英伟达",
                    logoUrl: URL(string: "https://example.com/nvidia.png")!,
                    ticker: "NVDA",
                    exchange: "纳斯达克证券交易所",
                    industry: "半导体",
                    location: "美国",
                    tagline: "AI",
                    thesis: "持续跟踪",
                    metrics: [],
                    highlights: [],
                    moats: [],
                    risks: [],
                    questions: [],
                    sources: [],
                    buyback: CompanyResearchBuyback(
                        status: "持续执行", asOfDate: "2026-08-10", shares: "--", amount: "--",
                        percentage: "--", priceRange: "--", purpose: "--", progressNote: "--", source: source
                    ),
                    nextReport: CompanyResearchReport(
                        reportType: "季度业绩", expectedDate: "2026-08-26", dateStatus: "预计窗口", note: "--", source: source
                    ),
                    consensus: nil,
                    financials: CompanyResearchFinancials(unit: "亿美元", years: [], quarters: nil, forecasts: nil, source: source),
                    framework: nil,
                    business: nil,
                    indicators: nil,
                    updates: nil,
                    market: CompanyResearchMarket(
                        symbol: "NVDA", price: 223.96, changePercent: "2.71%", marketCap: 5_419_832_162_476,
                        pe: pe, peStatic: nil, peType: "ttm", netIncomeTTM: nil, week52Low: nil, currency: "USD",
                        fiscalYear: nil, fundamentalsSource: nil, fundamentalsAsOf: nil,
                        timestamp: 1_786_329_600_000, status: "complete"
                    ),
                    updatedAt: Date(timeIntervalSince1970: 1_786_329_600)
                )],
                updatedAt: Date(timeIntervalSince1970: 1_786_329_600)
            )
        }

        var fetchCount = 0
        let store = CompanyResearchStore(fetch: {
            fetchCount += 1
            return payload(pe: fetchCount == 1 ? nil : 34.3)
        })

        await store.load()
        XCTAssertEqual(fetchCount, 1)
        XCTAssertNil(store.companies.first?.market?.pe)

        await store.load()
        XCTAssertEqual(fetchCount, 1)

        await store.load(force: true)
        XCTAssertEqual(fetchCount, 2)
        XCTAssertEqual(store.companies.first?.market?.pe, 34.3)
    }

    @MainActor
    func testCompanyResearchStoreOnlyRefreshesAfterCacheExpires() async {
        var fetchCount = 0
        let store = CompanyResearchStore(refreshInterval: 300) {
            fetchCount += 1
            return CompanyResearchPayload(companies: [], updatedAt: nil)
        }
        let initialDate = Date(timeIntervalSince1970: 1_000)

        await store.loadIfNeeded(now: initialDate)
        await store.loadIfNeeded(now: initialDate.addingTimeInterval(299))
        XCTAssertEqual(fetchCount, 1)

        await store.loadIfNeeded(now: initialDate.addingTimeInterval(300))
        XCTAssertEqual(fetchCount, 2)
    }

    func testDecodesUnifiedCompanyFundamentalsFromMarketQuote() throws {
        let data = Data(#"{"symbol":"AAPL","name":"Apple","price":220.1,"pe":31.2,"peStatic":32.78,"marketCap":3350000000000,"peType":"ttm","netIncomeTTM":122575000000,"week52Low":169.21,"currency":"USD","fundamentalsCurrency":"USD","fiscalYear":"2025","fundamentalsSource":"TradingView","fundamentalsAsOf":"2026-08-10T08:00:00Z","trend":[],"nightTrend":[]}"#.utf8)

        let quote = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertEqual(quote.symbol, "AAPL")
        XCTAssertEqual(quote.pe, 31.2)
        XCTAssertEqual(quote.peStatic, 32.78)
        XCTAssertEqual(quote.peType, "ttm")
        XCTAssertEqual(quote.marketCap, 3_350_000_000_000)
        XCTAssertEqual(quote.netIncomeTTM, 122_575_000_000)
        XCTAssertEqual(quote.week52Low, 169.21)
        XCTAssertEqual(quote.fundamentalsCurrency, "USD")
        XCTAssertEqual(quote.fiscalYear, "2025")
        XCTAssertEqual(quote.fundamentalsSource, "TradingView")
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

    func testDecodesCompanyStaticAndTTMPEHistory() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"company_valuation_history_v2","symbol":"GOOGL","frequency":"daily","method":"fiscal_anchor_scaled_by_adjusted_daily_close","peStatic":[{"date":"2026-08-07","value":32.61},{"date":"2026-08-10","value":32.75}],"peTTM":[{"date":"2026-08-07","value":17.72},{"date":"2026-08-10","value":17.80}],"source":"TradingView","asOf":"2026-08-10T08:00:00Z"}}"#.utf8)

        let response = try JSONDecoder().decode(MarketCompanyValuationHistoryResponse.self, from: data)

        XCTAssertEqual(response.data.dataContract, MarketCompanyValuationHistory.dataContractV2)
        XCTAssertEqual(response.data.symbol, "GOOGL")
        XCTAssertEqual(response.data.frequency, MarketCompanyValuationHistory.dailyFrequency)
        XCTAssertEqual(response.data.method, MarketCompanyValuationHistory.dailyMethod)
        XCTAssertEqual(response.data.peStatic.last?.value, 32.75)
        XCTAssertEqual(response.data.peTTM.last?.value, 17.80)
        XCTAssertEqual(response.data.source, "TradingView")
    }

    func testCompanyPEDisplayPointsPreserveDailyRangeAndExtrema() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var points = (0..<1_000).map { index in
            CompanyPEChartPoint(
                date: start.addingTimeInterval(Double(index) * 86_400),
                value: 20 + Double(index % 17) / 10
            )
        }
        points[444] = CompanyPEChartPoint(date: points[444].date, value: 80)
        points[555] = CompanyPEChartPoint(date: points[555].date, value: 4)

        let displayPoints = marketCompanyPEDisplayPoints(points, maxCount: 80)

        XCTAssertLessThanOrEqual(displayPoints.count, 80)
        XCTAssertEqual(displayPoints.first?.date, points.first?.date)
        XCTAssertEqual(displayPoints.last?.date, points.last?.date)
        XCTAssertTrue(displayPoints.contains { $0.value == 80 })
        XCTAssertTrue(displayPoints.contains { $0.value == 4 })
        XCTAssertEqual(displayPoints.map(\.date), displayPoints.map(\.date).sorted())
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
        let data = Data(#"{"success":true,"data":{"dataContract":"market_investor_mood_v1","generatedAt":"2026-07-23T04:00:00Z","methodology":"public-video-sample","disclaimer":"观点样本来自公开视频，不代表整体市场情绪，不构成投资建议。","items":[{"nickname":"王小雨","awemeId":"123","description":"今天继续观察","url":"https://www.douyin.com/video/123","coverUrl":"https://example.com/cover.jpg","videoUrl":"https://video.example.com/123.mp4","createdAt":"2026-07-23T03:00:00Z","label":"观望","reasons":["等待方向"],"transcript":"今天继续观察，等待市场方向。","transcriptStatus":"字幕成功","analysis":"情绪保持中性。","evidence":["继续观察"],"analysisSource":"qwen","model":"qwen-vl","stale":false,"ageHours":1.0}]}}"#.utf8)
        let response = try JSONDecoder().decode(InvestorMoodResponse.self, from: data)
        XCTAssertEqual(response.data.dataContract, "market_investor_mood_v1")
        XCTAssertEqual(response.data.methodology, "public-video-sample")
        XCTAssertEqual(response.data.items.first?.nickname, "王小雨")
        XCTAssertEqual(response.data.items.first?.label, "观望")
        XCTAssertEqual(response.data.items.first?.analysis, "情绪保持中性。")
        XCTAssertEqual(response.data.items.first?.transcript, "今天继续观察，等待市场方向。")
        XCTAssertEqual(response.data.items.first?.videoUrl, "https://video.example.com/123.mp4")
        XCTAssertEqual(response.data.items.first?.directPlaybackURL?.absoluteString, "https://video.example.com/123.mp4")
        XCTAssertTrue(response.data.items.first?.playbackURL?.absoluteString.contains("/api/ios/v1/media-proxy?") == true)
        XCTAssertEqual(response.data.items.first?.directCoverURL?.absoluteString, "https://example.com/cover.jpg")
        XCTAssertTrue(response.data.items.first?.coverPlaybackURL?.absoluteString.contains("/api/ios/v1/media-proxy?") == true)
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
        XCTAssertEqual(response.interpretation?.timeline.first?.time, "00:18")
        XCTAssertEqual(response.estimatedCostCNY, 0.036)
        XCTAssertFalse(response.cached)
    }

    func testDecodesPendingInvestorVideoInterpretation() throws {
        let data = Data(#"{"success":true,"source_id":"123","status":"pending","provider":"","model":"","cached":false,"estimated_cost_cny":0}"#.utf8)

        let response = try JSONDecoder().decode(InvestorVideoInterpretationResponse.self, from: data)

        XCTAssertEqual(response.status, "pending")
        XCTAssertNil(response.interpretation)
    }

    func testDecodesMarketChartQualityContract() throws {
        let data = Data(#"{"success":true,"data":{"symbol":"000001.SS","market":"CN","tradingDate":"2026-07-22","timezone":"Asia/Shanghai","session":"regular","interval":"1m","periodReturn":{"range":"1d","basis":"previous-close","startPrice":3864.37,"endPrice":3883.58,"change":19.21,"percent":0.4971,"startTimestamp":null,"endTimestamp":1784691000000},"periodVolatility":{"range":"1d","basis":"annualized-log-returns","percent":18.42,"observationCount":118,"annualizationPeriods":98280},"quality":{"status":"repairing","expected":120,"actual":119,"missing":[{"startTimestamp":1784691000000,"endTimestamp":1784691000000}],"freshnessSeconds":35,"isFinal":false},"quote":{"price":3883.58,"previousClose":3864.37,"change":19.21,"changePercent":0.5,"providerTimestamp":1784691000000,"receivedTimestamp":1784691005000,"source":"eastmoney"},"candles":[{"timestamp":1784683860000,"open":3839.67,"high":3845.42,"low":3839.67,"close":3845.42,"volume":18226640,"state":"confirmed","source":"eastmoney","session":"regular"}]}}"#.utf8)
        let response = try JSONDecoder().decode(MarketChartResponse.self, from: data)
        XCTAssertEqual(response.data.quality.status, .repairing)
        XCTAssertEqual(response.data.quality.missing.count, 1)
        XCTAssertEqual(response.data.candles.first?.state, "confirmed")
        XCTAssertEqual(response.data.candles.first?.session, "regular")
        XCTAssertEqual(response.data.tradingDate, "2026-07-22")
        XCTAssertEqual(response.data.periodReturn?.basis, "previous-close")
        XCTAssertEqual(response.data.periodReturn?.percent, 0.4971)
        XCTAssertEqual(response.data.periodVolatility?.basis, "annualized-log-returns")
        XCTAssertEqual(response.data.periodVolatility?.percent, 18.42)
        XCTAssertEqual(response.data.periodVolatility?.observationCount, 118)
    }

    func testUnavailableEmptyStockChartRequestsAControlledRetry() throws {
        let data = Data(#"{"success":true,"data":{"symbol":"601398.SS","market":"CN","tradingDate":"2026-07-22","timezone":"Asia/Shanghai","session":"closed","interval":"1m","quality":{"status":"unavailable","expected":240,"actual":0,"missing":[],"freshnessSeconds":null,"isFinal":true},"quote":{"price":7.6,"previousClose":7.56,"change":0.04,"changePercent":0.53,"providerTimestamp":1784707014348,"receivedTimestamp":1784707014348,"source":"eastmoney"},"candles":[]}}"#.utf8)

        let response = try JSONDecoder().decode(MarketChartResponse.self, from: data)

        XCTAssertTrue(marketChartNeedsRetry(response.data))
        XCTAssertFalse(marketChartCanUseCache(response.data))
    }

    func test52WeekLowUsesValidCandleLows() throws {
        let data = Data(#"{"success":true,"data":{"symbol":"AAPL","market":"US","tradingDate":"2026-08-04","timezone":"America/New_York","session":"closed","interval":"1d","quality":{"status":"complete","expected":3,"actual":3,"missing":[],"freshnessSeconds":null,"isFinal":true},"quote":{"price":220,"previousClose":219,"change":1,"changePercent":0.46,"providerTimestamp":null,"receivedTimestamp":null,"source":"yahoo"},"candles":[{"timestamp":1,"open":210,"high":215,"low":205,"close":212,"volume":1,"state":"confirmed","source":"yahoo","session":"regular"},{"timestamp":2,"open":200,"high":210,"low":180,"close":205,"volume":1,"state":"invalid","source":"yahoo","session":"regular"},{"timestamp":3,"open":190,"high":220,"low":185.5,"close":220,"volume":1,"state":"confirmed","source":"yahoo","session":"regular"}]}}"#.utf8)

        let response = try JSONDecoder().decode(MarketChartResponse.self, from: data)

        XCTAssertEqual(market52WeekLow(response.data), 185.5)
    }

    func test52WeekLowRejectsPartialHistory() throws {
        let data = Data(#"{"success":true,"data":{"symbol":"AAPL","market":"US","tradingDate":"2026-08-04","timezone":"America/New_York","session":"closed","interval":"1d","quality":{"status":"partial","expected":6,"actual":6,"missing":[],"freshnessSeconds":null,"isFinal":true},"quote":{"source":"yahoo"},"candles":[{"timestamp":1,"open":210,"high":215,"low":205,"close":212,"volume":1,"state":"confirmed","source":"yahoo","session":"regular"}]}}"#.utf8)

        let response = try JSONDecoder().decode(MarketChartResponse.self, from: data)

        XCTAssertNil(market52WeekLow(response.data))
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

    func testExtendedSessionUsesSameDisplayedQuoteInListAndDetail() throws {
        let quote = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":217.56,"previousClose":219.74,"marketSession":"overnight","sessionPrice":219.195,"sessionChangePercent":-0.2480203877}"#.utf8)
        )

        XCTAssertEqual(quote.marketDisplayPrice, 219.195)
        XCTAssertEqual(quote.marketDisplayChangeValue, -0.545, accuracy: 0.0001)
        XCTAssertEqual(quote.marketDisplayPercentValue, -0.2480203877, accuracy: 0.0001)
        XCTAssertEqual(quote.marketDisplayFormattedPercent, "−0.25%")
    }

    func testRegularSessionKeepsSnapshotQuoteForDisplay() throws {
        let quote = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":217.56,"previousClose":219.74,"marketSession":"regular","sessionPrice":219.195,"sessionChangePercent":-0.248}"#.utf8)
        )

        XCTAssertEqual(quote.marketDisplayPrice, 217.56)
        XCTAssertEqual(quote.marketDisplayChangeValue, -2.18, accuracy: 0.0001)
        XCTAssertEqual(quote.marketDisplayPercentValue, quote.percentValue)
    }

    func testTrendBackfillProtectsRegionalLeadIndicesFromBoundedQueue() throws {
        let decoder = JSONDecoder()
        let regionalStocks = try (0..<30).map { index in
            try decoder.decode(
                MarketQuote.self,
                from: Data("{\"symbol\":\"STOCK\(index)\",\"name\":\"Stock \(index)\",\"price\":100,\"marketSession\":\"closed\",\"trend\":[]}".utf8)
            )
        }
        let leadIndices = try ["SPY", "000001.SS", "^N225", "^KS11", "^STOXX50E"].map { symbol in
            try decoder.decode(
                MarketQuote.self,
                from: Data("{\"symbol\":\"\(symbol)\",\"name\":\"Index\",\"price\":100,\"marketSession\":\"closed\",\"trend\":[]}".utf8)
            )
        }
        let dashboard = try decoder.decode(
            MarketDashboardResponse.self,
            from: Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v4","generatedAt":"2026-08-20T08:00:00Z","refreshIntervalMs":30000,"coreIndices":[],"referenceIndices":[],"realtimeProxies":[],"metrics":[],"componentsByRegion":{},"crypto":[],"missingSymbols":[],"expectedSymbols":[],"symbolHealth":[],"regions":[]}}"#.utf8)
        ).data
        var populatedDashboard = dashboard
        populatedDashboard.coreIndices = leadIndices
        populatedDashboard.componentsByRegion = ["us": regionalStocks]

        let symbols = marketTrendBackfillSymbols(for: populatedDashboard, limit: 24)

        XCTAssertEqual(Array(symbols.prefix(leadIndices.count)), leadIndices.map(\.symbol))
        XCTAssertTrue(symbols.contains("^N225"))
        XCTAssertEqual(symbols.count, 24)
    }

    func testTrendBackfillSkipsQuotesThatAlreadyHaveUsableTrends() throws {
        let decoder = JSONDecoder()
        let complete = try decoder.decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"SPY","name":"S&P 500","price":100,"marketSession":"closed","trend":[99,100]}"#.utf8)
        )
        let missing = try decoder.decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"^N225","name":"Nikkei 225","price":100,"marketSession":"closed","trend":[]}"#.utf8)
        )
        var dashboard = try decoder.decode(
            MarketDashboardResponse.self,
            from: Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v4","generatedAt":"2026-08-20T08:00:00Z","refreshIntervalMs":30000,"coreIndices":[],"referenceIndices":[],"realtimeProxies":[],"metrics":[],"componentsByRegion":{},"crypto":[],"missingSymbols":[],"expectedSymbols":[],"symbolHealth":[],"regions":[]}}"#.utf8)
        ).data
        dashboard.coreIndices = [complete, missing]

        XCTAssertEqual(marketTrendBackfillSymbols(for: dashboard), ["^N225"])
    }

    func testTradingSessionUsesExplicitSession() {
        XCTAssertEqual(MarketTradingSession(rawValue: "pre"), .premarket)
        XCTAssertEqual(MarketTradingSession(rawValue: "after"), .postmarket)
        XCTAssertEqual(MarketTradingSession(rawValue: nil), .unknown)
        XCTAssertEqual(MarketTradingSession(rawValue: "closed"), .closed)
        XCTAssertEqual(MarketTradingSession(rawValue: "pre").displayLabel, "盘前")
    }

    func testDashboardReplacementUsesSnapshotTrendExactly() throws {
        var dashboard = try JSONDecoder().decode(
            MarketDashboardResponse.self,
            from: Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v4","generatedAt":"2026-08-03T08:00:00Z","refreshIntervalMs":30000,"coreIndices":[],"referenceIndices":[],"realtimeProxies":[],"metrics":[],"componentsByRegion":{"us":[{"symbol":"NVDA","name":"英伟达","price":200,"marketSession":"pre","sessionPrice":201,"trend":[198,200],"nightTrend":[]}]},"crypto":[],"missingSymbols":[],"expectedSymbols":[],"symbolHealth":[],"regions":[]}}"#.utf8)
        ).data
        let replacement = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":200.5,"marketSession":"pre","sessionPrice":201.5,"trend":[],"nightTrend":[]}"#.utf8)
        )

        dashboard.replace(replacement)

        XCTAssertEqual(dashboard.componentsByRegion["us"]?.first?.nightTrend, [])
        XCTAssertEqual(dashboard.componentsByRegion["us"]?.first?.trend, [])
    }

    @MainActor
    func testPremarketQuoteUsesDashboardCurrentSessionTrend() throws {
        let quote = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":200.75,"previousClose":195.04,"marketSession":"pre","sessionPrice":200.84,"sessionChangePercent":2.97,"trend":[200.1,200.4,200.84]}"#.utf8)
        )
        let store = MarketStore()

        XCTAssertEqual(quote.trend, [200.1, 200.4, 200.84])
        XCTAssertEqual(store.trendValues(for: quote), quote.trend)
        XCTAssertFalse(marketQuoteNeedsTrendBackfill(quote))
        XCTAssertEqual(quote.sessionPrice, 200.84)
        XCTAssertTrue(quote.hasActiveExtendedSessionQuote)
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
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v4","generatedAt":"2026-07-16T10:00:00Z","refreshIntervalMs":15000,"coreIndices":[],"metrics":[],"componentsByRegion":{},"crypto":[{"symbol":"BINANCE:BTCUSDT","name":"比特币","price":79591.91,"previousClose":78000,"marketSession":"always-open","changePercent":"2.04%"}],"missingSymbols":[]}}"#.utf8)

        let response = try JSONDecoder().decode(MarketDashboardResponse.self, from: data)

        XCTAssertEqual(response.data.crypto.map(\.symbol), ["BINANCE:BTCUSDT"])
        XCTAssertEqual(response.data.quote(symbol: "BINANCE:BTCUSDT")?.name, "比特币")
        XCTAssertEqual(response.data.crypto.first?.freshnessLabel, "24小时交易")
    }

    func testDashboardDecodesCommodityQuotes() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v4","definitionVersion":"2026-08-12.1","generatedAt":"2026-08-12T10:00:00Z","refreshIntervalMs":30000,"coreIndices":[],"referenceIndices":[],"realtimeProxies":[],"metrics":[],"componentsByRegion":{},"crypto":[],"commodities":[{"symbol":"GC1!","name":"COMEX 黄金","instrumentType":"commodity-future","displayMode":"continuous-front-month","priceUnit":"美元/盎司","price":3310.5,"previousClose":3290,"marketSession":"regular","delaySeconds":600,"trend":[3290,3300,3310.5]}],"missingSymbols":[],"expectedSymbols":["GC1!"],"symbolHealth":[],"regions":[{"id":"commodity","metricSymbols":["GC1!"]}]}}"#.utf8)
        let response = try JSONDecoder().decode(MarketDashboardResponse.self, from: data)
        let gold = try XCTUnwrap(response.data.commodities.first)

        XCTAssertEqual(gold.detailInstrumentLabel, "黄金主连 · 连续主力合约 · 美元/盎司")
        XCTAssertEqual(gold.visibleDelayMinutes, 10)
        XCTAssertEqual(response.data.quote(symbol: "GC1!")?.price, 3310.5)
    }

    func testCommodityLogoKindsCoverDashboardSymbols() {
        let symbols = ["GC1!", "CL1!", "HG1!", "SI1!", "NG1!", "ZC1!", "LE1!", "GF1!", "HE1!"]
        let kinds = symbols.compactMap(CommodityLogoKind.init(symbol:))

        XCTAssertEqual(kinds.count, symbols.count)
        XCTAssertEqual(Set(kinds.map(\.logoText)), Set(["Au", "WTI", "Cu", "Ag", "NG", "ZC", "🐂", "🐄", "🐖"]))
        XCTAssertTrue(CommodityLogoKind(symbol: "LE1!")?.isLivestock == true)
        XCTAssertTrue(CommodityLogoKind(symbol: "GF1!")?.isLivestock == true)
        XCTAssertTrue(CommodityLogoKind(symbol: "HE1!")?.isLivestock == true)
        XCTAssertNil(CommodityLogoKind(symbol: "ES1!"))
    }

    func testDashboardDecodesV4RealtimeProxyContract() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v4","definitionVersion":"2026-07-29.2","generatedAt":"2026-07-30T07:26:57Z","refreshIntervalMs":30000,"coreIndices":[{"symbol":"SPY","name":"标普500实时代理（SPY）","displayName":"标普500实时代理（SPY）","instrumentType":"realtime-proxy-etf","proxyFor":"^GSPC","referenceSymbol":"^GSPC","historicalSymbol":"^GSPC","price":729.46}],"referenceIndices":[{"symbol":"^GSPC","name":"标普500","instrumentType":"reference-index","displayMode":"historical-reference","price":7316.15}],"realtimeProxies":[{"symbol":"SPY","referenceSymbol":"^GSPC","historicalSymbol":"^GSPC","displayName":"标普500实时代理（SPY）"}],"metrics":[],"componentsByRegion":{},"crypto":[],"indexSessions":{},"missingSymbols":[],"expectedSymbols":["SPY","^GSPC"],"symbolHealth":[],"regions":[]}}"#.utf8)

        let response = try JSONDecoder().decode(MarketDashboardResponse.self, from: data)
        let proxy = try XCTUnwrap(response.data.coreIndices.first)

        XCTAssertEqual(response.data.dataContract, "market_dashboard_v4")
        XCTAssertEqual(proxy.symbol, "SPY")
        XCTAssertEqual(proxy.presentationName, "标普500实时代理（SPY）")
        XCTAssertEqual(proxy.instrumentType, "realtime-proxy-etf")
        XCTAssertEqual(proxy.proxyFor, "^GSPC")
        XCTAssertEqual(proxy.historicalSymbol, "^GSPC")
        XCTAssertEqual(response.data.referenceIndices.first?.symbol, "^GSPC")
        XCTAssertEqual(response.data.realtimeProxies.first?.symbol, "SPY")
        XCTAssertEqual(response.data.quote(symbol: "^GSPC")?.displayMode, "historical-reference")
    }

    func testDashboardRejectsLegacyComponentsOnlyContract() {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v3","generatedAt":"2026-08-03T08:00:00Z","refreshIntervalMs":30000,"coreIndices":[],"metrics":[],"components":[{"symbol":"NVDA","name":"英伟达","price":180}],"crypto":[]}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(MarketDashboardResponse.self, from: data))
    }

    func testDashboardDecodesRegionalCoreStocksIncludingGoogle() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v4","definitionVersion":"2026-08-03.1","generatedAt":"2026-08-03T08:00:00Z","refreshIntervalMs":30000,"coreIndices":[],"referenceIndices":[],"realtimeProxies":[],"metrics":[],"componentsByRegion":{"us":[{"symbol":"NVDA","name":"英伟达","price":180},{"symbol":"GOOGL","name":"谷歌","price":201}],"jp":[{"symbol":"7203.T","name":"丰田汽车","price":3200}]},"crypto":[],"missingSymbols":[],"expectedSymbols":[],"symbolHealth":[],"regions":[]}}"#.utf8)

        let dashboard = try JSONDecoder().decode(MarketDashboardResponse.self, from: data).data

        XCTAssertEqual(dashboard.componentsByRegion["us"]?.map(\.symbol), ["NVDA", "GOOGL"])
        XCTAssertEqual(dashboard.componentsByRegion["jp"]?.map(\.symbol), ["7203.T"])
        XCTAssertEqual(dashboard.quote(symbol: "GOOGL")?.presentationName, "谷歌")
    }

    func testDashboardSkipsQuotesWithNullPriceWithoutDroppingValidData() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v4","generatedAt":"2026-08-02T08:09:10Z","refreshIntervalMs":30000,"coreIndices":[{"symbol":"SPY","name":"标普500实时代理","price":632.08}],"referenceIndices":[],"metrics":[{"symbol":"USDJPY","name":"美元兑日元","price":null,"lastKnownPrice":157.4,"stale":true},{"symbol":"^VIX","name":"波动率指数","price":16.72}],"componentsByRegion":{"us":[{"symbol":"NVDA","name":"英伟达","price":null,"stale":true},{"symbol":"GOOGL","name":"谷歌","price":201}]},"crypto":[],"indexSessions":{"SPY":{"symbol":"SPY","name":"标普500盘后","price":null,"stale":true}},"missingSymbols":[],"expectedSymbols":["SPY","USDJPY","^VIX"],"symbolHealth":[{"symbol":"USDJPY","status":"stale","reason":"quote_stale"}],"regions":[]}}"#.utf8)

        let response = try JSONDecoder().decode(MarketDashboardResponse.self, from: data)

        XCTAssertEqual(response.data.coreIndices.map(\.symbol), ["SPY"])
        XCTAssertEqual(response.data.metrics.map(\.symbol), ["^VIX"])
        XCTAssertEqual(response.data.componentsByRegion["us"]?.map(\.symbol), ["GOOGL"])
        XCTAssertEqual(response.data.indexSessions, [:])
        XCTAssertEqual(response.data.symbolHealth.first?.symbol, "USDJPY")
        XCTAssertEqual(response.data.symbolHealth.first?.status, .stale)
    }

    func testDashboardDecodesPerSymbolHealthAndRegions() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v4","definitionVersion":"2026-07-21.1","generatedAt":"2026-07-21T10:00:00Z","refreshIntervalMs":15000,"coreIndices":[],"metrics":[],"componentsByRegion":{},"crypto":[],"missingSymbols":["JP10Y"],"expectedSymbols":["JP10Y","KR10Y"],"symbolHealth":[{"symbol":"JP10Y","status":"missing","reason":"quote_unavailable"},{"symbol":"KR10Y","status":"delayed","delaySeconds":15}],"regions":[{"id":"jp","metricSymbols":["USDJPY","JP10Y","^TOPX"]}]}}"#.utf8)

        let response = try JSONDecoder().decode(MarketDashboardResponse.self, from: data)

        XCTAssertEqual(response.data.definitionVersion, "2026-07-21.1")
        XCTAssertEqual(response.data.symbolHealth.first?.status, .missing)
        XCTAssertEqual(response.data.symbolHealth.last?.delaySeconds, 15)
        XCTAssertEqual(response.data.regions.first?.metricSymbols, ["USDJPY", "JP10Y", "^TOPX"])
    }

    func testDashboardDecodesChinaMarketStructureSignals() throws {
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v4","generatedAt":"2026-07-22T10:00:00Z","refreshIntervalMs":15000,"coreIndices":[],"metrics":[],"componentsByRegion":{},"crypto":[],"missingSymbols":[],"marketStructure":{"dataContract":"market_structure_v2","generatedAt":"2026-07-22T09:00:00Z","etfSubscription":{"fundCode":"588000","fundName":"科创50ETF合计","fundCount":8,"fundCodes":["588000","588080"],"asOf":"2026-07-21","status":"accelerating","latestShares":45512668200,"latestNetSubscriptionShares":423000000,"latestEstimatedNetFlowCNY":861429000,"estimatedFlowFundCount":8,"netSubscriptionShares5d":900000000,"previousNetShares5d":500000000,"positiveDays5d":4,"consecutiveDirection":"inflow","consecutiveDays":2,"points":[{"date":"2026-07-21","totalShares":45512668200,"netSubscriptionShares":423000000}]},"marginBalance":{"asOf":"2026-07-21","status":"stabilizing","financingBalance":2689521390293,"securitiesBalance":20402350759,"totalBalance":2709923741052,"latestChange":1086577120,"change3d":-1200000000,"change5d":-5100000000,"positiveDays5d":2,"financingBuyAmount":267012306205,"aShareTurnover":2960321000000,"financingBuyRatio":9.02,"activityStatus":"active","points":[{"date":"2026-07-21","financingBalance":2689521390293,"securitiesBalance":20402350759,"totalBalance":2709923741052,"dailyChange":1086577120,"financingBuyAmount":267012306205}]},"combinedSignal":{"status":"allocation_support","title":"配置资金承接，杠杆仍谨慎","summary":"ETF资金保持流入，但两融余额尚未企稳。"},"sources":[{"name":"上交所","url":"https://www.sse.com.cn/"}]}}}"#.utf8)

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
        let data = Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v4","generatedAt":"2026-07-22T10:00:00Z","refreshIntervalMs":15000,"coreIndices":[],"metrics":[],"componentsByRegion":{},"crypto":[],"missingSymbols":[],"ashareOverview":{"breadth":{"Up":2219,"Down":3202,"Flat":94,"Total":5515},"hotSectors":[],"stale":true}}}"#.utf8)

        let response = try JSONDecoder().decode(MarketDashboardResponse.self, from: data)

        XCTAssertTrue(response.data.ashareOverview?.stale == true)
        XCTAssertNil(response.data.currentAShareBreadth)
    }

    func testDelayedOpenMarketQuoteExplainsSourceDelay() throws {
        let data = Data(#"{"symbol":"^NDX","name":"纳斯达克100","price":23000,"marketSession":"regular","delaySeconds":900}"#.utf8)
        let quote = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertEqual(quote.visibleDelayMinutes, 15)
        XCTAssertEqual(quote.freshnessLabel, "延迟15分钟")
    }

    func testSubminuteTransportLatencyDoesNotPresentAsOneMinuteDelay() throws {
        let data = Data(#"{"symbol":"THS:883418","name":"微盘股","price":1000,"marketSession":"regular","delaySeconds":59}"#.utf8)
        let quote = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertNil(quote.visibleDelayMinutes)
        XCTAssertEqual(quote.freshnessLabel, "交易中")
    }

    func testOneMinuteTransportLatencyPresentsDelayIndicator() throws {
        let data = Data(#"{"symbol":"THS:883418","name":"微盘股","price":1000,"marketSession":"regular","delaySeconds":60}"#.utf8)
        let quote = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertEqual(quote.visibleDelayMinutes, 1)
        XCTAssertEqual(quote.freshnessLabel, "延迟1分钟")
    }

    func testClosedQuoteUsesTradingDateInsteadOfProviderReceiptTime() throws {
        let data = Data(#"{"symbol":"^STOXX50E","name":"欧洲STOXX 50","price":6523.87,"marketSession":"closed","delaySeconds":900,"timestamp":1786285136181,"quality":{"status":"delayed","reason":"official_close","asOfTimestamp":1786116600000,"tradingDate":"2026-08-07","fallbackUsed":false}}"#.utf8)
        let quote = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertNil(quote.visibleDelayMinutes)
        XCTAssertEqual(quote.freshnessLabel, "截至 2026-08-07 收盘")
        XCTAssertEqual(quote.marketAsOfLabel, "2026-08-07 收盘行情")
    }

    func testRealtimeUpdateClearsPreviousDelayIndicator() throws {
        let quote = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"1211.HK","name":"比亚迪股份","price":92.25,"marketSession":"regular","delaySeconds":900}"#.utf8)
        )
        let update = try JSONDecoder().decode(
            MarketQuoteUpdate.self,
            from: Data(#"{"symbol":"1211.HK","name":"比亚迪股份","price":92.6,"marketSession":"regular","delaySeconds":0}"#.utf8)
        )

        let merged = update.merging(into: quote)

        XCTAssertEqual(merged.delaySeconds, 0)
        XCTAssertNil(merged.visibleDelayMinutes)
        XCTAssertEqual(merged.freshnessLabel, "交易中")
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

    func testPremarketRealtimeUpdateAppendsSessionPriceToVisibleTrend() throws {
        let current = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":200.75,"marketSession":"pre","sessionPrice":200.84,"receivedAt":100,"trend":[200.1,200.4,200.84],"nightTrend":[200.84]}"#.utf8)
        )
        let update = try JSONDecoder().decode(
            MarketQuoteUpdate.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":200.75,"marketSession":"pre","sessionPrice":200.9,"receivedAt":200}"#.utf8)
        )

        let merged = update.merging(into: current)
        let repeated = update.merging(into: merged)

        XCTAssertEqual(merged.trend, [200.1, 200.4, 200.84])
        XCTAssertEqual(merged.liveTrendValue, 200.9)
        XCTAssertEqual(merged.nightTrend, [200.84, 200.9])
        XCTAssertEqual(repeated.trend, merged.trend)
        XCTAssertEqual(repeated.liveTrendValue, merged.liveTrendValue)
        XCTAssertEqual(repeated.nightTrend, merged.nightTrend)
    }

    func testExtendedRealtimeUpdateWithoutSessionPriceDoesNotAppendRegularPrice() throws {
        let current = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":200.75,"marketSession":"pre","sessionPrice":200.84,"trend":[200.1,200.4,200.84],"nightTrend":[200.84]}"#.utf8)
        )
        let update = try JSONDecoder().decode(
            MarketQuoteUpdate.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":201.2,"marketSession":"pre","receivedAt":200}"#.utf8)
        )

        let merged = update.merging(into: current)

        XCTAssertEqual(merged.trend, current.trend)
        XCTAssertNil(merged.liveTrendValue)
        XCTAssertEqual(merged.nightTrend, current.nightTrend)
        XCTAssertEqual(merged.sessionPrice, current.sessionPrice)
    }

    func testRegularRealtimeUpdateStartsRegularTrendAndClearsExtendedFields() throws {
        let current = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":200.75,"marketSession":"pre","sessionPrice":200.84,"sessionChangePercent":2.3,"sessionDataSource":"TradingView","trend":[200.1,200.4,200.84],"nightTrend":[200.84]}"#.utf8)
        )
        let update = try JSONDecoder().decode(
            MarketQuoteUpdate.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":201.2,"marketSession":"regular","sessionPrice":199,"sessionChangePercent":-1,"sessionDataSource":"stale","receivedAt":200}"#.utf8)
        )

        let merged = update.merging(into: current)

        XCTAssertEqual(merged.trend, [])
        XCTAssertEqual(merged.liveTrendValue, 201.2)
        XCTAssertEqual(merged.nightTrend, [])
        XCTAssertNil(merged.sessionPrice)
        XCTAssertNil(merged.sessionChangePercent)
        XCTAssertNil(merged.sessionDataSource)
    }

    func testDashboardRealtimeOverlayKeepsFreshSnapshotTrend() throws {
        var dashboard = try JSONDecoder().decode(
            MarketDashboardResponse.self,
            from: Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v4","generatedAt":"2026-08-10T10:24:08Z","refreshIntervalMs":30000,"coreIndices":[],"referenceIndices":[],"realtimeProxies":[],"metrics":[],"componentsByRegion":{"us":[{"symbol":"NVDA","name":"英伟达","price":300,"marketSession":"pre","sessionPrice":302,"timestamp":500,"receivedAt":500,"quality":{"status":"live"},"trend":[300,301,302]}]},"crypto":[],"missingSymbols":[],"expectedSymbols":[],"symbolHealth":[],"regions":[]}}"#.utf8)
        ).data
        let update = try JSONDecoder().decode(
            MarketQuoteUpdate.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":299,"marketSession":"pre","sessionPrice":303,"timestamp":499,"receivedAt":501}"#.utf8)
        )

        dashboard.merge(update)

        XCTAssertEqual(dashboard.quote(symbol: "NVDA")?.trend, [300, 301, 302])
        XCTAssertEqual(dashboard.quote(symbol: "NVDA")?.liveTrendValue, 303)
        XCTAssertEqual(dashboard.quote(symbol: "NVDA")?.receivedAt, 501)
        XCTAssertNil(dashboard.quote(symbol: "NVDA")?.quality)
    }

    func testDashboardRealtimeOverlayRejectsOlderReceipt() throws {
        var dashboard = try JSONDecoder().decode(
            MarketDashboardResponse.self,
            from: Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v4","generatedAt":"2026-08-10T10:24:08Z","refreshIntervalMs":30000,"coreIndices":[],"referenceIndices":[],"realtimeProxies":[],"metrics":[],"componentsByRegion":{"us":[{"symbol":"NVDA","name":"英伟达","price":300,"marketSession":"pre","sessionPrice":302,"receivedAt":500,"trend":[300,301,302]}]},"crypto":[],"missingSymbols":[],"expectedSymbols":[],"symbolHealth":[],"regions":[]}}"#.utf8)
        ).data
        let update = try JSONDecoder().decode(
            MarketQuoteUpdate.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":299,"marketSession":"pre","sessionPrice":299,"receivedAt":499}"#.utf8)
        )

        dashboard.merge(update)

        XCTAssertEqual(dashboard.quote(symbol: "NVDA")?.trend, [300, 301, 302])
        XCTAssertEqual(dashboard.quote(symbol: "NVDA")?.receivedAt, 500)
    }

    func testDashboardRealtimeOverlayFindsIndexSessionByQuoteSymbol() throws {
        var dashboard = try JSONDecoder().decode(
            MarketDashboardResponse.self,
            from: Data(#"{"success":true,"data":{"dataContract":"market_dashboard_v4","generatedAt":"2026-08-10T10:24:08Z","refreshIntervalMs":30000,"coreIndices":[],"referenceIndices":[],"realtimeProxies":[],"metrics":[],"componentsByRegion":{},"crypto":[],"indexSessions":{"SPY":{"symbol":"ES1!","name":"E-mini","price":7500,"marketSession":"regular","receivedAt":500,"trend":[7498,7499,7500]}},"missingSymbols":[],"expectedSymbols":[],"symbolHealth":[],"regions":[]}}"#.utf8)
        ).data
        let update = try JSONDecoder().decode(
            MarketQuoteUpdate.self,
            from: Data(#"{"symbol":"ES1!","name":"E-mini","price":7501,"marketSession":"regular","receivedAt":501}"#.utf8)
        )

        dashboard.merge(update)

        XCTAssertEqual(dashboard.quote(symbol: "ES1!")?.trend, [7498, 7499, 7500])
        XCTAssertEqual(dashboard.quote(symbol: "ES1!")?.liveTrendValue, 7501)
        XCTAssertEqual(dashboard.indexSessions?["SPY"]?.trend, [7498, 7499, 7500])
        XCTAssertEqual(dashboard.indexSessions?["SPY"]?.liveTrendValue, 7501)
    }

    @MainActor
    func testHighFrequencyRealtimeUpdatesKeepFortyMinuteSnapshotPoints() throws {
        let snapshot = (1...40).map(Double.init)
        var quote = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":40,"marketSession":"pre","sessionPrice":40,"receivedAt":100,"trend":[]}"#.utf8)
        )
        quote.trend = snapshot

        for offset in 1...100 {
            let value = 40 + Double(offset) / 100
            let update = try JSONDecoder().decode(
                MarketQuoteUpdate.self,
                from: Data("{\"symbol\":\"NVDA\",\"name\":\"英伟达\",\"price\":40,\"marketSession\":\"pre\",\"sessionPrice\":\(value),\"receivedAt\":\(100 + offset)}".utf8)
            )
            quote = update.merging(into: quote)
        }

        XCTAssertEqual(quote.trend, snapshot)
        XCTAssertEqual(quote.liveTrendValue, 41)
        let displayed = MarketStore().trendValues(for: quote)
        XCTAssertEqual(displayed.count, 40)
        XCTAssertEqual(displayed.last, 41)
        XCTAssertEqual(displayed.dropLast(), snapshot.suffix(39))
    }

    func testRealtimeReceiptOrderingRejectsMissingAndRegressiveUpdates() throws {
        let current = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":300,"receivedAt":500}"#.utf8)
        )
        let cached = try JSONDecoder().decode(
            MarketQuoteUpdate.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":301,"receivedAt":501}"#.utf8)
        )
        let missing = try JSONDecoder().decode(
            MarketQuoteUpdate.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":302}"#.utf8)
        )
        let older = try JSONDecoder().decode(
            MarketQuoteUpdate.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":302,"receivedAt":500}"#.utf8)
        )
        let equal = try JSONDecoder().decode(
            MarketQuoteUpdate.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":302,"receivedAt":501}"#.utf8)
        )

        XCTAssertFalse(marketRealtimeUpdateIsCurrent(missing, current: current, cached: cached))
        XCTAssertFalse(marketRealtimeUpdateIsCurrent(older, current: current, cached: cached))
        XCTAssertTrue(marketRealtimeUpdateIsCurrent(equal, current: current, cached: cached))
    }

    func testConstituentRealtimeMergeRejectsOlderReceipt() throws {
        let responseData = Data(#"{"indexSymbol":"^NDX","label":"主要成分股","selectionBasis":"test","asOf":"2026-08-10","generatedAt":"2026-08-10T10:00:00Z","items":[{"rank":1,"detailAvailable":true,"quote":{"symbol":"NVDA","name":"英伟达","price":300,"marketSession":"pre","sessionPrice":301,"receivedAt":500,"trend":[299,300,301]}}],"missingSymbols":[]}"#.utf8)
        let updateData = Data(#"{"symbol":"NVDA","name":"英伟达","price":299,"marketSession":"pre","sessionPrice":299,"receivedAt":499}"#.utf8)
        var constituents = try JSONDecoder().decode(MarketIndexConstituents.self, from: responseData)
        let update = try JSONDecoder().decode(MarketQuoteUpdate.self, from: updateData)

        constituents.merge(update)

        XCTAssertEqual(constituents.items[0].quote.price, 300)
        XCTAssertEqual(constituents.items[0].quote.trend, [299, 300, 301])
        XCTAssertNil(constituents.items[0].quote.liveTrendValue)
    }

    func testSessionChangeClearsCloseOnlyMetadata() throws {
        let current = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":300,"marketSession":"closed","delaySeconds":900,"timestamp":400,"receivedAt":500,"quality":{"status":"delayed","reason":"official_close","asOfTimestamp":300,"tradingDate":"2026-08-07"},"trend":[298,299,300]}"#.utf8)
        )
        let update = try JSONDecoder().decode(
            MarketQuoteUpdate.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":301,"marketSession":"regular","timestamp":501,"receivedAt":501}"#.utf8)
        )

        let merged = update.merging(into: current)

        XCTAssertNil(merged.delaySeconds)
        XCTAssertNil(merged.quality)
        XCTAssertEqual(merged.marketAsOfTimestamp, 501)
    }

    func testClientLiveTrendTailIsNotPersistedInSnapshotCache() throws {
        let current = try JSONDecoder().decode(
            MarketQuote.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":300,"marketSession":"pre","sessionPrice":301,"receivedAt":500,"trend":[299,300,301]}"#.utf8)
        )
        let update = try JSONDecoder().decode(
            MarketQuoteUpdate.self,
            from: Data(#"{"symbol":"NVDA","name":"英伟达","price":300,"marketSession":"pre","sessionPrice":302,"receivedAt":501}"#.utf8)
        )
        let merged = update.merging(into: current)

        let restored = try JSONDecoder().decode(MarketQuote.self, from: JSONEncoder().encode(merged))

        XCTAssertEqual(merged.liveTrendValue, 302)
        XCTAssertNil(restored.liveTrendValue)
        XCTAssertEqual(restored.trend, current.trend)
    }

    func testRealtimeNightQuoteDecodesAsIncrementAndAppendsNightPrice() throws {
        let data = Data(#"{"symbol":"NVDA","name":"英伟达","price":212.5,"previousClose":211.8,"marketSession":"overnight","sessionPrice":212.49,"sessionChangePercent":0.3257,"timestamp":1784174184396}"#.utf8)
        let update = try JSONDecoder().decode(MarketQuoteUpdate.self, from: data)
        let quote = update.merging(into: nil)

        XCTAssertEqual(quote.symbol, "NVDA")
        XCTAssertEqual(quote.sessionPrice, 212.49)
        XCTAssertEqual(quote.trend, [])
        XCTAssertEqual(quote.liveTrendValue, 212.49)
        XCTAssertEqual(quote.nightTrend, [212.49])
        XCTAssertEqual(quote.tradingSession, .overnight)
    }

    func testExtendedSessionDisplayFallsBackToMarketSession() throws {
        let data = Data(#"{"symbol":"NVDA","name":"英伟达","price":196.51,"previousClose":206.84,"marketSession":"overnight","sessionPrice":196.54,"sessionChangePercent":-4.98}"#.utf8)
        let quote = try JSONDecoder().decode(MarketQuote.self, from: data)

        XCTAssertTrue(quote.hasActiveExtendedSessionQuote)
    }

    func testRealtimeUpdatePreservesConstituentNightTrend() throws {
        let responseData = Data(#"{"indexSymbol":"^NDX","label":"主要成分股","selectionBasis":"test","asOf":"2026-07-16","generatedAt":"2026-07-16T05:00:00Z","items":[{"rank":1,"weight":null,"logoPath":null,"detailAvailable":true,"quote":{"symbol":"NVDA","name":"英伟达","price":212.5,"previousClose":211.8,"marketSession":"overnight","sessionPrice":212.49,"timestamp":1784174184000,"receivedAt":1784174184000,"trend":[210,211],"nightTrend":[212.1,212.2,212.3]}}],"missingSymbols":[]}"#.utf8)
        let updateData = Data(#"{"symbol":"NVDA","name":"英伟达","price":212.5,"previousClose":211.8,"marketSession":"overnight","sessionPrice":212.49,"sessionChangePercent":0.3257,"timestamp":1784174184396,"receivedAt":1784174184396}"#.utf8)
        var constituents = try JSONDecoder().decode(MarketIndexConstituents.self, from: responseData)
        let update = try JSONDecoder().decode(MarketQuoteUpdate.self, from: updateData)

        constituents.merge(update)

        XCTAssertEqual(constituents.items[0].quote.nightTrend, [212.1, 212.2, 212.3, 212.49])
        XCTAssertEqual(constituents.items[0].quote.trend, [210, 211])
        XCTAssertEqual(constituents.items[0].quote.liveTrendValue, 212.49)
    }

    func testConstituentContractRequiresDetailAvailability() {
        let data = Data(#"{"indexSymbol":"^NDX","label":"主要成分股","selectionBasis":"test","asOf":"2026-08-09","generatedAt":"2026-08-09T14:00:00Z","items":[{"rank":1,"quote":{"symbol":"NVDA","name":"英伟达","price":212.5}}],"missingSymbols":[]}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(MarketIndexConstituents.self, from: data))
    }

    func testMarketRangesUseExpectedIntervalsAndLimits() {
        XCTAssertEqual(MarketRange.day.apiInterval, "1m")
        XCTAssertEqual(MarketRange.week.apiRange, "5d")
        XCTAssertEqual(MarketRange.week.apiInterval, "15m")
        XCTAssertEqual(MarketRange.week.apiLimit, 1_000)
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

    func testChartPresentationPrecomputesStableDrawingInputs() throws {
        let data = Data(#"""
        {
          "symbol":"TEST","market":"US","tradingDate":"2026-08-20",
          "timezone":"America/New_York","session":"regular","interval":"1m",
          "quality":{"status":"complete","expected":3,"actual":3,"missing":[],"freshnessSeconds":0,"isFinal":true},
          "quote":{"previousClose":10,"changePercent":10,"source":"test"},
          "candles":[
            {"timestamp":3,"open":11,"high":12,"low":10,"close":12,"volume":300,"state":"confirmed","source":"test","session":"regular"},
            {"timestamp":1,"open":9,"high":10,"low":8,"close":10,"volume":100,"state":"confirmed","source":"test","session":"regular"},
            {"timestamp":2,"open":10,"high":11,"low":9,"close":11,"volume":200,"state":"confirmed","source":"test","session":"regular"},
            {"timestamp":4,"open":12,"high":12,"low":12,"close":12,"volume":400,"state":"invalid","source":"test","session":"regular"}
          ]
        }
        """#.utf8)
        let chart = try JSONDecoder().decode(MarketChart.self, from: data)

        let presentation = MarketChartPresentation(chart: chart)

        XCTAssertEqual(presentation.points.map(\.timestamp), [1, 2, 3])
        XCTAssertEqual(presentation.values, [10, 11, 12])
        XCTAssertEqual(presentation.xFractions, [0, 0.5, 1])
        XCTAssertEqual(presentation.low, 8)
        XCTAssertEqual(presentation.high, 12)
        XCTAssertTrue(presentation.hasVolume)
        XCTAssertEqual(presentation.volumeCeiling, 200)
        XCTAssertEqual(presentation.volumeFractionGap, 0.5)
    }

    func testMarketSampledChartTrendUsesWholeDayAndKeepsEndpoints() {
        var points: [MarketChartPoint] = []
        for index in 0..<120 {
            let value = Double(index + 1)
            let point = MarketChartPoint(
                timestamp: Int64(index), open: value, high: value,
                low: value, close: value, volume: nil,
                state: "confirmed", source: "tradingview", session: "regular"
            )
            points.append(point)
        }

        let values = marketSampledChartTrend(points, limit: 40)

        XCTAssertEqual(values.count, 40)
        XCTAssertEqual(values.first, 1)
        XCTAssertEqual(values.last, 120)
        XCTAssertTrue(values.contains { $0 > 40 && $0 < 80 })
    }

    func testMarketListTrendKeepsRichSnapshotWhenChartOnlyHasEndpoints() {
        let snapshot = [10.0, 11.0, 10.5, 12.0]

        let values = marketPreferredListTrend(
            chartValues: [10.0, 12.0],
            snapshotValues: snapshot
        )

        XCTAssertEqual(values, snapshot)
    }

    func testMarketListTrendUsesChartOnceItHasShape() {
        let chart = [10.0, 11.0, 10.5]

        let values = marketPreferredListTrend(
            chartValues: chart,
            snapshotValues: [9.0, 9.5, 10.0, 10.5]
        )

        XCTAssertEqual(values, chart)
    }

    func testMarketListTrendStillUsesTwoPointChartWithoutRichFallback() {
        let chart = [10.0, 12.0]

        let values = marketPreferredListTrend(
            chartValues: chart,
            snapshotValues: [10.0]
        )

        XCTAssertEqual(values, chart)
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

    func testMovingAverageStartsAfterFullPeriod() {
        let points = (1...5).map { chartPoint(timestamp: Int64($0), close: Double($0)) }

        let values = marketMovingAverageValues(points, period: 3)

        XCTAssertNil(values[0])
        XCTAssertNil(values[1])
        XCTAssertEqual(values[2], 2)
        XCTAssertEqual(values[3], 3)
        XCTAssertEqual(values[4], 4)
    }

    func testEvenChartFractionsCoverFullPlot() {
        XCTAssertEqual(marketEvenChartFractions(count: 3), [0, 0.5, 1])
        XCTAssertEqual(marketEvenChartFractions(count: 1), [0.5])
        XCTAssertEqual(marketEvenChartFractions(count: 0), [])
    }

    func testNearestChartIndexClampsAndSelectsClosestPoint() {
        let fractions: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]
        XCTAssertEqual(marketNearestChartIndex(fraction: -1, fractions: fractions), 0)
        XCTAssertEqual(marketNearestChartIndex(fraction: 0.62, fractions: fractions), 2)
        XCTAssertEqual(marketNearestChartIndex(fraction: 2, fractions: fractions), 4)
    }

    func testLeadSparklineDoesNotExaggerateTinyRelativeMoves() {
        let bounds = marketSparklineBounds([7_686, 7_691], minimumRelativeRange: 0.0025)

        XCTAssertEqual(bounds.upper - bounds.lower, 7_691 * 0.0025, accuracy: 0.001)
        XCTAssertLessThanOrEqual(bounds.lower, 7_686)
        XCTAssertGreaterThanOrEqual(bounds.upper, 7_691)
    }

    func testLeadSparklineKeepsRealRangeWhenMovementIsLarger() {
        let bounds = marketSparklineBounds([100, 104, 102], minimumRelativeRange: 0.0025)

        XCTAssertEqual(bounds, MarketSparklineBounds(lower: 100, upper: 104))
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
