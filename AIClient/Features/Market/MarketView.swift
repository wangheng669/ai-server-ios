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

private struct MarketDetailRoute: Identifiable, Equatable {
    let symbol: String
    var id: String { symbol }
}

// StateObject defers creation until SwiftUI installs the owning view. In particular,
// opening a sheet must not decode the holdings cache again through a view initializer.
@MainActor
private final class MarketDetailStores: ObservableObject {
    lazy var globalRanking = GlobalRankingStore()
    lazy var holdings = FamousHoldingsStore()
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
    @State private var showsInstitutionResearch = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--institution-research-preview")
        #else
        false
        #endif
    }()
    @State private var showsIndustries = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--industries-preview")
        #else
        false
        #endif
    }()
    @State private var showsInvestors = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--holdings-preview") ||
            ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--holdings-detail-preview=") })
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
    @State private var showsMacro = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--market-macro-sheet-preview") ||
            ProcessInfo.processInfo.arguments.contains("--china-macro-preview")
        #else
        false
        #endif
    }()
    @State private var selectedMarketQuotesRegion: MarketRegion? = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--market-core-stocks-preview") ? .unitedStates : nil
        #else
        nil
        #endif
    }()
    @State private var showsChinaMarketStructure = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--market-structure-sheet-preview") ||
            ProcessInfo.processInfo.arguments.contains("--market-structure-preview")
        #else
        false
        #endif
    }()
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
        rootTabIsActive && selectedDetail == nil && selectedMarketQuotesRegion == nil
            && !showsRetailInvestors && !showsInstitutionResearch && !showsIndustries
            && !showsInvestors && !showsGlobalRanking && !showsMacro && !showsChinaMarketStructure
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
            onOpenMacro: {
                showsMacro = true
            },
            onOpenGlobalRanking: {
                rankingCategory = .globalAssets
                showsGlobalRanking = true
            },
            onOpenInvestors: {
                showsInvestors = true
            },
            onOpenInstitutionResearch: {
                showsInstitutionResearch = true
            },
            onOpenIndustries: {
                showsIndustries = true
            },
            onOpenMarketQuotes: { region in
                selectedMarketQuotesRegion = region
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
            RetailInvestorView(store: investorMoodStore)
                .appPresentationDetents([.large])
                .appPresentationCornerRadius(28)
                .appPresentationBackground(InvestmentDesign.surface)
                .appPresentationScrollsWithoutExpanding()
        }
        .appSheet(isPresented: $showsInvestors) {
            FamousHoldingsView(store: holdingsStore)
                .overlay(alignment: .bottomTrailing) {
                    DetailSheetControls(closeLabel: "关闭名人持仓", onClose: { showsInvestors = false })
                        .padding(12)
                }
            .appPresentationDetents([.large])
            .appPresentationCornerRadius(24)
            .appPresentationBackground(Color(uiColor: .systemBackground))
            .appPresentationScrollsWithoutExpanding()
        }
        .appSheet(isPresented: $showsInstitutionResearch) {
            NavigationStack {
                InstitutionResearchView(store: institutionResearchStore)
            }
            .appPresentationDetents([.large])
            .appPresentationCornerRadius(24)
            .appPresentationBackground(Color(uiColor: .systemBackground))
            .appPresentationScrollsWithoutExpanding()
        }
        .appSheet(isPresented: $showsIndustries) {
            IndustryPanoramaView(onClose: { showsIndustries = false })
            .appPresentationDetents([.large])
            .appPresentationCornerRadius(28)
            .appPresentationBackground(InvestmentDesign.canvas)
            .appPresentationScrollsWithoutExpanding()
        }
        .appSheet(isPresented: $showsGlobalRanking) {
            CountryGDPRankingView(store: globalRankingStore, initialCategory: rankingCategory)
                .overlay(alignment: .bottomTrailing) {
                    DetailSheetControls(closeLabel: "关闭全球排行", onClose: { showsGlobalRanking = false })
                        .padding(12)
                }
            .appPresentationDetents([.large])
            .appPresentationCornerRadius(28)
            .appPresentationBackground(InvestmentDesign.surface)
            .appPresentationScrollsWithoutExpanding()
        }
        .appSheet(isPresented: $showsMacro) {
            ChinaMacroView()
                .overlay(alignment: .bottomTrailing) {
                    DetailSheetControls(closeLabel: "关闭中国宏观", onClose: { showsMacro = false })
                        .padding(12)
                }
            .appPresentationDetents([.large])
            .appPresentationCornerRadius(24)
            .appPresentationBackground(Color(uiColor: .systemBackground))
        }
        .appSheet(item: $selectedMarketQuotesRegion) { region in
            MarketQuotesSheet(region: region, store: store)
                .appPresentationDetents([.large])
                .appPresentationCornerRadius(28)
                .appPresentationBackground(MarketStyle.surface)
                .appPresentationScrollsWithoutExpanding()
        }
        .appSheet(isPresented: $showsChinaMarketStructure) {
            ChinaMarketStructureSheet(structure: store.dashboard?.marketStructure)
                .appPresentationDetents([.large])
                .appPresentationCornerRadius(28)
                .appPresentationBackground(MarketStyle.surface)
                .appPresentationScrollsWithoutExpanding()
        }
        .appSheet(item: $selectedDetail) { route in
            MarketIndexDetailView(
                symbol: route.symbol,
                store: store,
                onSelectSymbol: {
                    selectedDetail = MarketDetailRoute(symbol: $0)
                }
            )
            .id(route.symbol)
            .appPresentationDetents([.large])
            .appPresentationCornerRadius(28)
            .appPresentationBackground(MarketStyle.surface)
            .appPresentationScrollsWithoutExpanding()
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await store.runUpdates()
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

private enum MarketTerminalPalette {
    static let header = InvestmentDesign.surface
    static let headerDivider = InvestmentDesign.divider
}

enum MarketRegion: String, CaseIterable, Identifiable {
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
    let onOpenMarketQuotes: () -> Void
    let onOpenMarketDetail: (String) -> Void
    let onOpenVIXHistory: () -> Void
    let onOpenChinaMarketStructure: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedRange: MarketRange = .day
    @State private var showsDataNotes = false

    private let chartRanges: [MarketRange] = [.day, .week, .month, .quarter, .year, .fiveYears, .maximum]

    private var quote: MarketQuote? { store.quote(symbol: region.primarySymbol) }
    private var displayedQuote: MarketQuote? { quote }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 7) {
                Button(action: onOpenMarketQuotes) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 7) {
                            Text(heroTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer(minLength: 6)
                            Circle()
                                .fill(sessionTint)
                                .frame(width: 6, height: 6)
                            Text(sessionLabel)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        heroPrice
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(MarketPressStyle())
                .accessibilityLabel(heroAccessibilityLabel)
                .accessibilityHint("打开指数与核心股票")

                HStack(spacing: 6) {
                    ForEach(chartRanges) { range in
                        Button {
                            selectedRange = range
                        } label: {
                            VStack(spacing: 4) {
                                Text(range == .day ? "日内" : range.rawValue)
                                    .font(.system(size: 11, weight: selectedRange == range ? .semibold : .medium))
                                    .foregroundStyle(selectedRange == range ? MarketStyle.accent : .secondary)
                                Capsule()
                                    .fill(selectedRange == range ? MarketStyle.accent : .clear)
                                    .frame(width: 18, height: 2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedRange == range ? .isSelected : [])
                    }
                }
                .padding(.top, 2)

                Button {
                    onOpenMarketDetail(region.primarySymbol)
                } label: {
                    heroChart
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? 190 : 140)
                        .allowsHitTesting(false)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(heroTitle)走势图")
                .accessibilityHint("打开行情详情面板")
                .accessibilityIdentifier("market.heroChart")

                heroStatistics
                DisclosureGroup(isExpanded: $showsDataNotes) {
                    VStack(alignment: .leading, spacing: 4) {
                    Text(quote.map { "\($0.currency ?? "") · \($0.marketAsOfLabel)" } ?? "等待行情")
                    Text("来源：\(heroSourceLabel)")
                    if quote?.hasActiveExtendedSessionQuote == true {
                        Text("涨跌相对常规收盘；下方开高低为常规交易时段")
                    }
                    if let chart = store.chart(symbol: chartSymbol, range: selectedRange) {
                        Text("图表交易日：\(chart.tradingDate) · \(chart.timezone == "America/New_York" ? "纽约时间" : chart.timezone)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 5)
                } label: {
                    HStack(spacing: 4) {
                        Text(quote?.marketAsOfLabel ?? "等待行情")
                        Spacer(minLength: 0)
                        Text("数据口径").foregroundStyle(MarketStyle.accent)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                .tint(.secondary)
            }
            .padding(.vertical, 8)
            .background(MarketStyle.surface)

            Divider().opacity(0.45)
            temperatureMetrics
            if region == .unitedStates, showsDataNotes {
                Text("VIX：\(store.quote(symbol: "^VIX")?.freshnessLabel ?? "等待更新")\n美债：\(store.quote(symbol: "^TNX")?.freshnessLabel ?? "等待更新")\n情绪：\(store.dashboard?.sentiment?.source ?? "—") · \(store.dashboard?.sentiment?.updatedAt.map { String($0.prefix(10)) } ?? "日期未知")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Divider().opacity(0.45)
        }
        .padding(.horizontal, MarketStyle.pageInset)
        .padding(.top, 8)
        .onChange(of: region) { _, _ in selectedRange = .day }
        .task(id: chartSymbol) {
            async let day: Void = store.loadChart(symbol: chartSymbol, range: .day)
            async let week: Void = store.loadChart(symbol: chartSymbol, range: .week)
            async let month: Void = store.loadChart(symbol: chartSymbol, range: .month)
            async let year: Void = store.loadChart(symbol: chartSymbol, range: .year)
            _ = await (day, week, month, year)
        }
        .task(id: ChartKey(symbol: chartSymbol, range: selectedRange)) {
            await store.loadChart(symbol: chartSymbol, range: selectedRange)
        }
    }

    private var heroPrice: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(displayedQuote.map { number($0.marketDisplayPrice, digits: marketPriceDigits($0.marketDisplayPrice, symbol: $0.symbol)) } ?? "—")
                    .font(.system(size: 36, weight: .semibold))
                    .tracking(-1)
                Text(heroPerformanceText)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(heroPerformanceTint)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Text(quote?.currency ?? "—").font(.caption.weight(.medium))
                Text(heroVolatilityText).font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var heroStatistics: some View {
        HStack(spacing: 0) {
            heroStatistic("常规开盘", value: displayedQuote?.openPrice)
            heroStatistic("常规最高", value: displayedQuote?.high)
            heroStatistic("常规最低", value: displayedQuote?.low)
            heroStatistic("常规前收", value: displayedQuote?.previousClose)
        }
        .padding(.top, 2)
    }

    private func heroStatistic(_ label: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value.map { number($0, digits: marketPriceDigits($0, symbol: displayedQuote?.symbol ?? "")) } ?? "—")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var temperatureMetrics: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                metricContent
            }
            .dynamicTypeSize(.large)
        } else {
            metricContent
        }
    }

    @ViewBuilder
    private var metricContent: some View {
        if region == .commodity {
            HStack(spacing: 8) {
                temperatureCard { marketMetric(symbol: "CL1!") }
                temperatureCard { marketMetric(symbol: "HG1!") }
                temperatureCard { marketMetric(symbol: "SI1!") }
            }
        } else if region == .crypto {
            HStack(spacing: 8) {
                temperatureCard { cryptoMetric(symbol: "BINANCE:ETHUSDT") }
                temperatureCard { cryptoMetric(symbol: "BINANCE:SOLUSDT") }
                temperatureCard { cryptoMetric(symbol: "BINANCE:BNBUSDT") }
            }
        } else if region == .unitedStates {
            HStack(spacing: 8) {
                Button(action: onOpenVIXHistory) {
                    temperatureCard { unitedStatesVIXMetric }
                }
                .buttonStyle(MarketPressStyle())
                .frame(maxWidth: .infinity)
                .accessibilityHint("查看 VIX 历史走势")
                temperatureCard { MarketTerminalSentiment(sentiment: store.dashboard?.sentiment) }
                temperatureCard { unitedStatesYieldMetric }
            }
        } else {
            Group {
                if region == .china {
                    ChinaMarketMetrics(store: store, onOpenMarketStructure: onOpenChinaMarketStructure)
                } else if region == .japan {
                    JapanMarketMetrics(store: store)
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
                } else {
                    EuropeMarketMetrics(store: store)
                }
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 180 : 82)
            .background(MarketStyle.cardSurface, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(MarketStyle.cardBorder, lineWidth: 0.8)
            }
        }
    }

    private func temperatureCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 76 : 70)
            .background(MarketStyle.cardSurface, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(MarketStyle.cardBorder, lineWidth: 0.8)
            }
    }

    private var heroTitle: String {
        if displayedQuote?.symbol == "SPY" || region.primarySymbol == "SPY" {
            return "标普 500 ETF（SPY）"
        }
        return displayedQuote?.presentationName ?? CoreDescriptor(symbol: region.primarySymbol).name
    }

    private var chartSymbol: String {
        quote?.symbol ?? region.primarySymbol
    }

    private var selectedTrend: [Double] {
        marketPreferredLeadChartTrend(
            chartValues: store.chartPresentation(symbol: chartSymbol, range: selectedRange)?.values ?? [],
            fallbackValues: selectedRange == .day ? store.trendValues(for: displayedQuote) : []
        )
    }

    private var selectedPeriodReturn: Double? {
        guard selectedRange != .day else { return nil }
        return store.chart(symbol: chartSymbol, range: selectedRange)?.periodReturn?.percent
    }

    private var selectedPeriodVolatility: Double? {
        store.chart(symbol: chartSymbol, range: selectedRange)?.periodVolatility?.percent
    }

    private var heroPerformanceText: String {
        if selectedRange == .day {
            return displayedQuote.map { "\(signed($0.marketDisplayChangeValue, digits: 2))  \($0.marketDisplayFormattedPercent)" } ?? "等待行情"
        }
        guard let selectedPeriodReturn else { return "正在计算\(selectedRange.rawValue)收益率" }
        let prefix = selectedPeriodReturn >= 0 ? "+" : "−"
        return "\(selectedRange.rawValue)收益率 \(prefix)\(number(abs(selectedPeriodReturn), digits: 2))%"
    }

    private var heroPerformanceTint: Color {
        guard selectedRange != .day else { return marketDisplayTint(displayedQuote) }
        guard let selectedPeriodReturn else { return .secondary }
        if selectedPeriodReturn > 0 { return MarketStyle.gain }
        if selectedPeriodReturn < 0 { return MarketStyle.loss }
        return .secondary
    }

    private var heroSourceLabel: String {
        let source = (quote?.hasActiveExtendedSessionQuote == true ? quote?.sessionDataSource : quote?.dataSource) ?? "—"
        switch source {
        case "AlpacaOvernightIndicative": return "Alpaca · 夜盘参考报价"
        case "TradingViewBrowser": return "TradingView"
        default: return source
        }
    }

    private var heroVolatilityText: String {
        guard let selectedPeriodVolatility else { return "波动率载入中" }
        return "年化波动率 \(number(selectedPeriodVolatility, digits: 2))%"
    }

    private var chartLabels: [String] {
        if let chart = store.chart(symbol: chartSymbol, range: selectedRange),
           let points = store.chartPresentation(symbol: chartSymbol, range: selectedRange)?.points,
           let first = points.first,
           let last = points.last {
            return [first, points[points.count / 2], last].map {
                chartTime($0.timestamp, range: selectedRange, timezone: chart.timezone)
            }
        }
        switch selectedRange {
        case .day:
            return ["开盘", "盘中", "最新"]
        case .week: return ["5日前", "本周", "最新"]
        case .month: return ["1月前", "本月", "最新"]
        case .year: return ["1年前", "年内", "最新"]
        case .quarter, .fiveYears, .maximum: return ["起点", "期间", "最新"]
        }
    }

    private var sessionLabel: String {
        if region == .crypto { return "24H 交易中" }
        return quote?.tradingSession.displayLabel ?? "行情更新"
    }

    private var sessionTint: Color {
        switch quote?.tradingSession {
        case .regular, .premarket, .postmarket, .overnight, .alwaysOpen:
            MarketStyle.live
        case .closed, .unknown, .none:
            .secondary
        }
    }

    private func cryptoMetric(symbol: String) -> some View {
        let value = store.quote(symbol: symbol)
        return MarketTerminalMetric(
            title: value?.presentationName ?? CoreDescriptor(symbol: symbol).name,
            value: value.map { number($0.price, digits: marketPriceDigits($0.price, symbol: $0.symbol)) } ?? "—",
            change: value?.formattedPercent ?? "—",
            tint: quoteTint(value),
            trend: store.trendValues(for: value)
        )
    }

    private func marketMetric(symbol: String) -> some View {
        let value = store.quote(symbol: symbol)
        return MarketTerminalMetric(
            title: value?.presentationName ?? CoreDescriptor(symbol: symbol).name,
            value: value.map { number($0.price, digits: marketPriceDigits($0.price, symbol: $0.symbol)) } ?? "—",
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
            change: store.quote(symbol: "^TNX").map { marketYieldChangeText(price: $0.price, previousClose: $0.previousClose) } ?? "—",
            tint: quoteTint(store.quote(symbol: "^TNX")),
            trend: store.trendValues(for: store.quote(symbol: "^TNX"))
        )
    }

    private var heroChart: some View {
        TerminalLeadChart(
            trend: selectedTrend,
            color: heroPerformanceTint,
            labels: chartLabels
        )
    }

    private var heroAccessibilityLabel: String {
        guard let displayedQuote else { return "\(heroTitle)，等待行情" }
        return "\(heroTitle)，最新价 \(number(displayedQuote.price, digits: marketPriceDigits(displayedQuote.price, symbol: displayedQuote.symbol)))，\(heroPerformanceText)，\(sessionLabel)"
    }
}

private struct JapanMarketMetrics: View {
    let store: MarketStore
    @StateObject private var volatilityStore = VolatilityResearchStore()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.rootTabIsActive) private var rootTabIsActive

    private var exchangeQuote: MarketQuote? { store.quote(symbol: "USDJPY") }
    private var yieldQuote: MarketQuote? { store.quote(symbol: "JP10Y") }
    private var volatility: VolatilityResearchInstrument? {
        volatilityStore.payload?.items.first { $0.market == "日本" }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    exchangeMetric.frame(height: 58)
                    Divider()
                    yieldMetric.frame(height: 58)
                    Divider()
                    volatilityMetric.frame(height: 58)
                }
                .dynamicTypeSize(.large)
            } else {
                HStack(spacing: 0) {
                    exchangeMetric
                    TerminalDivider()
                    yieldMetric
                    TerminalDivider()
                    volatilityMetric
                }
            }
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await volatilityStore.load()
        }
    }

    private var exchangeMetric: some View {
        MarketTerminalMetric(
            title: "美元兑日元",
            value: exchangeQuote.map { number($0.price, digits: marketPriceDigits($0.price, symbol: $0.symbol)) } ?? "—",
            change: exchangeQuote?.formattedPercent ?? "USDJPY",
            tint: quoteTint(exchangeQuote),
            trend: exchangeQuote?.trend ?? []
        )
    }

    private var yieldMetric: some View {
        MarketTerminalMetric(
            title: "日本 10Y 国债",
            value: yieldQuote.map { String(format: "%.2f%%", $0.price) } ?? "—",
            change: yieldQuote?.formattedPercent ?? "等待行情",
            tint: quoteTint(yieldQuote),
            trend: yieldQuote?.trend ?? []
        )
    }

    private var volatilityMetric: some View {
        MarketTerminalMetric(
            title: volatility?.shortName ?? "日经 225 VI",
            value: volatility.map { number($0.value, digits: 1) } ?? "—",
            change: volatility.map { String(format: "%+.2f%%", $0.dailyChangePercent) } ?? "等待行情",
            tint: volatilityTint,
            trend: volatility?.history.map(\.value) ?? []
        )
    }

    private var volatilityTint: Color {
        guard let change = volatility?.dailyChangePercent else { return .secondary }
        if change > 0 { return MarketStyle.loss }
        if change < 0 { return MarketStyle.gain }
        return .secondary
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
            value: quote.map { number($0.price, digits: marketPriceDigits($0.price, symbol: $0.symbol)) } ?? "—",
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
            value: companionQuote.map { number($0.price, digits: marketPriceDigits($0.price, symbol: $0.symbol)) } ?? "—",
            change: companionQuote?.formattedPercent ?? "等待行情",
            tint: quoteTint(companionQuote),
            trend: companionQuote?.trend ?? []
        )
    }
}

private struct ChinaMarketMetrics: View {
    let store: MarketStore
    let onOpenMarketStructure: () -> Void
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
                    MarketBreadthMetric(
                        breadth: breadth,
                        isStale: breadthIsStale,
                        onOpenMarketStructure: onOpenMarketStructure
                    )
                    .frame(height: 58)
                }
                .dynamicTypeSize(.large)
            } else {
                HStack(spacing: 0) {
                    exchangeMetric
                    TerminalDivider()
                    turnoverView
                    TerminalDivider()
                    MarketBreadthMetric(
                        breadth: breadth,
                        isStale: breadthIsStale,
                        onOpenMarketStructure: onOpenMarketStructure
                    )
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
    let onOpenMarketStructure: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("市场宽度")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Button(action: onOpenMarketStructure) {
                    HStack(spacing: 1) {
                        Text("杠杆")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7.5, weight: .bold))
                    }
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(MarketStyle.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("资金与杠杆信号")
                .accessibilityHint("打开 A 股资金与杠杆详情")
            }
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
    let trend: [Double]
    let color: Color
    let labels: [String]
    @State private var selectedIndex: Int?

    private var points: [MarketLeadChartPoint] {
        trend.enumerated().map { MarketLeadChartPoint(index: $0.offset, value: $0.element) }
    }

    private var activePoint: MarketLeadChartPoint? {
        guard !points.isEmpty else { return nil }
        return points[min(max(selectedIndex ?? points.count - 1, 0), points.count - 1)]
    }

    private var bounds: MarketSparklineBounds {
        marketSparklineBounds(trend, minimumRelativeRange: 0.0025)
    }

    private var xAxisValues: [Int] {
        guard points.count > 1 else { return [0] }
        return Array(Set([0, points.count / 2, points.count - 1])).sorted()
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(amplitudeText)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if points.count > 1 {
                Chart {
                    ForEach(points) { point in
                        AreaMark(
                            x: .value("位置", point.index),
                            yStart: .value("图表下界", bounds.lower),
                            yEnd: .value("价格", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color.opacity(0.08), color.opacity(0.005)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("位置", point.index),
                            y: .value("价格", point.value)
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    }

                    if let activePoint {
                        if selectedIndex != nil {
                            RuleMark(x: .value("查看位置", activePoint.index))
                                .foregroundStyle(color.opacity(0.25))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                        PointMark(
                            x: .value("当前位置", activePoint.index),
                            y: .value("当前价格", activePoint.value)
                        )
                        .foregroundStyle(color)
                        .symbolSize(selectedIndex == nil ? 28 : 45)
                        .annotation(position: .top, spacing: 5) {
                            if selectedIndex != nil {
                                Text(number(activePoint.value, digits: marketAxisDigits(values: trend)))
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            }
                        }
                    }
                }
                .chartYScale(domain: bounds.lower...bounds.upper)
                .chartXAxis {
                    AxisMarks(values: xAxisValues) { value in
                        AxisGridLine().foregroundStyle(.clear)
                        AxisTick().foregroundStyle(.clear)
                        AxisValueLabel {
                            if let index = value.as(Int.self) {
                                Text(axisLabel(for: index))
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisTick().foregroundStyle(.clear)
                        AxisValueLabel()
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let plotFrame = proxy.plotFrame {
                            let frame = geometry[plotFrame]
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            guard frame.contains(value.location) else { return }
                                            let locationX = value.location.x - frame.origin.x
                                            if let index: Int = proxy.value(atX: locationX) {
                                                selectedIndex = min(max(index, 0), points.count - 1)
                                            }
                                        }
                                        .onEnded { _ in selectedIndex = nil }
                                )
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "走势载入中",
                    systemImage: "chart.xyaxis.line",
                    description: Text("正在获取真实行情点")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("行情走势图，(amplitudeText)")
    }

    private var amplitudeText: String {
        guard let first = trend.first,
              first != 0,
              let minimum = trend.min(),
              let maximum = trend.max() else { return "区间振幅 —" }
        let amplitude = (maximum - minimum) / abs(first) * 100
        return "区间振幅 \(number(amplitude, digits: 2))%"
    }

    private func axisLabel(for index: Int) -> String {
        guard !labels.isEmpty, points.count > 1 else { return "" }
        if index == 0 { return labels[0] }
        if index == points.count - 1 { return labels[min(2, labels.count - 1)] }
        return labels[min(1, labels.count - 1)]
    }
}

private struct MarketLeadChartPoint: Identifiable {
    let index: Int
    let value: Double
    var id: Int { index }
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
                Text("恐惧与贪婪")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.secondary)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(sentiment.map { number($0.score, digits: 1) } ?? "—")
                        .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
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
            .frame(width: 22, height: 22)
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

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(MarketRegion.allCases) { region in
                    regionButton(region)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func regionButton(_ region: MarketRegion) -> some View {
        let isSelected = selection == region
        let weight: Font.Weight = isSelected ? .semibold : .medium
        let quote = store.quote(symbol: region.primarySymbol)
        let overnightQuote = region == .unitedStates && quote?.tradingSession != .regular
            ? marketActiveIndexSession(store.dashboard?.indexSessions?[region.primarySymbol])
            : nil
        let movementQuote = overnightQuote ?? quote
        let status = tabStatus(for: region, quote: quote, overnightQuote: overnightQuote)

        return Button {
            selection = region
        } label: {
            VStack(spacing: 6) {
                Text(region.rawValue)
                    .font(.system(size: 14, weight: weight))
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
        .id(region)
        .buttonStyle(.plain)
        .accessibilityLabel("\(region.rawValue)，\(tabMovementLabel(for: movementQuote))，\(status.accessibilityLabel)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func tabMovementTint(for quote: MarketQuote?) -> Color {
        guard let quote else { return Color.secondary }
        if quote.marketDisplayPercentValue > 0 { return MarketStyle.gain }
        if quote.marketDisplayPercentValue < 0 { return MarketStyle.loss }
        return Color.secondary
    }

    private func tabMovementLabel(for quote: MarketQuote?) -> String {
        guard let quote else { return "涨跌幅更新中" }
        let change = quote.marketDisplayPercentValue
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
    @State private var region: MarketRegion
    let store: MarketStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDetail: MarketDetailRoute?

    init(region: MarketRegion, store: MarketStore) {
        _region = State(initialValue: region)
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                MarketRegionPicker(store: store, selection: $region)
                DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭市场行情")
            }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .background(InvestmentDesign.surface)
                .overlay(alignment: .bottom) { Divider() }

            TabView(selection: $region) {
                ForEach(MarketRegion.allCases) { pageRegion in
                    MarketQuotesPage(region: pageRegion, store: store, isActive: region == pageRegion && selectedDetail == nil) { symbol in
                        selectedDetail = MarketDetailRoute(symbol: symbol)
                    }
                    .tag(pageRegion)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(MarketStyle.surface)
        .accessibilityIdentifier("market-quotes-sheet")
        .accessibilityAction(.escape) { dismiss() }
        .appSheet(item: $selectedDetail) { route in
            MarketIndexDetailView(
                symbol: route.symbol,
                store: store,
                onSelectSymbol: { selectedDetail = MarketDetailRoute(symbol: $0) }
            )
            .appPresentationDetents([.large])
            .appPresentationCornerRadius(28)
            .appPresentationBackground(MarketStyle.surface)
            .appPresentationScrollsWithoutExpanding()
        }
    }
}

private struct MarketQuotesPage: View {
    let region: MarketRegion
    let store: MarketStore
    let isActive: Bool
    let onSelectQuote: (String) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    @State private var showsMarketStructure = false
    @State private var chinaScope: ChinaIndexScope = .core
    @State private var displayedLogoPaths: [String: String]
    @ScaledMetric(relativeTo: .body) private var indexCardWidth: CGFloat = 136

    init(region: MarketRegion, store: MarketStore, isActive: Bool, onSelectQuote: @escaping (String) -> Void) {
        self.region = region
        self.store = store
        self.isActive = isActive
        self.onSelectQuote = onSelectQuote
        _displayedLogoPaths = State(initialValue: store.companyLogoPaths)
    }

    private var indexSymbols: [String] {
        region == .china && chinaScope == .all ? region.allSymbols : region.symbols
    }

    private var indices: [MarketQuote] {
        indexSymbols.compactMap { store.quote(symbol: $0) }
    }

    private var stocks: [MarketQuote] {
        store.dashboard?.componentsByRegion[region.dashboardID] ?? []
    }

    private var stocksTitle: String {
        store.dashboard?.componentsMeta?.label ?? "核心股票"
    }

    private var requestedQuotes: [MarketQuote] {
        (indices + stocks).reduce(into: [MarketQuote]()) { result, quote in
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
                        indexOverview
                    }
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
                            ForEach(stocks, id: \.symbol) { quote in
                                quoteRow(quote)
                                if quote.symbol != stocks.last?.symbol {
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
            .padding(.vertical, 14)
        }
        .accessibilityIdentifier("market-quotes-page-\(region.dashboardID)")
        .refreshable { await store.refresh() }
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
        switch region {
        case .commodity: "商品行情"
        case .crypto: "加密资产"
        default: "主要指数"
        }
    }

    @ViewBuilder
    private var indexOverview: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                ForEach(indices, id: \.symbol) { quote in
                    quoteRow(quote)
                    if quote.symbol != indices.last?.symbol {
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
                ForEach(indices, id: \.symbol) { quote in
                    Button { onSelectQuote(quote.symbol) } label: {
                        MarketOverviewIndexCard(quote: quote, trend: store.listTrendValues(for: quote))
                    }
                    .buttonStyle(MarketPressStyle())
                    .accessibilityIdentifier("market-quote-\(quote.symbol)")
                    .accessibilityHint("弹出行情详情")
                }
            }
            .padding(.horizontal, 18)
            .accessibilityIdentifier("market-quotes-indices")
        }
    }

    private func quoteRow(_ quote: MarketQuote) -> some View {
        Button { onSelectQuote(quote.symbol) } label: {
            MarketOverviewQuoteRow(
                quote: quote,
                trend: store.listTrendValues(for: quote),
                logoPath: displayedLogoPaths[quote.symbol]
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("market-quote-\(quote.symbol)")
        .accessibilityHint("弹出行情详情")
    }

    private var emptyQuotes: some View {
        VStack(spacing: 12) {
            if store.isLoading {
                ProgressView()
                Text("正在加载\(region.rawValue)市场行情")
            } else {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                Text(store.errorMessage == nil ? "暂无\(region.rawValue)市场行情" : "行情暂时无法加载")
                Button("重新加载") { Task { await store.refresh() } }
                    .buttonStyle(.bordered)
                    .tint(InvestmentDesign.accent)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 156)
        .padding(.horizontal, 18)
    }

    private var requestID: String {
        "\(region.dashboardID):\(requestedQuotes.map(\.symbol).joined(separator: ","))"
    }
}

private struct MarketOverviewIndexCard: View {
    let quote: MarketQuote
    let trend: [Double]

    private var formattedPrice: String {
        number(quote.marketDisplayPrice, digits: marketPriceDigits(quote.marketDisplayPrice, symbol: quote.symbol))
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesExpandedLayout: Bool { dynamicTypeSize >= .xxLarge }

    private var formattedPrice: String {
        number(quote.marketDisplayPrice, digits: marketPriceDigits(quote.marketDisplayPrice, symbol: quote.symbol))
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
        .accessibilityLabel("\(quote.presentationName)，\(quote.displayCode)，\(quote.freshnessLabel)，价格 \(formattedPrice)，涨跌幅 \(quote.marketDisplayFormattedPercent)")
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
            Text("\(quote.displayCode) · \(quote.freshnessLabel)")
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

private struct StableMarketIndexTableRow: View {
    let quote: MarketQuote
    let overnightQuote: MarketQuote?
    let incomingTrend: [Double]
    let companyLogoPath: String?
    let showsCompanyLogo: Bool
    let usesStockLayout: Bool
    let commonSession: MarketTradingSession?
    @State private var displayedTrend: [Double]

    init(
        quote: MarketQuote,
        overnightQuote: MarketQuote?,
        incomingTrend: [Double],
        companyLogoPath: String?,
        showsCompanyLogo: Bool,
        usesStockLayout: Bool = false,
        commonSession: MarketTradingSession? = nil
    ) {
        self.quote = quote
        self.overnightQuote = overnightQuote
        self.incomingTrend = incomingTrend
        self.companyLogoPath = companyLogoPath
        self.showsCompanyLogo = showsCompanyLogo
        self.usesStockLayout = usesStockLayout
        self.commonSession = commonSession
        _displayedTrend = State(initialValue: incomingTrend)
    }

    var body: some View {
        MarketIndexTableRow(
            quote: quote,
            overnightQuote: overnightQuote,
            trend: displayedTrend,
            companyLogoPath: companyLogoPath,
            showsCompanyLogo: showsCompanyLogo,
            usesStockLayout: usesStockLayout,
            commonSession: commonSession
        )
        .onChange(of: incomingTrend) { _, newValue in
            displayedTrend = marketPinnedListTrend(
                current: displayedTrend,
                incoming: newValue
            )
        }
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
    var usesStockLayout = false
    var commonSession: MarketTradingSession? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
                    .dynamicTypeSize(.xLarge)
            } else if usesStockLayout {
                stockLayout
            } else {
                standardLayout
            }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 88 : 62)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(usesStockLayout ? "打开股票详情" : "打开指数详情")
    }

    private var stockLayout: some View {
        HStack(spacing: 10) {
            if showsCompanyLogo {
                MarketInstrumentLogo(quote: quote, path: companyLogoPath, size: 30)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(displayedName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(displayedCode)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if commonSession != quote.tradingSession || quote.visibleDelayMinutes != nil {
                    Text(statusLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(number(displayedPrice, digits: marketPriceDigits(displayedPrice, symbol: displayedSymbol)))
                    .font(.subheadline.weight(.medium))
                Text(displayedPercent)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(displayedTint)
            }
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
            Group {
                if trend.count >= 2 {
                    Sparkline(values: trend, color: displayedTint, showsFill: false)
                } else {
                    Text("—").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 76, height: 34)
        }
        .padding(.vertical, 8)
        .accessibilityLabel("\(displayedName)，\(displayedCode)，\(statusLabel)，价格 \(displayedPrice)，涨跌幅 \(displayedPercent)，涨跌额 \(displayedChangeText)")
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

            Text(number(displayedPrice, digits: marketPriceDigits(displayedPrice, symbol: displayedSymbol)))
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
                Text(number(displayedPrice, digits: marketPriceDigits(displayedPrice, symbol: displayedSymbol)))
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
        return quote.marketDisplayPrice
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
        return quote.marketDisplayPercentValue
    }

    private var displayedPercent: String {
        if (overnightQuote ?? quote).hasSuspiciousIndexMove { return "待核验" }
        return String(format: "%@%.2f%%", displayedPercentValue >= 0 ? "+" : "−", abs(displayedPercentValue))
    }

    private var displayedChangeText: String {
        guard !(overnightQuote ?? quote).hasSuspiciousIndexMove else { return "—" }
        return signed(displayedChange, digits: marketChangeDigits(overnightQuote ?? quote))
    }

    private var displayedChange: Double {
        if let previousClose = overnightQuote?.previousClose ?? quote.previousClose {
            return displayedPrice - previousClose
        }
        return overnightQuote?.changeValue ?? quote.marketDisplayChangeValue
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
                Text(quote.map { number($0.price, digits: marketPriceDigits($0.price, symbol: $0.symbol)) } ?? "—")
                    .font(.system(size: 14.5, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    Text(quote.map { "\(signed($0.changeValue, digits: marketChangeDigits($0)))  \($0.formattedPercent)" } ?? "等待行情数据")
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
                    Text(quote.map { number($0.price, digits: marketPriceDigits($0.price, symbol: $0.symbol)) } ?? "—")
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
    let showsNavigationBar: Bool
    let onSelectSymbol: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPeriod: MarketChartPeriod
    @State private var displayedChart: MarketDetailChartRender?
    @State private var presentedValuation: CompanyValuationHistoryRoute?

    init(symbol: String, store: MarketStore, showsNavigationBar: Bool = false, onSelectSymbol: @escaping (String) -> Void) {
        self.symbol = symbol
        self.store = store
        self.showsNavigationBar = showsNavigationBar
        self.onSelectSymbol = onSelectSymbol
        _selectedPeriod = State(initialValue: symbol == "^VIX" ? .daily : .intraday)
    }

    private var selectedRange: MarketRange { selectedPeriod.sourceRange }
    private var quote: MarketQuote? { store.quote(symbol: symbol) }
    private var constituent: MarketIndexConstituent? { store.constituent(symbol: symbol) }
    private var companyLogoPath: String? { constituent?.logoPath ?? store.companyLogoPaths[symbol] }
    private var historicalSymbol: String { quote?.historicalSymbol ?? symbol }
    private var chartSymbol: String { quote?.symbol ?? symbol }
    private var selectedRangeChart: MarketChart? {
        guard displayedChart?.period == selectedPeriod,
              displayedChart?.symbol == chartSymbol else { return nil }
        return displayedChart?.artifacts.chart
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
    private var isAShareIndex: Bool {
        symbol.hasSuffix(".SS") || symbol.hasSuffix(".SZ") || symbol.hasPrefix("THS:")
    }
    private var xueqiuURL: URL? {
        guard !isIndex, !isCrypto, !isCommodity else { return nil }
        return marketXueqiuURL(for: quote?.symbol ?? symbol)
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
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    detailHeader
                    MarketDetailChart(
                        selectedPeriod: $selectedPeriod,
                        symbol: chartSymbol,
                        store: store,
                        renderedChart: $displayedChart
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
                    if isIndex { componentStocks }
                    MarketSummary(quote: quote, isIndex: isIndex)
                        .padding(.bottom, 18)
                        .overlay(alignment: .top) { Divider().padding(.horizontal, 18) }
                    Text("数据来源：\(quote?.dataSource ?? "行情服务") · \(quote?.freshnessLabel ?? "更新中")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 22)
                        .padding(.bottom, 20)
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("market-detail-scroll")
            detailActions
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(MarketStyle.surface)
        }
        .background(MarketStyle.surface.ignoresSafeArea())
        .accessibilityAction(.escape) { dismiss() }
        .toolbar(showsNavigationBar ? .visible : .hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .appSheet(item: $presentedValuation) { route in
            CompanyValuationHistorySheet(route: route)
                .appPresentationDetents([.large])
                .appPresentationCornerRadius(28)
        }
        .task(id: historicalSymbol) {
            async let yearChart: Void = store.loadChart(symbol: chartSymbol, range: .year)
            if isIndex { await store.loadIndexConstituents(symbol: historicalSymbol) }
            await yearChart
            if let quote, !isCommodity, symbol != "^VIX" {
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

    private var detailActions: some View {
        DetailSheetControls(
            closeLabel: "关闭行情详情",
            closeIdentifier: "market-detail-close",
            onClose: dismiss.callAsFunction
        ) {
            if let xueqiuURL {
                Button {
                    UIApplication.shared.open(xueqiuURL)
                } label: {
                    Image("XueqiuMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("在雪球打开\(quote?.presentationName ?? symbol)")
                .accessibilityIdentifier("market-xueqiu-link")
            }
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(quote?.detailPresentationName ?? CoreDescriptor(symbol: symbol).name)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .accessibilityIdentifier("market-detail-title")
                Text(quote?.detailInstrumentLabel ?? CoreDescriptor(symbol: symbol).code)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.bottom, 8)
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
            HStack(spacing: 6) {
                Text(quote?.marketAsOfLabel ?? "行情更新中")
                Text("·")
                Text(sessionText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if selectedRange == .day, let quote, quote.hasActiveExtendedSessionQuote {
                Text("较最近常规收盘 · \(number(quote.price, digits: marketPriceDigits(quote.price, symbol: quote.symbol)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    private var detailPrice: some View {
        Text(quote.map { number($0.marketDisplayPrice, digits: marketPriceDigits($0.marketDisplayPrice, symbol: $0.symbol)) } ?? "—")
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
            return quote.map {
                "\(signed($0.marketDisplayChangeValue, digits: marketChangeDigits($0)))  \($0.marketDisplayFormattedPercent)"
            } ?? "等待行情数据"
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
        VStack(alignment: .leading, spacing: 14) {
            Text("行情数据")
                .font(.headline)
                .accessibilityIdentifier("market-detail-statistics")
            if quote?.hasActiveExtendedSessionQuote == true {
                Text(yearChart.map {
                    "常规时段数据 · \($0.tradingDate)"
                } ?? "最近常规交易时段数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Grid(horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    metric(isCrypto ? "24H开盘" : "开盘", quote?.openPrice)
                    metric("最高", quote?.high)
                }
                GridRow {
                    metric("最低", quote?.low)
                    metric(quote?.hasActiveExtendedSessionQuote == true ? "常规收盘" : "昨收",
                           quote?.hasActiveExtendedSessionQuote == true ? quote?.price : quote?.previousClose)
                }
                GridRow {
                    metric("成交量", quote?.volume, compact: true)
                    textMetric("振幅", amplitudeText)
                }
                GridRow {
                    metric("涨跌额", quote?.changeValue)
                    textMetric("年化波动率", detailVolatilityText)
                }
                GridRow {
                    metric("52周最高", market52WeekHigh(yearChart, symbol: chartSymbol))
                    metric("52周最低", quote?.week52Low ?? market52WeekLow(yearChart))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .overlay(alignment: .top) { Divider().padding(.horizontal, 20) }
    }

    private var yearChart: MarketChart? {
        store.chart(symbol: chartSymbol, range: .year)
    }

    private var showsCompanyProfile: Bool {
        !isIndex && (constituent != nil || quote?.marketCap != nil || quote?.peStatic != nil || quote?.pe != nil)
    }

    private var companyProfile: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("公司资料").font(.system(size: 19, weight: .semibold))
            HStack(alignment: .center, spacing: 12) {
                if let quote { CompanyLogo(quote: quote, path: companyLogoPath) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(quote?.presentationName ?? symbol).font(.subheadline.weight(.semibold))
                    Text("\(quote?.displayCode ?? symbol) · \(companyMarketLabel(symbol))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Divider()
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
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .overlay(alignment: .top) { Divider().padding(.horizontal, 18) }
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
                Text(value.map { number($0, digits: 2) } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chart.xyaxis.line")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(kind.color)
            }
            .font(.footnote)
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
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            Text(value)
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
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

private struct MarketDetailChartRenderKey: Equatable {
    let symbol: String
    let period: MarketChartPeriod
    let snapshotID: UUID?
}

private struct MarketDetailChartRender {
    let symbol: String
    let period: MarketChartPeriod
    let artifacts: MarketChartDisplayArtifacts
}

private struct MarketDetailChart: View {
    @Binding var selectedPeriod: MarketChartPeriod
    let symbol: String
    let store: MarketStore
    @Binding var renderedChart: MarketDetailChartRender?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedPointIndex: Int?
    @State private var showsChartData = false
    @State private var showsMinutePeriods = false
    @State private var unsupportedPeriod: MarketChartPeriod?
    private var selectedRange: MarketRange { selectedPeriod.sourceRange }
    private var sourceSnapshot: MarketChartSnapshot? { store.chartSnapshot(symbol: symbol, range: selectedRange) }
    private var currentRender: MarketDetailChartRender? {
        guard renderedChart?.period == selectedPeriod,
              renderedChart?.symbol == symbol else { return nil }
        return renderedChart
    }
    private var chart: MarketChart? { currentRender?.artifacts.chart }
    private var presentation: MarketChartPresentation? {
        currentRender?.artifacts.presentation
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
        let source = sourceSnapshot
        let renderKey = MarketDetailChartRenderKey(symbol: symbol, period: selectedPeriod, snapshotID: source?.id)
        VStack(alignment: .leading, spacing: 10) {
            periodPicker
            HStack(alignment: .firstTextBaseline) {
                Text(selectedPointIndex == nil
                     ? chartWindowLabel
                     : inspectedPointIndex.map { pointTime(points[$0].timestamp) } ?? "")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("market-chart-readout")
                Spacer(minLength: 8)
                if selectedPointIndex != nil, let inspectedPointIndex {
                    Text(formattedPrice(points[inspectedPointIndex].close))
                        .fontWeight(.semibold)
                }
            }
            .font(.caption)
            .monospacedDigit()
            .frame(minHeight: 20)
            chartPlot
            HStack {
                ForEach(Array(timelineLabels.enumerated()), id: \.offset) { index, label in
                    Text(label).lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityIdentifier("market-chart-time-\(index)")
                    if index < timelineLabels.count - 1 { Spacer() }
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.trailing, 48)
            if let presentation, presentation.hasVolume {
                VolumeBars(
                    points: presentation.points,
                    xFractions: presentation.xFractions,
                    volumeCeiling: presentation.volumeCeiling,
                    fractionGap: presentation.volumeFractionGap
                )
                .frame(height: 28)
                .padding(.trailing, 48)
                .accessibilityLabel("成交量")
            }
            Text(chartCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            if presentation?.lineSegments.contains(where: \.isMissing) == true {
                Text("虚线表示数据缺口，期间走势未知")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    if selectedRange == .day, let quote = store.quote(symbol: symbol), quote.hasActiveExtendedSessionQuote {
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
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .onChange(of: selectedPeriod) { _, _ in
            selectedPointIndex = nil
        }
        .task(id: renderKey) {
            guard !Task.isCancelled else { return }
            guard let source else {
                renderedChart = nil
                unsupportedPeriod = nil
                return
            }
            let artifacts = try? await marketChartDisplayArtifacts(for: source.chart, period: renderKey.period)
            guard !Task.isCancelled, selectedPeriod == renderKey.period, sourceSnapshot?.id == source.id else { return }
            guard let artifacts else {
                renderedChart = nil
                unsupportedPeriod = renderKey.period
                return
            }
            unsupportedPeriod = nil
            renderedChart = MarketDetailChartRender(
                symbol: renderKey.symbol, period: renderKey.period, artifacts: artifacts
            )
        }
        .task(id: selectedPeriod) {
            selectedPointIndex = nil
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
            Button { showsMinutePeriods.toggle() } label: { minutePeriodLabel }
            .accessibilityIdentifier("market-chart-minute-menu")
            .accessibilityLabel(selectedPeriod.isMinute ? "\(selectedPeriod.rawValue)钟周期" : "分钟周期")
            .accessibilityAddTraits(selectedPeriod.isMinute ? .isSelected : [])
            periodButton(.daily)
            periodButton(.weekly)
            periodButton(.monthly)
        }
    }

    private var minutePeriodLabel: some View {
        HStack(spacing: 2) {
            Text(selectedPeriod.isMinute ? selectedPeriod.rawValue : "分钟")
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
        }
        .font(.footnote.weight(selectedPeriod.isMinute ? .semibold : .medium))
        .foregroundStyle(selectedPeriod.isMinute ? .primary : .secondary)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(periodSelectionBackground(isSelected: selectedPeriod.isMinute))
    }

    private func periodButton(_ period: MarketChartPeriod) -> some View {
        Button {
            selectedPeriod = period
            showsMinutePeriods = false
        } label: {
            Text(period.rawValue)
                .font(.footnote.weight(selectedPeriod == period ? .semibold : .medium))
                .foregroundStyle(selectedPeriod == period ? .primary : .secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(periodSelectionBackground(isSelected: selectedPeriod == period))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(periodIdentifier(period))
        .accessibilityLabel("\(period.rawValue)行情")
        .accessibilityAddTraits(selectedPeriod == period ? .isSelected : [])
    }

    private func periodSelectionBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? Color.secondary.opacity(0.12) : .clear)
            .padding(.vertical, 4)
    }

    private func periodIdentifier(_ period: MarketChartPeriod) -> String {
        "market-chart-period-\(String(describing: period))"
    }

    private var chartPlot: some View {
        ZStack {
            ChartGrid(low: presentation?.low, high: presentation?.high, digits: presentation?.axisDigits ?? 2)
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
                if !values.isEmpty, let previousClose = chart?.quote.previousClose {
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
        .frame(height: 240)
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
            if let movingAverages = currentRender?.artifacts.movingAverages, !movingAverages.isEmpty {
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
        MarketViewDateFormatters.chart(period: selectedPeriod, timezone: chart?.timezone)
            .string(from: Date(timeIntervalSince1970: Double(timestamp) / 1_000))
    }

    private var chartWindowLabel: String {
        guard let chart else { return "交易所时间" }
        guard !selectedPeriod.isIntraday,
              let first = points.first else {
            return "\(chart.tradingDate) · 交易所时间"
        }
        let formatter = MarketViewDateFormatters.chart(period: .weekly, timezone: chart.timezone)
        let startTimestamp = chart.periodReturn?.startTimestamp ?? first.timestamp
        let start = formatter.string(from: Date(timeIntervalSince1970: Double(startTimestamp) / 1_000))
        let dates = "\(start) – \(chart.tradingDate)"
        switch selectedPeriod {
        case .weekly: return "近5年 · \(dates)"
        case .monthly: return "全部可用历史 · \(dates)"
        default: return dates
        }
    }

    private var chartDisplayTitle: String {
        selectedPeriod.chartTitle
    }

    private var chartAccessibilityValue: String {
        let summary = "\(chartDisplayTitle)，\(points.count)个数据点"
        guard let first = points.first, let last = points.last else { return summary }
        let formatter = MarketViewDateFormatters.chartCoverage(timezone: chart?.timezone)
        let start = formatter.string(from: Date(timeIntervalSince1970: Double(first.timestamp) / 1_000))
        let end = formatter.string(from: Date(timeIntervalSince1970: Double(last.timestamp) / 1_000))
        let drawnCount = currentRender?.artifacts.drawnPointCount ?? 0
        return "\(summary)，起点\(start)，终点\(end)，绘制\(drawnCount)个数据点"
    }

    private var chartCaption: String {
        let dated = chart.map { "\(chartDisplayTitle) · \($0.tradingDate)" } ?? chartDisplayTitle
        let sessionText = presentation?.extendedSessionLabel.map { " · \($0)" } ?? ""
        return presentation?.hasVolume == true
            ? "\(dated)\(sessionText) · 成交量"
            : "\(dated)\(sessionText)"
    }
    private var chartColor: Color {
        if selectedRange != .day, let periodReturn = chart?.periodReturn?.percent {
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
        if unsupportedPeriod == selectedPeriod { return "当前行情数据无法生成\(selectedPeriod.rawValue)图表" }
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
            if selectedPeriod == .daily, chart?.tradingDate != sourceSnapshot?.chart.tradingDate {
                return "最新交易日的日线待确认"
            }
            guard !quality.isFinal || points.last?.state == "provisional" else { return nil }
            return selectedPeriod.isIntraday ? "当前分钟更新中" : "当前周期尚未收盘"
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
                let color = segment.isMissing ? Color.secondary : segment.isRegular ? regularColor : MarketStyle.purple
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
        let digits = marketDetailPriceDigits(value: low, price: quote.price, symbol: quote.symbol)
        return "\(subject)当前\(direction)昨收，日内运行于 \(number(low, digits: digits))–\(number(high, digits: digits))，目前位于\(positionText)。"
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
                Text(number(quote.price, digits: marketPriceDigits(quote.price, symbol: quote.symbol))).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                Text(quote.formattedPercent).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(quoteTint(quote))
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(quote.presentationName)，\(quote.symbol)，市值 \(quote.marketCap.map(compactNumber) ?? "未知")，最新价 \(number(quote.price, digits: marketPriceDigits(quote.price, symbol: quote.symbol)))，\(quote.formattedPercent)，点按查看详情")
    }
}

private struct MarketInstrumentLogo: View {
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

private struct Sparkline: View {
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
        case "^GSPC", "^NDX", "^DJI", "SPY", "QQQ", "DIA", "000001.SS", "000016.SS", "000300.SS", "399006.SZ",
             "000688.SS", "000905.SS", "000852.SS", "932000.SS", "THS:883418", "^HSTECH",
             "^HSI", "^N225", "^KS11", "^STOXX50E", "^GDAXI", "^FTSE", "^FCHI":
            true
        default:
            false
        }
    }
    var name: String { switch symbol { case "^GSPC": "标普500"; case "^NDX": "纳斯达克100"; case "^DJI": "道琼斯工业指数"; case "SPY": "标普500实时代理（SPY）"; case "QQQ": "纳斯达克100实时代理（QQQ）"; case "DIA": "道琼斯实时代理（DIA）"; case "000001.SS": "上证指数"; case "000016.SS": "上证50"; case "000300.SS": "沪深300"; case "399006.SZ": "创业板指"; case "000688.SS": "科创50"; case "000905.SS": "中证500"; case "000852.SS": "中证1000"; case "932000.SS": "中证2000"; case "THS:883418": "微盘股"; case "^HSTECH": "恒生科技指数"; case "^HSI": "恒生指数"; case "^N225": "日经225"; case "^KS11": "韩国KOSPI"; case "^STOXX50E": "欧洲STOXX 50"; case "^GDAXI": "德国DAX"; case "^FTSE": "英国富时100"; case "^FCHI": "法国CAC 40"; case "GC1!": "COMEX 黄金"; case "CL1!": "WTI 原油"; case "HG1!": "COMEX 铜"; case "SI1!": "COMEX 白银"; case "NG1!": "NYMEX 天然气"; case "ZC1!": "CBOT 玉米"; default: symbol } }
    var code: String { switch symbol { case "^GSPC": "SPX"; case "^NDX": "NDX"; case "^DJI": "DJI"; case "SPY", "QQQ", "DIA": symbol; case "000001.SS": "000001.SH"; case "000300.SS": "000300.SH"; case "000688.SS": "000688.SH"; case "^HSTECH": "HSTECH"; case "^HSI": "HSI"; case "^N225": "N225"; case "^KS11": "KOSPI"; case "^STOXX50E": "SX5E"; case "^GDAXI": "DAX"; case "^FTSE": "FTSE"; case "^FCHI": "CAC40"; default: symbol } }
    var icon: String { switch symbol { case "^GSPC", "^NDX", "^DJI": "chart.line.uptrend.xyaxis"; case "QQQ": "q.circle.fill"; case "DIA": "building.columns.fill"; case "000001.SS", "000300.SS": "building.2.fill"; case "000688.SS": "cpu.fill"; case "^HSTECH": "asterisk"; case "^HSI": "h.circle.fill"; case "^N225": "yensign.circle.fill"; case "^KS11": "k.circle.fill"; case "^STOXX50E": "globe.europe.africa.fill"; case "^GDAXI": "shield.fill"; case "^FTSE": "sterlingsign.circle.fill"; case "^FCHI": "f.circle.fill"; default: "star.fill" } }
}

private func marketLocalTime(_ timestamp: Int64?, city: String, timeZone: String) -> String {
    guard let timestamp else { return "等待更新" }
    let formatter = MarketViewDateFormatters.localTime(timeZone: timeZone)
    return "\(city) \(formatter.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000)))"
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

private func quoteTint(_ quote: MarketQuote?) -> Color { guard let quote else { return .secondary }; return quote.isUp ? MarketStyle.gain : MarketStyle.loss }
private func marketDisplayTint(_ quote: MarketQuote?) -> Color {
    guard let quote else { return .secondary }
    return quote.marketDisplayPercentValue >= 0 ? MarketStyle.gain : MarketStyle.loss
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
private func marketHeroChangeText(_ quote: MarketQuote) -> String {
    guard !quote.hasSuspiciousIndexMove else { return "异常波动待核验" }
    return "\(signed(quote.changeValue, digits: marketChangeDigits(quote)))  \(quote.formattedPercent)"
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
private func marketChangeDigits(_ quote: MarketQuote) -> Int {
    marketDetailPriceDigits(value: quote.marketDisplayChangeValue, price: quote.marketDisplayPrice, symbol: quote.symbol)
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
        return chart(format: format, timezone: timezone)
    }

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
private func stockSymbol(_ symbol: String) -> String { switch symbol { case "AAPL": "apple.logo"; case "MSFT": "square.grid.2x2.fill"; case "META": "infinity"; case "AMZN": "a.circle.fill"; default: "eye.fill" } }
private func stockColor(_ symbol: String) -> Color { switch symbol { case "AAPL": .primary; case "AMZN": .orange; case "NVDA": .green; default: .blue } }

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
