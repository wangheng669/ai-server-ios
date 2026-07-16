import XCTest
@testable import AIServerClient

final class FeedAdapterTests: XCTestCase {
    func testYouTubeRequestsAllScores() {
        let items = APIClient.regularPostQueryItems(page: 1, limit: 20, source: .youtube)
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(query["source"], "rss")
        XCTAssertEqual(query["include_zero_score"], "true")
        XCTAssertNil(query["final_score"])
    }

    func testRegularFeedsKeepMinimumScoreFilter() {
        let items = APIClient.regularPostQueryItems(page: 1, limit: 20, source: .rss)
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(query["include_zero_score"], "false")
        XCTAssertEqual(query["final_score"], String(Post.minimumFeedScore))
    }

    func testPlaybackStreamPathUsesAPIPrefix() throws {
        let url = try XCTUnwrap(APIClient.playbackURL(
            from: "/post/video-playback/stream?formatId=18",
            baseURL: URL(string: "http://example.com:3001")!
        ))
        XCTAssertEqual(url.absoluteString, "http://example.com:3001/api/v1/post/video-playback/stream?formatId=18")
    }

    @MainActor
    func testHotTopicChannelsRequestLargerFirstPage() async {
        var requestedLimit = 0
        let model = NewsFeedViewModel(source: .douyin) { _, limit, _ in
            requestedLimit = limit
            return []
        }

        await model.refresh()

        XCTAssertEqual(requestedLimit, 20)
    }

    @MainActor
    func testTruthRequestsEnoughPostsToIncludeMediaUpdates() async {
        var requestedLimit = 0
        let model = NewsFeedViewModel(source: .truth) { _, limit, _ in
            requestedLimit = limit
            return []
        }

        await model.refresh()

        XCTAssertEqual(requestedLimit, 20)
    }

    @MainActor
    func testCacheWarmingMakesFirstSourceSelectionImmediate() async {
        var requestedSources: [FeedSource] = []
        let model = NewsFeedViewModel(source: .x) { _, _, source in
            requestedSources.append(source)
            return []
        }

        await model.warmSourceCache()
        model.select(.zhihu)

        XCTAssertFalse(model.isSwitchingSource)
        XCTAssertEqual(Set(requestedSources), Set(FeedSource.allCases.filter { $0 != .x }))
    }

    @MainActor
    func testSwitchingSourceStartsNewestLoadBeforeCancelledLoadFinishes() async throws {
        let firstRequestStarted = expectation(description: "first request started")
        let model = NewsFeedViewModel(source: .x) { _, _, source in
            if source == .x {
                firstRequestStarted.fulfill()
                try await Task.sleep(for: .seconds(5))
            }
            return []
        }

        let firstLoad = Task { await model.refresh() }
        await fulfillment(of: [firstRequestStarted], timeout: 1)
        model.select(.zhihu)
        let newestLoad = Task { await model.refresh() }
        firstLoad.cancel()

        await newestLoad.value
        await firstLoad.value

        XCTAssertEqual(model.source, .zhihu)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isSwitchingSource)
        XCTAssertNil(model.errorMessage)
    }

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
        let json = #"{"success":true,"data":{"items":[{"id":"f1","time":"18:00","text":"快讯正文","source":"flash:jin10","isImportant":false,"finalScore":7.4}],"hasMore":false}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(FlashResponse.self, from: json)
        let post = Post.flash(try XCTUnwrap(response.data.items.first))

        XCTAssertEqual(post.displayContent, "快讯正文")
        XCTAssertEqual(post.authorName, "金十数据")
        XCTAssertEqual(post.score, 7.4)
        XCTAssertEqual(post.tagNames, ["重要"])
    }

    func testFlashScoreOverridesLegacyImportantFlag() throws {
        let json = #"{"success":true,"data":{"items":[{"id":"f2","time":"18:01","text":"普通快讯","source":"flash:sina","isImportant":true,"finalScore":6.9}],"hasMore":false}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(FlashResponse.self, from: json)
        let post = Post.flash(try XCTUnwrap(response.data.items.first))

        XCTAssertEqual(post.score, 6.9)
        XCTAssertTrue(post.tagNames.isEmpty)
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

    func testExtractsXTweetIDFromPostLink() throws {
        let data = #"{"id":7,"source":"x","post_link":"https://x.com/example/status/2076997109048308052?ref=feed"}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: data)
        XCTAssertEqual(post.xTweetID, "2076997109048308052")
    }
}
