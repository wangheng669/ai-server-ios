import Foundation
import Observation

@MainActor
@Observable
final class PersonDetailStore {
    private(set) var ownPosts: [Post] = []
    private(set) var discussions: [Post] = []
    private(set) var isLoadingOwnPosts = false
    private(set) var isLoadingDiscussions = false
    private(set) var ownPostsError: String?
    private(set) var discussionsError: String?
    private let service: PeopleService

    init(baseURL: URL = ServerConfiguration.currentURL) {
        service = PeopleService(baseURL: baseURL)
    }

    func load(person: SpecialPerson) async {
        async let ownPostsLoad: Void = loadOwnPosts(for: person)
        async let discussionsLoad: Void = loadDiscussions(for: person)
        await (ownPostsLoad, discussionsLoad)
    }

    private func loadOwnPosts(for person: SpecialPerson) async {
        isLoadingOwnPosts = true
        ownPostsError = nil
        defer { isLoadingOwnPosts = false }
        do {
            ownPosts = person.hasXSource ? try await service.posts(userID: person.userID) : []
        } catch is CancellationError {
            return
        } catch {
            ownPostsError = error.localizedDescription
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
