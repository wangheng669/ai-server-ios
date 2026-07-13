import SwiftUI
import AVKit

struct PostDetailView: View {
    @State private var post: Post
    @State private var player: AVPlayer?
    @Environment(\.openURL) private var openURL

    init(post: Post) { _post = State(initialValue: post) }

    var body: some View {
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
        .navigationTitle("详情").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await loadDetail() }
        .onDisappear { player?.pause() }
    }

    private func loadDetail() async {
        guard !post.isSynthetic else { return }
        if let detail = try? await APIClient(baseURL: ServerConfiguration.currentURL).fetchPost(id: post.id) { post = detail }
        if let video = post.videoURLs.first { player = AVPlayer(url: video) }
    }
}
