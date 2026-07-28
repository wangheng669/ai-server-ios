import XCTest
@testable import AIServerClient

final class LearningServiceTests: XCTestCase {
    func testParsesAllSectionsAndTopics() throws {
        let html = """
        <div class="topic-layout">
          <h2 class="topic-layout__main-title main-title-color">股票</h2>
          <ul class="resize-box">
            <li><a href="https://www.futunn.com/learn/detail-pe" class="wiki-topic-item">
              <h3 class="wiki-topic-item__wiki-title">什么是市盈率？</h3>
              <p class="wiki-topic-item__wiki-intro">衡量上市公司估值的指标</p>
            </a></li>
          </ul>
        </div>
        <div class="topic-layout">
          <h2 class="topic-layout__main-title main-title-color">基金</h2>
          <ul class="resize-box">
            <li><a href="https://www.futunn.com/learn/detail-index-fund" class="wiki-topic-item">
              <h3 class="wiki-topic-item__wiki-title">什么是指数基金？</h3>
              <p class="wiki-topic-item__wiki-intro">跟踪指数的基金产品</p>
            </a></li>
          </ul>
        </div>
        """

        let catalog = LearningService.parseCatalog(html)

        XCTAssertEqual(catalog.sections.map(\.name), ["股票", "基金"])
        XCTAssertEqual(catalog.topicCount, 2)
        XCTAssertEqual(catalog.sections[0].topics[0].title, "什么是市盈率？")
        XCTAssertEqual(catalog.sections[0].topics[0].category, "股票")
        XCTAssertEqual(catalog.sections[1].topics[0].summary, "跟踪指数的基金产品")
    }

    func testIgnoresLinksOutsideFutu() {
        let html = """
        <div class="topic-layout">
          <h2 class="topic-layout__main-title">股票</h2>
          <ul class="resize-box">
            <li><a href="https://example.com/learn/detail" class="wiki-topic-item">
              <h3 class="wiki-topic-item__wiki-title">外部内容</h3>
              <p class="wiki-topic-item__wiki-intro">不应载入</p>
            </a></li>
          </ul>
        </div>
        """

        XCTAssertTrue(LearningService.parseCatalog(html).sections.isEmpty)
    }
}
