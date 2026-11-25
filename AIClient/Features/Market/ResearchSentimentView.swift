import Charts
import SwiftUI

struct ResearchSentimentView: View {
    let store: MarketStore
    @State private var showsFullHistory = false

    private let sourceURL = URL(string: "https://www.cnn.com/markets/fear-and-greed")!
    private var sentiment: MarketSentiment? { store.dashboard?.sentiment }

    private var history: [MarketSentiment.HistoryPoint] {
        let points = (sentiment?.historical ?? [])
            .filter { (0...100).contains($0.value) }
            .sorted { $0.timestamp < $1.timestamp }
        return showsFullHistory ? points : Array(points.suffix(30))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                summary
                Divider()
                historySection
                Divider()
                indicatorSection
                Link(destination: sourceURL) {
                    Label("CNN Fear & Greed 原始数据", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44, alignment: .leading)
                }
                .tint(InvestmentDesign.accent)
            }
            .padding(18)
            .padding(.bottom, 48)
        }
        .accessibilityIdentifier("research-sentiment-detail")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let sentiment, sentiment.available != false {
                Text("\(sentiment.score.formatted(.number.precision(.fractionLength(1)))) / 100")
                    .font(.largeTitle.weight(.semibold).monospacedDigit())
                Text(sentiment.ratingZh)
                    .font(.headline)
                if let reason = sentiment.reasonSummary, !reason.isEmpty {
                    Text(reason).font(.subheadline)
                }
            } else {
                Text("当前指数暂缺").font(.headline)
            }

            if let date = marketISODate(sentiment?.updatedAt) {
                Text("更新时间 \(marketShortTimestamp(Int64(date.timeIntervalSince1970 * 1000)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if store.errorMessage != nil {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label(store.isRetrying ? "正在重试" : "数据待更新 · 重试", systemImage: "arrow.clockwise")
                        .font(.footnote)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(ResearchDesign.accent)
                .disabled(store.isRetrying)
            } else if sentiment?.stale == true || store.isShowingCachedSnapshot {
                Label("数据待更新", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var historySection: some View {
        let points = history
        return VStack(alignment: .leading, spacing: 10) {
            Text("指数走势").font(.headline).accessibilityAddTraits(.isHeader)
            if points.count > 1 {
                Picker("走势范围", selection: $showsFullHistory) {
                    Text("最近 30 个交易日").tag(false)
                    Text("全部").tag(true)
                }
                .pickerStyle(.segmented)
                Chart(points) { point in
                    LineMark(x: .value("日期", point.date), y: .value("指数", point.value))
                        .foregroundStyle(InvestmentDesign.accent)
                }
                .chartYScale(domain: 0.0...100.0)
                .frame(height: 160)
                .accessibilityLabel("CNN 恐慌与贪婪指数走势")
            } else {
                Text("暂无历史走势").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var indicatorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("构成指标").font(.headline).accessibilityAddTraits(.isHeader)
            if let indicators = sentiment?.indicators, !indicators.isEmpty {
                ForEach(indicators) { indicator in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(indicator.label)
                            if let date = marketISODate(indicator.updatedAt) {
                                Text(marketShortTimestamp(Int64(date.timeIntervalSince1970 * 1000)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 6)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(indicator.score?.formatted(.number.precision(.fractionLength(1))) ?? "—")
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            if let rating = indicator.ratingZh {
                                Text(rating).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            } else {
                Text("暂无构成指标").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
