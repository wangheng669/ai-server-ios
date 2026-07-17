import Foundation
import Observation

@MainActor
@Observable
final class PeopleStore {
    private(set) var people: [SpecialPerson] = []
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
            let loadedPeople = try await service.specialPeople()
            people = loadedPeople
            let xLeaders = SpecialPerson.artificialIntelligenceLeaders.filter(\.hasXSource)
            latestPosts = await service.latestPosts(for: loadedPeople + xLeaders)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func latestPost(for person: SpecialPerson) -> Post? {
        latestPosts[person.id]
    }
}
