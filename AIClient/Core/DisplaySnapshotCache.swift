import CryptoKit
import Foundation

actor DisplaySnapshotCache {
    static let editions = DisplaySnapshotCache(name: "today-editions", capacity: 4)
    static let charts = DisplaySnapshotCache(name: "market-charts", capacity: 24)

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

    private func fileURL(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: digest + ".json")
    }
}
