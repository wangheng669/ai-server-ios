import SwiftUI
import WebKit

enum RootTab: Hashable { case observation, market, events }

struct NewsFeedView: View {
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
        .overlay {
            if isShowingLaunchCover {
                LaunchCoverView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(10)
            }
        }
        .task(id: model.source) {
            await model.loadInitial()
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
                sourceIcon(source)
                    .opacity(isSelected ? 1 : 0.78)
                    .scaleEffect(isSelected ? 1 : 0.94)
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
        }
    }
}

@MainActor
private final class EmbeddedWebViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var estimatedProgress = 0.0
    weak var webView: WKWebView?

    func reload() {
        webView?.reload()
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
        webView.load(URLRequest(url: url))
        return webView
    }

    private func isWeiboURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "weibo.com" || host.hasSuffix(".weibo.com") || host == "weibo.cn" || host.hasSuffix(".weibo.cn")
    }

    private static let weiboEmbeddedStyleScript = #"""
    (() => {
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
          if (label !== '问智搜' && !/^和当前\d+人一起讨论$/.test(label)) return;

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

      const updateEmbeddedLayout = () => {
        installStyle();
        hideTopNavigation();
        removePromotions();
        hideBrokenImages();
        removeBottomPromotionBar();
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
        guard webView.url == nil else { return }
        webView.load(URLRequest(url: url))
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let model: EmbeddedWebViewModel
        private var progressObservation: NSKeyValueObservation?

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

        func stopObserving() {
            progressObservation?.invalidate()
            progressObservation = nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in model.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in model.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in model.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in model.isLoading = false }
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
        else { socialCard }
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

#Preview { NewsFeedView() }
