import Foundation
import Observation

@MainActor
@Observable
final class PersonDetailStore {
    private(set) var ownPosts: [Post] = []
    private(set) var discussions: [Post] = []
    private(set) var isLoadingOwnPosts = false
    private(set) var isLoadingMoreOwnPosts = false
    private(set) var isLoadingDiscussions = false
    private(set) var ownPostsError: String?
    private(set) var ownPostsLoadMoreError: String?
    private(set) var discussionsError: String?
    private(set) var canLoadMoreOwnPosts = true
    private(set) var xTranslations: [Int: String] = [:]
    private var loadingXTranslationIDs: Set<Int> = []
    private var ownPostsPage = 1
    private let pageSize = 12
    private let baseURL: URL
    private let service: PeopleService

    init(baseURL: URL = ServerConfiguration.currentURL) {
        self.baseURL = baseURL
        service = PeopleService(baseURL: baseURL)
    }

    func load(person: SpecialPerson) async {
        async let ownPostsLoad: Void = loadOwnPosts(for: person)
        async let discussionsLoad: Void = loadDiscussions(for: person)
        _ = await (ownPostsLoad, discussionsLoad)
    }

    private func loadOwnPosts(for person: SpecialPerson) async {
        isLoadingOwnPosts = true
        ownPostsError = nil
        ownPostsLoadMoreError = nil
        defer { isLoadingOwnPosts = false }
        do {
            let posts = person.hasXSource ? try await service.posts(userID: person.userID, page: 1, limit: pageSize) : []
            ownPosts = posts
            ownPostsPage = 1
            canLoadMoreOwnPosts = posts.count == pageSize
        } catch is CancellationError {
            return
        } catch {
            ownPostsError = error.localizedDescription
        }
    }

    func loadMoreOwnPostsIfNeeded(current post: Post, person: SpecialPerson) async {
        guard person.hasXSource,
              post.id == ownPosts.last?.id,
              canLoadMoreOwnPosts,
              !isLoadingOwnPosts,
              !isLoadingMoreOwnPosts else { return }
        isLoadingMoreOwnPosts = true
        ownPostsLoadMoreError = nil
        defer { isLoadingMoreOwnPosts = false }
        do {
            let nextPage = ownPostsPage + 1
            let posts = try await service.posts(userID: person.userID, page: nextPage, limit: pageSize)
            guard !Task.isCancelled else { return }
            let existingIDs = Set(ownPosts.map(\.id))
            ownPosts += posts.filter { !existingIDs.contains($0.id) }
            ownPostsPage = nextPage
            canLoadMoreOwnPosts = posts.count == pageSize
        } catch is CancellationError {
            return
        } catch {
            ownPostsLoadMoreError = error.localizedDescription
        }
    }

    func postForDisplay(_ post: Post) -> Post {
        guard let translation = xTranslations[post.id] else { return post }
        return post.replacingTranslation(with: translation)
    }

    func translateXPostIfNeeded(_ post: Post) async {
        guard post.needsXTranslation,
              let tweetID = post.xTweetID,
              xTranslations[post.id] == nil,
              !loadingXTranslationIDs.contains(post.id) else { return }
        loadingXTranslationIDs.insert(post.id)
        defer { loadingXTranslationIDs.remove(post.id) }
        do {
            let result = try await APIClient(baseURL: baseURL).fetchXTranslation(tweetID: tweetID)
            guard !Task.isCancelled else { return }
            let value = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value != post.originalDisplayContent else { return }
            xTranslations[post.id] = value
        } catch is CancellationError {
            return
        } catch {
            // Translation is best-effort. Keep the original post visible on failure.
        }
    }

    private func loadDiscussions(for person: SpecialPerson) async {
        isLoadingDiscussions = true
        discussionsError = nil
        defer { isLoadingDiscussions = false }
        do {
            discussions = try await service.relatedDiscussions(for: person)
        } catch is CancellationError {
            return
        } catch {
            discussionsError = error.localizedDescription
        }
    }
}
