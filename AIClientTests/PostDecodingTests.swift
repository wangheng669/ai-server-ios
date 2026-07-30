import XCTest
@testable import AIServerClient

final class PostDecodingTests: XCTestCase {
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
        XCTAssertEqual(focused.first?.id, "satya")
        XCTAssertTrue(focused.contains { $0.id == "greg" })
        XCTAssertEqual(Set(openAI.map(\.id)), Set(["sam", "greg"]))
        XCTAssertEqual(clusters.first?.title, "合作")
        XCTAssertEqual(clusters.first?.members.map(\.id), ["satya"])
        XCTAssertEqual(
            PeopleRelationshipPlanner.relationshipLabel(from: people[0], to: people[2]),
            "战略合作伙伴"
        )
    }

    func testDecodesXQuotedTweetForPersonPostCard() throws {
        let data = #"{"post":{"id":1,"source":"x","meta":{"quoted_tweet":{"id":"99","text":"Gemini who?","text_zh":"双子座是谁？","author":{"name":"Example","screenName":"example","profileImageUrl":"https://example.com/a.jpg"},"media":[{"type":"photo","url":"https://example.com/p.jpg","thumbnail_url":"https://example.com/t.jpg","width":1200,"height":800}]}}}}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(PostDetailResponse.self, from: data).post

        XCTAssertEqual(post.meta?.quotedTweet?.author?.handle, "@example")
        XCTAssertEqual(post.meta?.quotedTweet?.displayText, "双子座是谁？")
        XCTAssertEqual(post.meta?.quotedTweet?.media?.first?.displayURL?.absoluteString, "https://example.com/t.jpg")
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
        let data = #"{"data":{"feeds":[{"id":78,"name":"人民日报微博","icon":"/img/rss-feed-icons/rss-feed-78.jpg","avatar_url":"/api/v1/rss/feeds/78/avatar?v=abc123","updated_at":"2026-07-20T10:00:00Z","is_enabled":true}]}}"#.data(using: .utf8)!
        let feed = try JSONDecoder().decode(RSSFeedsResponse.self, from: data).data.feeds[0]

        XCTAssertTrue(feed.hasManagedAvatar)
        XCTAssertEqual(feed.preferredAvatarURL?.path, "/api/v1/rss/feeds/78/avatar")
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

    func testYouTubePostBuildsCoverFromVideoLink() throws {
        let json = #"{"id":79,"title":"最新一期","source":"rss:79","post_link":"https://www.youtube.com/watch?v=DZR27djdRco","postTags":[]}"#.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: json)

        XCTAssertTrue(post.isYouTube)
        XCTAssertEqual(post.youtubeCoverURL?.absoluteString, "https://i.ytimg.com/vi/DZR27djdRco/hqdefault.jpg")
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
        XCTAssertEqual(components.path, "/api/v1/bilibili/hls/BV1c3NY6kERj/video.mp4")
        XCTAssertNil(components.query)
        XCTAssertEqual(post.previewURL?.path, "/api/v1/image-proxy")
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

        XCTAssertTrue(url.path.hasSuffix("/api/v1/image-proxy"))
    }

    func testBuildsReadableNewYorkTimesParagraphsFromStoredText() throws {
        let sentence = "这是一段已经保存到服务器的纽约时报正文。"
        let article = try XCTUnwrap(NewYorkTimesArticle.storedText(Array(repeating: sentence, count: 12).joined(separator: " ")))

        XCTAssertGreaterThan(article.blocks.count, 1)
        XCTAssertTrue(article.blocks.allSatisfy { if case .paragraph = $0 { return true }; return false })
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
