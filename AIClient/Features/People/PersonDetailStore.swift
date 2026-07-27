import Foundation
import Observation

@MainActor
@Observable
final class PersonDetailStore {
    private(set) var ownPosts: [Post] = []
    private(set) var discussions: [Post] = []
    private(set) var relatedVideos: [PersonVideo] = []
    private(set) var isLoadingOwnPosts = false
    private(set) var isLoadingMoreOwnPosts = false
    private(set) var isLoadingDiscussions = false
    private(set) var isLoadingRelatedVideos = false
    private(set) var ownPostsError: String?
    private(set) var ownPostsLoadMoreError: String?
    private(set) var discussionsError: String?
    private(set) var relatedVideosError: String?
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
        async let videosLoad: Void = loadRelatedVideos(for: person)
        _ = await (ownPostsLoad, discussionsLoad, videosLoad)
    }

    private func loadOwnPosts(for person: SpecialPerson) async {
        isLoadingOwnPosts = true
        ownPostsError = nil
        ownPostsLoadMoreError = nil
        defer { isLoadingOwnPosts = false }
        do {
            let posts = person.hasOwnPostSource ? try await service.posts(userID: person.userID, page: 1, limit: pageSize) : []
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
        guard person.hasOwnPostSource,
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
            let value = Self.presentedTranslation(
                result.text.trimmingCharacters(in: .whitespacesAndNewlines),
                original: post.originalDisplayContent
            )
            guard !value.isEmpty, value != post.originalDisplayContent else { return }
            xTranslations[post.id] = value
        } catch is CancellationError {
            return
        } catch {
            // Translation is best-effort. Keep the original post visible on failure.
        }
    }

    nonisolated static func presentedTranslation(_ translation: String, original: String) -> String {
        var result = translation
        let protectedTerms: [(original: String, mistranslations: [String])] = [
            ("Gemini", ["双子座", "双子星座"]),
            ("Grok", ["格罗克"]),
            ("Claude", ["克劳德"]),
            ("Llama", ["骆驼"])
        ]
        for term in protectedTerms where original.localizedCaseInsensitiveContains(term.original) {
            for mistranslation in term.mistranslations {
                result = result.replacingOccurrences(of: mistranslation, with: term.original)
            }
        }
        return result
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

    private func loadRelatedVideos(for person: SpecialPerson) async {
        isLoadingRelatedVideos = true
        relatedVideosError = nil
        defer { isLoadingRelatedVideos = false }
        do {
            relatedVideos = try await service.relatedVideos(personID: person.id)
        } catch is CancellationError {
            return
        } catch {
            relatedVideosError = error.localizedDescription
        }
    }
}
