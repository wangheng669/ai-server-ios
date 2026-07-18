import SwiftUI
import UIKit
import ImageIO
import AVKit

struct PostAuthorHeader: View {
    let post: Post
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            AvatarView(url: post.avatarURL, name: post.authorName, size: compact ? 34 : 42)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(post.authorName).font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold)).lineLimit(1)
                    if post.sourceName == "X" { Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.blue) }
                }
                HStack(spacing: 5) {
                    if let handle = post.authorHandle { Text(handle) }
                    if let time = post.formattedTime { Text(time) }
                    if post.isRSS { Text("来自\(post.sourceName)") }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let score = post.score, score > 0 {
                Text(score.formatted(.number.precision(.fractionLength(1))))
                    .font(.caption2.weight(.semibold)).foregroundStyle(score >= 8 ? .green : .secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.09), in: Capsule())
            }
            Image(systemName: "ellipsis").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AvatarView: View {
    let url: URL?
    let name: String
    let size: CGFloat
    var assetName: String? = nil
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let assetName { Image(assetName).resizable().scaledToFill() }
            else if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Circle().fill(Color.blue.opacity(0.11)).overlay { Text(name.prefix(1)).font(.caption.bold()).foregroundStyle(.blue) } }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .task(id: url) {
            guard assetName == nil else { return }
            image = await ImageLoader.load(url, targetSize: CGSize(width: size, height: size))
        }
    }
}

struct RemoteImage: View {
    let url: URL
    var height: CGFloat? = nil
    var cornerRadius: CGFloat = 0
    var contentMode: ContentMode = .fill
    var onImageLoaded: ((UIImage) -> Void)? = nil
    @State private var image: UIImage?
    @State private var finished = false

    var body: some View {
        ZStack {
            Color.clear
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if finished {
                Image(systemName: "photo").foregroundStyle(.secondary)
            } else {
                ProgressView().foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped().clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .task(id: url) {
            finished = false
            let targetHeight = height ?? UIScreen.main.bounds.height
            let loadedImage = await ImageLoader.load(
                url,
                targetSize: CGSize(width: UIScreen.main.bounds.width, height: targetHeight)
            )
            image = loadedImage
            if let loadedImage { onImageLoaded?(loadedImage) }
            finished = true
        }
    }

}

actor ImageLoader {
    static let shared = ImageLoader()

    private struct Download {
        let id: UUID
        let task: Task<Data?, Never>
    }

    private let cache = NSCache<NSString, UIImage>()
    private var downloads: [URL: Download] = [:]

    private init() {
        cache.totalCostLimit = 96 * 1024 * 1024
        cache.countLimit = 240
    }

    static func load(_ url: URL?, targetSize: CGSize? = nil) async -> UIImage? {
        guard let url else { return nil }
        return await shared.image(for: url, targetSize: targetSize, scale: UIScreen.main.scale)
    }

    private func image(for url: URL, targetSize: CGSize?, scale: CGFloat) async -> UIImage? {
        let pixelLimit = targetSize.map { max($0.width, $0.height) * scale }
        let cacheKey = NSString(string: "\(url.absoluteString)|\(Int(pixelLimit ?? 0))")
        if let cached = cache.object(forKey: cacheKey) { return cached }

        let download: Download
        if let existing = downloads[url] {
            download = existing
        } else {
            let created = Download(id: UUID(), task: Task { await Self.download(url) })
            downloads[url] = created
            download = created
        }

        let data = await download.task.value
        if downloads[url]?.id == download.id { downloads[url] = nil }
        guard let data else { return nil }

        let image = await Task.detached(priority: .utility) {
            Self.decode(data, pixelLimit: pixelLimit, scale: scale)
        }.value
        guard let image else { return nil }
        let cost = max(1, image.cgImage.map { $0.bytesPerRow * $0.height } ?? Int(image.size.width * image.size.height * scale * scale * 4))
        cache.setObject(image, forKey: cacheKey, cost: cost)
        return image
    }

    private static func download(_ url: URL) async -> Data? {
        var candidates = [url]
        if url.path.hasSuffix("image-proxy"),
           let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
           let direct = URL(string: target) {
            candidates.append(direct)
        }

        for candidate in candidates {
            var request = URLRequest(url: candidate, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
            request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  http.mimeType?.lowercased() != "image/svg+xml",
                  !data.isEmpty else { continue }
            return data
        }
        return nil
    }

    private static func decode(_ data: Data, pixelLimit: CGFloat?, scale: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any]
        if let pixelLimit, pixelLimit > 0 {
            options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, Int(pixelLimit)),
                kCGImageSourceShouldCacheImmediately: true
            ]
        } else {
            options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ]
        }
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        return image.size.width > 1 && image.size.height > 1 ? image : nil
    }
}

struct PostMediaGrid: View {
    let post: Post
    var singleImageHeight: CGFloat? = nil
    var singleImageMaxHeight: CGFloat? = nil
    var singleImageContentMode: ContentMode = .fit
    var multiImageHeight: CGFloat = 132
    var availableWidth: CGFloat? = nil
    @State private var previewURL: URL?
    @State private var compactImageURLs: Set<URL> = []

    private var knownCompactImageURLs: Set<URL> {
        guard post.isRSS else { return [] }
        let knownURLs = Set((post.images ?? []).filter(\.isKnownInlineAsset).compactMap { MediaURL.image($0.url) })
        return knownURLs.union(post.htmlInlineAssetURLs)
    }

    private var contentImageURLs: [URL] {
        Array(post.imageURLs.filter { !knownCompactImageURLs.contains($0) && !compactImageURLs.contains($0) }.prefix(4))
    }

    private var resolvedSingleImageHeight: CGFloat {
        if let singleImageHeight { return singleImageHeight }
        let availableWidth = availableWidth ?? UIScreen.main.bounds.width - 28
        guard let image = post.images?.first(where: { !post.isRSS || !$0.isKnownInlineAsset }),
              let width = image.width,
              let height = image.height,
              width > 0,
              height > 0 else {
            return min(210, singleImageMaxHeight ?? 210)
        }
        return min(availableWidth * CGFloat(height) / CGFloat(width), singleImageMaxHeight ?? 560)
    }

    private func classifyInlineAsset(_ image: UIImage, at url: URL) {
        guard post.isRSS, let cgImage = image.cgImage else { return }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return }

        let aspectRatio = width / height
        let isSmallIcon = max(width, height) <= 192 && (0.5...2).contains(aspectRatio)
        let isShortBadge = height <= 96 && width <= 360 && aspectRatio > 2
        guard isSmallIcon || isShortBadge else { return }

        compactImageURLs.insert(url)
    }

    private func showPreview(_ url: URL) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { previewURL = url }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let urls = contentImageURLs
            if urls.count == 1, let url = urls.first {
                Button { showPreview(url) } label: {
                    RemoteImage(
                        url: url,
                        height: resolvedSingleImageHeight,
                        cornerRadius: 8,
                        contentMode: singleImageContentMode,
                        onImageLoaded: { classifyInlineAsset($0, at: url) }
                    )
                        .overlay(alignment: .center) { if !(post.videos ?? []).isEmpty { playButton } }
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看图片")
            } else if !urls.isEmpty {
                LazyVGrid(columns: [.init(.flexible(), spacing: 3), .init(.flexible(), spacing: 3)], spacing: 3) {
                    ForEach(urls, id: \.self) { url in
                        Button { showPreview(url) } label: {
                            RemoteImage(
                                url: url,
                                height: multiImageHeight,
                                cornerRadius: 6,
                                contentMode: .fit,
                                onImageLoaded: { classifyInlineAsset($0, at: url) }
                            )
                                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看图片")
                    }
                }
            } else if let preview = post.previewURL {
                Button { showPreview(preview) } label: {
                    RemoteImage(url: preview, height: resolvedSingleImageHeight, cornerRadius: 8, contentMode: singleImageContentMode)
                        .overlay { playButton }
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看图片")
            }
        }
        .fullScreenCover(item: $previewURL) { url in ZoomableImageView(url: url) }
    }

    private var playButton: some View {
        Image(systemName: "play.circle.fill").font(.system(size: 48)).symbolRenderingMode(.palette)
            .foregroundStyle(.white, .black.opacity(0.45)).shadow(radius: 4)
    }
}

struct XFeedMediaView: View {
    let post: Post
    var horizontalInset: CGFloat = 78
    @State private var showsFullscreenPlayer = false
    @State private var inlinePlayer: AVPlayer?
    @State private var detectedVideoAspectRatio: CGFloat?

    var body: some View {
        if let videoURL = post.videoURLs.first {
            Color.black
                .aspectRatio(videoAspectRatio, contentMode: .fit)
                .overlay {
                    XInlineVideoView(
                        url: videoURL,
                        onPlayerAvailable: { inlinePlayer = $0 },
                        onAspectRatioDetected: { detectedVideoAspectRatio = $0 }
                    )
                }
                .overlay(alignment: .topLeading) {
                    Button {
                        guard inlinePlayer != nil else { return }
                        showsFullscreenPlayer = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 34)
                            .background(.black.opacity(0.68), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .accessibilityLabel("全屏播放")
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .fullScreenCover(isPresented: $showsFullscreenPlayer) {
                    if let inlinePlayer {
                        FullscreenInlineVideoView(player: inlinePlayer)
                    }
                }
        } else {
            PostMediaGrid(
                post: post,
                singleImageMaxHeight: 420,
                availableWidth: availableWidth
            )
        }
    }

    private var availableWidth: CGFloat {
        max(UIScreen.main.bounds.width - horizontalInset, 240)
    }

    private var videoAspectRatio: CGFloat {
        if let detectedVideoAspectRatio, detectedVideoAspectRatio > 0 {
            return detectedVideoAspectRatio
        }
        guard let video = post.videos?.first,
              let width = video.width,
              let height = video.height,
              width > 0,
              height > 0 else {
            return 16.0 / 9.0
        }
        return CGFloat(width) / CGFloat(height)
    }
}

@MainActor
final class XVideoPlaybackSession {
    static let shared = XVideoPlaybackSession()

    private weak var activePlayer: AVPlayer?
    private var activeURL: URL?
    private var positions: [URL: CMTime] = [:]

    func play(_ player: AVPlayer, url: URL) {
        claimPlayback(player, url: url)
        if let position = positions[url], position.isNumeric, position.seconds > 0.25 {
            player.seek(to: position, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.play()
    }

    /// Called from AVPlayer's real playback state as well as our custom button.
    /// This catches playback started from the native VideoPlayer controls.
    func claimPlayback(_ player: AVPlayer, url: URL) {
        guard activePlayer !== player else { return }
        if let activePlayer {
            savePosition(of: activePlayer, url: activeURL)
            activePlayer.pause()
        }
        activePlayer = player
        activeURL = url
    }

    func pause(_ player: AVPlayer, url: URL) {
        savePosition(of: player, url: url)
        player.pause()
        if activePlayer === player {
            activePlayer = nil
            activeURL = nil
        }
    }

    func pauseActive() {
        guard let activePlayer else { return }
        savePosition(of: activePlayer, url: activeURL)
        activePlayer.pause()
        self.activePlayer = nil
        activeURL = nil
    }

    private func savePosition(of player: AVPlayer, url: URL?) {
        guard let url else { return }
        let position = player.currentTime()
        guard position.isNumeric, position.seconds.isFinite, position.seconds > 0 else { return }
        positions[url] = position
    }
}

private struct XInlineVideoView: View {
    private static let thumbnailCache = NSCache<NSURL, UIImage>()

    @State private var player: AVPlayer
    @State private var thumbnail: UIImage?
    @State private var hasStartedPlayback = false
    @State private var isPlaying = false
    @State private var thumbnailFailed = false
    @AppStorage("x.video.isMuted") private var isMuted = false
    private let url: URL
    private let onPlayerAvailable: (AVPlayer) -> Void
    private let onAspectRatioDetected: (CGFloat) -> Void

    init(
        url: URL,
        onPlayerAvailable: @escaping (AVPlayer) -> Void,
        onAspectRatioDetected: @escaping (CGFloat) -> Void
    ) {
        self.url = url
        self.onPlayerAvailable = onPlayerAvailable
        self.onAspectRatioDetected = onAspectRatioDetected
        let player = AVPlayer(url: url)
        player.isMuted = UserDefaults.standard.bool(forKey: "x.video.isMuted")
        _player = State(initialValue: player)
    }

    var body: some View {
        ZStack {
            Color.black

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else if !hasStartedPlayback, !thumbnailFailed {
                ProgressView().tint(.white)
            }

            VideoPlayer(player: player)
                .opacity(hasStartedPlayback ? 1 : 0.001)

            if !hasStartedPlayback {
                Button {
                    activateAudioSession()
                    player.isMuted = isMuted
                    hasStartedPlayback = true
                    isPlaying = true
                    XVideoPlaybackSession.shared.play(player, url: url)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 40)
                        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放视频")
            }

            if thumbnailFailed, !hasStartedPlayback {
                Button {
                    thumbnailFailed = false
                    Task { await loadThumbnail(ignoringCache: true) }
                } label: {
                    Label("重试封面", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.62), in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hasStartedPlayback {
                Button {
                    isMuted.toggle()
                    player.isMuted = isMuted
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 30)
                        .background(.black.opacity(0.62), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel(isMuted ? "打开声音" : "静音")
            }
        }
        .overlay(alignment: .bottomLeading) {
            if hasStartedPlayback {
                Button {
                    if isPlaying {
                        player.pause()
                        isPlaying = false
                    } else {
                        activateAudioSession()
                        XVideoPlaybackSession.shared.play(player, url: url)
                        isPlaying = true
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 32)
                        .background(.black.opacity(0.62), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel(isPlaying ? "暂停视频" : "继续播放")
            }
        }
        .clipped()
        .task(id: url) { await loadThumbnail() }
        .onAppear { onPlayerAvailable(player) }
        .onReceive(player.publisher(for: \.timeControlStatus)) { status in
            if status == .playing {
                hasStartedPlayback = true
                isPlaying = true
                XVideoPlaybackSession.shared.claimPlayback(player, url: url)
            } else if status == .paused {
                isPlaying = false
            }
        }
        .onDisappear { XVideoPlaybackSession.shared.pause(player, url: url) }
    }

    private func activateAudioSession() {
        #if !targetEnvironment(simulator)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
        #endif
    }

    @MainActor
    private func loadThumbnail(ignoringCache: Bool = false) async {
        guard thumbnail == nil else { return }
        if !ignoringCache, let cached = Self.thumbnailCache.object(forKey: url as NSURL) {
            thumbnail = cached
            reportAspectRatio(of: cached)
            return
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_200, height: 1_200)
        do {
            let (image, _) = try await generator.image(at: .zero)
            guard !Task.isCancelled else { return }
            let result = UIImage(cgImage: image)
            Self.thumbnailCache.setObject(result, forKey: url as NSURL)
            thumbnail = result
            reportAspectRatio(of: result)
            thumbnailFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            thumbnailFailed = true
        }
    }

    private func reportAspectRatio(of image: UIImage) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        onAspectRatioDetected(image.size.width / image.size.height)
    }
}

private struct FullscreenInlineVideoView: View {
    let player: AVPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.62), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityLabel("退出全屏")
        }
        .onAppear { player.play() }
        .onDisappear { player.pause() }
    }
}

struct FeedEngagementRow: View {
    let post: Post
    var showsOnlyLikeAndBookmark = false
    @State private var isBookmarking = false
    @State private var isBookmarked = false
    @State private var bookmarkError: String?

    init(post: Post, showsOnlyLikeAndBookmark: Bool = false) {
        self.post = post
        self.showsOnlyLikeAndBookmark = showsOnlyLikeAndBookmark
        _isBookmarked = State(initialValue: post.xTweetID.map(XBookmarkStore.contains) ?? false)
    }

    var body: some View {
        Group {
            if showsOnlyLikeAndBookmark {
                HStack {
                    metric("heart", post.meta?.metrics?.likes)
                        .accessibilityLabel("喜欢")
                    Spacer()
                    bookmarkButton
                }
            } else {
                HStack {
                    metric("bubble", post.meta?.metrics?.replies)
                    Spacer()
                    metric("arrow.2.squarepath", post.meta?.metrics?.retweets)
                    Spacer()
                    metric("heart", post.meta?.metrics?.likes)
                    Spacer()
                    metric("chart.bar", post.meta?.metrics?.views)
                    Spacer()
                    Image(systemName: "bookmark")
                    Spacer()
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .font(.system(size: 16, weight: .regular))
        .foregroundStyle(.secondary)
        .frame(height: 24)
        .contentShape(Rectangle())
        .sensoryFeedback(.success, trigger: isBookmarked)
        .alert("书签保存失败", isPresented: bookmarkErrorBinding) {
            Button("知道了", role: .cancel) { bookmarkError = nil }
        } message: {
            Text(bookmarkError ?? "请稍后重试")
        }
    }

    private var bookmarkButton: some View {
        Button { saveBookmark() } label: {
            Group {
                if isBookmarking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isBookmarked ? Color.blue : Color.secondary)
        .disabled(isBookmarking || isBookmarked || post.xTweetID == nil)
        .accessibilityLabel(isBookmarked ? "已加入书签" : "加入书签")
    }

    private var bookmarkErrorBinding: Binding<Bool> {
        Binding(
            get: { bookmarkError != nil },
            set: { if !$0 { bookmarkError = nil } }
        )
    }

    private func saveBookmark() {
        guard let tweetID = post.xTweetID, !isBookmarking, !isBookmarked else { return }
        isBookmarking = true
        Task {
            defer { isBookmarking = false }
            do {
                let result = try await APIClient(baseURL: ServerConfiguration.currentURL).bookmarkXPost(tweetID: tweetID)
                guard result.bookmarked else { throw APIError.invalidResponse }
                XBookmarkStore.insert(tweetID)
                isBookmarked = true
            } catch {
                bookmarkError = error.localizedDescription
            }
        }
    }

    private func metric(_ symbol: String, _ value: Int?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            if let value, value > 0 { Text(compactCount(value)).font(.system(size: 13)) }
        }
    }

    private func compactCount(_ value: Int) -> String {
        if value >= 10_000 {
            return String(format: "%.1f万", Double(value) / 10_000)
                .replacingOccurrences(of: ".0万", with: "万")
        }
        return value.formatted()
    }
}

private enum XBookmarkStore {
    private static let key = "x.bookmarkedTweetIDs"

    static func contains(_ tweetID: String) -> Bool {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? []).contains(tweetID)
    }

    static func insert(_ tweetID: String) {
        var values = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        values.insert(tweetID)
        UserDefaults.standard.set(values.sorted(), forKey: key)
    }
}

struct ZoomableImageView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero
    @State private var isPresented = false
    @State private var isClosing = false

    var body: some View {
        ZStack {
            Color.black.opacity(backdropOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(magnificationGesture.simultaneously(with: dragGesture))
                        .onTapGesture(count: 2) { toggleZoom() }
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(presentationScale)
            .opacity(isPresented ? 1 : 0)
        }
        .presentationBackground(.clear)
        .accessibilityAction(.escape) { close() }
        .task(id: url) { image = await ImageLoader.load(url) }
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { isPresented = true }
        }
    }

    private var presentationScale: CGFloat {
        guard isPresented else { return 0.82 }
        guard scale == 1, offset.height > 0 else { return 1 }
        return max(0.88, 1 - offset.height / 1_600)
    }

    private var backdropOpacity: CGFloat {
        guard isPresented else { return 0 }
        guard scale == 1, offset.height > 0 else { return 1 }
        return max(0, 1 - offset.height / 360)
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in scale = min(max(settledScale * value.magnification, 1), 5) }
            .onEnded { _ in
                settledScale = scale
                if scale == 1 { resetPosition() }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1 {
                    offset = CGSize(width: settledOffset.width + value.translation.width, height: settledOffset.height + value.translation.height)
                } else if value.translation.height > 0 {
                    offset = CGSize(width: 0, height: value.translation.height)
                }
            }
            .onEnded { value in
                if scale > 1 {
                    settledOffset = offset
                } else if shouldDismiss(for: value) {
                    close()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { resetPosition() }
                }
            }
    }

    private func shouldDismiss(for value: DragGesture.Value) -> Bool {
        let isVertical = abs(value.translation.height) > abs(value.translation.width)
        return isVertical && (value.translation.height > 100 || value.predictedEndTranslation.height > 220)
    }

    private func toggleZoom() {
        if scale > 1 { scale = 1; settledScale = 1; resetPosition() }
        else { scale = 2; settledScale = 2 }
    }

    private func resetPosition() { offset = .zero; settledOffset = .zero }

    private func close() {
        guard !isClosing else { return }
        isClosing = true
        withAnimation(.easeOut(duration: 0.16)) { isPresented = false }
        Task {
            try? await Task.sleep(for: .milliseconds(160))
            dismiss()
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct PostActionRow: View {
    let post: Post
    var body: some View {
        HStack {
            action("arrowshape.turn.up.left", "回复")
            Spacer(); action("arrow.2.squarepath", "转发")
            Spacer(); action("heart", "赞")
            Spacer(); Image(systemName: "bookmark").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func action(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.caption).foregroundStyle(.secondary)
    }
}
