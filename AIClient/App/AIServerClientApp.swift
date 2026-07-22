import SwiftUI

@main
struct AIServerClientApp: App {
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
    @State private var isShowingLaunchCover = true

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
        if ProcessInfo.processInfo.arguments.contains("--holdings-preview") { return nil }
        #endif
        return deploymentPreview ?? deploymentStore.snapshot
    }

    private var hidesRootTabBar: Bool {
        switch selectedTab {
        case .observation: feedHidesTabBar || feedShowsDetail
        case .investment: marketShowsDetail
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
            tabContent(.people) {
                PeopleView(store: peopleStore, showsDetail: $peopleShowsDetail)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !hidesRootTabBar {
                RootNavigationBar(selection: $selectedTab)
                    .padding(.horizontal, 22)
                    .offset(y: 8)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let deploymentStatus {
                DeploymentStatusTip(
                    snapshot: deploymentStatus,
                    initiallyExpanded: deploymentPreview != nil
                        ? !ProcessInfo.processInfo.arguments.contains("--deployment-tip-collapsed-preview")
                        : true
                )
                    .id(deploymentStatus.identity)
                    .padding(.top, 6)
                    .padding(.trailing, 12)
            }
        }
        .overlay {
            if isShowingLaunchCover {
                LaunchCoverView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(100)
            }
        }
        .task {
            deploymentStore.start()
            await PeopleImagePreheater.preheatTechnologyLeaders()
        }
        .task {
            guard isShowingLaunchCover, !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.42)) {
                isShowingLaunchCover = false
            }
        }
        .onChange(of: scenePhase) { phase in
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
            item(.people, title: "人物", icon: "person")
        }
        .frame(height: 50)
        .background(Color(uiColor: .systemBackground).opacity(0.98), in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
        .overlay(Capsule().stroke(Color.black.opacity(0.025)))
    }

    private func item(_ tab: RootTab, title: String, icon: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { selection = tab }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: selection == tab ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 11, weight: selection == tab ? .semibold : .regular))
            }
            .foregroundStyle(selection == tab ? HoldingsPalette.purple : Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}
