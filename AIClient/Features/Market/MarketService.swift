import Foundation

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
        var components = URLComponents(url: baseURL.appending(path: "api/v1/market/dashboard"), resolvingAgainstBaseURL: false)
        if refresh { components?.queryItems = [.init(name: "refresh", value: "true")] }
        guard let url = components?.url else { throw MarketServiceError.invalidURL }
        return try await request(url, as: MarketDashboardResponse.self).data
    }

    func chart(symbol: String, range: MarketRange) async throws -> MarketChart {
        var components = URLComponents(url: baseURL.appending(path: "api/v1/market/chart"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "symbol", value: symbol),
            .init(name: "interval", value: range.apiInterval),
            .init(name: "range", value: range.apiRange),
            .init(name: "limit", value: String(range.apiLimit))
        ]
        guard let url = components?.url else { throw MarketServiceError.invalidURL }
        return try await request(url, as: MarketChartResponse.self).data
    }

    /// 收盘后日内 trend 兜底：拉取 5 日 5 分钟线，客户端截取最近一个交易日。
    func recentIntradayChart(symbol: String) async throws -> MarketChart {
        var components = URLComponents(url: baseURL.appending(path: "api/v1/market/chart"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "symbol", value: symbol),
            .init(name: "interval", value: "5m"),
            .init(name: "range", value: "5d"),
            .init(name: "limit", value: "1000")
        ]
        guard let url = components?.url else { throw MarketServiceError.invalidURL }
        return try await request(url, as: MarketChartResponse.self).data
    }

    func indexConstituents(symbol: String) async throws -> MarketIndexConstituents {
        var components = URLComponents(url: baseURL.appending(path: "api/v1/market/index-constituents"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "symbol", value: symbol),
            .init(name: "contract", value: "8")
        ]
        guard let url = components?.url else { throw MarketServiceError.invalidURL }
        return try await request(url, as: MarketIndexConstituentsResponse.self).data
    }

    func famousHoldings(managerKey: String? = nil) async throws -> FamousHoldings {
        var components = URLComponents(url: baseURL.appending(path: "api/v1/market/famous-holdings"), resolvingAgainstBaseURL: false)
        if let managerKey { components?.queryItems = [.init(name: "manager", value: managerKey)] }
        guard let url = components?.url else { throw MarketServiceError.invalidURL }
        return try await request(url, as: FamousHoldingsResponse.self).data
    }

    private func request<Response: Decodable>(_ url: URL, as type: Response.Type) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw MarketServiceError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else { throw MarketServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw MarketServiceError.httpStatus(http.statusCode) }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw MarketServiceError.decoding(error) }
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
        case .decoding: "行情数据格式不兼容"
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
