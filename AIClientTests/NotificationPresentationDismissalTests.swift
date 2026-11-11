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
        store.handle(title: "", body: "", userInfo: payload)
        let first = store.request
        store.handle(title: "", body: "", userInfo: payload)
        XCTAssertNotEqual(first?.id, store.request?.id)
    }

    func testNotificationWithoutLinkRetainsDetailsForTap() throws {
        let store = PersonPushNavigationStore()
        store.handle(title: "监控告警", body: "接口响应延迟已超过阈值。", userInfo: ["kind": "observability"])
        let details = try XCTUnwrap(store.request?.details)
        XCTAssertEqual(details.title, "监控告警")
        XCTAssertEqual(details.body, "接口响应延迟已超过阈值。")
        XCTAssertNil(details.url)
    }

    func testNotificationDetailsRetainHTTPSLinkAndAttachment() throws {
        let store = PersonPushNavigationStore()
        store.handle(title: "TestFlight 构建完成", body: "版本 1.8.0", userInfo: [
            "kind": "testflight",
            "url": "https://github.com/example/actions/runs/42",
            "image_url": "https://example.com/report.png"
        ])
        let details = try XCTUnwrap(store.request?.details)
        XCTAssertEqual(details.url?.absoluteString, "https://github.com/example/actions/runs/42")
        XCTAssertEqual(details.imageURL?.absoluteString, "https://example.com/report.png")
    }

    func testPostNotificationStillUsesNativeArticleRoute() throws {
        let store = PersonPushNavigationStore()
        store.handle(title: "文章", body: "摘要", userInfo: ["kind": "post", "content_id": "123"])
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

