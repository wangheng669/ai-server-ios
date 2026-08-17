import SwiftUI
import UIKit
import UserNotifications

private struct RootTabIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

private struct RootBottomChromeHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct RootBottomChromeHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension EnvironmentValues {
    var rootTabIsActive: Bool {
        get { self[RootTabIsActiveKey.self] }
        set { self[RootTabIsActiveKey.self] = newValue }
    }

    var rootBottomChromeHeight: CGFloat {
        get { self[RootBottomChromeHeightKey.self] }
        set { self[RootBottomChromeHeightKey.self] = newValue }
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

final class AIServerClientAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { await PersonPushNotificationManager.shared.restoreRegistration() }
        #if DEBUG
        if let preview = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("--person-push-video-preview=")
        })?.split(separator: "=", maxSplits: 1).last {
            let values = preview.split(separator: ":", maxSplits: 1).map(String.init)
            if values.count == 2 {
                Task { @MainActor in
                    PersonPushNavigationStore.shared.handle(userInfo: [
                        "kind": "video",
                        "person_id": values[0],
                        "content_id": values[1]
                    ])
                }
            }
        }
        #endif
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await PersonPushNotificationManager.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PersonPushNotificationManager.shared.didFailToRegister()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            PersonPushNavigationStore.shared.handle(
                userInfo: response.notification.request.content.userInfo
            )
        }
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated {
            AppOrientationController.shared.supportedOrientations
        }
    }
}

struct PersonPushNavigationRequest: Equatable {
    let kind: String
    let contentID: String
    let personID: String
}

@MainActor
final class PersonPushNavigationStore: ObservableObject {
    static let shared = PersonPushNavigationStore()

    @Published private(set) var request: PersonPushNavigationRequest?

    func handle(userInfo: [AnyHashable: Any]) {
        request = PersonPushNavigationRequest(
            kind: (userInfo["kind"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            contentID: (userInfo["content_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            personID: (userInfo["person_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    func clear() {
        request = nil
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

private enum EditorialTab: Hashable {
    case world, signal, observation, investment, company, learning, people, city

    static let researchTabs: [EditorialTab] = [.investment, .company, .people]

    var sectionTitle: String {
        switch self {
        case .signal: "信号"
        case .observation: "动态"
        case .company: "公司"
        case .people: "人物"
        case .world: "今日"
        case .investment: "数据"
        case .learning: "知识"
        case .city: "城市"
        }
    }

    var researchSelectorIcon: String {
        switch self {
        case .investment: "chart.xyaxis.line"
        case .company: "building.2"
        case .people: "person.2"
        default: "magnifyingglass"
        }
    }
}

private struct EditorialRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var deploymentStore = DeploymentStatusStore()
    @StateObject private var personPushNavigation = PersonPushNavigationStore.shared
    @State private var peopleStore = PeopleStore()
    @State private var selectedTab: EditorialTab = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--today-world-preview") { return .world }
        if ProcessInfo.processInfo.arguments.contains("--feed-preview") { return .observation }
        if ProcessInfo.processInfo.arguments.contains("--google-signal-preview") { return .signal }
        if ProcessInfo.processInfo.arguments.contains("--people-preview") ||
            ProcessInfo.processInfo.arguments.contains("--person-detail-preview") ||
            ProcessInfo.processInfo.arguments.contains("--article-detail-preview") ||
            ProcessInfo.processInfo.arguments.contains("--video-detail-preview") {
            return .people
        }
        if ProcessInfo.processInfo.arguments.contains("--market-preview") ||
            ProcessInfo.processInfo.arguments.contains("--china-macro-preview") ||
            ProcessInfo.processInfo.arguments.contains("--holdings-preview") ||
            ProcessInfo.processInfo.arguments.contains("--industries-preview") ||
            ProcessInfo.processInfo.arguments.contains("--retail-preview") ||
            ProcessInfo.processInfo.arguments.contains("--sentiment-preview") ||
            ProcessInfo.processInfo.arguments.contains("--korea-leverage-preview") ||
            ProcessInfo.processInfo.arguments.contains("--gdp-preview") ||
            ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--gdp-detail-preview=") }) { return .investment }
        if ProcessInfo.processInfo.arguments.contains("--company-preview") { return .company }
        if ProcessInfo.processInfo.arguments.contains("--learning-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-detail-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-video-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-books-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-book-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-concepts-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-concept-detail-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-ideology-preview") { return .learning }
        if ProcessInfo.processInfo.arguments.contains("--city-preview") ||
            ProcessInfo.processInfo.arguments.contains("--city-province-preview") ||
            ProcessInfo.processInfo.arguments.contains("--city-city-preview") ||
            ProcessInfo.processInfo.arguments.contains("--city-district-preview") { return .city }
        return .world
        #else
        .world
        #endif
    }()
    @State private var marketShowsDetail = false
    @State private var worldShowsDetail = false
    @State private var feedShowsDetail = false
    @State private var peopleShowsDetail = false
    @State private var learningShowsDetail = false
    @State private var feedHidesTabBar = false
    @State private var notificationPostID: Int?
    @State private var notificationPersonID: String?
    @State private var notificationVideoID: Int64?
    @State private var lastDynamicTab: EditorialTab = .observation
    @State private var lastResearchTab: EditorialTab = .investment
    @State private var presentedExternalLink: InAppBrowserDestination?
    @State private var signalSection: GoogleSignalSection = .highlights
    @State private var signalSentiment: GoogleSignalSentimentFilter = .all
    @State private var showsSignalFilters = false
    @State private var rootBottomChromeHeight: CGFloat = 0
    @State private var dismissedDeploymentIdentity: String?

    private var deploymentPreview: DeploymentStatusSnapshot? {
        #if DEBUG
        let previewDate = Date(timeIntervalSince1970: 0)
        if ProcessInfo.processInfo.arguments.contains("--deployment-tip-success-preview") {
            return DeploymentStatusSnapshot(
                phase: .succeeded,
                commit: "b0d5411",
                updatedAt: previewDate,
                stage: "installed"
            )
        }
        if ProcessInfo.processInfo.arguments.contains("--deployment-tip-failed-preview") {
            return DeploymentStatusSnapshot(
                phase: .failed,
                commit: "b0d5411",
                updatedAt: previewDate,
                stage: "install-failed"
            )
        }
        guard ProcessInfo.processInfo.arguments.contains("--deployment-tip-preview") ||
            ProcessInfo.processInfo.arguments.contains("--deployment-tip-collapsed-preview") else { return nil }
        return DeploymentStatusSnapshot(
            phase: .running(progress: 0.75),
            commit: "b0d5411",
            updatedAt: previewDate
        )
        #else
        return nil
        #endif
    }

    private var deploymentStatus: DeploymentStatusSnapshot? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--holdings-preview") ||
            ProcessInfo.processInfo.arguments.contains("--china-macro-preview") ||
            ProcessInfo.processInfo.arguments.contains("--industries-preview") ||
            ProcessInfo.processInfo.arguments.contains("--gdp-preview") ||
            ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--gdp-detail-preview=") }) { return nil }
        #endif
        let value = deploymentPreview ?? deploymentStore.snapshot
        guard value?.identity != dismissedDeploymentIdentity else { return nil }
        return value
    }

    private var hidesRootTabBar: Bool {
        switch selectedTab {
        case .world: worldShowsDetail
        case .signal: false
        case .observation: feedHidesTabBar || feedShowsDetail
        case .investment: marketShowsDetail
        case .company: false
        case .learning: learningShowsDetail
        case .people: peopleShowsDetail
        case .city: false
        }
    }

    private var showsResearchSelector: Bool {
        !hidesRootTabBar && EditorialTab.researchTabs.contains(selectedTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                tabContent(.world) {
                    TodayWorldView(showsDetail: $worldShowsDetail)
                }
                tabContent(.signal) {
                    GoogleSignalView(
                        section: $signalSection,
                        sentiment: $signalSentiment
                    )
                }
                tabContent(.observation) {
                    NewsFeedView(
                        showsDetail: $feedShowsDetail,
                        hidesTabBar: $feedHidesTabBar,
                        notificationPostID: $notificationPostID
                    )
                }
                tabContent(.investment) {
                    InvestmentView(showsDetail: $marketShowsDetail)
                }
                tabContent(.company) {
                    CompanyResearchView()
                }
                tabContent(.learning) {
                    LearningView(showsDetail: $learningShowsDetail)
                }
                tabContent(.people) {
                    PeopleView(
                        store: peopleStore,
                        showsDetail: $peopleShowsDetail,
                        notificationPersonID: $notificationPersonID,
                        notificationVideoID: $notificationVideoID
                    )
                }
                tabContent(.city) {
                    CityNewsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .environment(\.rootBottomChromeHeight, rootBottomChromeHeight)
        .environment(\.openURL, OpenURLAction { url in
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                return .systemAction
            }
            presentedExternalLink = InAppBrowserDestination(url: url)
            return .handled
        })
        .inAppBrowserCover(item: $presentedExternalLink)
        .overlay(alignment: .topLeading) {
            if let deploymentStatus {
                DeploymentStatusTip(
                    snapshot: deploymentStatus,
                    initiallyExpanded: deploymentPreview != nil &&
                        ProcessInfo.processInfo.arguments.contains("--deployment-tip-preview"),
                    onDismiss: {
                        dismissedDeploymentIdentity = deploymentStatus.identity
                        deploymentStore.dismissFailure(deploymentStatus)
                    }
                )
                .id(deploymentStatus.identity)
                .padding(.leading, 12)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if selectedTab == .signal {
                    GoogleSignalFilterButton(
                        section: signalSection,
                        sentiment: signalSentiment,
                        showsFilters: $showsSignalFilters
                    )
                }

                if showsResearchSelector {
                    HStack {
                        Spacer(minLength: 0)
                        ResearchSectionSelector(selection: $selectedTab)
                    }
                    .padding(.horizontal, 14)
                }

                if !hidesRootTabBar {
                    RootNavigationBar(
                        selection: $selectedTab,
                        dynamicTarget: lastDynamicTab,
                        researchTarget: lastResearchTab
                    )
                }
            }
            .padding(.bottom, -13)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: RootBottomChromeHeightPreferenceKey.self,
                        value: max(0, proxy.size.height)
                    )
                }
            }
            .animation(
                reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0),
                value: deploymentStatus?.identity
            )
            .background(.clear)
        }
        .onPreferenceChange(RootBottomChromeHeightPreferenceKey.self) { height in
            rootBottomChromeHeight = height
        }
        .overlay {
            if selectedTab == .signal, showsSignalFilters {
                GoogleSignalFilterOverlay(
                    section: $signalSection,
                    sentiment: $signalSentiment,
                    isPresented: $showsSignalFilters
                )
            }
        }
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.24, extraBounce: 0),
            value: showsSignalFilters
        )
        .sensoryFeedback(.success, trigger: deploymentStatus?.identity) { _, _ in
            if case .succeeded = deploymentStatus?.phase { return true }
            return false
        }
        .task {
            deploymentStore.start()
            await peopleStore.load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                deploymentStore.start()
            } else {
                deploymentStore.stop()
            }
        }
        .onChange(of: personPushNavigation.request, initial: true) { _, request in
            guard let request else { return }
            switch request.kind {
            case "post":
                selectedTab = .observation
                notificationPostID = Int(request.contentID)
            case "video":
                selectedTab = .people
                notificationPersonID = request.personID
                notificationVideoID = Int64(request.contentID)
            default:
                selectedTab = .observation
            }
            personPushNavigation.clear()
        }
        .onChange(of: selectedTab, initial: true) { _, tab in
            if tab != .signal {
                showsSignalFilters = false
            }
            switch tab {
            case .signal, .observation:
                lastDynamicTab = tab
            case .investment, .company, .people:
                lastResearchTab = tab
            case .world, .learning, .city:
                break
            }
        }
    }

    private func tabContent<Content: View>(
        _ tab: EditorialTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .environment(\.rootTabIsActive, selectedTab == tab)
            .opacity(selectedTab == tab ? 1 : 0)
            .scaleEffect(selectedTab == tab || reduceMotion ? 1 : 0.992)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
            .zIndex(selectedTab == tab ? 1 : 0)
            .animation(
                reduceMotion ? nil : .smooth(duration: 0.2, extraBounce: 0),
                value: selectedTab
            )
    }
}

private struct ResearchSectionSelector: View {
    @Binding var selection: EditorialTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        Button {
            withAnimation(expansionAnimation) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selection.researchSelectorIcon)
                    .font(.system(size: 15, weight: .semibold))

                Text(selection.sectionTitle)
                    .font(.system(size: 15, weight: .semibold))

                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .heavy))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minWidth: 112, minHeight: 48)
            .background(InvestmentDesign.accent, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
            }
            .contentShape(Rectangle())
            .shadow(color: InvestmentDesign.accent.opacity(0.26), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换研究栏目，当前为\(selection.sectionTitle)")
        .accessibilityValue(isExpanded ? "已展开" : "已收起")
        .overlay(alignment: .bottomTrailing) {
            if isExpanded {
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(EditorialTab.researchTabs, id: \.self) { tab in
                        option(tab)
                    }
                }
                .offset(y: -56)
                .transition(
                    .move(edge: .bottom)
                        .combined(with: .scale(scale: 0.94, anchor: .bottomTrailing))
                        .combined(with: .opacity)
                )
                .zIndex(1)
            }
        }
        .zIndex(10)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var expansionAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.26, extraBounce: 0.08)
    }

    private func option(_ tab: EditorialTab) -> some View {
        let isSelected = selection == tab

        return Button {
            withAnimation(expansionAnimation) {
                selection = tab
                isExpanded = false
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.researchSelectorIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)

                Text(tab.sectionTitle)
                    .font(.system(size: 15, weight: .semibold))

                Circle()
                    .fill(isSelected ? Color.white : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.82))
            .padding(.horizontal, 14)
            .frame(width: 132, height: 46, alignment: .leading)
            .background(
                isSelected ? InvestmentDesign.accent : Color(uiColor: .systemBackground),
                in: RoundedRectangle(cornerRadius: 15)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(
                        isSelected ? InvestmentDesign.accent : Color.primary.opacity(0.12),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0.09), radius: 10, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct RootNavigationBar: View {
    @Binding var selection: EditorialTab
    let dynamicTarget: EditorialTab
    let researchTarget: EditorialTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionAnimation

    var body: some View {
        HStack(spacing: 0) {
            item(.world, title: "今日", icon: "globe")
            intelligenceItem
            item(
                researchTarget,
                selectedTabs: [.investment, .company, .people],
                title: "研究",
                icon: "magnifyingglass"
            )
            item(.learning, title: "知识", icon: "books.vertical")
            item(.city, title: "城市", icon: "map")
        }
        .frame(maxWidth: 368)
        .frame(height: 54)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.16), lineWidth: 0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 11)
        .padding(.bottom, 2)
    }

    private var intelligenceItem: some View {
        let isSelected = selection == .observation || selection == .signal
        let currentTab = isSelected ? selection : dynamicTarget
        let icon = currentTab == .signal ? "waveform.path.ecg" : "list.bullet.rectangle"

        return Menu {
            Picker("情报视图", selection: Binding(
                get: { currentTab },
                set: { select($0) }
            )) {
                Label("动态", systemImage: "list.bullet.rectangle")
                    .tag(EditorialTab.observation)
                Label("信号", systemImage: "waveform.path.ecg")
                    .tag(EditorialTab.signal)
            }
        } label: {
            itemLabel(title: "情报", icon: icon, isSelected: isSelected)
        } primaryAction: {
            let destination: EditorialTab
            switch selection {
            case .observation:
                destination = .signal
            case .signal:
                destination = .observation
            default:
                destination = dynamicTarget
            }
            select(destination)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("情报，当前\(currentTab.sectionTitle)")
        .accessibilityHint(isSelected ? "轻点切换动态和信号，长按选择" : "轻点打开，长按选择动态或信号")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func item(
        _ tab: EditorialTab,
        selectedTabs: [EditorialTab] = [],
        title: String,
        icon: String
    ) -> some View {
        let isSelected = selection == tab || selectedTabs.contains(selection)

        return Button {
            select(tab)
        } label: {
            itemLabel(title: title, icon: icon, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ tab: EditorialTab) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.24, extraBounce: 0.04)) {
            selection = tab
        }
    }

    private func itemLabel(title: String, icon: String, isSelected: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                .symbolRenderingMode(.monochrome)

            Text(title)
                .font(.system(size: 10, weight: isSelected ? .medium : .regular))

            Circle()
                .fill(isSelected ? InvestmentDesign.accent : Color.clear)
                .frame(width: 3, height: 3)
        }
        .foregroundStyle(
            isSelected
                ? InvestmentDesign.accent
                : Color.primary.opacity(0.68)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .background {
            if isSelected {
                Capsule()
                    .fill(InvestmentDesign.accent.opacity(0.1))
                    .matchedGeometryEffect(id: "root-tab-selection", in: selectionAnimation)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
            }
        }
    }
}

@MainActor
private final class TodayWorldStore: ObservableObject {
    @Published private(set) var report: TodayWorldYesterdayReportPayload?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load(force: Bool = false) async {
        guard !isLoading, force || report == nil else { return }
        isLoading = true
        if report == nil { errorMessage = nil }
        defer { isLoading = false }

        do {
            report = try await APIClient(baseURL: ServerConfiguration.currentURL)
                .fetchTodayWorldYesterdayReport()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            if report == nil {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "暂时无法读取进阶日报"
            }
        }
    }
}

private struct TodayWorldView: View {
    @Binding var showsDetail: Bool
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = TodayWorldStore()
    @State private var selectedSectionKey: String?
    @State private var selectedSystem: TodayWorldAdvancedReportSystem?

    var body: some View {
        NavigationStack {
            Group {
                if let report = store.report {
                    reportView(report)
                } else if store.isLoading {
                    loadingView
                } else if let errorMessage = store.errorMessage {
                    errorView(errorMessage)
                } else {
                    Color(uiColor: .systemBackground)
                }
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $selectedSystem) { system in
            TodayWorldReportSourcesSheet(system: system, reportDate: store.report?.date ?? "")
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationContentInteraction(.scrolls)
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await store.load(force: true)
        }
        .onChange(of: scenePhase) { _, phase in
            guard rootTabIsActive, phase == .active else { return }
            Task { await store.load(force: true) }
        }
        .onChange(of: selectedSystem) { _, system in
            showsDetail = system != nil
        }
    }

    @ViewBuilder
    private func reportView(_ report: TodayWorldYesterdayReportPayload) -> some View {
        if let advanced = report.report.advanced,
           advanced.status == "succeeded",
           !advanced.sections.isEmpty {
            let section = advanced.sections.first { $0.id == selectedSectionKey } ?? advanced.sections[0]
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    metadata(report)
                    sectionSelector(advanced.sections, selectedID: section.id)

                    ForEach(Array(section.systems.enumerated()), id: \.element.id) { index, system in
                        if index > 0 { Divider().padding(.leading, 18) }
                        systemRow(system)
                    }

                    Color.clear.frame(height: 88)
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.load(force: true) }
            .background(Color(uiColor: .systemBackground))
        } else {
            reportStatusView(report)
        }
    }

    private func metadata(_ report: TodayWorldYesterdayReportPayload) -> some View {
        Text("\(displayDate(report.date)) · \(report.postCount) 条动态 · \(report.sourceCount) 个账号")
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 16)
    }

    private func sectionSelector(
        _ sections: [TodayWorldAdvancedReportSection],
        selectedID: String
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(sections) { section in
                Button {
                    selectedSectionKey = section.id
                } label: {
                    VStack(spacing: 9) {
                        Text("\(section.sectionName) \(section.systems.count)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(section.id == selectedID ? Color.teal : Color.secondary)

                        Capsule()
                            .fill(section.id == selectedID ? Color.teal : Color.clear)
                            .frame(width: 68, height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section.id == selectedID ? .isSelected : [])
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func systemRow(_ system: TodayWorldAdvancedReportSystem) -> some View {
        Button {
            selectedSystem = system
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                Text(system.systemName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)

                Text("\(system.sourceKeys.count) 个账号 · \(system.postIDs.count) 条依据")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(system.summary)
                    .font(.system(size: 14.5))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: -7) {
                    ForEach(Array(system.sourceKeys.prefix(3).enumerated()), id: \.offset) { index, key in
                        AvatarView(
                            url: todayWorldSourceAvatarURL(key),
                            name: sourceName(system, at: index),
                            size: 30
                        )
                        .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看引用动态和原文")
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Capsule().fill(Color.secondary.opacity(0.12)).frame(width: 220, height: 12)
            HStack {
                Capsule().fill(Color.secondary.opacity(0.12)).frame(width: 90, height: 16)
                Spacer()
                Capsule().fill(Color.secondary.opacity(0.08)).frame(width: 70, height: 16)
            }
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    Capsule().fill(Color.secondary.opacity(0.12)).frame(width: 110, height: 16)
                    Capsule().fill(Color.secondary.opacity(0.09)).frame(width: 150, height: 11)
                    Capsule().fill(Color.secondary.opacity(0.08)).frame(height: 12)
                    Capsule().fill(Color.secondary.opacity(0.07)).frame(width: 250, height: 12)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .redacted(reason: .placeholder)
        .accessibilityLabel("正在载入今日世界")
    }

    private func reportStatusView(_ report: TodayWorldYesterdayReportPayload) -> some View {
        let isRunning = report.status == "running" || report.status == "queued"
            || report.report.advanced?.status == "running" || report.report.advanced?.status == "queued"
        return ContentUnavailableView {
            Label(
                isRunning ? "正在生成日报" : "暂无进阶日报",
                systemImage: isRunning ? "hourglass" : "doc.text.magnifyingglass"
            )
        } description: {
            Text(isRunning ? "完成后会自动展示总结内容" : "服务端尚未生成可展示的总结")
        } actions: {
            Button("重新加载") { Task { await store.load(force: true) } }
                .buttonStyle(.borderedProminent)
        }
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("暂时无法载入", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("重新加载") {
                Task { await store.load(force: true) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func displayDate(_ value: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func sourceName(_ system: TodayWorldAdvancedReportSystem, at index: Int) -> String {
        guard system.sourceNames.indices.contains(index) else { return system.systemName }
        return system.sourceNames[index]
    }
}

private func todayWorldSourceAvatarURL(_ key: String) -> URL? {
    let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
    return MediaURL.image("/api/ios/v1/today-world/avatars/\(encoded)?v=2")
}

private struct TodayWorldReportSourcesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let system: TodayWorldAdvancedReportSystem
    let reportDate: String

    @State private var posts: [Post] = []
    @State private var translations: [Int: String] = [:]
    @State private var translationFailures: Set<Int> = []
    @State private var originalPostIDs: Set<Int> = []
    @State private var selectedPost: Post?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedPage: Page = .summary

    private enum Page {
        case summary
        case posts
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader

            if selectedPage == .summary {
                summaryPage
            } else {
                VStack(spacing: 0) {
                    postsHeader
                    Group {
                        if isLoading {
                            ProgressView("正在载入动态")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let errorMessage {
                            ContentUnavailableView {
                                Label("暂时无法载入", systemImage: "wifi.exclamationmark")
                            } description: {
                                Text(errorMessage)
                            } actions: {
                                Button("重新加载") {
                                    Task { await load() }
                                }
                            }
                        } else {
                            postsPage
                        }
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .task(id: system.id) { await load() }
        .sheet(item: $selectedPost) { post in
            TodayWorldPostDetailCarousel(posts: posts, initialPost: post)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationContentInteraction(.scrolls)
        }
    }

    private var sheetHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.teal)
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(system.systemName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(system.sourceKeys.count) 个账号 · \(system.postIDs.count) 条依据")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(Color(uiColor: .secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    private var summaryPage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("今日摘要")
                        .font(.system(size: 15, weight: .semibold))

                    Text(system.summary)
                        .font(.system(size: 16))
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)

            summaryFooter
        }
    }

    private var summaryFooter: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                HStack(spacing: -10) {
                    ForEach(Array(system.sourceKeys.prefix(4).enumerated()), id: \.offset) { index, key in
                        AvatarView(
                            url: todayWorldSourceAvatarURL(key),
                            name: sourceName(at: index),
                            size: 44
                        )
                        .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("来源账号")
                        .font(.system(size: 14, weight: .semibold))
                    Text("共 \(system.sourceKeys.count) 个账号")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { selectedPage = .posts }
            } label: {
                HStack(spacing: 6) {
                    Text("查看 \(system.postIDs.count) 条动态")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.teal)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .top) { Divider() }
    }

    private var postsHeader: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { selectedPage = .summary }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("今日摘要")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.teal)

            Spacer()

            Text("用户动态")
                .font(.system(size: 15, weight: .semibold))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var postsPage: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("\(displayDate) · \(posts.count) 条动态")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)

                ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                    if index > 0 {
                        Divider()
                            .padding(.vertical, 16)
                    }
                    postSection(post)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func sourceName(at index: Int) -> String {
        guard system.sourceNames.indices.contains(index) else { return system.systemName }
        return system.sourceNames[index]
    }

    @ViewBuilder
    private func postSection(_ post: Post) -> some View {
        let showsOriginal = originalPostIDs.contains(post.id)
        VStack(alignment: .leading, spacing: 9) {
            Text(post.formattedTime ?? "")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)

            if showsOriginal {
                Text(post.xStoredOriginalContent)
                    .font(.system(size: 15))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let translation = translations[post.id] ?? (post.hasTranslation ? post.displayContent : nil) {
                Text(translation)
                    .font(.system(size: 15))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            } else if translationFailures.contains(post.id) {
                Text("中文翻译暂不可用")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在翻译")
            }

            HStack(spacing: 16) {
                Button(showsOriginal ? "显示翻译" : "显示原文") {
                    if showsOriginal {
                        originalPostIDs.remove(post.id)
                    } else {
                        originalPostIDs.insert(post.id)
                    }
                }
                Button("查看帖子详情") {
                    selectedPost = post
                }
                .accessibilityHint("打开动态详情，可左右滑动切换")
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        posts = []
        translations = [:]
        translationFailures = []
        let baseURL = ServerConfiguration.currentURL
        do {
            var loadedByID: [Int: Post] = [:]
            for batch in system.postIDs.batches(of: 4) {
                try await withThrowingTaskGroup(of: (Int, Post).self) { group in
                    for postID in batch {
                        group.addTask {
                            (postID, try await APIClient(baseURL: baseURL).fetchPost(id: postID))
                        }
                    }
                    for try await (postID, post) in group {
                        loadedByID[postID] = post
                    }
                }
                posts = system.postIDs.compactMap { loadedByID[$0] }
                isLoading = false
            }

            let pendingTranslations = posts.compactMap { post -> (Int, String)? in
                guard post.needsXTranslation, let tweetID = post.xTweetID else { return nil }
                return (post.id, tweetID)
            }
            for batch in pendingTranslations.batches(of: 4) {
                await withTaskGroup(of: (Int, String?).self) { group in
                    for (postID, tweetID) in batch {
                        group.addTask {
                            let text = try? await APIClient(baseURL: baseURL).fetchXTranslation(tweetID: tweetID).text
                            return (postID, text)
                        }
                    }
                    for await (postID, text) in group {
                        if let text {
                            translations[postID] = text
                        } else {
                            translationFailures.insert(postID)
                        }
                    }
                }
            }
            isLoading = false
        } catch {
            errorMessage = NetworkErrorPresentation.message(for: error)
            isLoading = false
        }
    }

    private var displayDate: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: reportDate) else { return reportDate }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}

private struct TodayWorldPostDetailCarousel: View {
    let posts: [Post]

    @State private var selectedPostID: Int

    init(posts: [Post], initialPost: Post) {
        self.posts = posts
        _selectedPostID = State(initialValue: initialPost.id)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if posts.count > 1 {
                    navigationStrip
                }

                TabView(selection: $selectedPostID) {
                    ForEach(posts) { post in
                        PostDetailView(post: post, presentedAsSheet: true)
                            .tag(post.id)
                            .id(post.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: posts.count > 1 ? .automatic : .never))
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("动态详情")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("动态详情，第\(selectedIndex + 1)条，共\(posts.count)条")
        .accessibilityHint(posts.count > 1 ? "左右滑动切换动态" : "")
        .accessibilityAction(named: "上一条动态") { move(by: -1) }
        .accessibilityAction(named: "下一条动态") { move(by: 1) }
    }

    private var navigationStrip: some View {
        HStack(spacing: 14) {
            Button {
                move(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 36, height: 32)
            }
            .disabled(selectedIndex == 0)
            .accessibilityLabel("上一条动态")

            Text("第\(selectedIndex + 1) / \(posts.count) 条")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            Button {
                move(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 36, height: 32)
            }
            .disabled(selectedIndex == posts.count - 1)
            .accessibilityLabel("下一条动态")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .contain)
    }

    private var selectedIndex: Int {
        posts.firstIndex(where: { $0.id == selectedPostID }) ?? 0
    }

    private func move(by offset: Int) {
        let newIndex = selectedIndex + offset
        guard posts.indices.contains(newIndex) else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedPostID = posts[newIndex].id
        }
    }
}

private extension Array {
    func batches(of size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: startIndex, to: endIndex, by: size).map { start in
            Array(self[start..<Swift.min(start + size, endIndex)])
        }
    }
}
