import SwiftUI

private enum ResearchTopic: String, Identifiable {
    case company = "公司", industry = "行业", macro = "宏观", viewpoints = "观点", sentiment = "市场情绪"

    static let shortcuts: [Self] = [.company, .industry, .macro, .viewpoints]

    var id: Self { self }

    var title: String {
        switch self {
        case .company: "公司研究"
        case .industry: "行业全景"
        case .macro: "宏观指标"
        case .viewpoints: "机构观点"
        case .sentiment: "CNN 恐慌与贪婪指数"
        }
    }

    var icon: String {
        switch self {
        case .company: "building.2"
        case .industry: "square.grid.2x2"
        case .macro: "chart.line.uptrend.xyaxis"
        case .viewpoints: "text.bubble"
        case .sentiment: "gauge.with.dots.needle.50percent"
        }
    }
}

enum ResearchHomeContent {
    static let primaryMarkets = [("标普500", "^GSPC"), ("沪深300", "000300.SS"), ("日经225", "^N225")]
    static let sectors = [("半导体", "NVDA"), ("软件云", "MSFT"), ("能源", "SHEL"), ("消费", "AMZN")]
    static var chartSymbols: [String] { primaryMarkets.map(\.1) }

    static func stocks(in dashboard: MarketDashboard?, region: MarketRegion) -> [MarketQuote] {
        Array((dashboard?.componentsByRegion[region.dashboardID] ?? []).prefix(4))
    }

    static func afterHoursSymbols(for stocks: [MarketQuote]) -> [String] {
        stocks.filter {
            $0.tradingSession == .overnight || $0.tradingSession == .premarket || $0.tradingSession == .closed
        }.map(\.symbol)
    }
}

private enum ResearchStyle {
    static let surface = InvestmentDesign.surface
    static let muted = Color.secondary
    static let accent = Color(red: 0.22, green: 0.36, blue: 0.27)
    static let selection = accent.opacity(0.10)
    static let marketSurface = accent.opacity(0.06)
    static let divider = Color.primary.opacity(0.09)
    static let inset: CGFloat = 18

    static func tint(_ quote: MarketQuote?) -> Color {
        guard let quote, !quote.hasSuspiciousIndexMove else { return muted }
        return quote.marketDisplayPercentValue >= 0 ? InvestmentDesign.gain : InvestmentDesign.loss
    }
}

struct ResearchHomeView: View {
    let store: MarketStore
    let researchStore: InstitutionResearchStore
    let companyStore: CompanyResearchStore
    let onOpenGlobalRanking: () -> Void
    let onOpenInvestors: () -> Void
    let onOpenMarketQuotes: (MarketQuotesScope) -> Void
    let onOpenMarketDetail: (String) -> Void
    let onOpenRetailInvestors: () -> Void
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var stockRegion: MarketRegion = .unitedStates
    @State private var presentedTopic: ResearchTopic? = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--company-preview") { return .company }
        #endif
        return nil
    }()

    private let primaryMarkets = ResearchHomeContent.primaryMarkets
    // These are explicitly identified as representative companies, rather than invented sector indices.
    private let sectors = ResearchHomeContent.sectors
    private var chartSymbols: [String] { ResearchHomeContent.chartSymbols }
    private let stockRegions: [MarketRegion] = [.unitedStates, .china, .japan, .korea, .europe]
    private var stocks: [MarketQuote] {
        ResearchHomeContent.stocks(in: store.dashboard, region: stockRegion)
    }
    private var isLoadingMarket: Bool { store.dashboard == nil && store.errorMessage == nil }
    private var shouldRefreshCharts: Bool { rootTabIsActive && scenePhase == .active && presentedTopic == nil }

    private var afterHoursSymbols: [String] {
        guard shouldRefreshCharts, stockRegion == .unitedStates else { return [] }
        return ResearchHomeContent.afterHoursSymbols(for: stocks)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isLoadingMarket {
                    ContentLoadingPlaceholder(title: "正在准备市场概览", layout: .chart)
                        .accessibilityIdentifier("research-home-loading")
                } else {
                    if let message = store.errorMessage {
                        Button { Task { await store.refresh() } } label: {
                            Label(store.isRetrying ? "正在重试行情" : "\(message) · 点击重试",
                                  systemImage: "arrow.clockwise")
                                .font(.footnote)
                                .foregroundStyle(ResearchStyle.accent)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isRetrying)
                    } else if let notice = store.quoteIssueMessage {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(ResearchStyle.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    globalMarkets
                }
                researchTopics
                if !isLoadingMarket {
                    coreStocks
                    industries
                }
                utilities
            }
            .padding(.horizontal, ResearchStyle.inset)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(ResearchStyle.surface)
        .accessibilityIdentifier("research-overview")
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .appSheet(item: $presentedTopic) { topic in
            ResearchTopicSheet(title: topic.title) {
                switch topic {
                case .company:
                    CompanyResearchView(store: companyStore)
                case .industry:
                    IndustryPanoramaView()
                case .macro:
                    ChinaMacroView()
                case .viewpoints:
                    NavigationStack { InstitutionResearchView(store: researchStore) }
                case .sentiment:
                    ResearchSentimentView(store: store)
                }
            }
            .appPresentationDetents([.large])
            .appPresentationCornerRadius(28)
            .appPresentationBackground(ResearchStyle.surface)
            .appPresentationDragIndicator()
            .appPresentationScrollsWithoutExpanding()
        }
        .task(id: afterHoursSymbols) {
            let symbols = afterHoursSymbols
            guard !symbols.isEmpty else { return }
            while !Task.isCancelled {
                let missing = store.missingAfterHoursSymbols(symbols)
                guard !missing.isEmpty else { return }
                await store.preloadListCharts(symbols: missing)
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
        }
        .task(id: shouldRefreshCharts && store.dashboard != nil) {
            guard shouldRefreshCharts, store.dashboard != nil else { return }
            while !Task.isCancelled {
                await store.preloadListCharts(symbols: chartSymbols)
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
            }
        }
    }

    private var researchTopics: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
            ForEach(ResearchTopic.shortcuts) { topic in
                Button { presentedTopic = topic } label: {
                    Label(topic.rawValue, systemImage: topic.icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ResearchStyle.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(topic.title)
                .accessibilityIdentifier("research-topic-\(topic.rawValue)")
            }
        }
        .padding(4)
        .background(ResearchStyle.marketSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var globalMarkets: some View {
        VStack(spacing: 0) {
            sectionHeading(
                "全球市场", trailing: "全部行情", prominent: true,
                status: store.isShowingCachedSnapshot ? "缓存行情" : nil
            ) {
                onOpenMarketQuotes(.global)
            }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 0))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            layout {
                ForEach(primaryMarkets, id: \.1) { title, symbol in
                    marketIndex(title: title, symbol: symbol)
                        .overlay(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .leading) {
                            if symbol != primaryMarkets.first?.1 {
                                if dynamicTypeSize.isAccessibilitySize {
                                    ResearchStyle.divider.frame(height: 1).padding(.horizontal, 10)
                                } else {
                                    ResearchStyle.divider.frame(width: 1).padding(.vertical, 11)
                                }
                            }
                        }
                }
            }
            .background(ResearchStyle.marketSurface, in: RoundedRectangle(cornerRadius: 15))

            layout {
                ticker("欧洲 STOXX 50", symbol: "^STOXX50E", showsPrice: false)
                ticker("黄金", symbol: "GC1!", showsPrice: true)
                ticker("比特币", symbol: "BINANCE:BTCUSDT", showsPrice: true)
            }
            .padding(.vertical, 5)
            ResearchStyle.divider.frame(height: 1)
            marketIndicators(layout)
        }
    }

    private func marketIndex(title: String, symbol: String) -> some View {
        let quote = store.quote(symbol: symbol)
        let color = ResearchStyle.tint(quote)
        let trend = store.listTrendValues(for: quote)
        return Button { onOpenMarketDetail(symbol) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(price(quote))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(quote?.marketDisplayFormattedPercent ?? "—")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(color)
                ResearchSparkline(values: trend, color: color, emptyLabel: trendStatus(symbol: symbol))
                    .equatable()
                    .frame(height: 22)
                    .padding(.top, 2)
                Text(quote?.researchStatus ?? "暂无行情")
                    .font(.caption2)
                    .foregroundStyle(ResearchStyle.muted)
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("research-market-\(symbol)")
    }

    private func ticker(_ title: String, symbol: String, showsPrice: Bool) -> some View {
        let quote = store.quote(symbol: symbol)
        return Button { onOpenMarketDetail(symbol) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ResearchStyle.muted)
                if showsPrice {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 4) {
                            Text(price(quote)).foregroundStyle(.primary)
                            tickerChange(quote)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(price(quote)).foregroundStyle(.primary)
                            tickerChange(quote)
                        }
                    }
                    .font(.caption2.weight(.semibold))
                } else {
                    tickerChange(quote)
                        .font(.caption2.weight(.semibold))
                }
                if showsPrice, let unit = quote?.priceUnit ?? quote?.currency {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(ResearchStyle.muted)
                }
                Text(quote?.researchStatus ?? "暂无行情")
                    .font(.caption2)
                    .foregroundStyle(ResearchStyle.muted)
                    .lineLimit(2)
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("research-market-\(symbol)")
    }

    private func tickerChange(_ quote: MarketQuote?) -> some View {
        Text(quote?.marketDisplayFormattedPercent ?? "—")
            .foregroundStyle(ResearchStyle.tint(quote))
    }

    private func marketIndicators(_ layout: AnyLayout) -> some View {
        layout {
            metric("VIX", symbol: "^VIX", yield: false)
            metric("美债10Y", symbol: "^TNX", yield: true)
            Button { presentedTopic = .sentiment } label: {
                indicator("CNN 市场情绪") {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(sentiment.map { String(format: "%.1f", $0.score) } ?? "—")
                        Text("/100").font(.caption).foregroundStyle(ResearchStyle.muted)
                    }
                } detail: {
                    Text(sentiment?.ratingZh ?? "暂无数据")
                        .foregroundStyle(ResearchStyle.muted)
                    if let date = marketISODate(sentiment?.updatedAt) {
                        Text(marketShortTimestamp(Int64(date.timeIntervalSince1970 * 1000)))
                            .foregroundStyle(ResearchStyle.muted)
                    }
                    if sentiment?.stale == true {
                        Text("待更新").foregroundStyle(ResearchStyle.muted)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("research-sentiment")
        }
        .padding(.top, 9)
    }

    private var sentiment: MarketSentiment? {
        guard let value = store.dashboard?.sentiment, value.available != false else { return nil }
        return value
    }

    private func metric(_ title: String, symbol: String, yield: Bool) -> some View {
        let quote = store.quote(symbol: symbol)
        let change = quote.flatMap { $0.previousClose == nil ? nil : $0.marketDisplayChangeValue }
        return Button { onOpenMarketDetail(symbol) } label: {
            indicator(title) {
                Text(quote.map { String(format: yield ? "%.2f%%" : "%.2f", $0.marketDisplayPrice) } ?? "—")
            } detail: {
                Text(change.map { String(format: yield ? "%+.0f bp" : "%+.2f 点", $0 * (yield ? 100 : 1)) } ?? "—")
                    .foregroundStyle(ResearchStyle.tint(quote))
                if let quality = store.dashboard?.unavailableMetric(symbol: symbol), quote == nil {
                    Text(quality.unavailableLabel)
                        .foregroundStyle(ResearchStyle.muted)
                        .lineLimit(2)
                } else {
                    Text(quote?.researchStatus ?? "暂无行情").foregroundStyle(ResearchStyle.muted)
                    if let timestamp = quote?.marketAsOfTimestamp {
                        Text(marketShortTimestamp(timestamp)).foregroundStyle(ResearchStyle.muted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("research-market-\(symbol)")
    }

    private func indicator<Value: View, Detail: View>(
        _ title: String,
        @ViewBuilder value: () -> Value,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(ResearchStyle.muted)
            value().font(.title3.weight(.semibold)).foregroundStyle(.primary)
            detail().font(.caption2.weight(.medium))
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.74)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var industries: some View {
        VStack(spacing: 0) {
            sectionHeading("行业表现", trailing: "全部行业", status: "代表公司") {
                presentedTopic = .industry
            }
            ResearchStyle.divider.frame(height: 0.5)
            let column = GridItem(.flexible())
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [column] : [column, column], spacing: 0) {
                ForEach(sectors, id: \.1) { title, symbol in
                    sectorCard(title, symbol: symbol)
                }
            }
        }
    }

    private func sectorCard(_ title: String, symbol: String) -> some View {
        let quote = store.quote(symbol: symbol)
        return Button { onOpenMarketDetail(symbol) } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Text(symbol)
                        .font(.caption2).foregroundStyle(ResearchStyle.muted)
                    Text(quote?.researchStatus ?? "暂无行情")
                        .font(.caption2).foregroundStyle(ResearchStyle.muted)
                }
                Spacer(minLength: 0)
                Text(quote?.marketDisplayFormattedPercent ?? "—")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ResearchStyle.tint(quote))
                    .monospacedDigit()
            }
            .lineLimit(1).minimumScaleFactor(0.75)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("research-sector-\(symbol)")
    }

    private var coreStocks: some View {
        VStack(spacing: 2) {
            sectionHeading(store.dashboard?.componentsMeta?.label ?? "核心股票", trailing: "全部股票") {
                onOpenMarketQuotes(.region(stockRegion))
            }
            stockRegionSelector
            if stocks.isEmpty {
                Text("暂无股票行情")
                    .font(.subheadline).foregroundStyle(ResearchStyle.muted)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ResearchStockQuotes(
                    quotes: stocks,
                    region: stockRegion,
                    store: store,
                    onOpen: onOpenMarketDetail
                )
            }
        }
    }

    private var stockRegionSelector: some View {
        HStack(spacing: 6) {
            ForEach(stockRegions) { region in
                Button { stockRegion = region } label: {
                    Text(region.rawValue)
                        .font(.footnote.weight(stockRegion == region ? .semibold : .medium))
                        .foregroundStyle(stockRegion == region ? ResearchStyle.accent : ResearchStyle.muted)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(stockRegion == region ? ResearchStyle.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(stockRegion == region ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("股票市场")
        .accessibilityIdentifier("research-stock-region")
    }

    private var utilities: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 0))
            : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            utility("机构持仓", icon: "person.2", action: onOpenInvestors)
            utility("资产排行", icon: "list.number", action: onOpenGlobalRanking)
            utility("散户观点", icon: "bubble.left.and.bubble.right", action: onOpenRetailInvestors)
        }
        .padding(.horizontal, 6)
        .background(ResearchStyle.marketSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func utility(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.footnote.weight(.medium))
                .foregroundStyle(ResearchStyle.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("research-utility-\(title)")
    }

    private func sectionHeading(
        _ title: String, trailing: String, prominent: Bool = false, status: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(prominent ? .title2.weight(.bold) : .headline)
                    .accessibilityAddTraits(.isHeader)
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(ResearchStyle.muted)
                }
            }
            Spacer(minLength: 0)
            Button(action: action) {
                HStack(spacing: 4) {
                    Text(trailing).font(.footnote.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(ResearchStyle.accent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("research-all-\(title)")
        }
    }

    private func price(_ quote: MarketQuote?) -> String {
        guard let quote else { return "—" }
        return quote.marketDisplayPrice.formatted(.number.precision(.fractionLength(2)))
    }
    private func trendStatus(symbol: String) -> String {
        if store.isLoadingChart(symbol: symbol, range: .day) { return "走势加载中" }
        if store.chartError(symbol: symbol, range: .day) != nil { return "走势加载失败" }
        return store.chartSnapshot(symbol: symbol, range: .day) == nil && store.quote(symbol: symbol) != nil
            ? "走势待加载" : "暂无走势"
    }
}

private extension MarketQuote {
    var researchStatus: String {
        if stale == true { return "报价待更新" }
        if tradingSession == .closed, let date = quality?.tradingDate {
            return "\(date.suffix(5)) 收盘"
        }
        let sessionLabel: String
        if hasIndicativeOvernightPrice {
            sessionLabel = "夜盘参考 · 中间价"
        } else if symbol == "^VIX", tradingSession == .premarket {
            sessionLabel = "盘前快照"
        } else if tradingSession.isExtended, !hasActiveExtendedSessionQuote {
            sessionLabel = "常规收盘"
        } else {
            sessionLabel = tradingSession.displayLabel
        }
        if let minutes = visibleDelayMinutes {
            return "\(sessionLabel) · 延迟 \(minutes) 分钟"
        }
        return quality?.status == "delayed" ? "\(sessionLabel) · 延迟报价" : sessionLabel
    }
}

private struct ResearchTopicSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭\(title)")
            }
            .padding(.horizontal, ResearchStyle.inset)
            .padding(.top, 12)
            .overlay(alignment: .bottom) { ResearchStyle.divider.frame(height: 1) }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(ResearchStyle.surface)
    }
}

private struct ResearchStockQuotes: View {
    let quotes: [MarketQuote]
    let region: MarketRegion
    let store: MarketStore
    let onOpen: (String) -> Void

    private var showsExtendedHours: Bool { region == .unitedStates }
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
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(ResearchStyle.marketSurface, in: RoundedRectangle(cornerRadius: 8))

            ForEach(quotes) { quote in
                if quote.id != quotes.first?.id {
                    ResearchStyle.divider.frame(height: 0.5)
                }
                stockRow(quote)
            }

            if showsExtendedHours {
                Text(StockSessionQuotes.sourceNote(indicative: showsIndicative))
                    .font(.caption)
                    .foregroundStyle(ResearchStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.top, 7)
            }
        }
    }

    private func columnTitle(_ title: String) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.trailing, showsExtendedHours ? 4 : 0)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func stockRow(_ quote: MarketQuote) -> some View {
        let active = quote.stale != true && !store.isShowingCachedSnapshot
        let lastTrade = store.lastSessionTrade(for: quote)
        return Button { onOpen(quote.symbol) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(quote.presentationName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(stockSubtitle(quote, active: active, hasLastTrade: lastTrade != nil))
                            .font(.caption2)
                            .foregroundStyle(ResearchStyle.muted)
                            .lineLimit(showsExtendedHours ? 1 : 3)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if showsExtendedHours {
                        let sessions = store.stockSessionQuotes(for: quote, chartSymbol: quote.symbol,
                                                                extendedSession: extendedSession, isCurrent: active)
                        ForEach(sessions.columns) { column in
                            StockSessionPriceCell(column: column, symbol: quote.symbol, muted: ResearchStyle.muted)
                        }
                    } else {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(quote.stale == true ? "—" : quote.marketDisplayPrice.formatted(
                                .number.precision(.fractionLength(marketPriceDigits(quote.marketDisplayPrice, symbol: quote.symbol)))
                            ))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            if let currency = quote.currency {
                                Text(currency).font(.caption2).foregroundStyle(ResearchStyle.muted)
                            }
                        }
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(quote.stale == true ? "—" : quote.marketDisplayFormattedPercent)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ResearchStyle.tint(quote))
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                if let lastTrade {
                    MarketLastSessionTradeNote(trade: lastTrade, symbol: quote.symbol)
                }
            }
            .monospacedDigit()
            .padding(.horizontal, 8)
            .frame(minHeight: showsExtendedHours ? 54 : 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("research-stock-\(quote.symbol)")
    }

    private func stockSubtitle(_ quote: MarketQuote, active: Bool, hasLastTrade: Bool) -> String {
        let code = region == .europe && quote.listingCountryCode == "US" ? "\(quote.displayCode) · 美股" : quote.displayCode
        if hasLastTrade { return code }
        if !active { return "\(code) · 待更新" }
        return showsExtendedHours ? code : "\(code)\n\(quote.researchStatus)"
    }
}

private struct ResearchSparkline: View, Equatable {
    let values: [Double]
    let color: Color
    let emptyLabel: String

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            if let first = points.first, let last = points.last {
                Path { path in
                    path.addLines(points)
                    path.addLine(to: CGPoint(x: last.x, y: proxy.size.height))
                    path.addLine(to: CGPoint(x: first.x, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.18), color.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))
                Path { $0.addLines(points) }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            } else {
                Text(emptyLabel).font(.caption2).foregroundStyle(ResearchStyle.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
