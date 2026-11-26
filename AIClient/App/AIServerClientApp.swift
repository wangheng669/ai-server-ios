import AVFAudio
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
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        if session.role == .windowApplication {
            configuration.delegateClass = FocusSceneDelegate.self
        }
        return configuration
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self
        notificationCenter.setNotificationCategories(Set(["person-post", "focus-post", "focus-report"].map {
            UNNotificationCategory(identifier: $0, actions: [], intentIdentifiers: [])
        }))
        #if DEBUG
        if ProcessInfo.processInfo.environment["AI_FEED_UI_FIXTURE"] != nil { return true }
        #endif
        let push = PersonPushNotificationManager.shared
        ReadingReminderManager.shared.applyNotificationPause(push.notificationsPaused)
        Task { await push.restoreRegistration() }
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
        await MainActor.run {
            guard !PersonPushNotificationManager.shared.notificationsPaused else { return [] }
            PersonPushNavigationStore.shared.prepare(notification.request.content)
            return [.banner, .list, .sound]
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let content = response.notification.request.content
        await MainActor.run {
            PersonPushNavigationStore.shared.handle(content)
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

final class FocusSceneDelegate: NSObject, UIWindowSceneDelegate {
    private enum NotificationShortcut: String {
        case pause = "com.wangheng.aiserverclient.pause-notifications"
        case resume = "com.wangheng.aiserverclient.resume-notifications"
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shortcutItem = connectionOptions.shortcutItem {
            handleNotificationShortcut(shortcutItem)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(handleNotificationShortcut(shortcutItem))
    }

    @discardableResult
    private func handleNotificationShortcut(_ item: UIApplicationShortcutItem) -> Bool {
        guard let shortcut = NotificationShortcut(rawValue: item.type) else { return false }
        let paused = shortcut == .pause
        PersonPushNotificationManager.shared.setNotificationsPaused(paused)
        ReadingReminderManager.shared.applyNotificationPause(paused)
        return true
    }
}

enum PushNotificationContent {
    case post(Post)
    case detail(PushNotificationDetails)
}

struct PushNotificationDestination: Identifiable, Equatable {
    enum Target: Equatable {
        case post(Int)
        case detail(UUID)
    }

    let id = UUID()
    let target: Target
    let title: String
    let summary: String
    let prefersLargeSheet: Bool
    var initialLoad: Task<PushNotificationContent, Error>? = nil

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    var opensPost: Bool {
        if case .post = target { return true }
        return false
    }
}

private extension PushNotificationDestination.Target {
    func fetch(using api: APIClient) async throws -> PushNotificationContent {
        switch self {
        case .post(let id): .post(try await api.fetchPost(id: id))
        case .detail(let id): .detail(try await api.fetchPushNotification(id: id))
        }
    }
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
    let sec13f: Sec13FNotificationSnapshot?
    var report: NativeNotificationReport? = nil

    enum CodingKeys: String, CodingKey {
        case title, body, links, sec13f, report
        case imageURL = "image_url"
    }
}

struct PushNotificationDetailsView: View {
    private enum LoadFailure {
        case unavailable, retryable
    }

    let destination: PushNotificationDestination
    private let feedModel: NewsFeedViewModel?
    private let loadDetails: ((UUID) async throws -> PushNotificationDetails)?
    @State private var loadedContent: PushNotificationContent?
    @Environment(\.dismiss) private var dismiss
    @State private var failure: LoadFailure?
    @State private var attempt = 0
    @State private var browser: InAppBrowserDestination?
    @State private var gallerySelection: ImageGallerySelection?

    init(
        destination: PushNotificationDestination,
        feedModel: NewsFeedViewModel? = nil,
        loadDetails: ((UUID) async throws -> PushNotificationDetails)? = nil
    ) {
        self.destination = destination
        self.feedModel = feedModel
        self.loadDetails = loadDetails
    }

    private var needsLargeSheet: Bool {
        if destination.prefersLargeSheet { return true }
        guard case .detail(let details) = loadedContent else { return false }
        return details.sec13f != nil || details.report != nil
    }

    var body: some View {
        Group {
            switch loadedContent {
            case .post(let post):
                FeedPostSheetContent(
                    post: post, model: feedModel, loadsStoredDetail: false, autoplaysYouTube: false
                )
            case .detail(let details):
                if let snapshot = details.sec13f {
                    Sec13FNotificationView(snapshot: snapshot)
                } else if let report = details.report, report.version == 1 {
                    NativeReportNotificationView(report: report, links: details.links ?? [])
                } else {
                    content(details)
                        .contentMargins(.bottom, 48, for: .scrollContent)
                        .floatingSheetClose("关闭通知详情", action: dismiss.callAsFunction)
                }
            case nil:
                preview
                    .contentMargins(.bottom, 48, for: .scrollContent)
                    .floatingSheetClose("关闭通知详情", action: dismiss.callAsFunction)
            }
        }
        .presentationDetents(needsLargeSheet ? [.large] : [.medium, .large])
        .task(id: attempt) {
            await fetchContent()
        }
        .onDisappear { destination.initialLoad?.cancel() }
        .imageGallery(item: $gallerySelection)
        .inAppBrowserCover(item: $browser)
    }

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                message(title: destination.title, body: destination.summary)
                switch failure {
                case .unavailable:
                    Text("这条通知的详情已不可用。").foregroundStyle(.secondary)
                case .retryable:
                    Text("暂时无法加载详情。").foregroundStyle(.secondary)
                    Button("重试") { attempt += 1 }
                        .buttonStyle(.bordered)
                case nil:
                    ProgressView("正在获取完整详情")
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private func fetchContent() async {
        failure = nil
        let api = APIClient(baseURL: ServerConfiguration.currentURL)
        do {
            let loaded: PushNotificationContent
            if attempt == 0, let initialLoad = destination.initialLoad {
                loaded = try await initialLoad.value
            } else if case .detail(let id) = destination.target, let loadDetails {
                loaded = .detail(try await loadDetails(id))
            } else {
                loaded = try await destination.target.fetch(using: api)
            }
            try Task.checkCancellation()
            loadedContent = loaded
        } catch {
            guard !Task.isCancelled else { return }
            if case APIError.httpStatus(404) = error {
                failure = .unavailable
            } else {
                failure = .retryable
            }
        }
    }

    @ViewBuilder
    private func message(title: String, body: String) -> some View {
        if !title.isEmpty {
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
        }
        if !body.isEmpty {
            Text(body)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    private func content(_ details: PushNotificationDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                message(title: details.title, body: details.body)
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
            if top.isBeingPresented || top.isBeingDismissed, let transition = top.transitionCoordinator {
                await withCheckedContinuation { continuation in
                    var pending: CheckedContinuation<Void, Never>? = continuation
                    let finish = {
                        pending?.resume()
                        pending = nil
                    }
                    let registered = transition.animate(alongsideTransition: nil) { _ in finish() }
                    if !registered { finish() }
                }
            }
            guard root.presentedViewController != nil else { break }
            await withCheckedContinuation { continuation in
                root.dismiss(animated: false) { continuation.resume() }
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

    @Published private(set) var request: PushNotificationDestination?
    private var prepared: (target: PushNotificationDestination.Target, server: URL, expires: Date, load: Task<PushNotificationContent, Error>)?

    private func target(for content: UNNotificationContent) -> PushNotificationDestination.Target? {
        let kind = content.userInfo["kind"] as? String
        if kind == "post" {
            guard let value = content.userInfo["content_id"] as? String, let id = Int(value), id > 0 else { return nil }
            return .post(id)
        }
        guard let value = content.userInfo["notification_id"] as? String, let id = UUID(uuidString: value) else { return nil }
        return .detail(id)
    }

    func prepare(_ content: UNNotificationContent) {
        guard let target = target(for: content) else { return }
        let server = ServerConfiguration.currentURL
        if let prepared, prepared.target == target, prepared.server == server, prepared.expires > .now { return }
        prepared?.load.cancel()
        let api = APIClient(baseURL: server)
        prepared = (target, server, .now.addingTimeInterval(30), Task(priority: .utility) { try await target.fetch(using: api) })
    }

    func handle(_ content: UNNotificationContent) {
        guard let target = target(for: content) else { return }
        request?.initialLoad?.cancel()
        let server = ServerConfiguration.currentURL
        let api = APIClient(baseURL: server)
        let preparedLoad = prepared
        prepared = nil
        let initialLoad = Task(priority: .userInitiated) {
            if let preparedLoad, preparedLoad.target == target, preparedLoad.server == server, preparedLoad.expires > .now {
                let result = try? await withTaskCancellationHandler {
                    try await preparedLoad.load.value
                } onCancel: {
                    preparedLoad.load.cancel()
                }
                try Task.checkCancellation()
                if let result { return result }
            } else {
                preparedLoad?.load.cancel()
            }
            return try await target.fetch(using: api)
        }
        let kind = content.userInfo["kind"] as? String
        request = PushNotificationDestination(
            target: target,
            title: content.title,
            summary: content.body,
            prefersLargeSheet: kind == "post" || kind == "sec13f" || content.categoryIdentifier == "focus-report",
            initialLoad: initialLoad
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
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: .mixWithOthers)
        } catch {
            print("Could not configure video audio: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--sec13f-notification-preview") {
                    Sec13FNotificationPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--modal-contract-preview") {
                    AppModalContractPreview()
                } else {
                    EditorialRootView()
                }
                #else
                EditorialRootView()
                #endif
            }
            .scrollBounceBehavior(.basedOnSize, axes: [.vertical, .horizontal])
            .overlay(alignment: .top) {
                NotificationPauseFeedbackView()
            }
        }
    }
}

private struct NotificationPauseFeedbackView: View {
    @ObservedObject private var push = PersonPushNotificationManager.shared

    var body: some View {
        if let feedback = push.pauseFeedback {
            let message = feedback.paused ? "通知已暂停" : "已解除通知暂停"
            Label(message, systemImage: feedback.paused ? "bell.slash.fill" : "bell.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
                .allowsHitTesting(false)
                .task(id: feedback.id) {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    push.dismissPauseFeedback(feedback.id)
                }
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
            "--holdings-preview", "--gdp-preview"
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
    lazy var market = MarketStore()
    lazy var investorMood = InvestorMoodStore()
    lazy var people = PeopleStore()
    lazy var learning = LearningStore()
    private(set) var loadedFeed: NewsFeedViewModel?
    var feed: NewsFeedViewModel {
        if let loadedFeed { return loadedFeed }
        let model = NewsFeedViewModel()
        loadedFeed = model
        return model
    }
    lazy var research = InstitutionResearchStore()
}

private struct EditorialRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var deploymentStore = DeploymentStatusStore()
    @StateObject private var personPushNavigation = PersonPushNavigationStore.shared
    @State private var pageStores = EditorialPageStores()
    @State private var selectedTab = EditorialPreview.initialTab
    @State private var notificationPresentationAnchor: UIView?
    @State private var presentedNotificationDetails: PushNotificationDestination?
    @State private var showFeedAfterNotification = false
    @State private var lastDynamicTab: EditorialTab = .observation
    @State private var presentedExternalLink = EditorialPreview.externalLink
    @State private var signalSentiment: GoogleSignalSentimentFilter = .all
    @State private var showsSignalFilters = false
    @State private var visitedTabs: Set<EditorialTab> = []
    @State private var rootBottomChromeHeight: CGFloat = 0
    @State private var dismissedDeploymentIdentity: String?
    @State private var backgroundPrefetchReady = false

    private var canPrefetchBackground: Bool {
        scenePhase == .active && personPushNavigation.request == nil && presentedNotificationDetails == nil
    }

    private var canPrefetchOtherTabs: Bool {
        canPrefetchBackground && backgroundPrefetchReady
    }

    private var deploymentStatus: DeploymentStatusSnapshot? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AI_FEED_UI_FIXTURE"] != nil { return nil }
        #endif
        guard !EditorialPreview.opensResearchSheet else { return nil }
        let value = EditorialPreview.deployment ?? deploymentStore.snapshot
        guard value?.identity != dismissedDeploymentIdentity else { return nil }
        return value
    }

    var body: some View {
        ZStack {
            tabContent(.world) {
                TodayWorldView(store: pageStores.today, marketStore: pageStores.market)
            }
            tabContent(.signal) {
                GoogleSignalView(sentiment: signalSentiment)
            }
            tabContent(.observation) {
                NewsFeedView(model: pageStores.feed)
            }
            tabContent(.investment) {
                MarketView(
                    store: pageStores.market,
                    investorMoodStore: pageStores.investorMood,
                    researchStore: pageStores.research
                )
            }
            tabContent(.learning) {
                LearningView(
                    peopleStore: pageStores.people,
                    store: pageStores.learning
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
        .sheet(item: $presentedNotificationDetails, onDismiss: {
            guard personPushNavigation.request == nil, showFeedAfterNotification else { return }
            showFeedAfterNotification = false
            selectedTab = .observation
        }) { details in
            PushNotificationDetailsView(destination: details, feedModel: details.opensPost ? pageStores.loadedFeed : nil)
                .id(details.id)
                .presentationDragIndicator(.hidden)
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
            VStack(spacing: 0) {
                FocusUpdateTip()
                if selectedTab == .signal {
                    GoogleSignalFilterButton(
                        sentiment: signalSentiment,
                        showsFilters: $showsSignalFilters
                    )
                    .padding(.bottom, 8)
                }

                // Root navigation stays visible regardless of page scrolling or detail state.
                // The inset reserves content space and follows the keyboard safe area.
                RootNavigationBar(
                    selection: $selectedTab,
                    dynamicTarget: lastDynamicTab
                )
            }
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
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                deploymentStore.start()
            } else {
                deploymentStore.stop()
            }
        }
        .task(id: canPrefetchBackground, priority: .utility) {
            backgroundPrefetchReady = false
            guard canPrefetchBackground else { return }
            do {
                try await Task.sleep(for: .seconds(1))
                backgroundPrefetchReady = true
            } catch {}
        }
        .task(id: canPrefetchOtherTabs, priority: .utility) {
            guard canPrefetchOtherTabs, selectedTab != .world else { return }
            await pageStores.today.load()
        }
        .task(id: canPrefetchOtherTabs, priority: .utility) {
            guard canPrefetchOtherTabs, selectedTab == .world else { return }
            async let signal: Void = GoogleSignalService().prepareFirstPage()
            async let adjacentFeeds: Void = pageStores.feed.prepareAdjacentSources()
            await pageStores.feed.loadInitial()
            _ = await (signal, adjacentFeeds)
        }
        .task(id: canPrefetchOtherTabs, priority: .utility) {
            guard canPrefetchOtherTabs else { return }
            async let directory: Void = pageStores.feed.prepareXueqiuForOpening()
            async let xTimeline: Void = pageStores.feed.prepareXForOpening()
            await pageStores.feed.prepareVideoAndFlashPages()
            _ = await (directory, xTimeline)
        }
        .task(id: canPrefetchOtherTabs, priority: .background) {
            guard canPrefetchOtherTabs, selectedTab != .learning else { return }
            async let overview: Void = pageStores.learning.loadOverview()
            await pageStores.people.load()
            await overview
        }
        .task(id: canPrefetchOtherTabs, priority: .utility) {
            guard canPrefetchOtherTabs, selectedTab != .investment else { return }
            let marketStore = pageStores.market
            async let indexCharts: Void = marketStore.preloadListCharts(symbols: ResearchHomeContent.chartSymbols)
            await marketStore.preloadDashboard()
            await indexCharts
        }
        .task(id: NotificationNavigationTaskID(
            requestID: personPushNavigation.request?.id,
            canPresent: scenePhase != .background,
            anchorReady: notificationPresentationAnchor != nil
        )) {
            guard scenePhase != .background,
                  let request = personPushNavigation.request,
                  let root = notificationPresentationAnchor?.window?.rootViewController else { return }
            if root.presentedViewController != nil {
                await NotificationPresentationDismissal.dismissPresentedContent(from: root)
            }
            guard !Task.isCancelled, personPushNavigation.request?.id == request.id else { return }
            presentedExternalLink = nil
            showsSignalFilters = false
            showFeedAfterNotification = request.opensPost
            presentedNotificationDetails = request
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
                .environment(\.rootTabIsActive, isSelected && canPrefetchBackground)
                .opacity(isSelected ? 1 : 0)
                .allowsHitTesting(isSelected)
                .accessibilityHidden(!isSelected)
                .zIndex(isSelected ? 1 : 0)
                .transition(.identity)
        }
    }
}

private struct NotificationNavigationTaskID: Equatable {
    let requestID: UUID?
    let canPresent: Bool
    let anchorReady: Bool
}

private struct RootNavigationBar: View {
    @Binding var selection: EditorialTab
    let dynamicTarget: EditorialTab
    @ScaledMetric(relativeTo: .footnote) private var barWidth: CGFloat = 344
    @ScaledMetric(relativeTo: .footnote) private var iconSize: CGFloat = 19

    private let accent = Color(red: 0.22, green: 0.36, blue: 0.27)

    var body: some View {
        HStack(spacing: 2) {
            item(.world, title: "今日", icon: "newspaper")
            intelligenceItem
            item(.investment, title: "研究", icon: "chart.bar")
            item(.learning, title: "知识", icon: "book")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: barWidth)
        .background(.white, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(accent.opacity(0.16), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
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
        .buttonStyle(.plain)
        .accessibilityIdentifier("root-tab-情报")
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
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: isSelected ? .semibold : .regular))
                .accessibilityHidden(true)
            Text(title)
                .font(.footnote.weight(isSelected ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .symbolRenderingMode(.monochrome)
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .foregroundStyle(isSelected ? accent : Color.primary.opacity(0.66))
        .frame(maxWidth: .infinity, minHeight: 52)
        .background {
            if isSelected {
                Capsule().fill(Color(red: 0.91, green: 0.94, blue: 0.92))
            }
        }
        .contentShape(Rectangle())
    }
}
