import XCTest
@testable import AIServerClient

final class PostDecodingTests: XCTestCase {
    func testPeopleSearchRequestRetriggersAndRoutesSourcesReliably() {
        let hidden = PeopleSearchRequest(
            isPresented: false,
            source: .all,
            query: " 爱因斯坦 "
        )
        XCTAssertEqual(hidden.query, "爱因斯坦")
        XCTAssertFalse(hidden.searchesX)
        XCTAssertFalse(hidden.searchesWikipedia)

        let allSources = PeopleSearchRequest(
            isPresented: true,
            source: .all,
            query: "爱因斯坦"
        )
        XCTAssertTrue(allSources.searchesX)
        XCTAssertTrue(allSources.searchesWikipedia)

        let wikipediaOnly = PeopleSearchRequest(
            isPresented: true,
            source: .wikipedia,
            query: "爱因斯坦"
        )
        XCTAssertFalse(wikipediaOnly.searchesX)
        XCTAssertTrue(wikipediaOnly.searchesWikipedia)

        let submittedAgain = PeopleSearchRequest(
            isPresented: true,
            source: .wikipedia,
            query: "爱因斯坦",
            revision: 1
        )
        XCTAssertNotEqual(wikipediaOnly, submittedAgain)
    }

    func testWikipediaReaderStyleHidesChromeAndKeepsArticleContentStyled() {
        let script = WikipediaReaderStyle.script

        XCTAssertTrue(script.contains("wikipedia\\.org"))
        XCTAssertTrue(script.contains(".mw-header"))
        XCTAssertTrue(script.contains(".vector-page-toolbar"))
        XCTAssertTrue(script.contains("#p-lang-btn"))
        XCTAssertTrue(script.contains(".mw-editsection"))
        XCTAssertTrue(script.contains(".vector-toc"))
        XCTAssertTrue(script.contains(".mw-footer-container"))
        XCTAssertTrue(script.contains("#firstHeading"))
        XCTAssertTrue(script.contains(".mw-parser-output"))
        XCTAssertTrue(script.contains("来自维基百科，自由的百科全书"))
        XCTAssertTrue(script.contains("font-size: 18px"))
        XCTAssertTrue(script.contains("--aiserver-paper: #fbf7ed"))
        XCTAssertTrue(script.contains("__aiserverToggleTOC"))
        XCTAssertTrue(script.contains("本文目录"))
        XCTAssertTrue(script.contains("aiserver-deck-root"))
        XCTAssertTrue(script.contains("scroll-snap-type: x mandatory"))
        XCTAssertTrue(script.contains("__aiserverDeckPrevious"))
        XCTAssertTrue(script.contains("__aiserverDeckNext"))
        XCTAssertTrue(script.contains("const validSlides = sourceSlides.filter"))
        XCTAssertTrue(script.contains("aria-hidden='true'"))
        XCTAssertTrue(script.contains("data:image\\/(?:svg\\+xml|gif)"))
        XCTAssertTrue(script.contains("__aiserverToggleOriginal"))
        XCTAssertTrue(script.contains("mw-heading2"))
        XCTAssertFalse(script.contains("关键资料"))
    }

    func testWikipediaLinksAreRecognizedForInReaderNavigation() throws {
        let destinationURL = try XCTUnwrap(URL(string: "https://zh.wikipedia.org/wiki/机器学习"))

        XCTAssertTrue(destinationURL.isWikipediaURL)
    }

    func testWikipediaSamePageAnchorRemainsInsideCurrentPresentation() throws {
        let currentURL = try XCTUnwrap(URL(string: "https://zh.wikipedia.org/wiki/人工智能"))
        let anchorURL = try XCTUnwrap(URL(string: "https://zh.wikipedia.org/wiki/人工智能#历史"))

        XCTAssertNil(
            WikipediaLinkPresentation.entity(for: anchorURL, currentURL: currentURL)
        )
    }

    func testExternalWikipediaReferenceAlsoOpensWithoutReplacingCurrentPage() throws {
        let currentURL = try XCTUnwrap(URL(string: "https://zh.wikipedia.org/wiki/人工智能"))
        let referenceURL = try XCTUnwrap(URL(string: "https://example.com/research/paper"))

        let entity = try XCTUnwrap(
            WikipediaLinkPresentation.entity(for: referenceURL, currentURL: currentURL)
        )

        XCTAssertEqual(entity.title, "paper")
        XCTAssertFalse(entity.url.isWikipediaURL)
    }

    func testPersonArticleDecoding() throws {
        let data = Data(
            """
            {
              "id": 9,
              "person_id": "1605",
              "source_name": "Sam Altman Blog",
              "source_url": "https://blog.samaltman.com",
              "title": "Reflections",
              "title_zh": "",
              "summary": "A retrospective.",
              "canonical_url": "https://blog.samaltman.com/reflections",
              "published_at": "2025-01-06T00:00:00Z",
              "reading_minutes": 8,
              "language": "en"
            }
            """.utf8
        )

        let article = try JSONDecoder().decode(PersonArticle.self, from: data)
        XCTAssertEqual(article.personID, "1605")
        XCTAssertEqual(article.displayTitle, "Reflections")
        XCTAssertEqual(article.readingMinutes, 8)
        XCTAssertEqual(article.canonicalURL?.host, "blog.samaltman.com")
    }

    func testPersonArticleSearchResponseConfirmsQueryWasApplied() throws {
        let data = Data(
            """
            {
              "success": true,
              "person_id": "1605",
              "query_applied": true,
              "articles": []
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(PeopleArticlesResponse.self, from: data)
        XCTAssertTrue(response.queryApplied == true)
        XCTAssertTrue(response.articles.isEmpty)
    }

    func testPersonArticleTranslationPreservesProductNames() {
        XCTAssertEqual(
            PersonArticleTranslationService.preserveProductNames(
                in: "姐姐 更新 #1 来自开放人工智能",
                original: "Sora update #1 from OpenAI"
            ),
            "Sora 更新 #1 来自OpenAI"
        )
    }

    func testPersonArticleTranslationSplitsLongContent() {
        let chunks = PersonArticleTranslationService.chunks(
            from: "First paragraph\nSecond paragraph",
            maximumCharacters: 18
        )
        XCTAssertEqual(chunks, ["First paragraph", "Second paragraph"])
    }

    func testDecodesPersonVideoChineseSubtitleTimeline() throws {
        let data = Data(
            """
            {
              "success": true,
              "video_id": 42,
              "language": "zh-Hans",
              "status": "ready",
              "cues": [
                {"start_ms": 1200, "end_ms": 3400, "text": "欢迎来到创业课堂"}
              ]
            }
            """.utf8
        )

        let payload = try JSONDecoder().decode(PersonVideoSubtitlesResponse.self, from: data)

        XCTAssertEqual(payload.videoID, 42)
        XCTAssertEqual(payload.status, "ready")
        XCTAssertEqual(payload.cues.first?.text, "欢迎来到创业课堂")
        XCTAssertEqual(payload.cues.first?.startMS, 1200)
    }

    func testDecodesRelatedPersonVideos() throws {
        let data = Data(
            """
            {
              "success": true,
              "person_id": "1605",
              "videos": [{
                "id": 1,
                "person_id": "1605",
                "platform": "youtube",
                "platform_video_id": "abc123",
                "title": "Sam Altman Interview",
                "title_zh": "山姆·奥特曼访谈",
                "channel_name": "TED",
                "published_at": "2026-07-26T12:00:00Z",
                "duration_seconds": 768,
                "cover_url": "https://i.ytimg.com/vi/abc123/hqdefault.jpg",
                "canonical_url": "https://www.youtube.com/watch?v=abc123",
                "relevance_score": 12,
                "video_type": "interview",
                "is_featured": true
              }]
            }
            """.utf8
        )

        let payload = try JSONDecoder().decode(PeopleVideosResponse.self, from: data)

        XCTAssertEqual(payload.personID, "1605")
        XCTAssertEqual(payload.videos.first?.channelName, "TED")
        XCTAssertEqual(payload.videos.first?.durationLabel, "12:48")
        XCTAssertEqual(payload.videos.first?.platformVideoID, "abc123")
        XCTAssertEqual(payload.videos.first?.displayTitle, "山姆·奥特曼访谈")
        XCTAssertEqual(payload.videos.first?.publishedDateLabel, "2026年7月26日")
    }

    func testDecodesServerManagedPeopleDirectory() throws {
        let data = Data(
            """
            {
              "success": true,
              "categories": [
                {"id": "technology", "title": "科技", "sort_order": 10},
                {"id": "investment", "title": "投资", "sort_order": 30}
              ],
              "users": [{
                "user_id": "curated:peter-thiel",
                "user_name": "Peter Thiel",
                "user_desc": "科技投资人",
                "x_screen_name": "peterthiel",
                "organization_name": "Founders Fund 联合创始人",
                "life_years": "1967–",
                "topic": "investment",
                "discussion_keywords": ["Peter Thiel", "彼得·蒂尔"],
                "focus_tags": ["投资", "创业"],
                "roles": [{"organization": "Founders Fund", "title": "联合创始人"}],
                "milestones": [{"year": "2005", "title": "创立 Founders Fund"}],
                "related_people": [{
                  "id": "curated:elon-musk",
                  "name": "Elon Musk",
                  "relationship": "合作伙伴",
                  "avatar_url": "https://example.com/elon.jpg"
                }],
                "social_accounts": [{
                  "platform": "微博",
                  "handle": "@peterthiel",
                  "profile_url": "https://weibo.com/peterthiel"
                }],
                "profile_updated_at": "2026年7月",
                "has_own_post_source": false,
                "today_count": 0,
                "total_count": 0,
                "last_post_time": null
              }]
            }
            """.utf8
        )

        let payload = try JSONDecoder().decode(SpecialPeopleResponse.self, from: data)

        XCTAssertEqual(payload.categories?.compactMap(\.topic), [.technology, .investment])
        XCTAssertEqual(payload.users.first?.topic, .investment)
        XCTAssertEqual(payload.users.first?.organizationName, "Founders Fund 联合创始人")
        XCTAssertEqual(payload.users.first?.lifeYears, "1967–")
        XCTAssertEqual(payload.users.first?.discussionKeywords, ["Peter Thiel", "彼得·蒂尔"])
        XCTAssertEqual(payload.users.first?.focusTags, ["投资", "创业"])
        XCTAssertEqual(payload.users.first?.roles.first?.organization, "Founders Fund")
        XCTAssertEqual(payload.users.first?.milestones.first?.year, "2005")
        XCTAssertEqual(payload.users.first?.relatedPeople.first?.name, "Elon Musk")
        XCTAssertEqual(payload.users.first?.socialAccounts.first?.platform, "微博")
        XCTAssertEqual(payload.users.first?.socialAccounts.first?.displayHandle, "@peterthiel")
        XCTAssertEqual(payload.users.first?.socialAccounts.count, 2)
        XCTAssertEqual(payload.users.first?.profileUpdatedAt, "2026年7月")
        XCTAssertEqual(payload.users.first?.hasOwnPostSource, false)
        XCTAssertEqual(payload.users.first?.xHandle, "@peterthiel")
        XCTAssertEqual(payload.users.first?.xProfileURL?.absoluteString, "https://x.com/peterthiel")
    }

    func testDecodesServerManagedIdeologyTopic() throws {
        let data = Data(
            """
            {
              "success": true,
              "categories": [
                {"id": "ideology", "title": "意识形态", "sort_order": 40}
              ],
              "users": [{
                "user_id": "curated:zhang-weiwei",
                "user_name": "张维为",
                "user_desc": "关注中国道路、中国模式与国际秩序。",
                "organization_name": "复旦大学中国研究院院长",
                "topic": "ideology",
                "discussion_keywords": ["张维为", "这就是中国"],
                "has_own_post_source": false,
                "today_count": 0,
                "total_count": 0,
                "last_post_time": null
              }]
            }
            """.utf8
        )

        let payload = try JSONDecoder().decode(SpecialPeopleResponse.self, from: data)

        XCTAssertEqual(payload.categories?.compactMap(\.topic), [.ideology])
        XCTAssertEqual(payload.users.first?.topic, .ideology)
        XCTAssertEqual(payload.users.first?.name, "张维为")
    }

    func testRelationshipPlannerBuildsServerDrivenLocalGraph() throws {
        let data = Data(
            """
            {
              "success": true,
              "users": [
                {
                  "user_id": "sam",
                  "user_name": "Sam",
                  "user_desc": "OpenAI CEO",
                  "organization_name": "OpenAI 联合创始人兼 CEO",
                  "topic": "technology",
                  "roles": [{"organization": "OpenAI", "title": "CEO"}],
                  "related_people": [{"id": "satya", "name": "Satya", "relationship": "战略合作伙伴"}],
                  "today_count": 2,
                  "total_count": 20
                },
                {
                  "user_id": "greg",
                  "user_name": "Greg",
                  "user_desc": "OpenAI President",
                  "organization_name": "OpenAI 联合创始人兼总裁",
                  "topic": "technology",
                  "roles": [{"organization": "OpenAI", "title": "总裁"}],
                  "today_count": 0,
                  "total_count": 10
                },
                {
                  "user_id": "satya",
                  "user_name": "Satya",
                  "user_desc": "Microsoft CEO",
                  "organization_name": "Microsoft 董事长兼 CEO",
                  "topic": "technology",
                  "roles": [{"organization": "Microsoft", "title": "CEO"}],
                  "today_count": 1,
                  "total_count": 15
                }
              ]
            }
            """.utf8
        )

        let people = try JSONDecoder().decode(SpecialPeopleResponse.self, from: data).users
        let lenses = PeopleRelationshipPlanner.lenses(for: people)
        let focused = PeopleRelationshipPlanner.visiblePeople(
            topicPeople: people,
            allPeople: people,
            focusedPersonID: "sam",
            organization: nil
        )
        let openAI = PeopleRelationshipPlanner.visiblePeople(
            topicPeople: people,
            allPeople: people,
            focusedPersonID: nil,
            organization: "OpenAI"
        )
        let clusters = PeopleRelationshipPlanner.clusters(
            around: people[0],
            allPeople: people
        )

        XCTAssertEqual(lenses.first, PeopleRelationshipLens(title: "OpenAI", memberCount: 2))
        XCTAssertEqual(focused.map(\.id), ["satya"])
        XCTAssertEqual(Set(openAI.map(\.id)), Set(["sam", "greg"]))
        XCTAssertEqual(clusters.first?.title, "合作")
        XCTAssertEqual(clusters.first?.members.map(\.id), ["satya"])
        XCTAssertEqual(
            PeopleRelationshipPlanner.relationshipLabel(from: people[0], to: people[2]),
            "战略合作伙伴"
        )
        XCTAssertEqual(
            PeopleRelationshipPlanner.relationshipLabel(from: people[0], to: people[1]),
            "暂无已核实关系"
        )
        XCTAssertTrue(
            PeopleRelationshipPlanner.clusters(around: people[1], allPeople: people).isEmpty
        )
    }

    func testElonMuskUsesBundledPortraitInsteadOfServerAvatar() {
        let person = SpecialPerson(
            id: "elon-musk",
            name: "Elon Musk",
            organization: "xAI",
            summary: "xAI 创始人",
            avatarURL: "https://example.com/wrong-image.jpg"
        )

        XCTAssertEqual(person.avatarAssetName, "ElonMuskAvatar")
    }

    func testDecodesXQuotedTweetForPersonPostCard() throws {
        let data = #"{"post":{"id":1,"source":"x","meta":{"quoted_tweet":{"id":"99","text":"Gemini who?","text_zh":"双子座是谁？","author":{"name":"Example","screenName":"example","profileImageUrl":"https://example.com/a.jpg"},"media":[{"type":"photo","url":"https://example.com/p.jpg","thumbnail_url":"https://example.com/t.jpg","width":1200,"height":800}]}}}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(PostDetailResponse.self, from: data).post

        XCTAssertEqual(post.meta?.quotedTweet?.author?.handle, "@example")
        XCTAssertEqual(post.meta?.quotedTweet?.displayText, "双子座是谁？")
        XCTAssertEqual(post.meta?.quotedTweet?.media?.first?.displayURL?.absoluteString, "https://example.com/t.jpg")
    }

    func testDecodesXReplyAndQuotedVideoContext() throws {
        let data = #"{"post":{"id":1,"source":"x","meta":{"in_reply_to_screen_name":"openai","in_reply_to_status_id":"42","reply_context":{"id":"42","author_name":"OpenAI","screen_name":"openai","avatar_url":"https://example.com/openai.jpg","text":"Parent post","text_zh":"被回复的动态"},"quoted_tweet":{"id":"99","text":"Demo","author":{"name":"Example","screenName":"example"},"media":[{"type":"video","url":"https://example.com/demo.mp4","thumbnail_url":"https://example.com/demo.jpg","width":1920,"height":1080}]}}}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(PostDetailResponse.self, from: data).post

        XCTAssertEqual(post.meta?.inReplyToScreenName, "openai")
        XCTAssertEqual(post.meta?.inReplyToStatusID, "42")
        XCTAssertEqual(post.meta?.replyContext?.displayText, "被回复的动态")
        XCTAssertEqual(post.meta?.replyContext?.handle, "@openai")
        let media = try XCTUnwrap(post.meta?.quotedTweet?.media?.first)
        XCTAssertTrue(media.isVideo)
        XCTAssertEqual(media.playbackURL?.absoluteString, "https://example.com/demo.mp4")
        XCTAssertEqual(media.previewURL?.absoluteString, "https://example.com/demo.jpg")
    }

    func testXDetailUsesStoredLongTextAndFormatsBullets() throws {
        let data = #"{"id":7,"source":"x","content":"short…","post_link":"https://x.com/example/status/123","meta":{"raw_text":"价格调整： *第一项 *第二项","note_text":"第一段\n\n价格调整： *第一项 *第二项"}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: data)

        XCTAssertEqual(post.xStoredOriginalContent, "第一段\n\n价格调整： *第一项 *第二项")
        XCTAssertEqual(
            XPostTextFormatter.detailText(post.xStoredOriginalContent),
            "第一段\n\n价格调整：\n• 第一项\n• 第二项"
        )
        XCTAssertFalse(XPostTextFormatter.isTruncated(post.xStoredOriginalContent))
        XCTAssertTrue(XPostTextFormatter.isTruncated("上游摘要…"))
    }

    func testDecodesLiveXTweetDetailResponse() throws {
        let data = #"{"success":true,"data":{"item":{"id":"123","text":"short…","shortText":"short…","noteText":"完整正文第一段\n\n第二段","createdAt":"Sat Aug 01 08:16:38 +0000 2026","metrics":{"bookmarks":9,"likes":15,"quotes":0,"replies":1,"retweets":2,"views":3740}}}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(XTweetDetailResponse.self, from: data)

        XCTAssertEqual(response.data.item.fullText, "完整正文第一段\n\n第二段")
        XCTAssertEqual(response.data.item.metrics?.views, 3740)
        XCTAssertEqual(response.data.item.metrics?.bookmarks, 9)
    }

    func testDecodesCompleteXCommentMetrics() throws {
        let data = #"{"success":true,"data":{"items":[{"id":"456","text":"@author 回复正文","author":{"name":"用户","screenName":"reader","profileImageUrl":null,"verified":true},"metrics":{"bookmarks":3,"likes":4,"quotes":0,"replies":1,"retweets":2,"views":118},"createdAt":"Sat Aug 01 08:56:28 +0000 2026","inReplyToScreenName":"author","lang":"zh"}],"nextCursor":null}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(XCommentsResponse.self, from: data)

        XCTAssertEqual(response.data.items.first?.metrics?.views, 118)
        XCTAssertEqual(response.data.items.first?.metrics?.bookmarks, 3)
    }

    func testDecodesLiveXTweetVideoForDetailFallback() throws {
        let data = #"{"success":true,"data":{"item":{"id":"2083612366155984927","text":"这是哪个国家？","media":[{"type":"video","url":"https://video.twimg.com/amplify_video/demo.mp4","thumbnail_url":"https://pbs.twimg.com/amplify_video_thumb/demo.jpg","width":720,"height":1280}]}}}"#.data(using: .utf8)!
        let item = try JSONDecoder().decode(XTweetDetailResponse.self, from: data).data.item

        XCTAssertTrue(item.videoMedia?.isVideo == true)
        XCTAssertEqual(item.videoMedia?.width, 720)
        XCTAssertEqual(item.videoMedia?.height, 1280)
        XCTAssertEqual(item.directVideoURL?.host, "video.twimg.com")
        XCTAssertEqual(item.videoURL?.path, "/api/ios/v1/media-proxy")
        XCTAssertEqual(item.videoPreviewURL?.path, "/api/ios/v1/image-proxy")
    }

    func testXDetailPrefersCompleteStoredTranslationOverLiveSummary() {
        let storedBody = "这是已经存储的完整中文正文，包含第一段和第二段。"
        let liveSummary = "中文摘要…"

        XCTAssertEqual(
            XPostTextFormatter.longestText(liveSummary, storedBody),
            storedBody
        )
        XCTAssertEqual(
            XPostTextFormatter.longestText("  \(storedBody)  ", nil),
            storedBody
        )
    }

    func testXDetailSwitchesFromTruncatedSummaryToLiveFullOriginal() {
        XCTAssertTrue(
            XPostTextFormatter.shouldPreferFullOriginal(
                displayed: "这是列表接口返回的摘要…",
                fullOriginal: "这是 X 详情接口返回的完整正文，包含摘要中缺少的后续内容。"
            )
        )
        XCTAssertFalse(
            XPostTextFormatter.shouldPreferFullOriginal(
                displayed: "这已经是完整正文。",
                fullOriginal: "这是另一份完整正文。"
            )
        )
    }

    func testXDetailKeepsParagraphsSeparateAndSingleLineBreaksInsideParagraphs() {
        XCTAssertEqual(
            XPostTextFormatter.paragraphs(
                "第一段。\n\n第二段第一行。\n第二段第二行。\n\n\n第三段。"
            ),
            [
                "第一段。",
                "第二段第一行。\n第二段第二行。",
                "第三段。"
            ]
        )
    }

    func testXCommentRemovesDuplicatedReplyMention() {
        XCTAssertEqual(
            XPostTextFormatter.commentText("@AsiaFinance AI 牛市中场。", replyingTo: "AsiaFinance"),
            "AI 牛市中场。"
        )
        XCTAssertEqual(
            XPostTextFormatter.commentText("普通评论", replyingTo: nil),
            "普通评论"
        )
    }

    func testXDetailHidesPlatformShortLinksButKeepsRealArticleLinks() {
        XCTAssertFalse(XPostTextFormatter.shouldShowExternalURL(URL(string: "https://t.co/abc")))
        XCTAssertFalse(XPostTextFormatter.shouldShowExternalURL(URL(string: "https://x.com/example/status/1")))
        XCTAssertTrue(XPostTextFormatter.shouldShowExternalURL(URL(string: "https://example.com/story")))
        XCTAssertFalse(XPostTextFormatter.shouldShowExternalURL(nil))
    }

    func testXDetailWaitsOnlyWhenInitialTextIsTruncated() {
        XCTAssertTrue(XPostTextFormatter.shouldWaitForFullText("列表摘要…"))
        XCTAssertTrue(XPostTextFormatter.shouldWaitForFullText("列表摘要..."))
        XCTAssertFalse(XPostTextFormatter.shouldWaitForFullText("这已经是完整正文。"))
    }

    func testXDetailReusesCompleteStoredTextAndTranslation() throws {
        let data = #"{"id":7,"source":"x","content":"Complete stored original.","content_zh":"已经存储的完整中文翻译。","post_link":"https://x.com/example/status/123","meta":{"lang":"en","raw_text":"Complete stored original."}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: data)

        XCTAssertFalse(post.needsXLiveDetail)
        XCTAssertFalse(post.needsXTranslation)
        XCTAssertFalse(post.needsXStoredDetailRefresh)
    }

    func testXDetailFetchesOnlyMissingStoredData() throws {
        let data = #"{"id":7,"source":"x","content":"Truncated original…","post_link":"https://x.com/example/status/123","meta":{"lang":"en"}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: data)

        XCTAssertTrue(post.needsXLiveDetail)
        XCTAssertTrue(post.needsXTranslation)
        XCTAssertTrue(post.needsXStoredDetailRefresh)
    }

    func testChineseXPostTreatsContentZHAsEnrichedOriginalRatherThanTranslation() throws {
        let data = #"{"id":7,"source":"x","content":"列表摘要…","content_zh":"被压平的完整中文正文","post_link":"https://x.com/example/status/123","meta":{"lang":"zh","note_text":"第一段。\n\n第二段。"}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: data)

        XCTAssertTrue(post.isChineseXSource)
        XCTAssertEqual(post.xStoredOriginalContent, "第一段。\n\n第二段。")
        XCTAssertEqual(XPostTextFormatter.paragraphs(post.xStoredOriginalContent), ["第一段。", "第二段。"])
    }

    func testChineseXDetailUsesCompleteStoredChineseContentWithoutRefresh() throws {
        let data = #"{"id":7,"source":"x","content":"列表摘要...","content_zh":"已经存储的完整中文正文，不需要进入详情后再次加载。","post_link":"https://x.com/example/status/123","meta":{"lang":"zh"}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: data)

        XCTAssertEqual(post.xStoredOriginalContent, "已经存储的完整中文正文，不需要进入详情后再次加载。")
        XCTAssertFalse(post.needsXLiveDetail)
        XCTAssertFalse(post.needsXStoredDetailRefresh)
    }

    func testProtectsModelNamesInXTranslation() {
        XCTAssertEqual(
            PersonDetailStore.presentedTranslation("双子座是谁？格罗克也来了。", original: "Gemini who? Grok is here."),
            "Gemini是谁？Grok也来了。"
        )
    }

    func testServerPersonWithPostsCanLoadOwnPostFeed() throws {
        let data = #"{"success":true,"users":[{"user_id":"rss:16","user_name":"但斌","user_screen_name":"雪球-但斌","today_count":2,"total_count":30}]}"#.data(using: .utf8)!
        let person = try JSONDecoder().decode(SpecialPeopleResponse.self, from: data).users[0]

        XCTAssertFalse(person.isCurated)
        XCTAssertFalse(person.hasXSource)
        XCTAssertTrue(person.hasOwnPostSource)
    }

    func testKnownAccountIdentityUsesCanonicalPersonNameAndKeepsPlatformAlias() throws {
        let data = #"{"success":true,"users":[{"user_id":"rss:14","user_name":"大道无形我有型","user_screen_name":"雪球-大道无形我有型","today_count":1,"total_count":20,"discussion_keywords":["大道无形我有型"]}]}"#.data(using: .utf8)!
        let person = try JSONDecoder().decode(SpecialPeopleResponse.self, from: data).users[0]

        XCTAssertEqual(person.name, "段永平")
        XCTAssertEqual(person.secondaryLabel, "雪球 · 大道无形我有型")
        XCTAssertEqual(person.discussionKeywords, ["大道无形我有型", "段永平"])
    }

    func testDecodesXPeopleSearchAndImportResponses() throws {
        let searchData = #"{"success":true,"results":[{"id":"1605","name":"Sam Altman","screen_name":"sama","description":"OpenAI","avatar_url":"https://example.com/avatar.jpg","verified":true,"followers_count":100,"following_count":10,"already_in_directory":false}]}"#.data(using: .utf8)!
        let importData = #"{"success":true,"added":true,"person":{"user_id":"1605","user_name":"Sam Altman","user_screen_name":"sama","x_user_id":"1605","x_screen_name":"sama","today_count":0,"total_count":0}}"#.data(using: .utf8)!
        let search = try JSONDecoder().decode(XPeopleSearchResponse.self, from: searchData)
        let imported = try JSONDecoder().decode(XPersonImportResponse.self, from: importData)

        XCTAssertEqual(search.results.first?.handle, "@sama")
        XCTAssertEqual(search.results.first?.avatarURL?.absoluteString, "https://example.com/avatar.jpg")
        XCTAssertTrue(search.results.first?.verified == true)
        XCTAssertEqual(imported.person.id, "1605")
        XCTAssertTrue(imported.added)
    }

    func testDecodesWikipediaPeopleSearchAndImportResponses() throws {
        let searchData = #"{"success":true,"results":[{"id":"Q1137062","page_id":123,"language":"zh","title":"马云","description":"中国企业家","extract":"阿里巴巴集团主要创始人。","avatar_url":"https://example.com/jack-ma.jpg","article_url":"https://zh.wikipedia.org/wiki/%E9%A9%AC%E4%BA%91","already_in_directory":false}]}"#.data(using: .utf8)!
        let importData = #"{"success":true,"added":true,"person":{"user_id":"curated:wikidata:q1137062","user_name":"马云","user_screen_name":"维基百科","user_description":"阿里巴巴集团主要创始人。","avatar_url":"https://example.com/jack-ma.jpg","organization_name":"中国企业家","today_count":0,"total_count":0,"has_own_post_source":false}}"#.data(using: .utf8)!
        let search = try JSONDecoder().decode(WikipediaPeopleSearchResponse.self, from: searchData)
        let imported = try JSONDecoder().decode(WikipediaPersonImportResponse.self, from: importData)

        XCTAssertEqual(search.results.first?.name, "马云")
        XCTAssertEqual(search.results.first?.sourceLabel, "中文维基百科")
        XCTAssertEqual(search.results.first?.avatarURL?.absoluteString, "https://example.com/jack-ma.jpg")
        XCTAssertEqual(search.results.first?.articleURL?.host, "zh.wikipedia.org")
        XCTAssertEqual(imported.person.id, "curated:wikidata:q1137062")
        XCTAssertFalse(imported.person.hasOwnPostSource)
        XCTAssertTrue(imported.added)
    }

    func testCuratedPersonWithoutAccountDoesNotRequestOwnPostFeed() {
        let person = SpecialPerson(
            id: "xi-jinping",
            name: "习近平",
            organization: "中国政治人物",
            summary: "关注中国政治、外交与公共政策相关动态。"
        )

        XCTAssertTrue(person.isCurated)
        XCTAssertFalse(person.hasOwnPostSource)
    }

    func testRSSFeedPrefersHighResolutionAvatarAndVersionsStaticIcon() throws {
        let data = #"{"data":{"feeds":[{"id":64,"name":"Example","icon":"/img/rss-feed-icons/rss-feed-64.jpg","avatar_url":"https://cdn.example.com/avatar-180.jpg","updated_at":"2026-07-18T10:00:00Z","is_enabled":true}]}}"#.data(using: .utf8)!
        let feed = try JSONDecoder().decode(RSSFeedsResponse.self, from: data).data.feeds[0]

        XCTAssertEqual(feed.preferredAvatarURL?.absoluteString, "https://cdn.example.com/avatar-180.jpg")
        XCTAssertTrue(feed.iconURL?.absoluteString.contains("v=2026-07-18T10:00:00Z") == true)
    }

    func testRSSFeedRecognizesServerManagedAvatar() throws {
        let data = #"{"data":{"feeds":[{"id":78,"name":"人民日报微博","icon":"/img/rss-feed-icons/rss-feed-78.jpg","avatar_url":"/api/ios/v1/rss/feeds/78/avatar?v=abc123","updated_at":"2026-07-20T10:00:00Z","is_enabled":true}]}}"#.data(using: .utf8)!
        let feed = try JSONDecoder().decode(RSSFeedsResponse.self, from: data).data.feeds[0]

        XCTAssertTrue(feed.hasManagedAvatar)
        XCTAssertEqual(feed.preferredAvatarURL?.path, "/api/ios/v1/rss/feeds/78/avatar")
    }

    func testWikipediaCandidateExtractionFindsNamedEntitiesWithoutDuplicates() {
        let candidates = WikipediaEntityCandidateExtractor.candidates(
            in: ["英伟达、微软和 OpenAI 正在推动投资。OpenAI 随后发布了更新。"]
        )

        XCTAssertTrue(candidates.contains("OpenAI"))
        XCTAssertTrue(candidates.contains("英伟达"))
        XCTAssertTrue(candidates.contains("微软"))
        XCTAssertEqual(candidates.filter { $0 == "OpenAI" }.count, 1)
    }

    func testWikipediaCandidateExtractionCoversEntitiesLateInLongArticles() {
        let earlyParagraphs = (0..<30).map { "第\($0)段介绍人工智能产业的发展趋势和相关背景。" }
        let candidates = WikipediaEntityCandidateExtractor.candidates(
            in: earlyParagraphs + ["文章最后讨论美国、欧洲、英伟达与微软。"]
        )

        XCTAssertTrue(candidates.contains("美国"))
        XCTAssertTrue(candidates.contains("欧洲"))
        XCTAssertTrue(candidates.contains("英伟达"))
        XCTAssertTrue(candidates.contains("微软"))
    }

    func testWikipediaCandidateExtractionDoesNotLinkGenericChineseWords() {
        let candidates = WikipediaEntityCandidateExtractor.candidates(
            in: ["官员表示相关法律要求企业使用普通工具维护社会稳定。"]
        )

        XCTAssertFalse(candidates.contains("官员"))
        XCTAssertFalse(candidates.contains("法律"))
        XCTAssertFalse(candidates.contains("工具"))
        XCTAssertFalse(candidates.contains("稳定"))
    }

    func testSmallSquareRSSImageIsTreatedAsInlineEmoji() throws {
        let data = #"{"url":"https://example.com/emoji.png","width":64,"height":64}"#.data(using: .utf8)!
        let image = try JSONDecoder().decode(PostImage.self, from: data)

        XCTAssertTrue(image.isLikelyInlineEmoji)
    }

    func testArticleImageIsNotTreatedAsInlineEmoji() throws {
        let data = #"{"url":"https://example.com/photo.jpg","width":1080,"height":1080}"#.data(using: .utf8)!
        let image = try JSONDecoder().decode(PostImage.self, from: data)

        XCTAssertFalse(image.isLikelyInlineEmoji)
    }

    func testWeiboVideoPlaceholderIsTreatedAsKnownInlineAssetWithoutDimensions() throws {
        let data = #"{"url":"https://h5.sinaimg.cn/upload/timeline_card_small_video_default.png"}"#.data(using: .utf8)!
        let image = try JSONDecoder().decode(PostImage.self, from: data)

        XCTAssertTrue(image.isKnownInlineAsset)
    }

    func testDecodesPostListResponse() throws {
        let json = #"""
        {
          "data": [{
            "id": 42,
            "title": "测试新闻",
            "summary": "摘要内容",
            "content_zh": "中文正文",
            "source": "rss:77",
            "formatted_time": "刚刚",
            "final_score": 8.6,
            "post_link": "https://example.com/post",
            "user": { "user_screen_name": "示例来源" },
            "postTags": [{ "id": 1, "name": "AI" }],
            "images": [{ "url": "https://example.com/image.jpg", "width": 1080, "height": 1350, "alt_text": "VCG/Getty Images" }],
            "meta": { "lang": "en", "urls": ["https://example.com/story"], "photo_credit": "VCG/Getty Images" }
          }]
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(PostListResponse.self, from: json)

        XCTAssertEqual(response.data.first?.id, 42)
        XCTAssertEqual(response.data.first?.authorName, "示例来源")
        XCTAssertEqual(response.data.first?.normalizedSource, "RSS")
        XCTAssertEqual(response.data.first?.score, 8.6)
        XCTAssertEqual(response.data.first?.displayTitle, "中文正文")
        XCTAssertEqual(response.data.first?.displayContent, "中文正文")
        XCTAssertEqual(response.data.first?.authorName, "示例来源")
        XCTAssertEqual(response.data.first?.photoCredit, "VCG/Getty Images")
        XCTAssertEqual(response.data.first?.externalURL?.absoluteString, "https://example.com/story")
    }

    func testKnownPostAccountUsesCanonicalNameWithoutLosingOriginalAccount() throws {
        let json = #"{"data":[{"id":14,"source":"rss:14","user":{"user_id":"rss:14","user_name":"大道无形我有型","user_screen_name":"大道无形我有型"}}]}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(PostListResponse.self, from: json).data[0]

        XCTAssertEqual(post.authorName, "段永平")
        XCTAssertEqual(post.authorHandle, "雪球 · 大道无形我有型")
    }

    func testXueqiuImageUsesOriginalAssetInsteadOfCustomThumbnail() throws {
        let json = #"{"id":17,"source":"rss:14","images":[{"url":"https://xqimg.imedao.com/example.jpeg!custom.jpg"}]}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: json)

        XCTAssertEqual(post.imageURLs.first?.absoluteString, "https://xqimg.imedao.com/example.jpeg")
    }

    func testXueqiuImagesKeepTheirBodyAndReplyPlacement() throws {
        let json = #"{"id":18,"source":"rss:14","content":"正文<br/><img src=\"https://xqimg.imedao.com/body.jpg!custom.jpg\"/><blockquote>回复者: 回复内容<br/><img src=\"https://xqimg.imedao.com/reply.jpg!custom.jpg\"/></blockquote>","images":[{"url":"https://xqimg.imedao.com/body.jpg!custom.jpg"},{"url":"https://xqimg.imedao.com/reply.jpg!custom.jpg"},{"url":"https://xqimg.imedao.com/unplaced.jpg!custom.jpg"}]}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: json)

        XCTAssertEqual(post.xueqiuBodyImageURLs.map(\.lastPathComponent), ["body.jpg"])
        XCTAssertEqual(post.xueqiuQuoteImageURLs.map(\.lastPathComponent), ["reply.jpg"])
        XCTAssertEqual(post.xueqiuUnplacedImageURLs.map(\.lastPathComponent), ["unplaced.jpg"])
    }

    func testXueqiuEmojiOnlyBodyDoesNotDuplicateQuotedPost() throws {
        let json = #"{"id":19,"source":"rss:14","content":"<img src=\"//assets.imedao.com/ugc/images/face/emoji_13_coldsweat.png?v=1\" title=\"[滴汗]\" alt=\"[滴汗]\" height=\"24\" /><blockquote>大道无形逍遥游:&nbsp;<a href=\"https://xueqiu.com/n/大道无形我有型\" target=\"_blank\">@大道无形我有型</a> 大道你好，很好奇你对美债的看法。</blockquote>"}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: json)

        XCTAssertEqual(post.xueqiuBodyContent, "[滴汗]")
        XCTAssertEqual(post.xueqiuBodyInlineEmojis.map(\.token), ["[滴汗]"])
        XCTAssertEqual(post.xueqiuQuoteAuthor, "大道无形逍遥游")
        XCTAssertEqual(post.xueqiuQuoteBody, "@大道无形我有型 大道你好，很好奇你对美债的看法。")
        XCTAssertFalse(post.xueqiuBodyContent.contains("大道你好"))
    }

    func testXueqiuPrefersServerManagedInlineEmojiAndUsesImageProxy() throws {
        let json = #"{"id":20,"source":"rss:14","content":"[滴汗]<blockquote>提问者: 问题</blockquote>","images":[{"url":"https://assets.imedao.com/ugc/images/face/emoji_13_coldsweat.png?v=1","height":24,"alt_text":"[滴汗]","kind":"inline_emoji"}]}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: json)

        let emoji = try XCTUnwrap(post.xueqiuBodyInlineEmojis.first)
        XCTAssertEqual(emoji.token, "[滴汗]")
        XCTAssertTrue(emoji.url.path.hasSuffix("/api/ios/v1/image-proxy"))
        let sourceURL = URLComponents(url: emoji.url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "url" })?.value
        XCTAssertEqual(sourceURL, "https://assets.imedao.com/ugc/images/face/emoji_13_coldsweat.png?v=1")
    }

    func testConfirmedServerIdentityIsShownButUnconfirmedClaimIsIgnored() throws {
        let confirmedJSON = #"{"data":[{"id":15,"source":"weibo","user":{"user_id":"weibo:123","user_name":"平台昵称","canonical_name":"真实人物","platform_display_name":"平台昵称","platform":"微博","identity_status":"verified"}}]}"#.data(using: .utf8)!
        let unconfirmedJSON = #"{"data":[{"id":16,"source":"weibo","user":{"user_id":"weibo:456","user_name":"另一个昵称","canonical_name":"不应展示的人物","identity_status":"unconfirmed"}}]}"#.data(using: .utf8)!
        let confirmed = try JSONDecoder().decode(PostListResponse.self, from: confirmedJSON).data[0]
        let unconfirmed = try JSONDecoder().decode(PostListResponse.self, from: unconfirmedJSON).data[0]

        XCTAssertEqual(confirmed.authorName, "真实人物")
        XCTAssertEqual(confirmed.authorHandle, "微博 · 平台昵称")
        XCTAssertEqual(unconfirmed.authorName, "另一个昵称")
    }

    func testYouTubePostBuildsCoverFromVideoLink() throws {
        let json = #"{"id":79,"title":"最新一期","source":"rss:79","post_link":"https://www.youtube.com/watch?v=DZR27djdRco","postTags":[]}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: json)

        XCTAssertTrue(post.isYouTube)
        XCTAssertEqual(post.youtubeCoverURL?.absoluteString, "https://i.ytimg.com/vi/DZR27djdRco/hqdefault.jpg")
    }

    func testBilibiliRSSPostUsesBilibiliPresentationFromArticleLink() throws {
        let json = #"{"id":1271,"title":"最新视频","source":"rss:1271","post_link":"https://www.bilibili.com/video/BV1Pxgy68Ek9","videos":[]}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: json)

        XCTAssertTrue(post.isRSS)
        XCTAssertTrue(post.isBilibili)
        XCTAssertEqual(post.sourceName, "B站")
        XCTAssertEqual(post.bilibiliPlaybackPageURL?.absoluteString, "https://www.bilibili.com/video/BV1Pxgy68Ek9")
    }

    func testBilibiliRSSPostUsesBilibiliPresentationFromFeedMetadata() throws {
        let json = #"{"id":1272,"title":"最新视频","source":"rss:1271","meta":{"rss_feed_name":"王骁 · 哔哩哔哩","rss_article_link":"https://example.com/video"}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: json)

        XCTAssertTrue(post.isBilibili)
        XCTAssertEqual(post.sourceName, "B站")
    }

    func testBilibiliListContentKeepsTitleWhenHTMLPreviewHasTooLittleText() throws {
        let json = #"{"id":1271,"title":"100天亏掉40%？理财大赛S2结果公布！","source":"rss:1271","content":"<iframe></iframe><br><img src='cover.jpg'><br>谁是理...","post_link":"https://www.bilibili.com/video/BV1Pxgy68Ek9"}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: json)

        XCTAssertEqual(post.bilibiliListContent, "100天亏掉40%？理财大赛S2结果公布！")
    }

    func testDecodesBilibiliSubtitleTimeline() throws {
        let json = #"{"success":true,"bvid":"BV1Pxgy68Ek9","language":"zh-Hans","status":"ready","cues":[{"start_ms":1250,"end_ms":3400,"text":"欢迎来到本期视频"}]}"#.data(using: .utf8)!
        let payload = try JSONDecoder().decode(BilibiliSubtitlesResponse.self, from: json)

        XCTAssertEqual(payload.bvid, "BV1Pxgy68Ek9")
        XCTAssertEqual(payload.cues.first?.startMS, 1250)
        XCTAssertEqual(payload.cues.first?.text, "欢迎来到本期视频")
    }

    func testDecodesBilibiliAISummary() throws {
        let json = #"{"success":true,"bvid":"BV1Pxgy68Ek9","status":"ready","summary":{"overview":"比赛结果反映了不同策略的风险收益差异。","key_points":["高波动策略回撤明显","长期纪律比短期排名更重要"]},"provider":"qwen","model":"qwen3.5-flash","cached":true}"#.data(using: .utf8)!
        let payload = try JSONDecoder().decode(BilibiliSummaryResponse.self, from: json)

        XCTAssertEqual(payload.provider, "qwen")
        XCTAssertEqual(payload.summary.keyPoints.count, 2)
        XCTAssertTrue(payload.cached)
    }

    func testDecodesBilibiliVideoInterpretation() throws {
        let json = #"{"success":true,"bvid":"BV1Pxgy68Ek9","status":"ready","interpretation":{"overview":"画面通过收益曲线展示不同策略。","visual_findings":["曲线在中段出现明显分化"],"timeline":[{"time":"01:20","title":"结果公布","detail":"表格展示最终排名"}],"creator_notes":["数据图承担主要证据作用"]},"provider":"bigmodel","model":"glm-4.6v","cached":false,"estimated_cost_cny":0.18,"pricing_note":"按标准价估算"}"#.data(using: .utf8)!
        let payload = try JSONDecoder().decode(BilibiliInterpretationResponse.self, from: json)

        XCTAssertEqual(payload.interpretation.timeline.first?.time, "01:20")
        XCTAssertEqual(payload.estimatedCostCNY, 0.18)
        XCTAssertEqual(payload.model, "glm-4.6v")
    }

    func testTruthFeedUsesOnlyTranslatedContentAndRelevance() throws {
        let json = #"{"post":{"id":9,"content":"English original","content_zh":"中文翻译","source":"truth","final_score":8.2}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(PostDetailResponse.self, from: json).post

        XCTAssertEqual(post.truthFeedContent, "中文翻译")
        XCTAssertEqual(post.truthRelevanceLabel, "高度相关")
        XCTAssertFalse(post.truthFeedContent.contains("English"))
    }

    func testTruthFeedShowsMediumRelevanceAndUsefulImpactOnly() throws {
        let useful = #"{"post":{"id":12,"content_zh":"中文翻译","source":"truth","final_score":6.2,"weight_reason":"关键事实：将发表讲话。可能影响：可能引发宏观环境波动与资金流向变化。"}}"#.data(using: .utf8)!
        let usefulPost = try JSONDecoder().decode(PostDetailResponse.self, from: useful).post
        XCTAssertEqual(usefulPost.truthRelevanceLabel, "中度相关")
        XCTAssertEqual(usefulPost.truthImpactText, "可能引发宏观环境波动与资金流向变化")

        let fallback = #"{"post":{"id":13,"source":"truth","weight_reason":"正式模型失败，使用本地基础评分器分数临时兜底。"}}"#.data(using: .utf8)!
        let fallbackPost = try JSONDecoder().decode(PostDetailResponse.self, from: fallback).post
        XCTAssertNil(fallbackPost.truthImpactText)
    }

    func testTruthFeedDoesNotFallBackToOriginalWhileTranslationIsPending() throws {
        let json = #"{"post":{"id":10,"content":"English original","source":"truth"}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(PostDetailResponse.self, from: json).post

        XCTAssertEqual(post.truthFeedContent, "翻译处理中")
    }

    func testTruthFeedRemovesTrailingLinkFromTranslation() throws {
        let json = #"{"post":{"id":11,"content_zh":"美国的好消息：https://example.com/a-long-story","source":"truth"}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(PostDetailResponse.self, from: json).post

        XCTAssertEqual(post.truthFeedContent, "美国的好消息")
    }

    func testDecodesDetailAndStripsHTML() throws {
        let json = #"{"post":{"id":7,"title":"标题","content":"<p>第一段</p><p>第二段</p>","images":[]}}"#.data(using: .utf8)!

        let response = try JSONDecoder().decode(PostDetailResponse.self, from: json)

        XCTAssertEqual(response.post.id, 7)
        XCTAssertTrue(response.post.displayContent.contains("第一段"))
        XCTAssertFalse(response.post.displayContent.contains("<p>"))
    }

    func testStripsEntityEncodedHTML() throws {
        let json = #"{"post":{"id":8,"content":"正文&amp;lt;img src=&amp;quot;https://example.com/a.jpg&amp;quot;&amp;gt;结尾"}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(PostDetailResponse.self, from: json)

        XCTAssertFalse(response.post.displayContent.contains("img src"))
        XCTAssertTrue(response.post.displayContent.contains("正文"))
        XCTAssertTrue(response.post.displayContent.contains("结尾"))
    }

    func testDecodesNumericEntitiesAndRemovesPrivateUseGlyphs() throws {
        let json = #"{"post":{"id":108,"content":"回复：冠以&#34;价投&#34;的文字<br>下一行","source":"rss:16","meta":{"rss_feed_name":"雪球-但斌"}}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(PostDetailResponse.self, from: json).post

        XCTAssertEqual(post.displayContent, "回复：冠以\"价投\"的文字\n下一行")
        XCTAssertFalse(post.displayContent.contains("&#34;"))
        XCTAssertFalse(post.displayContent.contains(""))
    }

    func testStripsTruncatedTrailingHTMLTag() throws {
        let json = #"{"success":true,"data":[{"id":47,"content":"正文<p><img src='image.jpg'/></p><p style='text-align: right; col...","source":"rss:47"}]}"#
        let response = try JSONDecoder().decode(PostListResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.data[0].displayContent, "正文")
    }

    func testDecodesZhihuPresentationMetadata() throws {
        let json = #"""
        {
          "data": [{
            "id": 99,
            "title": "如何评价新的 AI 模型？",
            "content": "如何评价新的 AI 模型？\n热度: 119 万热度\n回答数: 15",
            "source": "zhihu",
            "user": { "user_name": "知乎热榜" },
            "postTags": [{ "id": 1, "name": "人工智能" }],
            "meta": {
              "zhihu_heat": "119 万热度",
              "zhihu_answers": 15,
              "zhihu_answer_excerpt": "这是高赞回答的摘要。\n\n第二段。",
              "zhihu_answer_content": "这是完整回答第一段。\n\n这是完整回答第二段，内容更长。",
              "zhihu_answer_author": {
                "name": "张俊林",
                "headline": "AI 算法研究员",
                "avatar_url": "https://example.com/avatar.jpg"
              },
              "zhihu_answer_voteup_count": 1200,
              "zhihu_answer_comment_count": 86
            }
          }]
        }
        """#.data(using: .utf8)!

        let post = try JSONDecoder().decode(PostListResponse.self, from: json).data[0]

        XCTAssertEqual(post.zhihuQuestionTitle, "如何评价新的 AI 模型？")
        XCTAssertEqual(post.zhihuTopicLabel, "人工智能")
        XCTAssertEqual(post.zhihuAnswerPreview, "这是高赞回答的摘要。\n\n第二段。")
        XCTAssertEqual(post.zhihuCompactAnswerPreview, "这是高赞回答的摘要。 第二段。")
        XCTAssertEqual(post.zhihuAnswerBody, "这是完整回答第一段。\n\n这是完整回答第二段，内容更长。")
        XCTAssertTrue(post.hasFullZhihuAnswer)
        XCTAssertEqual(post.zhihuArticleParagraphs.count, 2)
        XCTAssertEqual(post.zhihuAnswerAuthorName, "张俊林")
        XCTAssertEqual(post.zhihuAnswerAuthorHeadline, "AI 算法研究员")
        XCTAssertTrue(post.hasZhihuAnswer)
        XCTAssertEqual(post.zhihuHeat, "119 万热度")
        XCTAssertEqual(post.zhihuAnswerCount, 15)
        XCTAssertEqual(post.zhihuHotMeta, "119 万热度")
    }

    func testBuildsHonestZhihuFallbackFromExistingContent() throws {
        let json = #"{"post":{"id":100,"title":"一个问题？","content":"一个问题？\n热度: 67 万热度\n回答数: 19","source":"zhihu","user":{"user_name":"知乎热榜"}}}"#.data(using: .utf8)!

        let post = try JSONDecoder().decode(PostDetailResponse.self, from: json).post

        XCTAssertEqual(post.zhihuHeat, "67 万热度")
        XCTAssertEqual(post.zhihuAnswerCount, 19)
        XCTAssertEqual(post.zhihuAnswerPreview, "当前热度 67 万热度。打开查看高赞回答与完整讨论。")
        XCTAssertEqual(post.zhihuAnswerAuthorName, "知乎热榜")
        XCTAssertEqual(post.zhihuAnswerAuthorHeadline, "今日热榜")
        XCTAssertFalse(post.hasZhihuAnswer)
        XCTAssertFalse(post.hasFullZhihuAnswer)
    }

    func testZhihuAnswerWithoutAvatarDoesNotReuseSourceAvatar() throws {
        let json = #"{"post":{"id":101,"title":"一个问题？","source":"zhihu","user":{"user_name":"知乎热榜","avatar_url":"/img/source-avatars/zhihu.svg"},"meta":{"zhihu_answer_excerpt":"真实回答","zhihu_answer_author":{"name":"真实答主"},"zhihu_rank":3}}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(PostDetailResponse.self, from: json).post

        XCTAssertTrue(post.hasZhihuAnswer)
        XCTAssertEqual(post.zhihuHotMeta, "热榜 #3")
        XCTAssertEqual(post.zhihuAnswerAuthorName, "真实答主")
        XCTAssertNil(post.zhihuAnswerAvatarURL)
    }

    func testBuildsBilibiliPlaybackResolverAndDecodesPreview() throws {
        let json = #"{"post":{"id":101,"source":"bilibili","videos":[{"url":"https://www.bilibili.com/video/BV1c3NY6kERj","preview":"https://i0.hdslb.com/cover.jpg"}]}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(PostDetailResponse.self, from: json).post

        let playbackURL = try XCTUnwrap(post.videoURLs.first)
        let components = try XCTUnwrap(URLComponents(url: playbackURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/api/ios/v1/bilibili/hls/BV1c3NY6kERj/video.mp4")
        XCTAssertNil(components.query)
        XCTAssertEqual(post.previewURL?.path, "/api/ios/v1/image-proxy")
    }

    func testPrefersExplicitVideoPlayURL() throws {
        let json = #"{"post":{"id":102,"videos":[{"url":"https://example.com/page","play_url":"https://cdn.example.com/video.mp4"}]}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(PostDetailResponse.self, from: json).post

        XCTAssertEqual(post.videoURLs.first?.absoluteString, "https://cdn.example.com/video.mp4")
    }

    func testDecodesXVideoWithoutRequiringImageOrPreview() throws {
        let json = #"{"post":{"id":2423252,"source":"x","images":[],"videos":[{"url":"https://video.twimg.com/demo.mp4","width":1920,"height":1080}]}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(PostDetailResponse.self, from: json).post

        XCTAssertEqual(post.videoURLs.count, 1)
        XCTAssertEqual(post.directVideoURLs.first?.absoluteString, "https://video.twimg.com/demo.mp4")
        XCTAssertEqual(post.videoURLs.first?.path, "/api/ios/v1/media-proxy")
        XCTAssertNil(post.previewURL)
        XCTAssertEqual(post.videos?.first?.width, 1920)
        XCTAssertEqual(post.videos?.first?.height, 1080)
    }

    func testExtractsCompleteNewYorkTimesArticleBody() throws {
        let html = """
        <section class="article-body">
          <div class="article-paragraph">第一段包含<strong>重点</strong>。</div>
          <div class="article-paragraph">第二段包含<a href="#">链接文字</a>。</div>
          <div class="article-paragraph">第三段。</div>
          <div class="article-paragraph">第四段是文章结尾。</div>
        </section>
        """
        XCTAssertEqual(
            NewYorkTimesArticleParser.extract(from: html),
            NewYorkTimesArticle(blocks: [
                .paragraph("第一段包含重点。"),
                .paragraph("第二段包含链接文字。"),
                .paragraph("第三段。"),
                .paragraph("第四段是文章结尾。")
            ])
        )
    }

    func testPreservesNewYorkTimesInlineImageOrderAndCaption() throws {
        let html = """
        <section class="article-body">
          <div class="article-paragraph">图片前正文。</div>
          <div class="article-paragraph"><figure><div class="img-box"><img src="preview.jpg" data-src="https://example.com/full.jpg" alt="图片说明"></div><figcaption><span>图片说明</span><cite>摄影署名</cite></figcaption></figure></div>
          <div class="article-paragraph">图片后正文。</div>
        </section>
        """
        XCTAssertEqual(
            NewYorkTimesArticleParser.extract(from: html),
            NewYorkTimesArticle(blocks: [
                .paragraph("图片前正文。"),
                .image(url: URL(string: "https://example.com/full.jpg")!, caption: "图片说明", credit: "摄影署名"),
                .paragraph("图片后正文。")
            ])
        )
    }

    func testNewYorkTimesInlineImageUsesServerProxy() throws {
        let html = #"<div class="article-paragraph"><img src="https://static01.nyt.com/images/example.jpg"></div>"#
        let article = try XCTUnwrap(NewYorkTimesArticleParser.extract(from: html))
        guard case .image(let url, _, _) = try XCTUnwrap(article.blocks.first) else {
            return XCTFail("Expected an image block")
        }

        XCTAssertTrue(url.path.hasSuffix("/api/ios/v1/image-proxy"))
    }

    func testBuildsReadableNewYorkTimesParagraphsFromStoredText() throws {
        let sentence = "这是一段已经保存到服务器的纽约时报正文。"
        let article = try XCTUnwrap(NewYorkTimesArticle.storedText(Array(repeating: sentence, count: 12).joined(separator: " ")))

        XCTAssertGreaterThan(article.blocks.count, 1)
        XCTAssertTrue(article.blocks.allSatisfy { if case .paragraph = $0 { return true }; return false })
    }

    func testNewYorkTimesStoredTextPreservesParagraphsAndRemovesBrokenChineseSpacing() throws {
        let article = try XCTUnwrap(NewYorkTimesArticle.storedText(
            "第一段首次 超过 了预期。\n\n第二段正在被 迅速 采用，并通过 复 制 完成。"
        ))

        XCTAssertEqual(article.blocks, [
            .paragraph("第一段首次超过了预期。"),
            .paragraph("第二段正在被迅速采用，并通过复制完成。")
        ])
    }

    func testNewYorkTimesLeadRemovesHeroImageCredit() throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            "post": [
                "id": 502,
                "source": "rss:47",
                "summary": "这是一段文章摘要。 Benny Douet",
                "images": [[
                    "url": "https://example.com/hero.png",
                    "alt_text": "Benny Douet"
                ]]
            ]
        ])
        let post = try JSONDecoder().decode(PostDetailResponse.self, from: payload).post

        XCTAssertEqual(post.newYorkTimesLead, "这是一段文章摘要。")
    }

    func testNewYorkTimesFeedExcerptDoesNotExposeTheCompleteArticle() throws {
        let body = Array(repeating: "纽约时报正文段落。", count: 100).joined()
        let payload = try JSONSerialization.data(withJSONObject: [
            "post": [
                "id": 501,
                "source": "rss:47",
                "title": "测试文章",
                "content": body
            ]
        ])
        let post = try JSONDecoder().decode(PostDetailResponse.self, from: payload).post

        XCTAssertLessThanOrEqual(post.newYorkTimesFeedExcerpt.count, 281)
        XCTAssertTrue(post.newYorkTimesFeedExcerpt.hasSuffix("…"))
        XCTAssertLessThan(post.newYorkTimesFeedExcerpt.count, body.count)
        XCTAssertNotEqual(post.newYorkTimesFeedExcerpt, body)
    }
}
