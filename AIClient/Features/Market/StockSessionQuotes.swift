import SwiftUI

struct StockSessionQuotes {
    struct Price {
        let value: Double
        let percent: Double?
        var timestamp: Int64?
        var isDelayed = false
    }

    struct Column: Identifiable {
        var id: String { title }
        let title: String
        let price: Price?
        let highlighted: Bool
        var emptyLabel = "暂无报价"
    }

    let columns: [Column]

    init(quote: MarketQuote, chart: MarketChart?, afterHoursEmptyLabel: String,
         extendedSession: MarketTradingSession, isCurrent: Bool) {
        let session = quote.tradingSession
        let regular = Price(value: quote.price, percent: quote.percentValue,
                            isDelayed: session == .regular && quote.hasDelayedSessionPrice)
        let post: Price?
        if session == .postmarket {
            post = Self.activePrice(quote, session: .postmarket)
        } else if session != .regular, quote.price > 0, let point = chart?.stockAfterHoursEnd(for: quote) {
            post = Price(value: point.close, percent: (point.close / quote.price - 1) * 100, timestamp: point.timestamp)
        } else {
            post = nil
        }
        let extended = Self.activePrice(quote, session: extendedSession)
        columns = [
            Column(title: session == .regular ? "常规盘" : "常规收盘", price: regular,
                   highlighted: isCurrent && session == .regular),
            Column(title: "盘后", price: post, highlighted: isCurrent && session == .postmarket && post != nil,
                   emptyLabel: afterHoursEmptyLabel),
            Column(title: Self.extendedTitle(extendedSession, indicative: quote.hasIndicativeOvernightPrice),
                   price: extended, highlighted: isCurrent && extended != nil),
        ]
    }

    static func extendedTitle(_ session: MarketTradingSession, indicative: Bool) -> String {
        if session == .premarket { return "盘前" }
        return indicative ? "夜盘参考" : "夜盘"
    }

    static func sourceNote(indicative: Bool) -> String {
        indicative ? "盘后收盘取已确认分钟线 · 夜盘参考取买卖中间价" : "盘后收盘取已确认分钟线"
    }

    private static func activePrice(_ quote: MarketQuote, session: MarketTradingSession) -> Price? {
        guard quote.tradingSession == session, let price = quote.sessionPrice, price.isFinite, price > 0 else { return nil }
        return Price(value: price, percent: quote.marketDisplayPercentValue, timestamp: quote.marketAsOfTimestamp,
                     isDelayed: quote.hasDelayedSessionPrice)
    }
}

extension MarketQuote {
    var hasDelayedSessionPrice: Bool {
        quality?.status == "delayed" || visibleDelayMinutes != nil
    }

    var hasIndicativeOvernightPrice: Bool {
        tradingSession == .overnight && sessionDataSource == "AlpacaOvernightIndicative"
    }
}

struct StockSessionPriceCell: View {
    let column: StockSessionQuotes.Column
    let symbol: String
    var muted: Color = .secondary
    var showsTitle = false

    var body: some View {
        let quote = column.price
        let time = quote?.timestamp.map(marketShortTimestamp)
        let detail = [quote?.isDelayed == true ? "延迟" : nil, time].compactMap { $0 }.joined(separator: " · ")
        let price = quote.map {
            $0.value.formatted(.number.precision(.fractionLength(marketPriceDigits($0.value, symbol: symbol))))
        } ?? column.emptyLabel
        let percent = quote?.percent
        let percentLabel = quote.map { $0.percent.map(marketFormattedChangePercent) ?? "涨跌暂缺" }
        let tint: Color = percent.map { $0 > 0 ? InvestmentDesign.gain : $0 < 0 ? InvestmentDesign.loss : muted } ?? muted
        return VStack(alignment: showsTitle ? .leading : .trailing, spacing: showsTitle ? 4 : 2) {
            if showsTitle {
                Text(column.title).font(.caption.weight(.medium)).foregroundStyle(muted)
            }
            Text(price)
                .font(quote == nil ? .caption2 : (showsTitle ? .title3.weight(.semibold) : .subheadline.weight(.semibold)))
                .foregroundStyle(quote == nil ? muted : .primary)
            if let percentLabel {
                Text(percentLabel)
                    .font(.caption2.weight(.medium)).foregroundStyle(tint)
            }
            if !detail.isEmpty {
                Text(detail).font(showsTitle ? .caption2 : .system(size: 9)).foregroundStyle(muted)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .padding(.vertical, showsTitle ? 8 : 4)
        .padding(.horizontal, showsTitle ? 9 : 4)
        .frame(maxWidth: .infinity, alignment: showsTitle ? .leading : .trailing)
        .background {
            if column.highlighted && quote?.isDelayed != true {
                RoundedRectangle(cornerRadius: 6).fill(InvestmentDesign.accent.opacity(0.08))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([column.title, price, percentLabel,
                             quote?.isDelayed == true ? "延迟" : nil, time].compactMap { $0 }.joined(separator: "，"))
    }
}

extension MarketChart {
    func matchesAfterHoursAnchor(for quote: MarketQuote) -> Bool {
        guard self.quote.price == quote.price else { return false }
        let session: String
        switch quote.tradingSession {
        case .premarket: session = "pre"
        case .overnight: session = "overnight"
        case .closed: return quote.quality?.tradingDate == tradingDate
        default: return false
        }
        guard let timestamp = quote.marketAsOfTimestamp,
              let active = analysis.sessionWindows.last(where: {
                  $0.session == session && $0.startTimestamp <= timestamp && timestamp <= $0.endTimestamp
              }),
              let regular = analysis.sessionWindows.last(where: {
                  $0.session == "regular" && $0.endTimestamp <= active.startTimestamp
              }) else { return false }
        return regular.tradingDate == tradingDate
    }

    func stockAfterHoursEnd(for quote: MarketQuote) -> MarketChartPoint? {
        guard market == "US", interval == "1m", matchesAfterHoursAnchor(for: quote),
              let window = analysis.sessionWindows.last(where: { $0.session == "post" && $0.tradingDate == tradingDate }),
              let regular = analysis.sessionWindows.last(where: { $0.session == "regular" && $0.tradingDate == tradingDate }),
              candles.contains(where: { $0.session == "regular" && regular.contains($0.timestamp, convention: analysis.candleTimestamp) })
        else { return nil }
        return candles.last {
            $0.session == "post" && $0.state == "confirmed" && ($0.volume ?? 0) > 0 &&
                $0.close.isFinite && $0.close > 0 && window.contains($0.timestamp, convention: analysis.candleTimestamp)
        }
    }
}

extension MarketStore {
    func stockSessionQuotes(for quote: MarketQuote, chartSymbol: String, extendedSession: MarketTradingSession,
                            isCurrent: Bool) -> StockSessionQuotes {
        let chart = chart(symbol: chartSymbol, range: .day)
        let emptyLabel: String
        switch quote.tradingSession {
        case .regular:
            emptyLabel = "未开始"
        case .postmarket, .unknown, .alwaysOpen:
            emptyLabel = "暂无报价"
        case .overnight, .premarket, .closed:
            if isLoadingChart(symbol: chartSymbol, range: .day) {
                emptyLabel = "加载中"
            } else if chartError(symbol: chartSymbol, range: .day) != nil {
                emptyLabel = "加载失败"
            } else {
                emptyLabel = chartSnapshot(symbol: chartSymbol, range: .day) == nil ? "待加载" : "无确认价"
            }
        }
        return StockSessionQuotes(quote: quote, chart: chart, afterHoursEmptyLabel: emptyLabel,
                                  extendedSession: extendedSession, isCurrent: isCurrent)
    }

    func missingAfterHoursSymbols(_ symbols: [String]) -> [String] {
        symbols.filter { symbol in
            guard let quote = quote(symbol: symbol) else { return false }
            return chart(symbol: symbol, range: .day)?.stockAfterHoursEnd(for: quote) == nil
        }
    }
}

struct MarketLastSessionTradeNote: View {
    let trade: MarketLastSessionTrade
    let symbol: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let date = Date(timeIntervalSince1970: Double(trade.timestamp) / 1_000)
            let minutes = max(0, Int(timeline.date.timeIntervalSince(date) / 60))
            let price = trade.price.formatted(.number.precision(.fractionLength(
                marketPriceDigits(trade.price, symbol: symbol)
            )))
            Text("最近成交 \(price) · \(date.formatted(date: .omitted, time: .shortened)) · \(minutes) 分钟前 · \(trade.source)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("market-last-session-trade-\(symbol)")
    }
}
