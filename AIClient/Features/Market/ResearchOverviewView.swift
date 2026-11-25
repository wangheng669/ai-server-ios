import SwiftUI

private enum ResearchTopic: String, Identifiable {
    case company = "公司", industry = "行业", macro = "宏观", viewpoints = "机构观点", sentiment = "市场情绪"

    case industryQuotes = "全部行业"

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
        }
    }
}

enum ResearchHomeContent {
    static let primaryMarkets = [("标普500", "^GSPC"), ("沪深300", "000300.SS"), ("日经225", "^N225")]
    static var chartSymbols: [String] { primaryMarkets.map(\.1) }

    static func stocks(in dashboard: MarketDashboard?, region: MarketRegion) -> [MarketQuote] {
        stockEntries(in: dashboard, region: region).compactMap(\.quote)
    }

    static func stockEntries(in dashboard: MarketDashboard?, region: MarketRegion) -> [MarketDashboardQuoteEntry] {
        Array((dashboard?.regionalStockEntries[region.dashboardID] ?? []).prefix(4))
    }

    static func afterHoursSymbols(for stocks: [MarketQuote]) -> [String] {
        stocks.filter {
            $0.tradingSession == .overnight || $0.tradingSession == .premarket || $0.tradingSession == .closed
        }.map(\.symbol)
    }
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
    let onOpenMarketQuotes: (MarketQuotesScope) -> Void
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
    private let stockRegions: [MarketRegion] = [.unitedStates, .china, .japan, .korea, .europe]
    private var stocks: [MarketQuote] {
        ResearchHomeContent.stocks(in: store.dashboard, region: stockRegion)
    }
    private var isLoadingMarket: Bool { store.dashboard == nil && store.errorMessage == nil }
    private var shouldRefreshCharts: Bool { rootTabIsActive && scenePhase == .active && presentedTopic == nil }
    private var shouldRefreshIndustryQuotes: Bool {
        rootTabIsActive && scenePhase == .active && (presentedTopic == nil || presentedTopic == .industryQuotes)
    }

    private var afterHoursSymbols: [String] {
        guard shouldRefreshCharts, stockRegion == .unitedStates else { return [] }
        return ResearchHomeContent.afterHoursSymbols(for: stocks)
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
            ResearchTopicSheet(title: topic.title, onClose: { presentedTopic = nil }) {
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
        .refreshable {
            async let dashboard: Void = store.refresh()
            async let industryQuotes: Void = store.refreshAShareIndustryQuotes(force: true)
            _ = await (dashboard, industryQuotes)
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
        VStack(spacing: 8) {
            sectionHeading(
                "主要指数", trailing: "全部行情",
                status: store.isShowingCachedSnapshot ? "缓存行情" : nil
            ) {
                onOpenMarketQuotes(.global)
            }
            ResearchGlobalMarketSnapshot(
                store: store,
                onOpenQuote: onOpenMarketDetail,
                onOpenSentiment: { presentedTopic = .sentiment }
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
            sectionHeading(store.dashboard?.componentsMeta?.label ?? "核心股票", trailing: "全部股票",
                           status: store.isShowingCachedSnapshot ? "缓存行情" : nil) {
                onOpenMarketQuotes(.region(stockRegion))
            }
            stockRegionSelector
            let entries = ResearchHomeContent.stockEntries(in: store.dashboard, region: stockRegion)
            if entries.isEmpty {
                Text("暂无股票行情")
                    .font(.subheadline).foregroundStyle(ResearchStyle.muted)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ResearchStockQuotes(
                    entries: entries,
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
            Button(action: action) {
                HStack(spacing: 4) {
                    Text(trailing).font(.footnote.weight(.medium))
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
            .accessibilityIdentifier("research-all-\(title)")
        }
    }
}

private struct ResearchGlobalMarketSnapshot: View {
    let store: MarketStore
    let onOpenQuote: (String) -> Void
    let onOpenSentiment: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var changeColumnWidth: CGFloat = 66
    @ScaledMetric(relativeTo: .caption2) private var sparklineHeight: CGFloat = 30

    private var usesSingleColumn: Bool { dynamicTypeSize >= .xxxLarge }

    var body: some View {
        VStack(spacing: 12) {
            primaryIndices

            section("指数、商品与加密资产") {
                ticker("欧洲 STOXX 50", symbol: "^STOXX50E", showsPrice: false)
                rowDivider
                ticker("黄金", symbol: "GC1!", showsPrice: true)
                rowDivider
                ticker("比特币", symbol: "BINANCE:BTCUSDT", showsPrice: true)
            }

            section("风险与利率") {
                metric("VIX", symbol: "^VIX", isYield: false)
                rowDivider
                metric("美债 10 年期", symbol: "^TNX", isYield: true)
                rowDivider
                sentimentRow
            }
        }
    }

    private var primaryIndices: some View {
        panel {
            ForEach(ResearchHomeContent.primaryMarkets, id: \.1) { title, symbol in
                if symbol != ResearchHomeContent.primaryMarkets.first?.1 { rowDivider }
                indexRow(title, symbol: symbol)
            }
        }
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
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .frame(minHeight: 65)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("research-market-\(symbol)")
    }

    private func ticker(_ title: String, symbol: String, showsPrice: Bool) -> some View {
        let quote = store.quote(symbol: symbol)
        let change = quote?.marketDisplayFormattedPercent ?? "—"
        return snapshotRow(
            title, status: quoteStatus(quote, symbol: symbol),
            identifier: "research-market-\(symbol)", action: { onOpenQuote(symbol) }
        ) {
            if showsPrice {
                reading(price(quote), unit: quote?.priceUnit ?? quote?.currency)
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

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            panel(content: content)
        }
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .researchPanel()
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
            } else {
                ResearchIndustryQuoteStatus(store: store)
                    .padding(ResearchDesign.inset)
            }
        }
        .refreshable { await store.refreshAShareIndustryQuotes(force: true) }
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

private extension MarketQuote {
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
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            ResearchSheetHeading(title: title, onClose: onClose)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(InvestmentDesign.surface)
    }
}

private struct ResearchStockQuotes: View {
    let entries: [MarketDashboardQuoteEntry]
    let region: MarketRegion
    let store: MarketStore
    let onOpen: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var quotes: [MarketQuote] { entries.compactMap(\.quote) }
    private var showsExtendedHours: Bool { region == .unitedStates }
    private var extendedSession: MarketTradingSession {
        quotes.contains { $0.tradingSession == .premarket } ? .premarket : .overnight
    }
    private var showsIndicative: Bool { quotes.contains(where: \.hasIndicativeOvernightPrice) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsExtendedHours {
                VStack(spacing: 8) {
                    ForEach(entries) { entry in
                        stockEntry(entry)
                            .researchPanel()
                    }
                }
                Text(StockSessionQuotes.sourceNote(indicative: showsIndicative))
                    .font(.caption)
                    .foregroundStyle(ResearchStyle.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        if entry.id != entries.first?.id {
                            ResearchDesign.line.frame(height: 1).padding(.horizontal, 12)
                        }
                        stockEntry(entry)
                    }
                }
                .researchPanel()
            }
        }
    }

    @ViewBuilder
    private func stockEntry(_ entry: MarketDashboardQuoteEntry) -> some View {
        switch entry {
        case let .quote(quote):
            stockRow(quote)
        case let .unavailable(stock):
            Button { onOpen(stock.symbol) } label: {
                MarketUnavailableQuoteRow(quote: stock, store: store)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("research-stock-\(stock.symbol)")
        }
    }

    private func stockRow(_ quote: MarketQuote) -> some View {
        let active = quote.stale != true && !store.isShowingCachedSnapshot
        let lastTrade = store.lastSessionTrade(for: quote)
        let subtitle = stockSubtitle(quote, active: active, hasLastTrade: lastTrade != nil)
        return Button { onOpen(quote.symbol) } label: {
            VStack(alignment: .leading, spacing: 6) {
                if showsExtendedHours {
                    HStack(spacing: 8) {
                        Text(quote.presentationName).font(.subheadline.weight(.semibold))
                        Text([subtitle, quote.currency].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ResearchStyle.muted)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 5)
                    sessionPrices(quote, active: active)
                } else {
                    regularPrice(quote, subtitle: subtitle)
                }
                if let lastTrade {
                    MarketLastSessionTradeNote(trade: lastTrade, symbol: quote.symbol)
                        .padding(.horizontal, showsExtendedHours ? 5 : 0)
                }
            }
            .monospacedDigit()
            .padding(.horizontal, showsExtendedHours ? 8 : 12)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("research-stock-\(quote.symbol)")
    }

    private func sessionPrices(_ quote: MarketQuote, active: Bool) -> some View {
        let sessions = store.stockSessionQuotes(for: quote, chartSymbol: quote.symbol,
                                                extendedSession: extendedSession, isCurrent: active)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 2))
        return layout {
            ForEach(sessions.columns) { column in
                StockSessionPriceCell(column: column, symbol: quote.symbol, muted: ResearchStyle.muted, showsTitle: true)
            }
        }
        .background(ResearchDesign.fill, in: RoundedRectangle(cornerRadius: 8))
    }

    private func regularPrice(_ quote: MarketQuote, subtitle: String) -> some View {
        let price = quote.stale == true ? "—" : quote.marketDisplayPrice.formatted(
            .number.precision(.fractionLength(marketPriceDigits(quote.marketDisplayPrice, symbol: quote.symbol)))
        )
        let change = quote.stale == true ? "—" : quote.marketDisplayFormattedPercent
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(quote.presentationName).font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(ResearchStyle.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                Text([price, quote.currency].compactMap { $0 }.joined(separator: " "))
                    .font(.subheadline.weight(.semibold))
                    .minimumScaleFactor(0.75)
                Text(change)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ResearchStyle.tint(quote))
            }
        }
    }

    private func stockSubtitle(_ quote: MarketQuote, active: Bool, hasLastTrade: Bool) -> String {
        let code = region == .europe && quote.listingCountryCode == "US" ? "\(quote.displayCode) · 美股" : quote.displayCode
        if hasLastTrade { return code }
        if !active { return "\(code) · 待更新" }
        return showsExtendedHours ? code : "\(code)\n\(quote.researchStatus)"
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
