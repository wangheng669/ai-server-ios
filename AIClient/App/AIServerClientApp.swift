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
        let details: PushNotificationDestination?
        switch kind {
        case "post":
            guard let id = Int(contentID), id > 0 else { return }
            details = nil
        default:
            guard let value = userInfo["notification_id"] as? String, let id = UUID(uuidString: value) else { return }
            details = PushNotificationDestination(id: id)
        }
        request = PersonPushNavigationRequest(kind: kind, contentID: contentID, details: details)
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

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--modal-contract-preview") {
                    AppModalContractPreview()
                } else {
                    EditorialRootView()
                }
                #else
                EditorialRootView()
                #endif
            }
            .scrollBounceBehavior(.basedOnSize, axes: [.vertical, .horizontal])
        }
    }
}

private enum EditorialTab: Hashable {
    case world, signal, observation, investment, learning
}

private enum EditorialPreview {
    #if DEBUG
    private static let arguments = Set(ProcessInfo.processInfo.arguments)
    #endif

    static let initialTab: EditorialTab = {
        #if DEBUG
        if arguments.contains("--today-world-preview") { return .world }
        if arguments.contains("--feed-preview") { return .observation }
        if arguments.contains("--google-signal-preview") { return .signal }
        if !arguments.isDisjoint(with: [
            "--people-preview", "--person-detail-preview", "--article-detail-preview"
        ]) { return .learning }
        if opensResearchSheet || !arguments.isDisjoint(with: [
            "--market-preview", "--company-preview"
        ]) { return .investment }
        if !arguments.isDisjoint(with: [
            "--learning-preview", "--learning-detail-preview", "--learning-video-preview",
            "--learning-books-preview", "--learning-book-preview", "--learning-concepts-preview",
            "--learning-concept-detail-preview", "--learning-ideology-preview",
            "--city-preview", "--city-province-preview", "--city-city-preview", "--city-district-preview"
        ]) { return .learning }
        #endif
        return .world
    }()

    static let opensResearchSheet: Bool = {
        #if DEBUG
        return !arguments.isDisjoint(with: [
            "--china-macro-preview", "--holdings-preview", "--institution-research-preview",
            "--industries-preview", "--market-core-stocks-preview", "--market-structure-sheet-preview",
            "--gdp-preview"
        ]) || arguments.contains { $0.hasPrefix("--gdp-detail-preview=") }
        #else
        return false
        #endif
    }()

    static let externalLink: InAppBrowserDestination? = {
        #if DEBUG
        let prefix = "--in-app-browser-preview="
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
           let url = URL(string: String(argument.dropFirst(prefix.count))) {
            return InAppBrowserDestination(url: url)
        }
        #endif
        return nil
    }()

    static let deployment: DeploymentStatusSnapshot? = {
        #if DEBUG
        let phase: DeploymentStatusSnapshot.Phase
        let stage: String?
        if arguments.contains("--deployment-tip-success-preview") {
            phase = .succeeded
            stage = "installed"
        } else if arguments.contains("--deployment-tip-failed-preview") {
            phase = .failed
            stage = "install-failed"
        } else if expandsDeployment || arguments.contains("--deployment-tip-collapsed-preview") {
            phase = .running(progress: 0.75)
            stage = nil
        } else {
            return nil
        }
        return DeploymentStatusSnapshot(
            phase: phase,
            commit: "b0d5411",
            updatedAt: Date(timeIntervalSince1970: 0),
            stage: stage
        )
        #else
        return nil
        #endif
    }()

    static let expandsDeployment: Bool = {
        #if DEBUG
        arguments.contains("--deployment-tip-preview")
        #else
        false
        #endif
    }()
}

@MainActor
private final class EditorialPageStores {
    lazy var today = TodayWorldStore()
    lazy var feed = NewsFeedViewModel()
    lazy var research = InstitutionResearchStore()
}

private struct EditorialRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var deploymentStore = DeploymentStatusStore()
    @StateObject private var personPushNavigation = PersonPushNavigationStore.shared
    @State private var peopleStore = PeopleStore()
    @State private var marketStore = MarketStore()
    @State private var investorMoodStore = InvestorMoodStore()
    @State private var learningStore = LearningStore()
    @State private var pageStores = EditorialPageStores()
    @State private var selectedTab = EditorialPreview.initialTab
    @State private var learningShowsDetail = false
    @State private var feedHidesTabBar = false
    @State private var notificationPostID: Int?
    @State private var notificationPresentationAnchor: UIView?
    @State private var presentedNotificationDetails: PushNotificationDestination?
    @State private var lastDynamicTab: EditorialTab = .observation
    @State private var presentedExternalLink = EditorialPreview.externalLink
    @State private var signalSentiment: GoogleSignalSentimentFilter = .all
    @State private var showsSignalFilters = false
    @State private var visitedTabs: Set<EditorialTab> = []
    @State private var rootBottomChromeHeight: CGFloat = 0
    @State private var dismissedDeploymentIdentity: String?

    private var deploymentStatus: DeploymentStatusSnapshot? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AI_FEED_UI_FIXTURE"] != nil { return nil }
        #endif
        guard !EditorialPreview.opensResearchSheet else { return nil }
        let value = EditorialPreview.deployment ?? deploymentStore.snapshot
        guard value?.identity != dismissedDeploymentIdentity else { return nil }
        return value
    }

    // Native sheets cover root navigation without changing its layout underneath.
    private var hidesRootTabBar: Bool {
        switch selectedTab {
        case .observation: feedHidesTabBar
        case .learning: learningShowsDetail
        case .world, .signal, .investment: false
        }
    }

    var body: some View {
        ZStack {
            tabContent(.world) {
                TodayWorldView(store: pageStores.today)
            }
            tabContent(.signal) {
                GoogleSignalView(sentiment: signalSentiment)
            }
            tabContent(.observation) {
                NewsFeedView(
                    model: pageStores.feed,
                    hidesTabBar: $feedHidesTabBar,
                    notificationPostID: $notificationPostID
                )
            }
            tabContent(.investment) {
                MarketView(
                    store: marketStore,
                    investorMoodStore: investorMoodStore,
                    researchStore: pageStores.research
                )
            }
            tabContent(.learning) {
                LearningView(
                    peopleStore: peopleStore,
                    store: learningStore,
                    showsDetail: $learningShowsDetail
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    initiallyExpanded: EditorialPreview.expandsDeployment,
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
                        dynamicTarget: lastDynamicTab
                    )
                }
            }
            .padding(.bottom, 4)
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
            reduceMotion ? nil : AppModalMotion.animation,
            value: showsSignalFilters
        )
        .sensoryFeedback(.success, trigger: deploymentStatus?.identity) { _, _ in
            if case .succeeded = deploymentStatus?.phase { return true }
            return false
        }
        .task(id: scenePhase == .active, priority: .utility) {
            guard scenePhase == .active else { return }
            do { try await Task.sleep(for: .milliseconds(800)) }
            catch { return }
            let tabs: [EditorialTab] = [.learning, .investment, .observation, .signal, .world]
            await runWithLimitedConcurrency(tabs, maximumConcurrentRequests: 2) { tab in
                await prepareTab(tab)
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                deploymentStore.start()
            } else {
                deploymentStore.stop()
            }
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
            default:
                break
            }
            personPushNavigation.clear()
        }
        .onChange(of: selectedTab, initial: true) { _, tab in
            visitedTabs.insert(tab)
            if tab != .signal {
                showsSignalFilters = false
            }
            switch tab {
            case .signal, .observation:
                lastDynamicTab = tab
            case .investment, .world, .learning:
                break
            }
        }
    }

    @ViewBuilder
    private func tabContent<Content: View>(
        _ tab: EditorialTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isSelected = selectedTab == tab
        if isSelected || visitedTabs.contains(tab) {
            content()
                .environment(\.rootTabIsActive, isSelected)
                .opacity(isSelected ? 1 : 0)
                .allowsHitTesting(isSelected)
                .accessibilityHidden(!isSelected)
                .zIndex(isSelected ? 1 : 0)
                .transition(.identity)
        }
    }

    private func prepareTab(_ tab: EditorialTab) async {
        guard !Task.isCancelled, selectedTab != tab else { return }
        switch tab {
        case .learning:
            async let overview: Void = learningStore.loadOverview()
            async let people: Void = peopleStore.load()
            _ = await (overview, people)
        case .investment:
            async let dashboard: Void = marketStore.preloadDashboard()
            async let research: Void = pageStores.research.load()
            _ = await (dashboard, research)
            await marketStore.preloadListCharts(symbols: ResearchHomeContent.chartSymbols)
        case .observation:
            await pageStores.feed.loadInitial()
        case .signal:
            let service = GoogleSignalService()
            if let company = try? await service.fetchCompanies().first {
                _ = try? await service.fetchNews(company: company.id, sentiment: .all)
            }
        case .world:
            await pageStores.today.load()
        }
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
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 0.67, green: 0.84, blue: 0.72)
            : Color(red: 0.22, green: 0.36, blue: 0.27)
    }

    private var selectedForeground: Color {
        colorScheme == .dark
            ? Color(red: 0.09, green: 0.16, blue: 0.11)
            : .white
    }

    var body: some View {
        HStack(spacing: 4) {
            item(.world, title: "今日", icon: "list.bullet.rectangle")
            intelligenceItem
            item(.investment, title: "研究", icon: "chart.bar.fill")
            item(.learning, title: "知识", icon: "book")
        }
        .frame(height: 52)
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 12, y: 5)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var intelligenceItem: some View {
        let isSelected = selection == .observation || selection == .signal
        let currentTab = isSelected ? selection : dynamicTarget
        let currentTitle = currentTab == .signal ? "信号" : "动态"

        return Menu {
            Picker("情报视图", selection: Binding(
                get: { currentTab },
                set: { selection = $0 }
            )) {
                Label("动态", systemImage: "list.bullet.rectangle")
                    .tag(EditorialTab.observation)
                Label("信号", systemImage: "waveform.path.ecg")
                    .tag(EditorialTab.signal)
            }
        } label: {
            itemLabel(title: "情报", icon: "doc.on.doc", isSelected: isSelected)
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
            selection = destination
        }
        .menuOrder(.fixed)
        .accessibilityLabel("情报，当前\(currentTitle)")
        .accessibilityHint(isSelected ? "轻点切换动态和信号，长按选择" : "轻点打开，长按选择动态或信号")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func item(
        _ tab: EditorialTab,
        title: String,
        icon: String
    ) -> some View {
        let isSelected = selection == tab

        return Button {
            selection = tab
        } label: {
            itemLabel(title: title, icon: icon, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("root-tab-\(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func itemLabel(title: String, icon: String, isSelected: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .font(.system(size: 21, weight: isSelected ? .semibold : .regular))
                .symbolRenderingMode(.monochrome)
                .frame(width: 22, height: 22)

            Text(title)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))

        }
        .foregroundStyle(
            isSelected
                ? selectedForeground
                : Color.secondary
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if isSelected {
                Capsule().fill(accent)
            }
        }
        .contentShape(Capsule())
    }
}
