import SwiftUI
import UIKit

private enum MarketStyle {
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let divider = Color(uiColor: .separator).opacity(0.55)
    static let gain = Color(red: 0.96, green: 0.18, blue: 0.22)
    static let loss = Color(red: 0.06, green: 0.65, blue: 0.32)
    static let accent = Color(red: 0.07, green: 0.49, blue: 0.98)
    static let chartTransition = Animation.smooth(duration: 0.6)
    static let purple = Color(red: 0.50, green: 0.30, blue: 0.94)
}

struct MarketView: View {
    @Binding private var showsDetail: Bool
    @State private var store = MarketStore()
    @State private var watchlist = MarketWatchlistStore()
    @State private var path: [String] = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--market-detail-preview") ? ["^NDX"] : []
        #else
        []
        #endif
    }()

    init(showsDetail: Binding<Bool> = .constant(false)) { _showsDetail = showsDetail }

    var body: some View {
        NavigationStack(path: $path) {
            MarketHomeView(store: store) { path.append($0) }
                .navigationDestination(for: String.self) { symbol in
                    MarketIndexDetailView(symbol: symbol, store: store, watchlist: watchlist)
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .task { await store.runUpdates() }
        .onChange(of: path) { _, path in showsDetail = !path.isEmpty }
        .onAppear { showsDetail = !path.isEmpty }
        .onDisappear { showsDetail = false }
    }
}

private struct MarketHomeView: View {
    let store: MarketStore
    let onSelectIndex: (String) -> Void
    @State private var selectedMarket = MarketRegion.unitedStates
    @State private var suppressIndexSelection = false
    @State private var selectionResetTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ZStack {
                    MarketTerminalHero(store: store, region: selectedMarket, onSelectIndex: onSelectIndex)
                        .id(selectedMarket)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.18), value: selectedMarket)

                VStack(spacing: 14) {
                    if let error = store.errorMessage {
                        MarketErrorBanner(message: error) { await store.refresh() }
                    }
                    MarketRegionPicker(selection: $selectedMarket)
                    MarketIndexTable(
                        region: selectedMarket,
                        store: store,
                        onSelectIndex: selectIndex
                    )
                    .id(selectedMarket)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.16), value: selectedMarket)
                    .simultaneousGesture(regionSwipeGesture)
                    MarketCountryStrip(store: store, onSelectIndex: onSelectIndex)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("热门板块")
                            .font(.system(size: 19, weight: .semibold))
                            .padding(.horizontal, 18)
                        MarketSectorsRow(overview: store.dashboard?.ashareOverview)
                    }
                }
                .padding(.top, 12)
                .background(MarketStyle.canvas)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
            }
        }
        .background(MarketTerminalPalette.header.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
    }

    private var regionSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                selectionResetTask?.cancel()
                suppressIndexSelection = true
            }
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height
                if abs(horizontalDistance) > abs(verticalDistance), abs(horizontalDistance) >= 56 {
                    selectAdjacentRegion(offset: horizontalDistance < 0 ? 1 : -1)
                }
                allowIndexSelectionAfterGesture()
            }
    }

    private func selectIndex(_ symbol: String) {
        guard !suppressIndexSelection else { return }
        onSelectIndex(symbol)
    }

    private func allowIndexSelectionAfterGesture() {
        selectionResetTask?.cancel()
        selectionResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            suppressIndexSelection = false
        }
    }

    private func selectAdjacentRegion(offset: Int) {
        let regions = MarketRegion.allCases
        guard let currentIndex = regions.firstIndex(of: selectedMarket) else { return }
        let nextIndex = currentIndex + offset
        guard regions.indices.contains(nextIndex) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedMarket = regions[nextIndex]
        }
    }
}

private enum MarketTerminalPalette {
    static let header = Color(red: 0.035, green: 0.045, blue: 0.060)
    static let headerSurface = Color.white.opacity(0.055)
    static let headerDivider = Color.white.opacity(0.15)
}

private enum MarketRegion: String, CaseIterable, Identifiable {
    case unitedStates = "美国"
    case china = "中国"
    case japan = "日本"
    case korea = "韩国"

    var id: Self { self }

    var symbols: [String] {
        switch self {
        case .unitedStates: ["^GSPC", "^NDX", "^DJI", "^VIX"]
        case .china: ["000001.SS", "000300.SS", "000688.SS", "^HSTECH", "^HSI"]
        case .japan: ["^N225"]
        case .korea: ["^KS11"]
        }
    }

    var primarySymbol: String { symbols[0] }
}

private struct MarketTerminalHero: View {
    let store: MarketStore
    let region: MarketRegion
    let onSelectIndex: (String) -> Void

    private var quote: MarketQuote? { store.quote(symbol: region.primarySymbol) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                HStack(spacing: 6) {
                    Circle().fill(sessionTint).frame(width: 7, height: 7)
                    Text("\(region.rawValue) · \(sessionLabel)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(sessionTint)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(heroDate)
                    MarketLiveStatus(store: store)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.62))
            }

            Button { if quote != nil { onSelectIndex(region.primarySymbol) } } label: {
                HStack(alignment: .bottom, spacing: 15) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(quote?.name ?? CoreDescriptor(symbol: region.primarySymbol).name)
                                .font(.system(size: 22, weight: .semibold))
                            Text(quote?.displayCode ?? CoreDescriptor(symbol: region.primarySymbol).code)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.white.opacity(0.58))
                        }
                        Text(quote.map { number($0.price, digits: 2) } ?? "—")
                            .font(.system(size: 31, weight: .semibold))
                            .monospacedDigit()
                            .tracking(-0.8)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text(quote.map { "\(signed($0.changeValue, digits: 2))  \($0.formattedPercent)" } ?? "等待行情")
                            .font(.system(size: 16, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(quoteTint(quote))
                    }
                    .frame(width: 142, alignment: .leading)

                    TerminalLeadChart(quote: quote)
                        .frame(maxWidth: .infinity, minHeight: 128)
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(MarketPressStyle())
            .accessibilityHint("打开代表指数详情")

            HStack(spacing: 0) {
                MarketTerminalMetric(
                    title: "VIX 恐慌指数",
                    value: store.quote(symbol: "^VIX").map { number($0.price, digits: 1) } ?? "—",
                    change: store.quote(symbol: "^VIX")?.formattedPercent ?? "—",
                    tint: quoteTint(store.quote(symbol: "^VIX")),
                    trend: store.quote(symbol: "^VIX")?.trend ?? []
                )
                TerminalDivider()
                MarketTerminalSentiment(sentiment: store.dashboard?.sentiment)
                TerminalDivider()
                MarketTerminalMetric(
                    title: "美国 10Y 国债收益率",
                    value: store.quote(symbol: "^TNX").map { String(format: "%.2f%%", $0.price) } ?? "—",
                    change: store.quote(symbol: "^TNX")?.formattedPercent ?? "—",
                    tint: quoteTint(store.quote(symbol: "^TNX")),
                    trend: store.quote(symbol: "^TNX")?.trend ?? []
                )
            }
            .frame(height: 76)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 22)
        .background(MarketTerminalPalette.header)
    }

    private var sessionLabel: String {
        switch quote?.marketSession {
        case "regular": "交易中"
        case "pre": "盘前"
        case "post", "after": "盘后"
        default: "已收盘"
        }
    }

    private var sessionTint: Color { quote?.marketSession == "regular" ? Color(red: 0.08, green: 0.83, blue: 0.47) : Color.white.opacity(0.58) }

    private var heroDate: String {
        let date = quote?.timestamp.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? Date()
        return date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }
}

private struct TerminalLeadChart: View {
    let quote: MarketQuote?

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        Rectangle().fill(Color.white.opacity(index == 1 ? 0.13 : 0.07)).frame(height: 0.5)
                        if index < 2 { Spacer() }
                    }
                }
                Sparkline(values: quote?.trend ?? [], color: quoteTint(quote))
                    .padding(.vertical, 5)
            }
            HStack {
                Text("开盘")
                Spacer()
                Text("盘中")
                Spacer()
                Text("最新")
            }
            .font(.caption2)
            .foregroundStyle(Color.white.opacity(0.58))
        }
    }
}

private struct TerminalDivider: View {
    var body: some View {
        Rectangle().fill(MarketTerminalPalette.headerDivider).frame(width: 0.5).padding(.vertical, 3)
    }
}

private struct MarketTerminalMetric: View {
    let title: String
    let value: String
    let change: String
    let tint: Color
    let trend: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2.weight(.medium)).foregroundStyle(Color.white.opacity(0.68)).lineLimit(1).minimumScaleFactor(0.85)
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                    Text(change)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                Spacer(minLength: 3)
                Sparkline(values: trend, color: tint, showsFill: false).frame(width: 34, height: 24)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarketTerminalSentiment: View {
    let sentiment: MarketSentiment?

    var body: some View {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 5) {
                Text("市场情绪")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.68))
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(sentiment.map { String(Int($0.score.rounded())) } ?? "—")
                        .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                    Text("/100").font(.caption2).foregroundStyle(Color.white.opacity(0.62))
                }
                Text(sentimentChange)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(sentimentTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            ZStack {
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(sentiment?.score ?? 0, 0), 100) / 100))
                    .stroke(Color(red: 0.05, green: 0.80, blue: 0.66), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 32, height: 32)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sentimentChange: String {
        guard let score = sentiment?.score, let previous = sentiment?.previousClose else { return "较前值 —" }
        return "较前值 \(signed(score - previous, digits: 1))"
    }

    private var sentimentTint: Color {
        guard let score = sentiment?.score, let previous = sentiment?.previousClose else { return Color.white.opacity(0.55) }
        return score >= previous ? MarketStyle.gain : MarketStyle.loss
    }
}

private struct MarketRegionPicker: View {
    @Binding var selection: MarketRegion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MarketRegion.allCases) { region in
                Button { withAnimation(.easeOut(duration: 0.18)) { selection = region } } label: {
                    VStack(spacing: 9) {
                        Text(region.rawValue)
                            .font(.subheadline.weight(selection == region ? .semibold : .medium))
                        Capsule()
                            .fill(selection == region ? MarketStyle.accent : Color.clear)
                            .frame(width: 38, height: 2.5)
                    }
                    .foregroundStyle(selection == region ? MarketStyle.accent : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == region ? .isSelected : [])
            }
        }
        .background(MarketStyle.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(MarketStyle.divider, lineWidth: 0.5) }
        .padding(.horizontal, 14)
    }
}

private struct MarketIndexTable: View {
    let region: MarketRegion
    let store: MarketStore
    let onSelectIndex: (String) -> Void

    private var quotes: [MarketQuote] { region.symbols.compactMap { store.quote(symbol: $0) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("名称 / 代码").frame(width: 112, alignment: .leading)
                Text("最新价").frame(maxWidth: .infinity, alignment: .trailing)
                Text("涨跌幅").frame(width: 64, alignment: .trailing)
                Text("日内走势").frame(width: 60, alignment: .trailing)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 32)

            Divider().opacity(0.45)

            if quotes.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在加载\(region.rawValue)市场行情")
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ForEach(Array(quotes.enumerated()), id: \.element.symbol) { index, quote in
                    Button { onSelectIndex(quote.symbol) } label: {
                        MarketIndexTableRow(quote: quote)
                    }
                    .buttonStyle(MarketPressStyle())
                    if index < quotes.count - 1 { Divider().opacity(0.45).padding(.leading, 12) }
                }
            }

            Text(sessionFootnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Color.black.opacity(0.015))
        }
        .background(MarketStyle.surface, in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(MarketStyle.divider, lineWidth: 0.5) }
        .padding(.horizontal, 14)
        .animation(.easeOut(duration: 0.16), value: region)
    }

    private var sessionFootnote: String {
        switch region {
        case .unitedStates: "美股常规交易时段 09:30–16:00（纽约时间）"
        case .china: "A股常规交易时段 09:30–15:00（北京时间）"
        case .japan: "日股常规交易时段 09:00–15:30（东京时间）"
        case .korea: "韩股常规交易时段 09:00–15:30（首尔时间）"
        }
    }
}

private struct MarketIndexTableRow: View {
    let quote: MarketQuote

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle().fill(sessionTint).frame(width: 5, height: 5)
                    Text(sessionLabel).font(.caption2).foregroundStyle(.secondary)
                }
                Text(quote.name).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.85)
                Text(quote.displayCode).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 112, alignment: .leading)

            Text(number(quote.price, digits: 2))
                .font(.system(size: 13.5, weight: .medium)).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(1).minimumScaleFactor(0.72)

            VStack(alignment: .trailing, spacing: 3) {
                Text(quote.formattedPercent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(signed(quote.changeValue, digits: 2))
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .font(.footnote.weight(.semibold)).monospacedDigit()
            .foregroundStyle(quoteTint(quote))
            .frame(width: 64, alignment: .trailing)

            Sparkline(values: quote.trend, color: quoteTint(quote))
                .frame(width: 60, height: 32)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开指数详情")
    }

    private var sessionLabel: String { quote.marketSession == "regular" ? "交易中" : "已收盘" }
    private var sessionTint: Color { quote.marketSession == "regular" ? MarketStyle.accent : .secondary }
}

private struct MarketCountryStrip: View {
    let store: MarketStore
    let onSelectIndex: (String) -> Void

    private let markets: [(String, String, String?)] = [
        ("美国", "^GSPC", "^NDX"),
        ("中国", "000001.SS", "000300.SS"),
        ("日本", "^N225", nil),
        ("韩国", "^KS11", nil),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("全球市场概览").font(.title3.weight(.semibold))
                Spacer()
                MarketLiveStatus(store: store)
            }
            .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(markets, id: \.0) { item in
                        MarketCountrySummaryCard(
                            country: item.0,
                            primary: store.quote(symbol: item.1),
                            secondary: item.2.flatMap { store.quote(symbol: $0) },
                            onSelectIndex: onSelectIndex
                        )
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }
}

private struct MarketCountrySummaryCard: View {
    let country: String
    let primary: MarketQuote?
    let secondary: MarketQuote?
    let onSelectIndex: (String) -> Void

    var body: some View {
        Button { if let primary { onSelectIndex(primary.symbol) } } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(country).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(primary?.marketSession == "regular" ? "交易中" : "休市")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(primary?.marketSession == "regular" ? MarketStyle.accent : .secondary)
                }
                quoteLine(primary)
                if let secondary { quoteLine(secondary) }
                else { Text("市场广度暂不可用").font(.caption2).foregroundStyle(.secondary) }
            }
            .padding(10)
            .frame(width: 154, height: 105, alignment: .topLeading)
            .background(MarketStyle.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(MarketStyle.divider, lineWidth: 0.5) }
        }
        .buttonStyle(MarketPressStyle())
        .disabled(primary == nil)
    }

    private func quoteLine(_ quote: MarketQuote?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(quote?.name ?? "等待行情").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(quote.map { number($0.price, digits: 2) } ?? "—")
                    .font(.system(size: 12.5, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                Text(quote?.formattedPercent ?? "—")
                    .font(.caption2.weight(.semibold)).foregroundStyle(quoteTint(quote)).lineLimit(1)
            }
        }
    }
}

private struct MarketLiveStatus: View {
    let store: MarketStore

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
            if store.isLoading && store.dashboard == nil {
                Text("加载中")
            } else if store.hasOpenMarket && store.realtimeStatus == .connected {
                Text("实时连接")
            } else if store.realtimeStatus == .connecting || store.realtimeStatus == .reconnecting {
                Text("连接重试中")
            } else if let date = store.latestQuoteDate {
                Text("截至 \(date.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("等待行情")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .accessibilityLabel(accessibilityStatus)
    }

    private var statusColor: Color {
        if store.errorMessage != nil || store.realtimeStatus == .reconnecting { return .orange }
        if store.hasOpenMarket && store.realtimeStatus == .connected { return MarketStyle.loss }
        return .secondary
    }

    private var accessibilityStatus: String {
        if let error = store.errorMessage { return "行情更新异常：\(error)" }
        if store.hasOpenMarket && store.realtimeStatus == .connected { return "行情实时连接正常" }
        if let date = store.latestQuoteDate { return "行情截至 \(date.formatted(date: .abbreviated, time: .shortened))" }
        return "行情等待更新"
    }
}

private struct MarketErrorBanner: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            Button("重试") { Task { await retry() } }
                .font(.system(size: 12, weight: .semibold))
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 18)
        .accessibilityElement(children: .contain)
    }
}

private struct MarketMoodDashboard: View {
    let dashboard: MarketDashboard?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sentimentTitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
                Text(dashboard?.sentiment?.ratingZh ?? "—").font(.system(size: 16.5, weight: .semibold))
                HStack(spacing: 10) {
                    MoodGauge(value: dashboard?.sentiment?.score)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("较前值").font(.caption).foregroundStyle(.secondary)
                        Text(sentimentChange).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(sentimentTint)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(MarketStyle.divider).frame(width: 0.5)
            VStack(spacing: 0) {
                DashboardMetric(title: "风险指数 (VIX)", quote: dashboard?.metrics.first(where: { $0.symbol == "^VIX" }))
                Rectangle().fill(MarketStyle.divider).frame(height: 0.5)
                DashboardMetric(title: "美债10年收益率", quote: dashboard?.metrics.first(where: { $0.symbol == "^TNX" }), yield: true)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 118)
        .marketCard(cornerRadius: 11)
        .padding(.horizontal, 18)
    }

    private var sentimentChange: String {
        guard let current = dashboard?.sentiment?.score, let previous = dashboard?.sentiment?.previousClose else { return "—" }
        return signed(current - previous, digits: 1)
    }

    private var sentimentTint: Color {
        guard let current = dashboard?.sentiment?.score, let previous = dashboard?.sentiment?.previousClose else { return .secondary }
        return current >= previous ? MarketStyle.gain : MarketStyle.loss
    }

    private var sentimentTitle: String {
        dashboard?.sentiment?.source?.contains("CNN") == true ? "CNN 市场情绪" : "市场情绪"
    }
}

private struct DashboardMetric: View {
    let title: String
    let quote: MarketQuote?
    var yield = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value).font(.system(size: 16.5, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.72)
                    Text(percent).font(.caption2.weight(.medium)).foregroundStyle(quoteTint(quote)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 4)
            Sparkline(values: quote?.trend ?? [], color: quoteTint(quote), showsFill: false).frame(width: 50, height: 23)
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
    }

    private var value: String {
        guard let quote else { return "—" }
        return yield ? String(format: "%.2f%%", quote.price) : number(quote.price, digits: 1)
    }
    private var percent: String { quote?.formattedPercent ?? "—" }
}

private struct MoodGauge: View {
    let value: Double?
    var body: some View {
        ZStack {
            Circle().stroke(MarketStyle.divider, lineWidth: 7)
            Circle().trim(from: 0, to: CGFloat(min(max(value ?? 0, 0), 100) / 100))
                .stroke(AngularGradient(colors: [.mint, .green], center: .center), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(value.map { String(Int($0.rounded())) } ?? "—").font(.system(size: 21, weight: .semibold)).monospacedDigit()
                Text("/100").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 62, height: 62)
    }
}

private struct MarketCoreIndexCard: View {
    let descriptor: CoreDescriptor
    let quote: MarketQuote?
    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(quote?.name ?? descriptor.name).font(.caption.weight(.medium)).lineLimit(1)
                Text(descriptor.code).font(.caption2).foregroundStyle(.secondary.opacity(0.85))
                Spacer(minLength: 1)
                Text(quote.map { number($0.price, digits: 2) } ?? "—")
                    .font(.system(size: 14.5, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                Text(quote.map { "\(signed($0.changeValue, digits: 2))  \($0.formattedPercent)" } ?? "等待行情数据")
                    .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(quoteTint(quote)).lineLimit(1)
            }
            Sparkline(values: quote?.trend ?? [], color: quoteTint(quote)).frame(width: 56, height: 32)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .marketCard(cornerRadius: 9)
    }
}

private struct GlobalMarketOverviewGrid: View {
    let store: MarketStore
    let onSelectIndex: (String) -> Void

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            countryButton(
                country: "中国",
                city: "北京",
                timeZone: "Asia/Shanghai",
                symbol: "000001.SS",
                breadth: store.dashboard?.ashareOverview?.breadth
            )
            countryButton(
                country: "美国",
                city: "纽约",
                timeZone: "America/New_York",
                symbol: "^GSPC",
                auxiliary: store.quote(symbol: "^VIX")
            )
            countryButton(country: "日本", city: "东京", timeZone: "Asia/Tokyo", symbol: "^N225")
            countryButton(country: "韩国", city: "首尔", timeZone: "Asia/Seoul", symbol: "^KS11")
        }
        .padding(.horizontal, 18)
    }

    private func countryButton(
        country: String,
        city: String,
        timeZone: String,
        symbol: String,
        breadth: MarketBreadth? = nil,
        auxiliary: MarketQuote? = nil
    ) -> some View {
        let quote = store.quote(symbol: symbol)
        return Button { if quote != nil { onSelectIndex(symbol) } } label: {
            MarketCountryCard(
                country: country,
                city: city,
                timeZone: timeZone,
                quote: quote,
                breadth: breadth,
                auxiliary: auxiliary
            )
        }
        .disabled(quote == nil)
        .buttonStyle(MarketPressStyle())
        .accessibilityHint(quote == nil ? "行情加载完成后可查看详情" : "打开\(country)市场代表指数详情")
    }
}

private struct MarketCountryCard: View {
    let country: String
    let city: String
    let timeZone: String
    let quote: MarketQuote?
    let breadth: MarketBreadth?
    let auxiliary: MarketQuote?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(country).font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 3)
                Circle().fill(sessionTint).frame(width: 6, height: 6)
                Text(sessionLabel).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quote?.name ?? "等待行情").font(.caption.weight(.medium)).lineLimit(1)
                    Text(quote.map { number($0.price, digits: 2) } ?? "—")
                        .font(.system(size: 16, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer(minLength: 2)
                Text(quote?.formattedPercent ?? "—")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(quoteTint(quote)).lineLimit(1)
            }
            Spacer(minLength: 0)
            detail
            Text(marketLocalTime(quote?.timestamp, city: city, timeZone: timeZone))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .marketCard(cornerRadius: 10)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var detail: some View {
        if let breadth {
            let total = max(breadth.total, breadth.up + breadth.down + breadth.flat)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("涨 \(breadth.up)").foregroundStyle(MarketStyle.gain)
                    Text("跌 \(breadth.down)").foregroundStyle(MarketStyle.loss)
                    Text("平 \(breadth.flat)").foregroundStyle(.secondary)
                }
                .font(.caption2.weight(.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
                MarketBreadthComposition(up: breadth.up, down: breadth.down, flat: breadth.flat, total: total)
            }
        } else if let auxiliary {
            HStack(spacing: 4) {
                Text("VIX").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                Text(number(auxiliary.price, digits: 1)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                Text(auxiliary.formattedPercent).font(.caption2.weight(.semibold)).foregroundStyle(quoteTint(auxiliary))
            }
        } else {
            Label("市场广度暂不可用", systemImage: "info.circle")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
        }
    }

    private var sessionLabel: String {
        switch quote?.marketSession {
        case "regular": "交易中"
        case "pre": "盘前"
        case "post", "after": "盘后"
        case "always-open": "全天"
        default: "已收盘"
        }
    }

    private var sessionTint: Color { quote?.marketSession == "regular" ? MarketStyle.loss : .secondary }
}

private struct MarketBreadthComposition: View {
    let up: Int
    let down: Int
    let flat: Int
    let total: Int

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - 2, 0)
            HStack(spacing: 1) {
                Capsule().fill(MarketStyle.gain).frame(width: width * ratio(up))
                Capsule().fill(Color.gray.opacity(0.45)).frame(width: width * ratio(flat))
                Capsule().fill(MarketStyle.loss).frame(width: width * ratio(down))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private func ratio(_ value: Int) -> Double { total > 0 ? Double(value) / Double(total) : 0 }
}

private struct MarketSectorsRow: View {
    let overview: MarketAShareOverview?
    private var sectors: [MarketSector] { overview?.hotSectors ?? [] }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sectors) { sector in
                    VStack(alignment: .leading, spacing: 7) {
                        Label(sector.name, systemImage: sectorSymbol(sector.name)).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                        Text(sector.changePercent).font(.system(size: 11, weight: .semibold)).foregroundStyle(sector.percentValue >= 0 ? MarketStyle.gain : MarketStyle.loss)
                        Text(sourceLabel).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(9).frame(width: 98, height: 76, alignment: .topLeading).marketCard(cornerRadius: 9)
                }
                if sectors.isEmpty {
                    Text("板块数据加载中").font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 76)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 4)
        }
    }

    private var sourceLabel: String {
        if overview?.stale == true { return "缓存数据 · 可能延迟" }
        if let date = marketISODate(overview?.fetchedAt ?? overview?.generatedAt) {
            return "截至 \(date.formatted(date: .omitted, time: .shortened))"
        }
        return overview?.cached == true ? "缓存行情" : "板块涨幅"
    }
}

private struct MarketIndexDetailView: View {
    let symbol: String
    let store: MarketStore
    let watchlist: MarketWatchlistStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRange = MarketRange.day

    private var quote: MarketQuote? { store.quote(symbol: symbol) }

    var body: some View {
        ZStack {
            MarketStyle.canvas.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 15) {
                    detailHeader
                    MarketDetailChart(selectedRange: $selectedRange, symbol: symbol, store: store)
                    keyData
                    MarketSummary(quote: quote)
                    componentStocks
                    Text("数据来源：\(quote?.dataSource ?? "行情服务") · \(quote?.freshnessLabel ?? "更新中")")
                        .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 18)
                    Color.clear.frame(height: 20)
                }
                .padding(.top, 4)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .background(InteractivePopGestureEnabler())
        .task { await store.loadIndexConstituents(symbol: symbol) }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("返回市场")
                Spacer()
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                }
                .accessibilityLabel("分享行情")
            }
            .font(.system(size: 21, weight: .medium)).foregroundStyle(.primary)

            HStack(spacing: 10) {
                Image(systemName: CoreDescriptor(symbol: symbol).icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.blue)
                    .frame(width: 30, height: 30).background(Color.blue.opacity(0.10), in: Circle())
                Text(quote?.name ?? CoreDescriptor(symbol: symbol).name).font(.system(size: 22, weight: .semibold)).tracking(-0.35)
                Text(CoreDescriptor(symbol: symbol).code).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 5).background(Color.primary.opacity(0.06), in: Capsule())
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(quote.map { number($0.price, digits: 2) } ?? "—").font(.system(size: 33, weight: .bold)).monospacedDigit().tracking(-0.8).foregroundStyle(quoteTint(quote))
                    Text(quote.map { "\(signed($0.changeValue, digits: 2))  \($0.formattedPercent)" } ?? "等待行情数据")
                        .font(.system(size: 16, weight: .semibold)).monospacedDigit().foregroundStyle(quoteTint(quote))
                    HStack(spacing: 7) {
                        Circle().fill(sessionColor).frame(width: 6, height: 6)
                        Text(sessionText)
                        if let timestamp = quote?.timestamp { Text(marketTimestamp(timestamp)) }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { watchlist.toggle(symbol) } label: {
                    Text(watchlist.contains(symbol) ? "✓ 已自选" : "+ 自选").font(.system(size: 12.5, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .foregroundStyle(.primary)
                .frame(minHeight: 44)
                .accessibilityLabel(watchlist.contains(symbol) ? "移出自选" : "加入自选")
            }
        }
        .padding(.horizontal, 18)
    }

    private var keyData: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("关键数据").font(.system(size: 17, weight: .semibold))
            Grid(horizontalSpacing: 10, verticalSpacing: 13) {
                GridRow { metric("开盘", quote?.openPrice); metric("最高", quote?.high, MarketStyle.gain); metric("最低", quote?.low, MarketStyle.loss); metric("昨收", quote?.previousClose) }
                GridRow { metric("成交量", quote?.volume, compact: true); metric("涨跌幅", quote?.percentValue, quoteTint(quote), suffix: "%"); metric("市盈率", quote?.pe); textMetric("状态", quote?.freshnessLabel ?? "更新中") }
            }
            .padding(12).marketCard(cornerRadius: 10)
        }
        .padding(.horizontal, 18)
    }

    private func metric(_ title: String, _ value: Double?, _ color: Color = .primary, compact: Bool = false, suffix: String = "") -> some View {
        textMetric(title, value.map { (compact ? compactNumber($0) : number($0, digits: 2)) + suffix } ?? "—", color)
    }

    private func textMetric(_ title: String, _ value: String, _ color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var componentStocks: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(store.indexConstituents[symbol]?.label ?? "主要成分股").font(.system(size: 17, weight: .semibold))
                Spacer()
                if let asOf = store.indexConstituents[symbol]?.asOf { Text("指数专属 · \(asOf)").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            VStack(spacing: 0) {
                let items = store.indexConstituents[symbol]?.items ?? []
                ForEach(items) { item in
                    MarketConstituentRow(item: item)
                    if item.id != items.last?.id { Divider().padding(.leading, 62) }
                }
                if let error = store.constituentErrors[symbol] {
                    Text(error).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 72)
                } else if store.indexConstituents[symbol] == nil {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 72)
                }
            }
            .marketCard(cornerRadius: 11)
        }
        .padding(.horizontal, 18)
    }

    private var sessionText: String {
        switch quote?.marketSession { case "regular": "交易中"; case "pre": "盘前"; case "post", "after": "盘后"; default: "已收盘" }
    }
    private var sessionColor: Color { quote?.marketSession == "regular" ? MarketStyle.loss : .secondary }

    private var shareText: String {
        guard let quote else { return "\(CoreDescriptor(symbol: symbol).name)行情更新中" }
        let timestamp = quote.timestamp.map(marketTimestamp) ?? "时间未知"
        return "\(quote.name)（\(quote.displayCode)）\n最新价：\(number(quote.price, digits: 2))\n涨跌：\(signed(quote.changeValue, digits: 2))  \(quote.formattedPercent)\n状态：\(quote.freshnessLabel) · \(timestamp)\n来源：\(quote.dataSource ?? "行情服务")\n仅供行情参考，不构成投资建议。"
    }
}

struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.enableSwipeBack()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableSwipeBack()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            DispatchQueue.main.async { [weak self] in self?.enableSwipeBack() }
        }

        func enableSwipeBack() {
            guard let navigationController,
                  let gesture = navigationController.interactivePopGestureRecognizer else { return }
            gesture.delegate = self
            gesture.isEnabled = navigationController.viewControllers.count > 1
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}

private struct MarketDetailChart: View {
    @Binding var selectedRange: MarketRange
    let symbol: String
    let store: MarketStore
    @State private var inspectedPoint: MarketChartPoint?

    private var chart: MarketChart? { store.chart(symbol: symbol, range: selectedRange) }
    private var points: [MarketChartPoint] { marketPointsForRange(chart?.points ?? [], range: selectedRange) }
    private var values: [Double] {
        let bounds = points.flatMap { [$0.low, $0.high].compactMap { $0 } }
        return bounds.isEmpty ? points.compactMap(\.displayValue) : bounds
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(MarketRange.allCases) { range in
                    Button {
                        withAnimation(MarketStyle.chartTransition) { selectedRange = range }
                    } label: {
                        VStack(spacing: 5) {
                            Text(range.rawValue).font(.footnote.weight(selectedRange == range ? .semibold : .regular))
                            Capsule().fill(selectedRange == range ? MarketStyle.accent : Color.clear).frame(width: 18, height: 2)
                        }
                    }
                    .foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityLabel("\(range.rawValue)行情")
                    .accessibilityAddTraits(selectedRange == range ? .isSelected : [])
                }
            }
            ZStack {
                ChartGrid(values: values)
                if values.isEmpty {
                    if store.loadingCharts.contains(ChartKey(symbol: symbol, range: selectedRange)) { ProgressView() }
                    else if let error = store.chartError(symbol: symbol, range: selectedRange) {
                        VStack(spacing: 8) {
                            Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                            Button("重新加载") { Task { await store.loadChart(symbol: symbol, range: selectedRange, force: true) } }
                                .font(.system(size: 12, weight: .semibold)).frame(minWidth: 88, minHeight: 44)
                        }
                    } else { Text("该周期暂无行情数据").font(.system(size: 12)).foregroundStyle(.secondary) }
                } else {
                    MarketLineChart(
                        values: points.compactMap(\.displayValue),
                        color: quoteTint(store.quote(symbol: symbol))
                    )
                        .padding(.leading, 48).padding(.top, 9).padding(.bottom, 6)
                    ChartInspectionOverlay(points: points, selected: $inspectedPoint)
                }
            }
            .frame(height: 184)
            .animation(MarketStyle.chartTransition, value: selectedRange)
            if let inspectedPoint {
                Text("\(chartTime(inspectedPoint.timestamp, range: selectedRange))  \(number(inspectedPoint.displayValue ?? 0, digits: 2))")
                    .font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack {
                ForEach(Array(timelineLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                    if index < 2 { Spacer() }
                }
            }
            .font(.caption2).foregroundStyle(.secondary).padding(.leading, 48).padding(.trailing, 5)
            VolumeBars(points: points).frame(height: 25).padding(.leading, 48)
                .overlay(alignment: .topTrailing) {
                    Text(selectedRange.apiInterval == "1m" ? "分钟K · 成交量" : "日K · 成交量")
                        .font(.caption2).foregroundStyle(.secondary)
                }
        }
        .padding(.horizontal, 18)
        .task(id: selectedRange) {
            inspectedPoint = nil
            await store.loadChart(symbol: symbol, range: selectedRange)
        }
        .task(priority: .utility) { await store.preloadCharts(symbol: symbol) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(selectedRange.rawValue)行情图表，可拖动查看具体时间和价格")
    }

    private var timelineLabels: [String] {
        guard let first = points.first, let last = points.last else { return ["—", "—", "—"] }
        return [first, points[points.count / 2], last].map { chartTime($0.timestamp, range: selectedRange) }
    }

}

private struct ChartInspectionOverlay: View {
    let points: [MarketChartPoint]
    @Binding var selected: MarketChartPoint?

    var body: some View {
        GeometryReader { proxy in
            let leftInset: CGFloat = 48
            let usableWidth = max(proxy.size.width - leftInset, 1)
            ZStack(alignment: .leading) {
                if let selected, let index = points.firstIndex(where: { $0.id == selected.id }) {
                    let x = leftInset + usableWidth * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                    Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 1).offset(x: x)
                }
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        guard !points.isEmpty else { return }
                        let fraction = min(max((value.location.x - leftInset) / usableWidth, 0), 1)
                        let index = Int((fraction * CGFloat(points.count - 1)).rounded())
                        selected = points[index]
                    })
            }
        }
    }
}

private struct ChartGrid: View {
    let values: [Double]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                HStack(spacing: 6) {
                    Text(axisLabel(index))
                        .font(.caption2)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .leading)
                    Rectangle().fill(MarketStyle.divider).frame(height: 0.5)
                }
                if index < 4 { Spacer() }
            }
        }
        .animation(MarketStyle.chartTransition, value: values)
    }

    private func axisLabel(_ index: Int) -> String {
        guard let min = values.min(), let max = values.max(), max > min else { return "—" }
        return number(max - (max - min) * Double(index) / 4, digits: 0)
    }
}

private struct MarketLineChart: View {
    let values: [Double]
    let color: Color
    @State private var previous: [Double]
    @State private var current: [Double]
    @State private var progress: CGFloat = 1

    init(values: [Double], color: Color) {
        self.values = values
        self.color = color
        _previous = State(initialValue: values)
        _current = State(initialValue: values)
    }

    var body: some View {
        AnimatedLineCanvas(previous: previous, current: current, color: color, progress: progress)
            .onChange(of: values) { _, newValues in
                guard newValues != current else { return }
                previous = current
                current = newValues
                progress = 0
                withAnimation(MarketStyle.chartTransition) { progress = 1 }
            }
    }
}

private struct AnimatedLineCanvas: View, Animatable {
    let previous: [Double]
    let current: [Double]
    let color: Color
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let sampleCount = min(max(max(previous.count, current.count), 2), 120)
            let from = normalizedSamples(marketAnimationStartValues(previous: previous, current: current), count: sampleCount)
            let to = normalizedSamples(current, count: sampleCount)
            guard from.count == sampleCount, to.count == sampleCount else { return }

            let points = zip(from, to).enumerated().map { index, pair in
                CGPoint(
                    x: size.width * CGFloat(index) / CGFloat(sampleCount - 1),
                    y: size.height * (pair.0 + (pair.1 - pair.0) * progress)
                )
            }
            guard let first = points.first, let last = points.last else { return }

            var fill = Path()
            fill.move(to: CGPoint(x: first.x, y: size.height))
            fill.addLine(to: first)
            points.dropFirst().forEach { fill.addLine(to: $0) }
            fill.addLine(to: CGPoint(x: last.x, y: size.height))
            fill.closeSubpath()
            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.22), color.opacity(0.01)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            var line = Path()
            line.move(to: first)
            points.dropFirst().forEach { line.addLine(to: $0) }
            context.stroke(
                line,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func normalizedSamples(_ values: [Double], count: Int) -> [CGFloat] {
        guard !values.isEmpty, count > 1 else { return [] }
        let low = values.min() ?? 0
        let high = values.max() ?? low
        let span = max(high - low, 0.000_001)

        return (0..<count).map { index in
            let position = Double(index) * Double(values.count - 1) / Double(count - 1)
            let lower = Int(position.rounded(.down))
            let upper = min(lower + 1, values.count - 1)
            let fraction = position - Double(lower)
            let value = values[lower] + (values[upper] - values[lower]) * fraction
            let normalized = CGFloat((high - value) / span)
            return 0.06 + normalized * 0.88
        }
    }
}

private struct VolumeBars: View {
    let points: [MarketChartPoint]
    var body: some View {
        GeometryReader { proxy in
            let maxVolume = points.compactMap(\.volume).max() ?? 1
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(points.suffix(80)) { point in
                    let rising = (point.close ?? point.value ?? 0) >= (point.open ?? point.close ?? point.value ?? 0)
                    Rectangle().fill((rising ? MarketStyle.gain : MarketStyle.loss).opacity(0.68))
                        .frame(maxWidth: .infinity).frame(height: max(2, proxy.size.height * CGFloat((point.volume ?? 0) / maxVolume)))
                        .transition(.scale(scale: 0.2, anchor: .bottom).combined(with: .opacity))
                }
            }
            .animation(MarketStyle.chartTransition, value: points)
        }
    }
}

private struct MarketSummary: View {
    let quote: MarketQuote?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: "info.circle.fill").foregroundStyle(.white).frame(width: 22, height: 22).background(MarketStyle.purple, in: Circle()); Text("日内摘要").font(.system(size: 16, weight: .semibold)); Spacer(); Text(quote?.freshnessLabel ?? "更新中").font(.system(size: 11)).foregroundStyle(.secondary) }
            Text(summary).font(.footnote).lineSpacing(3).foregroundStyle(.primary.opacity(0.86))
            Text("仅汇总当前行情字段，不构成分析或投资建议。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(LinearGradient(colors: [MarketStyle.purple.opacity(0.08), MarketStyle.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(MarketStyle.purple.opacity(0.07), lineWidth: 0.5) }
        .padding(.horizontal, 18)
    }

    private var summary: String {
        guard let quote else { return "正在获取最新行情。" }
        var details: [String] = []
        if let high = quote.high, let low = quote.low {
            let baseline = quote.previousClose ?? low
            let amplitude = baseline == 0 ? 0 : (high - low) / baseline * 100
            details.append("日内区间 \(number(low, digits: 2))–\(number(high, digits: 2))，振幅 \(number(amplitude, digits: 2))%")
        }
        if let open = quote.openPrice, open != 0 {
            let changeFromOpen = (quote.price - open) / open * 100
            details.append("较开盘\(changeFromOpen >= 0 ? "上涨" : "下跌") \(number(abs(changeFromOpen), digits: 2))%")
        }
        if let volume = quote.volume { details.append("成交量 \(compactNumber(volume))") }
        details.append("来源：\(quote.dataSource ?? "行情服务")")
        return details.joined(separator: "；") + "。"
    }
}

private struct MarketConstituentRow: View {
    let item: MarketIndexConstituent
    private var quote: MarketQuote { item.quote }

    var body: some View {
        HStack(spacing: 12) {
            CompanyLogo(quote: quote, path: item.logoPath)
            VStack(alignment: .leading, spacing: 4) {
                Text(quote.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(quote.symbol)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(number(quote.price, digits: 2)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                Text(quote.formattedPercent).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(quoteTint(quote))
            }
            Sparkline(values: quote.trend, color: quoteTint(quote), showsFill: false)
                .frame(width: 58, height: 28)
        }
        .padding(.horizontal, 12).frame(minHeight: 66)
        .accessibilityElement(children: .combine)
        .overlay(alignment: .bottomLeading) {
            Text("市值 \(quote.marketCap.map(compactNumber) ?? "—")")
                .font(.caption2).foregroundStyle(.secondary).padding(.leading, 64).padding(.bottom, 5)
        }
        .padding(.bottom, 12)
        .accessibilityLabel("第 \(item.rank)，\(quote.name)，\(quote.symbol)，市值 \(quote.marketCap.map(compactNumber) ?? "未知")，最新价 \(number(quote.price, digits: 2))，\(quote.formattedPercent)")
    }
}

private struct CompanyLogo: View {
    let quote: MarketQuote
    let path: String?

    var body: some View {
        AsyncImage(url: logoURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit().padding(6)
            } else {
                fallback
            }
        }
        .frame(width: 40, height: 40)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(MarketStyle.divider, lineWidth: 0.5) }
    }

    private var logoURL: URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: path, relativeTo: ServerConfiguration.currentURL)?.absoluteURL
    }

    private var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(stockColor(quote.symbol).opacity(0.10))
            Text(String(quote.symbol.prefix(1))).font(.system(size: 16, weight: .bold)).foregroundStyle(stockColor(quote.symbol))
        }
    }
}

private struct Sparkline: View {
    let values: [Double]
    let color: Color
    var showsFill = true
    var body: some View {
        GeometryReader { proxy in
            let points = chartPoints(values, size: proxy.size)
            if points.count > 1 {
                ZStack {
                    if showsFill {
                        Path { path in
                            guard let first = points.first, let last = points.last else { return }
                            path.move(to: CGPoint(x: first.x, y: proxy.size.height)); path.addLine(to: first)
                            points.dropFirst().forEach { path.addLine(to: $0) }
                            path.addLine(to: CGPoint(x: last.x, y: proxy.size.height)); path.closeSubpath()
                        }.fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    }
                    Path { path in guard let first = points.first else { return }; path.move(to: first); points.dropFirst().forEach { path.addLine(to: $0) } }
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            } else {
                Capsule().fill(Color.secondary.opacity(0.12)).frame(height: 1)
            }
        }
    }
}

private struct MarketProgress: View {
    let value: Double
    let tint: Color
    var body: some View { GeometryReader { proxy in ZStack(alignment: .leading) { Capsule().fill(Color.secondary.opacity(0.14)); Capsule().fill(tint.opacity(0.85)).frame(width: proxy.size.width * min(max(value, 0), 1)) } }.frame(height: 5) }
}

private struct MarketPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.scaleEffect(configuration.isPressed ? 0.985 : 1).opacity(configuration.isPressed ? 0.88 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed) }
}

private extension View {
    func marketCard(cornerRadius: CGFloat) -> some View {
        background(MarketStyle.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: cornerRadius).stroke(MarketStyle.divider, lineWidth: 0.5) }
            .shadow(color: Color.black.opacity(0.06), radius: 9, x: 0, y: 4)
    }
}

private struct CoreRegion: Identifiable {
    let title: String
    let symbols: [String]
    var id: String { title }
    static let all = [
        CoreRegion(title: "美国", symbols: ["^GSPC", "^NDX", "^DJI"]),
        CoreRegion(title: "中国 / 香港", symbols: ["000001.SS", "000300.SS", "000688.SS", "^HSTECH", "^HSI"]),
        CoreRegion(title: "日本 / 韩国", symbols: ["^N225", "^KS11"]),
        CoreRegion(title: "欧洲", symbols: ["^STOXX50E", "^GDAXI", "^FTSE", "^FCHI"]),
    ]
}

private struct CoreDescriptor {
    let symbol: String
    var name: String { switch symbol { case "^GSPC": "标普500"; case "^NDX": "纳斯达克100"; case "^DJI": "道琼斯工业指数"; case "000001.SS": "上证指数"; case "000300.SS": "沪深300"; case "000688.SS": "科创50"; case "^HSTECH": "恒生科技指数"; case "^HSI": "恒生指数"; case "^N225": "日经225"; case "^KS11": "韩国KOSPI"; case "^STOXX50E": "欧洲STOXX 50"; case "^GDAXI": "德国DAX"; case "^FTSE": "英国富时100"; case "^FCHI": "法国CAC 40"; default: symbol } }
    var code: String { switch symbol { case "^GSPC": "SPX"; case "^NDX": "NDX"; case "^DJI": "DJI"; case "000001.SS": "000001.SH"; case "000300.SS": "000300.SH"; case "000688.SS": "000688.SH"; case "^HSTECH": "HSTECH"; case "^HSI": "HSI"; case "^N225": "N225"; case "^KS11": "KOSPI"; case "^STOXX50E": "SX5E"; case "^GDAXI": "DAX"; case "^FTSE": "FTSE"; case "^FCHI": "CAC40"; default: symbol } }
    var icon: String { switch symbol { case "^NDX": "n.circle.fill"; case "^DJI": "building.columns.fill"; case "000001.SS", "000300.SS": "building.2.fill"; case "000688.SS": "cpu.fill"; case "^HSTECH": "asterisk"; case "^HSI": "h.circle.fill"; case "^N225": "yensign.circle.fill"; case "^KS11": "k.circle.fill"; case "^STOXX50E": "globe.europe.africa.fill"; case "^GDAXI": "shield.fill"; case "^FTSE": "sterlingsign.circle.fill"; case "^FCHI": "f.circle.fill"; default: "star.fill" } }
}

private func marketLocalTime(_ timestamp: Int64?, city: String, timeZone: String) -> String {
    guard let timestamp else { return "等待更新" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = TimeZone(identifier: timeZone)
    formatter.dateFormat = "HH:mm"
    return "\(city) \(formatter.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000)))"
}

private func chartPoints(_ values: [Double], size: CGSize) -> [CGPoint] {
    let minValue = values.min() ?? 0, maxValue = values.max() ?? 1, range = max(maxValue - minValue, 0.01)
    return values.enumerated().map { CGPoint(x: size.width * CGFloat($0.offset) / CGFloat(max(values.count - 1, 1)), y: size.height * (1 - CGFloat(($0.element - minValue) / range))) }
}

private func quoteTint(_ quote: MarketQuote?) -> Color { guard let quote else { return .secondary }; return quote.isUp ? MarketStyle.gain : MarketStyle.loss }
private func number(_ value: Double, digits: Int) -> String { value.formatted(.number.grouping(.automatic).precision(.fractionLength(digits))) }
private func signed(_ value: Double, digits: Int) -> String { (value >= 0 ? "+" : "−") + number(abs(value), digits: digits) }
private func compactNumber(_ value: Double) -> String { value.formatted(.number.notation(.compactName).precision(.fractionLength(1))) }
private func marketTimestamp(_ timestamp: Int64) -> String {
    marketShortTimestamp(timestamp)
}
private func chartTime(_ timestamp: Int64, range: MarketRange) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    switch range {
    case .day, .week: formatter.dateFormat = "MM-dd HH:mm"
    case .month, .quarter, .year: formatter.dateFormat = "MM-dd"
    case .fiveYears, .maximum: formatter.dateFormat = "yyyy-MM"
    }
    return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000))
}
private func sectorSymbol(_ name: String) -> String { if name.contains("石油") || name.contains("能源") { return "drop.fill" }; if name.contains("医疗") { return "cross.case.fill" }; if name.contains("家具") { return "house.fill" }; return "chart.line.uptrend.xyaxis" }
private func stockSymbol(_ symbol: String) -> String { switch symbol { case "AAPL": "apple.logo"; case "MSFT": "square.grid.2x2.fill"; case "META": "infinity"; case "AMZN": "a.circle.fill"; default: "eye.fill" } }
private func stockColor(_ symbol: String) -> Color { switch symbol { case "AAPL": .primary; case "AMZN": .orange; case "NVDA": .green; default: .blue } }

#Preview { MarketView() }
