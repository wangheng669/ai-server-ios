import SwiftUI

struct StockSessionQuotes {
    struct Price {
        let value: Double
        let percent: Double
        var timestamp: Int64?
    }

    struct Column: Identifiable {
        var id: String { title }
        let title: String
        let price: Price?
        let highlighted: Bool
    }

    let columns: [Column]

    init(quote: MarketQuote, chart: MarketChart?, extendedSession: MarketTradingSession, isCurrent: Bool) {
        let session = quote.tradingSession
        let regular = Price(value: quote.price, percent: quote.percentValue)
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
            Column(title: "盘后", price: post, highlighted: isCurrent && session == .postmarket && post != nil),
            Column(title: Self.extendedTitle(extendedSession, indicative: quote.hasIndicativeOvernightPrice),
                   price: extended, highlighted: isCurrent && extended != nil),
        ]
    }

    static func extendedTitle(_ session: MarketTradingSession, indicative: Bool) -> String {
        if session == .premarket { return "盘前" }
        return indicative ? "夜盘参考" : "夜盘"
    }

    static func sourceNote(indicative: Bool) -> String {
        indicative ? "盘后末价取已确认分钟线 · 夜盘参考取买卖中间价" : "盘后末价取已确认分钟线"
    }

    private static func activePrice(_ quote: MarketQuote, session: MarketTradingSession) -> Price? {
        guard quote.tradingSession == session, let price = quote.sessionPrice, price.isFinite, price > 0 else { return nil }
        return Price(value: price, percent: quote.marketDisplayPercentValue, timestamp: quote.marketAsOfTimestamp)
    }
}

extension MarketQuote {
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
        let price = quote.map {
            $0.value.formatted(.number.precision(.fractionLength(marketPriceDigits($0.value, symbol: symbol))))
        } ?? "—"
        let percent = quote.map {
            String(format: "%@%.2f%%", $0.percent >= 0 ? "+" : "−", abs($0.percent))
        }
        let tint = quote.map { $0.percent >= 0 ? InvestmentDesign.gain : InvestmentDesign.loss } ?? muted
        return VStack(alignment: showsTitle ? .leading : .trailing, spacing: showsTitle ? 4 : 2) {
            if showsTitle {
                Text(column.title).font(.caption.weight(.medium)).foregroundStyle(muted)
            }
            Text(price)
                .font(showsTitle ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(quote == nil ? muted : .primary)
            if let percent {
                Text(percent).font(.caption2.weight(.medium)).foregroundStyle(tint)
            }
            if let time {
                Text(time).font(showsTitle ? .caption2 : .system(size: 9)).foregroundStyle(muted)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .padding(.vertical, showsTitle ? 8 : 4)
        .padding(.horizontal, showsTitle ? 9 : 4)
        .frame(maxWidth: .infinity, alignment: showsTitle ? .leading : .trailing)
        .background {
            if column.highlighted {
                RoundedRectangle(cornerRadius: 6).fill(InvestmentDesign.accent.opacity(0.08))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([column.title, quote == nil ? "暂无行情" : price, percent, time].compactMap { $0 }.joined(separator: "，"))
    }
}

extension MarketChart {
    func stockAfterHoursEnd(for quote: MarketQuote) -> MarketChartPoint? {
        guard market == "US", interval == "1m", self.quote.price == quote.price,
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
    func dayChartForSessionQuotes(symbol: String) -> MarketChart? {
        guard let snapshot = chartSnapshot(symbol: symbol, range: .day) else { return nil }
        if snapshot.isRestored {
            guard let quote = quote(symbol: symbol),
                  quote.quality?.tradingDate == snapshot.chart.tradingDate,
                  let timestamp = quote.timestamp, timestamp == snapshot.chart.quote.providerTimestamp,
                  quote.price == snapshot.chart.quote.price else { return nil }
        }
        return snapshot.chart
    }
}
