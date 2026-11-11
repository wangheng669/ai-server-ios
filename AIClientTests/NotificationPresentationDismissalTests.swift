import XCTest
import SwiftUI
@testable import AIServerClient

@MainActor
final class NotificationPresentationDismissalTests: XCTestCase {
    func testDismissesSwiftUISheetAndClearsItsBindingBeforeRouting() async throws {
        let state = SheetState()
        let root = UIHostingController(rootView: SheetFixture(state: state))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        state.isPresented = true
        try await waitUntil { root.presentedViewController != nil }

        await NotificationPresentationDismissal.dismissPresentedContent(from: root)

        XCTAssertNil(root.presentedViewController)
        try await waitUntil { !state.isPresented }
        XCTAssertFalse(state.isPresented)
        state.isPresented = true
        try await waitUntil { root.presentedViewController != nil }
        await NotificationPresentationDismissal.dismissPresentedContent(from: root)
    }

    func testDismissesNestedPresentationsAndAllowsNextPresentation() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let root = UIViewController()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let sheet = UIViewController()
        await present(sheet, from: root)
        await present(UIViewController(), from: sheet)
        async let first: Void = NotificationPresentationDismissal.dismissPresentedContent(from: root)
        async let second: Void = NotificationPresentationDismissal.dismissPresentedContent(from: root)
        _ = await (first, second)
        XCTAssertNil(root.presentedViewController)
        let destination = UIViewController()
        await present(destination, from: root)
        XCTAssertTrue(root.presentedViewController === destination)
        await NotificationPresentationDismissal.dismissPresentedContent(from: root)
    }

    func testRepeatedNotificationCreatesNewNavigationRequest() {
        let store = PersonPushNavigationStore()
        let payload = ["kind": "post", "content_id": "123"]
        store.handle(userInfo: payload)
        let first = store.request
        store.handle(userInfo: payload)
        XCTAssertNotEqual(first?.id, store.request?.id)
    }

    func testNotificationUsesServerDetailIDForTap() throws {
        let store = PersonPushNavigationStore()
        let id = UUID()
        store.handle(userInfo: ["kind": "observability", "notification_id": id.uuidString])
        let details = try XCTUnwrap(store.request?.details)
        XCTAssertEqual(details.id, id)
    }

    func testNotificationDetailsDecodeAllLinksAndAttachment() throws {
        let data = Data("""
        {
          "title": "日报",
          "body": "完整内容",
          "links": [
            {"label": "报告", "url": "https://example.com/report"},
            {"label": "来源", "url": "https://example.com/source"}
          ],
          "image_url": "https://example.com/report.png"
        }
        """.utf8)
        let details = try JSONDecoder().decode(PushNotificationDetails.self, from: data)
        XCTAssertEqual(details.links?.map(\.label), ["报告", "来源"])
        XCTAssertEqual(details.body, "完整内容")
        XCTAssertEqual(details.imageURL?.absoluteString, "https://example.com/report.png")
    }

    func testPostNotificationStillUsesNativeArticleRoute() throws {
        let store = PersonPushNavigationStore()
        store.handle(userInfo: ["kind": "post", "content_id": "123"])
        let request = try XCTUnwrap(store.request)
        XCTAssertEqual(request.kind, "post")
        XCTAssertEqual(request.contentID, "123")
        XCTAssertNil(request.details)
    }

    private func present(_ controller: UIViewController, from parent: UIViewController) async {
        await withCheckedContinuation { continuation in
            parent.present(controller, animated: false) { continuation.resume() }
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Presentation state did not settle")
    }

    private final class SheetState: ObservableObject {
        @Published var isPresented = false
    }

    private struct SheetFixture: View {
        @ObservedObject var state: SheetState
        var body: some View {
            Text("Root").sheet(isPresented: $state.isPresented) { Text("Core stocks") }
        }
    }
}

