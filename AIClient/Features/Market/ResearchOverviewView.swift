import SwiftUI

private enum ResearchSection: String, CaseIterable {
    case overview = "概览", company = "公司", industry = "行业", macro = "宏观", viewpoints = "观点"
}

enum ResearchHomeContent {
    static let primaryMarkets = [("美国 · 标普500", "^GSPC"), ("中国 · 沪深300", "000300.SS"), ("日本 · 日经225", "^N225")]
    static let sectors = [("半导体", "NVDA"), ("软件云", "MSFT"), ("能源", "SHEL"), ("消费", "AMZN")]
    static var chartSymbols: [String] { primaryMarkets.map(\.1) + sectors.map(\.1) }
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
    let onOpenInstitutionResearch: () -> Void
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
                        store: store, researchStore: researchStore,
                        onOpenMacro: onOpenMacro, onOpenGlobalRanking: onOpenGlobalRanking,
                        onOpenInvestors: onOpenInvestors, onOpenInstitutionResearch: onOpenInstitutionResearch,
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
    @ObservedObject var researchStore: InstitutionResearchStore
    let onOpenMacro: () -> Void
    let onOpenGlobalRanking: () -> Void
    let onOpenInvestors: () -> Void
    let onOpenInstitutionResearch: () -> Void
    let onOpenIndustries: () -> Void
    let onOpenMarketQuotes: (MarketRegion) -> Void
    let onOpenMarketDetail: (String) -> Void
    let onOpenRetailInvestors: () -> Void
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @State private var selectedReport: InstitutionResearchItem?
    @Environment(\.scenePhase) private var scenePhase

    private let primaryMarkets = ResearchHomeContent.primaryMarkets
    // These are explicitly identified as representative companies, rather than invented sector indices.
    private let sectors = ResearchHomeContent.sectors
    private var chartSymbols: [String] { ResearchHomeContent.chartSymbols }
    private var reports: [InstitutionResearchItem] { Array((researchStore.payload?.items ?? []).prefix(2)) }

    var body: some View {
        ScrollView {
            if store.dashboard == nil && store.errorMessage == nil {
                ContentLoadingPlaceholder(title: "正在准备市场概览", rowCount: 5)
                    .accessibilityIdentifier("research-home-loading")
            } else {
            VStack(spacing: 8) {
                globalMarkets
                environment
                industries
                research
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
        .task(id: "\(rootTabIsActive):\(scenePhase):\(store.dashboard != nil)") {
            guard rootTabIsActive, scenePhase == .active, store.dashboard != nil else { return }
            while !Task.isCancelled {
                await store.preloadListCharts(symbols: chartSymbols)
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
            }
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await researchStore.load()
        }
        .appSheet(item: $selectedReport) { item in
            InstitutionResearchDetail(item: item)
                .overlay(alignment: .bottomTrailing) {
                    DetailSheetControls(closeLabel: "关闭", onClose: { selectedReport = nil })
                        .padding(12)
                }
        }
    }

    private var globalMarkets: some View {
        VStack(spacing: 7) {
            sectionHeading("全球市场", trailing: marketDate) { onOpenMarketQuotes(.unitedStates) }
            HStack(spacing: 7) {
                ForEach(primaryMarkets, id: \.1) { title, symbol in
                    marketCard(title: title, symbol: symbol)
                }
            }
            HStack(spacing: 0) {
                ticker("欧洲 STOXX50", symbol: "^STOXX50E", showsPrice: false)
                separator(height: 16)
                ticker("黄金", symbol: "GC1!", showsPrice: true)
                separator(height: 16)
                ticker("比特币", symbol: "BINANCE:BTCUSDT", showsPrice: true)
            }
            .padding(.vertical, 6)
            .background(ResearchStyle.canvas.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(8)
        .background(ResearchStyle.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func marketCard(title: String, symbol: String) -> some View {
        let quote = store.quote(symbol: symbol)
        let color = ResearchStyle.tint(quote)
        return Button { onOpenMarketDetail(symbol) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 10.5)).foregroundStyle(ResearchStyle.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(price(quote)).font(.system(size: 20, weight: .semibold))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    .foregroundStyle(.primary)
                Text(quote?.marketDisplayFormattedPercent ?? "—")
                    .font(.system(size: 14, weight: .medium)).monospacedDigit().foregroundStyle(color)
                ResearchSparkline(values: store.listTrendValues(for: quote), color: color, filled: true)
                    .frame(height: 27).padding(.top, 2)
                if quote?.stale == true {
                    Text("行情待更新").font(.system(size: 9)).foregroundStyle(ResearchStyle.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(ResearchStyle.canvas.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
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
            separator(height: 60)
            metric("美债10Y", symbol: "^TNX", yield: true)
            separator(height: 60)
            Button(action: onOpenRetailInvestors) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("市场情绪").font(.system(size: 11)).foregroundStyle(ResearchStyle.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(sentiment.map { String(format: "%.1f", $0.score) } ?? "—")
                            .font(.system(size: 20, weight: .semibold)).foregroundStyle(.primary)
                        Text("/100").font(.system(size: 13)).foregroundStyle(ResearchStyle.muted)
                    }.monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    GeometryReader { proxy in
                        Capsule().fill(ResearchStyle.canvas)
                            .overlay(alignment: .leading) {
                                if let score = sentiment?.score {
                                    Capsule().fill(InvestmentDesign.loss.opacity(0.75))
                                        .frame(width: proxy.size.width * min(max(score, 0), 100) / 100)
                                }
                            }
                    }.frame(height: 6)
                    Text(sentiment?.ratingZh ?? "暂无数据").font(.system(size: 10)).foregroundStyle(ResearchStyle.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("research-sentiment")
        }
        .padding(.vertical, 12)
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
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 11)).foregroundStyle(ResearchStyle.muted)
                Text(quote.map { String(format: yield ? "%.2f%%" : "%.2f", $0.marketDisplayPrice) } ?? "—")
                    .font(.system(size: 21, weight: .semibold)).foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(change.map { String(format: yield ? "%+.0f bp" : "%+.2f 点", $0 * (yield ? 100 : 1)) } ?? "—")
                    .font(.system(size: 13)).foregroundStyle(ResearchStyle.tint(quote))
            }
            .monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 17).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("research-market-\(symbol)")
    }

    private var industries: some View {
        VStack(spacing: 8) {
            sectionHeading("行业表现", trailing: "代表公司 · 全部", action: onOpenIndustries)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
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
        let color = ResearchStyle.tint(quote)
        return Button { onOpenMarketDetail(symbol) } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 3) {
                        Text(title).font(.system(size: 12)).foregroundStyle(.primary)
                        Text(symbol).font(.system(size: 8)).foregroundStyle(ResearchStyle.muted)
                    }
                    Text(quote?.marketDisplayFormattedPercent ?? "—")
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(color)
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                }
                ResearchSparkline(values: store.listTrendValues(for: quote), color: color, filled: false)
                    .frame(maxWidth: .infinity).frame(height: 30)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(color.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，代表公司\(symbol)，\(quote?.marketDisplayFormattedPercent ?? "暂无行情")")
        .accessibilityIdentifier("research-sector-\(symbol)")
    }

    private var research: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeading("研究动态", trailing: "全部", action: onOpenInstitutionResearch)
            if reports.isEmpty {
                VStack(spacing: 9) {
                    if researchStore.isLoading { ProgressView() }
                    Text(researchStore.isLoading ? "正在加载研究" : researchStore.errorMessage ?? "暂无研究动态")
                        .font(.subheadline).foregroundStyle(ResearchStyle.muted)
                    if !researchStore.isLoading {
                        Button("重新加载") { Task { await researchStore.load(force: true) } }
                            .font(.caption).tint(ResearchStyle.blue)
                    }
                }.frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ForEach(Array(reports.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { ResearchStyle.divider.frame(height: 0.5).padding(.horizontal, 5) }
                    Button { selectedReport = item } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("机构观点 · \(institutionChineseName(item.institutionShortName)) · \(reportDate(item.publishedOn))")
                                    .font(.system(size: 10)).foregroundStyle(ResearchStyle.muted).lineLimit(1)
                                Text(item.displayTitle).font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary).lineLimit(1)
                                Text(item.summary).font(.system(size: 11.5))
                                    .foregroundStyle(ResearchStyle.muted).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ResearchStyle.muted)
                        }
                        .padding(.horizontal, 5).padding(.vertical, 9).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("research-report-\(item.id)")
                }
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

    private func reportDate(_ value: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: value) else { return value }
        let display = DateFormatter()
        display.locale = Locale(identifier: "zh_CN")
        display.dateFormat = "M月d日"
        return display.string(from: date)
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

private struct ResearchSparkline: View {
    let values: [Double]
    let color: Color
    let filled: Bool

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            if points.count > 1 {
                if filled {
                    Path { path in
                        path.addLines(points)
                        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                        path.addLine(to: CGPoint(x: 0, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.12), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                }
                Path { $0.addLines(points) }.stroke(color, style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round))
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
