import XCTest
@testable import AIServerClient
final class GoogleSignalTests: XCTestCase {
    func testNewsUsesIOSProfileAndIndependentCompanyFilter() throws {
        let service = GoogleSignalService(baseURL: URL(string: "https://example.com")!)
        let url = try service.newsURL(company: "openai", sentiment: .uncertain, cursor: "next")
        XCTAssertEqual(url.path, "/api/ios/v1/company-news")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(query.contains(URLQueryItem(name: "company", value: "openai")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "sentiment", value: "uncertain")))
        XCTAssertFalse(query.contains { $0.name == "view" || $0.name == "fact_status" })
    }
    func testNewsDecodesWithoutEventEvidenceFields() throws {
        let raw = #"{"items":[{"id":8,"quote_content":"","reply_content":"","translation_post_id":18,"article_id":"123","source":"x","source_url":"https://x.com/i/status/123","title":"Original title","original_content":"Original body","content_zh":"译文","author_name":"Author","author_handle":"author","published_at":"2026-09-22T01:00:00Z","companies":{"google":"negative","openai":"positive","nvidia":"uncertain"},"sentiment":"positive"}],"has_more":false,"next_cursor":""}"#
        let page = try JSONDecoder().decode(CompanyNewsPage.self, from: Data(raw.utf8))
        XCTAssertEqual(page.items[0].originalContent, "Original body")
        XCTAssertEqual(page.items[0].companies["nvidia"], "uncertain")
        XCTAssertEqual(page.items[0].companies["google"], "negative")
        XCTAssertEqual(page.items[0].contentZH, "译文")
    }
    func testDateParsing() {
        XCTAssertNotNil(GoogleSignalDateParser.date(from: "2026-08-12T12:18:05.130556+08:00"))
        XCTAssertNotNil(GoogleSignalDateParser.date(from: "2026-08-12T08:18:08Z"))
    }
}
