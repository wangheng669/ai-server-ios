import SwiftUI
import AVKit

struct PostDetailView: View {
    @State private var post: Post
    @State private var player: AVPlayer?
    @Environment(\.openURL) private var openURL

    init(post: Post) { _post = State(initialValue: post) }

    var body: some View {
        Group {
            if post.sourceName == "X" { xDetail }
            else { standardDetail }
        }
        .navigationTitle(post.sourceName == "X" ? "帖子" : "详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if post.sourceName == "X" {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { openOriginal() } label: { Image(systemName: "bell.slash") }
                    Menu {
                        if let link = post.linkURL { ShareLink(item: link) { Label("分享帖子", systemImage: "square.and.arrow.up") } }
                        Button("在 X 中打开") { openOriginal() }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
        }
        .task { await loadDetail() }
        .onDisappear { player?.pause() }
    }

    private var standardDetail: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                PostAuthorHeader(post: post)
                if post.displayTitle != post.displayContent {
                    Text(post.displayTitle).font(.title3.bold())
                }
                Text(post.displayContent).font(.body).lineSpacing(5).textSelection(.enabled)

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

    private var xDetail: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 11) {
                    xAuthorHeader
                    Text(post.displayContent)
                        .font(.system(size: 17))
                        .lineSpacing(3)
                        .textSelection(.enabled)

                    PostMediaGrid(post: post)

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

    private func compactCount(_ value: Int) -> String {
        if value >= 10_000 { return String(format: "%.1f万", Double(value) / 10_000).replacingOccurrences(of: ".0万", with: "万") }
        return value.formatted()
    }

    private func openOriginal() {
        if let link = post.linkURL { openURL(link) }
    }

    private func loadDetail() async {
        guard !post.isSynthetic else { return }
        if let detail = try? await APIClient(baseURL: ServerConfiguration.currentURL).fetchPost(id: post.id) { post = detail }
        if let video = post.videoURLs.first { player = AVPlayer(url: video) }
    }
}
