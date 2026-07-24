import SwiftUI
import UIKit

private enum MarketStyle {
    static let canvas = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .systemBackground)
    static let divider = Color(uiColor: .separator).opacity(0.55)
    static let gain = Color(red: 0.96, green: 0.18, blue: 0.22)
    static let loss = Color(red: 0.06, green: 0.65, blue: 0.32)
    static let accent = Color(red: 0.07, green: 0.49, blue: 0.98)
    static let chartTransition = Animation.smooth(duration: 0.6)
    static let purple = accent
}

struct MarketView: View {
    @Binding private var showsDetail: Bool
    @State private var store = MarketStore()
    @State private var path: [String] = {
        #if DEBUG
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--market-detail-symbol=") }) {
            return [String(argument.dropFirst("--market-detail-symbol=".count))]
        }
        if ProcessInfo.processInfo.arguments.contains("--market-vix-detail-preview") { return ["^VIX"] }
        return ProcessInfo.processInfo.arguments.contains("--market-detail-preview") ? ["^NDX"] : []
        #else
        []
        #endif
    }()
    @Environment(\.scenePhase) private var scenePhase

    init(showsDetail: Binding<Bool> = .constant(false)) { _showsDetail = showsDetail }

    var body: some View {
        NavigationStack(path: $path) {
            MarketHomeView(store: store) { path.append($0) }
                .navigationDestination(for: String.self) { symbol in
                    MarketIndexDetailView(
                        symbol: symbol,
                        store: store,
                        onSelectSymbol: { path.append($0) }
                    )
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .task { await store.runUpdates() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.resumeUpdates() }
        }
        .onChange(of: path) { _, path in showsDetail = !path.isEmpty }
        .onAppear { showsDetail = !path.isEmpty }
        .onDisappear { showsDetail = false }
    }
}

private struct MarketHomeView: View {
    let store: MarketStore
    let onSelectIndex: (String) -> Void
    @State private var selectedMarket: MarketRegion = {
        #if DEBUG
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--market-region=") }) else {
            return .unitedStates
        }
        switch argument.dropFirst("--market-region=".count) {
        case "china": return .china
        case "japan": return .japan
        case "korea": return .korea
        case "europe": return .europe
        case "crypto": return .crypto
        default: return .unitedStates
        }
        #else
        return .unitedStates
        #endif
    }()
    @State private var suppressIndexSelection = false
    @State private var selectionResetTask: Task<Void, Never>?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("market-top")
                    ZStack {
                        MarketTerminalHero(store: store, region: selectedMarket, onSelectIndex: onSelectIndex)
                            .id(selectedMarket)
                            .transition(.opacity)
                    }
                    .animation(.easeInOut(duration: 0.18), value: selectedMarket)

                    VStack(spacing: 0) {
                        if let error = regionalHealthMessage {
                            MarketErrorBanner(
                                message: error,
                                isRetrying: store.isRetrying
                            ) { await store.refresh() }
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
                        if selectedMarket == .china {
                            ChinaMarketStructurePanel(structure: store.dashboard?.marketStructure)
                                .id("market-structure")
                        }
                        if selectedMarket != .crypto {
                            MarketWorldMap(store: store, selection: $selectedMarket)
                                .id("market-map")
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .background(MarketStyle.canvas)
                }
            }
            .background(MarketTerminalPalette.header.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .safeAreaPadding(.bottom, 112)
            .refreshable { await store.refresh() }
            .onChange(of: selectedMarket) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("market-top", anchor: .top)
                }
            }
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--market-structure-preview") {
                    try? await Task.sleep(for: .seconds(2))
                    proxy.scrollTo("market-structure", anchor: .top)
                } else if ProcessInfo.processInfo.arguments.contains("--market-map-preview") {
                    try? await Task.sleep(for: .milliseconds(700))
                    proxy.scrollTo("market-map", anchor: .bottom)
                }
                #endif
            }
            #if DEBUG
            .onChange(of: store.dashboard?.marketStructure?.generatedAt) { _, generatedAt in
                guard generatedAt != nil,
                      ProcessInfo.processInfo.arguments.contains("--market-structure-preview") else { return }
                proxy.scrollTo("market-structure", anchor: .top)
            }
            #endif
        }
    }

    private var regionalHealthMessage: String? {
        let relevant = store.healthIssues.filter { selectedMarket.relevantHealthSymbols.contains($0.symbol) }
        if let summary = marketHealthSummary(relevant) { return summary }
        return store.healthIssues.isEmpty ? store.errorMessage : nil
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
    static let header = Color(uiColor: .systemBackground)
    static let headerSurface = Color(uiColor: .secondarySystemBackground)
    static let headerDivider = Color(uiColor: .separator).opacity(0.55)
}

private enum MarketRegion: String, CaseIterable, Identifiable {
    case unitedStates = "美国"
    case china = "中国"
    case japan = "日本"
    case korea = "韩国"
    case europe = "欧洲"
    case crypto = "加密"

    var id: Self { self }

    var symbols: [String] {
        switch self {
        case .unitedStates: ["^GSPC", "^NDX", "^DJI", "^VIX"]
        case .china: ["000001.SS", "000300.SS", "000688.SS", "^HSTECH", "^HSI"]
        case .japan: ["^N225"]
        case .korea: ["^KS11"]
        case .europe: ["^STOXX50E", "^GDAXI", "^FTSE", "^FCHI"]
        case .crypto: ["BINANCE:BTCUSDT", "BINANCE:ETHUSDT", "BINANCE:SOLUSDT", "BINANCE:BNBUSDT", "BINANCE:XRPUSDT", "BINANCE:DOGEUSDT"]
        }
    }

    var allSymbols: [String] {
        guard self == .china else { return symbols }
        return [
            "000001.SS", "000016.SS", "000300.SS", "399006.SZ", "000688.SS",
            "000905.SS", "000852.SS", "932000.SS", "THS:883418", "^HSTECH", "^HSI"
        ]
    }

    var primarySymbol: String { symbols[0] }

    var relevantHealthSymbols: Set<String> {
        switch self {
        case .unitedStates: Set(symbols + ["^TNX"])
        case .china: Set(allSymbols.filter { $0 != "THS:883418" } + ["USDCNY", "399001.SZ"])
        case .japan: Set(symbols + ["USDJPY", "JP10Y", "^TOPX"])
        case .korea: Set(symbols + ["USDKRW", "KR10Y"])
        case .europe: Set(symbols)
        case .crypto: Set(symbols)
        }
    }
}

private struct MarketTerminalHero: View {
    let store: MarketStore
    let region: MarketRegion
    let onSelectIndex: (String) -> Void

    private var quote: MarketQuote? { store.quote(symbol: region.primarySymbol) }
    private var overnightQuote: MarketQuote? {
        guard region == .unitedStates, quote?.marketSession != "regular",
              let session = store.dashboard?.indexSessions?[region.primarySymbol],
              session.marketSession == "regular" else { return nil }
        return session
    }
    private var displayedQuote: MarketQuote? { overnightQuote ?? quote }

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
                .foregroundStyle(Color.secondary)
            }

            Button { if quote != nil { onSelectIndex(region.primarySymbol) } } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(quote?.name ?? CoreDescriptor(symbol: region.primarySymbol).name)
                            .font(.system(size: 22, weight: .semibold))
                            .lineLimit(1)
                            .layoutPriority(1)
                        Text(overnightQuote.map { "\(CoreDescriptor(symbol: region.primarySymbol).code) · \($0.displayCode) 夜盘" }
                            ?? quote?.displayCode
                            ?? CoreDescriptor(symbol: region.primarySymbol).code)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Spacer(minLength: 0)
                    }
                    HStack(alignment: .bottom, spacing: 15) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(displayedQuote.map { number($0.price, digits: cryptoPriceDigits($0.price, symbol: $0.symbol)) } ?? "—")
                                .font(.system(size: 36, weight: .semibold))
                                .monospacedDigit()
                                .tracking(-0.8)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            Text(displayedQuote.map { "\(signed($0.changeValue, digits: cryptoChangeDigits($0)))  \($0.formattedPercent)" } ?? "等待行情")
                                .font(.system(size: 16, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(quoteTint(displayedQuote))
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)
                        }
                        .frame(width: 142, alignment: .leading)

                        TerminalLeadChart(
                            quote: displayedQuote,
                            trend: store.trendValues(for: displayedQuote),
                            isOvernight: overnightQuote != nil
                        )
                             .frame(maxWidth: .infinity, minHeight: 128)
                     }
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(MarketPressStyle())
            .accessibilityLabel(heroAccessibilityLabel)
            .accessibilityHint("打开代表指数详情")

            Group {
            if region == .crypto {
                HStack(spacing: 0) {
                    cryptoMetric(symbol: "BINANCE:ETHUSDT")
                    TerminalDivider()
                    cryptoMetric(symbol: "BINANCE:SOLUSDT")
                    TerminalDivider()
                    cryptoMetric(symbol: "BINANCE:BNBUSDT")
                }
                .frame(height: 76)
            } else if region == .china {
                ChinaMarketMetrics(store: store)
            } else if region == .japan {
                RegionalMarketMetrics(
                    store: store,
                    exchangeTitle: "美元兑日元",
                    exchangeSymbol: "USDJPY",
                    exchangeDigits: 2,
                    yieldTitle: "日本 10Y 国债",
                    yieldSymbol: "JP10Y",
                    companionTitle: "东证指数",
                    companionSymbol: "^TOPX"
                )
            } else if region == .korea {
                RegionalMarketMetrics(
                    store: store,
                    exchangeTitle: "美元兑韩元",
                    exchangeSymbol: "USDKRW",
                    exchangeDigits: 1,
                    yieldTitle: "韩国 10Y 国债",
                    yieldSymbol: "KR10Y",
                    companionTitle: "KOSPI 指数",
                    companionSymbol: "^KS11"
                )
            } else if region == .unitedStates {
                HStack(spacing: 0) {
                     MarketTerminalMetric(
                        title: "VIX 恐慌指数",
                        value: store.quote(symbol: "^VIX").map { number($0.price, digits: 1) } ?? "—",
                        change: store.quote(symbol: "^VIX")?.formattedPercent ?? "—",
                        tint: quoteTint(store.quote(symbol: "^VIX")),
                         trend: store.trendValues(for: store.quote(symbol: "^VIX"))
                    )
                    TerminalDivider()
                    MarketTerminalSentiment(sentiment: store.dashboard?.sentiment)
                    TerminalDivider()
                    MarketTerminalMetric(
                        title: "美国 10Y 国债收益率",
                        value: store.quote(symbol: "^TNX").map { String(format: "%.2f%%", $0.price) } ?? "—",
                        change: store.quote(symbol: "^TNX")?.formattedPercent ?? "—",
                        tint: quoteTint(store.quote(symbol: "^TNX")),
                         trend: store.trendValues(for: store.quote(symbol: "^TNX"))
                    )
                }
            } else {
                 EuropeMarketMetrics(store: store)
            }
            }
            .frame(height: 76)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(MarketTerminalPalette.header)
    }

    private var sessionLabel: String {
        if region == .crypto { return "24H 交易中" }
        if overnightQuote != nil { return "夜盘" }
        return switch quote?.marketSession {
        case "regular": "交易中"
        case "pre": "盘前"
        case "post", "after": "盘后"
        default: "已收盘"
        }
    }

    private var sessionTint: Color {
        region == .crypto || quote?.marketSession == "regular" || overnightQuote != nil
            ? Color(red: 0.08, green: 0.83, blue: 0.47)
            : Color.secondary
    }

    private func cryptoMetric(symbol: String) -> some View {
        let value = store.quote(symbol: symbol)
        return MarketTerminalMetric(
            title: value?.name ?? CoreDescriptor(symbol: symbol).name,
            value: value.map { number($0.price, digits: cryptoPriceDigits($0.price, symbol: $0.symbol)) } ?? "—",
            change: value?.formattedPercent ?? "—",
            tint: quoteTint(value),
            trend: store.trendValues(for: value)
        )
    }

    private var heroDate: String {
        let date = quote?.timestamp.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? Date()
        return date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))
    }

    private var heroAccessibilityLabel: String {
        let name = quote?.name ?? CoreDescriptor(symbol: region.primarySymbol).name
        guard let displayedQuote else { return "\(name)，等待行情" }
        return "\(name)，最新价 \(number(displayedQuote.price, digits: cryptoPriceDigits(displayedQuote.price, symbol: displayedQuote.symbol)))，\(displayedQuote.formattedPercent)，\(sessionLabel)"
    }
}

private struct EuropeMarketMetrics: View {
    let store: MarketStore

    var body: some View {
        HStack(spacing: 0) {
            metric("欧洲50", "^STOXX50E")
            TerminalDivider()
            metric("德国 DAX", "^GDAXI")
            TerminalDivider()
            metric("英国 FTSE", "^FTSE")
        }
    }

    private func metric(_ title: String, _ symbol: String) -> some View {
        let quote = store.quote(symbol: symbol)
        return MarketTerminalMetric(
            title: title,
            value: quote.map { number($0.price, digits: 2) } ?? "—",
            change: quote?.formattedPercent ?? "等待行情",
            tint: quoteTint(quote),
            trend: quote?.trend ?? []
        )
    }
}

private struct RegionalMarketMetrics: View {
    let store: MarketStore
    let exchangeTitle: String
    let exchangeSymbol: String
    let exchangeDigits: Int
    let yieldTitle: String
    let yieldSymbol: String
    let companionTitle: String
    let companionSymbol: String

    private var exchangeQuote: MarketQuote? { store.quote(symbol: exchangeSymbol) }
    private var yieldQuote: MarketQuote? { store.quote(symbol: yieldSymbol) }
    private var companionQuote: MarketQuote? { store.quote(symbol: companionSymbol) }

    var body: some View {
        HStack(spacing: 0) {
            MarketTerminalMetric(
                title: exchangeTitle,
                value: exchangeQuote.map { number($0.price, digits: exchangeDigits) } ?? "—",
                change: exchangeQuote?.formattedPercent ?? exchangeSymbol,
                tint: quoteTint(exchangeQuote),
                trend: exchangeQuote?.trend ?? []
            )
            TerminalDivider()
            MarketTerminalMetric(
                title: yieldTitle,
                value: yieldQuote.map { String(format: "%.2f%%", $0.price) } ?? "—",
                change: yieldQuote?.formattedPercent ?? "等待行情",
                tint: quoteTint(yieldQuote),
                trend: yieldQuote?.trend ?? []
            )
            TerminalDivider()
            MarketTerminalMetric(
                title: companionTitle,
                value: companionQuote.map { number($0.price, digits: 2) } ?? "—",
                change: companionQuote?.formattedPercent ?? "等待行情",
                tint: quoteTint(companionQuote),
                trend: companionQuote?.trend ?? []
            )
        }
    }
}

private struct ChinaMarketMetrics: View {
    let store: MarketStore

    private var exchangeRate: MarketQuote? { store.quote(symbol: "USDCNY") }
    private var breadth: MarketBreadth? { store.dashboard?.currentAShareBreadth }
    private var breadthIsStale: Bool { store.dashboard?.ashareOverview?.stale == true }
    private var turnoverMetric: (title: String, value: Double, note: String)? {
        let shanghai = store.quote(symbol: "000001.SS")?.turnover
        let shenzhen = store.quote(symbol: "399001.SZ")?.turnover
        return switch (shanghai, shenzhen) {
        case let (.some(shanghai), .some(shenzhen)): ("两市成交额", shanghai + shenzhen, "沪深合计")
        case let (.some(shanghai), .none): ("沪市成交额", shanghai, "深市待补")
        case let (.none, .some(shenzhen)): ("深市成交额", shenzhen, "沪市待补")
        case (.none, .none): nil
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            MarketTerminalMetric(
                title: "人民币汇率",
                value: exchangeRate.map { number($0.price, digits: 4) } ?? "—",
                change: exchangeRate?.formattedPercent ?? "USD/CNY",
                tint: quoteTint(exchangeRate),
                trend: exchangeRate?.trend ?? []
            )
            TerminalDivider()
            MarketTerminalMetric(
                title: turnoverMetric?.title ?? "成交额",
                value: turnoverMetric.map { turnoverText($0.value) } ?? "—",
                change: turnoverMetric?.note ?? "等待行情",
                tint: .secondary,
                trend: []
            )
            TerminalDivider()
            MarketBreadthMetric(breadth: breadth, isStale: breadthIsStale)
        }
    }

    private func turnoverText(_ value: Double) -> String {
        if value >= 100_000_000_000 { return String(format: "%.1f万亿", value / 1_000_000_000_000) }
        return String(format: "%.0f亿", value / 100_000_000)
    }
}

private struct MarketBreadthMetric: View {
    let breadth: MarketBreadth?
    var isStale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("市场宽度").font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            Text(isStale ? "数据过期" : (breadth.map { "\($0.up) / \($0.down)" } ?? "—"))
                .font(.system(size: 15, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.72)
            HStack(spacing: 3) {
                if isStale {
                    Text("等待实时刷新").foregroundStyle(.secondary)
                } else {
                    Text("上涨").foregroundStyle(MarketStyle.gain)
                    Text("/").foregroundStyle(.secondary)
                    Text("下跌").foregroundStyle(MarketStyle.loss)
                }
            }
            .font(.system(size: 9.5, weight: .medium))
            MarketBreadthComposition(
                up: breadth?.up ?? 0,
                down: breadth?.down ?? 0,
                flat: breadth?.flat ?? 0,
                total: breadth.map { max($0.total, $0.up + $0.down + $0.flat) } ?? 0
            )
            .frame(height: 5)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct TerminalLeadChart: View {
    let quote: MarketQuote?
    let trend: [Double]
    let isOvernight: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        Rectangle().fill(Color.secondary.opacity(index == 1 ? 0.20 : 0.11)).frame(height: 0.5)
                        if index < 2 { Spacer() }
                    }
                }
                Sparkline(values: trend, color: quoteTint(quote))
                    .padding(.vertical, 5)
            }
            HStack {
                Text(isOvernight ? "夜盘开盘" : "开盘")
                Spacer()
                Text(isOvernight ? "夜盘中" : "盘中")
                Spacer()
                Text(trailingLabel)
            }
            .font(.caption2)
            .foregroundStyle(Color.secondary)
        }
    }

    private var trailingLabel: String {
        switch quote?.marketSession {
        case "regular", "pre": "最新"
        default: "收盘"
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
            Text(title).font(.caption2.weight(.medium)).foregroundStyle(Color.secondary).lineLimit(1).minimumScaleFactor(0.75)
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 17, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .layoutPriority(1)
                    Text(change)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                Spacer(minLength: 3)
                Sparkline(values: trend, color: tint, showsFill: false).frame(width: 28, height: 24)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 7)
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
                    .foregroundStyle(Color.secondary)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(sentiment.map { String(Int($0.score.rounded())) } ?? "—")
                        .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                    Text("/100").font(.caption2).foregroundStyle(Color.secondary)
                }
                Text(sentimentChange)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(sentimentTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.20), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(sentiment?.score ?? 0, 0), 100) / 100))
                    .stroke(Color(red: 0.05, green: 0.80, blue: 0.66), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 32, height: 32)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sentimentChange: String {
        guard let score = sentiment?.score, let previous = sentiment?.previousClose else { return "较前值 —" }
        return "较前值 \(signed(score - previous, digits: 1))"
    }

    private var sentimentTint: Color {
        guard let score = sentiment?.score, let previous = sentiment?.previousClose else { return Color.secondary }
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
        .padding(.horizontal, 18)
        .overlay(alignment: .bottom) { Divider().opacity(0.5).padding(.horizontal, 18) }
    }
}

private struct MarketIndexTable: View {
    let region: MarketRegion
    let store: MarketStore
    let onSelectIndex: (String) -> Void

    @State private var chinaScope: ChinaIndexScope = .core

    private var symbols: [String] { region == .china && chinaScope == .all ? region.allSymbols : region.symbols }
    private var quotes: [MarketQuote] { symbols.compactMap { store.quote(symbol: $0) } }

    var body: some View {
        VStack(spacing: 0) {
            if region == .china {
                ChinaIndexScopePicker(selection: $chinaScope)
            }
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
                         MarketIndexTableRow(
                             quote: quote,
                             overnightQuote: region == .unitedStates && quote.marketSession != "regular"
                                 ? store.dashboard?.indexSessions?[quote.symbol]
                                 : nil,
                             trend: store.trendValues(for: region == .unitedStates && quote.marketSession != "regular"
                                 ? store.dashboard?.indexSessions?[quote.symbol] ?? quote
                                 : quote)
                         )
                    }
                    .buttonStyle(MarketPressStyle())
                    if index < quotes.count - 1 { Divider().opacity(0.45).padding(.leading, 12) }
                }
            }

            if region == .unitedStates, let components = store.dashboard?.components, !components.isEmpty {
                HStack {
                    Text(store.dashboard?.componentsMeta?.label ?? "主要成分股")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 6)

                Divider().opacity(0.45)
                ForEach(Array(components.enumerated()), id: \.element.symbol) { index, quote in
                    Button { onSelectIndex(quote.symbol) } label: {
                        MarketIndexTableRow(
                            quote: quote,
                            overnightQuote: nil,
                            trend: store.trendValues(for: quote)
                        )
                    }
                    .buttonStyle(MarketPressStyle())
                    if index < components.count - 1 { Divider().opacity(0.45).padding(.leading, 12) }
                }
            }

        }
        .padding(.horizontal, 18)
        .animation(.easeOut(duration: 0.16), value: region)
    }
}

private struct ChinaMarketStructurePanel: View {
    let structure: MarketStructure?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("资金与杠杆信号")
                        .font(.headline)
                    Text("交易所官方日频数据 · 趋势判断不代表预测")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let asOf = structure?.marginBalance.asOf {
                    Text("截至 \(asOf)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let structure {
                if let combinedSignal = structure.combinedSignal {
                    CombinedCapitalSignal(signal: combinedSignal)
                    Divider().opacity(0.45)
                }
                ETFSubscriptionSignal(subscription: structure.etfSubscription)
                Divider().opacity(0.45)
                MarginBalanceSignal(balance: structure.marginBalance)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在等待 ETF 份额与两融余额日频数据")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            }
        }
        .padding(16)
        .marketCard(cornerRadius: 16)
        .padding(.horizontal, 18)
        .padding(.top, 20)
    }
}

private struct CombinedCapitalSignal: View {
    let signal: MarketCombinedSignal

    private var tint: Color {
        switch signal.status {
        case "resonance": MarketStyle.gain
        case "allocation_support": .blue
        case "leverage_driven": .orange
        case "risk_off": MarketStyle.loss
        default: .secondary
        }
    }

    private var icon: String {
        switch signal.status {
        case "resonance": "arrow.trianglehead.2.clockwise.rotate.90"
        case "allocation_support": "shield.lefthalf.filled"
        case "leverage_driven": "bolt.fill"
        case "risk_off": "arrow.down.right"
        default: "arrow.left.and.right"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(signal.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(signal.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ETFSubscriptionSignal: View {
    let subscription: MarketETFSubscription

    private var tint: Color {
        subscription.status == "outflow" ? MarketStyle.loss : MarketStyle.gain
    }

    private var statusLabel: String {
        switch subscription.status {
        case "accelerating": "持续放量"
        case "inflow": "保持净申购"
        case "outflow": "转为净赎回"
        default: "多空交错"
        }
    }

    private var streakLabel: String {
        guard subscription.consecutiveDays > 0 else { return "连续性待观察" }
        let direction = subscription.consecutiveDirection == "outflow" ? "净赎回" : "净申购"
        return "连续 \(subscription.consecutiveDays) 日\(direction)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("科创50ETF 合计净申购", systemImage: "arrow.left.arrow.right.circle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                MarketSignalBadge(label: statusLabel, tint: tint)
            }
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(marketSignedShares(subscription.latestNetSubscriptionShares))
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(subscription.latestNetSubscriptionShares >= 0 ? MarketStyle.gain : MarketStyle.loss)
                    Text("当日份额变化 · \(subscription.fundCount ?? 1) 只主要ETF")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                MarketFlowBars(values: subscription.points.suffix(10).map(\.netSubscriptionShares))
                    .frame(width: 112, height: 42)
            }
            HStack(spacing: 12) {
                MarketSignalDatum(title: "近 5 日", value: marketSignedShares(subscription.netSubscriptionShares5d))
                MarketSignalDatum(title: "前 5 日", value: marketSignedShares(subscription.previousNetShares5d))
                MarketSignalDatum(title: "净流入天数", value: "\(subscription.positiveDays5d) / 5")
            }
            if let estimatedFlow = subscription.latestEstimatedNetFlowCNY,
               let coverage = subscription.estimatedFlowFundCount,
               coverage > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "yensign.circle")
                    Text("按收盘价估算当日净流入 \(marketSignedMoney(estimatedFlow))")
                    Spacer(minLength: 4)
                    Text("覆盖 \(coverage) 只")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
            }
            Text("\(streakLabel)；净申购按上交所披露的每日基金总份额变化计算。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MarginBalanceSignal: View {
    let balance: MarketMarginBalance

    private var tint: Color {
        switch balance.riskAppetite {
        case .strong: MarketStyle.gain
        case .repairing: .blue
        case .weak: .orange
        case .uncertain: .secondary
        }
    }

    private var statusLabel: String {
        switch balance.riskAppetite {
        case .strong: "明显走强"
        case .repairing: "企稳修复"
        case .weak: "偏弱"
        case .uncertain: "方向待定"
        }
    }

    private var summary: String {
        switch balance.riskAppetite {
        case .strong:
            "短中期余额同步回升，杠杆资金风险偏好明显走强。"
        case .repairing where balance.latestChange > 0:
            "单日资金回流，短期跌势正在收窄，处于企稳修复阶段。"
        case .repairing:
            "短期跌幅已经收窄，杠杆资金处于企稳观察阶段。"
        case .weak where balance.latestChange > 0:
            "单日有所回流，但 3 日及 5 日趋势仍向下，尚未形成企稳信号。"
        case .weak:
            "日、3 日及 5 日趋势仍向下，杠杆资金风险偏好偏弱。"
        case .uncertain:
            "日、3 日与 5 日变化方向不一致，风险偏好方向仍待确认。"
        }
    }

    private var summaryIcon: String {
        switch balance.riskAppetite {
        case .strong: "arrow.up.right"
        case .repairing: "waveform.path.ecg"
        case .weak: "arrow.down.right"
        case .uncertain: "arrow.left.and.right"
        }
    }

    private var activityLabel: String {
        switch balance.activityStatus {
        case "aggressive": "偏积极"
        case "active": "中性活跃"
        case "cautious": "偏谨慎"
        default: "待更新"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("沪深两融余额", systemImage: "scale.3d")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                MarketSignalBadge(label: statusLabel, tint: tint)
            }
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(marketMoney(balance.totalBalance))
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("沪深两融余额 · 日变动 \(marketSignedMoney(balance.latestChange))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Sparkline(
                    values: balance.points.suffix(15).map(\.totalBalance),
                    color: tint,
                    showsFill: true
                )
                .frame(width: 112, height: 42)
            }
            HStack(spacing: 12) {
                MarketSignalDatum(title: "3 日变化", value: marketSignedMoney(balance.change3d))
                MarketSignalDatum(title: "5 日变化", value: marketSignedMoney(balance.change5d))
                MarketSignalDatum(title: "回升天数", value: "\(balance.positiveDays5d) / 5")
            }
            if let ratio = balance.financingBuyRatio {
                HStack(spacing: 7) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .foregroundStyle(tint)
                    Text("融资买入占A股成交额")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f%%", ratio))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Spacer(minLength: 4)
                    Text(activityLabel)
                        .fontWeight(.semibold)
                        .foregroundStyle(tint)
                }
                .font(.caption2)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: summaryIcon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("杠杆风险偏好：\(statusLabel)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("判断综合余额趋势与融资买入活跃度；两融数据仅作为杠杆风险偏好的代理指标。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MarketSignalBadge: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(height: 23)
            .background(tint.opacity(0.10), in: Capsule())
    }
}

private struct MarketSignalDatum: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarketFlowBars: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let maximum = max(values.map(abs).max() ?? 0, 1)
            let width = proxy.size.width / CGFloat(max(values.count, 1))
            let middle = proxy.size.height / 2
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: middle))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: middle))
                }
                .stroke(Color.secondary.opacity(0.20), lineWidth: 0.5)
                flowPath(values: values, positive: true, maximum: maximum, width: width, middle: middle)
                    .fill(MarketStyle.gain.opacity(0.86))
                flowPath(values: values, positive: false, maximum: maximum, width: width, middle: middle)
                    .fill(MarketStyle.loss.opacity(0.86))
            }
        }
    }

    private func flowPath(values: [Double], positive: Bool, maximum: Double, width: CGFloat, middle: CGFloat) -> Path {
        Path { path in
            for (index, value) in values.enumerated() where (value >= 0) == positive {
                let height = max(1, middle * CGFloat(abs(value) / maximum))
                let x = CGFloat(index) * width + 1
                let y = positive ? middle - height : middle
                path.addRoundedRect(
                    in: CGRect(x: x, y: y, width: max(1, width - 2), height: height),
                    cornerSize: CGSize(width: 1.5, height: 1.5)
                )
            }
        }
    }
}

private func marketSignedShares(_ value: Double) -> String {
    String(format: "%@%.2f亿份", value >= 0 ? "+" : "−", abs(value) / 100_000_000)
}

private func marketMoney(_ value: Double) -> String {
    if value >= 1_000_000_000_000 { return String(format: "%.2f万亿", value / 1_000_000_000_000) }
    return String(format: "%.0f亿", value / 100_000_000)
}

private func marketSignedMoney(_ value: Double) -> String {
    String(format: "%@%.0f亿", value >= 0 ? "+" : "−", abs(value) / 100_000_000)
}

private enum ChinaIndexScope: String, CaseIterable, Identifiable {
    case core = "核心"
    case all = "全部 A 股指数"
    var id: Self { self }
}

private struct ChinaIndexScopePicker: View {
    @Binding var selection: ChinaIndexScope

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ChinaIndexScope.allCases) { scope in
                Button { withAnimation(.easeOut(duration: 0.16)) { selection = scope } } label: {
                    Text(scope.rawValue)
                        .font(.caption.weight(selection == scope ? .semibold : .medium))
                        .foregroundStyle(selection == scope ? MarketStyle.accent : Color.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(selection == scope ? MarketStyle.accent.opacity(0.09) : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == scope ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

private struct MarketIndexTableRow: View {
    let quote: MarketQuote
    let overnightQuote: MarketQuote?
    private var displayedQuote: MarketQuote { overnightQuote ?? quote }
    let trend: [Double]

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

            Text(number(displayedQuote.price, digits: cryptoPriceDigits(displayedQuote.price, symbol: displayedQuote.symbol)))
                .font(.system(size: 13.5, weight: .medium)).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(1).minimumScaleFactor(0.72)

            VStack(alignment: .trailing, spacing: 3) {
                Text(displayedQuote.formattedPercent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(signed(displayedQuote.changeValue, digits: cryptoChangeDigits(displayedQuote)))
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .font(.footnote.weight(.semibold)).monospacedDigit()
            .foregroundStyle(quoteTint(displayedQuote))
            .frame(width: 64, alignment: .trailing)

            Sparkline(values: trend, color: quoteTint(displayedQuote))
                .frame(width: 60, height: 32)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开指数详情")
    }

    private var sessionLabel: String { overnightQuote != nil ? "夜盘" : (quote.marketSession == "always-open" || quote.symbol.hasPrefix("BINANCE:") ? "24H" : (quote.marketSession == "regular" ? "交易中" : "已收盘")) }
    private var sessionTint: Color { overnightQuote != nil || quote.marketSession == "always-open" || quote.symbol.hasPrefix("BINANCE:") || quote.marketSession == "regular" ? MarketStyle.accent : .secondary }
}

private struct MarketWorldMap: View {
    let store: MarketStore
    @Binding var selection: MarketRegion
    @Environment(\.colorScheme) private var colorScheme

    private let markets: [MarketMapLocation] = [
        .init(region: .unitedStates, city: "纽约", latitude: 40.71, longitude: -74.00),
        .init(region: .china, city: "上海", latitude: 31.23, longitude: 121.47, labelOffset: .init(width: -30, height: 30)),
        .init(region: .japan, city: "东京", latitude: 35.68, longitude: 139.69, labelOffset: .init(width: 6, height: 22)),
        .init(region: .korea, city: "首尔", latitude: 37.56, longitude: 126.97, labelOffset: .init(width: -8, height: -30)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("全球市场地图").font(.title3.weight(.semibold))
                Spacer()
                MarketLiveStatus(store: store)
            }
            .padding(.horizontal, 18)

            VStack(spacing: 0) {
                GeometryReader { proxy in
                    ZStack {
                        mapBackground

                        ForEach(markets) { market in
                            Button { select(market.region) } label: {
                                MarketMapNode(
                                    country: market.city,
                                    quote: store.quote(symbol: market.region.primarySymbol),
                                    isSelected: selection == market.region
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(mapAccessibilityLabel(for: market))
                            .accessibilityHint("切换到\(market.region.rawValue)市场")
                            .position(market.position(in: proxy.size))
                            .offset(market.labelOffset)
                        }
                    }
                }
                .frame(height: 176)

                MarketSessionSchedule(region: selection)
            }
            .padding(.horizontal, 14)
        }
    }

    @ViewBuilder private var mapBackground: some View {
        if colorScheme == .dark {
            Image("MarketWorldMap")
                .resizable()
                .scaledToFill()
                .colorInvert()
                .saturation(0)
                .contrast(1.05)
                .brightness(0.02)
                .opacity(0.95)
                .accessibilityHidden(true)
        } else {
            Image("MarketWorldMap")
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        }
    }

    private func select(_ region: MarketRegion) {
        withAnimation(.easeOut(duration: 0.18)) { selection = region }
    }

    private func mapAccessibilityLabel(for market: MarketMapLocation) -> String {
        let quote = store.quote(symbol: market.region.primarySymbol)
        return "\(market.region.rawValue)，\(quote?.formattedPercent ?? "等待行情")"
    }
}

private struct MarketSessionSchedule: View {
    let region: MarketRegion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 10) {
                Divider().opacity(0.55)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(region.cityName) · 北京时间")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(currentStatus(at: context.date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MarketStyle.accent)
                }

                HStack(spacing: 0) {
                    ForEach(Array(periods(at: context.date).enumerated()), id: \.offset) { index, period in
                        VStack(spacing: 4) {
                            Text(period.title)
                                .font(.caption.weight(activePeriod(at: context.date) == index ? .semibold : .medium))
                            Text(period.time)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(activePeriod(at: context.date) == index ? MarketStyle.accent : .secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(activePeriod(at: context.date) == index ? MarketStyle.accent.opacity(0.08) : .clear)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(activePeriod(at: context.date) == index ? MarketStyle.accent : MarketStyle.divider)
                                .frame(height: activePeriod(at: context.date) == index ? 2 : 0.5)
                        }
                    }
                }

                if region == .unitedStates {
                    Text(newYorkIsDaylightSaving(at: context.date) ? "当前为夏令时；冬令时各时段自动顺延 1 小时" : "当前为冬令时；App 已自动完成北京时间换算")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(region.sessionNote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 14)
    }

    private func periods(at date: Date) -> [SessionPeriod] {
        switch region {
        case .unitedStates:
            let summer = newYorkIsDaylightSaving(at: date)
            return summer
                ? [.init("夜盘", "08:00–16:00"), .init("盘前", "16:00–21:30"), .init("常规", "21:30–次日04:00"), .init("盘后", "04:00–08:00")]
                : [.init("夜盘", "09:00–17:00"), .init("盘前", "17:00–22:30"), .init("常规", "22:30–次日05:00"), .init("盘后", "05:00–09:00")]
        case .china:
            return [.init("上午盘", "09:30–11:30"), .init("午间休市", "11:30–13:00"), .init("下午盘", "13:00–15:00")]
        case .japan:
            return [.init("上午盘", "08:00–10:30"), .init("午间休市", "10:30–11:30"), .init("下午盘", "11:30–14:30")]
        case .korea:
            return [.init("常规交易", "08:00–14:30")]
        case .europe:
            return berlinIsDaylightSaving(at: date)
                ? [.init("常规交易", "15:00–23:30")]
                : [.init("常规交易", "16:00–次日00:30")]
        case .crypto:
            return [.init("全天交易", "00:00–24:00")]
        }
    }

    private func activePeriod(at date: Date) -> Int? {
        guard isTradingWeekday(date) || region == .crypto else { return nil }
        let minute = beijingMinute(date)
        switch region {
        case .unitedStates:
            let shift = newYorkIsDaylightSaving(at: date) ? 0 : 60
            if ((480 + shift)..<(960 + shift)).contains(minute) { return 0 }
            if ((960 + shift)..<(1290 + shift)).contains(minute) { return 1 }
            if minute >= 1290 + shift || minute < 240 + shift { return 2 }
            if ((240 + shift)..<(480 + shift)).contains(minute) { return 3 }
        case .china:
            if (570..<690).contains(minute) { return 0 }
            if (690..<780).contains(minute) { return 1 }
            if (780..<900).contains(minute) { return 2 }
        case .japan:
            if (480..<630).contains(minute) { return 0 }
            if (630..<690).contains(minute) { return 1 }
            if (690..<870).contains(minute) { return 2 }
        case .korea:
            if (480..<870).contains(minute) { return 0 }
        case .europe:
            let start = berlinIsDaylightSaving(at: date) ? 900 : 960
            let end = berlinIsDaylightSaving(at: date) ? 1410 : 30
            if end > start ? (start..<end).contains(minute) : (minute >= start || minute < end) { return 0 }
        case .crypto:
            return 0
        }
        return nil
    }

    private func currentStatus(at date: Date) -> String {
        guard let index = activePeriod(at: date) else { return region == .crypto ? "24H 交易中" : "当前已收盘" }
        return "当前：\(periods(at: date)[index].title)"
    }

    private func beijingMinute(_ date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func isTradingWeekday(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        let identifier: String
        switch region {
        case .unitedStates: identifier = "America/New_York"
        case .china, .crypto: identifier = "Asia/Shanghai"
        case .japan: identifier = "Asia/Tokyo"
        case .korea: identifier = "Asia/Seoul"
        case .europe: identifier = "Europe/Berlin"
        }
        calendar.timeZone = TimeZone(identifier: identifier)!
        return !calendar.isDateInWeekend(date)
    }

    private func newYorkIsDaylightSaving(at date: Date) -> Bool {
        TimeZone(identifier: "America/New_York")?.isDaylightSavingTime(for: date) == true
    }

    private func berlinIsDaylightSaving(at date: Date) -> Bool {
        TimeZone(identifier: "Europe/Berlin")?.isDaylightSavingTime(for: date) == true
    }
}

private struct SessionPeriod {
    let title: String
    let time: String

    init(_ title: String, _ time: String) {
        self.title = title
        self.time = time
    }
}

private extension MarketRegion {
    var cityName: String {
        switch self {
        case .unitedStates: "纽约"
        case .china: "上海"
        case .japan: "东京"
        case .korea: "首尔"
        case .europe: "法兰克福"
        case .crypto: "加密市场"
        }
    }

    var sessionNote: String {
        switch self {
        case .china: "午间休市 11:30–13:00；法定节假日休市"
        case .japan: "以上时间已由东京时间换算为北京时间"
        case .korea: "以上时间已由首尔时间换算为北京时间"
        case .europe: "以上时间已由欧洲中部时间换算为北京时间"
        case .crypto: "全年无休，行情以 USDT 计价"
        case .unitedStates: ""
        }
    }
}

private struct MarketMapLocation: Identifiable {
    let region: MarketRegion
    let city: String
    let latitude: Double
    let longitude: Double
    var labelOffset = CGSize.zero
    var id: MarketRegion { region }

    func position(in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width * CGFloat((longitude + 180) / 360),
            y: size.height * CGFloat((83 - latitude) / 155)
        )
    }
}

private struct MarketMapNode: View {
    let country: String
    let quote: MarketQuote?
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Circle()
                .fill(isSelected ? Color(uiColor: .systemBackground) : nodeTint)
                .frame(width: 7, height: 7)
                .overlay {
                    if isSelected {
                        Circle().stroke(MarketStyle.accent, lineWidth: 3)
                    }
                }
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(country)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(quote?.formattedPercent ?? "—")
                    .font(.system(size: 9.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(quoteTint(quote))
            }
        }
        .padding(5)
        .contentShape(Rectangle())
    }

    private var nodeTint: Color {
        isSelected ? MarketStyle.accent : quoteTint(quote)
    }
}

private struct MarketSessionColumn: View {
    let city: String
    let quote: MarketQuote?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(city)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? MarketStyle.accent : .primary)
            HStack(spacing: 4) {
                Circle().fill(sessionTint).frame(width: 5, height: 5)
                Text(sessionLabel).font(.caption2.weight(.medium))
            }
            .foregroundStyle(sessionTint)
            Capsule()
                .fill(isSelected ? MarketStyle.accent : Color.clear)
                .frame(width: 28, height: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var sessionLabel: String {
        switch quote?.marketSession {
        case "regular": "交易中"
        case "pre": "盘前"
        case "post", "after": "盘后"
        default: "已收盘"
        }
    }

    private var sessionTint: Color { quote?.marketSession == "regular" ? MarketStyle.loss : .secondary }
}

private struct MarketLiveStatus: View {
    let store: MarketStore

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
            if store.isLoading && store.dashboard == nil {
                Text("加载中")
            } else if let age = store.cachedSnapshotAge {
                Text(cacheLabel(age: age))
            } else if store.hasOpenMarket && store.realtimeIsFresh {
                if let delay = store.maximumOpenMarketDelayMinutes {
                    Text("实时连接 · 部分延迟\(delay)分钟")
                } else {
                    Text("实时连接")
                }
            } else if store.realtimeStatus == .connecting || store.realtimeStatus == .reconnecting {
                Text("连接重试中")
            } else if store.realtimeStatus == .connected {
                Text("等待实时行情")
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
        if store.errorMessage != nil || store.realtimeStatus == .reconnecting || (store.cachedSnapshotAge ?? 0) >= 300 { return .orange }
        if store.hasOpenMarket && store.realtimeIsFresh { return MarketStyle.loss }
        return .secondary
    }

    private var accessibilityStatus: String {
        if let error = store.errorMessage { return "行情更新异常：\(error)" }
        if let age = store.cachedSnapshotAge { return "当前显示\(cacheLabel(age: age))" }
        if store.hasOpenMarket && store.realtimeIsFresh { return "行情实时连接正常" }
        if let date = store.latestQuoteDate { return "行情截至 \(date.formatted(date: .abbreviated, time: .shortened))" }
        return "行情等待更新"
    }

    private func cacheLabel(age: TimeInterval) -> String {
        if age >= 86_400 { return "历史缓存 · 超过1天" }
        if age >= 300 { return "缓存数据 · \(max(5, Int(age / 60)))分钟前" }
        return "缓存数据"
    }
}

private struct MarketErrorBanner: View {
    let message: String
    let isRetrying: Bool
    let retry: () async -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            Button { Task { await retry() } } label: {
                if isRetrying {
                    ProgressView().controlSize(.small)
                } else {
                    Text("重试")
                }
            }
                .font(.system(size: 12, weight: .semibold))
                .frame(minWidth: 44, minHeight: 44)
                .disabled(isRetrying)
                .accessibilityLabel(isRetrying ? "正在重试行情" : "重试缺失行情")
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
                    Text(quote.map { "\(signed($0.changeValue, digits: cryptoChangeDigits($0)))  \($0.formattedPercent)" } ?? "等待行情数据")
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
                breadth: store.dashboard?.currentAShareBreadth
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

private struct MarketIndexDetailView: View {
    let symbol: String
    let store: MarketStore
    let onSelectSymbol: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRange = MarketRange.day

    private var quote: MarketQuote? { store.quote(symbol: symbol) }
    private var indexSessionQuote: MarketQuote? { store.dashboard?.indexSessions?[symbol] }
    private var constituent: MarketIndexConstituent? { store.constituent(symbol: symbol) }
    private var companyLogoPath: String? { constituent?.logoPath ?? store.companyLogoPaths[symbol] }
    private var isIndex: Bool { store.dashboard?.coreIndices.contains(where: { $0.symbol == symbol }) == true }

    var body: some View {
        ZStack {
            MarketStyle.canvas.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 15) {
                    detailHeader
                    MarketDetailChart(selectedRange: $selectedRange, symbol: symbol, store: store)
                    keyData
                    if showsCompanyProfile { companyProfile }
                    MarketSummary(quote: quote)
                    if isIndex { componentStocks }
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
        .task {
            if isIndex { await store.loadIndexConstituents(symbol: symbol, force: true) }
            if showsCompanyProfile, let quote { await store.loadCompanyLogo(symbol: quote.symbol, name: quote.name) }
        }
        .refreshable {
            await store.refresh(force: false)
            if isIndex { await store.loadIndexConstituents(symbol: symbol, force: true) }
            await store.loadChart(symbol: symbol, range: selectedRange, force: true)
        }
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
                if let quote, showsCompanyProfile {
                    CompanyLogo(quote: quote, path: companyLogoPath)
                } else {
                    Image(systemName: CoreDescriptor(symbol: symbol).icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.blue)
                        .frame(width: 30, height: 30).background(Color.blue.opacity(0.10), in: Circle())
                }
                Text(quote?.name ?? CoreDescriptor(symbol: symbol).name).font(.system(size: 22, weight: .semibold)).tracking(-0.35)
                Text(quote?.displayCode ?? CoreDescriptor(symbol: symbol).code).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 5).background(Color.primary.opacity(0.06), in: Capsule())
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(quote.map { number($0.price, digits: cryptoPriceDigits($0.price, symbol: $0.symbol)) } ?? "—").font(.system(size: 33, weight: .bold)).monospacedDigit().tracking(-0.8).foregroundStyle(quoteTint(quote))
                    Text(quote.map { "\(signed($0.changeValue, digits: cryptoChangeDigits($0)))  \($0.formattedPercent)" } ?? "等待行情数据")
                        .font(.system(size: 16, weight: .semibold)).monospacedDigit().foregroundStyle(quoteTint(quote))
                    HStack(spacing: 7) {
                        Circle().fill(sessionColor).frame(width: 6, height: 6)
                        Text(sessionText)
                        if let timestamp = quote?.timestamp { Text(marketTimestamp(timestamp)) }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if showsIndexSession, let session = indexSessionQuote {
                        HStack(spacing: 7) {
                            Text("期货夜盘").fontWeight(.semibold)
                            Text(session.symbol)
                            Text(number(session.price, digits: 2)).fontWeight(.semibold).monospacedDigit()
                            Text(session.formattedPercent).fontWeight(.semibold).monospacedDigit().foregroundStyle(quoteTint(session))
                            Sparkline(values: session.trend, color: MarketStyle.purple, showsFill: false)
                                .frame(width: 52, height: 20)
                        }
                        .font(.caption)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(MarketStyle.purple.opacity(0.08), in: Capsule())
                        .accessibilityLabel("期货夜盘，\(session.name)，\(number(session.price, digits: 2))，\(session.formattedPercent)")
                    } else if quote?.isNightSession == true, let quote, let nightPrice = quote.sessionPrice {
                        HStack(spacing: 7) {
                            Text("个股夜盘").fontWeight(.semibold)
                            Text(number(nightPrice, digits: 2)).fontWeight(.semibold).monospacedDigit()
                            Text(quote.formattedSessionPercent ?? "—").fontWeight(.semibold).monospacedDigit()
                            Sparkline(values: quote.nightTrend, color: MarketStyle.purple, showsFill: false)
                                .frame(width: 52, height: 20)
                        }
                        .font(.caption)
                        .foregroundStyle(MarketStyle.purple)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(MarketStyle.purple.opacity(0.08), in: Capsule())
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 18)
    }

    private var keyData: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("关键数据").font(.system(size: 17, weight: .semibold))
            Grid(horizontalSpacing: 10, verticalSpacing: 13) {
                GridRow { metric("开盘", quote?.openPrice); metric("最高", quote?.high, MarketStyle.gain); metric("最低", quote?.low, MarketStyle.loss); metric(isCrypto ? "24H开盘" : "昨收", quote?.previousClose) }
                GridRow { metric("成交量", quote?.volume, compact: true); metric("市值", quote?.marketCap, compact: true); metric("市盈率", quote?.pe); textMetric("状态", quote?.freshnessLabel ?? "更新中") }
            }
            .padding(12).marketCard(cornerRadius: 10)
        }
        .padding(.horizontal, 18)
    }

    private var showsCompanyProfile: Bool {
        !isIndex && (constituent != nil || quote?.marketCap != nil || quote?.pe != nil)
    }

    private var companyProfile: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("公司资料").font(.system(size: 17, weight: .semibold))
            HStack(alignment: .top, spacing: 12) {
                if let quote { CompanyLogo(quote: quote, path: companyLogoPath) }
                VStack(alignment: .leading, spacing: 7) {
                    Text(quote?.name ?? symbol).font(.subheadline.weight(.semibold))
                    Text("股票代码  \(quote?.displayCode ?? symbol)")
                    Text("上市市场  \(companyMarketLabel(symbol))")
                    if let marketCap = quote?.marketCap { Text("总市值  \(compactNumber(marketCap))") }
                    if let pe = quote?.pe { Text("市盈率  \(number(pe, digits: 2))") }
                }
                .font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(14).marketCard(cornerRadius: 10)
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
                    Button {
                        onSelectSymbol(item.quote.symbol)
                    } label: {
                        MarketConstituentRow(item: item, trend: store.trendValues(for: item.quote))
                    }
                    .buttonStyle(.plain)
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
        switch quote?.marketSession { case "regular": "交易中"; case "always-open": "24小时交易"; case "pre": "盘前"; case "post", "after": "盘后"; default: "已收盘" }
    }
    private var isCrypto: Bool { symbol.hasPrefix("BINANCE:") }
    private var sessionColor: Color { quote?.marketSession == "regular" || quote?.marketSession == "always-open" ? MarketStyle.loss : .secondary }

    private var showsIndexSession: Bool {
        guard quote?.marketSession != "regular", let session = indexSessionQuote, let timestamp = session.timestamp else { return false }
        return Date().timeIntervalSince1970 - Double(timestamp) / 1_000 < 10 * 60
    }

    private var shareText: String {
        guard let quote else { return "\(CoreDescriptor(symbol: symbol).name)行情更新中" }
        let timestamp = quote.timestamp.map(marketTimestamp) ?? "时间未知"
        return "\(quote.name)（\(quote.displayCode)）\n最新价：\(number(quote.price, digits: 2))\n涨跌：\(signed(quote.changeValue, digits: 2))  \(quote.formattedPercent)\n状态：\(quote.freshnessLabel) · \(timestamp)\n来源：\(quote.dataSource ?? "行情服务")\n仅供行情参考，不构成投资建议。"
    }
}

struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    var isEnabled = true

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.shouldEnableSwipeBack = isEnabled
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.shouldEnableSwipeBack = isEnabled
        uiViewController.enableSwipeBack()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        var shouldEnableSwipeBack = true

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
            gesture.isEnabled = shouldEnableSwipeBack && navigationController.viewControllers.count > 1
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            shouldEnableSwipeBack && (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}

private struct MarketDetailChart: View {
    @Binding var selectedRange: MarketRange
    let symbol: String
    let store: MarketStore
    @State private var inspectedPoint: MarketChartPoint?

    private var chart: MarketChart? { store.chart(symbol: symbol, range: selectedRange) }
    private var points: [MarketChartPoint] {
        (chart?.candles ?? []).sorted { $0.timestamp < $1.timestamp }
    }
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
                    } else { Text(chartStatusMessage).font(.system(size: 12)).foregroundStyle(.secondary) }
                } else {
                    MarketSessionLineChart(
                        points: points,
                        regularColor: quoteTint(store.quote(symbol: symbol)),
                        interval: chart?.interval
                    )
                        .id(selectedRange)
                        .padding(.leading, 48).padding(.top, 9).padding(.bottom, 6)
                    ChartInspectionOverlay(points: points, selected: $inspectedPoint)
                }
            }
            .frame(height: 184)
            .animation(MarketStyle.chartTransition, value: selectedRange)
            if let inspectedPoint {
                Text("\(chartTime(inspectedPoint.timestamp, range: selectedRange, timezone: chart?.timezone))  \(number(inspectedPoint.displayValue ?? 0, digits: 2))")
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
            Group {
                if hasVolume {
                    VolumeBars(points: points).frame(height: 25).padding(.leading, 48)
                } else {
                    Color.clear.frame(height: 25)
                }
            }
                .overlay(alignment: .topTrailing) {
                    Text(chartCaption)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            if let coverageMessage {
                Text(coverageMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 18)
        .task(id: selectedRange) {
            inspectedPoint = nil
            await store.loadChart(symbol: symbol, range: selectedRange)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(selectedRange.rawValue)行情图表，可拖动查看具体时间和价格")
    }

    private var timelineLabels: [String] {
        guard let first = points.first, let last = points.last else { return ["—", "—", "—"] }
        return [first, points[points.count / 2], last].map { chartTime($0.timestamp, range: selectedRange, timezone: chart?.timezone) }
    }

    private var hasVolume: Bool { points.contains { ($0.volume ?? 0) > 0 } }
    private var chartCaption: String {
        let base = selectedRange.apiInterval == "1m" ? "分时走势" : "日线走势"
        let dated = chart.map { "\(base) · \($0.tradingDate)" } ?? base
        let sessionText = points.contains { $0.session.map { $0 != "regular" && $0 != "closed" } == true } ? " · 含夜盘" : ""
        return hasVolume ? "\(dated)\(sessionText) · 成交量" : "\(dated)\(sessionText)"
    }
    private var coverageMessage: String? {
        guard let quality = chart?.quality else { return nil }
        switch quality.status {
        case .complete:
            guard points.last?.state == "provisional" else { return nil }
            return selectedRange.apiInterval == "1m" ? "当前分钟更新中" : "当日数据更新中"
        case .repairing:
            return "数据补齐中 · 已有 \(quality.actual)/\(quality.expected) 个真实数据点"
        case .partial:
            return "数据不完整 · 缺少 \(max(quality.expected - quality.actual, 0)) 个数据点"
        case .unavailable:
            return "当前交易日暂无可用行情"
        }
    }

    private var chartStatusMessage: String {
        switch chart?.quality.status {
        case .repairing: "数据补齐中"
        case .partial: "该交易日行情不完整"
        case .unavailable: "当前交易日暂无可用行情"
        case .complete, .none: "暂无行情数据"
        }
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
        return number(max - (max - min) * Double(index) / 4, digits: marketAxisDigits(values: values))
    }
}

private struct MarketLineChart: View {
    let values: [Double]
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        AnimatedLineCanvas(values: values, color: color, progress: progress)
            .onAppear {
                if reduceMotion {
                    progress = 1
                } else {
                    withAnimation(.easeOut(duration: 0.45)) { progress = 1 }
                }
            }
    }
}

private struct MarketSessionLineChart: View {
    let points: [MarketChartPoint]
    let regularColor: Color
    let interval: String?

    var body: some View {
        Canvas { context, size in
            let sorted = points.sorted { $0.timestamp < $1.timestamp }
            guard sorted.count > 1,
                  let firstTimestamp = sorted.first?.timestamp,
                  let lastTimestamp = sorted.last?.timestamp,
                  lastTimestamp > firstTimestamp else { return }
            let low = sorted.map(\.close).min() ?? 0
            let high = sorted.map(\.close).max() ?? low
            let span = max(high - low, 0.000_001)
            func canvasPoint(_ point: MarketChartPoint) -> CGPoint {
                CGPoint(
                    x: size.width * marketChartXFraction(timestamp: point.timestamp, firstTimestamp: firstTimestamp, lastTimestamp: lastTimestamp),
                    y: size.height * (0.06 + CGFloat((high - point.close) / span) * 0.88)
                )
            }

            var segment: [MarketChartPoint] = []
            func drawSegment() {
                guard segment.count > 1 else { return }
                var path = Path()
                path.move(to: canvasPoint(segment[0]))
                segment.dropFirst().forEach { path.addLine(to: canvasPoint($0)) }
                let isRegular = segment[0].session == nil || segment[0].session == "regular"
                context.stroke(
                    path,
                    with: .color(isRegular ? regularColor : MarketStyle.purple),
                    style: StrokeStyle(lineWidth: isRegular ? 1.7 : 2, lineCap: .round, lineJoin: .round)
                )
            }

            for point in sorted {
                if let previous = segment.last {
                    if marketChartShouldSplitSegment(previous: previous, current: point, interval: interval) {
                        drawSegment()
                        segment = []
                    }
                }
                segment.append(point)
            }
            drawSegment()
        }
        .accessibilityHidden(true)
    }
}

private struct AnimatedLineCanvas: View, Animatable {
    let values: [Double]
    let color: Color
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let sampleCount = min(max(values.count, 2), 120)
            let samples = normalizedSamples(values, count: sampleCount)
            guard samples.count == sampleCount else { return }

            let reveal = min(max(progress, 0), 1)
            context.clip(to: Path(CGRect(x: 0, y: 0, width: size.width * reveal, height: size.height)))
            let points = samples.enumerated().map { index, sample in
                CGPoint(
                    x: size.width * CGFloat(index) / CGFloat(sampleCount - 1),
                    y: size.height * sample
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
        Canvas { context, size in
            let sorted = points.sorted { $0.timestamp < $1.timestamp }
            guard let firstTimestamp = sorted.first?.timestamp,
                  let lastTimestamp = sorted.last?.timestamp,
                  lastTimestamp > firstTimestamp else { return }
            let maxVolume = max(sorted.compactMap(\.volume).max() ?? 0, 1)
            let fractions = sorted.map {
                marketChartXFraction(timestamp: $0.timestamp, firstTimestamp: firstTimestamp, lastTimestamp: lastTimestamp)
            }
            let minimumGap = zip(fractions, fractions.dropFirst()).map { $1 - $0 }.filter { $0 > 0 }.min() ?? 1
            let barWidth = min(max(size.width * minimumGap * 0.72, 1), 8)

            for (index, point) in sorted.enumerated() {
                guard let volume = point.volume, volume > 0 else { continue }
                let height = max(2, size.height * CGFloat(volume / maxVolume))
                let x = size.width * fractions[index]
                let rect = CGRect(x: x - barWidth / 2, y: size.height - height, width: barWidth, height: height)
                let color = point.close >= point.open ? MarketStyle.gain : MarketStyle.loss
                context.fill(Path(rect), with: .color(color.opacity(0.68)))
            }
        }
        .accessibilityHidden(true)
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
    let trend: [Double]
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
                if quote.isNightSession == true, let nightPrice = quote.sessionPrice {
                    Text("夜 \(number(nightPrice, digits: 2)) \(quote.formattedSessionPercent ?? "")\(nightUpdateTime)")
                        .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(MarketStyle.purple)
                }
            }
            Sparkline(
                values: trend,
                color: quoteTint(quote),
                showsFill: false
            )
                .frame(width: 58, height: 28)
        }
        .padding(.horizontal, 12).frame(minHeight: 66)
        .accessibilityElement(children: .combine)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 10) {
                Text("占比 \(item.weight.map { "\(number($0, digits: 2))%" } ?? "—")")
                Text("市值 \(quote.marketCap.map(compactNumber) ?? "—")")
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.leading, 64)
            .padding(.bottom, 5)
        }
        .padding(.bottom, 12)
        .accessibilityLabel("\(quote.name)，\(quote.symbol)，市值 \(quote.marketCap.map(compactNumber) ?? "未知")，最新价 \(number(quote.price, digits: 2))，\(quote.formattedPercent)，点按查看详情")
    }

    private var nightUpdateTime: String {
        guard let timestamp = quote.timestamp else { return "" }
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1_000)
        return " · " + date.formatted(date: .omitted, time: .standard)
    }
}

private struct CompanyLogo: View {
    let quote: MarketQuote
    let path: String?

    var body: some View {
        AsyncImage(url: logoURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit().padding(6)
            } else if phase.error == nil {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "building.2.crop.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
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
                            path.move(to: CGPoint(x: -2, y: proxy.size.height))
                            path.addLine(to: CGPoint(x: -2, y: first.y))
                            path.addLine(to: first)
                            points.dropFirst().forEach { path.addLine(to: $0) }
                            path.addLine(to: CGPoint(x: proxy.size.width + 2, y: last.y))
                            path.addLine(to: CGPoint(x: proxy.size.width + 2, y: proxy.size.height))
                            path.closeSubpath()
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
    var name: String { switch symbol { case "^GSPC": "标普500"; case "^NDX": "纳斯达克100"; case "^DJI": "道琼斯工业指数"; case "000001.SS": "上证指数"; case "000016.SS": "上证50"; case "000300.SS": "沪深300"; case "399006.SZ": "创业板指"; case "000688.SS": "科创50"; case "000905.SS": "中证500"; case "000852.SS": "中证1000"; case "932000.SS": "中证2000"; case "THS:883418": "微盘股"; case "^HSTECH": "恒生科技指数"; case "^HSI": "恒生指数"; case "^N225": "日经225"; case "^KS11": "韩国KOSPI"; case "^STOXX50E": "欧洲STOXX 50"; case "^GDAXI": "德国DAX"; case "^FTSE": "英国富时100"; case "^FCHI": "法国CAC 40"; default: symbol } }
    var code: String { switch symbol { case "^GSPC": "SPX"; case "^NDX": "NDX"; case "^DJI": "DJI"; case "000001.SS": "000001.SH"; case "000300.SS": "000300.SH"; case "000688.SS": "000688.SH"; case "^HSTECH": "HSTECH"; case "^HSI": "HSI"; case "^N225": "N225"; case "^KS11": "KOSPI"; case "^STOXX50E": "SX5E"; case "^GDAXI": "DAX"; case "^FTSE": "FTSE"; case "^FCHI": "CAC40"; default: symbol } }
    var icon: String { switch symbol { case "^NDX": "n.circle.fill"; case "^DJI": "building.columns.fill"; case "000001.SS", "000300.SS": "building.2.fill"; case "000688.SS": "cpu.fill"; case "^HSTECH": "asterisk"; case "^HSI": "h.circle.fill"; case "^N225": "yensign.circle.fill"; case "^KS11": "k.circle.fill"; case "^STOXX50E": "globe.europe.africa.fill"; case "^GDAXI": "shield.fill"; case "^FTSE": "sterlingsign.circle.fill"; case "^FCHI": "f.circle.fill"; default: "star.fill" } }
}

private func marketLocalTime(_ timestamp: Int64?, city: String, timeZone: String) -> String {
    guard let timestamp else { return "等待更新" }
    let formatter = MarketViewDateFormatters.localTime(timeZone: timeZone)
    return "\(city) \(formatter.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000)))"
}

private func chartPoints(_ values: [Double], size: CGSize) -> [CGPoint] {
    let minValue = values.min() ?? 0, maxValue = values.max() ?? 1, range = max(maxValue - minValue, 0.01)
    return values.enumerated().map { CGPoint(x: size.width * CGFloat($0.offset) / CGFloat(max(values.count - 1, 1)), y: size.height * (1 - CGFloat(($0.element - minValue) / range))) }
}

private func quoteTint(_ quote: MarketQuote?) -> Color { guard let quote else { return .secondary }; return quote.isUp ? MarketStyle.gain : MarketStyle.loss }
private func companyMarketLabel(_ symbol: String) -> String {
    if symbol.hasSuffix(".SS") { return "上海证券交易所" }
    if symbol.hasSuffix(".SZ") { return "深圳证券交易所" }
    if symbol.hasSuffix(".HK") { return "香港交易所" }
    if symbol.hasSuffix(".T") { return "东京证券交易所" }
    if symbol.hasSuffix(".KS") || symbol.hasSuffix(".KQ") { return "韩国证券市场" }
    return "美国证券市场"
}
private func number(_ value: Double, digits: Int) -> String { value.formatted(.number.grouping(.automatic).precision(.fractionLength(digits))) }
private func signed(_ value: Double, digits: Int) -> String { (value >= 0 ? "+" : "−") + number(abs(value), digits: digits) }
private func compactNumber(_ value: Double) -> String { value.formatted(.number.notation(.compactName).precision(.fractionLength(1))) }
private func marketTimestamp(_ timestamp: Int64) -> String {
    marketShortTimestamp(timestamp)
}

private func cryptoPriceDigits(_ price: Double, symbol: String = "BINANCE:") -> Int {
    guard symbol.hasPrefix("BINANCE:") else { return 2 }
    if price < 1 { return 5 }
    if price < 100 { return 3 }
    return 2
}
private func cryptoChangeDigits(_ quote: MarketQuote) -> Int {
    cryptoPriceDigits(max(abs(quote.changeValue), quote.price), symbol: quote.symbol)
}
private func chartTime(_ timestamp: Int64, range: MarketRange, timezone: String?) -> String {
    let formatter = MarketViewDateFormatters.chart(range: range, timezone: timezone)
    return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000))
}

private enum MarketViewDateFormatters {
    private static var localTimeCache: [String: DateFormatter] = [:]
    private static var chartCache: [String: DateFormatter] = [:]

    static func localTime(timeZone: String) -> DateFormatter {
        if let cached = localTimeCache[timeZone] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: timeZone)
        formatter.dateFormat = "HH:mm"
        localTimeCache[timeZone] = formatter
        return formatter
    }

    static func chart(range: MarketRange, timezone: String?) -> DateFormatter {
        let format: String
        switch range {
        case .day, .week: format = "MM-dd HH:mm"
        case .month, .quarter, .year: format = "MM-dd"
        case .fiveYears, .maximum: format = "yyyy-MM"
        }
        let cacheKey = "\(format)|\(timezone ?? "")"
        if let cached = chartCache[cacheKey] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if let timezone { formatter.timeZone = TimeZone(identifier: timezone) }
        formatter.dateFormat = format
        chartCache[cacheKey] = formatter
        return formatter
    }
}
private func stockSymbol(_ symbol: String) -> String { switch symbol { case "AAPL": "apple.logo"; case "MSFT": "square.grid.2x2.fill"; case "META": "infinity"; case "AMZN": "a.circle.fill"; default: "eye.fill" } }
private func stockColor(_ symbol: String) -> Color { switch symbol { case "AAPL": .primary; case "AMZN": .orange; case "NVDA": .green; default: .blue } }

#Preview { MarketView() }
