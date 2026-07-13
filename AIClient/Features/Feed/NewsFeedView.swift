import SwiftUI

struct NewsFeedView: View {
    private enum RootTab: Hashable { case home, market, events }

    @StateObject private var model = NewsFeedViewModel()
    @State private var path: [Post] = []
    @State private var rootTab: RootTab = .home
    @State private var showsSettings = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        TabView(selection: $rootTab) {
            NavigationStack(path: $path) {
                VStack(spacing: 0) {
                    sourceBar
                    Divider().opacity(0.55)
                    content
                }
                .background(Color(uiColor: .systemBackground))
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Post.self) { PostDetailView(post: $0) }
                .sheet(isPresented: $showsSettings, onDismiss: { Task { await model.refresh() } }) { ServerSetupView() }
                .task(id: model.source) { await model.loadInitial() }
            }
            .tag(RootTab.home)
            .tabItem { Label("主页", systemImage: rootTab == .home ? "house.fill" : "house") }

            Color.clear
                .tag(RootTab.market)
                .tabItem { Label("市场", systemImage: "chart.xyaxis.line") }

            Color.clear
                .tag(RootTab.events)
                .tabItem { Label("事件", systemImage: "point.3.connected.trianglepath.dotted") }
        }
        .tint(.blue)
        .onChange(of: rootTab) { _, tab in
            guard tab != .home else { return }
            rootTab = .home
            open(tab == .market ? "explore" : "events")
        }
    }

    private var sourceBar: some View {
        HStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(FeedSource.allCases) { source in sourceButton(source).id(source.id) }
                        Button { open("daily") } label: {
                            Image(systemName: "calendar")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.purple)
                                .frame(width: 40, height: 50)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("日报")
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 2)
                }
                .onAppear { DispatchQueue.main.async { proxy.scrollTo(model.source.id, anchor: .center) } }
                .onChange(of: model.source) { _, source in
                    withAnimation(.snappy) { proxy.scrollTo(source.id, anchor: .center) }
                }
            }

            Divider().frame(height: 24)
            Button { showsSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("服务器设置")
            .padding(.trailing, 8)
        }
        .frame(height: 52)
        .background(Color.clear)
        .sensoryFeedback(.selection, trigger: model.source)
    }

    private func sourceButton(_ source: FeedSource) -> some View {
        Button { model.select(source) } label: {
            ZStack(alignment: .bottom) {
                sourceIcon(source).padding(.bottom, 8)
                if model.source == source {
                    Capsule().fill(.blue).frame(width: 22, height: 2.5)
                }
            }
            .frame(width: 40, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(source.title)
        .accessibilityAddTraits(model.source == source ? .isSelected : [])
    }

    @ViewBuilder private func sourceIcon(_ source: FeedSource) -> some View {
        if let asset = source.iconAsset {
            Image(asset).resizable().renderingMode(.template).scaledToFit()
                .foregroundStyle(source.iconColor).frame(width: 21, height: 21)
        } else {
            Image(systemName: source.systemIcon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(source.iconColor).frame(width: 21, height: 21)
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
                        Button { path.append(post) } label: { NewsCardView(post: post) }
                            .buttonStyle(.plain)
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
            }
            .refreshable { await model.refresh() }
        }
    }

    private func open(_ path: String) {
        if let url = URL(string: path, relativeTo: ServerConfiguration.currentURL)?.absoluteURL { openURL(url) }
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
        VStack(alignment: .leading, spacing: 10) {
            PostAuthorHeader(post: post)
            Text(post.displayContent).font(.body).lineSpacing(3).multilineTextAlignment(.leading).lineLimit(12)
            PostMediaGrid(post: post)
            tags
        }.padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
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
            Text(post.displayContent).font(.body).lineSpacing(4).lineLimit(14).multilineTextAlignment(.leading)
            PostMediaGrid(post: post)
            PostActionRow(post: post)
            tags
        }.padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
    }

    @ViewBuilder private var tags: some View {
        if !post.tagNames.isEmpty {
            Text(post.tagNames.prefix(3).map { "#\($0)" }.joined(separator: "  "))
                .font(.caption).foregroundStyle(.blue).lineLimit(2).multilineTextAlignment(.leading)
        }
    }
}

#Preview { NewsFeedView() }
