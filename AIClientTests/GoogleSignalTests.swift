import XCTest
@testable import AIServerClient

final class GoogleSignalTests: XCTestCase {
    func testDecodesEventPageWithPriorityAndTimeline() throws {
        let data = Data(
            """
            {
              "items": [{
                "id": 5005,
                "representative_id": 352283,
                "representative_post_id": 495112,
                "member_count": 3,
                "source_count": 2,
                "first_seen_at": "2026-08-12T12:28:24+08:00",
                "latest_seen_at": "2026-08-12T13:30:00+08:00",
                "title": "Google 已发布 Gemini 新版本",
                "content": "中文内容",
                "original_content": "Original content",
                "content_zh": "中文内容",
                "language": "en",
                "representative_author_name": "Google AI",
                "representative_author": "GoogleAI",
                "representative_avatar_url": "https://example.com/avatar.jpg",
                "representative_source_url": "https://x.com/GoogleAI/status/42",
                "sentiment": "positive",
                "confidence": 0.95,
                "reason": "产品发布增强竞争力",
                "fact_status": "completed",
                "company_terms": ["google", "gemini"],
                "classified_at": "2026-08-12T13:31:00+08:00",
                "published_at": "2026-08-12T12:28:24+08:00",
                "priority_score": 80,
                "priority_reasons": ["近 24 小时新事件", "双来源"],
                "timeline": [{
                  "event_id": 4900,
                  "relation": "UPDATE_OF",
                  "direction": "previous",
                  "title": "Google 计划发布 Gemini 新版本",
                  "fact_status": "planned",
                  "member_count": 1,
                  "source_count": 1,
                  "first_seen_at": "2026-08-11T10:00:00+08:00",
                  "latest_seen_at": "2026-08-11T10:00:00+08:00"
                }]
              }],
              "has_more": true,
              "next_cursor": "next"
            }
            """.utf8
        )

        let page = try JSONDecoder().decode(GoogleSignalEventPage.self, from: data)
        let event = try XCTUnwrap(page.items.first)

        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextCursor, "next")
        XCTAssertEqual(event.factStatusTitle, "已完成")
        XCTAssertEqual(event.sentimentTitle, "利好")
        XCTAssertEqual(event.memberCount, 3)
        XCTAssertEqual(event.sourceCount, 2)
        XCTAssertEqual(event.priorityReasons, ["近 24 小时新事件", "双来源"])
        XCTAssertEqual(event.timeline.first?.direction, "previous")
        XCTAssertNotNil(event.firstSeenDate)
    }

    func testDecodesMinimalEventWithoutOptionalBriefingFields() throws {
        let data = Data(
            """
            {
              "id": 1,
              "representative_id": 2,
              "representative_post_id": 3,
              "member_count": 1,
              "source_count": 1,
              "first_seen_at": "2026-08-12T08:00:00Z",
              "latest_seen_at": "2026-08-12T08:00:00Z",
              "title": "据报：Google 正在测试新功能",
              "content": "内容",
              "original_content": "Content",
              "language": "en",
              "representative_author_name": "",
              "representative_author": "",
              "representative_avatar_url": "",
              "representative_source_url": "",
              "sentiment": "neutral",
              "confidence": 0.85,
              "reason": "尚未得到独立确认",
              "fact_status": "unverified",
              "company_terms": [],
              "classified_at": "2026-08-12T08:01:00Z",
              "timeline": []
            }
            """.utf8
        )

        let event = try JSONDecoder().decode(GoogleSignalEvent.self, from: data)

        XCTAssertEqual(event.factStatusTitle, "未证实")
        XCTAssertEqual(event.priorityReasons, [])
        XCTAssertNil(event.priorityScore)
        XCTAssertNil(event.contentZH)
    }

    func testEvidenceBuildsInternalXPost() throws {
        let data = Data(
            """
            {
              "id": 10,
              "post_id": 495112,
              "article_id": "42",
              "title": "Google update",
              "content": "Google 发布了新版本 &amp; 更多功能。",
              "language": "zh",
              "author_name": "Google AI",
              "author_handle": "GoogleAI",
              "avatar_url": "https://example.com/avatar.jpg",
              "source_url": "https://x.com/GoogleAI/status/42",
              "published_at": "2026-08-12T12:28:24+08:00"
            }
            """.utf8
        )

        let evidence = try JSONDecoder().decode(GoogleSignalEvidence.self, from: data)
        let post = try XCTUnwrap(evidence.previewPost)

        XCTAssertEqual(post.id, 495112)
        XCTAssertEqual(post.sourceName, "X")
        XCTAssertEqual(post.authorHandle, "@GoogleAI")
        XCTAssertEqual(post.displayContent, "Google 发布了新版本 & 更多功能。")
        XCTAssertEqual(post.xTweetID, "42")
        XCTAssertFalse(post.needsXTranslation)
    }

    func testEnglishEvidenceUsesExistingXTranslationEligibility() throws {
        let data = Data(
            """
            {
              "id": 11,
              "post_id": 495113,
              "article_id": "43",
              "title": "Google update",
              "content": "Google released a new Gemini update.",
              "language": "en",
              "author_name": "Google AI",
              "author_handle": "GoogleAI",
              "avatar_url": "https://example.com/avatar.jpg",
              "source_url": "https://x.com/GoogleAI/status/43",
              "published_at": "2026-08-12T12:28:24+08:00"
            }
            """.utf8
        )

        let evidence = try JSONDecoder().decode(GoogleSignalEvidence.self, from: data)
        let untranslated = try XCTUnwrap(evidence.previewPost)
        let translated = try XCTUnwrap(evidence.previewPost(translation: "Google 发布了 Gemini 更新。"))

        XCTAssertTrue(untranslated.needsXTranslation)
        XCTAssertEqual(untranslated.xTweetID, "43")
        XCTAssertEqual(translated.displayContent, "Google 发布了 Gemini 更新。")
        XCTAssertFalse(translated.needsXTranslation)
    }

    func testDateParserSupportsFractionalSeconds() {
        let date = GoogleSignalDateParser.date(from: "2026-08-12T12:18:05.130556+08:00")
        XCTAssertNotNil(date)
        XCTAssertNotNil(GoogleSignalDateParser.date(from: "2026-08-12T08:18:08Z"))
        XCTAssertTrue(GoogleSignalDatePresentation.detail(date).contains("8月12日"))
    }
}
