import Foundation

enum ServerConfiguration {
    static let defaultURL = URL(string: "http://47.100.175.141:3001")!

    static var currentURL: URL {
        let stored = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        return ServerAddressValidator.normalizedURL(stored) ?? defaultURL
    }
}
