import XCTest
@testable import AIServerClient

final class CityNewsTests: XCTestCase {
    func testHierarchyDrillsFromProvinceToCityToDistrict() {
        let path = CityRegions.path(to: 440305)

        XCTAssertEqual(path.map(\.name), ["广东省", "深圳市", "南山区"])
        XCTAssertEqual(path.map(\.level), [.province, .city, .district])
        XCTAssertTrue(path.last?.children.isEmpty == true)
    }

    func testParentLevelsExposeTheExpectedNextLevel() throws {
        let root = CityRegions.root
        let province = try XCTUnwrap(root.children.first { $0.adcode == 440000 })
        let city = try XCTUnwrap(province.children.first { $0.adcode == 440300 })

        XCTAssertTrue(root.children.allSatisfy { $0.level == .province })
        XCTAssertTrue(province.children.allSatisfy { $0.level == .city })
        XCTAssertTrue(city.children.allSatisfy { $0.level == .district })
    }

    func testGuangdongExposesAllPrefectureLevelCities() throws {
        let guangdong = try XCTUnwrap(CityRegions.path(to: 440000).last)

        XCTAssertEqual(guangdong.children.count, 21)
        XCTAssertEqual(Set(guangdong.children.map(\.adcode)).count, 21)
        XCTAssertNotNil(guangdong.children.first { $0.adcode == 440100 })
        XCTAssertNotNil(guangdong.children.first { $0.adcode == 440300 })
        XCTAssertNotNil(guangdong.children.first { $0.adcode == 441900 })
        XCTAssertNotNil(guangdong.children.first { $0.adcode == 440400 })
    }

    func testEveryRegionHasRealAdministrativeGeometry() {
        XCTAssertGreaterThan(CityRegions.root.children.count, 30)
        assertGeometry(in: CityRegions.root)
    }

    func testMapProjectionUsesTheSameOutlineForDrawingAndHitTesting() throws {
        let payload = Data(#"""
        {
          "properties":{"adcode":1,"name":"Test","level":"city"},
          "geometry":{"type":"Polygon","coordinates":[
            [[0,0],[10,0],[10,10],[0,10],[0,0]],
            [[4,4],[6,4],[6,6],[4,6],[4,4]]
          ]}
        }
        """#.utf8)
        let feature = try JSONDecoder().decode(CityMapFeature.self, from: payload)
        let projection = CityMapProjection(features: [feature], size: CGSize(width: 200, height: 100))
        XCTAssertEqual(projection.point(for: [5, 5]), CGPoint(x: 100, y: 50))
        XCTAssertTrue(projection.contains(projection.point(for: [2, 5]), in: feature))
        XCTAssertFalse(projection.contains(projection.point(for: [5, 5]), in: feature))
        XCTAssertFalse(projection.contains(projection.point(for: [-1, 5]), in: feature))
    }

    func testJourneyDrillsInPlaceAndGoesBackOneLevelAtATime() throws {
        let guangdong = try XCTUnwrap(CityRegions.path(to: 440000).last)
        let shenzhen = try XCTUnwrap(CityRegions.path(to: 440300).last)
        var journey = CityRegionJourney()

        XCTAssertTrue(journey.enter(guangdong))
        XCTAssertTrue(journey.enter(shenzhen))
        XCTAssertEqual(journey.current.id, "440300")
        XCTAssertEqual(journey.path.map(\.id), ["440000", "440300"])
        XCTAssertEqual(journey.parent?.name, "广东省")

        XCTAssertTrue(journey.goBack())
        XCTAssertEqual(journey.current.id, "440000")
        XCTAssertEqual(journey.path.map(\.id), ["440000"])

        XCTAssertTrue(journey.goBack())
        XCTAssertEqual(journey.current.id, "100000")
        XCTAssertFalse(journey.canGoBack)
        XCTAssertFalse(journey.goBack())
    }

    func testJourneyRejectsInvalidOrRepeatedDrillDown() throws {
        let guangdong = try XCTUnwrap(CityRegions.path(to: 440000).last)
        let zhejiang = try XCTUnwrap(CityRegions.path(to: 330000).last)
        let district = try XCTUnwrap(CityRegions.path(to: 440305).last)
        var journey = CityRegionJourney()

        XCTAssertFalse(journey.enter(district))
        XCTAssertTrue(journey.enter(guangdong))
        XCTAssertFalse(journey.enter(guangdong))
        XCTAssertFalse(journey.enter(zhejiang))
        XCTAssertEqual(journey.path.map(\.id), ["440000"])
    }

    func testDistrictCanSwitchToASiblingWithoutAddingAnotherLevel() throws {
        var journey = CityRegionJourney(path: CityRegions.path(to: 440305))
        let futian = try XCTUnwrap(CityRegions.path(to: 440304).last)

        XCTAssertEqual(journey.mapScope.name, "深圳市")
        XCTAssertTrue(Set(journey.mapRegions.map(\.name)).isSuperset(of: ["南山区", "福田区", "罗湖区", "宝安区"]))
        XCTAssertEqual(journey.selectedMapRegionID, "440305")
        XCTAssertTrue(journey.selectPeer(futian))
        XCTAssertEqual(journey.current.name, "福田区")
        XCTAssertEqual(journey.path.map(\.id), ["440000", "440300", "440304"])
        XCTAssertEqual(journey.mapScope.name, "深圳市")
        XCTAssertEqual(journey.selectedMapRegionID, "440304")
        XCTAssertFalse(journey.selectPeer(futian))
    }

    func testTerminalCityKeepsProvinceMapAvailable() throws {
        let guangdong = try XCTUnwrap(CityRegions.path(to: 440000).last)
        let foshan = try XCTUnwrap(CityRegions.path(to: 440600).last)
        var journey = CityRegionJourney(path: [guangdong])

        XCTAssertTrue(foshan.children.isEmpty)
        XCTAssertTrue(journey.enter(foshan))
        XCTAssertEqual(journey.current.id, "440600")
        XCTAssertEqual(journey.mapScope.id, "440000")
        XCTAssertEqual(journey.selectedMapRegionID, "440600")
        XCTAssertEqual(journey.mapRegions.count, 21)
    }

    func testMapScopeOnlyChangesWhenTheGeographicViewportChanges() throws {
        let guangdong = try XCTUnwrap(CityRegions.path(to: 440000).last)
        let shenzhen = try XCTUnwrap(CityRegions.path(to: 440300).last)
        let nanshan = try XCTUnwrap(CityRegions.path(to: 440305).last)
        var journey = CityRegionJourney()

        XCTAssertEqual(journey.mapScope.id, "100000")
        XCTAssertTrue(journey.enter(guangdong))
        XCTAssertEqual(journey.mapScope.id, "440000")
        XCTAssertTrue(journey.enter(shenzhen))
        XCTAssertEqual(journey.mapScope.id, "440300")
        XCTAssertTrue(journey.enter(nanshan))
        XCTAssertEqual(journey.mapScope.id, "440300")
        XCTAssertEqual(journey.selectedMapRegionID, nanshan.id)
        XCTAssertTrue(journey.goBack())
        XCTAssertEqual(journey.mapScope.id, "440300")
        XCTAssertNil(journey.selectedMapRegionID)
    }

    private func assertGeometry(in region: CityRegion, file: StaticString = #filePath, line: UInt = #line) {
        let features = CityMapRepository.shared.features(for: region)
        XCTAssertEqual(
            Set(features.map(\.id)),
            Set(region.children.map(\.adcode)),
            "\(region.name) 的下级入口与地图边界不匹配",
            file: file,
            line: line
        )
        XCTAssertTrue(
            region.children.allSatisfy { $0.parentAdcode == region.adcode && !$0.name.isEmpty },
            "\(region.name) 的下级行政区信息缺失",
            file: file,
            line: line
        )

        region.children.forEach { assertGeometry(in: $0, file: file, line: line) }
    }
}
