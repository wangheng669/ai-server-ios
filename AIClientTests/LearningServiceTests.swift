import XCTest
@testable import AIServerClient

final class LearningServiceTests: XCTestCase {
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
        let response = try decoder.decode(LearningCatalogResponse.self, from: data)
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
                "books": [{
                  "id": "3300203616",
                  "title": "哈萨比斯：谷歌AI之脑",
                  "author": "[英]塞巴斯蒂安·马拉比",
                  "cover_url": "https://example.com/hassabis.jpg",
                  "category": "经济理财-商业",
                  "open_url": "weread://reading?bId=3300203616",
                  "is_finished": false,
                  "read_update_time": 1785655834
                }, {
                  "id": "907585",
                  "title": "滚雪球：巴菲特和他的财富人生（套装共2册）",
                  "author": "艾丽斯·施罗德",
                  "cover_url": "https://example.com/snowball.jpg",
                  "category": "人物传记-财经人物",
                  "open_url": "weread://reading?bId=907585",
                  "is_finished": false,
                  "read_update_time": 1785657041
                }]
              }
            }
            """.utf8
        )
        let response = try JSONDecoder().decode(LearningBookshelfResponse.self, from: data)
        XCTAssertEqual(response.data.source, "微信读书")
        XCTAssertEqual(response.data.books.count, 2)
        XCTAssertEqual(response.data.books.first?.id, "3300203616")
        XCTAssertEqual(response.data.books.first?.coverURL?.host, "example.com")
        XCTAssertEqual(response.data.books.first?.openURL?.scheme, "weread")
        XCTAssertEqual(response.data.books.first?.readUpdateTime, 1_785_655_834)
        XCTAssertEqual(response.data.books.last?.title, "滚雪球：巴菲特和他的财富人生（套装共2册）")
    }

    func testDecodesKnowledgeConceptCardAndDetail() throws {
        let data = Data(
            """
            {
              "data": {
                "id": "xinhai-revolution",
                "kind": "event",
                "title": "辛亥革命",
                "subtitle": "事件 · 1911",
                "summary": "推动清帝退位与中华民国建立的革命进程。",
                "importance": "开启共和政治实践。",
                "cover_url": "https://commons.wikimedia.org/example.jpg",
                "image_attribution": "公有领域",
                "wikipedia_language": "zh",
                "wikipedia_title": "辛亥革命",
                "wikipedia_url": "https://zh.wikipedia.org/wiki/辛亥革命",
                "key_people": ["孙中山", "黄兴"],
                "content": {
                  "background": "历史背景",
                  "timeline": [{
                    "date": "1911-10-10",
                    "title": "武昌起义",
                    "description": "各省随后相继响应。"
                  }],
                  "key_points": ["并非单一事件"],
                  "key_people": ["孙中山", "黄兴"]
                },
                "related": []
              }
            }
            """.utf8
        )
        let response = try JSONDecoder().decode(KnowledgeConceptDetailResponse.self, from: data)
        XCTAssertEqual(response.data.kind, .event)
        XCTAssertEqual(response.data.keyPeople, ["孙中山", "黄兴"])
        XCTAssertEqual(response.data.content.timeline.first?.title, "武昌起义")
        XCTAssertEqual(response.data.wikipediaURL?.host, "zh.wikipedia.org")
    }

    func testKnowledgeConceptCoverURLUsesWikimediaThumbnail() throws {
        let original = "https://upload.wikimedia.org/wikipedia/commons/4/4e/YuanShikaiPresidente1915.jpg"
        let optimized = try XCTUnwrap(KnowledgeConceptImageURL.optimized(original))

        XCTAssertEqual(optimized.host, "upload.wikimedia.org")
        XCTAssertTrue(optimized.path.contains("/wikipedia/commons/thumb/"))
        XCTAssertEqual(optimized.lastPathComponent, "960px-YuanShikaiPresidente1915.jpg")
    }

    func testKnowledgeConceptCoverURLKeepsExistingThumbnail() throws {
        let thumbnail = "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4e/Yuan.jpg/320px-Yuan.jpg"
        let optimized = try XCTUnwrap(KnowledgeConceptImageURL.optimized(thumbnail))

        XCTAssertEqual(optimized.absoluteString, thumbnail)
    }

    func testKnowledgeConceptCoverURLSetsRedirectWidth() throws {
        let redirect = "https://commons.wikimedia.org/wiki/Special:Redirect/file/Hankou.jpg?width=1200"
        let optimized = try XCTUnwrap(KnowledgeConceptImageURL.optimized(redirect))
        let width = URLComponents(url: optimized, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "width" })?
            .value

        XCTAssertEqual(width, "960")
    }

    func testKnowledgeConceptCoverURLLeavesOtherHostsUntouched() throws {
        let original = "https://example.com/history/cover.jpg"
        let optimized = try XCTUnwrap(KnowledgeConceptImageURL.optimized(original))

        XCTAssertEqual(optimized.absoluteString, original)
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

        let response = try JSONDecoder().decode(LearningVideoLessonResponse.self, from: data)
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
