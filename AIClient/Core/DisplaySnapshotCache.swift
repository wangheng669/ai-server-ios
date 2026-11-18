import CryptoKit
import Foundation

actor DisplaySnapshotCache {
    static let pages = DisplaySnapshotCache(name: "page-snapshots", capacity: 96)
    static let billing = DisplaySnapshotCache(name: "today-billing", capacity: 4)
    static let editions = DisplaySnapshotCache(name: "today-editions", capacity: 4)
    static let charts = DisplaySnapshotCache(name: "market-charts", capacity: 24)
    static let knowledge = DisplaySnapshotCache(name: "knowledge-overview", capacity: 12)
    static let companies = DisplaySnapshotCache(name: "company-research", capacity: 4)

    struct Entry<Value: Codable & Sendable>: Codable, Sendable {
        let value: Value
        let savedAt: Date
    }

    private let directory: URL
    private let capacity: Int
    private let maximumEntrySize = 2 * 1_024 * 1_024

    private init(name: String, capacity: Int) {
        directory = URL.cachesDirectory.appending(path: name, directoryHint: .isDirectory)
        self.capacity = capacity
    }

    func load<Value: Codable & Sendable>(
        _ type: Value.Type, key: String, maximumAge: TimeInterval
    ) -> Entry<Value>? {
        read(type, key: key, maximumAge: maximumAge)
    }

    // Billing reads one small, atomically written snapshot before the first frame.
    nonisolated func read<Value: Codable & Sendable>(
        _ type: Value.Type, key: String, maximumAge: TimeInterval
    ) -> Entry<Value>? {
        let url = fileURL(key)
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry<Value>.self, from: data),
              (0...maximumAge).contains(Date().timeIntervalSince(entry.savedAt)) else { return nil }
        return entry
    }

    func save<Value: Codable & Sendable>(
        _ value: Value, key: String, at date: Date, minimumInterval: TimeInterval = 0
    ) {
        let fileManager = FileManager.default
        let destination = fileURL(key)
        if minimumInterval > 0,
           let modifiedAt = try? destination.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           (0..<minimumInterval).contains(date.timeIntervalSince(modifiedAt)) {
            return
        }
        do {
            let data = try JSONEncoder().encode(Entry(value: value, savedAt: date))
            guard data.count <= maximumEntrySize else {
                remove(key: key)
                return
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            let files = try fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
            )
            let ordered = files.compactMap { url -> (URL, Date)? in
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                else { return nil }
                return (url, date)
            }.sorted { $0.1 > $1.1 }
            for (url, _) in ordered.dropFirst(capacity) {
                try? fileManager.removeItem(at: url)
            }
        } catch {
            // Display snapshots are disposable. Network data is authoritative.
        }
    }

    func remove(key: String) {
        try? FileManager.default.removeItem(at: fileURL(key))
    }

    nonisolated private func fileURL(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: digest + ".json")
    }
}

/// Start the authoritative request while restoring the last validated response for this URL.
func loadDisplayPage<Value>(
    request: URLRequest, session: URLSession,
    onCached: @escaping @MainActor (Value) -> Void,
    decode: (Data) throws -> Value
) async throws -> Value {
    guard let key = request.url?.absoluteString else { throw URLError(.badURL) }
    async let response = session.data(for: request)
    if let saved = await DisplaySnapshotCache.pages.load(Data.self, key: key, maximumAge: 7 * 86400),
       let page = try? decode(saved.value) {
        try Task.checkCancellation()
        await onCached(page)
    }
    let (data, metadata) = try await response
    try Task.checkCancellation()
    guard let http = metadata as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw URLError(.badServerResponse)
    }
    let page = try decode(data)
    await DisplaySnapshotCache.pages.save(data, key: key, at: Date())
    return page
}
