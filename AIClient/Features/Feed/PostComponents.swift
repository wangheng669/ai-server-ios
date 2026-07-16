import SwiftUI
import UIKit
import ImageIO

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
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Circle().fill(Color.blue.opacity(0.11)).overlay { Text(name.prefix(1)).font(.caption.bold()).foregroundStyle(.blue) } }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .task(id: url) {
            image = await ImageLoader.load(url, targetSize: CGSize(width: size, height: size))
        }
    }
}

struct RemoteImage: View {
    let url: URL
    var height: CGFloat? = nil
    var cornerRadius: CGFloat = 0
    var contentMode: ContentMode = .fill
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
            image = await ImageLoader.load(
                url,
                targetSize: CGSize(width: UIScreen.main.bounds.width, height: targetHeight)
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

    private var resolvedSingleImageHeight: CGFloat {
        if let singleImageHeight { return singleImageHeight }
        let availableWidth = availableWidth ?? UIScreen.main.bounds.width - 28
        guard let image = post.images?.first,
              let width = image.width,
              let height = image.height,
              width > 0,
              height > 0 else {
            return min(210, singleImageMaxHeight ?? 210)
        }
        return min(availableWidth * CGFloat(height) / CGFloat(width), singleImageMaxHeight ?? 560)
    }

    private func showPreview(_ url: URL) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { previewURL = url }
    }

    var body: some View {
        Group {
            let urls = Array(post.imageURLs.prefix(4))
            if urls.count == 1, let url = urls.first {
                RemoteImage(url: url, height: resolvedSingleImageHeight, cornerRadius: 8, contentMode: singleImageContentMode)
                    .overlay(alignment: .center) { if !(post.videos ?? []).isEmpty { playButton } }
                    .highPriorityGesture(TapGesture().onEnded { showPreview(url) })
            } else if !urls.isEmpty {
                LazyVGrid(columns: [.init(.flexible(), spacing: 3), .init(.flexible(), spacing: 3)], spacing: 3) {
                    ForEach(urls, id: \.self) { url in
                        RemoteImage(url: url, height: multiImageHeight, cornerRadius: 6)
                            .highPriorityGesture(TapGesture().onEnded { showPreview(url) })
                    }
                }
            } else if let preview = post.previewURL {
                RemoteImage(url: preview, height: resolvedSingleImageHeight, cornerRadius: 8, contentMode: singleImageContentMode)
                    .overlay { playButton }
                    .highPriorityGesture(TapGesture().onEnded { showPreview(preview) })
            }
        }
        .fullScreenCover(item: $previewURL) { url in ZoomableImageView(url: url) }
    }

    private var playButton: some View {
        Image(systemName: "play.circle.fill").font(.system(size: 48)).symbolRenderingMode(.palette)
            .foregroundStyle(.white, .black.opacity(0.45)).shadow(radius: 4)
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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(isPresented ? 1 : 0).ignoresSafeArea()
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
            .scaleEffect(isPresented ? 1 : 0.82)
            .opacity(isPresented ? 1 : 0)

            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .padding(.top, 12).padding(.trailing, 16)
            .accessibilityLabel("关闭图片")
        }
        .task(id: url) { image = await ImageLoader.load(url) }
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { isPresented = true }
        }
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
                } else if value.translation.height > 120,
                          abs(value.translation.height) > abs(value.translation.width) {
                    close()
                } else {
                    withAnimation(.snappy) { resetPosition() }
                }
            }
    }

    private func toggleZoom() {
        if scale > 1 { scale = 1; settledScale = 1; resetPosition() }
        else { scale = 2; settledScale = 2 }
    }

    private func resetPosition() { offset = .zero; settledOffset = .zero }

    private func close() {
        withAnimation(.easeIn(duration: 0.18)) { isPresented = false }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
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
