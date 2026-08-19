import Charts
import SwiftUI
import UIKit

private enum MarketStyle {
    static let canvas = InvestmentDesign.canvas
    static let surface = InvestmentDesign.surface
    static let divider = InvestmentDesign.divider
    static let gain = InvestmentDesign.gain
    static let loss = InvestmentDesign.loss
    static let accent = InvestmentDesign.accent
    static let chartTransition = Animation.smooth(duration: 0.6)
    static let regionTransition = Animation.smooth(duration: 0.26, extraBounce: 0)
    static let purple = accent
    static let pageSpacing: CGFloat = 10
}

private struct MarketDetailRoute: Identifiable, Equatable {
    let symbol: String
    var id: String { symbol }
}

struct MarketView: View {
    @Binding private var showsDetail: Bool
    private let store: MarketStore
    private let onCompactHeaderChange: (Bool) -> Void
    @State private var selectedDetail: MarketDetailRoute? = {
        #if DEBUG
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--market-detail-symbol=") }) {
            return MarketDetailRoute(symbol: String(argument.dropFirst("--market-detail-symbol=".count)))
        }
        if ProcessInfo.processInfo.arguments.contains("--market-vix-detail-preview") {
            return MarketDetailRoute(symbol: "^VIX")
        }
        return ProcessInfo.processInfo.arguments.contains("--market-detail-preview")
            ? MarketDetailRoute(symbol: "QQQ")
            : nil
        #else
        nil
        #endif
    }()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.rootTabIsActive) private var rootTabIsActive

    @MainActor
    init(
        store: MarketStore,
        showsDetail: Binding<Bool> = .constant(false),
        onCompactHeaderChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.store = store
        self.onCompactHeaderChange = onCompactHeaderChange
        _showsDetail = showsDetail
    }

    @MainActor
    init(
        showsDetail: Binding<Bool> = .constant(false),
        onCompactHeaderChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.init(
            store: MarketStore(),
            showsDetail: showsDetail,
            onCompactHeaderChange: onCompactHeaderChange
        )
    }

    var body: some View {
        MarketHomeView(store: store, onCompactHeaderChange: onCompactHeaderChange) {
            selectedDetail = MarketDetailRoute(symbol: $0)
        }
        .sheet(item: $selectedDetail, onDismiss: {
            showsDetail = false
        }) { route in
            MarketIndexDetailView(
                symbol: route.symbol,
                store: store,
                onSelectSymbol: {
                    selectedDetail = MarketDetailRoute(symbol: $0)
                }
            )
            .id(route.symbol)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(MarketStyle.surface)
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await store.runUpdates()
        }
        .onChange(of: scenePhase) { _, phase in
            guard rootTabIsActive, phase == .active else { return }
            Task { await store.resumeUpdates() }
        }
        .onChange(of: selectedDetail) { _, route in
            if route != nil {
                showsDetail = true
            }
        }
        .onAppear { showsDetail = selectedDetail != nil }
        .onDisappear { showsDetail = false }
    }
}

private struct MarketHomeView: View {
    let store: MarketStore
    let onCompactHeaderChange: (Bool) -> Void
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
        case "commodity": return .commodity
        case "crypto": return .crypto
        default: return .unitedStates
        }
        #else
        return .unitedStates
        #endif
    }()
    @State private var suppressIndexSelection = false
    @State private var selectionResetTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: MarketHomeScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .named("market-scroll")).minY
                            )
                        }
                        .frame(height: 1)
                        .id("market-top")

                        ZStack(alignment: .topTrailing) {
                            MarketTerminalHero(store: store, region: selectedMarket, onSelectIndex: onSelectIndex)
                                .id(selectedMarket)
                                .transition(.opacity)
                            MarketRegionPicker(store: store, selection: $selectedMarket)
                                .padding(.top, 14)
                                .padding(.trailing, 8)
                        }
                        .background(MarketStyle.surface)
                        .animation(reduceMotion ? nil : MarketStyle.regionTransition, value: selectedMarket)

                        VStack(spacing: MarketStyle.pageSpacing) {
                            if let error = regionalHealthMessage {
                                MarketErrorBanner(
                                    message: error,
                                    isRetrying: store.isRetrying
                                ) { await store.refresh() }
                            }
                            MarketIndexTable(
                                region: selectedMarket,
                                store: store,
                                onSelectIndex: selectIndex
                            )
                            .id(selectedMarket)
                            .transition(.opacity)
                            .animation(reduceMotion ? nil : MarketStyle.regionTransition, value: selectedMarket)
                            .simultaneousGesture(regionSwipeGesture)
                            if selectedMarket == .china {
                                ChinaMarketStructurePanel(structure: store.dashboard?.marketStructure)
                                    .id("market-structure")
                            }
                        }
                        .padding(.top, MarketStyle.pageSpacing)
                        // Keep the final market rows clear of the floating root navigation capsule.
                        .padding(.bottom, 76)
                        .background(MarketStyle.canvas)
                    }
                    .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .top)
                    .background(MarketStyle.canvas)
                }
                .background(MarketStyle.canvas.ignoresSafeArea())
                .coordinateSpace(name: "market-scroll")
                .scrollIndicators(.hidden)
                .refreshable { await store.refresh() }
                .onChange(of: selectedMarket) { _, _ in
                    withAnimation(reduceMotion ? nil : MarketStyle.regionTransition) {
                        proxy.scrollTo("market-top", anchor: .top)
                    }
                }
                .onPreferenceChange(MarketHomeScrollOffsetPreferenceKey.self) { offset in
                    onCompactHeaderChange(offset < -28)
                }
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--market-structure-preview") {
                        try? await Task.sleep(for: .seconds(2))
                        proxy.scrollTo("market-structure", anchor: .top)
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
    }

    private var regionalHealthMessage: String? {
        let relevant = store.healthIssues.filter { selectedMarket.relevantHealthSymbols.contains($0.symbol) }
        if let summary = marketHealthSummary(relevant) { return summary }
        return store.healthIssues.isEmpty ? store.errorMessage : nil
    }

    private var regionSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                selectionResetTask?.cancel()
                suppressIndexSelection = true
            }
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height
                let projectedHorizontalDistance = value.predictedEndTranslation.width
                let isHorizontal = abs(horizontalDistance) > abs(verticalDistance)
                let crossedDistance = abs(horizontalDistance) >= 36
                let hasHorizontalMomentum = abs(projectedHorizontalDistance) >= 64
                if isHorizontal, crossedDistance || hasHorizontalMomentum {
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
        withAnimation(reduceMotion ? nil : MarketStyle.regionTransition) {
            selectedMarket = regions[nextIndex]
        }
    }
}

private struct MarketHomeScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum MarketTerminalPalette {
    static let header = InvestmentDesign.surface
    static let headerDivider = InvestmentDesign.divider
}

private enum MarketRegion: String, CaseIterable, Identifiable {
    case unitedStates = "美国"
    case china = "中国"
    case japan = "日本"
    case korea = "韩国"
    case europe = "欧洲"
    case commodity = "商品"
    case crypto = "加密"

    var id: Self { self }

    var symbols: [String] {
        switch self {
        case .unitedStates: ["SPY", "QQQ", "DIA", "^VIX"]
        case .china: ["000001.SS", "000300.SS", "000688.SS", "^HSTECH", "^HSI"]
        case .japan: ["^N225"]
        case .korea: ["^KS11"]
        case .europe: ["^STOXX50E", "^GDAXI", "^FTSE", "^FCHI"]
        case .commodity: ["GC1!", "CL1!", "HG1!", "SI1!", "NG1!", "ZC1!", "LE1!", "GF1!", "HE1!"]
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

    var dashboardID: String {
        switch self {
        case .unitedStates: "us"
        case .china: "cn"
        case .japan: "jp"
        case .korea: "kr"
        case .europe: "eu"
        case .commodity: "commodity"
        case .crypto: "crypto"
        }
    }

    var relevantHealthSymbols: Set<String> {
        switch self {
        case .unitedStates: Set(symbols + ["^TNX"])
        case .china: Set(allSymbols.filter { $0 != "THS:883418" } + ["USDCNY", "399001.SZ"])
        case .japan: Set(symbols + ["USDJPY", "JP10Y", "^TOPX"])
        case .korea: Set(symbols + ["USDKRW", "KR10Y"])
        case .europe: Set(symbols)
        case .commodity: Set(symbols)
        case .crypto: Set(symbols)
        }
    }
}

private struct MarketTerminalHero: View {
    let store: MarketStore
    let region: MarketRegion
    let onSelectIndex: (String) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var quote: MarketQuote? { store.quote(symbol: region.primarySymbol) }
    private var overnightQuote: MarketQuote? {
        guard region == .unitedStates, quote?.marketSession != "regular",
              let session = marketActiveIndexSession(store.dashboard?.indexSessions?[region.primarySymbol]) else { return nil }
        return session
    }
    private var displayedQuote: MarketQuote? { overnightQuote ?? quote }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            heroStatusHeader
                .padding(.trailing, 76)

            Button { if quote != nil { onSelectIndex(region.primarySymbol) } } label: {
                VStack(alignment: .leading, spacing: 8) {
                    heroInstrumentTitle
                    heroPriceAndChart
                }
                .foregroundStyle(.primary)
                .padding(.trailing, 76)
            }
            .buttonStyle(MarketPressStyle())
            .accessibilityLabel(heroAccessibilityLabel)
            .accessibilityHint("打开代表指数详情")

            Group {
            if region == .commodity {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 0) {
                        marketMetric(symbol: "CL1!").frame(height: 58)
                        Divider()
                        marketMetric(symbol: "HG1!").frame(height: 58)
                        Divider()
                        marketMetric(symbol: "SI1!").frame(height: 58)
                    }
                    .dynamicTypeSize(.large)
                } else {
                    HStack(spacing: 0) {
                        marketMetric(symbol: "CL1!")
                        TerminalDivider()
                        marketMetric(symbol: "HG1!")
                        TerminalDivider()
                        marketMetric(symbol: "SI1!")
                    }
                }
            } else if region == .crypto {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 0) {
                        cryptoMetric(symbol: "BINANCE:ETHUSDT").frame(height: 58)
                        Divider()
                        cryptoMetric(symbol: "BINANCE:SOLUSDT").frame(height: 58)
                        Divider()
                        cryptoMetric(symbol: "BINANCE:BNBUSDT").frame(height: 58)
                    }
                    .dynamicTypeSize(.large)
                } else {
                    HStack(spacing: 0) {
                        cryptoMetric(symbol: "BINANCE:ETHUSDT")
                        TerminalDivider()
                        cryptoMetric(symbol: "BINANCE:SOLUSDT")
                        TerminalDivider()
                        cryptoMetric(symbol: "BINANCE:BNBUSDT")
                    }
                }
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
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 0) {
                        unitedStatesVIXMetric.frame(height: 58)
                        Divider()
                        MarketTerminalSentiment(sentiment: store.dashboard?.sentiment).frame(height: 58)
                        Divider()
                        unitedStatesYieldMetric.frame(height: 58)
                    }
                    .dynamicTypeSize(.large)
                } else {
                    HStack(spacing: 0) {
                        unitedStatesVIXMetric
                        TerminalDivider()
                        MarketTerminalSentiment(sentiment: store.dashboard?.sentiment)
                        TerminalDivider()
                        unitedStatesYieldMetric
                    }
                }
            } else {
                 EuropeMarketMetrics(store: store)
            }
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 180 : 76)
            .padding(.top, 12)
            .overlay(alignment: .top) {
                Divider().opacity(0.55)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(MarketTerminalPalette.header)
    }

    private var sessionLabel: String {
        if region == .crypto { return "24H 交易中" }
        if overnightQuote != nil { return "股票休市" }
        return quote?.tradingSession.displayLabel ?? "行情更新"
    }

    private var sessionHeadline: String {
        if region == .unitedStates, overnightQuote != nil { return "美股休市 · 期指夜盘" }
        return "\(region.rawValue) · \(sessionLabel)"
    }

    private var sessionTint: Color {
        region == .crypto || quote?.marketSession == "regular" || overnightQuote != nil
            ? Color(red: 0.08, green: 0.83, blue: 0.47)
            : Color.secondary
    }

    private func cryptoMetric(symbol: String) -> some View {
        let value = store.quote(symbol: symbol)
        return MarketTerminalMetric(
            title: value?.presentationName ?? CoreDescriptor(symbol: symbol).name,
            value: value.map { number($0.price, digits: cryptoPriceDigits($0.price, symbol: $0.symbol)) } ?? "—",
            change: value?.formattedPercent ?? "—",
            tint: quoteTint(value),
            trend: store.trendValues(for: value)
        )
    }

    private func marketMetric(symbol: String) -> some View {
        let value = store.quote(symbol: symbol)
        return MarketTerminalMetric(
            title: value?.presentationName ?? CoreDescriptor(symbol: symbol).name,
            value: value.map { number($0.price, digits: 2) } ?? "—",
            change: value?.formattedPercent ?? "—",
            tint: quoteTint(value),
            trend: store.trendValues(for: value)
        )
    }

    private var unitedStatesVIXMetric: some View {
        MarketTerminalMetric(
            title: "VIX 恐慌指数",
            value: store.quote(symbol: "^VIX").map { number($0.price, digits: 1) } ?? "—",
            change: store.quote(symbol: "^VIX")?.formattedPercent ?? "—",
            tint: quoteTint(store.quote(symbol: "^VIX")),
            trend: store.trendValues(for: store.quote(symbol: "^VIX"))
        )
    }

    private var unitedStatesYieldMetric: some View {
        MarketTerminalMetric(
            title: "美国 10Y 国债收益率",
            value: store.quote(symbol: "^TNX").map { String(format: "%.2f%%", $0.price) } ?? "—",
            change: store.quote(symbol: "^TNX")?.formattedPercent ?? "—",
            tint: quoteTint(store.quote(symbol: "^TNX")),
            trend: store.trendValues(for: store.quote(symbol: "^TNX"))
        )
    }

    @ViewBuilder private var heroStatusHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 7) {
                sessionStatus
                HStack(spacing: 8) {
                    Text(heroDateLabel)
                    MarketLiveStatus(store: store)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.secondary)
                .dynamicTypeSize(.large)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                sessionStatus
                Group {
                    Text(heroDateLabel)
                    MarketLiveStatus(store: store)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.secondary)
            }
        }
    }

    private var sessionStatus: some View {
        HStack(spacing: 6) {
            Circle().fill(sessionTint).frame(width: 7, height: 7)
            Text(sessionHeadline)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(sessionTint)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    @ViewBuilder private var heroInstrumentTitle: some View {
        let name = displayedQuote?.presentationName ?? quote?.presentationName ?? CoreDescriptor(symbol: region.primarySymbol).name
        let code = overnightQuote.map { "\($0.displayCode) · 指数期货夜盘" }
            ?? quote?.displayCode
            ?? CoreDescriptor(symbol: region.primarySymbol).code
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.title3.weight(.semibold)).lineLimit(2)
                Text(code).font(.caption.weight(.medium)).foregroundStyle(Color.secondary).lineLimit(1)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(name)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(code)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var heroPriceAndChart: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                heroPriceSummary
                heroChart.frame(maxWidth: .infinity, minHeight: 112)
            }
        } else {
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 12) {
                    heroPriceSummary
                        .frame(width: max(120, geometry.size.width - 182), alignment: .leading)
                        .clipped()
                    heroChart.frame(width: 170, height: 128)
                }
            }
            .frame(height: 128)
        }
    }

    private var heroPriceSummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(displayedQuote.map { number($0.price, digits: cryptoPriceDigits($0.price, symbol: $0.symbol)) } ?? "—")
                .font(.system(.largeTitle, design: .default, weight: .semibold))
                .monospacedDigit()
                .tracking(-0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(displayedQuote.map(marketHeroChangeText) ?? "等待行情")
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(quoteTint(displayedQuote))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var heroChart: some View {
        TerminalLeadChart(
            quote: displayedQuote,
            trend: store.trendValues(for: displayedQuote),
            isOvernight: overnightQuote != nil
        )
    }

    private var heroDateLabel: String {
        "\(region == .crypto ? "行情日期" : "交易日") \(heroDate)"
    }

    private var heroDate: String {
        if let tradingDate = quote?.quality?.tradingDate,
           let date = DateFormatter.marketTradingDate.date(from: tradingDate) {
            return date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))
        }
        let date = quote?.marketAsOfTimestamp.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? Date()
        return date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))
    }

    private var heroAccessibilityLabel: String {
        let name = displayedQuote?.presentationName ?? quote?.presentationName ?? CoreDescriptor(symbol: region.primarySymbol).name
        guard let displayedQuote else { return "\(name)，等待行情" }
        return "\(name)，最新价 \(number(displayedQuote.price, digits: cryptoPriceDigits(displayedQuote.price, symbol: displayedQuote.symbol)))，\(displayedQuote.formattedPercent)，\(sessionLabel)"
    }
}

private struct EuropeMarketMetrics: View {
    let store: MarketStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    metric("欧洲50", "^STOXX50E").frame(height: 58)
                    Divider()
                    metric("德国 DAX", "^GDAXI").frame(height: 58)
                    Divider()
                    metric("英国 FTSE", "^FTSE").frame(height: 58)
                }
                .dynamicTypeSize(.large)
            } else {
                HStack(spacing: 0) {
                    metric("欧洲50", "^STOXX50E")
                    TerminalDivider()
                    metric("德国 DAX", "^GDAXI")
                    TerminalDivider()
                    metric("英国 FTSE", "^FTSE")
                }
            }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var exchangeQuote: MarketQuote? { store.quote(symbol: exchangeSymbol) }
    private var yieldQuote: MarketQuote? { store.quote(symbol: yieldSymbol) }
    private var companionQuote: MarketQuote? { store.quote(symbol: companionSymbol) }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    exchangeMetric.frame(height: 58)
                    Divider()
                    yieldMetric.frame(height: 58)
                    Divider()
                    companionMetric.frame(height: 58)
                }
                .dynamicTypeSize(.large)
            } else {
                HStack(spacing: 0) {
                    exchangeMetric
                    TerminalDivider()
                    yieldMetric
                    TerminalDivider()
                    companionMetric
                }
            }
        }
    }

    private var exchangeMetric: some View {
        MarketTerminalMetric(
            title: exchangeTitle,
            value: exchangeQuote.map { number($0.price, digits: exchangeDigits) } ?? "—",
            change: exchangeQuote?.formattedPercent ?? exchangeSymbol,
            tint: quoteTint(exchangeQuote),
            trend: exchangeQuote?.trend ?? []
        )
    }

    private var yieldMetric: some View {
        MarketTerminalMetric(
            title: yieldTitle,
            value: yieldQuote.map { String(format: "%.2f%%", $0.price) } ?? "—",
            change: yieldQuote?.formattedPercent ?? "等待行情",
            tint: quoteTint(yieldQuote),
            trend: yieldQuote?.trend ?? []
        )
    }

    private var companionMetric: some View {
        MarketTerminalMetric(
            title: companionTitle,
            value: companionQuote.map { number($0.price, digits: 2) } ?? "—",
            change: companionQuote?.formattedPercent ?? "等待行情",
            tint: quoteTint(companionQuote),
            trend: companionQuote?.trend ?? []
        )
    }
}

private struct ChinaMarketMetrics: View {
    let store: MarketStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    exchangeMetric.frame(height: 58)
                    Divider()
                    turnoverView.frame(height: 58)
                    Divider()
                    MarketBreadthMetric(breadth: breadth, isStale: breadthIsStale).frame(height: 58)
                }
                .dynamicTypeSize(.large)
            } else {
                HStack(spacing: 0) {
                    exchangeMetric
                    TerminalDivider()
                    turnoverView
                    TerminalDivider()
                    MarketBreadthMetric(breadth: breadth, isStale: breadthIsStale)
                }
            }
        }
    }

    private var exchangeMetric: some View {
        MarketTerminalMetric(
            title: "人民币汇率",
            value: exchangeRate.map { number($0.price, digits: 4) } ?? "—",
            change: exchangeRate?.formattedPercent ?? "USD/CNY",
            tint: quoteTint(exchangeRate),
            trend: exchangeRate?.trend ?? []
        )
    }

    private var turnoverView: some View {
        MarketTerminalMetric(
            title: turnoverMetric?.title ?? "成交额",
            value: turnoverMetric.map { turnoverText($0.value) } ?? "—",
            change: turnoverMetric?.note ?? "等待行情",
            tint: .secondary,
            trend: []
        )
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
    let store: MarketStore
    @Binding var selection: MarketRegion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 1) {
            ForEach(MarketRegion.allCases) { region in
                regionButton(region)
            }
        }
        .padding(3)
        .frame(width: 68)
        .background(Color.clear)
    }

    private func regionButton(_ region: MarketRegion) -> some View {
        let isSelected = selection == region
        let weight: Font.Weight = isSelected ? .semibold : .medium
        let foreground = isSelected ? MarketStyle.accent : Color.secondary
        let quote = store.quote(symbol: region.primarySymbol)

        return Button {
            withAnimation(reduceMotion ? nil : MarketStyle.regionTransition) {
                selection = region
            }
        } label: {
            VStack(spacing: 1) {
                Text(region.rawValue)
                    .font(.system(size: 12, weight: weight))
                    .foregroundStyle(foreground)
                Text(quote?.formattedPercent ?? "—")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(quoteTint(quote))
            }
                .lineLimit(1)
                .frame(width: 62, height: 33)
                .background(Color.clear)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(MarketStyle.accent.opacity(0.45), lineWidth: 0.75)
                    }
                }
                .contentShape(Rectangle())
        }
        .id(region)
        .buttonStyle(.plain)
        .accessibilityLabel("\(region.rawValue)，\(quote?.formattedPercent ?? "涨跌幅等待更新")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MarketIndexTable: View {
    let region: MarketRegion
    let store: MarketStore
    let onSelectIndex: (String) -> Void

    @State private var chinaScope: ChinaIndexScope = .core
    @State private var displayedLogoPaths: [String: String]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(region: MarketRegion, store: MarketStore, onSelectIndex: @escaping (String) -> Void) {
        self.region = region
        self.store = store
        self.onSelectIndex = onSelectIndex
        _displayedLogoPaths = State(initialValue: store.companyLogoPaths)
    }

    private var symbols: [String] { region == .china && chinaScope == .all ? region.allSymbols : region.symbols }
    private var quotes: [MarketQuote] { symbols.compactMap { store.quote(symbol: $0) } }
    private var coreStocks: [MarketQuote] {
        store.dashboard?.componentsByRegion[region.dashboardID] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            if region == .china {
                ChinaIndexScopePicker(selection: $chinaScope)
            }
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    Text("名称 / 代码").frame(width: 132, alignment: .leading)
                    Text("最新价").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("涨跌幅").frame(width: 62, alignment: .trailing)
                    Text("走势").frame(width: 50, alignment: .trailing)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .frame(height: 32)

                Divider().opacity(0.45)
            }

            if quotes.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("正在加载\(region.rawValue)市场行情")
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ForEach(Array(quotes.enumerated()), id: \.element.symbol) { index, quote in
                    Button { onSelectIndex(quote.symbol) } label: {
                         MarketIndexTableRow(
                             quote: quote,
                            overnightQuote: nil,
                            trend: store.listTrendValues(for: quote),
                            companyLogoPath: displayedLogoPaths[quote.symbol],
                            showsCompanyLogo: true
                         )
                    }
                    .buttonStyle(MarketPressStyle())
                    if index < quotes.count - 1 { Divider().opacity(0.45).padding(.leading, 18) }
                }
            }

            if !coreStocks.isEmpty {
                HStack {
                    Text(store.dashboard?.componentsMeta?.label ?? "核心股票")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 6)

                Divider().opacity(0.45)
                ForEach(Array(coreStocks.enumerated()), id: \.element.symbol) { index, quote in
                    Button { onSelectIndex(quote.symbol) } label: {
                        MarketIndexTableRow(
                            quote: quote,
                            overnightQuote: nil,
                            trend: store.listTrendValues(for: quote),
                            companyLogoPath: displayedLogoPaths[quote.symbol],
                            showsCompanyLogo: true
                        )
                    }
                    .buttonStyle(MarketPressStyle())
                    if index < coreStocks.count - 1 { Divider().opacity(0.45).padding(.leading, 18) }
                }
            }

        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(MarketStyle.surface)
        .overlay(alignment: .top) {
            Divider().opacity(0.65)
        }
        .animation(.easeOut(duration: 0.16), value: region)
        .task(id: componentLogoRequestID) {
            guard region != .commodity else { return }
            let requestedQuotes = (quotes + coreStocks).reduce(into: [String: MarketQuote]()) {
                $0[$1.symbol] = $1
            }.values
            await withTaskGroup(of: Void.self) { group in
                for quote in requestedQuotes {
                    group.addTask { @MainActor in
                        await store.loadCompanyLogo(symbol: quote.symbol, name: quote.presentationName)
                        guard let path = store.companyLogoPaths[quote.symbol],
                              let url = marketCompanyLogoURL(path) else { return }
                        _ = await MarketLogoImageCache.shared.image(for: url)
                    }
                }
            }
            guard !Task.isCancelled else { return }
            displayedLogoPaths = store.companyLogoPaths
        }
        .task(id: componentChartRequestID) {
            await withTaskGroup(of: Void.self) { group in
                for quote in quotes + coreStocks {
                    group.addTask { @MainActor in
                        await store.loadChart(symbol: quote.symbol, range: .day)
                    }
                }
            }
        }
    }

    private var componentLogoRequestID: String {
        "\(region.dashboardID):\((quotes + coreStocks).map(\.symbol).joined(separator: ","))"
    }

    private var componentChartRequestID: String {
        "day:\(componentLogoRequestID)"
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
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .overlay(alignment: .top) {
            Divider().opacity(0.65)
        }
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
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .frame(height: 30)
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
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(selection == scope ? MarketStyle.accent : Color.clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == scope ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }
}

private struct MarketIndexTableRow: View {
    let quote: MarketQuote
    let overnightQuote: MarketQuote?
    let trend: [Double]
    var companyLogoPath: String? = nil
    var showsCompanyLogo = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
                    .dynamicTypeSize(.xLarge)
            } else {
                standardLayout
            }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 88 : 62)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开指数详情")
    }

    private var standardLayout: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                if showsCompanyLogo {
                    MarketInstrumentLogo(quote: quote, path: companyLogoPath, size: 32)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Circle().fill(sessionTint).frame(width: 5, height: 5)
                        Text(statusLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    Text(displayedName).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.78)
                    Text(displayedCode).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: 132, alignment: .leading)

            Text(number(displayedPrice, digits: cryptoPriceDigits(displayedPrice, symbol: displayedSymbol)))
                .font(.system(size: 13.5, weight: .medium)).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(1).minimumScaleFactor(0.72)

            VStack(alignment: .trailing, spacing: 3) {
                Text(displayedPercent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(displayedChangeText)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .font(.footnote.weight(.semibold)).monospacedDigit()
            .foregroundStyle(displayedTint)
            .frame(width: 62, alignment: .trailing)

            Group {
                if trend.count >= 2 {
                    Sparkline(values: trend, color: displayedTint)
                } else {
                    Text("—").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 50, height: 32)
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                if showsCompanyLogo {
                    MarketInstrumentLogo(quote: quote, path: companyLogoPath, size: 32)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayedName).font(.headline).lineLimit(2)
                    Text(statusLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if trend.count >= 2 {
                    Sparkline(values: trend, color: displayedTint)
                        .frame(width: 64, height: 34)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(displayedCode).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(number(displayedPrice, digits: cryptoPriceDigits(displayedPrice, symbol: displayedSymbol)))
                    .font(.body.weight(.medium)).monospacedDigit()
                Text(displayedPercent)
                    .font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(displayedTint)
            }
        }
    }

    private var usesEmbeddedExtendedSession: Bool {
        overnightQuote == nil && quote.hasActiveExtendedSessionQuote
    }

    private var displayedPrice: Double {
        if let overnightQuote { return overnightQuote.price }
        if usesEmbeddedExtendedSession, let sessionPrice = quote.sessionPrice { return sessionPrice }
        return quote.price
    }

    private var displayedSymbol: String {
        overnightQuote?.symbol ?? quote.symbol
    }

    private var displayedName: String {
        (overnightQuote ?? quote).compactMarketName
    }

    private var displayedCode: String {
        overnightQuote?.displayCode ?? quote.displayCode
    }

    private var displayedPercentValue: Double {
        if let overnightQuote { return overnightQuote.percentValue }
        if usesEmbeddedExtendedSession {
            if let sessionChangePercent = quote.sessionChangePercent { return sessionChangePercent }
            if let previousClose = quote.previousClose, previousClose > 0 {
                return (displayedPrice - previousClose) / previousClose * 100
            }
        }
        return quote.percentValue
    }

    private var displayedPercent: String {
        if (overnightQuote ?? quote).hasSuspiciousIndexMove { return "待核验" }
        return String(format: "%@%.2f%%", displayedPercentValue >= 0 ? "+" : "−", abs(displayedPercentValue))
    }

    private var displayedChangeText: String {
        guard !(overnightQuote ?? quote).hasSuspiciousIndexMove else { return "—" }
        return signed(displayedChange, digits: cryptoChangeDigits(overnightQuote ?? quote))
    }

    private var displayedChange: Double {
        if let previousClose = overnightQuote?.previousClose ?? quote.previousClose {
            return displayedPrice - previousClose
        }
        return overnightQuote?.changeValue ?? quote.changeValue
    }

    private var displayedTint: Color {
        displayedPercentValue >= 0 ? MarketStyle.gain : MarketStyle.loss
    }

    private var sessionLabel: String {
        if overnightQuote != nil { return "夜盘" }
        if quote.tradingSession == .alwaysOpen || quote.symbol.hasPrefix("BINANCE:") { return "24H" }
        return quote.tradingSession.displayLabel
    }

    private var statusLabel: String {
        guard let delayMinutes = quote.visibleDelayMinutes else { return sessionLabel }
        return "\(compactSessionLabel)·延\(delayMinutes)分"
    }

    private var compactSessionLabel: String {
        switch quote.tradingSession {
        case .regular: "交易中"
        case .premarket: "盘前"
        case .postmarket: "盘后"
        case .overnight: "夜盘"
        case .closed: "收盘"
        case .alwaysOpen: "24H"
        case .unknown: "行情"
        }
    }

    private var sessionTint: Color {
        overnightQuote != nil || usesEmbeddedExtendedSession || quote.marketSession == "always-open"
            || quote.symbol.hasPrefix("BINANCE:") || quote.marketSession == "regular"
            ? MarketStyle.accent
            : .secondary
    }
}

private struct MarketWorldMap: View {
    let store: MarketStore
    @Binding var selection: MarketRegion
    @Environment(\.colorScheme) private var colorScheme

    private let markets: [MarketMapLocation] = [
        .init(
            region: .unitedStates,
            city: "纽约",
            marketCode: "SPY",
            timeZone: "America/New_York",
            assetPoint: .init(x: 512, y: 306),
            calloutOffset: .init(width: 40, height: 32)
        ),
        .init(
            region: .china,
            city: "上海",
            marketCode: "上证",
            timeZone: "Asia/Shanghai",
            assetPoint: .init(x: 1_400, y: 340),
            calloutOffset: .init(width: -50, height: 34)
        ),
        .init(
            region: .japan,
            city: "东京",
            marketCode: "N225",
            timeZone: "Asia/Tokyo",
            assetPoint: .init(x: 1_497, y: 344),
            calloutOffset: .init(width: 18, height: 47)
        ),
        .init(
            region: .korea,
            city: "首尔",
            marketCode: "KOSPI",
            timeZone: "Asia/Seoul",
            assetPoint: .init(x: 1_450, y: 324),
            calloutOffset: .init(width: -17, height: -27)
        ),
        .init(
            region: .europe,
            city: "法兰克福",
            marketCode: "STOXX",
            timeZone: "Europe/Berlin",
            assetPoint: .init(x: 860, y: 283),
            calloutOffset: .init(width: 3, height: -24)
        ),
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            GeometryReader { proxy in
                ZStack {
                    mapBackground

                    ForEach(markets) { market in
                        Button { select(market.region) } label: {
                            MarketMapNode(
                                market: market,
                                quote: store.quote(symbol: market.region.primarySymbol),
                                isSelected: selection == market.region,
                                date: context.date
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(mapAccessibilityLabel(for: market))
                        .accessibilityHint("切换到\(market.region.rawValue)市场")
                        .position(market.position(in: proxy.size))
                        .zIndex(selection == market.region ? 2 : 1)
                    }
                }
            }
        }
        .frame(height: 164)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 4)
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
        let status = switch quote?.tradingSession {
        case .regular: "交易中"
        case .some: "已休市"
        case .none: "等待行情"
        }
        let change = quote.map { "今日\($0.formattedPercent)" } ?? "涨跌等待更新"
        return "\(market.region.rawValue)，\(status)，\(change)"
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
        case .commodity:
            return [.init("电子盘", "近 24 小时"), .init("维护", "每日约 1 小时")]
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
        case .commodity:
            return 0
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
        case .china, .commodity, .crypto: identifier = "Asia/Shanghai"
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
        case .commodity: "全球商品"
        case .crypto: "加密市场"
        }
    }

    var sessionNote: String {
        switch self {
        case .china: "午间休市 11:30–13:00；法定节假日休市"
        case .japan: "以上时间已由东京时间换算为北京时间"
        case .korea: "以上时间已由首尔时间换算为北京时间"
        case .europe: "以上时间已由欧洲中部时间换算为北京时间"
        case .commodity: "连续主力合约；交易时段与换月安排以交易所为准"
        case .crypto: "全年无休，行情以 USDT 计价"
        case .unitedStates: ""
        }
    }
}

private struct MarketMapLocation: Identifiable {
    private static let assetSize = CGSize(width: 1_821, height: 864)

    let region: MarketRegion
    let city: String
    let marketCode: String
    let timeZone: String
    // Pixel coordinates calibrated against market-world-map.png.
    let assetPoint: CGPoint
    let calloutOffset: CGSize
    var id: MarketRegion { region }

    func position(in size: CGSize) -> CGPoint {
        let scale = max(size.width / Self.assetSize.width, size.height / Self.assetSize.height)
        let renderedSize = CGSize(
            width: Self.assetSize.width * scale,
            height: Self.assetSize.height * scale
        )
        let origin = CGPoint(
            x: (size.width - renderedSize.width) / 2,
            y: (size.height - renderedSize.height) / 2
        )
        return CGPoint(
            x: origin.x + assetPoint.x * scale,
            y: origin.y + assetPoint.y * scale
        )
    }
}

private struct MarketMapNode: View {
    let market: MarketMapLocation
    let quote: MarketQuote?
    let isSelected: Bool
    let date: Date

    var body: some View {
        ZStack {
            connector

            if isSelected {
                Circle()
                    .fill(MarketStyle.accent.opacity(0.14))
                    .frame(width: 24, height: 24)
            }

            Circle()
                .stroke(nodeTint.opacity(isOpen ? 0.34 : 0), lineWidth: 1.5)
                .frame(width: 18, height: 18)

            Circle()
                .fill(nodeTint)
                .frame(width: 9, height: 9)
                .overlay {
                    Circle().stroke(.background.opacity(0.9), lineWidth: 1)
                }

            callout
                .offset(market.calloutOffset)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }

    private var connector: some View {
        let offset = market.calloutOffset
        let distance = hypot(offset.width, offset.height)
        let angle = Angle(radians: atan2(Double(offset.height), Double(offset.width)))
        return Capsule()
            .fill(nodeTint.opacity(isOpen ? 0.45 : 0.22))
            .frame(width: max(distance - 18, 8), height: 1)
            .rotationEffect(angle)
            .offset(x: offset.width / 2, y: offset.height / 2)
    }

    private var callout: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(market.city)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(localTime)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(nodeTint)
                    .frame(width: 4, height: 4)
                Text(statusLabel)
                    .foregroundStyle(statusTint)
                Text("· \(market.marketCode)")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 8.5, weight: .semibold))

            HStack(spacing: 3) {
                Text("今日")
                    .foregroundStyle(.secondary)
                Image(systemName: changeIcon)
                    .font(.system(size: 7.5, weight: .bold))
                Text(changeLabel)
                    .monospacedDigit()
            }
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(changeTint)
        }
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? MarketStyle.accent.opacity(0.7) : Color.primary.opacity(0.09), lineWidth: isSelected ? 1.2 : 0.7)
        }
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }

    private var nodeTint: Color {
        isOpen ? MarketStyle.loss : Color.secondary.opacity(0.55)
    }

    private var isOpen: Bool {
        quote?.tradingSession == .regular || quote?.tradingSession == .alwaysOpen
    }

    private var statusLabel: String {
        switch quote?.tradingSession {
        case .regular: "交易中"
        case .premarket: "盘前"
        case .postmarket: "盘后"
        case .overnight: "夜盘"
        case .closed: "已休市"
        case .alwaysOpen: "24H"
        case .unknown: "待更新"
        case .none: "等待行情"
        }
    }

    private var statusTint: Color {
        switch quote?.tradingSession {
        case .regular, .alwaysOpen: MarketStyle.loss
        case .premarket, .postmarket, .overnight: .orange
        case .closed, .unknown, .none: .secondary
        }
    }

    private var localTime: String {
        MarketViewDateFormatters.localTime(timeZone: market.timeZone).string(from: date)
    }

    private var changeLabel: String {
        quote?.formattedPercent ?? "等待更新"
    }

    private var changeIcon: String {
        guard let quote else { return "clock" }
        if quote.percentValue > 0 { return "arrow.up.right" }
        if quote.percentValue < 0 { return "arrow.down.right" }
        return "minus"
    }

    private var changeTint: Color {
        guard let quote else { return .secondary }
        if quote.percentValue > 0 { return MarketStyle.gain }
        if quote.percentValue < 0 { return MarketStyle.loss }
        return .secondary
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
        quote?.tradingSession.displayLabel ?? "行情更新"
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
                if store.maximumOpenMarketDelayMinutes != nil {
                    Text("行情已连接 · 延迟以品种标注为准")
                } else {
                    Text("实时连接")
                }
            } else if store.realtimeStatus == .connecting || store.realtimeStatus == .reconnecting {
                if let date = store.latestQuoteDate {
                    Text("截至 \(date.formatted(date: .omitted, time: .shortened)) · 连接恢复中")
                } else {
                    Text("实时连接恢复中")
                }
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
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
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
                Text(quote?.presentationName ?? descriptor.name).font(.caption.weight(.medium)).lineLimit(1)
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
                symbol: "SPY",
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
                    Text(quote?.presentationName ?? "等待行情").font(.caption.weight(.medium)).lineLimit(1)
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
        quote?.tradingSession == .alwaysOpen ? "全天" : quote?.tradingSession.displayLabel ?? "行情更新"
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

private struct MarketDetailBreadth: View {
    let title: String
    let breadth: MarketBreadth?

    private var total: Int {
        guard let breadth else { return 0 }
        return max(breadth.total, breadth.up + breadth.down + breadth.flat)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(breadth == nil ? "更新中" : "共 \(total.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let breadth {
                MarketBreadthComposition(
                    up: breadth.up,
                    down: breadth.down,
                    flat: breadth.flat,
                    total: total
                )
                .frame(height: 7)
                HStack {
                    breadthLabel("上涨", value: breadth.up, color: MarketStyle.gain)
                    Spacer()
                    breadthLabel("平盘", value: breadth.flat, color: .secondary)
                    Spacer()
                    breadthLabel("下跌", value: breadth.down, color: MarketStyle.loss)
                }
            } else {
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 7)
                Text("市场宽度更新中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Divider().padding(.horizontal, 18) }
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 18) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private func breadthLabel(_ title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).foregroundStyle(.secondary)
            Text(percent(value)).foregroundStyle(color)
        }
        .font(.caption)
        .monospacedDigit()
    }

    private func percent(_ value: Int) -> String {
        guard total > 0 else { return "—" }
        return "\(Int((Double(value) / Double(total) * 100).rounded()))%"
    }

    private var accessibilityText: String {
        guard let breadth else { return "\(title)，市场宽度更新中" }
        return "\(title)，上涨 \(breadth.up)，平盘 \(breadth.flat)，下跌 \(breadth.down)"
    }
}

private struct MarketIndexDetailView: View {
    let symbol: String
    let store: MarketStore
    let onSelectSymbol: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRange = MarketRange.day
    @State private var isScrollAtTop = true
    @State private var isTrackingDismissalDrag = false
    @State private var dismissalDragStartedAtTop = false
    @State private var presentedValuation: CompanyValuationHistoryRoute?

    private var quote: MarketQuote? { store.quote(symbol: symbol) }
    private var constituent: MarketIndexConstituent? { store.constituent(symbol: symbol) }
    private var companyLogoPath: String? { constituent?.logoPath ?? store.companyLogoPaths[symbol] }
    private var historicalSymbol: String { quote?.historicalSymbol ?? symbol }
    private var chartSymbol: String { quote?.symbol ?? symbol }
    private var chartFallbackSymbol: String? {
        guard historicalSymbol != chartSymbol else { return nil }
        return historicalSymbol
    }
    private var isIndex: Bool {
        store.dashboard?.coreIndices.contains(where: { $0.symbol == symbol }) == true
            || CoreDescriptor(symbol: symbol).isIndex
    }
    private var isAShareIndex: Bool {
        symbol.hasSuffix(".SS") || symbol.hasSuffix(".SZ") || symbol.hasPrefix("THS:")
    }
    private var detailBreadth: MarketBreadth? {
        if isAShareIndex {
            return store.dashboard?.currentAShareBreadth
        }
        guard let items = store.indexConstituents[historicalSymbol]?.items, !items.isEmpty else { return nil }
        let up = items.filter { $0.quote.percentValue > 0.005 }.count
        let down = items.filter { $0.quote.percentValue < -0.005 }.count
        let flat = max(items.count - up - down, 0)
        return MarketBreadth(up: up, down: down, flat: flat, total: items.count)
    }

    var body: some View {
        ZStack {
            MarketStyle.surface.ignoresSafeArea()
            VStack(spacing: 0) {
                detailNavigation
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Color.clear
                            .frame(height: 1)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: MarketDetailScrollTopPreferenceKey.self,
                                        value: geometry.frame(in: .named("market-detail-scroll")).minY
                                    )
                                }
                            }
                        detailHeader
                        MarketDetailChart(
                            selectedRange: $selectedRange,
                            symbol: chartSymbol,
                            fallbackSymbol: chartFallbackSymbol,
                            store: store
                        )
                            .id(chartSymbol)
                        keyData
                        if showsCompanyProfile { companyProfile }
                        if isIndex {
                            MarketDetailBreadth(
                                title: isAShareIndex ? "市场温度" : "成分表现",
                                breadth: detailBreadth
                            )
                        }
                        MarketSummary(quote: quote, isIndex: isIndex)
                        if isIndex { componentStocks }
                        Text("数据来源：\(quote?.dataSource ?? "行情服务") · \(quote?.freshnessLabel ?? "更新中")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 16)
                            .padding(.horizontal, 18)
                        Color.clear.frame(height: 28)
                    }
                }
                .modifier(MarketDetailScrollTopTracker(isAtTop: $isScrollAtTop))
                .scrollIndicators(.hidden)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(oneHandDismissGesture)
        .accessibilityHint("在详情内容区域向下滑动即可收起")
        .accessibilityAction(.escape) { dismiss() }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $presentedValuation) { route in
            CompanyValuationHistorySheet(route: route)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .task(id: historicalSymbol) {
            if isIndex { await store.loadIndexConstituents(symbol: historicalSymbol) }
            if !isIndex && !isCrypto {
                await store.loadChart(symbol: historicalSymbol, range: .year)
            }
            if let quote, !isCommodity {
                await store.loadCompanyLogo(symbol: quote.symbol, name: quote.presentationName)
            }
            #if DEBUG
            if let preview = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--market-pe-history-preview=") }) {
                let value = String(preview.dropFirst("--market-pe-history-preview=".count))
                presentedValuation = valuationRoute(kind: value == "ttm" ? .ttm : .staticPE)
            }
            #endif
        }
    }

    private var oneHandDismissGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { _ in
                guard !isTrackingDismissalDrag else { return }
                isTrackingDismissalDrag = true
                dismissalDragStartedAtTop = isScrollAtTop
            }
            .onEnded { value in
                let startedAtTop = dismissalDragStartedAtTop
                isTrackingDismissalDrag = false
                dismissalDragStartedAtTop = false

                let verticalDistance = value.translation.height
                let projectedDistance = value.predictedEndTranslation.height
                guard startedAtTop,
                      verticalDistance > abs(value.translation.width) * 1.2,
                      verticalDistance >= 88 || projectedDistance >= 180 else {
                    return
                }
                dismiss()
            }
    }

    private var detailNavigation: some View {
        HStack {
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("关闭行情详情")
            Spacer(minLength: 0)
            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 44, height: 44, alignment: .trailing)
            }
            .accessibilityLabel("分享行情")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 18)
        .background(MarketStyle.surface)
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                if let quote {
                    MarketInstrumentLogo(quote: quote, path: companyLogoPath)
                } else {
                    Image(systemName: CoreDescriptor(symbol: symbol).icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(MarketStyle.accent, in: RoundedRectangle(cornerRadius: 9))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(quote?.detailPresentationName ?? CoreDescriptor(symbol: symbol).name)
                        .font(.title3.weight(.semibold))
                        .tracking(-0.25)
                        .lineLimit(2)
                    Text(quote?.detailInstrumentLabel ?? CoreDescriptor(symbol: symbol).code)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    Circle().fill(sessionColor).frame(width: 6, height: 6)
                    Text(sessionText)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(sessionColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .overlay {
                    Capsule().stroke(sessionColor.opacity(0.35), lineWidth: 0.75)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(quote.map { number($0.price, digits: cryptoPriceDigits($0.price, symbol: $0.symbol)) } ?? "—")
                    .font(.system(size: 40, weight: .bold))
                    .monospacedDigit()
                    .tracking(-1.2)
                    .foregroundStyle(quoteTint(quote))
                    .contentTransition(.numericText())
                Text(quote.map { "\(signed($0.changeValue, digits: cryptoChangeDigits($0)))  \($0.formattedPercent)" } ?? "等待行情数据")
                    .font(.system(size: 18, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(quoteTint(quote))
                Text(quote?.marketAsOfLabel ?? "行情更新中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var keyData: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                metric(isCrypto ? "24H开盘" : "今开", quote?.openPrice)
                metricDivider
                metric("最高", quote?.high, MarketStyle.gain)
                metricDivider
                metric("最低", quote?.low, MarketStyle.loss)
                metricDivider
                if !isIndex && !isCrypto {
                    metric(
                        "52周最低",
                        quote?.week52Low ?? market52WeekLow(store.chart(symbol: historicalSymbol, range: .year)),
                        MarketStyle.loss
                    )
                    metricDivider
                }
                metric("昨收", quote?.previousClose)
            }
            Divider()
            HStack(spacing: 0) {
                metric("成交量", quote?.volume, compact: true)
                metricDivider
                textMetric("振幅", amplitudeText)
                metricDivider
                textMetric("涨跌额", quote.map { signed($0.changeValue, digits: cryptoChangeDigits($0)) } ?? "—", quoteTint(quote))
                metricDivider
                textMetric("状态", sessionText)
            }
            Divider()
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 18)
    }

    private var showsCompanyProfile: Bool {
        !isIndex && (constituent != nil || quote?.marketCap != nil || quote?.peStatic != nil || quote?.pe != nil)
    }

    private var companyProfile: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("公司资料").font(.system(size: 17, weight: .semibold))
            HStack(alignment: .top, spacing: 12) {
                if let quote { CompanyLogo(quote: quote, path: companyLogoPath) }
                VStack(alignment: .leading, spacing: 7) {
                    Text(quote?.presentationName ?? symbol).font(.subheadline.weight(.semibold))
                    Text("股票代码  \(quote?.displayCode ?? symbol)")
                    Text("上市市场  \(companyMarketLabel(symbol))")
                    if let marketCap = quote?.marketCap { Text("总市值  \(compactNumber(marketCap))") }
                    valuationMetric(.staticPE, value: quote?.peStatic)
                    valuationMetric(.ttm, value: quote?.pe)
                    Text("归母净利润（TTM）  \(formattedNetIncome)")
                    if let fiscalYear = quote?.fiscalYear, !fiscalYear.isEmpty {
                        Text("财报基准  FY\(fiscalYear)")
                    }
                    if let source = quote?.fundamentalsSource, !source.isEmpty {
                        Text("基础数据  \(source)")
                    }
                }
                .font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(14).marketCard(cornerRadius: 10)
        }
        .padding(.horizontal, 18)
    }

    private var formattedNetIncome: String {
        guard let quote, let netIncome = quote.netIncomeTTM else { return "—" }
        return marketFinancialAmount(netIncome, currency: quote.fundamentalsCurrency ?? quote.currency ?? "")
    }

    private func valuationMetric(_ kind: CompanyPEKind, value: Double?) -> some View {
        Button {
            presentedValuation = valuationRoute(kind: kind)
        } label: {
            HStack(spacing: 6) {
                Text(kind.metricTitle)
                Text(value.map { number($0, digits: 2) } ?? "—")
                    .monospacedDigit()
                Image(systemName: "chart.xyaxis.line")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(kind.color)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看历史变化曲线")
    }

    private func valuationRoute(kind: CompanyPEKind) -> CompanyValuationHistoryRoute {
        CompanyValuationHistoryRoute(
            symbol: quote?.symbol ?? symbol,
            name: quote?.presentationName ?? symbol,
            initialKind: kind
        )
    }

    private func metric(_ title: String, _ value: Double?, _ color: Color = .primary, compact: Bool = false, suffix: String = "") -> some View {
        textMetric(title, value.map { (compact ? compactNumber($0) : number($0, digits: 2)) + suffix } ?? "—", color)
    }

    private func textMetric(_ title: String, _ value: String, _ color: Color = .primary) -> some View {
        VStack(alignment: .center, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 62)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(MarketStyle.divider)
            .frame(width: 0.5, height: 42)
    }

    private var amplitudeText: String {
        guard let quote, let high = quote.high, let low = quote.low else { return "—" }
        let baseline = quote.previousClose ?? low
        guard baseline != 0 else { return "—" }
        return "\(number((high - low) / baseline * 100, digits: 2))%"
    }

    private var componentStocks: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.indexConstituents[historicalSymbol]?.label ?? "主要成分股")
                    .font(.system(size: 19, weight: .semibold))
                Spacer()
                if let asOf = store.indexConstituents[historicalSymbol]?.asOf {
                    Text("截至 \(asOf)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 0) {
                let items = store.indexConstituents[historicalSymbol]?.items ?? []
                ForEach(items) { item in
                    if item.detailAvailable {
                        Button {
                            onSelectSymbol(item.quote.symbol)
                        } label: {
                            MarketConstituentRow(item: item, trend: store.trendValues(for: item.quote))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("打开行情详情")
                    } else {
                        MarketConstituentRow(item: item, trend: store.trendValues(for: item.quote))
                            .accessibilityHint("该本地代码仅展示当前行情")
                    }
                    if item.id != items.last?.id { Divider().padding(.leading, 52) }
                }
                if store.isLoadingIndexConstituents(symbol: historicalSymbol) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在加载成分股")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
                } else if let error = store.constituentErrors[historicalSymbol] {
                    VStack(spacing: 6) {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                        Button("重新加载") {
                            Task { await store.loadIndexConstituents(symbol: historicalSymbol, force: true) }
                        }
                        .font(.footnote.weight(.semibold))
                        .frame(minWidth: 88, minHeight: 44)
                    }
                    .frame(maxWidth: .infinity, minHeight: 88)
                } else if store.indexConstituents[historicalSymbol] == nil {
                    Text("暂无成分股数据")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
            }
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
    }

    private var sessionText: String {
        quote?.tradingSession.displayLabel ?? "行情更新"
    }
    private var isCrypto: Bool { symbol.hasPrefix("BINANCE:") }
    private var isCommodity: Bool { quote?.instrumentType == "commodity-future" || symbol.hasSuffix("1!") }
    private var sessionColor: Color { quote?.marketSession == "regular" || quote?.marketSession == "always-open" ? MarketStyle.loss : .secondary }

    private var shareText: String {
        guard let quote else { return "\(CoreDescriptor(symbol: symbol).name)行情更新中" }
        return "\(quote.presentationName)（\(quote.displayCode)）\n最新价：\(number(quote.price, digits: 2))\n涨跌：\(signed(quote.changeValue, digits: 2))  \(quote.formattedPercent)\n状态：\(quote.freshnessLabel) · \(quote.marketAsOfLabel)\n来源：\(quote.dataSource ?? "行情服务")\n仅供行情参考，不构成投资建议。"
    }
}

private struct MarketDetailScrollTopPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct MarketDetailScrollTopTracker: ViewModifier {
    @Binding var isAtTop: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top <= 4
            } action: { _, newValue in
                isAtTop = newValue
            }
        } else {
            content
                .coordinateSpace(name: "market-detail-scroll")
                .onPreferenceChange(MarketDetailScrollTopPreferenceKey.self) { offset in
                    isAtTop = offset >= -4
                }
        }
    }
}

enum CompanyPEKind: String, CaseIterable, Identifiable {
    case staticPE
    case ttm

    var id: String { rawValue }
    var metricTitle: String { self == .staticPE ? "市盈率（静）" : "市盈率（TTM）" }
    var shortTitle: String { self == .staticPE ? "静态 PE" : "TTM PE" }
    var color: Color { self == .staticPE ? .indigo : .blue }
    var explanation: String {
        switch self {
        case .staticPE:
            "以各财年末静态市盈率为锚点，按 TradingView 每个交易日的复权收盘价换算；最新点使用当前市值与最近完整财年净利润。"
        case .ttm:
            "以各季度末滚动市盈率为锚点，按 TradingView 每个交易日的复权收盘价换算；最新点为当前最近十二个月市盈率。"
        }
    }
}

struct CompanyValuationHistoryRoute: Identifiable {
    let symbol: String
    let name: String
    let initialKind: CompanyPEKind

    var id: String { "\(symbol)-\(initialKind.rawValue)" }
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

private enum CompanyPETimeRange: String, CaseIterable, Identifiable {
    case fiveYears
    case tenYears
    case all

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fiveYears: "近 5 年"
        case .tenYears: "近 10 年"
        case .all: "全部"
        }
    }

    var years: Int? {
        switch self {
        case .fiveYears: 5
        case .tenYears: 10
        case .all: nil
        }
    }
}

struct CompanyValuationHistorySheet: View {
    let route: CompanyValuationHistoryRoute
    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: CompanyPEKind
    @State private var selectedRange: CompanyPETimeRange = .all
    @State private var selectedDate: Date?
    @State private var history: MarketCompanyValuationHistory?
    @State private var staticPoints: [CompanyPEChartPoint] = []
    @State private var ttmPoints: [CompanyPEChartPoint] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(route: CompanyValuationHistoryRoute) {
        self.route = route
        _selectedKind = State(initialValue: route.initialKind)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    Picker("市盈率口径", selection: $selectedKind) {
                        ForEach(CompanyPEKind.allCases) { kind in
                            Text(kind.shortTitle).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    rangePicker
                    chartCard
                    historyPositionCard
                    methodologyCard
                }
                .padding(18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("PE 历史变化")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottomTrailing) {
                DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭 PE 历史详情")
                    .padding(16)
            }
        }
        .task(id: route.symbol) { await load() }
        .onChange(of: selectedKind) { _, _ in selectedDate = nil }
        .onChange(of: selectedRange) { _, _ in selectedDate = nil }
    }

    private var rangePicker: some View {
        Picker("时间范围", selection: $selectedRange) {
            ForEach(CompanyPETimeRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(route.name)
                    .font(.title3.weight(.semibold))
                Text(route.symbol)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let latest = points.last {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(String(format: "%.2f", latest.value))
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(selectedKind.color)
                    Text("当前 \(selectedKind.shortTitle)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isLoading {
                ProgressView("正在加载真实历史数据")
                    .frame(maxWidth: .infinity, minHeight: 270)
            } else if let errorMessage {
                ContentUnavailableView(
                    "暂时无法显示曲线",
                    systemImage: "chart.xyaxis.line",
                    description: Text(errorMessage)
                )
                .frame(maxWidth: .infinity, minHeight: 270)
                Button("重新加载") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            } else if points.count < 2 {
                ContentUnavailableView(
                    "历史数据不足",
                    systemImage: "chart.xyaxis.line",
                    description: Text("至少需要两个真实历史点才能绘制变化曲线")
                )
                .frame(maxWidth: .infinity, minHeight: 270)
            } else {
                chartReading

                Chart {
                    ForEach(chartPoints) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("PE", point.value)
                        )
                        .foregroundStyle(selectedKind.color.gradient)
                        .lineStyle(.init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }

                    if let activePoint {
                        RuleMark(x: .value("查看日期", activePoint.date))
                            .foregroundStyle(selectedKind.color.opacity(0.28))
                            .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                        PointMark(
                            x: .value("查看日期", activePoint.date),
                            y: .value("PE", activePoint.value)
                        )
                        .foregroundStyle(selectedKind.color)
                        .symbolSize(55)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let plotFrame = proxy.plotFrame {
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    SpatialTapGesture()
                                        .onEnded { value in
                                            let frame = geometry[plotFrame]
                                            guard frame.contains(value.location) else { return }
                                            let locationX = value.location.x - frame.origin.x
                                            guard let date: Date = proxy.value(atX: locationX) else { return }
                                            selectedDate = date
                                        }
                                )
                        }
                    }
                }
                .chartYScale(domain: yDomain)
                .chartXScale(range: .plotDimension(startPadding: 10, endPadding: 34))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisValueLabel(format: .dateTime.year())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisValueLabel()
                    }
                }
                .frame(height: 270)

                Divider()

                HStack(spacing: 0) {
                    statistic("中位数", median)
                    statistic("历史分位", percentile, suffix: "%", digits: 0)
                    statistic("较前日", previousChange, suffix: "%", digits: 1, signed: true)
                }

                extremaRow
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        }
    }

    private var chartReading: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(activePoint?.id == points.last?.id ? "当前读数" : "历史读数")
                    Text("每日交易日 + 当前")
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(selectedKind.color.opacity(0.1), in: Capsule())
                        .foregroundStyle(selectedKind.color)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Text(activePoint.map { formattedDate($0.date) } ?? "—")
                    .font(.caption.weight(.medium))
                Text("轻点曲线查看读数，纵向滑动可直接滚动")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(activePoint.map { String(format: "%.2f", $0.value) } ?? "—")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(selectedKind.color)
                if selectedDate != nil {
                    Button("返回当前") { selectedDate = nil }
                        .font(.caption2.weight(.medium))
                }
            }
        }
    }

    private var extremaRow: some View {
        HStack(spacing: 10) {
            extremaBadge("区间最低", pointForMinimum, color: .green)
            extremaBadge("区间最高", pointForMaximum, color: .red)
        }
    }

    private func extremaBadge(_ title: String, _ point: CompanyPEChartPoint?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(point.map { String(format: "%.2f", $0.value) } ?? "—")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
                Text(point.map { formattedDate($0.date) } ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statistic(
        _ title: String,
        _ value: Double?,
        suffix: String = "",
        digits: Int = 2,
        signed: Bool = false
    ) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value.map {
                let prefix = signed && $0 > 0 ? "+" : ""
                return prefix + String(format: "%.*f", digits, $0) + suffix
            } ?? "—")
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var historyPositionCard: some View {
        if let percentile, let latest = points.last, let median {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("当前历史位置", systemImage: "scope")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(percentile.rounded()))% 分位")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(selectedKind.color)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.13))
                        Capsule()
                            .fill(selectedKind.color.gradient)
                            .frame(width: geometry.size.width * min(max(percentile / 100, 0), 1))
                    }
                }
                .frame(height: 8)

                Text("当前 \(String(format: "%.2f", latest.value))，高于所选区间约 \(Int(percentile.rounded()))% 的历史样本；区间中位数为 \(String(format: "%.2f", median))。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .padding(16)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var methodologyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("数据口径", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
            Text(selectedKind.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            if let history {
                Divider()
                HStack {
                    Text("频率")
                    Spacer()
                    Text(history.frequency == MarketCompanyValuationHistory.dailyFrequency ? "每个交易日" : history.frequency)
                }
                HStack {
                    Text("来源")
                    Spacer()
                    Text(history.source)
                }
                HStack {
                    Text("更新日期")
                    Spacer()
                    Text(formattedAsOf(history.asOf))
                }
                HStack {
                    Text("所选区间")
                    Spacer()
                    Text(rangeDescription)
                }
                Text("财务锚点按财务期末生效，用于保持 TradingView 历史口径一致；它不代表市场在该日已经获得对应财报。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var allPoints: [CompanyPEChartPoint] {
        selectedKind == .staticPE ? staticPoints : ttmPoints
    }

    private static func parsedPoints(_ rawPoints: [MarketCompanyPEPoint]) -> [CompanyPEChartPoint] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return rawPoints.compactMap { point in
            guard point.value.isFinite, point.value > 0, let date = formatter.date(from: point.date) else { return nil }
            return CompanyPEChartPoint(date: date, value: point.value)
        }
        .sorted { $0.date < $1.date }
    }

    private var points: [CompanyPEChartPoint] {
        guard let years = selectedRange.years, let lastDate = allPoints.last?.date else { return allPoints }
        let calendar = Calendar(identifier: .gregorian)
        guard let cutoff = calendar.date(byAdding: .year, value: -years, to: lastDate) else { return allPoints }
        return allPoints.filter { $0.date >= cutoff }
    }

    private var chartPoints: [CompanyPEChartPoint] {
        marketCompanyPEDisplayPoints(points)
    }

    private var values: [Double] { points.map(\.value) }

    private var activePoint: CompanyPEChartPoint? {
        guard let selectedDate else { return points.last }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private var median: Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let midpoint = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[midpoint - 1] + sorted[midpoint]) / 2 : sorted[midpoint]
    }

    private var percentile: Double? {
        guard let latest = points.last?.value, !values.isEmpty else { return nil }
        return Double(values.filter { $0 <= latest }.count) / Double(values.count) * 100
    }

    private var previousChange: Double? {
        guard points.count >= 2 else { return nil }
        let latest = points[points.count - 1].value
        let previous = points[points.count - 2].value
        guard previous != 0 else { return nil }
        return (latest / previous - 1) * 100
    }

    private var pointForMinimum: CompanyPEChartPoint? { points.min { $0.value < $1.value } }
    private var pointForMaximum: CompanyPEChartPoint? { points.max { $0.value < $1.value } }

    private var rangeDescription: String {
        guard let first = points.first, let last = points.last else { return "—" }
        return "\(formattedDate(first.date)) – \(formattedDate(last.date)) · \(points.count) 个点"
    }

    private var yDomain: ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let padding = max((high - low) * 0.12, max(high * 0.04, 1))
        return max(0, low - padding)...(high + padding)
    }

    private func formattedAsOf(_ value: String) -> String {
        String(value.prefix(10))
    }

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return String(format: "%d-%02d-%02d", year, month, day)
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loadedHistory = try await MarketService(baseURL: ServerConfiguration.currentURL)
                .companyValuationHistory(symbol: route.symbol)
            history = loadedHistory
            staticPoints = Self.parsedPoints(loadedHistory.peStatic)
            ttmPoints = Self.parsedPoints(loadedHistory.peTTM)
        } catch MarketServiceError.httpStatus(let status) where status == 404 {
            history = nil
            staticPoints = []
            ttmPoints = []
            errorMessage = "这家公司暂时没有可用的 PE 历史"
        } catch {
            history = nil
            staticPoints = []
            ttmPoints = []
            errorMessage = error.localizedDescription
        }
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
    let fallbackSymbol: String?
    let store: MarketStore
    @State private var inspectedPoint: MarketChartPoint?

    private var primaryChart: MarketChart? { store.chart(symbol: symbol, range: selectedRange) }
    private var fallbackChart: MarketChart? {
        guard let fallbackSymbol else { return nil }
        return store.chart(symbol: fallbackSymbol, range: selectedRange)
    }
    private var usesFallbackChart: Bool {
        marketShouldUseFallbackChart(
            primaryPoints: primaryChart?.candles ?? [],
            fallbackPoints: fallbackChart?.candles ?? []
        )
    }
    private var displayedSymbol: String { usesFallbackChart ? fallbackSymbol ?? symbol : symbol }
    private var chart: MarketChart? { usesFallbackChart ? fallbackChart : primaryChart }
    private var points: [MarketChartPoint] {
        marketChartDisplayPoints(chart?.candles ?? []).sorted { $0.timestamp < $1.timestamp }
    }
    private var values: [Double] {
        points.compactMap(\.displayValue)
    }

    var body: some View {
        VStack(spacing: 0) {
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
            Divider()
            ZStack {
                ChartGrid(values: values)
                if values.isEmpty {
                    if isLoadingChart {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("正在加载\(selectedRange.rawValue)走势图")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    else if let error = displayedChartError {
                        VStack(spacing: 8) {
                            Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                            Button("重新加载") { Task { await reloadChart() } }
                                .font(.system(size: 12, weight: .semibold)).frame(minWidth: 88, minHeight: 44)
                        }
                    } else { Text(chartStatusMessage).font(.system(size: 12)).foregroundStyle(.secondary) }
                } else {
                    MarketSessionLineChart(
                        points: points,
                        regularColor: quoteTint(store.quote(symbol: displayedSymbol)),
                        interval: chart?.interval
                    )
                        .id(selectedRange)
                        .padding(.leading, 48).padding(.top, 9).padding(.bottom, 6)
                    if let sessionBreak = marketChartLunchBreak(
                        points: points,
                        market: chart?.market,
                        interval: chart?.interval,
                        timezone: chart?.timezone
                    ) {
                        MarketSessionBreakMarker(
                            sessionBreak: sessionBreak,
                            points: points,
                            interval: chart?.interval
                        )
                        .padding(.leading, 48).padding(.top, 9).padding(.bottom, 6)
                    }
                    if let previousClose = store.quote(symbol: displayedSymbol)?.previousClose {
                        ChartReferenceLine(value: previousClose, values: values)
                    }
                    ChartInspectionOverlay(
                        points: points,
                        interval: chart?.interval,
                        range: selectedRange,
                        timezone: chart?.timezone,
                        tint: quoteTint(store.quote(symbol: displayedSymbol)),
                        selected: $inspectedPoint
                    )
                }
            }
            .frame(height: 210)
            .padding(.top, 10)
            .animation(MarketStyle.chartTransition, value: selectedRange)
            HStack {
                ForEach(Array(timelineLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                    if index < 2 { Spacer() }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.leading, 48)
            .padding(.trailing, 5)
            .padding(.top, 5)
            if hasVolume {
                VolumeBars(points: points, interval: chart?.interval)
                    .frame(height: 22)
                    .padding(.leading, 48)
                    .padding(.top, 4)
            }
            Text(chartCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
            if let coverageMessage {
                Text(coverageMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 5)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .task(id: ChartKey(symbol: symbol, range: selectedRange)) {
            inspectedPoint = nil
            await store.loadChart(symbol: symbol, range: selectedRange)
            if marketChartDisplayPoints(primaryChart?.candles ?? []).count < 2,
               let fallbackSymbol {
                await store.loadChart(symbol: fallbackSymbol, range: selectedRange)
            }
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
        let sessionText = marketChartExtendedSessionLabel(points).map { " · \($0)" } ?? ""
        let referenceText = usesFallbackChart ? " · 参考 \(displayedSymbol)" : ""
        return hasVolume ? "\(dated)\(sessionText)\(referenceText) · 成交量" : "\(dated)\(sessionText)\(referenceText)"
    }
    private var isLoadingChart: Bool {
        store.loadingCharts.contains(ChartKey(symbol: symbol, range: selectedRange))
            || fallbackSymbol.map { store.loadingCharts.contains(ChartKey(symbol: $0, range: selectedRange)) } == true
    }
    private var displayedChartError: String? {
        if let fallbackSymbol,
           let fallbackError = store.chartError(symbol: fallbackSymbol, range: selectedRange) {
            return fallbackError
        }
        return store.chartError(symbol: symbol, range: selectedRange)
    }
    private func reloadChart() async {
        await store.loadChart(symbol: symbol, range: selectedRange, force: true)
        if marketChartDisplayPoints(primaryChart?.candles ?? []).count < 2,
           let fallbackSymbol {
            await store.loadChart(symbol: fallbackSymbol, range: selectedRange, force: true)
        }
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

private struct MarketSessionBreakMarker: View {
    let sessionBreak: MarketChartSessionBreak
    let points: [MarketChartPoint]
    let interval: String?

    var body: some View {
        GeometryReader { proxy in
            let sorted = points.sorted { $0.timestamp < $1.timestamp }
            let fractions = marketChartXFractions(timestamps: sorted.map(\.timestamp), interval: interval)
            let fractionByTimestamp = Dictionary(uniqueKeysWithValues: zip(sorted.map(\.timestamp), fractions))
            let start = fractionByTimestamp[sessionBreak.previousTimestamp] ?? 0
            let end = fractionByTimestamp[sessionBreak.currentTimestamp] ?? start
            let x = proxy.size.width * (start + end) / 2
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: x, y: 24))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                }
                .stroke(Color.secondary.opacity(0.28), style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
                Text(sessionBreak.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                    .fixedSize()
                    .position(x: min(max(x, 30), proxy.size.width - 30), y: 10)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ChartInspectionOverlay: View {
    let points: [MarketChartPoint]
    let interval: String?
    let range: MarketRange
    let timezone: String?
    let tint: Color
    @Binding var selected: MarketChartPoint?

    var body: some View {
        GeometryReader { proxy in
            let leftInset: CGFloat = 48
            let usableWidth = max(proxy.size.width - leftInset, 1)
            let topInset: CGFloat = 9
            let bottomInset: CGFloat = 6
            let usableHeight = max(proxy.size.height - topInset - bottomInset, 1)
            let fractions = marketChartXFractions(timestamps: points.map(\.timestamp), interval: interval)
            ZStack(alignment: .topLeading) {
                if let selected, let index = points.firstIndex(where: { $0.id == selected.id }) {
                    let x = leftInset + usableWidth * fractions[index]
                    let y = topInset + usableHeight * normalizedY(selected.displayValue ?? selected.close)
                    Path { path in
                        path.move(to: CGPoint(x: x, y: topInset))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height - bottomInset))
                    }
                    .stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
                    Circle()
                        .fill(MarketStyle.surface)
                        .frame(width: 8, height: 8)
                        .overlay { Circle().stroke(tint, lineWidth: 2) }
                        .position(x: x, y: y)
                    Text("\(chartTime(selected.timestamp, range: range, timezone: timezone))  \(number(selected.displayValue ?? selected.close, digits: 2))")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(MarketStyle.divider, lineWidth: 0.5)
                        }
                        .shadow(color: Color.black.opacity(0.08), radius: 5, y: 2)
                        .fixedSize()
                        .position(
                            x: min(max(x, 84), proxy.size.width - 84),
                            y: max(y - 28, 20)
                        )
                }
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        guard !points.isEmpty else { return }
                        let fraction = min(max((value.location.x - leftInset) / usableWidth, 0), 1)
                        let index = fractions.enumerated().min { abs($0.element - fraction) < abs($1.element - fraction) }?.offset ?? 0
                        selected = points[index]
                    })
            }
        }
    }

    private func normalizedY(_ value: Double) -> CGFloat {
        let displayValues = points.compactMap(\.displayValue)
        guard let low = displayValues.min(), let high = displayValues.max(), high > low else { return 0.5 }
        return 0.06 + CGFloat((high - value) / (high - low)) * 0.88
    }
}

private struct ChartReferenceLine: View {
    let value: Double
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            if let low = values.min(), let high = values.max(), high > low, value >= low, value <= high {
                let topInset: CGFloat = 19
                let bottomInset: CGFloat = 6
                let chartHeight = max(proxy.size.height - topInset - bottomInset, 1)
                let y = topInset + chartHeight * (0.06 + CGFloat((high - value) / (high - low)) * 0.88)
                Path { path in
                    path.move(to: CGPoint(x: 48, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
                .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
            guard sorted.count > 1 else { return }
            let fractions = marketChartXFractions(timestamps: sorted.map(\.timestamp), interval: interval)
            let fractionByTimestamp = Dictionary(uniqueKeysWithValues: zip(sorted.map(\.timestamp), fractions))
            let low = sorted.map(\.close).min() ?? 0
            let high = sorted.map(\.close).max() ?? low
            let span = max(high - low, 0.000_001)
            func canvasPoint(_ point: MarketChartPoint) -> CGPoint {
                CGPoint(
                    x: size.width * (fractionByTimestamp[point.timestamp] ?? 0),
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
                if isRegular, let first = segment.first, let last = segment.last {
                    var fill = path
                    fill.addLine(to: CGPoint(x: canvasPoint(last).x, y: size.height))
                    fill.addLine(to: CGPoint(x: canvasPoint(first).x, y: size.height))
                    fill.closeSubpath()
                    context.fill(
                        fill,
                        with: .linearGradient(
                            Gradient(colors: [regularColor.opacity(0.18), regularColor.opacity(0.01)]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: 0, y: size.height)
                        )
                    )
                }
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
    let interval: String?
    var body: some View {
        Canvas { context, size in
            let sorted = points.sorted { $0.timestamp < $1.timestamp }
            guard sorted.count > 1 else { return }
            let maxVolume = marketChartVolumeCeiling(sorted)
            let fractions = marketChartXFractions(timestamps: sorted.map(\.timestamp), interval: interval)
            let minimumGap = zip(fractions, fractions.dropFirst()).map { $1 - $0 }.filter { $0 > 0 }.min() ?? 1
            let barWidth = min(max(size.width * minimumGap * 0.72, 1), 8)

            for (index, point) in sorted.enumerated() {
                guard let volume = point.volume, volume > 0 else { continue }
                let height = max(2, size.height * CGFloat(min(volume, maxVolume) / maxVolume))
                let x = marketVolumeBarX(fraction: fractions[index], width: size.width, barWidth: barWidth)
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
    let isIndex: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MarketStyle.gain)
                Text("行情洞察")
                    .font(.system(size: 19, weight: .semibold))
                Spacer()
                Text(quote?.freshnessLabel ?? "更新中")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(summary)
                .font(.subheadline)
                .lineSpacing(4)
                .foregroundStyle(.primary.opacity(0.88))
            HStack(spacing: 8) {
                insightTag(relativeCloseLabel, tint: quoteTint(quote))
                insightTag(amplitudeLabel, tint: MarketStyle.accent)
                if let quote {
                    insightTag("成交量 \(quote.volume.map(compactNumber) ?? "—")", tint: .secondary)
                }
            }
            Text("仅供行情参考，不构成投资建议。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    private var summary: String {
        guard let quote else { return "正在获取最新行情。" }
        let subject = isIndex ? "指数" : "价格"
        let direction = quote.changeValue >= 0 ? "高于" : "低于"
        guard let high = quote.high, let low = quote.low, high > low else {
            return "\(subject)当前\(direction)昨收，最新行情仍在更新。"
        }
        let position = (quote.price - low) / (high - low)
        let positionText: String
        switch position {
        case ..<0.35: positionText = "区间下部"
        case 0.65...: positionText = "区间上部"
        default: positionText = "区间中部"
        }
        return "\(subject)当前\(direction)昨收，日内运行于 \(number(low, digits: 2))–\(number(high, digits: 2))，目前位于\(positionText)。"
    }

    private var relativeCloseLabel: String {
        guard let quote else { return "等待行情" }
        return quote.changeValue >= 0 ? "高于昨收" : "低于昨收"
    }

    private var amplitudeLabel: String {
        guard let quote, let high = quote.high, let low = quote.low else { return "振幅 —" }
        let baseline = quote.previousClose ?? low
        guard baseline != 0 else { return "振幅 —" }
        return "振幅 \(number((high - low) / baseline * 100, digits: 2))%"
    }

    private func insightTag(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(tint.opacity(0.18), lineWidth: 0.5)
            }
    }
}

private struct MarketConstituentRow: View {
    let item: MarketIndexConstituent
    let trend: [Double]
    private var quote: MarketQuote { item.quote }

    var body: some View {
        HStack(spacing: 10) {
            CompanyLogo(quote: quote, path: item.logoPath)
            VStack(alignment: .leading, spacing: 4) {
                Text(quote.presentationName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                HStack(spacing: 5) {
                    Text(quote.symbol)
                    if let weight = item.weight {
                        Text("· \(number(weight, digits: 2))%")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            Sparkline(
                values: trend,
                color: quoteTint(quote),
                showsFill: false
            )
            .frame(width: 64, height: 26)
            VStack(alignment: .trailing, spacing: 4) {
                Text(number(quote.price, digits: 2)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                Text(quote.formattedPercent).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(quoteTint(quote))
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(quote.presentationName)，\(quote.symbol)，市值 \(quote.marketCap.map(compactNumber) ?? "未知")，最新价 \(number(quote.price, digits: 2))，\(quote.formattedPercent)，点按查看详情")
    }
}

private struct MarketInstrumentLogo: View {
    let quote: MarketQuote
    let path: String?
    var size: CGFloat = 40

    @ViewBuilder
    var body: some View {
        if let commodity = CommodityLogoKind(symbol: quote.symbol) {
            CommodityLogo(kind: commodity, size: size)
        } else {
            CompanyLogo(quote: quote, path: path, size: size)
        }
    }
}

private struct CommodityLogo: View {
    let kind: CommodityLogoKind
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: size * 0.72, height: size * 0.72)
                .offset(x: size * 0.25, y: size * 0.24)
            if kind.isLivestock {
                Text(kind.logoText)
                    .font(.system(size: size * 0.52))
            } else {
                Text(kind.logoText)
                    .font(.system(size: size * (kind == .crudeOil ? 0.25 : 0.32), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 0.75)
        }
        .shadow(color: colors.last?.opacity(0.18) ?? .clear, radius: 2, y: 1)
        .accessibilityLabel("\(kind.accessibilityName)标识")
    }

    private var colors: [Color] {
        switch kind {
        case .gold:
            [Color(red: 0.98, green: 0.75, blue: 0.18), Color(red: 0.73, green: 0.43, blue: 0.03)]
        case .crudeOil:
            [Color(red: 0.29, green: 0.31, blue: 0.34), Color(red: 0.08, green: 0.09, blue: 0.11)]
        case .copper:
            [Color(red: 0.86, green: 0.46, blue: 0.25), Color(red: 0.55, green: 0.20, blue: 0.10)]
        case .silver:
            [Color(red: 0.76, green: 0.81, blue: 0.87), Color(red: 0.38, green: 0.46, blue: 0.57)]
        case .naturalGas:
            [Color(red: 0.24, green: 0.67, blue: 0.96), Color(red: 0.10, green: 0.32, blue: 0.72)]
        case .corn:
            [Color(red: 0.64, green: 0.76, blue: 0.20), Color(red: 0.23, green: 0.48, blue: 0.15)]
        case .liveCattle:
            [Color(red: 0.73, green: 0.49, blue: 0.27), Color(red: 0.35, green: 0.20, blue: 0.12)]
        case .feederCattle:
            [Color(red: 0.38, green: 0.63, blue: 0.45), Color(red: 0.15, green: 0.34, blue: 0.22)]
        case .leanHogs:
            [Color(red: 0.94, green: 0.53, blue: 0.61), Color(red: 0.68, green: 0.23, blue: 0.34)]
        }
    }
}

private struct CompanyLogo: View {
    let quote: MarketQuote
    let path: String?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let logoURL {
                MarketCachedLogoImage(url: logoURL, size: size, fallback: AnyView(fallback))
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.25))
        .overlay { RoundedRectangle(cornerRadius: size * 0.25).stroke(MarketStyle.divider, lineWidth: 0.5) }
    }

    private var fallback: some View {
        Text(String(quote.presentationName.prefix(2)))
            .font(.system(size: size * 0.25, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .minimumScaleFactor(0.7)
    }

    private var logoURL: URL? {
        marketCompanyLogoURL(path)
    }

}

private func marketCompanyLogoURL(_ path: String?) -> URL? {
    guard let path, !path.isEmpty else { return nil }
    guard let url = URL(string: path, relativeTo: ServerConfiguration.currentURL)?.absoluteURL else { return nil }
    return MediaURL.image(url.absoluteString) ?? url
}

@MainActor
private final class MarketLogoImageCache {
    static let shared = MarketLogoImageCache()

    private let images = NSCache<NSURL, UIImage>()
    private var requests: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        images.countLimit = 160
        images.totalCostLimit = 24 * 1_024 * 1_024
    }

    func cachedImage(for url: URL) -> UIImage? {
        images.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let image = cachedImage(for: url) { return image }
        if let request = requests[url] { return await request.value }

        let request = Task { () -> UIImage? in
            var urlRequest = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
            urlRequest.timeoutInterval = 20
            guard let (data, response) = try? await URLSession.shared.data(for: urlRequest),
                  (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) ?? true,
                  let image = UIImage(data: data) else { return nil }
            return image
        }
        requests[url] = request
        let image = await request.value
        requests[url] = nil
        if let image {
            images.setObject(image, forKey: url as NSURL, cost: image.marketCacheCost)
        }
        return image
    }
}

private struct MarketCachedLogoImage: View {
    let url: URL
    let size: CGFloat
    let fallback: AnyView
    @State private var loadedImage: UIImage?

    var body: some View {
        Group {
            if let image = loadedImage ?? MarketLogoImageCache.shared.cachedImage(for: url) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.15)
            } else {
                fallback
            }
        }
        .task(id: url) {
            loadedImage = await MarketLogoImageCache.shared.image(for: url)
        }
    }
}

private extension UIImage {
    var marketCacheCost: Int {
        guard let cgImage else { return Int(size.width * size.height * scale * scale * 4) }
        return cgImage.bytesPerRow * cgImage.height
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
        CoreRegion(title: "美国", symbols: ["SPY", "QQQ", "DIA"]),
        CoreRegion(title: "中国 / 香港", symbols: ["000001.SS", "000300.SS", "000688.SS", "^HSTECH", "^HSI"]),
        CoreRegion(title: "日本 / 韩国", symbols: ["^N225", "^KS11"]),
        CoreRegion(title: "欧洲", symbols: ["^STOXX50E", "^GDAXI", "^FTSE", "^FCHI"]),
    ]
}

private struct CoreDescriptor {
    let symbol: String
    var isIndex: Bool {
        switch symbol {
        case "SPY", "QQQ", "DIA", "000001.SS", "000016.SS", "000300.SS", "399006.SZ",
             "000688.SS", "000905.SS", "000852.SS", "932000.SS", "THS:883418", "^HSTECH",
             "^HSI", "^N225", "^KS11", "^STOXX50E", "^GDAXI", "^FTSE", "^FCHI":
            true
        default:
            false
        }
    }
    var name: String { switch symbol { case "SPY": "标普500实时代理（SPY）"; case "QQQ": "纳斯达克100实时代理（QQQ）"; case "DIA": "道琼斯实时代理（DIA）"; case "000001.SS": "上证指数"; case "000016.SS": "上证50"; case "000300.SS": "沪深300"; case "399006.SZ": "创业板指"; case "000688.SS": "科创50"; case "000905.SS": "中证500"; case "000852.SS": "中证1000"; case "932000.SS": "中证2000"; case "THS:883418": "微盘股"; case "^HSTECH": "恒生科技指数"; case "^HSI": "恒生指数"; case "^N225": "日经225"; case "^KS11": "韩国KOSPI"; case "^STOXX50E": "欧洲STOXX 50"; case "^GDAXI": "德国DAX"; case "^FTSE": "英国富时100"; case "^FCHI": "法国CAC 40"; case "GC1!": "COMEX 黄金"; case "CL1!": "WTI 原油"; case "HG1!": "COMEX 铜"; case "SI1!": "COMEX 白银"; case "NG1!": "NYMEX 天然气"; case "ZC1!": "CBOT 玉米"; default: symbol } }
    var code: String { switch symbol { case "SPY", "QQQ", "DIA": symbol; case "000001.SS": "000001.SH"; case "000300.SS": "000300.SH"; case "000688.SS": "000688.SH"; case "^HSTECH": "HSTECH"; case "^HSI": "HSI"; case "^N225": "N225"; case "^KS11": "KOSPI"; case "^STOXX50E": "SX5E"; case "^GDAXI": "DAX"; case "^FTSE": "FTSE"; case "^FCHI": "CAC40"; default: symbol } }
    var icon: String { switch symbol { case "QQQ": "q.circle.fill"; case "DIA": "building.columns.fill"; case "000001.SS", "000300.SS": "building.2.fill"; case "000688.SS": "cpu.fill"; case "^HSTECH": "asterisk"; case "^HSI": "h.circle.fill"; case "^N225": "yensign.circle.fill"; case "^KS11": "k.circle.fill"; case "^STOXX50E": "globe.europe.africa.fill"; case "^GDAXI": "shield.fill"; case "^FTSE": "sterlingsign.circle.fill"; case "^FCHI": "f.circle.fill"; default: "star.fill" } }
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
private func marketHeroChangeText(_ quote: MarketQuote) -> String {
    guard !quote.hasSuspiciousIndexMove else { return "异常波动待核验" }
    return "\(signed(quote.changeValue, digits: cryptoChangeDigits(quote)))  \(quote.formattedPercent)"
}

private extension DateFormatter {
    static let marketTradingDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
private func compactNumber(_ value: Double) -> String { value.formatted(.number.notation(.compactName).precision(.fractionLength(1))) }

func marketFinancialAmount(_ value: Double, currency: String) -> String {
    let magnitude = abs(value)
    let divisor: Double
    let unit: String
    if magnitude >= 100_000_000 {
        divisor = 100_000_000
        unit = "亿"
    } else if magnitude >= 10_000 {
        divisor = 10_000
        unit = "万"
    } else {
        divisor = 1
        unit = ""
    }
    let scaled = value / divisor
    let number = scaled.formatted(.number.precision(.fractionLength(0...1)))
    let currencyLabel = switch currency.uppercased() {
    case "USD": "美元"
    case "CNY", "RMB": "元"
    case "HKD": "港元"
    case "JPY": "日元"
    case "KRW": "韩元"
    case "EUR": "欧元"
    case "GBP": "英镑"
    case "": ""
    default: currency.uppercased()
    }
    return "\(number) \(unit)\(currencyLabel)".trimmingCharacters(in: .whitespaces)
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
