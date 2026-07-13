import Foundation
import Combine

@MainActor
final class NewsFeedViewModel: ObservableObject {
    @Published private(set) var posts: [Post] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = true
    @Published var errorMessage: String?
    @Published var source: FeedSource {
        didSet { UserDefaults.standard.set(source.rawValue, forKey: "feed.source") }
    }

    private struct Snapshot { var posts: [Post]; var page: Int; var canLoadMore: Bool }
    private var cache: [FeedSource: Snapshot] = [:]
    private var page = 1
    private let pageSize = 20

    init() {
        #if DEBUG
        let override = ProcessInfo.processInfo.environment["AI_FEED_SOURCE"]
        #else
        let override: String? = nil
        #endif
        source = FeedSource(rawValue: override ?? UserDefaults.standard.string(forKey: "feed.source") ?? "x") ?? .x
    }

    func select(_ next: FeedSource) {
        guard next != source else { return }
        cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
        source = next
        let saved = cache[next]
        posts = saved?.posts ?? []
        page = saved?.page ?? 1
        canLoadMore = saved?.canLoadMore ?? true
        errorMessage = nil
    }

    func loadInitial() async {
        if !posts.isEmpty { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        let requestedSource = source
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await client.fetchPosts(page: 1, limit: pageSize, source: requestedSource)
            guard source == requestedSource else { return }
            posts = result
            page = 1
            canLoadMore = result.count >= pageSize
            cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
        } catch is CancellationError { } catch { errorMessage = error.localizedDescription }
    }

    func loadMoreIfNeeded(current post: Post) async {
        guard post.id == posts.last?.id, canLoadMore, !isLoadingMore, !isLoading else { return }
        let requestedSource = source
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await client.fetchPosts(page: page + 1, limit: pageSize, source: requestedSource)
            guard source == requestedSource else { return }
            let ids = Set(posts.map(\.id))
            posts += result.filter { !ids.contains($0.id) }
            page += 1
            canLoadMore = result.count >= pageSize
            cache[source] = .init(posts: posts, page: page, canLoadMore: canLoadMore)
        } catch is CancellationError { } catch { errorMessage = error.localizedDescription }
    }

    private var client: APIClient { APIClient(baseURL: ServerConfiguration.currentURL) }
}
