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
    func testXRequestsLargerPageAndKeepsPagingAfterPartialResult() async throws {
        var requests: [(page: Int, limit: Int)] = []
        let first = try JSONDecoder().decode(Post.self, from: Data(#"{"id":1,"source":"x"}"#.utf8))
        let second = try JSONDecoder().decode(Post.self, from: Data(#"{"id":2,"source":"x"}"#.utf8))
        let model = NewsFeedViewModel(source: .x) { page, limit, _ in
            requests.append((page, limit))
            return page == 1 ? [first] : [second]
        }

        await model.refresh()
        await model.loadMoreIfNeeded(current: first)

        XCTAssertEqual(requests.map(\.page), [1, 2])
        XCTAssertEqual(requests.map(\.limit), [10, 10])
        XCTAssertEqual(model.posts.map(\.id), [1, 2])
    }

    @MainActor
    func testPaginationRetriesOnceAfterTransientFailure() async throws {
        var secondPageAttempts = 0
        let first = try JSONDecoder().decode(Post.self, from: Data(#"{"id":1,"source":"x"}"#.utf8))
        let second = try JSONDecoder().decode(Post.self, from: Data(#"{"id":2,"source":"x"}"#.utf8))
        let model = NewsFeedViewModel(source: .x) { page, _, _ in
            guard page > 1 else { return [first] }
            secondPageAttempts += 1
            if secondPageAttempts == 1 { throw URLError(.timedOut) }
            return [second]
        }

        await model.refresh()
        await model.loadMoreIfNeeded(current: first)

        XCTAssertEqual(secondPageAttempts, 2)
        XCTAssertEqual(model.posts.map(\.id), [1, 2])
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testRealtimePostWaitsUntilFeedAcceptsIt() async throws {
        let existing = try JSONDecoder().decode(Post.self, from: Data(#"{"id":1,"source":"x"}"#.utf8))
        let incoming = try JSONDecoder().decode(Post.self, from: Data(#"{"id":2,"source":"x"}"#.utf8))
        let model = NewsFeedViewModel(source: .x) { _, _, _ in [existing] }
        await model.refresh()

        model.receiveRealtimePost(incoming)

        XCTAssertEqual(model.posts.map(\.id), [1])
        XCTAssertEqual(model.pendingRealtimePosts.map(\.id), [2])

        model.acceptPendingRealtimePosts()

        XCTAssertEqual(model.posts.map(\.id), [2, 1])
        XCTAssertTrue(model.pendingRealtimePosts.isEmpty)
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

    @MainActor
    func testFlashChannelAcceptsRealtimeFlashPosts() throws {
        let data = #"{"id":101,"source":"flash","content":"实时快讯"}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: data)
        let model = NewsFeedViewModel(source: .flash) { _, _, _ in [] }

        XCTAssertTrue(model.matchesCurrentSource(post))
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
