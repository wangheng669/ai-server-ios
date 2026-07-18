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
                .tabItem { Label("观点", systemImage: "newspaper.fill") }

            InvestmentView(showsDetail: $marketShowsDetail)
                .tag(RootTab.investment)
                .tabItem { Label("投资", systemImage: "chart.line.uptrend.xyaxis") }

            PeopleView(showsDetail: $peopleShowsDetail)
                .tag(RootTab.people)
                .tabItem { Label("人物", systemImage: "person.2.fill") }
        }
        .toolbar(hidesPrimaryTabBar ? .hidden : .visible, for: .tabBar)
        .tint(.blue)
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
