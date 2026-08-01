import XCTest
@testable import AIServerClient

final class PeopleWikipediaPresentationTests: XCTestCase {
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
    func testPersonPushPreferencesMigrateLegacySamAltmanSetting() {
        let suiteName = "PersonPushNotificationManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "personPush.samAltman.enabled")

        let manager = PersonPushNotificationManager(defaults: defaults)

        XCTAssertTrue(manager.isEnabled(for: "1605"))
        XCTAssertEqual(defaults.stringArray(forKey: "personPush.enabledPersonIDs"), ["1605"])
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
}
