import SwiftUI

private enum MarketStockSort: String, CaseIterable, Identifiable {
    case featured = "默认顺序"
    case gainers = "涨幅优先"
    case losers = "跌幅优先"

    var id: Self { self }

    func orders(_ first: MarketDashboardQuoteEntry, before second: MarketDashboardQuoteEntry) -> Bool {
        switch (first.changeForRanking, second.changeForRanking) {
        case let (left?, right?): self == .gainers ? left > right : left < right
        case (_?, nil): true
        default: false
        }
    }
}

struct MarketStocksSheet: View {
    let store: MarketStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var priceWidth: CGFloat = 96
    @State private var region: MarketRegion
    @State private var query = ""
    @State private var sort: MarketStockSort = .featured
    @State private var selectedDetail: MarketDetailRoute?
    @FocusState private var searchFocused: Bool

    init(region: MarketRegion, store: MarketStore) {
        _region = State(initialValue: region)
        self.store = store
    }

    var body: some View {
        let entries = store.dashboard?.regionalStockEntries[region.dashboardID] ?? []
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = search.isEmpty ? entries : entries.filter { $0.matches(search) }
        let visible = sort == .featured ? matches : matches.sorted { sort.orders($0, before: $1) }
        let chartSymbols = entries.compactMap(\.quote).map(\.symbol)
        let isActive = scenePhase == .active && selectedDetail == nil

        VStack(spacing: 0) {
            titleBar
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    VStack(alignment: .leading, spacing: 12) {
                        regionPicker
                        searchField
                        if !entries.isEmpty, let quoteNotice {
                            Label(quoteNotice, systemImage: "clock")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if !entries.isEmpty {
                            listControls(visibleCount: visible.count, totalCount: entries.count)
                        }
                    }
                    .padding(.bottom, 12)

                    if visible.isEmpty {
                        emptyState(isSearching: !search.isEmpty && !entries.isEmpty)
                    } else {
                        Section {
                            ForEach(visible) { entry in
                                stockButton(entry, isActive: isActive)
                                Rectangle()
                                    .fill(ResearchDesign.line)
                                    .frame(height: 1)
                                    .accessibilityHidden(true)
                            }
                        } header: {
                            if dynamicTypeSize < .xxLarge {
                                columnHeaders
                            }
                        }
                        Text("分时曲线取自最近交易日，可包含盘前、盘后及夜盘。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 14)
                    }
                }
                .padding(.horizontal, ResearchDesign.inset)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.refresh() }
        }
        .background(InvestmentDesign.surface)
        .accessibilityIdentifier("market-stocks-sheet")
        .accessibilityAction(.escape) { dismiss() }
        .marketInstrumentDetailSheet(item: $selectedDetail, store: store)
        .task(id: isActive ? chartSymbols : []) {
            guard isActive, !chartSymbols.isEmpty else { return }
            while !Task.isCancelled {
                await store.preloadListCharts(symbols: chartSymbols)
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
            }
        }
    }

    private var quoteNotice: String? {
        if store.isShowingCachedSnapshot {
            return store.errorMessage == nil ? "正在显示缓存行情" : "更新失败，正在显示缓存行情"
        }
        return store.errorMessage == nil ? nil : "行情列表更新失败"
    }

    private var titleBar: some View {
        HStack(spacing: 12) {
            Text("全部股票")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭全部股票")
                .accessibilityIdentifier("detail-sheet-close")
        }
        .padding(.horizontal, ResearchDesign.inset)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var regionPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(MarketRegion.stockRegions) { item in
                        let isSelected = item == region
                        Button {
                            searchFocused = false
                            region = item
                        } label: {
                            Text(item.rawValue)
                                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? ResearchDesign.accent : .secondary)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 36)
                                .background(isSelected ? ResearchDesign.selection : Color.clear, in: Capsule())
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("market-stocks-region-\(item.dashboardID)")
                        .id(item)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: region, initial: true) { _, region in
                proxy.scrollTo(region, anchor: .center)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("股票市场")
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索名称或代码", text: $query)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
                .frame(minHeight: 44)
                .accessibilityIdentifier("market-stocks-search")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.leading, 12)
        .background(ResearchDesign.fill, in: RoundedRectangle(cornerRadius: 12))
    }

    private func listControls(visibleCount: Int, totalCount: Int) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.dashboard?.componentsMeta?.label ?? "核心股票")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(visibleCount == totalCount ? "\(totalCount) 家" : "\(visibleCount) / \(totalCount) 家")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Picker("排序", selection: $sort) {
                    ForEach(MarketStockSort.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
            } label: {
                Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ResearchDesign.accent)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 34)
                    .background(ResearchDesign.selection, in: RoundedRectangle(cornerRadius: 8))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("排序")
            .accessibilityValue(sort.rawValue)
            .accessibilityIdentifier("market-stocks-sort")
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 8) {
            Text("公司")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("分时")
                .frame(width: 52)
            Text("价格 / 涨跌幅").lineLimit(1)
                .frame(width: priceWidth, alignment: .trailing)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(ResearchDesign.fill, in: RoundedRectangle(cornerRadius: 8))
        .background(InvestmentDesign.surface)
        .accessibilityHidden(true)
    }

    private func stockButton(_ entry: MarketDashboardQuoteEntry, isActive: Bool) -> some View {
        Button {
            searchFocused = false
            selectedDetail = MarketDetailRoute(symbol: entry.id)
        } label: {
            MarketStockQuoteRow(entry: entry, store: store, priceWidth: priceWidth)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("market-quote-\(entry.id)")
        .accessibilityHint("打开个股详情")
        .task(id: isActive) {
            guard isActive, let quote = entry.quote else { return }
            await store.loadCompanyLogo(symbol: quote.symbol, name: quote.presentationName)
        }
    }

    private func emptyState(isSearching: Bool) -> some View {
        VStack(spacing: 10) {
            if !isSearching, store.dashboard == nil, store.errorMessage == nil || store.isLoading {
                ProgressView()
                Text("正在加载\(region.rawValue)股票")
            } else if isSearching {
                Image(systemName: "magnifyingglass")
                    .accessibilityHidden(true)
                Text("未找到匹配的股票")
            } else if store.errorMessage != nil {
                Text("股票行情暂时无法加载")
                Button("重新加载") { Task { await store.refresh() } }
                    .buttonStyle(.bordered)
                    .tint(ResearchDesign.accent)
                    .disabled(store.isRetrying)
            } else {
                Text("暂无\(region.rawValue)股票行情")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 144)
    }
}

private struct MarketStockQuoteRow: View {
    let entry: MarketDashboardQuoteEntry
    let store: MarketStore
    let priceWidth: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var lastTrade: MarketLastSessionTrade? {
        switch entry {
        case let .quote(quote): store.lastSessionTrade(for: quote)
        case let .unavailable(quote): store.lastSessionTrade(symbol: quote.symbol, asOf: quote.quality.asOfTimestamp)
        }
    }

    private var tint: Color {
        guard let change = entry.changeForRanking else { return .secondary }
        return change > 0 ? InvestmentDesign.gain : change < 0 ? InvestmentDesign.loss : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if dynamicTypeSize < .xxLarge {
                HStack(spacing: 8) {
                    identity
                    chart.frame(width: 52, height: 27)
                    price.frame(width: priceWidth, alignment: .trailing)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    identity
                    HStack(spacing: 12) {
                        price
                        chart.frame(height: 28)
                    }
                }
            }
            if let lastTrade {
                MarketLastSessionTradeNote(trade: lastTrade, symbol: entry.id)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var identity: some View {
        HStack(spacing: 8) {
            if let quote = entry.quote {
                MarketInstrumentLogo(quote: quote, path: store.companyLogoPaths[quote.symbol], size: 30)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "building.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(ResearchDesign.fill, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.stockName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(dynamicTypeSize >= .xxLarge ? nil : 2)
                Text(entry.stockCode)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chart: some View {
        let values = store.listTrendValues(for: entry.quote)
        return Group {
            if values.count >= 2 {
                Sparkline(values: values, color: tint, showsFill: false, showsLatestPoint: true)
            } else {
                Text("—")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var price: some View {
        VStack(alignment: dynamicTypeSize < .xxLarge ? .trailing : .leading, spacing: 3) {
            if let quote = entry.displayQuote {
                let priceText = [marketQuotePriceText(quote), quote.currency].compactMap { $0 }.joined(separator: " ")
                Text(priceText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .accessibilityLabel("价格 \(priceText)")
                Text(quote.marketDisplayFormattedPercent)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .accessibilityLabel("涨跌幅 \(quote.marketDisplayFormattedPercent)")
            } else {
                Text("—")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if let status = statusLabel {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(dynamicTypeSize < .xxLarge ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .monospacedDigit()
    }

    private var statusLabel: String? {
        if case let .unavailable(stock) = entry { return stock.quality.unavailableLabel }
        guard let quote = entry.displayQuote else { return entry.quote?.quality?.unavailableLabel ?? "报价暂缺" }
        if store.isShowingCachedSnapshot, quote.tradingSession == .regular { return quote.marketAsOfLabel }
        return quote.researchStatus
    }
}

private extension MarketDashboardQuoteEntry {
    var stockName: String {
        switch self {
        case let .quote(quote): quote.presentationName
        case let .unavailable(quote): quote.presentationName
        }
    }

    var stockCode: String { quote?.displayCode ?? id }

    var displayQuote: MarketQuote? {
        guard let quote, quote.stale != true, quote.marketDisplayPrice.isFinite,
              quote.marketDisplayPrice > 0 else { return nil }
        return quote
    }

    var changeForRanking: Double? {
        guard let quote = displayQuote, !quote.hasSuspiciousIndexMove,
              let change = quote.marketDisplayPercentValue, change.isFinite else { return nil }
        return change
    }

    func matches(_ search: String) -> Bool {
        let name: String?
        switch self {
        case let .quote(quote): name = quote.name
        case let .unavailable(quote): name = quote.name
        }
        return stockName.localizedStandardContains(search)
            || stockCode.localizedStandardContains(search)
            || id.localizedStandardContains(search)
            || name?.localizedStandardContains(search) == true
    }
}
