import SwiftUI
import WebKit

enum RootTab: Hashable { case observation, market, events }

struct NewsFeedView: View {
    @Binding private var showsDetail: Bool
    @StateObject private var model = NewsFeedViewModel()
    @State private var path: [Post] = []
    @State private var isShowingLaunchCover = true
    @State private var isFeedChromeHidden = false
    @State private var sourceContentOffset: CGFloat = 0
    @State private var pendingSourceContentOffset: CGFloat = 14
    @State private var sourceContentOpacity = 1.0
    @Namespace private var sourceSelectionAnimation
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private let opensZhihuDetailPreview = ProcessInfo.processInfo.arguments.contains("--zhihu-detail-preview")

    init(showsDetail: Binding<Bool> = .constant(false)) {
        _showsDetail = showsDetail
        WeiboSessionCookieStore.importFromEnvironmentIfPresent()
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                content
                    .id(model.sourceContentRevision)
                    .offset(x: sourceContentOffset)
                    .opacity(sourceContentOpacity)
                feedHeader
                    .zIndex(1)
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Post.self) { post in
                if let source = FeedSource(rawValue: post.source ?? ""),
                   source == .weibo || source == .douyin,
                   let link = post.linkURL {
                    EmbeddedWebPage(url: link, source: source)
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
                Task { await model.refresh() }
            } else {
                model.stopRealtime()
            }
        }
        .onChange(of: model.sourceContentRevision) { _, _ in
            animateSourceContentEntrance()
        }
        .onChange(of: path.isEmpty, initial: true) { _, isEmpty in
            showsDetail = !isEmpty
        }
        .onDisappear {
            showsDetail = false
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
            #if DEBUG
            if opensZhihuDetailPreview,
               path.isEmpty,
               let first = model.posts.first(where: { $0.sourceName == "知乎" }) {
                path = [first]
            }
            #endif
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
        return Button { selectSource(source) } label: {
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
                        .fill(.blue)
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
        } else if source == .truth {
            Image("TruthMark")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else if let asset = source.iconAsset {
            Image(asset).resizable().renderingMode(.template).scaledToFit()
                .foregroundStyle(source.iconColor).frame(width: 20, height: 20)
        } else {
            Image(systemName: source.systemIcon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(source.iconColor).frame(width: 20, height: 20)
        }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading && model.posts.isEmpty {
            Spacer(); ProgressView("正在加载").font(.footnote); Spacer()
        } else if let error = model.errorMessage, model.posts.isEmpty {
            Spacer()
            ContentUnavailableView { Label("网络连接失败", systemImage: "wifi.exclamationmark") }
                description: { Text(error) }
                actions: { Button("重新加载") { Task { await model.refresh() } } }
            Spacer()
        } else if model.posts.isEmpty {
            Spacer()
            ContentUnavailableView("这个频道暂时没有新内容", systemImage: "tray")
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 53)
                    ForEach(Array(model.posts.enumerated()), id: \.element.id) { index, post in
                        NewsCardView(
                            post: post,
                            isFeaturedBilibili: model.source == .bilibili && index == 0
                        )
                            .contentShape(Rectangle())
                            .onTapGesture { path.append(post) }
                            .task { await model.loadMoreIfNeeded(current: post) }
                        Divider().opacity(0.6)
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
                .frame(maxWidth: .infinity)
            }
            .modifier(FeedChromeScrollModifier(isHidden: $isFeedChromeHidden))
            .refreshable { await model.refresh() }
            .simultaneousGesture(channelSwipeGesture)
        }
    }

    private var channelSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.predictedEndTranslation.width
                let vertical = value.predictedEndTranslation.height
                guard abs(horizontal) >= 64, abs(horizontal) > abs(vertical) * 1.35 else { return }
                selectAdjacentSource(offset: horizontal < 0 ? 1 : -1)
            }
    }

    private func selectSource(_ source: FeedSource) {
        guard source != model.source,
              let current = FeedSource.allCases.firstIndex(of: model.source),
              let next = FeedSource.allCases.firstIndex(of: source) else { return }
        pendingSourceContentOffset = next > current ? 14 : -14
        isFeedChromeHidden = false
        model.select(source)
    }

    private func animateSourceContentEntrance() {
        sourceContentOffset = pendingSourceContentOffset
        sourceContentOpacity = 0.84
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.28)) {
                sourceContentOffset = 0
                sourceContentOpacity = 1
            }
        }
    }

    private func selectAdjacentSource(offset: Int) {
        let sources = FeedSource.allCases
        guard let current = sources.firstIndex(of: model.source) else { return }
        let next = current + offset
        guard sources.indices.contains(next) else { return }
        selectSource(sources[next])
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

private struct EmbeddedWebPage: View {
    let url: URL
    let source: FeedSource
    @StateObject private var model = EmbeddedWebViewModel()
    @State private var isShowingWeiboAccountMenu = false

    var body: some View {
        VStack(spacing: 0) {
            if model.isLoading {
                ProgressView(value: model.estimatedProgress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }

            EmbeddedWebView(url: url, model: model)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
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

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
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

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        context.coordinator.observe(webView)
        model.webView = webView
        context.coordinator.load(url, in: webView)
        return webView
    }

    private func isWeiboURL(_ url: URL) -> Bool {
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

private struct FeedChromeScrollModifier: ViewModifier {
    @Binding var isHidden: Bool
    @State private var isScrollActive = false
    @State private var direction: FeedScrollDirection?
    @State private var directionalTravel: CGFloat = 0
    @State private var lastGestureTranslation: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollPhaseChange { _, phase in
                    isScrollActive = phase.isScrolling
                    if !phase.isScrolling { resetDirectionTracking() }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { oldOffset, newOffset in
                    handleOffsetChange(from: oldOffset, to: newOffset)
                }
        } else {
            content.simultaneousGesture(fallbackGesture)
        }
    }

    private var fallbackGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
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

struct EditorialTabBar: View {
    let selected: RootTab
    let onSelect: (RootTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.65)
            HStack(spacing: 0) {
                tabButton(.observation, title: "观察", icon: "newspaper", selectedIcon: "newspaper.fill")
                tabButton(.market, title: "市场", icon: "chart.line.uptrend.xyaxis", selectedIcon: "chart.line.uptrend.xyaxis")
                tabButton(.events, title: "事件", icon: "calendar.badge.clock", selectedIcon: "calendar.badge.clock")
            }
            .frame(height: 54)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea(edges: .bottom))
    }

    private func tabButton(_ tab: RootTab, title: String, icon: String, selectedIcon: String) -> some View {
        let isSelected = selected == tab
        return Button { onSelect(tab) } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? selectedIcon : icon)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .frame(height: 21)
                Text(title)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.blue : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    var body: some View {
        if post.isHotTopic { hotTopicCard }
        else if post.isFlash { flashCard }
        else if post.isBilibili { bilibiliCard }
        else if post.isNewYorkTimes { newYorkTimesCard }
        else if post.isRSS { rssCard }
        else if post.sourceName == "知乎" { zhihuCard }
        else { socialCard }
    }

    private var zhihuCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            zhihuHotLine

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
            if let tag = post.tagNames.first {
                Text(tag).font(.caption2.weight(.semibold)).foregroundStyle(.pink)
                    .padding(.horizontal, 5).padding(.vertical, 3).background(Color.pink.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle())
    }

    private var flashCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(post.formattedTime ?? "--:--").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .leading)
            if post.tagNames.contains("重要") { Circle().fill(Color.red).frame(width: 6, height: 6).padding(.top, 6) }
            Text(post.displayContent).font(.subheadline).lineSpacing(3).multilineTextAlignment(.leading)
            Spacer(minLength: 2)
        }
        .padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle())
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
                    showsOnlyLikeAndBookmark: post.sourceName == "X"
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

    private var rssCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            PostAuthorHeader(post: post, compact: true)
            if post.displayTitle != post.displayContent { Text(post.displayTitle).font(.body.weight(.semibold)).multilineTextAlignment(.leading) }
            Text(post.displayContent).font(.system(size: 17, weight: .regular)).lineSpacing(2).lineLimit(14).multilineTextAlignment(.leading)
            PostMediaGrid(post: post)
            PostActionRow(post: post)
            tags
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

    @ViewBuilder private var tags: some View {
        if !post.tagNames.isEmpty {
            Text(post.tagNames.prefix(3).map { "#\($0)" }.joined(separator: "  "))
                .font(.caption).foregroundStyle(.blue).lineLimit(2).multilineTextAlignment(.leading)
        }
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
