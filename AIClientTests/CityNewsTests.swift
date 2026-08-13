import XCTest
@testable import AIServerClient

final class CityNewsTests: XCTestCase {
    func testEveryLevelHasIntroductionAndNews() {
        assertContent(in: CityNewsMockData.root)
    }

    func testHierarchyDrillsFromProvinceToCityToDistrict() {
        let path = CityNewsMockData.path(to: "shenzhen-440305")

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

    func testEveryRegionHasRealAdministrativeGeometry() {
        assertGeometry(in: CityNewsMockData.root)
    }

    func testJourneyDrillsInPlaceAndReturnsToAnyAncestor() throws {
        let guangdong = try XCTUnwrap(CityNewsMockData.region(withID: "guangdong"))
        let shenzhen = try XCTUnwrap(CityNewsMockData.region(withID: "shenzhen"))
        var journey = CityRegionJourney()

        XCTAssertTrue(journey.enter(guangdong))
        XCTAssertTrue(journey.enter(shenzhen))
        XCTAssertEqual(journey.current.id, "shenzhen")
        XCTAssertEqual(journey.regionIDs, ["guangdong", "shenzhen"])
        XCTAssertEqual(journey.trail.map(\.name), ["全国", "广东省", "深圳市"])

        XCTAssertTrue(journey.returnTo(guangdong))
        XCTAssertEqual(journey.current.id, "guangdong")
        XCTAssertEqual(journey.regionIDs, ["guangdong"])

        XCTAssertTrue(journey.returnTo(CityNewsMockData.root))
        XCTAssertEqual(journey.current.id, "china")
        XCTAssertFalse(journey.canGoBack)
    }

    func testJourneyRejectsInvalidOrRepeatedDrillDown() throws {
        let guangdong = try XCTUnwrap(CityNewsMockData.region(withID: "guangdong"))
        let zhejiang = try XCTUnwrap(CityNewsMockData.region(withID: "zhejiang"))
        let district = try XCTUnwrap(CityNewsMockData.region(withID: "shenzhen-440305"))
        var journey = CityRegionJourney()

        XCTAssertFalse(journey.enter(district))
        XCTAssertTrue(journey.enter(guangdong))
        XCTAssertFalse(journey.enter(guangdong))
        XCTAssertFalse(journey.enter(zhejiang))
        XCTAssertEqual(journey.regionIDs, ["guangdong"])
    }

    func testDistrictCanSwitchToASiblingWithoutAddingAnotherLevel() throws {
        var journey = CityRegionJourney(path: CityNewsMockData.path(to: "shenzhen-440305"))
        let futian = try XCTUnwrap(CityNewsMockData.region(withID: "shenzhen-440304"))

        XCTAssertEqual(journey.mapScope.name, "深圳市")
        XCTAssertEqual(journey.mapRegions.map(\.name), ["南山区", "福田区", "罗湖区", "宝安区"])
        XCTAssertEqual(journey.selectedMapRegionID, "shenzhen-440305")
        XCTAssertTrue(journey.selectPeer(futian))
        XCTAssertEqual(journey.current.name, "福田区")
        XCTAssertEqual(journey.regionIDs, ["guangdong", "shenzhen", "shenzhen-440304"])
        XCTAssertEqual(journey.mapScope.name, "深圳市")
        XCTAssertEqual(journey.selectedMapRegionID, "shenzhen-440304")
        XCTAssertFalse(journey.selectPeer(futian))
    }

    func testMapScopeOnlyChangesWhenTheGeographicViewportChanges() throws {
        let guangdong = try XCTUnwrap(CityNewsMockData.region(withID: "guangdong"))
        let shenzhen = try XCTUnwrap(CityNewsMockData.region(withID: "shenzhen"))
        let nanshan = try XCTUnwrap(CityNewsMockData.region(withID: "shenzhen-440305"))
        var journey = CityRegionJourney()

        XCTAssertEqual(journey.mapScope.id, "china")
        XCTAssertTrue(journey.enter(guangdong))
        XCTAssertEqual(journey.mapScope.id, "guangdong")
        XCTAssertTrue(journey.enter(shenzhen))
        XCTAssertEqual(journey.mapScope.id, "shenzhen")
        XCTAssertTrue(journey.enter(nanshan))
        XCTAssertEqual(journey.mapScope.id, "shenzhen")
        XCTAssertEqual(journey.selectedMapRegionID, nanshan.id)
        XCTAssertTrue(journey.goBack())
        XCTAssertEqual(journey.mapScope.id, "shenzhen")
        XCTAssertNil(journey.selectedMapRegionID)
    }

    private func assertContent(in region: CityRegion, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(region.introduction.isEmpty, "\(region.name) 缺少简介", file: file, line: line)
        XCTAssertFalse(region.facts.isEmpty, "\(region.name) 缺少事实标签", file: file, line: line)
        XCTAssertFalse(region.news.isEmpty, "\(region.name) 缺少新闻", file: file, line: line)
        region.children.forEach { assertContent(in: $0, file: file, line: line) }
    }

    private func assertGeometry(in region: CityRegion, file: StaticString = #filePath, line: UInt = #line) {
        let features = CityMapRepository.shared.features(for: region)
        XCTAssertFalse(features.isEmpty, "\(region.name) 缺少行政区边界", file: file, line: line)

        if region.level == .district {
            XCTAssertTrue(
                features.contains { $0.id == region.adcode },
                "\(region.name) 未出现在所属城市地图中",
                file: file,
                line: line
            )
        } else {
            let featureAdcodes = Set(features.map(\.id))
            XCTAssertTrue(
                region.children.allSatisfy { featureAdcodes.contains($0.adcode) },
                "\(region.name) 的下级入口与地图边界不匹配",
                file: file,
                line: line
            )
        }

        region.children.forEach { assertGeometry(in: $0, file: file, line: line) }
    }
}
