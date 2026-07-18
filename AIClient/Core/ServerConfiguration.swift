import Foundation

enum ServerConfiguration {
    static let defaultURL = URL(string: "https://api.wanghengai.xin")!
    private static let legacyURLs: Set<URL> = [
        URL(string: "http://47.100.175.141:3001")!,
        URL(string: "https://buf-confident-beads-bronze.trycloudflare.com")!
    ]

    static var currentURL: URL {
        let stored = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        guard let normalized = ServerAddressValidator.normalizedURL(stored) else { return defaultURL }
        if legacyURLs.contains(normalized) {
            UserDefaults.standard.set(defaultURL.absoluteString, forKey: "serverURL")
            return defaultURL
        }
        return normalized
    }
}
