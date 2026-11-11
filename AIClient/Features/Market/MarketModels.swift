import Foundation

struct MarketDashboardResponse: Decodable {
    let success: Bool
    let data: MarketDashboard
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
        guard price.isFinite, price > 0 else { return percentValue }
        return (marketDisplayPrice - price) / price * 100
    }

    var marketDisplayChangeValue: Double {
        // Extended quotes are separate from the latest regular-session close.
        // previousClose belongs to that regular session, not the new night session.
        if hasActiveExtendedSessionQuote { return marketDisplayPrice - price }
        return changeValue
    }

    var marketDisplayFormattedPercent: String {
        if hasSuspiciousIndexMove { return "待核验" }
        let value = marketDisplayPercentValue
        return String(format: "%@%.2f%%", value >= 0 ? "+" : "−", abs(value))
    }

    var formattedSessionPercent: String? {
        hasActiveExtendedSessionQuote ? marketDisplayFormattedPercent : nil
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

struct CompanyPEChartPoint: Identifiable {
    let date: Date
    let value: Double

    var id: Date { date }
}

func marketCompanyPEDisplayPoints(
    _ points: [CompanyPEChartPoint],
    maxCount: Int = 480
) -> [CompanyPEChartPoint] {
    guard maxCount >= 4, points.count > maxCount else { return points }
    let interiorCount = points.count - 2
    let bucketCount = max(1, (maxCount - 2) / 2)
    let bucketSize = max(1, Int(ceil(Double(interiorCount) / Double(bucketCount))))
    var result = [points[0]]
    result.reserveCapacity(maxCount)

    for start in stride(from: 1, to: points.count - 1, by: bucketSize) {
        let end = min(start + bucketSize, points.count - 1)
        guard start < end else { continue }
        let bucket = points[start..<end]
        guard let minimum = bucket.min(by: { $0.value < $1.value }),
              let maximum = bucket.max(by: { $0.value < $1.value }) else { continue }
        if minimum.id == maximum.id {
            result.append(minimum)
        } else if minimum.date < maximum.date {
            result.append(contentsOf: [minimum, maximum])
        } else {
            result.append(contentsOf: [maximum, minimum])
        }
    }
    result.append(points[points.count - 1])
    return result
}

struct CompanyPEChartProjection {
    let points: [CompanyPEChartPoint]
    let displayPoints: [CompanyPEChartPoint]
    let median: Double?
    let percentile: Double?
    let previousChange: Double?
    let minimum: CompanyPEChartPoint?
    let maximum: CompanyPEChartPoint?
    let yDomain: ClosedRange<Double>

    init(sortedPoints: [CompanyPEChartPoint], years: Int? = nil) {
        if let years, let lastDate = sortedPoints.last?.date,
           let cutoff = Calendar(identifier: .gregorian).date(byAdding: .year, value: -years, to: lastDate) {
            points = sortedPoints.filter { $0.date >= cutoff }
        } else {
            points = sortedPoints
        }
        displayPoints = marketCompanyPEDisplayPoints(points)
        minimum = points.min { $0.value < $1.value }
        maximum = points.max { $0.value < $1.value }
        if let low = minimum?.value, let high = maximum?.value, let latest = points.last?.value {
            let sorted = points.map(\.value).sorted()
            let midpoint = sorted.count / 2
            median = sorted.count.isMultiple(of: 2) ? (sorted[midpoint - 1] + sorted[midpoint]) / 2 : sorted[midpoint]
            percentile = Double(points.count { $0.value <= latest }) / Double(points.count) * 100
            let padding = max((high - low) * 0.12, max(high * 0.04, 1))
            yDomain = max(0, low - padding)...(high + padding)
        } else {
            median = nil
            percentile = nil
            yDomain = 0...1
        }
        if let latest = points.last?.value, let previous = points.dropLast().last?.value, previous != 0 {
            previousChange = (latest / previous - 1) * 100
        } else {
            previousChange = nil
        }
    }

    func point(closestTo date: Date?) -> CompanyPEChartPoint? {
        guard let date else { return points.last }
        return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
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
    let periodReturn: MarketChartPeriodReturn?
    let periodVolatility: MarketChartPeriodVolatility?
    let quality: MarketChartQuality
    let quote: MarketChartQuote
    let candles: [MarketChartPoint]
    let analysis: MarketChartAnalysis

    init(
        symbol: String, market: String, tradingDate: String, timezone: String, session: String,
        interval: String, periodReturn: MarketChartPeriodReturn?, periodVolatility: MarketChartPeriodVolatility?,
        quality: MarketChartQuality, quote: MarketChartQuote, candles: [MarketChartPoint], analysis: MarketChartAnalysis
    ) {
        self.symbol = symbol
        self.market = market
        self.tradingDate = tradingDate
        self.timezone = timezone
        self.session = session
        self.interval = interval
        self.periodReturn = periodReturn
        self.periodVolatility = periodVolatility
        self.quality = quality
        self.quote = quote
        self.candles = candles
        self.analysis = analysis
    }
}

enum MarketChartTimestampConvention: String, Decodable, Sendable {
    case intervalEnd = "interval-end"
    case intervalStart = "interval-start"
    case tradingDate = "trading-date"
}

struct MarketChartSessionWindow: Decodable, Equatable, Sendable {
    let startTimestamp: Int64
    let endTimestamp: Int64
    let tradingDate: String
    let session: String

    func contains(_ timestamp: Int64, convention: MarketChartTimestampConvention) -> Bool {
        switch convention {
        case .intervalEnd: timestamp > startTimestamp && timestamp <= endTimestamp
        case .intervalStart: timestamp >= startTimestamp && timestamp < endTimestamp
        case .tradingDate: false
        }
    }
}

struct MarketChartAnalysis: Decodable, Sendable {
    let aggregation: String
    let candleTimestamp: MarketChartTimestampConvention
    let sessionWindows: [MarketChartSessionWindow]
}

struct MarketChartPeriodReturn: Decodable, Sendable {
    let range: String
    let basis: String
    let startPrice: Double?
    let endPrice: Double?
    let change: Double?
    let percent: Double?
    let startTimestamp: Int64?
    let endTimestamp: Int64?
}

struct MarketChartPeriodVolatility: Decodable, Sendable {
    let range: String
    let basis: String
    let percent: Double?
    let observationCount: Int
    let annualizationPeriods: Int
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
    let tradingDate: String?

    init(
        timestamp: Int64, open: Double, high: Double, low: Double, close: Double,
        volume: Double?, state: String, source: String, session: String?, tradingDate: String? = nil
    ) {
        self.timestamp = timestamp
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
        self.state = state
        self.source = source
        self.session = session
        self.tradingDate = tradingDate
    }

    var displayValue: Double? { close }
}

func marketChartDisplayPoints(_ points: [MarketChartPoint], interval: String) -> [MarketChartPoint] {
    let isRawIntraday = interval == "1m" || interval == "15m"
    return points.filter { point in
        guard point.state != "invalid" else { return false }
        let session = point.session ?? "regular"
        let isExtended = session != "regular" && session != "closed"
        if isRawIntraday && isExtended && point.state == "provisional" {
            return false
        }
        // Raw browser quote snapshots are not completed intraday bars. A daily
        // live candle and an already-derived aggregate have their own interval contract.
        let providers = point.source.split(separator: ",")
        if isRawIntraday, point.state == "provisional", !providers.isEmpty,
           providers.allSatisfy({ String($0).localizedCaseInsensitiveContains("tradingview") }) {
            return false
        }
        return true
    }
}

struct MarketChartPresentation: Sendable {
    let points: [MarketChartPoint]
    let values: [Double]
    let xFractions: [CGFloat]
    let lineSegments: [MarketChartLineSegment]
    let low: Double?
    let high: Double?
    let axisDigits: Int
    let hasVolume: Bool
    let volumeCeiling: Double
    let volumeFractionGap: CGFloat
    let extendedSessionLabel: String?
    let sessionBreak: MarketChartSessionBreak?

    init(chart: MarketChart) {
        let points = marketChartDisplayPoints(chart.candles, interval: chart.interval)
            .sorted { $0.timestamp < $1.timestamp }
        let values = points.compactMap(\.displayValue)
        self.points = points
        self.values = values
        let xFractions = marketChartXFractions(
            timestamps: points.map(\.timestamp),
            interval: chart.interval
        )
        self.xFractions = xFractions
        lineSegments = marketChartLineSegments(points: points, chart: chart)
        let rawLow = points.map(\.low).filter(\.isFinite).min()
        let rawHigh = points.map(\.high).filter(\.isFinite).max()
        if let rawLow, let rawHigh, rawLow == rawHigh {
            let padding = max(abs(rawLow) * 0.001, 0.000_001)
            low = rawLow - padding
            high = rawHigh + padding
        } else {
            low = rawLow
            high = rawHigh
        }
        axisDigits = marketAxisDigits(values: [low, high].compactMap { $0 })
        hasVolume = points.contains { ($0.volume ?? 0) > 0 }
        volumeCeiling = marketChartVolumeCeiling(points)
        volumeFractionGap = zip(xFractions, xFractions.dropFirst())
            .map { $1 - $0 }
            .filter { $0 > 0 }
            .min() ?? 1
        extendedSessionLabel = marketChartIntervalMinutes(chart.interval) != nil ? marketChartExtendedSessionLabel(points) : nil
        sessionBreak = marketChartSessionBreak(points: points, chart: chart)
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

struct MarketMovingAverageSeries: Sendable {
    let period: Int
    let values: [Double?]
}

struct MarketChartDisplayArtifacts: Sendable {
    let chart: MarketChart
    let presentation: MarketChartPresentation
    let movingAverages: [MarketMovingAverageSeries]
    let drawnPointCount: Int
}

func marketChartDisplayArtifacts(
    for source: MarketChart, period: MarketChartPeriod
) async throws -> MarketChartDisplayArtifacts? {
    try Task.checkCancellation()
    guard let chart = marketChartForDisplay(source, period: period) else { return nil }
    try Task.checkCancellation()
    let presentation = MarketChartPresentation(chart: chart)
    let points = presentation.points
    let movingAverages = [5, 10, 20, 60].filter { $0 <= points.count }.map { period in
        MarketMovingAverageSeries(period: period, values: marketMovingAverageValues(points, period: period))
    }
    let drawnPointCount = Set(presentation.lineSegments.flatMap(\.indices)).count
    try Task.checkCancellation()
    return MarketChartDisplayArtifacts(
        chart: chart, presentation: presentation,
        movingAverages: movingAverages, drawnPointCount: drawnPointCount
    )
}

func marketSampledChartTrend(_ points: [MarketChartPoint], interval: String, limit: Int = 120) -> [Double] {
    marketSampledChartTrend(
        displayPoints: marketChartDisplayPoints(points, interval: interval).sorted { $0.timestamp < $1.timestamp },
        limit: limit
    )
}

func marketPreferredLeadChartTrend(chartValues: [Double], fallbackValues: [Double]) -> [Double] {
    chartValues.count >= 2 ? chartValues : fallbackValues
}

private func marketSampledChartTrend(displayPoints: [MarketChartPoint], limit: Int = 120) -> [Double] {
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

func market52WeekHigh(_ chart: MarketChart?, symbol: String) -> Double? {
    guard let chart, chart.symbol == symbol, chart.quality.status == .complete else { return nil }
    return chart.candles
        .filter { $0.state != "invalid" && $0.high.isFinite && $0.high > 0 }
        .map(\.high)
        .max()
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

struct MarketChartLineSegment: Equatable, Sendable {
    let indices: [Int]
    let isRegular: Bool
    let isMissing: Bool
}

private func marketChartLineSegments(points: [MarketChartPoint], chart: MarketChart) -> [MarketChartLineSegment] {
    guard let first = points.first else { return [] }
    guard points.count > 1 else {
        return [MarketChartLineSegment(indices: [0], isRegular: marketChartLineSession(first) == "regular", isMissing: false)]
    }
    let intervalMilliseconds = marketChartIntervalMinutes(chart.interval).map { Int64($0) * 60 * 1_000 }
    let canInferMissing = chart.quality.status == .repairing || chart.quality.status == .partial
    var segments: [MarketChartLineSegment] = []
    var indices: [Int] = []
    var isRegular = false
    var isMissing = false
    for index in 1..<points.count {
        let previous = points[index - 1]
        let current = points[index]
        let edgeIsRegular = marketChartLineSession(current) == "regular"
        let explicitMissing = chart.quality.missing.contains { gap in
            gap.startTimestamp <= current.timestamp && gap.endTimestamp >= previous.timestamp
        }
        let inferredMissing = canInferMissing && intervalMilliseconds.map { interval in
            current.timestamp - previous.timestamp > interval * 3 / 2
                && marketChartPointsShareOpenSession(previous, current, analysis: chart.analysis)
        } == true
        let edgeIsMissing = explicitMissing || inferredMissing
        if !indices.isEmpty && edgeIsRegular == isRegular && edgeIsMissing == isMissing {
            indices.append(index)
        } else {
            if !indices.isEmpty {
                segments.append(MarketChartLineSegment(indices: indices, isRegular: isRegular, isMissing: isMissing))
            }
            // Share the boundary point so a style change never drops a real price edge.
            indices = [index - 1, index]
            isRegular = edgeIsRegular
            isMissing = edgeIsMissing
        }
    }
    segments.append(MarketChartLineSegment(indices: indices, isRegular: isRegular, isMissing: isMissing))
    return segments
}

private func marketChartLineSession(_ point: MarketChartPoint) -> String {
    switch point.session {
    case nil, "regular", "closed": "regular"
    case let session?: session
    }
}

private func marketChartPointsShareOpenSession(
    _ previous: MarketChartPoint, _ current: MarketChartPoint, analysis: MarketChartAnalysis
) -> Bool {
    guard marketChartLineSession(previous) == marketChartLineSession(current),
          let first = analysis.sessionWindows.first(where: { $0.contains(previous.timestamp, convention: analysis.candleTimestamp) }),
          let last = analysis.sessionWindows.first(where: { $0.contains(current.timestamp, convention: analysis.candleTimestamp) }) else { return false }
    if first == last { return true }
    var end = first.endTimestamp
    for window in analysis.sessionWindows where window.startTimestamp >= end && window.startTimestamp < last.endTimestamp {
        guard window.startTimestamp == end, window.session == first.session else { return false }
        end = window.endTimestamp
        if end == last.endTimestamp { return true }
    }
    return false
}

private func marketChartIntervalMinutes(_ interval: String?) -> Int? {
    switch interval {
    case "1m": 1
    case "5m": 5
    case "15m": 15
    case "30m": 30
    case "60m": 60
    default: nil
    }
}

struct MarketChartSessionBreak: Equatable, Sendable {
    let previousTimestamp: Int64
    let currentTimestamp: Int64
    let label: String
}

func marketChartSessionBreak(points: [MarketChartPoint], chart: MarketChart) -> MarketChartSessionBreak? {
    guard let minutes = marketChartIntervalMinutes(chart.interval), points.count > 1 else { return nil }
    let duration = Int64(minutes) * 60_000
    let convention = chart.analysis.candleTimestamp
    for (previous, current) in zip(points, points.dropFirst()) {
        guard let first = chart.analysis.sessionWindows.first(where: { $0.contains(previous.timestamp, convention: convention) }),
              let last = chart.analysis.sessionWindows.first(where: { $0.contains(current.timestamp, convention: convention) }),
              first.tradingDate == last.tradingDate, first.endTimestamp < last.startTimestamp,
              first.session == "regular", last.session == "regular" else { continue }
        let previousEnd = convention == .intervalEnd ? previous.timestamp : min(previous.timestamp + duration, first.endTimestamp)
        let currentStart = convention == .intervalEnd ? current.timestamp - 60_000 : current.timestamp
        guard previousEnd == first.endTimestamp, currentStart == last.startTimestamp else { continue }
        return MarketChartSessionBreak(
            previousTimestamp: previous.timestamp, currentTimestamp: current.timestamp,
            label: ["CN", "HK", "JP"].contains(chart.market) ? "午间休市" : "日间休市"
        )
    }
    return nil
}

func marketChartXFraction(timestamp: Int64, firstTimestamp: Int64, lastTimestamp: Int64) -> CGFloat {
    guard lastTimestamp > firstTimestamp else { return 0 }
    return min(max(CGFloat(Double(timestamp - firstTimestamp) / Double(lastTimestamp - firstTimestamp)), 0), 1)
}

func marketChartXFractions(timestamps: [Int64], interval: String?) -> [CGFloat] {
    guard timestamps.count > 1 else { return timestamps.map { _ in 0.5 } }
    let maximumIntradayGap = marketChartIntervalMinutes(interval).map { Int64(max($0, 5)) * 60 * 1_000 }
    var positions = [Double](repeating: 0, count: timestamps.count)
    for index in 1..<timestamps.count {
        let elapsed = max(timestamps[index] - timestamps[index - 1], 0)
        let displayedElapsed = maximumIntradayGap.map { min(elapsed, $0) } ?? elapsed
        positions[index] = positions[index - 1] + Double(displayedElapsed)
    }
    guard let total = positions.last, total > 0 else { return positions.map { _ in 0 } }
    return positions.map { CGFloat($0 / total) }
}

func marketVolumeBarX(fraction: CGFloat, width: CGFloat, barWidth: CGFloat) -> CGFloat {
    let inset = min(max(barWidth / 2, 0), max(width / 2, 0))
    return min(max(width * fraction, inset), max(width - inset, inset))
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

    var apiInterval: String {
        switch self {
        case .day: "1m"
        case .week: "15m"
        case .month, .quarter, .year, .fiveYears, .maximum: "1d"
        }
    }

    var apiLimit: Int {
        switch self {
        case .day: 600
        case .week: 1_000
        case .month: 64
        case .quarter: 128
        case .year: 400
        case .fiveYears: 2_000
        case .maximum: 50_000
        }
    }

}

enum MarketChartPeriod: String, CaseIterable, Identifiable, Sendable {
    case intraday = "分时"
    case fiveDays = "5日"
    case minute1 = "1分"
    case minute5 = "5分"
    case minute15 = "15分"
    case minute30 = "30分"
    case minute60 = "60分"
    case daily = "日线"
    case weekly = "周线"
    case monthly = "月线"

    var id: Self { self }

    var sourceRange: MarketRange {
        switch self {
        case .intraday, .minute1, .minute5, .minute30, .minute60: .day
        case .fiveDays, .minute15: .week
        case .daily: .year
        case .weekly: .fiveYears
        case .monthly: .maximum
        }
    }

    var displayInterval: String {
        switch self {
        case .intraday, .minute1: "1m"
        case .fiveDays, .minute15: "15m"
        case .minute5: "5m"
        case .minute30: "30m"
        case .minute60: "60m"
        case .daily: "1d"
        case .weekly: "1wk"
        case .monthly: "1mo"
        }
    }

    var isIntraday: Bool {
        switch self {
        case .daily, .weekly, .monthly: false
        default: true
        }
    }

    var isMinute: Bool {
        switch self {
        case .minute1, .minute5, .minute15, .minute30, .minute60: true
        default: false
        }
    }

    var chartTitle: String {
        switch self {
        case .intraday: "分时走势"
        case .fiveDays: "5日走势"
        case .minute1: "1分钟走势"
        case .minute5: "5分钟走势"
        case .minute15: "15分钟走势"
        case .minute30: "30分钟走势"
        case .minute60: "60分钟走势"
        case .daily: "日线走势"
        case .weekly: "周线走势"
        case .monthly: "月线走势"
        }
    }

    var dateFormat: String {
        switch self {
        case .intraday, .minute1, .minute5, .minute30, .minute60: "HH:mm"
        case .fiveDays, .minute15: "MM-dd HH:mm"
        case .daily: "MM-dd"
        case .weekly: "yyyy-MM-dd"
        case .monthly: "yyyy-MM"
        }
    }
}

func marketChartForDisplay(
    _ chart: MarketChart, period: MarketChartPeriod, now: Date = Date()
) -> MarketChart? {
    guard chart.interval == period.sourceRange.apiInterval,
          let timeZone = TimeZone(identifier: chart.timezone) else { return nil }
    let expectedConvention: MarketChartTimestampConvention = chart.interval == "1m" ? .intervalEnd : chart.interval == "1d" ? .tradingDate : .intervalStart
    guard chart.analysis.candleTimestamp == expectedConvention else { return nil }
    if chart.interval == "1d", chart.analysis.aggregation != "none" {
        return nil
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    let visiblePoints = marketChartDisplayPoints(chart.candles, interval: chart.interval)
        .sorted { $0.timestamp < $1.timestamp }
    let sourcePoints: [MarketChartPoint]
    let invalidDateCount: Int
    if chart.interval == "1m" {
        guard chart.analysis.candleTimestamp == .intervalEnd,
              visiblePoints.allSatisfy({ $0.timestamp % 60_000 == 0 }),
              Set(visiblePoints.map(\.timestamp)).count == visiblePoints.count else { return nil }
        guard visiblePoints.allSatisfy({ point in
            chart.analysis.sessionWindows.contains { $0.contains(point.timestamp, convention: .intervalEnd) }
        }) else { return nil }
        sourcePoints = visiblePoints
        invalidDateCount = 0
    } else if chart.interval == "1d" {
        sourcePoints = marketNormalizedDailyChartPoints(visiblePoints, calendar: calendar)
        invalidDateCount = visiblePoints.count - sourcePoints.count
    } else {
        sourcePoints = visiblePoints
        invalidDateCount = 0
    }
    let candles: [MarketChartPoint]
    let includedDailyPoints: [MarketChartPoint]
    switch period {
    case .minute5, .minute30, .minute60:
        let minutes = marketChartIntervalMinutes(period.displayInterval)!
        candles = marketMinuteChartBuckets(sourcePoints, minutes: minutes, windows: chart.analysis.sessionWindows)
            .map { marketAggregatedChartPoint($0) }
        includedDailyPoints = []
    case .weekly, .monthly:
        let buckets = marketCalendarChartBuckets(sourcePoints, period: period, calendar: calendar)
        candles = buckets.map { marketAggregatedChartPoint($0) }
        includedDailyPoints = buckets.flatMap(\.points)
    case .daily:
        candles = sourcePoints
        includedDailyPoints = sourcePoints
    default:
        candles = sourcePoints
        includedDailyPoints = []
    }
    let hasProvisionalPoint = candles.contains { $0.state == "provisional" }
    let isCalendarAggregation = period == .weekly || period == .monthly
    let currentCalendarPeriod = isCalendarAggregation
        ? calendar.dateInterval(of: period == .weekly ? .weekOfYear : .month, for: now)?.start
        : nil
    let isCurrentCalendarPeriod = currentCalendarPeriod.map {
        candles.last?.timestamp == Int64(($0.timeIntervalSince1970 * 1_000).rounded())
    } ?? false
    let hasOpenMinuteBucket = marketChartIntervalMinutes(period.displayInterval).map { minutes in
        candles.last.map { Double($0.timestamp) / 1_000 + Double(minutes * 60) > now.timeIntervalSince1970 } ?? false
    } ?? false
    let hasInvalidData = chart.candles.contains { $0.state == "invalid" } || invalidDateCount > 0
    let hasSourceGaps = !chart.quality.missing.isEmpty
    let status: MarketChartQualityStatus = (hasInvalidData || hasSourceGaps) && chart.quality.status == .complete
        ? .partial : chart.quality.status
    // Coverage describes the real source samples, not the number of display buckets.
    let quality = MarketChartQuality(
        status: status,
        expected: chart.quality.expected,
        actual: chart.quality.actual,
        missing: chart.quality.missing,
        freshnessSeconds: chart.quality.freshnessSeconds,
        isFinal: chart.quality.isFinal && !hasProvisionalPoint && !isCurrentCalendarPeriod && !hasOpenMinuteBucket
    )
    let displayedTradingDate: String
    if chart.interval == "1d" {
        displayedTradingDate = includedDailyPoints.last?.tradingDate ?? ""
    } else {
        displayedTradingDate = chart.tradingDate
    }
    let periodReturn: MarketChartPeriodReturn?
    if period == .fiveDays || chart.interval == "1d" {
        periodReturn = marketDisplayedChartPeriodReturn(
            chart.interval == "1d" ? includedDailyPoints : sourcePoints,
            range: period.sourceRange.apiRange
        )
    } else {
        periodReturn = chart.periodReturn
    }
    return MarketChart(
        symbol: chart.symbol,
        market: chart.market,
        tradingDate: displayedTradingDate,
        timezone: chart.timezone,
        session: chart.session,
        interval: period.displayInterval,
        periodReturn: periodReturn,
        periodVolatility: chart.periodVolatility,
        quality: quality,
        quote: chart.quote,
        candles: candles,
        analysis: MarketChartAnalysis(
            aggregation: chart.analysis.aggregation,
            candleTimestamp: period.displayInterval == "1m" ? .intervalEnd : chart.interval == "1d" ? .tradingDate : .intervalStart,
            sessionWindows: chart.analysis.sessionWindows
        )
    )
}

private func marketDisplayedChartPeriodReturn(
    _ points: [MarketChartPoint], range: String
) -> MarketChartPeriodReturn? {
    guard let first = points.first, let last = points.last,
          first.close.isFinite, last.close.isFinite else { return nil }
    let change = last.close - first.close
    return MarketChartPeriodReturn(
        range: range,
        basis: "displayed-close-to-close",
        startPrice: first.close,
        endPrice: last.close,
        change: change,
        percent: first.close == 0 ? nil : change / first.close * 100,
        startTimestamp: first.timestamp,
        endTimestamp: last.timestamp
    )
}

private struct MarketChartAggregationBucket {
    let timestamp: Int64
    var points: [MarketChartPoint]
}

private func marketNormalizedDailyChartPoints(
    _ points: [MarketChartPoint], calendar: Calendar
) -> [MarketChartPoint] {
    let formatter = marketTradingDateFormatter(calendar: calendar)
    return points.compactMap { point in
        let sourceDate = Date(timeIntervalSince1970: Double(point.timestamp) / 1_000)
        let tradingDate = point.tradingDate ?? formatter.string(from: sourceDate)
        guard let date = formatter.date(from: tradingDate) else { return nil }
        return MarketChartPoint(
            timestamp: Int64((date.timeIntervalSince1970 * 1_000).rounded()),
            open: point.open, high: point.high, low: point.low, close: point.close,
            volume: point.volume, state: point.state, source: point.source,
            session: point.session, tradingDate: tradingDate
        )
    }
    .sorted { $0.timestamp < $1.timestamp }
}

private func marketMinuteChartBuckets(
    _ points: [MarketChartPoint], minutes: Int, windows: [MarketChartSessionWindow]
) -> [MarketChartAggregationBucket] {
    let duration = Int64(minutes) * 60_000
    var buckets: [MarketChartAggregationBucket] = []
    for point in points {
        guard let window = windows.first(where: { $0.contains(point.timestamp, convention: .intervalEnd) }) else { continue }
        let timestamp = window.startTimestamp + (point.timestamp - 1 - window.startTimestamp) / duration * duration
        if buckets.last?.timestamp == timestamp {
            buckets[buckets.count - 1].points.append(point)
        } else {
            buckets.append(MarketChartAggregationBucket(timestamp: timestamp, points: [point]))
        }
    }
    return buckets
}

private func marketCalendarChartBuckets(
    _ points: [MarketChartPoint], period: MarketChartPeriod, calendar: Calendar
) -> [MarketChartAggregationBucket] {
    let component: Calendar.Component = period == .weekly ? .weekOfYear : .month
    var buckets: [MarketChartAggregationBucket] = []
    for point in points {
        let date = Date(timeIntervalSince1970: Double(point.timestamp) / 1_000)
        guard let start = calendar.dateInterval(of: component, for: date)?.start else { continue }
        let timestamp = Int64((start.timeIntervalSince1970 * 1_000).rounded())
        if buckets.last?.timestamp == timestamp {
            buckets[buckets.count - 1].points.append(point)
        } else {
            buckets.append(MarketChartAggregationBucket(timestamp: timestamp, points: [point]))
        }
    }
    return buckets
}

private func marketTradingDateFormatter(calendar: Calendar) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    return formatter
}

private func marketAggregatedChartPoint(
    _ bucket: MarketChartAggregationBucket
) -> MarketChartPoint {
    let first = bucket.points[0]
    let last = bucket.points[bucket.points.count - 1]
    let volumes = bucket.points.compactMap(\.volume)
    let sources = Set(bucket.points.map(\.source)).sorted()
    let sessions = Set(bucket.points.map(\.session))
    return MarketChartPoint(
        timestamp: bucket.timestamp,
        open: first.open,
        high: bucket.points.map(\.high).max()!,
        low: bucket.points.map(\.low).min()!,
        close: last.close,
        volume: volumes.isEmpty ? nil : volumes.reduce(0, +),
        state: bucket.points.contains { $0.state == "provisional" } ? "provisional" : last.state,
        source: sources.joined(separator: ","),
        session: sessions.count == 1 ? first.session : nil
    )
}

func marketAxisDigits(values: [Double]) -> Int {
    guard let low = values.min(), let high = values.max(), high > low else { return 2 }
    let step = (high - low) / 4
    if step >= 10 { return 0 }
    if step >= 1 { return 1 }
    guard step > 0 else { return 10 }
    return min(max(Int(ceil(-log10(step))), 2), 10)
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
    guard !target.isNaN else { return 0 }

    // Chart fractions are ordered by timestamp. Only the neighbors can be closest.
    func firstIndex(before end: Int, matching predicate: (CGFloat) -> Bool) -> Int {
        var lower = 0
        var upper = end
        while lower < upper {
            let mid = lower + (upper - lower) / 2
            if predicate(fractions[mid]) {
                upper = mid
            } else {
                lower = mid + 1
            }
        }
        return lower
    }

    let right = firstIndex(before: fractions.count) { $0 >= target }
    guard right > 0 else { return right }
    let leftDistance = target - fractions[right - 1]
    if right < fractions.count, fractions[right] - target < leftDistance {
        return right
    }

    // Return the first equally close point when positions or distances tie.
    return firstIndex(before: right) { target - $0 <= leftDistance }
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
