import XCTest

/// Exercise the real feed views with populated, repeatable feeds.
final class FeedResponsivenessUITests: XCTestCase {
    func testResearchSectionsKeepLoadedContentAndSelections() {
        executionTimeAllowance = 240
        let app = XCUIApplication()
        app.launchArguments = ["--market-preview"]
        app.launch()
        let company = app.buttons["research-section-公司"]
        XCTAssertTrue(company.waitForExistence(timeout: 20))
        company.tap()
        XCTAssertTrue(app.scrollViews["company-home"].waitForExistence(timeout: 30))
        app.buttons["research-section-行业"].tap()
        let industries = app.scrollViews["industry-category-picker"]
        XCTAssertTrue(industries.waitForExistence(timeout: 30))
        let selection = industries.buttons.element(boundBy: 1)
        XCTAssertTrue(selection.exists)
        selection.tap()
        let industryName = selection.label
        XCTAssertTrue(selection.isSelected)
        app.buttons["research-section-宏观"].tap()
        XCTAssertTrue(app.scrollViews["macro-category-picker"].waitForExistence(timeout: 30))
        app.buttons["信用"].tap()
        XCTAssertTrue(app.buttons["信用"].isSelected)
        app.buttons["research-section-观点"].tap()
        let search = app.textFields["institution-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        search.typeText("摩根")
        app.buttons["research-section-概览"].tap()
        app.buttons["research-section-观点"].tap()
        XCTAssertEqual(search.value as? String, "摩根")
        app.buttons["research-section-宏观"].tap()
        XCTAssertTrue(!app.keyboards.firstMatch.exists || app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["信用"].isSelected)
        app.buttons["research-section-行业"].tap()
        XCTAssertTrue(industries.buttons[industryName].isSelected)
        company.tap()
        XCTAssertTrue(app.scrollViews["company-home"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["company-home-loading"].exists)
        capture(app, name: "research-tabs-retained")
        app.terminate()
    }

    func testRootTabRevisitsKeepPreparedContentWithoutLoadingAgain() throws {
        executionTimeAllowance = 240
        let app = XCUIApplication()
        app.launchArguments = ["--today-world-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["root-tab-知识"].waitForExistence(timeout: 20))

        let today = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'today-overview' OR identifier == 'today-status-scroll'")).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 25))
        app.buttons["root-tab-知识"].tap()
        let books = app.buttons["knowledge-books-entry"]
        XCTAssertTrue(books.waitForExistence(timeout: 25))
        let booksLabel = books.label
        XCTAssertFalse(app.descendants(matching: .any)["knowledge-home-loading"].exists)
        capture(app, name: "tabs-knowledge-prepared")

        app.buttons["root-tab-研究"].tap()
        let market = app.buttons["research-market-^GSPC"]
        XCTAssertTrue(market.waitForExistence(timeout: 25))
        capture(app, name: "tabs-research-prepared")

        let intelligence = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '情报，当前'")).firstMatch
        intelligence.tap()
        let post = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'feed-post-'")).firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: 30))
        capture(app, name: "tabs-feed-prepared")
        intelligence.tap()
        let news = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'signal-news-'")).firstMatch
        XCTAssertTrue(news.waitForExistence(timeout: 25))
        capture(app, name: "tabs-signal-prepared")

        for round in 0..<2 {
            let routes: [(XCUIElement, XCUIElement, String)] = [
                (app.buttons["root-tab-今日"], today, "today"),
                (app.buttons["root-tab-知识"], books, "knowledge"),
                (app.buttons["root-tab-研究"], market, "research"),
                (intelligence, news, "signal"),
                (intelligence, post, "feed")
            ]
            for (button, content, name) in routes {
                let start = ProcessInfo.processInfo.systemUptime
                button.tap()
                if name == "signal", !content.exists { button.tap() }
                XCTAssertTrue(content.exists || content.waitForExistence(timeout: 3), name)
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                print("TAB_AUTOMATION round=\(round) page=\(name) seconds=\(elapsed)")
                XCTAssertTrue(app.buttons["root-tab-知识"].isHittable)
            }
            app.buttons["root-tab-知识"].tap()
            XCTAssertEqual(books.label, booksLabel)
            XCTAssertFalse(app.descendants(matching: .any)["knowledge-home-loading"].exists)
            app.buttons["root-tab-研究"].tap()
            XCTAssertFalse(app.descendants(matching: .any)["research-home-loading"].exists)
        }
        app.terminate()
    }

    func testRootPagesRemainResponsive() {
        executionTimeAllowance = 240
        let app = XCUIApplication()
        app.launchArguments = ["--today-world-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["root-tab-知识"].waitForExistence(timeout: 20))
        capture(app, name: "audit-today")
        let routes = ["情报，当前动态", "情报，当前动态", "研究", "知识", "今日"]
        for (index, label) in routes.enumerated() {
            let button = app.buttons[label].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), label)
            let start = Date()
            button.tap()
            XCTAssertTrue(app.buttons["root-tab-知识"].isHittable)
            print("PAGE_AUDIT switch \(index) \(label): \(Date().timeIntervalSince(start))s")
            if let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                let start = Date()
                scroll.swipeUp(velocity: .fast)
                scroll.swipeDown(velocity: .fast)
                print("PAGE_AUDIT scroll \(index): \(Date().timeIntervalSince(start))s")
            }
            capture(app, name: "audit-page-\(index)")
        }
        app.buttons["研究"].tap()
        let company = app.buttons["公司"].firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 5))
        company.tap()
        if let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable }) {
            scroll.swipeUp(velocity: .fast)
            scroll.swipeDown(velocity: .fast)
        }
        capture(app, name: "audit-company")
        XCTAssertTrue(app.buttons["root-tab-知识"].isHittable)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 90
    }

    func testZhihuRemainsResponsiveAfterRepeatedScrolling() throws {
        let app = try launchFeed("zhihu")
        try exerciseScrolling(app, source: "zhihu")
    }

    func testYouTubeRemainsResponsiveAfterRepeatedScrolling() throws {
        let app = try launchFeed("youtube")
        try exerciseScrolling(app, source: "youtube")
    }

    func testDouyinPresentsClosableDetailBeforeLoading() throws {
        let app = try launchFeed("douyin-hot")
        firstPost(in: feed(app, source: "douyin-hot")).tap()
        let close = app.buttons["关闭网页详情"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertTrue(close.isHittable)
        capture(app, name: "douyin-immediate-detail")
        close.tap()
        XCTAssertTrue(firstPost(in: feed(app, source: "douyin-hot")).isHittable)
        app.terminate()
    }

    func testWebFailureCanRetryAndClose() throws {
        let app = try launchFeed("douyin-hot", webURL: "https://127.0.0.1:65534/unavailable")
        firstPost(in: feed(app, source: "douyin-hot")).tap()
        XCTAssertTrue(app.buttons["关闭网页详情"].waitForExistence(timeout: 3))
        let error = app.staticTexts["网页暂时无法加载"]
        XCTAssertTrue(error.waitForExistence(timeout: 25))
        capture(app, name: "web-failure-before-retry")
        let retry = app.buttons["embedded-web-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(error.waitForExistence(timeout: 25))
        capture(app, name: "web-failure-retry")
        app.buttons["关闭网页详情"].tap()
        XCTAssertTrue(firstPost(in: feed(app, source: "douyin-hot")).isHittable)
        app.terminate()
    }

    func testZhihuKeepsPositionWhenSwitchingSources() throws {
        try exerciseSourceRoundtrip(source: "zhihu", title: "知乎", nextTitle: "雪球", rowPrefix: "feed-zhihu-question-")
    }

    func testXueqiuKeepsPositionWhenSwitchingSources() throws {
        try exerciseSourceRoundtrip(source: "xueqiu", title: "雪球", nextTitle: "Truth", rowPrefix: "feed-xueqiu-author-")
    }

    func testXueqiuSwitchesBetweenSubscribedAuthors() throws {
        let app = try launchFeed("xueqiu")
        defer { app.terminate() }
        let list = feed(app, source: "xueqiu")
        let selector = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "选择账号，当前")).firstMatch
        XCTAssertTrue(selector.waitForExistence(timeout: 10))
        selector.tap()
        let quietAuthor = app.buttons["feed-account-choice-rss:14"]
        let activeAuthor = app.buttons["feed-account-choice-rss:16"]
        XCTAssertTrue(quietAuthor.waitForExistence(timeout: 10))
        XCTAssertTrue(activeAuthor.exists)
        capture(app, name: "xueqiu-subscriptions")

        quietAuthor.tap()
        XCTAssertTrue(app.buttons["选择账号，当前大道无形我有型"].waitForExistence(timeout: 10))
        XCTAssertTrue(list.staticTexts["大道无形我有型"].firstMatch.waitForExistence(timeout: 15))

        selector.tap()
        activeAuthor.tap()
        XCTAssertTrue(app.buttons["选择账号，当前但斌"].waitForExistence(timeout: 10))
        XCTAssertTrue(list.staticTexts["但斌"].firstMatch.waitForExistence(timeout: 15))

        selector.tap()
        app.buttons["feed-account-all"].tap()
        XCTAssertTrue(app.buttons["选择账号，当前全部账号"].waitForExistence(timeout: 10))
        XCTAssertTrue(firstPost(in: list).waitForExistence(timeout: 15))
    }

    private func exerciseSourceRoundtrip(source: String, title: String, nextTitle: String, rowPrefix: String) throws {
        let app = try launchFeed(source)
        let list = feed(app, source: source)
        list.swipeUp()
        list.swipeUp()
        if app.staticTexts["这个频道暂时没有新内容"].exists {
            capture(app, name: source + "-refreshed-empty")
            throw XCTSkip("The live service replaced cached rows with an empty feed; position retention remains unverified")
        }
        let visiblePost = list.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", rowPrefix))
            .allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(visiblePost)
        let identifier = visiblePost?.identifier ?? ""
        app.swipeLeft()
        XCTAssertTrue(app.buttons["选择观点来源，当前" + nextTitle].waitForExistence(timeout: 8))
        app.swipeRight()
        XCTAssertTrue(app.buttons["选择观点来源，当前" + title].waitForExistence(timeout: 8))
        XCTAssertTrue(list.descendants(matching: .any)[identifier].firstMatch.isHittable)
        list.swipeDown()
        capture(app, name: source + "-source-roundtrip")
        app.terminate()
    }

    private func launchFeed(_ source: String, webURL: String? = nil) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--feed-preview"]
        app.launchEnvironment["AI_FEED_SOURCE"] = source
        app.launchEnvironment["AI_FEED_UI_FIXTURE"] = Self.fixture
        if let webURL { app.launchEnvironment["AI_EMBEDDED_WEB_TEST_URL"] = webURL }
        app.launch()
        let list = feed(app, source: source)
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        if !firstPost(in: list).waitForExistence(timeout: 20) {
            capture(app, name: source + "-data-prerequisite")
            if app.staticTexts["这个频道暂时没有新内容"].exists {
                throw XCTSkip("The live feed is empty; populated-feed scrolling remains unverified")
            }
            XCTFail("No usable post appeared in the feed")
        }
        return app
    }

    private static let fixture: String = {
        let sources = ["zhihu", "xueqiu", "youtube", "douyin-hot"]
        let posts = Dictionary(uniqueKeysWithValues: sources.enumerated().map { index, source in
            let rows: [[String: Any]] = (1...40).map { row in
                [
                    "id": index * 100 + row,
                    "source": source,
                    "title": "测试文章 \(row)",
                    "summary": "用于验证滚动、切换频道和打开详情的内容。",
                    "final_score": 8,
                    "post_link": "https://127.0.0.1:65534/article"
                ]
            }
            return (source, rows)
        })
        return String(decoding: try! JSONSerialization.data(withJSONObject: posts), as: UTF8.self)
    }()

    private func feed(_ app: XCUIApplication, source: String) -> XCUIElement {
        app.descendants(matching: .any)["feed-list-\(source)"].firstMatch
    }

    private func firstPost(in list: XCUIElement) -> XCUIElement {
        let posts = list.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "feed-post-"))
        // Rank labels share the article identifier, and a live delivery banner
        // can cover the first row. Exercise a visible article headline.
        return posts.allElementsBoundByIndex.first { $0.isHittable && $0.frame.width > 60 }
            ?? posts.firstMatch
    }

    private func exerciseScrolling(_ app: XCUIApplication, source: String) throws {
        let list = feed(app, source: source)
        for _ in 0..<3 {
            list.swipeUp(velocity: .fast)
            list.swipeUp(velocity: .fast)
            list.swipeDown(velocity: .fast)
            list.swipeDown(velocity: .fast)
        }
        XCTAssertEqual(app.state, .runningForeground)
        if app.staticTexts["这个频道暂时没有新内容"].exists {
            capture(app, name: source + "-refreshed-empty")
            throw XCTSkip("The live service returned an empty feed; populated-feed scrolling remains unverified")
        }
        XCTAssertTrue(firstPost(in: list).exists)
        capture(app, name: source + "-scroll-regression")
        app.terminate()
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
