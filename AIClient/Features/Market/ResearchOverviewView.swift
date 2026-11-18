import SwiftUI

private enum ResearchSection: String, CaseIterable {
    case overview = "概览", company = "公司", industry = "行业", macro = "宏观", viewpoints = "观点"
}

enum ResearchHomeContent {
    static let primaryMarkets = [("标普500", "^GSPC"), ("沪深300", "000300.SS"), ("日经225", "^N225")]
    static let sectors = [("半导体", "NVDA"), ("软件云", "MSFT"), ("能源", "SHEL"), ("消费", "AMZN")]
    static var chartSymbols: [String] { primaryMarkets.map(\.1) }
}

private enum ResearchStyle {
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGroupedBackground : UIColor(red: 0.966, green: 0.972, blue: 0.980, alpha: 1)
    })
    static let surface = Color(uiColor: .systemBackground)
    static let muted = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .secondaryLabel : UIColor(red: 0.37, green: 0.41, blue: 0.50, alpha: 1)
    })
    static let blue = InvestmentDesign.accent
    static let divider = Color(uiColor: .separator).opacity(0.25)
    static func tint(_ quote: MarketQuote?) -> Color {
        guard let quote, !quote.hasSuspiciousIndexMove else { return muted }
        return quote.marketDisplayPercentValue >= 0 ? InvestmentDesign.gain : InvestmentDesign.loss
    }
}

/// The research shell owns its visible sections; each section keeps its existing detail flows.
struct ResearchHomeView: View {
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @State private var visitedSections: Set<ResearchSection> = []
    let store: MarketStore
    @ObservedObject var researchStore: InstitutionResearchStore
    let onOpenMacro: () -> Void
    let onOpenGlobalRanking: () -> Void
    let onOpenInvestors: () -> Void
    let onOpenIndustries: () -> Void
    let onOpenMarketQuotes: (MarketRegion) -> Void
    let onOpenMarketDetail: (String) -> Void
    let onOpenRetailInvestors: () -> Void
    @State private var section: ResearchSection = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--company-preview") { return .company }
        #endif
        return .overview
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(ResearchSection.allCases, id: \.self) { item in
                    Button { section = item } label: {
                        VStack(spacing: 7) {
                            Text(item.rawValue)
                                .font(.system(size: 15, weight: section == item ? .semibold : .regular))
                                .foregroundStyle(section == item ? Color.primary : ResearchStyle.muted)
                            Capsule().fill(section == item ? ResearchStyle.blue : .clear)
                                .frame(width: 26, height: 2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("research-section-\(item.rawValue)")
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 3)
            ZStack {
                sectionContent(.overview) {
                    ResearchOverviewView(
                        store: store,
                        onOpenMacro: onOpenMacro, onOpenGlobalRanking: onOpenGlobalRanking,
                        onOpenInvestors: onOpenInvestors,
                        onOpenIndustries: onOpenIndustries, onOpenMarketQuotes: onOpenMarketQuotes,
                        onOpenMarketDetail: onOpenMarketDetail, onOpenRetailInvestors: onOpenRetailInvestors
                    )
                }
                sectionContent(.company) { CompanyResearchView() }
                sectionContent(.industry) { IndustryPanoramaView() }
                sectionContent(.macro) { ChinaMacroView() }
                sectionContent(.viewpoints) {
                    NavigationStack { InstitutionResearchView(store: researchStore, showsCloseButton: false) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ResearchStyle.canvas)
        .onChange(of: section, initial: true) { _, value in visitedSections.insert(value) }
    }

    @ViewBuilder
    private func sectionContent<Content: View>(_ target: ResearchSection, @ViewBuilder content: () -> Content) -> some View {
        if section == target || visitedSections.contains(target) {
            content()
                .environment(\.rootTabIsActive, rootTabIsActive && section == target)
                .opacity(section == target ? 1 : 0)
                .allowsHitTesting(section == target)
                .accessibilityHidden(section != target)
                .zIndex(section == target ? 1 : 0)
                .transition(.identity)
        }
    }
}

private struct ResearchOverviewView: View {
    let store: MarketStore
    let onOpenMacro: () -> Void
    let onOpenGlobalRanking: () -> Void
    let onOpenInvestors: () -> Void
    let onOpenIndustries: () -> Void
    let onOpenMarketQuotes: (MarketRegion) -> Void
    let onOpenMarketDetail: (String) -> Void
    let onOpenRetailInvestors: () -> Void
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @State private var stockRegion: MarketRegion = .unitedStates
    @Environment(\.scenePhase) private var scenePhase

    private let primaryMarkets = ResearchHomeContent.primaryMarkets
    // These are explicitly identified as representative companies, rather than invented sector indices.
    private let sectors = ResearchHomeContent.sectors
    private var chartSymbols: [String] { ResearchHomeContent.chartSymbols }
    private let stockRegions: [MarketRegion] = [.unitedStates, .china, .japan, .korea, .europe]
    private var stocks: [MarketQuote] {
        // Keep the server's existing membership and ordering, with no synthetic quotes.
        Array((store.dashboard?.componentsByRegion[stockRegion.dashboardID] ?? []).prefix(4))
    }

    private var afterHoursSymbols: [String] {
        guard rootTabIsActive, scenePhase == .active, stockRegion == .unitedStates else { return [] }
        return stocks.filter {
            $0.tradingSession == .overnight || $0.tradingSession == .premarket || $0.tradingSession == .closed
        }.map(\.symbol)
    }

    var body: some View {
        ScrollView {
            if store.dashboard == nil && store.errorMessage == nil {
                ContentLoadingPlaceholder(title: "正在准备市场概览", rowCount: 5)
                    .accessibilityIdentifier("research-home-loading")
            } else {
            VStack(spacing: 8) {
                globalMarkets
                environment
                coreStocks
                industries
                utilities
                if let message = store.errorMessage {
                    Button { Task { await store.refresh() } } label: {
                        Label("\(message) · 点击重试", systemImage: "arrow.clockwise")
                            .font(.caption).foregroundStyle(ResearchStyle.muted)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 10)
            }
        }
        .accessibilityIdentifier("research-overview")
        .scrollIndicators(.hidden)
        .task(id: afterHoursSymbols) {
            let symbols = afterHoursSymbols
            guard !symbols.isEmpty else { return }
            while !Task.isCancelled {
                let missing = symbols.filter { symbol in
                    guard let quote = store.quote(symbol: symbol) else { return false }
                    return store.dayChartForSessionQuotes(symbol: symbol)?.stockAfterHoursEnd(for: quote) == nil
                }
                guard !missing.isEmpty else { return }
                await store.preloadListCharts(symbols: missing)
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
        }
        .task(id: "\(rootTabIsActive):\(scenePhase):\(store.dashboard != nil)") {
            guard rootTabIsActive, scenePhase == .active, store.dashboard != nil else { return }
            while !Task.isCancelled {
                await store.preloadListCharts(symbols: chartSymbols)
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
            }
        }
    }

    private var globalMarkets: some View {
        VStack(spacing: 4) {
            sectionHeading("全球市场", trailing: marketDate) { onOpenMarketQuotes(.unitedStates) }
            VStack(spacing: 0) {
                ForEach(primaryMarkets, id: \.1) { title, symbol in
                    ResearchStyle.divider.frame(height: 0.5)
                    marketRow(title: title, symbol: symbol)
                }
            }
            ResearchStyle.divider.frame(height: 0.5)
            HStack(spacing: 0) {
                ticker("欧洲 STOXX50", symbol: "^STOXX50E", showsPrice: false)
                separator(height: 16)
                ticker("黄金", symbol: "GC1!", showsPrice: true)
                separator(height: 16)
                ticker("比特币", symbol: "BINANCE:BTCUSDT", showsPrice: true)
            }
        }
        .padding(8)
        .background(ResearchStyle.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func marketRow(title: String, symbol: String) -> some View {
        let quote = store.quote(symbol: symbol)
        let color = ResearchStyle.tint(quote)
        return Button { onOpenMarketDetail(symbol) } label: {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).foregroundStyle(ResearchStyle.muted)
                    if quote?.stale == true {
                        Text("行情待更新").font(.caption2).foregroundStyle(ResearchStyle.muted)
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)

                ResearchSparkline(values: store.listTrendValues(for: quote), color: color)
                    .frame(maxWidth: .infinity).frame(height: 24)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(price(quote)).font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(quote?.marketDisplayFormattedPercent ?? "—")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(color)
                }
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                .frame(width: 100, alignment: .trailing)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("research-market-\(symbol)")
    }

    private func ticker(_ title: String, symbol: String, showsPrice: Bool) -> some View {
        let quote = store.quote(symbol: symbol)
        return Button { onOpenMarketDetail(symbol) } label: {
            ViewThatFits(in: .horizontal) {
                tickerText(title, quote: quote, showsPrice: showsPrice)
                tickerText(title, quote: quote, showsPrice: showsPrice).font(.system(size: 8.5))
                tickerText(title, quote: quote, showsPrice: false)
                VStack(spacing: 3) {
                    Text(title).foregroundStyle(ResearchStyle.muted)
                    Text(quote?.marketDisplayFormattedPercent ?? "—").foregroundStyle(ResearchStyle.tint(quote))
                }
            }
            .font(.system(size: 9.5)).monospacedDigit()
            .frame(maxWidth: .infinity, minHeight: 18)
            .padding(.horizontal, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("research-market-\(symbol)")
    }

    private func tickerText(_ title: String, quote: MarketQuote?, showsPrice: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(ResearchStyle.muted)
            if showsPrice { Text(price(quote)).foregroundStyle(ResearchStyle.muted) }
            Text(quote?.marketDisplayFormattedPercent ?? "—").foregroundStyle(ResearchStyle.tint(quote))
        }.fixedSize(horizontal: true, vertical: false)
    }

    private var environment: some View {
        HStack(alignment: .top, spacing: 0) {
            metric("VIX", symbol: "^VIX", yield: false)
            separator(height: 48)
            metric("美债10Y", symbol: "^TNX", yield: true)
            separator(height: 48)
            Button(action: onOpenRetailInvestors) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("市场情绪").font(.caption).foregroundStyle(ResearchStyle.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(sentiment.map { String(format: "%.1f", $0.score) } ?? "—")
                            .font(.system(size: 19, weight: .semibold)).foregroundStyle(.primary)
                        Text("/100").font(.caption).foregroundStyle(ResearchStyle.muted)
                    }.monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    Text(sentiment?.ratingZh ?? "暂无数据").font(.caption2).foregroundStyle(ResearchStyle.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("research-sentiment")
        }
        .padding(.vertical, 8)
        .background(ResearchStyle.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var sentiment: MarketSentiment? {
        guard let value = store.dashboard?.sentiment, value.available != false else { return nil }
        return value
    }

    private func metric(_ title: String, symbol: String, yield: Bool) -> some View {
        let quote = store.quote(symbol: symbol)
        let change = quote?.marketDisplayChangeValue
        return Button { onOpenMarketDetail(symbol) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(ResearchStyle.muted)
                Text(quote.map { String(format: yield ? "%.2f%%" : "%.2f", $0.marketDisplayPrice) } ?? "—")
                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(change.map { String(format: yield ? "%+.0f bp" : "%+.2f 点", $0 * (yield ? 100 : 1)) } ?? "—")
                    .font(.caption2).foregroundStyle(ResearchStyle.tint(quote))
            }
            .monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("research-market-\(symbol)")
    }

    private var industries: some View {
        VStack(spacing: 5) {
            sectionHeading("行业表现", trailing: "代表公司 · 全部", action: onOpenIndustries)
            ResearchStyle.divider.frame(height: 0.5)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(sectors, id: \.1) { title, symbol in
                    sectorCard(title, symbol: symbol)
                }
            }
        }
        .padding(8)
        .background(ResearchStyle.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectorCard(_ title: String, symbol: String) -> some View {
        let quote = store.quote(symbol: symbol)
        return Button { onOpenMarketDetail(symbol) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Text(symbol).font(.caption2).foregroundStyle(ResearchStyle.muted)
                }
                Text(quote?.marketDisplayFormattedPercent ?? "—")
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(ResearchStyle.tint(quote))
                    .monospacedDigit()
            }
            .lineLimit(1).minimumScaleFactor(0.75)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，代表公司\(symbol)，\(quote?.marketDisplayFormattedPercent ?? "暂无行情")")
        .accessibilityIdentifier("research-sector-\(symbol)")
    }

    private var coreStocks: some View {
        VStack(spacing: 5) {
            sectionHeading(store.dashboard?.componentsMeta?.label ?? "核心股票", trailing: "全部") {
                onOpenMarketQuotes(stockRegion)
            }
            Picker("股票市场", selection: $stockRegion) {
                ForEach(stockRegions) { region in
                    Text(region.rawValue).tag(region)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("research-stock-region")

            if stocks.isEmpty {
                Text("暂无股票行情")
                    .font(.subheadline).foregroundStyle(ResearchStyle.muted)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ResearchStockQuotes(
                    quotes: stocks,
                    showsExtendedHours: stockRegion == .unitedStates,
                    store: store,
                    onOpen: onOpenMarketDetail
                )
            }
        }
        .padding(8)
        .background(ResearchStyle.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var utilities: some View {
        HStack(spacing: 0) {
            utility("机构持仓", action: onOpenInvestors)
            separator(height: 16)
            utility("宏观指标", action: onOpenMacro)
            separator(height: 16)
            utility("资产排行", action: onOpenGlobalRanking)
        }
        .padding(.vertical, 2)
        .background(ResearchStyle.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func utility(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 12))
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
            }.foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 32).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("research-utility-\(title)")
    }

    private func sectionHeading(_ title: String, trailing: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 16, weight: .semibold))
            Spacer(minLength: 4)
            Button(action: action) {
                HStack(spacing: 6) {
                    Text(trailing).font(.system(size: 11))
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
                }.foregroundStyle(ResearchStyle.muted).frame(minHeight: 20).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("research-all-\(title)")
        }.padding(.horizontal, 4)
    }

    private func separator(height: CGFloat) -> some View {
        ResearchStyle.divider.frame(width: 0.5, height: height)
    }

    private func price(_ quote: MarketQuote?) -> String {
        guard let quote else { return "—" }
        return quote.marketDisplayPrice.formatted(.number.precision(.fractionLength(2)))
    }



    private var marketDate: String {
        // Markets close in different time zones; identify the displayed snapshot as an update.
        guard let timestamp = store.quote(symbol: "^GSPC")?.timestamp else { return "指数与股票" }
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        let display = DateFormatter()
        display.locale = Locale(identifier: "zh_CN")
        display.dateFormat = "M月d日"
        return display.string(from: date) + "更新"
    }
}

private struct ResearchStockQuotes: View {
    let quotes: [MarketQuote]
    let showsExtendedHours: Bool
    let store: MarketStore
    let onOpen: (String) -> Void

    private var extendedSession: MarketTradingSession {
        quotes.contains { $0.tradingSession == .premarket } ? .premarket : .overnight
    }
    private var showsIndicative: Bool { quotes.contains(where: \.hasIndicativeOvernightPrice) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(showsExtendedHours ? "股票 · USD" : "股票")
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsExtendedHours {
                    columnTitle(quotes.contains { $0.tradingSession == .regular } ? "常规盘" : "常规收盘")
                    columnTitle("盘后")
                    columnTitle(StockSessionQuotes.extendedTitle(extendedSession, indicative: showsIndicative))
                } else {
                    columnTitle("报价")
                    columnTitle("涨跌幅")
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(ResearchStyle.muted)
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            .background(ResearchStyle.canvas, in: RoundedRectangle(cornerRadius: 6))

            ForEach(quotes) { quote in
                if quote.id != quotes.first?.id {
                    ResearchStyle.divider.frame(height: 0.5)
                }
                stockRow(quote)
            }

            if showsExtendedHours {
                Text(StockSessionQuotes.sourceNote(indicative: showsIndicative))
                    .font(.caption2)
                    .foregroundStyle(ResearchStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }
        }
    }

    private func columnTitle(_ title: String) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func stockRow(_ quote: MarketQuote) -> some View {
        let active = quote.stale != true && !store.isShowingCachedSnapshot
        return Button { onOpen(quote.symbol) } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(quote.presentationName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(active ? quote.displayCode : "\(quote.displayCode) · 待更新")
                        .font(.caption2)
                        .foregroundStyle(ResearchStyle.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsExtendedHours {
                    let sessions = StockSessionQuotes(quote: quote, chart: store.dayChartForSessionQuotes(symbol: quote.symbol),
                                                      extendedSession: extendedSession, isCurrent: active)
                    ForEach(sessions.columns) { column in
                        StockSessionPriceCell(column: column, symbol: quote.symbol, muted: ResearchStyle.muted)
                    }
                } else {
                    Text(quote.marketDisplayPrice.formatted(.number.precision(.fractionLength(
                        marketPriceDigits(quote.marketDisplayPrice, symbol: quote.symbol)
                    ))))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(quote.marketDisplayFormattedPercent)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ResearchStyle.tint(quote))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .monospacedDigit()
            .padding(.horizontal, 6)
            .frame(minHeight: showsExtendedHours ? 54 : 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("research-stock-\(quote.symbol)")
    }

}

private struct ResearchSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            if points.count > 1 {
                Path { $0.addLines(points) }.stroke(color, style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
            } else {
                Text("暂无走势").font(.system(size: 9)).foregroundStyle(ResearchStyle.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let valid = values.filter(\.isFinite)
        guard valid.count > 1, let low = valid.min(), let high = valid.max() else { return [] }
        let span = high - low
        return valid.enumerated().map { index, value in
            CGPoint(x: size.width * Double(index) / Double(valid.count - 1),
                    y: span > 0 ? 2 + (size.height - 4) * (1 - (value - low) / span) : size.height / 2)
        }
    }
}
