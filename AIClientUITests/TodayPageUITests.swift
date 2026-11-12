import XCTest

final class TodayPageUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTodayShowsBalanceAndReportFromTheNormalTab() {
        let app = launch(report: Self.report)
        let balance = app.staticTexts["today-aliyun-balance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 12))
        XCTAssertEqual(balance.label, "¥123.45")
        XCTAssertEqual(app.staticTexts["today-model-cost"].label, "¥0.50")
        XCTAssertTrue(app.scrollViews["today-overview"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["today-app-update"].isHittable)

        let article = app.buttons["today-highlight-0"]
        XCTAssertTrue(article.waitForExistence(timeout: 8))
        article.tap()
        let close = app.buttons["today-detail-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["测试日报要闻"].exists)
        close.tap()
        XCTAssertTrue(article.waitForExistence(timeout: 8))
        XCTAssertTrue(balance.exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "today-report"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testTodayShowsBalanceWhenReportCannotLoad() {
        let app = launch(report: nil)
        XCTAssertTrue(app.scrollViews["today-status-scroll"].waitForExistence(timeout: 10))
        let balance = app.staticTexts["today-aliyun-balance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 10))
        XCTAssertEqual(balance.label, "¥123.45")
        XCTAssertTrue(app.buttons["today-app-update"].isHittable)
        XCTAssertFalse(app.scrollViews["today-overview"].exists)
    }

    private func launch(report: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--today-world-preview"]
        app.launchEnvironment["TODAY_BALANCE_TEST_RESPONSE"] = Self.balance
        if let report {
            app.launchEnvironment["TODAY_REPORT_TEST_RESPONSE"] = report
        } else {
            app.launchEnvironment["TODAY_REPORT_TEST_OFFLINE"] = "1"
        }
        app.launch()
        return app
    }

    private static let balance = #"""
    {
      "ok": true,
      "currency": "CNY",
      "availableAmount": "123.45",
      "usage": {
        "date": "2026-11-11", "yesterdayDate": "2026-11-10", "timezone": "Asia/Shanghai",
        "todayCostCny": 0.5, "yesterdayCostCny": 0.25
      }
    }
    """#

    private static let report = #"""
    {
      "date": "2026-11-10", "timezone": "Asia/Shanghai", "status": "succeeded",
      "stage": "done", "progress": 100, "source_count": 1, "post_count": 1,
      "total_tokens": 0, "cost_cny": 0,
      "report": {"final": {
        "status": "succeeded",
        "overview": {
          "headline": "测试日报",
          "highlights": [{"title":"测试日报要闻","text":"用于验证详情打开和返回。","system_keys":["altman"],"post_ids":[]}],
          "watch_items": []
        },
        "sections": [{
          "section_key": "technology", "section_name": "科技",
          "groups": [{
            "group_key": "ai", "group_name": "人工智能",
            "systems": [{
              "system_key": "altman", "system_name": "OpenAI", "headline": "测试公司动态",
              "signal_level": "normal", "facts": [], "source_keys": [], "source_names": [], "post_ids": []
            }]
          }]
        }]
      }}
    }
    """#
}
