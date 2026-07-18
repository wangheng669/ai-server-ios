import SwiftUI
import WebKit

enum RootTab: Hashable { case observation, investment, people }

private enum FlashFilter: String, CaseIterable, Identifiable {
    case all, important, ai, market, policy

    var id: Self { self }
    var title: String {
        return switch self {
        case .all: "全部"
        case .important: "重要"
        case .ai: "AI"
        case .market: "市场"
        case .policy: "政策"
        }
    }

    func matches(_ post: Post) -> Bool {
        let content = post.displayContent.lowercased()
        return switch self {
        case .all: true
        case .important: post.tagNames.contains("重要")
        case .ai: ["ai", "人工智能", "大模型", "算力", "芯片", "openai", "gpt"].contains { content.contains($0) }
        case .market: ["股", "市场", "指数", "涨", "跌", "ipo", "营收", "利润"].contains { content.contains($0) }
        case .policy: ["政策", "发改委", "工信部", "国务院", "监管", "标准", "方案"].contains { content.contains($0) }
        }
    }
}

struct NewsFeedView: View {
    @Binding private var showsDetail: Bool
    @Binding private var hidesTabBar: Bool
    @StateObject private var model = NewsFeedViewModel()
    @State private var path: [Post] = []
    @State private var isShowingLaunchCover = true
    @State private var isFeedChromeHidden = false
    @State private var isFeedAtTop = true
    @State private var sourceChromeStates: [FeedSource: Bool] = [:]
    @StateObject private var scrollPositionStore = FeedScrollPositionStore()
    @State private var hasLoadedFeedOnce = false
    @State private var flashFilter: FlashFilter = .all
    @State private var expandedFlashIDs: Set<Int> = []
    @State private var openingWebPostID: Int?
    @State private var webOpenError: String?
    @State private var preparedWebViews: [Int: WKWebView] = [:]
    @Namespace private var sourceSelectionAnimation
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private let opensZhihuDetailPreview = ProcessInfo.processInfo.arguments.contains("--zhihu-detail-preview")
    private let opensYouTubeDetailPreview = ProcessInfo.processInfo.arguments.contains("--youtube-detail-preview")
    private let opensBilibiliDetailPreview = ProcessInfo.processInfo.arguments.contains("--bilibili-detail-preview")

    init(
        showsDetail: Binding<Bool> = .constant(false),
        hidesTabBar: Binding<Bool> = .constant(false)
    ) {
        _showsDetail = showsDetail
        _hidesTabBar = hidesTabBar
        WeiboSessionCookieStore.importFromEnvironmentIfPresent()
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                content
                feedHeader
                    .zIndex(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Post.self) { post in
                if let source = FeedSource(rawValue: post.source ?? ""),
                   source == .weibo || source == .douyin,
                   let link = post.linkURL {
                    EmbeddedWebPage(url: link, source: source, preparedWebView: preparedWebViews[post.id])
                } else {
                    PostDetailView(post: post)
                }
            }
        }
        .onAppear { model.startRealtime() }
        .onDisappear { model.stopRealtime() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.startRealtime()
                if hasLoadedFeedOnce {
                    Task { await model.refresh() }
                }
            } else {
                model.stopRealtime()
            }
        }
        .onChange(of: path.isEmpty, initial: true) { _, isEmpty in
            showsDetail = !isEmpty
            if isEmpty { preparedWebViews.removeAll() }
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
        .overlay {
            if isShowingLaunchCover {
                LaunchCoverView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(10)
            }
        }
        .task(id: model.source) {
            await model.loadInitial()
            hasLoadedFeedOnce = true
            #if DEBUG
            if opensZhihuDetailPreview,
               path.isEmpty,
               let first = model.posts.first(where: { $0.sourceName == "知乎" }) {
                path = [first]
            } else if opensYouTubeDetailPreview,
                      path.isEmpty,
                      let first = model.posts.first(where: \.isYouTube) {
                path = [first]
            } else if opensBilibiliDetailPreview,
                      path.isEmpty,
                      let first = model.posts.first(where: \.isBilibili) {
                path = [first]
            }
            #endif
        }
        .task {
            await model.warmSourceCache()
        }
        .task {
            guard isShowingLaunchCover, !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.42)) {
                isShowingLaunchCover = false
            }
        }
    }

    private var feedHeader: some View {
        VStack(spacing: 0) {
            sourceBar
            Divider().opacity(0.55)
        }
        .frame(height: 53)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) {
            if model.isSwitchingSource {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }
        }
        .offset(y: isFeedChromeHidden ? -53 : 0)
        .opacity(isFeedChromeHidden ? 0 : 1)
        .allowsHitTesting(!isFeedChromeHidden)
        .accessibilityHidden(isFeedChromeHidden)
        .animation(.easeOut(duration: 0.18), value: isFeedChromeHidden)
    }

    private var sourceBar: some View {
        HStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(FeedSource.allCases) { source in sourceButton(source).id(source.id) }
                        Button { open("daily") } label: {
                            Image(systemName: "calendar")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.purple)
                                .frame(width: 42, height: 50)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("日报")
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 4)
                }
                .onAppear { DispatchQueue.main.async { proxy.scrollTo(model.source.id, anchor: .center) } }
                .onChange(of: model.source) { _, source in
                    withAnimation(.snappy) { proxy.scrollTo(source.id, anchor: .center) }
                }
            }
        }
        .frame(height: 52)
        .background(Color.clear)
        .animation(.snappy(duration: 0.25), value: model.source)
        .sensoryFeedback(.selection, trigger: model.source)
    }

    private func sourceButton(_ source: FeedSource) -> some View {
        let isSelected = model.source == source
        return Button {
            withAnimation(.snappy(duration: 0.32)) { selectSource(source) }
        } label: {
            VStack(spacing: 4) {
                if isSelected && source == .zhihu {
                    Text("知乎")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 32, height: 22)
                } else {
                    sourceIcon(source)
                        .opacity(isSelected ? 1 : 0.78)
                        .scaleEffect(isSelected ? 1 : 0.94)
                }
                if isSelected {
                    Capsule()
                        .fill(source == .truth ? Color.red : Color.blue)
                        .frame(width: 18, height: 2)
                        .matchedGeometryEffect(id: "source-selection", in: sourceSelectionAnimation)
                } else {
                    Color.clear.frame(width: 18, height: 2)
                }
            }
            .frame(width: 42, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(source.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private func sourceIcon(_ source: FeedSource) -> some View {
        if source == .newYorkTimes {
            Text("NYT")
                .font(.system(size: 10.5, weight: .black, design: .serif))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 22)
                .fixedSize(horizontal: true, vertical: false)
        } else if source == .x {
            Text("X")
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundStyle(.primary)
                .frame(width: 22, height: 22)
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
                sourcePage(source)
                    .tag(source)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sourcePage(_ source: FeedSource) -> some View {
        let posts = model.posts(for: source)
        return ZStack {
            feedList(for: source, posts: posts)
                .opacity(posts.isEmpty ? 0 : 1)
                .allowsHitTesting(!posts.isEmpty)

            if posts.isEmpty {
                feedStatus(for: source)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: source) {
            if source == .rss { await model.loadRSSFeedsIfNeeded() }
        }
    }

    private func feedList(for source: FeedSource, posts: [Post]) -> some View {
        let visiblePosts = visiblePosts(for: source, posts: posts)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 53).id("feed-top")
                    if source == .rss {
                        rssSourceFilterBar
                        Divider().opacity(0.55)
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
                    if source == .flash {
                        flashFeedHeader
                    }
                    ForEach(Array(visiblePosts.enumerated()), id: \.element.id) { index, post in
                        let displayPost = model.postForDisplay(post)
                        NewsCardView(
                            post: displayPost,
                            isFeaturedBilibili: source == .bilibili && post.id == posts.first?.id,
                            isExpandedFlash: expandedFlashIDs.contains(post.id),
                            onOpen: { openPost(displayPost) }
                        )
                            .contentShape(Rectangle())
                            .modifier(ConditionalTapGestureModifier(isEnabled: !post.isXueqiu) {
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
                            .task {
                                guard source == model.source else { return }
                                await model.translateXPostIfNeeded(post)
                            }
                            .task {
                                guard source == model.source else { return }
                                await model.loadMoreIfNeeded(current: post)
                            }
                        if source == .flash, index == 2, visiblePosts.count > 3 {
                            flashUnreadDivider(count: min(visiblePosts.count - 3, 3))
                        } else {
                            Divider().opacity(source == .flash ? 0.42 : 0.6)
                                .padding(.leading, source == .flash ? 84 : 0)
                        }
                    }
                    if model.isLoadingMore { ProgressView().padding(20) }
                    if model.errorMessage != nil {
                        Button("加载失败，点按重试") {
                            if let last = model.posts.last { Task { await model.loadMoreIfNeeded(current: last) } }
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
            .refreshable {
                guard source == model.source else { return }
                await model.refresh()
            }
            .allowsHitTesting(openingWebPostID == nil)
            .overlay(alignment: .top) {
                if source == .x, model.source == .x, !model.pendingRealtimePosts.isEmpty {
                    xNewPostsPill {
                        withAnimation(.snappy(duration: 0.35)) {
                            model.acceptPendingRealtimePosts()
                            proxy.scrollTo("feed-top", anchor: .top)
                        }
                    }
                    .padding(.top, isFeedChromeHidden ? 12 : 61)
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
        guard let source = FeedSource(rawValue: post.source ?? ""),
              source == .weibo || source == .douyin,
              let url = post.linkURL else {
            path.append(post)
            return
        }
        if preparedWebViews[post.id] != nil {
            path.append(post)
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
                path.append(post)
            } catch {
                guard !Task.isCancelled else { return }
                openingWebPostID = nil
                let platformName = source == .weibo ? "微博" : "抖音"
                webOpenError = "暂时无法打开\(platformName)页面，请检查网络后重试。"
            }
        }
    }

    private func visiblePosts(for source: FeedSource, posts: [Post]) -> [Post] {
        if source == .rss, model.selectedRSSFeedID != nil {
            return model.selectedRSSPosts
        }
        guard source == .flash else { return posts }
        return posts.filter { flashFilter.matches($0) }
    }

    private var rssSourceFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                rssSourceButton(id: nil, name: "全部", avatarURL: nil)
                ForEach(model.rssFeeds) { feed in
                    rssSourceButton(id: feed.id, name: feed.name, avatarURL: feed.iconURL)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func rssSourceButton(id: Int?, name: String, avatarURL: URL?) -> some View {
        let isSelected = model.selectedRSSFeedID == id
        return Button {
            Task { await model.selectRSSFeed(id) }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    if let id {
                        AvatarView(url: avatarURL, name: name, size: 34)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Text("快讯")
                    .font(.system(size: 24, weight: .bold))
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                Text("实时更新")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(FlashFilter.allCases) { filter in
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { flashFilter = filter }
                        } label: {
                            Text(filter.title)
                                .font(.system(size: 14, weight: flashFilter == filter ? .semibold : .regular))
                                .foregroundStyle(flashFilter == filter ? Color.white : Color.primary)
                                .padding(.horizontal, 18)
                                .frame(height: 36)
                                .background(
                                    flashFilter == filter ? Color.blue : Color(uiColor: .secondarySystemBackground),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(flashFilter == filter ? .isSelected : [])
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(Color(uiColor: .systemBackground))
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

    @ViewBuilder private func feedStatus(for source: FeedSource) -> some View {
        VStack {
            if source == model.source, model.isLoading {
                ProgressView("正在加载").font(.footnote)
            } else if source == model.source, let error = model.errorMessage {
                ContentUnavailableView { Label("网络连接失败", systemImage: "wifi.exclamationmark") }
                    description: { Text(error) }
                    actions: { Button("重新加载") { Task { await model.refresh() } } }
            } else {
                ContentUnavailableView("这个频道暂时没有新内容", systemImage: "tray")
            }
        }
        .padding(.top, 53)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectSource(_ source: FeedSource) {
        guard source != model.source else { return }
        sourceChromeStates[model.source] = isFeedChromeHidden
        isFeedChromeHidden = sourceChromeStates[source] ?? false
        model.select(source)
    }

    private func open(_ path: String) {
        if let url = URL(string: path, relativeTo: ServerConfiguration.currentURL)?.absoluteURL { openURL(url) }
    }

}

private struct LaunchCoverView: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 190, height: 190)
                    .scaleEffect(isAnimating || reduceMotion ? 1 : 0.92)
                    .shadow(color: .black.opacity(0.06), radius: 18, y: 8)

                VStack(spacing: 7) {
                    Text("化繁为简")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .tracking(2)
                    Text("穿过纷繁，抵达清晰")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在梳理信息")
                        .font(.caption)
                }
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
            .opacity(isAnimating || reduceMotion ? 1 : 0.45)
            .scaleEffect(isAnimating || reduceMotion ? 1 : 0.96)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("化繁为简，正在梳理信息")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.55)) {
                isAnimating = true
            }
        }
    }
}

@MainActor
private final class EmbeddedWebPagePreloader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<WKWebView, Error>?

    func load(_ url: URL) async throws -> WKWebView {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = EmbeddedWebView.configuration(for: url)
            let webView = WKWebView(frame: .zero, configuration: configuration)
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
    @StateObject private var model = EmbeddedWebViewModel()
    @State private var isShowingWeiboAccountMenu = false

    var body: some View {
        EmbeddedWebView(url: url, model: model, preparedWebView: preparedWebView)
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .background(InteractivePopGestureEnabler())
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(source == .weibo ? "WeiboMark" : "TikTokMark")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .foregroundStyle(source == .weibo ? Color.red : Color.primary)
                        .frame(width: 19, height: 19)
                    Text(source == .weibo ? "微博热搜" : "抖音热榜")
                        .font(.system(size: 16, weight: .semibold))
                }
                .accessibilityElement(children: .combine)
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

    @ViewBuilder private var weiboAccountButtonLabel: some View {
        if let avatarURL = model.weiboAvatarURL {
            AsyncImage(url: avatarURL) { image in
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
    @Published var weiboAvatarURL: URL?
    @Published var weiboDisplayName: String? = WeiboSessionCookieStore.storedDisplayName
    var weiboAccountInitial: String? {
        weiboDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init)?.uppercased()
    }
    weak var webView: WKWebView?
    private var returnURL: URL?
    private var isFetchingAvatar = false

    func reload() {
        webView?.reload()
    }

    func rememberReturnURL(_ url: URL) {
        if returnURL == nil { returnURL = url }
    }

    func beginWeiboLogin() {
        guard let webView else { return }
        if let current = webView.url, !isWeiboLoginURL(current) { rememberReturnURL(current) }
        isAuthenticating = true
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
        let destination = returnURL ?? URL(string: "https://s.weibo.com/top/summary")!
        returnURL = nil
        if let cookieStore = webView?.configuration.websiteDataStore.httpCookieStore {
            refreshWeiboSession(from: cookieStore, persist: true)
        }
        webView?.load(URLRequest(url: destination))
    }

    func refreshWeiboSession(from cookieStore: WKHTTPCookieStore, persist: Bool = false) {
        cookieStore.getAllCookies { [weak self] cookies in
            let authenticationNames: Set<String> = ["SUB", "SUBP", "WBPSESS"]
            let isLoggedIn = cookies.contains { cookie in
                authenticationNames.contains(cookie.name) &&
                (cookie.domain.lowercased().contains("weibo") || cookie.domain.lowercased().contains("sina"))
            }
            Task { @MainActor in
                self?.isWeiboLoggedIn = isLoggedIn
                if persist, isLoggedIn {
                    WeiboSessionCookieStore.store(cookies: cookies)
                }
            }
        }
    }

    func logoutWeibo() {
        guard let webView else { return }
        isAuthenticating = false
        isWeiboLoggedIn = false
        weiboAvatarURL = nil
        weiboDisplayName = nil
        returnURL = nil
        WeiboSessionCookieStore.clear()

        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { cookies in
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
                webView.reload()
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
                }
                if let raw = profile["avatar"] as? String,
                   !raw.localizedCaseInsensitiveContains("default_avatar"),
                   let url = URL(string: raw) {
                    self?.weiboAvatarURL = url
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
            var request = URLRequest(url: URL(string: "https://weibo.com/")!)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("https://weibo.com/", forHTTPHeaderField: "Referer")
            let configuration = URLSessionConfiguration.ephemeral
            let cookieStorage = HTTPCookieStorage()
            cookies.forEach(cookieStorage.setCookie)
            configuration.httpCookieStorage = cookieStorage
            configuration.httpShouldSetCookies = true
            let session = URLSession(configuration: configuration)
            defer { isFetchingAvatar = false }
            guard let (data, _) = try? await session.data(for: request),
                  let html = String(data: data, encoding: .utf8) else { return }

            if let displayName = jsonString(named: "screen_name", in: html) {
                weiboDisplayName = displayName
                WeiboSessionCookieStore.store(displayName: displayName)
            }
            let avatarFields = ["avatar_hd", "avatar_large", "profile_image_url"]
            for field in avatarFields {
                guard let value = jsonString(named: field, in: html),
                      !value.localizedCaseInsensitiveContains("default_avatar"),
                      let url = URL(string: value) else { continue }
                weiboAvatarURL = url
                break
            }
        }
    }

    private func jsonString(named field: String, in source: String) -> String? {
        guard let marker = source.range(of: "\"\(field)\":\"") else { return nil }
        let remainder = source[marker.upperBound...]
        guard let end = remainder.firstIndex(of: "\"") else { return nil }
        return remainder[..<end]
            .replacingOccurrences(of: #"\/"#, with: "/")
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
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        context.coordinator.observe(webView)
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let model: EmbeddedWebViewModel
        private var progressObservation: NSKeyValueObservation?
        private var didBeginLoad = false

        init(model: EmbeddedWebViewModel) {
            self.model = model
        }

        func observe(_ webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak model] webView, _ in
                Task { @MainActor in
                    model?.estimatedProgress = webView.estimatedProgress
                    model?.isLoading = webView.estimatedProgress < 1
                }
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
            model.rememberReturnURL(webView.url ?? url)
            model.estimatedProgress = 1
            model.isLoading = false
        }

        func stopObserving() {
            progressObservation?.invalidate()
            progressObservation = nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in model.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                model.isLoading = false
                model.captureAccountAvatar(from: webView)
                let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
                model.refreshWeiboSession(from: cookieStore, persist: !model.isAuthenticating)
                model.fetchAccountAvatar(from: cookieStore)
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

private enum WeiboSessionCookieStore {
    private static let defaultsKey = "weibo.session.cookies"
    private static let environmentKey = "WEIBO_COOKIES_JSON"
    private static let displayNameDefaultsKey = "weibo.session.displayName"
    private static let displayNameEnvironmentKey = "WEIBO_DISPLAY_NAME"
    private static let logoutSuppressedKey = "weibo.session.logoutSuppressed"

    static var storedDisplayName: String? {
        importFromEnvironmentIfPresent()
        return UserDefaults.standard.string(forKey: displayNameDefaultsKey)
    }

    static func store(displayName: String) {
        UserDefaults.standard.set(displayName, forKey: displayNameDefaultsKey)
    }

    static func store(cookies: [HTTPCookie]) {
        let weiboCookies = cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            return domain.contains("weibo") || domain.contains("sina")
        }
        guard !weiboCookies.isEmpty,
              let data = try? JSONEncoder().encode(weiboCookies.map(StoredWebCookie.init(cookie:))) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
        UserDefaults.standard.set(false, forKey: logoutSuppressedKey)
    }

    static func importFromEnvironmentIfPresent() {
        guard !UserDefaults.standard.bool(forKey: logoutSuppressedKey) else { return }
        if let displayName = ProcessInfo.processInfo.environment[displayNameEnvironmentKey],
           !displayName.isEmpty {
            store(displayName: displayName)
        }
        guard let raw = ProcessInfo.processInfo.environment[environmentKey],
              let data = raw.data(using: .utf8),
              (try? JSONDecoder().decode([StoredWebCookie].self, from: data)) != nil else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        UserDefaults.standard.removeObject(forKey: displayNameDefaultsKey)
        UserDefaults.standard.set(true, forKey: logoutSuppressedKey)
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
        return UserDefaults.standard.data(forKey: defaultsKey)
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

        func update(scrollView: UIScrollView, source: FeedSource, store: FeedScrollPositionStore) {
            if self.scrollView !== scrollView {
                self.scrollView = scrollView
                activeSource = source
                offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                    guard let self, !self.isRestoring, let activeSource = self.activeSource else { return }
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
            DispatchQueue.main.async {
                scrollView.layoutIfNeeded()
                scrollView.setContentOffset(self.clamped(target, in: scrollView), animated: false)
                DispatchQueue.main.async {
                    scrollView.layoutIfNeeded()
                    scrollView.setContentOffset(self.clamped(target, in: scrollView), animated: false)
                    self.isRestoring = false
                }
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
                    isAtTop = newOffset <= 8
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

private struct ConditionalTapGestureModifier: ViewModifier {
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

struct EditorialTabBar: View {
    let selected: RootTab
    let onSelect: (RootTab) -> Void

    var body: some View {
        HStack(spacing: 6) {
            tabButton(.observation, title: "观点", icon: "newspaper", selectedIcon: "newspaper.fill")
            tabButton(.investment, title: "投资", icon: "chart.line.uptrend.xyaxis", selectedIcon: "chart.line.uptrend.xyaxis")
            tabButton(.people, title: "人物", icon: "person.2", selectedIcon: "person.2.fill")
        }
        .padding(6)
        .background(
            Color(uiColor: .systemBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.10), radius: 14, y: 5)
        .padding(.horizontal, 14)
        .padding(.top, 7)
        .padding(.bottom, 5)
        .background {
            LinearGradient(
                colors: [.clear, Color(uiColor: .systemBackground).opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabButton(_ tab: RootTab, title: String, icon: String, selectedIcon: String) -> some View {
        let isSelected = selected == tab
        return Button { onSelect(tab) } label: {
            HStack(spacing: 7) {
                Image(systemName: isSelected ? selectedIcon : icon)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.28), value: selected)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension FeedSource {
    var iconAsset: String? {
        switch self {
        case .weibo: "WeiboMark"
        case .douyin: "TikTokMark"
        case .bilibili: "BilibiliMark"
        case .zhihu: "ZhihuMark"
        case .youtube: "YouTubeMark"
        default: nil
        }
    }

    var systemIcon: String {
        switch self {
        case .newYorkTimes: "newspaper.fill"
        case .x: "house.fill"
        case .truth: "t.square.fill"
        case .xueqiu: "circle.hexagongrid.fill"
        case .rss: "dot.radiowaves.up.forward"
        case .laozhong: "person.fill"
        case .flash: "bolt.fill"
        default: "circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .newYorkTimes: .primary
        case .x, .zhihu, .truth: .blue
        case .xueqiu: Color(red: 0.95, green: 0.32, blue: 0.12)
        case .weibo, .youtube: .red
        case .douyin: .primary
        case .bilibili: Color(red: 0.98, green: 0.45, blue: 0.62)
        case .rss: .orange
        case .laozhong: .green
        case .flash: .yellow
        }
    }
}

private struct NewsCardView: View {
    let post: Post
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
        else if post.isRSS { rssCard }
        else if post.sourceName == "知乎" { zhihuCard }
        else if post.sourceName == "Truth" { truthCard }
        else if post.sourceName == "X" { xCard }
        else { socialCard }
    }

    private var xCard: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(
                url: post.avatarURL,
                name: post.authorName,
                size: 44,
                cornerRadius: xAvatarCornerRadius
            )

            VStack(alignment: .leading, spacing: 10) {
                xAuthorHeader

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(xTimelineParagraphs.enumerated()), id: \.offset) { _, paragraph in
                        xRichText(paragraph)
                            .font(.system(size: 17, weight: .regular))
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                XFeedMediaView(post: post)

                FeedEngagementRow(post: post, showsOnlyLikeAndBookmark: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func xRichText(_ value: String) -> Text {
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

            if post.hasXueqiuFeedMedia {
                PostMediaGrid(
                    post: post,
                    singleImageMaxHeight: 220,
                    singleImageContentMode: .fill,
                    multiImageHeight: 148,
                    availableWidth: max(UIScreen.main.bounds.width - 64, 240)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private var xueqiuTextContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                AvatarView(url: post.avatarURL, name: post.authorName, size: 32)
                Text(post.authorName)
                    .font(.system(size: 15.5, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.18))
                if let time = post.formattedTime {
                    Text("修改于\(time)")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
                Spacer(minLength: 0)
            }

            xueqiuRichText(post.xueqiuBodyContent)
                .font(.system(size: 17))
                .lineSpacing(8)
                .lineLimit(post.hasXueqiuFeedMedia ? 5 : 8)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let quoteBody = post.xueqiuQuoteBody {
                VStack(alignment: .leading, spacing: 12) {
                    (Text(post.xueqiuQuoteAuthor.map { "@\($0)： " } ?? "")
                        .foregroundStyle(Color.blue) + xueqiuRichText(quoteBody))
                        .font(.system(size: 15.5))
                        .lineSpacing(6)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 4) {
                        Text("相关讨论")
                        if let replies = post.meta?.metrics?.replies, replies > 0 {
                            Text(replies.formattedFeedCount)
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay {
            Button { onOpen?() } label: {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开雪球文章详情")
        }
        .zIndex(1)
    }

    private func xueqiuMetric(_ icon: String, _ value: Int?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            if let value, value > 0 { Text(value.formattedFeedCount) }
        }
    }

    private func xueqiuRichText(_ value: String) -> Text {
        let nsValue = value as NSString
        let matches = (try? NSRegularExpression(pattern: #"@[^\s:：，,。/]+|\$[^$\n]{2,40}\$"#)
            .matches(in: value, range: NSRange(location: 0, length: nsValue.length))) ?? []
        var result = Text("")
        var location = 0
        for match in matches {
            if match.range.location > location {
                result = result + Text(nsValue.substring(with: NSRange(location: location, length: match.range.location - location)))
            }
            let token = nsValue.substring(with: match.range)
            let color = token.hasPrefix("$") ? Color(red: 0.95, green: 0.28, blue: 0.10) : Color.blue
            result = result + Text(token).foregroundColor(color)
            location = match.range.location + match.range.length
        }
        if location < nsValue.length {
            result = result + Text(nsValue.substring(from: location))
        }
        return result
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
        HStack(alignment: .top, spacing: 0) {
            Text(post.formattedTime ?? "--:--")
                .font(.system(size: 14, weight: .regular, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
                .padding(.leading, 13)

            VStack(alignment: .leading, spacing: 8) {
                Text(post.displayContent)
                    .font(.system(size: 16, weight: .regular))
                    .lineSpacing(5)
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

                Text("来源：\(post.authorName)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var flashCategory: String {
        let content = post.displayContent.lowercased()
        if ["ai", "人工智能", "大模型", "算力", "芯片", "openai", "gpt"].contains(where: content.contains) { return "AI" }
        if ["政策", "发改委", "工信部", "国务院", "监管", "标准"].contains(where: content.contains) { return "政策" }
        if ["股", "市场", "指数", "涨", "跌", "ipo", "营收", "利润"].contains(where: content.contains) { return "市场" }
        return "快讯"
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
                    height: max(UIScreen.main.bounds.width - 28, 240) * 9 / 16,
                    cornerRadius: 9,
                    contentMode: .fill
                )
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 36)
                        .background(Color.red.opacity(0.94), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                }
            }

            Text(post.displayTitle)
                .font(.system(size: 17, weight: .semibold))
                .lineSpacing(2)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                AvatarView(url: post.avatarURL, name: post.authorName, size: 28)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var rssCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            PostAuthorHeader(post: post, compact: true)
            if post.displayTitle != post.displayContent { Text(post.displayTitle).font(.body.weight(.semibold)).multilineTextAlignment(.leading) }
            Text(post.displayContent).font(.system(size: 17, weight: .regular)).lineSpacing(2).lineLimit(14).multilineTextAlignment(.leading)
            PostMediaGrid(post: post)
            PostActionRow(post: post)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
    }

    private var newYorkTimesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(post.displayTitle)
                .font(.system(size: 21, weight: .bold, design: .serif))
                .lineSpacing(2)
                .multilineTextAlignment(.leading)

            if post.displayContent != post.displayTitle {
                Text(post.displayContent)
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
            }

            PostMediaGrid(post: post)

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
