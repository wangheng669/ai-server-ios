import Charts
import SwiftUI
import UIKit

private enum MarketStyle {
    static let canvas = InvestmentDesign.surface
    static let surface = InvestmentDesign.surface
    static let secondarySurface = InvestmentDesign.secondarySurface
    static let cardSurface = InvestmentDesign.surface
    static let cardBorder = Color.clear
    static let divider = InvestmentDesign.divider
    static let gain = InvestmentDesign.gain
    static let loss = InvestmentDesign.loss
    static let accent = Color(red: 0.98, green: 0.36, blue: 0.12)
    static let live = Color(red: 0.08, green: 0.72, blue: 0.40)
    static let purple = accent
    static let pageSpacing: CGFloat = 12
    static let pageInset: CGFloat = 16
    static let cornerRadius: CGFloat = 18
}

struct MarketDetailRoute: Identifiable, Equatable {
    let symbol: String
    var companyName: String? = nil
    var id: String { symbol }
}

extension View {
    func marketInstrumentDetailSheet(item: Binding<MarketDetailRoute?>, store: MarketStore) -> some View {
        appSheet(item: item) { route in
            MarketInstrumentDetailView(route: route, store: store) { symbol in
                item.wrappedValue = MarketDetailRoute(symbol: symbol)
            }
            .id(route.symbol)
            .appPresentationDetents([.large])
            .appPresentationCornerRadius(28)
            .appPresentationBackground(MarketStyle.surface)
            .appPresentationScrollsWithoutExpanding()
        }
    }
}

// StateObject defers creation until SwiftUI installs the owning view. In particular,
// opening a sheet must not decode the holdings cache again through a view initializer.
@MainActor
private final class MarketDetailStores: ObservableObject {
    lazy var globalRanking = GlobalRankingStore()
    lazy var holdings = FamousHoldingsStore()
    lazy var companies = CompanyResearchStore()
}

struct MarketView: View {
    private let store: MarketStore
    private let investorMoodStore: InvestorMoodStore
    @StateObject private var detailStores = MarketDetailStores()
    private var globalRankingStore: GlobalRankingStore { detailStores.globalRanking }
    private var holdingsStore: FamousHoldingsStore { detailStores.holdings }
    private let institutionResearchStore: InstitutionResearchStore
    @State private var rankingCategory = GlobalRankingCategory.countryGDP
    @State private var showsRetailInvestors = false
    @State private var showsInvestors = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--holdings-preview")
        #else
        false
        #endif
    }()
    @State private var showsGlobalRanking = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--gdp-preview") ||
            ProcessInfo.processInfo.arguments.contains("--global-assets-preview") ||
            ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--gdp-detail-preview=") })
        #else
        false
        #endif
    }()
    @State private var showsMarketQuotes = false
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

    private var isResearchVisible: Bool {
        rootTabIsActive && selectedDetail == nil && !showsMarketQuotes
            && !showsRetailInvestors && !showsInvestors && !showsGlobalRanking
    }

    @MainActor
    init(
        store: MarketStore,
        investorMoodStore: InvestorMoodStore,
        researchStore: InstitutionResearchStore
    ) {
        self.store = store
        self.investorMoodStore = investorMoodStore
        institutionResearchStore = researchStore
    }

    var body: some View {
        ResearchHomeView(
            store: store,
            researchStore: institutionResearchStore,
            companyStore: detailStores.companies,
            onOpenGlobalRanking: {
                rankingCategory = .globalAssets
                showsGlobalRanking = true
            },
            onOpenInvestors: {
                showsInvestors = true
            },
            onOpenMarketQuotes: {
                showsMarketQuotes = true
            },
            onOpenMarketDetail: { symbol in
                #if DEBUG
                AppModalTiming.beginRequest()
                #endif
                selectedDetail = MarketDetailRoute(symbol: symbol)
            },
            onOpenRetailInvestors: {
                showsRetailInvestors = true
            }
        )
        .environment(\.rootTabIsActive, isResearchVisible)
        .appSheet(isPresented: $showsRetailInvestors) {
            RetailInvestorView(store: investorMoodStore, onClose: { showsRetailInvestors = false })
                .appPresentationDetents([.large])
                .appPresentationCornerRadius(28)
                .appPresentationBackground(InvestmentDesign.surface)
                .appPresentationScrollsWithoutExpanding()
        }
        .appSheet(isPresented: $showsInvestors) {
            FamousHoldingsView(store: holdingsStore, onClose: { showsInvestors = false })
                .appPresentationDetents([.medium, .large])
                .appPresentationGrabber()
                .appPresentationCornerRadius(28)
                .appPresentationBackground(InvestmentDesign.surface)
                .appPresentationScrollsWithoutExpanding()
        }
        .appSheet(isPresented: $showsGlobalRanking) {
            CountryGDPRankingView(store: globalRankingStore, initialCategory: rankingCategory,
                                  onClose: { showsGlobalRanking = false })
                .appPresentationDetents([.large])
                .appPresentationCornerRadius(28)
                .appPresentationBackground(InvestmentDesign.surface)
                .appPresentationScrollsWithoutExpanding()
        }
        .appSheet(isPresented: $showsMarketQuotes) {
            MarketQuotesSheet(store: store)
                .appPresentationDetents([.large])
                .appPresentationCornerRadius(28)
                .appPresentationBackground(MarketStyle.surface)
                .appPresentationScrollsWithoutExpanding()
        }
        .marketInstrumentDetailSheet(item: $selectedDetail, store: store)
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await store.runUpdates()
        }
        .task(id: rootTabIsActive && scenePhase == .active) {
            guard rootTabIsActive, scenePhase == .active else { return }
            async let companies: Void = detailStores.companies.loadIfNeeded()
            async let holdings: Void = holdingsStore.load()
            _ = await (companies, holdings)
        }
        .task(id: rootTabIsActive && scenePhase == .active) {
            guard rootTabIsActive, scenePhase == .active else { return }
            while !Task.isCancelled {
                await investorMoodStore.refreshInvestorMood()
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard rootTabIsActive, phase == .active else { return }
            Task { await store.resumeUpdates() }
        }
    }
}

enum MarketRegion: String, CaseIterable, Identifiable {
    case unitedStates = "美国"
    case china = "中国"
    case japan = "日本"
    case korea = "韩国"
    case europe = "欧洲"
    case commodity = "商品"
    case crypto = "加密"

    static let stockRegions: [Self] = [.unitedStates, .china, .japan, .korea, .europe]

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
}

private enum MarketQuotesScope: Hashable, Identifiable {
    case global
    case region(MarketRegion)

    var id: String { region?.dashboardID ?? "global" }
    var title: String { region?.rawValue ?? "全球" }

    var region: MarketRegion? {
        guard case let .region(region) = self else { return nil }
        return region
    }
}

private struct MarketRegionPicker: View {
    let store: MarketStore
    @Binding var selection: MarketQuotesScope

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    scopeButton(.global, accessibilityLabel: "全球市场")
                    ForEach(MarketRegion.allCases) { region in
                        regionButton(region)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection, initial: true) { _, scope in
                proxy.scrollTo(scope, anchor: .center)
            }
        }
    }

    private func regionButton(_ region: MarketRegion) -> some View {
        let quote = store.quote(symbol: region.primarySymbol)
        let overnightQuote = region == .unitedStates && quote?.tradingSession != .regular
            ? marketActiveIndexSession(store.dashboard?.indexSessions?[region.primarySymbol])
            : nil
        let movementQuote = overnightQuote ?? quote
        let status = tabStatus(for: region, quote: quote, overnightQuote: overnightQuote)
        return scopeButton(.region(region), accessibilityLabel: "\(region.rawValue)，\(tabMovementLabel(for: movementQuote))，\(status.accessibilityLabel)")
    }

    private func scopeButton(_ scope: MarketQuotesScope, accessibilityLabel: String) -> some View {
        let isSelected = selection == scope
        return Button {
            selection = scope
        } label: {
            VStack(spacing: 6) {
                Text(scope.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? InvestmentDesign.accent : .primary)
                Capsule()
                    .fill(isSelected ? InvestmentDesign.accent : .clear)
                    .frame(height: 2)
            }
            .lineLimit(1)
            .frame(minWidth: 44, minHeight: 44)
            .background(isSelected ? InvestmentDesign.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .id(scope)
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("market-quotes-scope-\(scope.id)")
    }

    private func tabMovementTint(for quote: MarketQuote?) -> Color {
        marketChangeTint(quote?.marketDisplayPercentValue)
    }

    private func tabMovementLabel(for quote: MarketQuote?) -> String {
        guard let change = quote?.marketDisplayPercentValue else { return "涨跌暂缺" }
        if change > 0 { return String(format: "上涨 %.2f%%", change) }
        if change < 0 { return String(format: "下跌 %.2f%%", abs(change)) }
        return "平盘"
    }

    private func tabStatus(
        for region: MarketRegion,
        quote: MarketQuote?,
        overnightQuote: MarketQuote?
    ) -> (label: String, accessibilityLabel: String, tint: Color) {
        if region == .unitedStates, overnightQuote != nil {
            return ("夜盘", "期指夜盘交易中", MarketStyle.live)
        }

        if quote?.isMiddayBreak == true {
            return ("午休", "午间休市", .secondary)
        }

        switch quote?.tradingSession {
        case .regular:
            return ("交易中", "交易中", MarketStyle.live)
        case .premarket:
            return ("盘前", "盘前交易", MarketStyle.live)
        case .postmarket:
            return ("盘后", "盘后交易", MarketStyle.live)
        case .overnight:
            return ("夜盘", "夜盘交易", MarketStyle.live)
        case .alwaysOpen:
            return ("24H", "24小时交易", MarketStyle.live)
        case .closed:
            return ("休市", "已休市", Color.secondary)
        case .unknown, .none:
            return ("更新中", "交易状态更新中", Color.secondary)
        }
    }
}

private struct MarketQuotesSheet: View {
    @State private var scope: MarketQuotesScope = .global
    let store: MarketStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDetail: MarketDetailRoute?

    var body: some View {
        VStack(spacing: 0) {
            MarketRegionPicker(store: store, selection: $scope)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .background(InvestmentDesign.surface)
                .overlay(alignment: .bottom) { Divider() }

            TabView(selection: $scope) {
                ForEach([MarketQuotesScope.global] + MarketRegion.allCases.map(MarketQuotesScope.region)) { page in
                    MarketQuotesPage(scope: page, store: store, isActive: scope == page && selectedDetail == nil) { symbol in
                        selectedDetail = MarketDetailRoute(symbol: symbol)
                    }
                    .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(MarketStyle.surface)
        .floatingSheetClose("关闭市场行情", action: dismiss.callAsFunction)
        .accessibilityIdentifier("market-quotes-sheet")
        .accessibilityAction(.escape) { dismiss() }
        .marketInstrumentDetailSheet(item: $selectedDetail, store: store)
    }
}

private struct MarketQuotesPage: View {
    let scope: MarketQuotesScope
    let store: MarketStore
    let isActive: Bool
    let onSelectQuote: (String) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    @State private var showsMarketStructure = false
    @State private var chinaScope: ChinaIndexScope = .core
    @State private var displayedLogoPaths: [String: String]
    @ScaledMetric(relativeTo: .body) private var indexCardWidth: CGFloat = 136

    init(scope: MarketQuotesScope, store: MarketStore, isActive: Bool, onSelectQuote: @escaping (String) -> Void) {
        self.scope = scope
        self.store = store
        self.isActive = isActive
        self.onSelectQuote = onSelectQuote
        _displayedLogoPaths = State(initialValue: store.companyLogoPaths)
    }

    private var region: MarketRegion? { scope.region }

    private var indexSymbols: [String] {
        guard let region else {
            return ResearchHomeContent.chartSymbols + ["^KS11", "^STOXX50E", "GC1!", "BINANCE:BTCUSDT"]
        }
        return region == .china && chinaScope == .all ? region.allSymbols : region.symbols
    }

    private var indices: [MarketDashboardQuoteEntry] {
        indexSymbols.compactMap { symbol in
            if let quote = store.quote(symbol: symbol) { return .quote(quote) }
            return store.dashboard?.commodityEntries.first(where: { $0.id == symbol })
        }
    }

    private var regionalMetrics: [MarketDashboardQuoteEntry] {
        guard let region, let dashboard = store.dashboard,
              let definition = dashboard.regions.first(where: { $0.id == region.dashboardID }) else { return [] }
        let shown = Set(indexSymbols)
        return definition.metricSymbols.compactMap { symbol in
            guard !shown.contains(symbol) else { return nil }
            return dashboard.metricEntry(symbol: symbol)
        }
    }

    private var stocks: [MarketDashboardQuoteEntry] {
        guard let region else { return [] }
        return store.dashboard?.regionalStockEntries[region.dashboardID] ?? []
    }

    private var stocksTitle: String {
        store.dashboard?.componentsMeta?.label ?? "核心股票"
    }

    private var requestedQuotes: [MarketQuote] {
        (indices + regionalMetrics + stocks).compactMap(\.quote).reduce(into: [MarketQuote]()) { result, quote in
            guard !result.contains(where: { $0.symbol == quote.symbol }) else { return }
            result.append(quote)
        }
    }

    private var selectionDescription: String? {
        switch store.dashboard?.componentsMeta?.selectionBasis {
        case "regional-market-leaders": "区域市场代表公司"
        case "market-cap": "按市值筛选"
        default: nil
        }
    }

    var body: some View {
        let visibleRequestID = "\(requestID):\(isActive):\(scenePhase)"
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(indexSectionTitle)
                            .font(.headline)
                        Spacer()
                        if !indices.isEmpty {
                            Text("\(indices.count) 项")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 18)

                    if region == .china {
                        ChinaIndexScopePicker(selection: $chinaScope)
                        Button("查看中国市场结构", systemImage: "chart.pie") { showsMarketStructure = true }
                            .font(.subheadline)
                            .tint(InvestmentDesign.accent)
                            .padding(.horizontal, 18)
                    }

                    if indices.isEmpty {
                        emptyQuotes
                    } else {
                        quoteOverview(indices)
                            .accessibilityIdentifier("market-quotes-indices")
                    }
                }

                if !regionalMetrics.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("区域指标")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, 18)
                        quoteOverview(regionalMetrics)
                    }
                    .accessibilityIdentifier("market-quotes-regional-metrics")
                }

                if !stocks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(stocksTitle)
                                    .font(.title3.weight(.bold))
                                    .accessibilityIdentifier("market-quotes-stock-title")
                                Spacer()
                                Text("\(stocks.count) 家")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let selectionDescription {
                                Text(selectionDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 18)

                        LazyVStack(spacing: 0) {
                            ForEach(stocks) { entry in
                                switch entry {
                                case let .quote(quote):
                                    quoteRow(quote)
                                case let .unavailable(quote):
                                    unavailableQuoteButton(quote)
                                        .padding(.horizontal, 18)
                                }
                                if entry.id != stocks.last?.id {
                                    Divider().padding(.leading, 66).padding(.trailing, 18)
                                }
                            }
                        }

                        Text("曲线按最近交易日展示，可含盘前盘后及夜盘")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                    }
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 60)
        }
        .accessibilityIdentifier("market-quotes-page-\(scope.id)")
        .scrollIndicators(.hidden)
        .background(MarketStyle.surface)
        .appSheet(isPresented: $showsMarketStructure) {
            ChinaMarketStructureSheet(structure: store.dashboard?.marketStructure)

        }
        .task(id: visibleRequestID) {
            guard isActive, scenePhase == .active, region != .commodity else { return }
            await runWithLimitedConcurrency(requestedQuotes) { quote in
                await store.loadCompanyLogo(symbol: quote.symbol, name: quote.presentationName)
                guard let path = await store.companyLogoPaths[quote.symbol],
                      let url = marketCompanyLogoURL(path) else { return }
                _ = await MarketLogoImageCache.shared.image(for: url)
            }
            guard !Task.isCancelled else { return }
            displayedLogoPaths = store.companyLogoPaths
        }
        .task(id: visibleRequestID) {
            guard isActive, scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.preloadListCharts(symbols: requestedQuotes.map(\.symbol))
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
            }
        }
    }

    private var indexSectionTitle: String {
        switch scope {
        case .global: "全球市场"
        case .region(.commodity): "商品行情"
        case .region(.crypto): "加密资产"
        default: "主要指数"
        }
    }

    @ViewBuilder
    private func quoteOverview(_ entries: [MarketDashboardQuoteEntry]) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    switch entry {
                    case let .quote(quote):
                        quoteRow(quote)
                    case let .unavailable(quote):
                        unavailableQuoteButton(quote)
                            .padding(.horizontal, 18)
                    }
                    if entry.id != entries.last?.id {
                        Divider().padding(.horizontal, 18)
                    }
                }
            }
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: indexCardWidth), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(entries) { entry in
                    switch entry {
                    case let .quote(quote):
                        Button { onSelectQuote(quote.symbol) } label: {
                            MarketOverviewIndexCard(quote: quote, trend: store.listTrendValues(for: quote))
                        }
                        .buttonStyle(MarketPressStyle())
                        .accessibilityIdentifier("market-quote-\(quote.symbol)")
                        .accessibilityHint("弹出行情详情")
                    case let .unavailable(quote):
                        unavailableQuoteButton(quote)
                            .padding(.horizontal, 10)
                    }
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func unavailableQuoteButton(_ quote: MarketDashboardQuoteEntry.Unavailable) -> some View {
        Button { onSelectQuote(quote.symbol) } label: {
            MarketUnavailableQuoteRow(quote: quote, store: store)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("market-quote-\(quote.symbol)")
        .accessibilityHint("弹出行情详情")
    }

    private func quoteRow(_ quote: MarketQuote) -> some View {
        let lastTrade = store.lastSessionTrade(for: quote)
        return Button { onSelectQuote(quote.symbol) } label: {
            VStack(alignment: .leading, spacing: 0) {
                MarketOverviewQuoteRow(
                    quote: quote,
                    trend: store.listTrendValues(for: quote),
                    logoPath: displayedLogoPaths[quote.symbol],
                    hasLastTrade: lastTrade != nil
                )
                if let trade = lastTrade {
                    MarketLastSessionTradeNote(trade: trade, symbol: quote.symbol)
                        .padding(.leading, 66)
                        .padding(.trailing, 18)
                        .padding(.bottom, 8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("market-quote-\(quote.symbol)")
        .accessibilityHint("弹出行情详情")
    }

    private var emptyQuotes: some View {
        VStack(spacing: 12) {
            if store.isLoading {
                ProgressView()
                Text("正在加载\(scope.title)市场行情")
            } else {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                Text(store.errorMessage == nil ? "暂无\(scope.title)市场行情" : "行情暂时无法加载")
                if store.errorMessage != nil {
                    Button("重新加载") { Task { await store.refresh() } }
                        .buttonStyle(.bordered)
                        .tint(InvestmentDesign.accent)
                        .disabled(store.isRetrying)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 156)
        .padding(.horizontal, 18)
    }

    private var requestID: String {
        "\(scope.id):\(requestedQuotes.map(\.symbol).joined(separator: ","))"
    }
}

private struct MarketOverviewIndexCard: View {
    let quote: MarketQuote
    let trend: [Double]

    private var formattedPrice: String {
        marketQuotePriceText(quote)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(marketCardTitle(symbol: quote.symbol, name: quote.presentationName))
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(formattedPrice)
                        .font(.headline)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(quote.marketDisplayFormattedPercent)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(marketDisplayTint(quote))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                Sparkline(values: trend, color: marketDisplayTint(quote), showsFill: false)
                    .frame(width: 46, height: 26)
                    .accessibilityHidden(true)
            }
            Text(quote.freshnessLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarketStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(quote.presentationName)，\(quote.displayCode)，\(quote.freshnessLabel)，价格 \(formattedPrice)，涨跌幅 \(quote.marketDisplayFormattedPercent)")
    }
}

private struct MarketOverviewQuoteRow: View {
    let quote: MarketQuote
    let trend: [Double]
    let logoPath: String?
    let hasLastTrade: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesExpandedLayout: Bool { dynamicTypeSize >= .xxLarge }

    private var formattedPrice: String {
        guard quote.stale != true else { return "—" }
        return marketQuotePriceText(quote)
    }

    private var identitySubtitle: String {
        hasLastTrade ? quote.displayCode : "\(quote.displayCode) · \(quote.freshnessLabel)"
    }

    var body: some View {
        Group {
            if usesExpandedLayout {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        logo
                        identity
                    }
                    if dynamicTypeSize.isAccessibilitySize {
                        price.frame(maxWidth: .infinity, alignment: .leading)
                        sparkline.frame(height: 32)
                    } else {
                        HStack(spacing: 16) {
                            sparkline.frame(width: 84, height: 36)
                            Spacer(minLength: 0)
                            price
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    logo
                    identity.frame(maxWidth: .infinity, alignment: .leading)
                    sparkline.frame(width: 58, height: 30)
                    price
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(quote.presentationName)，\(identitySubtitle)，价格 \(formattedPrice)，涨跌幅 \(quote.marketDisplayFormattedPercent)")
    }

    private var logo: some View {
        MarketInstrumentLogo(quote: quote, path: logoPath, size: 34)
            .accessibilityHidden(true)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(marketCardTitle(symbol: quote.symbol, name: quote.presentationName))
                .font(.subheadline.weight(.semibold))
                .lineLimit(usesExpandedLayout ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            Text(identitySubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var price: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(formattedPrice)
                .font(.body.weight(.semibold))
                .monospacedDigit()
            Text(quote.marketDisplayFormattedPercent)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(marketDisplayTint(quote))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(minWidth: 76, alignment: .trailing)
                .background(marketDisplayTint(quote).opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var sparkline: some View {
        Group {
            if trend.count >= 2 {
                Sparkline(values: trend, color: marketDisplayTint(quote), showsFill: false)
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ChinaMarketStructureSheet: View {
    @Environment(\.dismiss) private var dismiss
    let structure: MarketStructure?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                ChinaMarketStructurePanel(structure: structure)
                    .padding(.bottom, 76)
            }
            .scrollIndicators(.hidden)
            .background(MarketStyle.surface)
        }
        .overlay(alignment: .bottomTrailing) {
            DetailSheetControls(closeLabel: "关闭资金与杠杆信号", onClose: dismiss.callAsFunction)
                .padding(12)
        }
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
                    Text("交易所日频数据 · ETF 信号按近 5 个交易日合计")
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
        case "accelerating": "近 5 日申购放量"
        case "inflow": "近 5 日净申购"
        case "outflow": "近 5 日净赎回"
        default: "近 5 日方向未明"
        }
    }

    private var latestDirection: String {
        let shares = subscription.latestNetSubscriptionShares
        return shares > 0 ? "净申购" : shares < 0 ? "净赎回" : "净申赎持平"
    }

    private var streakLabel: String {
        guard subscription.consecutiveDays > 0 else { return "连续性待观察" }
        let direction = subscription.consecutiveDirection == "outflow" ? "净赎回" : "净申购"
        return "连续 \(subscription.consecutiveDays) 日\(direction)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("科创50ETF 份额变化", systemImage: "arrow.left.arrow.right.circle")
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
                    Text("\(subscription.asOf) · \(latestDirection)")
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
                    Text("按收盘价估算 \(marketSignedMoney(estimatedFlow))")
                    Spacer(minLength: 4)
                    Text("覆盖 \(coverage) 只")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(marketChangeTint(estimatedFlow))
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

private enum MarketDetailPageStyle {
    static let canvas = InvestmentDesign.canvas
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let accent = InvestmentDesign.accent
    static let extended = Color(uiColor: .systemIndigo)
    static let cornerRadius: CGFloat = 14
}

private enum StockDetailStyle {
    static let ink = Color(red: 0.08, green: 0.14, blue: 0.22)
    static let plot = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let rule = Color(red: 0.88, green: 0.90, blue: 0.93)
    static let inset: CGFloat = 18
}

private struct MarketInstrumentDetailView: View {
    let route: MarketDetailRoute
    let store: MarketStore
    let onSelectSymbol: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedPeriod: MarketChartPeriod
    @State private var presentedValuation: CompanyValuationHistoryRoute?
    @State private var openingStockApp: MarketStockApp?
    @State private var stockAppError: String?

    init(route: MarketDetailRoute, store: MarketStore, onSelectSymbol: @escaping (String) -> Void) {
        self.route = route
        self.store = store
        self.onSelectSymbol = onSelectSymbol
        let showsDaily = route.symbol == "^VIX" || (route.companyName != nil && store.quote(symbol: route.symbol) == nil)
        _selectedPeriod = State(initialValue: showsDaily ? .daily : .intraday)
    }

    private var symbol: String { route.symbol }
    private var selectedRange: MarketRange { selectedPeriod.sourceRange }
    private var quote: MarketQuote? { store.quote(symbol: symbol) }
    private var constituent: MarketIndexConstituent? { store.constituent(symbol: symbol) }
    private var companyLogoPath: String? { constituent?.logoPath ?? store.companyLogoPaths[symbol] }
    private var historicalSymbol: String { quote?.historicalSymbol ?? symbol }
    private var chartSymbol: String { quote?.symbol ?? symbol }
    private var selectedRangeChart: MarketChart? {
        store.chartSnapshot(symbol: chartSymbol, range: selectedRange)?.artifacts.displays[selectedPeriod]?.chart
    }
    private var selectedPeriodReturn: Double? {
        guard selectedRange != .day else { return nil }
        return selectedRangeChart?.periodReturn?.percent
    }
    private var selectedPeriodVolatility: Double? {
        selectedRangeChart?.periodVolatility?.percent
    }
    private var isIndex: Bool {
        quote?.instrumentType == "reference-index"
            || store.dashboard?.coreIndices.contains(where: { $0.symbol == symbol }) == true
            || CoreDescriptor(symbol: symbol).isIndex
    }
    private var isStock: Bool {
        guard !isIndex, !isCrypto, !isCommodity else { return false }
        if route.companyName != nil || showsCompanyProfile { return true }
        return store.dashboard?.regionalStockEntries.values.contains { entries in
            entries.contains { $0.id == symbol }
        } == true
    }
    private var isAShareIndex: Bool {
        symbol.hasSuffix(".SS") || symbol.hasSuffix(".SZ") || symbol.hasPrefix("THS:")
    }
    private var stockLinks: MarketStockAppLinks? {
        guard !isIndex, !isCrypto, !isCommodity else { return nil }
        return MarketStockAppLinks(symbol: chartSymbol)
    }
    private var detailBreadth: MarketBreadth? {
        if isAShareIndex {
            return store.dashboard?.currentAShareBreadth
        }
        guard let items = store.indexConstituents[historicalSymbol]?.items, !items.isEmpty else { return nil }
        let changes = items.compactMap(\.quote.percentValue)
        guard changes.count == items.count else { return nil }
        let up = changes.filter { $0 > 0.005 }.count
        let down = changes.filter { $0 < -0.005 }.count
        return MarketBreadth(up: up, down: down, flat: changes.count - up - down, total: changes.count)
    }

    var body: some View {
        let links = stockLinks
        let showsStockControls = isStock || links != nil
        return VStack(spacing: 0) {
            if isStock { stockToolbar }
            else { detailToolbar }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: isStock ? 24 : 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        if isStock {
                            stockOverview
                        } else {
                            detailHeader
                            Divider().padding(.horizontal, 14)
                        }
                        MarketDetailChart(
                            selectedPeriod: $selectedPeriod,
                            symbol: chartSymbol,
                            store: store,
                            usesStockLayout: isStock
                        )
                        .id(chartSymbol)
                    }
                    .background(isStock ? Color.clear : MarketDetailPageStyle.card,
                                in: RoundedRectangle(cornerRadius: MarketDetailPageStyle.cornerRadius))

                    if isStock, showsStockSessionQuotes, let quote {
                        stockSessionHeader(quote)
                    }
                    keyData
                    if showsCompanyProfile { companyProfile }
                    if isIndex {
                        MarketDetailBreadth(
                            title: isAShareIndex ? "市场温度" : "成分表现",
                            breadth: detailBreadth
                        )
                        .background(MarketDetailPageStyle.card, in: RoundedRectangle(cornerRadius: MarketDetailPageStyle.cornerRadius))
                        componentStocks
                    }
                    if !isStock || quote != nil {
                        MarketSummary(quote: quote, isIndex: isIndex, quoteUnavailable: unavailableQuote != nil)
                    }
                    if unavailableQuote == nil, !isStock || quote != nil {
                        Text(quoteSourceText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 6)
                    }
                }
                .frame(maxWidth: isStock ? 640 : .infinity)
                .padding(.horizontal, isStock ? StockDetailStyle.inset : 10)
                .padding(.bottom, showsStockControls ? 76 : 60)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("market-detail-scroll")
        }
        .background((isStock ? InvestmentDesign.surface : MarketDetailPageStyle.canvas).ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            if showsStockControls {
                stockDetailControls(links)
                    .padding(12)
            }
        }
        .floatingSheetClose("关闭行情详情", identifier: "market-detail-close", isVisible: !showsStockControls, action: dismiss.callAsFunction)
        .accessibilityAction(.escape) { dismiss() }
        .alert("无法打开 App", isPresented: Binding(
            get: { stockAppError != nil },
            set: { if !$0 { stockAppError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(stockAppError ?? "")
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .appSheet(item: $presentedValuation) { route in
            CompanyValuationHistorySheet(route: route)
                .appPresentationDetents([.large])
                .appPresentationCornerRadius(28)
        }
        .task(id: openingStockApp) {
            if let app = openingStockApp, let links {
                await openStockApp(app, links: links)
            }
        }
        .task(id: isStock ? chartSymbol : nil) {
            guard isStock else { return }
            await store.preloadStockCharts(symbol: chartSymbol, ranges: [.day, .week, .year, .fiveYears, .maximum])
        }
        .task(id: historicalSymbol) {
            if isIndex {
                await store.loadIndexConstituents(symbol: historicalSymbol)
            } else if isStock || (quote != nil && !isCommodity && symbol != "^VIX") {
                await store.loadCompanyLogo(symbol: symbol, name: instrumentName)
            }
            guard !Task.isCancelled else { return }
            #if DEBUG
            if let preview = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--market-pe-history-preview=") }) {
                let value = String(preview.dropFirst("--market-pe-history-preview=".count))
                presentedValuation = valuationRoute(kind: value == "ttm" ? .ttm : .staticPE)
            }
            #endif
        }
        .task(id: isStock ? nil : chartSymbol) {
            guard !isStock else { return }
            await store.loadChart(symbol: chartSymbol, range: .year)
        }
        .task(id: isStock ? symbol : nil, priority: .utility) {
            guard isStock else { return }
            await store.stockQuotes.runUpdates(symbols: [symbol])
        }
    }

    private var instrumentName: String {
        let name = quote?.detailPresentationName ?? unavailableQuote?.presentationName
        if let name, name != symbol { return name }
        return route.companyName ?? CoreDescriptor(symbol: symbol).name
    }

    private var stockToolbar: some View {
        HStack(spacing: 10) {
            stockLogo
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(instrumentName)
                    .font(.headline)
                    .foregroundStyle(StockDetailStyle.ink)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("market-detail-title")
                Text(instrumentSubtitle)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 640, alignment: .leading)
        .padding(.horizontal, StockDetailStyle.inset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(InvestmentDesign.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(StockDetailStyle.rule).frame(height: 1) }
    }

    @ViewBuilder
    private var stockLogo: some View {
        if let quote {
            MarketInstrumentLogo(quote: quote, path: companyLogoPath, size: 32)
        } else {
            let monogram = Text(String(symbol.prefix(3)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(InvestmentDesign.accent)
            Group {
                if let url = marketCompanyLogoURL(companyLogoPath) {
                    MarketCachedLogoImage(url: url, size: 32, fallback: AnyView(monogram))
                } else {
                    monogram
                }
            }
            .frame(width: 32, height: 32)
            .background(InvestmentDesign.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var stockOverview: some View {
        let current = store.stockQuotes.currentQuote(for: symbol, marketStore: store)
        let close = store.stockQuotes.confirmedClose(for: symbol, marketStore: store)
        return VStack(alignment: .leading, spacing: 8) {
            if let price = current ?? close {
                stockPriceHero(price)
                if !showsStockSessionQuotes, current != nil, let close {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(close.label).font(.caption).foregroundStyle(.secondary)
                        Text(close.formattedAmount(symbol: symbol))
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            } else {
                Text(store.stockQuotes.snapshots[symbol] == nil && unavailableQuote == nil ? "正在读取报价" : "报价暂缺")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 70)
            }
            if let quote, let lastTrade = store.lastSessionTrade(for: quote) {
                MarketLastSessionTradeNote(trade: lastTrade, symbol: symbol)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    }

    private func stockPriceHero(_ price: MarketStockPrice) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    stockPriceAmount(price)
                    stockPriceChange(price)
                }
                VStack(alignment: .leading, spacing: 5) {
                    stockPriceAmount(price)
                    stockPriceChange(price)
                }
            }
            Text(price.label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("market-detail-price-status")
        }
        .monospacedDigit()
        .accessibilityElement(children: .contain)
    }

    private func stockPriceAmount(_ price: MarketStockPrice) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(number(price.amount, digits: marketPriceDigits(price.amount, symbol: symbol)))
                .font(.system(.largeTitle, weight: .bold))
                .tracking(-1.2)
                .foregroundStyle(StockDetailStyle.ink)
                .accessibilityIdentifier("market-detail-price")
            if let currency = price.currency, !currency.isEmpty {
                Text(currency).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func stockPriceChange(_ price: MarketStockPrice) -> some View {
        if let change = price.changePercent {
            Text(marketFormattedChangePercent(change))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(price.changeColor)
                .fixedSize()
                .accessibilityIdentifier("market-detail-change")
        }
    }

    private var detailToolbar: some View {
        HStack(spacing: 9) {
            if let quote {
                MarketInstrumentLogo(quote: quote, path: companyLogoPath, size: 37)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(instrumentName)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityIdentifier("market-detail-title")
                HStack(spacing: 6) {
                    Text(instrumentSubtitle)
                    Text("·").accessibilityHidden(true)
                    Text(quoteStatus)
                        .foregroundStyle(quote?.hasActiveExtendedSessionQuote == true && quote?.stale != true
                                         && !store.isShowingCachedSnapshot ? MarketDetailPageStyle.extended : .secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 15)
        .padding(.trailing, 10)
        .padding(.top, 11)
        .padding(.bottom, 8)
    }

    private func stockDetailControls(_ links: MarketStockAppLinks?) -> some View {
        DetailSheetControls(
            closeLabel: "关闭行情详情",
            closeIdentifier: "market-detail-close",
            onClose: dismiss.callAsFunction
        ) {
            if links != nil {
                ForEach(MarketStockApp.allCases) { app in
                    stockShortcut(app)
                }
            }
        }
    }

    private func stockShortcut(_ app: MarketStockApp) -> some View {
        Button {
            openingStockApp = app
        } label: {
            Text(app.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 5)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(openingStockApp != nil)
        .accessibilityLabel("在\(app.title) App 打开\(instrumentName)")
        .accessibilityIdentifier("market-\(app.rawValue)-link")
    }

    private func openStockApp(_ app: MarketStockApp, links: MarketStockAppLinks) async {
        defer { openingStockApp = nil }
        let url = try? await links.url(for: app)
        guard !Task.isCancelled else { return }
        guard let url else {
            stockAppError = "暂时无法在\(app.title)查到这只股票。"
            return
        }
        let options: [UIApplication.OpenExternalURLOptionsKey: Any] =
            app.requiresUniversalLink ? [.universalLinksOnly: true] : [:]
        let opened = await UIApplication.shared.open(url, options: options)
        if !opened, !Task.isCancelled {
            stockAppError = "请确认已安装\(app.title) App。"
        }
    }

    private var instrumentSubtitle: String {
        let instrument = quote?.detailInstrumentLabel ?? CoreDescriptor(symbol: symbol).code
        let currency = quote?.currency ?? unavailableQuote?.currency ?? store.stockQuotes.snapshots[symbol]?.history?.currency
        return [instrument, currency].compactMap { $0 }.joined(separator: " · ")
    }

    private var unavailableQuote: MarketDashboardQuoteEntry.Unavailable? {
        guard quote == nil else { return nil }
        return store.dashboard?.unavailableQuote(symbol: symbol)
    }

    private var quoteStatus: String {
        if unavailableQuote != nil { return "报价暂缺" }
        if store.isShowingCachedSnapshot || quote?.stale == true { return "行情待更新" }
        return quote?.freshnessLabel ?? "更新中"
    }

    private var quoteSourceText: String {
        guard let quote else { return "行情数据更新中" }
        let regular = quote.dataSource ?? "行情服务"
        if quote.hasActiveExtendedSessionQuote, let source = quote.sessionDataSource, source != regular {
            return "常规行情来源 \(regular) · \(quote.tradingSession.displayLabel)来源 \(source)"
        }
        return "行情来源 \(regular)"
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let missing = unavailableQuote {
                Text("当前报价暂缺")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let trade = store.lastSessionTrade(symbol: symbol, asOf: missing.quality.asOfTimestamp) {
                    MarketLastSessionTradeNote(trade: trade, symbol: symbol)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        detailPrice
                        detailChange
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 4) {
                        detailPrice
                        detailChange
                    }
                }
                Text(quote?.marketAsOfLabel ?? store.dashboard?.unavailableMetric(symbol: symbol)?.unavailableLabel
                     ?? "行情更新中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if selectedRange == .day, let quote, quote.hasActiveExtendedSessionQuote {
                    Text("较最近常规收盘 · \(number(quote.price, digits: marketPriceDigits(quote.price, symbol: quote.symbol)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showsStockSessionQuotes: Bool {
        guard !isIndex, !isCrypto, !isCommodity else { return false }
        let usStocks = store.dashboard?.regionalStockEntries[MarketRegion.unitedStates.dashboardID]
        return usStocks?.contains(where: { $0.id == symbol }) == true
            || (isStock && store.chart(symbol: chartSymbol, range: .day)?.market == "US")
    }

    private func stockSessionHeader(_ quote: MarketQuote) -> some View {
        let extended: MarketTradingSession = quote.tradingSession == .premarket ? .premarket : .overnight
        let sessions = store.stockSessionQuotes(for: quote, chartSymbol: chartSymbol, extendedSession: extended,
                                                isCurrent: quote.stale != true && !store.isShowingCachedSnapshot)
        return VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 4) {
                    stockSessionColumns(sessions, quote: quote)
                }
                VStack(alignment: .leading, spacing: 0) {
                    stockSessionColumns(sessions, quote: quote)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("market-detail-stock-sessions")

            Text(StockSessionQuotes.sourceNote(indicative: quote.hasIndicativeOvernightPrice))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
            if quote.stale == true || store.isShowingCachedSnapshot {
                Text(quote.marketAsOfLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stockSessionColumns(_ sessions: StockSessionQuotes, quote: MarketQuote) -> some View {
        ForEach(sessions.columns) { column in
            StockSessionPriceCell(column: column, symbol: quote.symbol, showsTitle: true)
        }
    }

    private var detailPrice: some View {
        Text(quote.map(marketQuotePriceText) ?? "—")
            .font(.title.weight(.semibold))
            .monospacedDigit()
            .tracking(-0.5)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityIdentifier("market-detail-price")
    }

    private var detailChange: some View {
        Text(detailPerformanceText)
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(detailPerformanceTint)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("market-detail-change")
    }

    private var detailPerformanceText: String {
        if selectedRange == .day {
            guard let quote else { return "等待行情数据" }
            let percent = quote.marketDisplayFormattedPercent
            guard let change = quote.marketDisplayChangeValue, !quote.hasSuspiciousIndexMove else { return percent }
            let digits = marketDetailPriceDigits(value: change, price: quote.marketDisplayPrice, symbol: quote.symbol)
            return "\(signed(change, digits: digits))  \(percent)"
        }
        guard let selectedPeriodReturn else { return "正在计算区间收益率" }
        let prefix = selectedPeriodReturn >= 0 ? "+" : "−"
        return "区间收益率  \(prefix)\(number(abs(selectedPeriodReturn), digits: 2))%"
    }

    private var detailPerformanceTint: Color {
        guard selectedRange != .day else { return marketDisplayTint(quote) }
        guard let selectedPeriodReturn else { return .secondary }
        if selectedPeriodReturn > 0 { return MarketStyle.gain }
        if selectedPeriodReturn < 0 { return MarketStyle.loss }
        return .secondary
    }

    private var detailVolatilityText: String {
        guard let selectedPeriodVolatility else { return "—" }
        return "\(number(selectedPeriodVolatility, digits: 2))%"
    }

    private var keyData: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .leading),
                            count: dynamicTypeSize.isAccessibilitySize ? 2 : 3)
        return VStack(alignment: .leading, spacing: isStock ? 13 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("行情数据")
                    .font(isStock ? .title3.weight(.semibold) : .headline)
                    .accessibilityIdentifier("market-detail-statistics")
                Spacer(minLength: 0)
                if quote?.hasActiveExtendedSessionQuote == true {
                    Text(yearChart.map { "常规盘 · \($0.tradingDate)" } ?? "最近常规盘")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                metric(isCrypto ? "24H开盘" : "开盘", quote?.openPrice)
                metric("最高", quote?.high)
                metric("最低", quote?.low)
                metric(quote?.hasActiveExtendedSessionQuote == true ? "常规收盘" : "昨收",
                       quote?.hasActiveExtendedSessionQuote == true ? quote?.price : quote?.previousClose)
                metric("成交量", quote?.volume, compact: true)
                textMetric("振幅", amplitudeText)
                metric("涨跌额", quote?.changeValue)
                metric("52周最高", market52WeekHigh(yearChart, symbol: chartSymbol))
                metric("52周最低", quote?.week52Low ?? market52WeekLow(yearChart))
            }
            Divider()
            companyMetric("年化波动率", value: detailVolatilityText)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("年化波动率")
                .accessibilityValue(detailVolatilityText)
                .accessibilityIdentifier("market-detail-metric-年化波动率")
        }
        .padding(.horizontal, isStock ? 0 : 14)
        .padding(.vertical, 14)
        .background(isStock ? Color.clear : MarketDetailPageStyle.card,
                    in: RoundedRectangle(cornerRadius: MarketDetailPageStyle.cornerRadius))
        .overlay(alignment: .top) {
            if isStock { Rectangle().fill(StockDetailStyle.rule).frame(height: 1) }
        }
    }

    private var yearChart: MarketChart? {
        store.chart(symbol: chartSymbol, range: .year)
    }

    private var showsCompanyProfile: Bool {
        !isIndex && (constituent != nil || quote?.marketCap != nil || quote?.peStatic != nil || quote?.pe != nil)
    }

    private var companyProfile: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("公司资料").font(.headline)
                Spacer()
                Text(companyMarketLabel(symbol)).font(.caption2).foregroundStyle(.secondary)
            }
            if let marketCap = quote?.marketCap {
                companyMetric("总市值", value: compactNumber(marketCap))
            }
            valuationMetric(.staticPE, value: quote?.peStatic)
            valuationMetric(.ttm, value: quote?.pe)
            companyMetric("归母净利润（TTM）", value: formattedNetIncome)
            if let fiscalYear = quote?.fiscalYear, !fiscalYear.isEmpty {
                companyMetric("财报基准", value: "FY\(fiscalYear)")
            }
            if let source = quote?.fundamentalsSource, !source.isEmpty {
                companyMetric("基础数据", value: source)
            }
        }
        .padding(.horizontal, isStock ? 0 : 14)
        .padding(.vertical, 14)
        .background(isStock ? .clear : MarketDetailPageStyle.card,
                    in: RoundedRectangle(cornerRadius: MarketDetailPageStyle.cornerRadius))
        .overlay(alignment: .top) {
            if isStock { Rectangle().fill(StockDetailStyle.rule).frame(height: 1) }
        }
    }

    private var formattedNetIncome: String {
        guard let quote, let netIncome = quote.netIncomeTTM else { return "—" }
        return marketFinancialAmount(netIncome, currency: quote.fundamentalsCurrency ?? quote.currency ?? "")
    }

    private func valuationMetric(_ kind: CompanyPEKind, value: Double?) -> some View {
        Button {
            presentedValuation = valuationRoute(kind: kind)
        } label: {
            HStack(spacing: 8) {
                Text(kind.metricTitle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(value.map { number($0, digits: 2) } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Image(systemName: "chart.xyaxis.line")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(kind.color)
            }
            .font(.footnote)
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看历史变化曲线")
    }

    private func companyMetric(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .font(.footnote)
    }

    private func valuationRoute(kind: CompanyPEKind) -> CompanyValuationHistoryRoute {
        CompanyValuationHistoryRoute(
            symbol: quote?.symbol ?? symbol,
            name: quote?.presentationName ?? symbol,
            initialKind: kind
        )
    }

    private func metric(_ title: String, _ value: Double?, _ color: Color = .primary, compact: Bool = false, suffix: String = "") -> some View {
        textMetric(title, value.map {
            (compact ? compactNumber($0) : number($0, digits: marketDetailPriceDigits(value: $0, price: quote?.price, symbol: symbol))) + suffix
        } ?? "—", color)
    }

    private func textMetric(_ title: String, _ value: String, _ color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityIdentifier("market-detail-metric-\(title)")
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
            LazyVStack(spacing: 0) {
                let items = store.indexConstituents[historicalSymbol]?.items ?? []
                ForEach(items) { item in
                    if item.detailAvailable {
                        Button {
                            onSelectSymbol(item.quote.symbol)
                        } label: {
                            MarketConstituentRow(item: item, store: store)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("打开行情详情")
                    } else {
                        MarketConstituentRow(item: item, store: store)
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
        .padding(14)
        .background(MarketDetailPageStyle.card, in: RoundedRectangle(cornerRadius: MarketDetailPageStyle.cornerRadius))
    }

    private var isCrypto: Bool { symbol.hasPrefix("BINANCE:") }
    private var isCommodity: Bool { quote?.instrumentType == "commodity-future" || symbol.hasSuffix("1!") }

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
    @Environment(\.dismiss) private var dismiss
    let route: CompanyValuationHistoryRoute
    @State private var selectedKind: CompanyPEKind
    @State private var selectedRange: CompanyPETimeRange = .all
    @State private var selectedDate: Date?
    @State private var history: MarketCompanyValuationHistory?
    @State private var staticPoints: [CompanyPEChartPoint] = []
    @State private var ttmPoints: [CompanyPEChartPoint] = []
    @State private var projection = CompanyPEChartProjection(sortedPoints: [])
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(route: CompanyValuationHistoryRoute) {
        self.route = route
        _selectedKind = State(initialValue: route.initialKind)
    }

    private var kindSelection: Binding<CompanyPEKind> {
        Binding(get: { selectedKind }, set: { kind in
            guard selectedKind != kind else { return }
            selectedKind = kind
            selectedDate = nil
            updateProjection()
        })
    }

    private var rangeSelection: Binding<CompanyPETimeRange> {
        Binding(get: { selectedRange }, set: { range in
            guard selectedRange != range else { return }
            selectedRange = range
            selectedDate = nil
            updateProjection()
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    Picker("市盈率口径", selection: kindSelection) {
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
                .padding(.bottom, 68)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .overlay(alignment: .bottomTrailing) {
            DetailSheetControls(closeLabel: "关闭历史估值", onClose: dismiss.callAsFunction)
                .padding(12)
        }
        .task(id: route.symbol) { await load() }
    }

    private var rangePicker: some View {
        Picker("时间范围", selection: rangeSelection) {
            ForEach(CompanyPETimeRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("market-company-valuation-range")
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
            if let latest = projection.points.last {
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
                ContentLoadingPlaceholder(title: "正在读取历史数据", layout: .chart)
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
            } else if projection.points.count < 2 {
                ContentUnavailableView(
                    "历史数据不足",
                    systemImage: "chart.xyaxis.line",
                    description: Text("至少需要两个真实历史点才能绘制变化曲线")
                )
                .frame(maxWidth: .infinity, minHeight: 270)
            } else {
                let activePoint = projection.point(closestTo: selectedDate)
                chartReading(activePoint)

                Chart {
                    ForEach(projection.displayPoints) { point in
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
                .chartYScale(domain: projection.yDomain)
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
                .accessibilityIdentifier("market-company-valuation-chart")

                Divider()

                HStack(spacing: 0) {
                    statistic("中位数", projection.median)
                    statistic("历史分位", projection.percentile, suffix: "%", digits: 0)
                    statistic("较前日", projection.previousChange, suffix: "%", digits: 1, signed: true)
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

    private func chartReading(_ activePoint: CompanyPEChartPoint?) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(activePoint?.id == projection.points.last?.id ? "当前读数" : "历史读数")
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
            extremaBadge("区间最低", projection.minimum, color: .green)
            extremaBadge("区间最高", projection.maximum, color: .red)
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
        if let percentile = projection.percentile, let latest = projection.points.last, let median = projection.median {
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

    private func updateProjection() {
        let points = selectedKind == .staticPE ? staticPoints : ttmPoints
        projection = CompanyPEChartProjection(sortedPoints: points, years: selectedRange.years)
    }

    private var rangeDescription: String {
        guard let first = projection.points.first, let last = projection.points.last else { return "—" }
        return "\(formattedDate(first.date)) – \(formattedDate(last.date)) · \(projection.points.count) 个点"
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
            guard !Task.isCancelled else { return }
            history = loadedHistory
            staticPoints = Self.parsedPoints(loadedHistory.peStatic)
            ttmPoints = Self.parsedPoints(loadedHistory.peTTM)
            updateProjection()
        } catch MarketServiceError.httpStatus(let status) where status == 404 {
            guard !Task.isCancelled else { return }
            history = nil
            staticPoints = []
            ttmPoints = []
            updateProjection()
            errorMessage = "这家公司暂时没有可用的 PE 历史"
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            history = nil
            staticPoints = []
            ttmPoints = []
            updateProjection()
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

private extension MarketMovingAverageSeries {
    var color: Color {
        switch period {
        case 5: .orange
        case 10: .purple
        case 20: MarketStyle.accent
        default: .secondary
        }
    }
}

private struct MarketDetailChart: View {
    @Binding var selectedPeriod: MarketChartPeriod
    let symbol: String
    let store: MarketStore
    let usesStockLayout: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedPointIndex: Int?
    @State private var showsChartData = false
    @State private var showsMinutePeriods = false
    @State private var previousPeriod: MarketChartPeriod?

    private var selectedRange: MarketRange { selectedPeriod.sourceRange }
    private var displayedPeriod: MarketChartPeriod {
        guard usesStockLayout, snapshot(for: selectedPeriod) == nil,
              let previousPeriod,
              snapshot(for: previousPeriod)?.artifacts.displays[previousPeriod]?.presentation.points.isEmpty == false
        else { return selectedPeriod }
        return previousPeriod
    }
    private var sourceSnapshot: MarketChartSnapshot? { snapshot(for: displayedPeriod) }
    private var currentRender: MarketChartDisplayArtifacts? { sourceSnapshot?.artifacts.displays[displayedPeriod] }
    private var chart: MarketChart? { currentRender?.chart }
    private var presentation: MarketChartPresentation? { currentRender?.presentation }

    private func snapshot(for period: MarketChartPeriod) -> MarketChartSnapshot? {
        store.chartSnapshot(symbol: symbol, range: period.sourceRange)
    }
    private var points: [MarketChartPoint] { presentation?.points ?? [] }
    private var values: [Double] { presentation?.values ?? [] }
    private var plotFractions: [CGFloat] {
        presentation?.xFractions ?? []
    }
    private var inspectedPointIndex: Int? {
        guard !points.isEmpty else { return nil }
        return min(max(selectedPointIndex ?? points.count - 1, 0), points.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: usesStockLayout ? 8 : 7) {
            periodPicker
            plotPanel
            chartLegend
            if presentation?.lineSegments.contains(where: \.isMissing) == true {
                Text("虚线表示数据缺口，期间走势未知")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if sourceSnapshot?.isRestored == true, currentRender != nil {
                if store.chartError(symbol: symbol, range: displayedPeriod.sourceRange) != nil {
                    Button {
                        Task { await store.loadChart(symbol: symbol, range: displayedPeriod.sourceRange, force: true) }
                    } label: {
                        Label("上次图表 · 更新失败，重试", systemImage: "arrow.clockwise")
                    }
                    .font(.caption)
                } else {
                    Text("上次图表 · 正在更新")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("market-chart-cached-snapshot")
                }
            }
            if let coverageMessage {
                Text(coverageMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            DisclosureGroup(isExpanded: $showsChartData) {
                VStack(alignment: .leading, spacing: 12) {
                    if let inspectedPointIndex {
                        chartReadout(point: points[inspectedPointIndex], index: inspectedPointIndex)
                    }
                    if displayedPeriod.sourceRange == .day, let quote = store.quote(symbol: symbol), quote.hasActiveExtendedSessionQuote {
                        Text("上方为\(quote.tradingSession.displayLabel)报价；曲线按所示交易日展示")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("图表数据与指标")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 32)
            }
            .tint(.secondary)
            .accessibilityIdentifier("market-chart-data")
        }
        .padding(.horizontal, usesStockLayout ? 0 : 14)
        .padding(.vertical, usesStockLayout ? 14 : 8)
        .task(id: selectedRange) {
            await loadChart(force: false)
            guard selectedPeriod.isIntraday else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
                guard scenePhase == .active else { continue }
                await loadChart(force: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(selectedPeriod.rawValue)行情图表")
    }

    private var plotPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            chartContext
            chartPlot
            if !points.isEmpty {
                timeline
            }
            if let presentation, presentation.hasVolume {
                VolumeBars(
                    points: presentation.points,
                    xFractions: presentation.xFractions,
                    volumeCeiling: presentation.volumeCeiling,
                    fractionGap: presentation.volumeFractionGap
                )
                .frame(height: 26)
                .padding(.trailing, 48)
                .accessibilityLabel("成交量")
            }
        }
        .padding(usesStockLayout ? 11 : 0)
        .background(usesStockLayout ? StockDetailStyle.plot : .clear, in: RoundedRectangle(cornerRadius: 16))
    }

    private var chartContext: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if displayedPeriod != selectedPeriod {
                Text(displayedPeriod.chartTitle)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
                if store.chartError(symbol: symbol, range: selectedRange) != nil {
                    Button("\(selectedPeriod.rawValue)加载失败 · 重试") { Task { await reloadChart() } }
                        .buttonStyle(.plain)
                        .foregroundStyle(MarketDetailPageStyle.accent)
                } else {
                    Text("正在读取\(selectedPeriod.rawValue)")
                }
            } else {
                Text(selectedPointIndex == nil
                     ? chartWindowLabel
                     : inspectedPointIndex.map { pointTime(points[$0].timestamp) } ?? "")
                    .accessibilityIdentifier("market-chart-readout")
                Spacer(minLength: 0)
                if selectedPointIndex != nil, let inspectedPointIndex {
                    Text(formattedPrice(points[inspectedPointIndex].close))
                        .fontWeight(.semibold)
                } else if usesStockLayout, selectedRange != .day, let change = chart?.periodReturn?.percent, change.isFinite {
                    Text(marketFormattedChangePercent(change))
                        .fontWeight(.semibold)
                        .foregroundStyle(marketChangeTint(change))
                        .accessibilityLabel("区间涨跌幅 \(marketFormattedChangePercent(change))")
                }
            }
        }
        .foregroundStyle(.secondary)
        .font(.caption)
        .monospacedDigit()
        .frame(minHeight: 20)
    }

    private var timeline: some View {
        HStack {
            ForEach(Array(timelineLabels.enumerated()), id: \.offset) { index, label in
                Text(label).lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityIdentifier("market-chart-time-\(index)")
                if index < timelineLabels.count - 1 { Spacer() }
            }
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.trailing, 48)
    }

    private func selectPeriod(_ period: MarketChartPeriod) {
        previousPeriod = points.isEmpty ? nil : displayedPeriod
        selectedPointIndex = nil
        selectedPeriod = period
        showsMinutePeriods = false
    }

    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView(.horizontal) { periodControls.fixedSize(horizontal: true, vertical: false) }
                        .scrollIndicators(.hidden)
                        .accessibilityIdentifier("market-chart-periods-scroll")
                } else {
                    periodControls
                }
            }
            .padding(.horizontal, usesStockLayout ? 0 : 3)
            .background(usesStockLayout ? .clear : MarketDetailPageStyle.canvas,
                        in: RoundedRectangle(cornerRadius: 9))
            if showsMinutePeriods {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(MarketChartPeriod.allCases.filter(\.isMinute)) { period in
                            periodButton(period)
                                .frame(minWidth: 44)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("market-chart-minute-periods-scroll")
            }
        }
    }

    private var periodControls: some View {
        HStack(spacing: 2) {
            periodButton(.intraday)
            periodButton(.fiveDays)
            if !usesStockLayout {
                Button { showsMinutePeriods.toggle() } label: { minutePeriodLabel }
                    .accessibilityIdentifier("market-chart-minute-menu")
                    .accessibilityLabel(selectedPeriod.isMinute ? "\(selectedPeriod.rawValue)钟周期" : "分钟周期")
                    .accessibilityAddTraits(selectedPeriod.isMinute ? .isSelected : [])
            }
            periodButton(.daily)
            periodButton(.weekly)
            periodButton(.monthly)
            if usesStockLayout {
                Menu {
                    ForEach(MarketChartPeriod.allCases.filter(\.isMinute)) { period in
                        Button { selectPeriod(period) } label: {
                            if selectedPeriod == period {
                                Label(period.rawValue, systemImage: "checkmark")
                            } else {
                                Text(period.rawValue)
                            }
                        }
                        .accessibilityIdentifier(periodIdentifier(period))
                    }
                } label: {
                    minutePeriodLabel
                }
                .accessibilityIdentifier("market-chart-minute-menu")
                .accessibilityLabel(selectedPeriod.isMinute ? "\(selectedPeriod.rawValue)钟周期" : "分钟周期")
                .accessibilityAddTraits(selectedPeriod.isMinute ? .isSelected : [])
            }
        }
    }

    private var minutePeriodLabel: some View {
        HStack(spacing: 2) {
            Text(selectedPeriod.isMinute ? selectedPeriod.rawValue : "分钟")
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
        }
        .font(.footnote.weight(selectedPeriod.isMinute ? .semibold : .medium))
        .foregroundStyle(periodSelectionTint(isSelected: selectedPeriod.isMinute))
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(periodSelectionBackground(isSelected: selectedPeriod.isMinute))
    }

    private func periodButton(_ period: MarketChartPeriod) -> some View {
        Button { selectPeriod(period) } label: {
            Text(period.rawValue)
                .font(.footnote.weight(selectedPeriod == period ? .semibold : .medium))
                .foregroundStyle(periodSelectionTint(isSelected: selectedPeriod == period))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(periodSelectionBackground(isSelected: selectedPeriod == period))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(periodIdentifier(period))
        .accessibilityLabel("\(period.rawValue)行情")
        .accessibilityAddTraits(selectedPeriod == period ? .isSelected : [])
    }

    private func periodSelectionTint(isSelected: Bool) -> Color {
        guard isSelected else { return .secondary }
        return usesStockLayout ? .white : MarketDetailPageStyle.accent
    }

    private func periodSelectionBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? (usesStockLayout ? StockDetailStyle.ink : MarketDetailPageStyle.accent.opacity(0.11)) : .clear)
            .padding(.vertical, usesStockLayout ? 6 : 4)
    }

    private func periodIdentifier(_ period: MarketChartPeriod) -> String {
        "market-chart-period-\(String(describing: period))"
    }

    private var chartPlot: some View {
        ZStack {
            if !points.isEmpty || !usesStockLayout {
                ChartGrid(low: presentation?.low, high: presentation?.high, digits: presentation?.axisDigits ?? 2)
            }
            Group {
                if values.isEmpty {
                    if isLoadingChart {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("正在加载\(selectedPeriod.rawValue)走势图")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    } else if let error = displayedChartError {
                        VStack(spacing: 8) {
                            Text(error).font(.caption).foregroundStyle(.secondary)
                            Button("重新加载") { Task { await reloadChart() } }
                                .font(.footnote.weight(.semibold))
                                .frame(minWidth: 88, minHeight: 44)
                        }
                    } else {
                        Text(chartStatusMessage).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    MarketSessionLineChart(
                        points: points, xFractions: plotFractions,
                        low: presentation?.low, high: presentation?.high,
                        regularColor: chartColor, segments: presentation?.lineSegments ?? []
                    )
                    if let sessionBreak = presentation?.sessionBreak {
                        MarketSessionBreakMarker(sessionBreak: sessionBreak, points: points, xFractions: plotFractions)
                    }
                }
                if !values.isEmpty, (!usesStockLayout || displayedPeriod.sourceRange == .day),
                   let previousClose = chart?.quote.previousClose {
                    ChartReferenceLine(value: previousClose, low: presentation?.low, high: presentation?.high)
                }
                if selectedPointIndex != nil, let inspectedPointIndex {
                    let point = points[inspectedPointIndex]
                    MarketChartPriceOverlay(
                        value: point.close,
                        xFraction: plotFractions.indices.contains(inspectedPointIndex) ? plotFractions[inspectedPointIndex] : 1,
                        low: presentation?.low, high: presentation?.high,
                        digits: marketChartReadoutDigits(point.close, symbol: symbol, axisDigits: presentation?.axisDigits),
                        tint: chartTint, showsCrosshair: true
                    )
                }
            }
            .padding(.trailing, 48)
        }
        .frame(height: usesStockLayout ? 218 : 212)
        .overlay {
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.25, maximumDistance: 12)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { phase in
                                guard case let .second(true, value?) = phase else { return }
                                let width = max(proxy.size.width - 48, 0)
                                let inset = marketLinePlotX(fraction: 0, width: width)
                                let fraction = (value.location.x - inset) / max(width - inset * 2, 1)
                                let index = marketNearestChartIndex(fraction: fraction, fractions: plotFractions)
                                if index != selectedPointIndex { selectedPointIndex = index }
                            }
                            .onEnded { _ in selectedPointIndex = nil }
                    )
            }
        }
        .accessibilityElement(children: values.isEmpty ? .contain : .ignore)
        .accessibilityLabel("行情图表")
        .accessibilityValue(chartAccessibilityValue)
        .accessibilityIdentifier("market-detail-chart")
    }

    private func chartReadout(point: MarketChartPoint, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pointTime(point.timestamp))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                readoutValue("开", point.open)
                readoutValue("高", point.high)
                readoutValue("低", point.low)
                readoutValue("收", point.close)
            }
            if let movingAverages = currentRender?.movingAverages, !movingAverages.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    ForEach(movingAverages, id: \.period) { series in
                        let value = series.values.indices.contains(index) ? series.values[index] : nil
                        Text("MA\(series.period)  \(value.map(formattedPrice) ?? "—")")
                            .foregroundStyle(series.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Text("该时段成交量 \(point.volume.map(compactNumber) ?? "—")")
                .foregroundStyle(.secondary)
            if presentation?.extendedSessionLabel != nil {
                HStack(spacing: 12) {
                    legendDot("常规", color: chartColor)
                    legendDot("盘前/盘后/夜盘", color: MarketStyle.purple)
                }
            }
        }
        .font(.footnote)
        .monospacedDigit()
    }

    private func readoutValue(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(formattedPrice(value))
        }
    }

    private func formattedPrice(_ value: Double) -> String {
        number(value, digits: marketChartReadoutDigits(value, symbol: symbol, axisDigits: presentation?.axisDigits))
    }

    private func legendDot(_ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private var timelineLabels: [String] {
        guard let first = points.first, let last = points.last else { return ["—"] }
        if points.count == 1 { return [pointTime(first.timestamp)] }
        if points.count == 2 { return [first, last].map { pointTime($0.timestamp) } }
        return [first, points[points.count / 2], last].map { pointTime($0.timestamp) }
    }

    private func pointTime(_ timestamp: Int64) -> String {
        MarketViewDateFormatters.chart(period: displayedPeriod, timezone: chart?.timezone)
            .string(from: Date(timeIntervalSince1970: Double(timestamp) / 1_000))
    }

    private var chartWindowLabel: String {
        guard let chart else { return "交易所时间" }
        guard let first = points.first, let last = points.last else {
            return "交易所时间"
        }
        if usesStockLayout, displayedPeriod.sourceRange == .week {
            let formatter = MarketViewDateFormatters.chart(period: .daily, timezone: chart.timezone)
            let start = formatter.string(from: Date(timeIntervalSince1970: Double(first.timestamp) / 1_000))
            let end = formatter.string(from: Date(timeIntervalSince1970: Double(last.timestamp) / 1_000))
            return "\(start) – \(end) · 交易所时间"
        }
        if displayedPeriod.isIntraday {
            return "\(chart.tradingDate) · 交易所时间"
        }
        let formatter = MarketViewDateFormatters.chart(period: .weekly, timezone: chart.timezone)
        let startTimestamp = chart.periodReturn?.startTimestamp ?? first.timestamp
        let start = formatter.string(from: Date(timeIntervalSince1970: Double(startTimestamp) / 1_000))
        let dates = "\(start) – \(chart.tradingDate)"
        switch displayedPeriod {
        case .weekly where !usesStockLayout: return "近5年 · \(dates)"
        case .monthly where !usesStockLayout: return "全部可用历史 · \(dates)"
        default: return dates
        }
    }

    private var chartDisplayTitle: String {
        displayedPeriod.chartTitle
    }

    private var chartAccessibilityValue: String {
        let summary = "\(chartDisplayTitle)，\(points.count)个数据点"
        guard let first = points.first, let last = points.last else { return summary }
        let formatter = MarketViewDateFormatters.chartCoverage(timezone: chart?.timezone)
        let start = formatter.string(from: Date(timeIntervalSince1970: Double(first.timestamp) / 1_000))
        let end = formatter.string(from: Date(timeIntervalSince1970: Double(last.timestamp) / 1_000))
        let drawnCount = currentRender?.drawnPointCount ?? 0
        return "\(summary)，起点\(start)，终点\(end)，绘制\(drawnCount)个数据点"
    }

    private var chartLegend: some View {
        HStack(spacing: 11) {
            if let label = presentation?.extendedSessionLabel {
                HStack(spacing: 4) {
                    Capsule().fill(chartColor).frame(width: 10, height: 2)
                    Text("常规盘")
                }
                HStack(spacing: 4) {
                    Capsule().fill(MarketDetailPageStyle.extended).frame(width: 10, height: 2)
                    Text(label)
                }
            }
            if presentation?.hasVolume == true {
                Text("成交量")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    private var chartColor: Color {
        if displayedPeriod.sourceRange != .day, let periodReturn = chart?.periodReturn?.percent {
            return periodReturn >= 0 ? MarketStyle.gain : MarketStyle.loss
        }
        let change = chart?.quote.changePercent ?? {
            guard let first = values.first, let last = values.last else { return 0 }
            return last - first
        }()
        return change >= 0 ? MarketStyle.gain : MarketStyle.loss
    }
    private var chartTint: Color {
        guard let change = chart?.quote.changePercent else { return chartColor }
        if change > 0 { return MarketStyle.gain }
        if change < 0 { return MarketStyle.loss }
        return .secondary
    }
    private var isLoadingChart: Bool {
        store.isLoadingChart(symbol: symbol, range: selectedRange)
    }
    private var displayedChartError: String? {
        if sourceSnapshot != nil, currentRender == nil { return "当前行情数据无法生成\(selectedPeriod.rawValue)图表" }
        return store.chartError(symbol: symbol, range: selectedRange)
    }
    private func reloadChart() async {
        await loadChart(force: true)
    }

    private func loadChart(force: Bool) async {
        await store.loadChart(symbol: symbol, range: selectedRange, force: force)
    }
    private var coverageMessage: String? {
        guard let quality = chart?.quality else { return nil }
        switch quality.status {
        case .complete:
            if displayedPeriod == .daily, chart?.tradingDate != sourceSnapshot?.chart.tradingDate {
                return "最新交易日的日线待确认"
            }
            guard !quality.isFinal || points.last?.state == "provisional" else { return nil }
            return displayedPeriod.isIntraday ? "当前分钟更新中" : "当前周期尚未收盘"
        case .repairing:
            return "数据补齐中 · 已有 \(quality.actual)/\(quality.expected) 个真实数据点"
        case .partial:
            let missing = max(quality.expected - quality.actual, 0)
            return missing > 0 ? "数据不完整 · 缺少 \(missing) 个数据点" : "部分行情尚待确认"
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
    let xFractions: [CGFloat]

    var body: some View {
        GeometryReader { proxy in
            let startIndex = points.firstIndex { $0.timestamp == sessionBreak.previousTimestamp } ?? 0
            let endIndex = points.firstIndex { $0.timestamp == sessionBreak.currentTimestamp } ?? startIndex
            let start = xFractions.indices.contains(startIndex) ? xFractions[startIndex] : 0
            let end = xFractions.indices.contains(endIndex) ? xFractions[endIndex] : start
            let x = marketLinePlotX(fraction: (start + end) / 2, width: proxy.size.width)
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

private struct ChartReferenceLine: View {
    let value: Double
    let low: Double?
    let high: Double?

    var body: some View {
        GeometryReader { proxy in
            if let low, let high, high > low, value >= low, value <= high {
                let y = proxy.size.height * (0.06 + CGFloat((high - value) / (high - low)) * 0.88)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
                .stroke(Color.secondary.opacity(0.30), style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ChartGrid: View {
    let low: Double?
    let high: Double?
    let digits: Int

    var body: some View {
        GeometryReader { proxy in
            ForEach(0..<5, id: \.self) { index in
                let y = proxy.size.height * (0.06 + CGFloat(index) / 4 * 0.88)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: max(proxy.size.width - 48, 0), y: y))
                }
                .stroke(Color.secondary.opacity(0.10), lineWidth: 0.5)
                Text(axisLabel(index))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 44, alignment: .trailing)
                    .position(x: proxy.size.width - 22, y: y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func axisLabel(_ index: Int) -> String {
        guard let low, let high, high > low else { return "—" }
        return number(high - (high - low) * Double(index) / 4, digits: digits)
    }
}

private struct MarketSessionLineChart: View {
    let points: [MarketChartPoint]
    let xFractions: [CGFloat]
    let low: Double?
    let high: Double?
    let regularColor: Color
    let segments: [MarketChartLineSegment]

    var body: some View {
        Canvas { context, size in
            guard !points.isEmpty,
                  xFractions.count == points.count,
                  let low,
                  let high else { return }
            let span = max(high - low, 0.000_001)
            func canvasPoint(_ point: MarketChartPoint, at index: Int) -> CGPoint {
                CGPoint(
                    x: marketLinePlotX(fraction: xFractions[index], width: size.width),
                    y: size.height * (0.06 + CGFloat((high - point.close) / span) * 0.88)
                )
            }

            for segment in segments {
                guard let firstIndex = segment.indices.first,
                      let lastIndex = segment.indices.last else { continue }
                let firstPoint = points[firstIndex]
                let color = segment.isMissing ? Color.secondary : segment.isRegular ? regularColor : MarketDetailPageStyle.extended
                if segment.indices.count == 1 {
                    let position = canvasPoint(firstPoint, at: firstIndex)
                    let dot = CGRect(x: position.x - 2, y: position.y - 2, width: 4, height: 4)
                    context.fill(Path(ellipseIn: dot), with: .color(color))
                    continue
                }
                var path = Path()
                path.move(to: canvasPoint(points[firstIndex], at: firstIndex))
                segment.indices.dropFirst().forEach { index in
                    path.addLine(to: canvasPoint(points[index], at: index))
                }
                if segment.isRegular && !segment.isMissing {
                    var fill = path
                    fill.addLine(to: CGPoint(x: canvasPoint(points[lastIndex], at: lastIndex).x, y: size.height))
                    fill.addLine(to: CGPoint(x: canvasPoint(firstPoint, at: firstIndex).x, y: size.height))
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
                    with: .color(color),
                    style: StrokeStyle(
                        lineWidth: segment.isMissing ? 1.2 : segment.isRegular ? 1.7 : 2,
                        lineCap: .round, lineJoin: .round,
                        dash: segment.isMissing ? [4, 3] : []
                    )
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MarketChartPriceOverlay: View {
    let value: Double
    let xFraction: CGFloat
    let low: Double?
    let high: Double?
    let digits: Int
    let tint: Color
    let showsCrosshair: Bool

    var body: some View {
        GeometryReader { proxy in
            if let low, let high, high > low {
                let x = marketLinePlotX(fraction: xFraction, width: proxy.size.width)
                let normalizedY = 0.06 + CGFloat((high - value) / (high - low)) * 0.88
                let y = proxy.size.height * min(max(normalizedY, 0.02), 0.98)
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        if showsCrosshair {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                        }
                    }
                    .stroke(tint.opacity(showsCrosshair ? 0.55 : 0.28), style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))

                    if showsCrosshair {
                        Circle()
                            .fill(MarketStyle.surface)
                            .overlay { Circle().stroke(tint, lineWidth: 1.5) }
                            .frame(width: 7, height: 7)
                            .position(x: x, y: y)
                    }

                    Text(number(value, digits: digits))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(tint, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .fixedSize()
                        .position(x: max(proxy.size.width - 24, 24), y: min(max(y, 10), proxy.size.height - 10))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct VolumeBars: View {
    let points: [MarketChartPoint]
    let xFractions: [CGFloat]
    let volumeCeiling: Double
    let fractionGap: CGFloat

    var body: some View {
        Canvas { context, size in
            guard !points.isEmpty, xFractions.count == points.count else { return }
            let cellWidth = size.width * fractionGap
            let barWidth = min(cellWidth, min(max(cellWidth * 0.72, 1), 8))

            for (index, point) in points.enumerated() {
                guard let volume = point.volume, volume > 0 else { continue }
                let height = max(2, size.height * CGFloat(min(volume, volumeCeiling) / volumeCeiling))
                let x = marketVolumeBarX(fraction: xFractions[index], width: size.width, barWidth: barWidth)
                let rect = CGRect(x: x - barWidth / 2, y: size.height - height, width: barWidth, height: height)
                context.fill(Path(rect), with: .color(Color.secondary.opacity(0.35)))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MarketSummary: View {
    let quote: MarketQuote?
    let isIndex: Bool
    let quoteUnavailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(quote?.hasActiveExtendedSessionQuote == true ? "常规盘表现" : "行情概况")
                .font(.headline)
            Text(summary)
                .font(.subheadline)
                .lineSpacing(4)
                .foregroundStyle(.primary.opacity(0.88))
            Text("仅供行情参考，不构成投资建议。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(MarketDetailPageStyle.card, in: RoundedRectangle(cornerRadius: MarketDetailPageStyle.cornerRadius))
    }

    private var summary: String {
        guard let quote else { return quoteUnavailable ? "当前报价暂缺。" : "正在获取最新行情。" }
        let subject = quote.hasActiveExtendedSessionQuote ? "常规收盘" : isIndex ? "指数" : "价格"
        guard let change = quote.changeValue else { return "昨收暂缺，无法计算涨跌额。" }
        let comparison = change > 0 ? "高于昨收" : change < 0 ? "低于昨收" : "与昨收持平"
        guard let high = quote.high, let low = quote.low, high > low else {
            return "\(subject)\(comparison)。"
        }
        let position = (quote.price - low) / (high - low)
        let positionText: String
        switch position {
        case ..<0.35: positionText = "区间下部"
        case 0.65...: positionText = "区间上部"
        default: positionText = "区间中部"
        }
        let digits = marketDetailPriceDigits(value: low, price: quote.price, symbol: quote.symbol)
        return "\(subject)\(comparison)，日内运行于 \(number(low, digits: digits))–\(number(high, digits: digits))，目前位于\(positionText)。"
    }


}

private struct MarketConstituentRow: View {
    let item: MarketIndexConstituent
    let store: MarketStore
    private var quote: MarketQuote { item.quote }
    private var logoPath: String? { item.logoPath ?? store.companyLogoPaths[quote.symbol] }
    private var trend: [Double] {
        let values = store.trendValues(for: quote)
        return values.count > 1 ? values : store.listTrendValues(for: quote)
    }

    var body: some View {
        HStack(spacing: 10) {
            CompanyLogo(quote: quote, path: logoPath)
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
                Text(number(quote.price, digits: marketPriceDigits(quote.price, symbol: quote.symbol))).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                Text(quote.formattedPercent).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(quoteTint(quote))
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 64)
        .task(id: quote.symbol) {
            if item.detailAvailable, trend.count < 2 {
                await store.loadChart(symbol: quote.symbol, range: .day)
            }
        }
        .task(id: quote.symbol) {
            if item.detailAvailable, logoPath == nil {
                await store.loadCompanyLogo(symbol: quote.symbol, name: quote.name)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(quote.presentationName)，\(quote.symbol)，市值 \(quote.marketCap.map(compactNumber) ?? "未知")，最新价 \(number(quote.price, digits: marketPriceDigits(quote.price, symbol: quote.symbol)))，\(quote.formattedPercent)，点按查看详情")
    }
}

struct MarketInstrumentLogo: View {
    let quote: MarketQuote
    let path: String?
    var size: CGFloat = 40

    @ViewBuilder
    var body: some View {
        if quote.symbol == "^VIX" {
            VIXLogo(size: size)
        } else if let commodity = CommodityLogoKind(symbol: quote.symbol) {
            CommodityLogo(kind: commodity, size: size)
        } else {
            CompanyLogo(quote: quote, path: path, size: size)
        }
    }
}

private struct VIXLogo: View {
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.98, green: 0.42, blue: 0.24), Color(red: 0.72, green: 0.12, blue: 0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("VIX")
                .font(.system(size: size * 0.28, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 0.75)
        }
        .accessibilityLabel("VIX 恐慌指数标识")
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

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var showsFill = true
    var minimumRelativeRange = 0.0
    var showsLatestPoint = false
    var body: some View {
        GeometryReader { proxy in
            let points = marketSparklinePoints(values, size: proxy.size, minimumRelativeRange: minimumRelativeRange)
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
                    if showsLatestPoint, let latest = points.last {
                        Circle()
                            .fill(color)
                            .frame(width: 5, height: 5)
                            .position(
                                x: min(max(latest.x, 2.5), proxy.size.width - 2.5),
                                y: min(max(latest.y, 2.5), proxy.size.height - 2.5)
                            )
                    }
                }
            } else {
                Capsule().fill(Color.secondary.opacity(0.12)).frame(height: 1)
            }
        }
    }
}

private struct MarketPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.scaleEffect(configuration.isPressed ? 0.985 : 1).opacity(configuration.isPressed ? 0.88 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed) }
}

private struct CoreDescriptor {
    let symbol: String
    var isIndex: Bool {
        switch symbol {
        case "^GSPC", "^NDX", "^DJI", "SPY", "QQQ", "DIA", "000001.SS", "000016.SS", "000300.SS", "399006.SZ",
             "000688.SS", "000905.SS", "000852.SS", "932000.SS", "THS:883418", "^HSTECH",
             "^HSI", "^N225", "^TOPX", "^KS11", "^STOXX50E", "^GDAXI", "^FTSE", "^FCHI":
            true
        default:
            false
        }
    }
    var name: String { switch symbol { case "^GSPC": "标普500"; case "^NDX": "纳斯达克100"; case "^DJI": "道琼斯工业指数"; case "SPY": "标普500实时代理（SPY）"; case "QQQ": "纳斯达克100实时代理（QQQ）"; case "DIA": "道琼斯实时代理（DIA）"; case "000001.SS": "上证指数"; case "000016.SS": "上证50"; case "000300.SS": "沪深300"; case "399006.SZ": "创业板指"; case "000688.SS": "科创50"; case "000905.SS": "中证500"; case "000852.SS": "中证1000"; case "932000.SS": "中证2000"; case "THS:883418": "微盘股"; case "^HSTECH": "恒生科技指数"; case "^HSI": "恒生指数"; case "^N225": "日经225"; case "^TOPX": "东证指数"; case "^KS11": "韩国KOSPI"; case "^STOXX50E": "欧洲STOXX 50"; case "^GDAXI": "德国DAX"; case "^FTSE": "英国富时100"; case "^FCHI": "法国CAC 40"; case "GC1!": "COMEX 黄金"; case "CL1!": "WTI 原油"; case "HG1!": "COMEX 铜"; case "SI1!": "COMEX 白银"; case "NG1!": "NYMEX 天然气"; case "ZC1!": "CBOT 玉米"; default: symbol } }
    var code: String { switch symbol { case "^GSPC": "SPX"; case "^NDX": "NDX"; case "^DJI": "DJI"; case "SPY", "QQQ", "DIA": symbol; case "000001.SS": "000001.SH"; case "000300.SS": "000300.SH"; case "000688.SS": "000688.SH"; case "^HSTECH": "HSTECH"; case "^HSI": "HSI"; case "^N225": "N225"; case "^TOPX": "TOPIX"; case "^KS11": "KOSPI"; case "^STOXX50E": "SX5E"; case "^GDAXI": "DAX"; case "^FTSE": "FTSE"; case "^FCHI": "CAC40"; default: symbol } }
}


struct MarketSparklineBounds: Equatable {
    let lower: Double
    let upper: Double
}

func marketSparklineBounds(_ values: [Double], minimumRelativeRange: Double) -> MarketSparklineBounds {
    guard let minimum = values.min(), let maximum = values.max() else {
        return MarketSparklineBounds(lower: 0, upper: 1)
    }
    let midpoint = (minimum + maximum) / 2
    let reference = max(abs(minimum), abs(maximum))
    // Scale padding with the instrument, so sub-cent movements remain visible.
    // A flat series still needs a finite domain centred on its real price.
    let flatRange = reference > 0 ? reference * 0.001 : 0.001
    let displayedRange = max(maximum - minimum, reference * max(minimumRelativeRange, 0))
    let range = displayedRange > 0 ? displayedRange : flatRange
    return MarketSparklineBounds(lower: midpoint - range / 2, upper: midpoint + range / 2)
}

func marketLinePlotX(fraction: CGFloat, width: CGFloat) -> CGFloat {
    let inset = min(3, max(width, 0) / 2)
    return inset + max(width - inset * 2, 0) * min(max(fraction, 0), 1)
}

func marketSparklinePoints(_ values: [Double], size: CGSize, minimumRelativeRange: Double = 0) -> [CGPoint] {
    let bounds = marketSparklineBounds(values, minimumRelativeRange: minimumRelativeRange)
    let range = bounds.upper - bounds.lower
    let verticalInset = min(3, max(size.height, 0) / 2)
    let plotHeight = max(size.height - verticalInset * 2, 0)
    return values.enumerated().map {
        CGPoint(
            x: marketLinePlotX(fraction: values.count == 1 ? 0.5 : CGFloat($0.offset) / CGFloat(values.count - 1), width: size.width),
            y: verticalInset + plotHeight * (1 - CGFloat(($0.element - bounds.lower) / range))
        )
    }
}

private func quoteTint(_ quote: MarketQuote?) -> Color {
    marketChangeTint(quote?.percentValue)
}
private func marketDisplayTint(_ quote: MarketQuote?) -> Color {
    marketChangeTint(quote?.marketDisplayPercentValue)
}
private func marketChangeTint(_ change: Double?) -> Color {
    guard let change else { return .secondary }
    return change > 0 ? MarketStyle.gain : change < 0 ? MarketStyle.loss : .secondary
}
func marketQuotePriceText(_ quote: MarketQuote) -> String {
    let price = quote.marketDisplayPrice
    let suffix = quote.currency == "%" ? "%" : ""
    return number(price, digits: marketPriceDigits(price, symbol: quote.symbol)) + suffix
}
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
func marketPriceDigits(_ price: Double, symbol: String) -> Int {
    switch symbol {
    case "USDCNY": return 4
    case "USDJPY", "NG1!", "HG1!", "SI1!", "LE1!", "GF1!", "HE1!", "^TNX", "JP10Y", "KR10Y": return 3
    default:
        guard symbol.hasPrefix("BINANCE:") else { return 2 }
        let magnitude = abs(price)
        if magnitude > 0 && magnitude < 1 {
            return min(10, max(5, Int(ceil(-log10(magnitude))) + 3))
        }
        return magnitude < 100 ? 3 : 2
    }
}
func marketChartReadoutDigits(_ price: Double, symbol: String, axisDigits: Int?) -> Int {
    max(axisDigits ?? 2, marketPriceDigits(price, symbol: symbol))
}
func marketDetailPriceDigits(value: Double, price: Double?, symbol: String) -> Int {
    let priceDigits = marketPriceDigits(abs(price ?? value), symbol: symbol)
    guard value != 0 else { return priceDigits }
    // Preserve a nonzero price/change even when it is below the usual precision.
    let nonzeroDigits = max(0, Int(ceil(-log10(abs(value)))))
    return min(max(priceDigits, nonzeroDigits), 10)
}
private enum MarketViewDateFormatters {
    private static var chartCache: [String: DateFormatter] = [:]

    static func chart(period: MarketChartPeriod, timezone: String?) -> DateFormatter {
        chart(format: period.dateFormat, timezone: timezone)
    }

    static func chartCoverage(timezone: String?) -> DateFormatter {
        chart(format: "yyyy-MM-dd HH:mm", timezone: timezone)
    }

    private static func chart(format: String, timezone: String?) -> DateFormatter {
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

#Preview {
    MarketView(
        store: MarketStore(),
        investorMoodStore: InvestorMoodStore(),
        researchStore: InstitutionResearchStore()
    )
}

func marketYieldChangeText(price: Double, previousClose: Double?) -> String {
    guard let previousClose, price.isFinite, previousClose.isFinite else { return "—" }
    return "\(signed((price - previousClose) * 100, digits: 1)) bp"
}

func marketCardTitle(symbol: String, name: String) -> String {
    switch symbol {
    case "SPY": "标普500 ETF"
    case "QQQ": "纳斯达克100 ETF"
    case "DIA": "道琼斯 ETF"
    default: name
    }
}
