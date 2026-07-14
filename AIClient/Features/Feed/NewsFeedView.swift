import SwiftUI
import WebKit

private enum RootTab: Hashable { case observation, market, events }

struct NewsFeedView: View {
    @StateObject private var model = NewsFeedViewModel()
    @State private var path: [Post] = []
    @State private var isFeedChromeHidden = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                feedHeader
                content
            }
            .animation(.easeOut(duration: 0.2), value: isFeedChromeHidden)
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Post.self) { post in
                if post.source == FeedSource.weibo.rawValue, let link = post.linkURL {
                    EmbeddedWebPage(url: link, title: post.displayTitle)
                } else {
                    PostDetailView(post: post)
                }
            }
            .task(id: model.source) { await model.loadInitial() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if path.isEmpty {
                EditorialTabBar(selected: .observation) { tab in
                    switch tab {
                    case .observation: break
                    case .market: open("explore")
                    case .events: open("events")
                    }
                }
                .offset(y: isFeedChromeHidden ? 55 : 0)
                .frame(height: isFeedChromeHidden ? 0 : 55, alignment: .top)
                .clipped()
                .opacity(isFeedChromeHidden ? 0 : 1)
                .allowsHitTesting(!isFeedChromeHidden)
                .accessibilityHidden(isFeedChromeHidden)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isFeedChromeHidden)
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
    }

    private var feedHeader: some View {
        VStack(spacing: 0) {
            sourceBar
            Divider().opacity(0.55)
        }
        .frame(height: 53)
        .offset(y: isFeedChromeHidden ? -53 : 0)
        .frame(height: isFeedChromeHidden ? 0 : 53, alignment: .top)
        .clipped()
        .opacity(isFeedChromeHidden ? 0 : 1)
        .allowsHitTesting(!isFeedChromeHidden)
        .accessibilityHidden(isFeedChromeHidden)
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
        .sensoryFeedback(.selection, trigger: model.source)
    }

    private func sourceButton(_ source: FeedSource) -> some View {
        Button { model.select(source) } label: {
            VStack(spacing: 4) {
                sourceIcon(source)
                    .opacity(model.source == source ? 1 : 0.78)
                if model.source == source {
                    Capsule().fill(.blue).frame(width: 18, height: 2)
                } else {
                    Color.clear.frame(width: 18, height: 2)
                }
            }
            .frame(width: 42, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(source.title)
        .accessibilityAddTraits(model.source == source ? .isSelected : [])
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
                    ForEach(model.posts) { post in
                        NewsCardView(post: post)
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
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    model.selectAdjacent(offset: horizontal < 0 ? 1 : -1)
                }
            }
    }

    private func open(_ path: String) {
        if let url = URL(string: path, relativeTo: ServerConfiguration.currentURL)?.absoluteURL { openURL(url) }
    }

}

private struct EmbeddedWebPage: View {
    let url: URL
    let title: String
    @StateObject private var model = EmbeddedWebViewModel()
    @Environment(\.openURL) private var openURL

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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { model.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新")

                Button { openURL(url) } label: {
                    Image(systemName: "safari")
                }
                .accessibilityLabel("在浏览器中打开")
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
        withAnimation(.easeOut(duration: 0.2)) { isHidden = hidden }
    }
}

private enum FeedScrollDirection {
    case towardOlder
    case towardNewer
}

private struct EditorialTabBar: View {
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
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
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
                if let summary = post.displaySummary, !summary.isEmpty {
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
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: post.avatarURL, name: post.authorName, size: 44)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(post.authorName).font(.subheadline.weight(.semibold))
                    Text(post.formattedTime ?? "").font(.caption).foregroundStyle(.secondary)
                    if let score = post.score, score > 0 {
                        Text("\(score.formatted(.number.precision(.fractionLength(1))))分")
                            .font(.caption2).foregroundStyle(.blue).padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
                    }
                    Spacer(); Image(systemName: "ellipsis").font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 10) {
                    Text(post.displayContent).font(.subheadline).fontWeight(.medium).lineSpacing(2).lineLimit(5).multilineTextAlignment(.leading)
                    if let image = post.previewURL { RemoteImage(url: image, height: 82, cornerRadius: 6).frame(width: 112) }
                }
            }
        }.padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
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
