import XCTest
@testable import AIServerClient

final class FeedAdapterTests: XCTestCase {
    func testRSSCardImmediatelyUsesServerLocalizedSummaryAsTitle() throws {
        let post = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":1,"source":"rss:71","title":"Target appoints its first chief AI officer","summary":"大型零售商押注人工智能，Target任命其首位首席人工智能官","content":"In this article"}"#.utf8)
        )

        XCTAssertEqual(post.rssServerLocalizedTitle, "大型零售商押注人工智能，Target任命其首位首席人工智能官")
        XCTAssertEqual(post.displayTitle, "大型零售商押注人工智能，Target任命其首位首席人工智能官")
        XCTAssertEqual(post.rssListContent, post.displayTitle)
        XCTAssertFalse(post.needsRSSCardTranslation)
    }

    func testEnglishRSSCardRequestsChineseTranslation() throws {
        let post = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":1,"source":"rss:12","title":"Markets fall as investors assess risk","summary":"Stocks moved lower in afternoon trading."}"#.utf8)
        )

        XCTAssertTrue(post.needsRSSCardTranslation)
        XCTAssertEqual(post.rssTranslationTitle, "Markets fall as investors assess risk")
        XCTAssertEqual(post.rssTranslationExcerpt, "Stocks moved lower in afternoon trading.")
    }

    func testChineseOrAlreadyTranslatedRSSCardSkipsTranslation() throws {
        let chinese = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":1,"source":"rss:12","title":"市场等待最新数据"}"#.utf8)
        )
        let translated = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":2,"source":"rss:12","title":"Markets wait for data","content_zh":"市场等待最新数据"}"#.utf8)
        )

        XCTAssertFalse(chinese.needsRSSCardTranslation)
        XCTAssertFalse(translated.needsRSSCardTranslation)
    }

    func testRSSCardTranslationChangesOnlyListPresentation() throws {
        let post = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":1,"source":"rss:12","title":"Original title","content":"Original article body"}"#.utf8)
        )
        let displayed = post.replacingRSSCardTranslation(title: "中文标题", excerpt: "中文摘要")

        XCTAssertEqual(displayed.displayTitle, "中文标题")
        XCTAssertEqual(displayed.rssListContent, "中文摘要")
        XCTAssertEqual(displayed.displayContent, "Original article body")
    }

    func testRSSPlaceholderExcerptIsHidden() throws {
        let post = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":1,"source":"rss:12","title":"Retailers invest in AI","content":"In this article"}"#.utf8)
        )

        XCTAssertNil(post.rssTranslationExcerpt)
        XCTAssertEqual(post.rssListContent, post.displayTitle)
    }

    @MainActor
    func testRSSCardTranslationPublishesIntoDisplayedPost() async throws {
        let post = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":1,"source":"rss:12","title":"Markets fall","summary":"Stocks moved lower."}"#.utf8)
        )
        let model = NewsFeedViewModel(
            source: .rss,
            translateRSSCard: { title, excerpt in
                XCTAssertEqual(title, "Markets fall")
                XCTAssertEqual(excerpt, "Stocks moved lower.")
                return RSSCardTranslation(title: "市场下跌", excerpt: "股市走低。")
            }
        )

        await model.translateRSSPostIfNeeded(post)

        XCTAssertEqual(model.postForDisplay(post).displayTitle, "市场下跌")
        XCTAssertEqual(model.postForDisplay(post).rssListContent, "股市走低。")
    }

    func testFeedDiskCacheBoundsPostsAndSeparatesServers() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FeedDiskCache(directory: directory)
        let posts = try (1...120).map { id in
            try JSONDecoder().decode(Post.self, from: Data(#"{"id":\#(id),"source":"x"}"#.utf8))
        }
        let snapshot = FeedDiskSnapshot(
            schemaVersion: 1,
            savedAt: Date(),
            source: FeedSource.x.rawValue,
            flashCategory: nil,
            posts: posts,
            page: 12,
            canLoadMore: true
        )
        let firstServer = URL(string: "https://one.example")!
        await cache.save(snapshot, serverURL: firstServer)

        let restored = await cache.load(source: .x, flashCategory: nil, serverURL: firstServer)
        XCTAssertEqual(restored?.posts.count, 100)
        let otherServer = await cache.load(
            source: .x,
            flashCategory: nil,
            serverURL: URL(string: "https://two.example")!
        )
        XCTAssertNil(otherServer)
    }

    func testFeedDiskCacheDeletesExpiredSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FeedDiskCache(directory: directory, maximumAge: 60)
        let post = try JSONDecoder().decode(Post.self, from: Data(#"{"id":1,"source":"x"}"#.utf8))
        await cache.save(
            FeedDiskSnapshot(
                schemaVersion: 1,
                savedAt: Date().addingTimeInterval(-61),
                source: FeedSource.x.rawValue,
                flashCategory: nil,
                posts: [post],
                page: 1,
                canLoadMore: true
            ),
            serverURL: URL(string: "https://expired.example")!
        )

        let restored = await cache.load(
            source: .x,
            flashCategory: nil,
            serverURL: URL(string: "https://expired.example")!
        )
        XCTAssertNil(restored)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: directory.path).count), 0)
    }

    @MainActor
    func testInitialNetworkFailureKeepsOfflineSnapshotVisible() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FeedDiskCache(directory: directory)
        let post = try JSONDecoder().decode(Post.self, from: Data(#"{"id":42,"source":"x","title":"离线内容"}"#.utf8))
        await cache.save(
            FeedDiskSnapshot(
                schemaVersion: 1,
                savedAt: Date(),
                source: FeedSource.x.rawValue,
                flashCategory: nil,
                posts: [post],
                page: 1,
                canLoadMore: true
            ),
            serverURL: ServerConfiguration.currentURL
        )
        let model = NewsFeedViewModel(
            source: .x,
            fetchPosts: { _, _, _ in throw URLError(.notConnectedToInternet) },
            diskCache: cache
        )

        await model.loadInitial()

        XCTAssertEqual(model.posts.map(\.id), [42])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isSwitchingSource)
    }

    func testFeedSourceTransitionAnimatesOnlyAdjacentTabs() {
        let sources = FeedSource.allCases
        XCTAssertGreaterThanOrEqual(sources.count, 3)
        XCTAssertTrue(FeedSourceTransitionPolicy.animatesTap(from: sources[0], to: sources[1]))
        XCTAssertTrue(FeedSourceTransitionPolicy.animatesTap(from: sources[1], to: sources[0]))
        XCTAssertFalse(FeedSourceTransitionPolicy.animatesTap(from: sources[0], to: sources[2]))
        XCTAssertFalse(FeedSourceTransitionPolicy.animatesTap(from: sources[0], to: sources[0]))
    }

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
            fetchRSSFeedPosts: { _, _, _ in feedPosts },
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

    @MainActor
    func testSelectedRSSFeedLoadsMoreAndDeduplicates() async throws {
        var requests: [(feedID: Int, page: Int, limit: Int)] = []
        let first = try JSONDecoder().decode(Post.self, from: Data(#"{"id":1,"source":"rss:88"}"#.utf8))
        let duplicate = try JSONDecoder().decode(Post.self, from: Data(#"{"id":1,"source":"rss:88"}"#.utf8))
        let second = try JSONDecoder().decode(Post.self, from: Data(#"{"id":2,"source":"rss:88"}"#.utf8))
        let model = NewsFeedViewModel(
            source: .rss,
            fetchRSSFeedPosts: { feedID, page, limit in
                requests.append((feedID, page, limit))
                return page == 1 ? [first] : [duplicate, second]
            }
        )

        await model.selectRSSFeed(88)
        await model.loadMoreSelectedRSSIfNeeded(current: first)

        XCTAssertEqual(requests.map(\.feedID), [88, 88])
        XCTAssertEqual(requests.map(\.page), [1, 2])
        XCTAssertEqual(requests.map(\.limit), [20, 20])
        XCTAssertEqual(model.selectedRSSPosts.map(\.id), [1, 2])
    }

    @MainActor
    func testRSSPaginationKeepsRawRowsSoFilteredPagesCanContinue() async throws {
        let dedicated = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":1,"source":"rss:47"}"#.utf8)
        )
        let visible = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":2,"source":"rss"}"#.utf8)
        )
        let model = NewsFeedViewModel(source: .rss) { page, _, _ in
            page == 1 ? [dedicated] : [visible]
        }

        await model.refresh()
        await model.loadMoreIfNeeded(current: dedicated)

        XCTAssertEqual(model.posts.map(\.id), [1, 2])
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

    func testWeChatRequestsAllScoresFromMaobidaoFeed() {
        let items = APIClient.regularPostQueryItems(page: 1, limit: 20, source: .wechat)
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(query["source"], "rss:57")
        XCTAssertEqual(query["include_zero_score"], "true")
        XCTAssertNil(query["final_score"])
    }

    func testWeChatAggregatesMaobidaoAndXiaohuAI() {
        XCTAssertEqual(APIClient.weChatFeedIDs, [57, 2373])
    }

    func testWeChatMergedPostsAreNewestFirstAndDeduplicated() throws {
        let decoder = JSONDecoder()
        let older = try decoder.decode(
            Post.self,
            from: Data(#"{"id":1,"source":"rss:57","article_post_at":"2026-08-01T10:00:00Z"}"#.utf8)
        )
        let newer = try decoder.decode(
            Post.self,
            from: Data(#"{"id":2,"source":"rss:2373","article_post_at":"2026-08-03T14:08:00Z"}"#.utf8)
        )

        let result = APIClient.mergeWeChatPosts([older, newer, older])

        XCTAssertEqual(result.map(\.id), [2, 1])
    }

    func testMaobidaoIsExcludedFromGenericRSSBecauseItHasDedicatedWeChatTab() throws {
        let post = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":57,"source":"rss:57","title":"猫笔刀"}"#.utf8)
        )

        XCTAssertTrue(post.hasDedicatedFeedTab)
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

    func testWeiboCommentsRequestUsesDedicatedEndpointContract() throws {
        let postURL = try XCTUnwrap(URL(string: "https://weibo.com/2397417584/RcLu9FEvg"))
        let items = APIClient.weiboCommentsQueryItems(postURL: postURL, limit: 20)
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(query["url"], postURL.absoluteString)
        XCTAssertEqual(query["limit"], "20")
        XCTAssertEqual(query["reply_limit"], "3")
    }

    func testWeiboFollowingImagesExcludeSinaPlaceholderArtwork() throws {
        let post = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":17,"source":"rss:17","images":[{"url":"https://h5.sinaimg.cn/upload/2015/09/25/3/timeline_card_small_video_default.png"},{"url":"https://h5.sinaimg.cn/upload/2015/09/25/3/timeline_card_small_web_default.png"},{"url":"https://tvax1.sinaimg.cn/mw2000/real-photo.jpg"}]}"#.utf8)
        )

        XCTAssertEqual(post.weiboFollowingImageURLs.count, 1)
        let retained = try XCTUnwrap(post.weiboFollowingImageURLs.first)
        let originalURL = URLComponents(url: retained, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "url" })?
            .value
        XCTAssertEqual(originalURL, "https://tvax1.sinaimg.cn/mw2000/real-photo.jpg")
    }

    func testWeiboFollowingImagesKeepMatchingFilenameFromUnrelatedHost() throws {
        let post = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":18,"source":"rss:18","images":[{"url":"https://example.com/timeline_card_small_video_default.png"}]}"#.utf8)
        )

        XCTAssertEqual(post.weiboFollowingImageURLs.count, 1)
    }

    func testWeiboVideoDetailRemovesCoverWithoutDimensions() throws {
        let post = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":18,"source":"rss:18","post_link":"https://weibo.com/123/abc","images":[{"url":"https://tvax4.sinaimg.cn/mw2000/video-cover.jpg"}],"videos":[{"url":"https://f.video.weibocdn.com/video.mp4"}]}"#.utf8)
        )

        XCTAssertEqual(post.weiboFollowingImageURLs.count, 1)
        XCTAssertTrue(post.weiboDetailImageURLs.isEmpty)
    }

    func testWeiboVideoDetailKeepsSizedGalleryImages() throws {
        let post = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":19,"source":"rss:19","post_link":"https://weibo.com/123/abc","images":[{"url":"https://tvax1.sinaimg.cn/mw2000/photo.jpg","width":1200,"height":800},{"url":"https://tvax4.sinaimg.cn/mw2000/video-cover.jpg"}],"videos":[{"url":"https://f.video.weibocdn.com/video.mp4"}]}"#.utf8)
        )

        let retained = try XCTUnwrap(post.weiboDetailImageURLs.first)
        XCTAssertEqual(post.weiboDetailImageURLs.count, 1)
        XCTAssertEqual(
            URLComponents(url: retained, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "url" })?
                .value,
            "https://tvax1.sinaimg.cn/mw2000/photo.jpg"
        )
    }

    func testWeiboDetailUsesSourceImageAspectRatio() throws {
        let post = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":19,"source":"rss:19","post_link":"https://weibo.com/123/abc","images":[{"url":"https://example.com/photo.jpg","width":1200,"height":800}]}"#.utf8)
        )

        let url = try XCTUnwrap(post.weiboFollowingImageURLs.first)
        XCTAssertEqual(post.weiboImageAspectRatio(for: url), 1.5)
    }

    func testWeiboRSSDetailRecognitionAndImportedMarkerCleanup() throws {
        let post = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":20,"source":"rss:20","post_link":"https://weibo.com/123/abc","content":"今天  真开心[裂开][图片]\n\n\n继续分享"}"#.utf8)
        )

        XCTAssertTrue(post.isWeiboRSS)
        XCTAssertEqual(post.weiboDetailContent, "今天 真开心😵‍💫\n\n继续分享")
    }

    func testWeiboRSSDetailPreservesAndResolvesInlineEmoji() throws {
        let post = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":20,"source":"rss:20","post_link":"https://weibo.com/123/abc","content":"今天<img class='emoji' src='https://h5.sinaimg.cn/face/emoji_wabi.png' alt='[挖鼻]'>继续"}"#.utf8)
        )

        XCTAssertEqual(post.weiboDetailContent, "今天[挖鼻]继续")
        let emoji = try XCTUnwrap(post.weiboInlineEmojis.first)
        XCTAssertEqual(post.weiboInlineEmojis.count, 1)
        XCTAssertEqual(emoji.token, "[挖鼻]")
        XCTAssertEqual(
            URLComponents(url: emoji.url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "url" })?
                .value,
            "https://h5.sinaimg.cn/face/emoji_wabi.png"
        )
    }

    func testWeiboRSSDetailFallsBackToUnicodeForEmojiWithoutImageURL() throws {
        let post = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":21,"source":"rss:21","post_link":"https://weibo.com/123/abc","content":"专业意见。[挖鼻] 感谢[心][鲜花]"}"#.utf8)
        )

        XCTAssertEqual(post.weiboDetailContent, "专业意见。😏 感谢❤️🌹")
        XCTAssertTrue(post.weiboInlineEmojis.isEmpty)
    }

    func testWeiboRSSRecognizesEmbeddedVideoButUnrelatedRSSDoesNot() throws {
        let weibo = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":22,"source":"rss:22","post_link":"https://weibo.com/123/abc","content":"<video src='https://video.weibo.com/example'></video>"}"#.utf8)
        )
        let unrelated = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":23,"source":"rss:23","post_link":"https://example.com/article","content":"<video src='clip.mp4'></video>"}"#.utf8)
        )

        XCTAssertTrue(weibo.hasWeiboVideoReference)
        XCTAssertFalse(unrelated.isWeiboRSS)
        XCTAssertFalse(unrelated.hasWeiboVideoReference)
    }

    func testWeiboFollowingListPrefersCompleteSummaryOverTruncatedHTMLContent() throws {
        let post = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":22,"source":"rss:78","content":"【<a href=\"https://weibo.com\"><span>#中方...","title":"【#中方已救起47名越南船员#】越方感谢中方救援，搜救工作仍在进行中。"}"#.utf8)
        )

        XCTAssertEqual(
            post.weiboFollowingListContent,
            "【#中方已救起47名越南船员#】越方感谢中方救援，搜救工作仍在进行中。"
        )
    }

    func testPlaybackStreamPathUsesAPIPrefix() throws {
        let url = try XCTUnwrap(APIClient.playbackURL(
            from: "/post/video-playback/stream?formatId=18",
            baseURL: URL(string: "http://example.com:3001")!
        ))
        XCTAssertEqual(url.absoluteString, "http://example.com:3001/api/ios/v1/post/video-playback/stream?formatId=18")
    }

    func testVideoThumbnailUsesOriginalMediaURL() throws {
        let baseURL = ServerConfiguration.defaultURL
        let original = "https://video.twimg.com/ext_tw_video/1/pu/vid/avc1/720x720/example.mp4?tag=12"
        let proxied = try XCTUnwrap(MediaURL.video(original))
        let thumbnail = try XCTUnwrap(MediaURL.videoThumbnail(for: proxied))
        let components = try XCTUnwrap(URLComponents(url: thumbnail, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.path, "/api/ios/v1/video-thumbnail")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "url" })?.value, original)
        XCTAssertEqual(thumbnail.host, baseURL.host)
    }

    func testVideoThumbnailSupportsSeekPosition() throws {
        let original = try XCTUnwrap(URL(string: "https://video.twimg.com/amplify_video/example.mp4?tag=29"))
        let thumbnail = try XCTUnwrap(MediaURL.videoThumbnail(for: original, at: 1))
        let components = try XCTUnwrap(URLComponents(url: thumbnail, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "url" })?.value, original.absoluteString)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "at" })?.value, "1")
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
    func testFlashCategorySelectionIsSentToDedicatedLoader() async {
        var categories: [String?] = []
        let model = NewsFeedViewModel(
            source: .flash,
            fetchPosts: { _, _, _ in [] },
            fetchFlashPosts: { _, _, category in
                categories.append(category)
                return []
            }
        )

        await model.refresh()
        await model.selectFlashCategory("company")

        XCTAssertEqual(categories.count, 2)
        XCTAssertNil(categories[0])
        XCTAssertEqual(categories[1], "company")
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
    func testCacheWarmingOnlyPreloadsAdjacentSources() async {
        var requestedSources: [FeedSource] = []
        let model = NewsFeedViewModel(source: .x) { _, _, source in
            requestedSources.append(source)
            return []
        }

        await model.warmSourceCache()
        model.select(.weibo)

        XCTAssertFalse(model.isSwitchingSource)
        XCTAssertEqual(Set(requestedSources), Set([.wechat, .weibo]))
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
    func testConcurrentInitialLoadsReuseTheActiveRequest() async {
        var requestCount = 0
        let firstRequestStarted = expectation(description: "first request started")
        let model = NewsFeedViewModel(source: .flash) { _, _, _ in
            requestCount += 1
            firstRequestStarted.fulfill()
            try await Task.sleep(for: .milliseconds(100))
            return []
        }

        let backgroundLoad = Task { await model.loadInitial() }
        await fulfillment(of: [firstRequestStarted], timeout: 1)
        await model.loadInitial()
        await backgroundLoad.value

        XCTAssertEqual(requestCount, 1)
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

    func testDecodesAndMapsBaiduHotTopic() throws {
        let json = #"{"success":true,"data":{"topics":[{"id":19,"keyword":"百度测试热搜","latest_rank":1,"latest_heat":7654321,"meta":{"last_payload":{"heat":7654321}},"search_link":"https://www.baidu.com/s?wd=test"}]}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(HotTopicsResponse.self, from: json)
        let post = Post.hotTopic(try XCTUnwrap(response.data.topics.first), source: .baidu)

        XCTAssertEqual(post.displayTitle, "百度测试热搜")
        XCTAssertEqual(post.feedRank, 1)
        XCTAssertEqual(post.formattedTime, "第 1 名 · 热度 7654321")
        XCTAssertEqual(post.source, "baidu")
        XCTAssertTrue(post.isSynthetic)
    }

    func testHotTopicEmbeddedPageBrandingMatchesSource() {
        XCTAssertEqual(FeedSource.weibo.hotTopicPageTitle, "微博热搜")
        XCTAssertEqual(FeedSource.weibo.hotTopicMarkAssetName, "WeiboMark")
        XCTAssertEqual(FeedSource.douyin.hotTopicPageTitle, "抖音热榜")
        XCTAssertEqual(FeedSource.douyin.hotTopicMarkAssetName, "TikTokMark")
        XCTAssertEqual(FeedSource.baidu.hotTopicPageTitle, "百度热搜")
        XCTAssertEqual(FeedSource.baidu.hotTopicMarkAssetName, "BaiduMark")
    }

    func testHotTopicDisplayRepairsDuplicateRanksAndTieOrdering() throws {
        let json = #"{"success":true,"data":{"topics":[{"id":1,"keyword":"低热度插入项","latest_rank":6,"meta":{"last_payload":{"heat":"543815"}}},{"id":2,"keyword":"高热度正常项","latest_rank":6,"meta":{"last_payload":{"heat":"545903"}}},{"id":3,"keyword":"下一项","latest_rank":7,"meta":{"last_payload":{"heat":"540000"}}}]}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(HotTopicsResponse.self, from: json)

        let posts = APIClient.hotTopicPostsForDisplay(
            response.data.topics,
            page: 1,
            limit: 20,
            source: .weibo
        )

        XCTAssertEqual(posts.map(\.displayTitle), ["高热度正常项", "低热度插入项", "下一项"])
        XCTAssertEqual(posts.map(\.feedRank), [1, 2, 3])
        XCTAssertEqual(posts.map(\.formattedTime), [
            "第 1 名 · 热度 545903",
            "第 2 名 · 热度 543815",
            "第 3 名 · 热度 540000"
        ])
    }

    func testHotTopicDisplayContinuesRankAcrossPages() throws {
        let json = #"{"success":true,"data":{"topics":[{"id":21,"keyword":"第二页第一项","latest_rank":20,"latest_heat":12345}]}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(HotTopicsResponse.self, from: json)

        let posts = APIClient.hotTopicPostsForDisplay(
            response.data.topics,
            page: 2,
            limit: 20,
            source: .weibo
        )

        XCTAssertEqual(posts.first?.feedRank, 21)
        XCTAssertEqual(posts.first?.formattedTime, "第 21 名 · 热度 12345")
    }

    func testHiddenFeedChromeRemovesHeaderReservation() {
        XCTAssertEqual(FeedChromeLayout.headerReservationHeight(isHidden: false), 0)
        XCTAssertEqual(FeedChromeLayout.headerReservationHeight(isHidden: true), 0)
    }

    func testSourceSelectorClearsMeasuredRootBottomChrome() {
        XCTAssertEqual(
            FeedChromeLayout.sourceSelectorBottomPadding(rootBottomChromeHeight: 82),
            94
        )
        XCTAssertEqual(
            FeedChromeLayout.sourceSelectorBottomPadding(rootBottomChromeHeight: 0),
            12
        )
        XCTAssertEqual(
            FeedChromeLayout.sourceSelectorBottomPadding(rootBottomChromeHeight: -10),
            12
        )
    }

    func testXueqiuDetailKeepsRootChromeVisible() {
        XCTAssertFalse(FeedDetailChromePolicy.hidesRootChrome(isPresented: true, isXueqiu: true))
        XCTAssertTrue(FeedDetailChromePolicy.hidesRootChrome(isPresented: true, isXueqiu: false))
        XCTAssertFalse(FeedDetailChromePolicy.hidesRootChrome(isPresented: false, isXueqiu: false))
    }

    func testFilteredPaginationTaskAdvancesWithRawTail() {
        XCTAssertEqual(
            FeedPaginationLayout.taskPostID(
                visibleTailID: 3,
                rawTailID: 10,
                usesFilteredPagination: true
            ),
            10
        )
        XCTAssertEqual(
            FeedPaginationLayout.taskPostID(
                visibleTailID: 3,
                rawTailID: 10,
                usesFilteredPagination: false
            ),
            3
        )
    }

    @MainActor
    func testWeChatAggregateRequestsTwentyPosts() async {
        var requestedLimit = 0
        let model = NewsFeedViewModel(source: .wechat) { _, limit, _ in
            requestedLimit = limit
            return []
        }

        await model.refresh()

        XCTAssertEqual(requestedLimit, 20)
    }

    @MainActor
    func testForcedRSSFeedRefreshReplacesCachedAvatarMetadata() async throws {
        var requestCount = 0
        let first = try JSONDecoder().decode(
            RSSFeedSource.self,
            from: Data(#"{"id":2373,"name":"小互AI","avatar_url":"https://example.com/old.jpg","is_enabled":true}"#.utf8)
        )
        let refreshed = try JSONDecoder().decode(
            RSSFeedSource.self,
            from: Data(#"{"id":2373,"name":"小互AI","avatar_url":"https://wx.qlogo.cn/avatar.jpg","is_enabled":true}"#.utf8)
        )
        let model = NewsFeedViewModel(source: .wechat, fetchRSSFeeds: {
            requestCount += 1
            return requestCount == 1 ? [first] : [refreshed]
        })

        await model.loadRSSFeedsIfNeeded()
        await model.loadRSSFeedsIfNeeded(forceRefresh: true)

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(model.rssFeeds.first?.avatar, "https://wx.qlogo.cn/avatar.jpg")
    }

    @MainActor
    func testWeChatAccountSelectionUsesServerFeedEndpointWithoutClientFiltering() async throws {
        var requests: [(feedID: Int, page: Int, limit: Int)] = []
        let first = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":1,"source":"rss:2373"}"#.utf8)
        )
        let second = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":2,"source":"rss:2373"}"#.utf8)
        )
        let model = NewsFeedViewModel(
            source: .wechat,
            fetchWeChatFeedPosts: { feedID, page, limit in
                requests.append((feedID, page, limit))
                return page == 1 ? [first] : [second]
            }
        )

        await model.selectWeChatFeed(2373)
        await model.loadMoreSelectedWeChatIfNeeded(current: first)

        XCTAssertEqual(requests.map(\.feedID), [2373, 2373])
        XCTAssertEqual(requests.map(\.page), [1, 2])
        XCTAssertEqual(requests.map(\.limit), [20, 20])
        XCTAssertEqual(model.selectedWeChatPosts.map(\.id), [1, 2])
    }

    func testDecodesAndMapsFlashItem() throws {
        let json = #"{"success":true,"data":{"items":[{"id":"f1","time":"18:00","text":"快讯正文","source":"flash:jin10","category":"company","isImportant":false,"finalScore":7.4}],"hasMore":false}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(FlashResponse.self, from: json)
        let post = Post.flash(try XCTUnwrap(response.data.items.first))

        XCTAssertEqual(post.displayContent, "快讯正文")
        XCTAssertEqual(post.authorName, "金十数据")
        XCTAssertEqual(post.score, 7.4)
        XCTAssertEqual(post.tagNames, [])
        XCTAssertEqual(post.meta?.flashCategory, "company")
    }

    func testFlashCategoryQueryUsesServerFilter() {
        let items = APIClient.flashQueryItems(page: 2, limit: 20, category: "tech", importantOnly: false)
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(query["offset"], "20")
        XCTAssertEqual(query["category"], "tech")
        XCTAssertNil(query["important_only"])
    }

    func testDefaultImportantFlashQueryUsesServerFilter() {
        let items = APIClient.flashQueryItems(page: 1, limit: 20, category: nil, importantOnly: true)
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(query["offset"], "0")
        XCTAssertEqual(query["important_only"], "1")
        XCTAssertNil(query["category"])
    }

    func testFlashUsesExplicitServerImportantFlagBeforeScore() throws {
        let json = #"{"success":true,"data":{"items":[{"id":"f2","time":"18:01","text":"普通快讯","source":"flash:sina","isImportant":true,"finalScore":6.9}],"hasMore":false}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(FlashResponse.self, from: json)
        let post = Post.flash(try XCTUnwrap(response.data.items.first))

        XCTAssertEqual(post.score, 6.9)
        XCTAssertEqual(post.tagNames, ["重要"])
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

    @MainActor
    func testFilteredFlashChannelRejectsRealtimeItemsWithoutMatchingServerCategory() async throws {
        let company = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":101,"source":"flash","content":"公司快讯","meta":{"flashCategory":"company"}}"#.utf8)
        )
        let tech = try JSONDecoder().decode(
            Post.self,
            from: Data(#"{"id":102,"source":"flash","content":"科技快讯","meta":{"flashCategory":"tech"}}"#.utf8)
        )
        let model = NewsFeedViewModel(source: .flash) { _, _, _ in [] }

        await model.selectFlashCategory("company")

        XCTAssertTrue(model.matchesCurrentSource(company))
        XCTAssertFalse(model.matchesCurrentSource(tech))
    }

    func testXImageUsesServerProxy() throws {
        let url = try XCTUnwrap(MediaURL.image("https://pbs.twimg.com/media/demo.jpg"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertTrue(url.path.hasSuffix("/api/ios/v1/image-proxy"))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "url" })?.value, "https://pbs.twimg.com/media/demo.jpg")
    }

    func testOrdinaryImageUsesServerProxy() throws {
        let url = try XCTUnwrap(MediaURL.image("https://example.com/image.jpg"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertTrue(url.path.hasSuffix("/api/ios/v1/image-proxy"))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "url" })?.value, "https://example.com/image.jpg")
    }

    func testNewYorkTimesImageUsesServerProxy() throws {
        let url = try XCTUnwrap(MediaURL.image("https://static01.nyt.com/images/example.jpg"))
        XCTAssertTrue(url.path.hasSuffix("/api/ios/v1/image-proxy"))
    }

    func testWeChatRSSImageUnwrapsBlockedProxyAndUsesServerProxy() throws {
        let raw = "https://wechat2rss.xlab.app/img-proxy/?k=1&u=https%3A%2F%2Fmmbiz.qpic.cn%2Fsz_mmbiz_jpg%2Fdemo%2F0%3Fwx_fmt%3Djpeg"
        let url = try XCTUnwrap(MediaURL.image(raw))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertTrue(url.path.hasSuffix("/api/ios/v1/image-proxy"))
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "url" })?.value,
            "https://mmbiz.qpic.cn/sz_mmbiz_jpg/demo/0?wx_fmt=jpeg"
        )
    }

    func testXueqiuMediaGridRejectsMalformedRelativeImageSource() throws {
        let data = #"{"id":2806844,"source":"rss:16","meta":{"rss_feed_name":"雪球-但斌"}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: data)
        let malformedRelativeURL = ServerConfiguration.currentURL.appending(path: "title=")
        var proxyComponents = URLComponents(
            url: ServerConfiguration.currentURL.appending(path: "api/ios/v1/image-proxy"),
            resolvingAgainstBaseURL: false
        )
        proxyComponents?.queryItems = [
            .init(name: "url", value: "https://xqimg.imedao.com/example.jpg")
        ]
        let proxyURL = try XCTUnwrap(proxyComponents?.url)
        let directURL = try XCTUnwrap(URL(string: "https://xqimg.imedao.com/example.jpg"))

        XCTAssertFalse(
            XueqiuMediaDisplayPolicy.shouldDisplay(
                malformedRelativeURL,
                post: post,
                usesExplicitPlacement: true
            )
        )
        XCTAssertTrue(XueqiuMediaDisplayPolicy.shouldDisplay(proxyURL, post: post, usesExplicitPlacement: true))
        XCTAssertTrue(XueqiuMediaDisplayPolicy.shouldDisplay(directURL, post: post, usesExplicitPlacement: true))
    }

    func testWeChatArticlePreservesTextAndInlineImageOrder() throws {
        let html = """
        <p>第一段正文。</p>
        <p><img src="https://wechat2rss.xlab.app/img-proxy/?k=1&amp;u=https%3A%2F%2Fmmbiz.qpic.cn%2Fdemo.jpg"></p>
        <p>第二段正文。</p>
        """
        let payload = try JSONSerialization.data(withJSONObject: [
            "id": 57,
            "source": "rss:57",
            "content": html
        ])
        let post = try JSONDecoder().decode(Post.self, from: payload)

        XCTAssertEqual(post.rssArticleBlocks.count, 3)
        XCTAssertEqual(post.rssArticleBlocks[0], .paragraph(text: "第一段正文。", emojis: []))
        guard case .image(let url) = post.rssArticleBlocks[1] else {
            return XCTFail("Expected inline image")
        }
        XCTAssertTrue(url.path.hasSuffix("/api/ios/v1/image-proxy"))
        XCTAssertEqual(post.rssArticleBlocks[2], .paragraph(text: "第二段正文。", emojis: []))
    }

    func testWeChatArticleKeepsEmojiAtInlineSizeInsteadOfArticleImageSize() throws {
        let html = """
        <p>正文</p><img class="rich_pages wxw-img" data-ratio="1" data-w="20" style="display:inline-block;width:20px;vertical-align:middle" src="https://wechat2rss.xlab.app/img-proxy/?k=1&amp;u=https%3A%2F%2Fres.wx.qq.com%2Ft%2Fwx_fed%2Fwe-emoji%2Fres%2Fassets%2FExpression%2FExpression_94%402x.png"/>
        """
        let payload = try JSONSerialization.data(withJSONObject: [
            "id": 58,
            "source": "rss:57",
            "content": html
        ])
        let post = try JSONDecoder().decode(Post.self, from: payload)

        XCTAssertEqual(post.rssArticleBlocks.count, 1)
        guard case .paragraph(let text, let emojis) = post.rssArticleBlocks[0] else {
            return XCTFail("Expected WeChat emoji to stay inside its paragraph")
        }
        XCTAssertEqual(text, "正文[表情]")
        XCTAssertEqual(emojis.count, 1)
        XCTAssertNotNil(try XCTUnwrap(emojis.first).url.host())
    }

    func testGenericRSSKeepsWordPressAndDiscourseEmojiInline() throws {
        let html = """
        <p>机器人<img src="https://s.w.org/images/core/emoji/17.0.2/72x72/1f916.png" alt="🤖" class="wp-smiley" style="height: 1em; max-height: 1em;" />继续正文</p>
        <p><img src="https://cdn.ldstatic.com/images/emoji/twemoji/cold_face.png" title=":cold_face:" class="emoji" alt=":cold_face:" width="20" height="20">结束</p>
        """
        let payload = try JSONSerialization.data(withJSONObject: [
            "id": 72,
            "source": "rss:72",
            "content": html
        ])
        let post = try JSONDecoder().decode(Post.self, from: payload)

        XCTAssertEqual(post.rssArticleBlocks.count, 2)
        guard case .paragraph(let firstText, let firstEmojis) = post.rssArticleBlocks[0],
              case .paragraph(let secondText, let secondEmojis) = post.rssArticleBlocks[1] else {
            return XCTFail("Expected emoji paragraphs")
        }
        XCTAssertEqual(firstText, "机器人🤖继续正文")
        XCTAssertEqual(firstEmojis.map(\.token), ["🤖"])
        XCTAssertEqual(secondText, ":cold_face:结束")
        XCTAssertEqual(secondEmojis.map(\.token), [":cold_face:"])
        XCTAssertEqual(post.rssListContent, "机器人🤖继续正文\n:cold_face:结束")
    }

    func testGenericRSSDropsTrackingAndDecorativeImages() throws {
        let html = """
        <p>正文</p>
        <img src="https://1px.example/track" width="1" height="1" aria-hidden="true" />
        <img src="https://icons.duckduckgo.com/ip3/example.com.ico" width="24" height="24" alt="favicon" />
        <p>结尾</p>
        """
        let payload = try JSONSerialization.data(withJSONObject: [
            "id": 73,
            "source": "rss:73",
            "content": html
        ])
        let post = try JSONDecoder().decode(Post.self, from: payload)

        XCTAssertEqual(
            post.rssArticleBlocks,
            [
                .paragraph(text: "正文", emojis: []),
                .paragraph(text: "结尾", emojis: [])
            ]
        )
        XCTAssertEqual(post.rssListContent, "正文\n结尾")
    }

    func testNewYorkTimesArticleUsesServerPreviewEndpoint() throws {
        let article = try XCTUnwrap(URL(string: "https://www.nytimes.com/2026/07/19/example.html"))
        let base = try XCTUnwrap(URL(string: "https://api.wanghengai.xin"))
        let url = try XCTUnwrap(APIClient.articlePreviewURL(for: article, baseURL: base))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.path, "/api/ios/v1/post/preview")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "url" })?.value, article.absoluteString)
        XCTAssertNil(components.queryItems?.first(where: { $0.name == "prefer_remote" }))
    }

    func testNewYorkTimesHeroVariantsAreRecognizedAsTheSameImage() throws {
        let hero = try XCTUnwrap(URL(string: "https://api.example/api/ios/v1/image-proxy?url=https%3A%2F%2Fstatic01.nyt.com%2Fimages%2F2026%2F07%2F01%2Fhero%2Fhero-articleLarge.jpg"))
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

    func testImageDiskCachePersistsAcrossLoaderInstances() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageDiskCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try XCTUnwrap(URL(string: "https://images.example.com/persisted.jpg"))
        let expected = Data("persisted-image-data".utf8)

        let firstCache = ImageDiskCache(directory: directory, maxBytes: 1_024, maxFileCount: 10)
        await firstCache.store(expected, for: url)
        let secondCache = ImageDiskCache(directory: directory, maxBytes: 1_024, maxFileCount: 10)
        let loaded = await secondCache.data(for: url)

        XCTAssertEqual(loaded, expected)
    }

    func testImageDiskCacheEvictsLeastRecentlyUsedFiles() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageDiskCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ImageDiskCache(directory: directory, maxBytes: 1_024, maxFileCount: 2)
        let urls = try (1...3).map {
            try XCTUnwrap(URL(string: "https://images.example.com/\($0).jpg"))
        }

        for url in urls {
            await cache.store(Data(url.absoluteString.utf8), for: url)
            try await Task.sleep(for: .milliseconds(20))
        }
        await cache.trim()

        let oldest = await cache.data(for: urls[0])
        let middle = await cache.data(for: urls[1])
        let newest = await cache.data(for: urls[2])
        XCTAssertNil(oldest)
        XCTAssertNotNil(middle)
        XCTAssertNotNil(newest)
    }
}
