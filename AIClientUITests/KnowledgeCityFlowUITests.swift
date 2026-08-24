import XCTest

final class KnowledgeCityFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCityLivesInsideKnowledgeSheetAndNotRootNavigation() {
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

        let knowledgeTab = app.buttons["root-tab-知识"]
        XCTAssertTrue(knowledgeTab.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["今日"].exists)
        XCTAssertTrue(app.buttons["情报，当前动态"].exists)
        XCTAssertTrue(app.buttons["研究，当前数据"].exists)
        XCTAssertFalse(app.buttons["城市"].exists)

        let cityEntry = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "城市观察")
        ).firstMatch
        XCTAssertTrue(cityEntry.waitForExistence(timeout: 8))
        cityEntry.tap()

        let citySheet = app.scrollViews["city-region-screen"].firstMatch
        XCTAssertTrue(citySheet.waitForExistence(timeout: 5))
        let citySheetTitle = app.staticTexts.matching(identifier: "city-region-screen").firstMatch
        XCTAssertTrue(citySheetTitle.exists)
        XCTAssertFalse(cityEntry.isHittable)

        citySheetTitle.swipeDown()
        XCTAssertTrue(cityEntry.waitForExistence(timeout: 5))
        XCTAssertTrue(citySheet.waitForNonExistence(timeout: 5))
    }
}
