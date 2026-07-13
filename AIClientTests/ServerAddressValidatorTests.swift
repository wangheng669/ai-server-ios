import XCTest
@testable import AIServerClient

final class ServerAddressValidatorTests: XCTestCase {
    func testAcceptsHTTPServerAddress() {
        XCTAssertTrue(ServerAddressValidator.isValid("http://127.0.0.1:8000"))
    }

    func testRejectsAddressWithoutScheme() {
        XCTAssertFalse(ServerAddressValidator.isValid("127.0.0.1:8000"))
    }

    func testRejectsUnsupportedScheme() {
        XCTAssertFalse(ServerAddressValidator.isValid("ftp://example.com"))
    }

    func testAcceptsProductionServerAddress() {
        XCTAssertTrue(ServerAddressValidator.isValid("http://47.100.175.141:3001/"))
    }

    func testNormalizesTrailingRootSlash() {
        XCTAssertEqual(
            ServerAddressValidator.normalizedURL("http://47.100.175.141:3001/")?.absoluteString,
            "http://47.100.175.141:3001"
        )
    }
}
