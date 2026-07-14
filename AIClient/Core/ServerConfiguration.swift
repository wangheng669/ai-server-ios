import Foundation

enum ServerConfiguration {
    static let defaultURL = URL(string: "http://47.100.175.141:3001")!

    static var currentURL: URL {
        let stored = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        return ServerAddressValidator.normalizedURL(stored) ?? defaultURL
    }

    static var xBookmarkAPIKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "XBookmarkAPIKey") as? String else { return nil }
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty || key == "$(X_BOOKMARK_API_KEY)" ? nil : key
    }
}
