import SwiftUI
import UIKit

private struct RootTabIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var rootTabIsActive: Bool {
        get { self[RootTabIsActiveKey.self] }
        set { self[RootTabIsActiveKey.self] = newValue }
    }
}

@MainActor
final class AppOrientationController {
    static let shared = AppOrientationController()
    private(set) var supportedOrientations: UIInterfaceOrientationMask = .portrait

    func setVideoFullscreen(_ isFullscreen: Bool) {
        let orientations: UIInterfaceOrientationMask = isFullscreen
            ? .landscape
            : .portrait
        guard supportedOrientations != orientations else { return }
        supportedOrientations = orientations

        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
        }
    }
}

final class AIServerClientAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated {
            AppOrientationController.shared.supportedOrientations
        }
    }
}

@main
struct AIServerClientApp: App {
    @UIApplicationDelegateAdaptor(AIServerClientAppDelegate.self) private var appDelegate

    init() {
        URLCache.shared = URLCache(memoryCapacity: 48_000_000, diskCapacity: 240_000_000)
    }

    var body: some Scene { WindowGroup { EditorialRootView() } }
}

private struct EditorialRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var deploymentStore = DeploymentStatusStore()
    @State private var peopleStore = PeopleStore()
    @State private var selectedTab: RootTab = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--people-preview") ||
            ProcessInfo.processInfo.arguments.contains("--person-detail-preview") ||
            ProcessInfo.processInfo.arguments.contains("--article-detail-preview") ||
            ProcessInfo.processInfo.arguments.contains("--video-detail-preview") {
            return .people
        }
        if ProcessInfo.processInfo.arguments.contains("--market-preview") ||
            ProcessInfo.processInfo.arguments.contains("--holdings-preview") ||
            ProcessInfo.processInfo.arguments.contains("--industries-preview") ||
            ProcessInfo.processInfo.arguments.contains("--retail-preview") ||
            ProcessInfo.processInfo.arguments.contains("--sentiment-preview") ||
            ProcessInfo.processInfo.arguments.contains("--gdp-preview") ||
            ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--gdp-detail-preview=") }) { return .investment }
        if ProcessInfo.processInfo.arguments.contains("--learning-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-detail-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-video-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-books-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-book-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-concepts-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-ideology-preview") { return .learning }
        return .observation
        #else
        .observation
        #endif
    }()
    @State private var marketShowsDetail = false
    @State private var feedShowsDetail = false
    @State private var peopleShowsDetail = false
    @State private var learningShowsDetail = false
    @State private var feedHidesTabBar = false

    private var deploymentPreview: DeploymentStatusSnapshot? {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--deployment-tip-preview") ||
            ProcessInfo.processInfo.arguments.contains("--deployment-tip-collapsed-preview") else { return nil }
        return DeploymentStatusSnapshot(phase: .running(progress: 0.75), commit: "b0d5411")
        #else
        return nil
        #endif
    }

    private var deploymentStatus: DeploymentStatusSnapshot? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--holdings-preview") ||
            ProcessInfo.processInfo.arguments.contains("--industries-preview") ||
            ProcessInfo.processInfo.arguments.contains("--gdp-preview") ||
            ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--gdp-detail-preview=") }) { return nil }
        #endif
        return deploymentPreview ?? deploymentStore.snapshot
    }

    private var hidesRootTabBar: Bool {
        switch selectedTab {
        case .observation: feedHidesTabBar || feedShowsDetail
        case .investment: marketShowsDetail
        case .learning: learningShowsDetail
        case .people: peopleShowsDetail
        }
    }

    var body: some View {
        ZStack {
            tabContent(.observation) {
                NewsFeedView(showsDetail: $feedShowsDetail, hidesTabBar: $feedHidesTabBar)
            }
            tabContent(.investment) {
                InvestmentView(showsDetail: $marketShowsDetail)
            }
            tabContent(.learning) {
                LearningView(showsDetail: $learningShowsDetail)
            }
            tabContent(.people) {
                PeopleView(store: peopleStore, showsDetail: $peopleShowsDetail)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !hidesRootTabBar {
                RootNavigationBar(selection: $selectedTab)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let deploymentStatus {
                DeploymentStatusTip(
                    snapshot: deploymentStatus,
                    initiallyExpanded: deploymentPreview != nil
                        ? !ProcessInfo.processInfo.arguments.contains("--deployment-tip-collapsed-preview")
                        : false
                )
                    .id(deploymentStatus.identity)
                    .padding(.top, 6)
                    .padding(.trailing, 12)
            }
        }
        .task {
            deploymentStore.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                deploymentStore.start()
            } else {
                deploymentStore.stop()
            }
        }
    }

    private func tabContent<Content: View>(
        _ tab: RootTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .environment(\.rootTabIsActive, selectedTab == tab)
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
            .zIndex(selectedTab == tab ? 1 : 0)
    }
}

private struct RootNavigationBar: View {
    @Binding var selection: RootTab

    var body: some View {
        HStack(spacing: 0) {
            item(.observation, title: "观点", icon: "list.bullet.rectangle")
            item(.investment, title: "数据", icon: "chart.line.uptrend.xyaxis")
            item(.learning, title: "知识", icon: "books.vertical")
            item(.people, title: "人物", icon: "person")
        }
        .frame(height: 56)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(InvestmentDesign.divider)
                .frame(height: 0.5)
        }
    }

    private func item(_ tab: RootTab, title: String, icon: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { selection = tab }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: selection == tab ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 10.5, weight: selection == tab ? .semibold : .regular))
            }
            .foregroundStyle(selection == tab ? InvestmentDesign.accent : Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}
