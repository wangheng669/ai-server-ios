import Foundation

enum ServerConfiguration {
    static let defaultURL = URL(string: "https://api.wanghengai.xin")!

    static var currentURL: URL {
        let stored = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        guard let normalized = ServerAddressValidator.normalizedURL(stored) else {
            UserDefaults.standard.set(defaultURL.absoluteString, forKey: "serverURL")
            return defaultURL
        }
        return normalized
    }
}
