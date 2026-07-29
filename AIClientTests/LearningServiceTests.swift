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
                    "thumbnail_url": "/api/v1/learning/media/cover.jpg",
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

    func testResolvesCachedMediaAgainstServer() throws {
        let topic = try JSONDecoder().decode(
            LearningTopic.self,
            from: Data(
                """
                {
                  "id":"1","lesson_id":"2","title":"标题","summary":"",
                  "category":"股票","source_url":"https://www.futunn.com/learn/detail",
                  "thumbnail_url":"/api/v1/learning/media/a.jpg","has_video":false
                }
                """.utf8
            )
        )
        let url = topic.mediaURL(topic.thumbnailURLValue, baseURL: URL(string: "https://api.example.com")!)
        XCTAssertEqual(url?.absoluteString, "https://api.example.com/api/v1/learning/media/a.jpg")
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
                  "is_finished": false
                }]
              }
            }
            """.utf8
        )
        let response = try JSONDecoder().decode(LearningBookshelfResponse.self, from: data)
        XCTAssertEqual(response.data.source, "微信读书")
        XCTAssertEqual(response.data.books.count, 1)
        XCTAssertEqual(response.data.books.first?.id, "3300203616")
        XCTAssertEqual(response.data.books.first?.coverURL?.host, "example.com")
        XCTAssertEqual(response.data.books.first?.openURL?.scheme, "weread")
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
