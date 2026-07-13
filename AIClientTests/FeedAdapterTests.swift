import XCTest
@testable import AIServerClient

final class FeedAdapterTests: XCTestCase {
    func testDecodesAndMapsWeiboHotTopic() throws {
        let json = #"{"success":true,"data":{"topics":[{"id":9,"keyword":"测试热搜","latest_rank":2,"meta":{"last_payload":{"heat":"9988"}},"search_link":"https://s.weibo.com/test"}]}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(HotTopicsResponse.self, from: json)
        let post = Post.hotTopic(try XCTUnwrap(response.data.topics.first), source: .weibo)

        XCTAssertEqual(post.displayTitle, "测试热搜")
        XCTAssertEqual(post.feedRank, 2)
        XCTAssertEqual(post.formattedTime, "第 2 名 · 热度 9988")
        XCTAssertTrue(post.isSynthetic)
    }

    func testDecodesAndMapsFlashItem() throws {
        let json = #"{"success":true,"data":{"items":[{"id":"f1","time":"18:00","text":"快讯正文","source":"flash:jin10","isImportant":true}],"hasMore":false}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(FlashResponse.self, from: json)
        let post = Post.flash(try XCTUnwrap(response.data.items.first))

        XCTAssertEqual(post.displayContent, "快讯正文")
        XCTAssertEqual(post.authorName, "金十数据")
        XCTAssertEqual(post.tagNames, ["重要"])
    }

    func testXImageUsesServerProxy() throws {
        let url = try XCTUnwrap(MediaURL.image("https://pbs.twimg.com/media/demo.jpg"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertTrue(url.path.hasSuffix("/api/v1/image-proxy"))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "url" })?.value, "https://pbs.twimg.com/media/demo.jpg")
    }

    func testOrdinaryImageRemainsDirect() throws {
        let url = try XCTUnwrap(MediaURL.image("https://example.com/image.jpg"))
        XCTAssertEqual(url.absoluteString, "https://example.com/image.jpg")
    }

    func testBuildsWebSocketURLFromServerURL() throws {
        let url = try XCTUnwrap(RealtimeFeedClient.webSocketURL(from: URL(string: "https://example.com:3001/api")!))
        XCTAssertEqual(url.absoluteString, "wss://example.com:3001/post")
    }
}
