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
            latestPosts = await service.latestPosts(for: payload.users.filter(\.hasOwnPostSource))
            await translateLatestPostsIfNeeded()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func latestPost(for person: SpecialPerson) -> Post? {
        latestPosts[person.id]
    }

    private func translateLatestPostsIfNeeded() async {
        for (personID, post) in latestPosts {
            guard post.needsXTranslation, let tweetID = post.xTweetID else { continue }
            do {
                let result = try await APIClient(baseURL: baseURL).fetchXTranslation(tweetID: tweetID)
                guard !Task.isCancelled else { return }
                let translation = PersonDetailStore.presentedTranslation(
                    result.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    original: post.originalDisplayContent
                )
                guard !translation.isEmpty, translation != post.originalDisplayContent else { continue }
                latestPosts[personID] = post.replacingTranslation(with: translation)
            } catch is CancellationError {
                return
            } catch {
                // Translation is best-effort. Keep the original latest update visible on failure.
            }
        }
    }
}

enum PeopleImagePreheater {
    @MainActor
    static func preheatTechnologyLeaders() async {
        guard let payload = try? await PeopleService().specialPeople() else { return }
        let requests = payload.users
            .filter { $0.topic == .technology }
            .prefix(6)
            .compactMap { $0.avatarURL(baseURL: ServerConfiguration.currentURL) }

        await withTaskGroup(of: Void.self) { group in
            for url in requests {
                group.addTask {
                    _ = await ImageLoader.load(url, targetSize: CGSize(width: 52, height: 52))
                }
            }
        }
    }
}
