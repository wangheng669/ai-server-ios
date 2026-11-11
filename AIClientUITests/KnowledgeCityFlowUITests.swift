import XCTest

final class KnowledgeCityFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCityLivesInsideKnowledgeSheetAndNotRootNavigation() {
        let app = launchKnowledgeApp()

        let knowledgeTab = app.buttons["root-tab-知识"]
        XCTAssertTrue(knowledgeTab.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["今日"].exists)
        XCTAssertTrue(app.buttons["情报，当前动态"].exists)
        XCTAssertTrue(app.buttons["研究"].exists)
        XCTAssertFalse(app.buttons["城市"].exists)

        let cityEntry = app.buttons["knowledge-city-entry"]
        let knowledgeScroll = app.scrollViews["knowledge-home"]
        XCTAssertTrue(cityEntry.waitForExistence(timeout: 8))
        // An offscreen row can be reported hittable when only its top edge
        // is visible above the navigation bar. Reveal the actual tap target.
        for _ in 0..<6 where !cityEntry.isHittable || cityEntry.frame.midY >= knowledgeTab.frame.minY {
            knowledgeScroll.swipeUp()
        }
        XCTAssertTrue(cityEntry.isHittable)
        XCTAssertLessThan(cityEntry.frame.midY, knowledgeTab.frame.minY)
        cityEntry.tap()

        let citySheet = app.scrollViews["city-region-screen"].firstMatch
        XCTAssertTrue(citySheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["城市观察"].exists)
        XCTAssertTrue(app.staticTexts["广东省"].exists)
        let enterShenzhen = app.buttons["进入城市深圳市"]
        for _ in 0..<3 where !enterShenzhen.isHittable { citySheet.swipeUp() }
        XCTAssertTrue(enterShenzhen.isHittable)
        enterShenzhen.tap()
        XCTAssertEqual(app.staticTexts["city-current-title"].label, "深圳市")
        XCTAssertFalse(cityEntry.isHittable)

        let sheetHandle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        let dismissTarget = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        sheetHandle.press(forDuration: 0.1, thenDragTo: dismissTarget)
        XCTAssertTrue(citySheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(cityEntry.isHittable)
    }

    func testPeopleLivesInsideKnowledgeSheetAndNotRootNavigation() {
        let app = launchKnowledgeApp()

        XCTAssertTrue(app.buttons["root-tab-知识"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["研究"].exists)
        XCTAssertFalse(app.buttons["人物"].exists)

        let peopleEntry = app.buttons["knowledge-people-entry"]
        XCTAssertTrue(peopleEntry.waitForExistence(timeout: 8))
        for _ in 0..<6 where !peopleEntry.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(peopleEntry.isHittable)
        peopleEntry.tap()

        let peopleTitle = app.staticTexts["人物关系"]
        let peopleSearch = app.buttons["搜索人物"]
        XCTAssertTrue(peopleTitle.waitForExistence(timeout: 8))
        XCTAssertTrue(peopleSearch.exists)
        XCTAssertFalse(peopleEntry.isHittable)

        let sheetHandle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        let dismissTarget = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        sheetHandle.press(forDuration: 0.1, thenDragTo: dismissTarget)
        let entryIsHittable = NSPredicate(format: "isHittable == true")
        expectation(for: entryIsHittable, evaluatedWith: peopleEntry)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(peopleTitle.waitForNonExistence(timeout: 5))
    }

    func testFullReportExpandsSourcesInlineAndReturnsToList() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--today-world-preview"]
        app.launch()
        let details = app.buttons["today-all-groups"]
        guard details.waitForExistence(timeout: 30) else {
            add(XCTAttachment(screenshot: app.screenshot()))
            XCTAssertTrue(app.staticTexts["阿里云余额"].exists)
            throw XCTSkip("No published report available; report sources remain unverified")
        }
        for _ in 0..<6 where !details.isHittable { app.swipeUp() }
        details.tap()
        let row = app.buttons["yesterday-system-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        if todayDetail("公司动态", in: app).waitForExistence(timeout: 2) {
            app.scrollViews.buttons.firstMatch.tap()
        }
        let source = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today-source-")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 30))
        for _ in 0..<8 where !source.isHittable { app.swipeUp() }
        XCTAssertTrue(source.isHittable)
        source.tap()
        XCTAssertEqual(source.value as? String, "已展开")
        XCTAssertTrue(todayDetail("事件详情", in: app).exists)
        source.tap()
        XCTAssertEqual(source.value as? String, "已收起")
        closeTodayDetail(app)
        if todayDetail("公司动态", in: app).exists { closeTodayDetail(app) }
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(row.isHittable)
    }

    private func todayDetail(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.otherElements["today-detail-\(title)"]
    }

    private func closeTodayDetail(_ app: XCUIApplication) {
        let buttons = app.buttons.matching(identifier: "today-detail-close")
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 5))
        let close = buttons.allElementsBoundByIndex.last(where: { $0.isHittable })
        XCTAssertNotNil(close)
        close?.tap()
    }

    private func launchKnowledgeApp() -> XCUIApplication {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "系统权限") { alert in
            for title in ["允许", "不允许"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        app.launchArguments = ["--learning-preview"]
        app.launch()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.02)).tap()
        return app
    }
}
