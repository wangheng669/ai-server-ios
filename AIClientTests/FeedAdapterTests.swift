import XCTest
@testable import AIServerClient

final class FeedAdapterTests: XCTestCase {
    @MainActor
    func testNewYorkTimesSourceDoesNotPublishCardsUntilFullBodiesAreReady() async throws {
        let feedPosts = try (1...5).map { id in
            try JSONDecoder().decode(
                Post.self,
                from: Data(#"{"id":\#(id),"source":"rss:47","title":"Article \#(id)","content":"这是 RSS 提供的长摘要，不是完整正文。","post_link":"https://example.com/\#(id)"}"#.utf8)
            )
        }
        let model = NewsFeedViewModel(
            source: .newYorkTimes,
            fetchPosts: { _, _, _ in feedPosts },
            fetchPostDetail: { id in
                try JSONDecoder().decode(
                    Post.self,
                    from: Data(#"{"id":\#(id),"source":"rss:47","title":"Article \#(id)","content":"数据库完整正文 \#(id)。这是正文的第二段。","post_link":"https://example.com/\#(id)"}"#.utf8)
                )
            },
            fetchNewYorkTimesArticle: { url in
                NewYorkTimesArticle(blocks: [.paragraph("不应使用网页预览 \(url.lastPathComponent)。")])
            }
        )

        await model.refresh()

        XCTAssertEqual(model.posts.count, feedPosts.count)
        XCTAssertTrue(model.posts.allSatisfy {
            model.preloadedNewYorkTimesArticle(for: $0.id) == NewYorkTimesArticle(
                blocks: [.paragraph("数据库完整正文 \($0.id)。这是正文的第二段。")]
            )
        })
    }

    @MainActor
    func testNewYorkTimesRSSSelectionPrefetchesEveryArticleBody() async throws {
        let feedPosts = try (1...6).map { id in
            try JSONDecoder().decode(
                Post.self,
                from: Data(#"{"id":\#(id),"source":"rss:47","title":"Article \#(id)","content":"RSS 中已有一段很长、但并不完整的文章摘要。","post_link":"https://example.com/\#(id)"}"#.utf8)
            )
        }
        let model = NewsFeedViewModel(
            source: .rss,
            fetchRSSFeedPosts: { _ in feedPosts },
            fetchPostDetail: { id in
                try JSONDecoder().decode(
                    Post.self,
                    from: Data(#"{"id":\#(id),"source":"rss:47","title":"Article \#(id)","content":"数据库完整正文 \#(id)。这是正文的第二段。","post_link":"https://example.com/\#(id)"}"#.utf8)
                )
            },
            fetchNewYorkTimesArticle: { url in
                NewYorkTimesArticle(blocks: [.paragraph("不应使用网页预览 \(url.lastPathComponent)。")])
            }
        )

        await model.selectRSSFeed(47)

        XCTAssertEqual(model.selectedRSSPosts.count, feedPosts.count)
        XCTAssertTrue(model.selectedRSSPosts.allSatisfy {
            model.preloadedNewYorkTimesArticle(for: $0.id) == NewYorkTimesArticle(
                blocks: [.paragraph("数据库完整正文 \($0.id)。这是正文的第二段。")]
            )
        })
        XCTAssertFalse(model.isLoadingRSSSelection)
    }

    func testYouTubeRequestsAllScores() {
        let items = APIClient.regularPostQueryItems(page: 1, limit: 20, source: .youtube)
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(query["source"], "rss")
        XCTAssertEqual(query["include_zero_score"], "true")
        XCTAssertNil(query["final_score"])
    }

    func testRSSFeedsUseElevatedScoreFilter() {
        let items = APIClient.regularPostQueryItems(page: 1, limit: 20, source: .rss)
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(query["include_zero_score"], "false")
        XCTAssertEqual(query["final_score"], "6")
    }

    func testWeiboFeedIdentityUsesAuthoritativeFeedRoute() throws {
        let decoder = JSONDecoder()
        let direct = try decoder.decode(
            RSSFeedSource.self,
            from: Data(#"{"id":17,"name":"任意显示名","feed_url":"http://127.0.0.1:1200/weibo/user/1249424622","is_enabled":true}"#.utf8)
        )
        let imported = try decoder.decode(
            RSSFeedSource.self,
            from: Data(#"{"id":61,"name":"任意显示名","feed_url":"http://example.test/rss","folo_meta":{"raw_feed_url":"rsshub://weibo/user/1769173661"},"is_enabled":true}"#.utf8)
        )
        let unrelated = try decoder.decode(
            RSSFeedSource.self,
            from: Data(#"{"id":72,"name":"微博讨论区","feed_url":"http://127.0.0.1:1200/discourse/latest","is_enabled":true}"#.utf8)
        )

        XCTAssertTrue(direct.isWeiboFeed)
        XCTAssertTrue(imported.isWeiboFeed)
        XCTAssertFalse(unrelated.isWeiboFeed)
    }

    @MainActor
    func testWeiboFollowingPaginationIsIndependentAndDeduplicated() async throws {
        var requests: [(page: Int, limit: Int)] = []
        let first = try JSONDecoder().decode(Post.self, from: Data(#"{"id":1,"source":"rss:41"}"#.utf8))
        let duplicate = try JSONDecoder().decode(Post.self, from: Data(#"{"id":1,"source":"rss:41"}"#.utf8))
        let second = try JSONDecoder().decode(Post.self, from: Data(#"{"id":2,"source":"rss:52"}"#.utf8))
        let model = WeiboFollowingFeedModel { page, limit in
            requests.append((page, limit))
            return page == 1 ? [first] : [duplicate, second]
        }

        await model.refresh()
        await model.loadMoreIfNeeded(current: first)

        XCTAssertEqual(requests.map(\.page), [1, 2])
        XCTAssertEqual(requests.map(\.limit), [20, 20])
        XCTAssertEqual(model.posts.map(\.id), [1, 2])
    }

    func testWeiboFollowingRequestUsesPlatformAggregateContract() {
        let items = APIClient.weiboFollowingQueryItems(page: 3, limit: 20)
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(query["source"], "rss")
        XCTAssertEqual(query["rss_platform"], "weibo")
        XCTAssertEqual(query["page"], "3")
        XCTAssertEqual(query["limit"], "20")
        XCTAssertEqual(query["sort"], "time_desc")
        XCTAssertEqual(query["include_zero_score"], "true")
        XCTAssertNil(query["final_score"])
        XCTAssertNil(query["group_similar"])
    }

    func testPlaybackStreamPathUsesAPIPrefix() throws {
        let url = try XCTUnwrap(APIClient.playbackURL(
            from: "/post/video-playback/stream?formatId=18",
            baseURL: URL(string: "http://example.com:3001")!
        ))
        XCTAssertEqual(url.absoluteString, "http://example.com:3001/api/v1/post/video-playback/stream?formatId=18")
    }

    func testVideoThumbnailUsesOriginalMediaURL() throws {
        let baseURL = ServerConfiguration.defaultURL
        let original = "https://video.twimg.com/ext_tw_video/1/pu/vid/avc1/720x720/example.mp4?tag=12"
        let proxied = try XCTUnwrap(MediaURL.video(original))
        let thumbnail = try XCTUnwrap(MediaURL.videoThumbnail(for: proxied))
        let components = try XCTUnwrap(URLComponents(url: thumbnail, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.path, "/api/v1/video-thumbnail")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "url" })?.value, original)
        XCTAssertEqual(thumbnail.host, baseURL.host)
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
    func testFlashRequestsEnoughPostsForClientSideFilters() async {
        var requestedLimit = 0
        let model = NewsFeedViewModel(source: .flash) { _, limit, _ in
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
    func testFilteredFeedLoadsMoreFromVisibleTail() async throws {
        var requestedPages: [Int] = []
        let visibleTail = try JSONDecoder().decode(Post.self, from: Data(#"{"id":1,"source":"flash"}"#.utf8))
        let hiddenRawTail = try JSONDecoder().decode(Post.self, from: Data(#"{"id":2,"source":"flash"}"#.utf8))
        let nextMatch = try JSONDecoder().decode(Post.self, from: Data(#"{"id":3,"source":"flash"}"#.utf8))
        let model = NewsFeedViewModel(source: .flash) { page, _, _ in
            requestedPages.append(page)
            return page == 1 ? [visibleTail, hiddenRawTail] : [nextMatch]
        }

        await model.refresh()
        await model.loadMoreIfNeeded(current: visibleTail, thresholdPostID: visibleTail.id)

        XCTAssertEqual(requestedPages, [1, 2])
        XCTAssertEqual(model.posts.map(\.id), [visibleTail.id, hiddenRawTail.id, nextMatch.id])
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
    func testSwitchingToUncachedSourceClearsPreviousChannelPosts() async throws {
        let youtubePost = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":1,"source":"rss","post_link":"https://www.youtube.com/watch?v=abc"}"#.utf8)
        )
        let model = NewsFeedViewModel(source: .youtube) { _, _, _ in [youtubePost] }

        await model.refresh()
        model.select(.flash)

        XCTAssertEqual(model.source, .flash)
        XCTAssertTrue(model.posts.isEmpty)
        XCTAssertTrue(model.isSwitchingSource)
    }

    @MainActor
    func testReturningToCachedSourceKeepsExactSnapshotWithoutRefetching() async throws {
        var xRequests = 0
        let xPost = try JSONDecoder().decode(Post.self, from: Data(#"{"id":1,"source":"x"}"#.utf8))
        let zhihuPost = try JSONDecoder().decode(Post.self, from: Data(#"{"id":2,"source":"zhihu"}"#.utf8))
        let model = NewsFeedViewModel(source: .x) { _, _, source in
            if source == .x {
                xRequests += 1
                return [xPost]
            }
            return [zhihuPost]
        }

        await model.refresh()
        model.select(.zhihu)
        await model.loadInitial()
        model.select(.x)
        await model.loadInitial()

        XCTAssertEqual(xRequests, 1)
        XCTAssertEqual(model.posts.map(\.id), [xPost.id])
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

    func testFlashMapsMergedPlatformMetadata() throws {
        let json = #"{"success":true,"data":{"items":[{"id":"f3","time":"18:02","text":"同一消息","source":"flash:cls","similarityGroupId":123,"similarityScore":0.96,"similarCount":4,"platformCount":3,"platforms":["cls","jin10","sina"]}],"hasMore":false}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(FlashResponse.self, from: json)
        let post = Post.flash(try XCTUnwrap(response.data.items.first))

        XCTAssertEqual(post.meta?.flashSimilarityGroupId, 123)
        XCTAssertEqual(post.meta?.flashSimilarCount, 4)
        XCTAssertEqual(post.meta?.flashPlatformCount, 3)
        XCTAssertEqual(post.meta?.flashPlatforms ?? [], ["cls", "jin10", "sina"])
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

    func testNewYorkTimesImageUsesServerProxy() throws {
        let url = try XCTUnwrap(MediaURL.image("https://static01.nyt.com/images/example.jpg"))
        XCTAssertTrue(url.path.hasSuffix("/api/v1/image-proxy"))
    }

    func testNewYorkTimesArticleUsesServerPreviewEndpoint() throws {
        let article = try XCTUnwrap(URL(string: "https://www.nytimes.com/2026/07/19/example.html"))
        let base = try XCTUnwrap(URL(string: "https://api.wanghengai.xin"))
        let url = try XCTUnwrap(APIClient.articlePreviewURL(for: article, baseURL: base))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.path, "/api/v1/post/preview")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "url" })?.value, article.absoluteString)
        XCTAssertNil(components.queryItems?.first(where: { $0.name == "prefer_remote" }))
    }

    func testNewYorkTimesHeroVariantsAreRecognizedAsTheSameImage() throws {
        let hero = try XCTUnwrap(URL(string: "https://api.example/api/v1/image-proxy?url=https%3A%2F%2Fstatic01.nyt.com%2Fimages%2F2026%2F07%2F01%2Fhero%2Fhero-articleLarge.jpg"))
        let inline = try XCTUnwrap(URL(string: "https://static01.nyt.com/images/2026/07/01/hero/hero-master1050.jpg"))

        XCTAssertTrue(NewYorkTimesArticle.isSameImageAsset(inline, hero))
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
