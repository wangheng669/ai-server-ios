import Foundation
import Observation

struct LearningService {
    static let catalogURL = URL(string: "https://www.futunn.com/learn/wiki")!

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            configuration.urlCache = .shared
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetchCatalog() async throws -> LearningCatalog {
        var request = URLRequest(url: Self.catalogURL)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw LearningError.invalidResponse
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw LearningError.invalidEncoding
        }
        let catalog = Self.parseCatalog(html)
        guard !catalog.sections.isEmpty else {
            throw LearningError.emptyCatalog
        }
        return catalog
    }

    static func parseCatalog(_ html: String) -> LearningCatalog {
        let sectionPattern = #"<div\b[^>]*class="[^"]*\btopic-layout\b[^"]*"[^>]*>.*?<h2\b[^>]*class="[^"]*\btopic-layout__main-title\b[^"]*"[^>]*>(.*?)</h2>.*?<ul\b[^>]*class="[^"]*\bresize-box\b[^"]*"[^>]*>(.*?)</ul>"#
        let sections = matches(pattern: sectionPattern, in: html).compactMap { match -> LearningSection? in
            guard match.count >= 3 else { return nil }
            let name = normalizedText(match[1])
            guard !name.isEmpty else { return nil }
            let topics = parseTopics(match[2], category: name)
            return topics.isEmpty ? nil : LearningSection(name: name, topics: topics)
        }
        return LearningCatalog(sections: sections)
    }

    private static func parseTopics(_ html: String, category: String) -> [LearningTopic] {
        let linkPattern = #"<a\b([^>]*class="[^"]*\bwiki-topic-item\b[^"]*"[^>]*)>(.*?)</a>"#
        return matches(pattern: linkPattern, in: html).compactMap { match in
            guard match.count >= 3,
                  let href = attribute("href", in: match[1]),
                  let url = URL(string: decodeEntities(href)),
                  url.host?.hasSuffix("futunn.com") == true,
                  let titleHTML = firstCapture(
                    pattern: #"<h3\b[^>]*class="[^"]*\bwiki-topic-item__wiki-title\b[^"]*"[^>]*>(.*?)</h3>"#,
                    in: match[2]
                  ) else {
                return nil
            }
            let title = normalizedText(titleHTML)
            guard !title.isEmpty else { return nil }
            let summary = firstCapture(
                pattern: #"<p\b[^>]*class="[^"]*\bwiki-topic-item__wiki-intro\b[^"]*"[^>]*>(.*?)</p>"#,
                in: match[2]
            ).map(normalizedText) ?? ""
            return LearningTopic(title: title, summary: summary, url: url, category: category)
        }
    }

    private static func matches(pattern: String, in value: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let source = value as NSString
        let range = NSRange(location: 0, length: source.length)
        return regex.matches(in: value, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                let itemRange = match.range(at: index)
                return itemRange.location == NSNotFound ? "" : source.substring(with: itemRange)
            }
        }
    }

    private static func firstCapture(pattern: String, in value: String) -> String? {
        matches(pattern: pattern, in: value).first.flatMap { $0.count > 1 ? $0[1] : nil }
    }

    private static func attribute(_ name: String, in value: String) -> String? {
        firstCapture(
            pattern: #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*["']([^"']+)["']"#,
            in: value
        )
    }

    private static func normalizedText(_ value: String) -> String {
        let withoutTags = value.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        return decodeEntities(withoutTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ value: String) -> String {
        var result = value
        let entities = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " "
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}
@MainActor
@Observable
final class LearningStore {
    private(set) var catalog: LearningCatalog?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let service: LearningService

    init(service: LearningService = LearningService()) {
        self.service = service
    }

    func load(force: Bool = false) async {
        guard force || catalog == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            catalog = try await service.fetchCatalog()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum LearningError: LocalizedError {
    case invalidResponse
    case invalidEncoding
    case emptyCatalog

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "富途学习页面暂时无法访问"
        case .invalidEncoding:
            "富途学习页面格式暂时无法识别"
        case .emptyCatalog:
            "暂时没有读取到投资课程"
        }
    }
}
