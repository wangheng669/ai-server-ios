import Foundation

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

    static func containsAuthenticatedSession(in cookies: [HTTPCookie]) -> Bool {
        cookies.contains { cookie in
            authenticationCookieNames.contains(cookie.name) && isWeiboCookieDomain(cookie.domain)
        }
    }

    static func shouldPersistSession(cookies: [HTTPCookie], isLoggingOut: Bool) -> Bool {
        !isLoggingOut && containsAuthenticatedSession(in: cookies)
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
