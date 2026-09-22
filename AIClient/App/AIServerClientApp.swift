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
    let id = UUID()
    let kind: String
    let contentID: String
    let personID: String
}

@MainActor
enum NotificationPresentationDismissal {
    private static var dismissal: Task<Void, Never>?

    static func dismissPresentedContent(from root: UIViewController) async {
        if let dismissal {
            await dismissal.value
            return
        }
        let task = Task { await dismissStack(from: root) }
        dismissal = task
        await task.value
        dismissal = nil
    }

    private static func dismissStack(from root: UIViewController) async {
        // A notification can arrive while a sheet is still animating.
        while let presented = root.presentedViewController {
            var top = presented
            while let child = top.presentedViewController { top = child }
            if let transition = top.transitionCoordinator {
                await withCheckedContinuation { continuation in
                    let registered = transition.animate(alongsideTransition: nil) { _ in
                        continuation.resume()
                    }
                    if !registered { continuation.resume() }
                }
            }
            guard root.presentedViewController != nil else { break }
            await withCheckedContinuation { continuation in
                root.dismiss(animated: true) { continuation.resume() }
            }
        }
    }
}

private struct NotificationPresentationAnchor: UIViewRepresentable {
    let resolve: (UIView) -> Void

    final class AnchorView: UIView {
        var resolve: ((UIView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { resolve?(self) }
        }
    }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView(frame: .zero)
        view.resolve = resolve
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {}
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
    case world, signal, observation, investment, company, learning

    static let researchTabs: [EditorialTab] = [.investment, .company]

    var sectionTitle: String {
        switch self {
        case .signal: "信号"
        case .observation: "动态"
        case .company: "公司"
        case .world: "今日"
        case .investment: "数据"
        case .learning: "知识"
        }
    }

    var researchSelectorIcon: String {
        switch self {
        case .investment: "chart.xyaxis.line"
        case .company: "building.2"
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
    @State private var marketStore = MarketStore()
    @State private var marketSentimentStore = RetailSentimentStore()
    @State private var selectedTab: EditorialTab = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--today-world-preview") { return .world }
        if ProcessInfo.processInfo.arguments.contains("--feed-preview") { return .observation }
        if ProcessInfo.processInfo.arguments.contains("--google-signal-preview") { return .signal }
        if ProcessInfo.processInfo.arguments.contains("--people-preview") ||
            ProcessInfo.processInfo.arguments.contains("--person-detail-preview") ||
            ProcessInfo.processInfo.arguments.contains("--article-detail-preview") ||
            ProcessInfo.processInfo.arguments.contains("--video-detail-preview") {
            return .learning
        }
        if ProcessInfo.processInfo.arguments.contains("--market-preview") ||
            ProcessInfo.processInfo.arguments.contains("--china-macro-preview") ||
            ProcessInfo.processInfo.arguments.contains("--holdings-preview") ||
            ProcessInfo.processInfo.arguments.contains("--institution-research-preview") ||
            ProcessInfo.processInfo.arguments.contains("--industries-preview") ||
            ProcessInfo.processInfo.arguments.contains("--market-core-stocks-preview") ||
            ProcessInfo.processInfo.arguments.contains("--market-structure-sheet-preview") ||
            ProcessInfo.processInfo.arguments.contains("--market-research-entries-preview") ||
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
            ProcessInfo.processInfo.arguments.contains("--city-district-preview") { return .learning }
        return .world
        #else
        .world
        #endif
    }()
    @State private var marketShowsDetail = false
    @State private var worldShowsDetail = false
    @State private var feedShowsDetail = false
    @State private var learningShowsDetail = false
    @State private var feedHidesTabBar = false
    @State private var notificationPostID: Int?
    @State private var notificationPersonID: String?
    @State private var notificationVideoID: Int64?
    @State private var notificationPresentationAnchor: UIView?
    @State private var lastDynamicTab: EditorialTab = .observation
    @State private var lastResearchTab: EditorialTab = .investment
    @State private var presentedExternalLink: InAppBrowserDestination? = {
        #if DEBUG
        let prefix = "--in-app-browser-preview="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
              let url = URL(string: String(argument.dropFirst(prefix.count))) else { return nil }
        return InAppBrowserDestination(url: url)
        #else
        return nil
        #endif
    }()
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
            ProcessInfo.processInfo.arguments.contains("--institution-research-preview") ||
            ProcessInfo.processInfo.arguments.contains("--industries-preview") ||
            ProcessInfo.processInfo.arguments.contains("--market-core-stocks-preview") ||
            ProcessInfo.processInfo.arguments.contains("--market-structure-sheet-preview") ||
            ProcessInfo.processInfo.arguments.contains("--market-research-entries-preview") ||
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
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                tabContent(.world) {
                    TodayWorldView(showsDetail: $worldShowsDetail)
                }
                tabContent(.signal) {
                    GoogleSignalView(
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
                    InvestmentView(
                        showsDetail: $marketShowsDetail,
                        marketStore: marketStore,
                        sentimentStore: marketSentimentStore
                    )
                }
                tabContent(.company) {
                    CompanyResearchView()
                }
                tabContent(.learning) {
                    LearningView(
                        peopleStore: peopleStore,
                        showsDetail: $learningShowsDetail,
                        notificationPersonID: $notificationPersonID,
                        notificationVideoID: $notificationVideoID
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .background {
            NotificationPresentationAnchor { view in
                notificationPresentationAnchor = view
            }
            .frame(width: 0, height: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            Task { await ImageLoader.shared.removeCachedImages() }
        }
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
                        sentiment: signalSentiment,
                        showsFilters: $showsSignalFilters
                    )
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
        .task {
            await marketSentimentStore.preload(marketStore: marketStore)
        }
        .task(id: NotificationNavigationTaskID(
            requestID: personPushNavigation.request?.id,
            isActive: scenePhase == .active,
            anchorReady: notificationPresentationAnchor != nil
        )) {
            guard scenePhase == .active,
                  let request = personPushNavigation.request,
                  let root = notificationPresentationAnchor?.window?.rootViewController else { return }
            await NotificationPresentationDismissal.dismissPresentedContent(from: root)
            guard !Task.isCancelled, personPushNavigation.request?.id == request.id else { return }
            presentedExternalLink = nil
            showsSignalFilters = false
            switch request.kind {
            case "post":
                selectedTab = .observation
                notificationPostID = Int(request.contentID)
            case "video":
                selectedTab = .learning
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
            case .investment, .company:
                lastResearchTab = tab
            case .world, .learning:
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

private struct NotificationNavigationTaskID: Equatable {
    let requestID: UUID?
    let isActive: Bool
    let anchorReady: Bool
}

private struct RootNavigationBar: View {
    @Binding var selection: EditorialTab
    let dynamicTarget: EditorialTab
    let researchTarget: EditorialTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            item(.world, title: "今日", icon: "globe")
            intelligenceItem
            researchItem
            item(.learning, title: "知识", icon: "books.vertical")
        }
        .frame(maxWidth: 368)
        .frame(height: 54)
        .background(
            Color(uiColor: .systemBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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

    private var researchItem: some View {
        let isSelected = EditorialTab.researchTabs.contains(selection)
        let currentTab = isSelected ? selection : researchTarget

        return Menu {
            Picker("研究栏目", selection: Binding(
                get: { currentTab },
                set: { select($0) }
            )) {
                ForEach(EditorialTab.researchTabs, id: \.self) { tab in
                    Label(tab.sectionTitle, systemImage: tab.researchSelectorIcon)
                        .tag(tab)
                }
            }
        } label: {
            itemLabel(title: "研究", icon: currentTab.researchSelectorIcon, isSelected: isSelected)
        } primaryAction: {
            select(currentTab)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("研究，当前\(currentTab.sectionTitle)")
        .accessibilityHint(isSelected ? "轻点保持当前栏目，长按选择其他研究栏目" : "轻点打开，长按选择研究栏目")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func item(
        _ tab: EditorialTab,
        title: String,
        icon: String
    ) -> some View {
        let isSelected = selection == tab

        return Button {
            select(tab)
        } label: {
            itemLabel(title: title, icon: icon, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("root-tab-\(title)")
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
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "暂时无法读取最终版日报"
            }
        }
    }

    func generate() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let client = APIClient(baseURL: ServerConfiguration.currentURL)
        do {
            report = try await client.generateTodayWorldYesterdayReport()
            for _ in 0..<240 {
                guard let report, report.shouldPollForFinalReport else { return }
                try await Task.sleep(for: .seconds(2))
                self.report = try await client.fetchTodayWorldYesterdayReport()
            }
            errorMessage = "日报仍在后台生成，请稍后重新加载"
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "暂时无法生成最终版日报"
        }
    }
}

private actor TodayWorldPostMemoryCache {
    static let shared = TodayWorldPostMemoryCache()

    private struct Entry {
        let post: Post
        let loadedAt: Date
    }

    private let lifetime: TimeInterval = 6 * 60 * 60
    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<Post, Error>] = [:]

    func cachedPosts(ids: [Int], baseURL: URL) -> [Post] {
        discardExpiredEntries()
        return ids.compactMap { entries[key(id: $0, baseURL: baseURL)]?.post }
    }

    func store(posts: [Post], baseURL: URL) {
        let loadedAt = Date()
        for post in posts {
            entries[key(id: post.id, baseURL: baseURL)] = Entry(post: post, loadedAt: loadedAt)
        }
    }

    func post(id: Int, baseURL: URL) async throws -> Post {
        let cacheKey = key(id: id, baseURL: baseURL)
        if let entry = entries[cacheKey], Date().timeIntervalSince(entry.loadedAt) <= lifetime {
            return entry.post
        }
        if let task = inFlight[cacheKey] {
            return try await task.value
        }

        let task = Task {
            try await APIClient(baseURL: baseURL).fetchPost(id: id)
        }
        inFlight[cacheKey] = task
        do {
            let post = try await task.value
            entries[cacheKey] = Entry(post: post, loadedAt: Date())
            inFlight[cacheKey] = nil
            return post
        } catch {
            inFlight[cacheKey] = nil
            throw error
        }
    }

    private func key(id: Int, baseURL: URL) -> String {
        "\(baseURL.absoluteString)|\(id)"
    }

    private func discardExpiredEntries() {
        let cutoff = Date().addingTimeInterval(-lifetime)
        entries = entries.filter { $0.value.loadedAt >= cutoff }
    }
}

private struct TodayWorldPostBatchResponse: Decodable {
    let success: Bool
    let posts: [Post]
}

enum TodayWorldPostLoadingPolicy {
    static func shouldLoad(isPostsPagePresented: Bool, postsAreEmpty: Bool) -> Bool {
        isPostsPagePresented && postsAreEmpty
    }
}

private func fetchTodayWorldPostBatch(ids: [Int], baseURL: URL) async throws -> [Post] {
    var seen = Set<Int>()
    let requestedIDs = ids.filter { $0 > 0 && seen.insert($0).inserted }.prefix(50)
    guard !requestedIDs.isEmpty else { return [] }

    var components = URLComponents(
        url: baseURL.appending(path: "api/ios/v1/post/batch"),
        resolvingAgainstBaseURL: false
    )
    components?.queryItems = [
        .init(name: "ids", value: requestedIDs.map(String.init).joined(separator: ",")),
        .init(name: "full", value: "1")
    ]
    guard let url = components?.url else { throw APIError.invalidURL }

    let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else { throw APIError.httpStatus(http.statusCode) }
    let decoded = try JSONDecoder().decode(TodayWorldPostBatchResponse.self, from: data)
    guard decoded.success else { throw APIError.invalidResponse }
    guard decoded.posts.allSatisfy({ $0.content != nil || $0.text != nil || $0.summary != nil }) else {
        throw APIError.invalidResponse
    }
    return decoded.posts
}

private struct TodayWorldView: View {
    @Binding var showsDetail: Bool
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = TodayWorldStore()
    @State private var selectedSectionKey: String?
    @State private var selectedSystem: TodayWorldFinalReportSystem?
    @State private var showsReportDetails = false
    @State private var featuredIndex: Int? = 0
    @State private var activeBriefSheet: BriefSheet?
    @State private var showsWatchItems = false

    private enum BriefSheet: Identifiable {
        case highlight(TodayWorldFinalReportOverviewItem)
        case system(TodayWorldFinalReportSystem)
        case watch
        var id: String {
            switch self {
            case .highlight(let item): return "highlight-" + item.id
            case .system(let system): return "system-" + system.id
            case .watch: return "watch"
            }
        }
    }

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
            .navigationDestination(isPresented: Binding(
                get: { activeBriefSheet != nil },
                set: { if !$0 { activeBriefSheet = nil } }
            )) {
                if let route = activeBriefSheet {
                    briefSheet(route)
                        .toolbar(.visible, for: .navigationBar)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .sheet(isPresented: $showsReportDetails, onDismiss: {
            selectedSystem = nil
            showsDetail = false
        }) {
            if let report = store.report,
               let final = report.report.final,
               final.status == "succeeded" {
                reportDetailsSheet(final, reportDate: report.date)
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
        }
        .sheet(isPresented: $showsWatchItems) {
            NavigationStack { briefSheet(.watch) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: activeBriefSheet?.id) { _, value in
            showsDetail = value != nil || showsReportDetails || showsWatchItems
        }
        .onChange(of: showsWatchItems) { _, value in
            showsDetail = value || activeBriefSheet != nil || showsReportDetails
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await store.load(force: true)
        }
        .task(id: ServerConfiguration.currentURL.absoluteString + "|" + preparationIDs.map(String.init).joined(separator: ",")) {
            await TodayChinesePreparation.warm(ids: preparationIDs, baseURL: ServerConfiguration.currentURL)
        }
        .onChange(of: scenePhase) { _, phase in
            guard rootTabIsActive, phase == .active else { return }
            Task { await store.load(force: true) }
        }
        .onChange(of: showsReportDetails) { _, isPresented in
            showsDetail = isPresented
        }
    }

    private var preparationIDs: [Int] {
        guard rootTabIsActive, scenePhase == .active, let final = store.report?.report.final else { return [] }
        let section = final.sections.first { $0.id == selectedSectionKey } ?? final.sections.first
        return TodayChinesePreparation.prioritizedIDs(
            highlights: final.overview.highlights.flatMap(\.postIDs),
            visible: section?.systems.prefix(5).flatMap(\.postIDs) ?? []
        )
    }

    private var pageBackground: Color { Color(uiColor: .systemGroupedBackground) }
    private var accent: Color { InvestmentDesign.accent }

    @ViewBuilder
    private func reportView(_ report: TodayWorldYesterdayReportPayload) -> some View {
        if let final = report.report.final, final.status == "succeeded", !final.sections.isEmpty {
            let section = final.sections.first { $0.id == selectedSectionKey } ?? final.sections[0]
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(displayDate(report.date))
                                .font(.system(size: 25, weight: .semibold))
                            Text("每日简报 · \(report.sourceCount) 个来源")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { showsReportDetails = true } label: {
                            Label("全文", systemImage: "doc.text")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("today-full-report")
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 20)

                    featuredStories(final)

                    VStack(spacing: 0) {
                        categoryTabs(final.sections, selectedID: section.id)
                        ForEach(Array(section.systems.prefix(5).enumerated()), id: \.element.id) { index, system in
                            if index > 0 { Divider().padding(.leading, 62) }
                            compactSystemRow(system)
                        }
                        if section.systems.isEmpty {
                            Text("这个领域暂无动态")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(24)
                        }
                        Button { showsReportDetails = true } label: {
                            HStack(spacing: 8) {
                                Spacer()
                                Text("查看全部 \(section.systems.count) 组")
                                Image(systemName: "arrow.right")
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 14)
                        }
                        .accessibilityIdentifier("today-all-groups")
                    }
                    .padding(.horizontal, 20)

                    Button { showsWatchItems = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "scope").foregroundStyle(accent)
                            Text("持续观察").fontWeight(.semibold)
                            Text("\(final.overview.watchItems.count) 项待跟进")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12)).foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 15))
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today-watch-items")
                    .padding(.horizontal, 20)
                }
                .padding(.top, 16)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
            .background(pageBackground)
            .refreshable { await store.load(force: true) }
        } else {
            reportStatusView(report)
        }
    }

    private func featuredStories(_ final: TodayWorldFinalReport) -> some View {
        let highlights = final.overview.highlights
        return VStack(spacing: 12) {
            if highlights.isEmpty {
                Text(final.overview.headline)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(highlights.enumerated()), id: \.element.id) { index, item in
                            Button { activeBriefSheet = .highlight(item) } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("编辑精选").foregroundStyle(accent)
                                        Spacer()
                                        Text(String(format: "%02d / %02d", index + 1, highlights.count))
                                            .foregroundStyle(.secondary).monospacedDigit()
                                    }
                                    .font(.system(size: 12, weight: .medium))
                                    Text(item.title?.isEmpty == false ? item.title! : final.overview.headline)
                                        .font(.system(size: 20, weight: .semibold))
                                        .lineSpacing(2).lineLimit(3)
                                    Text(item.text)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                        .lineSpacing(3).lineLimit(3)
                                    Spacer(minLength: 0)
                                    HStack {
                                        Text(featuredSource(item, final: final))
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                    }
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                .multilineTextAlignment(.leading)
                                .padding(18)
                                .frame(height: 254)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)
                            .containerRelativeFrame(.horizontal)
                            .id(index)
                            .accessibilityIdentifier("today-highlight-\(index)")
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $featuredIndex)
                .scrollIndicators(.hidden)
                HStack(spacing: 7) {
                    ForEach(highlights.indices, id: \.self) { index in
                        Circle().fill(index == (featuredIndex ?? 0) ? accent : Color.secondary.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityLabel("精选第 \((featuredIndex ?? 0) + 1) 条，共 \(highlights.count) 条")
            }
        }
    }

    private func featuredSource(_ item: TodayWorldFinalReportOverviewItem, final: TodayWorldFinalReport) -> String {
        let names = final.systems.filter { item.systemKeys.contains($0.systemKey) }.map(\.systemName)
        return names.isEmpty ? "查看解读与依据" : names.joined(separator: " · ")
    }

    private func categoryTabs(_ sections: [TodayWorldFinalReportSection], selectedID: String) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 26) {
                ForEach(sections) { section in
                    Button { selectedSectionKey = section.id } label: {
                        VStack(spacing: 9) {
                            Text(section.sectionName)
                                .font(.system(size: 16, weight: section.id == selectedID ? .semibold : .regular))
                                .foregroundStyle(section.id == selectedID ? Color.primary : .secondary)
                            Capsule().fill(section.id == selectedID ? accent : .clear)
                                .frame(width: 25, height: 3)
                        }
                        .padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today-category-\(section.id)")
                    .accessibilityAddTraits(section.id == selectedID ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 8)
    }

    private func compactSystemRow(_ system: TodayWorldFinalReportSystem) -> some View {
        Button { activeBriefSheet = .system(system) } label: {
            HStack(alignment: .center, spacing: 12) {
                AvatarView(url: system.sourceKeys.first.flatMap(todayWorldSourceAvatarURL), name: system.systemName, size: 32)
                VStack(alignment: .leading, spacing: 5) {
                    Text(system.systemName).font(.system(size: 15, weight: .semibold))
                    Text(system.headline)
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .lineSpacing(2).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .multilineTextAlignment(.leading)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-system-\(system.id)")
    }

    @ViewBuilder
    private func briefSheet(_ route: BriefSheet) -> some View {
        if let report = store.report, let final = report.report.final {
            switch route {
            case .system(let system):
                TodayWorldReportSourcesView(system: system, reportDate: report.date, highlights: final.overview.highlights)
            case .highlight(let item):
                TodayEventDetailView(event: TodayReadingEvent.highlight(item, systems: final.systems, date: report.date))
            case .watch:
                List {
                    if final.overview.watchItems.isEmpty {
                        Text("暂无待跟进事项").foregroundStyle(.secondary)
                    }
                    ForEach(final.overview.watchItems) { item in
                        NavigationLink {
                            TodayEventDetailView(event: TodayReadingEvent.highlight(item, systems: final.systems, date: report.date))
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                if let title = item.title, !title.isEmpty { Text(title).font(.headline) }
                                Text(item.text).font(.body).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }
                    }
                }
                .listStyle(.plain)
                .navigationTitle("持续观察")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func reportDetailsSheet(
        _ final: TodayWorldFinalReport,
        reportDate: String
    ) -> some View {
        let section = final.sections.first { $0.id == selectedSectionKey } ?? final.sections[0]
        return NavigationStack {
            VStack(spacing: 0) {
                sectionSelector(final.sections, selectedID: section.id)
                    .padding(.top, 16)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(section.groups) { group in
                            if section.groups.count > 1 || section.sectionKey == "investment" {
                                Text(group.groupName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 18)
                                    .padding(.top, 14)
                                    .padding(.bottom, 4)
                            }
                            ForEach(Array(group.systems.enumerated()), id: \.element.id) { index, system in
                                if index > 0 { Divider().padding(.leading, 18) }
                                systemRow(system)
                            }
                        }

                        Color.clear.frame(height: 24)
                    }
                    .padding(.top, 12)
                }
                .id(section.id)
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: Binding(
                get: { selectedSystem != nil },
                set: { if !$0 { selectedSystem = nil } }
            )) {
                if let system = selectedSystem {
                    TodayWorldReportSourcesView(system: system, reportDate: reportDate, highlights: final.overview.highlights)
                }
            }
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
        _ sections: [TodayWorldFinalReportSection],
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

    private func systemRow(_ system: TodayWorldFinalReportSystem) -> some View {
        Button {
            selectedSystem = system
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Text(system.systemName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(signalLabel(system.signalLevel))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(signalColor(system.signalLevel))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(signalColor(system.signalLevel).opacity(0.1), in: Capsule())
                }

                Text("\(system.sourceKeys.count) 个账号 · \(system.postIDs.count) 条依据")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(system.headline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let fact = system.facts.first {
                    Text(fact.text)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

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
        .accessibilityIdentifier("yesterday-system-row")
    }

    private func signalLabel(_ level: String) -> String {
        ["high": "高信号", "medium": "中信号", "low": "低信号"][level] ?? "已筛选"
    }

    private func signalColor(_ level: String) -> Color {
        switch level {
        case "high": return .red
        case "low": return Color(uiColor: .secondaryLabel)
        default: return .orange
        }
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
        let isRunning = report.isGenerating
        return ContentUnavailableView {
            Label(
                isRunning ? "正在生成最终版日报" : "暂无最终版日报",
                systemImage: isRunning ? "hourglass" : "doc.text.magnifyingglass"
            )
        } description: {
            Text(isRunning ? "完成后会自动展示主线、要点与直接依据" : (store.errorMessage ?? report.report.final?.error ?? "最终版日报尚未生成"))
        } actions: {
            Button(isRunning ? "刷新进度" : "重新加载") {
                Task {
                    if isRunning {
                        await store.load(force: true)
                    } else {
                        await store.generate()
                    }
                }
            }
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading)
        }
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("暂时无法载入", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("重新加载") {
                Task { await store.generate() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isLoading)
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

    private func sourceName(_ system: TodayWorldFinalReportSystem, at index: Int) -> String {
        guard system.sourceNames.indices.contains(index) else { return system.systemName }
        return system.sourceNames[index]
    }
}

private func todayWorldSourceAvatarURL(_ key: String) -> URL? {
    let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
    return MediaURL.image("/api/ios/v1/today-world/avatars/\(encoded)?v=2")
}

// Reading content stays tied to explicit report references; facts are not inferred to be separate events.
struct TodayReadingEvent: Identifiable {
    let id: String
    let title: String
    let summary: String
    let sourceLabel: String
    let date: String
    let details: [String]
    let watchItems: [String]
    let postIDs: [Int]

    static func canonical(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { !$0.isWhitespace }
            .trimmingCharacters(in: CharacterSet(charactersIn: "。！？!?，,；;：:."))
    }

    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter {
            let key = canonical($0)
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    // Exact sentence matching only: never collapse different numbers, negations or qualifications.
    static func additionalDetails(_ values: [String], excluding existing: [String]) -> [String] {
        func sentences(_ text: String) -> [String] {
            var result: [String] = []
            var current = ""
            for character in text {
                current.append(character)
                if "。！？\n".contains(character) {
                    result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    current = ""
                }
            }
            if !current.isEmpty { result.append(current.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return result
        }
        var seen = Set(existing.flatMap { sentences($0).map(canonical) })
        return values.compactMap { value in
            let fresh = sentences(value).filter {
                let key = canonical($0)
                return !key.isEmpty && seen.insert(key).inserted
            }.joined()
            return fresh.isEmpty ? nil : fresh
        }
    }

    static func highlight(_ item: TodayWorldFinalReportOverviewItem, systems: [TodayWorldFinalReportSystem], date: String) -> Self {
        let related = systems.filter {
            item.systemKeys.contains($0.systemKey) || !Set(item.postIDs).isDisjoint(with: $0.postIDs)
        }
        let ids = item.postIDs.isEmpty ? related.flatMap(\.postIDs) : item.postIDs
        let sourceIDs = Set(ids.filter { $0 > 0 })
        let title = item.title?.isEmpty == false ? item.title! : "事件详情"
        let summary = additionalDetails([item.text], excluding: [title]).joined(separator: "\n")
        let facts = related.flatMap(\.facts).filter {
            !$0.postIDs.isEmpty && Set($0.postIDs).isSubset(of: sourceIDs)
        }
        return Self(id: item.id, title: title,
                    summary: summary, sourceLabel: unique(related.map(\.systemName)).joined(separator: " · "),
                    date: date, details: additionalDetails(facts.map(\.text), excluding: [title, summary]),
                    watchItems: [], postIDs: sourceIDs.sorted())
    }

    static func system(_ system: TodayWorldFinalReportSystem, date: String) -> Self {
        let paragraphs = additionalDetails(system.facts.map(\.text), excluding: [system.headline])
        return Self(id: system.id, title: system.headline, summary: paragraphs.first ?? "",
                    sourceLabel: system.systemName, date: date, details: Array(paragraphs.dropFirst()),
                    watchItems: unique([system.watchItem].compactMap { $0 }),
                    postIDs: Array(Set(system.postIDs.filter { $0 > 0 })).sorted())
    }
}

private struct TodayWorldReportSourcesView: View {
    let system: TodayWorldFinalReportSystem
    let reportDate: String
    var highlights: [TodayWorldFinalReportOverviewItem] = []

    private var events: [TodayReadingEvent] {
        let matches = highlights.filter {
            $0.systemKeys.contains(system.systemKey) || !Set($0.postIDs).isDisjoint(with: system.postIDs)
        }
        // A company report may contain additional material beyond the selected highlights.
        // Only use a directory when multiple explicit events cover all of its cited sources.
        let covered = Set(matches.flatMap(\.postIDs))
        guard matches.count > 1, Set(system.postIDs).isSubset(of: covered) else {
            return [.system(system, date: reportDate)]
        }
        return matches.map { .highlight($0, systems: [system], date: reportDate) }
    }

    var body: some View {
        Group {
            if events.count == 1, let event = events.first {
                TodayEventDetailView(event: event)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(system.systemName).font(.title2.weight(.semibold))
                        Text(reportDate).font(.subheadline).foregroundStyle(.secondary).padding(.top, 6).padding(.bottom, 20)
                        ForEach(events) { event in
                            NavigationLink {
                                TodayEventDetailView(event: event)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(event.title).font(.headline).foregroundStyle(.primary)
                                        Text(event.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .multilineTextAlignment(.leading).padding(.vertical, 18)
                            }
                            Divider()
                        }
                        if let watch = system.watchItem, !watch.isEmpty {
                            Text("后续关注").font(.headline).padding(.top, 24)
                            Text(watch).foregroundStyle(.secondary).padding(.top, 8)
                        }
                    }.padding(20)
                }
                .navigationTitle("公司动态")
            }
        }
        .background(Color(uiColor: .systemBackground))
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TodayEventDetailView: View {
    let event: TodayReadingEvent
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var failedIDs: [Int] = []
    @State private var expandedPostID: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Text([event.sourceLabel, event.date].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(event.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                    if !event.summary.isEmpty {
                        Text(event.summary).font(.body).lineSpacing(5).textSelection(.enabled)
                    }
                }
                if !event.details.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("具体进展").font(.headline)
                        ForEach(event.details, id: \.self) { text in
                            Text(text).lineSpacing(5).textSelection(.enabled)
                        }
                    }
                }
                if !event.watchItems.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("后续关注").font(.headline)
                        ForEach(event.watchItems, id: \.self) { Text($0).foregroundStyle(.secondary).lineSpacing(4) }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    Text("消息来源").font(.headline).padding(.bottom, 12)
                    if event.postIDs.isEmpty {
                        Text("本条简报暂未提供原文引用")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                    }
                    ForEach(posts) { post in
                        TodayInlineSourceView(post: post, isExpanded: expandedPostID == post.id) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedPostID = expandedPostID == post.id ? nil : post.id
                            }
                        }
                        Divider()
                    }
                    if isLoading {
                        ProgressView("正在载入来源").font(.caption).padding(.vertical, 16)
                    }
                    if !failedIDs.isEmpty && !isLoading {
                        HStack {
                            Text(posts.isEmpty ? "暂时无法载入来源" : "部分来源暂未载入").foregroundStyle(.secondary)
                            Spacer()
                            Button("重试") { Task { await loadSources() } }
                        }.font(.subheadline).padding(.vertical, 16)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("事件详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: event.id) { await loadSources() }
    }

    @MainActor private func loadSources() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let url = ServerConfiguration.currentURL
        var loaded = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
        let cached = await TodayWorldPostMemoryCache.shared.cachedPosts(ids: event.postIDs, baseURL: url)
        for post in cached { loaded[post.id] = post }
        posts = event.postIDs.compactMap { loaded[$0] }
        let missing = event.postIDs.filter { loaded[$0] == nil }
        for start in stride(from: 0, to: missing.count, by: 50) {
            guard !Task.isCancelled else { return }
            let ids = Array(missing[start..<min(start + 50, missing.count)])
            do {
                let batch = try await fetchTodayWorldPostBatch(ids: ids, baseURL: url)
                await TodayWorldPostMemoryCache.shared.store(posts: batch, baseURL: url)
                for post in batch where event.postIDs.contains(post.id) { loaded[post.id] = post }
            } catch { /* Individual retries below also support servers without the batch endpoint. */ }
        }
        for id in event.postIDs where loaded[id] == nil {
            guard !Task.isCancelled else { return }
            if let post = try? await TodayWorldPostMemoryCache.shared.post(id: id, baseURL: url) { loaded[id] = post }
        }
        guard !Task.isCancelled else { return }
        posts = event.postIDs.compactMap { loaded[$0] }
        failedIDs = event.postIDs.filter { loaded[$0] == nil }
    }
}

enum TodayChinesePreparation {
    static func prioritizedIDs(highlights: [Int], visible: [Int]) -> [Int] {
        var seen = Set<Int>()
        return Array((highlights + visible).filter { $0 > 0 && seen.insert($0).inserted }.prefix(12))
    }

    static func isChinese(_ text: String) -> Bool {
        text.range(of: "[\\p{Han}]", options: .regularExpression) != nil
            && !XPostTextFormatter.containsUntranslatedEnglishPassage(text)
    }

    static func texts(_ post: Post) -> [String] {
        TodayReadingEvent.unique([
            post.hasTranslation ? post.displayContent : post.xStoredOriginalContent,
            post.meta?.replyContext?.displayText, post.meta?.quotedTweet?.displayText
        ].compactMap { $0 })
    }

    static func warm(ids: [Int], baseURL: URL) async {
        guard !ids.isEmpty, !Task.isCancelled else { return }
        let cached = await TodayWorldPostMemoryCache.shared.cachedPosts(ids: ids, baseURL: baseURL)
        var posts = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        let missing = ids.filter { posts[$0] == nil }
        if !missing.isEmpty, let fetched = try? await fetchTodayWorldPostBatch(ids: missing, baseURL: baseURL) {
            await TodayWorldPostMemoryCache.shared.store(posts: fetched, baseURL: baseURL)
            for post in fetched { posts[post.id] = post }
        }
        for id in ids {
            guard !Task.isCancelled else { return }
            guard let post = posts[id] else { continue }
            for text in texts(post) where !isChinese(text) {
                guard !Task.isCancelled else { return }
                _ = try? await TodayChineseTextCache.shared.text(text, tweetID: text == texts(post).first ? post.xTweetID : nil, baseURL: baseURL)
            }
        }
    }
}

private actor TodayChineseTextCache {
    static let shared = TodayChineseTextCache()
    private var values: [String: String] = [:]
    private var inFlight: [String: Task<String, Error>] = [:]
    private var insertionOrder: [String] = []
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func acquireSlot() async {
        if activeCount < 2 { activeCount += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func releaseSlot() {
        if waiters.isEmpty { activeCount -= 1 } else { waiters.removeFirst().resume() }
    }

    func text(_ source: String, tweetID: String?, baseURL: URL) async throws -> String {
        if TodayChinesePreparation.isChinese(source) { return source }
        let key = baseURL.absoluteString + "|" + (tweetID ?? "") + "|" + source
        if let value = values[key] { return value }
        if let pending = inFlight[key] { return try await pending.value }
        let task = Task<String, Error> {
            await acquireSlot()
            defer { releaseSlot() }
            let result: String
            if let tweetID {
                result = try await APIClient(baseURL: baseURL).fetchXTranslation(tweetID: tweetID).text
            } else {
                result = try await PersonArticleTranslationService.shared.translate(source)
            }
            guard TodayChinesePreparation.isChinese(result) else { throw APIError.invalidResponse }
            return result
        }
        inFlight[key] = task
        do {
            let value = try await task.value
            inFlight[key] = nil
            values[key] = value
            insertionOrder.append(key)
            while insertionOrder.count > 128 { values.removeValue(forKey: insertionOrder.removeFirst()) }
            return value
        } catch {
            inFlight[key] = nil
            throw error
        }
    }
}

private struct TodayInlineSourceView: View {
    let post: Post
    let isExpanded: Bool
    let toggle: () -> Void
    @State private var translations: [String: String] = [:]
    @State private var translating = false
    @State private var translationFailed = false

    private var sourceText: String { post.hasTranslation ? post.displayContent : post.xStoredOriginalContent }
    private func chineseText(_ text: String) -> String? {
        if let translated = translations[text] { return translated }
        guard text.range(of: "[\\p{Han}]", options: .regularExpression) != nil,
              !XPostTextFormatter.containsUntranslatedEnglishPassage(text) else { return nil }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 10) {
                    AvatarView(url: post.avatarURL, name: post.authorName, size: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(post.authorName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        if let time = post.formattedTime { Text(time).font(.caption).foregroundStyle(.secondary) }
                        if !isExpanded {
                            Text(chineseText(sourceText) ?? "展开阅读中文内容")
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today-source-\(post.id)")
            .accessibilityValue(isExpanded ? "已展开" : "已收起")
            if isExpanded {
                if let text = chineseText(sourceText) {
                    Text(text).font(.body).lineSpacing(5).textSelection(.enabled)
                }
                if let reply = post.meta?.replyContext?.displayText, let text = chineseText(reply) {
                    Text("回复：\(text)").font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let quote = post.meta?.quotedTweet, let original = quote.displayText, let text = chineseText(original) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(quote.author?.name ?? "引用内容").font(.caption.weight(.semibold))
                        Text(text).font(.subheadline).textSelection(.enabled)
                    }.padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 2) }
                }
                if post.previewURL != nil || !post.videoURLs.isEmpty { XFeedMediaView(post: post) }
                if translating { ProgressView("正在载入中文内容").font(.caption) }
                if translationFailed {
                    Text("部分中文内容暂不可用，请稍后重新展开")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 16)
        .task(id: post.id) { await prepareChinese() }
        .task(id: isExpanded) {
            if isExpanded && translationFailed { await prepareChinese() }
        }
    }

    @MainActor private func prepareChinese() async {
        guard !translating else { return }
        translationFailed = false
        translating = true
        defer { translating = false }
        let baseURL = ServerConfiguration.currentURL
        for text in TodayChinesePreparation.texts(post) where chineseText(text) == nil {
            guard !Task.isCancelled else { return }
            do {
                let translated = try await TodayChineseTextCache.shared.text(
                    text, tweetID: text == sourceText ? post.xTweetID : nil, baseURL: baseURL
                )
                guard !Task.isCancelled else { return }
                translations[text] = translated
            } catch {
                if !Task.isCancelled { translationFailed = true }
            }
        }
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
        VStack(spacing: 0) {
            if posts.count > 1 {
                navigationStrip
            }

            TabView(selection: $selectedPostID) {
                ForEach(posts) { post in
                    PostDetailView(post: post)
                        .tag(post.id)
                        .id(post.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: posts.count > 1 ? .automatic : .never))
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
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
