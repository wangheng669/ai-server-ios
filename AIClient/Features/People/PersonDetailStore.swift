import Foundation
import Observation

@MainActor
@Observable
final class PersonDetailStore {
    private(set) var ownPosts: [Post] = []
    private(set) var discussions: [Post] = []
    private(set) var relatedVideos: [PersonVideo] = []
    private(set) var articles: [PersonArticle] = []
    private(set) var isLoadingOwnPosts = false
    private(set) var isLoadingMoreOwnPosts = false
    private(set) var isLoadingDiscussions = false
    private(set) var isLoadingRelatedVideos = false
    private(set) var isLoadingArticles = false
    private(set) var ownPostsError: String?
    private(set) var ownPostsLoadMoreError: String?
    private(set) var discussionsError: String?
    private(set) var relatedVideosError: String?
    private(set) var articlesError: String?
    private(set) var articleSearchResults: [PersonArticle]?
    private(set) var isSearchingArticles = false
    private(set) var articleSearchError: String?
    private(set) var canLoadMoreOwnPosts = true
    private(set) var xTranslations: [Int: String] = [:]
    private(set) var xLiveDetails: [Int: XTweetDetailItem] = [:]
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
        async let articlesLoad: Void = loadArticles(for: person)
        _ = await (ownPostsLoad, discussionsLoad, videosLoad, articlesLoad)
    }

    private func loadArticles(for person: SpecialPerson) async {
        isLoadingArticles = true
        articlesError = nil
        articleSearchResults = nil
        articleSearchError = nil
        defer { isLoadingArticles = false }
        do {
            articles = try await service.articles(personID: person.id)
        } catch is CancellationError {
            return
        } catch {
            articles = []
            articlesError = error.localizedDescription
        }
    }

    func searchArticles(personID: String, query: String) async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            articleSearchResults = nil
            articleSearchError = nil
            isSearchingArticles = false
            return
        }

        isSearchingArticles = true
        articleSearchError = nil
        defer { isSearchingArticles = false }
        do {
            let results = try await service.articles(personID: personID, query: normalized)
            guard !Task.isCancelled else { return }
            articleSearchResults = results
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            articleSearchResults = []
            articleSearchError = error.localizedDescription
        }
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
            let newPosts = posts.filter { !existingIDs.contains($0.id) }
            ownPosts += newPosts
            ownPostsPage = nextPage
            canLoadMoreOwnPosts = posts.count == pageSize
        } catch is CancellationError {
            return
        } catch {
            ownPostsLoadMoreError = error.localizedDescription
        }
    }

    func postForDisplay(_ post: Post) -> Post {
        var displayed = post
        if let detail = xLiveDetails[post.id] {
            displayed = displayed.replacingXLiveDetail(with: detail)
        }
        if let translation = xTranslations[post.id] {
            displayed = displayed.replacingTranslation(with: translation)
        }
        return displayed
    }

    func translateXPostIfNeeded(_ post: Post) async {
        if post.isXRetweetWrapper {
            await loadXRetweetPresentationIfNeeded(post)
            return
        }
        guard post.needsXTranslation,
              let tweetID = post.xTweetID,
              xTranslations[post.id] == nil,
              !loadingXTranslationIDs.contains(post.id) else { return }
        if let cached = Self.cachedXTranslation(tweetID: tweetID) {
            xTranslations[post.id] = cached
            return
        }
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
            Self.cacheXTranslation(value, tweetID: tweetID)
            xTranslations[post.id] = value
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    private func loadXRetweetPresentationIfNeeded(_ post: Post) async {
        guard let tweetID = post.xTweetID,
              xLiveDetails[post.id] == nil,
              !loadingXTranslationIDs.contains(post.id) else { return }
        loadingXTranslationIDs.insert(post.id)
        defer { loadingXTranslationIDs.remove(post.id) }
        do {
            let client = APIClient(baseURL: baseURL)
            let detail = try await client.fetchXTweetDetail(tweetID: tweetID)
            guard !Task.isCancelled else { return }
            xLiveDetails[post.id] = detail

            guard detail.lang?.lowercased().hasPrefix("zh") != true,
                  xTranslations[post.id] == nil else { return }
            if let cached = Self.cachedXTranslation(tweetID: detail.id) {
                xTranslations[post.id] = cached
                return
            }
            let result = try await client.fetchXTranslation(tweetID: detail.id)
            guard !Task.isCancelled else { return }
            let value = Self.presentedTranslation(
                result.text.trimmingCharacters(in: .whitespacesAndNewlines),
                original: detail.fullText
            )
            guard !value.isEmpty, value != detail.fullText else { return }
            Self.cacheXTranslation(value, tweetID: detail.id)
            xTranslations[post.id] = value
        } catch is CancellationError {
            return
        } catch {
            return
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

    nonisolated static func cachedXTranslation(tweetID: String) -> String? {
        UserDefaults.standard.string(forKey: xTranslationCacheKey(tweetID: tweetID))
    }

    nonisolated static func cacheXTranslation(_ translation: String, tweetID: String) {
        UserDefaults.standard.set(translation, forKey: xTranslationCacheKey(tweetID: tweetID))
    }

    nonisolated private static func xTranslationCacheKey(tweetID: String) -> String {
        "people.x-translation.v1.\(tweetID)"
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
