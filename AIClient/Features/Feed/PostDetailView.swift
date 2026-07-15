import SwiftUI
import AVKit

struct PostDetailView: View {
    @State private var post: Post
    @State private var player: AVPlayer?
    @State private var showsOriginal = false
    @State private var isDescriptionExpanded = false
    @State private var videoPlaybackFailed = false
    @State private var isVideoReady = false
    @State private var newYorkTimesArticle: NewYorkTimesArticle?
    @State private var isLoadingNewYorkTimesBody = false
    @Environment(\.openURL) private var openURL

    init(post: Post) { _post = State(initialValue: post) }

    var body: some View {
        Group {
            if post.isNewYorkTimes { newYorkTimesDetail }
            else if post.sourceName == "X" { xDetail }
            else if post.isBilibili { bilibiliDetail }
            else { standardDetail }
        }
        .navigationTitle(post.isNewYorkTimes ? "纽约时报" : (post.sourceName == "X" ? "帖子" : "详情"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if post.sourceName == "X" {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { openOriginal() } label: { Image(systemName: "bell.slash") }
                    Menu {
                        if let link = post.linkURL { ShareLink(item: link) { Label("分享帖子", systemImage: "square.and.arrow.up") } }
                        Button("在 X 中打开") { openOriginal() }
                    } label: { Image(systemName: "ellipsis") }
                }
            } else if post.isBilibili {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let link = post.linkURL {
                        ShareLink(item: link) { Image(systemName: "square.and.arrow.up") }
                    }
                    Menu {
                        Button("在 B 站观看") { openOriginal() }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .task { await loadDetail() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            guard let failedItem = notification.object as? AVPlayerItem, failedItem === player?.currentItem else { return }
            player = nil
            videoPlaybackFailed = true
            isVideoReady = false
        }
        .onDisappear { player?.pause() }
    }

    private var newYorkTimesDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(post.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? post.displayTitle)
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .lineSpacing(3)

                if let lead = newYorkTimesLead, lead != post.displayTitle {
                    Text(lead)
                        .font(.system(size: 18, design: .serif))
                        .foregroundStyle(.secondary)
                        .lineSpacing(5)
                }

                HStack(spacing: 5) {
                    if post.authorName != "RSS" && post.authorName != "纽约时报中文网 国际纵览" {
                        Text(post.authorName.uppercased())
                    }
                    if let time = post.formattedTime { Text("· \(time)") }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

                ForEach(post.imageURLs.prefix(1), id: \.self) {
                    NewYorkTimesArticleImage(url: $0, height: 245)
                }

                Divider()

                if isLoadingNewYorkTimesBody {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在加载完整正文…")
                    }
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
                } else if let article = newYorkTimesArticle {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(Array(article.blocks.enumerated()), id: \.offset) { _, block in
                            switch block {
                            case .paragraph(let text):
                                Text(text)
                                    .font(.system(size: 18, weight: .regular, design: .serif))
                                    .lineSpacing(8)
                                    .textSelection(.enabled)
                            case .image(let url, let caption, let credit):
                                NewYorkTimesArticleImage(
                                    url: url,
                                    caption: caption,
                                    credit: credit,
                                    height: 230
                                )
                            }
                        }
                    }
                } else {
                    Text("正文暂未收录，请打开原文阅读。")
                        .font(.system(size: 17, design: .serif))
                        .foregroundStyle(.secondary)
                }

                if let link = post.linkURL {
                    Button("在纽约时报阅读原文") { openURL(link) }
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(.primary)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
    }

    private var newYorkTimesLead: String? {
        guard let raw = post.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let lead = raw.split(separator: "<", maxSplits: 1).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return lead?.isEmpty == false ? lead : nil
    }

    private var standardDetail: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                PostAuthorHeader(post: post)
                if post.displayTitle != post.displayContent {
                    Text(post.displayTitle).font(.title3.bold())
                }
                Text(post.displayContent).font(.system(size: 17, weight: .regular)).lineSpacing(2).textSelection(.enabled)

                ForEach(post.imageURLs, id: \.self) { RemoteImage(url: $0, height: 300, cornerRadius: 8) }
                if let player { VideoPlayer(player: player).frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 8)) }

                if !post.tagNames.isEmpty {
                    Text(post.tagNames.map { "#\($0)" }.joined(separator: "  "))
                        .font(.subheadline).foregroundStyle(.blue)
                }
                Divider()
                PostActionRow(post: post)

                if let link = post.linkURL {
                    HStack(spacing: 10) {
                        Button { openURL(link) } label: { Label("打开原文", systemImage: "safari").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                        ShareLink(item: link) { Image(systemName: "square.and.arrow.up").frame(width: 42, height: 30) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    private var bilibiliDetail: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                bilibiliMedia

                VStack(alignment: .leading, spacing: 15) {
                    Text(post.bilibiliTitle)
                        .font(.system(size: 22, weight: .bold))
                        .lineSpacing(5)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    bilibiliMetadata

                    Divider()

                    HStack(spacing: 11) {
                        AvatarView(url: post.avatarURL, name: post.authorName, size: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(post.authorName)
                                .font(.system(size: 17, weight: .semibold))
                                .lineLimit(1)
                            Text(post.user?.userDesc?.nonEmpty ?? "B 站内容创作者")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if post.linkURL != nil {
                            Button("在 B 站观看") { openOriginal() }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.pink)
                                .buttonStyle(.bordered)
                                .tint(.pink)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text(post.displayContent)
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .lineSpacing(5)
                            .lineLimit(isDescriptionExpanded ? nil : 3)
                            .textSelection(.enabled)

                        if post.displayContent.count > 90 {
                            Button(isDescriptionExpanded ? "收起" : "展开") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isDescriptionExpanded.toggle()
                                }
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.pink)
                            .buttonStyle(.plain)
                        }
                    }

                    if !post.tagNames.isEmpty {
                        Divider()
                        Text(post.tagNames.prefix(4).map { "#\($0)" }.joined(separator: "  "))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
        }
    }

    @ViewBuilder private var bilibiliMedia: some View {
        if let player, let item = player.currentItem {
            ZStack {
                Color.black
                if let image = post.previewURL, !isVideoReady {
                    RemoteImage(url: image, height: 230, cornerRadius: 0)
                }
                VideoPlayer(player: player)
                    .opacity(isVideoReady ? 1 : 0.01)
                if !isVideoReady {
                    ProgressView()
                        .tint(.white)
                        .padding(12)
                        .background(.black.opacity(0.55), in: Circle())
                }
            }
            .frame(height: 230)
            .onAppear { player.playImmediately(atRate: 1) }
            .onReceive(item.publisher(for: \.status)) { status in
                if status == .readyToPlay {
                    withAnimation(.easeOut(duration: 0.15)) { isVideoReady = true }
                }
            }
        } else if let image = post.previewURL {
            ZStack {
                RemoteImage(url: image, height: 230, cornerRadius: 0)
                if videoPlaybackFailed, post.linkURL != nil {
                    Button {
                        openOriginal()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(.black.opacity(0.58), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("在 B 站观看")
                }
                if videoPlaybackFailed {
                    Text("播放源暂不可用，点击前往 B 站观看")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.7), in: Capsule())
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 14)
                        .allowsHitTesting(false)
                } else {
                    ProgressView()
                        .tint(.white)
                        .padding(12)
                        .background(.black.opacity(0.55), in: Circle())
                }
            }
        }
    }

    private var bilibiliMetadata: some View {
        HStack(spacing: 12) {
            if let views = post.meta?.metrics?.views {
                Label(compactCount(views), systemImage: "play")
            }
            if let replies = post.meta?.metrics?.replies {
                Label(compactCount(replies), systemImage: "text.bubble")
            }
            if let time = post.formattedTime {
                Text(time).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
    }

    private var xDetail: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 11) {
                    xAuthorHeader
                    if post.hasTranslation {
                        HStack(spacing: 5) {
                            Image(systemName: "character.bubble")
                            Text(showsOriginal ? "英语原文" : "翻译自英语")
                            Button(showsOriginal ? "显示翻译" : "显示原文") { showsOriginal.toggle() }
                                .foregroundStyle(.blue)
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    }

                    Text(showsOriginal ? post.originalDisplayContent : post.displayContent)
                        .font(.system(size: 17))
                        .lineSpacing(3)
                        .textSelection(.enabled)

                    if let link = post.externalURL {
                        Button { openURL(link) } label: {
                            Text("阅读更多：\(link.host() ?? link.absoluteString)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    if let credit = post.photoCredit {
                        Text(credit.hasPrefix("📷") ? credit : "📷：\(credit)")
                            .font(.system(size: 15, weight: .medium))
                    }

                    PostMediaGrid(post: post, singleImageHeight: detailImageHeight)

                    HStack(spacing: 4) {
                        Text(xTimestamp)
                        if let views = post.meta?.metrics?.views {
                            Text("·")
                            Text("\(compactCount(views)) 次查看").fontWeight(.semibold).foregroundStyle(.primary)
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 15)
                .padding(.top, 12)
                .padding(.bottom, 10)

                Divider()
                xEngagementRow
                    .padding(.horizontal, 15)
                    .frame(height: 44)
                Divider()

                HStack {
                    Text("相关").font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down").font(.caption2)
                    Spacer()
                    Button("查看引用") { openOriginal() }
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 15)
                .frame(height: 48)
                Divider()

                Button { openOriginal() } label: {
                    VStack(spacing: 7) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.title3)
                        Text("在 X 中查看回复")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
                .buttonStyle(.plain)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { openOriginal() } label: {
                HStack {
                    Text("发布你的回复")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                .padding(.horizontal, 15)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .background(.bar)
        }
    }

    private var xAuthorHeader: some View {
        HStack(spacing: 9) {
            AvatarView(url: post.avatarURL, name: post.authorName, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(post.authorName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.blue)
                }
                if let handle = post.authorHandle {
                    Text(handle).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var xEngagementRow: some View {
        let metrics = post.meta?.metrics
        return HStack {
            xMetric("bubble.left", metrics?.replies)
            Spacer(); xMetric("arrow.2.squarepath", metrics?.retweets)
            Spacer(); xMetric("heart", metrics?.likes)
            Spacer(); xMetric("chart.bar", metrics?.views)
            Spacer(); xMetric("bookmark", metrics?.bookmarks)
            Spacer()
            if let link = post.linkURL {
                ShareLink(item: link) { Image(systemName: "square.and.arrow.up") }
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
    }

    private func xMetric(_ symbol: String, _ value: Int?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            if let value, value > 0 { Text(compactCount(value)).font(.caption) }
        }
    }

    private var xTimestamp: String {
        guard let raw = post.articlePostAt else { return post.formattedTime ?? "" }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: raw) else { return post.formattedTime ?? raw }
        return date.formatted(.dateTime.hour().minute().month().day().year().locale(Locale(identifier: "zh_CN")))
    }

    private var detailImageHeight: CGFloat {
        guard let image = post.images?.first, let width = image.width, let height = image.height, width > 0 else { return 300 }
        let availableWidth = UIScreen.main.bounds.width - 30
        return min(availableWidth * CGFloat(height) / CGFloat(width), 620)
    }

    private func compactCount(_ value: Int) -> String {
        if value >= 10_000 { return String(format: "%.1f万", Double(value) / 10_000).replacingOccurrences(of: ".0万", with: "万") }
        return value.formatted()
    }

    private func openOriginal() {
        if let link = post.linkURL { openURL(link) }
    }

    private func loadDetail() async {
        guard !post.isSynthetic else { return }
        let client = APIClient(baseURL: ServerConfiguration.currentURL)
        if let detail = try? await client.fetchPost(id: post.id) { post = detail }
        if let video = post.videoURLs.first {
            startVideoPlayback(url: video)
        } else if post.isBilibili {
            videoPlaybackFailed = true
        }
        guard post.isNewYorkTimes, let link = post.linkURL else { return }
        isLoadingNewYorkTimesBody = true
        defer { isLoadingNewYorkTimesBody = false }
        newYorkTimesArticle = try? await client.fetchNewYorkTimesArticle(url: link)
    }

    private func startVideoPlayback(url: URL) {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .moviePlayback)
        try? audioSession.setActive(true)
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 1
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        player = newPlayer
        videoPlaybackFailed = false
        isVideoReady = false
        newPlayer.playImmediately(atRate: 1)
    }
}

private struct NewYorkTimesArticleImage: View {
    let url: URL
    var caption: String? = nil
    var credit: String? = nil
    var height: CGFloat
    @State private var previewURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RemoteImage(url: url, height: height, contentMode: .fit)
                .contentShape(Rectangle())
                .onTapGesture { previewURL = url }

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            if let credit, !credit.isEmpty {
                Text(credit)
                    .font(.system(size: 11, weight: .medium, design: .serif))
                    .foregroundStyle(.tertiary)
            }
        }
        .fullScreenCover(item: $previewURL) { ZoomableImageView(url: $0) }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
