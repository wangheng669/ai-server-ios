import SwiftUI

private enum ResearchTopic: String, Identifiable {
    case company = "公司", industry = "行业", macro = "宏观", viewpoints = "机构观点", sentiment = "市场情绪"

    case industryQuotes = "全部行业"
    case chinaMarketStructure = "中国市场结构"

    static let shortcuts: [Self] = [.company, .industry, .macro, .viewpoints]

    var id: Self { self }

    var title: String {
        switch self {
        case .company: "公司研究"
        case .industry: "行业全景"
        case .industryQuotes: "A 股行业排行"
        case .macro: "宏观指标"
        case .viewpoints: "机构观点"
        case .sentiment: "CNN 恐慌与贪婪指数"
        case .chinaMarketStructure: "资金与杠杆信号"
        }
    }

    var icon: String {
        switch self {
        case .company: "building.2"
        case .industry: "square.grid.2x2"
        case .industryQuotes: "chart.bar.xaxis"
        case .macro: "chart.line.uptrend.xyaxis"
        case .viewpoints: "text.bubble"
        case .sentiment: "gauge.with.dots.needle.50percent"
        case .chinaMarketStructure: "chart.pie"
        }
    }
}

enum ResearchHomeContent {
    static let primaryMarkets = [("标普500", "^GSPC"), ("沪深300", "000300.SS"), ("日经225", "^N225")]
    static var chartSymbols: [String] { primaryMarkets.map(\.1) }
}

private enum ResearchStyle {
    static let muted = Color.secondary

    static func tint(_ quote: MarketQuote?) -> Color {
        guard let quote, !quote.hasSuspiciousIndexMove, let change = quote.marketDisplayPercentValue else { return muted }
        return change > 0 ? InvestmentDesign.gain : change < 0 ? InvestmentDesign.loss : muted
    }
}

private enum ResearchPage: String, CaseIterable, Identifiable {
    case globalMarkets = "全球市场"
    case coreStocks = "核心股票"
    case industries = "行业表现"

    var id: Self { self }
}

struct ResearchHomeView: View {
    let store: MarketStore
    let researchStore: InstitutionResearchStore
    let companyStore: CompanyResearchStore
    let onOpenGlobalRanking: () -> Void
    let onOpenInvestors: () -> Void
    let onOpenMarketDetail: (String) -> Void
    let onOpenRetailInvestors: () -> Void
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPage: ResearchPage = .globalMarkets
    @State private var stockRegion: MarketRegion = .unitedStates
    @State private var presentedTopic: ResearchTopic? = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--company-preview") { return .company }
        #endif
        return nil
    }()

    private var chartSymbols: [String] { ResearchHomeContent.chartSymbols }
    private var isLoadingMarket: Bool { store.dashboard == nil && store.errorMessage == nil }
    private var shouldRefreshCharts: Bool { rootTabIsActive && scenePhase == .active && presentedTopic == nil }
    private var shouldRefreshIndustryQuotes: Bool {
        rootTabIsActive && scenePhase == .active && (presentedTopic == nil || presentedTopic == .industryQuotes)
    }

    var body: some View {
        VStack(spacing: 0) {
            pageSelector
                .padding(.horizontal, ResearchDesign.inset)
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(ResearchDesign.line).frame(height: 1) }

            TabView(selection: $selectedPage) {
                ForEach(ResearchPage.allCases) { page in
                    pageContent(page)
                        .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: .infinity)

            researchShortcuts
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, ResearchDesign.inset)
                .padding(.top, 4)
                .padding(.bottom, 6)
                .overlay(alignment: .top) { Rectangle().fill(ResearchDesign.line).frame(height: 1) }
        }
        .background(InvestmentDesign.surface)
        .accessibilityIdentifier("research-overview")
        .appSheet(item: $presentedTopic) { topic in
            ResearchTopicSheet(closeLabel: "关闭\(topic.title)", onClose: { presentedTopic = nil }) {
                switch topic {
                case .company:
                    CompanyResearchView(store: companyStore)
                case .industry:
                    IndustryPanoramaView()
                case .industryQuotes:
                    ResearchIndustryRanking(store: store)
                case .macro:
                    ChinaMacroView()
                case .viewpoints:
                    NavigationStack { InstitutionResearchView(store: researchStore) }
                case .sentiment:
                    ResearchSentimentView(store: store)
                case .chinaMarketStructure:
                    ScrollView {
                        ChinaMarketStructurePanel(structure: store.dashboard?.marketStructure)
                            .padding(.bottom, 76)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .appPresentationDetents([.large])
            .appPresentationCornerRadius(28)
            .appPresentationBackground(InvestmentDesign.surface)
            .appPresentationScrollsWithoutExpanding()
        }
        .task(id: shouldRefreshIndustryQuotes) {
            guard shouldRefreshIndustryQuotes else { return }
            while !Task.isCancelled {
                await store.refreshAShareIndustryQuotes()
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

    private var pageSelector: some View {
        HStack(spacing: 6) {
            ForEach(ResearchPage.allCases) { page in
                let isSelected = selectedPage == page
                Button {
                    withAnimation { selectedPage = page }
                } label: {
                    Text(page.rawValue)
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(isSelected ? ResearchDesign.accent : ResearchStyle.muted)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isSelected ? ResearchDesign.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("研究栏目")
    }

    private func pageContent(_ page: ResearchPage) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                switch page {
                case .globalMarkets:
                    marketContent { globalMarkets }
                case .coreStocks:
                    marketContent { coreStocks }
                case .industries:
                    industries
                }
            }
            .padding(.horizontal, ResearchDesign.inset)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .id(page == .coreStocks ? stockRegion : nil)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if page == .coreStocks {
                stockRegionSelector
                    .padding(.horizontal, ResearchDesign.inset)
                    .background(InvestmentDesign.surface)
                    .overlay(alignment: .top) { Rectangle().fill(ResearchDesign.line).frame(height: 1) }
            }
        }
    }

    @ViewBuilder
    private func marketContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if isLoadingMarket {
            ContentLoadingPlaceholder(title: "正在准备市场概览", layout: .chart)
                .accessibilityIdentifier("research-home-loading")
        } else {
            if let message = store.errorMessage {
                Button { Task { await store.refresh() } } label: {
                    Label(store.isRetrying ? "正在重试行情" : "\(message) · 点击重试",
                          systemImage: "arrow.clockwise")
                        .font(.footnote)
                        .foregroundStyle(ResearchDesign.accent)
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
            content()
        }
    }

    private var researchShortcuts: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
            ForEach(ResearchTopic.shortcuts) { topic in
                researchShortcut(topic.rawValue, icon: topic.icon, accessibilityLabel: topic.title) {
                    presentedTopic = topic
                }
            }
            researchShortcut("机构持仓", icon: "person.2", action: onOpenInvestors)
            researchShortcut("资产排行", icon: "list.number", action: onOpenGlobalRanking)
            researchShortcut("散户观点", icon: "bubble.left.and.bubble.right", action: onOpenRetailInvestors)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("研究快捷入口")
    }

    private func researchShortcut(
        _ title: String, icon: String, accessibilityLabel: String? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ResearchDesign.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityIdentifier("research-shortcut-\(title)")
    }

    private var globalMarkets: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.isShowingCachedSnapshot {
                Text("缓存行情")
                    .font(.caption)
                    .foregroundStyle(ResearchStyle.muted)
            }
            ResearchGlobalMarketSnapshot(
                store: store,
                onOpenQuote: onOpenMarketDetail,
                onOpenSentiment: { presentedTopic = .sentiment },
                onOpenChinaMarketStructure: { presentedTopic = .chinaMarketStructure }
            )
        }
    }

    private var industries: some View {
        VStack(spacing: 8) {
            sectionHeading("A 股行业表现", trailing: "全部行业", status: "申万一级行业") {
                presentedTopic = .industryQuotes
            }
            ResearchIndustryPerformance(store: store)
        }
    }

    private var coreStocks: some View {
        VStack(spacing: 8) {
            if store.isShowingCachedSnapshot {
                Text("缓存行情")
                    .font(.caption)
                    .foregroundStyle(ResearchStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            let entries = store.dashboard?.regionalStockEntries[stockRegion.dashboardID] ?? []
            if entries.isEmpty {
                Text("暂无股票行情")
                    .font(.subheadline).foregroundStyle(ResearchStyle.muted)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ResearchStockQuotes(
                    entries: entries,
                    region: stockRegion,
                    store: store,
                    isActive: shouldRefreshCharts && selectedPage == .coreStocks,
                    onOpen: onOpenMarketDetail
                )
            }
        }
    }

    private var stockRegionSelector: some View {
        HStack(spacing: 6) {
            ForEach(MarketRegion.stockRegions) { region in
                Button { stockRegion = region } label: {
                    Text(region.rawValue)
                        .font(.footnote.weight(stockRegion == region ? .semibold : .medium))
                        .foregroundStyle(stockRegion == region ? ResearchDesign.accent : ResearchStyle.muted)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(stockRegion == region ? ResearchDesign.selection : .clear,
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

    private func sectionHeading(
        _ title: String, trailing: String, status: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            sectionTitle(title, status: status)
            sectionAction(trailing, action: action)
                .accessibilityIdentifier("research-all-\(title)")
        }
    }

    private func sectionAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.footnote.weight(.medium))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(ResearchDesign.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(ResearchDesign.selection, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String, status: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(ResearchStyle.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ResearchGlobalMarketSnapshot: View {
    let store: MarketStore
    let onOpenQuote: (String) -> Void
    let onOpenSentiment: () -> Void
    let onOpenChinaMarketStructure: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsMore = false
    @ScaledMetric(relativeTo: .caption) private var changeColumnWidth: CGFloat = 66
    @ScaledMetric(relativeTo: .caption2) private var sparklineHeight: CGFloat = 30

    private static let tickers: [(title: String, symbol: String, showsPrice: Bool)] = [
        ("欧洲 STOXX 50", "^STOXX50E", false),
        ("黄金", "GC1!", true),
        ("比特币", "BINANCE:BTCUSDT", true)
    ]
    private static let metrics: [(title: String, symbol: String, isYield: Bool)] = [
        ("VIX", "^VIX", false),
        ("美债 10 年期", "^TNX", true)
    ]

    private var usesSingleColumn: Bool { dynamicTypeSize >= .xxxLarge }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(ResearchHomeContent.primaryMarkets, id: \.1) { title, symbol in
                indexRow(title, symbol: symbol)
                rowDivider
            }
            ForEach(Self.tickers, id: \.symbol) { item in
                ticker(item.title, symbol: item.symbol, quote: store.quote(symbol: item.symbol), showsPrice: item.showsPrice)
                rowDivider
            }
            ForEach(Self.metrics, id: \.symbol) { item in
                metric(item.title, symbol: item.symbol, isYield: item.isYield)
                rowDivider
            }
            sentimentRow
            if let dashboard = store.dashboard {
                rowDivider
                moreButton
                if showsMore {
                    ForEach(additionalQuotes(in: dashboard)) { entry in
                        rowDivider
                        ticker(marketCardTitle(symbol: entry.id, name: entry.stockName), symbol: entry.id, quote: entry.quote)
                    }
                    rowDivider
                    marketLink("中国市场结构", icon: "chevron.right", action: onOpenChinaMarketStructure)
                        .accessibilityIdentifier("research-china-market-structure")
                }
            }
        }
        .researchPanel()
    }

    private func additionalQuotes(in dashboard: MarketDashboard) -> [MarketDashboardQuoteEntry] {
        var seen = Set(ResearchHomeContent.chartSymbols + Self.tickers.map(\.symbol) + Self.metrics.map(\.symbol))
        return MarketRegion.allCases.flatMap { region in
            let regionalMetrics = dashboard.regions.first { $0.id == region.dashboardID }?.metricSymbols ?? []
            return (region.marketSymbols + regionalMetrics).compactMap { symbol in
                guard seen.insert(symbol).inserted else { return nil }
                if let quote = store.quote(symbol: symbol) { return .quote(quote) }
                return dashboard.unavailableQuote(symbol: symbol).map(MarketDashboardQuoteEntry.unavailable)
            }
        }
    }

    private var moreButton: some View {
        marketLink(showsMore ? "收起更多行情" : "更多行情", icon: showsMore ? "chevron.up" : "chevron.down") {
            showsMore.toggle()
        }
        .accessibilityIdentifier("research-more-market-indicators")
    }

    private func marketLink(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(ResearchDesign.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func indexRow(_ title: String, symbol: String) -> some View {
        let quote = store.quote(symbol: symbol)
        let value = price(quote)
        let change = quote?.marketDisplayFormattedPercent ?? "—"
        let tint = ResearchStyle.tint(quote)
        let layout = usesSingleColumn
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))

        return Button { onOpenQuote(symbol) } label: {
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(quoteStatus(quote, symbol: symbol))
                        .font(.caption2)
                        .foregroundStyle(ResearchStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ResearchSparkline(
                    values: store.listTrendValues(for: quote),
                    color: tint,
                    emptyLabel: trendStatus(symbol: symbol, hasQuote: quote != nil)
                )
                .equatable()
                .frame(width: usesSingleColumn ? nil : 72, height: sparklineHeight)
                VStack(alignment: usesSingleColumn ? .leading : .trailing, spacing: 3) {
                    Text(value)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .accessibilityLabel("价格 \(value)")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    changeBadge(change, tint: tint)
                        .accessibilityLabel("涨跌幅 \(change)")
                }
                .frame(minWidth: usesSingleColumn ? nil : 86, alignment: usesSingleColumn ? .leading : .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minHeight: 65)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("research-market-\(symbol)")
    }

    private func ticker(_ title: String, symbol: String, quote: MarketQuote?, showsPrice: Bool = true) -> some View {
        let change = quote?.marketDisplayFormattedPercent ?? "—"
        let unit = quote?.priceUnit ?? quote?.currency
        return snapshotRow(
            title, status: quoteStatus(quote, symbol: symbol),
            identifier: "research-market-\(symbol)", action: { onOpenQuote(symbol) }
        ) {
            if showsPrice {
                reading(quote.map(marketQuotePriceText) ?? "—", unit: unit == "%" ? nil : unit)
            }
            changeBadge(change, tint: ResearchStyle.tint(quote))
                .frame(width: changeColumnWidth, alignment: .trailing)
                .accessibilityLabel("涨跌幅 \(change)")
        }
    }

    private func metric(_ title: String, symbol: String, isYield: Bool) -> some View {
        let quote = store.quote(symbol: symbol)
        let status = quoteStatus(quote, symbol: symbol)
        let timestamp = quote?.marketAsOfTimestamp.map(marketShortTimestamp)
        let value = quote.map { String(format: isYield ? "%.2f%%" : "%.2f", $0.marketDisplayPrice) } ?? "—"
        let change = quote?.marketDisplayChangeValue.map {
            isYield ? String(format: "%+.0f bp", $0 * 100) : String(format: "%+.2f 点", $0)
        } ?? "—"

        return snapshotRow(
            title, status: [status, timestamp].compactMap { $0 }.joined(separator: " · "),
            identifier: "research-market-\(symbol)", action: { onOpenQuote(symbol) }
        ) {
            reading(value)
            changeBadge(change, tint: ResearchStyle.tint(quote))
                .frame(width: changeColumnWidth, alignment: .trailing)
                .accessibilityLabel("变动 \(change)")
        }
    }

    private var sentimentRow: some View {
        let sentiment = store.dashboard?.sentiment.flatMap { $0.available == false ? nil : $0 }
        let timestamp = marketISODate(sentiment?.updatedAt).map {
            marketShortTimestamp(Int64($0.timeIntervalSince1970 * 1000))
        }
        let status = [sentiment?.ratingZh ?? "暂无数据", timestamp, sentiment?.stale == true ? "待更新" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")

        return snapshotRow(
            "CNN 市场情绪", status: status,
            identifier: "research-sentiment", action: onOpenSentiment
        ) {
            VStack(alignment: .trailing, spacing: 5) {
                Text(sentiment.map { String(format: "%.1f / 100", $0.score) } ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                if let score = sentiment?.score, (0...100).contains(score) {
                    ProgressView(value: score, total: 100)
                        .tint(ResearchDesign.accent)
                        .frame(width: 72)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func snapshotRow<Readings: View>(
        _ title: String,
        status: String,
        identifier: String,
        action: @escaping () -> Void,
        @ViewBuilder readings: () -> Readings
    ) -> some View {
        let layout = usesSingleColumn
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))

        return Button(action: action) {
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(ResearchStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6, content: readings)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func reading(_ value: String, unit: String? = nil) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(ResearchStyle.muted)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func changeBadge(_ value: String, tint: Color) -> some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
    }

    private var rowDivider: some View {
        ResearchDesign.line.frame(height: 0.5).padding(.horizontal, 12)
    }

    private func price(_ quote: MarketQuote?) -> String {
        guard let quote else { return "—" }
        return quote.marketDisplayPrice.formatted(.number.precision(.fractionLength(2)))
    }

    private func quoteStatus(_ quote: MarketQuote?, symbol: String) -> String {
        quote?.researchStatus ?? store.dashboard?.unavailableQuote(symbol: symbol)?.quality.unavailableLabel ?? "暂无行情"
    }

    private func trendStatus(symbol: String, hasQuote: Bool) -> String {
        if store.isLoadingChart(symbol: symbol, range: .day) { return "走势加载中" }
        if store.chartError(symbol: symbol, range: .day) != nil { return "走势加载失败" }
        return store.chartSnapshot(symbol: symbol, range: .day) == nil && hasQuote
            ? "走势待加载" : "暂无走势"
    }
}

private struct ResearchIndustryPerformance: View {
    let store: MarketStore

    var body: some View {
        if let snapshot = store.ashareIndustryQuotes {
            let quotes = snapshot.rankedQuotes
            let leaders = quotes.filter { ($0.changePercent ?? 0) > 0 }.prefix(2)
            let laggards = quotes.reversed().filter { ($0.changePercent ?? 0) < 0 }.prefix(2)
            let unchanged = quotes.filter { $0.changePercent == 0 }.prefix(4)
            let scale = max(1, (Array(leaders) + laggards).compactMap(\.changePercent).map(abs).max() ?? 0)
            let changes = quotes.compactMap(\.changePercent)

            VStack(alignment: .leading, spacing: 10) {
                if !changes.isEmpty {
                    IndustryMarketBreadth(changes: changes)
                }
                if !leaders.isEmpty {
                    quoteGroup("领涨行业", quotes: leaders, scale: scale, tint: InvestmentDesign.gain)
                }
                if !laggards.isEmpty {
                    quoteGroup("领跌行业", quotes: laggards, scale: scale, tint: InvestmentDesign.loss)
                }
                if leaders.isEmpty && laggards.isEmpty {
                    if unchanged.isEmpty {
                        Text("行业涨跌幅暂缺")
                            .font(.footnote)
                            .foregroundStyle(ResearchStyle.muted)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .researchPanel()
                    } else {
                        quoteGroup("平盘行业", quotes: unchanged, scale: scale, tint: ResearchStyle.muted)
                    }
                }
                ResearchIndustryQuoteCaption(snapshot: snapshot)
                    .padding(.top, 2)
            }
        } else {
            ResearchIndustryQuoteStatus(store: store)
                .padding(.horizontal, 14)
                .researchPanel()
        }
    }

    private func quoteGroup(
        _ title: String, quotes: ArraySlice<MarketAShareIndustryQuote>, scale: Double, tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityAddTraits(.isHeader)
                .padding(.vertical, 9)
            ForEach(quotes) { quote in
                ResearchDesign.line.frame(height: 1)
                ResearchIndustryQuoteRow(quote: quote, scale: scale)
                    .frame(minHeight: 43)
            }
        }
        .padding(.horizontal, 14)
        .researchPanel()
    }
}

private struct IndustryMarketBreadth: View {
    let changes: [Double]

    var body: some View {
        let up = changes.filter { $0 > 0 }.count
        let flat = changes.filter { $0 == 0 }.count
        let down = changes.filter { $0 < 0 }.count

        VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    count("上涨", up)
                    Spacer(minLength: 12)
                    count("平盘", flat)
                    Spacer(minLength: 12)
                    count("下跌", down)
                }
                VStack(alignment: .leading, spacing: 4) {
                    count("上涨", up)
                    count("平盘", flat)
                    count("下跌", down)
                }
            }
            GeometryReader { geometry in
                let unit = geometry.size.width / CGFloat(changes.count)
                HStack(spacing: 0) {
                    InvestmentDesign.gain.frame(width: unit * CGFloat(up))
                    Color.secondary.opacity(0.35).frame(width: unit * CGFloat(flat))
                    InvestmentDesign.loss.frame(width: unit * CGFloat(down))
                }
                .clipShape(Capsule())
            }
            .frame(height: 5)
            .accessibilityHidden(true)
        }
        .padding(14)
        .researchPanel(fill: ResearchDesign.fill)
        .accessibilityElement(children: .combine)
    }

    private func count(_ title: String, _ value: Int) -> some View {
        Text("\(title) \(value)")
            .font(.footnote.weight(.semibold).monospacedDigit())
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ResearchIndustryRanking: View {
    let store: MarketStore
    @State private var gainFirst = true

    var body: some View {
        ScrollView {
            if let snapshot = store.ashareIndustryQuotes {
                let ranked = snapshot.rankedQuotes
                let rankedWithChange = ranked.prefix(snapshot.availableCount)
                let quotes = gainFirst ? ranked : Array(rankedWithChange.reversed()) + ranked.dropFirst(snapshot.availableCount)
                VStack(alignment: .leading, spacing: 10) {
                    let changes = ranked.compactMap(\.changePercent)
                    if !changes.isEmpty {
                        IndustryMarketBreadth(changes: changes)
                    }
                    Picker("排序", selection: $gainFirst) {
                        Text("涨幅优先").tag(true)
                        Text("跌幅优先").tag(false)
                    }
                    .pickerStyle(.segmented)

                    LazyVStack(spacing: 0) {
                        ForEach(quotes) { quote in
                            if quote.id != quotes.first?.id {
                                ResearchDesign.line.frame(height: 1)
                            }
                            ResearchIndustryQuoteRow(quote: quote, showsPrice: true)
                                .frame(minHeight: 47)
                        }
                    }
                    .padding(.horizontal, 12)
                    .researchPanel()
                    ResearchIndustryQuoteCaption(snapshot: snapshot)
                }
                .padding(ResearchDesign.inset)
                .padding(.bottom, 48)
            } else {
                ResearchIndustryQuoteStatus(store: store)
                    .padding(ResearchDesign.inset)
            }
        }
        .accessibilityIdentifier("ashare-industry-ranking")
    }
}

private struct ResearchIndustryQuoteCaption: View {
    let snapshot: MarketAShareIndustryQuotes

    var body: some View {
        let format = Date.FormatStyle(date: .numeric, time: .shortened,
                                      locale: Locale(identifier: "zh_CN"),
                                      timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .gmt)
        VStack(alignment: .leading, spacing: 3) {
            Text("\(snapshot.source) · 采集于 \(snapshot.collectionTime.formatted(format))（北京时间）")
            if snapshot.availableCount < snapshot.quotes.count {
                Text("涨跌幅暂缺 \(snapshot.quotes.count - snapshot.availableCount) 个行业")
            }
        }
        .font(.caption)
        .foregroundStyle(ResearchStyle.muted)
    }
}

private struct ResearchIndustryQuoteStatus: View {
    let store: MarketStore

    var body: some View {
        if store.industryQuotesUnavailable {
            Button {
                Task { await store.refreshAShareIndustryQuotes(force: true) }
            } label: {
                Label(store.isRefreshingIndustryQuotes ? "正在重试" : "行业行情暂不可用 · 点击重试",
                      systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .font(.footnote)
            .foregroundStyle(ResearchDesign.accent)
            .buttonStyle(.plain)
            .disabled(store.isRefreshingIndustryQuotes)
        } else {
            ProgressView("正在加载行业行情")
                .font(.footnote)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
    }
}

private struct ResearchIndustryQuoteRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let quote: MarketAShareIndustryQuote
    var scale: Double? = nil
    var showsPrice = false

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 10))
        let change = quote.changePercent ?? 0
        let tint = change > 0 ? InvestmentDesign.gain : change < 0 ? InvestmentDesign.loss : ResearchStyle.muted

        layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(quote.name).font(.subheadline.weight(.semibold))
                if showsPrice {
                    Text(quote.code).font(.caption.monospaced()).foregroundStyle(ResearchStyle.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let scale, !dynamicTypeSize.isAccessibilitySize {
                ResearchIndustryChangeBar(change: change, scale: scale, tint: tint)
                    .frame(width: 62, height: 14)
            }
            if showsPrice, let price = quote.price {
                Text(price.formatted(.number.precision(.fractionLength(2))))
                    .font(.footnote.monospacedDigit())
                    .accessibilityLabel("指数点位")
                    .accessibilityValue(price.formatted(.number.precision(.fractionLength(2))))
            }
            Text(quote.changePercent.map {
                ($0 / 100).formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false)))
            } ?? "涨跌幅暂缺")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? nil : 74, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("research-sector-\(quote.code)")
    }
}

private struct ResearchIndustryChangeBar: View {
    let change: Double
    let scale: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let halfWidth = geometry.size.width / 2
            let width = halfWidth * CGFloat(abs(change) / scale)
            ZStack {
                Capsule()
                    .fill(ResearchDesign.fill)
                    .frame(height: 6)
                Rectangle()
                    .fill(ResearchStyle.muted.opacity(0.35))
                    .frame(width: 1)
                Capsule()
                    .fill(tint)
                    .frame(width: width, height: 6)
                    .offset(x: change < 0 ? -width / 2 : width / 2)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }
}

extension MarketQuote {
    var researchStatus: String {
        if stale == true { return "报价待更新" }
        if isMiddayBreak { return "午间休市" }
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
    let closeLabel: String
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(InvestmentDesign.surface)
            .floatingSheetClose(closeLabel, action: onClose)
            .accessibilityAction(.escape) { onClose() }
    }
}

private struct ResearchStockQuotes: View {
    let entries: [MarketDashboardQuoteEntry]
    let region: MarketRegion
    let store: MarketStore
    let isActive: Bool
    let onOpen: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : dynamicTypeSize >= .xxLarge ? 2 : 3
        return Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6, alignment: .top), count: count)
    }

    private var extendedPriceSymbols: [String] {
        guard isActive, !store.isShowingCachedSnapshot else { return [] }
        return entries.compactMap { entry in
            guard let quote = entry.quote, quote.stale != true, quote.quality?.fallbackUsed != true,
                  includesExtendedHours(entry), quote.tradingSession == .closed || (quote.tradingSession.isExtended
                      && (quote.coreStockSessionPrice == nil || quote.hasDelayedSessionPrice)) else { return nil }
            return entry.id
        }
    }

    private func includesExtendedHours(_ entry: MarketDashboardQuoteEntry) -> Bool {
        region == .unitedStates || entry.quote?.listingCountryCode == "US"
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(entries) { entry in
                Button { onOpen(entry.id) } label: {
                    ResearchStockCard(
                        entry: entry,
                        region: region,
                        price: store.coreStockPrice(for: entry, includesExtendedHours: includesExtendedHours(entry))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("research-stock-\(entry.id)")
            }
        }
        .task(id: extendedPriceSymbols) {
            let symbols = extendedPriceSymbols
            guard !symbols.isEmpty else { return }
            while !Task.isCancelled {
                let needingChart = symbols.filter { symbol in
                    guard let quote = store.quote(symbol: symbol) else { return false }
                    guard quote.tradingSession == .closed else { return true }
                    guard let snapshot = store.chartSnapshot(symbol: symbol, range: .day), !snapshot.isRestored,
                          snapshot.chart.session == "closed" else { return true }
                    return snapshot.chart.latestStockExtendedTrade(for: quote) == nil
                }
                await store.preloadListCharts(symbols: needingChart)
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
        }
    }
}

private struct ResearchStockCard: View {
    let entry: MarketDashboardQuoteEntry
    let region: MarketRegion
    let price: MarketStockPrice?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var code: String {
        if region == .europe, entry.quote?.listingCountryCode == "US" {
            return "\(entry.stockCode) · 美股"
        }
        return entry.stockCode
    }

    private var status: String {
        if case let .unavailable(stock) = entry { return stock.quality.unavailableLabel }
        return entry.quote?.quality?.unavailableLabel ?? "报价待更新"
    }

    var body: some View {
        let tint = price?.changeColor ?? ResearchStyle.muted
        let amount = price.map {
            $0.amount.formatted(.number.precision(.fractionLength(marketPriceDigits($0.amount, symbol: entry.id))))
        }
        VStack(alignment: .leading, spacing: 3) {
            Text(code)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(entry.stockName)
                .font(.caption)
                .foregroundStyle(ResearchStyle.muted)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(amount ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityLabel(amount.map { "价格 \($0)" } ?? "价格暂缺")
                if let currency = price?.currency {
                    Text(currency)
                        .font(.caption2)
                        .foregroundStyle(ResearchStyle.muted)
                        .fixedSize()
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    changeText(tint: tint)
                    Spacer(minLength: 0)
                    statusText
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 2) {
                    changeText(tint: tint)
                    statusText
                }
            }
        }
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background(tint.opacity(price == nil ? 0.06 : 0.09), in: RoundedRectangle(cornerRadius: 11))
        .contentShape(Rectangle())
    }

    private func changeText(tint: Color) -> some View {
        let text = price.map { $0.changePercent.map(marketFormattedChangePercent) ?? "涨跌暂缺" } ?? "—"
        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .accessibilityLabel(price == nil ? "涨跌幅暂缺" : "涨跌幅 \(text)")
    }

    private var statusText: some View {
        Text(price?.label ?? status)
            .font(.caption2)
            .foregroundStyle(ResearchStyle.muted)
    }
}

struct MarketUnavailableQuoteRow: View {
    let quote: MarketDashboardQuoteEntry.Unavailable
    let store: MarketStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(quote.presentationName).font(.subheadline.weight(.semibold))
                    Text([quote.symbol, quote.currency].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text("当前报价暂缺")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let trade = store.lastSessionTrade(symbol: quote.symbol, asOf: quote.quality.asOfTimestamp) {
                MarketLastSessionTradeNote(trade: trade, symbol: quote.symbol)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
                ZStack {
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
                }
                .accessibilityHidden(true)
            } else {
                Text(emptyLabel)
                    .font(.caption2)
                    .foregroundStyle(ResearchStyle.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
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
