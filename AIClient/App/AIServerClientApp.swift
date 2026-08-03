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
    case world, observation, investment, learning, people
}

private struct EditorialRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var deploymentStore = DeploymentStatusStore()
    @StateObject private var personPushNavigation = PersonPushNavigationStore.shared
    @State private var peopleStore = PeopleStore()
    @State private var selectedTab: EditorialTab = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--today-world-preview") { return .world }
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
        .background(Color.white.ignoresSafeArea())
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
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
            .zIndex(selectedTab == tab ? 1 : 0)
    }
}

private struct RootNavigationBar: View {
    @Binding var selection: EditorialTab

    var body: some View {
        HStack(spacing: 0) {
            item(.observation, title: "观点", icon: "list.bullet.rectangle")
            item(.investment, title: "数据", icon: "chart.line.uptrend.xyaxis")
            item(.world, title: "今日世界", icon: "globe")
            item(.learning, title: "知识", icon: "books.vertical")
            item(.people, title: "人物", icon: "person")
        }
        .frame(maxWidth: 292)
        .frame(height: 46)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 44)
        .padding(.bottom, 10)
    }

    private func item(_ tab: EditorialTab, title: String, icon: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: selection == tab ? .semibold : .regular))
                    .symbolRenderingMode(.monochrome)

                Circle()
                    .fill(selection == tab ? InvestmentDesign.accent : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(selection == tab ? InvestmentDesign.accent : Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
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
    @State private var selectedPost: Post?
    @State private var selectedSystemKey = "musk"

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
        .sheet(item: $selectedPost) { post in
            NavigationStack {
                PostDetailView(post: post, presentedAsSheet: true)
            }
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
        .onChange(of: selectedPost) { _, post in
            showsDetail = post != nil
        }
    }

    private func timeline(_ payload: TodayWorldPayload) -> some View {
        let allGroups = TodayWorldAuthorGroup.make(from: payload)
        let systems = TodayWorldLeaderSystem.make(from: payload, groups: allGroups)
        let selectedSystem = systems.first { $0.key == selectedSystemKey } ?? systems.first

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                TodayWorldDailyDigestView(
                    payload: payload,
                    groups: allGroups,
                    systemCount: systems.count,
                    isRefreshing: store.isLoading
                )

                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        ForEach(systems) { system in
                            TodayWorldLeaderChip(
                                system: system,
                                isSelected: selectedSystem?.key == system.key,
                                action: {
                                    selectedSystemKey = system.key
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .scrollIndicators(.hidden)

                if let selectedSystem {
                    TodayWorldSelectedSystemView(
                        system: selectedSystem,
                        onOpenPost: { selectedPost = $0 },
                        onLoadMore: {
                            await store.loadMore(systemKey: selectedSystem.key)
                        },
                        isLoadingMore: store.isLoadingMore
                    )
                }

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
    var accountSummary: String { accountNames.joined(separator: " / ") }
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
        return ["altman", "pichai", "musk", "zuckerberg"].compactMap { key in
            guard let name = names[key] else { return nil }
            let systemGroups = groups.filter { $0.companyKey == key }
            let leaderSection = payload.sections.first {
                $0.entity?.companyKey == key && $0.entity?.xHandle?.lowercased() == leaderHandle(for: key)
            }
            let leader = systemGroups.first {
                $0.handle?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "@")) == leaderHandle(for: key)
            }
            return TodayWorldLeaderSystem(
                key: key,
                name: name,
                accountNames: accounts[key] ?? [],
                groups: systemGroups,
                postCount: systemGroups.reduce(0) { $0 + $1.posts.count },
                hasMore: payload.sections.contains { $0.entity?.companyKey == key && $0.hasMore },
                leaderName: leaderSection?.entity?.name ?? leader?.authorName ?? fallbackLeaderName(for: key),
                leaderAvatarURL: leaderSection?.entity?.avatarURL.flatMap(URL.init(string:)) ?? leader?.avatarURL
            )
        }
    }

    private static func leaderHandle(for key: String) -> String {
        ["altman": "sama", "pichai": "sundarpichai", "musk": "elonmusk", "zuckerberg": "finkd"][key] ?? ""
    }

    private static func fallbackLeaderName(for key: String) -> String {
        ["altman": "Sam Altman", "pichai": "Sundar Pichai", "musk": "Elon Musk", "zuckerberg": "Mark Zuckerberg"][key] ?? ""
    }
}

private struct TodayWorldLeaderChip: View {
    let system: TodayWorldLeaderSystem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    leaderAvatar
                    VStack(alignment: .leading, spacing: 1) {
                        Text(system.name)
                            .font(.system(size: 14, weight: .bold))
                        Text(system.leaderName)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
                    }
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(system.postCount > 0 ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 5, height: 5)
                    Text(system.postCount > 0 ? "\(system.postCount) 条更新" : "暂无更新")
                        .font(.system(size: 10.5, weight: .semibold))
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(10)
            .frame(width: 142, alignment: .leading)
            .background(isSelected ? Color(uiColor: .label) : Color.secondary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.primary.opacity(0.07), lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
    }

    private var leaderAvatar: some View {
        AvatarView(url: system.leaderAvatarURL, name: system.leaderName, size: 34)
        .overlay { Circle().stroke(Color.white.opacity(isSelected ? 0.25 : 0), lineWidth: 1) }
    }
}

private struct TodayWorldSelectedSystemView: View {
    let system: TodayWorldLeaderSystem
    let onOpenPost: (Post) -> Void
    let onLoadMore: () async -> Void
    let isLoadingMore: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(system.name)
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    Text("\(system.postCount) 条")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(system.accountSummary)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().opacity(0.5)

            if system.groups.isEmpty {
                ContentUnavailableView(
                    "今天暂无动态",
                    systemImage: "clock.badge.questionmark",
                    description: Text("已关注 \(system.accountSummary)，有新内容时会自动出现在这里。")
                )
                .frame(minHeight: 190)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(system.groups) { group in
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
                            Text("\(highlight.0)：\(highlight.1)")
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

private struct TodayWorldAuthorGroup: Identifiable {
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
        let entries = payload.sections.flatMap { section in
            section.items.map { post in
                TodayWorldPostEntry(post: post, section: section)
            }
        }
        .sorted { lhs, rhs in
            postDate(lhs.post) > postDate(rhs.post)
        }

        var groups: [TodayWorldAuthorGroup] = []
        var groupIndexByAuthor: [String: Int] = [:]
        for entry in entries {
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
                roleLabel: entry.section.entity?.type == "company" ? "\(authorName) 官方" : "\(companyName) 成员",
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

                    Text(group.roleLabel)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                ForEach(Array(group.posts.enumerated()), id: \.element.id) { index, post in
                    TodayWorldGroupedPostRow(
                        post: post,
                        isLast: index == group.posts.indices.last
                    ) {
                        onOpenPost(post)
                    }
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

                    Text(post.displayContent)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .lineSpacing(1)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
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
            if let replyHandle {
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
