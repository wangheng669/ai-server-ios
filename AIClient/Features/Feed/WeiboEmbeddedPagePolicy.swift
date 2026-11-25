import Foundation

struct WeiboAccountProfile: Decodable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "screen_name"
    }
}

enum WeiboAccountAPI {
    static let accountPage = URL(string: "https://m.weibo.cn/me")!
    private static let profileURL = URL(string: "https://m.weibo.cn/api/users/show")!

    private struct Response: Decodable {
        let ok: Int
        let data: WeiboAccountProfile?
    }

    static func isAccountPage(_ url: URL?) -> Bool {
        url?.scheme == accountPage.scheme && url?.host == accountPage.host && url?.path == accountPage.path
    }

    static func currentProfile(cookies: [HTTPCookie]) async -> WeiboAccountProfile? {
        let configuration = URLSessionConfiguration.ephemeral
        let cookieStorage = configuration.httpCookieStorage
        cookieStorage?.setCookies(cookies, for: profileURL, mainDocumentURL: accountPage)
        let session = URLSession(configuration: configuration, delegate: ProfileRequestDelegate(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: profileURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(accountPage.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("1", forHTTPHeaderField: "MWeibo-Pwa")
        if let token = cookieStorage?.cookies(for: profileURL)?.first(where: { $0.name == "XSRF-TOKEN" }) {
            request.setValue(token.value.removingPercentEncoding, forHTTPHeaderField: "X-XSRF-TOKEN")
        }

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONDecoder().decode(Response.self, from: data),
              result.ok > 0 else { return nil }
        return result.data
    }

    private final class ProfileRequestDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}

enum WeiboEmbeddedPagePolicy {
    private static let authenticationCookieNames: Set<String> = [
        "SUB", "SUBP", "SCF", "WBPSESS", "SSOLoginState"
    ]

    static let bodyTextJavaScript = #"""
    (document.body?.innerText || '').replace(/\s+/g, ' ').trim()
    """#

    static func shouldRestoreSession(for url: URL) -> Bool {
        isWeiboHost(url.host)
    }

    static func requiresAuthentication(url: URL?, bodyText: String) -> Bool {
        guard let url,
              isWeiboHost(url.host),
              !isAuthenticationURL(url) else { return false }

        let normalized = bodyText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.contains("这里还没有内容")
    }

    static func authenticationCookies(in cookies: [HTTPCookie]) -> [HTTPCookie] {
        cookies.filter { cookie in
            authenticationCookieNames.contains(cookie.name)
                && !cookie.value.isEmpty
                && (cookie.expiresDate ?? .distantFuture) > .now
                && isWeiboCookieDomain(cookie.domain)
        }
    }

    private static func isWeiboHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "weibo.com"
            || host.hasSuffix(".weibo.com")
            || host == "weibo.cn"
            || host.hasSuffix(".weibo.cn")
    }

    private static func isWeiboCookieDomain(_ domain: String) -> Bool {
        let normalized = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalized == "weibo.com"
            || normalized.hasSuffix(".weibo.com")
            || normalized == "weibo.cn"
            || normalized.hasSuffix(".weibo.cn")
            || normalized == "sina.com.cn"
            || normalized.hasSuffix(".sina.com.cn")
    }

    private static func isAuthenticationURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        if host == "passport.weibo.com" || host.hasSuffix(".passport.weibo.com") { return true }
        if host == "passport.weibo.cn" || host.hasSuffix(".passport.weibo.cn") { return true }
        let path = url.path.lowercased()
        return path.contains("login") || path.contains("signin")
    }
}
