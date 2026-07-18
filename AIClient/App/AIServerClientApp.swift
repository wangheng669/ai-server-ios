import SwiftUI

@main
struct AIServerClientApp: App {
    init() {
        URLCache.shared = URLCache(memoryCapacity: 48_000_000, diskCapacity: 240_000_000)
    }

    var body: some Scene { WindowGroup { EditorialRootView() } }
}

private struct EditorialRootView: View {
    @State private var selectedTab: RootTab = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--people-preview") ||
            ProcessInfo.processInfo.arguments.contains("--person-detail-preview") {
            return .people
        }
        if ProcessInfo.processInfo.arguments.contains("--market-preview") ||
            ProcessInfo.processInfo.arguments.contains("--holdings-preview") ||
            ProcessInfo.processInfo.arguments.contains("--retail-preview") { return .investment }
        return .observation
        #else
        .observation
        #endif
    }()
    @State private var marketShowsDetail = false
    @State private var feedShowsDetail = false
    @State private var peopleShowsDetail = false
    @State private var feedHidesTabBar = false

    private var hidesPrimaryTabBar: Bool {
        marketShowsDetail || feedShowsDetail || peopleShowsDetail ||
            (selectedTab == .observation && feedHidesTabBar)
    }

    private var deploymentPreview: DeploymentStatusSnapshot? {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--deployment-tip-preview") ||
            ProcessInfo.processInfo.arguments.contains("--deployment-tip-collapsed-preview") else { return nil }
        return DeploymentStatusSnapshot(phase: .running(progress: 0.75), commit: "b0d5411")
        #else
        return nil
        #endif
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NewsFeedView(showsDetail: $feedShowsDetail, hidesTabBar: $feedHidesTabBar)
                .tag(RootTab.observation)

            InvestmentView(showsDetail: $marketShowsDetail)
                .tag(RootTab.investment)

            PeopleView(showsDetail: $peopleShowsDetail)
                .tag(RootTab.people)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: hidesPrimaryTabBar ? 0 : 66)
        }
        .overlay(alignment: .bottom) {
            EditorialTabBar(selected: selectedTab) { selectedTab = $0 }
                .offset(y: hidesPrimaryTabBar ? 140 : 0)
                .allowsHitTesting(!hidesPrimaryTabBar)
                .accessibilityHidden(hidesPrimaryTabBar)
                .animation(.easeOut(duration: 0.2), value: hidesPrimaryTabBar)
        }
        .overlay(alignment: .topTrailing) {
            if let deploymentPreview {
                DeploymentStatusTip(
                    snapshot: deploymentPreview,
                    initiallyExpanded: !ProcessInfo.processInfo.arguments.contains("--deployment-tip-collapsed-preview")
                )
                    .padding(.top, 6)
                    .padding(.trailing, 12)
            }
        }
    }
}
