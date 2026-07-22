import Foundation

struct MarketDashboardResponse: Decodable {
    let success: Bool
    let data: MarketDashboard
}

struct MarketDashboard: Codable {
    let dataContract: String
    let definitionVersion: String?
    let generatedAt: String
    let refreshIntervalMs: Int
    var coreIndices: [MarketQuote]
    var metrics: [MarketQuote]
    var components: [MarketQuote]
    var crypto: [MarketQuote]
    var indexSessions: [String: MarketQuote]?
    let componentsMeta: MarketComponentsMeta?
    let freshness: MarketDashboardFreshness?
    let missingSymbols: [String]
    let expectedSymbols: [String]
    let symbolHealth: [MarketSymbolHealth]
    let regions: [MarketRegionDefinition]
    let ashareOverview: MarketAShareOverview?
    let marketStructure: MarketStructure?
    let sentiment: MarketSentiment?

    var currentAShareBreadth: MarketBreadth? {
        guard ashareOverview?.stale != true else { return nil }
        return ashareOverview?.breadth
    }

    enum CodingKeys: String, CodingKey {
        case dataContract, definitionVersion, generatedAt, refreshIntervalMs, coreIndices, metrics, components, crypto
        case indexSessions, componentsMeta, freshness, missingSymbols, expectedSymbols, symbolHealth, regions
        case ashareOverview, marketStructure, sentiment
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        dataContract = try values.decode(String.self, forKey: .dataContract)
        definitionVersion = try values.decodeIfPresent(String.self, forKey: .definitionVersion)
        generatedAt = try values.decode(String.self, forKey: .generatedAt)
        refreshIntervalMs = try values.decode(Int.self, forKey: .refreshIntervalMs)
        coreIndices = try values.decodeIfPresent([MarketQuote].self, forKey: .coreIndices) ?? []
        metrics = try values.decodeIfPresent([MarketQuote].self, forKey: .metrics) ?? []
        components = try values.decodeIfPresent([MarketQuote].self, forKey: .components) ?? []
        crypto = try values.decodeIfPresent([MarketQuote].self, forKey: .crypto) ?? []
        indexSessions = try values.decodeIfPresent([String: MarketQuote].self, forKey: .indexSessions)
        componentsMeta = try values.decodeIfPresent(MarketComponentsMeta.self, forKey: .componentsMeta)
        freshness = try values.decodeIfPresent(MarketDashboardFreshness.self, forKey: .freshness)
        missingSymbols = try values.decodeIfPresent([String].self, forKey: .missingSymbols) ?? []
        expectedSymbols = try values.decodeIfPresent([String].self, forKey: .expectedSymbols) ?? []
        symbolHealth = try values.decodeIfPresent([MarketSymbolHealth].self, forKey: .symbolHealth) ?? []
        regions = try values.decodeIfPresent([MarketRegionDefinition].self, forKey: .regions) ?? []
        ashareOverview = try values.decodeIfPresent(MarketAShareOverview.self, forKey: .ashareOverview)
        marketStructure = try values.decodeIfPresent(MarketStructure.self, forKey: .marketStructure)
        sentiment = try values.decodeIfPresent(MarketSentiment.self, forKey: .sentiment)
    }

    mutating func replace(_ quote: MarketQuote) {
        replace(quote, in: &coreIndices)
        replace(quote, in: &metrics)
        replace(quote, in: &components)
        replace(quote, in: &crypto)
        for key in indexSessions.map({ Array($0.keys) }) ?? [] where indexSessions?[key]?.symbol == quote.symbol {
            var quotes = [indexSessions?[key]].compactMap { $0 }
            replace(quote, in: &quotes)
            indexSessions?[key] = quotes.first
        }
    }

    func quote(symbol: String) -> MarketQuote? {
        coreIndices.first(where: { $0.symbol == symbol })
            ?? metrics.first(where: { $0.symbol == symbol })
            ?? components.first(where: { $0.symbol == symbol })
            ?? crypto.first(where: { $0.symbol == symbol })
    }

    private func replace(_ quote: MarketQuote, in quotes: inout [MarketQuote]) {
        guard let index = quotes.firstIndex(where: { $0.symbol == quote.symbol }) else { return }
        var next = quote
        if next.trend.isEmpty {
            next.trend = marketAppendingLiveValue(next.price, to: quotes[index].trend)
        }
        if next.nightTrend.isEmpty {
            next.nightTrend = marketAppendingLiveValue(next.sessionPrice ?? next.price, to: quotes[index].nightTrend)
        }
        quotes[index] = next
    }
}

struct MarketSymbolHealth: Codable, Hashable {
    enum Status: String, Codable {
        case live, delayed, stale, missing
    }

    let symbol: String
    let status: Status
    let asOf: String?
    let timestamp: Int64?
    let source: String?
    let delaySeconds: Int?
    let reason: String?
}

struct MarketRegionDefinition: Codable, Hashable {
    let id: String
    let metricSymbols: [String]
}

struct MarketComponentsMeta: Codable {
    let label: String
    let selectionBasis: String
}

struct MarketIndexConstituentsResponse: Decodable {
    let success: Bool
    let data: MarketIndexConstituents
}

struct MarketIndexConstituents: Decodable {
    let indexSymbol: String
    let label: String
    let selectionBasis: String
    let asOf: String
    let generatedAt: String
    var items: [MarketIndexConstituent]
    let missingSymbols: [String]
    let staleSymbols: [String]?

    var symbolsPendingRefresh: [String] {
        Array(Set(missingSymbols + (staleSymbols ?? []))).sorted()
    }

    mutating func merge(_ update: MarketQuoteUpdate) {
        guard let index = items.firstIndex(where: { $0.quote.symbol == update.symbol }) else { return }
        items[index].quote = update.merging(into: items[index].quote)
    }
}

struct MarketIndexConstituent: Decodable, Identifiable {
    let rank: Int
    let weight: Double?
    let logoPath: String?
    var quote: MarketQuote
    var id: String { quote.symbol }
}

struct MarketDashboardFreshness: Codable {
    let latestQuoteAt: String?
    let latestTimestamp: Int64?
    let hasOpenMarket: Bool
    let hasStaleQuotes: Bool
    let sessions: [String]
}

struct MarketQuote: Codable, Identifiable, Hashable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let price: Double
    let openPrice: Double?
    let previousClose: Double?
    let high: Double?
    let low: Double?
    let pe: Double?
    let marketCap: Double?
    let volume: Double?
    let turnover: Double?
    let dataSource: String?
    let delaySeconds: Int?
    let marketSession: String?
    let isNightSession: Bool?
    let sessionPrice: Double?
    let sessionChangePercent: Double?
    let sessionDataSource: String?
    let changePercent: String?
    let timestamp: Int64?
    var trend: [Double]
    var nightTrend: [Double]
    let stale: Bool?

    var percentValue: Double {
        if let previousClose, previousClose > 0 {
            return (price - previousClose) / previousClose * 100
        }
        return Double((changePercent ?? "0").replacingOccurrences(of: "%", with: "")) ?? 0
    }

    var formattedPercent: String {
        String(format: "%@%.2f%%", percentValue >= 0 ? "+" : "−", abs(percentValue))
    }

    var changeValue: Double {
        guard let previousClose else { return 0 }
        return price - previousClose
    }

    var isUp: Bool { percentValue >= 0 }

    var formattedSessionPercent: String? {
        sessionChangePercent.map { String(format: "%@%.2f%%", $0 >= 0 ? "+" : "−", abs($0)) }
    }

    enum CodingKeys: String, CodingKey {
        case symbol, name, price, openPrice, previousClose, high, low, pe, marketCap, volume, turnover
        case dataSource, delaySeconds, marketSession, isNightSession, sessionPrice, sessionChangePercent, sessionDataSource
        case changePercent, timestamp, trend, nightTrend, stale
    }

    init(
        symbol: String,
        name: String,
        price: Double,
        openPrice: Double?,
        previousClose: Double?,
        high: Double?,
        low: Double?,
        pe: Double?,
        marketCap: Double?,
        volume: Double?,
        turnover: Double?,
        dataSource: String?,
        delaySeconds: Int?,
        marketSession: String?,
        isNightSession: Bool?,
        sessionPrice: Double?,
        sessionChangePercent: Double?,
        sessionDataSource: String?,
        changePercent: String?,
        timestamp: Int64?,
        trend: [Double],
        nightTrend: [Double],
        stale: Bool?
    ) {
        self.symbol = symbol
        self.name = name
        self.price = price
        self.openPrice = openPrice
        self.previousClose = previousClose
        self.high = high
        self.low = low
        self.pe = pe
        self.marketCap = marketCap
        self.volume = volume
        self.turnover = turnover
        self.dataSource = dataSource
        self.delaySeconds = delaySeconds
        self.marketSession = marketSession
        self.isNightSession = isNightSession
        self.sessionPrice = sessionPrice
        self.sessionChangePercent = sessionChangePercent
        self.sessionDataSource = sessionDataSource
        self.changePercent = changePercent
        self.timestamp = timestamp
        self.trend = trend
        self.nightTrend = nightTrend
        self.stale = stale
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try values.decode(String.self, forKey: .symbol)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? symbol
        price = try values.decode(Double.self, forKey: .price)
        openPrice = try values.decodeIfPresent(Double.self, forKey: .openPrice)
        previousClose = try values.decodeIfPresent(Double.self, forKey: .previousClose)
        high = try values.decodeIfPresent(Double.self, forKey: .high)
        low = try values.decodeIfPresent(Double.self, forKey: .low)
        pe = try values.decodeIfPresent(Double.self, forKey: .pe)
        marketCap = try values.decodeIfPresent(Double.self, forKey: .marketCap)
        volume = try values.decodeIfPresent(Double.self, forKey: .volume)
        turnover = try values.decodeIfPresent(Double.self, forKey: .turnover)
        dataSource = try values.decodeIfPresent(String.self, forKey: .dataSource)
        delaySeconds = try values.decodeIfPresent(Int.self, forKey: .delaySeconds)
        marketSession = try values.decodeIfPresent(String.self, forKey: .marketSession)
        isNightSession = try values.decodeIfPresent(Bool.self, forKey: .isNightSession)
        sessionPrice = try values.decodeIfPresent(Double.self, forKey: .sessionPrice)
        sessionChangePercent = try values.decodeIfPresent(Double.self, forKey: .sessionChangePercent)
        sessionDataSource = try values.decodeIfPresent(String.self, forKey: .sessionDataSource)
        changePercent = try values.decodeIfPresent(String.self, forKey: .changePercent)
        timestamp = try values.decodeIfPresent(Int64.self, forKey: .timestamp)
        trend = try values.decodeIfPresent([Double].self, forKey: .trend) ?? []
        nightTrend = try values.decodeIfPresent([Double].self, forKey: .nightTrend) ?? []
        stale = try values.decodeIfPresent(Bool.self, forKey: .stale)
    }
}

struct MarketQuoteUpdate: Decodable {
    let symbol: String
    let name: String
    let price: Double
    let openPrice: Double?
    let previousClose: Double?
    let high: Double?
    let low: Double?
    let pe: Double?
    let marketCap: Double?
    let volume: Double?
    let turnover: Double?
    let dataSource: String?
    let delaySeconds: Int?
    let marketSession: String?
    let isNightSession: Bool?
    let sessionPrice: Double?
    let sessionChangePercent: Double?
    let sessionDataSource: String?
    let changePercent: String?
    let timestamp: Int64?

    func merging(into current: MarketQuote?) -> MarketQuote {
        let regularTrend = marketAppendingLiveValue(price, to: current?.trend ?? [])
        let extendedTrend: [Double]
        if isNightSession == true, let sessionPrice {
            extendedTrend = marketAppendingLiveValue(sessionPrice, to: current?.nightTrend ?? [])
        } else {
            extendedTrend = current?.nightTrend ?? []
        }
        return MarketQuote(
            symbol: symbol,
            name: name,
            price: price,
            openPrice: openPrice ?? current?.openPrice,
            previousClose: previousClose ?? current?.previousClose,
            high: high ?? current?.high,
            low: low ?? current?.low,
            pe: pe ?? current?.pe,
            marketCap: marketCap ?? current?.marketCap,
            volume: volume ?? current?.volume,
            turnover: turnover ?? current?.turnover,
            dataSource: dataSource ?? current?.dataSource,
            delaySeconds: delaySeconds ?? current?.delaySeconds,
            marketSession: marketSession ?? current?.marketSession,
            isNightSession: isNightSession ?? current?.isNightSession,
            sessionPrice: sessionPrice ?? current?.sessionPrice,
            sessionChangePercent: sessionChangePercent ?? current?.sessionChangePercent,
            sessionDataSource: sessionDataSource ?? current?.sessionDataSource,
            changePercent: changePercent ?? current?.changePercent,
            timestamp: timestamp ?? current?.timestamp,
            trend: regularTrend,
            nightTrend: extendedTrend,
            stale: false
        )
    }
}

struct MarketAShareOverview: Codable {
    let breadth: MarketBreadth
    let hotSectors: [MarketSector]
    let generatedAt: String?
    let fetchedAt: String?
    let source: String?
    let cached: Bool?
    let stale: Bool?
}

struct MarketBreadth: Codable {
    let up: Int
    let down: Int
    let flat: Int
    let total: Int

    enum CodingKeys: String, CodingKey {
        case up = "Up"
        case down = "Down"
        case flat = "Flat"
        case total = "Total"
    }
}

struct MarketSector: Codable, Identifiable {
    var id: String { name }
    let name: String
    let changePercent: String
    let direction: String?
    let rank: Int?
    let lastSeenAt: String?

    var percentValue: Double {
        Double(changePercent.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")) ?? 0
    }
}

struct MarketStructure: Codable {
    let dataContract: String
    let generatedAt: String
    let etfSubscription: MarketETFSubscription
    let marginBalance: MarketMarginBalance
    let combinedSignal: MarketCombinedSignal?
    let sources: [MarketStructureSource]
}

struct MarketCombinedSignal: Codable {
    let status: String
    let title: String
    let summary: String
}

struct MarketStructureSource: Codable, Identifiable {
    let name: String
    let url: String
    var id: String { url }
}

struct MarketETFSubscription: Codable {
    let fundCode: String
    let fundName: String
    let fundCount: Int?
    let fundCodes: [String]?
    let asOf: String
    let status: String
    let latestShares: Double
    let latestNetSubscriptionShares: Double
    let latestEstimatedNetFlowCNY: Double?
    let estimatedFlowFundCount: Int?
    let netSubscriptionShares5d: Double
    let previousNetShares5d: Double
    let positiveDays5d: Int
    let consecutiveDirection: String
    let consecutiveDays: Int
    let points: [MarketETFSubscriptionPoint]
}

struct MarketETFSubscriptionPoint: Codable, Identifiable {
    let date: String
    let totalShares: Double
    let netSubscriptionShares: Double
    var id: String { date }
}

struct MarketMarginBalance: Codable {
    let asOf: String
    let status: String
    let financingBalance: Double
    let securitiesBalance: Double
    let totalBalance: Double
    let latestChange: Double
    let change3d: Double
    let change5d: Double
    let positiveDays5d: Int
    let financingBuyAmount: Double?
    let aShareTurnover: Double?
    let financingBuyRatio: Double?
    let activityStatus: String?
    let points: [MarketMarginPoint]

    var riskAppetite: MarketLeverageRiskAppetite {
        MarketLeverageRiskAppetite(status: status)
    }
}

enum MarketLeverageRiskAppetite: Equatable {
    case weak
    case repairing
    case strong
    case uncertain

    init(status: String) {
        switch status {
        case "declining": self = .weak
        case "stabilizing": self = .repairing
        case "recovering": self = .strong
        default: self = .uncertain
        }
    }
}

struct MarketMarginPoint: Codable, Identifiable {
    let date: String
    let financingBalance: Double
    let securitiesBalance: Double
    let totalBalance: Double
    let dailyChange: Double
    let financingBuyAmount: Double?
    var id: String { date }
}

struct MarketSentiment: Codable {
    let score: Double
    let previousClose: Double?
    let ratingZh: String
    let reasonSummary: String?
    let updatedAt: String?
    let source: String?
    let available: Bool?
    let stale: Bool?
}

struct MarketChartResponse: Decodable {
    let success: Bool
    let data: MarketChart
}

struct MarketChart: Decodable {
    let symbol: String
    let market: String
    let tradingDate: String
    let timezone: String
    let session: String
    let interval: String
    let quality: MarketChartQuality
    let quote: MarketChartQuote
    let candles: [MarketChartPoint]
}

enum MarketChartQualityStatus: String, Decodable {
    case complete, repairing, partial, unavailable
}

struct MarketChartQuality: Decodable {
    let status: MarketChartQualityStatus
    let expected: Int
    let actual: Int
    let missing: [MarketChartGap]
    let freshnessSeconds: Int?
    let isFinal: Bool
}

struct MarketChartGap: Decodable, Equatable {
    let startTimestamp: Int64
    let endTimestamp: Int64
}

struct MarketChartQuote: Decodable {
    let price: Double?
    let previousClose: Double?
    let change: Double?
    let changePercent: Double?
    let providerTimestamp: Int64?
    let receivedTimestamp: Int64?
    let source: String
}

struct MarketChartPoint: Decodable, Identifiable, Equatable {
    var id: Int64 { timestamp }
    let timestamp: Int64
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double?
    let state: String
    let source: String

    var displayValue: Double? { close }
}

enum MarketRange: String, CaseIterable, Identifiable {
    case day = "1日", week = "1周", month = "1月", quarter = "3月", year = "1年", fiveYears = "5年", maximum = "最大"
    var id: Self { self }

    var apiRange: String {
        switch self {
        case .day: "1d"
        case .week: "5d"
        case .month: "1mo"
        case .quarter: "3mo"
        case .year: "1y"
        case .fiveYears: "5y"
        case .maximum: "max"
        }
    }

    var apiInterval: String { self == .day ? "1m" : "1d" }

    var apiLimit: Int {
        switch self {
        case .day: 600
        case .week: 8
        case .month: 64
        case .quarter: 128
        case .year: 400
        case .fiveYears, .maximum: 1_000
        }
    }

}

struct MarketCandleSample: Identifiable, Equatable {
    var id: Int64 { timestamp }
    let timestamp: Int64
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double?
}

func marketAxisDigits(values: [Double]) -> Int {
    guard let low = values.min(), let high = values.max(), high > low else { return 2 }
    let step = (high - low) / 4
    if step >= 10 { return 0 }
    if step >= 1 { return 1 }
    return 2
}

func marketCandleSamples(_ points: [MarketChartPoint], maxCount: Int) -> [MarketCandleSample] {
    let candles = points.compactMap { point -> MarketCandleSample? in
        let close = point.close
        let open = point.open
        return MarketCandleSample(
            timestamp: point.timestamp,
            open: open,
            high: max(point.high, max(open, close)),
            low: min(point.low, min(open, close)),
            close: close,
            volume: point.volume
        )
    }
    guard maxCount > 0, candles.count > maxCount else { return candles }

    let bucketSize = Int(ceil(Double(candles.count) / Double(maxCount)))
    return stride(from: 0, to: candles.count, by: bucketSize).compactMap { start in
        let bucket = candles[start..<min(start + bucketSize, candles.count)]
        let volumes = bucket.compactMap(\.volume)
        guard let first = bucket.first,
              let last = bucket.last,
              let high = bucket.map(\.high).max(),
              let low = bucket.map(\.low).min() else { return nil }
        return MarketCandleSample(
            timestamp: last.timestamp,
            open: first.open,
            high: high,
            low: low,
            close: last.close,
            volume: volumes.isEmpty ? nil : volumes.reduce(0, +)
        )
    }
}

func marketTrendIsUp(values: [Double], fallbackIsUp: Bool) -> Bool {
    guard let first = values.first, let last = values.last, first != last else { return fallbackIsUp }
    return last > first
}

func marketAppendingLiveValue(_ value: Double, to values: [Double], limit: Int = 240) -> [Double] {
    guard value.isFinite, limit > 0 else { return Array(values.suffix(max(limit, 0))) }
    var result = values
    if result.last != value { result.append(value) }
    return Array(result.suffix(limit))
}

extension MarketQuote {
    var freshnessLabel: String {
        if marketSession == "always-open" { return "24小时交易" }
        if marketSession == "closed" {
            return timestamp.map { "截至 \(marketShortTimestamp($0))" } ?? "已收盘"
        }
        if let delaySeconds, delaySeconds > 0 { return "延迟\(max(1, delaySeconds / 60))分钟" }
        if stale == true { return "数据延迟" }
        return marketSession == "regular" ? "交易中" : "行情更新"
    }

    var displayCode: String {
        if symbol.hasPrefix("BINANCE:"), symbol.hasSuffix("USDT") {
            let base = symbol.dropFirst("BINANCE:".count).dropLast("USDT".count)
            return "\(base)/USDT"
        }
        if symbol.hasSuffix(".SS") {
            return String(symbol.dropLast(3)) + ".SH"
        }
        return switch symbol {
        case "^GSPC": "SPX"
        case "^NDX": "NDX"
        case "^DJI": "DJI"
        case "^HSTECH": "HSTECH"
        case "^HSI": "HSI"
        case "^N225": "N225"
        case "^KS11": "KOSPI"
        case "^STOXX50E": "SX5E"
        case "^GDAXI": "DAX"
        case "^FTSE": "FTSE"
        case "^FCHI": "CAC40"
        case "^VIX": "VIX"
        case "^TNX": "US10Y"
        default: symbol
        }
    }
}

func marketShortTimestamp(_ timestamp: Int64) -> String {
    MarketDateFormatters.shortTimestamp.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000))
}

func marketISODate(_ value: String?) -> Date? {
    guard let value else { return nil }
    return MarketDateFormatters.isoFractional.date(from: value) ?? MarketDateFormatters.iso.date(from: value)
}

private enum MarketDateFormatters {
    static let shortTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
    static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    static let iso = ISO8601DateFormatter()
}
