import XCTest

/// Integration regressions against the app's configured feed service.
/// Require populated feeds so an empty page cannot count as a scrolling pass.
final class FeedResponsivenessUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 90
    }

    func testZhihuRemainsResponsiveAfterRepeatedScrolling() {
        let app = launchFeed("zhihu")
        exerciseScrolling(app, source: "zhihu")
    }

    func testYouTubeRemainsResponsiveAfterRepeatedScrolling() {
        let app = launchFeed("youtube")
        exerciseScrolling(app, source: "youtube")
    }

    func testDouyinPresentsClosableDetailBeforeLoading() {
        let app = launchFeed("douyin-hot")
        firstPost(in: feed(app, source: "douyin-hot")).tap()
        let close = app.buttons["关闭网页详情"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertTrue(close.isHittable)
        capture(app, name: "douyin-immediate-detail")
        close.tap()
        XCTAssertTrue(firstPost(in: feed(app, source: "douyin-hot")).isHittable)
        app.terminate()
    }

    func testWebFailureCanRetryAndClose() {
        let app = launchFeed("douyin-hot", webURL: "https://127.0.0.1:65534/unavailable")
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

    func testZhihuKeepsPositionWhenSwitchingSources() {
        let app = launchFeed("zhihu")
        let list = feed(app, source: "zhihu")
        list.swipeUp()
        list.swipeUp()
        let visiblePost = list.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "feed-post-"))
            .allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(visiblePost)
        let identifier = visiblePost?.identifier ?? ""
        app.swipeLeft()
        XCTAssertTrue(app.buttons["选择观点来源，当前雪球"].waitForExistence(timeout: 8))
        app.swipeRight()
        XCTAssertTrue(app.buttons["选择观点来源，当前知乎"].waitForExistence(timeout: 8))
        XCTAssertTrue(list.descendants(matching: .any)[identifier].firstMatch.isHittable)
        list.swipeDown()
        capture(app, name: "zhihu-source-roundtrip")
        app.terminate()
    }

    private func launchFeed(_ source: String, webURL: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--feed-preview"]
        app.launchEnvironment["AI_FEED_SOURCE"] = source
        if let webURL { app.launchEnvironment["AI_EMBEDDED_WEB_TEST_URL"] = webURL }
        app.launch()
        let list = feed(app, source: source)
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        XCTAssertTrue(firstPost(in: list).waitForExistence(timeout: 20))
        return app
    }

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

    private func exerciseScrolling(_ app: XCUIApplication, source: String) {
        let list = feed(app, source: source)
        for _ in 0..<3 {
            list.swipeUp(velocity: .fast)
            list.swipeUp(velocity: .fast)
            list.swipeDown(velocity: .fast)
            list.swipeDown(velocity: .fast)
        }
        XCTAssertEqual(app.state, .runningForeground)
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
