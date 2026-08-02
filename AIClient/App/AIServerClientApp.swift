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
            if let deploymentStatus {
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
    @Published private(set) var errorMessage: String?

    func load(force: Bool = false) async {
        guard !isLoading, force || payload == nil else { return }
        isLoading = true
        if payload == nil { errorMessage = nil }
        defer { isLoading = false }

        do {
            payload = try await APIClient(baseURL: ServerConfiguration.currentURL)
                .fetchTodayWorld(limit: 8)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            if payload == nil {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "暂时无法读取今日动态"
            }
        }
    }
}

private struct TodayWorldView: View {
    @Binding var showsDetail: Bool
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @StateObject private var store = TodayWorldStore()
    @State private var selectedPost: Post?

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
            await store.load()
        }
        .onChange(of: selectedPost) { _, post in
            showsDetail = post != nil
        }
    }

    private func timeline(_ payload: TodayWorldPayload) -> some View {
        let groups = TodayWorldAuthorGroup.make(from: payload)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                pageHeader(payload)

                TodayWorldBriefingView(payload: payload, groups: groups)

                Text("成员动态")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
                    .padding(.bottom, 8)

                if groups.isEmpty {
                    Text("今天还没有新的动态")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 24)
                } else {
                    ForEach(groups) { group in
                        TodayWorldAuthorGroupView(group: group) { post in
                            selectedPost = post
                        }
                    }
                }

                Color.clear.frame(height: 104)
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.load(force: true) }
    }

    private func pageHeader(_ payload: TodayWorldPayload) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("今日世界")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .tracking(-0.7)

            Spacer()

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(Self.displayDate(payload.date))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var loadingView: some View {
        VStack(spacing: 18) {
            HStack {
                Text("今日世界")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Spacer()
            }

            ForEach(0..<3, id: \.self) { _ in
                HStack(alignment: .top, spacing: 11) {
                    Circle().fill(Color.secondary.opacity(0.12)).frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 10) {
                        Capsule().fill(Color.secondary.opacity(0.12)).frame(width: 128, height: 13)
                        Capsule().fill(Color.secondary.opacity(0.10)).frame(height: 12)
                        Capsule().fill(Color.secondary.opacity(0.08)).frame(width: 230, height: 12)
                    }
                }
            }
        }
        .padding(18)
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

    private static func displayDate(_ value: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: value) else { return value }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }
}

private struct TodayWorldBriefingView: View {
    let payload: TodayWorldPayload
    let groups: [TodayWorldAuthorGroup]

    private var totalCount: Int {
        groups.reduce(0) { $0 + $1.posts.count }
    }

    private var activeAuthorCount: Int { Set(groups.map(\.authorKey)).count }

    private var leadingGroup: TodayWorldAuthorGroup? {
        groups.max { $0.posts.count < $1.posts.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("OpenAI · 今日 \(totalCount) 条动态 · \(activeAuthorCount) 位成员更新")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 24, height: 24)
                    .background(Color.blue.opacity(0.1), in: Circle())

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("今日焦点")
                            .font(.system(size: 16, weight: .bold))
                        Spacer()
                        if totalCount > 0 {
                            Text("\(totalCount) 条更新")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                    }

                    Text(briefingText)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 2)
    }

    private var briefingText: String {
        guard let leadingGroup, let latestPost = leadingGroup.posts.first else {
            return "OpenAI 及已关注成员今天暂未发布新动态。"
        }
        let authorSummary = activeAuthorCount == 1
            ? "\(leadingGroup.authorName) 今日更新 \(leadingGroup.posts.count) 条"
            : "\(leadingGroup.authorName) 等 \(activeAuthorCount) 位成员今日共更新 \(totalCount) 条"
        return "\(authorSummary)。最新：\(latestPost.displayContent)"
    }
}

private struct TodayWorldAuthorGroup: Identifiable {
    let id: String
    let authorKey: String
    let authorName: String
    let handle: String?
    let avatarURL: URL?
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
        for entry in entries {
            let handle = entry.post.authorHandle ?? normalizedHandle(entry.section.entity?.xHandle)
            let authorName = entry.post.authorName.isEmpty
                ? (entry.section.entity?.name ?? "OpenAI")
                : entry.post.authorName
            let authorKey = handle?.lowercased() ?? authorName.lowercased()

            if groups.last?.authorKey == authorKey {
                groups[groups.count - 1].posts.append(entry.post)
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
                roleLabel: entry.section.entity?.type == "company" ? "OpenAI 官方" : "OpenAI 成员",
                posts: [entry.post]
            ))
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
        HStack(alignment: .top, spacing: 12) {
            AvatarView(url: group.avatarURL, name: group.authorName, size: 42)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(group.authorName)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.blue)

                    if let handle = group.handle {
                        Text(handle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                Text(group.roleLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .padding(.bottom, 4)

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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 72) }
    }
}

private struct TodayWorldGroupedPostRow: View {
    let post: Post
    let isLast: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 0) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)

                    if !isLast {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: 1)
                    }
                }
                .frame(width: 8)

                VStack(alignment: .leading, spacing: 5) {
                    if let time = post.formattedTime {
                        Text(time)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }

                    Text(post.displayContent)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if hasContext {
                        contextLine
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, isLast ? 4 : 9)
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
            if media.isVideo, let preview = media.previewURL {
                return TodayWorldMediaItem(url: preview, isVideo: true)
            }
            guard let url = media.displayURL else { return nil }
            return TodayWorldMediaItem(url: url, isVideo: media.isVideo)
        }
    }

    private var ownMediaItems: [TodayWorldMediaItem] {
        let images = post.imageURLs.map { TodayWorldMediaItem(url: $0, isVideo: false) }
        let videoPreviews = (post.videos ?? []).compactMap { video -> TodayWorldMediaItem? in
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
