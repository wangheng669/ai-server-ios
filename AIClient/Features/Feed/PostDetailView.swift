import SwiftUI
import AVKit
import WebKit

struct PostDetailView: View {
    private let presentedAsSheet: Bool
    @State private var post: Post
    @State private var player: AVPlayer?
    @State private var detectedVideoAspectRatio: CGFloat?
    @State private var showsOriginal = false
    @State private var isDescriptionExpanded = false
    @State private var videoPlaybackFailed = false
    @State private var isVideoReady = false
    @State private var bilibiliPlaybackStartedAt: Date?
    @State private var bilibiliPlaybackRetryTask: Task<Void, Never>?
    @State private var bilibiliPlaybackRetryCount = 0
    @State private var bilibiliSubtitleCues: [PersonVideoSubtitleCue] = []
    @State private var bilibiliSubtitleStatus = "loading"
    @State private var bilibiliSubtitleError: String?
    @State private var bilibiliSummary: BilibiliVideoSummary?
    @State private var bilibiliSummaryModel: String?
    @State private var bilibiliSummaryStatus = "loading"
    @State private var bilibiliSummaryError: String?
    @State private var bilibiliInterpretation: BilibiliVideoInterpretation?
    @State private var bilibiliInterpretationModel: String?
    @State private var bilibiliInterpretationCost: Double?
    @State private var bilibiliInterpretationCached = false
    @State private var bilibiliInterpretationStatus = "idle"
    @State private var bilibiliInterpretationError: String?
    @State private var bilibiliInterpretationProgress = 0
    @State private var bilibiliInterpretationStepLabel: String?
    @State private var bilibiliInterpretationDetail: String?
    @State private var bilibiliInterpretationTask: Task<Void, Never>?
    @State private var youtubePlaybackState: YouTubePlaybackState = .idle
    @State private var isYouTubeVideoReady = false
    @State private var youtubePlaybackLabel: String?
    @State private var youtubePlayerReloadID = UUID()
    @State private var youtubePlaybackStartedAt: ContinuousClock.Instant?
    @State private var newYorkTimesArticle: NewYorkTimesArticle?
    @State private var isLoadingNewYorkTimesBody = true
    @State private var wikipediaEntitiesByParagraph: [Int: [WikipediaEntity]] = [:]
    @State private var selectedWikipediaEntity: WikipediaSelection?
    @State private var presentedWikipediaEntity: WikipediaEntity?
    @State private var isTruthBookmarked: Bool
    @State private var isRSSBookmarked: Bool
    @State private var xComments: [XComment] = []
    @State private var isLoadingXComments = false
    @State private var xCommentsError: String?
    @State private var xTranslations: [String: String] = [:]
    @State private var loadingXTranslationIDs: Set<String> = []
    @State private var xLiveDetail: XTweetDetailItem?
    @State private var xLiveTranslationText: String?
    @State private var isLoadingXFullText: Bool
    @State private var weiboImageSelection: ImageGallerySelection?
    @State private var speechPlayer: AVPlayer?
    @State private var isSpeechLoading = false
    @State private var isSpeechPlaying = false
    @State private var speechErrorMessage: String?
    @State private var presentedXueqiuLink: InAppBrowserDestination?
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    init(
        post: Post,
        preloadedNewYorkTimesArticle: NewYorkTimesArticle? = nil,
        presentedAsSheet: Bool = false
    ) {
        self.presentedAsSheet = presentedAsSheet
        let storedArticle = preloadedNewYorkTimesArticle ?? (post.isNewYorkTimes
            ? (post.contentZH ?? post.content).flatMap(NewYorkTimesArticle.storedText)
            : nil)
        _post = State(initialValue: post)
        _newYorkTimesArticle = State(initialValue: storedArticle)
        _isLoadingNewYorkTimesBody = State(initialValue: post.isNewYorkTimes && storedArticle == nil)
        _isTruthBookmarked = State(initialValue: TruthBookmarkStore.contains(post.id))
        _isRSSBookmarked = State(initialValue: RSSBookmarkStore.contains(post.id))
        _isLoadingXFullText = State(initialValue:
            post.sourceName == "X"
                && XPostTextFormatter.shouldWaitForFullText(post.xStoredOriginalContent)
        )
    }

    private var usesCustomDismissControl: Bool {
        post.isNewYorkTimes
            || isWeChatArticle
            || ["知乎", "Truth", "雪球"].contains(post.sourceName)
            || post.isYouTube
            || post.isWeiboRSS
    }

    private var dismissIconName: String {
        presentedAsSheet ? "xmark" : "chevron.left"
    }

    private var dismissAccessibilityLabel: String {
        presentedAsSheet ? "关闭动态详情" : "返回"
    }

    var body: some View {
        Group {
            if post.isNewYorkTimes { newYorkTimesDetail }
            else if isWeChatArticle { weChatDetail }
            else if post.sourceName == "X" { xDetail }
            else if post.isBilibili { bilibiliDetail }
            else if post.isYouTube { youtubeDetail }
            else if post.sourceName == "知乎" { zhihuDetail }
            else if post.sourceName == "Truth" { truthDetail }
            else if post.isXueqiu { xueqiuDetail }
            else if post.isWeiboRSS { weiboDetail }
            else if post.isRSS { rssDetail }
            else { standardDetail }
        }
        .navigationTitle(post.isWeiboRSS ? "微博正文" : (post.isNewYorkTimes ? "纽约时报" : (post.sourceName == "X" ? "帖子" : (post.isYouTube ? "YouTube" : (["知乎", "Truth"].contains(post.sourceName) || isWeChatArticle ? "" : "详情")))))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar((post.isNewYorkTimes || isWeChatArticle || ["X", "知乎", "Truth", "雪球"].contains(post.sourceName) || post.isYouTube || post.isWeiboRSS) ? .hidden : .visible, for: .navigationBar)
        .navigationBarBackButtonHidden(post.isNewYorkTimes || isWeChatArticle || ["X", "知乎", "Truth", "雪球"].contains(post.sourceName) || post.isYouTube || post.isWeiboRSS)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $presentedWikipediaEntity) { entity in
            WikipediaReaderView(entity: entity)
                .wikipediaReaderPresentation()
        }
        .inAppBrowserCover(item: $presentedXueqiuLink)
        .imageGallery(item: $weiboImageSelection)
        // The Bilibili web player uses horizontal drags for seeking. Disabling the
        // navigation pop recognizer on this screen prevents a scrub from popping
        // the detail view; the visible back button remains available.
        .background(InteractivePopGestureEnabler(
            isEnabled: !post.isBilibili && weiboImageSelection == nil
        ))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if post.isWeiboRSS {
                weiboBottomBar
            }
        }
        .toolbar {
            if presentedAsSheet && !usesCustomDismissControl {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭动态详情")
                }
            }
            if post.isBilibili {
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
            } else if post.isRSS && !post.isNewYorkTimes && !isWeChatArticle {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isRSSBookmarked.toggle()
                        RSSBookmarkStore.set(isRSSBookmarked, postID: post.id)
                    } label: {
                        Image(systemName: isRSSBookmarked ? "bookmark.fill" : "bookmark")
                    }
                    .accessibilityLabel(isRSSBookmarked ? "取消收藏" : "收藏")
                }
            }
        }
        .task {
            let commentsTask = post.sourceName == "X" ? Task { await loadXComments() } : nil
            if post.isNewYorkTimes {
                await loadNewYorkTimesDetail()
            } else {
                await loadDetail()
            }
            await commentsTask?.value
            if post.isYouTube {
                await playYouTubeVideo()
            } else if post.isBilibili {
                await loadBilibiliSubtitles()
                await loadBilibiliSummary()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            if notification.object as? AVPlayerItem === speechPlayer?.currentItem {
                speechPlayer = nil
                isSpeechPlaying = false
                speechErrorMessage = "音频播放失败，请稍后重试"
                return
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard notification.object as? AVPlayerItem === speechPlayer?.currentItem else { return }
            speechPlayer = nil
            isSpeechPlaying = false
        }
        .onDisappear {
            player?.pause()
            speechPlayer?.pause()
            bilibiliPlaybackRetryTask?.cancel()
            bilibiliInterpretationTask?.cancel()
        }
        .alert("朗读失败", isPresented: Binding(
            get: { speechErrorMessage != nil },
            set: { if !$0 { speechErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(speechErrorMessage ?? "请稍后重试")
        }
    }

    @ViewBuilder
    private var newYorkTimesDetail: some View {
        VStack(spacing: 0) {
            newYorkTimesHeader
            Divider()

            if isLoadingNewYorkTimesBody {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在加载完整文章…")
                        .font(.system(size: 16, design: .serif))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(post.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? post.displayTitle)
                            .font(.system(size: 30, weight: .bold, design: .serif))
                            .lineSpacing(3)

                        if let lead = post.newYorkTimesLead, lead != post.displayTitle {
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

                        if let article = newYorkTimesArticle {
                            LazyVStack(alignment: .leading, spacing: 22) {
                                ForEach(Array(article.blocks.enumerated()), id: \.offset) { index, block in
                                    switch block {
                                    case .paragraph(let text):
                                        VStack(alignment: .leading, spacing: 12) {
                                            WikipediaLinkedParagraph(
                                                text: text,
                                                entities: wikipediaEntitiesByParagraph[index] ?? []
                                            ) { entity in
                                                withAnimation(.easeOut(duration: 0.18)) {
                                                    selectedWikipediaEntity = WikipediaSelection(
                                                        paragraphIndex: index,
                                                        entity: entity
                                                    )
                                                }
                                            }
                                            if let selection = selectedWikipediaEntity,
                                               selection.paragraphIndex == index {
                                                WikipediaEntityCard(entity: selection.entity) {
                                                    presentedWikipediaEntity = selection.entity
                                                } close: {
                                                    withAnimation(.easeOut(duration: 0.15)) {
                                                        selectedWikipediaEntity = nil
                                                    }
                                                }
                                            }
                                        }
                                    case .image(let url, let caption, let credit):
                                        if !NewYorkTimesArticle.isSameImageAsset(url, post.imageURLs.first) {
                                            NewYorkTimesArticleImage(
                                                url: url,
                                                caption: caption,
                                                credit: credit,
                                                height: 230
                                            )
                                        }
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
        }
    }

    private var newYorkTimesHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: dismissIconName)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(dismissAccessibilityLabel)

            Spacer(minLength: 0)

            Text("纽约时报")
                .font(.system(size: 17, weight: .semibold, design: .serif))

            Spacer(minLength: 0)

            Button {
                isRSSBookmarked.toggle()
                RSSBookmarkStore.set(isRSSBookmarked, postID: post.id)
            } label: {
                Image(systemName: isRSSBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(isRSSBookmarked ? "取消收藏" : "收藏")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .frame(height: 52)
        .background(.background)
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

    private var rssDetail: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                rssSourceHeader

                Text(post.displayTitle)
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .lineSpacing(4)

                if post.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                   post.summary != post.displayTitle {
                    Text(post.summary ?? "")
                        .font(.system(size: 18, design: .serif))
                        .foregroundStyle(.secondary)
                        .lineSpacing(5)
                }

                rssMetadata

                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(post.rssArticleBlocks.enumerated()), id: \.offset) { _, block in
                        rssArticleBlock(block, isWeChat: false)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(Color(uiColor: .systemBackground))
        .sensoryFeedback(.success, trigger: isRSSBookmarked)
    }

    private var isWeChatArticle: Bool {
        guard let source = post.source, source.hasPrefix("rss:"),
              let feedID = Int(source.dropFirst(4)) else { return false }
        return APIClient.weChatFeedIDs.contains(feedID)
    }

    private var weChatDetail: some View {
        VStack(spacing: 0) {
            weChatDetailHeader

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text(post.displayTitle)
                        .font(.system(size: 25, weight: .semibold))
                        .tracking(-0.25)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Text(post.sourceName)
                            .foregroundStyle(Color(red: 0.34, green: 0.48, blue: 0.62))
                        if let time = post.formattedTime { Text(time) }
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                    .padding(.bottom, 28)

                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(post.rssArticleBlocks.enumerated()), id: \.offset) { _, block in
                            rssArticleBlock(block, isWeChat: true)
                        }
                    }

                }
                .padding(.horizontal, 18)
                .padding(.top, 24)
                .padding(.bottom, 36)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { weChatBottomBar }
        .sensoryFeedback(.success, trigger: isRSSBookmarked)
    }

    private var weChatDetailHeader: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: dismissIconName)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(dismissAccessibilityLabel)

            Spacer(minLength: 0)
            Text(post.sourceName)
                .font(.system(size: 16, weight: .medium))
            Spacer(minLength: 0)

            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .frame(height: 52)
        .background(.background)
    }

    @ViewBuilder
    private func rssArticleBlock(_ block: RSSArticleBlock, isWeChat: Bool) -> some View {
        switch block {
        case .paragraph(let text, let emojis):
            if emojis.isEmpty {
                Text(text)
                    .font(.system(size: isWeChat ? 17 : 19, design: isWeChat ? .default : .serif))
                    .foregroundStyle(isWeChat ? Color(uiColor: .label).opacity(0.9) : .primary)
                    .lineSpacing(isWeChat ? 8 : 9)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                InlineEmojiText(
                    text: text,
                    emojis: emojis,
                    fontSize: isWeChat ? 17 : 19,
                    lineSpacing: isWeChat ? 8 : 9
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .image(let url):
            WeChatArticleImage(url: url)
        }
    }

    private var weChatBottomBar: some View {
        HStack(spacing: 0) {
            Button {
                isRSSBookmarked.toggle()
                RSSBookmarkStore.set(isRSSBookmarked, postID: post.id)
            } label: {
                Label(isRSSBookmarked ? "已收藏" : "收藏", systemImage: isRSSBookmarked ? "bookmark.fill" : "bookmark")
                    .frame(maxWidth: .infinity)
            }

            Divider().frame(height: 26)

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

        }
        .font(.system(size: 13.5, weight: .medium))
        .foregroundStyle(.primary)
        .frame(height: 56)
        .background(.bar)
        .overlay(alignment: .top) { Divider().opacity(0.65) }
    }

    private var weiboDetail: some View {
        VStack(spacing: 0) {
            weiboNavigationBar

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 11) {
                            AvatarView(url: post.avatarURL, name: post.authorName, size: 46)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text(post.authorName)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(post.user?.verified == true ? Color(red: 0.94, green: 0.42, blue: 0.08) : .primary)
                                        .lineLimit(1)

                                    if post.user?.verified == true {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color(red: 0.96, green: 0.55, blue: 0.08))
                                            .accessibilityLabel("已认证")
                                    }
                                }

                                HStack(spacing: 6) {
                                    if let time = post.formattedTime {
                                        Text(time)
                                    }
                                    Text("来自微博")
                                }
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            Button { openOriginal() } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34, height: 34)
                                    .background(Color(uiColor: .secondarySystemBackground), in: Circle())
                            }
                            .accessibilityLabel("更多微博操作")
                        }

                        if !post.weiboDetailContent.isEmpty {
                            InlineEmojiText(
                                text: post.weiboDetailContent,
                                emojis: post.weiboInlineEmojis
                            )
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let videoURL = post.videoURLs.first {
                            XVideoPlayerView(
                                url: videoURL,
                                thumbnailURL: post.previewURL,
                                onAspectRatioResolved: { detectedVideoAspectRatio = $0 }
                            )
                            .id(videoURL)
                            .frame(height: weiboVideoHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        if post.weiboFollowingImageURLs.count == 1,
                           let url = post.weiboFollowingImageURLs.first {
                            WeiboDetailImage(
                                url: url,
                                index: 0,
                                count: 1,
                                initialAspectRatio: post.weiboImageAspectRatio(for: url)
                            ) {
                                weiboImageSelection = ImageGallerySelection(
                                    urls: post.weiboFollowingImageURLs,
                                    initialIndex: 0
                                )
                            }
                        } else if !post.weiboFollowingImageURLs.isEmpty {
                            LazyVGrid(columns: weiboImageColumns, spacing: 4) {
                                ForEach(Array(post.weiboFollowingImageURLs.enumerated()), id: \.element) { index, url in
                                    WeiboDetailImage(
                                        url: url,
                                        index: index,
                                        count: post.weiboFollowingImageURLs.count,
                                        isCompact: true,
                                        compactHeight: weiboGridImageHeight,
                                        initialAspectRatio: post.weiboImageAspectRatio(for: url)
                                    ) {
                                        weiboImageSelection = ImageGallerySelection(
                                            urls: post.weiboFollowingImageURLs,
                                            initialIndex: index
                                        )
                                    }
                                }
                            }
                        }

                        if post.videoURLs.isEmpty,
                           post.hasWeiboVideoReference,
                           let link = post.linkURL {
                            Button { openURL(link) } label: {
                                HStack(spacing: 11) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 17))
                                        .foregroundStyle(.white)
                                        .frame(width: 38, height: 38)
                                        .background(.black.opacity(0.72), in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("微博视频")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        Text("点击前往微博观看")
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(12)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 16)

                    Divider()
                    weiboEngagementRow
                    Rectangle()
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .frame(height: 10)

                    weiboCommentsSection
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .sensoryFeedback(.success, trigger: isRSSBookmarked)
    }

    private var weiboVideoHeight: CGFloat {
        let availableWidth = max(UIScreen.main.bounds.width - 32, 240)
        let metadataAspectRatio: CGFloat? = post.videos?.first.flatMap { video in
            guard let width = video.width,
                  let height = video.height,
                  width > 0,
                  height > 0 else { return nil }
            return CGFloat(width) / CGFloat(height)
        }
        let aspectRatio = max(detectedVideoAspectRatio ?? metadataAspectRatio ?? (16.0 / 9.0), 0.2)
        return min(max(availableWidth / aspectRatio, 180), 620)
    }

    private var weiboNavigationBar: some View {
        ZStack {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: dismissIconName)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dismissAccessibilityLabel)

                Spacer()

                if let link = post.linkURL {
                    ShareLink(item: link) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 34, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("分享")
                }

                Menu {
                    Button {
                        isRSSBookmarked.toggle()
                        RSSBookmarkStore.set(isRSSBookmarked, postID: post.id)
                    } label: {
                        Label(isRSSBookmarked ? "取消收藏" : "收藏", systemImage: isRSSBookmarked ? "bookmark.slash" : "bookmark")
                    }
                    Button { openOriginal() } label: {
                        Label("在微博中打开", systemImage: "safari")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 34, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("更多")
            }

            Text("微博正文")
                .font(.system(size: 17, weight: .semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var weiboImageColumnCount: Int {
        [2, 4].contains(post.weiboFollowingImageURLs.count) ? 2 : 3
    }

    private var weiboImageColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 4),
            count: weiboImageColumnCount
        )
    }

    private var weiboGridImageHeight: CGFloat {
        let availableWidth = max(UIScreen.main.bounds.width - 32, 240)
        let totalSpacing = CGFloat(weiboImageColumnCount - 1) * 4
        return (availableWidth - totalSpacing) / CGFloat(weiboImageColumnCount)
    }

    private var weiboEngagementRow: some View {
        HStack(spacing: 0) {
            weiboEngagementButton(
                icon: "arrow.2.squarepath",
                title: "转发",
                value: post.meta?.metrics?.retweets
            )
            weiboEngagementButton(
                icon: "bubble.left",
                title: "评论",
                value: post.meta?.metrics?.replies
            )
            weiboEngagementButton(
                icon: "hand.thumbsup",
                title: "赞",
                value: post.meta?.metrics?.likes
            )
        }
        .frame(height: 46)
        .background(Color(uiColor: .systemBackground))
    }

    private func weiboEngagementButton(icon: String, title: String, value: Int?) -> some View {
        Button { openOriginal() } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(value.flatMap { $0 > 0 ? compactCount($0) : nil } ?? title)
                    .font(.system(size: 13.5))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value.flatMap { $0 > 0 ? "\(title) \(compactCount($0))" : nil } ?? title)
    }

    private var weiboCommentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("评论")
                    .font(.system(size: 16, weight: .semibold))
                if let replies = post.meta?.metrics?.replies, replies > 0 {
                    Text(compactCount(replies))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { openOriginal() } label: {
                    HStack(spacing: 3) {
                        Text("按热度")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)

            Divider()

            VStack(spacing: 11) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                Text((post.meta?.metrics?.replies ?? 0) > 0 ? "前往微博查看全部评论" : "还没有评论，快来抢沙发")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                if post.linkURL != nil {
                    Button("打开微博") { openOriginal() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.12))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var weiboBottomBar: some View {
        HStack(spacing: 16) {
            Button { openOriginal() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "pencil")
                    Text("写评论...")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
            }
            .buttonStyle(.plain)

            Button { openOriginal() } label: {
                Image(systemName: "arrow.2.squarepath")
            }
            .accessibilityLabel("转发")
            Button { openOriginal() } label: {
                Image(systemName: "bubble.left")
            }
            .accessibilityLabel("评论")
            Button { openOriginal() } label: {
                Image(systemName: "hand.thumbsup")
            }
            .accessibilityLabel("赞")
        }
        .font(.system(size: 18))
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var rssSourceHeader: some View {
        HStack(spacing: 10) {
            AvatarView(url: post.avatarURL, name: post.sourceName, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(post.sourceName)
                    .font(.system(size: 16, weight: .semibold))
                Text("RSS · 原生阅读")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var rssMetadata: some View {
        HStack(spacing: 7) {
            if post.authorName != "RSS" { Text(post.authorName) }
            if let time = post.formattedTime { Text("· \(time)") }
            Text("· 图文")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private var xueqiuDetail: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    xueqiuDetailAuthor

                    if let emoji = post.xueqiuStandaloneInlineEmoji {
                        InlineEmojiImage(emoji: emoji)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if post.xueqiuBodyInlineEmojis.isEmpty {
                        xueqiuRichText(post.xueqiuBodyContent, links: post.xueqiuBodyLinks)
                            .environment(\.openURL, xueqiuLinkOpenAction)
                            .font(.system(size: 20))
                            .lineSpacing(10)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        InlineEmojiText(
                            text: post.xueqiuBodyContent,
                            emojis: post.xueqiuBodyInlineEmojis,
                            fontSize: 20,
                            lineSpacing: 10
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !post.xueqiuBodyImageURLs.isEmpty {
                        PostMediaGrid(
                            post: post,
                            imageURLs: post.xueqiuBodyImageURLs,
                            singleImageMaxHeight: 620,
                            availableWidth: UIScreen.main.bounds.width - 32,
                            cornerRadius: 8
                        )
                    }

                    if post.xueqiuQuoteBody != nil {
                        HStack(spacing: 9) {
                            Image(systemName: "bubble.left.and.bubble.right")
                            Text("查看对话")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .font(.system(size: 15.5))
                        .foregroundStyle(.secondary)
                    }

                    if let quoteBody = post.xueqiuQuoteBody {
                        VStack(alignment: .leading, spacing: 14) {
                            (Text(post.xueqiuQuoteAuthor.map { "@\($0)： " } ?? "")
                                .foregroundStyle(Color.blue) + xueqiuRichText(quoteBody, links: post.xueqiuQuoteLinks))
                                .environment(\.openURL, xueqiuLinkOpenAction)
                                .font(.system(size: 16.5))
                                .lineSpacing(7)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if !post.xueqiuQuoteImageURLs.isEmpty {
                                PostMediaGrid(
                                    post: post,
                                    imageURLs: post.xueqiuQuoteImageURLs,
                                    singleImageMaxHeight: 520,
                                    availableWidth: UIScreen.main.bounds.width - 60,
                                    cornerRadius: 7
                                )
                            }

                            HStack(spacing: 4) {
                                Text("相关讨论")
                                if let replies = post.meta?.metrics?.replies, replies > 0 {
                                    Text(replies.formattedFeedCount)
                                }
                            }
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 9))
                    }

                    if !post.videoURLs.isEmpty || !post.xueqiuUnplacedImageURLs.isEmpty {
                        xMedia
                    }

                    Text("风险提示：用户发表的所有文章仅代表个人观点，与雪球的立场无关。投资决策需建立在独立思考之上。")
                        .font(.system(size: 14.5))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        .lineSpacing(5)

                    Color.clear.frame(height: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { xueqiuDetailBottomBar }
    }

    private var xueqiuDetailAuthor: some View {
        HStack(spacing: 11) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(url: post.avatarURL, name: post.authorName, size: 46)
                Text("V")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 19, height: 19)
                    .background(Color.orange, in: Circle())
                    .overlay { Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(post.authorName)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(xueqiuDetailMetadata)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var xueqiuDetailMetadata: String {
        let time = post.articlePostAt.flatMap { raw -> String? in
            guard let date = ISO8601DateFormatter().date(from: raw) else { return nil }
            return date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
        } ?? post.formattedTime ?? ""
        return time.isEmpty ? "来自雪球" : "修改于 \(time) · 来自雪球"
    }

    private var xueqiuDetailBottomBar: some View {
        HStack {
            Spacer()
            Button { Task { await toggleXueqiuSpeech() } } label: {
                if isSpeechLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isSpeechPlaying ? "speaker.wave.2.fill" : "speaker.wave.2")
                }
            }
            .disabled(isSpeechLoading)
            .accessibilityLabel(isSpeechPlaying ? "暂停朗读" : "朗读正文")
            Spacer()
            Image(systemName: "hand.thumbsup")
            Spacer()
            Image(systemName: "star")
            Spacer()
        }
        .font(.system(size: 23, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .top) { Divider().opacity(0.55) }
    }

    @MainActor
    private func toggleXueqiuSpeech() async {
        if let speechPlayer {
            if speechPlayer.timeControlStatus == .playing {
                speechPlayer.pause()
                isSpeechPlaying = false
            } else {
                speechPlayer.play()
                isSpeechPlaying = true
            }
            return
        }
        isSpeechLoading = true
        defer { isSpeechLoading = false }
        do {
            let url = try await APIClient(baseURL: ServerConfiguration.currentURL)
                .synthesizeSpeech(text: post.xueqiuBodyContent)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            let newPlayer = AVPlayer(url: url)
            speechPlayer = newPlayer
            newPlayer.play()
            isSpeechPlaying = true
        } catch is CancellationError {
            return
        } catch {
            speechErrorMessage = NetworkErrorPresentation.message(for: error)
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
        for link in links where !link.label.isEmpty {
            let searchRange = NSRange(location: searchLocation, length: nsValue.length - searchLocation)
            let range = nsValue.range(of: link.label, options: [], range: searchRange)
            guard range.location != NSNotFound,
                  let stringRange = Range(range, in: value),
                  let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
                  let upper = AttributedString.Index(stringRange.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].foregroundColor = .blue
            attributed[lower..<upper].underlineStyle = .single
            attributed[lower..<upper].link = link.url
            searchLocation = range.location + range.length
        }
        return Text(attributed)
    }

    private var xueqiuLinkOpenAction: OpenURLAction {
        OpenURLAction { url in
            presentedXueqiuLink = InAppBrowserDestination(url: url)
            return .handled
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

            if youtubePlaybackState != .idle, let videoID = post.youtubeVideoID {
                YouTubeEmbeddedPlayer(
                    videoID: videoID,
                    onPlaying: {
                        logYouTubePlaybackReady()
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
                Image(systemName: dismissIconName)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel(dismissAccessibilityLabel)

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
                        Task { await playYouTubeVideo() }
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
                Image(systemName: dismissIconName)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44, alignment: .leading)
            }
            .foregroundStyle(.primary)
            .accessibilityLabel(dismissAccessibilityLabel)

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
                Image(systemName: dismissIconName)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 36, height: 44, alignment: .leading)
            }
            .foregroundStyle(.primary)
            .accessibilityLabel(dismissAccessibilityLabel)

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

                    Divider()

                    bilibiliAISummary

                    Divider()

                    bilibiliVideoInterpretation

                    Divider()

                    bilibiliSubtitles

                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
        }
    }

    @ViewBuilder private var bilibiliVideoInterpretation: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill").foregroundStyle(.blue)
                Text("视频解读").font(.system(size: 19, weight: .bold))
                Spacer()
                if let bilibiliInterpretationModel {
                    Text(bilibiliInterpretationModel).font(.caption).foregroundStyle(.secondary)
                }
            }

            if bilibiliInterpretationStatus == "idle" {
                Text("由 GLM-4.6V 直接观看画面，补充字幕总结看不到的图表、动作、剪辑和时间线信息。")
                    .font(.system(size: 15)).foregroundStyle(.secondary).lineSpacing(3)
                Text("按官方标准价约 2 元/百万 Token；实际费用随视频时长变化，生成后显示本次估算。同一视频 30 天内读取缓存不重复收费。")
                    .font(.caption).foregroundStyle(.secondary)
                Button { startBilibiliInterpretation() } label: {
                    Label("开始视频解读", systemImage: "play.rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent).tint(.blue)
            } else if bilibiliInterpretationStatus == "loading" {
                ProgressView(value: Double(bilibiliInterpretationProgress), total: 100) {
                    Text(bilibiliInterpretationStepLabel ?? "服务器正在处理视频…")
                } currentValueLabel: {
                    Text("\(bilibiliInterpretationProgress)%")
                }
                Text(bilibiliInterpretationDetail ?? "任务已交给服务器，退出当前页面后仍会继续。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let bilibiliInterpretationError {
                ContentUnavailableView("视频解读暂不可用", systemImage: "eye.slash", description: Text(bilibiliInterpretationError))
                Button("重试") { startBilibiliInterpretation() }.buttonStyle(.bordered).tint(.blue)
            } else if let interpretation = bilibiliInterpretation {
                VStack(alignment: .leading, spacing: 16) {
                    Text(interpretation.overview).font(.system(size: 16)).lineSpacing(5).textSelection(.enabled)
                    interpretationBulletSection("画面发现", items: interpretation.visualFindings, color: .blue)
                    if !interpretation.timeline.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("事件时间线").font(.headline)
                            ForEach(Array(interpretation.timeline.enumerated()), id: \.offset) { _, event in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(event.time).font(.caption.monospacedDigit().weight(.bold)).foregroundStyle(.blue).frame(width: 48, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(event.title).font(.subheadline.weight(.semibold))
                                        Text(event.detail).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    interpretationBulletSection("表达与创作观察", items: interpretation.creatorNotes, color: .indigo)
                    if let bilibiliInterpretationCost {
                        HStack(spacing: 10) {
                            Image(systemName: bilibiliInterpretationCached ? "bolt.horizontal.circle.fill" : "yensign.circle.fill")
                                .font(.title3)
                                .foregroundStyle(bilibiliInterpretationCached ? .green : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bilibiliInterpretationCached ? "缓存结果，本次未新增费用" : "本次视频解读费用")
                                    .font(.subheadline.weight(.semibold))
                                Text(String(format: "模型处理成本约 ¥%.3f", bilibiliInterpretationCost))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            (bilibiliInterpretationCached ? Color.green : Color.orange).opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                }
                .padding(14).background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    @ViewBuilder private func interpretationBulletSection(_ title: String, items: [String], color: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(color).frame(width: 6, height: 6).padding(.top, 7)
                        Text(item).font(.subheadline).lineSpacing(3)
                    }
                }
            }
        }
    }

    @ViewBuilder private var bilibiliAISummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("AI 总结")
                    .font(.system(size: 19, weight: .bold))
                Spacer()
                if let bilibiliSummaryModel {
                    Text(bilibiliSummaryModel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if bilibiliSummaryStatus == "loading" {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView("Qwen 正在总结视频内容…")
                    Text("首次生成可能需要几十秒，之后会直接读取缓存。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let bilibiliSummaryError {
                VStack(alignment: .leading, spacing: 10) {
                    ContentUnavailableView(
                        "AI 总结暂不可用",
                        systemImage: "sparkles",
                        description: Text(bilibiliSummaryError)
                    )
                    Button("重新生成") { Task { await loadBilibiliSummary() } }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                }
            } else if let bilibiliSummary {
                VStack(alignment: .leading, spacing: 14) {
                    Text(bilibiliSummary.overview)
                        .font(.system(size: 16))
                        .lineSpacing(5)
                        .textSelection(.enabled)

                    if !bilibiliSummary.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(bilibiliSummary.keyPoints.enumerated()), id: \.offset) { index, point in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(Color.purple, in: Circle())
                                    Text(point)
                                        .font(.system(size: 15))
                                        .lineSpacing(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    @ViewBuilder private var bilibiliSubtitles: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "captions.bubble.fill")
                    .foregroundStyle(.pink)
                Text("中文字幕")
                    .font(.system(size: 19, weight: .bold))
            }

            if bilibiliSubtitleStatus == "loading" {
                ProgressView("正在解析字幕…")
            } else if let bilibiliSubtitleError {
                ContentUnavailableView(
                    "字幕载入失败",
                    systemImage: "captions.bubble",
                    description: Text(bilibiliSubtitleError)
                )
            } else if bilibiliSubtitleCues.isEmpty {
                ContentUnavailableView("该视频暂无可用字幕", systemImage: "captions.bubble")
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(bilibiliSubtitleCues) { cue in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(bilibiliSubtitleTimeLabel(cue.startMS))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .leading)
                            Text(cue.text)
                                .font(.system(size: 16))
                                .lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 10)
                        if cue.id != bilibiliSubtitleCues.last?.id { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder private var bilibiliMedia: some View {
        if let bvid = bilibiliBVID {
            BilibiliEmbeddedPlayer(bvid: bvid)
            .frame(height: 230)
            .background(Color.black)
        } else if let image = post.previewURL {
            ZStack {
                RemoteImage(url: image, height: 230, cornerRadius: 0)
                if post.linkURL != nil {
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
            }
        }
    }

    private var bilibiliBVID: String? {
        let urls = ([post.linkURL] + post.videoURLs.map(Optional.some)).compactMap { $0 }
        let expression = try? NSRegularExpression(pattern: "BV[0-9A-Za-z]{10}", options: [.caseInsensitive])
        for url in urls {
            let value = url.absoluteString
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            if let match = expression?.firstMatch(in: value, range: range),
               let swiftRange = Range(match.range, in: value) {
                return String(value[swiftRange])
            }
        }
        return nil
    }

    private func loadBilibiliSubtitles() async {
        guard let bilibiliBVID else {
            bilibiliSubtitleStatus = "unavailable"
            return
        }
        bilibiliSubtitleStatus = "loading"
        bilibiliSubtitleError = nil
        do {
            let payload = try await APIClient(baseURL: ServerConfiguration.currentURL)
                .fetchBilibiliSubtitles(bvid: bilibiliBVID)
            guard !Task.isCancelled else { return }
            bilibiliSubtitleCues = payload.cues
            bilibiliSubtitleStatus = payload.status
        } catch is CancellationError {
            return
        } catch {
            bilibiliSubtitleStatus = "failed"
            bilibiliSubtitleError = NetworkErrorPresentation.message(for: error)
        }
    }

    private func loadBilibiliSummary() async {
        guard let bilibiliBVID else {
            bilibiliSummaryStatus = "unavailable"
            return
        }
        bilibiliSummaryStatus = "loading"
        bilibiliSummaryError = nil
        do {
            let payload = try await APIClient(baseURL: ServerConfiguration.currentURL)
                .fetchBilibiliSummary(bvid: bilibiliBVID, title: post.bilibiliTitle)
            guard !Task.isCancelled else { return }
            bilibiliSummary = payload.summary
            bilibiliSummaryModel = payload.model
            bilibiliSummaryStatus = payload.status
        } catch is CancellationError {
            return
        } catch {
            bilibiliSummaryStatus = "failed"
            bilibiliSummaryError = NetworkErrorPresentation.message(for: error)
        }
    }

    private func startBilibiliInterpretation() {
        bilibiliInterpretationTask?.cancel()
        bilibiliInterpretationTask = Task { await loadBilibiliInterpretation() }
    }

    private func loadBilibiliInterpretation() async {
        guard let bilibiliBVID else { return }
        bilibiliInterpretationStatus = "loading"
        bilibiliInterpretationError = nil
        do {
            let client = APIClient(baseURL: ServerConfiguration.currentURL)
            var payload = try await client.interpretBilibiliVideo(bvid: bilibiliBVID, title: post.bilibiliTitle)
            while !Task.isCancelled {
                bilibiliInterpretationProgress = payload.progress ?? (payload.status == "ready" ? 100 : 2)
                bilibiliInterpretationStepLabel = payload.stepLabel
                bilibiliInterpretationDetail = payload.detail
                if payload.status == "ready", let interpretation = payload.interpretation {
                    bilibiliInterpretation = interpretation
                    bilibiliInterpretationModel = payload.model
                    bilibiliInterpretationCost = payload.estimatedCostCNY
                    bilibiliInterpretationCached = payload.cached
                    bilibiliInterpretationStatus = "ready"
                    return
                }
                if payload.status == "failed" {
                    bilibiliInterpretationStatus = "failed"
                    bilibiliInterpretationError = payload.error ?? payload.detail ?? "服务器处理失败"
                    return
                }
                try await Task.sleep(for: .seconds(3))
                payload = try await client.fetchBilibiliInterpretationStatus(bvid: bilibiliBVID, title: post.bilibiliTitle)
            }
        } catch is CancellationError {
            return
        } catch {
            bilibiliInterpretationStatus = "failed"
            bilibiliInterpretationError = NetworkErrorPresentation.message(for: error)
        }
    }

    private func bilibiliSubtitleTimeLabel(_ milliseconds: Int64) -> String {
        let totalSeconds = max(0, milliseconds / 1_000)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
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
        VStack(spacing: 0) {
            xNavigationBar

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        xAuthorHeader
                        if !post.isChineseXSource,
                           post.hasTranslation || xLiveTranslationText != nil {
                            HStack(spacing: 5) {
                                Image(systemName: "character.bubble")
                                Text(showsOriginal ? xOriginalLanguageLabel : "翻译自英语")
                                Button(showsOriginal ? "显示翻译" : "显示原文") { showsOriginal.toggle() }
                                    .foregroundStyle(.blue)
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)
                        }

                        Group {
                            if isLoadingXFullText {
                                xFullTextLoadingPlaceholder
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(Array(xDisplayedDetailParagraphs.enumerated()), id: \.offset) { _, paragraph in
                                        Text(xStyledParagraph(paragraph))
                                            .font(.system(size: 17, weight: .regular))
                                            .lineSpacing(3)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .textSelection(.enabled)
                            }
                        }
                        .padding(.top, 24)

                        if let replyHandle = xReplyHandle {
                            Label("回复 \(replyHandle)", systemImage: "arrowshape.turn.up.left")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.top, 14)
                        }

                        if let quote = post.meta?.quotedTweet {
                            xQuotedPostCard(quote)
                                .padding(.top, 16)
                        }

                        if !isLoadingXFullText,
                           XPostTextFormatter.isTruncated(xDisplayedDetailText),
                           post.linkURL != nil {
                            Button { openOriginal() } label: {
                                Label("X 源仅返回了摘要，前往 X 查看全文", systemImage: "arrow.up.right.square")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 16)
                        }

                        if let link = post.externalURL,
                           XPostTextFormatter.shouldShowExternalURL(link) {
                            Button { openURL(link) } label: {
                                Text("阅读更多：\(link.host() ?? link.absoluteString)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 16)
                        }

                        if let credit = post.photoCredit {
                            Text(credit.hasPrefix("📷") ? credit : "📷：\(credit)")
                                .font(.system(size: 15, weight: .medium))
                                .padding(.top, 16)
                        }

                        xMedia
                            .padding(.top, xDetailHasMedia ? 16 : 0)

                        HStack(spacing: 4) {
                            Text(xTimestamp)
                            if let views = xMetrics?.views, views > 0 {
                                Text("·")
                                Text("\(compactCount(views)) 次查看").fontWeight(.semibold).foregroundStyle(.primary)
                            }
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .padding(.top, 18)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                    Divider()
                    xEngagementRow
                        .padding(.horizontal, 15)
                        .frame(height: 44)
                    Divider()

                    xCommentsSection
                }
            }
        }
    }

    private var xNavigationBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: presentedAsSheet ? "xmark" : "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 48)
            }
            .accessibilityLabel(dismissAccessibilityLabel)

            Spacer()
            Text("帖子")
                .font(.system(size: 17, weight: .bold))
            Spacer()

            Menu {
                if let link = post.linkURL {
                    ShareLink(item: link) {
                        Label("分享帖子", systemImage: "square.and.arrow.up")
                    }
                }
                Button("在 X 中打开") { openOriginal() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 40, height: 48)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .frame(height: 50)
        .background(Color(uiColor: .systemBackground))
    }

    private var xDisplayedDetailText: String {
        let value: String
        if showsOriginal || post.isChineseXSource {
            value = xLiveDetail?.fullText ?? post.xStoredOriginalContent
        } else {
            value = XPostTextFormatter.longestText(
                xLiveTranslationText,
                post.hasTranslation ? post.displayContent : nil
            ) ?? post.displayContent
        }
        return XPostTextFormatter.detailText(value)
    }

    private var xOriginalLanguageLabel: String {
        post.isChineseXSource ? "原文" : "英语原文"
    }

    private var xDisplayedDetailParagraphs: [String] {
        XPostTextFormatter.paragraphs(xDisplayedDetailText)
    }

    private var xFullTextLoadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach([1.0, 0.94, 0.98, 0.88, 0.72], id: \.self) { width in
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: (UIScreen.main.bounds.width - 16) * width, height: 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载完整帖子")
    }

    private var xAuthorHeader: some View {
        HStack(spacing: 9) {
            AvatarView(url: post.avatarURL, name: post.authorName, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(post.authorName).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.blue)
                }
                if let handle = post.authorHandle {
                    Text(handle).font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { openOriginal() } label: {
                Text("X.com")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
    }

    private func xStyledParagraph(_ paragraph: String) -> AttributedString {
        var result = AttributedString(paragraph)
        let pattern = #"(?:\$[A-Za-z]{1,8}\b)|(?:@[A-Za-z0-9_]{1,15}\b)|(?:https?://\S+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return result }
        let fullRange = NSRange(paragraph.startIndex..<paragraph.endIndex, in: paragraph)
        for match in expression.matches(in: paragraph, range: fullRange) {
            guard let stringRange = Range(match.range, in: paragraph),
                  let attributedRange = Range(stringRange, in: result) else { continue }
            result[attributedRange].foregroundColor = .blue
        }
        return result
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
                Divider().padding(.leading, 58)
            }
        }
    }

    private var xEngagementRow: some View {
        let metrics = xMetrics
        return HStack {
            xMetric("bubble.left", metrics?.replies)
            Spacer(); xMetric("arrow.2.squarepath", metrics?.retweets)
            Spacer(); xMetric("heart", metrics?.likes)
            Spacer(); xMetric("bookmark", metrics?.bookmarks)
            Spacer()
            if let link = post.linkURL {
                ShareLink(item: link) { Image(systemName: "square.and.arrow.up") }
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .font(.system(size: 16, weight: .regular))
        .foregroundStyle(Color(uiColor: .label).opacity(0.72))
    }

    private func xMetric(_ symbol: String, _ value: Int?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            if let value, value > 0 { Text(compactCount(value)).font(.caption) }
        }
    }

    private var xMetrics: PostMetrics? {
        xLiveDetail?.metrics ?? post.meta?.metrics
    }

    private var xTimestamp: String {
        guard let raw = post.articlePostAt else { return post.formattedTime ?? "" }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: raw) else { return post.formattedTime ?? raw }
        let display = DateFormatter()
        display.locale = Locale(identifier: "zh_CN")
        display.dateFormat = "ah:mm · M/d/yy"
        return display.string(from: date)
    }

    private var xReplyHandle: String? {
        guard let value = post.meta?.inReplyToScreenName?
            .trimmingCharacters(in: CharacterSet(charactersIn: "@")),
              !value.isEmpty else { return nil }
        return "@\(value)"
    }

    private func xQuotedPostCard(_ quote: XQuotedPost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                if let avatar = quote.author?.profileImageURL.flatMap(MediaURL.image) {
                    RemoteImage(url: avatar, height: 28, cornerRadius: 14)
                        .frame(width: 28, height: 28)
                        .clipped()
                }

                Text(quote.author?.name ?? "引用动态")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                if let handle = quote.author?.handle {
                    Text(handle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let text = quote.displayText {
                Text(text)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            ForEach(Array((quote.media ?? []).enumerated()), id: \.offset) { _, media in
                xQuotedMedia(media)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func xQuotedMedia(_ media: XQuotedMedia) -> some View {
        if let videoURL = media.directPlaybackURL ?? media.playbackURL {
            XVideoPlayerView(
                url: videoURL,
                fallbackURL: media.directPlaybackURL == nil ? nil : media.playbackURL,
                thumbnailURL: media.previewURL,
                generatesThumbnailWhenMissing: false
            )
                .frame(height: xQuotedMediaHeight(media))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if let imageURL = media.displayURL {
            RemoteImage(
                url: imageURL,
                height: xQuotedMediaHeight(media),
                cornerRadius: 8,
                contentMode: .fit
            )
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .clipped()
        }
    }

    private func xQuotedMediaHeight(_ media: XQuotedMedia) -> CGFloat {
        let width = UIScreen.main.bounds.width - 42
        guard let mediaWidth = media.width,
              let mediaHeight = media.height,
              mediaWidth > 0,
              mediaHeight > 0 else { return 190 }
        return min(width * CGFloat(mediaHeight) / CGFloat(mediaWidth), 460)
    }

    private var detailImageHeight: CGFloat {
        guard let image = post.images?.first, let width = image.width, let height = image.height, width > 0 else { return 300 }
        let availableWidth = UIScreen.main.bounds.width - 16
        return min(availableWidth * CGFloat(height) / CGFloat(width), 620)
    }

    @ViewBuilder private var xMedia: some View {
        if post.sourceName == "X", let videoURL = xDetailVideoURL {
            XVideoPlayerView(
                url: videoURL,
                fallbackURL: xDetailVideoFallbackURL,
                thumbnailURL: xDetailVideoPreviewURL,
                generatesThumbnailWhenMissing: false,
                onAspectRatioResolved: xVideoMetadataAspectRatio == nil
                    ? { detectedVideoAspectRatio = $0 }
                    : nil
            )
                .id(videoURL)
                .frame(height: xVideoHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if !post.videoURLs.isEmpty {
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else if post.previewURL != nil {
                    PostMediaGrid(post: post, singleImageHeight: xVideoHeight)
                } else {
                    ZStack {
                        Color.black
                        ProgressView().tint(.white)
                    }
                }
            }
            .frame(height: xVideoHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            PostMediaGrid(
                post: post,
                imageURLs: post.isXueqiu ? post.xueqiuUnplacedImageURLs : nil,
                singleImageHeight: detailImageHeight,
                availableWidth: UIScreen.main.bounds.width - 16,
                cornerRadius: 6
            )
        }
    }

    private var xDetailVideoURL: URL? {
        post.directVideoURLs.first ?? xLiveDetail?.directVideoURL
    }

    private var xDetailVideoFallbackURL: URL? {
        post.videoURLs.first ?? xLiveDetail?.videoURL
    }

    private var xDetailVideoPreviewURL: URL? {
        post.previewURL ?? xLiveDetail?.videoPreviewURL
    }

    private var xDetailHasMedia: Bool {
        xDetailVideoURL != nil || !post.imageURLs.isEmpty
    }

    private var xVideoHeight: CGFloat {
        let availableWidth = UIScreen.main.bounds.width - 30
        let aspectRatio = detectedVideoAspectRatio ?? xVideoMetadataAspectRatio ?? (16.0 / 9.0)
        return min(availableWidth / aspectRatio, 620)
    }

    private var xVideoMetadataAspectRatio: CGFloat? {
        let dimensions = post.videos?.first.map { ($0.width, $0.height) }
            ?? xLiveDetail?.videoMedia.map { ($0.width, $0.height) }
        return dimensions.flatMap { dimensions in
            guard let width = dimensions.0,
                  let height = dimensions.1,
                  width > 0,
                  height > 0 else { return nil }
            return CGFloat(width) / CGFloat(height)
        }
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
        guard post.youtubeVideoID != nil else {
            youtubePlaybackState = .failed
            return
        }
        youtubePlaybackState = .loading
        isYouTubeVideoReady = false
        youtubePlaybackStartedAt = .now
        youtubePlaybackLabel = "自适应画质"
        youtubePlayerReloadID = UUID()
    }

    private func logYouTubePlaybackReady() {
        #if DEBUG
        if let youtubePlaybackStartedAt {
            let total = youtubePlaybackStartedAt.duration(to: .now)
            print("YouTube embedded playback ready in \(total.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)))")
        }
        #endif
    }

    private func loadDetail() async {
        guard !post.isSynthetic else { return }
        let client = APIClient(baseURL: ServerConfiguration.currentURL)

        // YouTube's list payload already contains everything rendered by this screen.
        // Avoid fetching the same post again before starting video playback.
        if post.isYouTube {
            player?.pause()
            player = nil
            return
        }

        if !post.isYouTube,
           !post.isBilibili,
           !post.isWeiboRSS,
           post.sourceName != "X",
           player == nil,
           let video = post.videoURLs.first {
            startVideoPlayback(url: video)
            await detectVideoAspectRatio(url: video)
        } else if post.sourceName == "X",
                  xVideoMetadataAspectRatio == nil,
                  let video = post.directVideoURLs.first ?? post.videoURLs.first {
            await detectVideoAspectRatio(url: video)
        }

        if post.sourceName != "X" || post.needsXStoredDetailRefresh,
           let detail = try? await client.fetchPost(id: post.id) {
            if detail.hasTranslation || !post.hasTranslation {
                post = detail
            } else {
                post = detail.replacingTranslation(with: post.displayContent)
            }
            if post.sourceName == "X",
               !XPostTextFormatter.shouldWaitForFullText(post.xStoredOriginalContent) {
                isLoadingXFullText = false
            }
        }
        if post.sourceName == "X", let tweetID = post.xTweetID {
            var translationTweetID = tweetID
            if post.needsXLiveDetail,
               let liveDetail = try? await client.fetchXTweetDetail(tweetID: tweetID) {
                xLiveDetail = liveDetail
                translationTweetID = liveDetail.id
                if post.videoURLs.isEmpty,
                   let videoURL = liveDetail.directVideoURL ?? liveDetail.videoURL,
                   detectedVideoAspectRatio == nil,
                   xVideoMetadataAspectRatio == nil {
                    await detectVideoAspectRatio(url: videoURL)
                }
                if !presentedAsSheet,
                   XPostTextFormatter.shouldPreferFullOriginal(
                    displayed: xDisplayedDetailText,
                    fullOriginal: liveDetail.fullText
                ) {
                    showsOriginal = true
                }
            }
            isLoadingXFullText = false
            if post.needsXTranslation,
               let translation = try? await client.fetchXTranslation(tweetID: translationTweetID) {
                xLiveTranslationText = translation.text
            }
        } else if post.sourceName == "X" {
            isLoadingXFullText = false
        }
        if post.isYouTube || post.isBilibili || post.isWeiboRSS {
            player?.pause()
            player = nil
        } else if post.sourceName != "X",
                  player == nil,
                  let video = post.videoURLs.first {
            startVideoPlayback(url: video)
            await detectVideoAspectRatio(url: video)
        } else if let video = post.videoURLs.first, detectedVideoAspectRatio == nil {
            await detectVideoAspectRatio(url: video)
        }
    }

    private func loadNewYorkTimesDetail() async {
        guard !post.isSynthetic, let link = post.linkURL else {
            isLoadingNewYorkTimesBody = false
            return
        }
        let client = APIClient(baseURL: ServerConfiguration.currentURL)

        // The feed already carries the article body. Render it immediately and
        // keep network refreshes and Wikipedia enrichment off the first-paint path.
        if newYorkTimesArticle != nil {
            isLoadingNewYorkTimesBody = false
        } else {
            if let detail = try? await client.fetchPost(id: post.id) {
                post = detail
            }
            guard !Task.isCancelled else { return }
            let storedArticle = (post.contentZH ?? post.content).flatMap(NewYorkTimesArticle.storedText)
            if let storedArticle {
                newYorkTimesArticle = storedArticle
            } else {
                newYorkTimesArticle = try? await client.fetchNewYorkTimesArticle(url: link)
            }
            isLoadingNewYorkTimesBody = false
        }

        guard !Task.isCancelled, let article = newYorkTimesArticle else { return }
        await enrichNewYorkTimesArticle(article)
    }

    private func enrichNewYorkTimesArticle(_ article: NewYorkTimesArticle) async {
        let paragraphs = article.blocks.compactMap { block -> String? in
            guard case .paragraph(let text) = block else { return nil }
            return text
        }
        let paragraphEntities = await WikipediaEntityResolver.shared.resolve(paragraphs: paragraphs)
        guard !Task.isCancelled else { return }
        var blockEntities: [Int: [WikipediaEntity]] = [:]
        var paragraphIndex = 0
        for (blockIndex, block) in article.blocks.enumerated() {
            guard case .paragraph = block else { continue }
            blockEntities[blockIndex] = paragraphEntities[paragraphIndex]
            paragraphIndex += 1
        }
        wikipediaEntitiesByParagraph = blockEntities
    }

    @MainActor
    private func detectVideoAspectRatio(url: URL) async {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_200, height: 1_200)
        guard let (image, _) = try? await generator.image(at: .zero),
              image.width > 0,
              image.height > 0,
              !Task.isCancelled else { return }
        detectedVideoAspectRatio = CGFloat(image.width) / CGFloat(image.height)
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
        if post.isBilibili { bilibiliPlaybackStartedAt = Date() }
        #if !targetEnvironment(simulator)
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .moviePlayback)
        try? audioSession.setActive(true)
        #endif
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 1
        let newPlayer = AVPlayer(playerItem: item)
        #if targetEnvironment(simulator)
        newPlayer.isMuted = true
        #endif
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        player = newPlayer
        videoPlaybackFailed = false
        isVideoReady = false
        newPlayer.play()
    }

    private func markBilibiliVideoReady() {
        guard !isVideoReady else { return }
        bilibiliPlaybackRetryTask?.cancel()
        bilibiliPlaybackRetryTask = nil
        bilibiliPlaybackRetryCount = 0
        if post.isBilibili, let startedAt = bilibiliPlaybackStartedAt {
            print("[BilibiliTiming] HLS ready in \(String(format: "%.3f", Date().timeIntervalSince(startedAt)))s")
        }
        withAnimation(.easeOut(duration: 0.15)) { isVideoReady = true }
    }

    private func scheduleBilibiliPlaybackRetry() {
        guard post.isBilibili,
              bilibiliPlaybackRetryCount < 12,
              bilibiliPlaybackRetryTask == nil,
              let url = post.videoURLs.first else { return }
        bilibiliPlaybackRetryCount += 1
        bilibiliPlaybackRetryTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            bilibiliPlaybackRetryTask = nil
            player?.pause()
            player = nil
            startVideoPlayback(url: url)
        }
    }

}

private struct BilibiliEmbeddedPlayer: UIViewRepresentable {
    let bvid: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        // Bilibili's control calls the browser Fullscreen API. WKWebView keeps
        // that API disabled unless it is explicitly enabled, so the button
        // otherwise receives the tap without changing presentation.
        configuration.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.allowsBackForwardNavigationGestures = false
        loadPlayer(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedBVID != bvid else { return }
        loadPlayer(in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    private func loadPlayer(in webView: WKWebView) {
        var components = URLComponents(string: "https://player.bilibili.com/player.html")
        components?.queryItems = [
            URLQueryItem(name: "bvid", value: bvid),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "high_quality", value: "1"),
            URLQueryItem(name: "danmaku", value: "0"),
            URLQueryItem(name: "autoplay", value: "1")
        ]
        guard let url = components?.url else { return }
        var request = URLRequest(url: url)
        request.setValue("https://www.bilibili.com/video/\(bvid)", forHTTPHeaderField: "Referer")
        webView.load(request)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedBVID: String?

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            loadedBVID = URLComponents(url: webView.url ?? URL(fileURLWithPath: ""), resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "bvid" })?.value
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               url.host?.contains("bilibili.com") == true {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

private struct XCommentRow: View {
    let comment: XComment
    let translation: String?
    let isTranslating: Bool
    let translate: () async -> Void
    @State private var showsOriginal = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            AvatarView(url: comment.author.avatarURL, name: comment.author.name, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    Text(comment.author.name)
                        .font(.system(size: 15, weight: .bold))
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
                    if let relativeTime {
                        Text("· \(relativeTime)")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                if translation != nil {
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
                Text(showsOriginal || translation == nil ? displayedCommentText : translation ?? displayedCommentText)
                    .font(.system(size: 16))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                HStack {
                    metric("bubble.left", comment.metrics?.replies)
                    Spacer()
                    metric("arrow.2.squarepath", comment.metrics?.retweets)
                    Spacer()
                    metric("heart", comment.metrics?.likes)
                    Spacer()
                    metric("chart.bar.xaxis", comment.metrics?.views)
                    Spacer()
                    metric("bookmark", comment.metrics?.bookmarks)
                    Spacer()
                    ShareLink(item: commentURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(Color(uiColor: .label).opacity(0.66))
                .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 11)
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

    private var displayedCommentText: String {
        XPostTextFormatter.commentText(comment.text, replyingTo: comment.inReplyToScreenName)
    }

    private var commentURL: URL {
        URL(string: "https://x.com/\(comment.author.screenName)/status/\(comment.id)")!
    }

    private var relativeTime: String? {
        guard let raw = comment.createdAt else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        guard let date = parser.date(from: raw) else { return nil }
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "刚刚" }
        if seconds < 3_600 { return "\(Int(seconds / 60))分钟" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))小时" }
        if seconds < 604_800 { return "\(Int(seconds / 86_400))天" }

        let display = DateFormatter()
        display.locale = Locale(identifier: "zh_CN")
        display.dateFormat = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
            ? "M月d日"
            : "yyyy年M月d日"
        return display.string(from: date)
    }
}

private enum YouTubePlaybackState: Equatable {
    case idle, loading, playing, failed
}

private final class BilibiliResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    nonisolated(unsafe) private static var retainedLoaders: [BilibiliResourceLoader] = []
    private static let retainedLoadersLock = NSLock()
    let queue = DispatchQueue(label: "com.wangheng.aiserverclient.bilibili-loader")
    private let sourceURL: URL
    private let headers: [String: String]
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]

    init(sourceURL: URL, headers: [String: String]) {
        self.sourceURL = sourceURL
        self.headers = headers
        super.init()
        Self.retainedLoadersLock.lock()
        Self.retainedLoaders.append(self)
        Self.retainedLoadersLock.unlock()
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        let key = ObjectIdentifier(loadingRequest)
        let start = loadingRequest.dataRequest.map {
            $0.currentOffset > 0 ? $0.currentOffset : $0.requestedOffset
        } ?? 0
        fetchChunk(for: loadingRequest, key: key, start: start)
        return true
    }

    private func fetchChunk(for loadingRequest: AVAssetResourceLoadingRequest, key: ObjectIdentifier, start: Int64) {
        var request = URLRequest(url: sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let dataRequest = loadingRequest.dataRequest {
            let requestedEnd = dataRequest.requestedOffset + Int64(dataRequest.requestedLength)
            let chunkLength = min(max(Int(requestedEnd - start), 1), 512 * 1024)
            let end = start + Int64(chunkLength) - 1
            request.setValue("bytes=\(start)-\(max(start, end))", forHTTPHeaderField: "Range")
        } else {
            request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        }
        let task = URLSession.shared.dataTask(with: request) { [weak self, loadingRequest] data, response, error in
            defer { self?.removeTask(for: key) }
            if let error {
                print("[BilibiliTiming] loader completion error=\(error.localizedDescription)")
                loadingRequest.finishLoading(with: error)
                return
            }
            guard let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                loadingRequest.finishLoading(with: URLError(.badServerResponse))
                return
            }
            self?.queue.async {
                let totalLength = Self.totalLength(from: http) ?? Int64(data.count)
                if let info = loadingRequest.contentInformationRequest {
                    info.contentType = "public.mpeg-4"
                    info.isByteRangeAccessSupported = true
                    info.contentLength = totalLength
                }
                loadingRequest.dataRequest?.respond(with: data)
                guard let dataRequest = loadingRequest.dataRequest else {
                    loadingRequest.finishLoading()
                    return
                }
                let next = start + Int64(data.count)
                let requestedEnd = dataRequest.requestedOffset + Int64(dataRequest.requestedLength)
                if next < requestedEnd, next < totalLength, !loadingRequest.isCancelled {
                    self?.fetchChunk(for: loadingRequest, key: key, start: next)
                } else {
                    loadingRequest.finishLoading()
                }
            }
        }
        lock.lock()
        tasks[key] = task
        lock.unlock()
        task.resume()
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let key = ObjectIdentifier(loadingRequest)
        lock.lock()
        let task = tasks.removeValue(forKey: key)
        lock.unlock()
        task?.cancel()
    }

    private func removeTask(for key: ObjectIdentifier) {
        lock.lock()
        tasks[key] = nil
        lock.unlock()
    }

    private static func totalLength(from response: HTTPURLResponse) -> Int64? {
        guard let value = response.value(forHTTPHeaderField: "Content-Range"),
              let total = value.split(separator: "/").last else { return nil }
        return Int64(total)
    }
}

@MainActor
final class YouTubeWarmPlayerPool: NSObject, WKScriptMessageHandler {
    static let shared = YouTubeWarmPlayerPool()

    private var webViews: [String: WKWebView] = [:]
    private var videoIDsByView: [ObjectIdentifier: String] = [:]
    private var callbacks: [String: (playing: () -> Void, failed: () -> Void, time: (Double) -> Void)] = [:]
    private var prewarmedIDs: Set<String> = []
    private var fullscreenObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]

    func prewarm(videoID: String) -> WKWebView {
        playerView(videoID: videoID, instanceID: "default", options: .standard)
    }

    func start(
        videoID: String,
        instanceID: String,
        options: YouTubePlayerOptions,
        onPlaying: @escaping () -> Void,
        onFailed: @escaping () -> Void,
        onTime: @escaping (Double) -> Void
    ) -> WKWebView {
        let key = "\(videoID)::\(instanceID)::\(options.cacheKey)"
        callbacks[key] = (onPlaying, onFailed, onTime)
        let webView = playerView(videoID: videoID, instanceID: instanceID, options: options)
        if prewarmedIDs.contains(key) {
            webView.evaluateJavaScript("beginPlayback()")
        }
        return webView
    }

    func stopCallbacks(videoID: String) {
        callbacks[videoID] = nil
    }

    func pause(
        videoID: String,
        instanceID: String,
        options: YouTubePlayerOptions
    ) {
        let key = "\(videoID)::\(instanceID)::\(options.cacheKey)"
        webViews[key]?.evaluateJavaScript("player.pauseVideo()")
    }

    func startPlayback(
        videoID: String,
        instanceID: String,
        options: YouTubePlayerOptions
    ) {
        let key = "\(videoID)::\(instanceID)::\(options.cacheKey)"
        webViews[key]?.evaluateJavaScript("beginPlayback()")
    }

    func seek(
        videoID: String,
        instanceID: String,
        options: YouTubePlayerOptions,
        seconds: Double
    ) {
        let key = "\(videoID)::\(instanceID)::\(options.cacheKey)"
        let safeSeconds = max(0, seconds)
        webViews[key]?.evaluateJavaScript("player.seekTo(\(safeSeconds), true); beginPlayback()")
    }

    private func playerView(
        videoID: String,
        instanceID: String,
        options: YouTubePlayerOptions
    ) -> WKWebView {
        let key = "\(videoID)::\(instanceID)::\(options.cacheKey)"
        if let existing = webViews[key] { return existing }

        let contentController = WKUserContentController()
        contentController.add(self, name: "youtubePlayer")
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webViews[key] = webView
        let viewID = ObjectIdentifier(webView)
        videoIDsByView[viewID] = key
        if options.allowsNativeFullscreen {
            fullscreenObservations[viewID] = webView.observe(
                \.fullscreenState,
                options: [.initial, .new]
            ) { _, change in
                let state = change.newValue ?? .notInFullscreen
                Task { @MainActor in
                    AppOrientationController.shared.setVideoFullscreen(
                        state == .enteringFullscreen || state == .inFullscreen
                    )
                }
            }
        }
        webView.loadHTMLString(
            Self.html(videoID: videoID, options: options),
            baseURL: URL(string: "https://www.youtube-nocookie.com")
        )
        return webView
    }

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            guard let webView = message.webView,
                  let videoID = videoIDsByView[ObjectIdentifier(webView)],
                  let value = message.body as? String else { return }
            switch value {
            case "ready":
                if callbacks[videoID] != nil {
                    _ = try? await webView.evaluateJavaScript("beginPlayback()")
                } else {
                    _ = try? await webView.evaluateJavaScript("beginPrewarm()")
                }
            case "playing":
                if let callback = callbacks[videoID] {
                    callback.playing()
                } else if !prewarmedIDs.contains(videoID) {
                    prewarmedIDs.insert(videoID)
                    _ = try? await webView.evaluateJavaScript("player.pauseVideo()")
                }
            default:
                if value.hasPrefix("error:") {
                    callbacks[videoID]?.failed()
                } else if value.hasPrefix("time:"),
                          let seconds = Double(value.dropFirst(5)) {
                    callbacks[videoID]?.time(seconds)
                }
            }
        }
    }

    private static func html(videoID: String, options: YouTubePlayerOptions) -> String {
        let safeID = videoID
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
          <style>html,body,#player{width:100%;height:100%;margin:0;background:#000;overflow:hidden}</style>
        </head>
        <body>
          <div id="player"></div>
          <script src="https://www.youtube.com/iframe_api"></script>
          <script>
            var player;
            function beginPrewarm() { player.mute(); player.playVideo(); }
            function beginPlayback() {
              player.unMute();
              player.playVideo();
            }
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', {
                videoId: '\(safeID)',
                width: '100%',
                height: '100%',
                playerVars: {
                  autoplay: 0,
                  playsinline: 1,
                  rel: 0,
                  modestbranding: 1,
                  fs: \(options.allowsNativeFullscreen ? 1 : 0),
                  cc_load_policy: \(options.loadsBuiltInCaptions ? 1 : 0),
                  cc_lang_pref: 'zh',
                  hl: 'zh-CN'
                },
                events: {
                  onReady: function() {
                    window.webkit.messageHandlers.youtubePlayer.postMessage('ready');
                    setInterval(function() {
                      if (player && player.getCurrentTime) {
                        window.webkit.messageHandlers.youtubePlayer.postMessage('time:' + player.getCurrentTime());
                      }
                    }, 250);
                  },
                  onStateChange: function(event) {
                    if (event.data === YT.PlayerState.PLAYING) {
                      window.webkit.messageHandlers.youtubePlayer.postMessage('playing');
                    }
                  },
                  onError: function(event) {
                    window.webkit.messageHandlers.youtubePlayer.postMessage('error:' + event.data);
                  }
                }
              });
            }
          </script>
        </body>
        </html>
        """
    }
}

struct YouTubePlayerOptions: Hashable {
    let allowsNativeFullscreen: Bool
    let loadsBuiltInCaptions: Bool

    static let standard = YouTubePlayerOptions(
        allowsNativeFullscreen: true,
        loadsBuiltInCaptions: true
    )
    static let customSubtitles = YouTubePlayerOptions(
        allowsNativeFullscreen: false,
        loadsBuiltInCaptions: false
    )

    var cacheKey: String {
        "\(allowsNativeFullscreen ? 1 : 0)-\(loadsBuiltInCaptions ? 1 : 0)"
    }
}

struct YouTubeEmbeddedPlayer: UIViewRepresentable {
    let videoID: String
    var instanceID = "default"
    var options = YouTubePlayerOptions.standard
    let onPlaying: () -> Void
    let onFailed: () -> Void
    var onTime: (Double) -> Void = { _ in }

    func makeUIView(context: Context) -> WKWebView {
        YouTubeWarmPlayerPool.shared.start(
            videoID: videoID,
            instanceID: instanceID,
            options: options,
            onPlaying: onPlaying,
            onFailed: onFailed,
            onTime: onTime
        )
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Void) {}
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

private enum RSSBookmarkStore {
    private static let key = "rss.bookmarkedPostIDs"

    static func contains(_ postID: Int) -> Bool {
        Set(UserDefaults.standard.array(forKey: key) as? [Int] ?? []).contains(postID)
    }

    static func set(_ isBookmarked: Bool, postID: Int) {
        var ids = Set(UserDefaults.standard.array(forKey: key) as? [Int] ?? [])
        if isBookmarked {
            ids.insert(postID)
        } else {
            ids.remove(postID)
        }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}

private struct WeChatArticleImage: View {
    let url: URL
    @State private var aspectRatio: CGFloat = 1.5
    @State private var isCompactAsset = false

    private var availableWidth: CGFloat {
        max(UIScreen.main.bounds.width - 36, 240)
    }

    private var displayWidth: CGFloat {
        isCompactAsset ? min(140, availableWidth) : availableWidth
    }

    private var displayHeight: CGFloat {
        max(isCompactAsset ? 44 : 120, displayWidth / aspectRatio)
    }

    var body: some View {
        RemoteImage(
            url: url,
            height: displayHeight,
            contentMode: .fit,
            onImageLoaded: { image in
                guard image.size.width > 0, image.size.height > 0 else { return }
                aspectRatio = image.size.width / image.size.height
                let pixelWidth = CGFloat(image.cgImage?.width ?? Int(image.size.width * image.scale))
                let pixelHeight = CGFloat(image.cgImage?.height ?? Int(image.size.height * image.scale))
                let ratio = pixelWidth / max(pixelHeight, 1)
                isCompactAsset = max(pixelWidth, pixelHeight) <= 480 && (0.55...1.8).contains(ratio)
            }
        )
        .frame(width: displayWidth, height: displayHeight, alignment: .leading)
        .animation(.easeOut(duration: 0.16), value: isCompactAsset)
    }
}

private struct WeiboDetailImage: View {
    let url: URL
    let index: Int
    let count: Int
    var isCompact = false
    var compactHeight: CGFloat = 172
    var initialAspectRatio: CGFloat?
    let onOpen: () -> Void
    @State private var loadedAspectRatio: CGFloat?

    private var availableWidth: CGFloat {
        max(UIScreen.main.bounds.width - 32, 240)
    }

    private var aspectRatio: CGFloat {
        loadedAspectRatio ?? initialAspectRatio ?? 4 / 3
    }

    private var isLongImage: Bool {
        !isCompact && aspectRatio < 0.6
    }

    private var imageHeight: CGFloat {
        if isCompact { return compactHeight }
        let safeRatio = min(max(aspectRatio, 0.2), 5)
        if isLongImage { return min(availableWidth / safeRatio, 420) }
        return min(max(availableWidth / safeRatio, 100), 520)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(
                url: url,
                height: imageHeight,
                cornerRadius: 8,
                contentMode: (isLongImage || isCompact) ? .fill : .fit
            ) { image in
                guard image.size.width > 0, image.size.height > 0 else { return }
                loadedAspectRatio = image.size.width / image.size.height
            }

            if isLongImage {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                    Text("长图 · 点击查看完整图片")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.black.opacity(0.58))
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityLabel("微博配图，第 \(index + 1) 张，共 \(count) 张")
        .accessibilityHint(count > 1 ? "双击全屏查看并左右滑动切换" : "双击全屏查看")
    }
}

private struct NewYorkTimesArticleImage: View {
    let url: URL
    var caption: String? = nil
    var credit: String? = nil
    var height: CGFloat
    @State private var gallerySelection: ImageGallerySelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RemoteImage(url: url, height: height, contentMode: .fit)
                .contentShape(Rectangle())
                .onTapGesture {
                    gallerySelection = ImageGallerySelection(urls: [url], initialIndex: 0)
                }

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
        .imageGallery(item: $gallerySelection)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
