import SwiftUI
import AVKit

struct PostDetailView: View {
    @State private var post: Post
    @State private var player: AVPlayer?
    @State private var showsOriginal = false
    @State private var isDescriptionExpanded = false
    @State private var videoPlaybackFailed = false
    @State private var isVideoReady = false
    @State private var youtubePlaybackState: YouTubePlaybackState = .idle
    @State private var isYouTubeVideoReady = false
    @State private var youtubePlaybackLabel: String?
    @State private var youtubePlaybackURL: URL?
    @State private var youtubePlayerReloadID = UUID()
    @State private var newYorkTimesArticle: NewYorkTimesArticle?
    @State private var isLoadingNewYorkTimesBody = false
    @State private var isTruthBookmarked: Bool
    @State private var xComments: [XComment] = []
    @State private var isLoadingXComments = false
    @State private var xCommentsError: String?
    @State private var xTranslations: [String: String] = [:]
    @State private var loadingXTranslationIDs: Set<String> = []
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    init(post: Post) {
        _post = State(initialValue: post)
        _isTruthBookmarked = State(initialValue: TruthBookmarkStore.contains(post.id))
    }

    var body: some View {
        Group {
            if post.isNewYorkTimes { newYorkTimesDetail }
            else if post.sourceName == "X" { xDetail }
            else if post.isBilibili { bilibiliDetail }
            else if post.isYouTube { youtubeDetail }
            else if post.sourceName == "知乎" { zhihuDetail }
            else if post.sourceName == "Truth" { truthDetail }
            else { standardDetail }
        }
        .navigationTitle(post.isNewYorkTimes ? "纽约时报" : (post.sourceName == "X" ? "帖子" : (post.isYouTube ? "YouTube" : (["知乎", "Truth"].contains(post.sourceName) ? "" : "详情"))))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar((["知乎", "Truth"].contains(post.sourceName) || post.isYouTube) ? .hidden : .visible, for: .navigationBar)
        .navigationBarBackButtonHidden(["知乎", "Truth"].contains(post.sourceName) || post.isYouTube)
        .toolbar(.hidden, for: .tabBar)
        .background(InteractivePopGestureEnabler())
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
        .task {
            let commentsTask = post.sourceName == "X" ? Task { await loadXComments() } : nil
            await loadDetail()
            await commentsTask?.value
            #if DEBUG
            if post.isYouTube,
               ProcessInfo.processInfo.arguments.contains("--youtube-autoplay-preview") {
                await playYouTubeVideo()
            }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            guard let failedItem = notification.object as? AVPlayerItem, failedItem === player?.currentItem else { return }
            player = nil
            if post.isYouTube {
                youtubePlaybackState = .failed
                isYouTubeVideoReady = false
            } else {
                videoPlaybackFailed = true
                isVideoReady = false
            }
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

    private var youtubeDetail: some View {
        VStack(spacing: 0) {
            youtubePlayerSurface

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    youtubeMetadata
                    Divider().opacity(0.55)
                    youtubeChannelRow
                    youtubeActionRow
                    if let description = youtubeDescription {
                        youtubeDescriptionCard(description)
                    }
                    Color.clear.frame(height: 32)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var youtubePlayerSurface: some View {
        ZStack {
            Color.black

            if let youtubePlaybackURL {
                NativeVideoPlayer(
                    url: youtubePlaybackURL,
                    onReady: {
                        withAnimation(.easeOut(duration: 0.18)) {
                            isYouTubeVideoReady = true
                            youtubePlaybackState = .playing
                        }
                    },
                    onFailed: {
                        youtubePlaybackState = .failed
                        isYouTubeVideoReady = false
                    }
                )
                    .id(youtubePlayerReloadID)
                    .opacity(isYouTubeVideoReady ? 1 : 0.02)
            }

            if !isYouTubeVideoReady, let cover = post.youtubeCoverURL {
                RemoteImage(
                    url: cover,
                    height: youtubePlayerHeight,
                    cornerRadius: 0,
                    contentMode: .fill
                )
            }

            switch youtubePlaybackState {
            case .idle:
                Button { Task { await playYouTubeVideo() } } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 48)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放视频")
            case .loading:
                VStack(spacing: 10) {
                    ProgressView().tint(.white).controlSize(.large)
                    Text("正在准备视频")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            case .failed:
                VStack(spacing: 12) {
                    Text("暂时无法播放")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 10) {
                        Button("重试") { Task { await playYouTubeVideo() } }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        Button("打开 YouTube") { openOriginal() }
                            .buttonStyle(.bordered)
                            .tint(.white)
                    }
                }
                .padding(16)
                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            case .playing:
                EmptyView()
            }

        }
        .frame(height: youtubePlayerHeight)
        .clipped()
        .overlay(alignment: .top) { youtubePlayerTopBar }
    }

    private var youtubePlayerTopBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel("返回")

            Spacer()

            if let link = post.linkURL {
                ShareLink(item: link) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .accessibilityLabel("分享视频")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var youtubeMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.displayTitle)
                .font(.system(size: 20, weight: .bold))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                Text(post.formattedTime ?? "刚刚")
                if let youtubePlaybackLabel, !youtubePlaybackLabel.isEmpty {
                    Text("·")
                    Text(youtubePlaybackLabel)
                }
                Text("· YouTube")
            }
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 15)
    }

    private var youtubeChannelRow: some View {
        HStack(spacing: 11) {
            AvatarView(url: post.avatarURL, name: post.authorName, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(post.authorName)
                    .font(.system(size: 15.5, weight: .semibold))
                    .lineLimit(1)
                Text("频道")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("YouTube 打开") { openOriginal() }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(post.linkURL == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var youtubeActionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                if let link = post.linkURL {
                    ShareLink(item: link) {
                        youtubeActionLabel("分享", symbol: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                }
                Button { openOriginal() } label: {
                    youtubeActionLabel("原视频", symbol: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .disabled(post.linkURL == nil)

                if youtubePlaybackState == .playing {
                    Button {
                        isYouTubeVideoReady = false
                        youtubePlayerReloadID = UUID()
                        youtubePlaybackState = .loading
                    } label: {
                        youtubeActionLabel("重新播放", symbol: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 14)
    }

    private func youtubeActionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 15)
            .frame(height: 38)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
    }

    private func youtubeDescriptionCard(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("简介").font(.system(size: 15, weight: .bold))
                if let time = post.formattedTime {
                    Text(time).font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            }
            Text(description)
                .font(.system(size: 14.5))
                .lineSpacing(4)
                .lineLimit(isDescriptionExpanded ? nil : 3)
                .textSelection(.enabled)
            if description.count > 90 {
                Button(isDescriptionExpanded ? "收起" : "展开") {
                    withAnimation(.easeInOut(duration: 0.2)) { isDescriptionExpanded.toggle() }
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var youtubePlayerHeight: CGFloat {
        max(UIScreen.main.bounds.width, 240) * 9 / 16
    }

    private var youtubeDescription: String? {
        let value = post.displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != post.displayTitle else { return nil }
        return value
    }

    private var truthDetail: some View {
        VStack(spacing: 0) {
            truthDetailToolbar
            Divider().opacity(0.55)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    truthDetailAuthor
                        .padding(.top, 18)

                    Divider()
                        .opacity(0.55)
                        .padding(.top, 18)

                    Text(post.truthFeedContent)
                        .font(.system(size: 18, weight: .regular))
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.top, 18)

                    if !post.imageURLs.isEmpty || post.previewURL != nil {
                        PostMediaGrid(
                            post: post,
                            singleImageMaxHeight: 360,
                            singleImageContentMode: .fill,
                            multiImageHeight: 180,
                            availableWidth: max(UIScreen.main.bounds.width - 32, 240)
                        )
                        .padding(.top, 18)
                    }

                    if let impact = post.truthImpactText {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("影响")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.red)
                            Text(impact)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 17)
                    }

                    Divider()
                        .opacity(0.55)
                        .padding(.top, 18)

                    Text(truthSourceLine)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 16)

                    if post.linkURL != nil {
                        Button { openOriginal() } label: {
                            HStack {
                                Text("在 Truth Social 中打开")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(height: 48)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .top) { Divider().opacity(0.55) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { truthDetailBottomBar }
    }

    private var truthDetailToolbar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44, alignment: .leading)
            }
            .foregroundStyle(.primary)
            .accessibilityLabel("返回")

            Spacer()
            Text("Truth")
                .font(.system(size: 17, weight: .semibold))
            Spacer()

            if let link = post.linkURL {
                ShareLink(item: link) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 19))
                        .frame(width: 44, height: 44, alignment: .trailing)
                }
                .foregroundStyle(.primary)
                .accessibilityLabel("分享帖子")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }

    private var truthDetailAuthor: some View {
        HStack(spacing: 11) {
            Image("TruthMark")
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("特朗普")
                        .font(.system(size: 17, weight: .bold))
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                }
                if let time = post.formattedTime {
                    Text(time)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)
            if let relevance = post.truthRelevanceLabel {
                Text(relevance)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(relevance == "高度相关" ? Color.red : Color.secondary)
            }
        }
    }

    private var truthDetailBottomBar: some View {
        HStack(spacing: 0) {
            Button {
                isTruthBookmarked.toggle()
                TruthBookmarkStore.set(isTruthBookmarked, postID: post.id)
            } label: {
                Label("收藏", systemImage: isTruthBookmarked ? "bookmark.fill" : "bookmark")
                    .frame(maxWidth: .infinity)
            }

            Divider().frame(height: 28)

            if let link = post.linkURL {
                ShareLink(item: link) {
                    Label("分享", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
            } else {
                Label("分享", systemImage: "square.and.arrow.up")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }

            Divider().frame(height: 28)

            Button { openOriginal() } label: {
                Label("打开原帖", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .disabled(post.linkURL == nil)
        }
        .font(.system(size: 13.5, weight: .medium))
        .foregroundStyle(.primary)
        .frame(height: 58)
        .background(.bar)
        .overlay(alignment: .top) { Divider().opacity(0.65) }
        .sensoryFeedback(.success, trigger: isTruthBookmarked)
    }

    private var truthSourceLine: String {
        let time = post.articlePostAt.flatMap(formatTruthTimestamp) ?? post.formattedTime
        return ["来源：Truth Social", time].compactMap { $0 }.joined(separator: "  ·  ")
    }

    private func formatTruthTimestamp(_ raw: String) -> String? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        guard let date = fractional.date(from: raw) ?? standard.date(from: raw) else { return nil }
        return date.formatted(
            .dateTime.year().month().day().hour().minute().locale(Locale(identifier: "zh_CN"))
        )
    }

    private var zhihuDetail: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                zhihuContentToolbar
                    .padding(.bottom, 10)

                Text(post.zhihuQuestionTitle)
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.35)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                if !post.hasFullZhihuAnswer {
                    Text(post.zhihuEditorialDeck)
                        .font(.system(size: 15.5))
                        .foregroundStyle(.secondary)
                        .lineSpacing(7)
                        .padding(.top, 14)
                }

                HStack(spacing: 10) {
                    AvatarView(url: post.zhihuAnswerAvatarURL, name: post.zhihuAnswerAuthorName, size: 38)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(post.zhihuAnswerAuthorName)
                                .font(.system(size: 15, weight: .semibold))
                            if let headline = post.zhihuAnswerAuthorHeadline {
                                Text("· \(headline)")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .font(.system(size: 13))
                        Text("2026-07-15 · \(post.zhihuReadingMinutes) 分钟阅读")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 18)

                Divider().padding(.top, 18)

                Text("赞同 \(post.zhihuAnswerVoteupCount) · \(post.zhihuAnswerCommentCount) 评论")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 13)

                zhihuArticleBody
            }
            .padding(.horizontal, 18)
            .padding(.top, 2)
            .padding(.bottom, 28)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { zhihuBottomBar }
    }

    private var zhihuContentToolbar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 36, height: 44, alignment: .leading)
            }
            .foregroundStyle(.primary)
            .accessibilityLabel("返回")

            HStack(spacing: 5) {
                Text("知乎")
                    .foregroundStyle(.blue)
                    .fontWeight(.semibold)
                if let hotMeta = post.zhihuHotMeta {
                    Text("· \(hotMeta)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 14))
            .minimumScaleFactor(0.82)

            Spacer(minLength: 4)

            if let link = post.linkURL {
                ShareLink(item: link) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 19))
                        .frame(width: 40, height: 44)
                }
                .foregroundStyle(.primary)
                .accessibilityLabel("分享回答")
            }

            Menu {
                Button("在知乎查看原回答") { openOriginal() }
                if let link = post.linkURL {
                    ShareLink(item: link) { Label("分享回答", systemImage: "square.and.arrow.up") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 36, height: 44, alignment: .trailing)
            }
            .foregroundStyle(.primary)
            .accessibilityLabel("更多")
        }
        .frame(height: 44)
    }

    private var zhihuArticleBody: some View {
        let paragraphs = post.zhihuArticleParagraphs
        return LazyVStack(alignment: .leading, spacing: 20) {
            if let first = paragraphs.first {
                HStack(alignment: .top, spacing: 8) {
                    Text(String(first.prefix(1)))
                        .font(.system(size: 52, weight: .medium))
                        .frame(width: 44, alignment: .leading)
                    Text(String(first.dropFirst()))
                        .font(.system(size: 16))
                        .lineSpacing(7)
                }
                .textSelection(.enabled)
            }

            if paragraphs.count > 2 {
                Text("一、循环双覆盖猜想是什么？")
                    .font(.system(size: 19, weight: .bold))
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.blue).frame(width: 3, height: 24)
                    }
            }

            ForEach(Array(paragraphs.dropFirst().enumerated()), id: \.offset) { index, paragraph in
                if index == 1, paragraphs.count > 3 {
                    Text("“ \(paragraph)")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .lineSpacing(7)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Text(paragraph)
                        .font(.system(size: 16))
                        .lineSpacing(7)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var zhihuBottomBar: some View {
        HStack(spacing: 0) {
            zhihuAction("hand.thumbsup", "赞同 \(post.zhihuAnswerVoteupCount)", tint: .blue)
            Divider().frame(height: 24)
            zhihuAction("bubble", "\(post.zhihuAnswerCommentCount)")
            Divider().frame(height: 24)
            zhihuAction("bookmark", "收藏")
            Divider().frame(height: 24)
            Button { openOriginal() } label: {
                Label("原文", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .frame(height: 52)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func zhihuAction(_ icon: String, _ title: String, tint: Color? = nil) -> some View {
        Button {} label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(tint ?? .secondary)
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

                xCommentsSection
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

    @ViewBuilder
    private var xCommentsSection: some View {
        if isLoadingXComments && xComments.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在加载评论…")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else if let xCommentsError, xComments.isEmpty {
            VStack(spacing: 10) {
                Text("评论加载失败")
                    .font(.subheadline.weight(.semibold))
                Text(xCommentsError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Button("重试") { Task { await loadXComments() } }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        } else if xComments.isEmpty {
            VStack(spacing: 7) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.title3)
                Text("暂无评论")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            ForEach(xComments) { comment in
                XCommentRow(
                    comment: comment,
                    translation: xTranslations[comment.id],
                    isTranslating: loadingXTranslationIDs.contains(comment.id)
                ) {
                    await loadXTranslation(for: comment)
                }
                Divider().padding(.leading, 62)
            }
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

    @MainActor
    private func playYouTubeVideo() async {
        guard let link = post.linkURL else {
            youtubePlaybackState = .failed
            return
        }
        youtubePlaybackState = .loading
        isYouTubeVideoReady = false
        youtubePlaybackURL = nil
        do {
            let source = try await APIClient(baseURL: ServerConfiguration.currentURL)
                .resolveYouTubePlayback(url: link, title: post.displayTitle)
            guard !Task.isCancelled else { return }
            youtubePlaybackLabel = source.label
            youtubePlayerReloadID = UUID()
            youtubePlaybackURL = source.url
        } catch is CancellationError {
            return
        } catch {
            youtubePlaybackState = .failed
        }
    }

    private func loadDetail() async {
        guard !post.isSynthetic else { return }
        let client = APIClient(baseURL: ServerConfiguration.currentURL)
        if let detail = try? await client.fetchPost(id: post.id) { post = detail }
        if post.isYouTube {
            player = nil
        } else if let video = post.videoURLs.first {
            startVideoPlayback(url: video)
        } else if post.isBilibili {
            videoPlaybackFailed = true
        }
        guard post.isNewYorkTimes, let link = post.linkURL else { return }
        isLoadingNewYorkTimesBody = true
        defer { isLoadingNewYorkTimesBody = false }
        newYorkTimesArticle = try? await client.fetchNewYorkTimesArticle(url: link)
    }

    @MainActor
    private func loadXComments() async {
        guard let tweetID = post.xTweetID else {
            xCommentsError = "无法识别帖子 ID"
            return
        }
        isLoadingXComments = true
        xCommentsError = nil
        defer { isLoadingXComments = false }
        do {
            let comments = try await APIClient(baseURL: ServerConfiguration.currentURL)
                .fetchXComments(tweetID: tweetID)
            guard !Task.isCancelled else { return }
            xComments = comments
        } catch is CancellationError {
            return
        } catch {
            xCommentsError = error.localizedDescription
        }
    }

    @MainActor
    private func loadXTranslation(for comment: XComment) async {
        guard !["zh", "zh-cn", "zh-tw"].contains(comment.lang?.lowercased() ?? "") else { return }
        guard xTranslations[comment.id] == nil,
              !loadingXTranslationIDs.contains(comment.id) else { return }
        loadingXTranslationIDs.insert(comment.id)
        defer { loadingXTranslationIDs.remove(comment.id) }
        do {
            let value = try await APIClient(baseURL: ServerConfiguration.currentURL)
                .fetchXTranslation(tweetID: comment.id)
            guard !Task.isCancelled else { return }
            xTranslations[comment.id] = value.text
        } catch is CancellationError {
            return
        } catch {
            // Translation is best-effort; the original comment remains readable.
        }
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

private struct XCommentRow: View {
    let comment: XComment
    let translation: String?
    let isTranslating: Bool
    let translate: () async -> Void
    @State private var showsOriginal = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: comment.author.avatarURL, name: comment.author.name, size: 38)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(comment.author.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if comment.author.verified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    Text(comment.author.handle)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let replyTo = comment.inReplyToScreenName, !replyTo.isEmpty {
                    Text("回复 @\(replyTo.trimmingCharacters(in: CharacterSet(charactersIn: "@")))")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                if let translation {
                    HStack(spacing: 5) {
                        Image(systemName: "character.bubble")
                        Text(showsOriginal ? "查看译文" : "X 自动翻译")
                        Button(showsOriginal ? "显示翻译" : "显示原文") {
                            showsOriginal.toggle()
                        }
                        .foregroundStyle(.blue)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                } else if isTranslating {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("正在翻译…")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                Text(showsOriginal || translation == nil ? comment.text : translation ?? comment.text)
                    .font(.system(size: 16))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                HStack(spacing: 28) {
                    metric("bubble.left", comment.metrics?.replies)
                    metric("arrow.2.squarepath", comment.metrics?.retweets)
                    metric("heart", comment.metrics?.likes)
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .task(id: comment.id) {
            await translate()
        }
    }

    private func metric(_ symbol: String, _ value: Int?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            if let value, value > 0 { Text(value.formatted()) }
        }
    }
}

private enum YouTubePlaybackState: Equatable {
    case idle, loading, playing, failed
}

private struct NativeVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    let onReady: () -> Void
    let onFailed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReady: onReady, onFailed: onFailed)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        #if targetEnvironment(simulator)
        player.isMuted = true
        #endif
        controller.player = player
        context.coordinator.observe(item: item, player: player)
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player?.pause()
        coordinator.stopObserving()
    }

    final class Coordinator: NSObject {
        let onReady: () -> Void
        let onFailed: () -> Void
        private var statusObservation: NSKeyValueObservation?
        private var failureObserver: NSObjectProtocol?
        private var deliveredState = false

        init(onReady: @escaping () -> Void, onFailed: @escaping () -> Void) {
            self.onReady = onReady
            self.onFailed = onFailed
        }

        func observe(item: AVPlayerItem, player: AVPlayer) {
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak player] item, _ in
                DispatchQueue.main.async {
                    guard let self, !self.deliveredState else { return }
                    switch item.status {
                    case .readyToPlay:
                        self.deliveredState = true
                        self.onReady()
                        player?.play()
                    case .failed:
                        self.deliveredState = true
                        #if DEBUG
                        print("YouTube AVPlayer failed: \(item.error?.localizedDescription ?? "unknown")")
                        #endif
                        self.onFailed()
                    default:
                        break
                    }
                }
            }
            failureObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] notification in
                guard let self, !self.deliveredState else { return }
                self.deliveredState = true
                #if DEBUG
                print("YouTube AVPlayer ended with error: \(notification.userInfo ?? [:])")
                #endif
                self.onFailed()
            }
        }

        func stopObserving() {
            statusObservation?.invalidate()
            statusObservation = nil
            if let failureObserver {
                NotificationCenter.default.removeObserver(failureObserver)
                self.failureObserver = nil
            }
        }
    }
}

private enum TruthBookmarkStore {
    private static let key = "truth.bookmarkedPostIDs"

    static func contains(_ postID: Int) -> Bool {
        Set(UserDefaults.standard.array(forKey: key) as? [Int] ?? []).contains(postID)
    }

    static func set(_ isBookmarked: Bool, postID: Int) {
        var values = Set(UserDefaults.standard.array(forKey: key) as? [Int] ?? [])
        if isBookmarked {
            values.insert(postID)
        } else {
            values.remove(postID)
        }
        UserDefaults.standard.set(values.sorted(), forKey: key)
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
