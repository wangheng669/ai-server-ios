import SwiftUI

struct MarketStockPrice {
    let amount: Double
    let currency: String?
    let change: Double?
    let label: String

    var changePercent: Double? { change.flatMap { $0.isFinite ? $0 : nil } }

    var changeColor: Color {
        guard let changePercent else { return .secondary }
        if changePercent > 0 { return InvestmentDesign.gain }
        if changePercent < 0 { return InvestmentDesign.loss }
        return .secondary
    }

    func formattedAmount(symbol: String) -> String {
        let value = amount.formatted(.number.precision(.fractionLength(marketPriceDigits(amount, symbol: symbol))))
        return [value, currency].compactMap { $0 }.joined(separator: " ")
    }
}

@MainActor
@Observable
final class MarketStockQuoteStore {
    struct Snapshot {
        let regularQuote: MarketStockPrice?
        let history: MarketStockHistory?
        let loadedAt: Date
    }

    private(set) var snapshots: [String: Snapshot] = [:]
    private let service: MarketService
    @ObservationIgnored private var requests: [String: Task<Void, Never>] = [:]

    init(service: MarketService) {
        self.service = service
    }

    func currentQuote(for symbol: String, marketStore: MarketStore) -> MarketStockPrice? {
        if let regularQuote = snapshots[symbol]?.regularQuote { return regularQuote }
        guard let quote = marketStore.quote(symbol: symbol), quote.stale != true,
              quote.tradingSession == .regular || quote.hasActiveExtendedSessionQuote,
              quote.marketDisplayPrice.isFinite, quote.marketDisplayPrice > 0,
              let timestamp = quote.marketAsOfTimestamp, timestamp > 0 else { return nil }
        let session = quote.hasIndicativeOvernightPrice ? "夜盘参考" : quote.tradingSession.displayLabel
        let status = marketStore.isShowingCachedSnapshot ? "缓存" : quote.hasDelayedSessionPrice ? "延迟" : nil
        let label = [session, status, marketShortTimestamp(timestamp)].compactMap { $0 }.joined(separator: " · ")
        return MarketStockPrice(amount: quote.marketDisplayPrice, currency: quote.currency,
                               change: quote.marketDisplayPercentValue, label: label)
    }

    func confirmedClose(for symbol: String, marketStore: MarketStore) -> MarketStockPrice? {
        if let price = snapshots[symbol]?.history?.confirmedClose { return price }
        guard let quote = marketStore.quote(symbol: symbol), quote.stale != true, quote.tradingSession == .closed,
              quote.price.isFinite, quote.price > 0, let date = quote.quality?.tradingDate else { return nil }
        let status = marketStore.isShowingCachedSnapshot ? " · 缓存" : ""
        return MarketStockPrice(amount: quote.price, currency: quote.currency, change: quote.percentValue,
                               label: "\(date) 收盘\(status)")
    }

    func runUpdates(symbols: [String]) async {
        while !Task.isCancelled {
            await runWithLimitedConcurrency(symbols) { symbol in
                await self.load(symbol: symbol)
            }
            do { try await Task.sleep(for: .seconds(60)) }
            catch { return }
        }
    }

    func load(symbol: String) async {
        guard !Task.isCancelled else { return }
        if let request = requests[symbol] {
            await request.value
            return
        }
        if let snapshot = snapshots[symbol], Date().timeIntervalSince(snapshot.loadedAt) < 30 { return }
        let request = Task {
            defer { requests[symbol] = nil }
            let chart = try? await service.recentDailyCloses(symbol: symbol)
            record(chart, for: symbol)
        }
        requests[symbol] = request
        await request.value
    }

    private func record(_ chart: MarketChart?, for symbol: String) {
        guard let chart, chart.symbol == symbol, let history = MarketStockHistory(chart: chart) else {
            snapshots[symbol] = Snapshot(regularQuote: nil, history: snapshots[symbol]?.history, loadedAt: Date())
            return
        }
        let regularQuote: MarketStockPrice?
        if MarketTradingSession(rawValue: chart.session) == .regular,
           let amount = chart.quote.price, amount.isFinite, amount > 0,
           let timestamp = chart.quote.providerTimestamp, timestamp > 0 {
            regularQuote = MarketStockPrice(amount: amount, currency: history.currency, change: chart.quote.changePercent,
                                           label: "盘中报价 · \(marketShortTimestamp(timestamp))")
        } else {
            regularQuote = nil
        }
        snapshots[symbol] = Snapshot(regularQuote: regularQuote, history: history, loadedAt: Date())
    }
}

struct MarketStockHistory {
    let currency: String
    let bars: [MarketChartPoint]
    let isComplete: Bool

    init?(chart: MarketChart) {
        guard chart.interval == "1d", let timeZone = TimeZone(identifier: chart.timezone) else { return nil }
        let closingMinute: Int
        switch chart.market {
        case "US": (currency, closingMinute) = ("USD", 16 * 60)
        case "HK": (currency, closingMinute) = ("HKD", 16 * 60 + 10)
        default: return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        guard let year = now.year, let month = now.month, let day = now.day,
              let hour = now.hour, let minute = now.minute else { return nil }
        let localDate = String(format: "%04d-%02d-%02d", year, month, day)
        // Some feeds publish a same-day daily bar while continuous trading is still open.
        let acceptsToday = chart.quality.isFinal && hour * 60 + minute >= closingMinute
        bars = chart.candles.filter {
            guard let date = $0.tradingDate, $0.state == "confirmed", $0.close.isFinite, $0.close > 0 else { return false }
            return date < localDate || (date == localDate && acceptsToday)
        }.sorted { $0.timestamp < $1.timestamp }
        isComplete = chart.quality.status == .complete
    }

    var confirmedClose: MarketStockPrice? {
        guard let latest = bars.last, let date = latest.tradingDate else { return nil }
        let previous = isComplete ? bars.dropLast().last : nil
        let change = previous.map { (latest.close / $0.close - 1) * 100 }
        return MarketStockPrice(amount: latest.close, currency: currency, change: change, label: "\(date) 收盘")
    }
}
