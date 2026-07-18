import XCTest
@testable import AIServerClient

final class ServerAddressValidatorTests: XCTestCase {
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
