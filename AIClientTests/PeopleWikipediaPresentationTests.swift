import Foundation
import XCTest
@testable import AIServerClient

final class PeopleWikipediaPresentationTests: XCTestCase {
    @MainActor
    func testEmptyDirectoryIsLoadedOnceAndSharedByConcurrentCallers() async {
        PeopleDirectoryURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PeopleDirectoryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let store = PeopleStore(baseURL: URL(string: "https://people-directory.test")!, session: session)

        async let warm: Void = store.load()
        async let visible: Void = store.load()
        _ = await (warm, visible)
        await store.load()

        XCTAssertTrue(store.hasLoadedDirectory)
        XCTAssertTrue(store.people.isEmpty)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(PeopleDirectoryURLProtocol.requestCount, 1)
        await store.load(force: true)
        XCTAssertEqual(PeopleDirectoryURLProtocol.requestCount, 2)
    }

    func testBuildsInternalWikipediaEntityOnlyForWikipediaLinks() throws {
        let person = SpecialPerson(
            id: "sam-altman",
            name: "Sam Altman",
            organization: "OpenAI",
            summary: "OpenAI 联合创始人兼 CEO"
        )
        let wikipedia = PersonSocialAccount(
            platform: "维基百科",
            handle: "萨姆·奥尔特曼",
            profileURLValue: "https://zh.wikipedia.org/wiki/萨姆·奥尔特曼"
        )
        let xAccount = PersonSocialAccount(
            platform: "X",
            handle: "@sama",
            profileURLValue: "https://x.com/sama"
        )

        let entity = try XCTUnwrap(
            PersonWikipediaPresentation.entity(for: person, account: wikipedia)
        )

        XCTAssertEqual(entity.term, "Sam Altman")
        XCTAssertEqual(entity.title, "萨姆·奥尔特曼")
        XCTAssertEqual(entity.url.host, "zh.wikipedia.org")
        XCTAssertNil(PersonWikipediaPresentation.entity(for: person, account: xAccount))
    }

    @MainActor
    func testPersonPushPreferencesRestoreIndependentSubscriptions() {
        let suiteName = "PersonPushNotificationManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["1605", "44196397"], forKey: "personPush.enabledPersonIDs")

        let manager = PersonPushNotificationManager(defaults: defaults)

        XCTAssertTrue(manager.isEnabled(for: "1605"))
        XCTAssertTrue(manager.isEnabled(for: "44196397"))
        XCTAssertFalse(manager.isEnabled(for: "missing"))
    }

    @MainActor
    func testFailedUnsubscribeRetriesOnNextLaunchWithNoEnabledPeople() async throws {
        let suiteName = "PersonPushNotificationManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PushSubscriptionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        PushSubscriptionURLProtocol.prepare(statusCodes: [503, 200])
        defaults.set(["1605"], forKey: "personPush.enabledPersonIDs")
        defaults.set(String(repeating: "ab", count: 32), forKey: "personPush.deviceToken")

        let manager = PersonPushNotificationManager(defaults: defaults, session: session)
        await manager.setEnabled(false, for: "1605")
        XCTAssertFalse(manager.isEnabled(for: "1605"))
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertEqual(PushSubscriptionURLProtocol.requests.count, 1)

        let restarted = PersonPushNotificationManager(defaults: defaults, session: session)
        await restarted.restoreRegistration()
        let afterSync = PersonPushNotificationManager(defaults: defaults, session: session)
        await afterSync.restoreRegistration()

        XCTAssertFalse(afterSync.isEnabled(for: "1605"))
        let requests = PushSubscriptionURLProtocol.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["POST", "POST"])
        XCTAssertEqual(requests.map { $0.url?.path }, Array(repeating: "/api/ios/v1/ios/push/subscriptions", count: 2))
    }

    @MainActor
    func testDisableAfterFailedTokenRotationRemovesBothPossibleRegistrations() async throws {
        let suiteName = "PersonPushNotificationManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PushSubscriptionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        let previous = String(repeating: "ab", count: 32)
        let replacement = String(repeating: "cd", count: 32)
        defaults.set(["1605"], forKey: "personPush.enabledPersonIDs")
        defaults.set(previous, forKey: "personPush.deviceToken")
        PushSubscriptionURLProtocol.prepare(statusCodes: [503, 503, 200, 200])

        let manager = PersonPushNotificationManager(defaults: defaults, session: session)
        await manager.didRegister(deviceToken: Data(repeating: 0xcd, count: 32))
        await manager.setEnabled(false, for: "1605")
        XCTAssertFalse(manager.isEnabled(for: "1605"))
        XCTAssertNotNil(manager.errorMessage)

        let restarted = PersonPushNotificationManager(defaults: defaults, session: session)
        await restarted.restoreRegistration()
        await restarted.restoreRegistration()

        let payloads = PushSubscriptionURLProtocol.payloads
        XCTAssertEqual(payloads.map(\.deviceToken), [replacement, previous, replacement, previous])
        XCTAssertEqual(payloads.map(\.enabled), [true, false, false, false])
    }
}

private final class PeopleDirectoryURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var count = 0

    static var requestCount: Int { lock.withLock { count } }
    static func reset() { lock.withLock { count = 0 } }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "people-directory.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.count += 1 }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"success":true,"users":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class PushSubscriptionURLProtocol: URLProtocol {
    struct Payload: Decodable {
        let deviceToken: String
        let enabled: Bool

        enum CodingKeys: String, CodingKey {
            case deviceToken = "device_token"
            case enabled
        }
    }

    private static let lock = NSLock()
    private static var received: [URLRequest] = []
    private static var receivedPayloads: [Payload] = []
    private static var statusCodes: [Int] = []

    static var requests: [URLRequest] { lock.withLock { received } }
    static var payloads: [Payload] { lock.withLock { receivedPayloads } }

    static func prepare(statusCodes: [Int]) {
        lock.withLock {
            received.removeAll()
            receivedPayloads.removeAll()
            self.statusCodes = statusCodes
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let payload = Self.requestBody(request).flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }
        let status = Self.lock.withLock {
            Self.received.append(request)
            if let payload { Self.receivedPayloads.append(payload) }
            return Self.statusCodes.isEmpty ? 500 : Self.statusCodes.removeFirst()
        }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func requestBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let capacity = 512
        var buffer = [UInt8](repeating: 0, count: capacity)
        while true {
            let count = stream.read(&buffer, maxLength: capacity)
            guard count >= 0 else { return nil }
            guard count > 0 else { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
