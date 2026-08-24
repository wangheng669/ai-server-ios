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
    case world, signal, observation, investment, company, learning, people

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
            ProcessInfo.processInfo.arguments.contains("--city-district-preview") { return .learning }
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
        .task {
            await marketSentimentStore.preload(marketStore: marketStore)
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

enum TodayWorldNestedSheetPresentationPolicy {
    static let contentInteraction = PresentationContentInteraction.resizes
}

enum TodayWorldPostLoadingPolicy {
    static func shouldLoad(isPostsSheetPresented: Bool, postsAreEmpty: Bool) -> Bool {
        isPostsSheetPresented && postsAreEmpty
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
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await store.load(force: true)
        }
        .onChange(of: scenePhase) { _, phase in
            guard rootTabIsActive, phase == .active else { return }
            Task { await store.load(force: true) }
        }
        .onChange(of: showsReportDetails) { _, isPresented in
            showsDetail = isPresented
        }
    }

    @ViewBuilder
    private func reportView(_ report: TodayWorldYesterdayReportPayload) -> some View {
        if let final = report.report.final,
           final.status == "succeeded",
           !final.sections.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                metadata(report)
                if !final.overview.headline.isEmpty {
                    finalOverview(final.overview)
                }
                Spacer(minLength: 12)
                Button {
                    showsReportDetails = true
                } label: {
                    HStack(spacing: 8) {
                        Text("查看昨日明细")
                        Text("\(final.sections.reduce(0) { $0 + $1.systems.count }) 个体系")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.up")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("弹出人工智能、投资及引用依据")
                .padding(.horizontal, 18)
                .padding(.bottom, 84)
            }
            .background(Color(uiColor: .systemBackground))
        } else {
            reportStatusView(report)
        }
    }

    private func finalOverview(_ overview: TodayWorldFinalReportOverview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("昨日主线")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.teal)

            Text(overview.headline)
                .font(.system(size: 20, weight: .bold))
                .lineSpacing(3)

            ForEach(Array(overview.highlights.prefix(3).enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.teal)
                    VStack(alignment: .leading, spacing: 3) {
                        if let title = item.title, !title.isEmpty {
                            Text(title).font(.system(size: 14, weight: .semibold))
                        }
                        Text(item.text)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .lineLimit(2)
                    }
                }
            }

            Text("完整分组、观察项和引用依据可在昨日明细中查看")
                .font(.system(size: 12.5))
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private func reportDetailsSheet(
        _ final: TodayWorldFinalReport,
        reportDate: String
    ) -> some View {
        let section = final.sections.first { $0.id == selectedSectionKey } ?? final.sections[0]
        return NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    sectionSelector(final.sections, selectedID: section.id)

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
            .scrollIndicators(.hidden)
            .navigationTitle("昨日明细")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showsReportDetails = false }
                }
            }
        }
        .sheet(item: $selectedSystem) { system in
            TodayWorldReportSourcesSheet(system: system, reportDate: reportDate)
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
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

private struct TodayWorldReportSourcesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let system: TodayWorldFinalReportSystem
    let reportDate: String

    @State private var posts: [Post] = []
    @State private var translations: [Int: String] = [:]
    @State private var translationFailures: Set<Int> = []
    @State private var selectedPost: Post?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingPosts = false

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            summaryPage
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $isShowingPosts) {
            postsSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
                .presentationContentInteraction(TodayWorldNestedSheetPresentationPolicy.contentInteraction)
                .task(id: system.id) {
                    guard TodayWorldPostLoadingPolicy.shouldLoad(
                        isPostsSheetPresented: isShowingPosts,
                        postsAreEmpty: posts.isEmpty
                    ) else { return }
                    await load()
                }
        }
    }

    private var sheetHeader: some View {
        HStack(spacing: 14) {
            AvatarView(
                url: system.sourceKeys.first.flatMap(todayWorldSourceAvatarURL),
                name: sourceName(at: 0),
                size: 54,
                assetName: primaryPersonAvatarAssetName
            )

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
                VStack(alignment: .leading, spacing: 18) {
                    Text("最终结论")
                        .font(.system(size: 15, weight: .semibold))

                    Text(system.headline)
                        .font(.system(size: 19, weight: .bold))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(system.facts) { fact in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(factCategoryLabel(fact.category))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.teal)
                                    Spacer()
                                    Text("\(fact.postIDs.count) 条直接依据")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.tertiary)
                                }
                                Text(fact.text)
                                    .font(.system(size: 16))
                                    .lineSpacing(5)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    if let watchItem = system.watchItem, !watchItem.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("继续观察")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.orange)
                            Text(watchItem)
                                .font(.system(size: 14.5))
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                        }
                        .padding(14)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            summaryFooter
        }
    }

    private func factCategoryLabel(_ category: String) -> String {
        ["release": "发布", "action": "行动", "viewpoint": "观点", "market": "市场", "risk": "风险", "context": "背景"][category] ?? "要点"
    }

    private var primaryPersonAvatarAssetName: String? {
        let identity = ([system.systemName] + system.sourceNames).joined(separator: " ").lowercased()
        let knownPeople: [(aliases: [String], asset: String)] = [
            (["马斯克", "elon musk", "musk"], "ElonMuskAvatar"),
            (["董明珠"], "DongMingzhuAvatar"),
            (["马云", "jack ma"], "JackMaAvatar"),
            (["雷军", "lei jun"], "LeiJunAvatar"),
            (["李彦宏", "robin li"], "RobinLiAvatar")
        ]
        return knownPeople.first { person in
            person.aliases.contains { identity.localizedCaseInsensitiveContains($0) }
        }?.asset
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
                isShowingPosts = true
            } label: {
                HStack(spacing: 6) {
                    Text("查看 \(system.postIDs.count) 条直接依据")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .top) { Divider() }
    }

    private var postsSheet: some View {
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
        .background(Color(uiColor: .systemBackground))
        .sheet(item: $selectedPost) { post in
            TodayWorldPostDetailCarousel(posts: posts, initialPost: post)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
                .presentationContentInteraction(TodayWorldNestedSheetPresentationPolicy.contentInteraction)
        }
    }

    private var postsHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(posts.count) 条动态")
                    .font(.system(size: 20, weight: .bold))

                Text("\(displayDate) · 按时间排序")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button { isShowingPosts = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(Color(uiColor: .secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭动态")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var postsPage: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 60)
                    }
                    postSection(post)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func sourceName(at index: Int) -> String {
        guard system.sourceNames.indices.contains(index) else { return system.systemName }
        return system.sourceNames[index]
    }

    @ViewBuilder
    private func postSection(_ post: Post) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(url: post.avatarURL, name: post.authorName, size: 48)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text([post.authorHandle, post.formattedTime].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let reply = post.meta?.replyContext,
                   let replyText = reply.displayText {
                    TodayWorldReplyContextCard(reply: reply, text: replyText)
                } else if let replyHandle = replyHandle(for: post) {
                    Text("回复 \(replyHandle)")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                }

                if let content = displayedContent(for: post) {
                    Text(content)
                        .font(.system(size: 16))
                        .lineSpacing(4)
                        .lineLimit(8)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.primary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在翻译")
                }

                if let quote = post.meta?.quotedTweet {
                    TodayWorldQuotedPostCard(quote: quote)
                }

                if post.previewURL != nil || !post.videoURLs.isEmpty {
                    XFeedMediaView(post: post)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedPost = post
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("打开动态详情")
    }

    private func displayedContent(for post: Post) -> String? {
        if let translation = translations[post.id] {
            return translation
        }
        if post.hasTranslation {
            return post.displayContent
        }
        if translationFailures.contains(post.id) || !post.needsXTranslation {
            return post.xStoredOriginalContent
        }
        return nil
    }

    private func replyHandle(for post: Post) -> String? {
        guard let value = post.meta?.inReplyToScreenName?
            .trimmingCharacters(in: CharacterSet(charactersIn: "@")),
              !value.isEmpty else { return nil }
        return "@\(value)"
    }

    private struct TodayWorldQuotedPostCard: View {
        let quote: XQuotedPost

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    AvatarView(
                        url: quote.author?.profileImageURL.flatMap(MediaURL.image),
                        name: quote.author?.name ?? "引用动态",
                        size: 24
                    )

                    Text(quote.author?.name ?? "引用动态")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    if let handle = quote.author?.handle {
                        Text(handle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let text = quote.displayText {
                    Text(text)
                        .font(.system(size: 14.5))
                        .lineSpacing(3)
                        .lineLimit(5)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                let media = Array((quote.media ?? []).compactMap(\.displayURL).prefix(4))
                if let image = media.first, media.count == 1 {
                    RemoteImage(url: image, height: 180, cornerRadius: 8)
                        .frame(maxWidth: .infinity)
                } else if !media.isEmpty {
                    LazyVGrid(
                        columns: [.init(.flexible(), spacing: 3), .init(.flexible(), spacing: 3)],
                        spacing: 3
                    ) {
                        ForEach(media, id: \.self) { url in
                            RemoteImage(url: url, height: 110, cornerRadius: 8)
                        }
                    }
                }
            }
            .padding(11)
            .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
        }
    }

    private struct TodayWorldReplyContextCard: View {
        let reply: XReplyContext
        let text: String

        var body: some View {
            VStack(alignment: .leading, spacing: 7) {
                Text("回复 \(reply.handle ?? "这条动态")")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 8) {
                    AvatarView(
                        url: reply.avatarURL.flatMap(MediaURL.image),
                        name: reply.authorName ?? reply.handle ?? "回复",
                        size: 26
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            if let name = reply.authorName, !name.isEmpty {
                                Text(name)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .lineLimit(1)
                            }
                            if let handle = reply.handle {
                                Text(handle)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Text(text)
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .lineLimit(4)
                            .truncationMode(.tail)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
        }
    }

    @MainActor
    private func load() async {
        errorMessage = nil
        translationFailures = []
        let baseURL = ServerConfiguration.currentURL
        let cachedPosts = await TodayWorldPostMemoryCache.shared.cachedPosts(
            ids: system.postIDs,
            baseURL: baseURL
        )
        guard !Task.isCancelled else { return }
        var loadedByID = Dictionary(uniqueKeysWithValues: cachedPosts.map { ($0.id, $0) })
        posts = system.postIDs.compactMap { loadedByID[$0] }
        translations = Dictionary(uniqueKeysWithValues: posts.compactMap { post in
            guard let tweetID = post.xTweetID,
                  let value = PersonDetailStore.cachedXTranslation(tweetID: tweetID) else { return nil }
            return (post.id, value)
        })
        isLoading = posts.isEmpty
        defer {
            if !Task.isCancelled {
                isLoading = false
            }
        }

        var lastError: Error?
        let batchIDs = system.postIDs.filter { loadedByID[$0] == nil }
        if !batchIDs.isEmpty {
            do {
                let batchPosts = try await fetchTodayWorldPostBatch(ids: batchIDs, baseURL: baseURL)
                guard !Task.isCancelled else { return }
                await TodayWorldPostMemoryCache.shared.store(posts: batchPosts, baseURL: baseURL)
                guard !Task.isCancelled else { return }
                for post in batchPosts {
                    loadedByID[post.id] = post
                    if let tweetID = post.xTweetID,
                       let value = PersonDetailStore.cachedXTranslation(tweetID: tweetID) {
                        translations[post.id] = value
                    }
                }
                posts = system.postIDs.compactMap { loadedByID[$0] }
                isLoading = posts.isEmpty
            } catch is CancellationError {
                return
            } catch {
                lastError = error
            }
        }

        await withTaskGroup(of: (Int, Result<Post, Error>).self) { group in
            for postID in system.postIDs where loadedByID[postID] == nil {
                group.addTask {
                    do {
                        let post = try await TodayWorldPostMemoryCache.shared.post(id: postID, baseURL: baseURL)
                        return (postID, .success(post))
                    } catch {
                        return (postID, .failure(error))
                    }
                }
            }

            for await (postID, result) in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                switch result {
                case .success(let post):
                    loadedByID[postID] = post
                    posts = system.postIDs.compactMap { loadedByID[$0] }
                    if let tweetID = post.xTweetID,
                       let value = PersonDetailStore.cachedXTranslation(tweetID: tweetID) {
                        translations[post.id] = value
                    }
                    isLoading = false
                case .failure(let error):
                    lastError = error
                }
            }
        }
        guard !Task.isCancelled else { return }

        if posts.isEmpty, let lastError {
            errorMessage = NetworkErrorPresentation.message(for: lastError)
            isLoading = false
            return
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
