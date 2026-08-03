import Foundation
import Observation

@MainActor
@Observable
final class PeopleStore {
    private(set) var people: [SpecialPerson] = []
    private(set) var topics: [PeopleTopic] = PeopleTopic.allCases
    private(set) var latestPosts: [String: Post] = [:]
    private(set) var xSearchResults: [XPersonSearchResult] = []
    private(set) var isSearchingX = false
    private(set) var xSearchErrorMessage: String?
    private(set) var importingXUserIDs: Set<String> = []
    private(set) var wikipediaSearchResults: [WikipediaPersonSearchResult] = []
    private(set) var isSearchingWikipedia = false
    private(set) var wikipediaSearchErrorMessage: String?
    private(set) var importingWikipediaIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    let baseURL: URL
    private let service: PeopleService
    private var loadingLatestPostIDs: Set<String> = []
    private var loadedLatestPostIDs: Set<String> = []
    private var activeXSearchQuery = ""
    private var activeWikipediaSearchQuery = ""

    init(baseURL: URL = ServerConfiguration.currentURL) {
        self.baseURL = baseURL
        service = PeopleService(baseURL: baseURL)
    }

    func load(force: Bool = false) async {
        guard !isLoading, force || people.isEmpty else { return }
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
            errorMessage = NetworkErrorPresentation.message(for: error)
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

    func searchXPeople(query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            activeXSearchQuery = ""
            xSearchResults = []
            xSearchErrorMessage = nil
            isSearchingX = false
            return
        }
        activeXSearchQuery = query
        xSearchResults = []
        isSearchingX = true
        xSearchErrorMessage = nil
        defer {
            if activeXSearchQuery == query {
                isSearchingX = false
            }
        }
        do {
            let results = try await service.searchXPeople(query: query)
            guard !Task.isCancelled, activeXSearchQuery == query else { return }
            xSearchResults = results
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, activeXSearchQuery == query else { return }
            xSearchResults = []
            xSearchErrorMessage = error.localizedDescription
        }
    }

    func importXPerson(_ result: XPersonSearchResult) async -> SpecialPerson? {
        if let existing = people.first(where: { person in
            (result.personID.map { $0 == person.id } ?? false) ||
                person.xUserID == result.id ||
                person.xScreenName?.caseInsensitiveCompare(result.screenName) == .orderedSame
        }) {
            return existing
        }
        guard importingXUserIDs.insert(result.id).inserted else { return nil }
        xSearchErrorMessage = nil
        defer { importingXUserIDs.remove(result.id) }
        do {
            let payload = try await service.importXPerson(screenName: result.screenName)
            await load(force: true)
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
        guard query.count >= 2 else {
            activeWikipediaSearchQuery = ""
            wikipediaSearchResults = []
            wikipediaSearchErrorMessage = nil
            isSearchingWikipedia = false
            return
        }
        activeWikipediaSearchQuery = query
        wikipediaSearchResults = []
        isSearchingWikipedia = true
        wikipediaSearchErrorMessage = nil
        defer {
            if activeWikipediaSearchQuery == query {
                isSearchingWikipedia = false
            }
        }
        do {
            let results = try await service.searchWikipediaPeople(query: query)
            guard !Task.isCancelled, activeWikipediaSearchQuery == query else { return }
            wikipediaSearchResults = results
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, activeWikipediaSearchQuery == query else { return }
            wikipediaSearchResults = []
            wikipediaSearchErrorMessage = error.localizedDescription
        }
    }

    func importWikipediaPerson(_ result: WikipediaPersonSearchResult) async -> SpecialPerson? {
        if let personID = result.personID,
           let existing = people.first(where: { $0.id == personID }) {
            return existing
        }
        guard importingWikipediaIDs.insert(result.id).inserted else { return nil }
        wikipediaSearchErrorMessage = nil
        defer { importingWikipediaIDs.remove(result.id) }
        do {
            let payload = try await service.importWikipediaPerson(result)
            await load(force: true)
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
