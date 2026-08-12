import XCTest
@testable import AIServerClient

final class CityNewsTests: XCTestCase {
    func testEveryLevelHasIntroductionAndNews() {
        assertContent(in: CityNewsMockData.root)
    }

    func testHierarchyDrillsFromProvinceToCityToDistrict() {
        let path = CityNewsMockData.path(to: "shenzhen-0")

        XCTAssertEqual(path.map(\.name), ["广东省", "深圳市", "南山区"])
        XCTAssertEqual(path.map(\.level), [.province, .city, .district])
        XCTAssertTrue(path.last?.children.isEmpty == true)
    }

    func testParentLevelsExposeTheExpectedNextLevel() throws {
        let root = CityNewsMockData.root
        let province = try XCTUnwrap(root.children.first { $0.id == "guangdong" })
        let city = try XCTUnwrap(province.children.first { $0.id == "shenzhen" })

        XCTAssertTrue(root.children.allSatisfy { $0.level == .province })
        XCTAssertTrue(province.children.allSatisfy { $0.level == .city })
        XCTAssertTrue(city.children.allSatisfy { $0.level == .district })
    }

    private func assertContent(in region: CityRegion, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(region.introduction.isEmpty, "\(region.name) 缺少简介", file: file, line: line)
        XCTAssertFalse(region.facts.isEmpty, "\(region.name) 缺少事实标签", file: file, line: line)
        XCTAssertFalse(region.news.isEmpty, "\(region.name) 缺少新闻", file: file, line: line)
        region.children.forEach { assertContent(in: $0, file: file, line: line) }
    }
}
