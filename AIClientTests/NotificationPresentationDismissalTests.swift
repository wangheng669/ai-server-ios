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

