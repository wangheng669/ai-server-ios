import XCTest
@testable import AIServerClient

final class LearningServiceTests: XCTestCase {
    @MainActor
    func testKnowledgePreloadAndVisiblePageShareAnOverviewAndOnlyExplicitRefreshReloads() async {
        TabOverviewURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TabOverviewURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let store = LearningStore(service: LearningService(baseURL: URL(string: "https://overview.test")!, session: session))
        XCTAssertFalse(store.hasLoadedOverview)
        async let preload: Void = store.loadOverview()
        async let visible: Void = store.loadOverview()
        _ = await (preload, visible)
        XCTAssertTrue(store.hasLoadedOverview)
        XCTAssertNotNil(store.catalog)
        XCTAssertNotNil(store.bookshelf)
        XCTAssertNotNil(store.conceptLibrary)
        XCTAssertNotNil(store.videoLibrary)
        XCTAssertEqual(TabOverviewURLProtocol.requestCount, 4)
        await store.loadOverview()
        XCTAssertEqual(TabOverviewURLProtocol.requestCount, 4)
        await store.loadOverview(force: true)
        XCTAssertEqual(TabOverviewURLProtocol.requestCount, 8)
    }

    @MainActor
    func testOverviewRetriesFailedSourceEvenWhenItHasEarlierData() async {
        TabOverviewURLProtocol.reset()
        defer { TabOverviewURLProtocol.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TabOverviewURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let store = LearningStore(service: LearningService(baseURL: URL(string: "https://overview.test")!, session: session))

        await store.loadOverview()
        TabOverviewURLProtocol.setUnavailableResource("video-lessons")
        await store.loadOverview(force: true)
        XCTAssertTrue(store.hasOverviewContent)
        XCTAssertNotNil(store.videoLibrary)
        XCTAssertNotNil(store.videoLibraryErrorMessage)

        TabOverviewURLProtocol.setUnavailableResource(nil)
        await store.loadOverview()
        XCTAssertEqual(TabOverviewURLProtocol.requestCount, 12)
        XCTAssertNil(store.videoLibraryErrorMessage)
    }

    func testStockPathUsesOnlyMatchingLessonsFromTheStockSection() {
        let fund = lesson(id: "fund", title: "基金估值")
        let unrelated = lesson(id: "dividend", title: "股票分红")
        let valuation = lesson(id: "pe", title: "什么是市盈率")
        let catalog = LearningCatalog(
            source: "fixture", fetchedAt: .distantPast,
            sections: [
                LearningSection(id: "funds", name: "基金", topics: [fund]),
                LearningSection(id: "stocks", name: "股票", topics: [unrelated, valuation])
            ]
        )
        XCTAssertEqual(catalog.stockTopics.map(\.id), ["dividend", "pe"])
        let milestones = LearningMilestone.plan(from: catalog.stockTopics)
        XCTAssertEqual(milestones.map(\.title), ["估值方法"])
        XCTAssertEqual(milestones.map(\.topic.id), ["pe"])
        let noStocks = LearningCatalog(source: "fixture", fetchedAt: .distantPast, sections: [catalog.sections[0]])
        XCTAssertTrue(noStocks.stockTopics.isEmpty)
    }

    private func lesson(id: String, title: String) -> LearningTopic {
        LearningTopic(
            id: id, lessonID: id, title: title, summary: "", category: "",
            sourceURLValue: "", thumbnailURLValue: nil, hasVideo: nil, detail: nil
        )
    }

    func testIdenticalCompanyCasesAreRemovedWithoutLosingDifferentExplanations() {
        let original = LearningCompanyExample(company: "开市客", ticker: "COST", situation: "会员收入稳定", connection: "估值包含质量预期", caution: "留意价格")
        let different = LearningCompanyExample(company: "开市客", ticker: "COST", situation: "会员收入稳定", connection: "另一个独立解释", caution: "留意价格")
        let detail = LearningDetail(title: "估值", subtitle: "", views: 0, viewsText: "", updatedAt: "", videoURLValue: nil, videoPosterURLValue: nil, videoDuration: nil, blocks: [], companyExamples: [original, original, different], videoReferences: nil)
        XCTAssertEqual(detail.uniqueCompanyExamples, [original, different])
        XCTAssertNotEqual(original.id, different.id)
    }

    func testCourseVideoKeepsCDNURLForSourceHeadersAndRelativeHLSPlaylists() throws {
        let topic = try JSONDecoder().decode(LearningTopic.self, from: Data(#"{"id":"49127","lesson_id":"1","title":"市盈率","summary":"","category":"基础","source_url":"https://www.futunn.com/learn/detail-49127"}"#.utf8))
        let url = try XCTUnwrap(topic.mediaURL("https://eduvod.futunn.com/course/master.m3u8"))
        XCTAssertEqual(url.absoluteString, "https://eduvod.futunn.com/course/master.m3u8")
        XCTAssertEqual(URL(string: "video_0.m3u8", relativeTo: url)?.absoluteURL.absoluteString,
                       "https://eduvod.futunn.com/course/video_0.m3u8")
    }

    func testDecodesCachedCatalogContract() throws {
        let data = Data(
            """
            {
              "data": {
                "source": "https://www.futunn.com/learn/wiki",
                "fetched_at": "2026-07-28T06:00:00Z",
                "sections": [{
                  "id": "56",
                  "name": "股票",
                  "topics": [{
                    "id": "49127",
                    "lesson_id": "220217121",
                    "title": "什么是市盈率？",
                    "summary": "估值指标",
                    "category": "股票",
                    "source_url": "https://www.futunn.com/learn/detail-pe",
                    "thumbnail_url": "/api/ios/v1/learning/media/cover.jpg",
                    "has_video": true
                  }]
                }]
              }
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(LearningResponse<LearningCatalog>.self, from: data)
        XCTAssertEqual(response.data.topicCount, 1)
        XCTAssertEqual(response.data.sections[0].topics[0].id, "49127")
        XCTAssertEqual(response.data.sections[0].topics[0].hasVideo, true)
    }

    func testDecodesEditorialReferencesInLearningDetail() throws {
        let topic = try JSONDecoder().decode(
            LearningTopic.self,
            from: Data(
                """
                {
                  "id":"49127","lesson_id":"220217121","title":"什么是市盈率？",
                  "summary":"估值指标","category":"股票",
                  "source_url":"https://www.futunn.com/learn/detail-pe",
                  "detail":{
                    "title":"什么是市盈率？","subtitle":"估值指标",
                    "views":1,"views_text":"1","updated_at":"2025/08/19",
                    "blocks":[],
                    "company_examples":[{
                      "company":"开市客","ticker":"COST",
                      "situation":"会员收入较稳定。",
                      "connection":"估值包含质量预期。",
                      "caution":"不构成投资建议。"
                    }],
                    "video_references":[{
                      "id":7,"platform":"bilibili","creator":"小Lin说",
                      "title":"真正的做空","external_id":"BV1v34y1j7Nu",
                      "watch_url":"https://www.bilibili.com/video/BV1v34y1j7Nu/",
                      "cover_url":"https://i0.hdslb.com/cover.jpg",
                      "duration_seconds":2150,"start_seconds":48,"end_seconds":202,
                      "recommendation":"卖空为什么是先卖后买\\n亏损为什么可能没有上限"
                    }]
                  }
                }
                """.utf8
            )
        )

        XCTAssertEqual(topic.detail?.companyExamples?.count, 1)
        XCTAssertEqual(topic.detail?.companyExamples?.first?.company, "开市客")
        XCTAssertEqual(topic.detail?.companyExamples?.first?.ticker, "COST")
        let video = try XCTUnwrap(topic.detail?.videoReferences?.first)
        XCTAssertEqual(video.creator, "小Lin说")
        XCTAssertEqual(video.externalID, "BV1v34y1j7Nu")
        XCTAssertEqual(video.clipDurationText, "3 分钟")
        XCTAssertEqual(video.recommendationItems.count, 2)
        XCTAssertEqual(video.watchURL?.absoluteString, "https://www.bilibili.com/video/BV1v34y1j7Nu/?t=48")
    }

    func testResolvesCachedMediaAgainstServer() throws {
        let topic = try JSONDecoder().decode(
            LearningTopic.self,
            from: Data(
                """
                {
                  "id":"1","lesson_id":"2","title":"标题","summary":"",
                  "category":"股票","source_url":"https://www.futunn.com/learn/detail",
                  "thumbnail_url":"/api/ios/v1/learning/media/a.jpg","has_video":false
                }
                """.utf8
            )
        )
        let url = topic.mediaURL(topic.thumbnailURLValue, baseURL: URL(string: "https://api.example.com")!)
        XCTAssertEqual(url?.absoluteString, "https://api.example.com/api/ios/v1/learning/media/a.jpg")
    }

    func testDecodesFilteredWeReadBookshelf() throws {
        let data = Data(
            """
            {
              "data": {
                "source": "微信读书",
                "today_reading_seconds": 1560,
                "yesterday_reading_seconds": 7380,
                "books": [{
                  "id": "3300203616",
                  "title": "哈萨比斯：谷歌AI之脑",
                  "author": "[英]塞巴斯蒂安·马拉比",
                  "cover_url": "https://example.com/hassabis.jpg",
                  "category": "经济理财-商业",
                  "open_url": "weread://reading?bId=3300203616",
                  "is_finished": false,
                  "reading_progress": 42,
                  "record_reading_seconds": 7380,
                  "estimated_remaining_seconds": 10140,
                  "read_update_time": 1785655834
                }, {
                  "id": "907585",
                  "title": "滚雪球：巴菲特和他的财富人生（套装共2册）",
                  "author": "艾丽斯·施罗德",
                  "cover_url": "https://example.com/snowball.jpg",
                  "category": "人物传记-财经人物",
                  "open_url": "weread://reading?bId=907585",
                  "is_finished": false,
                  "reading_progress": 18,
                  "read_update_time": 1785657041
                }]
              }
            }
            """.utf8
        )
        let response = try JSONDecoder().decode(LearningResponse<LearningBookshelf>.self, from: data)
        XCTAssertEqual(response.data.source, "微信读书")
        XCTAssertEqual(response.data.todayReadingText, "26 分钟")
        XCTAssertEqual(response.data.yesterdayReadingText, "2 小时 3 分钟")
        XCTAssertEqual(response.data.books.count, 2)
        XCTAssertEqual(response.data.books.first?.id, "3300203616")
        let coverURL = try XCTUnwrap(response.data.books.first?.coverURL)
        XCTAssertEqual(try proxiedImageTarget(coverURL).host, "example.com")
        XCTAssertEqual(response.data.books.first?.openURL?.scheme, "weread")
        XCTAssertEqual(response.data.books.first?.displayReadingProgress, 42)
        XCTAssertEqual(response.data.books.first?.readingDurationText, "累计阅读 2 小时 3 分钟")
        XCTAssertEqual(response.data.books.first?.estimatedRemainingText, "预计还需 2 小时 49 分钟")
        XCTAssertEqual(response.data.books.first?.readUpdateTime, 1_785_655_834)
        XCTAssertEqual(response.data.books.last?.title, "滚雪球：巴菲特和他的财富人生（套装共2册）")
    }

    func testKnowledgeConceptCatalogDecodesWikipediaDestination() throws {
        let data = Data(#"""
        {"data":{"concepts":[{"id":"xinhai-revolution","kind":"event","title":"辛亥革命","subtitle":"事件 · 1911",
         "summary":"推动清帝退位与中华民国建立的革命进程。","importance":"开启共和政治实践。",
         "cover_url":"https://commons.wikimedia.org/example.jpg","image_attribution":"公有领域",
         "wikipedia_language":"zh","wikipedia_title":"辛亥革命","wikipedia_url":"https://zh.wikipedia.org/wiki/辛亥革命",
         "key_people":["孙中山","黄兴"]}]}}
        """#.utf8)
        let response = try JSONDecoder().decode(LearningResponse<KnowledgeConceptLibrary>.self, from: data)
        let card = try XCTUnwrap(response.data.concepts.first)
        XCTAssertEqual(card.kind, .event)
        XCTAssertEqual(card.keyPeople, ["孙中山", "黄兴"])
        XCTAssertEqual(card.wikipediaTitle, "辛亥革命")
        XCTAssertEqual(card.wikipediaURL?.host, "zh.wikipedia.org")
    }

    func testLessonPositionKeepsProgressAndTitleTogether() {
        let position = LearningLessonPosition(title: "估值方法", number: 2, count: 4)
        XCTAssertEqual(position.progress, 0.5)
        XCTAssertEqual(position.text, "第 2/4 节 · 估值方法")
        XCTAssertEqual(LearningLessonPosition(title: "", number: 1, count: 1).text, "第 1/1 节")
    }

    func testKnowledgeConceptCoverURLUsesWikimediaThumbnail() throws {
        let original = "https://upload.wikimedia.org/wikipedia/commons/4/4e/YuanShikaiPresidente1915.jpg"
        let proxied = try XCTUnwrap(KnowledgeConceptImageURL.optimized(original))
        let optimized = try proxiedImageTarget(proxied)

        XCTAssertEqual(optimized.host, "upload.wikimedia.org")
        XCTAssertTrue(optimized.path.contains("/wikipedia/commons/thumb/"))
        XCTAssertEqual(optimized.lastPathComponent, "960px-YuanShikaiPresidente1915.jpg")
    }

    func testKnowledgeConceptCoverURLKeepsExistingThumbnail() throws {
        let thumbnail = "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4e/Yuan.jpg/320px-Yuan.jpg"
        let proxied = try XCTUnwrap(KnowledgeConceptImageURL.optimized(thumbnail))
        let optimized = try proxiedImageTarget(proxied)

        XCTAssertEqual(optimized.absoluteString, thumbnail)
    }

    func testKnowledgeConceptCoverURLSetsRedirectWidth() throws {
        let redirect = "https://commons.wikimedia.org/wiki/Special:Redirect/file/Hankou.jpg?width=1200"
        let proxied = try XCTUnwrap(KnowledgeConceptImageURL.optimized(redirect))
        let optimized = try proxiedImageTarget(proxied)
        let width = URLComponents(url: optimized, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "width" })?
            .value

        XCTAssertEqual(width, "960")
    }

    func testKnowledgeConceptCoverURLProxiesOtherHosts() throws {
        let original = "https://example.com/history/cover.jpg"
        let proxied = try XCTUnwrap(KnowledgeConceptImageURL.optimized(original))
        let optimized = try proxiedImageTarget(proxied)

        XCTAssertEqual(optimized.absoluteString, original)
    }

    private func proxiedImageTarget(_ url: URL) throws -> URL {
        XCTAssertEqual(url.path, "/api/ios/v1/image-proxy")
        let value = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "url" })?
                .value
        )
        return try XCTUnwrap(URL(string: value))
    }

    func testDecodesIndependentVideoLessonDetail() throws {
        let data = Data(
            """
            {
              "data": {
                "id": "xiaolin-short-selling",
                "platform": "bilibili",
                "creator": "小Lin说",
                "title": "真正的做空",
                "summary": "理解做空的机制与风险。",
                "external_id": "BV1v34y1j7Nu",
                "watch_url": "https://www.bilibili.com/video/BV1v34y1j7Nu/",
                "cover_url": "https://i0.hdslb.com/cover.jpg",
                "duration_seconds": 2150,
                "description": "从交易结构出发理解做空。",
                "watch_points": ["做空为什么是先卖后买", "损失为什么可能没有上限"],
                "chapters": [{
                  "id": 1,
                  "title": "做空是什么",
                  "start_seconds": 48
                }],
                "related_topics": [{
                  "id": "56810",
                  "title": "什么是卖空？",
                  "category": "股票"
                }]
              }
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(LearningResponse<LearningVideoLesson>.self, from: data)
        XCTAssertEqual(response.data.creator, "小Lin说")
        XCTAssertEqual(response.data.durationText, "36 分钟")
        XCTAssertEqual(response.data.chapters.first?.timestampText, "0:48")
        XCTAssertEqual(
            response.data.watchURL(at: 48)?.absoluteString,
            "https://www.bilibili.com/video/BV1v34y1j7Nu/?t=48"
        )
        XCTAssertEqual(response.data.relatedTopics.first?.id, "56810")
    }

    @MainActor
    func testLearningProgressPersistsRealCompletionDates() {
        let suiteName = "LearningProgressStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "completed"
        let calendar = Calendar(identifier: .iso8601)
        let completionDate = Date(timeIntervalSince1970: 1_786_467_600)

        let store = LearningProgressStore(defaults: defaults, storageKey: key)
        XCTAssertFalse(store.isCompleted("lesson-1"))

        store.markCompleted("lesson-1", at: completionDate)

        let restored = LearningProgressStore(defaults: defaults, storageKey: key)
        XCTAssertTrue(restored.isCompleted("lesson-1"))
        XCTAssertEqual(restored.completedAt["lesson-1"], completionDate)
        XCTAssertEqual(
            restored.studyDays(inWeekContaining: completionDate, calendar: calendar).count,
            1
        )
    }
}

private final class TabOverviewURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var count = 0
    private static var unavailableResource: String?
    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func reset() { lock.lock(); count = 0; unavailableResource = nil; lock.unlock() }
    static func setUnavailableResource(_ resource: String?) {
        lock.lock()
        unavailableResource = resource
        lock.unlock()
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "overview.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let resource = request.url!.lastPathComponent
        Self.lock.lock()
        Self.count += 1
        let status = Self.unavailableResource == resource ? 503 : 200
        Self.lock.unlock()
        let body: String
        switch resource {
        case "catalog": body = #"{"data":{"source":"test","fetched_at":"2026-10-22T00:00:00Z","sections":[]}}"#
        case "bookshelf": body = #"{"data":{"source":"test","books":[]}}"#
        case "concepts": body = #"{"data":{"concepts":[]}}"#
        default: body = #"{"data":{"lessons":[]}}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
