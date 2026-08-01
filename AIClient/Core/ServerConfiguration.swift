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

enum NetworkErrorPresentation {
    static func message(for error: Error) -> String {
        guard let urlError = urlError(from: error) else {
            return error.localizedDescription
        }

        switch urlError.code {
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return "安全连接失败，请检查 VPN 或代理设置后重试"
        case .notConnectedToInternet, .networkConnectionLost:
            return "网络连接已断开，请检查网络后重试"
        case .timedOut:
            return "连接超时，请稍后重试"
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "暂时无法连接服务器，请稍后重试"
        default:
            return "网络请求失败，请稍后重试"
        }
    }

    private static func urlError(from error: Error) -> URLError? {
        if let urlError = error as? URLError { return urlError }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return nil }
        return URLError(URLError.Code(rawValue: nsError.code))
    }
}
