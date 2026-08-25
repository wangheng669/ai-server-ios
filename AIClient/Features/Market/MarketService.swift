import Foundation
import CryptoKit
import OSLog

private let marketServiceLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "AIServerClient",
    category: "MarketService"
)

struct MarketService {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 20
            configuration.requestCachePolicy = .useProtocolCachePolicy
            configuration.urlCache = .shared
            self.session = URLSession(configuration: configuration)
        }
    }

    func dashboard(refresh: Bool) async throws -> MarketDashboard {
        var components = URLComponents(url: baseURL.appending(path: "api/ios/v1/market/dashboard"), resolvingAgainstBaseURL: false)
        if refresh { components?.queryItems = [.init(name: "refresh", value: "true")] }
        guard let url = components?.url else { throw MarketServiceError.invalidURL }
        return try await request(url, as: MarketDashboardResponse.self, bypassCache: refresh).data
    }

    func bootstrap() async throws -> MarketBootstrap {
        let url = baseURL.appending(path: "api/ios/v1/market/bootstrap")
        var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        urlRequest.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        return try await request(urlRequest, as: MarketBootstrapResponse.self).data
    }

    func chart(symbol: String, range: MarketRange, refresh: Bool = false) async throws -> MarketChart {
        var components = URLComponents(url: baseURL.appending(path: "api/ios/v1/market/chart"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = [
            .init(name: "symbol", value: symbol),
            .init(name: "interval", value: range.apiInterval),
            .init(name: "range", value: range.apiRange),
            .init(name: "limit", value: String(range.apiLimit))
        ]
        if refresh { queryItems.append(.init(name: "refresh", value: "true")) }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw MarketServiceError.invalidURL }
        return try await request(url, as: MarketChartResponse.self, bypassCache: refresh).data
    }

    /// 收盘后日内 trend 兜底：拉取 5 日 5 分钟线，客户端截取最近一个交易日。
    func recentIntradayChart(symbol: String) async throws -> MarketChart {
        var components = URLComponents(url: baseURL.appending(path: "api/ios/v1/market/chart"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "symbol", value: symbol),
            .init(name: "interval", value: "5m"),
            .init(name: "range", value: "5d"),
            .init(name: "limit", value: "1000")
        ]
        guard let url = components?.url else { throw MarketServiceError.invalidURL }
        return try await request(url, as: MarketChartResponse.self).data
    }

    func indexConstituents(symbol: String, refresh: Bool = false) async throws -> MarketIndexConstituents {
        var components = URLComponents(url: baseURL.appending(path: "api/ios/v1/market/index-constituents"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = [
            .init(name: "symbol", value: symbol),
            .init(name: "contract", value: "8")
        ]
        if refresh { queryItems.append(.init(name: "refresh", value: "true")) }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw MarketServiceError.invalidURL }
        return try await request(url, as: MarketIndexConstituentsResponse.self, bypassCache: refresh).data
    }

    func companyLogo(symbol: String, name: String) async throws -> String? {
        var components = URLComponents(url: baseURL.appending(path: "api/ios/v1/market/company-logo"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "symbol", value: symbol),
            .init(name: "name", value: name)
        ]
        guard let url = components?.url else { throw MarketServiceError.invalidURL }
        let logo = try await request(url, as: MarketCompanyLogoResponse.self).data
        return logo.found && !logo.url.isEmpty ? logo.url : nil
    }

    func famousHoldings(managerKey: String? = nil) async throws -> FamousHoldings {
        var components = URLComponents(url: baseURL.appending(path: "api/ios/v1/market/famous-holdings"), resolvingAgainstBaseURL: false)
        if let managerKey { components?.queryItems = [.init(name: "manager", value: managerKey)] }
        guard let url = components?.url else { throw MarketServiceError.invalidURL }
        return try await request(url, as: FamousHoldingsResponse.self).data
    }

    func investorMood() async throws -> InvestorMoodBoard {
        let url = baseURL.appending(path: "api/ios/v1/market/dashboard/investor-mood")
        return try await request(url, as: InvestorMoodResponse.self).data
    }

    func prewarmInvestorMoodVideos(_ items: [InvestorMoodItem]) async {
        for item in items.prefix(6) {
            guard let url = item.prewarmURL else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            request.cachePolicy = .reloadIgnoringLocalCacheData
            _ = try? await session.data(for: request)
        }
    }

    func investorVideoInterpretationStatus(_ item: InvestorMoodItem) async throws -> InvestorVideoInterpretationResponse {
        var components = URLComponents(url: baseURL.appending(path: "api/ios/v1/video/interpretation"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "source", value: "douyin-investor-mood"),
            .init(name: "source_id", value: item.awemeId),
        ]
        guard let url = components?.url else { throw MarketServiceError.invalidURL }
        var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        urlRequest.timeoutInterval = 20
        urlRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        do {
            return try await request(urlRequest, as: InvestorVideoInterpretationResponse.self)
        } catch MarketServiceError.httpStatus(let status) {
            throw VideoInterpretationServiceError.unavailable(status)
        }
    }

    func aShareTemperature(days: Int = 90) async throws -> MarketAShareTemperature {
        var components = URLComponents(url: baseURL.appending(path: "api/ios/v1/market/ashare-temperature"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "days", value: String(days))]
        guard let url = components?.url else { throw MarketServiceError.invalidURL }
        return try await request(url, as: MarketAShareTemperatureResponse.self).data
    }

    func koreaLeverage(refresh: Bool = false) async throws -> MarketKoreaLeverage {
        let url = baseURL.appending(path: "api/ios/v1/market/korea-leverage")
        return try await request(url, as: MarketKoreaLeverageResponse.self, bypassCache: refresh).data
    }

    func hongKongValuationHistory() async throws -> MarketHKValuationHistory {
        let history = try await valuationHistory(market: "hong-kong")
        return MarketHKValuationHistory(date: history.date, pe: history.pe)
    }

    func unitedStatesValuationHistory() async throws -> MarketUSValuationHistory {
        let history = try await valuationHistory(market: "united-states")
        return MarketUSValuationHistory(pe: history.pe)
    }

    func sentimentSnapshot(market: String, refresh: Bool = false) async throws -> MarketSentimentSnapshot {
        var components = URLComponents(
            url: baseURL.appending(path: "api/ios/v1/market/sentiment-snapshot"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [URLQueryItem(name: "market", value: market)]
        if refresh { queryItems.append(.init(name: "refresh", value: "true")) }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw MarketServiceError.invalidURL }
        return try await request(
            url,
            as: MarketSentimentSnapshotResponse.self,
            bypassCache: refresh,
            useCachedResponseWhenAvailable: true
        ).data
    }

    func companyValuationHistory(symbol: String) async throws -> MarketCompanyValuationHistory {
        var components = URLComponents(
            url: baseURL.appending(path: "api/ios/v1/market/company-valuation-history"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [.init(name: "symbol", value: symbol)]
        guard let url = components?.url else { throw MarketServiceError.invalidURL }
        let history = try await request(
            url,
            as: MarketCompanyValuationHistoryResponse.self,
            bypassCache: true
        ).data
        guard history.dataContract == MarketCompanyValuationHistory.dataContractV2,
              history.frequency == MarketCompanyValuationHistory.dailyFrequency,
              history.method == MarketCompanyValuationHistory.dailyMethod else {
            throw MarketServiceError.invalidResponse
        }
        return history
    }

    private func valuationHistory(market: String) async throws -> MarketValuationHistory {
        var components = URLComponents(url: baseURL.appending(path: "api/ios/v1/market/valuation-history"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "market", value: market)]
        guard let url = components?.url else { throw MarketServiceError.invalidURL }
        return try await request(url, as: MarketValuationHistoryResponse.self).data
    }

    private func request<Response: Decodable>(
        _ url: URL,
        as type: Response.Type,
        bypassCache: Bool = false,
        useCachedResponseWhenAvailable: Bool = false
    ) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            var request = URLRequest(
                url: url,
                cachePolicy: marketRequestCachePolicy(
                    bypassCache: bypassCache,
                    useCachedResponseWhenAvailable: useCachedResponseWhenAvailable
                )
            )
            if bypassCache { request.setValue("no-cache", forHTTPHeaderField: "Cache-Control") }
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw MarketServiceError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else { throw MarketServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw MarketServiceError.httpStatus(http.statusCode) }
        return try decode(data, response: http, url: url, as: type)
    }

    private func request<Response: Decodable>(
        _ request: URLRequest,
        as type: Response.Type
    ) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw MarketServiceError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else { throw MarketServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw MarketServiceError.httpStatus(http.statusCode) }
        return try decode(data, response: http, url: request.url, as: type)
    }

    private func decode<Response: Decodable>(
        _ data: Data,
        response: HTTPURLResponse,
        url: URL?,
        as type: Response.Type
    ) throws -> Response {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let diagnostic = marketDecodingDiagnostic(error)
            let requestID = response.value(forHTTPHeaderField: "x-request-id") ?? "missing"
            let contentType = response.value(forHTTPHeaderField: "content-type") ?? "missing"
            let actualValue = marketDecodingActualValue(in: data, error: error)
            marketServiceLogger.error(
                "Decoding failed endpoint=\(url?.path ?? "unknown", privacy: .public) request_id=\(requestID, privacy: .public) response_type=\(String(reflecting: type), privacy: .public) bytes=\(data.count) content_type=\(contentType, privacy: .public) category=\(diagnostic.category, privacy: .public) path=\(diagnostic.path, privacy: .public) expected=\(diagnostic.expectedType ?? "unknown", privacy: .public) detail=\(diagnostic.detail, privacy: .public)"
            )
            let report = MarketDecodingFailureReport(
                eventID: UUID().uuidString.lowercased(),
                requestID: requestID == "missing" ? nil : requestID,
                endpoint: url?.path ?? "unknown",
                query: url?.query,
                responseType: String(reflecting: type),
                category: diagnostic.category,
                path: diagnostic.path,
                expectedType: diagnostic.expectedType,
                actualType: actualValue?.type,
                actualValue: actualValue?.preview,
                detail: diagnostic.detail,
                httpStatus: response.statusCode,
                contentType: contentType,
                responseBytes: data.count,
                responseSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                buildVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                occurredAt: ISO8601DateFormatter().string(from: Date())
            )
            Task {
                await sendMarketDecodingFailureReport(
                    report,
                    baseURL: baseURL,
                    session: session
                )
            }
            throw MarketServiceError.decoding(error)
        }
    }
}

struct MarketDecodingFailureReport: Encodable, Equatable, Sendable {
    let eventID: String
    let requestID: String?
    let endpoint: String
    let query: String?
    let responseType: String
    let category: String
    let path: String
    let expectedType: String?
    let actualType: String?
    let actualValue: String?
    let detail: String
    let httpStatus: Int
    let contentType: String
    let responseBytes: Int
    let responseSHA256: String
    let appVersion: String?
    let buildVersion: String?
    let occurredAt: String
}

struct MarketDecodingActualValue: Equatable {
    let type: String
    let preview: String?
}

func marketDecodingActualValue(in data: Data, error: Error) -> MarketDecodingActualValue? {
    guard let root = try? JSONSerialization.jsonObject(with: data),
          let codingPath = marketDecodingCodingPath(error) else { return nil }
    var current: Any = root
    for key in codingPath {
        if let index = key.intValue {
            guard let values = current as? [Any], values.indices.contains(index) else {
                return MarketDecodingActualValue(type: "missing", preview: nil)
            }
            current = values[index]
        } else {
            guard let values = current as? [String: Any], let value = values[key.stringValue] else {
                return MarketDecodingActualValue(type: "missing", preview: nil)
            }
            current = value
        }
    }
    switch current {
    case is NSNull:
        return MarketDecodingActualValue(type: "null", preview: nil)
    case let value as Bool:
        return MarketDecodingActualValue(type: "boolean", preview: String(value))
    case let value as NSNumber:
        return MarketDecodingActualValue(type: "number", preview: value.stringValue)
    case let value as String:
        return MarketDecodingActualValue(type: "string", preview: "string(length=\(value.count))")
    case let value as [Any]:
        return MarketDecodingActualValue(type: "array", preview: "count=\(value.count)")
    case let value as [String: Any]:
        let keys = value.keys.sorted().prefix(12).joined(separator: ",")
        return MarketDecodingActualValue(type: "object", preview: "keys=\(keys)")
    default:
        return MarketDecodingActualValue(type: String(describing: type(of: current)), preview: nil)
    }
}

private func marketDecodingCodingPath(_ error: Error) -> [CodingKey]? {
    guard let error = error as? DecodingError else { return nil }
    switch error {
    case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
        return context.codingPath
    case let .keyNotFound(key, context):
        return context.codingPath + [key]
    @unknown default:
        return nil
    }
}

private func sendMarketDecodingFailureReport(
    _ report: MarketDecodingFailureReport,
    baseURL: URL,
    session: URLSession
) async {
    let url = baseURL.appending(path: "api/ios/v1/ios/client-diagnostics")
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    guard let body = try? JSONEncoder().encode(report) else { return }
    request.httpBody = body
    do {
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
    } catch { }
}

struct MarketDecodingDiagnostic: Equatable {
    let category: String
    let path: String
    let expectedType: String?
    let detail: String
}

func marketDecodingDiagnostic(_ error: Error) -> MarketDecodingDiagnostic {
    guard let error = error as? DecodingError else {
        return MarketDecodingDiagnostic(
            category: String(describing: type(of: error)),
            path: "$",
            expectedType: nil,
            detail: error.localizedDescription
        )
    }

    switch error {
    case let .typeMismatch(type, context):
        return MarketDecodingDiagnostic(
            category: "typeMismatch",
            path: marketDecodingPath(context.codingPath),
            expectedType: String(reflecting: type),
            detail: context.debugDescription
        )
    case let .valueNotFound(type, context):
        return MarketDecodingDiagnostic(
            category: "valueNotFound",
            path: marketDecodingPath(context.codingPath),
            expectedType: String(reflecting: type),
            detail: context.debugDescription
        )
    case let .keyNotFound(key, context):
        return MarketDecodingDiagnostic(
            category: "keyNotFound",
            path: marketDecodingPath(context.codingPath + [key]),
            expectedType: nil,
            detail: context.debugDescription
        )
    case let .dataCorrupted(context):
        return MarketDecodingDiagnostic(
            category: "dataCorrupted",
            path: marketDecodingPath(context.codingPath),
            expectedType: nil,
            detail: context.debugDescription
        )
    @unknown default:
        return MarketDecodingDiagnostic(
            category: "unknown",
            path: "$",
            expectedType: nil,
            detail: error.localizedDescription
        )
    }
}

private func marketDecodingPath(_ codingPath: [CodingKey]) -> String {
    codingPath.reduce(into: "$") { path, key in
        if let index = key.intValue {
            path += "[\(index)]"
        } else {
            path += ".\(key.stringValue)"
        }
    }
}

func marketRequestCachePolicy(
    bypassCache: Bool,
    useCachedResponseWhenAvailable: Bool
) -> URLRequest.CachePolicy {
    if bypassCache { return .reloadIgnoringLocalCacheData }
    if useCachedResponseWhenAvailable { return .returnCacheDataElseLoad }
    return .useProtocolCachePolicy
}

enum VideoInterpretationServiceError: LocalizedError {
    case unavailable(Int)

    var errorDescription: String? {
        switch self {
        case .unavailable(let status): "视频解读服务暂不可用（\(status)）"
        }
    }
}

func marketParseSP500PEHistory(_ html: String) -> [Double] {
    guard let expression = try? NSRegularExpression(
        pattern: #"<tr class=\"(?:odd|even)\">\s*<td>.*?</td>\s*<td>.*?([0-9]+(?:\.[0-9]+)?)\s*</td>\s*</tr>"#,
        options: [.dotMatchesLineSeparators]
    ) else { return [] }
    let range = NSRange(html.startIndex..<html.endIndex, in: html)
    return expression.matches(in: html, range: range).compactMap { match in
        guard let capture = Range(match.range(at: 1), in: html) else { return nil }
        return Double(html[capture])
    }
}

enum MarketServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "行情地址无效"
        case .invalidResponse: "行情服务响应无效"
        case .httpStatus(let status): "行情服务暂不可用（\(status)）"
        case .decoding: "行情数据格式异常"
        case .transport: "无法连接行情服务，请检查网络后重试"
        }
    }
}

@MainActor
final class MarketRealtimeClient {
    enum Status: Equatable {
        case stopped
        case connecting
        case connected
        case reconnecting
    }

    private let baseURL: URL
    private var socket: URLSessionWebSocketTask?
    private var task: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var active = false
    var onQuote: ((MarketQuoteUpdate) -> Void)?
    var onStatus: ((Status) -> Void)?

    init(baseURL: URL) { self.baseURL = baseURL }

    func start() {
        guard !active else { return }
        active = true
        onStatus?(.connecting)
        connect()
    }

    func stop() {
        active = false
        task?.cancel()
        task = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        onStatus?(.stopped)
    }

    func reconnect() {
        guard active else { return }
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
    }

    private func connect() {
        guard active, task == nil, let url = webSocketURL else { return }
        task = Task { [weak self] in
            guard let self else { return }
            let socket = URLSession.shared.webSocketTask(with: url)
            self.socket = socket
            socket.resume()
            self.startHeartbeat(for: socket)
            do {
                while active, !Task.isCancelled {
                    let message = try await socket.receive()
                    let data: Data?
                    switch message {
                    case .data(let value): data = value
                    case .string(let value): data = value.data(using: .utf8)
                    @unknown default: data = nil
                    }
                    guard let data,
                          let header = try? JSONDecoder().decode(MarketSocketHeader.self, from: data),
                          header.type == "market",
                          let quote = try? JSONDecoder().decode(MarketQuoteUpdate.self, from: data) else { continue }
                    self.onStatus?(.connected)
                    onQuote?(quote)
                }
            } catch { }
            socket.cancel(with: .goingAway, reason: nil)
            self.socket = nil
            self.task = nil
            self.heartbeatTask?.cancel()
            self.heartbeatTask = nil
            guard active, !Task.isCancelled else { return }
            self.onStatus?(.reconnecting)
            try? await Task.sleep(for: .seconds(2))
            connect()
        }
    }

    private func startHeartbeat(for socket: URLSessionWebSocketTask) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self, weak socket] in
            while let self, let socket, self.active, !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) }
                catch { return }
                guard self.socket === socket else { return }
                socket.sendPing { [weak self, weak socket] error in
                    Task { @MainActor in
                        guard let self, let socket, self.active, self.socket === socket else { return }
                        if error == nil {
                            self.onStatus?(.connected)
                        } else {
                            self.onStatus?(.reconnecting)
                            socket.cancel(with: .goingAway, reason: nil)
                        }
                    }
                }
            }
        }
    }

    private var webSocketURL: URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/post"
        components.query = nil
        return components.url
    }
}

private struct MarketSocketHeader: Decodable { let type: String }
