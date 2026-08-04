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
    var referenceIndices: [MarketQuote]
    let realtimeProxies: [MarketRealtimeProxyDefinition]
    var metrics: [MarketQuote]
    var components: [MarketQuote]
    var componentsByRegion: [String: [MarketQuote]]
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
        case dataContract, definitionVersion, generatedAt, refreshIntervalMs, coreIndices, referenceIndices, realtimeProxies
        case metrics, components, componentsByRegion, crypto
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
        components = try values.decodeLossyQuotes(forKey: .components)
        componentsByRegion = try values.decodeIfPresent([String: [MarketQuote]].self, forKey: .componentsByRegion) ?? [:]
        crypto = try values.decodeLossyQuotes(forKey: .crypto)
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
        replace(quote, in: &components)
        for region in Array(componentsByRegion.keys) {
            replace(quote, in: &componentsByRegion[region, default: []])
        }
        replace(quote, in: &crypto)
        for key in indexSessions.map({ Array($0.keys) }) ?? [] where indexSessions?[key]?.symbol == quote.symbol {
            var quotes = [indexSessions?[key]].compactMap { $0 }
            replace(quote, in: &quotes)
            indexSessions?[key] = quotes.first
        }
    }

    func quote(symbol: String) -> MarketQuote? {
        coreIndices.first(where: { $0.symbol == symbol })
            ?? referenceIndices.first(where: { $0.symbol == symbol })
            ?? metrics.first(where: { $0.symbol == symbol })
            ?? components.first(where: { $0.symbol == symbol })
            ?? componentsByRegion.values.lazy.flatMap({ $0 }).first(where: { $0.symbol == symbol })
            ?? crypto.first(where: { $0.symbol == symbol })
    }

    var allRegionalComponents: [MarketQuote] {
        var seen: Set<String> = []
        return componentsByRegion.values
            .flatMap { $0 }
            .filter { seen.insert($0.symbol).inserted }
    }

    private func replace(_ quote: MarketQuote, in quotes: inout [MarketQuote]) {
        guard let index = quotes.firstIndex(where: { $0.symbol == quote.symbol }) else { return }
        var next = quote
        if next.trend.isEmpty {
            next.trend = marketAppendingLiveValue(next.price, to: quotes[index].trend)
        }
        quotes[index] = next
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

struct MarketCompanyLogoResponse: Decodable {
    let data: MarketCompanyLogo
}

struct MarketCompanyLogo: Decodable {
    let found: Bool
    let url: String
}

struct MarketCompanyFinancialsResponse: Decodable {
    let data: MarketCompanyFinancials
}

struct MarketCompanyFinancials: Decodable {
    let symbol: String
    let netIncomeTTM: Double?
    let currency: String
    let period: String
    let fiscalYear: String?
    let dataSource: String
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
    let quality: MarketQuoteQuality?
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
        if hasSuspiciousIndexMove { return "待核验" }
        return String(format: "%@%.2f%%", percentValue >= 0 ? "+" : "−", abs(percentValue))
    }

    var changeValue: Double {
        guard let previousClose else { return 0 }
        return price - previousClose
    }

    var isUp: Bool { percentValue >= 0 }

    var tradingSession: MarketTradingSession {
        MarketTradingSession(rawValue: marketSession, legacyIsNightSession: isNightSession)
    }

    var hasActiveExtendedSessionQuote: Bool {
        sessionPrice != nil && tradingSession.isExtended
    }

    var formattedSessionPercent: String? {
        sessionChangePercent.map { String(format: "%@%.2f%%", $0 >= 0 ? "+" : "−", abs($0)) }
    }

    enum CodingKeys: String, CodingKey {
        case symbol, name, displayName, instrumentType, proxyFor, referenceSymbol, historicalSymbol, displayMode
        case price, openPrice, previousClose, high, low, pe, marketCap, volume, turnover
        case dataSource, delaySeconds, marketSession, isNightSession, sessionPrice, sessionChangePercent, sessionDataSource
        case changePercent, timestamp, quality, trend, nightTrend, stale
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
        self.quality = quality
        self.trend = trend
        self.nightTrend = nightTrend
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
        quality = try values.decodeIfPresent(MarketQuoteQuality.self, forKey: .quality)
        trend = try values.decodeIfPresent([Double].self, forKey: .trend) ?? []
        nightTrend = try values.decodeIfPresent([Double].self, forKey: .nightTrend) ?? []
        stale = try values.decodeIfPresent(Bool.self, forKey: .stale)
    }
}

enum MarketTradingSession: Equatable {
    case regular, premarket, postmarket, overnight, closed, alwaysOpen, unknown

    init(rawValue: String?, legacyIsNightSession: Bool? = nil) {
        switch rawValue?.lowercased() {
        case "regular": self = .regular
        case "pre", "premarket": self = .premarket
        case "post", "after": self = .postmarket
        case "overnight": self = .overnight
        case "always-open": self = .alwaysOpen
        case "closed": self = legacyIsNightSession == true ? .overnight : .closed
        default: self = legacyIsNightSession == true ? .overnight : .unknown
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
            displayName: current?.displayName,
            instrumentType: current?.instrumentType,
            proxyFor: current?.proxyFor,
            referenceSymbol: current?.referenceSymbol,
            historicalSymbol: current?.historicalSymbol,
            displayMode: current?.displayMode,
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
    let transcriptStatus: String
    let analysis: String
    let evidence: [String]
    let analysisSource: String
    let model: String
    let stale: Bool
    let ageHours: Double?

    private enum CodingKeys: String, CodingKey {
        case nickname, awemeId, description, url, coverUrl, createdAt, label, reasons
        case transcriptStatus, analysis, evidence, analysisSource, model, stale, ageHours
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

struct MarketChartSessionBreak: Equatable {
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

    var freshnessLabel: String {
        if tradingSession == .alwaysOpen { return tradingSession.displayLabel }
        if let delaySeconds, delaySeconds > 0 { return "延迟\(max(1, delaySeconds / 60))分钟" }
        if tradingSession == .closed {
            return marketAsOfTimestamp.map { "截至 \(marketShortTimestamp($0))" } ?? "已收盘"
        }
        if stale == true { return "数据延迟" }
        return tradingSession.displayLabel
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
        default: symbol
        }
    }
}

func marketActiveIndexSession(_ quote: MarketQuote?) -> MarketQuote? {
    guard let quote else { return nil }
    return quote.tradingSession.isActivelyTrading && quote.tradingSession != .alwaysOpen ? quote : nil
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
