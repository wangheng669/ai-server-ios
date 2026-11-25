import Charts
import SwiftUI

struct TodayStockDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var period = Period.recent
    @State private var histories: [Period: HistoryResult] = [:]
    @State private var retryAttempt = 0

    let stock: TodayCompanyStock
    let stockQuotes: TodayStockQuoteStore
    let marketStore: MarketStore

    private enum Period: String, CaseIterable, Identifiable {
        case recent = "近5日", month = "1月", quarter = "3月"
        var id: Self { self }

        var range: MarketRange? {
            switch self {
            case .recent: nil
            case .month: .month
            case .quarter: .quarter
            }
        }
    }

    private enum HistoryResult {
        case loaded(TodayStockHistory)
        case unavailable
        case failed
    }

    private struct HistoryRequest: Hashable {
        let period: Period
        let attempt: Int
    }

    private var snapshot: TodayStockQuoteStore.Snapshot? { stockQuotes.snapshots[stock.symbol] }

    var body: some View {
        let request = HistoryRequest(period: period, attempt: retryAttempt)
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    quotes
                    historySection
                }
                .frame(maxWidth: 540)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(TodayBriefStyle.surface)
        .accessibilityIdentifier("today-stock-detail-\(stock.symbol)")
        .task(id: request) { await loadHistory(for: request.period) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stock.name)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("\(stock.symbol) · \(stock.symbol.hasSuffix(".HK") ? "港股" : "美股")")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭股价详情")
                .accessibilityIdentifier("today-stock-detail-close")
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { TodayBriefStyle.rule.frame(height: 1) }
    }

    @ViewBuilder
    private var quotes: some View {
        let current = stockQuotes.currentQuote(for: stock.symbol, marketStore: marketStore)
        let close = snapshot?.history?.confirmedClose
        if let current, let close {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    quoteTile("最新报价", current, emphasized: true)
                    quoteTile("最近收盘", close)
                }
                VStack(spacing: 10) {
                    quoteTile("最新报价", current, emphasized: true)
                    quoteTile("最近收盘", close)
                }
            }
        } else if let current {
            quoteTile("最新报价", current, emphasized: true)
        } else if let close {
            quoteTile("最近收盘", close, emphasized: true)
        } else {
            Text(snapshot == nil ? "正在读取股价" : "股价暂缺")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
                .padding(.horizontal, 14)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func quoteTile(_ title: String, _ price: TodayStockPrice, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(price.formattedAmount(symbol: stock.symbol))
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let change = price.changePercent {
                Text(marketFormattedChangePercent(change))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(price.changeColor)
                    .accessibilityLabel("涨跌幅 \(marketFormattedChangePercent(change))")
            }
            Text(price.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .monospacedDigit()
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            emphasized ? TodayBriefStyle.accent.opacity(0.08) : Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .accessibilityElement(children: .combine)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("收盘走势")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Picker("走势区间", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("today-stock-detail-period")
            historyContent
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        let result = period == .recent
            ? snapshot.map { $0.history.map(HistoryResult.loaded) ?? .unavailable }
            : histories[period]
        switch result {
        case .loaded(let history) where !history.bars.isEmpty:
            TodayStockHistoryChart(history: history, symbol: stock.symbol, barLimit: period == .recent ? 5 : nil)
                .id(period)
        case .loaded, .unavailable:
            historyNotice("此区间暂无确认收盘记录")
        case .failed:
            historyNotice("走势读取失败")
        case nil:
            ProgressView("正在读取走势")
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 180)
        }
    }

    private func historyNotice(_ message: String) -> some View {
        VStack(spacing: 10) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if period.range != nil {
                Button("重新读取") {
                    histories[period] = nil
                    retryAttempt += 1
                }
                .buttonStyle(.bordered)
                .tint(TodayBriefStyle.accent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func loadHistory(for period: Period) async {
        guard let range = period.range, histories[period] == nil else { return }
        let service = MarketService(baseURL: ServerConfiguration.currentURL, session: .shared)
        let chart = try? await service.chart(symbol: stock.symbol, range: range)
        guard !Task.isCancelled else { return }
        if let chart, chart.symbol == stock.symbol, let history = TodayStockHistory(chart: chart) {
            histories[period] = .loaded(history)
        } else {
            histories[period] = .failed
        }
    }
}

private struct TodayStockHistoryChart: View {
    @State private var selection: Double?

    let history: TodayStockHistory
    let symbol: String
    let barLimit: Int?

    private var bars: [MarketChartPoint] {
        guard let barLimit else { return history.bars }
        return Array(history.bars.suffix(barLimit))
    }

    private var displayedBar: MarketChartPoint? {
        guard let selection else { return bars.last }
        return bars.min { abs(Double($0.timestamp) - selection) < abs(Double($1.timestamp) - selection) }
    }

    private var ticks: [Double] {
        guard bars.count > 2 else { return bars.map { Double($0.timestamp) } }
        return [bars[0], bars[bars.count / 2], bars[bars.count - 1]].map { Double($0.timestamp) }
    }

    var body: some View {
        let bounds = marketSparklineBounds(bars.map(\.close), minimumRelativeRange: 0.012)
        let inset = (bounds.upper - bounds.lower) * 0.12
        let selectedBar = selection == nil ? nil : displayedBar

        VStack(alignment: .leading, spacing: 10) {
            if let displayedBar, let date = displayedBar.tradingDate {
                let price = TodayStockPrice(amount: displayedBar.close, currency: history.currency,
                                            change: nil, label: date)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(price.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(price.formattedAmount(symbol: symbol))
                        .font(.subheadline.weight(.semibold))
                }
                .monospacedDigit()
                .accessibilityElement(children: .combine)
            }

            Chart {
                ForEach(bars) { bar in
                    if history.isComplete && bars.count > 1 {
                        LineMark(x: .value("交易日", Double(bar.timestamp)), y: .value("收盘价", bar.close))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(TodayBriefStyle.accent)
                    } else {
                        PointMark(x: .value("交易日", Double(bar.timestamp)), y: .value("收盘价", bar.close))
                            .foregroundStyle(TodayBriefStyle.accent)
                    }
                }
                if let selectedBar {
                    RuleMark(x: .value("所选交易日", Double(selectedBar.timestamp)))
                        .foregroundStyle(TodayBriefStyle.accent.opacity(0.25))
                    PointMark(x: .value("所选交易日", Double(selectedBar.timestamp)), y: .value("收盘价", selectedBar.close))
                        .foregroundStyle(TodayBriefStyle.accent)
                        .symbolSize(45)
                }
            }
            .chartXSelection(value: $selection)
            .chartXScale(range: .plotDimension(startPadding: 8, endPadding: 8))
            .chartYScale(domain: max(0, bounds.lower - inset)...(bounds.upper + inset))
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                    AxisGridLine().foregroundStyle(TodayBriefStyle.rule)
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: ticks) { value in
                    if let timestamp = value.as(Double.self),
                       let date = bars.first(where: { Double($0.timestamp) == timestamp })?.tradingDate {
                        AxisValueLabel { Text(String(date.suffix(5))) }
                    }
                }
            }
            .frame(height: 182)
            .accessibilityLabel("\(symbol) 收盘价走势")
            .accessibilityIdentifier("today-stock-detail-chart")

            if !history.isComplete {
                Text("部分区间暂无确认收盘记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TodayBriefStyle.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    }
}
