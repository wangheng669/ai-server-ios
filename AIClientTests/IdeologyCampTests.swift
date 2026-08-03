import XCTest
@testable import AIServerClient

final class IdeologyCampTests: XCTestCase {
    func testClassifiesPeopleFromServerManagedFocusTags() throws {
        let loyalist = try decodePerson(name: "王冰冰", tag: "忠臣")
        let rebel = try decodePerson(name: "王志安", tag: "反贼")

        XCTAssertEqual(IdeologyCamp(person: loyalist), .loyalist)
        XCTAssertEqual(IdeologyCamp(person: rebel), .rebel)
    }

    func testLeavesPeopleWithoutCampTagUnassigned() throws {
        let person = try decodePerson(name: "待整理人物", tag: "媒体观察")

        XCTAssertNil(IdeologyCamp(person: person))
    }

    func testUsesNeutralDisplayTitles() {
        XCTAssertEqual(IdeologyCamp.loyalist.title, "赢")
        XCTAssertEqual(IdeologyCamp.rebel.title, "输")
    }

    func testUsesNeutralTitlesInPersonDetailsWithoutChangingServerTags() throws {
        let person = try decodePerson(name: "王冰冰", tag: "忠臣")

        XCTAssertEqual(person.focusTags.first, "忠臣")
        XCTAssertEqual(person.displayFocusTags.first, "赢")
    }

    private func decodePerson(name: String, tag: String) throws -> SpecialPerson {
        let data = Data(
            """
            {
              "user_id": "curated:test",
              "user_name": "\(name)",
              "topic": "ideology",
              "focus_tags": ["\(tag)", "公共议题"],
              "today_count": 0,
              "total_count": 0
            }
            """.utf8
        )
        return try JSONDecoder().decode(SpecialPerson.self, from: data)
    }
}
