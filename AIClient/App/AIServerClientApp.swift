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
        #if DEBUG
        if ProcessInfo.processInfo.environment["AI_FEED_UI_FIXTURE"] != nil { return true }
        #endif
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
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let content = response.notification.request.content
        await MainActor.run {
            PersonPushNavigationStore.shared.handle(userInfo: content.userInfo)
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
    let details: PushNotificationDestination?
}

struct PushNotificationDestination: Identifiable, Equatable {
    let id: UUID
}

struct PushNotificationDetails: Decodable {
    struct Link: Decodable, Hashable {
        let label: String
        let url: URL
    }

    let title: String
    let body: String
    let links: [Link]?
    let imageURL: URL?

    enum CodingKeys: String, CodingKey {
        case title, body, links
        case imageURL = "image_url"
    }
}

private struct PushNotificationDetailsView: View {
    let destination: PushNotificationDestination
    @State private var details: PushNotificationDetails?
    @State private var loadFailed = false
    @State private var expired = false
    @State private var attempt = 0
    @State private var browser: InAppBrowserDestination?
    @State private var gallerySelection: ImageGallerySelection?

    var body: some View {
        Group {
            if let details {
                content(details)
            } else if loadFailed {
                ContentUnavailableView {
                    Label("无法打开通知", systemImage: "bell.slash")
                } description: {
                    Text(expired ? "这条通知的详情已不可用。" : "暂时无法加载详情，请重试。")
                } actions: {
                    if !expired {
                        Button("重试") { attempt += 1 }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                ProgressView("正在加载通知")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: attempt) {
            loadFailed = false
            do {
                details = try await APIClient(baseURL: ServerConfiguration.currentURL)
                    .fetchPushNotification(id: destination.id)
            } catch {
                guard !Task.isCancelled else { return }
                if case APIError.httpStatus(404) = error { expired = true }
                loadFailed = true
            }
        }
        .imageGallery(item: $gallerySelection)
        .inAppBrowserCover(item: $browser)
    }

    private func content(_ details: PushNotificationDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !details.title.isEmpty {
                    Text(details.title)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                }
                if !details.body.isEmpty {
                    Text(details.body)
                        .font(.body)
                        .textSelection(.enabled)
                }
                if let imageURL = details.imageURL {
                    Button {
                        gallerySelection = ImageGallerySelection(urls: [imageURL], initialIndex: 0)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            RemoteImage(url: imageURL, height: 240, cornerRadius: 12, contentMode: .fit)
                                .accessibilityHidden(true)
                            Label("查看大图", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.subheadline)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(Array((details.links ?? []).enumerated()), id: \.offset) { _, link in
                    Button(link.label, systemImage: "arrow.up.right") {
                        browser = InAppBrowserDestination(url: link.url)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
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
        let kind = userInfo["kind"] as? String ?? ""
        let contentID = userInfo["content_id"] as? String ?? ""
        let personID = userInfo["person_id"] as? String ?? ""
        let details: PushNotificationDestination?
        switch kind {
        case "post":
            guard let id = Int(contentID), id > 0 else { return }
            details = nil
        case "video":
            guard let id = Int64(contentID), id > 0, !personID.isEmpty else { return }
            details = nil
        default:
            guard let value = userInfo["notification_id"] as? String, let id = UUID(uuidString: value) else { return }
            details = PushNotificationDestination(id: id)
        }
        request = PersonPushNavigationRequest(kind: kind, contentID: contentID, personID: personID, details: details)
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
    @StateObject private var todayStore = TodayWorldStore()
    @State private var feedShowsDetail = false
    @State private var learningShowsDetail = false
    @State private var feedHidesTabBar = false
    @State private var notificationPostID: Int?
    @State private var notificationPersonID: String?
    @State private var notificationVideoID: Int64?
    @State private var notificationPresentationAnchor: UIView?
    @State private var presentedNotificationDetails: PushNotificationDestination?
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
        if ProcessInfo.processInfo.environment["AI_FEED_UI_FIXTURE"] != nil ||
            ProcessInfo.processInfo.arguments.contains("--holdings-preview") ||
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
        case .world: false
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
                    TodayWorldView(store: todayStore)
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
        .sheet(item: $presentedNotificationDetails) { details in
            PushNotificationDetailsView(destination: details)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
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
            presentedNotificationDetails = request.details
            switch request.kind {
            case "post":
                selectedTab = .observation
                notificationPostID = Int(request.contentID)
            case "video":
                selectedTab = .learning
                notificationPersonID = request.personID
                notificationVideoID = Int64(request.contentID)
            default:
                break
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
