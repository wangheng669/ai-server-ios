import XCTest
@testable import AIServerClient

final class ServerAddressValidatorTests: XCTestCase {
    func testNetworkErrorsUseActionableChineseMessages() {
        XCTAssertEqual(
            NetworkErrorPresentation.message(for: URLError(.secureConnectionFailed)),
            "安全连接失败，请检查 VPN 或代理设置后重试"
        )
        XCTAssertEqual(
            NetworkErrorPresentation.message(for: URLError(.timedOut)),
            "连接超时，请稍后重试"
        )
    }

    func testRejectsHTTPServerAddress() {
        XCTAssertFalse(ServerAddressValidator.isValid("http://127.0.0.1:8000"))
    }

    func testRejectsAddressWithoutScheme() {
        XCTAssertFalse(ServerAddressValidator.isValid("127.0.0.1:8000"))
    }

    func testRejectsUnsupportedScheme() {
        XCTAssertFalse(ServerAddressValidator.isValid("ftp://example.com"))
    }

    func testAcceptsProductionServerAddress() {
        XCTAssertTrue(ServerAddressValidator.isValid("https://api.wanghengai.xin/"))
    }

    func testNormalizesTrailingRootSlash() {
        XCTAssertEqual(
            ServerAddressValidator.normalizedURL("https://api.wanghengai.xin/")?.absoluteString,
            "https://api.wanghengai.xin"
        )
    }
}
