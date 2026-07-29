import Foundation
import Observation

@MainActor
@Observable
final class PeopleStore {
    private(set) var people: [SpecialPerson] = []
    private(set) var topics: [PeopleTopic] = PeopleTopic.allCases
    private(set) var latestPosts: [String: Post] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    let baseURL: URL
    private let service: PeopleService
    private var loadingLatestPostIDs: Set<String> = []
    private var loadedLatestPostIDs: Set<String> = []

    init(baseURL: URL = ServerConfiguration.currentURL) {
        self.baseURL = baseURL
        service = PeopleService(baseURL: baseURL)
    }

    func load(force: Bool = false) async {
        guard force || people.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let payload = try await service.specialPeople()
            people = payload.users
            let serverTopics = (payload.categories ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .compactMap(\.topic)
            if !serverTopics.isEmpty {
                topics = serverTopics
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func latestPost(for person: SpecialPerson) -> Post? {
        latestPosts[person.id]
    }

    func loadLatestPost(for person: SpecialPerson) async {
        guard person.hasOwnPostSource,
              !loadedLatestPostIDs.contains(person.id),
              loadingLatestPostIDs.insert(person.id).inserted else { return }
        defer { loadingLatestPostIDs.remove(person.id) }
        do {
            if let post = try await service.latestPost(userID: person.userID) {
                latestPosts[person.id] = post
            }
            loadedLatestPostIDs.insert(person.id)
        } catch is CancellationError {
            return
        } catch {
            // Latest activity is optional context; keep the directory usable.
        }
    }
}
