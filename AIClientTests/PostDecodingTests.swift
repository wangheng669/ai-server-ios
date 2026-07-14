import XCTest
@testable import AIServerClient

final class PostDecodingTests: XCTestCase {
    func testDecodesPostListResponse() throws {
        let json = #"""
        {
          "data": [{
            "id": 42,
            "title": "测试新闻",
            "summary": "摘要内容",
            "content_zh": "中文正文",
            "source": "rss:77",
            "formatted_time": "刚刚",
            "final_score": 8.6,
            "post_link": "https://example.com/post",
            "user": { "user_screen_name": "示例来源" },
            "postTags": [{ "id": 1, "name": "AI" }],
            "images": [{ "url": "https://example.com/image.jpg", "width": 1080, "height": 1350, "alt_text": "VCG/Getty Images" }],
            "meta": { "lang": "en", "urls": ["https://example.com/story"], "photo_credit": "VCG/Getty Images" }
          }]
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(PostListResponse.self, from: json)

        XCTAssertEqual(response.data.first?.id, 42)
        XCTAssertEqual(response.data.first?.authorName, "示例来源")
        XCTAssertEqual(response.data.first?.normalizedSource, "RSS")
        XCTAssertEqual(response.data.first?.score, 8.6)
        XCTAssertEqual(response.data.first?.displayTitle, "中文正文")
        XCTAssertEqual(response.data.first?.displayContent, "中文正文")
        XCTAssertEqual(response.data.first?.authorName, "示例来源")
        XCTAssertEqual(response.data.first?.photoCredit, "VCG/Getty Images")
        XCTAssertEqual(response.data.first?.externalURL?.absoluteString, "https://example.com/story")
    }

    func testDecodesDetailAndStripsHTML() throws {
        let json = #"{"post":{"id":7,"title":"标题","content":"<p>第一段</p><p>第二段</p>","images":[]}}"#.data(using: .utf8)!

        let response = try JSONDecoder().decode(PostDetailResponse.self, from: json)

        XCTAssertEqual(response.post.id, 7)
        XCTAssertTrue(response.post.displayContent.contains("第一段"))
        XCTAssertFalse(response.post.displayContent.contains("<p>"))
    }

    func testStripsEntityEncodedHTML() throws {
        let json = #"{"post":{"id":8,"content":"正文&amp;lt;img src=&amp;quot;https://example.com/a.jpg&amp;quot;&amp;gt;结尾"}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(PostDetailResponse.self, from: json)

        XCTAssertFalse(response.post.displayContent.contains("img src"))
        XCTAssertTrue(response.post.displayContent.contains("正文"))
        XCTAssertTrue(response.post.displayContent.contains("结尾"))
    }

    func testStripsTruncatedTrailingHTMLTag() throws {
        let json = #"{"success":true,"data":[{"id":47,"content":"正文<p><img src='image.jpg'/></p><p style='text-align: right; col...","source":"rss:47"}]}"#
        let response = try JSONDecoder().decode(PostListResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.data[0].displayContent, "正文")
    }

    func testExtractsCompleteNewYorkTimesArticleBody() throws {
        let html = """
        <section class="article-body">
          <div class="article-paragraph">第一段包含<strong>重点</strong>。</div>
          <div class="article-paragraph">第二段包含<a href="#">链接文字</a>。</div>
          <div class="article-paragraph">第三段。</div>
          <div class="article-paragraph">第四段是文章结尾。</div>
        </section>
        """
        XCTAssertEqual(
            NewYorkTimesArticleParser.extract(from: html),
            NewYorkTimesArticle(blocks: [
                .paragraph("第一段包含重点。"),
                .paragraph("第二段包含链接文字。"),
                .paragraph("第三段。"),
                .paragraph("第四段是文章结尾。")
            ])
        )
    }

    func testPreservesNewYorkTimesInlineImageOrderAndCaption() throws {
        let html = """
        <section class="article-body">
          <div class="article-paragraph">图片前正文。</div>
          <div class="article-paragraph"><figure><div class="img-box"><img src="preview.jpg" data-src="https://example.com/full.jpg" alt="图片说明"></div><figcaption><span>图片说明</span><cite>摄影署名</cite></figcaption></figure></div>
          <div class="article-paragraph">图片后正文。</div>
        </section>
        """
        XCTAssertEqual(
            NewYorkTimesArticleParser.extract(from: html),
            NewYorkTimesArticle(blocks: [
                .paragraph("图片前正文。"),
                .image(url: URL(string: "https://example.com/full.jpg")!, caption: "图片说明", credit: "摄影署名"),
                .paragraph("图片后正文。")
            ])
        )
    }
}
