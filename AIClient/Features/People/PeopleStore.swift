import Foundation
import Observation

@MainActor
@Observable
final class PeopleStore {
    private(set) var people: [SpecialPerson] = []
    private(set) var xSearchQuery = ""
    private(set) var xSearchResults: [XPersonSearchResult] = []
    private(set) var isSearchingX = false
    private(set) var xSearchErrorMessage: String?
    private(set) var importingXUserIDs: Set<String> = []
    private(set) var wikipediaSearchQuery = ""
    private(set) var wikipediaSearchResults: [WikipediaPersonSearchResult] = []
    private(set) var isSearchingWikipedia = false
    private(set) var wikipediaSearchErrorMessage: String?
    private(set) var importingWikipediaIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    let baseURL: URL
    private let service: PeopleService
    private var loadedAt: Date?
    @ObservationIgnored private var directoryRequest: Task<Void, Never>?
    @ObservationIgnored private var xSearchRequestID: UUID?
    @ObservationIgnored private var wikipediaSearchRequestID: UUID?

    init(baseURL: URL = ServerConfiguration.currentURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        service = PeopleService(baseURL: baseURL, session: session)
    }

    var hasLoadedDirectory: Bool { loadedAt != nil }

    func load(force: Bool = false) async {
        guard !Task.isCancelled else { return }
        if let directoryRequest {
            await directoryRequest.value
            return
        }
        let isStale = loadedAt.map { Date().timeIntervalSince($0) >= 300 } ?? true
        guard force || isStale else { return }
        isLoading = true
        errorMessage = nil
        let request = Task {
            defer {
                directoryRequest = nil
                isLoading = false
            }
            do {
                let payload = try await service.specialPeople()
                people = payload.users
                loadedAt = Date()
            } catch {
                errorMessage = NetworkErrorPresentation.message(for: error)
            }
        }
        directoryRequest = request
        await request.value
    }

    private func reloadAfterImport() async {
        // A directory read started before the import may still hold the old list.
        await directoryRequest?.value
        await load(force: true)
    }

    func searchXPeople(query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = UUID()
        xSearchRequestID = requestID
        xSearchQuery = query
        guard query.count >= 2 else {
            xSearchResults = []
            xSearchErrorMessage = nil
            isSearchingX = false
            return
        }
        xSearchResults = []
        isSearchingX = true
        xSearchErrorMessage = nil
        defer {
            if xSearchRequestID == requestID {
                isSearchingX = false
            }
        }
        do {
            let results = try await service.searchXPeople(query: query)
            guard !Task.isCancelled, xSearchRequestID == requestID else { return }
            xSearchResults = results
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, xSearchRequestID == requestID else { return }
            xSearchErrorMessage = error.localizedDescription
        }
    }

    func existingPerson(for result: XPersonSearchResult) -> SpecialPerson? {
        people.first { person in
            person.id == result.personID ||
                person.xUserID == result.id ||
                person.xScreenName?.caseInsensitiveCompare(result.screenName) == .orderedSame
        }
    }

    func existingPerson(for result: WikipediaPersonSearchResult) -> SpecialPerson? {
        guard let personID = result.personID else { return nil }
        return people.first { $0.id == personID }
    }

    func importXPerson(_ result: XPersonSearchResult) async -> SpecialPerson? {
        if let existing = existingPerson(for: result) { return existing }
        guard importingXUserIDs.insert(result.id).inserted else { return nil }
        xSearchErrorMessage = nil
        defer { importingXUserIDs.remove(result.id) }
        do {
            let payload = try await service.importXPerson(screenName: result.screenName)
            await reloadAfterImport()
            xSearchResults = xSearchResults.map { item in
                guard item.id == result.id else { return item }
                return XPersonSearchResult(
                    id: item.id,
                    name: item.name,
                    screenName: item.screenName,
                    description: item.description,
                    avatarURLValue: item.avatarURLValue,
                    verified: item.verified,
                    followersCount: item.followersCount,
                    followingCount: item.followingCount,
                    alreadyInDirectory: true,
                    personID: payload.person.id
                )
            }
            return people.first(where: { $0.id == payload.person.id }) ?? payload.person
        } catch is CancellationError {
            return nil
        } catch {
            xSearchErrorMessage = error.localizedDescription
            return nil
        }
    }

    func searchWikipediaPeople(query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = UUID()
        wikipediaSearchRequestID = requestID
        wikipediaSearchQuery = query
        guard query.count >= 2 else {
            wikipediaSearchResults = []
            wikipediaSearchErrorMessage = nil
            isSearchingWikipedia = false
            return
        }
        wikipediaSearchResults = []
        isSearchingWikipedia = true
        wikipediaSearchErrorMessage = nil
        defer {
            if wikipediaSearchRequestID == requestID {
                isSearchingWikipedia = false
            }
        }
        do {
            let results = try await service.searchWikipediaPeople(query: query)
            guard !Task.isCancelled, wikipediaSearchRequestID == requestID else { return }
            wikipediaSearchResults = results
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, wikipediaSearchRequestID == requestID else { return }
            wikipediaSearchErrorMessage = error.localizedDescription
        }
    }

    func importWikipediaPerson(_ result: WikipediaPersonSearchResult) async -> SpecialPerson? {
        if let existing = existingPerson(for: result) { return existing }
        guard importingWikipediaIDs.insert(result.id).inserted else { return nil }
        wikipediaSearchErrorMessage = nil
        defer { importingWikipediaIDs.remove(result.id) }
        do {
            let payload = try await service.importWikipediaPerson(result)
            await reloadAfterImport()
            wikipediaSearchResults = wikipediaSearchResults.map { item in
                guard item.id == result.id else { return item }
                return WikipediaPersonSearchResult(
                    id: item.id,
                    pageID: item.pageID,
                    language: item.language,
                    title: item.title,
                    description: item.description,
                    extract: item.extract,
                    avatarURLValue: item.avatarURLValue,
                    articleURLValue: item.articleURLValue,
                    alreadyInDirectory: true,
                    personID: payload.person.id
                )
            }
            return people.first(where: { $0.id == payload.person.id }) ?? payload.person
        } catch is CancellationError {
            return nil
        } catch {
            wikipediaSearchErrorMessage = error.localizedDescription
            return nil
        }
    }
}
