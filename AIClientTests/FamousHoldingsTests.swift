import XCTest
@testable import AIServerClient

final class FamousHoldingsTests: XCTestCase {
    func testDecodesIndustryPanoramaContract() throws {
        let data = Data(
            """
            {
              "success": true,
              "data": {
                "version": "2026-07-28",
                "industries": [{
                  "id": "new-energy",
                  "title": "新能源汽车",
                  "subtitle": "电池 · 整车 · 补能",
                  "icon": "car.side.fill",
                  "scale": {
                    "value": "1,286.6万辆",
                    "metric": "新能源汽车销量",
                    "period": "2024年",
                    "growth": "+35.5% 同比",
                    "source": {
                      "name": "工业和信息化部",
                      "url": "https://www.miit.gov.cn/example"
                    }
                  },
                  "history": [
                    {"year": 2024, "value": 1286.6}
                  ],
                  "auto_sales": {
                    "period": "2024年完整年度",
                    "unit": "万辆",
                    "source": {"name": "中国汽车工业协会", "url": "https://www.caam.org.cn/"},
                    "monthly": [
                      {"period": "2024-12", "total_sales": 348.9, "nev_sales": 159.6, "total_yoy": 10.5, "nev_yoy": 34.0, "nev_penetration_rate": 45.7}
                    ]
                  },
                  "anchors": ["动力电池", "整车制造"],
                  "chain": [
                    {"id": "upstream", "level": "上游", "title": "材料", "items": ["锂矿"]},
                    {"id": "midstream", "level": "中游", "title": "制造", "items": ["动力电池"]},
                    {"id": "downstream", "level": "下游", "title": "服务", "items": ["充电桩"]}
                  ],
                  "companies": [{
                    "id": "byd",
                    "name": "比亚迪",
                    "role": "整车与电池",
                    "stage_id": "midstream",
                    "ticker": "002594.SZ"
                  }],
                  "insights": [
                    {"id": "sales", "title": "产销扩张", "detail": "产业规模保持扩张"}
                  ],
                  "provenance": ["工业和信息化部"]
                }]
              }
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(IndustryPanoramaResponse.self, from: data)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data.version, "2026-07-28")
        XCTAssertEqual(response.data.industries.first?.scale.metric, "新能源汽车销量")
        XCTAssertEqual(response.data.industries.first?.companies.first?.stageID, "midstream")
        XCTAssertEqual(response.data.industries.first?.chain.count, 3)
        XCTAssertEqual(response.data.industries.first?.autoSales?.monthly.first?.nevSales, 159.6)
        XCTAssertEqual(response.data.industries.first?.autoSales?.monthly.first?.nevPenetrationRate, 45.7)
    }

    func testDecodesFamousHoldingsContract() throws {
        let data = Data(#"{"success":true,"data":{"generatedAt":"2026-07-16T00:00:00Z","reportDate":"2026-03-31","periodLabel":"2026 Q1","disclaimer":"公开披露数据，非实时交易","summary":{"new":1,"increased":2,"decreased":3,"exited":4},"managers":[{"key":"ark","cik":"0001697748","displayName":"凯茜·伍德","institutionName":"ARK Investment Management","portraitUrl":"/img/sec13f/ark.webp","reportDate":"2026-03-31","filingDate":"2026-05-12","positionsCount":182,"totalValueUsd":12859485476,"summary":{"new":1,"increased":2,"decreased":3,"exited":4},"changesCount":1,"changes":[{"symbol":"TSLA","name":"Tesla Inc","companyLogo":"/img/company-logos/tsla.png","action":"decreased","previousWeightPct":9.1,"weightPct":7.4,"weightChangePct":-1.7,"valueUsd":1000}]}]}}"#.utf8)
        let response = try JSONDecoder().decode(FamousHoldingsResponse.self, from: data)
        XCTAssertEqual(response.data.periodLabel, "2026 Q1")
        XCTAssertEqual(response.data.managers.first?.changes.first?.action, .decreased)
        XCTAssertEqual(response.data.managers.first?.changes.first?.weightPct, 7.4)
        XCTAssertEqual(response.data.managers.first?.portraitUrl, "/img/sec13f/ark.webp")
    }
}

final class DeploymentStatusTests: XCTestCase {
    func testCreatesVisibleRunningSnapshot() throws {
        let message = DeploymentStatusMessage(
            type: "deployment-status",
            phase: "running",
            stage: "signing",
            progress: 0.82,
            commit: "1234567890",
            runId: "42",
            updatedAt: "2026-07-19T08:00:00Z"
        )
        let snapshot = try XCTUnwrap(DeploymentStatusSnapshot(message: message))
        XCTAssertEqual(snapshot.commit, "1234567")
        XCTAssertEqual(snapshot.progress, 0.82, accuracy: 0.001)
        XCTAssertTrue(snapshot.isVisible(at: snapshot.updatedAt.addingTimeInterval(300)))
    }

    func testHidesStaleCompletedSnapshot() throws {
        let message = DeploymentStatusMessage(
            type: "deployment-status",
            phase: "succeeded",
            stage: "installed",
            progress: 1,
            commit: "1234567",
            runId: nil,
            updatedAt: "2026-07-19T08:00:00Z"
        )
        let snapshot = try XCTUnwrap(DeploymentStatusSnapshot(message: message))
        XCTAssertFalse(snapshot.isVisible(at: snapshot.updatedAt.addingTimeInterval(700)))
    }

    func testCompletedSnapshotHasStablePerDeploymentIdentity() throws {
        let message = DeploymentStatusMessage(
            type: "deployment-status",
            phase: "succeeded",
            stage: "installed",
            progress: 1,
            commit: "1234567890",
            runId: "42",
            updatedAt: "2026-07-19T08:00:00Z"
        )

        let snapshot = try XCTUnwrap(DeploymentStatusSnapshot(message: message))

        XCTAssertEqual(snapshot.completionIdentity, "1234567-installed")
    }
}
