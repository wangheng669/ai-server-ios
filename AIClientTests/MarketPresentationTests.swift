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

private final class MarketRequestProbeProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var recorded: [URLRequest] = []
    private static var payloads: [Data] = []
    private static var onRequest: (() -> Void)?

    static func reset(payloads: [Data] = [], onRequest: (() -> Void)? = nil) {
        lock.lock()
        defer { lock.unlock() }
        recorded = []
        Self.payloads = payloads
        Self.onRequest = onRequest
    }
    static func requests() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let payload = Self.recorded.count < Self.payloads.count ? Self.payloads[Self.recorded.count] : nil
        Self.recorded.append(request)
        let onRequest = Self.onRequest
        Self.lock.unlock()
        onRequest?()
        let response = HTTPURLResponse(url: request.url!, statusCode: payload == nil ? 503 : 200, httpVersion: nil, headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class MarketPresentationTests: XCTestCase {
    func testIndustryMetricFormattingPreservesMagnitudeUnitsAndQualifiers() {
        for (raw, qualifier, value, unit) in [
            ("1,649万辆", "", "1,649", "万辆"),
            ("近6,000亿元", "近", "6,000", "亿元"),
            ("超3,650万吨", "超", "3,650", "万吨"),
            ("7,982万千瓦", "", "7,982", "万千瓦"),
            ("2.94亿部", "", "2.94", "亿部"),
            ("万亿元级", "", "万亿元级", "")
        ] {
            let parts = IndustryMetricParts(raw)
            XCTAssertEqual(parts.qualifier, qualifier)
            XCTAssertEqual(parts.value, value)
            XCTAssertEqual(parts.unit, unit)
            XCTAssertEqual(parts.qualifier + parts.value + parts.unit, raw)
        }
    }

    func testIndustryMonthlyComparisonUsesConsecutiveCalendarMonthsAndSelectedMeasure() {
        let december = industryMonth("2025-12", total: 100, nev: 40)
        let january = industryMonth("2026-01", total: 90, nev: 44)
        XCTAssertEqual(IndustryDataPresentation.monthlyChange([january, december], isNEV: true)!, 10, accuracy: 0.0001)
        XCTAssertEqual(IndustryDataPresentation.monthlyChange([december, january], isNEV: false)!, -10, accuracy: 0.0001)
        XCTAssertEqual(IndustryDataPresentation.monthLabel("2026-06"), "2026年6月")
    }

    func testIndustryMonthlyComparisonDoesNotInventRatesAcrossMissingMonthsOrZeroValues() {
        let april = industryMonth("2026-04", total: 100, nev: 50)
        let june = industryMonth("2026-06", total: 120, nev: 60)
        let mayZero = industryMonth("2026-05", total: 0, nev: 0)
        XCTAssertNil(IndustryDataPresentation.monthlyChange([april, june], isNEV: true))
        XCTAssertNil(IndustryDataPresentation.monthlyChange([mayZero, june], isNEV: true))
        XCTAssertNil(IndustryDataPresentation.monthlyChange([june], isNEV: false))
    }

    private func industryMonth(_ period: String, total: Double, nev: Double) -> IndustryPayload.AutoSales.Month {
        .init(period: period, totalSales: total, nevSales: nev, totalYoY: 0, nevYoY: 0, nevPenetrationRate: 0)
    }

    private func researchItem(id: String = "translated", publishedOn: String = "2026-09-15") throws -> InstitutionResearchItem {
        let data = Data(#"{"id":"\#(id)","institution":"Goldman Sachs","institutionShortName":"GS","title":"中文标题","originalTitle":"Original title","summary":"中文摘要","originalSummary":"Official original synopsis.","translationStatus":"translated","publishedOn":"\#(publishedOn)","sourceType":"官网摘要 · 机器翻译","categories":[],"metrics":[],"sourceTitle":"Original title","sourceUrl":"https://www.goldmansachs.com/insights/articles/test","isSystemSummary":false,"presentation":"snapshot"}"#.utf8)
        return try JSONDecoder().decode(InstitutionResearchItem.self, from: data)
    }

    func testResearchTranslationKeepsOriginalForComparison() throws {
        let item = try researchItem()
        XCTAssertEqual(item.title, "中文标题")
        XCTAssertEqual(item.originalSummary, "Official original synopsis.")
        XCTAssertEqual(item.translationLabel, "中文译文")
        var pending = item
        pending.translationStatus = "failed"
        XCTAssertEqual(pending.translationLabel, "翻译待重试 · 英文原文")
    }

    func testResearchFreshnessUsesPublicationDate() throws {
        let now = ISO8601DateFormatter().date(from: "2026-09-17T00:00:00Z")!
        XCTAssertEqual(try researchItem().age(now: now), .recent)
        XCTAssertEqual(try researchItem(publishedOn: "2026-08-18").age(now: now), .recent)
        XCTAssertEqual(try researchItem(publishedOn: "2026-08-17").age(now: now), .historical)
        XCTAssertEqual(try researchItem(publishedOn: "2027-01-01").age(now: now), .unverified)
        XCTAssertEqual(try researchItem(publishedOn: "unknown").age(now: now), .unverified)
    }

    func testResearchPayloadPreparesStableChronologicalOrderAndUniqueInstitutions() throws {
        let items = try [researchItem(id: "z"), researchItem(id: "old", publishedOn: "2026-07-22"), researchItem(id: "a")]
        let payload = InstitutionResearchPayload(institutionsCount: 1, items: items, updatedAt: nil)
        XCTAssertEqual(payload.items.map(\.id), ["a", "z", "old"])
        XCTAssertEqual(payload.institutionShortNames, ["GS"])
    }

    func testInstitutionResearchDecodesCurrentReportsContractAndFiltersInactive() throws {
        let data = Data(#"{"data":{"sources":[{"institutionKey":"morgan-stanley"}],"reports":[{"id":"morgan-stanley-more-stocks-join-bull-market","institutionKey":"morgan-stanley","institution":"Morgan Stanley","institutionShortName":"MS","title":"更多股票加入牛市","originalTitle":"More Stocks Join the Bull Market","summary":"市场领导力正从半导体向可选消费品、运输和生物科技等领域扩散；短期波动并不意味着 AI 周期结束。","publishedOn":"2026-07-22","sourceType":"官方播客文字稿","categories":["美股","市场广度"],"metrics":[],"targetRevision":null,"sourceTitle":"More Stocks Join the Bull Market","sourceUrl":"https://www.morganstanley.com/insights/podcasts/thoughts-on-the-market/market-broadening-beyond-semiconductors-mike-wilson","isSystemSummary":true,"presentation":"lead","sortOrder":10,"isActive":true,"createdAt":"2026-08-10T14:57:04.312056+08:00","updatedAt":"2026-08-10T08:00:00+08:00"},{"id":"inactive-report","institutionKey":"morgan-stanley","institution":"Morgan Stanley","institutionShortName":"MS","title":"更多股票加入牛市","originalTitle":"More Stocks Join the Bull Market","summary":"市场领导力正从半导体向可选消费品、运输和生物科技等领域扩散；短期波动并不意味着 AI 周期结束。","publishedOn":"2026-07-22","sourceType":"官方播客文字稿","categories":["美股","市场广度"],"metrics":[],"targetRevision":null,"sourceTitle":"More Stocks Join the Bull Market","sourceUrl":"https://www.morganstanley.com/insights/podcasts/thoughts-on-the-market/market-broadening-beyond-semiconductors-mike-wilson","isSystemSummary":true,"presentation":"lead","sortOrder":10,"isActive":false,"createdAt":"2026-08-10T14:57:04.312056+08:00","updatedAt":"2026-08-10T08:00:00+08:00"}],"updatedAt":"2026-08-10T08:00:00+08:00"},"success":true}"#.utf8)
        let payload = try JSONDecoder().decode(InstitutionResearchResponse.self, from: data).data
        XCTAssertEqual(payload.institutionsCount, 1)
        XCTAssertEqual(payload.items.count, 1)
        XCTAssertEqual(payload.items.first?.id, "morgan-stanley-more-stocks-join-bull-market")
        XCTAssertEqual(payload.items.first?.source.url.host, "www.morganstanley.com")
        XCTAssertEqual(payload.items.first?.publishedOn, "2026-07-22")
        XCTAssertNotNil(payload.updatedAt)
    }


    func testYieldChangeUsesBasisPointsRatherThanRelativePercent() {
        XCTAssertEqual(marketYieldChangeText(price: 5, previousClose: 5.02), "−2.0 bp")
        XCTAssertEqual(marketYieldChangeText(price: 4.35, previousClose: 4.30), "+5.0 bp")
        XCTAssertEqual(marketYieldChangeText(price: 5, previousClose: nil), "—")
        XCTAssertEqual(marketYieldChangeText(price: .nan, previousClose: 5), "—")
    }

    func testProxyCardsAreExplicitlyNamedAsETFs() {
        XCTAssertEqual(marketCardTitle(symbol: "SPY", name: "标普500实时代理"), "标普500 ETF")
        XCTAssertEqual(marketCardTitle(symbol: "QQQ", name: "纳斯达克实时代理"), "纳斯达克100 ETF")
        XCTAssertEqual(marketCardTitle(symbol: "NVDA", name: "英伟达"), "英伟达")
    }

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

        await runWithLimitedConcurrency(Array(0..<10), maximumConcurrentRequests: 3) { value in
            await probe.start()
            try? await Task.sleep(for: .milliseconds(value.isMultiple(of: 3) ? 12 : 3))
            await probe.finish(value)
        }

        let result = await probe.result()
        XCTAssertEqual(result.completed.sorted(), Array(0..<10))
        XCTAssertEqual(result.maximumActive, 3)
    }

    func testChartsReachServerDespiteFreshFiveMinuteHTTPCache() async throws {
        MarketRequestProbeProtocol.reset()
        let cache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = cache
        configuration.protocolClasses = [MarketRequestProbeProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let base = URL(string: "https://chart-cache.example")!
        var parts = URLComponents(url: base.appending(path: "api/ios/v1/market/chart"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [.init(name: "symbol", value: "NVDA"), .init(name: "interval", value: MarketRange.week.apiInterval), .init(name: "range", value: MarketRange.week.apiRange), .init(name: "limit", value: String(MarketRange.week.apiLimit))]
        let response = HTTPURLResponse(url: parts.url!, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "public, max-age=300"])!
        cache.storeCachedResponse(CachedURLResponse(response: response, data: Data("old chart".utf8)), for: URLRequest(url: parts.url!))
        let service = MarketService(baseURL: base, session: session)
        for recent in [false, true] {
            do {
                if recent { _ = try await service.recentIntradayChart(symbol: "NVDA") }
                else { _ = try await service.chart(symbol: "NVDA", range: .week) }
                XCTFail("A cached chart must not hide the current server response")
            } catch MarketServiceError.httpStatus(503) {
                // The fresh server response must win, even when a cache entry is still fresh.
            }
        }
        let requests = MarketRequestProbeProtocol.requests()
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
            XCTAssertFalse(request.url!.query!.contains("refresh=true"), "HTTP freshness must not request an upstream repair")
        }
    }

    func testDashboardBypassesLocalCacheWithoutForcingUpstreamRefresh() async throws {
        MarketRequestProbeProtocol.reset()
        defer { MarketRequestProbeProtocol.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MarketRequestProbeProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = MarketService(baseURL: URL(string: "https://market-cache.example")!, session: session)

        do {
            _ = try await service.dashboard(refresh: false)
            XCTFail("The request probe returns a server error")
        } catch MarketServiceError.httpStatus(503) {}

        let request = try XCTUnwrap(MarketRequestProbeProtocol.requests().first)
        XCTAssertEqual(request.url?.path, "/api/ios/v1/market/dashboard")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
    }

    private let chartProbePayload = #"""
        {"success":true,"data":{
          "symbol":"NVDA","market":"US","tradingDate":"2026-10-21","timezone":"America/New_York","session":"regular","interval":"1m",
          "analysis":{"aggregation":"none","candleTimestamp":"interval-end","sessionWindows":[]},
          "quality":{"status":"complete","expected":1,"actual":1,"missing":[],"freshnessSeconds":0,"isFinal":true},
          "quote":{"previousClose":10,"changePercent":10,"source":"test"},
          "candles":[{"timestamp":60000,"open":10,"high":12,"low":9,"close":11,"volume":100,"state":"confirmed","source":"test","session":"regular"}]
        }}
        """#

    @MainActor
    func testChartSnapshotChangesForMetadataCorrectionsAndSurvivesFailedRefresh() async throws {
        let original = chartProbePayload
        let corrected = original.replacingOccurrences(of: #""previousClose":10"#, with: #""previousClose":10.5"#)
        MarketRequestProbeProtocol.reset(payloads: [Data(original.utf8), Data(corrected.utf8)])
        defer { MarketRequestProbeProtocol.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MarketRequestProbeProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let store = MarketStore(baseURL: URL(string: "https://chart-snapshot.example")!, session: session)

        await store.loadChart(symbol: "NVDA", range: .day)
        let first = try XCTUnwrap(store.chartSnapshot(symbol: "NVDA", range: .day))
        await store.loadChart(symbol: "NVDA", range: .day)
        XCTAssertEqual(store.chartSnapshot(symbol: "NVDA", range: .day)?.id, first.id)
        XCTAssertEqual(MarketRequestProbeProtocol.requests().count, 1)

        await store.loadChart(symbol: "NVDA", range: .day, force: true)
        let updated = try XCTUnwrap(store.chartSnapshot(symbol: "NVDA", range: .day))
        XCTAssertNotEqual(updated.id, first.id)
        XCTAssertEqual(updated.chart.candles, first.chart.candles)
        XCTAssertEqual(updated.chart.quote.previousClose, 10.5)
        XCTAssertEqual(updated.artifacts.presentation.values, [11])

        await store.loadChart(symbol: "NVDA", range: .day, force: true)
        XCTAssertEqual(store.chartSnapshot(symbol: "NVDA", range: .day)?.id, updated.id)
        XCTAssertNotNil(store.chartError(symbol: "NVDA", range: .day))
        XCTAssertEqual(MarketRequestProbeProtocol.requests().count, 3)
    }

    @MainActor
    func testChartRequestFinishesForNextPageWhenStartingPageIsCancelled() async {
        let requestStarted = expectation(description: "Initial chart request started")
        let releaseResponse = DispatchSemaphore(value: 0)
        MarketRequestProbeProtocol.reset(payloads: [Data(chartProbePayload.utf8)]) {
            requestStarted.fulfill()
            _ = releaseResponse.wait(timeout: .now() + 5)
        }
        defer { MarketRequestProbeProtocol.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MarketRequestProbeProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let store = MarketStore(baseURL: URL(string: "https://chart-handoff.example")!, session: session)

        let firstPage = Task { await store.loadChart(symbol: "NVDA", range: .day) }
        await fulfillment(of: [requestStarted], timeout: 5)
        firstPage.cancel()
        releaseResponse.signal()
        await store.loadChart(symbol: "NVDA", range: .day)

        XCTAssertEqual(store.chartSnapshot(symbol: "NVDA", range: .day)?.artifacts.listTrend, [11])
        XCTAssertEqual(MarketRequestProbeProtocol.requests().count, 1)
        XCTAssertFalse(store.isLoadingChart(symbol: "NVDA", range: .day))
        await firstPage.value
    }

    @MainActor
    func testHoldingsDetailKeepsSummaryRowsSeparateAndScopesCacheToTheFiling() async throws {
        let summary = #"""
        {"key":"ark","cik":"1","displayName":"ARK","institutionName":"ARK","reportDate":"2026-06-30",
         "filingDate":"2026-08-14","positionsCount":1,"totalValueUsd":100,
         "summary":{"new":0,"increased":0,"decreased":0,"exited":0,"unchanged":1},
         "changesCount":0,"changes":[]}
        """#
        let details = summary.dropLast() + #"""
        ,"positions":[{"id":"current:1","symbol":"AAA","name":"A","action":"unchanged","previousWeightPct":100,
         "weightPct":100,"weightChangePct":0,"valueUsd":100,"previousValueUsd":90}]}
        """#
        func response(_ manager: String) -> Data {
            Data(#"{"success":true,"data":{"generatedAt":"2026-08-14T00:00:00Z","reportDate":"2026-06-30","periodLabel":"Q2","disclaimer":"","summary":{"new":0,"increased":0,"decreased":0,"exited":0},"managers":[\#(manager)]}}"#.utf8)
        }
        MarketRequestProbeProtocol.reset(payloads: [response(summary), response(String(details)), response(String(details))])
        defer { MarketRequestProbeProtocol.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MarketRequestProbeProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let store = FamousHoldingsStore(baseURL: URL(string: "https://holdings.example")!, session: session)
        let manager = try JSONDecoder().decode(FamousHoldingsManager.self, from: Data(summary.utf8))

        await store.loadDetail(for: manager)
        XCTAssertNil(store.detail(for: manager))
        XCTAssertNotNil(store.detailError(for: manager))
        XCTAssertNil(store.errorMessage)

        await store.loadDetail(for: manager)
        let loaded = try XCTUnwrap(store.detail(for: manager))
        XCTAssertEqual(loaded.positions?.count, 1)
        XCTAssertEqual(loaded.valueChangeFromPreviousReport?.amountUsd, 10)
        XCTAssertNil(store.detailError(for: manager))
        await store.loadDetail(for: manager)
        XCTAssertEqual(MarketRequestProbeProtocol.requests().count, 2)

        let amended = summary.replacingOccurrences(of: "2026-08-14", with: "2026-08-15")
        let amendedManager = try JSONDecoder().decode(FamousHoldingsManager.self, from: Data(amended.utf8))
        XCTAssertNil(store.detail(for: amendedManager))
        await store.loadDetail(for: amendedManager)
        XCTAssertNil(store.detail(for: amendedManager))
        XCTAssertNotNil(store.detailError(for: amendedManager))
        XCTAssertEqual(MarketRequestProbeProtocol.requests().count, 3)
    }

    func testDecodesServerBackedInstitutionResearch() throws {
        let data = Data(#"{"data":{"updatedAt":"2026-08-10T00:00:00Z","reports":[{"id":"morgan-stanley-more-stocks-join-bull-market","institution":"Morgan Stanley","institutionShortName":"MS","title":"更多股票加入牛市","originalTitle":"More Stocks Join the Bull Market","summary":"市场领导力正在扩散。","publishedOn":"2026-07-22","sourceType":"官方播客文字稿","categories":["美股","市场广度"],"metrics":[],"isSystemSummary":true,"presentation":"lead","sourceTitle":"More Stocks Join the Bull Market","sourceUrl":"https://www.morganstanley.com/insights/example","isActive":true},{"id":"goldman-sp500-forecast-2026","institution":"Goldman Sachs","institutionShortName":"GS","title":"盈利增长推动美股上行","originalTitle":"The S&P 500 Is Forecast to Climb as Earnings Growth Powers Stocks Higher","summary":"盈利预测上调。","publishedOn":"2026-05-28","sourceType":"官方研究文章","categories":["美股"],"metrics":[{"label":"2026 EPS","value":"$340"}],"targetRevision":{"label":"标普500年末目标","previousValue":"7,600","currentValue":"8,000"},"isSystemSummary":true,"presentation":"revision","sourceTitle":"The S&P 500 Is Forecast to Climb as Earnings Growth Powers Stocks Higher","sourceUrl":"https://www.goldmansachs.com/insights/example","isActive":true}]},"success":true}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let payload = try decoder.decode(InstitutionResearchResponse.self, from: data).data

        XCTAssertEqual(payload.institutionsCount, 2)
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

    func testCompanyPEProjectionUsesEveryPointForStatisticsAndDateSelection() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0..<1_000).map { index in
            CompanyPEChartPoint(
                date: start.addingTimeInterval(Double(index) * 86_400),
                value: index < 900 ? 10 : index < 999 ? 30 : 20
            )
        }
        let projection = CompanyPEChartProjection(sortedPoints: points)

        XCTAssertEqual(projection.points.count, 1_000)
        XCTAssertLessThanOrEqual(projection.displayPoints.count, 480)
        XCTAssertEqual(projection.median, 10)
        XCTAssertEqual(try XCTUnwrap(projection.percentile), 90.1, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(projection.previousChange), -100.0 / 3, accuracy: 0.000_001)
        XCTAssertEqual(projection.minimum?.value, 10)
        XCTAssertEqual(projection.maximum?.value, 30)
        XCTAssertEqual(projection.yDomain, 7.6...32.4)

        let renderedDates = Set(projection.displayPoints.map(\.date))
        let omitted = try XCTUnwrap(points.first { !renderedDates.contains($0.date) })
        XCTAssertEqual(projection.point(closestTo: omitted.date)?.date, omitted.date)
        XCTAssertEqual(projection.point(closestTo: points[4].date.addingTimeInterval(43_200))?.date, points[4].date)
        XCTAssertEqual(projection.point(closestTo: nil)?.date, points.last?.date)
    }

    func testCompanyPEProjectionRebuildsStatisticsForSelectedSeriesAndRange() throws {
        let latest = Date(timeIntervalSince1970: 1_700_000_000)
        let cutoff = try XCTUnwrap(Calendar(identifier: .gregorian).date(byAdding: .year, value: -5, to: latest))
        let points = [
            CompanyPEChartPoint(date: cutoff.addingTimeInterval(-86_400), value: 100),
            CompanyPEChartPoint(date: cutoff, value: 10),
            CompanyPEChartPoint(date: latest, value: 20),
        ]
        let fiveYears = CompanyPEChartProjection(sortedPoints: points, years: 5)
        let otherSeries = CompanyPEChartProjection(sortedPoints: points.map { .init(date: $0.date, value: $0.value * 2) }, years: 5)
        let empty = CompanyPEChartProjection(sortedPoints: [])

        XCTAssertEqual(CompanyPEChartProjection(sortedPoints: points).maximum?.value, 100)
        XCTAssertEqual(fiveYears.points.map(\.date), [cutoff, latest])
        XCTAssertEqual(fiveYears.median, 15)
        XCTAssertEqual(fiveYears.percentile, 100)
        XCTAssertEqual(otherSeries.median, 30)
        XCTAssertNil(empty.median)
        XCTAssertNil(empty.point(closestTo: latest))
        XCTAssertEqual(empty.yDomain, 0...1)
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

    func testDecodesMarketChartQualityContract() throws {
        let data = Data(#"{"success":true,"data":{"symbol":"000001.SS","market":"CN","tradingDate":"2026-07-22","timezone":"Asia/Shanghai","session":"regular","interval":"1m","periodReturn":{"range":"1d","basis":"previous-close","startPrice":3864.37,"endPrice":3883.58,"change":19.21,"percent":0.4971,"startTimestamp":null,"endTimestamp":1784691000000},"periodVolatility":{"range":"1d","basis":"annualized-log-returns","percent":18.42,"observationCount":118,"annualizationPeriods":98280},"analysis":{"aggregation":"none","candleTimestamp":"interval-end","sessionWindows":[]},"quality":{"status":"repairing","expected":120,"actual":119,"missing":[{"startTimestamp":1784691000000,"endTimestamp":1784691000000}],"freshnessSeconds":35,"isFinal":false},"quote":{"price":3883.58,"previousClose":3864.37,"change":19.21,"changePercent":0.5,"providerTimestamp":1784691000000,"receivedTimestamp":1784691005000,"source":"eastmoney"},"candles":[{"timestamp":1784683860000,"open":3839.67,"high":3845.42,"low":3839.67,"close":3845.42,"volume":18226640,"state":"confirmed","source":"eastmoney","session":"regular"}]}}"#.utf8)
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
        let data = Data(#"{"success":true,"data":{"symbol":"601398.SS","market":"CN","tradingDate":"2026-07-22","timezone":"Asia/Shanghai","session":"closed","interval":"1m","analysis":{"aggregation":"none","candleTimestamp":"interval-end","sessionWindows":[]},"quality":{"status":"unavailable","expected":240,"actual":0,"missing":[],"freshnessSeconds":null,"isFinal":true},"quote":{"price":7.6,"previousClose":7.56,"change":0.04,"changePercent":0.53,"providerTimestamp":1784707014348,"receivedTimestamp":1784707014348,"source":"eastmoney"},"candles":[]}}"#.utf8)

        let response = try JSONDecoder().decode(MarketChartResponse.self, from: data)

        XCTAssertTrue(marketChartNeedsRetry(response.data))
        XCTAssertFalse(marketChartCanUseCache(response.data, loadedAt: periodTestNow, now: periodTestNow))
    }

    func test52WeekLowUsesValidCandleLows() throws {
        let data = Data(#"{"success":true,"data":{"symbol":"AAPL","market":"US","tradingDate":"2026-08-04","timezone":"America/New_York","session":"closed","interval":"1d","analysis":{"aggregation":"none","candleTimestamp":"trading-date","sessionWindows":[]},"quality":{"status":"complete","expected":3,"actual":3,"missing":[],"freshnessSeconds":null,"isFinal":true},"quote":{"price":220,"previousClose":219,"change":1,"changePercent":0.46,"providerTimestamp":null,"receivedTimestamp":null,"source":"yahoo"},"candles":[{"timestamp":1,"open":210,"high":215,"low":205,"close":212,"volume":1,"state":"confirmed","source":"yahoo","session":"regular"},{"timestamp":2,"open":200,"high":210,"low":180,"close":205,"volume":1,"state":"invalid","source":"yahoo","session":"regular"},{"timestamp":3,"open":190,"high":220,"low":185.5,"close":220,"volume":1,"state":"confirmed","source":"yahoo","session":"regular"}]}}"#.utf8)

        let response = try JSONDecoder().decode(MarketChartResponse.self, from: data)

        XCTAssertEqual(market52WeekLow(response.data), 185.5)
        XCTAssertEqual(market52WeekHigh(response.data, symbol: "AAPL"), 220)
        XCTAssertNil(market52WeekHigh(response.data, symbol: "SPY"), "An index or another instrument cannot supply an ETF price statistic")
    }

    func test52WeekLowRejectsPartialHistory() throws {
        let data = Data(#"{"success":true,"data":{"symbol":"AAPL","market":"US","tradingDate":"2026-08-04","timezone":"America/New_York","session":"closed","interval":"1d","analysis":{"aggregation":"none","candleTimestamp":"trading-date","sessionWindows":[]},"quality":{"status":"partial","expected":6,"actual":6,"missing":[],"freshnessSeconds":null,"isFinal":true},"quote":{"source":"yahoo"},"candles":[{"timestamp":1,"open":210,"high":215,"low":205,"close":212,"volume":1,"state":"confirmed","source":"yahoo","session":"regular"}]}}"#.utf8)

        let response = try JSONDecoder().decode(MarketChartResponse.self, from: data)

        XCTAssertNil(market52WeekLow(response.data))
        XCTAssertNil(market52WeekHigh(response.data, symbol: "AAPL"))
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
        XCTAssertEqual(quote.marketDisplayChangeValue, 1.635, accuracy: 0.0001)
        XCTAssertEqual(quote.marketDisplayPercentValue, 1.635 / 217.56 * 100, accuracy: 0.0001)
        XCTAssertEqual(quote.marketDisplayFormattedPercent, "+0.75%")
    }

    func testExtendedSessionChangeUsesLatestRegularCloseAcrossHoliday() throws {
        for session in ["pre", "post", "overnight"] {
            let payload = """
            {"symbol":"AAPL","name":"苹果","price":319.97,"previousClose":328.21,
             "marketSession":"\(session)","sessionPrice":318.885,"sessionChangePercent":-2.8411687639}
            """
            let quote = try JSONDecoder().decode(MarketQuote.self, from: Data(payload.utf8))
            XCTAssertEqual(quote.marketDisplayChangeValue, -1.085, accuracy: 0.0001)
            XCTAssertEqual(quote.marketDisplayPercentValue, -1.085 / 319.97 * 100, accuracy: 0.0001)
            XCTAssertEqual(quote.marketDisplayFormattedPercent, "−0.34%")
            XCTAssertEqual(quote.formattedSessionPercent, "−0.34%")
            XCTAssertEqual(quote.changeValue, -8.24, accuracy: 0.0001)
        }
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
        XCTAssertEqual(MarketRange.fiveYears.apiLimit, 2_000)
        XCTAssertEqual(MarketRange.maximum.apiLimit, 50_000)
    }

    func testLeadChartPrefersLoadedRangePointsOverDashboardSummary() {
        let chartValues = Array(0..<390).map(Double.init)
        let fallbackValues = Array(0..<40).map(Double.init)

        XCTAssertEqual(
            marketPreferredLeadChartTrend(chartValues: chartValues, fallbackValues: fallbackValues),
            chartValues
        )
        XCTAssertEqual(
            marketPreferredLeadChartTrend(chartValues: [1], fallbackValues: fallbackValues),
            fallbackValues
        )
    }

    func testDailyChartPointsRemainInOneDrawableSegmentAcrossTheWeekend() throws {
        let points = try [
            periodPoint("2026-10-16T04:00:00Z", close: 10),
            periodPoint("2026-10-19T04:00:00Z", close: 11),
            periodPoint("2026-10-20T04:00:00Z", close: 12)
        ]
        let presentation = MarketChartPresentation(chart: periodChart(points, interval: "1d", status: .partial))

        assertLinePlanCoversEveryEdgeOnce(presentation)
        XCTAssertEqual(presentation.lineSegments.count, 1)
        XCTAssertEqual(presentation.lineSegments.first?.indices, [0, 1, 2])
        XCTAssertTrue(presentation.lineSegments.allSatisfy { $0.isRegular && !$0.isMissing })
    }

    func testNonemptyIncompleteChartsKeepRequestingCoverageRepairInsteadOfFreezingTheCache() {
        let points = [chartPoint(timestamp: 60_000, close: 10), chartPoint(timestamp: 180_000, close: 11)]
        for status in [MarketChartQualityStatus.partial, .repairing] {
            let chart = periodChart(points, status: status, expected: 3, actual: 2)

            XCTAssertTrue(marketChartNeedsRetry(chart))
            XCTAssertFalse(marketChartCanUseCache(chart, loadedAt: periodTestNow, now: periodTestNow))
        }
    }

    func testExplicitSourceCoverageGapsCannotBeCachedAsComplete() {
        let points = [chartPoint(timestamp: 60_000, close: 10), chartPoint(timestamp: 180_000, close: 11)]
        let missing = [MarketChartGap(startTimestamp: 120_000, endTimestamp: 120_000)]
        for chart in [
            periodChart(points, expected: 3, actual: 2, missing: missing),
            periodChart(points, missing: missing)
        ] {
            XCTAssertTrue(marketChartNeedsRetry(chart))
            XCTAssertFalse(marketChartCanUseCache(chart, loadedAt: periodTestNow, now: periodTestNow))
        }

        let complete = periodChart(points)
        XCTAssertFalse(marketChartNeedsRetry(complete))
        XCTAssertTrue(marketChartCanUseCache(complete, loadedAt: periodTestNow, now: periodTestNow))
    }

    func testCompleteSparseCoverageKeepsItsSourceContractWithoutRepairRetries() throws {
        let points = try [
            periodPoint("2026-10-21T13:30:00Z", close: 10),
            periodPoint("2026-10-21T13:39:00Z", close: 12)
        ]
        for market in ["FX", "JP", "KR"] {
            let source = periodChart(points, market: market, expected: 10, actual: 2)
            let result = try XCTUnwrap(marketChartForDisplay(source, period: .intraday, now: periodTestNow))

            XCTAssertEqual(result.candles, points)
            XCTAssertEqual(result.quality.status, .complete)
            XCTAssertEqual(result.quality.expected, 10)
            XCTAssertEqual(result.quality.actual, 2)
            XCTAssertTrue(result.quality.missing.isEmpty)
            XCTAssertFalse(marketChartNeedsRetry(result))
            XCTAssertTrue(marketChartCanUseCache(result, loadedAt: periodTestNow, now: periodTestNow))
            XCTAssertTrue(MarketChartPresentation(chart: result).lineSegments.allSatisfy { !$0.isMissing })
        }
    }

    func testOpenCompleteChartExpiresWithoutRequestingCoverageRepair() {
        let points = [chartPoint(timestamp: 60_000, close: 10), chartPoint(timestamp: 120_000, close: 11)]
        let chart = periodChart(points, isFinal: false)

        XCTAssertFalse(marketChartNeedsRetry(chart))
        XCTAssertTrue(marketChartCanUseCache(chart, loadedAt: periodTestNow, now: periodTestNow))
        XCTAssertFalse(marketChartCanUseCache(chart, loadedAt: periodTestNow, now: periodTestNow.addingTimeInterval(30)))
    }

    func testChartCacheExpiresBySourceIntervalEvenWhenTheSessionWasFinal() {
        let points = [chartPoint(timestamp: 60_000, close: 10), chartPoint(timestamp: 120_000, close: 11)]
        for (interval, lifetime) in [("1m", 30.0), ("15m", 30.0), ("1d", 300.0)] {
            let chart = periodChart(points, interval: interval)

            XCTAssertTrue(marketChartCanUseCache(
                chart, loadedAt: periodTestNow, now: periodTestNow.addingTimeInterval(lifetime - 1)
            ))
            XCTAssertFalse(marketChartCanUseCache(
                chart, loadedAt: periodTestNow, now: periodTestNow.addingTimeInterval(lifetime)
            ))
        }
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

        let lunchBreak = marketChartSessionBreak(points: [point(hour: 11, minute: 30), point(hour: 13, minute: 1)], chart: periodChart([point(hour: 11, minute: 30), point(hour: 13, minute: 1)], symbol: "000001.SS", market: "CN", timezone: "Asia/Shanghai"))
        XCTAssertEqual(lunchBreak?.label, "午间休市")
        XCTAssertNil(marketChartSessionBreak(points: [point(hour: 10, minute: 0), point(hour: 11, minute: 5)], chart: periodChart([point(hour: 10, minute: 0), point(hour: 11, minute: 5)], symbol: "000001.SS", market: "CN", timezone: "Asia/Shanghai")))
        XCTAssertNil(marketChartSessionBreak(points: [point(hour: 11, minute: 30), point(hour: 13, minute: 1)], chart: periodChart([point(hour: 11, minute: 30), point(hour: 13, minute: 1)], symbol: "TEST", market: "US", timezone: "America/New_York")))
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

        XCTAssertEqual(marketChartDisplayPoints(points, interval: "1m").map(\.timestamp), [2])
    }

    func testChartPresentationPrecomputesStableDrawingInputs() throws {
        let data = Data(#"""
        {
          "symbol":"TEST","market":"US","tradingDate":"2026-08-20",
          "timezone":"America/New_York","session":"regular","interval":"1m",
          "analysis":{"aggregation":"none","candleTimestamp":"interval-end","sessionWindows":[]},
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
        assertLinePlanCoversEveryEdgeOnce(presentation)
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

        let values = marketSampledChartTrend(points, interval: "1m", limit: 40)

        XCTAssertEqual(values.count, 40)
        XCTAssertEqual(values.first, 1)
        XCTAssertEqual(values.last, 120)
        XCTAssertTrue(values.contains { $0 > 40 && $0 < 80 })
    }

    func testMarketListTrendWaitsForSessionDataInsteadOfDrawingSnapshot() {
        XCTAssertEqual(marketListChartTrend(chartValues: nil), [])
        XCTAssertEqual(marketListChartTrend(chartValues: []), [])
    }

    func testMarketListTrendShowsCachedSessionImmediately() {
        let chart = (1...120).map(Double.init)
        XCTAssertEqual(marketListChartTrend(chartValues: chart), chart)
    }

    func testMarketListTrendKeepsSparseSessionInsteadOfSwitchingWindows() {
        XCTAssertEqual(marketListChartTrend(chartValues: [10, 12]), [10, 12])
    }

    func testPinnedMarketListTrendAcceptsUpdatedChartWithSamePointCount() {
        let initial = [10.0, 11.0, 10.5, 12.0]
        let loadedChart = [20.0, 18.0, 21.0, 19.0]

        XCTAssertEqual(
            marketPinnedListTrend(current: initial, incoming: loadedChart),
            loadedChart
        )
    }

    func testPinnedMarketListTrendCanUpgradeSparsePlaceholder() {
        let loadedChart = [10.0, 11.0, 10.5, 12.0]

        XCTAssertEqual(
            marketPinnedListTrend(current: [10.0, 12.0], incoming: loadedChart),
            loadedChart
        )
    }

    func testPinnedMarketListTrendReplacesFortyPointSnapshotWithFullSession() {
        let snapshot = Array(repeating: 10.0, count: 40)
        let fullSession = (0..<120).map { Double($0 + 1) }

        XCTAssertEqual(marketPinnedListTrend(current: snapshot, incoming: fullSession), fullSession)
        XCTAssertEqual(marketPinnedListTrend(current: fullSession, incoming: []), fullSession)
        XCTAssertEqual(marketPinnedListTrend(current: fullSession, incoming: [10, 12]), fullSession)
        XCTAssertEqual(marketPinnedListTrend(current: fullSession, incoming: [10, 11, 12]), [10, 11, 12])
    }

    func testMarketListTrendDefaultSamplingRetainsFullSessionAtHigherDensity() {
        let points = (0..<390).map { index in
            let value = Double(index + 1)
            return MarketChartPoint(
                timestamp: Int64(index), open: value, high: value,
                low: value, close: value, volume: nil,
                state: "confirmed", source: "test", session: "regular"
            )
        }
        let values = marketSampledChartTrend(points, interval: "1m")

        XCTAssertEqual(values.count, 120)
        XCTAssertEqual(values.first, 1)
        XCTAssertEqual(values.last, 390)
        XCTAssertTrue(values.contains { $0 > 190 && $0 < 200 })
        XCTAssertEqual(marketSampledChartTrend(Array(points.prefix(80)), interval: "1m").count, 80)
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

    func testAxisDigitsDistinguishAllFiveTicksInRealLowPriceAndCurrencyWindows() throws {
        let windows: [(symbol: String, low: Double, high: Double, digits: Int)] = [
            ("DOGEUSDT 1m", 0.0787, 0.0796, 4),
            ("DOGEUSDT 15m", 0.07785, 0.0838, 3),
            ("XRPUSDT 1m", 1.3065, 1.3214, 3),
            ("USDCNY 1m", 6.6717, 6.674, 4),
            ("USDCNY 15m", 6.6715, 6.6862, 3)
        ]
        for window in windows {
            let step = (window.high - window.low) / 4
            let digits = marketAxisDigits(values: [window.low, window.high])
            let quantum = pow(10, -Double(digits))
            let ticks = (0..<5).map { window.high - (window.high - window.low) * Double($0) / 4 }
            let labels = ticks.map {
                $0.formatted(.number.grouping(.never).precision(.fractionLength(digits)).locale(Locale(identifier: "en_US_POSIX")))
            }

            XCTAssertEqual(digits, window.digits, window.symbol)
            XCTAssertEqual(Set(labels).count, 5, "\(window.symbol): \(labels)")
            XCTAssertLessThanOrEqual(quantum, step, window.symbol)
            for (tick, label) in zip(ticks, labels) {
                let displayed = try XCTUnwrap(Double(label))
                XCTAssertLessThanOrEqual(abs(displayed - tick), quantum / 2 + 1e-12, window.symbol)
            }
        }
    }

    func testAxisDigitsBoundTinyRangesAndKeepExistingLargeStepPrecision() {
        XCTAssertEqual(marketAxisDigits(values: []), 2)
        XCTAssertEqual(marketAxisDigits(values: [0, 0]), 2)
        XCTAssertEqual(marketAxisDigits(values: [10, 14]), 1)
        XCTAssertEqual(marketAxisDigits(values: [10, 50]), 0)
        XCTAssertEqual(marketAxisDigits(values: [0, 1e-30]), 10)
        XCTAssertEqual(marketAxisDigits(values: [0, Double.leastNonzeroMagnitude]), 10)
    }

    func testChartPeriodsSeparateSourceWindowsFromDisplayedLineIntervalsAndTitles() {
        let cases: [(MarketChartPeriod, MarketRange, String, Bool, Bool, String, String, String)] = [
            (.intraday, .day, "1m", true, false, "HH:mm", "分时", "分时走势"),
            (.fiveDays, .week, "15m", true, false, "MM-dd HH:mm", "5日", "5日走势"),
            (.minute1, .day, "1m", true, true, "HH:mm", "1分", "1分钟走势"),
            (.minute5, .day, "5m", true, true, "HH:mm", "5分", "5分钟走势"),
            (.minute15, .week, "15m", true, true, "MM-dd HH:mm", "15分", "15分钟走势"),
            (.minute30, .day, "30m", true, true, "HH:mm", "30分", "30分钟走势"),
            (.minute60, .day, "60m", true, true, "HH:mm", "60分", "60分钟走势"),
            (.daily, .year, "1d", false, false, "MM-dd", "日线", "日线走势"),
            (.weekly, .fiveYears, "1wk", false, false, "yyyy-MM-dd", "周线", "周线走势"),
            (.monthly, .maximum, "1mo", false, false, "yyyy-MM", "月线", "月线走势")
        ]

        XCTAssertEqual(cases.map { $0.0 }, MarketChartPeriod.allCases)
        for (period, sourceRange, interval, isIntraday, isMinute, dateFormat, label, title) in cases {
            XCTAssertEqual(period.sourceRange, sourceRange)
            XCTAssertEqual(period.displayInterval, interval)
            XCTAssertEqual(period.isIntraday, isIntraday)
            XCTAssertEqual(period.isMinute, isMinute)
            XCTAssertEqual(period.dateFormat, dateFormat)
            XCTAssertEqual(period.rawValue, label)
            XCTAssertEqual(period.chartTitle, title)
        }
        for period in MarketChartPeriod.allCases {
            XCTAssertTrue(period.chartTitle.hasSuffix("走势"))
            XCTAssertFalse(period.chartTitle.contains("K线"))
            XCTAssertFalse(period.rawValue.contains("K"))
        }
    }

    func testMinuteContractRejectsUnalignedOrDuplicateKeysBeforeAggregation() throws {
        let canonical = try [
            periodPoint("2026-10-21T13:31:00Z", close: 12, volume: 100),
            periodPoint("2026-10-21T13:32:00Z", close: 14, volume: 250),
            periodPoint("2026-10-21T13:33:00Z", close: 16, volume: 50)
        ]
        let unaligned = try periodPoint("2026-10-21T13:31:12Z", close: 99, volume: 999)
        for period in [MarketChartPeriod.intraday, .minute1, .minute5, .minute30, .minute60] {
            XCTAssertNil(marketChartForDisplay(periodChart([canonical[0], canonical[0]]), period: period, now: periodTestNow))
            XCTAssertNil(marketChartForDisplay(periodChart([unaligned]), period: period, now: periodTestNow))
            let result = try XCTUnwrap(marketChartForDisplay(periodChart(canonical), period: period, now: periodTestNow))
            XCTAssertEqual(result.quality.actual, 3)
            XCTAssertEqual(result.candles.compactMap(\.volume).reduce(0, +), 400)
            if period == .intraday || period == .minute1 {
                XCTAssertEqual(result.candles, canonical)
                XCTAssertEqual(marketMovingAverageValues(result.candles, period: 3), [nil, nil, 14])
            } else {
                XCTAssertEqual(result.candles.count, 1)
                XCTAssertEqual(result.candles.first?.timestamp, try periodTimestamp("2026-10-21T13:30:00Z"))
                XCTAssertEqual(result.candles.first?.close, 16)
            }
        }
    }

    func testNativeMinutePeriodsRetainRealGapsAndRejectInvalidSourceSamples() throws {
        let points = try [
            periodPoint("2026-10-21T13:31:00Z", close: 10, volume: 100),
            periodPoint("2026-10-21T13:32:00Z", close: 999, volume: 1000, state: "invalid"),
            periodPoint("2026-10-21T13:33:00Z", close: 12, volume: 200)
        ]
        let missingMinute = try periodTimestamp("2026-10-21T13:32:00Z")
        let gaps = [MarketChartGap(startTimestamp: missingMinute, endTimestamp: missingMinute)]
        let source = periodChart(points, expected: 3, actual: 2, missing: gaps)

        for period in [MarketChartPeriod.intraday, .minute1] {
            let result = try XCTUnwrap(marketChartForDisplay(source, period: period, now: periodTestNow))
            XCTAssertEqual(result.candles.map(\.timestamp), try [
                periodTimestamp("2026-10-21T13:31:00Z"), periodTimestamp("2026-10-21T13:33:00Z")
            ])
            XCTAssertEqual(result.candles.map(\.close), [10, 12])
            XCTAssertEqual(result.quality.status, .partial)
            XCTAssertEqual(result.quality.expected, 3)
            XCTAssertEqual(result.quality.actual, 2)
            XCTAssertEqual(result.quality.missing, gaps)
        }
    }

    func testHiddenSnapshotsDoNotDowngradeNativeMinuteCoverage() throws {
        let points = try [
            periodPoint("2026-10-21T13:31:00Z", close: 10, volume: 100),
            periodPoint("2026-10-21T13:30:42Z", close: 999, volume: 0,
                        state: "provisional", source: "TradingView"),
            periodPoint("2026-10-21T13:32:00Z", close: 12, volume: 200),
            periodPoint("2026-10-21T13:31:42Z", close: 888, volume: 0,
                        state: "provisional", session: "post")
        ]
        for period in [MarketChartPeriod.intraday, .minute1] {
            let result = try XCTUnwrap(marketChartForDisplay(periodChart(points, expected: 2, actual: 2), period: period, now: periodTestNow))
            XCTAssertEqual(result.candles.map(\.close), [10, 12])
            XCTAssertEqual(result.candles.map(\.volume), [100, 200])
            XCTAssertEqual(result.quality.status, .complete)
        }
    }

    func testFiveMinuteCandlesUseElapsedTimeAndPreserveOHLCAndOptionalVolume() throws {
        let points = try [
            periodPoint("2026-10-21T13:31:00Z", open: 10, high: 13, low: 9, close: 12, volume: 2),
            periodPoint("2026-10-21T13:32:00Z", open: 12, high: 14, low: 11, close: 13),
            periodPoint("2026-10-21T13:34:00Z", open: 13, high: 15, low: 8, close: 11, volume: 3),
            periodPoint("2026-10-21T13:36:00Z", open: 11, high: 12, low: 10, close: 12),
            periodPoint("2026-10-21T13:39:00Z", open: 12, high: 16, low: 11, close: 15),
            periodPoint("2026-10-21T13:46:00Z", open: 15, high: 17, low: 14, close: 16, volume: 4)
        ]
        let chart = periodChart(points)

        let result = try XCTUnwrap(marketChartForDisplay(chart, period: .minute5, now: periodTestNow))

        XCTAssertEqual(result.interval, "5m")
        XCTAssertEqual(result.candles, try [
            periodPoint("2026-10-21T13:30:00Z", open: 10, high: 15, low: 8, close: 11, volume: 5),
            periodPoint("2026-10-21T13:35:00Z", open: 11, high: 16, low: 10, close: 15),
            periodPoint("2026-10-21T13:45:00Z", open: 15, high: 17, low: 14, close: 16, volume: 4)
        ])
        XCTAssertEqual(result.quality.expected, points.count)
        XCTAssertEqual(result.quality.actual, points.count)
        XCTAssertEqual(result.quality.status, .complete)
        // No synthetic candle is inserted for the empty 13:41 bucket.
        XCTAssertEqual(result.candles.count, 3)
        XCTAssertNil(result.candles[1].volume)
    }

    func testThirtyAndSixtyMinuteCandlesUseTheirActualTimeBoundaries() throws {
        let instants = [
            "2026-10-21T13:31:00Z", "2026-10-21T13:45:00Z", "2026-10-21T14:00:00Z",
            "2026-10-21T14:01:00Z", "2026-10-21T14:16:00Z", "2026-10-21T14:30:00Z",
            "2026-10-21T14:31:00Z"
        ]
        let points = try instants.enumerated().map { index, instant in
            try periodPoint(instant, close: Double(index + 1))
        }
        let chart = periodChart(points)

        let halfHour = try XCTUnwrap(marketChartForDisplay(chart, period: .minute30, now: periodTestNow))
        let hour = try XCTUnwrap(marketChartForDisplay(chart, period: .minute60, now: periodTestNow))

        XCTAssertEqual(halfHour.interval, "30m")
        XCTAssertEqual(halfHour.candles, try [
            periodPoint("2026-10-21T13:30:00Z", open: 1, high: 3, low: 1, close: 3),
            periodPoint("2026-10-21T14:00:00Z", open: 4, high: 6, low: 4, close: 6),
            periodPoint("2026-10-21T14:30:00Z", close: 7)
        ])
        XCTAssertEqual(hour.interval, "60m")
        XCTAssertEqual(hour.candles, try [
            periodPoint("2026-10-21T13:30:00Z", open: 1, high: 6, low: 1, close: 6),
            periodPoint("2026-10-21T14:30:00Z", close: 7)
        ])
    }

    func testMinuteCandleAnchorsUseDeclaredSessionOpenAfterLunch() throws {
        let points = try [
            periodPoint("2026-10-21T01:31:00Z", close: 10),
            periodPoint("2026-10-21T01:45:00Z", close: 11),
            periodPoint("2026-10-21T05:01:00Z", close: 20),
            periodPoint("2026-10-21T05:14:00Z", close: 21)
        ]
        let source = periodChart(points, market: "CN", timezone: "Asia/Shanghai")
        let result = try XCTUnwrap(marketChartForDisplay(source, period: .minute60, now: periodTestNow))
        XCTAssertEqual(result.candles, try [
            periodPoint("2026-10-21T01:30:00Z", open: 10, high: 11, low: 10, close: 11),
            periodPoint("2026-10-21T05:00:00Z", open: 20, high: 21, low: 20, close: 21)
        ])
    }

    func testContinuousMarketBucketsUseDeclaredDailyBounds() throws {
        let points = try [periodPoint("2026-10-21T23:58:00Z", close: 10), periodPoint("2026-10-22T00:02:00Z", close: 20)]
        let result = try XCTUnwrap(marketChartForDisplay(periodChart(points, market: "CRYPTO", timezone: "UTC"), period: .minute30, now: periodTestNow))
        XCTAssertEqual(result.candles, try [periodPoint("2026-10-21T23:30:00Z", close: 10),periodPoint("2026-10-22T00:00:00Z", close: 20)])
    }

    func testWeeklyCandlesStartOnExchangeLocalMonday() throws {
        let points = try [
            periodPoint("2026-10-22T15:00:00Z", open: 10, high: 12, low: 9, close: 11, volume: 2),
            periodPoint("2026-10-25T15:00:00Z", open: 20, high: 23, low: 19, close: 22, volume: 3),
            periodPoint("2026-10-26T15:00:00Z", open: 22, high: 25, low: 18, close: 24, volume: 4)
        ]

        let result = try XCTUnwrap(marketChartForDisplay(periodChart(points, interval: "1d", timezone: "Asia/Tokyo"), period: .weekly, now: periodTestNow))

        XCTAssertEqual(result.interval, "1wk")
        XCTAssertEqual(result.candles, try [
            periodPoint("2026-10-18T15:00:00Z", open: 10, high: 12, low: 9, close: 11, volume: 2),
            periodPoint("2026-10-25T15:00:00Z", open: 20, high: 25, low: 18, close: 24, volume: 7)
        ])
        XCTAssertEqual(result.quality.expected, 3)
        XCTAssertEqual(result.quality.actual, 3)
        XCTAssertEqual(result.quality.status, .complete)
        XCTAssertEqual(result.tradingDate, "2026-10-27")
    }

    func testMonthlyCandlesUseExchangeLocalMonthAndKeepProvisionalTail() throws {
        let points = try [
            periodPoint("2026-09-29T15:00:00Z", open: 10, high: 12, low: 9, close: 11),
            periodPoint("2026-09-30T15:00:00Z", open: 20, high: 23, low: 19, close: 22, volume: 3),
            periodPoint("2026-10-01T15:00:00Z", open: 22, high: 25, low: 18, close: 24, volume: 4, state: "provisional")
        ]

        let result = try XCTUnwrap(marketChartForDisplay(
            periodChart(points, interval: "1d", timezone: "Asia/Tokyo"),
            period: .monthly, now: periodTestNow
        ))

        XCTAssertEqual(result.interval, "1mo")
        XCTAssertEqual(result.candles, try [
            periodPoint("2026-08-31T15:00:00Z", open: 10, high: 12, low: 9, close: 11),
            periodPoint("2026-09-30T15:00:00Z", open: 20, high: 25, low: 18, close: 24, volume: 7, state: "provisional")
        ])
        XCTAssertFalse(result.quality.isFinal)
        XCTAssertEqual(result.tradingDate, "2026-10-02")
    }

    func testCalendarLinesKeepSingleSampleOpeningBucketsAtTheStartOfTheWindow() throws {
        for (period, openingDate, nextDate) in [
            (MarketChartPeriod.weekly, "2026-10-16", "2026-10-19"),
            (.monthly, "2026-09-30", "2026-10-01")
        ] {
            let points = try [
                periodPoint("\(openingDate)T00:00:00Z", close: 10, volume: 2, tradingDate: openingDate),
                periodPoint("\(nextDate)T00:00:00Z", close: 12, volume: 3, tradingDate: nextDate)
            ]
            let result = try XCTUnwrap(marketChartForDisplay(
                periodChart(points, interval: "1d"), period: period, now: periodTestNow
            ))
            let presentation = MarketChartPresentation(chart: result)

            XCTAssertEqual(result.candles.map(\.close), [10, 12])
            XCTAssertEqual(result.candles.map(\.volume), [2, 3])
            XCTAssertEqual(result.quality.actual, 2)
            XCTAssertEqual(result.quality.expected, 2)
            XCTAssertEqual(result.periodReturn?.startPrice, 10)
            XCTAssertEqual(result.periodReturn?.startTimestamp, try periodTimestamp("\(openingDate)T04:00:00Z"))
            XCTAssertEqual(result.periodReturn?.endPrice, 12)
            XCTAssertEqual(presentation.xFractions, [0, 1])
            assertLinePlanCoversEveryEdgeOnce(presentation)
        }
    }

    func testLongDailyHistoryKeepsEverySampleWhenBuildingWeeklyAndMonthlyLines() throws {
        let start = try periodTimestamp("2019-12-30T00:00:00Z")
        // A continuously traded asset supplies 105 full weeks, including a leap year.
        var points: [MarketChartPoint] = []
        for index in 0..<735 {
            let value = Double(index)
            let timestamp = start + Int64(index) * 86_400_000
            let high: Double = index == 400 ? 50_000 : 102 + value
            let low: Double = index == 500 ? 1 : 98 + value
            points.append(chartPoint(
                timestamp: timestamp,
                open: 99 + value,
                high: high,
                low: low,
                close: 100 + value,
                volume: Double(index + 1),
                source: "history"
            ))
        }
        let source = periodChart(points, interval: "1d", symbol: "BTC-USD", market: "CRYPTO", timezone: "UTC")
        let now = Date(timeIntervalSince1970: Double(try periodTimestamp("2023-01-01T00:00:00Z")) / 1_000)

        let cases: [(MarketChartPeriod, Int, Double, Double, Double, String)] = [
            (.weekly, 105, 106.0, 108.0, 28.0, "2021-12-27T00:00:00Z"),
            (.monthly, 26, 101.0, 103.0, 3.0, "2022-01-01T00:00:00Z")
        ]
        for (period, count, firstClose, firstHigh, firstVolume, finalBucketStart) in cases {
            let result = try XCTUnwrap(marketChartForDisplay(source, period: period, now: now))
            let first = try XCTUnwrap(result.candles.first)
            let last = try XCTUnwrap(result.candles.last)
            let periodReturn = try XCTUnwrap(result.periodReturn)

            XCTAssertEqual(result.candles.count, count)
            XCTAssertEqual(first.open, 99)
            XCTAssertEqual(first.close, firstClose)
            XCTAssertEqual(first.high, firstHigh)
            XCTAssertEqual(first.low, 98)
            XCTAssertEqual(first.volume, firstVolume)
            XCTAssertEqual(last.timestamp, try periodTimestamp(finalBucketStart))
            XCTAssertEqual(last.close, 834)
            XCTAssertEqual(result.candles.map(\.high).max(), 50_000)
            XCTAssertEqual(result.candles.map(\.low).min(), 1)
            XCTAssertEqual(result.candles.compactMap(\.volume).reduce(0, +), 270_480)
            XCTAssertEqual(result.quality.actual, 735)
            XCTAssertEqual(result.quality.expected, 735)
            XCTAssertEqual(result.quality.status, .complete)
            XCTAssertTrue(result.quality.isFinal)
            XCTAssertEqual(periodReturn.range, period.sourceRange.apiRange)
            XCTAssertEqual(periodReturn.startTimestamp, start)
            XCTAssertEqual(periodReturn.endTimestamp, try periodTimestamp("2022-01-02T00:00:00Z"))
            XCTAssertEqual(periodReturn.startPrice, 100)
            XCTAssertEqual(periodReturn.endPrice, 834)
            XCTAssertEqual(periodReturn.change, 734)
            XCTAssertEqual(periodReturn.percent ?? .nan, 734, accuracy: 0.000_001)
            assertLinePlanCoversEveryEdgeOnce(MarketChartPresentation(chart: result))
        }
    }

    func testCalendarLinesKeepWindowsThatFitEntirelyWithinOnePartialWeekOrMonth() throws {
        let points = try [
            periodPoint("2026-10-21T00:00:00Z", open: 9, high: 12, low: 8, close: 10,
                        volume: 2, tradingDate: "2026-10-21"),
            periodPoint("2026-10-22T00:00:00Z", open: 10, high: 15, low: 9, close: 14,
                        volume: 3, tradingDate: "2026-10-22")
        ]
        for period in [MarketChartPeriod.weekly, .monthly] {
            for count in 1...points.count {
                let samples = Array(points.prefix(count))
                let result = try XCTUnwrap(marketChartForDisplay(
                    periodChart(samples, interval: "1d"), period: period, now: periodTestNow
                ))
                let point = try XCTUnwrap(result.candles.first)
                let presentation = MarketChartPresentation(chart: result)

                XCTAssertEqual(result.candles.count, 1)
                XCTAssertEqual(point.open, 9)
                XCTAssertEqual(point.low, 8)
                XCTAssertEqual(point.high, count == 1 ? 12 : 15)
                XCTAssertEqual(point.close, samples.last?.close)
                XCTAssertEqual(point.volume, count == 1 ? 2 : 5)
                XCTAssertEqual(result.quality.actual, count)
                XCTAssertEqual(result.periodReturn?.startPrice, 10)
                XCTAssertEqual(result.periodReturn?.endPrice, samples.last?.close)
                XCTAssertEqual(result.periodReturn?.startTimestamp, try periodTimestamp("2026-10-21T04:00:00Z"))
                XCTAssertEqual(presentation.values, [samples.last!.close])
                XCTAssertEqual(presentation.xFractions, [0.5])
            }
        }
    }

    func testMinuteLinePresentationsKeepMixedProviderProvisionalTailBuckets() async throws {
        let points = try [
            periodPoint("2026-10-21T13:00:00Z", close: 8, source: "tradingview"),
            periodPoint("2026-10-21T14:00:00Z", close: 10, source: "tradingview"),
            periodPoint("2026-10-21T14:01:00Z", close: 11, source: "tradingview"),
            periodPoint("2026-10-21T14:02:00Z", close: 12, state: "provisional", source: "sina-foreign-futures"),
            periodPoint("2026-10-21T14:03:00Z", close: 999, state: "provisional", source: "TradingView"),
            periodPoint("2026-10-21T14:04:00Z", close: 888, state: "provisional", source: "sina-foreign-futures", session: "post")
        ]
        for period in [MarketChartPeriod.minute5, .minute30, .minute60] {
            let source = periodChart(points, market: "COMMODITY", isFinal: false)
            let result = try XCTUnwrap(marketChartForDisplay(source, period: period, now: periodTestNow))
            let tail = try XCTUnwrap(result.candles.last)
            let artifacts = try await marketChartArtifacts(for: result)

            XCTAssertEqual(tail.timestamp, try periodTimestamp("2026-10-21T14:00:00Z"))
            XCTAssertEqual(tail.close, 12)
            XCTAssertEqual(tail.state, "provisional")
            XCTAssertEqual(Set(tail.source.split(separator: ",")), ["sina-foreign-futures", "tradingview"])
            XCTAssertFalse(result.quality.isFinal)
            XCTAssertEqual(artifacts.presentation.points, result.candles)
            XCTAssertEqual(artifacts.presentation.values, [8, 10, 12])
            XCTAssertEqual(artifacts.presentation.xFractions, [0, 0.5, 1])
            XCTAssertEqual(artifacts.listTrend, [8, 10, 12])
            assertLinePlanCoversEveryEdgeOnce(artifacts.presentation)
        }
    }

    func testCalendarLinePresentationsKeepMixedProviderProvisionalTailBuckets() async throws {
        let points = try [
            periodPoint("2026-08-31T00:00:00Z", close: 8, source: "tradingview", tradingDate: "2026-08-31"),
            periodPoint("2026-09-30T00:00:00Z", close: 10, source: "tradingview", tradingDate: "2026-09-30"),
            periodPoint("2026-10-01T00:00:00Z", close: 11, source: "tradingview", tradingDate: "2026-10-01"),
            periodPoint("2026-10-02T00:00:00Z", close: 12, state: "provisional",
                        source: "yahoo", tradingDate: "2026-10-02"),
            periodPoint("2026-10-03T00:00:00Z", close: 999, state: "invalid",
                        source: "TradingView", tradingDate: "2026-10-03")
        ]
        for period in [MarketChartPeriod.weekly, .monthly] {
            let source = periodChart(points, interval: "1d", market: "COMMODITY", isFinal: false)
            let result = try XCTUnwrap(marketChartForDisplay(source, period: period, now: periodTestNow))
            let tail = try XCTUnwrap(result.candles.last)
            let artifacts = try await marketChartArtifacts(for: result)
            let expectedValues: [Double] = period == .weekly ? [8, 12] : [8, 10, 12]

            XCTAssertEqual(tail.close, 12)
            XCTAssertEqual(tail.state, "provisional")
            XCTAssertEqual(Set(tail.source.split(separator: ",")), ["yahoo", "tradingview"])
            XCTAssertEqual(result.tradingDate, "2026-10-02")
            XCTAssertFalse(result.quality.isFinal)
            XCTAssertEqual(result.periodReturn?.endPrice, 12)
            XCTAssertEqual(artifacts.presentation.points, result.candles)
            XCTAssertEqual(artifacts.presentation.values, expectedValues)
            XCTAssertEqual(artifacts.presentation.xFractions.last, 1)
            XCTAssertEqual(artifacts.listTrend, expectedValues)
            assertLinePlanCoversEveryEdgeOnce(artifacts.presentation)
        }
    }

    func testDailyChartPointDecodesTheExplicitTradingDateContract() throws {
        let timestamp = try periodTimestamp("2026-10-19T00:00:00Z")
        let data = Data("""
        {"timestamp":\(timestamp),"tradingDate":"2026-10-19","open":10,"high":12,
         "low":9,"close":11,"volume":null,"state":"confirmed","source":"cboe"}
        """.utf8)

        let point = try JSONDecoder().decode(MarketChartPoint.self, from: data)

        XCTAssertEqual(point.tradingDate, "2026-10-19")
        XCTAssertEqual(point.timestamp, timestamp)
    }

    func testPureTradingViewDailyLiveTailSurvivesDailyWeeklyMonthlyAndListPresentation() async throws {
        let points = try [
            periodPoint("2026-10-16T00:00:00Z", close: 8, volume: 1, source: "tradingview", tradingDate: "2026-10-16"),
            periodPoint("2026-10-19T00:00:00Z", close: 10, volume: 1, source: "tradingview", tradingDate: "2026-10-19"),
            periodPoint("2026-10-20T00:00:00Z", close: 11, volume: 1, source: "tradingview", tradingDate: "2026-10-20"),
            periodPoint("2026-10-21T05:00:00Z", open: 11, high: 13, low: 10, close: 12, volume: 2,
                        state: "provisional", source: "TradingViewBrowser", tradingDate: "2026-10-21")
        ]
        let source = periodChart(points, interval: "1d", symbol: "NG1!", market: "COMMODITY", timezone: "America/Chicago", isFinal: false)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-21T16:00:00Z"))
        for period in [MarketChartPeriod.daily, .weekly, .monthly] {
            let result = try XCTUnwrap(marketChartForDisplay(source, period: period, now: now))
            let tail = try XCTUnwrap(result.candles.last)
            let artifacts = try await marketChartArtifacts(for: result)
            XCTAssertEqual(tail.close, 12)
            XCTAssertEqual(tail.high, 13)
            XCTAssertEqual(tail.state, "provisional")
            XCTAssertEqual(result.tradingDate, "2026-10-21")
            XCTAssertEqual(result.quality.actual, 4)
            XCTAssertFalse(result.quality.isFinal)
            XCTAssertEqual(result.periodReturn?.endPrice, 12)
            XCTAssertEqual(artifacts.presentation.points, result.candles)
            XCTAssertEqual(artifacts.presentation.values.last, 12)
            XCTAssertEqual(artifacts.listTrend.last, 12)
            assertLinePlanCoversEveryEdgeOnce(artifacts.presentation)
        }
        XCTAssertEqual(marketSampledChartTrend(points, interval: "1d").last, 12)
    }

    func testRawTradingViewProvisionalBarsRemainHiddenAtBothNativeIntradayIntervals() throws {
        let points = try [
            periodPoint("2026-10-21T13:30:00Z", close: 10, source: "TradingViewBrowser"),
            periodPoint("2026-10-21T13:45:00Z", close: 999, state: "provisional", source: "TradingViewBrowser"),
            periodPoint("2026-10-21T14:00:00Z", close: 888, state: "provisional", source: "yahoo", session: "post")
        ]
        for interval in ["1m", "15m"] {
            XCTAssertEqual(marketChartDisplayPoints(points, interval: interval), [points[0]])
            XCTAssertEqual(MarketChartPresentation(chart: periodChart(points, interval: interval)).points, [points[0]])
            XCTAssertEqual(marketSampledChartTrend(points, interval: interval), [10])
        }
    }

    func testWeeklyCandlesUseTradingDateInsteadOfShiftingUTCDateLabelsToSunday() throws {
        let points = try [
            periodPoint("2026-10-19T00:00:00Z", open: 10, high: 12, low: 9, close: 11,
                        volume: 2, source: "cboe", session: nil, tradingDate: "2026-10-19"),
            periodPoint("2026-10-20T00:00:00Z", open: 11, high: 15, low: 8, close: 14,
                        volume: 3, source: "cboe", session: nil, tradingDate: "2026-10-20")
        ]

        let result = try XCTUnwrap(marketChartForDisplay(periodChart(points, interval: "1d"), period: .weekly, now: periodTestNow))

        let candle = try XCTUnwrap(result.candles.first)
        XCTAssertEqual(result.candles.count, 1)
        XCTAssertEqual(candle.timestamp, try periodTimestamp("2026-10-19T04:00:00Z"))
        XCTAssertEqual(candle.open, 10)
        XCTAssertEqual(candle.high, 15)
        XCTAssertEqual(candle.low, 8)
        XCTAssertEqual(candle.close, 14)
        XCTAssertEqual(candle.volume, 5)
    }

    func testMonthlyCandlesUseTradingDateInsteadOfThePreviousLocalCalendarDate() throws {
        let points = try [
            periodPoint("2026-09-30T00:00:00Z", close: 10, source: "cboe", session: nil,
                        tradingDate: "2026-09-30"),
            periodPoint("2026-10-01T00:00:00Z", close: 20, source: "cboe", session: nil,
                        tradingDate: "2026-10-01")
        ]

        let result = try XCTUnwrap(marketChartForDisplay(periodChart(points, interval: "1d"), period: .monthly, now: periodTestNow))

        XCTAssertEqual(result.candles.map(\.timestamp), try [
            periodTimestamp("2026-09-01T04:00:00Z"),
            periodTimestamp("2026-10-01T04:00:00Z")
        ])
        XCTAssertEqual(result.candles.map(\.close), [10, 20])
    }

    func testAggregationExcludesInvalidPricesWithoutClaimingCompleteCoverage() throws {
        let points = try [
            periodPoint("2026-10-21T13:31:00Z", open: 10, high: 11, low: 9, close: 10, volume: 2),
            periodPoint("2026-10-21T13:32:00Z", open: 1, high: 999, low: 1, close: 999, volume: 1000, state: "invalid"),
            periodPoint("2026-10-21T13:33:00Z", open: 10, high: 12, low: 8, close: 11, volume: 4),
            periodPoint("2026-10-21T13:35:00Z", open: 11, high: 13, low: 10, close: 12, volume: 3, state: "provisional")
        ]

        let result = try XCTUnwrap(marketChartForDisplay(periodChart(points, isFinal: false), period: .minute5, now: periodTestNow))

        XCTAssertEqual(result.candles, try [
            periodPoint("2026-10-21T13:30:00Z", open: 10, high: 13, low: 8, close: 12, volume: 9, state: "provisional")
        ])
        XCTAssertEqual(result.quality.status, .partial)
        XCTAssertEqual(result.quality.expected, 4)
        XCTAssertEqual(result.quality.actual, 4)
        XCTAssertFalse(result.quality.isFinal)

        let invalidOnly = try XCTUnwrap(marketChartForDisplay(periodChart([points[1]]), period: .minute5, now: periodTestNow))
        XCTAssertTrue(invalidOnly.candles.isEmpty)
        XCTAssertEqual(invalidOnly.quality.status, .partial)
    }

    func testAggregatedCandleKeepsProvisionalStateUntilEverySourcePointIsConfirmed() throws {
        let points = try [
            periodPoint("2026-10-21T13:30:00Z", close: 10, state: "provisional"),
            periodPoint("2026-10-21T13:31:00Z", close: 12)
        ]

        let result = try XCTUnwrap(marketChartForDisplay(periodChart(points), period: .minute5, now: periodTestNow))

        XCTAssertEqual(result.candles.first?.state, "provisional")
        XCTAssertFalse(result.quality.isFinal)
    }

    func testHiddenProvisionalSnapshotsDoNotHideConfirmedCandlesOrClaimMissingData() throws {
        let points = try [
            periodPoint("2026-10-21T13:31:00Z", close: 10, volume: 2),
            periodPoint("2026-10-21T13:32:00Z", close: 999, volume: 1000,
                        state: "provisional", source: "TradingView"),
            periodPoint("2026-10-21T13:33:00Z", close: 12, volume: 3),
            periodPoint("2026-10-21T13:34:00Z", close: 888, volume: 1000,
                        state: "provisional", session: "post")
        ]

        let result = try XCTUnwrap(marketChartForDisplay(periodChart(points), period: .minute5, now: periodTestNow))

        XCTAssertEqual(result.candles, try [
            periodPoint("2026-10-21T13:30:00Z", open: 10, high: 12, low: 10, close: 12, volume: 5)
        ])
        XCTAssertEqual(MarketChartPresentation(chart: result).values, [12])
        XCTAssertEqual(result.quality.status, .complete)
        XCTAssertEqual(result.quality.expected, 4)
        XCTAssertEqual(result.quality.actual, 4)
    }

    func testAggregationPreservesRepairingStatusAndSourceGapStatistics() throws {
        let points = try [
            periodPoint("2026-10-21T13:31:00Z", close: 10, source: "provider-a"),
            periodPoint("2026-10-21T13:33:00Z", close: 12, source: "provider-b")
        ]
        let gapTimestamp = try periodTimestamp("2026-10-21T13:31:00Z")
        let gaps = [MarketChartGap(startTimestamp: gapTimestamp, endTimestamp: gapTimestamp)]
        let source = periodChart(points, status: .repairing, expected: 3, actual: 2, missing: gaps, isFinal: false)

        let result = try XCTUnwrap(marketChartForDisplay(source, period: .minute5, now: periodTestNow))

        XCTAssertEqual(result.candles.count, 1)
        XCTAssertEqual(Set(result.candles[0].source.split(separator: ",").map(String.init)), ["provider-a", "provider-b"])
        XCTAssertEqual(result.quality.status, .repairing)
        XCTAssertEqual(result.quality.expected, 3)
        XCTAssertEqual(result.quality.actual, 2)
        XCTAssertEqual(result.quality.missing, gaps)
        XCTAssertEqual(result.quality.freshnessSeconds, source.quality.freshnessSeconds)
        XCTAssertFalse(result.quality.isFinal)

        let unavailable = try XCTUnwrap(marketChartForDisplay(
            periodChart([], interval: "1d", status: .unavailable, expected: 250, actual: 0),
            period: .weekly, now: periodTestNow
        ))
        XCTAssertTrue(unavailable.candles.isEmpty)
        XCTAssertEqual(unavailable.quality.status, .unavailable)
        XCTAssertEqual(unavailable.quality.expected, 250)
        XCTAssertEqual(unavailable.quality.actual, 0)
    }

    func testNativePeriodsPreserveCanonicalCandlesAndSourceQuality() throws {
        for (period, interval) in [
            (MarketChartPeriod.intraday, "1m"), (.fiveDays, "15m"), (.minute1, "1m"),
            (.minute15, "15m"), (.daily, "1d")
        ] {
            let points: [MarketChartPoint]
            if interval == "1d" {
                points = try [
                    periodPoint("2026-10-19T04:00:00Z", close: 10, tradingDate: "2026-10-19"),
                    periodPoint("2026-10-20T04:00:00Z", close: 12, tradingDate: "2026-10-20"),
                    periodPoint("2026-10-21T04:00:00Z", close: 11, tradingDate: "2026-10-21")
                ]
            } else {
                let middle = interval == "15m" ? "2026-10-21T13:45:00Z" : "2026-10-21T13:31:00Z"
                let last = interval == "15m" ? "2026-10-21T14:00:00Z" : "2026-10-21T13:32:00Z"
                points = try [
                    periodPoint("2026-10-21T13:30:00Z", close: 10),
                    periodPoint(middle, close: 12),
                    periodPoint(last, close: 11)
                ]
            }
            let source = periodChart(points, interval: interval, status: .partial, expected: 4, actual: 3, isFinal: false)

            let result = try XCTUnwrap(marketChartForDisplay(source, period: period, now: periodTestNow))

            XCTAssertEqual(result.candles, source.candles)
            XCTAssertEqual(result.interval, source.interval)
            XCTAssertEqual(result.symbol, source.symbol)
            XCTAssertEqual(result.market, source.market)
            XCTAssertEqual(result.tradingDate, source.tradingDate)
            XCTAssertEqual(result.timezone, source.timezone)
            XCTAssertEqual(result.session, source.session)
            XCTAssertEqual(result.quality.status, source.quality.status)
            XCTAssertEqual(result.quality.expected, source.quality.expected)
            XCTAssertEqual(result.quality.actual, source.quality.actual)
            XCTAssertEqual(result.quality.missing, source.quality.missing)
            XCTAssertEqual(result.quality.freshnessSeconds, source.quality.freshnessSeconds)
            XCTAssertEqual(result.quality.isFinal, source.quality.isFinal)
            XCTAssertEqual(result.quote.price, source.quote.price)
            XCTAssertEqual(result.quote.source, source.quote.source)
        }
    }

    func testDailyDateLabelsNormalizeToExchangeMidnightBeforeDrawing() throws {
        let points = try [
            periodPoint("2026-10-19T00:00:00Z", open: 10, high: 12, low: 9, close: 11,
                        source: "cboe", session: nil, tradingDate: "2026-10-19"),
            periodPoint("2026-10-20T00:00:00Z", open: 11, high: 15, low: 8, close: 14,
                        source: "cboe", session: nil, tradingDate: "2026-10-20")
        ]

        let result = try XCTUnwrap(marketChartForDisplay(periodChart(points, interval: "1d"), period: .daily, now: periodTestNow))

        XCTAssertEqual(result.candles.map(\.timestamp), try [
            periodTimestamp("2026-10-19T04:00:00Z"), periodTimestamp("2026-10-20T04:00:00Z")
        ])
        XCTAssertEqual(result.candles.map(\.tradingDate), ["2026-10-19", "2026-10-20"])
        XCTAssertEqual(result.candles.map(\.close), [11, 14])
        XCTAssertEqual(result.quality.status, .complete)
    }

    func testInvalidDailyDateIsExcludedAndMarksCoveragePartial() throws {
        let points = try [
            periodPoint("2026-10-19T00:00:00Z", close: 10, source: "cboe", tradingDate: "2026-10-19"),
            periodPoint("2026-10-20T00:00:00Z", close: 999, source: "cboe", tradingDate: "2026-99-99")
        ]

        let result = try XCTUnwrap(marketChartForDisplay(periodChart(points, interval: "1d"), period: .daily, now: periodTestNow))

        XCTAssertEqual(result.candles.map(\.timestamp), try [periodTimestamp("2026-10-19T04:00:00Z")])
        XCTAssertEqual(result.candles.map(\.close), [10])
        XCTAssertEqual(result.tradingDate, "2026-10-19")
        XCTAssertEqual(result.quality.status, .partial)
        XCTAssertEqual(result.quality.expected, 2)
        XCTAssertEqual(result.quality.actual, 2)
    }

    func testExplicitSourceGapsDowngradeCompleteWithoutFillingMissingMinutes() throws {
        let points = try [
            periodPoint("2026-10-21T13:30:00Z", close: 10),
            periodPoint("2026-10-21T13:32:00Z", close: 12)
        ]
        let missingMinute = try periodTimestamp("2026-10-21T13:31:00Z")
        let gaps = [MarketChartGap(startTimestamp: missingMinute, endTimestamp: missingMinute)]
        for source in [
            periodChart(points, expected: 3, actual: 2, missing: gaps),
            periodChart(points, expected: 2, actual: 2, missing: gaps)
        ] {
            let result = try XCTUnwrap(marketChartForDisplay(source, period: .intraday, now: periodTestNow))
            XCTAssertEqual(result.candles, points)
            XCTAssertEqual(result.quality.status, .partial)
            XCTAssertEqual(result.quality.expected, source.quality.expected)
            XCTAssertEqual(result.quality.actual, source.quality.actual)
            XCTAssertEqual(result.quality.missing, source.quality.missing)
        }
    }

    func testCalendarChartDateStopsAtTheLastSourceDayActuallyDrawn() throws {
        for (period, firstInstant, firstTradingDate) in [
            (MarketChartPeriod.weekly, "2026-10-19T00:00:00Z", "2026-10-19"),
            (.monthly, "2026-10-01T00:00:00Z", "2026-10-01")
        ] {
            let points = try [
                periodPoint(firstInstant, close: 10, source: "cboe", tradingDate: firstTradingDate),
                periodPoint("2026-10-20T00:00:00Z", close: 12, source: "cboe", tradingDate: "2026-10-20"),
                periodPoint("2026-10-21T00:00:00Z", close: 999, state: "invalid",
                            source: "TradingView", tradingDate: "2026-10-21")
            ]

            let result = try XCTUnwrap(marketChartForDisplay(periodChart(points, interval: "1d"), period: period, now: periodTestNow))

            XCTAssertEqual(result.tradingDate, "2026-10-20")
            XCTAssertEqual(result.candles.last?.close, 12)
            XCTAssertEqual(result.quality.status, .partial)
        }
    }

    func testDisplayedCalendarReturnsUseAllIncludedDailyClosesAfterFiltering() throws {
        for period in [MarketChartPeriod.daily, .weekly, .monthly] {
            let firstDate = period == .monthly ? "2026-10-01" : "2026-10-19"
            var points: [MarketChartPoint] = []
            if period != .daily {
                let truncatedDate = period == .weekly ? "2026-10-16" : "2026-09-30"
                points.append(try periodPoint("\(truncatedDate)T00:00:00Z", close: 5,
                                              source: "cboe", tradingDate: truncatedDate))
            }
            points += try [
                periodPoint("\(firstDate)T00:00:00Z", close: 10, source: "cboe", tradingDate: firstDate),
                periodPoint("2026-10-20T00:00:00Z", close: 12, source: "cboe", tradingDate: "2026-10-20"),
                periodPoint("2026-10-21T00:00:00Z", close: 999, state: "invalid",
                            source: "TradingView", tradingDate: "2026-10-21")
            ]
            let sourceReturn = MarketChartPeriodReturn(
                range: "1y", basis: "source-with-hidden-tail", startPrice: 5, endPrice: 999,
                change: 994, percent: 19_880, startTimestamp: points.first?.timestamp,
                endTimestamp: points.last?.timestamp
            )
            let volatility = MarketChartPeriodVolatility(
                range: "1y", basis: "annualized-log-returns", percent: 18.5,
                observationCount: 252, annualizationPeriods: 252
            )
            let source = periodChart(points, interval: "1d", periodReturn: sourceReturn, periodVolatility: volatility)

            let result = try XCTUnwrap(marketChartForDisplay(source, period: period, now: periodTestNow))
            let displayedReturn = try XCTUnwrap(result.periodReturn)

            XCTAssertEqual(displayedReturn.range, period.sourceRange.apiRange)
            XCTAssertEqual(displayedReturn.basis, "displayed-close-to-close")
            let startPrice = period == .daily ? 10.0 : 5.0
            let startDate = period == .daily ? firstDate : period == .weekly ? "2026-10-16" : "2026-09-30"
            XCTAssertEqual(displayedReturn.startPrice, startPrice)
            XCTAssertEqual(displayedReturn.endPrice, 12)
            XCTAssertEqual(displayedReturn.change, 12 - startPrice)
            XCTAssertEqual(displayedReturn.percent ?? .nan, (12 - startPrice) / startPrice * 100, accuracy: 0.000_001)
            XCTAssertEqual(displayedReturn.startTimestamp, try periodTimestamp("\(startDate)T04:00:00Z"))
            XCTAssertEqual(displayedReturn.endTimestamp, try periodTimestamp("2026-10-20T04:00:00Z"))
            XCTAssertEqual(result.periodVolatility?.percent, 18.5)
            XCTAssertEqual(result.periodVolatility?.basis, "annualized-log-returns")
        }
    }

    func testFiveDayReturnUsesTheVisibleFifteenMinuteCloses() throws {
        let points = try [
            periodPoint("2026-10-20T13:30:00Z", close: 10),
            periodPoint("2026-10-21T13:30:00Z", close: 12),
            periodPoint("2026-10-21T13:45:00Z", close: 999, state: "provisional", source: "TradingView")
        ]
        let sourceReturn = MarketChartPeriodReturn(
            range: "5d", basis: "source-with-hidden-tail", startPrice: 10, endPrice: 999,
            change: 989, percent: 9_890, startTimestamp: points[0].timestamp, endTimestamp: points[2].timestamp
        )

        let result = try XCTUnwrap(marketChartForDisplay(
            periodChart(points, interval: "15m", periodReturn: sourceReturn), period: .fiveDays, now: periodTestNow
        ))
        let displayedReturn = try XCTUnwrap(result.periodReturn)

        XCTAssertEqual(displayedReturn.range, "5d")
        XCTAssertEqual(displayedReturn.basis, "displayed-close-to-close")
        XCTAssertEqual(displayedReturn.startPrice, 10)
        XCTAssertEqual(displayedReturn.endPrice, 12)
        XCTAssertEqual(displayedReturn.percent ?? .nan, 20, accuracy: 0.000_001)
        XCTAssertEqual(displayedReturn.startTimestamp, points[0].timestamp)
        XCTAssertEqual(displayedReturn.endTimestamp, points[1].timestamp)
    }

    func testEmptyDisplayedRangesDoNotRetainReturnsForInvisibleSourcePrices() throws {
        let sourceReturn = MarketChartPeriodReturn(
            range: "1y", basis: "source", startPrice: 10, endPrice: 12, change: 2,
            percent: 20, startTimestamp: 1, endTimestamp: 2
        )
        for period in [MarketChartPeriod.fiveDays, .daily, .weekly, .monthly] {
            let source = periodChart([], interval: period.sourceRange.apiInterval, status: .unavailable,
                                     expected: 100, actual: 0, periodReturn: sourceReturn)
            let result = try XCTUnwrap(marketChartForDisplay(source, period: period, now: periodTestNow))
            XCTAssertNil(result.periodReturn)
        }
    }

    func testIntradayAndMinutePeriodsKeepTheSourceReturnContract() throws {
        let sourceReturn = MarketChartPeriodReturn(
            range: "1d", basis: "previous-close", startPrice: 9, endPrice: 12, change: 3,
            percent: 33.33, startTimestamp: 1, endTimestamp: 2
        )
        for period in [MarketChartPeriod.intraday, .minute1, .minute5, .minute15, .minute30, .minute60] {
            let last = period == .minute15 ? "2026-10-21T13:45:00Z" : "2026-10-21T13:31:00Z"
            let points = try [periodPoint("2026-10-21T13:30:00Z", close: 10), periodPoint(last, close: 12)]
            let result = try XCTUnwrap(marketChartForDisplay(
                periodChart(points, interval: period.sourceRange.apiInterval, periodReturn: sourceReturn), period: period, now: periodTestNow
            ))
            XCTAssertEqual(result.periodReturn?.basis, sourceReturn.basis)
            XCTAssertEqual(result.periodReturn?.startPrice, sourceReturn.startPrice)
            XCTAssertEqual(result.periodReturn?.endPrice, sourceReturn.endPrice)
            XCTAssertEqual(result.periodReturn?.percent, sourceReturn.percent)
            XCTAssertEqual(result.periodReturn?.startTimestamp, sourceReturn.startTimestamp)
            XCTAssertEqual(result.periodReturn?.endTimestamp, sourceReturn.endTimestamp)
        }
    }

    func testCurrentMinuteAndFifteenMinuteBucketsAreUnfinishedEvenWithConfirmedSourceBars() throws {
        for (period, interval, start, during, end) in [
            (MarketChartPeriod.intraday, "1m", "2026-10-21T14:00:00Z", "2026-10-21T14:00:30Z", "2026-10-21T14:01:00Z"),
            (.minute1, "1m", "2026-10-21T14:00:00Z", "2026-10-21T14:00:30Z", "2026-10-21T14:01:00Z"),
            (.fiveDays, "15m", "2026-10-21T14:00:00Z", "2026-10-21T14:07:00Z", "2026-10-21T14:15:00Z"),
            (.minute15, "15m", "2026-10-21T14:00:00Z", "2026-10-21T14:07:00Z", "2026-10-21T14:15:00Z")
        ] {
            let source = periodChart(try [periodPoint(start, close: 10)], interval: interval)
            let duringBucket = Date(timeIntervalSince1970: Double(try periodTimestamp(during)) / 1_000)
            let followingBucket = Date(timeIntervalSince1970: Double(try periodTimestamp(end)) / 1_000)

            let current = try XCTUnwrap(marketChartForDisplay(source, period: period, now: duringBucket))
            let closed = try XCTUnwrap(marketChartForDisplay(source, period: period, now: followingBucket))

            XCTAssertFalse(current.quality.isFinal)
            XCTAssertTrue(closed.quality.isFinal)
            XCTAssertEqual(current.quality.status, source.quality.status)
            XCTAssertEqual(current.quality.expected, source.quality.expected)
            XCTAssertEqual(current.quality.actual, source.quality.actual)
            XCTAssertEqual(current.candles.first?.state, "confirmed")
        }
    }

    func testEveryChartPeriodRejectsMismatchedSourceIntervalsAndInvalidTimezones() throws {
        let points = try [periodPoint("2026-10-21T13:30:00Z", close: 10)]
        for period in MarketChartPeriod.allCases {
            let sourceInterval = period.sourceRange.apiInterval
            let wrongInterval = sourceInterval == "1d" ? "1m" : "1d"
            XCTAssertNil(marketChartForDisplay(periodChart(points, interval: wrongInterval), period: period, now: periodTestNow))
            XCTAssertNil(marketChartForDisplay(
                periodChart(points, interval: sourceInterval, timezone: "Invalid/Exchange"),
                period: period, now: periodTestNow
            ))
        }
    }

    func testDailyPeriodsDecodeAndRejectPreviouslyDownsampledOHLCBuckets() throws {
        let json = """
        {"symbol":"SPY","market":"US","tradingDate":"2026-10-21",
         "timezone":"America/New_York","session":"regular","interval":"1d",
         "analysis":{"aggregation":"ohlc-buckets","candleTimestamp":"trading-date","sessionWindows":[]},
         "quality":{"status":"complete","expected":2,"actual":2,"missing":[],
                    "freshnessSeconds":12,"isFinal":true},
         "quote":{"source":"yahoo"},
         "candles":[
           {"timestamp":1792468800000,"open":10,"high":12,"low":9,"close":11,
            "volume":2,"state":"confirmed","source":"yahoo","session":"regular"},
           {"timestamp":1792555200000,"open":11,"high":14,"low":10,"close":13,
            "volume":3,"state":"confirmed","source":"yahoo","session":"regular"}
         ]}
        """
        let sampled = try JSONDecoder().decode(MarketChart.self, from: Data(json.utf8))
        XCTAssertEqual(sampled.analysis.aggregation, "ohlc-buckets")
        for period in [MarketChartPeriod.daily, .weekly, .monthly] {
            XCTAssertNil(marketChartForDisplay(sampled, period: period, now: periodTestNow),
                         "A time-window OHLC bucket cannot be relabeled as a daily, weekly, or monthly candle")
        }

        let raw = try JSONDecoder().decode(
            MarketChart.self, from: Data(json.replacingOccurrences(of: "ohlc-buckets", with: "none").utf8)
        )
        XCTAssertEqual(raw.analysis.aggregation, "none")
        for period in [MarketChartPeriod.daily, .weekly, .monthly] {
            XCTAssertNotNil(marketChartForDisplay(raw, period: period, now: periodTestNow))
        }

        let unknown = try JSONDecoder().decode(
            MarketChart.self, from: Data(json.replacingOccurrences(of: "ohlc-buckets", with: "unknown-aggregation").utf8)
        )
        for period in [MarketChartPeriod.daily, .weekly, .monthly] {
            XCTAssertNil(marketChartForDisplay(unknown, period: period, now: periodTestNow))
        }
    }

    func testCurrentWeeklyCandleIsUnfinishedWithoutChangingConfirmedSourceState() throws {
        let points = try [periodPoint("2026-10-26T04:00:00Z", close: 10)]
        let source = periodChart(points, interval: "1d")
        let duringWeek = Date(timeIntervalSince1970: Double(try periodTimestamp("2026-10-27T13:00:00Z")) / 1_000)
        let followingWeek = Date(timeIntervalSince1970: Double(try periodTimestamp("2026-11-02T13:00:00Z")) / 1_000)

        let current = try XCTUnwrap(marketChartForDisplay(source, period: .weekly, now: duringWeek))
        let closed = try XCTUnwrap(marketChartForDisplay(source, period: .weekly, now: followingWeek))

        XCTAssertFalse(current.quality.isFinal)
        XCTAssertTrue(closed.quality.isFinal)
        XCTAssertEqual(current.candles.first?.state, "confirmed")
        XCTAssertEqual(current.quality.status, source.quality.status)
        XCTAssertEqual(current.quality.expected, source.quality.expected)
        XCTAssertEqual(current.quality.actual, source.quality.actual)
    }

    func testCurrentMonthlyCandleUsesTheExchangeLocalClockForFinality() throws {
        let points = try [periodPoint("2026-09-30T15:00:00Z", close: 10)]
        let source = periodChart(points, interval: "1d", timezone: "Asia/Tokyo")
        // Tokyo is already in October/November while UTC is still in the previous month.
        let duringMonth = Date(timeIntervalSince1970: Double(try periodTimestamp("2026-09-30T16:00:00Z")) / 1_000)
        let followingMonth = Date(timeIntervalSince1970: Double(try periodTimestamp("2026-10-31T16:00:00Z")) / 1_000)

        let current = try XCTUnwrap(marketChartForDisplay(source, period: .monthly, now: duringMonth))
        let closed = try XCTUnwrap(marketChartForDisplay(source, period: .monthly, now: followingMonth))

        XCTAssertFalse(current.quality.isFinal)
        XCTAssertTrue(closed.quality.isFinal)
        XCTAssertEqual(current.candles.first?.state, "confirmed")
        XCTAssertEqual(current.quality.status, source.quality.status)
        XCTAssertEqual(current.quality.expected, source.quality.expected)
        XCTAssertEqual(current.quality.actual, source.quality.actual)
    }

    func testAggregatedSixtyMinuteChartStillLabelsTheChinaLunchBreak() throws {
        let instants = [
            "2026-10-21T02:31:00Z", "2026-10-21T02:45:00Z", "2026-10-21T03:00:00Z",
            "2026-10-21T03:15:00Z", "2026-10-21T03:30:00Z", "2026-10-21T05:01:00Z",
            "2026-10-21T05:02:00Z"
        ]
        let points = try instants.enumerated().map { index, instant in
            try periodPoint(instant, close: Double(index + 1))
        }
        let chart = try XCTUnwrap(marketChartForDisplay(
            periodChart(points, market: "CN", timezone: "Asia/Shanghai"), period: .minute60, now: periodTestNow
        ))

        let presentation = MarketChartPresentation(chart: chart)

        XCTAssertEqual(chart.candles.count, 2)
        XCTAssertEqual(presentation.sessionBreak?.label, "午间休市")
        XCTAssertEqual(presentation.sessionBreak?.previousTimestamp, try periodTimestamp("2026-10-21T02:30:00Z"))
        XCTAssertEqual(presentation.sessionBreak?.currentTimestamp, try periodTimestamp("2026-10-21T05:00:00Z"))
    }

    func testFiveMinutePresentationKeepsExtendedSessionLabelsButMonthlyChartsDoNot() throws {
        let points = try [
            periodPoint("2026-10-21T13:00:00Z", close: 10, session: "pre"),
            periodPoint("2026-10-21T13:01:00Z", close: 11, session: "pre"),
            periodPoint("2026-10-21T13:30:00Z", close: 12)
        ]
        let minuteChart = try XCTUnwrap(marketChartForDisplay(periodChart(points), period: .minute5, now: periodTestNow))
        XCTAssertEqual(MarketChartPresentation(chart: minuteChart).extendedSessionLabel, "含盘前盘后")

        let monthlyChart = try XCTUnwrap(marketChartForDisplay(periodChart(points, interval: "1d"), period: .monthly, now: periodTestNow))
        XCTAssertNil(MarketChartPresentation(chart: monthlyChart).extendedSessionLabel)

        let minute = Int64(60 * 1_000)
        let fractions = marketChartXFractions(timestamps: [0, 60 * minute, 300 * minute], interval: "1mo")
        XCTAssertEqual(fractions[1], 0.2, accuracy: 0.0001)
        let followingMonth = try periodPoint("2026-11-21T13:00:00Z", close: 15, session: "pre")
        let monthlyPresentation = MarketChartPresentation(chart: periodChart([points[0], followingMonth], interval: "1mo"))
        assertLinePlanCoversEveryEdgeOnce(monthlyPresentation)
        XCTAssertTrue(monthlyPresentation.lineSegments.allSatisfy { !$0.isMissing })
    }

    func testSessionColorChangesPreserveEveryContinuousPremarketToRegularEdge() throws {
        let points = try [
            periodPoint("2026-10-21T13:28:00Z", close: 10, session: "pre"),
            periodPoint("2026-10-21T13:29:00Z", close: 11, session: "pre"),
            periodPoint("2026-10-21T13:30:00Z", close: 12),
            periodPoint("2026-10-21T13:31:00Z", close: 13)
        ]
        let presentation = MarketChartPresentation(chart: periodChart(points))

        assertLinePlanCoversEveryEdgeOnce(presentation)
        assertLineEdge(endingAt: 1, in: presentation, isRegular: false, isMissing: false)
        assertLineEdge(endingAt: 2, in: presentation, isRegular: true, isMissing: false)
        assertLineEdge(endingAt: 3, in: presentation, isRegular: true, isMissing: false)
    }

    func testNVDAMinuteAggregationsKeepTheContinuousPremarketToRegularBoundary() throws {
        let sourcePoints = try [
            periodPoint("2026-10-21T13:28:00Z", close: 180.10, session: "pre"),
            periodPoint("2026-10-21T13:29:00Z", close: 180.20, session: "pre"),
            periodPoint("2026-10-21T13:30:00Z", close: 180.30, session: "pre"),
            periodPoint("2026-10-21T13:31:00Z", close: 180.40)
        ]
        let source = periodChart(sourcePoints)

        for period in [MarketChartPeriod.minute5, .minute30, .minute60] {
            let chart = try XCTUnwrap(marketChartForDisplay(source, period: period, now: periodTestNow))
            let presentation = MarketChartPresentation(chart: chart)

            XCTAssertEqual(presentation.points.count, 2)
            XCTAssertEqual(presentation.points.map(\.session), ["pre", "regular"])
            XCTAssertEqual(presentation.values, [180.30, 180.40])
            assertLinePlanCoversEveryEdgeOnce(presentation)
            assertLineEdge(endingAt: 1, in: presentation, isRegular: true, isMissing: false)
        }
    }

    func testLineSegmentColorUsesTheCurrentPointAndNormalizesRegularSessionLabels() throws {
        let minute = Int64(60 * 1_000)
        let start = try periodTimestamp("2026-10-21T13:29:00Z")
        let sessions: [String?] = ["pre", "regular", nil, "closed", "post", "overnight", "regular"]
        let points = sessions.enumerated().map { index, session in
            chartPoint(timestamp: start + Int64(index) * minute, close: Double(index + 10), session: session)
        }
        let presentation = MarketChartPresentation(chart: periodChart(points))

        assertLinePlanCoversEveryEdgeOnce(presentation)
        for (end, regular) in [true, true, true, false, false, true].enumerated() {
            assertLineEdge(endingAt: end + 1, in: presentation, isRegular: regular, isMissing: false)
        }
    }

    func testCompleteMinuteCoverageDoesNotInventMissingDataFromWallClockSpacing() throws {
        let minute = Int64(60 * 1_000)
        let start = try periodTimestamp("2026-10-21T14:00:00Z")
        for (interval, minutes) in [("1m", 1), ("5m", 5), ("15m", 15), ("30m", 30), ("60m", 60)] {
            let points = [
                chartPoint(timestamp: start, close: 10),
                chartPoint(timestamp: start + Int64(minutes * 2) * minute, close: 12)
            ]
            let presentation = MarketChartPresentation(chart: periodChart(points, interval: interval))
            assertLinePlanCoversEveryEdgeOnce(presentation)
            assertLineEdge(endingAt: 1, in: presentation, isRegular: true, isMissing: false)
        }
    }

    func testPartialAndRepairingCoverageMarkOnlyOversizedGapsWithinTheOpenSession() throws {
        let minute = Int64(60 * 1_000)
        let start = try periodTimestamp("2026-10-21T14:00:00Z")
        for status in [MarketChartQualityStatus.partial, .repairing] {
            for (interval, minutes) in [("1m", 1), ("5m", 5), ("15m", 15), ("30m", 30), ("60m", 60)] {
                let points = [
                    chartPoint(timestamp: start, close: 10),
                    chartPoint(timestamp: start + Int64(minutes) * minute, close: 11),
                    chartPoint(timestamp: start + Int64(minutes * 3) * minute, close: 12)
                ]
                let presentation = MarketChartPresentation(chart: periodChart(
                    points, interval: interval, status: status, expected: 4, actual: 3
                ))
                assertLinePlanCoversEveryEdgeOnce(presentation)
                assertLineEdge(endingAt: 1, in: presentation, isRegular: true, isMissing: false)
                assertLineEdge(endingAt: 2, in: presentation, isRegular: true, isMissing: true)
            }
        }
    }

    func testExplicitMissingRangeMarksAnEdgeEvenWhenSourceStatusSaysComplete() throws {
        let points = try [
            periodPoint("2026-10-21T14:00:00Z", close: 10),
            periodPoint("2026-10-21T14:05:00Z", close: 12),
            periodPoint("2026-10-21T14:10:00Z", close: 13)
        ]
        let missingTimestamp = try periodTimestamp("2026-10-21T14:03:00Z")
        let presentation = MarketChartPresentation(chart: periodChart(
            points, interval: "5m", missing: [MarketChartGap(startTimestamp: missingTimestamp, endTimestamp: missingTimestamp)]
        ))

        assertLinePlanCoversEveryEdgeOnce(presentation)
        assertLineEdge(endingAt: 1, in: presentation, isRegular: true, isMissing: true)
        assertLineEdge(endingAt: 2, in: presentation, isRegular: true, isMissing: false)
    }

    func testExplicitMissingRangeOutsideAnEdgeDoesNotMarkUnrelatedPrices() throws {
        let points = try [
            periodPoint("2026-10-21T14:00:00Z", close: 10),
            periodPoint("2026-10-21T14:05:00Z", close: 11)
        ]
        let earlier = try periodTimestamp("2026-10-21T13:59:00Z")
        let later = try periodTimestamp("2026-10-21T14:06:00Z")
        let presentation = MarketChartPresentation(chart: periodChart(
            points, interval: "5m", missing: [
                MarketChartGap(startTimestamp: earlier, endTimestamp: earlier),
                MarketChartGap(startTimestamp: later, endTimestamp: later)
            ]
        ))

        assertLinePlanCoversEveryEdgeOnce(presentation)
        assertLineEdge(endingAt: 1, in: presentation, isRegular: true, isMissing: false)
    }

    func testMissingDataAndSessionColorChangesKeepIndependentEdgeStyles() throws {
        let points = try [
            periodPoint("2026-10-21T13:28:00Z", close: 10, session: "pre"),
            periodPoint("2026-10-21T13:30:00Z", close: 12),
            periodPoint("2026-10-21T13:31:00Z", close: 13)
        ]
        let missingTimestamp = try periodTimestamp("2026-10-21T13:29:00Z")
        let presentation = MarketChartPresentation(chart: periodChart(
            points, status: .partial, expected: 4, actual: 3,
            missing: [MarketChartGap(startTimestamp: missingTimestamp, endTimestamp: missingTimestamp)]
        ))

        assertLinePlanCoversEveryEdgeOnce(presentation)
        assertLineEdge(endingAt: 1, in: presentation, isRegular: true, isMissing: true)
        assertLineEdge(endingAt: 2, in: presentation, isRegular: true, isMissing: false)
    }

    func testFiveTradingDaysOfFifteenMinutePricesKeepOvernightAndWeekendEdgesSolid() throws {
        let minute = Int64(60 * 1_000)
        var points: [MarketChartPoint] = []
        for day in ["2026-10-15", "2026-10-16", "2026-10-19", "2026-10-20", "2026-10-21"] {
            let open = try periodTimestamp("\(day)T13:30:00Z")
            for index in 0...26 {
                points.append(chartPoint(timestamp: open + Int64(index * 15) * minute, close: Double(points.count + 100)))
            }
        }
        for status in [MarketChartQualityStatus.complete, .partial, .repairing] {
            let presentation = MarketChartPresentation(chart: periodChart(points, interval: "15m", status: status))

            assertLinePlanCoversEveryEdgeOnce(presentation)
            XCTAssertEqual(presentation.lineSegments.count, 1)
            XCTAssertEqual(presentation.lineSegments.first?.indices, Array(points.indices))
            XCTAssertTrue(presentation.lineSegments.allSatisfy { $0.isRegular && !$0.isMissing })
        }
    }

    func testChinaLunchClosureRemainsSolidWhileExplicitMissingMinutesRemainMissing() throws {
        let points = try [
            periodPoint("2026-10-21T03:29:00Z", close: 10),
            periodPoint("2026-10-21T03:30:00Z", close: 11),
            periodPoint("2026-10-21T05:01:00Z", close: 12),
            periodPoint("2026-10-21T05:02:00Z", close: 13)
        ]
        let presentation = MarketChartPresentation(chart: periodChart(
            points, market: "CN", timezone: "Asia/Shanghai", status: .repairing
        ))
        assertLinePlanCoversEveryEdgeOnce(presentation)
        XCTAssertTrue(presentation.lineSegments.allSatisfy { !$0.isMissing })
        assertLineEdge(endingAt: 2, in: presentation, isRegular: true, isMissing: false)

        let beforeLunch = try [
            periodPoint("2026-10-21T03:15:00Z", close: 10),
            periodPoint("2026-10-21T05:01:00Z", close: 12)
        ]
        let missingTimestamp = try periodTimestamp("2026-10-21T03:20:00Z")
        let withRealGap = MarketChartPresentation(chart: periodChart(
            beforeLunch, market: "CN", timezone: "Asia/Shanghai", status: .partial,
            missing: [MarketChartGap(startTimestamp: missingTimestamp, endTimestamp: missingTimestamp)]
        ))
        assertLinePlanCoversEveryEdgeOnce(withRealGap)
        assertLineEdge(endingAt: 1, in: withRealGap, isRegular: true, isMissing: true)
    }

    func testCornScheduledBreakPreservesPricesWithoutMissingEdgesAtEveryMinutePeriod() throws {
        let points = try [
            periodPoint("2026-10-21T12:44:00Z", close: 10, volume: 1),
            periodPoint("2026-10-21T12:45:00Z", close: 11, volume: 1),
            periodPoint("2026-10-21T13:31:00Z", close: 12, volume: 1),
            periodPoint("2026-10-21T13:32:00Z", close: 13, volume: 1)
        ]
        let source = periodChart(points, symbol: "ZC1!", market: "COMMODITY", timezone: "America/Chicago", status: .partial)
        for period in [MarketChartPeriod.intraday, .minute5, .minute30, .minute60] {
            let result = try XCTUnwrap(marketChartForDisplay(source, period: period, now: periodTestNow))
            let presentation = MarketChartPresentation(chart: result)
            XCTAssertEqual(result.candles.first?.open, 10)
            XCTAssertEqual(result.candles.last?.close, 13)
            XCTAssertEqual(result.candles.compactMap(\.volume).reduce(0, +), 4)
            XCTAssertEqual(result.quality.actual, 4)
            assertLinePlanCoversEveryEdgeOnce(presentation)
            XCTAssertTrue(presentation.lineSegments.allSatisfy { !$0.isMissing })
            XCTAssertEqual(presentation.sessionBreak?.label, "日间休市")
            XCTAssertEqual(presentation.sessionBreak?.currentTimestamp, try periodTimestamp(period == .intraday ? "2026-10-21T13:31:00Z" : "2026-10-21T13:30:00Z"))
        }
    }

    func testOvernightBucketsKeepFixedAnchorsAcrossChicagoMidnight() throws {
        let points = try [
            periodPoint("2026-10-22T04:58:00Z", close: 10, volume: 1),
            periodPoint("2026-10-22T04:59:00Z", close: 11, volume: 1),
            periodPoint("2026-10-22T05:00:00Z", close: 12, volume: 1),
            periodPoint("2026-10-22T05:01:00Z", close: 13, volume: 1)
        ]
        for (period, firstStart) in [(MarketChartPeriod.minute5,"04:55"),(.minute30,"04:30"),(.minute60,"04:00")] {
            for symbol in ["ZC1!", "GC1!"] {
                let chart = try XCTUnwrap(marketChartForDisplay(periodChart(points, symbol: symbol, market: "COMMODITY", timezone: "America/Chicago"), period: period, now: periodTestNow))
                XCTAssertEqual(chart.candles, try [
                    periodPoint("2026-10-22T\(firstStart):00Z", open: 10, high: 12, low: 10, close: 12, volume: 3),
                    periodPoint("2026-10-22T05:00:00Z", close: 13, volume: 1)
                ])
            }
        }
    }

    func testCornTradingDayRetainsItsPreviousEveningAndRestartsAtNextEvening() throws {
        let points = try [
            periodPoint("2026-10-21T00:01:00Z", close: 10, volume: 1),
            periodPoint("2026-10-21T00:02:00Z", close: 11, volume: 1),
            periodPoint("2026-10-21T18:20:00Z", close: 12, volume: 1),
            periodPoint("2026-10-22T00:01:00Z", close: 13, volume: 1),
            periodPoint("2026-10-22T00:02:00Z", close: 14, volume: 1)
        ]
        let source = periodChart(points, symbol: "ZC1!", market: "COMMODITY", timezone: "America/Chicago")
        let intraday = try XCTUnwrap(marketChartForDisplay(source, period: .intraday, now: periodTestNow))
        XCTAssertEqual(intraday.candles, points, "A trading-day date label must not discard the previous local evening")
        for (period, finalStart) in [(MarketChartPeriod.minute5,"18:15"),(.minute30,"18:00"),(.minute60,"17:30")] {
            let result = try XCTUnwrap(marketChartForDisplay(source, period: period, now: periodTestNow))
            XCTAssertEqual(result.candles.map(\.timestamp), try [
                periodTimestamp("2026-10-21T00:00:00Z"),
                periodTimestamp("2026-10-21T\(finalStart):00Z"),
                periodTimestamp("2026-10-22T00:00:00Z")
            ])
            XCTAssertEqual(result.candles.compactMap(\.volume).reduce(0, +), 5)
            XCTAssertEqual(result.candles.last?.close, 14)
        }
    }

    func testCornRealMissingMinutesAcrossMidnightRemainMissing() throws {
        let points = try [
            periodPoint("2026-10-22T04:59:00Z", close: 10),
            periodPoint("2026-10-22T05:01:00Z", close: 11),
            periodPoint("2026-10-22T05:02:00Z", close: 12)
        ]
        let presentation = MarketChartPresentation(chart: periodChart(
            points, symbol: "ZC1!", market: "COMMODITY", timezone: "America/Chicago", status: .repairing
        ))
        assertLinePlanCoversEveryEdgeOnce(presentation)
        assertLineEdge(endingAt: 1, in: presentation, isRegular: true, isMissing: true)
        assertLineEdge(endingAt: 2, in: presentation, isRegular: true, isMissing: false)
        XCTAssertNil(presentation.sessionBreak)
    }

    func testCornQuarterHourDaySessionStartsAtEightThirtyWithoutMissingBreak() throws {
        let points = try [
            periodPoint("2026-10-21T12:30:00Z", close: 10),
            periodPoint("2026-10-21T13:30:00Z", close: 11),
            periodPoint("2026-10-21T13:45:00Z", close: 12),
            periodPoint("2026-10-21T18:15:00Z", close: 13)
        ]
        let source = periodChart(points, interval: "15m", symbol: "ZC1!", market: "COMMODITY", timezone: "America/Chicago", status: .partial)
        for period in [MarketChartPeriod.fiveDays, .minute15] {
            let result = try XCTUnwrap(marketChartForDisplay(source, period: period, now: periodTestNow))
            XCTAssertEqual(result.candles, points, "The day-session's first and last real buckets must remain visible")
            let presentation = MarketChartPresentation(chart: result)
            assertLinePlanCoversEveryEdgeOnce(presentation)
            assertLineEdge(endingAt: 1, in: presentation, isRegular: true, isMissing: false)
            XCTAssertEqual(presentation.sessionBreak?.label, "日间休市")
            XCTAssertEqual(presentation.sessionBreak?.currentTimestamp, try periodTimestamp("2026-10-21T13:30:00Z"))
        }
    }

    func testCornQuarterHourNightSessionIncludesNineteenHundredBucketStart() throws {
        let points = try [
            periodPoint("2026-10-22T00:00:00Z", close: 10),
            periodPoint("2026-10-22T00:30:00Z", close: 11)
        ]
        let result = try XCTUnwrap(marketChartForDisplay(
            periodChart(points, interval: "15m", symbol: "ZC1!", market: "COMMODITY", timezone: "America/Chicago", status: .repairing),
            period: .minute15, now: periodTestNow
        ))
        XCTAssertEqual(result.candles, points)
        let presentation = MarketChartPresentation(chart: result)
        assertLinePlanCoversEveryEdgeOnce(presentation)
        assertLineEdge(endingAt: 1, in: presentation, isRegular: true, isMissing: true)
        XCTAssertNil(presentation.sessionBreak)
    }

    func testCornQuarterHourLastNightBucketKeepsItsSessionAndRealGap() throws {
        let points = try [
            periodPoint("2026-10-21T12:00:00Z", close: 10),
            periodPoint("2026-10-21T12:30:00Z", close: 11),
            periodPoint("2026-10-21T13:30:00Z", close: 12)
        ]
        let result = try XCTUnwrap(marketChartForDisplay(
            periodChart(points, interval: "15m", symbol: "ZC1!", market: "COMMODITY", timezone: "America/Chicago", status: .partial),
            period: .fiveDays, now: periodTestNow
        ))
        XCTAssertEqual(result.candles, points)
        let presentation = MarketChartPresentation(chart: result)
        assertLinePlanCoversEveryEdgeOnce(presentation)
        assertLineEdge(endingAt: 1, in: presentation, isRegular: true, isMissing: true)
        assertLineEdge(endingAt: 2, in: presentation, isRegular: true, isMissing: false)
        XCTAssertEqual(presentation.sessionBreak?.previousTimestamp, try periodTimestamp("2026-10-21T12:30:00Z"))
    }

    func testCryptoMissingMinutesAcrossMidnightStayMissingDuringContinuousTrading() throws {
        let points = try [
            periodPoint("2026-10-20T23:59:00Z", close: 10),
            periodPoint("2026-10-21T00:01:00Z", close: 11),
            periodPoint("2026-10-21T00:02:00Z", close: 12)
        ]
        for status in [MarketChartQualityStatus.partial, .repairing] {
            let presentation = MarketChartPresentation(chart: periodChart(
                points, market: "CRYPTO", timezone: "UTC", status: status, expected: 4, actual: 3
            ))
            assertLinePlanCoversEveryEdgeOnce(presentation)
            assertLineEdge(endingAt: 1, in: presentation, isRegular: true, isMissing: true)
            assertLineEdge(endingAt: 2, in: presentation, isRegular: true, isMissing: false)
        }
    }

    func testEmptyAndSinglePointLinePlansKeepDrawablePointsWithoutInventingEdges() {
        let empty = MarketChartPresentation(chart: periodChart([]))
        XCTAssertTrue(empty.lineSegments.isEmpty)
        assertLinePlanCoversEveryEdgeOnce(empty)

        for session: String? in [nil, "regular", "closed", "pre", "post", "overnight"] {
            let presentation = MarketChartPresentation(chart: periodChart([
                chartPoint(timestamp: 1_000, close: 10, session: session)
            ]))
            assertLinePlanCoversEveryEdgeOnce(presentation)
            XCTAssertEqual(presentation.lineSegments.count, 1)
            XCTAssertEqual(presentation.lineSegments.first?.indices, [0])
            XCTAssertEqual(presentation.lineSegments.first?.isRegular, session == nil || session == "regular" || session == "closed")
            XCTAssertEqual(presentation.lineSegments.first?.isMissing, false)
        }
    }

    func testLinePointsAndVolumeBarsUseTheSameCoordinatesWithOnlyEdgeClamping() {
        XCTAssertEqual(marketChartXFractions(timestamps: [], interval: "1m"), [])
        XCTAssertEqual(marketChartXFractions(timestamps: [1_000], interval: "1m"), [0.5])
        XCTAssertEqual(marketVolumeBarX(fraction: 0.5, width: 300, barWidth: 8), 150)
        XCTAssertEqual(marketVolumeBarX(fraction: 0.25, width: 300, barWidth: 8), 75)
        XCTAssertEqual(marketVolumeBarX(fraction: 0.75, width: 300, barWidth: 8), 225)

        let points = (0..<5).map { index in
            chartPoint(timestamp: Int64(index) * 60_000, close: Double(index + 10), volume: 100)
        }
        let presentation = MarketChartPresentation(chart: periodChart(points))
        XCTAssertEqual(presentation.xFractions, [0, 0.25, 0.5, 0.75, 1])
        XCTAssertTrue(presentation.hasVolume)
        for fraction in presentation.xFractions.dropFirst().dropLast() {
            XCTAssertEqual(marketVolumeBarX(fraction: fraction, width: 300, barWidth: 8), 300 * fraction)
        }
        XCTAssertEqual(marketVolumeBarX(fraction: presentation.xFractions[0], width: 300, barWidth: 8), 4)
        XCTAssertEqual(marketVolumeBarX(fraction: presentation.xFractions[4], width: 300, barWidth: 8), 296)
    }

    func testFlatPriceChartsExpandOnlyTheFiniteDisplayAxis() {
        for price in [100.0, 0.0, 0.000_000_01] {
            let points = [chartPoint(timestamp: 1_000, close: price), chartPoint(timestamp: 61_000, close: price)]
            let presentation = MarketChartPresentation(chart: periodChart(points))
            let margin = max(abs(price) * 0.001, 0.000_001)

            XCTAssertEqual(presentation.low ?? .nan, price - margin, accuracy: 0.000_000_001)
            XCTAssertEqual(presentation.high ?? .nan, price + margin, accuracy: 0.000_000_001)
            XCTAssertTrue(presentation.low?.isFinite == true)
            XCTAssertTrue(presentation.high?.isFinite == true)
            XCTAssertEqual(presentation.values, [price, price])
            XCTAssertEqual(presentation.points, points)
        }
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
        XCTAssertNil(marketNearestChartIndex(fraction: 0.5, fractions: []))
        XCTAssertEqual(marketNearestChartIndex(fraction: 0.25, fractions: [0.5]), 0)
    }

    func testNearestChartIndexUsesFirstPointWhenPositionsOrDistancesTie() {
        let fractions: [CGFloat] = [0, 0.25, 0.25, 0.75, 0.75, 1, 1]
        XCTAssertEqual(marketNearestChartIndex(fraction: 0.25, fractions: fractions), 1)
        XCTAssertEqual(marketNearestChartIndex(fraction: 0.5, fractions: fractions), 1)
        XCTAssertEqual(marketNearestChartIndex(fraction: 0.625, fractions: fractions), 3)
        XCTAssertEqual(marketNearestChartIndex(fraction: 2, fractions: fractions), 5)
    }

    func testChartDisplayArtifactsReuseDisplayedPointsForIndicatorsAndCoverage() async throws {
        let start = try periodTimestamp("2026-10-21T13:24:00Z")
        let points: [MarketChartPoint] = (1...24).map { minute in
            let timestamp = start + Int64(minute) * 60_000
            let state = minute == 24 ? "invalid" : "confirmed"
            let session = minute <= 6 ? "pre" : "regular"
            return chartPoint(timestamp: timestamp, close: Double(minute), state: state, session: session)
        }
        let result = try await marketChartDisplayArtifacts(for: periodChart(points), period: .intraday)
        let artifacts = try XCTUnwrap(result)
        XCTAssertEqual(artifacts.presentation.lineSegments.count, 2)
        XCTAssertEqual(artifacts.drawnPointCount, 23)
        XCTAssertEqual(artifacts.movingAverages.map(\.period), [5, 10, 20])
        XCTAssertEqual(artifacts.movingAverages.map { $0.values.first ?? nil }, [nil, nil, nil])
        XCTAssertEqual(artifacts.movingAverages.map { $0.values.last ?? nil }, [21, 18.5, 13.5])
    }

    func testSubCentSparklinesKeepTheirRealMovementAndRemainScaleInvariant() {
        let values = [0.07701, 0.07723, 0.07710]
        let size = CGSize(width: 76, height: 34)
        let points = marketSparklinePoints(values, size: size)
        let scaled = marketSparklinePoints(values.map { $0 * 1000 }, size: size)
        XCTAssertEqual(points.map(\.y).max()! - points.map(\.y).min()!, 28, accuracy: 0.000001)
        for (actual, expected) in zip(points, scaled) {
            XCTAssertEqual(actual.y, expected.y, accuracy: 0.000001)
        }
        for value in [0.0, 0.07711, 100.0] {
            let flat = marketSparklinePoints([value, value], size: size)
            XCTAssertTrue(flat.allSatisfy { $0.y.isFinite && abs($0.y - 17) < 0.000001 })
        }
        let bounds = marketSparklineBounds(values, minimumRelativeRange: 0.0025)
        XCTAssertEqual(bounds.upper - bounds.lower, 0.00022, accuracy: 0.000001)
    }

    func testDetailPricePrecisionPreservesLowPricesAndSmallChanges() {
        XCTAssertEqual(marketDetailPriceDigits(value: 0.07718, price: 0.07718, symbol: "BINANCE:DOGEUSDT"), 5)
        XCTAssertEqual(marketDetailPriceDigits(value: -0.00001, price: 0.07718, symbol: "BINANCE:DOGEUSDT"), 5)
        XCTAssertEqual(marketDetailPriceDigits(value: -0.000001, price: 0.07718, symbol: "BINANCE:DOGEUSDT"), 6)
        XCTAssertEqual(marketDetailPriceDigits(value: 0.0, price: 0.07718, symbol: "BINANCE:DOGEUSDT"), 5)
        XCTAssertEqual(marketDetailPriceDigits(value: 760.95, price: 761, symbol: "SPY"), 2)
    }

    func testInstrumentPrecisionPreservesCurrencyFuturesAndYieldMoves() {
        for (symbol, price, digits) in [("USDCNY", 6.6678, 4), ("USDJPY", 156.985, 3), ("NG1!", 2.519, 3), ("HG1!", 6.487, 3), ("^TNX", 4.968, 3), ("KR10Y", 4.079, 3)] {
            XCTAssertEqual(marketPriceDigits(price, symbol: symbol), digits, symbol)
            XCTAssertEqual(marketDetailPriceDigits(value: -0.0024, price: price, symbol: symbol), max(digits, 3), symbol)
        }
        XCTAssertEqual(marketPriceDigits(0.0000001234, symbol: "BINANCE:TESTUSDT"), 10)
        XCTAssertEqual(marketPriceDigits(-2.519, symbol: "NG1!"), 3)
    }

    func testChartReadoutKeepsInstrumentPrecisionWhenWideRangeUsesFewerAxisDigits() {
        let wideAxis = marketAxisDigits(values: [6.60, 6.72])
        XCTAssertEqual(wideAxis, 2)
        XCTAssertEqual(marketChartReadoutDigits(6.6678, symbol: "USDCNY", axisDigits: wideAxis), 4)
        XCTAssertEqual(marketChartReadoutDigits(0.07718, symbol: "BINANCE:DOGEUSDT", axisDigits: wideAxis), 5)
        XCTAssertEqual(marketChartReadoutDigits(6.487, symbol: "HG1!", axisDigits: wideAxis), 3)
        XCTAssertEqual(marketChartReadoutDigits(761.1, symbol: "SPY", axisDigits: 0), 2)
        XCTAssertEqual(marketChartReadoutDigits(761.0001, symbol: "SPY", axisDigits: 4), 4)
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

    func testSparklineExtremaAndEndpointsLeaveRoomForTheStrokeAndLatestPoint() {
        let size = CGSize(width: 50, height: 20)
        let points = marketSparklinePoints([10, 15, 5, 12], size: size)
        let markerRadius: CGFloat = 2.5

        XCTAssertEqual(points.count, 4)
        for point in points {
            XCTAssertGreaterThanOrEqual(point.x - markerRadius, 0)
            XCTAssertLessThanOrEqual(point.x + markerRadius, size.width)
            XCTAssertGreaterThanOrEqual(point.y - markerRadius, 0)
            XCTAssertLessThanOrEqual(point.y + markerRadius, size.height)
        }
        XCTAssertEqual(points.first?.x, 3)
        XCTAssertEqual(points.last?.x, size.width - 3)
        XCTAssertEqual(marketLinePlotX(fraction: 0, width: 200), 3)
        XCTAssertEqual(marketLinePlotX(fraction: 1, width: 200), 197)
    }

    func testSparklineSinglePointsAndCollapsedLayoutsRemainInsideTheirBounds() {
        XCTAssertEqual(marketSparklinePoints([10], size: CGSize(width: 50, height: 20)), [CGPoint(x: 25, y: 10)])
        XCTAssertTrue(marketSparklinePoints([], size: CGSize(width: 50, height: 20)).isEmpty)
        for size in [CGSize.zero, CGSize(width: 2, height: 1)] {
            let points = marketSparklinePoints([10, 12, 8], size: size)
            for point in points {
                XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                XCTAssertGreaterThanOrEqual(point.x, 0)
                XCTAssertLessThanOrEqual(point.x, size.width)
                XCTAssertGreaterThanOrEqual(point.y, 0)
                XCTAssertLessThanOrEqual(point.y, size.height)
            }
        }
    }

    private func assertLinePlanCoversEveryEdgeOnce(
        _ presentation: MarketChartPresentation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actualEdges = presentation.lineSegments.flatMap { segment in
            zip(segment.indices, segment.indices.dropFirst()).map { [$0, $1] }
        }
        let expectedEdges = (0..<max(presentation.points.count - 1, 0)).map { [$0, $0 + 1] }
        XCTAssertEqual(actualEdges, expectedEdges, "Every consecutive price edge must be drawn exactly once", file: file, line: line)
        XCTAssertTrue(presentation.lineSegments.allSatisfy { segment in
            !segment.indices.isEmpty && segment.indices.allSatisfy { presentation.points.indices.contains($0) }
        }, file: file, line: line)
    }

    private func assertLineEdge(
        endingAt end: Int,
        in presentation: MarketChartPresentation,
        isRegular: Bool,
        isMissing: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let segments = presentation.lineSegments.filter { segment in
            zip(segment.indices, segment.indices.dropFirst()).contains { $0 == end - 1 && $1 == end }
        }
        XCTAssertEqual(segments.count, 1, "A price edge needs exactly one rendering style", file: file, line: line)
        XCTAssertEqual(segments.first?.isRegular, isRegular, file: file, line: line)
        XCTAssertEqual(segments.first?.isMissing, isMissing, file: file, line: line)
    }

    private func chartPoint(
        timestamp: Int64,
        open: Double? = nil,
        high: Double? = nil,
        low: Double? = nil,
        close: Double,
        volume: Double? = nil,
        state: String = "confirmed",
        source: String = "test",
        session: String? = "regular",
        tradingDate: String? = nil
    ) -> MarketChartPoint {
        MarketChartPoint(
            timestamp: timestamp,
            open: open ?? close,
            high: high ?? close,
            low: low ?? close,
            close: close,
            volume: volume,
            state: state,
            source: source,
            session: session,
            tradingDate: tradingDate
        )
    }

    private var periodTestNow: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    private func periodTimestamp(_ instant: String) throws -> Int64 {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: instant))
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    private func periodPoint(
        _ instant: String,
        open: Double? = nil,
        high: Double? = nil,
        low: Double? = nil,
        close: Double,
        volume: Double? = nil,
        state: String = "confirmed",
        source: String = "yahoo",
        session: String? = "regular",
        tradingDate: String? = nil
    ) throws -> MarketChartPoint {
        chartPoint(
            timestamp: try periodTimestamp(instant), open: open, high: high, low: low,
            close: close, volume: volume, state: state, source: source, session: session,
            tradingDate: tradingDate
        )
    }

    func testMissingOpeningMinutesNeverMoveDeclaredBucketBoundaries() throws {
        let points = try [
            periodPoint("2026-10-21T01:34:00Z", close: 10, volume: 1),
            periodPoint("2026-10-21T01:35:00Z", close: 11, volume: 2),
            periodPoint("2026-10-21T01:36:00Z", close: 12, volume: 3),
            periodPoint("2026-10-21T02:16:00Z", close: 13, volume: 4)
        ]
        let source = periodChart(points, market: "CN", timezone: "Asia/Shanghai", status: .partial)
        let chart = try XCTUnwrap(marketChartForDisplay(source, period: .minute5, now: periodTestNow))
        XCTAssertEqual(chart.candles.map(\.timestamp), try [
            periodTimestamp("2026-10-21T01:30:00Z"), periodTimestamp("2026-10-21T01:35:00Z"), periodTimestamp("2026-10-21T02:15:00Z")
        ])
        XCTAssertEqual(chart.candles.compactMap(\.volume), [3, 3, 4])
        XCTAssertEqual(chart.analysis.candleTimestamp, .intervalStart)
    }

    func testFullChinaSessionHasExactMinuteBucketCountsAndVolume() throws {
        let start = try periodTimestamp("2026-10-21T01:30:00Z")
        let afternoon = try periodTimestamp("2026-10-21T05:00:00Z")
        let points = (1...120).map { minute in
            chartPoint(timestamp: start + Int64(minute) * 60_000, close: 10, volume: 1)
        } + (1...120).map { minute in
            chartPoint(timestamp: afternoon + Int64(minute) * 60_000, close: 11, volume: 1)
        }
        let source = periodChart(points, market: "CN", timezone: "Asia/Shanghai")
        for (period, count) in [(MarketChartPeriod.minute5,48),(.minute30,8),(.minute60,4)] {
            let chart = try XCTUnwrap(marketChartForDisplay(source, period: period, now: periodTestNow))
            XCTAssertEqual(chart.candles.count, count)
            XCTAssertEqual(chart.candles.compactMap(\.volume).reduce(0, +), 240)
            XCTAssertEqual(chart.quality.actual, 240)
            XCTAssertEqual(MarketChartPresentation(chart: chart).sessionBreak?.label, "午间休市")
        }
    }

    private func fixtureSessionWindows(
        _ points: [MarketChartPoint], market: String, symbol: String, timezone: String, interval: String
    ) -> [MarketChartSessionWindow] {
        guard interval != "1d", let zone = TimeZone(identifier: timezone) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let specifications: [(Int, Int, String)]
        switch market {
        case "CN": specifications = [(570, 690, "regular"), (780, 900, "regular")]
        case "HK": specifications = [(570, 720, "regular"), (780, 960, "regular")]
        case "JP": specifications = [(540, 690, "regular"), (750, 930, "regular")]
        case "KR": specifications = [(540, 930, "regular")]
        case "COMMODITY" where symbol == "ZC1!": specifications = [(-300, 465, "regular"), (510, 800, "regular")]
        case "COMMODITY" where symbol != "TEST": specifications = [(-420, 960, "regular")]
        case "FX": specifications = [(-120, 1320, "regular")]
        case "US": specifications = [(-240, 240, "overnight"), (240, 570, "pre"), (570, 960, "regular"), (960, 1200, "post")]
        default: specifications = [(0, 1440, "regular")]
        }
        var dates = Set<Date>()
        for point in points {
            let instant = Date(timeIntervalSince1970: Double(point.timestamp + (interval == "1m" ? -1 : 1)) / 1_000)
            let day = calendar.startOfDay(for: instant)
            let minute = calendar.component(.hour, from: instant) * 60 + calendar.component(.minute, from: instant)
            let rollover = specifications.first!.0
            let tradingDay = rollover < 0 && minute >= 1440 + rollover ? calendar.date(byAdding: .day, value: 1, to: day)! : day
            dates.insert(tradingDay)
        }
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        return dates.flatMap { day in
            specifications.map { start, end, session in
                MarketChartSessionWindow(
                    startTimestamp: Int64(day.addingTimeInterval(Double(start * 60)).timeIntervalSince1970 * 1_000),
                    endTimestamp: Int64(day.addingTimeInterval(Double(end * 60)).timeIntervalSince1970 * 1_000),
                    tradingDate: formatter.string(from: day), session: session
                )
            }
        }.sorted { $0.startTimestamp < $1.startTimestamp }
    }

    private func periodChart(
        _ points: [MarketChartPoint],
        interval: String = "1m",
        symbol: String = "TEST",
        market: String = "US",
        timezone: String = "America/New_York",
        status: MarketChartQualityStatus = .complete,
        expected: Int? = nil,
        actual: Int? = nil,
        missing: [MarketChartGap] = [],
        isFinal: Bool = true,
        periodReturn: MarketChartPeriodReturn? = nil,
        periodVolatility: MarketChartPeriodVolatility? = nil
    ) -> MarketChart {
        MarketChart(
            symbol: symbol, market: market, tradingDate: "2026-10-21", timezone: timezone,
            session: "regular", interval: interval, periodReturn: periodReturn, periodVolatility: periodVolatility,
            quality: MarketChartQuality(
                status: status, expected: expected ?? points.count, actual: actual ?? points.count,
                missing: missing, freshnessSeconds: 12, isFinal: isFinal
            ),
            quote: MarketChartQuote(
                price: 100, previousClose: 99, change: 1, changePercent: 1,
                providerTimestamp: points.last?.timestamp, receivedTimestamp: points.last?.timestamp,
                source: "fixture"
            ),
            candles: points,
            analysis: MarketChartAnalysis(
                aggregation: "none", candleTimestamp: interval == "1m" ? .intervalEnd : interval == "1d" ? .tradingDate : .intervalStart,
                sessionWindows: fixtureSessionWindows(points, market: market, symbol: symbol, timezone: timezone, interval: interval)
            )
        )
    }
}
