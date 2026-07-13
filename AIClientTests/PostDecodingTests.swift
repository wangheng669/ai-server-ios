import XCTest
@testable import AIServerClient

final class PostDecodingTests: XCTestCase {
    func testDecodesPostListResponse() throws {
        let json = #"""
        {
          "data": [{
            "id": 42,
            "title": "测试新闻",
            "summary": "摘要内容",
            "source": "rss:77",
            "formatted_time": "刚刚",
            "final_score": 8.6,
            "post_link": "https://example.com/post",
            "user": { "user_screen_name": "示例来源" },
            "postTags": [{ "id": 1, "name": "AI" }],
            "images": [{ "url": "https://example.com/image.jpg" }]
          }]
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(PostListResponse.self, from: json)

        XCTAssertEqual(response.data.first?.id, 42)
        XCTAssertEqual(response.data.first?.authorName, "示例来源")
        XCTAssertEqual(response.data.first?.normalizedSource, "RSS")
        XCTAssertEqual(response.data.first?.score, 8.6)
        XCTAssertEqual(response.data.first?.meetsMinimumFeedScore, true)
    }

    func testDecodesDetailAndStripsHTML() throws {
        let json = #"{"post":{"id":7,"title":"标题","content":"<p>第一段</p><p>第二段</p>","images":[]}}"#.data(using: .utf8)!

        let response = try JSONDecoder().decode(PostDetailResponse.self, from: json)

        XCTAssertEqual(response.post.id, 7)
        XCTAssertTrue(response.post.displayContent.contains("第一段"))
        XCTAssertFalse(response.post.displayContent.contains("<p>"))
    }

    func testMinimumFeedScoreBoundary() throws {
        let json = #"{"data":[{"id":1,"final_score":5},{"id":2,"final_score":4.99},{"id":3}]}"#.data(using: .utf8)!
        let posts = try JSONDecoder().decode(PostListResponse.self, from: json).data

        XCTAssertTrue(posts[0].meetsMinimumFeedScore)
        XCTAssertFalse(posts[1].meetsMinimumFeedScore)
        XCTAssertFalse(posts[2].meetsMinimumFeedScore)
    }

    func testStripsEntityEncodedHTML() throws {
        let json = #"{"post":{"id":8,"content":"正文&amp;lt;img src=&amp;quot;https://example.com/a.jpg&amp;quot;&amp;gt;结尾"}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(PostDetailResponse.self, from: json)

        XCTAssertFalse(response.post.displayContent.contains("img src"))
        XCTAssertTrue(response.post.displayContent.contains("正文"))
        XCTAssertTrue(response.post.displayContent.contains("结尾"))
    }
}
