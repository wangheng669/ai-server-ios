import SwiftUI
import WebKit
import QuartzCore

enum RootTab: Hashable { case observation, investment, learning, people }

private enum FlashFilter: String, CaseIterable, Identifiable {
    case important, tech, equity, commodity, company, geopolitical, other

    var id: Self { self }
    var title: String {
        return switch self {
        case .important: "重要"
        case .tech: "AI科技"
        case .equity: "股票"
        case .commodity: "商品"
        case .company: "公司"
        case .geopolitical: "国际"
        case .other: "综合"
        }
    }

    var serverCategory: String? {
        return switch self {
        case .important: nil
        default: rawValue
        }
    }

    func matches(_ post: Post) -> Bool {
        switch self {
        case .important: post.tagNames.contains("重要")
        default: true
        }
    }
}

private enum WeiboSection: String, CaseIterable, Identifiable {
    case hot
    case following

    var id: Self { self }
    var title: String { self == .hot ? "热搜" : "关注" }
}

private enum YouTubePersonFilter: String, CaseIterable, Identifiable {
    case all = ""
    case wangZhian = "王志安"
    case chaiJing = "柴静"
    case xiaodao = "小岛大浪吹"

    var id: Self { self }
    var title: String { self == .all ? "全部用户" : rawValue }
    var feedID: Int? {
        switch self {
        case .all: nil
        case .wangZhian: 79
        case .chaiJing: 1391
        case .xiaodao: 7911
        }
    }
    var person: String? { self == .all ? nil : rawValue }
    var avatarURL: URL? {
        if self == .xiaodao {
            return URL(string: "https://yt3.googleusercontent.com/ytc/AIdro_mb2vZI-xznESM1CQpzVUOQFe1h9DVsghEWhCHPWfpt7ss=s900-c-k-c0x00ffffff-no-rj")
        }
        guard let feedID else { return nil }
        return URL(string: "/api/ios/v1/rss/feeds/\(feedID)/avatar", relativeTo: ServerConfiguration.currentURL)?.absoluteURL
    }
}

enum FeedChromeLayout {
    static let headerHeight: CGFloat = 0
    static let sourceSelectorSpacing: CGFloat = 12

    static func headerReservationHeight(isHidden: Bool) -> CGFloat {
        isHidden ? 0 : headerHeight
    }

    static func sourceSelectorBottomPadding(rootBottomChromeHeight: CGFloat) -> CGFloat {
        max(0, rootBottomChromeHeight) + sourceSelectorSpacing
    }
}

enum FeedPaginationLayout {
    static func taskPostID(
        visibleTailID: Int,
        rawTailID: Int?,
        usesFilteredPagination: Bool
    ) -> Int {
        usesFilteredPagination ? rawTailID ?? visibleTailID : visibleTailID
    }
}

enum FeedDetailChromePolicy {
    static func hidesRootChrome(isPresented: Bool, isXueqiu: Bool) -> Bool {
        isPresented && !isXueqiu
    }
}

enum FeedSourceTransitionPolicy {
    static let fadeOutDuration = 0.10
    static let fadeInDuration = 0.22
}

enum FeedEntitySelectorPositionPolicy {
    static let allAccountsID = "feed-entity:all"

    static func targetID(selectedID: String?, visibleChoiceIDs: [String]) -> String {
        guard let selectedID, visibleChoiceIDs.contains(selectedID) else { return allAccountsID }
        return selectedID
    }
}

enum XFeedSelectorAvatarPolicy {
    static func resolvedAvatarURL(
        directoryAvatarURL: URL?,
        screenName: String,
        posts: [Post]
    ) -> URL? {
        let handle = normalizedHandle(screenName)
        return posts.first(where: {
            normalizedHandle($0.user?.userScreenName) == handle && $0.avatarURL != nil
        })?.avatarURL ?? directoryAvatarURL
    }

    private static func normalizedHandle(_ value: String?) -> String? {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "@")))
            .lowercased()
        return normalized?.isEmpty == false ? normalized : nil
    }
}

enum EmbeddedWebPresentationPolicy {
    static func opensImmediately(source: FeedSource) -> Bool {
        source == .weibo
    }
}

private struct WeChatAccount: Identifiable {
    let id: Int
    let name: String
}

private struct FeedEntityChoice: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String?
    let avatarURL: URL?
    let feedID: Int?
}

private struct YouTubeFirstVideoPrewarmer: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        YouTubeWarmPlayerPool.shared.prewarm(videoID: videoID)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

struct NewsFeedView: View {
    @Binding private var showsDetail: Bool
    @Binding private var hidesTabBar: Bool
    @Binding private var notificationPostID: Int?
    @StateObject private var model = NewsFeedViewModel()
    @StateObject private var weiboFollowingModel = WeiboFollowingFeedModel()
    @State private var selectedPost: Post?
    @State private var isFeedChromeHidden = false
    @State private var isFeedAtTop = true
    @State private var sourceChromeStates: [FeedSource: Bool] = [:]
    @StateObject private var scrollPositionStore = FeedScrollPositionStore()
    @State private var hasLoadedFeedOnce = false
    @State private var flashFilter: FlashFilter = .important
    @State private var expandedFlashIDs: Set<Int> = []
    @State private var weiboSection: WeiboSection = .hot
    @State private var openingWebPostID: Int?
    @State private var webOpenError: String?
    @State private var preparedWebViews: [Int: WKWebView] = [:]
    @State private var isSourceSelectorExpanded = false
    @State private var isYouTubePersonSelectorExpanded = false
    @State private var isFeedEntitySelectorExpanded = false
    @State private var feedEntitySearch = ""
    @State private var isSourceContentVisible = true
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @Environment(\.rootBottomChromeHeight) private var rootBottomChromeHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let opensZhihuDetailPreview = ProcessInfo.processInfo.arguments.contains("--zhihu-detail-preview")
    private let opensYouTubeDetailPreview = ProcessInfo.processInfo.arguments.contains("--youtube-detail-preview")
    private let opensBilibiliDetailPreview = ProcessInfo.processInfo.arguments.contains("--bilibili-detail-preview")
    private let opensWeChatDetailPreview = ProcessInfo.processInfo.arguments.contains("--wechat-detail-preview")

    init(
        showsDetail: Binding<Bool> = .constant(false),
        hidesTabBar: Binding<Bool> = .constant(false),
        notificationPostID: Binding<Int?> = .constant(nil)
    ) {
        _showsDetail = showsDetail
        _hidesTabBar = hidesTabBar
        _notificationPostID = notificationPostID
        WeiboSessionCookieStore.importFromEnvironmentIfPresent()
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                content
                    .opacity(isSourceContentVisible ? 1 : 0.15)
                    .scaleEffect(isSourceContentVisible ? 1 : 0.997)

                if isSourceSelectorExpanded || isYouTubePersonSelectorExpanded || isFeedEntitySelectorExpanded {
                    Color.black.opacity(0.045)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { closeSelectors() }
                        .gesture(
                            DragGesture(minimumDistance: 4)
                                .onChanged { _ in closeSelectors() }
                        )
                        .transition(.opacity)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    if !isSourceSelectorExpanded {
                        if model.source == .youtube {
                            youtubePersonSelector
                                .transition(userSelectorTransition)
                        } else if supportsFeedEntitySelector {
                            feedEntitySelector
                                .transition(userSelectorTransition)
                        }
                    }
                    sourceSelector
                }
                    .padding(.trailing, 16)
                    .padding(
                        .bottom,
                        FeedChromeLayout.sourceSelectorBottomPadding(
                            rootBottomChromeHeight: rootBottomChromeHeight
                        )
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $selectedPost, onDismiss: {
            showsDetail = false
        }) { post in
            NavigationStack {
                if let source = FeedSource(rawValue: post.source ?? ""),
                   source == .weibo || source == .douyin || source == .baidu,
                   let link = post.linkURL {
                    EmbeddedWebPage(
                        url: link,
                        source: source,
                        preparedWebView: preparedWebViews[post.id],
                        presentedAsSheet: true
                    )
                } else {
                    PostDetailView(
                        post: post,
                        preloadedNewYorkTimesArticle: model.preloadedNewYorkTimesArticle(for: post.id),
                        rssAvatarURL: rssDirectoryAvatarURL(for: post),
                        presentedAsSheet: true
                    )
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationContentInteraction(.scrolls)
        }
        .onChange(of: rootTabIsActive, initial: true) { _, isActive in
            if isActive && scenePhase == .active {
                model.startRealtime()
            } else {
                model.stopRealtime()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if rootTabIsActive, phase == .active {
                model.startRealtime()
                if hasLoadedFeedOnce {
                    Task { await model.refresh() }
                }
            } else {
                model.stopRealtime()
            }
        }
        .onChange(of: selectedPost, initial: true) { _, post in
            if let post {
                showsDetail = FeedDetailChromePolicy.hidesRootChrome(
                    isPresented: true,
                    isXueqiu: post.isXueqiu
                )
            }
            if post == nil {
                isFeedChromeHidden = false
                hidesTabBar = false
                preparedWebViews.removeAll()
            }
        }
        .task(id: notificationPostID) {
            guard let postID = notificationPostID else { return }
            defer { notificationPostID = nil }
            guard let post = try? await APIClient(baseURL: ServerConfiguration.currentURL).fetchPost(id: postID) else {
                return
            }
            selectedPost = post
        }
        .onChange(of: model.pendingRealtimePosts.count) { _, count in
            guard count > 0, isFeedAtTop else { return }
            withAnimation(.easeOut(duration: 0.2)) { model.acceptPendingRealtimePosts() }
        }
        .onChange(of: isFeedAtTop) { _, isAtTop in
            guard isAtTop, !model.pendingRealtimePosts.isEmpty else { return }
            withAnimation(.easeOut(duration: 0.2)) { model.acceptPendingRealtimePosts() }
        }
        .onChange(of: isFeedChromeHidden, initial: true) { _, isHidden in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                hidesTabBar = isHidden
            }
        }
        .onDisappear {
            showsDetail = false
            hidesTabBar = false
        }
        .task(id: model.source.rawValue) {
            await model.loadInitial()
            hasLoadedFeedOnce = true
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await model.loadInitial()
            #if DEBUG
            if opensZhihuDetailPreview,
               selectedPost == nil,
               let first = model.posts.first(where: { $0.sourceName == "知乎" }) {
                selectedPost = first
            } else if opensWeChatDetailPreview,
                      selectedPost == nil,
                      let first = model.posts.first(where: { post in
                          guard let source = post.source,
                                source.hasPrefix("rss:"),
                                let feedID = Int(source.dropFirst(4)) else { return false }
                          return APIClient.weChatFeedIDs.contains(feedID)
                      }) {
                selectedPost = first
            } else if opensYouTubeDetailPreview,
                      selectedPost == nil,
                      let first = model.posts.first(where: \.isYouTube) {
                if ProcessInfo.processInfo.arguments.contains("--youtube-prewarm-preview") {
                    try? await Task.sleep(for: .seconds(10))
                }
                selectedPost = first
            } else if opensBilibiliDetailPreview,
                      selectedPost == nil,
                      let first = model.posts.first(where: \.isBilibili) {
                selectedPost = first
            }
            #endif
            await model.warmSourceCache()
        }
    }

    private var sourceSelector: some View {
        HStack(alignment: .center, spacing: 8) {
            if isSourceSelectorExpanded {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 1) {
                            ForEach(FeedSource.allCases) { source in
                                sourceOption(source)
                                    .id(source)
                            }
                        }
                        .padding(4)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear {
                        Task { @MainActor in
                            await Task.yield()
                            proxy.scrollTo(model.source, anchor: .center)
                        }
                    }
                }
                .frame(width: sourceSelectorExpandedWidth, height: 54)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(InvestmentDesign.divider.opacity(0.8), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.10), radius: 16, y: 7)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.94, anchor: .trailing).combined(with: .opacity),
                        removal: .scale(scale: 0.97, anchor: .trailing).combined(with: .opacity)
                    )
                )
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.smooth(duration: 0.22)) {
                    isYouTubePersonSelectorExpanded = false
                    isFeedEntitySelectorExpanded = false
                    feedEntitySearch = ""
                    isSourceSelectorExpanded.toggle()
                }
            } label: {
                ZStack(alignment: .bottom) {
                    sourceIcon(model.source)
                        .frame(width: 24, height: 24)
                        .offset(y: isSourceSelectorExpanded ? -3 : 0)

                    Image(systemName: "chevron.up")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 5)
                        .opacity(isSourceSelectorExpanded ? 1 : 0)
                }
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(InvestmentDesign.divider.opacity(0.9), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("选择观点来源，当前\(model.source.title)")
            .accessibilityValue(isSourceSelectorExpanded ? "已展开" : "已收起")
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: isSourceSelectorExpanded)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.source)
    }

    private var sourceSelectorExpandedWidth: CGFloat {
        let contentWidth = CGFloat(FeedSource.allCases.count) * 55 + 8
        let availableWidth = UIScreen.main.bounds.width - 32 - 52
        return min(contentWidth, max(54, availableWidth))
    }

    private var userSelectorTransition: AnyTransition {
        .move(edge: .trailing)
            .combined(with: .scale(scale: 0.86, anchor: .trailing))
            .combined(with: .opacity)
    }

    private var youtubePersonSelector: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.smooth(duration: 0.22)) {
                isSourceSelectorExpanded = false
                isFeedEntitySelectorExpanded = false
                feedEntitySearch = ""
                isYouTubePersonSelectorExpanded.toggle()
            }
        } label: {
            youtubePersonAvatar(currentYouTubePersonFilter, size: 38)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle().stroke(
                        model.selectedYouTubePerson == nil
                            ? InvestmentDesign.divider.opacity(0.9)
                            : InvestmentDesign.accent.opacity(0.65),
                        lineWidth: model.selectedYouTubePerson == nil ? 0.5 : 1.5
                    )
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择 YouTube 用户，当前\(currentYouTubePersonFilter.title)")
        .accessibilityValue(isYouTubePersonSelectorExpanded ? "已展开" : "已收起")
        .overlay(alignment: .bottomTrailing) {
            if isYouTubePersonSelectorExpanded {
                youtubePersonMenu
                    .offset(y: -52)
                .transition(.scale(scale: 0.94, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: isYouTubePersonSelectorExpanded)
    }

    private var youtubePersonMenu: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("选择用户")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 7)
                .padding(.bottom, 1)

            ForEach(YouTubePersonFilter.allCases) { option in
                let isSelected = model.selectedYouTubePerson == option.person
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    isYouTubePersonSelectorExpanded = false
                    Task { await model.selectYouTubePerson(option.person) }
                } label: {
                    HStack(spacing: 11) {
                        youtubePersonAvatar(option, size: 36)
                        Text(option.title)
                            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(InvestmentDesign.accent)
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 9)
                    .frame(width: 176, height: 49)
                    .background(
                        isSelected ? InvestmentDesign.accent.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(InvestmentDesign.divider.opacity(0.8), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.10), radius: 16, y: 7)
    }

    private var supportsFeedEntitySelector: Bool {
        switch model.source {
        case .x, .xueqiu, .wechat, .rss:
            true
        case .weibo:
            weiboSection == .following
        default:
            false
        }
    }

    private var feedEntityChoices: [FeedEntityChoice] {
        if model.source == .x {
            return model.xFeedUsers.map { user in
                FeedEntityChoice(
                    id: "x:\(user.id)",
                    name: user.name,
                    subtitle: "@\(user.screenName.trimmingCharacters(in: CharacterSet(charactersIn: "@")))",
                    avatarURL: XFeedSelectorAvatarPolicy.resolvedAvatarURL(
                        directoryAvatarURL: user.avatarURL,
                        screenName: user.screenName,
                        posts: model.posts(for: .x)
                    ),
                    feedID: nil
                )
            }
        }
        if model.source == .wechat {
            return weChatAccounts.map { account in
                let feed = model.rssFeeds.first { $0.id == account.id }
                return FeedEntityChoice(
                    id: "rss:\(account.id)",
                    name: account.name,
                    subtitle: nil,
                    avatarURL: feed?.preferredAvatarURL,
                    feedID: account.id
                )
            }
        }
        if model.source == .rss {
            return model.rssFeeds.map { feed in
                FeedEntityChoice(
                    id: "rss:\(feed.id)",
                    name: feed.name,
                    subtitle: nil,
                    avatarURL: feed.preferredAvatarURL,
                    feedID: feed.id
                )
            }
        }

        let posts: [Post]
        if model.source == .weibo {
            posts = weiboFollowingModel.directoryPosts
        } else if model.source == .xueqiu {
            posts = model.xueqiuDirectoryPosts
        } else {
            posts = model.posts(for: model.source)
        }
        var seen = Set<String>()
        return posts.compactMap { post in
            guard let id = feedEntityID(for: post, source: model.source), seen.insert(id).inserted else {
                return nil
            }
            let handle = post.user?.userScreenName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = handle.map {
                "@\($0.trimmingCharacters(in: CharacterSet(charactersIn: "@")))"
            }
            return FeedEntityChoice(
                id: id,
                name: post.authorName,
                subtitle: model.source == .x ? subtitle : nil,
                avatarURL: post.avatarURL,
                feedID: feedID(from: post.source)
            )
        }
    }

    private var selectedFeedEntityID: String? {
        if model.source == .wechat {
            return model.selectedWeChatFeedID.map { "rss:\($0)" }
        }
        if model.source == .rss {
            return model.selectedRSSFeedID.map { "rss:\($0)" }
        }
        if model.source == .weibo {
            return weiboFollowingModel.selectedFeedID.map { "rss:\($0)" }
        }
        if model.source == .x {
            return model.selectedXUserID.map { "x:\($0)" }
        }
        if model.source == .xueqiu {
            return model.selectedXueqiuFeedID.map { "rss:\($0)" }
        }
        return nil
    }

    private var filteredFeedEntityChoices: [FeedEntityChoice] {
        let query = feedEntitySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return feedEntityChoices }
        return feedEntityChoices.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var feedEntitySelector: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.smooth(duration: 0.22)) {
                isSourceSelectorExpanded = false
                isYouTubePersonSelectorExpanded = false
                isFeedEntitySelectorExpanded.toggle()
                if !isFeedEntitySelectorExpanded { feedEntitySearch = "" }
            }
        } label: {
            feedEntityAvatar(selectedFeedEntityID, size: 38)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle().stroke(
                        selectedFeedEntityID == nil
                            ? InvestmentDesign.divider.opacity(0.9)
                            : InvestmentDesign.accent.opacity(0.65),
                        lineWidth: selectedFeedEntityID == nil ? 0.5 : 1.5
                    )
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择账号，当前\(selectedFeedEntityChoice?.name ?? "全部账号")")
        .accessibilityValue(isFeedEntitySelectorExpanded ? "已展开" : "已收起")
        .overlay(alignment: .bottomTrailing) {
            if isFeedEntitySelectorExpanded {
                feedEntityMenu
                    .offset(y: -52)
                    .transition(.scale(scale: 0.94, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: isFeedEntitySelectorExpanded)
    }

    private var selectedFeedEntityChoice: FeedEntityChoice? {
        guard let selectedFeedEntityID else { return nil }
        return feedEntityChoices.first { $0.id == selectedFeedEntityID }
    }

    private var feedEntityMenu: some View {
        VStack(spacing: 0) {
            HStack {
                Text("选择账号")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(feedEntityChoices.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)

            if feedEntityChoices.count > 8 {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("搜索账号", text: $feedEntitySearch)
                        .font(.system(size: 13))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        feedEntityMenuRow(nil)
                            .id(FeedEntitySelectorPositionPolicy.allAccountsID)
                        ForEach(filteredFeedEntityChoices) { choice in
                            feedEntityMenuRow(choice)
                                .id(choice.id)
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(feedEntityChoices.count > 6 ? .visible : .hidden)
                .task(id: feedEntityMenuScrollTargetID) {
                    await Task.yield()
                    proxy.scrollTo(feedEntityMenuScrollTargetID, anchor: .center)
                }
            }
        }
        .frame(
            width: feedEntityChoices.count > 8 ? 224 : 196,
            height: feedEntityMenuHeight
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(InvestmentDesign.divider.opacity(0.8), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }

    private var feedEntityMenuScrollTargetID: String {
        FeedEntitySelectorPositionPolicy.targetID(
            selectedID: selectedFeedEntityID,
            visibleChoiceIDs: filteredFeedEntityChoices.map(\.id)
        )
    }

    private var feedEntityMenuHeight: CGFloat {
        let headerHeight: CGFloat = 32
        let searchHeight: CGFloat = feedEntityChoices.count > 8 ? 42 : 0
        let visibleRows = min(filteredFeedEntityChoices.count + 1, 5)
        return min(344, headerHeight + searchHeight + CGFloat(visibleRows * 52) + 8)
    }

    private func feedEntityMenuRow(_ choice: FeedEntityChoice?) -> some View {
        let isSelected = selectedFeedEntityID == choice?.id
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectFeedEntity(choice)
        } label: {
            HStack(spacing: 10) {
                feedEntityAvatar(choice?.id, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice?.name ?? "全部账号")
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    if let subtitle = choice?.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(InvestmentDesign.accent)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(height: choice?.subtitle == nil ? 47 : 52)
            .background(
                isSelected ? InvestmentDesign.accent.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice?.name ?? "全部账号")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func feedEntityAvatar(_ id: String?, size: CGFloat) -> some View {
        if let id, let choice = feedEntityChoices.first(where: { $0.id == id }) {
            AvatarView(url: choice.avatarURL, name: choice.name, size: size)
                .clipShape(Circle())
        } else {
            let choices = Array(feedEntityChoices.prefix(3))
            if choices.isEmpty {
                Image(systemName: "person.2.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(Color(uiColor: .secondarySystemBackground), in: Circle())
            } else {
                ZStack {
                    ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                        AvatarView(url: choice.avatarURL, name: choice.name, size: size * 0.58)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))
                            .offset(entityAvatarOffset(index: index, size: size))
                    }
                }
                .frame(width: size, height: size)
                .background(Color(uiColor: .secondarySystemBackground), in: Circle())
            }
        }
    }

    private func entityAvatarOffset(index: Int, size: CGFloat) -> CGSize {
        switch index {
        case 0: CGSize(width: -size * 0.18, height: -size * 0.14)
        case 1: CGSize(width: size * 0.18, height: -size * 0.14)
        default: CGSize(width: 0, height: size * 0.20)
        }
    }

    private func selectFeedEntity(_ choice: FeedEntityChoice?) {
        withAnimation(.smooth(duration: 0.20)) {
            isFeedEntitySelectorExpanded = false
            feedEntitySearch = ""
            if model.source == .wechat {
                Task { await model.selectWeChatFeed(choice?.feedID) }
            } else if model.source == .rss {
                Task { await model.selectRSSFeed(choice?.feedID) }
            } else if model.source == .weibo {
                Task { await weiboFollowingModel.selectFeed(choice?.feedID) }
            } else if model.source == .x {
                let user = choice.flatMap { choice in
                    model.xFeedUsers.first { "x:\($0.id)" == choice.id }
                }
                Task { await model.selectXUser(user) }
            } else if model.source == .xueqiu {
                Task { await model.selectXueqiuFeed(choice?.feedID) }
            }
        }
    }

    private func feedEntityID(for post: Post, source: FeedSource) -> String? {
        if source == .x {
            guard let handle = post.user?.userScreenName?
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "@"))),
                  !handle.isEmpty else { return nil }
            return "x:\(handle.lowercased())"
        }
        guard let rawSource = post.source?.lowercased(), rawSource.hasPrefix("rss:") else { return nil }
        return rawSource
    }

    private func feedID(from source: String?) -> Int? {
        guard let source, source.lowercased().hasPrefix("rss:") else { return nil }
        return Int(source.dropFirst(4))
    }

    private var currentYouTubePersonFilter: YouTubePersonFilter {
        YouTubePersonFilter.allCases.first { $0.person == model.selectedYouTubePerson } ?? .all
    }

    @ViewBuilder
    private func youtubePersonAvatar(_ option: YouTubePersonFilter, size: CGFloat) -> some View {
        if option == .all {
            ZStack {
                youtubeRemoteAvatar(.wangZhian, size: size * 0.58)
                    .offset(x: -size * 0.18, y: -size * 0.14)
                youtubeRemoteAvatar(.chaiJing, size: size * 0.58)
                    .offset(x: size * 0.18, y: -size * 0.14)
                youtubeRemoteAvatar(.xiaodao, size: size * 0.58)
                    .offset(y: size * 0.20)
            }
            .frame(width: size, height: size)
            .background(Color(uiColor: .secondarySystemBackground), in: Circle())
        } else {
            youtubeRemoteAvatar(option, size: size)
        }
    }

    private func youtubeRemoteAvatar(_ option: YouTubePersonFilter, size: CGFloat) -> some View {
        AsyncImage(url: option.avatarURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemBackground))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: max(1, size * 0.045)))
    }

    private func sourceOption(_ source: FeedSource) -> some View {
        let isSelected = model.source == source
        return Button {
            if isSelected {
                closeSourceSelector()
            } else {
                selectSourceFromTap(source)
            }
        } label: {
            ZStack(alignment: .bottom) {
                sourceIcon(source)
                    .frame(width: 24, height: 24)

                Capsule()
                    .fill(InvestmentDesign.accent)
                    .frame(width: 18, height: 3)
                    .padding(.bottom, 2)
                    .opacity(isSelected ? 1 : 0)
            }
                .frame(width: 44, height: 44)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(source.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func closeSourceSelector() {
        withAnimation(.smooth(duration: 0.20)) {
            isSourceSelectorExpanded = false
        }
    }

    private func closeSelectors() {
        withAnimation(.smooth(duration: 0.20)) {
            isSourceSelectorExpanded = false
            isYouTubePersonSelectorExpanded = false
            isFeedEntitySelectorExpanded = false
            feedEntitySearch = ""
        }
    }

    @ViewBuilder private func sourceIcon(_ source: FeedSource) -> some View {
        if source == .newYorkTimes {
            Text("NYT")
                .font(.system(size: 10.5, weight: .black, design: .serif))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 22)
                .fixedSize(horizontal: true, vertical: false)
        } else if source == .wechat {
            Image("WeChatMark")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 23, height: 23)
        } else if source == .x {
            Text("X")
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundStyle(.primary)
                .frame(width: 22, height: 22)
        } else if source == .baidu {
            Image("BaiduMark")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 23, height: 23)
        } else if source == .xueqiu {
            Image("XueqiuMark")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: model.source == .xueqiu ? 28 : 22, height: model.source == .xueqiu ? 28 : 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else if source == .truth {
            Image("TruthMark")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: model.source == .truth ? 30 : 22, height: model.source == .truth ? 30 : 22)
                .clipShape(Circle())
        } else if source == .laozhong {
            Image("LaozhongMark")
                .resizable()
                .renderingMode(.original)
                .scaledToFill()
                .frame(width: model.source == .laozhong ? 30 : 22, height: model.source == .laozhong ? 30 : 22)
                .clipShape(Circle())
        } else if let asset = source.iconAsset {
            Image(asset).resizable().renderingMode(.template).scaledToFit()
                .foregroundStyle(source.iconColor).frame(width: 20, height: 20)
        } else {
            Image(systemName: source.systemIcon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(source.iconColor).frame(width: 20, height: 20)
        }
    }

    private var content: some View {
        TabView(selection: Binding(
            get: { model.source },
            set: { selectSource($0) }
        )) {
            ForEach(FeedSource.allCases) { source in
                // Keep every page mounted. Replacing distant pages with empty views
                // changes the page controller's contents while an interactive swipe
                // is settling, which causes abrupt snapping and unreliable jumps when
                // the user selects a source that is more than one page away.
                sourcePage(source)
                    .tag(source)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func sourcePage(_ source: FeedSource) -> some View {
        if source == .weibo {
            weiboPage
        } else {
            let posts = model.posts(for: source)
            ZStack {
                feedList(for: source, posts: posts)
                    .opacity(posts.isEmpty ? 0 : 1)
                    .allowsHitTesting(!posts.isEmpty)

                if posts.isEmpty {
                    feedStatus(for: source)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: "\(rootTabIsActive)-\(source.rawValue)") {
                if rootTabIsActive, source == .x {
                    await model.loadXFeedUsersIfNeeded()
                }
                if rootTabIsActive, source == .rss || source == .wechat {
                    await model.loadRSSFeedsIfNeeded(forceRefresh: source == .wechat)
                }
            }
        }
    }

    private var weiboPage: some View {
        VStack(spacing: 0) {
            Color.clear.frame(
                height: FeedChromeLayout.headerReservationHeight(isHidden: isFeedChromeHidden)
            )
            weiboSectionSelector
            Divider().opacity(0.5)
            if weiboSection == .hot {
                let posts = model.posts(for: .weibo)
                ZStack {
                    feedList(for: .weibo, posts: posts, topInset: 0)
                        .opacity(posts.isEmpty ? 0 : 1)
                        .allowsHitTesting(!posts.isEmpty)
                    if posts.isEmpty { feedStatus(for: .weibo, topInset: 0) }
                }
            } else {
                weiboFollowingFeed
            }
        }
        .task(id: rootTabIsActive) {
            if rootTabIsActive, weiboSection == .following {
                await weiboFollowingModel.loadInitial()
            }
        }
        .onChange(of: weiboSection) { _, section in
            guard section == .following else { return }
            Task { await weiboFollowingModel.loadInitial() }
        }
    }

    private var weiboSectionSelector: some View {
        HStack(spacing: 28) {
            ForEach(WeiboSection.allCases) { section in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        weiboSection = section
                        isFeedEntitySelectorExpanded = false
                        feedEntitySearch = ""
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(section.title)
                            .font(.system(size: 15, weight: weiboSection == section ? .semibold : .regular))
                            .foregroundStyle(weiboSection == section ? Color.primary : Color.secondary)

                        Capsule()
                            .fill(weiboSection == section ? InvestmentDesign.accent : .clear)
                            .frame(width: 16, height: 2)
                    }
                    .frame(width: 42, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(weiboSection == section ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
        .sensoryFeedback(.selection, trigger: weiboSection)
    }

    private var weiboFollowingFeed: some View {
        let followingPosts = visibleWeiboFollowingPosts
        return ZStack {
            if !followingPosts.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(followingPosts) { post in
                            WeiboFollowingRow(post: post)
                                .contentShape(Rectangle())
                                .onTapGesture { openPost(post) }
                                .task(id: rootTabIsActive) {
                                    guard rootTabIsActive, post.id == followingPosts.last?.id else { return }
                                    await weiboFollowingModel.loadMoreIfNeeded(current: post)
                                }
                            Divider()
                                .overlay(Color.primary.opacity(0.04))
                                .padding(.leading, 56)
                        }
                        if weiboFollowingModel.isLoadingMore {
                            ProgressView().padding(20)
                        } else if weiboFollowingModel.errorMessage != nil {
                            Button("加载失败，点按重试") {
                                if let last = weiboFollowingModel.posts.last {
                                    Task { await weiboFollowingModel.loadMoreIfNeeded(current: last) }
                                }
                            }
                            .font(.footnote)
                            .padding(16)
                        }
                        Color.clear.frame(height: 55)
                    }
                }
            } else if weiboFollowingModel.isLoading {
                ProgressView("正在加载关注内容").font(.footnote)
            } else if let error = weiboFollowingModel.errorMessage {
                ContentUnavailableView {
                    Label("关注内容加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("重新加载") { Task { await weiboFollowingModel.refresh() } }
                }
            } else {
                ContentUnavailableView(
                    weiboFollowingModel.selectedFeedID == nil ? "暂无关注内容" : "该账号暂时没有新内容",
                    systemImage: "person.2"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var visibleWeiboFollowingPosts: [Post] {
        weiboFollowingModel.posts
    }

    private func feedList(
        for source: FeedSource,
        posts: [Post],
        topInset: CGFloat = FeedChromeLayout.headerHeight
    ) -> some View {
        let visiblePosts = visiblePosts(for: source, posts: posts)
        let isSelectedRSSPage = source == .rss && model.selectedRSSFeedID != nil
        let isSelectedWeChatPage = source == .wechat && model.selectedWeChatFeedID != nil
        let usesFilteredPagination = source == .flash
            || (source == .rss && !isSelectedRSSPage)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: topInset).id("feed-top")
                    if source == .rss {
                        if model.isLoadingRSSSelection {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("正在加载该来源")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                        }
                    }
                    if source == .wechat {
                        if model.isLoadingWeChatSelection {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("正在加载该来源")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                        }
                    }
                    if source == .flash {
                        flashFeedHeader
                        if visiblePosts.isEmpty, !posts.isEmpty {
                            ContentUnavailableView(
                                "暂无\(flashFilter.title)快讯",
                                systemImage: "line.3.horizontal.decrease.circle"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                        }
                    }
                    Group {
                        if source == .youtube {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 2),
                                alignment: .leading,
                                spacing: 8
                            ) {
                                ForEach(Array(visiblePosts.enumerated()), id: \.element.id) { index, post in
                                    feedPostCell(source: source, post: post, index: index, posts: posts)
                                }
                            }
                            .padding(8)
                        } else {
                            ForEach(Array(visiblePosts.enumerated()), id: \.element.id) { index, post in
                                feedPostCell(source: source, post: post, index: index, posts: posts)
                                if source == .flash, index == 2, visiblePosts.count > 3 {
                                    flashUnreadDivider(count: min(visiblePosts.count - 3, 3))
                                } else if source == .wechat {
                                    Color.clear.frame(height: 10)
                                } else {
                                    Divider().opacity(source == .flash ? 0.42 : 0.6)
                                        .padding(.leading, source == .flash ? 84 : 0)
                                }
                            }
                        }
                    }
                    if let tail = visiblePosts.last {
                        let paginationTaskPostID = FeedPaginationLayout.taskPostID(
                            visibleTailID: tail.id,
                            rawTailID: posts.last?.id,
                            usesFilteredPagination: usesFilteredPagination
                        )
                        Color.clear
                            .frame(height: 1)
                            .task(id: "\(rootTabIsActive)-page-\(source.rawValue)-\(paginationTaskPostID)") {
                                guard rootTabIsActive, source == model.source else { return }
                                if isSelectedRSSPage {
                                    await model.loadMoreSelectedRSSIfNeeded(current: tail)
                                } else if isSelectedWeChatPage {
                                    await model.loadMoreSelectedWeChatIfNeeded(current: tail)
                                } else {
                                    await model.loadMoreIfNeeded(
                                        current: tail,
                                        thresholdPostID: usesFilteredPagination ? tail.id : nil
                                    )
                                }
                            }
                    }
                    if visiblePosts.isEmpty,
                       !posts.isEmpty,
                       !isSelectedRSSPage,
                       let rawTail = posts.last {
                        Color.clear
                            .frame(height: 1)
                            .task(id: "\(rootTabIsActive)-empty-page-\(rawTail.id)") {
                                guard rootTabIsActive, source == model.source else { return }
                                await model.loadMoreIfNeeded(current: rawTail)
                            }
                    }
                    if model.isLoadingMore
                        || (isSelectedRSSPage && model.isLoadingMoreRSSSelection)
                        || (isSelectedWeChatPage && model.isLoadingMoreWeChatSelection) {
                        ProgressView().padding(20)
                    }
                    if model.errorMessage != nil {
                        Button("加载失败，点按重试") {
                            if source == .rss,
                               model.selectedRSSFeedID != nil,
                               let last = model.selectedRSSPosts.last {
                                Task { await model.loadMoreSelectedRSSIfNeeded(current: last) }
                            } else if source == .wechat,
                                      model.selectedWeChatFeedID != nil,
                                      let last = model.selectedWeChatPosts.last {
                                Task { await model.loadMoreSelectedWeChatIfNeeded(current: last) }
                            } else if let last = model.posts.last {
                                Task { await model.loadMoreIfNeeded(current: last) }
                            }
                        }
                            .font(.footnote).padding(16)
                    }
                    Color.clear.frame(height: 55)
                }
                .background(SourceScrollOffsetPreserver(source: source, store: scrollPositionStore))
                .frame(maxWidth: .infinity)
            }
            .modifier(FeedChromeScrollModifier(
                isActive: source == model.source,
                isHidden: $isFeedChromeHidden,
                isAtTop: $isFeedAtTop
            ))
            .allowsHitTesting(openingWebPostID == nil)
            .overlay(alignment: .top) {
                if source == .x, model.source == .x, !model.pendingRealtimePosts.isEmpty {
                    xNewPostsPill {
                        withAnimation(.snappy(duration: 0.35)) {
                            model.acceptPendingRealtimePosts()
                            proxy.scrollTo("feed-top", anchor: .top)
                        }
                    }
                    .padding(.top, isFeedChromeHidden ? 12 : FeedChromeLayout.headerHeight + 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: model.pendingRealtimePosts.count)
            .alert("页面加载失败", isPresented: Binding(
                get: { webOpenError != nil },
                set: { if !$0 { webOpenError = nil } }
            )) {
                Button("知道了", role: .cancel) { webOpenError = nil }
            } message: {
                Text(webOpenError ?? "请稍后重试")
            }
        }
    }

    private func feedPostCell(
        source: FeedSource,
        post: Post,
        index: Int,
        posts: [Post]
    ) -> some View {
        let displayPost = model.postForDisplay(post)
        return NewsCardView(
            post: displayPost,
            rssAvatarURL: rssDirectoryAvatarURL(for: displayPost),
            usesWeChatStyle: source == .wechat,
            isFeaturedBilibili: source == .bilibili && post.id == posts.first?.id,
            isExpandedFlash: expandedFlashIDs.contains(post.id),
            onOpen: { openPost(displayPost) }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(ConditionalTapGestureModifier(
            isEnabled: !(post.sourceName == "X" && !post.videoURLs.isEmpty)
        ) {
            if post.isFlash {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if expandedFlashIDs.contains(post.id) {
                        expandedFlashIDs.remove(post.id)
                    } else {
                        expandedFlashIDs.insert(post.id)
                    }
                }
            } else {
                openPost(displayPost)
            }
        })
        .overlay {
            if openingWebPostID == post.id {
                HStack(spacing: 8) {
                    if let source = FeedSource(rawValue: post.source ?? "") {
                        Image(source == .weibo ? "WeiboMark" : "TikTokMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    }
                    ProgressView().controlSize(.small)
                    Text("正在准备页面")
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .allowsHitTesting(false)
            }
        }
        .task(id: "\(rootTabIsActive)-rss-translate-\(post.id)") {
            await model.translateRSSPostIfNeeded(post)
        }
        .task(id: "\(rootTabIsActive)-youtube-prewarm-\(post.id)") {
            guard rootTabIsActive,
                  source == .youtube,
                  source == model.source,
                  index < 2,
                  let url = displayPost.linkURL else { return }
            await YouTubePlaybackSourceCache.shared.prewarm(
                url: url,
                title: displayPost.displayTitle,
                baseURL: ServerConfiguration.currentURL
            )
        }
    }

    private func rssDirectoryAvatarURL(for post: Post) -> URL? {
        guard post.isRSS,
              let feedID = feedID(from: post.source) else { return nil }
        return model.rssFeeds.first { $0.id == feedID }?.preferredAvatarURL
    }

    private func xNewPostsPill(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                HStack(spacing: -8) {
                    ForEach(Array(model.pendingRealtimePosts.prefix(3)), id: \.id) { post in
                        AvatarView(url: post.avatarURL, name: post.authorName, size: 28)
                            .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                    }
                }
                Text(model.pendingRealtimePosts.count == 1 ? "1 条新帖" : "\(model.pendingRealtimePosts.count) 条新帖")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.blue, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.pendingRealtimePosts.count) 条新帖子，点按回到顶部")
    }

    private func openPost(_ post: Post) {
        guard selectedPost?.id != post.id else { return }
        guard let source = FeedSource(rawValue: post.source ?? ""),
              source == .weibo || source == .douyin,
              let url = post.linkURL else {
            selectedPost = post
            return
        }
        if EmbeddedWebPresentationPolicy.opensImmediately(source: source) {
            selectedPost = post
            return
        }
        if preparedWebViews[post.id] != nil {
            selectedPost = post
            return
        }
        guard openingWebPostID == nil else { return }
        openingWebPostID = post.id
        Task {
            do {
                let webView = try await EmbeddedWebPagePreloader().load(url)
                guard !Task.isCancelled else { return }
                preparedWebViews[post.id] = webView
                openingWebPostID = nil
                selectedPost = post
            } catch {
                guard !Task.isCancelled else { return }
                openingWebPostID = nil
                let platformName = source == .weibo ? "微博" : "抖音"
                webOpenError = "暂时无法打开\(platformName)页面，请检查网络后重试。"
            }
        }
    }

    private func visiblePosts(for source: FeedSource, posts: [Post]) -> [Post] {
        if source == .wechat, model.selectedWeChatFeedID != nil {
            return model.selectedWeChatPosts
        }
        if source == .rss {
            let rssPosts: [Post]
            if model.selectedRSSFeedID != nil {
                rssPosts = model.selectedRSSPosts
            } else {
                rssPosts = posts.filter { !$0.hasDedicatedFeedTab }
            }
            return rssPosts
        }
        guard source == .flash else { return posts }
        return posts.filter { flashFilter.matches($0) }
    }

    private var rssQualityThreshold: Double { 6.0 }

    private var weChatAccounts: [WeChatAccount] {
        [
            .init(id: 57, name: "猫笔刀"),
            .init(id: 2373, name: "小互 AI"),
            .init(id: 19, name: "量子位")
        ]
    }

    private func sourceAvatarButton(
        id: Int?,
        name: String,
        avatarURL: URL?,
        isSelected: Bool,
        rejectsUpscaledImages: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    if let id {
                        AvatarView(
                            url: avatarURL,
                            name: name,
                            size: 34,
                            rejectsUpscaledImages: rejectsUpscaledImages
                        )
                            .id(id)
                    } else {
                        Circle()
                            .fill(Color.secondary.opacity(0.10))
                            .frame(width: 34, height: 34)
                            .overlay {
                                Image(systemName: "square.grid.2x2.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                            }
                    }
                }
                .overlay {
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                        .padding(-2.5)
                }

                Text(name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .frame(width: 52)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("筛选来源：\(name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var flashFeedHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FlashFilter.allCases) { filter in
                    Button {
                        guard flashFilter != filter else { return }
                        withAnimation(.easeOut(duration: 0.18)) { flashFilter = filter }
                        Task { await model.selectFlashCategory(filter.serverCategory) }
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 14, weight: flashFilter == filter ? .semibold : .medium))
                            .foregroundStyle(flashFilter == filter ? Color.white : Color.secondary)
                            .padding(.horizontal, 17)
                            .frame(height: 34)
                            .background(
                                flashFilter == filter ? Color.accentColor : Color(uiColor: .secondarySystemBackground),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(flashFilter == filter ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
    }

    private func flashUnreadDivider(count: Int) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 0.5)
            Text("\(count) 条新快讯")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.blue)
                .fixedSize()
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 0.5)
        }
        .padding(.leading, 84)
        .padding(.trailing, 16)
        .frame(height: 38)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func feedStatus(
        for source: FeedSource,
        topInset: CGFloat = FeedChromeLayout.headerHeight
    ) -> some View {
        if source == model.source, model.isLoading {
            FeedTimelineLoadingView(topInset: topInset)
        } else {
            VStack {
                if source == model.source, let error = model.errorMessage {
                    ContentUnavailableView { Label("网络连接失败", systemImage: "wifi.exclamationmark") }
                        description: { Text(error) }
                        actions: { Button("重新加载") { Task { await model.refresh() } } }
                } else {
                    ContentUnavailableView(emptyFeedTitle(for: source), systemImage: "tray")
                }
            }
            .padding(.top, topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func emptyFeedTitle(for source: FeedSource) -> String {
        if source == .x, model.selectedXUserID != nil { return "该账号暂时没有新内容" }
        if source == .xueqiu, model.selectedXueqiuFeedID != nil { return "该账号暂时没有新内容" }
        if source == .youtube, model.selectedYouTubePerson != nil { return "该用户暂时没有新内容" }
        return "这个频道暂时没有新内容"
    }

    private func selectSource(_ source: FeedSource) {
        guard source != model.source else { return }
        closeSelectors()
        sourceChromeStates[model.source] = isFeedChromeHidden
        isFeedChromeHidden = sourceChromeStates[source] ?? false
        model.select(source)
    }

    private func selectSourceFromTap(_ source: FeedSource) {
        guard source != model.source else { return }
        UISelectionFeedbackGenerator().selectionChanged()

        guard !reduceMotion else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectSource(source)
                isSourceSelectorExpanded = false
            }
            return
        }

        withAnimation(.easeOut(duration: FeedSourceTransitionPolicy.fadeOutDuration)) {
            isSourceContentVisible = false
            isSourceSelectorExpanded = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + FeedSourceTransitionPolicy.fadeOutDuration) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectSource(source)
            }

            withAnimation(.easeInOut(duration: FeedSourceTransitionPolicy.fadeInDuration)) {
                isSourceContentVisible = true
            }
        }
    }

    private func open(_ path: String) {
        if let url = URL(string: path, relativeTo: ServerConfiguration.currentURL)?.absoluteURL { openURL(url) }
    }

}

private struct FeedTimelineLoadingView: View {
    let topInset: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Color.clear.frame(height: topInset)
                ForEach(0..<3, id: \.self) { index in
                    loadingCard(index: index)
                    Divider().padding(.leading, 68)
                }
            }
        }
        .scrollDisabled(true)
        .foregroundStyle(Color.secondary.opacity(0.14))
        .redacted(reason: .placeholder)
        .overlay {
            if !reduceMotion {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.48), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: proxy.size.width * 0.7)
                    .rotationEffect(.degrees(18))
                    .offset(x: shimmerOffset * proxy.size.width * 1.7)
                }
                .mask {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            Color.clear.frame(height: topInset)
                            ForEach(0..<3, id: \.self) { index in
                                loadingCard(index: index)
                            }
                        }
                    }
                    .scrollDisabled(true)
                }
                .allowsHitTesting(false)
            }
        }
        .task {
            guard !reduceMotion else { return }
            shimmerOffset = -1
            withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                shimmerOffset = 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载内容")
    }

    private func loadingCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 5).frame(width: 132, height: 14)
                    RoundedRectangle(cornerRadius: 4).frame(width: 84, height: 11)
                }
            }
            RoundedRectangle(cornerRadius: 5).frame(height: 13)
            RoundedRectangle(cornerRadius: 5).frame(width: 245, height: 13)
            if index == 0 { RoundedRectangle(cornerRadius: 14).frame(height: 190) }
            HStack(spacing: 36) {
                ForEach(0..<4, id: \.self) { _ in Circle().frame(width: 17, height: 17) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

@MainActor
private final class EmbeddedWebPagePreloader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<WKWebView, Error>?

    func load(_ url: URL) async throws -> WKWebView {
        let configuration = EmbeddedWebView.configuration(for: url)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        if WeiboEmbeddedPagePolicy.shouldRestoreSession(for: url) {
            await WeiboSessionCookieStore.install(
                in: configuration.websiteDataStore.httpCookieStore
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.navigationDelegate = self
            self.webView = webView
            webView.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20))

            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
                self?.finish(.failure(URLError(.timedOut)))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await finishWhenRendered(webView) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func finishWhenRendered(_ webView: WKWebView) async {
        let script = #"""
        (() => {
          const visible = (element) => {
            if (!element) return false;
            const style = getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== 'none' && style.visibility !== 'hidden' &&
              Number(style.opacity || 1) > 0 && rect.width > 0 && rect.height > 0;
          };
          const loading = Array.from(document.querySelectorAll(
            '[aria-busy="true"], [class*="loading"], [class*="spinner"], [class*="skeleton"]'
          )).some(visible);
          const bodyText = (document.body?.innerText || '').replace(/\s+/g, ' ').trim();
          const textLoading = /^(加载中|正在加载)[…\.]*$/.test(bodyText);
          const hasImage = Array.from(document.images).some((image) =>
            visible(image) && image.complete && image.naturalWidth > 0
          );
          const hasVideo = Array.from(document.querySelectorAll('video')).some((video) =>
            visible(video) && video.readyState >= 2
          );
          const hasContent = bodyText.length >= 80 || hasImage || hasVideo;
          return `${document.readyState}|${loading || textLoading ? 1 : 0}|${hasContent ? 1 : 0}`;
        })();
        """#

        var stableChecks = 0
        for _ in 0..<40 {
            guard continuation != nil else { return }
            if let fingerprint = try? await webView.evaluateJavaScript(script) as? String {
                let parts = fingerprint.split(separator: "|")
                let isReady = parts.first == "complete"
                let isLoading = parts.count > 1 && parts[1] == "1"
                let hasContent = parts.count > 2 && parts[2] == "1"
                if isReady && !isLoading && hasContent {
                    stableChecks += 1
                    if stableChecks >= 2 {
                        finish(.success(webView))
                        return
                    }
                } else {
                    stableChecks = 0
                }
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        finish(.success(webView))
    }

    private func finish(_ result: Result<WKWebView, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        webView?.navigationDelegate = nil
        if case .failure = result { webView?.stopLoading() }
        webView = nil
        continuation.resume(with: result)
    }
}

private struct EmbeddedWebPage: View {
    let url: URL
    let source: FeedSource
    let preparedWebView: WKWebView?
    let presentedAsSheet: Bool
    @StateObject private var model = EmbeddedWebViewModel()
    @State private var isShowingWeiboAccountMenu = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            EmbeddedWebView(url: url, model: model, preparedWebView: preparedWebView)

            if model.isLoading {
                ProgressView(value: model.estimatedProgress)
                    .progressViewStyle(.linear)
                    .tint(source == .weibo ? .red : .blue)
                    .accessibilityLabel("页面加载进度")
            }

            if source == .weibo, model.requiresWeiboAuthentication {
                weiboAuthenticationPrompt
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .background(InteractivePopGestureEnabler())
        .overlay(alignment: .bottomTrailing) {
            if presentedAsSheet {
                DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭网页详情")
                    .padding(16)
            }
        }
        .toolbar {
            if !presentedAsSheet {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        hotTopicMark
                        Text(source.hotTopicPageTitle)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if source == .weibo {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if model.isAuthenticating {
                            model.finishWeiboLogin()
                        } else if model.isWeiboLoggedIn {
                            isShowingWeiboAccountMenu = true
                        } else {
                            model.beginWeiboLogin()
                        }
                    } label: { weiboAccountButtonLabel }
                    .accessibilityLabel(model.isAuthenticating ? "完成微博登录" : (model.isWeiboLoggedIn ? "微博账号" : "登录微博"))
                }
            }
        }
        .confirmationDialog("微博账号", isPresented: $isShowingWeiboAccountMenu, titleVisibility: .visible) {
            Button("重新登录") { model.beginWeiboLogin() }
            Button("退出登录", role: .destructive) { model.logoutWeibo() }
            Button("取消", role: .cancel) {}
        } message: {
            if let displayName = model.weiboDisplayName {
                Text("当前账号：\(displayName)")
            }
        }
    }

    private var weiboAuthenticationPrompt: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("微博需要登录")
                    .font(.title2.bold())
                Text("微博已限制匿名搜索，登录后即可查看这条热搜的讨论内容。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("登录微博") { model.beginWeiboLogin() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 32)
        .padding(.top, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder private var hotTopicMark: some View {
        if source == .baidu {
            Image("BaiduMark")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 21, height: 21)
                .accessibilityHidden(true)
        } else {
            Image(source.hotTopicMarkAssetName)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(source == .weibo ? Color.red : Color.primary)
                .frame(width: 19, height: 19)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var weiboAccountButtonLabel: some View {
        if let avatarURL = model.weiboAvatarURL {
            AsyncImage(url: MediaURL.image(avatarURL.absoluteString) ?? avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: model.isAuthenticating ? "checkmark.circle.fill" : "person.crop.circle")
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
            .overlay { Circle().stroke(.quaternary, lineWidth: 0.5) }
        } else if let initial = model.weiboAccountInitial {
            Text(initial)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1, green: 0.35, blue: 0.18), Color(red: 0.88, green: 0.08, blue: 0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .overlay { Circle().stroke(.white.opacity(0.35), lineWidth: 0.5) }
        } else if model.isWeiboLoggedIn {
            Text("微")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.red, in: Circle())
        } else {
            Image(systemName: model.isAuthenticating ? "checkmark.circle.fill" : "person.crop.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(model.isAuthenticating ? Color.green : Color.primary)
        }
    }
}

@MainActor
private final class EmbeddedWebViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var estimatedProgress = 0.0
    @Published var isAuthenticating = false
    @Published var isWeiboLoggedIn = false
    @Published var requiresWeiboAuthentication = false
    @Published var weiboAvatarURL: URL? = WeiboSessionCookieStore.storedAvatarURL
    @Published var weiboDisplayName: String? = WeiboSessionCookieStore.storedDisplayName
    var weiboAccountInitial: String? {
        weiboDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init)?.uppercased()
    }
    weak var webView: WKWebView?
    private var returnURL: URL?
    private var isFetchingAvatar = false
    private var isLoggingOut = false

    func reload() {
        requiresWeiboAuthentication = false
        webView?.reload()
    }

    func rememberReturnURL(_ url: URL) {
        if returnURL == nil { returnURL = url }
    }

    func beginWeiboLogin() {
        guard let webView else { return }
        WeiboSessionCookieStore.allowPersistence()
        isLoggingOut = false
        if let current = webView.url, !isWeiboLoginURL(current) { rememberReturnURL(current) }
        isAuthenticating = true
        requiresWeiboAuthentication = false
        var components = URLComponents(string: "https://passport.weibo.com/sso/signin")!
        components.queryItems = [
            URLQueryItem(name: "entry", value: "wapsso"),
            URLQueryItem(name: "source", value: "wapssowb"),
            URLQueryItem(name: "url", value: returnURL?.absoluteString ?? "https://m.weibo.cn/")
        ]
        webView.load(URLRequest(url: components.url!))
    }

    func finishWeiboLogin() {
        isAuthenticating = false
        requiresWeiboAuthentication = false
        let destination = returnURL ?? URL(string: "https://s.weibo.com/top/summary")!
        returnURL = nil
        if let cookieStore = webView?.configuration.websiteDataStore.httpCookieStore {
            refreshWeiboSession(from: cookieStore, persist: true)
        }
        webView?.load(URLRequest(url: destination))
    }

    func refreshWeiboSession(from cookieStore: WKHTTPCookieStore, persist: Bool = false) {
        let isLoggingOutSnapshot = isLoggingOut
        cookieStore.getAllCookies { [weak self] cookies in
            let isLoggedIn = !isLoggingOutSnapshot &&
                WeiboEmbeddedPagePolicy.containsAuthenticatedSession(in: cookies)
            let shouldPersist = persist && WeiboEmbeddedPagePolicy.shouldPersistSession(
                cookies: cookies,
                isLoggingOut: isLoggingOutSnapshot
            )
            Task { @MainActor in
                self?.isWeiboLoggedIn = isLoggedIn
                if shouldPersist {
                    WeiboSessionCookieStore.store(cookies: cookies)
                }
            }
        }
    }

    func logoutWeibo() {
        guard let webView else { return }
        isAuthenticating = false
        isLoggingOut = true
        isWeiboLoggedIn = false
        requiresWeiboAuthentication = false
        weiboAvatarURL = nil
        weiboDisplayName = nil
        returnURL = nil
        WeiboSessionCookieStore.clear()

        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { [weak self, weak webView] cookies in
            let sessionCookies = cookies.filter { cookie in
                let domain = cookie.domain.lowercased()
                return domain.contains("weibo") || domain.contains("sina")
            }
            let group = DispatchGroup()
            for cookie in sessionCookies {
                group.enter()
                cookieStore.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                self?.isLoggingOut = false
                WeiboSessionCookieStore.clear()
                webView?.reload()
            }
        }
    }

    func captureAccountAvatar(from webView: WKWebView) {
        let script = #"""
        (() => {
          const configured = window.$CONFIG?.avatar_large || window.$CONFIG?.avatar || null;
          const displayName = window.$CONFIG?.screen_name || window.$CONFIG?.nick || null;
          if (configured || displayName) return { avatar: configured, displayName };
          const selectors = [
            'header img[class*="avatar"]',
            'nav img[class*="avatar"]',
            '[class*="user"] img[class*="avatar"]',
            'img[class*="Avatar"]'
          ];
          for (const selector of selectors) {
            const image = document.querySelector(selector);
            if (image?.src) return { avatar: image.src, displayName };
          }
          return null;
        })();
        """#
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let profile = result as? [String: Any] else { return }
            Task { @MainActor in
                if let name = profile["displayName"] as? String, !name.isEmpty {
                    self?.weiboDisplayName = name
                    self?.isWeiboLoggedIn = true
                    WeiboSessionCookieStore.store(displayName: name)
                }
                if let raw = profile["avatar"] as? String,
                   !raw.localizedCaseInsensitiveContains("default_avatar"),
                   let url = URL(string: raw) {
                    self?.weiboAvatarURL = url
                    WeiboSessionCookieStore.store(avatarURL: url)
                }
            }
        }
    }

    func fetchAccountAvatar(from cookieStore: WKHTTPCookieStore) {
        guard weiboAvatarURL == nil, !isFetchingAvatar else { return }
        isFetchingAvatar = true
        Task {
            let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
                cookieStore.getAllCookies { continuation.resume(returning: $0) }
            }
            let configuration = URLSessionConfiguration.ephemeral
            let cookieStorage = HTTPCookieStorage()
            cookies.forEach(cookieStorage.setCookie)
            configuration.httpCookieStorage = cookieStorage
            configuration.httpShouldSetCookies = true
            let session = URLSession(configuration: configuration)
            defer { isFetchingAvatar = false }

            var configRequest = URLRequest(url: URL(string: "https://m.weibo.cn/api/config")!)
            configureWeiboAccountRequest(&configRequest)
            guard let (configData, _) = try? await session.data(for: configRequest),
                  let uid = WeiboAccountAPIParser.accountUID(from: configData) else { return }

            var components = URLComponents(string: "https://m.weibo.cn/api/container/getIndex")!
            components.queryItems = [
                URLQueryItem(name: "type", value: "uid"),
                URLQueryItem(name: "value", value: uid)
            ]
            guard let profileURL = components.url else { return }
            var profileRequest = URLRequest(url: profileURL)
            configureWeiboAccountRequest(&profileRequest)
            guard let (profileData, _) = try? await session.data(for: profileRequest),
                  let profile = WeiboAccountAPIParser.profile(from: profileData) else { return }

            if let displayName = profile.displayName {
                weiboDisplayName = displayName
                WeiboSessionCookieStore.store(displayName: displayName)
            }
            weiboAvatarURL = profile.avatarURL
            WeiboSessionCookieStore.store(avatarURL: profile.avatarURL)
        }
    }

    private func configureWeiboAccountRequest(_ request: inout URLRequest) {
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://m.weibo.cn/", forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
    }
}

private struct EmbeddedWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var model: EmbeddedWebViewModel
    let preparedWebView: WKWebView?

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView: WKWebView
        if let preparedWebView {
            webView = preparedWebView
        } else {
            webView = WKWebView(frame: .zero, configuration: Self.configuration(for: url))
        }
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // Weibo's photo viewer uses horizontal swipes to move between images.
        // WKWebView's history gesture competes with that gesture and can navigate
        // back to the hot-search list while the user is browsing photos.
        webView.allowsBackForwardNavigationGestures = !Self.isWeiboURL(url)
        // SwiftUI's navigation container already positions the web view below its
        // toolbar. Automatic UIKit adjustment adds the same top inset a second
        // time on some Weibo documents, leaving an empty strip above the feed.
        webView.scrollView.contentInsetAdjustmentBehavior = Self.isWeiboURL(url) ? .never : .automatic
        context.coordinator.observe(webView, observesWeiboSession: Self.isWeiboURL(url))
        model.webView = webView
        if preparedWebView != nil {
            context.coordinator.adoptLoaded(url, in: webView)
        } else {
            context.coordinator.load(url, in: webView)
        }
        return webView
    }

    static func configuration(for url: URL) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        if isWeiboURL(url) {
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: Self.weiboEmbeddedStyleScript,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                )
            )
        }
        return configuration
    }

    private static func isWeiboURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "weibo.com" || host.hasSuffix(".weibo.com") || host == "weibo.cn" || host.hasSuffix(".weibo.cn")
    }

    private static let weiboEmbeddedStyleScript = #"""
    (() => {
      const isAuthenticationPage =
        location.hostname === 'passport.weibo.com' ||
        location.hostname.endsWith('.passport.weibo.com') ||
        location.hostname === 'passport.weibo.cn' ||
        location.hostname.endsWith('.passport.weibo.cn') ||
        location.pathname.includes('/signin');
      if (isAuthenticationPage) return;

      const styleID = 'zhongxiang-weibo-embedded-style';
      const installStyle = () => {
        if (document.getElementById(styleID)) return;
        const style = document.createElement('style');
        style.id = styleID;
        style.textContent = `
          .m-top-nav,
          header.m-top-nav {
            display: none !important;
          }
          body,
          #app,
          .m-container-max {
            padding-top: 0 !important;
            margin-top: 0 !important;
          }
          [data-ad],
          [data-adid],
          [data-ad-id],
          [class*="ad-card"],
          [class*="card-ad"],
          [class*="advert"],
          .m-ad {
            display: none !important;
          }
        `;
        (document.head || document.documentElement).appendChild(style);
      };

      const hideTopNavigation = () => {
        if (!document.documentElement) return;
        const searchField = document.querySelector(
          'input[type="search"], input[placeholder*="搜索"], .m-search input'
        );
        if (!searchField) return;

        let candidate = searchField;
        let topNavigation = null;
        while (candidate && candidate !== document.body) {
          const rect = candidate.getBoundingClientRect();
          if (
            rect.top <= 6 &&
            rect.width >= window.innerWidth * 0.82 &&
            rect.height >= 36 &&
            rect.height <= 96
          ) {
            topNavigation = candidate;
          }
          candidate = candidate.parentElement;
        }
        topNavigation?.remove();
      };

      const removeContainingCard = (element) => {
        if (!element?.isConnected) return;
        const card = element.closest(
          'article, .card, .m-panel, [class*="card-wrap"], [class*="card-item"]'
        ) || element;
        const rect = card.getBoundingClientRect();
        if (rect.width >= window.innerWidth * 0.72 && rect.height > 0 && rect.height <= 900) {
          card.remove();
        }
      };

      const removePromotions = () => {
        document.querySelectorAll(
          '[data-ad], [data-adid], [data-ad-id], [class*="ad-card"], ' +
          '[class*="card-ad"], [class*="advert"], .m-ad, ' +
          'a[href*="ad.weibo.com"], a[href*="biz.weibo.com"]'
        ).forEach(removeContainingCard);

        document.querySelectorAll('span, em, i, a, button').forEach((element) => {
          const label = (element.textContent || '').replace(/\s+/g, ' ').trim();
          if (/^(广告|推广|微博广告)$/.test(label) || /^(打开微博|打开微博App|下载微博客户端)$/.test(label)) {
            removeContainingCard(element);
          }
        });
      };

      const hideBrokenImages = () => {
        document.querySelectorAll('img').forEach((image) => {
          const hide = () => image.style.setProperty('visibility', 'hidden', 'important');
          if (image.complete && image.naturalWidth === 0) hide();
          if (!image.dataset.zhongxiangErrorHandler) {
            image.dataset.zhongxiangErrorHandler = '1';
            image.addEventListener('error', hide, { once: true });
          }
        });
      };

      const removeBottomPromotionBar = () => {
        document.querySelectorAll('span, div, a, button').forEach((element) => {
          const label = (element.textContent || '').replace(/\s+/g, ' ').trim();
          const isBottomAction =
            label === '问智搜' ||
            label === '讨论' ||
            label === '和大家一起讨论' ||
            /^和当前\d+人一起讨论$/.test(label);
          if (!isBottomAction) return;

          let candidate = element;
          while (candidate && candidate !== document.body) {
            const rect = candidate.getBoundingClientRect();
            const position = getComputedStyle(candidate).position;
            if (
              (position === 'fixed' || position === 'sticky') &&
              rect.width >= window.innerWidth * 0.86 &&
              rect.height >= 36 &&
              rect.height <= 100 &&
              rect.bottom >= window.innerHeight - 8
            ) {
              candidate.remove();
              return;
            }
            candidate = candidate.parentElement;
          }
        });
      };

      const keepVideosInline = () => {
        document.querySelectorAll('video').forEach((video) => {
          video.setAttribute('playsinline', '');
          video.setAttribute('webkit-playsinline', '');
          video.playsInline = true;

          const player = video.parentElement;
          if (player && !player.dataset.zhongxiangInlineBounds) {
            player.dataset.zhongxiangInlineBounds = '1';
            player.style.setProperty('width', '100%', 'important');
            player.style.setProperty('height', '46vh', 'important');
            player.style.setProperty('max-height', '46vh', 'important');
            player.style.setProperty('overflow', 'hidden', 'important');
          }
        });
      };

      const updateEmbeddedLayout = () => {
        installStyle();
        hideTopNavigation();
        removePromotions();
        hideBrokenImages();
        removeBottomPromotionBar();
        keepVideosInline();
      };
      updateEmbeddedLayout();
      let updateQueued = false;
      const scheduleUpdate = () => {
        if (updateQueued) return;
        updateQueued = true;
        requestAnimationFrame(() => {
          updateQueued = false;
          updateEmbeddedLayout();
        });
      };
      new MutationObserver(scheduleUpdate).observe(document.documentElement, {
        childList: true,
        subtree: true
      });
    })();
    """#

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(url, in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        private let model: EmbeddedWebViewModel
        private var progressObservation: NSKeyValueObservation?
        private var observedWeiboCookieStore: WKHTTPCookieStore?
        private var pageInspectionTask: Task<Void, Never>?
        private var didBeginLoad = false

        init(model: EmbeddedWebViewModel) {
            self.model = model
        }

        func observe(_ webView: WKWebView, observesWeiboSession: Bool) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak model] webView, _ in
                Task { @MainActor in
                    model?.estimatedProgress = webView.estimatedProgress
                    model?.isLoading = webView.estimatedProgress < 1
                }
            }
            if observesWeiboSession {
                let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
                observedWeiboCookieStore = cookieStore
                cookieStore.add(self)
                model.refreshWeiboSession(from: cookieStore, persist: true)
            }
        }

        func load(_ url: URL, in webView: WKWebView) {
            guard !didBeginLoad else { return }
            didBeginLoad = true
            model.rememberReturnURL(url)
            Task { @MainActor in
                if isWeiboHost(url.host) {
                    let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
                    await WeiboSessionCookieStore.install(in: cookieStore)
                    model.refreshWeiboSession(from: cookieStore)
                    model.fetchAccountAvatar(from: cookieStore)
                }
                webView.load(URLRequest(url: url))
            }
        }

        func adoptLoaded(_ url: URL, in webView: WKWebView) {
            didBeginLoad = true
            let loadedURL = webView.url ?? url
            model.rememberReturnURL(loadedURL)
            model.estimatedProgress = 1
            model.isLoading = false
            if isWeiboHost(loadedURL.host) {
                let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
                model.refreshWeiboSession(from: cookieStore, persist: true)
                model.fetchAccountAvatar(from: cookieStore)
                model.captureAccountAvatar(from: webView)
            }
            inspectWeiboPage(webView)
        }

        func stopObserving() {
            if let observedWeiboCookieStore {
                model.refreshWeiboSession(from: observedWeiboCookieStore, persist: true)
                observedWeiboCookieStore.remove(self)
                self.observedWeiboCookieStore = nil
            }
            pageInspectionTask?.cancel()
            pageInspectionTask = nil
            progressObservation?.invalidate()
            progressObservation = nil
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor [weak model] in
                model?.refreshWeiboSession(from: cookieStore, persist: true)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            pageInspectionTask?.cancel()
            pageInspectionTask = nil
            Task { @MainActor in
                model.isLoading = true
                model.requiresWeiboAuthentication = false
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                model.isLoading = false
                model.captureAccountAvatar(from: webView)
                let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
                model.refreshWeiboSession(from: cookieStore, persist: true)
                model.fetchAccountAvatar(from: cookieStore)
                inspectWeiboPage(webView)
            }
        }

        private func inspectWeiboPage(_ webView: WKWebView) {
            pageInspectionTask?.cancel()
            pageInspectionTask = Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                for _ in 0..<24 {
                    guard !Task.isCancelled else { return }
                    let bodyText = (try? await webView.evaluateJavaScript(
                        WeiboEmbeddedPagePolicy.bodyTextJavaScript
                    )) as? String ?? ""
                    let requiresAuthentication = WeiboEmbeddedPagePolicy.requiresAuthentication(
                        url: webView.url,
                        bodyText: bodyText
                    )
                    self.model.requiresWeiboAuthentication = requiresAuthentication
                    if requiresAuthentication { return }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in model.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in model.isLoading = false }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if isWeiboLoginURL(navigationAction.request.url) {
                Task { @MainActor in
                    if let current = webView.url, !isWeiboLoginURL(current) {
                        model.rememberReturnURL(current)
                    }
                }
                decisionHandler(.allow)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}

private struct StoredWebCookie: Codable {
    let domain: String
    let expirationDate: Double?
    let httpOnly: Bool?
    let name: String
    let path: String
    let secure: Bool?
    let value: String

    init(
        domain: String,
        expirationDate: Double?,
        httpOnly: Bool?,
        name: String,
        path: String,
        secure: Bool?,
        value: String
    ) {
        self.domain = domain
        self.expirationDate = expirationDate
        self.httpOnly = httpOnly
        self.name = name
        self.path = path
        self.secure = secure
        self.value = value
    }

    init(cookie: HTTPCookie) {
        domain = cookie.domain
        expirationDate = cookie.expiresDate?.timeIntervalSince1970
        httpOnly = cookie.isHTTPOnly
        name = cookie.name
        path = cookie.path
        secure = cookie.isSecure
        value = cookie.value
    }

    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: domain,
            .name: name,
            .path: path,
            .value: value
        ]
        if let expirationDate {
            properties[.expires] = Date(timeIntervalSince1970: expirationDate)
        }
        if secure == true { properties[.secure] = "TRUE" }
        if httpOnly == true { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        return HTTPCookie(properties: properties)
    }
}

enum WeiboSessionCookieStore {
    private static let defaultsKey = "weibo.session.cookies"
    private static let environmentKey = "WEIBO_COOKIES_JSON"
    private static let avatarURLDefaultsKey = "weibo.session.avatarURL"
    private static let displayNameDefaultsKey = "weibo.session.displayName"
    private static let displayNameEnvironmentKey = "WEIBO_DISPLAY_NAME"
    private static let logoutSuppressedKey = "weibo.session.logoutSuppressed"

    static var storedDisplayName: String? {
        importFromEnvironmentIfPresent()
        return UserDefaults.standard.string(forKey: displayNameDefaultsKey)
    }

    static var storedAvatarURL: URL? {
        avatarURL(defaults: .standard)
    }

    static func avatarURL(defaults: UserDefaults = .standard) -> URL? {
        guard let value = defaults.string(forKey: avatarURLDefaultsKey) else { return nil }
        return URL(string: value)
    }

    static func store(avatarURL: URL, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: logoutSuppressedKey),
              let scheme = avatarURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return }
        defaults.set(avatarURL.absoluteString, forKey: avatarURLDefaultsKey)
    }

    static func store(displayName: String, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: logoutSuppressedKey) else { return }
        defaults.set(displayName, forKey: displayNameDefaultsKey)
    }

    static func store(cookies: [HTTPCookie], defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: logoutSuppressedKey) else { return }
        guard let data = archivedData(for: cookies) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    static func archivedData(for cookies: [HTTPCookie]) -> Data? {
        let weiboCookies = cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            return domain.contains("weibo") || domain.contains("sina")
        }
        guard !weiboCookies.isEmpty,
              let data = try? JSONEncoder().encode(weiboCookies.map(StoredWebCookie.init(cookie:))) else { return nil }
        return data
    }

    static func restoredCookies(from data: Data) -> [HTTPCookie] {
        guard let cookies = try? JSONDecoder().decode([StoredWebCookie].self, from: data) else { return [] }
        return cookies.compactMap(\.httpCookie)
    }

    static func allowPersistence(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: logoutSuppressedKey)
    }

    static func importFromEnvironmentIfPresent(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard !defaults.bool(forKey: logoutSuppressedKey) else { return }
        if let displayName = environment[displayNameEnvironmentKey],
           !displayName.isEmpty {
            store(displayName: displayName, defaults: defaults)
        }
        guard let raw = environment[environmentKey],
              let data = raw.data(using: .utf8),
              (try? JSONDecoder().decode([StoredWebCookie].self, from: data)) != nil else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
        defaults.removeObject(forKey: avatarURLDefaultsKey)
        defaults.removeObject(forKey: displayNameDefaultsKey)
        defaults.set(true, forKey: logoutSuppressedKey)
    }

    static func storedCookiesData(defaults: UserDefaults = .standard) -> Data? {
        defaults.data(forKey: defaultsKey)
    }

    @MainActor
    static func install(in store: WKHTTPCookieStore) async {
        let data = importedOrStoredData()
        guard let data,
              let cookies = try? JSONDecoder().decode([StoredWebCookie].self, from: data) else { return }
        var webCookies = cookies.compactMap(\.httpCookie)
        let sharedAuthNames: Set<String> = ["SUB", "SUBP", "SCF", "ALF", "WBPSESS", "XSRF-TOKEN"]
        for domain in [".weibo.com", ".weibo.cn"] {
            webCookies += cookies.compactMap { cookie in
                guard sharedAuthNames.contains(cookie.name) else { return nil }
                return StoredWebCookie(
                    domain: domain,
                    expirationDate: cookie.expirationDate,
                    httpOnly: cookie.httpOnly,
                    name: cookie.name,
                    path: cookie.path,
                    secure: cookie.secure,
                    value: cookie.value
                ).httpCookie
            }
        }
        if let ulv = cookies.first(where: { $0.name == "ULV" }),
           let milliseconds = ulv.value.split(separator: ":").first,
           let loginTime = Int64(milliseconds).map({ $0 / 1_000 }) {
            for domain in [".weibo.com", ".weibo.cn"] {
                webCookies.append(StoredWebCookie(
                    domain: domain,
                    expirationDate: cookies.first(where: { $0.name == "SUB" })?.expirationDate,
                    httpOnly: false,
                    name: "SSOLoginState",
                    path: "/",
                    secure: true,
                    value: String(loginTime)
                ).httpCookie!)
            }
        }
        for cookie in webCookies {
            await withCheckedContinuation { continuation in
                store.setCookie(cookie) { continuation.resume() }
            }
        }
    }

    private static func importedOrStoredData() -> Data? {
        importFromEnvironmentIfPresent()
        return storedCookiesData()
    }
}

private func isWeiboHost(_ host: String?) -> Bool {
    guard let host = host?.lowercased() else { return false }
    return host == "weibo.com" || host.hasSuffix(".weibo.com") || host == "weibo.cn" || host.hasSuffix(".weibo.cn")
}

private func isWeiboLoginURL(_ url: URL?) -> Bool {
    guard let url, let host = url.host?.lowercased() else { return false }
    if host == "passport.weibo.cn" || host.hasSuffix(".passport.weibo.cn") { return true }
    if host == "passport.weibo.com" || host.hasSuffix(".passport.weibo.com") { return true }
    if host == "login.sina.com.cn" || host.hasSuffix(".login.sina.com.cn") { return true }
    return isWeiboHost(host) && url.path.lowercased().contains("login")
}

private final class FeedScrollPositionStore: ObservableObject {
    private var offsets: [FeedSource: CGPoint] = [:]

    func offset(for source: FeedSource) -> CGPoint? { offsets[source] }
    func save(_ offset: CGPoint, for source: FeedSource) { offsets[source] = offset }
}

private struct SourceScrollOffsetPreserver: UIViewRepresentable {
    let source: FeedSource
    let store: FeedScrollPositionStore

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        if let scrollView = view.enclosingScrollView {
            context.coordinator.update(scrollView: scrollView, source: source, store: store)
        } else {
            DispatchQueue.main.async {
                guard let scrollView = view.enclosingScrollView else { return }
                context.coordinator.update(scrollView: scrollView, source: source, store: store)
            }
        }
    }

    final class Coordinator {
        private weak var scrollView: UIScrollView?
        private var offsetObservation: NSKeyValueObservation?
        private var activeSource: FeedSource?
        private var isRestoring = false
        private var lastOffsetSaveTime: CFTimeInterval = 0

        func update(scrollView: UIScrollView, source: FeedSource, store: FeedScrollPositionStore) {
            if self.scrollView !== scrollView {
                self.scrollView = scrollView
                activeSource = source
                offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                    guard let self, !self.isRestoring, let activeSource = self.activeSource else { return }
                    let now = CACurrentMediaTime()
                    guard now - self.lastOffsetSaveTime >= 0.12 else { return }
                    self.lastOffsetSaveTime = now
                    store.save(scrollView.contentOffset, for: activeSource)
                }
                if let target = store.offset(for: source) {
                    restore(target, in: scrollView)
                }
                return
            }
            guard let activeSource, activeSource != source else { return }

            store.save(scrollView.contentOffset, for: activeSource)
            self.activeSource = source
            let top = CGPoint(
                x: -scrollView.adjustedContentInset.left,
                y: -scrollView.adjustedContentInset.top
            )
            let target = store.offset(for: source) ?? top
            restore(target, in: scrollView)
        }

        private func restore(_ target: CGPoint, in scrollView: UIScrollView) {
            isRestoring = true
            restore(target, in: scrollView, attempt: 0)
        }

        private func restore(_ target: CGPoint, in scrollView: UIScrollView, attempt: Int) {
            DispatchQueue.main.async {
                scrollView.layoutIfNeeded()
                let needsScrollableContent = target.y > -scrollView.adjustedContentInset.top + 1
                let contentIsReady = scrollView.contentSize.height > scrollView.bounds.height + 1
                if needsScrollableContent, !contentIsReady, attempt < 4 {
                    self.restore(target, in: scrollView, attempt: attempt + 1)
                    return
                }
                scrollView.setContentOffset(self.clamped(target, in: scrollView), animated: false)
                self.isRestoring = false
            }
        }

        private func clamped(_ offset: CGPoint, in scrollView: UIScrollView) -> CGPoint {
            let inset = scrollView.adjustedContentInset
            let minX = -inset.left
            let minY = -inset.top
            let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
            let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
            return CGPoint(
                x: min(max(offset.x, minX), maxX),
                y: min(max(offset.y, minY), maxY)
            )
        }
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        var view = superview
        while let current = view {
            if let scrollView = current as? UIScrollView { return scrollView }
            view = current.superview
        }
        return nil
    }
}

private struct FeedChromeScrollModifier: ViewModifier {
    let isActive: Bool
    @Binding var isHidden: Bool
    @Binding var isAtTop: Bool
    @State private var isScrollActive = false
    @State private var direction: FeedScrollDirection?
    @State private var directionalTravel: CGFloat = 0
    @State private var lastGestureTranslation: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollPhaseChange { _, phase in
                    guard isActive else { return }
                    isScrollActive = phase.isScrolling
                    if !phase.isScrolling { resetDirectionTracking() }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { oldOffset, newOffset in
                    guard isActive else { return }
                    let nextIsAtTop = newOffset <= 8
                    if isAtTop != nextIsAtTop {
                        isAtTop = nextIsAtTop
                    }
                    handleOffsetChange(from: oldOffset, to: newOffset)
                }
        } else {
            content.simultaneousGesture(fallbackGesture)
        }
    }

    private var fallbackGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard isActive else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                let translation = value.translation.height
                defer { lastGestureTranslation = translation }
                guard let previous = lastGestureTranslation else { return }
                handleDirectionalDelta(previous - translation)
            }
            .onEnded { _ in
                lastGestureTranslation = nil
                resetDirectionTracking()
            }
    }

    private func handleOffsetChange(from oldOffset: CGFloat, to newOffset: CGFloat) {
        if newOffset <= 8 {
            resetDirectionTracking()
            setHidden(false)
            return
        }

        guard isScrollActive else { return }
        let delta = newOffset - oldOffset
        guard abs(delta) < 80 else {
            resetDirectionTracking()
            return
        }
        handleDirectionalDelta(delta)
    }

    private func handleDirectionalDelta(_ delta: CGFloat) {
        guard abs(delta) >= 0.5 else { return }
        let nextDirection: FeedScrollDirection = delta > 0 ? .towardOlder : .towardNewer

        if direction != nextDirection {
            direction = nextDirection
            directionalTravel = 0
        }
        directionalTravel += abs(delta)

        switch nextDirection {
        case .towardOlder where directionalTravel >= 28:
            isAtTop = false
            setHidden(true)
            directionalTravel = 0
        case .towardNewer where directionalTravel >= 10:
            setHidden(false)
            directionalTravel = 0
        default:
            break
        }
    }

    private func resetDirectionTracking() {
        direction = nil
        directionalTravel = 0
    }

    private func setHidden(_ hidden: Bool) {
        guard isHidden != hidden else { return }
        isHidden = hidden
    }
}

private enum FeedScrollDirection {
    case towardOlder
    case towardNewer
}

struct ConditionalTapGestureModifier: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.onTapGesture(perform: action)
        } else {
            content
        }
    }
}

private extension FeedSource {
    var iconAsset: String? {
        switch self {
        case .weibo: "WeiboMark"
        case .douyin: "TikTokMark"
        case .baidu: "BaiduMark"
        case .bilibili: "BilibiliMark"
        case .zhihu: "ZhihuMark"
        case .youtube: "YouTubeMark"
        default: nil
        }
    }

    var systemIcon: String {
        switch self {
        case .newYorkTimes: "newspaper.fill"
        case .wechat: "bubble.left.and.bubble.right.fill"
        case .x: "house.fill"
        case .truth: "t.square.fill"
        case .xueqiu: "circle.hexagongrid.fill"
        case .rss: "dot.radiowaves.up.forward"
        case .laozhong: "person.fill"
        case .flash: "bolt.fill"
        case .baidu: "magnifyingglass"
        default: "circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .newYorkTimes: .primary
        case .wechat: Color(red: 0.03, green: 0.76, blue: 0.38)
        case .x, .zhihu, .truth: .blue
        case .xueqiu: Color(red: 0.95, green: 0.32, blue: 0.12)
        case .weibo, .youtube: .red
        case .douyin: .primary
        case .baidu: .blue
        case .bilibili: Color(red: 0.98, green: 0.45, blue: 0.62)
        case .rss: .orange
        case .laozhong: .green
        case .flash: .yellow
        }
    }
}

private struct WeiboFollowingRow: View {
    let post: Post

    private var contentParts: (body: String, context: String?) {
        let content = post.weiboFollowingListContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = ["//@","// @"]
        guard let match = separators.compactMap({ separator in
            content.range(of: separator).map { ($0, separator) }
        }).min(by: { $0.0.lowerBound < $1.0.lowerBound }) else {
            return (content, nil)
        }

        let body = content[..<match.0.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let context = content[match.0.lowerBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (body.isEmpty ? "转发微博" : body, context.isEmpty ? nil : context)
    }

    private var visibleImages: [URL] {
        Array(post.weiboFollowingImageURLs.prefix(3))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: post.avatarURL, name: post.authorName, size: 32)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(post.authorName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.blue)
                        .lineLimit(1)

                    if let time = post.formattedTime {
                        Text(time)
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                InlineEmojiText(
                    text: contentParts.body,
                    emojis: post.weiboInlineEmojis,
                    fontSize: 16,
                    lineSpacing: 4,
                    maximumNumberOfLines: 4,
                    allowsTextSelection: false
                )
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let context = contentParts.context {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 11, weight: .medium))
                        InlineEmojiText(
                            text: context,
                            emojis: post.weiboInlineEmojis,
                            fontSize: 13.5,
                            lineSpacing: 2,
                            maximumNumberOfLines: 2,
                            textColor: .tertiaryLabel,
                            allowsTextSelection: false
                        )
                    }
                    .foregroundStyle(.tertiary)
                }

                if !visibleImages.isEmpty {
                    if visibleImages.count == 1, let url = visibleImages.first {
                        WeiboFollowingSingleImage(post: post, url: url)
                    } else {
                        HStack(spacing: 5) {
                            ForEach(visibleImages, id: \.self) { url in
                                RemoteImage(url: url, height: 96, cornerRadius: 5, contentMode: .fill)
                                    .frame(width: 96)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct WeiboFollowingSingleImage: View {
    let post: Post
    let url: URL
    @State private var loadedAspectRatio: CGFloat?

    private var availableWidth: CGFloat {
        max(UIScreen.main.bounds.width - 74, 240)
    }

    private var sourceAspectRatio: CGFloat? {
        guard let image = post.images?.first(where: { MediaURL.image($0.url) == url }),
              let width = image.width,
              let height = image.height,
              width > 0,
              height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }

    private var aspectRatio: CGFloat {
        loadedAspectRatio ?? sourceAspectRatio ?? 4 / 3
    }

    private var isLongImage: Bool {
        aspectRatio < 0.6
    }

    private var imageSize: CGSize {
        let safeRatio = min(max(aspectRatio, 0.2), 5)
        if isLongImage {
            return CGSize(width: availableWidth, height: 170)
        }
        if safeRatio < 1 {
            let height = min(220, 180 / safeRatio)
            return CGSize(width: height * safeRatio, height: height)
        }
        return CGSize(
            width: availableWidth,
            height: min(max(availableWidth / safeRatio, 120), 190)
        )
    }

    var body: some View {
        RemoteImage(
            url: url,
            height: imageSize.height,
            cornerRadius: 5,
            contentMode: isLongImage ? .fill : .fit
        ) { image in
            guard image.size.width > 0, image.size.height > 0 else { return }
            loadedAspectRatio = image.size.width / image.size.height
        }
        .frame(width: imageSize.width)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("微博配图")
    }
}

private final class XAttributedTextBox {
    let value: AttributedString
    init(_ value: AttributedString) { self.value = value }
}

struct NewsCardView: View {
    private static let xTimelineCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 300
        return cache
    }()
    private static let xAttributedTextCache: NSCache<NSString, XAttributedTextBox> = {
        let cache = NSCache<NSString, XAttributedTextBox>()
        cache.countLimit = 300
        return cache
    }()
    let post: Post
    var rssAvatarURL: URL? = nil
    var usesWeChatStyle = false
    var isFeaturedBilibili = false
    var isExpandedFlash = false
    var onOpen: (() -> Void)?
    var body: some View {
        if post.isHotTopic { hotTopicCard }
        else if post.isFlash { flashCard }
        else if post.isBilibili { bilibiliCard }
        else if post.isNewYorkTimes { newYorkTimesCard }
        else if post.isYouTube { youtubeCard }
        else if post.isXueqiu { xueqiuCard }
        else if usesWeChatStyle { weChatCard }
        else if post.isRSS { rssCard }
        else if post.sourceName == "知乎" { zhihuCard }
        else if post.sourceName == "Truth" { truthCard }
        else if post.sourceName == "X" { xCard }
        else { socialCard }
    }

    private var xCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let attribution = post.xRepostAttributionText {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.system(size: 12, weight: .semibold))
                    Text(attribution)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 54)
                .accessibilityElement(children: .combine)
            }

            HStack(alignment: .top, spacing: 10) {
                AvatarView(
                    url: post.avatarURL,
                    name: post.authorName,
                    size: 44,
                    cornerRadius: xAvatarCornerRadius
                )
                .contentShape(Rectangle())
                .onTapGesture { onOpen?() }

                VStack(alignment: .leading, spacing: 10) {
                    xAuthorHeader
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen?() }

                    VStack(alignment: .leading, spacing: 5) {
                        xRichText(xTimelineContent)
                            .font(.system(size: 17, weight: .regular))
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                            .lineLimit(isLongXPost ? 8 : nil)
                            .fixedSize(horizontal: false, vertical: !isLongXPost)

                        if isLongXPost {
                            Button(action: { onOpen?() }) {
                                Text("显示更多")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("查看完整帖子")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen?() }

                    if let reply = post.xReplyContext,
                       let replyText = reply.displayText {
                        XReplyContextCard(reply: reply, text: replyText)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpen?() }
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        XFeedMediaView(post: post)
                        FeedEngagementRow(post: post, showsOnlyLikeAndBookmark: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private var xAuthorHeader: some View {
        HStack(spacing: 4) {
            Text(post.authorName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(3)

            if post.user?.verified == true {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(xVerificationColor)
                    .accessibilityLabel("已认证")
            }

            if let handle = post.authorHandle {
                Text(handle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let time = post.formattedTime {
                Text("· \(time)").lineLimit(1)
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
    }

    private var xTimelineParagraphs: [String] {
        var normalized = post.displayContent
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"https://\s+"#, with: "https://", options: .regularExpression)
            .replacingOccurrences(of: #"http://\s+"#, with: "http://", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        normalized = normalizedXTickerSpacing(normalized)
        normalized = normalized.replacingOccurrences(
            of: #"\s+(?=[1-9]\.\s)"#,
            with: "\n\n",
            options: .regularExpression
        )

        let explicitParagraphs = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if explicitParagraphs.count > 1 { return explicitParagraphs }

        guard post.hasTranslation else { return [normalized] }
        let sentences = normalized
            .replacingOccurrences(of: #"(?<=[。！？])\s*"#, with: "\n", options: .regularExpression)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return sentences.count > 1 ? sentences : [normalized]
    }

    /// Keep ordinary posts complete in the timeline, while giving translated long-form
    /// posts the same compact handoff to detail that X uses for "Show more".
    private var xTimelineContent: String {
        let key = NSString(string: "\(post.hasTranslation ? 1 : 0)|\(post.displayContent)")
        if let cached = Self.xTimelineCache.object(forKey: key) {
            return cached as String
        }
        let value = xTimelineParagraphs.joined(separator: "\n\n")
        Self.xTimelineCache.setObject(value as NSString, forKey: key, cost: value.utf8.count)
        return value
    }

    private var isLongXPost: Bool {
        xTimelineContent.count > 180
    }

    private func xRichText(_ value: String) -> Text {
        let cacheKey = value as NSString
        if let cached = Self.xAttributedTextCache.object(forKey: cacheKey) {
            return Text(cached.value)
        }
        var attributed = AttributedString(value)
        let source = value as NSString
        let pattern = #"\$[A-Za-z][A-Za-z0-9.]{0,9}|https?://[^\s]+"#
        let matches = (try? NSRegularExpression(pattern: pattern)
            .matches(in: value, range: NSRange(location: 0, length: source.length))) ?? []

        for match in matches {
            guard let stringRange = Range(match.range, in: value),
                  let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
                  let upper = AttributedString.Index(stringRange.upperBound, within: attributed) else { continue }
            let range = lower..<upper
            attributed[range].foregroundColor = .blue
            let token = String(value[stringRange])
            if token.hasPrefix("http"), let url = URL(string: token) {
                attributed[range].link = url
            }
        }
        Self.xAttributedTextCache.setObject(XAttributedTextBox(attributed), forKey: cacheKey)
        return Text(attributed)
    }

    private func normalizedXTickerSpacing(_ value: String) -> String {
        let pattern = #"\$\s+([A-Za-z][A-Za-z0-9.]{0,9})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let source = value as NSString
        var result = value
        for match in regex.matches(in: value, range: NSRange(location: 0, length: source.length)).reversed() {
            guard match.numberOfRanges > 1,
                  let range = Range(match.range, in: result) else { continue }
            let ticker = source.substring(with: match.range(at: 1))
            result.replaceSubrange(range, with: "$\(ticker)")
        }
        return result
    }

    private var xVerificationColor: Color {
        let type = post.user?.verifiedType?.lowercased() ?? ""
        return type.contains("business") || type.contains("government") ? .yellow : .blue
    }

    private var xAvatarCornerRadius: CGFloat {
        let type = post.user?.verifiedType?.lowercased() ?? ""
        let usesOrganizationShape = type.contains("business")
            || type.contains("government")
            || type.contains("organization")
        return usesOrganizationShape ? 10 : 22
    }

    private var xueqiuCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            xueqiuTextContent

            if !post.videoURLs.isEmpty || !post.xueqiuUnplacedImageURLs.isEmpty {
                PostMediaGrid(
                    post: post,
                    imageURLs: post.xueqiuUnplacedImageURLs,
                    singleImageMaxHeight: 220,
                    singleImageContentMode: .fit,
                    multiImageHeight: 148,
                    availableWidth: max(UIScreen.main.bounds.width - 32, 240),
                    videoContentMode: .fit,
                    videoMaxHeight: 360
                )
            }

            HStack(spacing: 0) {
                Label("分享", systemImage: "square.and.arrow.up")
                Spacer()
                xueqiuMetric("bubble.left", post.meta?.metrics?.replies)
                Spacer()
                xueqiuMetric("hand.thumbsup", post.meta?.metrics?.likes)
                Spacer()
                Image(systemName: "ellipsis")
            }
            .font(.system(size: 15.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("xueqiu-feed-card-\(post.id)")
        .accessibilityLabel("打开雪球帖子详情")
        .accessibilityAddTraits(.isButton)
    }

    private var xueqiuTextContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                AvatarView(url: post.avatarURL, name: post.authorName, size: 32)
                Text(post.authorName)
                    .font(.system(size: 15.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.18))
                    .fixedSize()
                if let time = post.formattedTime {
                    Text("修改于\(time)")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let emoji = post.xueqiuStandaloneInlineEmoji {
                InlineEmojiImage(emoji: emoji)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !post.xueqiuBodyInlineEmojis.isEmpty {
                InlineEmojiText(
                    text: post.xueqiuBodyContent,
                    emojis: post.xueqiuBodyInlineEmojis,
                    fontSize: 17,
                    lineSpacing: 8,
                    maximumNumberOfLines: post.hasXueqiuFeedMedia ? 5 : 8,
                    allowsTextSelection: false
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                xueqiuRichText(post.xueqiuBodyContent, links: post.xueqiuBodyLinks)
                    .font(.system(size: 17))
                    .lineSpacing(8)
                    .lineLimit(post.hasXueqiuFeedMedia ? 5 : 8)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !post.xueqiuBodyImageURLs.isEmpty {
                PostMediaGrid(
                    post: post,
                    imageURLs: post.xueqiuBodyImageURLs,
                    singleImageMaxHeight: 260,
                    availableWidth: max(UIScreen.main.bounds.width - 32, 240),
                    cornerRadius: 8
                )
            }

            if let quoteBody = post.xueqiuQuoteBody {
                VStack(alignment: .leading, spacing: 12) {
                    (Text(post.xueqiuQuoteAuthor.map { "@\($0)： " } ?? "")
                        .foregroundStyle(Color.blue) + xueqiuRichText(quoteBody, links: post.xueqiuQuoteLinks))
                        .font(.system(size: 15.5))
                        .lineSpacing(6)
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !post.xueqiuQuoteImageURLs.isEmpty {
                        PostMediaGrid(
                            post: post,
                            imageURLs: post.xueqiuQuoteImageURLs,
                            singleImageMaxHeight: 240,
                            availableWidth: max(UIScreen.main.bounds.width - 58, 220),
                            cornerRadius: 7
                        )
                    }

                    HStack(spacing: 4) {
                        Text("相关讨论")
                        if let replies = post.meta?.metrics?.replies, replies > 0 {
                            Text(replies.formattedFeedCount)
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func xueqiuMetric(_ icon: String, _ value: Int?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            if let value, value > 0 { Text(value.formattedFeedCount) }
        }
    }

    private func xueqiuRichText(_ value: String, links: [XueqiuTextLink] = []) -> Text {
        let nsValue = value as NSString
        let matches = (try? NSRegularExpression(pattern: #"@[^\s:：，,。/]+|\$[^$\n]{2,40}\$"#)
            .matches(in: value, range: NSRange(location: 0, length: nsValue.length))) ?? []
        var attributed = AttributedString(value)
        for match in matches {
            guard let stringRange = Range(match.range, in: value),
                  let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
                  let upper = AttributedString.Index(stringRange.upperBound, within: attributed) else { continue }
            let token = nsValue.substring(with: match.range)
            attributed[lower..<upper].foregroundColor = token.hasPrefix("$")
                ? Color(red: 0.95, green: 0.28, blue: 0.10)
                : Color.blue
        }

        var searchLocation = 0
        // Keep links visually distinct in the feed without installing a competing tap recognizer.
        // Links remain interactive in PostDetailView after the row's single tap opens the detail.
        for link in links where !link.label.isEmpty {
            let searchRange = NSRange(location: searchLocation, length: nsValue.length - searchLocation)
            let range = nsValue.range(of: link.label, options: [], range: searchRange)
            guard range.location != NSNotFound,
                  let stringRange = Range(range, in: value),
                  let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
                  let upper = AttributedString.Index(stringRange.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].foregroundColor = .blue
            attributed[lower..<upper].underlineStyle = .single
            searchLocation = range.location + range.length
        }
        return Text(attributed)
    }

    private var truthCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image("TruthMark")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())

                HStack(spacing: 5) {
                    Text("特朗普")
                        .font(.system(size: 15.5, weight: .bold))
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                    if let time = post.formattedTime {
                        Text(time)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 6)

            }

            Text(post.truthFeedContent)
                .font(.system(size: 15, weight: .regular))
                .lineSpacing(3)
                .lineLimit(post.imageURLs.isEmpty ? 3 : 2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            PostMediaGrid(
                post: post,
                singleImageMaxHeight: 210,
                singleImageContentMode: .fill,
                multiImageHeight: 126,
                availableWidth: max(UIScreen.main.bounds.width - 32, 240)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private var zhihuCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(post.zhihuQuestionTitle)
                .font(.system(size: 17, weight: .semibold))
                .lineSpacing(2)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                AvatarView(url: post.zhihuAnswerAvatarURL, name: post.zhihuAnswerAuthorName, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.zhihuAnswerAuthorName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    if let headline = post.zhihuAnswerAuthorHeadline {
                        Text(headline)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                zhihuMetrics
                ZhihuBookmarkButton(postID: post.id)
                zhihuMenu
            }

            Text(post.zhihuCompactAnswerPreview)
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.88))
                .lineSpacing(3)
                .lineLimit(post.hasZhihuAnswer ? 4 : 3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(post.hasZhihuAnswer ? "高赞回答，\(post.zhihuCompactAnswerPreview)" : post.zhihuCompactAnswerPreview)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var zhihuHotLine: some View {
        if let hotMeta = post.zhihuHotMeta {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.72))
                Text(hotMeta)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        } else if let topic = post.zhihuTopicLabel {
            Text(topic)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.blue)
        }
    }

    @ViewBuilder private var zhihuMetrics: some View {
        let votes = post.meta?.zhihuAnswerVoteupCount
        let comments = post.meta?.zhihuAnswerCommentCount
        if votes != nil || comments != nil {
            Text([
                votes.map { "赞同 \($0.formattedFeedCount)" },
                comments.map { "\($0.formattedFeedCount) 评论" }
            ].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text([
                post.zhihuAnswerCount.map { "\($0) 回答" },
                post.formattedTime
            ].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var zhihuMenu: some View {
        if let link = post.linkURL {
            Menu {
                Link(destination: link) {
                    Label("打开知乎原文", systemImage: "safari")
                }
                ShareLink(item: link) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .tint(.secondary)
            .accessibilityLabel("更多操作")
        }
    }

    private var hotTopicCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(post.feedRank.map(String.init) ?? "–")
                .font(.system(size: 17, weight: .bold, design: .rounded)).italic()
                .foregroundStyle((post.feedRank ?? 99) <= 3 ? .orange : .secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(post.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                if post.source != FeedSource.douyin.rawValue,
                   let summary = post.displaySummary,
                   !summary.isEmpty {
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if let meta = post.formattedTime {
                Text(meta.replacingOccurrences(of: "第 \(post.feedRank ?? 0) 名 · ", with: ""))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle())
    }

    private var flashCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(post.formattedTime ?? "--:--")
                .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
                .padding(.top, 2)

            VStack(spacing: 0) {
                Circle()
                    .fill(isImportantFlash ? Color.orange : Color.accentColor)
                    .frame(width: 7, height: 7)
                    .overlay {
                        Circle()
                            .stroke((isImportantFlash ? Color.orange : Color.accentColor).opacity(0.18), lineWidth: 5)
                    }
                    .padding(.top, 7)

                Rectangle()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 7)
            }
            .frame(width: 10)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Text(flashCategory)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isImportantFlash ? Color.orange : Color.accentColor)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(
                            (isImportantFlash ? Color.orange : Color.accentColor).opacity(0.10),
                            in: Capsule()
                        )

                    Text(post.authorName)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    if let aggregationLabel = flashAggregationLabel {
                        Label(aggregationLabel, systemImage: "square.stack.3d.up.fill")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Text(post.displayContent)
                    .font(.system(size: 16, weight: isImportantFlash ? .medium : .regular))
                    .lineSpacing(4)
                    .lineLimit(isExpandedFlash ? nil : 4)
                    .multilineTextAlignment(.leading)

                if post.displayContent.count > 90 {
                    HStack(spacing: 4) {
                        Text(isExpandedFlash ? "收起" : "展开全文")
                        Image(systemName: isExpandedFlash ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.top, 15)
        .padding(.bottom, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var isImportantFlash: Bool {
        post.tagNames.contains("重要")
    }

    private var flashAggregationLabel: String? {
        let platformCount = post.meta?.flashPlatformCount ?? 1
        let similarCount = post.meta?.flashSimilarCount ?? 1
        guard platformCount > 1 || similarCount > 1 else { return nil }

        var parts: [String] = []
        if platformCount > 1 { parts.append("\(platformCount) 个平台发布") }
        if similarCount > 1 { parts.append("合并 \(similarCount) 条") }
        return parts.joined(separator: " · ")
    }

    private var flashCategory: String {
        switch post.meta?.flashCategory {
        case "tech": "AI科技"
        case "equity": "股票"
        case "commodity": "商品"
        case "company": "公司"
        case "geopolitical": "国际"
        case "other": "综合"
        case "policy": "政策"
        default: "快讯"
        }
    }

    private var socialCard: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: post.avatarURL, name: post.authorName, size: 44)

            VStack(alignment: .leading, spacing: 8) {
                socialHeader

                Text(post.displayContent)
                    .font(.system(size: 17, weight: .regular))
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .lineLimit(12)
                    .fixedSize(horizontal: false, vertical: true)

                PostMediaGrid(
                    post: post,
                    availableWidth: max(UIScreen.main.bounds.width - 78, 240)
                )

                FeedEngagementRow(
                    post: post,
                    showsOnlyLikeAndBookmark: false
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var socialHeader: some View {
        HStack(spacing: 4) {
            Text(post.authorName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if post.sourceName == "X" {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)
            }
            if let handle = post.authorHandle {
                Text(handle).lineLimit(1)
            }
            if let time = post.formattedTime {
                Text("· \(time)").lineLimit(1)
            }
            Spacer(minLength: 4)
            if let score = post.score, score > 0 {
                Text(score.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(score >= 8 ? .green : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
            }
            if post.sourceName != "X" {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
    }

    private var bilibiliCard: some View {
        Group {
            if isFeaturedBilibili {
                bilibiliFeaturedCard
            } else {
                bilibiliCompactCard
            }
        }
        .contentShape(Rectangle())
    }

    private var bilibiliFeaturedCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let image = post.previewURL {
                RemoteImage(url: image, height: 194, cornerRadius: 8)
                    .frame(maxWidth: .infinity)
            }

            Text(post.bilibiliTitle)
                .font(.system(size: 19, weight: .bold))
                .lineSpacing(4)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 9) {
                AvatarView(url: post.avatarURL, name: post.authorName, size: 34)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(post.authorName)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        if let time = post.formattedTime {
                            Text(time).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    bilibiliMetrics
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var bilibiliCompactCard: some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = post.previewURL {
                RemoteImage(url: image, height: 94, cornerRadius: 7)
                    .frame(width: 146)
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(post.bilibiliTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .lineSpacing(3)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                HStack(spacing: 7) {
                    AvatarView(url: post.avatarURL, name: post.authorName, size: 24)
                    Text(post.authorName)
                        .lineLimit(1)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    bilibiliMetrics
                    Spacer(minLength: 0)
                    if let time = post.formattedTime {
                        Text(time).lineLimit(1)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var bilibiliMetrics: some View {
        HStack(spacing: 12) {
            if let views = post.meta?.metrics?.views {
                Label(views.formattedFeedCount, systemImage: "play")
            }
            if let replies = post.meta?.metrics?.replies {
                Label(replies.formattedFeedCount, systemImage: "text.bubble")
            }
        }
        .labelStyle(.titleAndIcon)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }

    private var youtubeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cover = post.youtubeCoverURL {
                RemoteImage(
                    url: cover,
                    height: max((UIScreen.main.bounds.width - 44) / 2, 120) * 9 / 16,
                    cornerRadius: 9,
                    contentMode: .fill
                )
            }

            Text(post.displayTitle)
                .font(.system(size: 15, weight: .semibold))
                .lineSpacing(2)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                AvatarView(url: post.avatarURL, name: post.authorName, size: 24)
                Text(post.authorName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let time = post.formattedTime {
                    Text("· \(time)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var rssCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                AvatarView(
                    url: rssAvatarURL ?? post.rssCardAvatarURL,
                    name: post.rssCardSourceName,
                    size: 25
                )
                Text(post.rssCardSourceName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                if let time = post.formattedTime {
                    Text("· \(time)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if let score = post.score, score > 0 {
                    Text(score.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.08), in: Capsule())
                }
            }

            Text(post.displayTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .lineSpacing(1)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if post.rssListContent != post.displayTitle {
                Text(post.rssListContent)
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var weChatCard: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    AvatarView(url: post.avatarURL, name: post.authorName, size: 25)
                    Text(post.authorName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let time = post.formattedTime {
                        Text("· \(time)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                            .lineLimit(1)
                    }
                }

                Text(post.displayTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let previewURL = post.previewURL {
                RemoteImage(url: previewURL, height: 86, cornerRadius: 10)
                    .frame(width: 98, height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var newYorkTimesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(post.displayTitle)
                .font(.system(size: 21, weight: .bold, design: .serif))
                .lineSpacing(2)
                .multilineTextAlignment(.leading)

            if post.newYorkTimesFeedExcerpt != post.displayTitle {
                Text(post.newYorkTimesFeedExcerpt)
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
            }

            PostMediaGrid(post: post, onImageTap: onOpen)

            HStack(spacing: 5) {
                if post.authorName != "RSS" && post.authorName != "纽约时报中文网 国际纵览" {
                    Text(post.authorName.uppercased())
                }
                if let time = post.formattedTime {
                    Text("· \(time)")
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

}

private struct ZhihuBookmarkButton: View {
    let postID: Int
    @State private var isBookmarked: Bool

    init(postID: Int) {
        self.postID = postID
        _isBookmarked = State(initialValue: ZhihuBookmarkStore.contains(postID))
    }

    var body: some View {
        Button {
            isBookmarked = ZhihuBookmarkStore.toggle(postID)
        } label: {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .font(.system(size: 15))
                .foregroundStyle(isBookmarked ? Color.blue : Color.secondary)
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isBookmarked ? "取消收藏" : "收藏")
        .sensoryFeedback(.success, trigger: isBookmarked)
    }
}

private enum ZhihuBookmarkStore {
    private static let key = "zhihu.bookmarkedPostIDs"

    static func contains(_ postID: Int) -> Bool {
        Set(UserDefaults.standard.array(forKey: key) as? [Int] ?? []).contains(postID)
    }

    @discardableResult
    static func toggle(_ postID: Int) -> Bool {
        var values = Set(UserDefaults.standard.array(forKey: key) as? [Int] ?? [])
        if values.contains(postID) {
            values.remove(postID)
        } else {
            values.insert(postID)
        }
        UserDefaults.standard.set(values.sorted(), forKey: key)
        return values.contains(postID)
    }
}

#Preview { NewsFeedView() }
