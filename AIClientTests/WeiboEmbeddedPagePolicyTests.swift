import XCTest
@testable import AIServerClient

final class WeiboEmbeddedPagePolicyTests: XCTestCase {
    func testRestoresSessionForWeiboSearchLinks() throws {
        let url = try XCTUnwrap(URL(string: "https://s.weibo.com/weibo?q=test"))

        XCTAssertTrue(WeiboEmbeddedPagePolicy.shouldRestoreSession(for: url))
    }

    func testDoesNotRestoreWeiboSessionForUnrelatedLinks() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/search?q=test"))

        XCTAssertFalse(WeiboEmbeddedPagePolicy.shouldRestoreSession(for: url))
    }

    func testAnonymousWeiboEmptyResultRequiresAuthentication() throws {
        let url = try XCTUnwrap(
            URL(string: "https://m.weibo.cn/search?containerid=100103type%3D1%26q%3Dtest")
        )

        XCTAssertTrue(
            WeiboEmbeddedPagePolicy.requiresAuthentication(
                url: url,
                bodyText: "\n 这里还没有内容 \n"
            )
        )
    }

    func testWeiboPageWithResultsDoesNotRequireAuthentication() throws {
        let url = try XCTUnwrap(URL(string: "https://m.weibo.cn/search?q=test"))

        XCTAssertFalse(
            WeiboEmbeddedPagePolicy.requiresAuthentication(
                url: url,
                bodyText: "测试热搜 第一条微博内容"
            )
        )
    }

    func testLoginPageIsNeverReplacedByAuthenticationPrompt() throws {
        let url = try XCTUnwrap(URL(string: "https://passport.weibo.com/sso/signin"))

        XCTAssertFalse(
            WeiboEmbeddedPagePolicy.requiresAuthentication(
                url: url,
                bodyText: "这里还没有内容"
            )
        )
    }

    func testSessionCookieWithoutExpirationIsPersistedAfterLogin() throws {
        let cookie = try makeCookie(name: "WBPSESS", domain: ".weibo.com")

        XCTAssertTrue(
            WeiboEmbeddedPagePolicy.shouldPersistSession(
                cookies: [cookie],
                isLoggingOut: false
            )
        )
    }

    func testSinaSSOCookieIsRecognizedAsAuthenticatedSession() throws {
        let cookie = try makeCookie(name: "SUB", domain: ".sina.com.cn")

        XCTAssertTrue(WeiboEmbeddedPagePolicy.containsAuthenticatedSession(in: [cookie]))
    }

    func testLogoutNeverPersistsRemainingAuthenticationCookies() throws {
        let cookie = try makeCookie(name: "SUB", domain: ".weibo.cn")

        XCTAssertFalse(
            WeiboEmbeddedPagePolicy.shouldPersistSession(
                cookies: [cookie],
                isLoggingOut: true
            )
        )
    }

    func testUnrelatedCookieDoesNotCreateAuthenticatedSession() throws {
        let cookie = try makeCookie(name: "SUB", domain: ".example.com")

        XCTAssertFalse(WeiboEmbeddedPagePolicy.containsAuthenticatedSession(in: [cookie]))
    }

    func testSessionCookieSurvivesArchiveAndRestoreWithoutExpiration() throws {
        let cookie = try makeCookie(name: "WBPSESS", domain: ".weibo.com")
        let data = try XCTUnwrap(WeiboSessionCookieStore.archivedData(for: [cookie]))

        let restored = try XCTUnwrap(WeiboSessionCookieStore.restoredCookies(from: data).first)

        XCTAssertEqual(restored.name, cookie.name)
        XCTAssertEqual(restored.value, cookie.value)
        XCTAssertEqual(restored.domain, cookie.domain)
        XCTAssertNil(restored.expiresDate)
    }

    func testLogoutSuppressionBlocksStaleCookieWriteUntilNextLogin() throws {
        let suiteName = "weibo-session-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cookie = try makeCookie(name: "SUB", domain: ".weibo.com")

        WeiboSessionCookieStore.clear(defaults: defaults)
        WeiboSessionCookieStore.store(cookies: [cookie], defaults: defaults)

        XCTAssertNil(WeiboSessionCookieStore.storedCookiesData(defaults: defaults))

        WeiboSessionCookieStore.allowPersistence(defaults: defaults)
        WeiboSessionCookieStore.store(cookies: [cookie], defaults: defaults)

        XCTAssertNotNil(WeiboSessionCookieStore.storedCookiesData(defaults: defaults))
    }

    func testAvatarURLPersistsAcrossWebPageRecreationAndClearsOnLogout() throws {
        let suiteName = "weibo-avatar-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let avatarURL = try XCTUnwrap(URL(string: "https://tvax.example.com/avatar.jpg"))

        WeiboSessionCookieStore.allowPersistence(defaults: defaults)
        WeiboSessionCookieStore.store(avatarURL: avatarURL, defaults: defaults)

        XCTAssertEqual(WeiboSessionCookieStore.avatarURL(defaults: defaults), avatarURL)

        WeiboSessionCookieStore.clear(defaults: defaults)

        XCTAssertNil(WeiboSessionCookieStore.avatarURL(defaults: defaults))
    }

    func testNonHTTPAvatarURLIsNotPersisted() throws {
        let suiteName = "weibo-avatar-scheme-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let avatarURL = try XCTUnwrap(URL(string: "file:///tmp/avatar.jpg"))

        WeiboSessionCookieStore.allowPersistence(defaults: defaults)
        WeiboSessionCookieStore.store(avatarURL: avatarURL, defaults: defaults)

        XCTAssertNil(WeiboSessionCookieStore.avatarURL(defaults: defaults))
    }

    func testParsesLoggedInAccountUIDFromMobileConfig() throws {
        let data = try XCTUnwrap(#"{"ok":1,"data":{"login":true,"uid":"5224669593"}}"#.data(using: .utf8))

        XCTAssertEqual(WeiboAccountAPIParser.accountUID(from: data), "5224669593")
    }

    func testAnonymousMobileConfigHasNoAccountUID() throws {
        let data = try XCTUnwrap(#"{"ok":1,"data":{"login":false,"uid":0}}"#.data(using: .utf8))

        XCTAssertNil(WeiboAccountAPIParser.accountUID(from: data))
    }

    func testParsesPreferredAvatarFromMobileProfile() throws {
        let data = try XCTUnwrap(
            #"{"ok":1,"data":{"userInfo":{"screen_name":"测试账号","profile_image_url":"https://example.com/small.jpg","avatar_hd":"https://example.com/large.jpg"}}}"#
                .data(using: .utf8)
        )

        XCTAssertEqual(
            WeiboAccountAPIParser.profile(from: data),
            WeiboAccountProfile(
                displayName: "测试账号",
                avatarURL: try XCTUnwrap(URL(string: "https://example.com/large.jpg"))
            )
        )
    }

    private func makeCookie(name: String, domain: String) throws -> HTTPCookie {
        try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: domain,
                .name: name,
                .path: "/",
                .secure: "TRUE",
                .value: "test-value"
            ])
        )
    }
}
