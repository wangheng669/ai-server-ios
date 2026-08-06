import SwiftUI
import UIKit
import ImageIO
import AVKit
import CryptoKit

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
    var cornerRadius: CGFloat? = nil
    var rejectsUpscaledImages = false
    @State private var image: UIImage?

    private var resolvedCornerRadius: CGFloat { cornerRadius ?? size / 2 }

    var body: some View {
        Group {
            if let assetName { Image(assetName).resizable().scaledToFill() }
            else if let image { Image(uiImage: image).resizable().scaledToFill() }
            else {
                RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                    .fill(Color.blue.opacity(0.11))
                    .overlay { Text(name.prefix(1)).font(.caption.bold()).foregroundStyle(.blue) }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous))
        .task(id: url) {
            guard assetName == nil else { return }
            let loaded = await ImageLoader.load(url, targetSize: CGSize(width: size, height: size))
            if rejectsUpscaledImages,
               let cgImage = loaded?.cgImage,
               min(cgImage.width, cgImage.height) < Int(size * UIScreen.main.scale * 0.9) {
                image = nil
            } else {
                image = loaded
            }
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

struct InlineEmojiImage: View {
    let emoji: WeiboInlineEmoji
    var size: CGFloat = 28
    @State private var image: UIImage?
    @State private var finished = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if finished {
                Text(emoji.token)
                    .font(.system(size: size * 0.72))
            } else {
                ProgressView()
            }
        }
        .frame(width: size, height: size, alignment: .leading)
        .accessibilityLabel(emoji.token)
        .task(id: emoji.url) {
            finished = false
            image = await ImageLoader.load(
                emoji.url,
                targetSize: CGSize(width: size, height: size)
            )
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
    private let dataCache = NSCache<NSURL, NSData>()
    private var downloads: [URL: Download] = [:]

    private init() {
        cache.totalCostLimit = 96 * 1024 * 1024
        cache.countLimit = 240
        dataCache.totalCostLimit = 48 * 1024 * 1024
        dataCache.countLimit = 180
    }

    static func load(_ url: URL?, targetSize: CGSize? = nil) async -> UIImage? {
        guard let url else { return nil }
        return await shared.image(for: url, targetSize: targetSize, scale: UIScreen.main.scale)
    }

    private func image(for url: URL, targetSize: CGSize?, scale: CGFloat) async -> UIImage? {
        let pixelLimit = targetSize.map { max($0.width, $0.height) * scale }
        let cacheKey = NSString(string: "\(url.absoluteString)|\(Int(pixelLimit ?? 0))")
        if let cached = cache.object(forKey: cacheKey) { return cached }

        let data: Data?
        var downloadedData = false
        var loadedFromDisk = false
        if let cachedData = dataCache.object(forKey: url as NSURL) {
            data = cachedData as Data
        } else if let cachedData = await ImageDiskCache.shared.data(for: url) {
            data = cachedData
            loadedFromDisk = true
            dataCache.setObject(cachedData as NSData, forKey: url as NSURL, cost: cachedData.count)
        } else {
            let download: Download
            if let existing = downloads[url] {
                download = existing
            } else {
                let created = Download(id: UUID(), task: Task { await Self.download(url) })
                downloads[url] = created
                download = created
            }

            data = await download.task.value
            if downloads[url]?.id == download.id { downloads[url] = nil }
            if let data {
                downloadedData = true
                dataCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
            }
        }

        guard let data else { return nil }

        let decodedImage = await Task.detached(priority: .utility) {
            Self.decode(data, pixelLimit: pixelLimit, scale: scale)
        }.value
        guard let decodedImage else {
            if loadedFromDisk {
                dataCache.removeObject(forKey: url as NSURL)
                await ImageDiskCache.shared.removeData(for: url)
                return await image(for: url, targetSize: targetSize, scale: scale)
            }
            return nil
        }
        let cost = max(1, decodedImage.cgImage.map { $0.bytesPerRow * $0.height } ?? Int(decodedImage.size.width * decodedImage.size.height * scale * scale * 4))
        cache.setObject(decodedImage, forKey: cacheKey, cost: cost)
        if downloadedData {
            Task(priority: .utility) {
                await ImageDiskCache.shared.store(data, for: url)
            }
        }
        return decodedImage
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

actor ImageDiskCache {
    static let shared = ImageDiskCache(
        directory: ImageDiskCache.defaultDirectory,
        maxBytes: 256 * 1024 * 1024,
        maxFileCount: 1_200
    )

    private let directory: URL
    private let maxBytes: Int
    private let maxFileCount: Int
    private var isPrepared = false
    private var writesSinceTrim = 0

    init(directory: URL, maxBytes: Int, maxFileCount: Int) {
        self.directory = directory
        self.maxBytes = max(1, maxBytes)
        self.maxFileCount = max(1, maxFileCount)
    }

    func data(for url: URL) -> Data? {
        prepareIfNeeded()
        let fileURL = cachedFileURL(for: url)
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe), !data.isEmpty else {
            return nil
        }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return data
    }

    func store(_ data: Data, for url: URL) {
        guard !data.isEmpty else { return }
        prepareIfNeeded()
        let fileURL = cachedFileURL(for: url)
        do {
            try data.write(to: fileURL, options: .atomic)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableFileURL = fileURL
            try? mutableFileURL.setResourceValues(resourceValues)
            writesSinceTrim += 1
            if writesSinceTrim >= 24 {
                trim()
            }
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func removeData(for url: URL) {
        prepareIfNeeded()
        try? FileManager.default.removeItem(at: cachedFileURL(for: url))
    }

    func trim() {
        prepareIfNeeded()
        writesSinceTrim = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }

        var entries = files.compactMap { fileURL -> (url: URL, size: Int, date: Date)? in
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }
            return (fileURL, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var totalBytes = entries.reduce(0) { $0 + $1.size }
        guard totalBytes > maxBytes || entries.count > maxFileCount else { return }

        entries.sort { $0.date < $1.date }
        while (totalBytes > maxBytes || entries.count > maxFileCount), !entries.isEmpty {
            let oldest = entries.removeFirst()
            try? FileManager.default.removeItem(at: oldest.url)
            totalBytes -= oldest.size
        }
    }

    private func prepareIfNeeded() {
        guard !isPrepared else { return }
        isPrepared = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        trim()
    }

    private func cachedFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(filename, isDirectory: false)
    }

    private static var defaultDirectory: URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("FeedImageCache", isDirectory: true)
    }
}

struct PostMediaGrid: View {
    let post: Post
    var imageURLs: [URL]? = nil
    var singleImageHeight: CGFloat? = nil
    var singleImageMaxHeight: CGFloat? = nil
    var singleImageContentMode: ContentMode = .fit
    var multiImageHeight: CGFloat = 132
    var availableWidth: CGFloat? = nil
    var cornerRadius: CGFloat = 8
    var videoContentMode: ContentMode = .fit
    var videoMaxHeight: CGFloat? = nil
    @State private var gallerySelection: ImageGallerySelection?
    @State private var compactImageURLs: Set<URL> = []
    @State private var loadedSingleImageAspectRatio: CGFloat?
    @State private var loadedVideoAspectRatio: CGFloat?

    private var knownCompactImageURLs: Set<URL> {
        guard post.isRSS else { return [] }
        let knownURLs = Set((post.images ?? []).filter(\.isKnownInlineAsset).compactMap { MediaURL.image($0.url) })
        return knownURLs.union(post.htmlInlineAssetURLs)
    }

    private var allContentImageURLs: [URL] {
        (imageURLs ?? post.imageURLs)
            .filter { !knownCompactImageURLs.contains($0) && !compactImageURLs.contains($0) }
    }

    private var contentImageURLs: [URL] {
        Array(allContentImageURLs.prefix(4))
    }

    private var resolvedSingleImageHeight: CGFloat {
        if let singleImageHeight { return singleImageHeight }
        let resolvedWidth = availableWidth ?? UIScreen.main.bounds.width - 28
        if let loadedSingleImageAspectRatio, loadedSingleImageAspectRatio > 0 {
            return min(resolvedWidth / loadedSingleImageAspectRatio, singleImageMaxHeight ?? 560)
        }
        guard let image = post.images?.first(where: { !post.isRSS || !$0.isKnownInlineAsset }),
              let width = image.width,
              let height = image.height,
              width > 0,
              height > 0 else {
            return min(210, singleImageMaxHeight ?? 210)
        }
        return min(resolvedWidth * CGFloat(height) / CGFloat(width), singleImageMaxHeight ?? 560)
    }

    private var resolvedVideoAspectRatio: CGFloat {
        if let loadedVideoAspectRatio, loadedVideoAspectRatio > 0 {
            return loadedVideoAspectRatio
        }
        if let video = post.videos?.first,
           let width = video.width,
           let height = video.height,
           width > 0,
           height > 0 {
            return CGFloat(width) / CGFloat(height)
        }
        return 16 / 9
    }

    private var resolvedVideoSize: CGSize {
        let resolvedWidth = availableWidth ?? UIScreen.main.bounds.width - 28
        if let singleImageHeight {
            return CGSize(width: resolvedWidth, height: singleImageHeight)
        }
        let widthForHeightLimit = videoMaxHeight.map { $0 * resolvedVideoAspectRatio } ?? resolvedWidth
        let width = min(resolvedWidth, widthForHeightLimit)
        return CGSize(width: width, height: width / resolvedVideoAspectRatio)
    }

    private func recordLoadedImage(_ image: UIImage, at url: URL, isSingleImage: Bool) {
        if isSingleImage, image.size.width > 0, image.size.height > 0 {
            loadedSingleImageAspectRatio = image.size.width / image.size.height
        }

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

    private func showGallery(startingAt url: URL, urls: [URL]) {
        let galleryURLs = urls.isEmpty ? [url] : urls
        let initialIndex = galleryURLs.firstIndex(of: url) ?? 0
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            gallerySelection = ImageGallerySelection(urls: galleryURLs, initialIndex: initialIndex)
        }
    }

    @MainActor
    private func loadVideoAspectRatio(for url: URL) async {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let preferredTransform = try? await track.load(.preferredTransform),
              !Task.isCancelled else { return }
        let displayedSize = naturalSize.applying(preferredTransform)
        let width = abs(displayedSize.width)
        let height = abs(displayedSize.height)
        guard width > 0, height > 0 else { return }
        loadedVideoAspectRatio = width / height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let urls = contentImageURLs
            if let videoURL = post.videoURLs.first {
                XVideoPlayerView(
                    url: videoURL,
                    thumbnailURL: post.previewURL,
                    contentMode: videoContentMode
                )
                    .id(videoURL)
                    .frame(width: resolvedVideoSize.width, height: resolvedVideoSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if urls.count == 1, let url = urls.first {
                Button { showGallery(startingAt: url, urls: allContentImageURLs) } label: {
                    RemoteImage(
                        url: url,
                        height: resolvedSingleImageHeight,
                        cornerRadius: cornerRadius,
                        contentMode: singleImageContentMode,
                        onImageLoaded: { recordLoadedImage($0, at: url, isSingleImage: true) }
                    )
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
                .accessibilityLabel("查看图片")
            } else if !urls.isEmpty {
                LazyVGrid(columns: [.init(.flexible(), spacing: 3), .init(.flexible(), spacing: 3)], spacing: 3) {
                    ForEach(urls, id: \.self) { url in
                        Button { showGallery(startingAt: url, urls: allContentImageURLs) } label: {
                            RemoteImage(
                                url: url,
                                height: multiImageHeight,
                                cornerRadius: 6,
                                contentMode: .fit,
                                onImageLoaded: { recordLoadedImage($0, at: url, isSingleImage: false) }
                            )
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看图片")
                    }
                }
            } else if let preview = post.previewURL {
                Button { showGallery(startingAt: preview, urls: [preview]) } label: {
                    RemoteImage(
                        url: preview,
                        height: resolvedSingleImageHeight,
                        cornerRadius: cornerRadius,
                        contentMode: singleImageContentMode
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看图片")
            }
        }
        .frame(maxWidth: availableWidth ?? .infinity, alignment: .leading)
        .clipped()
        .task(id: post.videoURLs.first) {
            guard let videoURL = post.videoURLs.first else { return }
            await loadVideoAspectRatio(for: videoURL)
        }
        .imageGallery(item: $gallerySelection)
    }
}

struct ImageGallerySelection: Identifiable {
    let id = UUID()
    let urls: [URL]
    let initialIndex: Int
}

struct XFeedMediaView: View {
    let post: Post

    var body: some View {
        if let videoURL = post.videoURLs.first {
            XVideoPlayerView(url: videoURL, thumbnailURL: post.previewURL)
                .id(videoURL)
                .frame(height: videoHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            PostMediaGrid(
                post: post,
                singleImageMaxHeight: 420,
                availableWidth: availableWidth,
                cornerRadius: 12
            )
        }
    }

    private var availableWidth: CGFloat {
        max(UIScreen.main.bounds.width - 78, 240)
    }

    private var videoHeight: CGFloat {
        guard let video = post.videos?.first,
              let width = video.width,
              let height = video.height,
              width > 0,
              height > 0 else {
            return availableWidth * 9 / 16
        }
        return min(availableWidth * CGFloat(height) / CGFloat(width), 440)
    }
}

@MainActor
final class XVideoPlaybackSession {
    static let shared = XVideoPlaybackSession()

    private weak var activePlayer: AVPlayer?
    private var activeURL: URL?
    private var positions: [URL: CMTime] = [:]

    func play(_ player: AVPlayer, url: URL) {
        if let activePlayer, activePlayer !== player {
            savePosition(of: activePlayer, url: activeURL)
            activePlayer.pause()
        }
        activePlayer = player
        activeURL = url
        if let position = positions[url], position.isNumeric, position.seconds > 0.25 {
            player.seek(
                to: position,
                toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: 600),
                toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: 600)
            )
        }
        player.playImmediately(atRate: 1)
    }

    func pause(_ player: AVPlayer, url: URL) {
        savePosition(of: player, url: url)
        player.pause()
        if activePlayer === player {
            activePlayer = nil
            activeURL = nil
        }
    }

    private func savePosition(of player: AVPlayer, url: URL?) {
        guard let url else { return }
        let position = player.currentTime()
        guard position.isNumeric, position.seconds.isFinite, position.seconds > 0 else { return }
        positions[url] = position
    }
}

enum XVideoPlayerChromeStyle {
    case standard
    case minimal
}

struct XVideoPlayerView: View {
    private enum PlaybackState {
        case idle
        case preparing
        case playing
        case failed
    }

    private static let thumbnailCache = NSCache<NSURL, UIImage>()

    @State private var player: AVPlayer?
    @State private var thumbnail: UIImage?
    @State private var preparedAsset: AVURLAsset?
    @State private var playbackState: PlaybackState = .idle
    @State private var playbackURL: URL
    @State private var hasUsedFallback = false
    @State private var isVideoReady = false
    @State private var thumbnailFailed = false
    @State private var isFullscreenPresented = false
    @State private var playbackFallbackTask: Task<Void, Never>?
    @AppStorage("x.video.isMuted") private var isMuted = false
    private let fallbackURL: URL?
    private let thumbnailURL: URL?
    private let fallbackThumbnailURL: URL?
    private let contentMode: ContentMode
    private let chromeStyle: XVideoPlayerChromeStyle
    private let isPlaybackActive: Bool
    private let generatesThumbnailWhenMissing: Bool
    private let onAspectRatioResolved: ((CGFloat) -> Void)?

    init(
        url: URL,
        fallbackURL: URL? = nil,
        thumbnailURL: URL? = nil,
        fallbackThumbnailURL: URL? = nil,
        contentMode: ContentMode = .fit,
        chromeStyle: XVideoPlayerChromeStyle = .standard,
        isPlaybackActive: Bool = true,
        generatesThumbnailWhenMissing: Bool = true,
        onAspectRatioResolved: ((CGFloat) -> Void)? = nil
    ) {
        _playbackURL = State(initialValue: url)
        self.fallbackURL = fallbackURL == url ? nil : fallbackURL
        self.thumbnailURL = thumbnailURL
        self.fallbackThumbnailURL = fallbackThumbnailURL == thumbnailURL ? nil : fallbackThumbnailURL
        self.contentMode = contentMode
        self.chromeStyle = chromeStyle
        self.isPlaybackActive = isPlaybackActive
        self.generatesThumbnailWhenMissing = generatesThumbnailWhenMissing
        self.onAspectRatioResolved = onAspectRatioResolved
    }

    var body: some View {
        ZStack {
            Color.black

            if !isVideoReady, let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if playbackState == .idle, !thumbnailFailed, chromeStyle == .standard {
                ProgressView().tint(.white)
            }

            XPlayerLayerView(
                player: player,
                videoGravity: contentMode == .fill ? .resizeAspectFill : .resizeAspect,
                onReadyForDisplay: markVideoReady,
                onFailure: markPlaybackFailed
            )
                .opacity(isVideoReady ? 1 : 0.001)
                .allowsHitTesting(false)

            switch playbackState {
            case .idle:
                if chromeStyle == .minimal {
                    MinimalVideoIdleControls(
                        onPlay: startPlayback,
                        onFullscreen: presentFullscreen
                    )
                    .frame(maxHeight: .infinity, alignment: .bottom)
                } else {
                    Button(action: startPlayback) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 40)
                            .background(
                                .black.opacity(0.62),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("播放视频")
                }
            case .preparing:
                if chromeStyle == .minimal {
                    MinimalVideoLoadingBar()
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .accessibilityLabel("正在加载视频")
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .padding(14)
                        .background(.black.opacity(0.56), in: Circle())
                        .accessibilityLabel("正在加载视频")
                }
            case .failed:
                if chromeStyle == .minimal {
                    MinimalVideoIdleControls(
                        onPlay: startPlayback,
                        onFullscreen: presentFullscreen
                    )
                } else {
                    Button(action: startPlayback) {
                        Label("重试播放", systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.68), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("重试播放视频")
                }
            case .playing:
                EmptyView()
            }

            if chromeStyle == .minimal, playbackState == .playing, let player {
                MinimalVideoControls(
                    player: player,
                    isMuted: $isMuted,
                    onPause: stopPlayback,
                    onFullscreen: presentFullscreen
                )
                .frame(maxHeight: .infinity, alignment: .bottom)
            } else if chromeStyle == .standard,
                      playbackState == .preparing || playbackState == .playing {
                Button {
                    isMuted.toggle()
                    player?.isMuted = isMuted
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: chromeStyle == .minimal ? 12 : 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(
                            width: chromeStyle == .minimal ? 30 : 34,
                            height: chromeStyle == .minimal ? 30 : 30
                        )
                        .background(
                            .black.opacity(chromeStyle == .minimal ? 0.38 : 0.62),
                            in: chromeStyle == .minimal ? AnyShape(Circle()) : AnyShape(Capsule())
                        )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(8)
                .accessibilityLabel(isMuted ? "打开声音" : "静音")
            }

            if thumbnailFailed, playbackState == .idle, chromeStyle == .standard {
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

            if chromeStyle == .standard {
                Button(action: presentFullscreen) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 30)
                        .background(.black.opacity(0.62), in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(8)
                .accessibilityLabel("全屏播放")
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .task(id: playbackURL) {
            if onAspectRatioResolved != nil {
                async let thumbnailLoad: Void = loadThumbnail()
                async let aspectRatioLoad: Void = loadVideoAspectRatio()
                _ = await (thumbnailLoad, aspectRatioLoad)
            } else {
                await loadThumbnail()
            }
        }
        .task(id: "\(isPlaybackActive):\(playbackURL.absoluteString)") {
            guard chromeStyle == .minimal, isPlaybackActive else { return }
            await preparePlaybackAsset()
        }
        .onDisappear {
            stopPlayback()
        }
        .onChange(of: isPlaybackActive) { _, isActive in
            if !isActive {
                stopPlayback()
            }
        }
        .fullScreenCover(isPresented: $isFullscreenPresented) {
            if let player {
                FullscreenVideoPlayerView(player: player, isMuted: $isMuted)
            }
        }
    }

    private func presentFullscreen() {
        guard isPlaybackActive else { return }
        if player == nil {
            startPlayback()
        }
        isFullscreenPresented = true
    }

    private func startPlayback() {
        beginPlayback(with: playbackURL)
    }

    private func beginPlayback(with sourceURL: URL) {
        guard isPlaybackActive else { return }
        activateAudioSession()
        let asset = preparedAsset ?? AVURLAsset(url: sourceURL)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 1
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.isMuted = isMuted
        self.player = player
        isVideoReady = false
        playbackState = .preparing
        XVideoPlaybackSession.shared.play(player, url: sourceURL)
        scheduleFallbackIfNeeded(from: sourceURL)
    }

    @MainActor
    private func preparePlaybackAsset() async {
        guard preparedAsset == nil else { return }
        let asset = AVURLAsset(
            url: playbackURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        do {
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable, !Task.isCancelled, isPlaybackActive else { return }
            preparedAsset = asset
        } catch {
            // Playback remains available through the normal tap-to-load path.
        }
    }

    private func stopPlayback() {
        playbackFallbackTask?.cancel()
        playbackFallbackTask = nil
        if let player {
            XVideoPlaybackSession.shared.pause(player, url: playbackURL)
        }
        self.player = nil
        isVideoReady = false
        playbackState = .idle
    }

    private func markVideoReady() {
        guard playbackState == .preparing else { return }
        playbackFallbackTask?.cancel()
        playbackFallbackTask = nil
        withAnimation(.easeOut(duration: 0.15)) {
            isVideoReady = true
            playbackState = .playing
        }
    }

    private func markPlaybackFailed() {
        guard playbackState == .preparing || playbackState == .playing else { return }
        if let fallbackURL, !hasUsedFallback, playbackURL != fallbackURL {
            switchToFallback(fallbackURL)
            return
        }
        stopPlayback()
        isVideoReady = false
        playbackState = .failed
    }

    private func scheduleFallbackIfNeeded(from sourceURL: URL) {
        playbackFallbackTask?.cancel()
        guard let fallbackURL, !hasUsedFallback, sourceURL != fallbackURL else { return }
        playbackFallbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, playbackState == .preparing else { return }
            switchToFallback(fallbackURL)
        }
    }

    private func switchToFallback(_ fallbackURL: URL) {
        stopPlayback()
        preparedAsset = nil
        hasUsedFallback = true
        playbackURL = fallbackURL
        beginPlayback(with: fallbackURL)
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
        if !ignoringCache, let cached = Self.thumbnailCache.object(forKey: playbackURL as NSURL) {
            thumbnail = cached
            return
        }
        let resolvedThumbnailURL = thumbnailURL ?? (generatesThumbnailWhenMissing ? MediaURL.videoThumbnail(for: playbackURL) : nil)
        let thumbnailURLs = [resolvedThumbnailURL, fallbackThumbnailURL]
            .compactMap { $0 }
            .reduce(into: [URL]()) { result, url in
                if !result.contains(url) { result.append(url) }
            }
        for thumbnailURL in thumbnailURLs {
            guard !Task.isCancelled else { return }
            guard let remoteThumbnail = await ImageLoader.load(
                thumbnailURL,
                targetSize: CGSize(width: 720, height: 720)
            ) else { continue }
            guard !Task.isCancelled else { return }
            Self.thumbnailCache.setObject(remoteThumbnail, forKey: playbackURL as NSURL)
            thumbnail = remoteThumbnail
            thumbnailFailed = false
            return
        }
        guard generatesThumbnailWhenMissing else {
            thumbnailFailed = true
            return
        }
        guard !Task.isCancelled else { return }
        let asset = AVURLAsset(url: playbackURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_200, height: 1_200)
        do {
            let (image, _) = try await generator.image(at: .zero)
            guard !Task.isCancelled else { return }
            let result = UIImage(cgImage: image)
            Self.thumbnailCache.setObject(result, forKey: playbackURL as NSURL)
            thumbnail = result
            thumbnailFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            thumbnailFailed = true
        }
    }

    @MainActor
    private func loadVideoAspectRatio() async {
        let asset = AVURLAsset(url: playbackURL)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let preferredTransform = try? await track.load(.preferredTransform),
              !Task.isCancelled else { return }
        let displayedSize = naturalSize.applying(preferredTransform)
        let width = abs(displayedSize.width)
        let height = abs(displayedSize.height)
        guard width > 0, height > 0 else { return }
        onAspectRatioResolved?(width / height)
    }
}

private struct MinimalVideoLoadingBar: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(.linear)
            .tint(.white.opacity(0.9))
            .scaleEffect(x: 1, y: 0.55, anchor: .bottom)
    }
}

private struct MinimalVideoIdleControls: View {
    let onPlay: () -> Void
    let onFullscreen: () -> Void

    var body: some View {
        ZStack {
            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .offset(x: 2)
                    .frame(width: 76, height: 76)
                    .contentShape(Rectangle())
                    .shadow(color: .black.opacity(0.38), radius: 7, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放视频")

            Button(action: onFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.34), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("全屏播放")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MinimalVideoControls: View {
    let player: AVPlayer
    @Binding var isMuted: Bool
    let onPause: () -> Void
    let onFullscreen: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            VideoPlaybackProgress(player: player)
                .frame(height: 2)

            HStack(spacing: 8) {
                controlButton("pause.fill", label: "暂停视频", action: onPause)
                Spacer()
                controlButton(
                    isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    label: isMuted ? "打开声音" : "静音"
                ) {
                    isMuted.toggle()
                    player.isMuted = isMuted
                }
                controlButton(
                    "arrow.up.left.and.arrow.down.right",
                    label: "全屏播放",
                    action: onFullscreen
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 20)
        .padding(.bottom, 7)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.58)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func controlButton(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct VideoPlaybackProgress: View {
    let player: AVPlayer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.28))
                    Capsule()
                        .fill(.white.opacity(0.95))
                        .frame(width: proxy.size.width * progress)
                }
            }
        }
    }

    private var progress: CGFloat {
        let duration = player.currentItem?.duration.seconds ?? 0
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(max(player.currentTime().seconds / duration, 0), 1)
    }
}

private struct FullscreenVideoPlayerView: View {
    let player: AVPlayer
    @Binding var isMuted: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()

            HStack(spacing: 10) {
                Button {
                    isMuted.toggle()
                    player.isMuted = isMuted
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.62), in: Circle())
                }
                .accessibilityLabel(isMuted ? "打开声音" : "静音")

                Spacer()

                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "xmark")
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.62), in: Circle())
                }
                .accessibilityLabel("退出全屏")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            player.isMuted = isMuted
            player.play()
        }
    }
}

private struct XPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?
    let videoGravity: AVLayerVideoGravity
    let onReadyForDisplay: () -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onReadyForDisplay: onReadyForDisplay,
            onFailure: onFailure
        )
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        context.coordinator.observe(player: player, layer: view.playerLayer)
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        view.playerLayer.player = nil
        coordinator.stopObserving()
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    final class Coordinator {
        private let onReadyForDisplay: () -> Void
        private let onFailure: () -> Void
        private weak var observedPlayer: AVPlayer?
        private var readyObservation: NSKeyValueObservation?
        private var statusObservation: NSKeyValueObservation?
        private var failureObserver: NSObjectProtocol?

        init(
            onReadyForDisplay: @escaping () -> Void,
            onFailure: @escaping () -> Void
        ) {
            self.onReadyForDisplay = onReadyForDisplay
            self.onFailure = onFailure
        }

        func observe(player: AVPlayer?, layer: AVPlayerLayer) {
            guard observedPlayer !== player else { return }
            stopObserving()
            observedPlayer = player
            guard let player, let item = player.currentItem else { return }

            readyObservation = layer.observe(
                \.isReadyForDisplay,
                options: [.initial, .new]
            ) { [weak self] layer, _ in
                guard layer.isReadyForDisplay else { return }
                DispatchQueue.main.async {
                    self?.onReadyForDisplay()
                }
            }
            statusObservation = item.observe(
                \.status,
                options: [.initial, .new]
            ) { [weak self] item, _ in
                guard item.status == .failed else { return }
                DispatchQueue.main.async {
                    self?.onFailure()
                }
            }
            failureObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.onFailure()
            }
        }

        func stopObserving() {
            readyObservation = nil
            statusObservation = nil
            if let failureObserver {
                NotificationCenter.default.removeObserver(failureObserver)
            }
            failureObserver = nil
            observedPlayer = nil
        }

        deinit {
            stopObserving()
        }
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
                HStack(spacing: 0) {
                    metric("bubble", post.meta?.metrics?.replies, label: "回复")
                    Spacer()
                    metric("arrow.2.squarepath", post.meta?.metrics?.retweets, label: "转发")
                    Spacer()
                    metric("heart", post.meta?.metrics?.likes, label: "喜欢")
                    Spacer()
                    metric("chart.bar", post.meta?.metrics?.views, label: "浏览")
                    Spacer()
                    bookmarkButton
                    Spacer()
                    if let link = post.linkURL {
                        ShareLink(item: link) {
                            Image(systemName: "square.and.arrow.up")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("分享")
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 44, height: 44)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .font(.system(size: 16, weight: .regular))
        .foregroundStyle(.secondary)
        .frame(height: 44)
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
            .frame(width: 44, height: 44)
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

    private func metric(_ symbol: String, _ value: Int?, label: String? = nil) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            if let value, value > 0 { Text(compactCount(value)).font(.system(size: 13)) }
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "互动数据")
        .accessibilityValue(value.map(compactCount) ?? "0")
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

extension View {
    func imageGallery(item: Binding<ImageGallerySelection?>) -> some View {
        modifier(ImageGalleryPresentationModifier(selection: item))
    }
}

private struct ImageGalleryPresentationModifier: ViewModifier {
    @Binding var selection: ImageGallerySelection?

    func body(content: Content) -> some View {
        content.background {
            if selection != nil {
                ImageGalleryPresentationBridge(selection: $selection)
                    .frame(width: 0, height: 0)
            }
        }
    }
}

private struct ImageGalleryPresentationBridge: UIViewControllerRepresentable {
    @Binding var selection: ImageGallerySelection?

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.selection = $selection
        guard let selection else {
            context.coordinator.dismiss(animated: false)
            return
        }
        context.coordinator.present(selection, from: controller)
    }

    static func dismantleUIViewController(
        _ controller: UIViewController,
        coordinator: Coordinator
    ) {
        coordinator.dismiss(animated: false)
    }

    @MainActor
    final class Coordinator {
        var selection: Binding<ImageGallerySelection?>
        private var hostingController: UIViewController?
        private var presentedSelectionID: UUID?
        private var pendingSelectionID: UUID?
        private var isDismissing = false

        init(selection: Binding<ImageGallerySelection?>) {
            self.selection = selection
        }

        func present(_ selection: ImageGallerySelection, from controller: UIViewController) {
            guard presentedSelectionID != selection.id, hostingController == nil else { return }
            guard controller.viewIfLoaded?.window != nil else {
                guard pendingSelectionID != selection.id else { return }
                pendingSelectionID = selection.id
                DispatchQueue.main.async { [weak self, weak controller] in
                    guard let self, let controller else { return }
                    self.pendingSelectionID = nil
                    guard controller.viewIfLoaded?.window != nil,
                          let selection = self.selection.wrappedValue else { return }
                    self.present(selection, from: controller)
                }
                return
            }

            pendingSelectionID = nil
            presentedSelectionID = selection.id
            let gallery = ImageGalleryView(
                urls: selection.urls,
                initialIndex: selection.initialIndex
            ) { [weak self] in
                self?.dismiss(animated: true)
            }
            let hostingController = UIHostingController(rootView: gallery)
            hostingController.view.backgroundColor = .clear
            hostingController.modalPresentationStyle = .overFullScreen
            hostingController.modalTransitionStyle = .crossDissolve
            self.hostingController = hostingController
            controller.present(hostingController, animated: true)
        }

        func dismiss(animated: Bool) {
            guard !isDismissing else { return }
            guard let hostingController else {
                presentedSelectionID = nil
                return
            }

            isDismissing = true
            hostingController.dismiss(animated: animated) { [weak self] in
                guard let self else { return }
                self.hostingController = nil
                self.presentedSelectionID = nil
                self.isDismissing = false
                if self.selection.wrappedValue != nil {
                    self.selection.wrappedValue = nil
                }
            }
        }
    }
}

struct ImageGalleryView: View {
    let urls: [URL]
    private let onDismiss: (() -> Void)?
    @Environment(\.dismiss) private var environmentDismiss
    @State private var selectedIndex: Int

    init(
        urls: [URL],
        initialIndex: Int = 0,
        onDismiss: (() -> Void)? = nil
    ) {
        let requestedURL = urls.indices.contains(initialIndex) ? urls[initialIndex] : urls.first
        var seen: Set<URL> = []
        let uniqueURLs = urls.filter { seen.insert($0).inserted }
        self.urls = uniqueURLs
        self.onDismiss = onDismiss
        _selectedIndex = State(
            initialValue: requestedURL.flatMap(uniqueURLs.firstIndex(of:)) ?? 0
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if urls.isEmpty {
                ContentUnavailableView(
                    "图片不可用",
                    systemImage: "photo",
                    description: Text("没有可预览的图片")
                )
                .foregroundStyle(.white)
            } else {
                TabView(selection: $selectedIndex) {
                    ForEach(urls.indices, id: \.self) { index in
                        GalleryImagePage(
                            url: urls[index],
                            isActive: selectedIndex == index,
                            position: index + 1,
                            count: urls.count,
                            onBackgroundTap: requestDismiss
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            ZStack {
                if urls.count > 1 {
                    Text("\(selectedIndex + 1) / \(urls.count)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(.black.opacity(0.56), in: Capsule())
                        .accessibilityLabel("第 \(selectedIndex + 1) 张，共 \(urls.count) 张")
                }

                HStack {
                    Spacer()
                    Button(action: requestDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.black.opacity(0.56), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭图片")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .statusBarHidden()
        .interactiveDismissDisabled()
        .accessibilityAction(.escape, requestDismiss)
    }

    private func requestDismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            environmentDismiss()
        }
    }
}

private struct GalleryImagePage: View {
    let url: URL
    let isActive: Bool
    let position: Int
    let count: Int
    let onBackgroundTap: () -> Void
    @State private var image: UIImage?
    @State private var didFail = false
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onBackgroundTap)

                if let image {
                    let imageSize = fittedImageSize(image, in: proxy.size)
                    Image(uiImage: image)
                        .resizable()
                        .frame(
                            width: imageSize.width,
                            height: imageSize.height
                        )
                        .scaleEffect(scale)
                        .offset(offset)
                        .contentShape(Rectangle())
                        .gesture(
                            dragGesture(in: proxy.size),
                            including: scale > 1 ? .all : .none
                        )
                        .simultaneousGesture(magnificationGesture(in: proxy.size))
                        .onTapGesture(count: 2) {
                            toggleZoom(in: proxy.size)
                        }
                } else if didFail {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                        Text("图片加载失败")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .task(id: url) {
            didFail = false
            image = await ImageLoader.load(url)
            didFail = image == nil
            resetZoom()
        }
        .onChange(of: isActive) { _, active in
            if !active { resetZoom() }
        }
        .accessibilityLabel("第 \(position) 张图片，共 \(count) 张")
        .accessibilityHint(count > 1 ? "左右滑动切换，双击或捏合缩放" : "双击或捏合缩放")
    }

    private func magnificationGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(settledScale * value.magnification, 1), 5)
                offset = clamped(offset, in: size, at: scale)
            }
            .onEnded { _ in
                settledScale = scale
                if scale <= 1 {
                    resetZoom()
                } else {
                    offset = clamped(offset, in: size, at: scale)
                    settledOffset = offset
                }
            }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                let proposed = CGSize(
                    width: settledOffset.width + value.translation.width,
                    height: settledOffset.height + value.translation.height
                )
                offset = clamped(proposed, in: size, at: scale)
            }
            .onEnded { _ in
                settledOffset = clamped(offset, in: size, at: scale)
                offset = settledOffset
            }
    }

    private func clamped(_ value: CGSize, in size: CGSize, at scale: CGFloat) -> CGSize {
        guard scale > 1, let image else { return .zero }
        let fittedSize = fittedImageSize(image, in: size)
        let maximumX = max(0, (fittedSize.width * scale - size.width) / 2)
        let maximumY = max(0, (fittedSize.height * scale - size.height) / 2)
        return CGSize(
            width: min(max(value.width, -maximumX), maximumX),
            height: min(max(value.height, -maximumY), maximumY)
        )
    }

    private func fittedImageSize(_ image: UIImage, in containerSize: CGSize) -> CGSize {
        guard image.size.width > 0,
              image.size.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return containerSize
        }
        let fitScale = min(
            containerSize.width / image.size.width,
            containerSize.height / image.size.height
        )
        return CGSize(
            width: image.size.width * fitScale,
            height: image.size.height * fitScale
        )
    }

    private func toggleZoom(in size: CGSize) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            if scale > 1 {
                resetZoom()
            } else {
                scale = 2
                settledScale = 2
                offset = clamped(offset, in: size, at: 2)
                settledOffset = offset
            }
        }
    }

    private func resetZoom() {
        scale = 1
        settledScale = 1
        offset = .zero
        settledOffset = .zero
    }
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
