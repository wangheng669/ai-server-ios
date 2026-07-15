import Foundation

struct MarketDashboardResponse: Decodable {
    let success: Bool
    let data: MarketDashboard
}

struct MarketDashboard: Codable {
    let dataContract: String
    let generatedAt: String
    let refreshIntervalMs: Int
    var coreIndices: [MarketQuote]
    var metrics: [MarketQuote]
    var components: [MarketQuote]
    let componentsMeta: MarketComponentsMeta?
    let freshness: MarketDashboardFreshness?
    let missingSymbols: [String]
    let ashareOverview: MarketAShareOverview?
    let sentiment: MarketSentiment?

    mutating func replace(_ quote: MarketQuote) {
        replace(quote, in: &coreIndices)
        replace(quote, in: &metrics)
        replace(quote, in: &components)
    }

    private func replace(_ quote: MarketQuote, in quotes: inout [MarketQuote]) {
        guard let index = quotes.firstIndex(where: { $0.symbol == quote.symbol }) else { return }
        var next = quote
        if next.trend.isEmpty { next.trend = quotes[index].trend }
        quotes[index] = next
    }
}

struct MarketComponentsMeta: Codable {
    let label: String
    let selectionBasis: String
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
    let dataSource: String?
    let delaySeconds: Int?
    let marketSession: String?
    let changePercent: String?
    let timestamp: Int64?
    var trend: [Double]
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

    enum CodingKeys: String, CodingKey {
        case symbol, name, price, openPrice, previousClose, high, low, pe, marketCap, volume
        case dataSource, delaySeconds, marketSession, changePercent, timestamp, trend, stale
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
        dataSource = try values.decodeIfPresent(String.self, forKey: .dataSource)
        delaySeconds = try values.decodeIfPresent(Int.self, forKey: .delaySeconds)
        marketSession = try values.decodeIfPresent(String.self, forKey: .marketSession)
        changePercent = try values.decodeIfPresent(String.self, forKey: .changePercent)
        timestamp = try values.decodeIfPresent(Int64.self, forKey: .timestamp)
        trend = try values.decodeIfPresent([Double].self, forKey: .trend) ?? []
        stale = try values.decodeIfPresent(Bool.self, forKey: .stale)
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
    let source: String?
    let delaySeconds: Int?
    let marketSession: String?
    let previousClose: Double?
    let latestPrice: Double?
    let latestTimestamp: Int64?
    let high: Double?
    let low: Double?
    let points: [MarketChartPoint]
}

struct MarketChartPoint: Decodable, Identifiable {
    var id: Int64 { timestamp }
    let timestamp: Int64
    let value: Double?
    let open: Double?
    let high: Double?
    let low: Double?
    let close: Double?
    let volume: Double?

    var displayValue: Double? { close ?? value }
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

    var apiInterval: String { self == .day || self == .week ? "1m" : "1d" }
}

extension MarketQuote {
    var freshnessLabel: String {
        if marketSession == "closed" {
            return timestamp.map { "截至 \(marketShortTimestamp($0))" } ?? "已收盘"
        }
        if let delaySeconds, delaySeconds > 0 { return "延迟\(max(1, delaySeconds / 60))分钟" }
        if stale == true { return "数据延迟" }
        return marketSession == "regular" ? "交易中" : "行情更新"
    }

    var displayCode: String {
        switch symbol {
        case "^GSPC": "SPX"
        case "^NDX": "NDX"
        case "^DJI": "DJI"
        case "000001.SS": "000001.SH"
        case "000300.SS": "000300.SH"
        case "000688.SS": "000688.SH"
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
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000))
}

func marketISODate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}
