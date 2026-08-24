import Foundation

struct MarketDashboardResponse: Decodable {
    let success: Bool
    let data: MarketDashboard
}

struct MarketBootstrapResponse: Decodable {
    let success: Bool
    let data: MarketBootstrap
}

struct MarketBootstrap: Decodable {
    let dataContract: String
    let generatedAt: String
    let dashboard: MarketDashboard
    let temperature: MarketAShareTemperature?
    let sentimentSnapshots: [String: MarketSentimentSnapshot]
    let errors: [String: String]?
}

enum CommodityLogoKind: String, CaseIterable {
    case gold
    case crudeOil
    case copper
    case silver
    case naturalGas
    case corn
    case liveCattle
    case feederCattle
    case leanHogs

    init?(symbol: String) {
        switch symbol.uppercased() {
        case "GC1!": self = .gold
        case "CL1!": self = .crudeOil
        case "HG1!": self = .copper
        case "SI1!": self = .silver
        case "NG1!": self = .naturalGas
        case "ZC1!": self = .corn
        case "LE1!": self = .liveCattle
        case "GF1!": self = .feederCattle
        case "HE1!": self = .leanHogs
        default: return nil
        }
    }

    var logoText: String {
        switch self {
        case .gold: "Au"
        case .crudeOil: "WTI"
        case .copper: "Cu"
        case .silver: "Ag"
        case .naturalGas: "NG"
        case .corn: "ZC"
        case .liveCattle: "🐂"
        case .feederCattle: "🐄"
        case .leanHogs: "🐖"
        }
    }

    var isLivestock: Bool {
        switch self {
        case .liveCattle, .feederCattle, .leanHogs: true
        default: false
        }
    }

    var accessibilityName: String {
        switch self {
        case .gold: "黄金"
        case .crudeOil: "原油"
        case .copper: "铜"
        case .silver: "白银"
        case .naturalGas: "天然气"
        case .corn: "玉米"
        case .liveCattle: "活牛"
        case .feederCattle: "育肥牛"
        case .leanHogs: "瘦肉猪"
        }
    }
}

struct MarketDashboard: Codable {
    let dataContract: String
    let definitionVersion: String?
    let generatedAt: String
    let refreshIntervalMs: Int
    var coreIndices: [MarketQuote]
    var referenceIndices: [MarketQuote]
    let realtimeProxies: [MarketRealtimeProxyDefinition]
    var metrics: [MarketQuote]
    var componentsByRegion: [String: [MarketQuote]]
    var crypto: [MarketQuote]
    var commodities: [MarketQuote]
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
        case dataContract, definitionVersion, generatedAt, refreshIntervalMs, coreIndices, referenceIndices, realtimeProxies
        case metrics, componentsByRegion, crypto, commodities
        case indexSessions, componentsMeta, freshness, missingSymbols, expectedSymbols, symbolHealth, regions
        case ashareOverview, marketStructure, sentiment
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        dataContract = try values.decode(String.self, forKey: .dataContract)
        definitionVersion = try values.decodeIfPresent(String.self, forKey: .definitionVersion)
        generatedAt = try values.decode(String.self, forKey: .generatedAt)
        refreshIntervalMs = try values.decode(Int.self, forKey: .refreshIntervalMs)
        coreIndices = try values.decodeLossyQuotes(forKey: .coreIndices)
        referenceIndices = try values.decodeLossyQuotes(forKey: .referenceIndices)
        realtimeProxies = try values.decodeIfPresent([MarketRealtimeProxyDefinition].self, forKey: .realtimeProxies) ?? []
        metrics = try values.decodeLossyQuotes(forKey: .metrics)
        componentsByRegion = try values.decodeLossyQuoteArrays(forKey: .componentsByRegion)
        crypto = try values.decodeLossyQuotes(forKey: .crypto)
        commodities = try values.decodeLossyQuotes(forKey: .commodities)
        indexSessions = try values.decodeLossyQuoteDictionary(forKey: .indexSessions)
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
        replace(quote, in: &referenceIndices)
        replace(quote, in: &metrics)
        for region in Array(componentsByRegion.keys) {
            replace(quote, in: &componentsByRegion[region, default: []])
        }
        replace(quote, in: &crypto)
        replace(quote, in: &commodities)
        for key in indexSessions.map({ Array($0.keys) }) ?? [] where indexSessions?[key]?.symbol == quote.symbol {
            var quotes = [indexSessions?[key]].compactMap { $0 }
            replace(quote, in: &quotes)
            indexSessions?[key] = quotes.first
        }
    }

    mutating func merge(_ update: MarketQuoteUpdate) {
        guard let current = quote(symbol: update.symbol),
              marketRealtimeUpdateIsCurrent(update, current: current) else { return }
        replace(update.merging(into: current))
    }

    func quote(symbol: String) -> MarketQuote? {
        if let quote = coreIndices.first(where: { $0.symbol == symbol }) { return quote }
        if let quote = referenceIndices.first(where: { $0.symbol == symbol }) { return quote }
        if let quote = metrics.first(where: { $0.symbol == symbol }) { return quote }
        if let quote = componentsByRegion.values.lazy.flatMap({ $0 }).first(where: { $0.symbol == symbol }) { return quote }
        if let quote = crypto.first(where: { $0.symbol == symbol }) { return quote }
        if let quote = commodities.first(where: { $0.symbol == symbol }) { return quote }
        return indexSessions?.values.first(where: { $0.symbol == symbol })
    }

    var allRegionalComponents: [MarketQuote] {
        var seen: Set<String> = []
        return componentsByRegion.values
            .flatMap { $0 }
            .filter { seen.insert($0.symbol).inserted }
    }

    private func replace(_ quote: MarketQuote, in quotes: inout [MarketQuote]) {
        guard let index = quotes.firstIndex(where: { $0.symbol == quote.symbol }) else { return }
        quotes[index] = quote
    }
}

private struct LossyMarketQuote: Decodable {
    let value: MarketQuote?

    init(from decoder: Decoder) throws {
        value = try? MarketQuote(from: decoder)
    }
}

private extension KeyedDecodingContainer where Key == MarketDashboard.CodingKeys {
    func decodeLossyQuotes(forKey key: Key) throws -> [MarketQuote] {
        try decodeIfPresent([LossyMarketQuote].self, forKey: key)?.compactMap(\.value) ?? []
    }

    func decodeLossyQuoteDictionary(forKey key: Key) throws -> [String: MarketQuote]? {
        try decodeIfPresent([String: LossyMarketQuote].self, forKey: key)?
            .compactMapValues(\.value)
    }

    func decodeLossyQuoteArrays(forKey key: Key) throws -> [String: [MarketQuote]] {
        try decode([String: [LossyMarketQuote]].self, forKey: key)
            .mapValues { $0.compactMap(\.value) }
    }
}

struct MarketRealtimeProxyDefinition: Codable, Hashable {
    let symbol: String
    let referenceSymbol: String
    let historicalSymbol: String
    let displayName: String
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
        guard let index = items.firstIndex(where: { $0.quote.symbol == update.symbol }),
              marketRealtimeUpdateIsCurrent(update, current: items[index].quote) else { return }
        items[index].quote = update.merging(into: items[index].quote)
    }
}

struct MarketIndexConstituent: Decodable, Identifiable {
    let rank: Int
    let weight: Double?
    let logoPath: String?
    let detailAvailable: Bool
    var quote: MarketQuote
    var id: String { quote.symbol }
}

struct MarketCompanyLogoResponse: Decodable {
    let data: MarketCompanyLogo
}

struct MarketCompanyLogo: Decodable {
    let found: Bool
    let url: String
}

struct MarketDashboardFreshness: Codable {
    let latestQuoteAt: String?
    let latestTimestamp: Int64?
    let hasOpenMarket: Bool
    let hasStaleQuotes: Bool
    let sessions: [String]
}

struct MarketQuoteQuality: Codable, Hashable {
    let status: String?
    let reason: String?
    let asOfTimestamp: Int64?
    let tradingDate: String?
    let fallbackUsed: Bool?
}

struct MarketQuote: Codable, Identifiable, Hashable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let displayName: String?
    let instrumentType: String?
    let proxyFor: String?
    let referenceSymbol: String?
    let historicalSymbol: String?
    let displayMode: String?
    let priceUnit: String?
    let price: Double
    let openPrice: Double?
    let previousClose: Double?
    let high: Double?
    let low: Double?
    let pe: Double?
    let marketCap: Double?
    var peStatic: Double?
    var peType: String?
    var netIncomeTTM: Double?
    var week52Low: Double?
    var currency: String?
    var fundamentalsCurrency: String?
    var fiscalYear: String?
    var fundamentalsSource: String?
    var fundamentalsAsOf: String?
    let volume: Double?
    let turnover: Double?
    let dataSource: String?
    let delaySeconds: Int?
    let marketSession: String?
    let sessionPrice: Double?
    let sessionChangePercent: Double?
    let sessionDataSource: String?
    let changePercent: String?
    let timestamp: Int64?
    let receivedAt: Int64?
    let quality: MarketQuoteQuality?
    var trend: [Double]
    var nightTrend: [Double]
    var liveTrendValue: Double?
    let stale: Bool?

    var percentValue: Double {
        if let previousClose, previousClose > 0 {
            return (price - previousClose) / previousClose * 100
        }
        return Double((changePercent ?? "0").replacingOccurrences(of: "%", with: "")) ?? 0
    }

    var formattedPercent: String {
        if hasSuspiciousIndexMove { return "待核验" }
        return String(format: "%@%.2f%%", percentValue >= 0 ? "+" : "−", abs(percentValue))
    }

    var changeValue: Double {
        guard let previousClose else { return 0 }
        return price - previousClose
    }

    var isUp: Bool { percentValue >= 0 }

    var tradingSession: MarketTradingSession {
        MarketTradingSession(rawValue: marketSession)
    }

    var visibleDelayMinutes: Int? {
        guard tradingSession != .closed, let delaySeconds, delaySeconds >= 60 else { return nil }
        return delaySeconds / 60
    }

    var hasActiveExtendedSessionQuote: Bool {
        sessionPrice != nil && tradingSession.isExtended
    }

    var marketDisplayPrice: Double {
        hasActiveExtendedSessionQuote ? sessionPrice ?? price : price
    }

    var marketDisplayPercentValue: Double {
        guard hasActiveExtendedSessionQuote else { return percentValue }
        if let sessionChangePercent { return sessionChangePercent }
        guard let previousClose, previousClose > 0 else { return percentValue }
        return (marketDisplayPrice - previousClose) / previousClose * 100
    }

    var marketDisplayChangeValue: Double {
        guard let previousClose else { return changeValue }
        return marketDisplayPrice - previousClose
    }

    var marketDisplayFormattedPercent: String {
        if hasSuspiciousIndexMove { return "待核验" }
        let value = marketDisplayPercentValue
        return String(format: "%@%.2f%%", value >= 0 ? "+" : "−", abs(value))
    }

    var formattedSessionPercent: String? {
        sessionChangePercent.map { String(format: "%@%.2f%%", $0 >= 0 ? "+" : "−", abs($0)) }
    }

    enum CodingKeys: String, CodingKey {
        case symbol, name, displayName, instrumentType, proxyFor, referenceSymbol, historicalSymbol, displayMode, priceUnit
        case price, openPrice, previousClose, high, low, pe, marketCap, peStatic, peType, netIncomeTTM, week52Low
        case currency, fundamentalsCurrency, fiscalYear, fundamentalsSource, fundamentalsAsOf, volume, turnover
        case dataSource, delaySeconds, marketSession, sessionPrice, sessionChangePercent, sessionDataSource
        case changePercent, timestamp, receivedAt, quality, trend, nightTrend, stale
    }

    init(
        symbol: String,
        name: String,
        displayName: String?,
        instrumentType: String?,
        proxyFor: String?,
        referenceSymbol: String?,
        historicalSymbol: String?,
        displayMode: String?,
        priceUnit: String? = nil,
        price: Double,
        openPrice: Double?,
        previousClose: Double?,
        high: Double?,
        low: Double?,
        pe: Double?,
        marketCap: Double?,
        peStatic: Double? = nil,
        peType: String? = nil,
        netIncomeTTM: Double? = nil,
        week52Low: Double? = nil,
        currency: String? = nil,
        fundamentalsCurrency: String? = nil,
        fiscalYear: String? = nil,
        fundamentalsSource: String? = nil,
        fundamentalsAsOf: String? = nil,
        volume: Double?,
        turnover: Double?,
        dataSource: String?,
        delaySeconds: Int?,
        marketSession: String?,
        sessionPrice: Double?,
        sessionChangePercent: Double?,
        sessionDataSource: String?,
        changePercent: String?,
        timestamp: Int64?,
        receivedAt: Int64?,
        trend: [Double],
        nightTrend: [Double],
        liveTrendValue: Double? = nil,
        stale: Bool?,
        quality: MarketQuoteQuality? = nil
    ) {
        self.symbol = symbol
        self.name = name
        self.displayName = displayName
        self.instrumentType = instrumentType
        self.proxyFor = proxyFor
        self.referenceSymbol = referenceSymbol
        self.historicalSymbol = historicalSymbol
        self.displayMode = displayMode
        self.priceUnit = priceUnit
        self.price = price
        self.openPrice = openPrice
        self.previousClose = previousClose
        self.high = high
        self.low = low
        self.pe = pe
        self.marketCap = marketCap
        self.peStatic = peStatic
        self.peType = peType
        self.netIncomeTTM = netIncomeTTM
        self.week52Low = week52Low
        self.currency = currency
        self.fundamentalsCurrency = fundamentalsCurrency
        self.fiscalYear = fiscalYear
        self.fundamentalsSource = fundamentalsSource
        self.fundamentalsAsOf = fundamentalsAsOf
        self.volume = volume
        self.turnover = turnover
        self.dataSource = dataSource
        self.delaySeconds = delaySeconds
        self.marketSession = marketSession
        self.sessionPrice = sessionPrice
        self.sessionChangePercent = sessionChangePercent
        self.sessionDataSource = sessionDataSource
        self.changePercent = changePercent
        self.timestamp = timestamp
        self.receivedAt = receivedAt
        self.quality = quality
        self.trend = trend
        self.nightTrend = nightTrend
        self.liveTrendValue = liveTrendValue
        self.stale = stale
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try values.decode(String.self, forKey: .symbol)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? symbol
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName)
        instrumentType = try values.decodeIfPresent(String.self, forKey: .instrumentType)
        proxyFor = try values.decodeIfPresent(String.self, forKey: .proxyFor)
        referenceSymbol = try values.decodeIfPresent(String.self, forKey: .referenceSymbol)
        historicalSymbol = try values.decodeIfPresent(String.self, forKey: .historicalSymbol)
        displayMode = try values.decodeIfPresent(String.self, forKey: .displayMode)
        priceUnit = try values.decodeIfPresent(String.self, forKey: .priceUnit)
        price = try values.decode(Double.self, forKey: .price)
        openPrice = try values.decodeIfPresent(Double.self, forKey: .openPrice)
        previousClose = try values.decodeIfPresent(Double.self, forKey: .previousClose)
        high = try values.decodeIfPresent(Double.self, forKey: .high)
        low = try values.decodeIfPresent(Double.self, forKey: .low)
        pe = try values.decodeIfPresent(Double.self, forKey: .pe)
        marketCap = try values.decodeIfPresent(Double.self, forKey: .marketCap)
        peStatic = try values.decodeIfPresent(Double.self, forKey: .peStatic)
        peType = try values.decodeIfPresent(String.self, forKey: .peType)
        netIncomeTTM = try values.decodeIfPresent(Double.self, forKey: .netIncomeTTM)
        week52Low = try values.decodeIfPresent(Double.self, forKey: .week52Low)
        currency = try values.decodeIfPresent(String.self, forKey: .currency)
        fundamentalsCurrency = try values.decodeIfPresent(String.self, forKey: .fundamentalsCurrency)
        fiscalYear = try values.decodeIfPresent(String.self, forKey: .fiscalYear)
        fundamentalsSource = try values.decodeIfPresent(String.self, forKey: .fundamentalsSource)
        fundamentalsAsOf = try values.decodeIfPresent(String.self, forKey: .fundamentalsAsOf)
        volume = try values.decodeIfPresent(Double.self, forKey: .volume)
        turnover = try values.decodeIfPresent(Double.self, forKey: .turnover)
        dataSource = try values.decodeIfPresent(String.self, forKey: .dataSource)
        delaySeconds = try values.decodeIfPresent(Int.self, forKey: .delaySeconds)
        marketSession = try values.decodeIfPresent(String.self, forKey: .marketSession)
        sessionPrice = try values.decodeIfPresent(Double.self, forKey: .sessionPrice)
        sessionChangePercent = try values.decodeIfPresent(Double.self, forKey: .sessionChangePercent)
        sessionDataSource = try values.decodeIfPresent(String.self, forKey: .sessionDataSource)
        changePercent = try values.decodeIfPresent(String.self, forKey: .changePercent)
        timestamp = try values.decodeIfPresent(Int64.self, forKey: .timestamp)
        receivedAt = try values.decodeIfPresent(Int64.self, forKey: .receivedAt)
        quality = try values.decodeIfPresent(MarketQuoteQuality.self, forKey: .quality)
        trend = try values.decodeIfPresent([Double].self, forKey: .trend) ?? []
        nightTrend = try values.decodeIfPresent([Double].self, forKey: .nightTrend) ?? []
        liveTrendValue = nil
        stale = try values.decodeIfPresent(Bool.self, forKey: .stale)
    }
}

enum MarketTradingSession: Equatable {
    case regular, premarket, postmarket, overnight, closed, alwaysOpen, unknown

    init(rawValue: String?) {
        switch rawValue?.lowercased() {
        case "regular": self = .regular
        case "pre", "premarket": self = .premarket
        case "post", "after": self = .postmarket
        case "overnight": self = .overnight
        case "always-open": self = .alwaysOpen
        case "closed": self = .closed
        default: self = .unknown
        }
    }

    var displayLabel: String {
        switch self {
        case .regular: "交易中"
        case .premarket: "盘前"
        case .postmarket: "盘后"
        case .overnight: "夜盘"
        case .closed: "已收盘"
        case .alwaysOpen: "24小时交易"
        case .unknown: "行情更新"
        }
    }

    var isExtended: Bool {
        self == .premarket || self == .postmarket || self == .overnight
    }

    var isActivelyTrading: Bool {
        self == .regular || self == .alwaysOpen || isExtended
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
    let volume: Double?
    let turnover: Double?
    let dataSource: String?
    let delaySeconds: Int?
    let marketSession: String?
    let sessionPrice: Double?
    let sessionChangePercent: Double?
    let sessionDataSource: String?
    let changePercent: String?
    let timestamp: Int64?
    let receivedAt: Int64?

    func merging(into current: MarketQuote?) -> MarketQuote {
        let tradingSession = MarketTradingSession(rawValue: marketSession ?? current?.marketSession)
        let sessionChanged = current.map { $0.tradingSession != tradingSession } ?? false
        let snapshotTrend = sessionChanged && tradingSession.isActivelyTrading ? [] : current?.trend ?? []
        let liveTrendValue: Double?
        switch tradingSession {
        case .premarket, .postmarket, .overnight:
            liveTrendValue = sessionPrice ?? (sessionChanged ? nil : current?.liveTrendValue)
        case .regular, .alwaysOpen:
            liveTrendValue = price
        case .closed, .unknown:
            liveTrendValue = nil
        }
        let extendedTrend: [Double]
        if tradingSession.isExtended, let sessionPrice {
            extendedTrend = marketAppendingLiveValue(sessionPrice, to: sessionChanged ? [] : current?.nightTrend ?? [])
        } else if tradingSession.isExtended {
            extendedTrend = sessionChanged ? [] : current?.nightTrend ?? []
        } else {
            extendedTrend = []
        }
        let mergedSessionPrice = tradingSession.isExtended
            ? sessionPrice ?? (sessionChanged ? nil : current?.sessionPrice)
            : nil
        let mergedSessionChangePercent = tradingSession.isExtended
            ? sessionChangePercent ?? (sessionChanged ? nil : current?.sessionChangePercent)
            : nil
        let mergedSessionDataSource = tradingSession.isExtended
            ? sessionDataSource ?? (sessionChanged ? nil : current?.sessionDataSource)
            : nil
        let mergedDelaySeconds = sessionChanged ? delaySeconds : delaySeconds ?? current?.delaySeconds
        var merged = MarketQuote(
            symbol: symbol,
            name: name,
            displayName: current?.displayName,
            instrumentType: current?.instrumentType,
            proxyFor: current?.proxyFor,
            referenceSymbol: current?.referenceSymbol,
            historicalSymbol: current?.historicalSymbol,
            displayMode: current?.displayMode,
            priceUnit: current?.priceUnit,
            price: price,
            openPrice: openPrice ?? current?.openPrice,
            previousClose: previousClose ?? current?.previousClose,
            high: high ?? current?.high,
            low: low ?? current?.low,
            pe: current?.pe,
            marketCap: current?.marketCap,
            volume: volume ?? current?.volume,
            turnover: turnover ?? current?.turnover,
            dataSource: dataSource ?? current?.dataSource,
            delaySeconds: mergedDelaySeconds,
            marketSession: marketSession ?? current?.marketSession,
            sessionPrice: mergedSessionPrice,
            sessionChangePercent: mergedSessionChangePercent,
            sessionDataSource: mergedSessionDataSource,
            changePercent: changePercent ?? current?.changePercent,
            timestamp: timestamp ?? current?.timestamp,
            receivedAt: receivedAt ?? current?.receivedAt,
            trend: snapshotTrend,
            nightTrend: extendedTrend,
            liveTrendValue: liveTrendValue,
            stale: false,
            quality: sessionChanged || tradingSession.isActivelyTrading ? nil : current?.quality
        )
        merged.peStatic = current?.peStatic
        merged.peType = current?.peType
        merged.netIncomeTTM = current?.netIncomeTTM
        merged.week52Low = current?.week52Low
        merged.currency = current?.currency
        merged.fundamentalsCurrency = current?.fundamentalsCurrency
        merged.fiscalYear = current?.fiscalYear
        merged.fundamentalsSource = current?.fundamentalsSource
        merged.fundamentalsAsOf = current?.fundamentalsAsOf
        return merged
    }
}

func marketRealtimeUpdateIsCurrent(
    _ update: MarketQuoteUpdate,
    current: MarketQuote?,
    cached: MarketQuoteUpdate? = nil
) -> Bool {
    guard let receivedAt = update.receivedAt else { return false }
    return receivedAt >= max(current?.receivedAt ?? 0, cached?.receivedAt ?? 0)
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
    let previousRank: Int?
    let rankChange: Int?
    let consecutiveTopCount: Int?
    let lastSeenAt: String?

    var percentValue: Double {
        Double(changePercent.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")) ?? 0
    }
}

struct InvestorMoodResponse: Decodable {
    let success: Bool
    let data: InvestorMoodBoard
}

struct InvestorMoodBoard: Decodable {
    let dataContract: String
    let generatedAt: String
    let methodology: String
    let disclaimer: String
    let items: [InvestorMoodItem]
}

struct InvestorVideoInterpretationResponse: Decodable {
    let success: Bool
    let sourceID: String
    let status: String
    let interpretation: BilibiliVideoInterpretation?
    let provider: String
    let model: String
    let cached: Bool
    let estimatedCostCNY: Double

    enum CodingKeys: String, CodingKey {
        case success, status, interpretation, provider, model, cached
        case sourceID = "source_id"
        case estimatedCostCNY = "estimated_cost_cny"
    }
}

struct InvestorMoodItem: Decodable, Identifiable {
    var id: String { awemeId }
    let nickname: String
    let awemeId: String
    let description: String
    let url: String
    let coverUrl: String
    let videoUrl: String
    let createdAt: String?
    let label: String
    let reasons: [String]
    let transcript: String
    let transcriptStatus: String
    let analysis: String
    let evidence: [String]
    let analysisSource: String
    let model: String
    let stale: Bool
    let ageHours: Double?

    private enum CodingKeys: String, CodingKey {
        case nickname, awemeId, description, url, coverUrl, createdAt, label, reasons
        case transcript, transcriptStatus, analysis, evidence, analysisSource, model, stale, ageHours
        case videoUrl, videoURL, playUrl, playURL
        case videoUrlSnake = "video_url"
        case playUrlSnake = "play_url"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        nickname = try values.decode(String.self, forKey: .nickname)
        awemeId = try values.decode(String.self, forKey: .awemeId)
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        url = try values.decodeIfPresent(String.self, forKey: .url) ?? ""
        coverUrl = try values.decodeIfPresent(String.self, forKey: .coverUrl) ?? ""
        videoUrl = [
            try values.decodeIfPresent(String.self, forKey: .videoUrl),
            try values.decodeIfPresent(String.self, forKey: .videoURL),
            try values.decodeIfPresent(String.self, forKey: .playUrl),
            try values.decodeIfPresent(String.self, forKey: .playURL),
            try values.decodeIfPresent(String.self, forKey: .videoUrlSnake),
            try values.decodeIfPresent(String.self, forKey: .playUrlSnake),
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? ""
        createdAt = try values.decodeIfPresent(String.self, forKey: .createdAt)
        label = try values.decodeIfPresent(String.self, forKey: .label) ?? "中性"
        reasons = try values.decodeIfPresent([String].self, forKey: .reasons) ?? []
        transcript = try values.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        transcriptStatus = try values.decodeIfPresent(String.self, forKey: .transcriptStatus) ?? ""
        analysis = try values.decodeIfPresent(String.self, forKey: .analysis) ?? ""
        evidence = try values.decodeIfPresent([String].self, forKey: .evidence) ?? []
        analysisSource = try values.decodeIfPresent(String.self, forKey: .analysisSource) ?? ""
        model = try values.decodeIfPresent(String.self, forKey: .model) ?? ""
        stale = try values.decodeIfPresent(Bool.self, forKey: .stale) ?? false
        ageHours = try values.decodeIfPresent(Double.self, forKey: .ageHours)
    }

    var playbackURL: URL? {
        proxiedMediaURL(from: videoUrl)
    }

    var directPlaybackURL: URL? {
        publicMediaURL(from: videoUrl)
    }

    var coverPlaybackURL: URL? {
        proxiedMediaURL(from: coverUrl)
    }

    var directCoverURL: URL? {
        publicMediaURL(from: coverUrl)
    }

    var prewarmURL: URL? {
        proxiedMediaURL(from: videoUrl, prewarm: true)
    }

    private func proxiedMediaURL(from value: String, prewarm: Bool = false) -> URL? {
        guard let source = publicMediaURL(from: value) else { return nil }
        var components = URLComponents(
            url: ServerConfiguration.currentURL.appending(path: "api/ios/v1/media-proxy"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            .init(name: "url", value: source.absoluteString),
            .init(name: "context", value: "ios-investor-mood"),
        ]
        if prewarm {
            components?.queryItems?.append(.init(name: "prewarm", value: "1"))
        }
        return components?.url
    }

    private func publicMediaURL(from value: String) -> URL? {
        guard let source = URL(string: value),
              let scheme = source.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return source
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

struct MarketAShareTemperatureResponse: Decodable {
    let success: Bool
    let data: MarketAShareTemperature
}

struct MarketKoreaLeverageResponse: Decodable {
    let success: Bool
    let data: MarketKoreaLeverage
}

struct MarketKoreaLeverage: Decodable {
    let dataContract: String
    let asOf: String
    let generatedAt: String
    let fetchedAt: String
    let leverageThermometer: MarketKoreaLeverageThermometer
    let r2FinancingRatio: MarketKoreaFinancingRatio
    let forcedLiquidation: MarketKoreaForcedLiquidation
    let indices: MarketKoreaIndices
    let alert: MarketKoreaLeverageAlert
    let freshness: MarketKoreaLeverageFreshness
    let source: MarketKoreaLeverageSource
    let disclaimer: String
}

struct MarketKoreaLeverageThermometer: Decodable {
    let value: Double
    let weighted: Double
    let unit: String
    let anchor: String
    let note: String
}

struct MarketKoreaFinancingRatio: Decodable {
    let value: Double
    let percentile10Y: Double
    let unit: String
    let note: String
}

struct MarketKoreaForcedLiquidation: Decodable {
    let unsettledBillionKRW: Double
    let fiveDayAverageBillionKRW: Double
    let percentile10Y: Double
}

struct MarketKoreaIndices: Decodable {
    let kospi: Double
    let spx: Double
}

struct MarketKoreaLeverageAlert: Decodable {
    let level: String
    let value: Double
    let message: String
    let thresholds: MarketKoreaLeverageThresholds
}

struct MarketKoreaLeverageThresholds: Decodable {
    let warning: Double
    let critical: Double
}

struct MarketKoreaLeverageFreshness: Decodable {
    let staleDays: Int
    let dailyFullRefreshBeijing: String
    let recommendedPoll: String
}

struct MarketKoreaLeverageSource: Decodable {
    let name: String
    let url: String
    let docs: String
}

struct MarketAShareTemperature: Decodable {
    let dataContract: String
    let days: Int
    let latest: MarketAShareTemperatureLatest
}

struct MarketAShareTemperatureLatest: Decodable {
    let aiServer: MarketAShareTemperatureMetrics?

    enum CodingKeys: String, CodingKey {
        case aiServer = "ai_server"
    }
}

struct MarketAShareTemperatureMetrics: Decodable {
    let compositeTemperature: MarketTemperatureMetric?
    let valuationPercentile: MarketTemperatureMetric?
    let sentimentPercentile: MarketTemperatureMetric?
    let advancerShare: MarketTemperatureMetric?

    enum CodingKeys: String, CodingKey {
        case compositeTemperature = "composite_temperature"
        case valuationPercentile = "valuation_percentile"
        case sentimentPercentile = "sentiment_percentile"
        case advancerShare = "advancer_share"
    }
}

struct MarketTemperatureMetric: Decodable {
    let value: Double
    let label: String
    let tradeDate: String
    let fetchedAt: String
}

struct MarketHKValuationHistory: Decodable {
    let date: [String]
    let pe: [Double]
}

struct MarketUSValuationHistory {
    let pe: [Double]
}

struct MarketSentimentSnapshotResponse: Decodable {
    let success: Bool
    let data: MarketSentimentSnapshot
}

struct MarketSentimentSnapshot: Decodable {
    let dataContract: String
    let market: String
    let score: Double
    let label: String
    let valuationPercentile: Double?
    let sentimentPercentile: Double?
    let advancerShare: Double?
    let breadth: MarketSentimentBreadth?
    let koreaLeverage: MarketKoreaLeverage?
    let fetchedAt: String
    let cached: Bool
    let stale: Bool
}

struct MarketSentimentBreadth: Decodable {
    let up: Int
    let down: Int
    let flat: Int
}

struct MarketValuationHistoryResponse: Decodable {
    let success: Bool
    let data: MarketValuationHistory
}

struct MarketValuationHistory: Decodable {
    let dataContract: String
    let market: String
    let date: [String]
    let pe: [Double]
    let source: String
    let fetchedAt: String
    let cached: Bool
    let stale: Bool
}

struct MarketCompanyValuationHistoryResponse: Decodable {
    let success: Bool
    let data: MarketCompanyValuationHistory
}

struct MarketCompanyValuationHistory: Decodable {
    static let dataContractV2 = "company_valuation_history_v2"
    static let dailyFrequency = "daily"
    static let dailyMethod = "fiscal_anchor_scaled_by_adjusted_daily_close"

    let dataContract: String
    let symbol: String
    let frequency: String
    let method: String
    let peStatic: [MarketCompanyPEPoint]
    let peTTM: [MarketCompanyPEPoint]
    let source: String
    let asOf: String
}

struct MarketCompanyPEPoint: Decodable, Hashable, Identifiable {
    let date: String
    let value: Double

    var id: String { date }
}

struct MarketChartResponse: Decodable {
    let success: Bool
    let data: MarketChart
}

struct MarketChart: Decodable, Sendable {
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

enum MarketChartQualityStatus: String, Decodable, Sendable {
    case complete, repairing, partial, unavailable
}

struct MarketChartQuality: Decodable, Sendable {
    let status: MarketChartQualityStatus
    let expected: Int
    let actual: Int
    let missing: [MarketChartGap]
    let freshnessSeconds: Int?
    let isFinal: Bool
}

struct MarketChartGap: Decodable, Equatable, Sendable {
    let startTimestamp: Int64
    let endTimestamp: Int64
}

struct MarketChartQuote: Decodable, Sendable {
    let price: Double?
    let previousClose: Double?
    let change: Double?
    let changePercent: Double?
    let providerTimestamp: Int64?
    let receivedTimestamp: Int64?
    let source: String
}

struct MarketChartPoint: Decodable, Identifiable, Equatable, Sendable {
    var id: Int64 { timestamp }
    let timestamp: Int64
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double?
    let state: String
    let source: String
    let session: String?

    var displayValue: Double? { close }
}

func marketChartDisplayPoints(_ points: [MarketChartPoint]) -> [MarketChartPoint] {
    points.filter { point in
        guard point.state != "invalid" else { return false }
        let session = point.session ?? "regular"
        let isExtended = session != "regular" && session != "closed"
        if isExtended && point.state == "provisional" {
            return false
        }
        if point.state == "provisional" && point.source.localizedCaseInsensitiveContains("tradingview") {
            return false
        }
        return true
    }
}

struct MarketChartPresentation: Sendable {
    let points: [MarketChartPoint]
    let values: [Double]
    let xFractions: [CGFloat]
    let low: Double?
    let high: Double?
    let axisDigits: Int
    let hasVolume: Bool
    let volumeCeiling: Double
    let volumeFractionGap: CGFloat
    let extendedSessionLabel: String?
    let sessionBreak: MarketChartSessionBreak?

    init(chart: MarketChart) {
        let points = marketChartDisplayPoints(chart.candles)
            .sorted { $0.timestamp < $1.timestamp }
        let values = points.compactMap(\.displayValue)
        self.points = points
        self.values = values
        let xFractions = marketChartXFractions(
            timestamps: points.map(\.timestamp),
            interval: chart.interval
        )
        self.xFractions = xFractions
        low = points.map(\.low).filter(\.isFinite).min()
        high = points.map(\.high).filter(\.isFinite).max()
        axisDigits = marketAxisDigits(values: [low, high].compactMap { $0 })
        hasVolume = points.contains { ($0.volume ?? 0) > 0 }
        volumeCeiling = marketChartVolumeCeiling(points)
        volumeFractionGap = zip(xFractions, xFractions.dropFirst())
            .map { $1 - $0 }
            .filter { $0 > 0 }
            .min() ?? 1
        extendedSessionLabel = chart.interval == "1m" ? marketChartExtendedSessionLabel(points) : nil
        sessionBreak = marketChartLunchBreak(
            points: points,
            market: chart.market,
            interval: chart.interval,
            timezone: chart.timezone
        )
    }
}

struct MarketChartArtifacts: Sendable {
    let presentation: MarketChartPresentation
    let listTrend: [Double]
}

func marketChartArtifacts(for chart: MarketChart) async throws -> MarketChartArtifacts {
    try Task.checkCancellation()
    let presentation = MarketChartPresentation(chart: chart)
    try Task.checkCancellation()
    return MarketChartArtifacts(
        presentation: presentation,
        listTrend: marketSampledChartTrend(displayPoints: presentation.points)
    )
}

func marketSampledChartTrend(_ points: [MarketChartPoint], limit: Int = 60) -> [Double] {
    marketSampledChartTrend(
        displayPoints: marketChartDisplayPoints(points).sorted { $0.timestamp < $1.timestamp },
        limit: limit
    )
}

private func marketSampledChartTrend(displayPoints: [MarketChartPoint], limit: Int = 60) -> [Double] {
    let values = displayPoints
        .compactMap(\.displayValue)
        .filter { $0.isFinite && $0 > 0 }
    guard limit > 1, values.count > limit else { return values }
    let lastIndex = values.count - 1
    return (0..<limit).map { index in
        let fraction = Double(index) / Double(limit - 1)
        return values[Int((fraction * Double(lastIndex)).rounded())]
    }
}

func marketShouldUseFallbackChart(
    primaryPoints: [MarketChartPoint],
    fallbackPoints: [MarketChartPoint]
) -> Bool {
    marketChartDisplayPoints(primaryPoints).count < 2
        && marketChartDisplayPoints(fallbackPoints).count >= 2
}

func market52WeekLow(_ chart: MarketChart?) -> Double? {
    guard chart?.quality.status == .complete else { return nil }
    return chart?.candles
        .filter { $0.state != "invalid" && $0.low.isFinite && $0.low > 0 }
        .map(\.low)
        .min()
}

func marketChartVolumeCeiling(_ points: [MarketChartPoint]) -> Double {
    let values = points.compactMap(\.volume).filter { $0 > 0 && $0.isFinite }.sorted()
    guard !values.isEmpty else { return 1 }
    let index = Int((Double(values.count - 1) * 0.95).rounded(.down))
    return max(values[index], 1)
}

func marketChartExtendedSessionLabel(_ points: [MarketChartPoint]) -> String? {
    let sessions = points.compactMap { $0.session?.lowercased() }
    if sessions.filter({ $0 == "overnight" }).count > 1 {
        return "含夜盘"
    }
    if sessions.contains(where: { $0 == "pre" || $0 == "post" || $0 == "after" }) {
        return "含盘前盘后"
    }
    return nil
}

func marketChartShouldSplitSegment(previous: MarketChartPoint, current: MarketChartPoint, interval: String?) -> Bool {
    let changedSession = (previous.session ?? "regular") != (current.session ?? "regular")
    let hasIntradayGap = interval == "1m" && current.timestamp - previous.timestamp > 15 * 60 * 1000
    return changedSession || hasIntradayGap
}

struct MarketChartSessionBreak: Equatable, Sendable {
    let previousTimestamp: Int64
    let currentTimestamp: Int64
    let label: String
}

func marketChartLunchBreak(
    points: [MarketChartPoint],
    market: String?,
    interval: String?,
    timezone: String?
) -> MarketChartSessionBreak? {
    guard interval == "1m", market?.uppercased() == "CN", points.count > 1 else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timezone ?? "Asia/Shanghai") ?? TimeZone(identifier: "Asia/Shanghai")!
    let sorted = points.sorted { $0.timestamp < $1.timestamp }

    for (previous, current) in zip(sorted, sorted.dropFirst()) {
        guard current.timestamp - previous.timestamp >= 60 * 60 * 1_000 else { continue }
        let previousDate = Date(timeIntervalSince1970: Double(previous.timestamp) / 1_000)
        let currentDate = Date(timeIntervalSince1970: Double(current.timestamp) / 1_000)
        let previousMinute = calendar.component(.hour, from: previousDate) * 60 + calendar.component(.minute, from: previousDate)
        let currentMinute = calendar.component(.hour, from: currentDate) * 60 + calendar.component(.minute, from: currentDate)
        guard (11 * 60 + 15)...(11 * 60 + 45) ~= previousMinute,
              (12 * 60 + 45)...(13 * 60 + 15) ~= currentMinute else { continue }
        return MarketChartSessionBreak(
            previousTimestamp: previous.timestamp,
            currentTimestamp: current.timestamp,
            label: "午间休市"
        )
    }
    return nil
}

func marketChartXFraction(timestamp: Int64, firstTimestamp: Int64, lastTimestamp: Int64) -> CGFloat {
    guard lastTimestamp > firstTimestamp else { return 0 }
    return min(max(CGFloat(Double(timestamp - firstTimestamp) / Double(lastTimestamp - firstTimestamp)), 0), 1)
}

func marketChartXFractions(timestamps: [Int64], interval: String?) -> [CGFloat] {
    guard timestamps.count > 1 else { return timestamps.map { _ in 0 } }
    let maximumIntradayGap = Int64(5 * 60 * 1_000)
    var positions = [Double](repeating: 0, count: timestamps.count)
    for index in 1..<timestamps.count {
        let elapsed = max(timestamps[index] - timestamps[index - 1], 0)
        let displayedElapsed = interval == "1m" ? min(elapsed, maximumIntradayGap) : elapsed
        positions[index] = positions[index - 1] + Double(displayedElapsed)
    }
    guard let total = positions.last, total > 0 else { return positions.map { _ in 0 } }
    return positions.map { CGFloat($0 / total) }
}

func marketVolumeBarX(fraction: CGFloat, width: CGFloat, barWidth: CGFloat) -> CGFloat {
    let inset = min(max(barWidth / 2, 0), max(width / 2, 0))
    return inset + min(max(fraction, 0), 1) * max(width - inset * 2, 0)
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
        case .fiveYears, .maximum: 600
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

func marketMovingAverageValues(_ points: [MarketChartPoint], period: Int) -> [Double?] {
    guard period > 0 else { return Array(repeating: nil, count: points.count) }
    var values = Array<Double?>(repeating: nil, count: points.count)
    var sum = 0.0
    for index in points.indices {
        sum += points[index].close
        if index >= period { sum -= points[index - period].close }
        if index >= period - 1 { values[index] = sum / Double(period) }
    }
    return values
}

func marketEvenChartFractions(count: Int) -> [CGFloat] {
    guard count > 1 else { return count == 1 ? [0.5] : [] }
    return (0..<count).map { CGFloat($0) / CGFloat(count - 1) }
}

func marketNearestChartIndex(fraction: CGFloat, fractions: [CGFloat]) -> Int? {
    guard !fractions.isEmpty else { return nil }
    let target = min(max(fraction, 0), 1)
    return fractions.indices.min { abs(fractions[$0] - target) < abs(fractions[$1] - target) }
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
    var hasSuspiciousIndexMove: Bool {
        let guardedSymbols: Set<String> = ["^GSPC", "^NDX", "^DJI", "^N225", "^KS11", "^STOXX50E", "^GDAXI", "^FTSE", "^FCHI"]
        return guardedSymbols.contains(symbol.uppercased()) && abs(percentValue) >= 15
    }

    var presentationName: String {
        displayName ?? name
    }

    var detailPresentationName: String {
        guard instrumentType == "realtime-proxy-etf" else { return presentationName }
        let base = presentationName
            .replacingOccurrences(of: "实时代理", with: "")
            .replacingOccurrences(of: "（\(symbol)）", with: "")
            .replacingOccurrences(of: "(\(symbol))", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return base.localizedCaseInsensitiveContains("ETF") ? base : "\(base) ETF"
    }

    var detailInstrumentLabel: String {
        if instrumentType == "realtime-proxy-etf" { return "\(displayCode) · 指数代理 ETF" }
        if instrumentType == "reference-index" { return "\(displayCode) · 参考指数" }
        if instrumentType == "commodity-future" {
            return [displayCode, "连续主力合约", priceUnit].compactMap { $0 }.joined(separator: " · ")
        }
        return displayCode
    }

    var compactMarketName: String {
        var name = presentationName
            .replacingOccurrences(of: "纳斯达克 100", with: "纳指 100")
            .replacingOccurrences(of: "纳斯达克100", with: "纳指100")
            .replacingOccurrences(of: "道琼斯工业指数", with: "道指")
            .replacingOccurrences(of: " E-mini", with: "")
            .replacingOccurrences(of: "E-mini ", with: "")
        if instrumentType == "realtime-proxy-etf" {
            name = name
                .replacingOccurrences(of: "实时代理", with: "")
                .replacingOccurrences(of: "（\(symbol)）", with: "")
                .replacingOccurrences(of: "(\(symbol))", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return name
    }

    var freshnessLabel: String {
        if tradingSession == .alwaysOpen { return tradingSession.displayLabel }
        if tradingSession == .closed {
            return quality?.tradingDate.map { "截至 \($0) 收盘" } ?? "已收盘"
        }
        if let visibleDelayMinutes { return "延迟\(visibleDelayMinutes)分钟" }
        if stale == true { return "数据延迟" }
        return tradingSession.displayLabel
    }

    var marketAsOfLabel: String {
        if tradingSession == .closed, let tradingDate = quality?.tradingDate {
            return "\(tradingDate) 收盘行情"
        }
        return marketAsOfTimestamp.map { "\(marketShortTimestamp($0)) 行情" } ?? "行情更新中"
    }

    var marketAsOfTimestamp: Int64? {
        quality?.asOfTimestamp ?? timestamp
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
        case "GC1!": "黄金主连"
        case "CL1!": "原油主连"
        case "HG1!": "铜主连"
        case "SI1!": "白银主连"
        case "NG1!": "天然气主连"
        case "ZC1!": "玉米主连"
        default: symbol
        }
    }
}

func marketActiveIndexSession(_ quote: MarketQuote?) -> MarketQuote? {
    guard let quote else { return nil }
    return quote.tradingSession.isActivelyTrading && quote.tradingSession != .alwaysOpen ? quote : nil
}

func marketXueqiuURL(for symbol: String) -> URL? {
    let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let xueqiuCode: String

    if normalized.hasSuffix(".SS") || normalized.hasSuffix(".SZ") {
        let code = String(normalized.dropLast(3))
        guard code.count == 6, code.allSatisfy(\.isNumber) else { return nil }
        xueqiuCode = (normalized.hasSuffix(".SS") ? "SH" : "SZ") + code
    } else if normalized.hasSuffix(".HK") {
        let code = String(normalized.dropLast(3))
        guard (1...5).contains(code.count), code.allSatisfy(\.isNumber) else { return nil }
        xueqiuCode = String(repeating: "0", count: 5 - code.count) + code
    } else {
        let supportedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        let unsupportedMarketSuffixes = [".T", ".KS", ".KQ"]
        guard !normalized.isEmpty,
              !normalized.hasPrefix("^"),
              !normalized.contains(":"),
              !normalized.contains("!"),
              !unsupportedMarketSuffixes.contains(where: normalized.hasSuffix),
              normalized.unicodeScalars.allSatisfy(supportedCharacters.contains),
              normalized.unicodeScalars.contains(where: CharacterSet.letters.contains) else { return nil }
        xueqiuCode = normalized
    }

    return URL(string: "https://xueqiu.com/S/\(xueqiuCode)")
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
