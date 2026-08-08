import SwiftUI
import UIKit
import UserNotifications

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
    case world, observation, investment, company, learning, people
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
            ProcessInfo.processInfo.arguments.contains("--china-macro-preview") ||
            ProcessInfo.processInfo.arguments.contains("--industries-preview") ||
            ProcessInfo.processInfo.arguments.contains("--gdp-preview") ||
            ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--gdp-detail-preview=") }) { return nil }
        #endif
        return deploymentPreview ?? deploymentStore.snapshot
    }

    private var hidesRootTabBar: Bool {
        switch selectedTab {
        case .world: worldShowsDetail
        case .observation: feedHidesTabBar || feedShowsDetail
        case .investment: marketShowsDetail
        case .company: false
        case .learning: learningShowsDetail
        case .people: peopleShowsDetail
        }
    }

    var body: some View {
        ZStack {
            tabContent(.world) {
                TodayWorldView(showsDetail: $worldShowsDetail)
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
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !hidesRootTabBar {
                RootNavigationBar(selection: $selectedTab)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let deploymentStatus, selectedTab != .investment {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionAnimation

    var body: some View {
        HStack(spacing: 0) {
            item(.observation, title: "观点", icon: "list.bullet.rectangle")
            item(.investment, title: "数据", icon: "chart.line.uptrend.xyaxis")
            item(.world, title: "今日世界", icon: "globe")
            item(.company, title: "公司", icon: "building.2")
            item(.learning, title: "知识", icon: "books.vertical")
            item(.people, title: "人物", icon: "person")
        }
        .frame(maxWidth: 352)
        .frame(height: 46)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.16), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func item(_ tab: EditorialTab, title: String, icon: String) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.24, extraBounce: 0.04)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: selection == tab ? .semibold : .regular))
                    .symbolRenderingMode(.monochrome)

                Circle()
                    .fill(selection == tab ? InvestmentDesign.accent : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(
                selection == tab
                    ? InvestmentDesign.accent
                    : Color.primary.opacity(0.68)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background {
                if selection == tab {
                    Capsule()
                        .fill(InvestmentDesign.accent.opacity(0.1))
                        .matchedGeometryEffect(id: "root-tab-selection", in: selectionAnimation)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

@MainActor
private final class TodayWorldStore: ObservableObject {
    @Published private(set) var payload: TodayWorldPayload?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?
    private var nextPageBySystem: [String: Int] = [:]
    private var hasMoreBySystem: [String: Bool] = [:]

    func load(force: Bool = false) async {
        guard !isLoading, force || payload == nil else { return }
        isLoading = true
        if payload == nil { errorMessage = nil }
        defer { isLoading = false }

        do {
            let freshPayload = try await APIClient(baseURL: ServerConfiguration.currentURL)
                .fetchTodayWorld(limit: 3, page: 1)
            payload = freshPayload
            resetPagination(from: freshPayload)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            if payload == nil {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "暂时无法读取今日动态"
            }
        }
    }

    func loadMore(systemKey: String) async {
        guard !isLoading, !isLoadingMore, hasMoreBySystem[systemKey] == true,
              let current = payload else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let page = nextPageBySystem[systemKey] ?? 2
        do {
            let next = try await APIClient(baseURL: ServerConfiguration.currentURL)
                .fetchTodayWorld(limit: 3, page: page, systemKey: systemKey)
            payload = merging(current, with: next)
            nextPageBySystem[systemKey] = page + 1
            hasMoreBySystem[systemKey] = next.sections.contains { $0.hasMore }
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    private func resetPagination(from payload: TodayWorldPayload) {
        let keys = Set(payload.sections.compactMap { $0.entity?.companyKey })
        nextPageBySystem = Dictionary(uniqueKeysWithValues: keys.map { ($0, 2) })
        hasMoreBySystem = Dictionary(uniqueKeysWithValues: keys.map { key in
            (key, payload.sections.contains { $0.entity?.companyKey == key && $0.hasMore })
        })
    }

    private func merging(_ current: TodayWorldPayload, with next: TodayWorldPayload) -> TodayWorldPayload {
        var sections = current.sections
        for incoming in next.sections {
            guard let index = sections.firstIndex(where: { $0.id == incoming.id }) else {
                sections.append(incoming)
                continue
            }
            let existing = sections[index]
            var seen = Set(existing.items.map(\.id))
            let items = existing.items + incoming.items.filter { seen.insert($0.id).inserted }
            sections[index] = TodayWorldSection(
                id: existing.id,
                kind: existing.kind,
                title: existing.title,
                subtitle: existing.subtitle,
                layout: existing.layout,
                entity: existing.entity,
                source: existing.source,
                items: items,
                itemCount: items.count,
                hasMore: incoming.hasMore,
                latestAt: existing.latestAt ?? incoming.latestAt
            )
        }
        return TodayWorldPayload(
            schemaVersion: current.schemaVersion,
            date: current.date,
            timezone: current.timezone,
            generatedAt: next.generatedAt,
            sections: sections
        )
    }
}

private struct TodayWorldView: View {
    @Binding var showsDetail: Bool
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = TodayWorldStore()
    @State private var selectedSystem: TodayWorldSystemSelection?

    var body: some View {
        NavigationStack {
            Group {
                if let payload = store.payload {
                    timeline(payload)
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
        .sheet(item: $selectedSystem) { selection in
            TodayWorldSystemSheet(systemKey: selection.id, store: store)
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

    private func timeline(_ payload: TodayWorldPayload) -> some View {
        let allGroups = TodayWorldAuthorGroup.make(from: payload)
        let systems = TodayWorldLeaderSystem.make(from: payload, groups: allGroups)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                TodayWorldDailyDigestView(
                    payload: payload,
                    groups: allGroups,
                    systemCount: systems.count,
                    isRefreshing: store.isLoading
                )

                LazyVStack(spacing: 8) {
                    ForEach(systems) { system in
                        TodayWorldLeaderRow(system: system) {
                            selectedSystem = TodayWorldSystemSelection(id: system.key)
                        }
                    }
                }
                .padding(.horizontal, 14)

                Color.clear.frame(height: 88)
            }
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.load(force: true) }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 92)

            ForEach(0..<3, id: \.self) { _ in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Color.secondary.opacity(0.12)).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(Color.secondary.opacity(0.12)).frame(width: 128, height: 13)
                        Capsule().fill(Color.secondary.opacity(0.10)).frame(height: 12)
                        Capsule().fill(Color.secondary.opacity(0.08)).frame(width: 230, height: 12)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .redacted(reason: .placeholder)
        .accessibilityLabel("正在载入今日世界")
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
}

private struct TodayWorldSystemSelection: Identifiable, Equatable {
    let id: String
}

private struct TodayWorldLeaderSystem: Identifiable {
    let key: String
    let name: String
    let accountNames: [String]
    let groups: [TodayWorldAuthorGroup]
    let postCount: Int
    let hasMore: Bool
    let leaderName: String
    let leaderAvatarURL: URL?
    var id: String { key }
    var latestHeadline: String? { groups.first?.posts.first?.displayContent }

    static func make(from payload: TodayWorldPayload, groups: [TodayWorldAuthorGroup]) -> [TodayWorldLeaderSystem] {
        var names: [String: String] = [:]
        var accounts: [String: [String]] = [:]
        for section in payload.sections {
            guard let key = section.entity?.companyKey, let name = section.entity?.companyName else { continue }
            names[key] = name
            if let accountName = section.entity?.name, !(accounts[key] ?? []).contains(accountName) {
                accounts[key, default: []].append(accountName)
            }
        }
        return names.keys.sorted { lhs, rhs in
            let leftIndex = payload.sections.firstIndex { $0.entity?.companyKey == lhs } ?? .max
            let rightIndex = payload.sections.firstIndex { $0.entity?.companyKey == rhs } ?? .max
            return leftIndex < rightIndex
        }.compactMap { key in
            guard let name = names[key] else { return nil }
            let systemGroups = groups.filter { $0.companyKey == key }
            let leaderSection = payload.sections.first {
                $0.entity?.companyKey == key && $0.id.hasPrefix("leader:")
            }
            let leader = systemGroups.first {
                $0.authorKey.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                    == leaderSection?.entity?.xHandle?.lowercased()
            }
            return TodayWorldLeaderSystem(
                key: key,
                name: name,
                accountNames: accounts[key] ?? [],
                groups: systemGroups,
                postCount: systemGroups.reduce(0) { $0 + $1.posts.count },
                hasMore: payload.sections.contains { $0.entity?.companyKey == key && $0.hasMore },
                leaderName: leaderSection?.entity?.name ?? leader?.authorName ?? name,
                leaderAvatarURL: leaderSection?.entity?.avatarURL.flatMap(URL.init(string:)) ?? leader?.avatarURL
            )
        }
    }
}

private struct TodayWorldLeaderRow: View {
    let system: TodayWorldLeaderSystem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AvatarView(url: system.leaderAvatarURL, name: system.leaderName, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(system.leaderName)
                        .font(.system(size: 15.5, weight: .bold))
                    Text(system.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(system.postCount > 0 ? "\(system.postCount) 条" : "暂无更新")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(system.postCount > 0 ? Color.green : Color.secondary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开动态弹窗")
    }
}

private struct TodayWorldSystemSheet: View {
    let systemKey: String
    @ObservedObject var store: TodayWorldStore
    @State private var selectedPost: Post?

    var body: some View {
        NavigationStack {
            Group {
                if let payload = store.payload {
                    let groups = TodayWorldAuthorGroup.make(from: payload)
                    let systems = TodayWorldLeaderSystem.make(from: payload, groups: groups)
                    if let system = systems.first(where: { $0.key == systemKey }) {
                        ScrollView {
                            TodayWorldSelectedSystemView(
                                system: system,
                                onOpenPost: { selectedPost = $0 },
                                onLoadMore: { await store.loadMore(systemKey: system.key) },
                                isLoadingMore: store.isLoadingMore
                            )
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                        }
                        .navigationTitle(system.leaderName)
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
        }
        .sheet(item: $selectedPost) { post in
            NavigationStack {
                PostDetailView(post: post, presentedAsSheet: true)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationContentInteraction(.scrolls)
        }
    }
}

private struct TodayWorldSelectedSystemView: View {
    let system: TodayWorldLeaderSystem
    let onOpenPost: (Post) -> Void
    let onLoadMore: () async -> Void
    let isLoadingMore: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if system.groups.allSatisfy({ $0.posts.isEmpty }) {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(InvestmentDesign.accent)
                        .frame(width: 38, height: 38)
                        .background(InvestmentDesign.accent.opacity(0.09), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("等待今天的第一条动态")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("已关注 \(system.accountNames.count) 个账号，有更新会自动出现在这里")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
                .accessibilityElement(children: .combine)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(system.groups.filter { !$0.posts.isEmpty }) { group in
                        TodayWorldAuthorGroupView(group: group, onOpenPost: onOpenPost)
                    }

                    if system.hasMore {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(isLoadingMore ? "正在加载更多" : "继续上滑加载")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .onAppear {
                            guard !isLoadingMore else { return }
                            Task { await onLoadMore() }
                        }
                    } else {
                        Text("今天的内容已全部加载")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.075), lineWidth: 0.6) }
        .padding(.horizontal, 14)
    }
}

private struct TodayWorldDailyDigestView: View {
    let payload: TodayWorldPayload
    let groups: [TodayWorldAuthorGroup]
    let systemCount: Int
    let isRefreshing: Bool

    private var totalCount: Int {
        groups.reduce(0) { $0 + $1.posts.count }
    }

    private var highlights: [(String, String)] {
        groups.compactMap { group in
            group.posts.first.map { (group.authorName, $0.displayContent) }
        }
        .prefix(3)
        .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                Text(displayDate)
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                Text("\(systemCount) 个体系 · \(totalCount) 条")
                    .font(.system(size: 12, weight: .medium))

                if isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 7) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.teal)
                Text("动态摘要")
                    .font(.system(size: 15, weight: .bold))
            }

            if highlights.isEmpty {
                Text("关注的体系今天暂未发布新动态。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(highlights.enumerated()), id: \.offset) { _, highlight in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Circle().fill(Color.teal).frame(width: 4, height: 4)
                            Text("\(highlight.0)：\(TodayWorldTextFormatter.compact(highlight.1))")
                                .font(.system(size: 12.5))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .padding(.horizontal, 14)
    }

    private var displayDate: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: payload.date) else { return payload.date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }
}

struct TodayWorldAuthorGroup: Identifiable {
    let id: String
    let authorKey: String
    let authorName: String
    let handle: String?
    let avatarURL: URL?
    let companyKey: String
    let companyName: String
    let roleLabel: String
    var posts: [Post]

    static func make(from payload: TodayWorldPayload) -> [TodayWorldAuthorGroup] {
        var groups: [TodayWorldAuthorGroup] = []
        var groupIndexByAuthor: [String: Int] = [:]

        for section in payload.sections {
            guard let entity = section.entity else { continue }
            let handle = normalizedHandle(entity.xHandle)
            let authorName = entity.name ?? "关注账号"
            let authorKey = handle?.lowercased() ?? authorName.lowercased()
            let companyKey = entity.companyKey ?? "altman"
            let groupingKey = "\(companyKey):\(authorKey)"
            guard groupIndexByAuthor[groupingKey] == nil else { continue }

            groups.append(TodayWorldAuthorGroup(
                id: section.id,
                authorKey: authorKey,
                authorName: authorName,
                handle: handle,
                avatarURL: entity.avatarURL.flatMap(URL.init(string:)),
                companyKey: companyKey,
                companyName: entity.companyName ?? "奥特曼系",
                roleLabel: entity.type == "company" ? "官方" : "",
                posts: []
            ))
            groupIndexByAuthor[groupingKey] = groups.count - 1
        }

        let entries = payload.sections.flatMap { section in
            section.items.map { post in
                TodayWorldPostEntry(post: post, section: section)
            }
        }
        .sorted { lhs, rhs in
            postDate(lhs.post) > postDate(rhs.post)
        }
        var seenPostIDs = Set<Int>()

        for entry in entries {
            guard seenPostIDs.insert(entry.post.id).inserted else { continue }
            let handle = entry.post.authorHandle ?? normalizedHandle(entry.section.entity?.xHandle)
            let authorName = entry.post.authorName.isEmpty
                ? (entry.section.entity?.name ?? "OpenAI")
                : entry.post.authorName
            let authorKey = handle?.lowercased() ?? authorName.lowercased()
            let companyKey = entry.section.entity?.companyKey ?? "altman"
            let companyName = entry.section.entity?.companyName ?? "奥特曼系"
            let groupingKey = "\(companyKey):\(authorKey)"

            if let index = groupIndexByAuthor[groupingKey] {
                groups[index].posts.append(entry.post)
                if groups[index].avatarURL == nil, let avatarURL = entry.post.avatarURL {
                    let group = groups[index]
                    groups[index] = TodayWorldAuthorGroup(
                        id: group.id,
                        authorKey: group.authorKey,
                        authorName: group.authorName,
                        handle: group.handle,
                        avatarURL: avatarURL,
                        companyKey: group.companyKey,
                        companyName: group.companyName,
                        roleLabel: group.roleLabel,
                        posts: group.posts
                    )
                }
                continue
            }

            let avatarURL = entry.post.avatarURL
                ?? entry.section.entity?.avatarURL.flatMap(URL.init(string:))
            groups.append(TodayWorldAuthorGroup(
                id: "\(authorKey)-\(entry.post.id)",
                authorKey: authorKey,
                authorName: authorName,
                handle: handle,
                avatarURL: avatarURL,
                companyKey: companyKey,
                companyName: companyName,
                roleLabel: entry.section.entity?.type == "company" ? "官方" : "",
                posts: [entry.post]
            ))
            groupIndexByAuthor[groupingKey] = groups.count - 1
        }
        return groups
    }

    private static func normalizedHandle(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value.hasPrefix("@") ? value : "@\(value)"
    }

    private static func postDate(_ post: Post) -> Date {
        guard let value = post.articlePostAt else { return .distantPast }
        return ISO8601DateFormatter().date(from: value) ?? .distantPast
    }
}

private struct TodayWorldPostEntry {
    let post: Post
    let section: TodayWorldSection
}

enum TodayWorldTextFormatter {
    static func compact(_ text: String) -> String {
        var previousLine: String?
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                guard line != previousLine else { return false }
                previousLine = line
                return true
            }
        return lines.joined(separator: " ")
    }
}

private struct TodayWorldAuthorGroupView: View {
    let group: TodayWorldAuthorGroup
    let onOpenPost: (Post) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: group.avatarURL, name: group.authorName, size: 36)

            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(group.authorName)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)

                    if let handle = group.handle {
                        Text(handle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if !group.roleLabel.isEmpty {
                        Text(group.roleLabel)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                ForEach(Array(group.posts.enumerated()), id: \.element.id) { index, post in
                    TodayWorldGroupedPostRow(
                        post: post,
                        isLast: index == group.posts.indices.last
                    ) {
                        onOpenPost(post)
                    }
                }

                if group.posts.isEmpty {
                    Text("今天暂无动态")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 7)
                        .padding(.bottom, 10)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 60) }
    }
}

private struct TodayWorldGroupedPostRow: View {
    let post: Post
    let isLast: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 0) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)

                    if !isLast {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: 1)
                    }
                }
                .frame(width: 8)

                VStack(alignment: .leading, spacing: 4) {
                    if let time = post.formattedTime {
                        Text(time)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    Text(TodayWorldTextFormatter.compact(post.displayContent))
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .lineSpacing(1)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if hasContext {
                        contextLine
                    }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, isLast ? 2 : 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(post.formattedTime ?? "")：\(post.displayContent)\(contextAccessibilityText)")
        .accessibilityHint("打开动态详情")
    }

    private var hasContext: Bool {
        replyHandle != nil || post.meta?.quotedTweet != nil || ownImageCount > 0 || ownVideoCount > 0
    }

    private var replyHandle: String? {
        guard let value = post.meta?.inReplyToScreenName?
            .trimmingCharacters(in: CharacterSet(charactersIn: "@")),
              !value.isEmpty else { return nil }
        return "@\(value)"
    }

    private var ownImageCount: Int { post.images?.count ?? 0 }
    private var ownVideoCount: Int { post.videos?.count ?? 0 }

    @ViewBuilder
    private var contextLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reply = post.meta?.replyContext,
               let replyText = reply.displayText {
                VStack(alignment: .leading, spacing: 7) {
                    Label("回复 \(reply.handle ?? replyHandle ?? "这条动态")", systemImage: "arrowshape.turn.up.left")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 7) {
                        AvatarView(
                            url: reply.avatarURL.flatMap(MediaURL.image),
                            name: reply.authorName ?? reply.handle ?? "回复",
                            size: 22
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                if let name = reply.authorName, !name.isEmpty {
                                    Text(name).fontWeight(.semibold)
                                }
                                if let handle = reply.handle {
                                    Text(handle).foregroundStyle(.secondary)
                                }
                            }
                            .font(.system(size: 12.5))
                            .lineLimit(1)

                            Text(replyText)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(9)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
                }
            } else if let replyHandle {
                Label("回复 \(replyHandle)", systemImage: "arrowshape.turn.up.left")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if let quote = post.meta?.quotedTweet {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        AvatarView(
                            url: quote.author?.profileImageURL.flatMap(MediaURL.image),
                            name: quote.author?.name ?? "引用",
                            size: 22
                        )
                        Text(quote.author?.name ?? "引用动态")
                            .fontWeight(.semibold)
                        if let handle = quote.author?.handle {
                            Text(handle)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "quote.bubble")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12.5))
                    .lineLimit(1)

                    if let text = quote.displayText {
                        Text(text.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    TodayWorldMediaGrid(items: quoteMediaItems(quote))
                }
                .padding(9)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
                }
            } else {
                TodayWorldMediaGrid(items: ownMediaItems)
            }
        }
    }

    private func quoteSummary(_ quote: XQuotedPost) -> String {
        let author = quote.author?.handle ?? quote.author?.name ?? "引用动态"
        guard let text = quote.displayText else { return "引用 \(author)" }
        return "\(author)：\(text.replacingOccurrences(of: "\n", with: " "))"
    }

    private func quoteMediaItems(_ quote: XQuotedPost) -> [TodayWorldMediaItem] {
        (quote.media ?? []).compactMap { media in
            if media.isVideo {
                if let videoURL = media.directPlaybackURL,
                   let generated = MediaURL.videoThumbnail(for: videoURL, at: 1) {
                    return TodayWorldMediaItem(url: generated, isVideo: true)
                }
                if let preview = media.previewURL {
                    return TodayWorldMediaItem(url: preview, isVideo: true)
                }
            }
            guard let url = media.displayURL else { return nil }
            return TodayWorldMediaItem(url: url, isVideo: media.isVideo)
        }
    }

    private var ownMediaItems: [TodayWorldMediaItem] {
        let images = post.imageURLs.map { TodayWorldMediaItem(url: $0, isVideo: false) }
        let videoPreviews = (post.videos ?? []).compactMap { video -> TodayWorldMediaItem? in
            if let rawVideoURL = video.playURL ?? video.url,
               let videoURL = MediaURL.directVideo(rawVideoURL),
               let generated = MediaURL.videoThumbnail(for: videoURL, at: 1) {
                return TodayWorldMediaItem(url: generated, isVideo: true)
            }
            guard let raw = video.coverURL ?? video.previewImageURL ?? video.preview,
                  let url = MediaURL.image(raw) else { return nil }
            return TodayWorldMediaItem(url: url, isVideo: true)
        }
        return images + videoPreviews
    }

    private var contextAccessibilityText: String {
        var parts: [String] = []
        if let replyHandle { parts.append("回复 \(replyHandle)") }
        if let replyText = post.meta?.replyContext?.displayText {
            parts.append("被回复内容：\(replyText)")
        }
        if let quote = post.meta?.quotedTweet { parts.append(quoteSummary(quote)) }
        if ownImageCount > 0 { parts.append("包含 \(ownImageCount) 张图片") }
        if ownVideoCount > 0 { parts.append("包含 \(ownVideoCount) 个视频") }
        return parts.isEmpty ? "" : "，" + parts.joined(separator: "，")
    }
}

private struct TodayWorldMediaItem: Identifiable {
    let url: URL
    let isVideo: Bool
    var id: URL { url }
}

private struct TodayWorldMediaGrid: View {
    let items: [TodayWorldMediaItem]

    var body: some View {
        if !items.isEmpty {
            GeometryReader { proxy in
                let visibleItems = Array(items.prefix(4))
                let columns = visibleItems.count == 1 ? 1 : 2
                let spacing: CGFloat = 3
                let width = max(0, (proxy.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns))

                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(width), spacing: spacing), count: columns),
                    spacing: spacing
                ) {
                    ForEach(visibleItems) { item in
                        ZStack {
                            RemoteImage(url: item.url, height: itemHeight, cornerRadius: 0, contentMode: .fill)
                                .frame(width: width, height: itemHeight)
                                .clipped()

                            if item.isVideo {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(.black.opacity(0.58), in: Circle())
                            }
                        }
                    }
                }
                .frame(width: proxy.size.width, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(height: gridHeight)
        }
    }

    private var itemHeight: CGFloat { items.count == 1 ? 150 : 112 }
    private var gridHeight: CGFloat { min(items.count, 4) > 2 ? itemHeight * 2 + 3 : itemHeight }
}
