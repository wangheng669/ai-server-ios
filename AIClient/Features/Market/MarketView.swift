import Charts
import SwiftUI
import UIKit

private enum MarketStyle {
    static let canvas = InvestmentDesign.surface
    static let surface = InvestmentDesign.surface
    static let secondarySurface = InvestmentDesign.secondarySurface
    static let cardSurface = InvestmentDesign.secondarySurface
    static let cardBorder = InvestmentDesign.divider
    static let divider = InvestmentDesign.divider
    static let gain = InvestmentDesign.gain
    static let loss = InvestmentDesign.loss
    static let accent = InvestmentDesign.accent
    static let live = Color(red: 0.08, green: 0.72, blue: 0.40)
    static let purple = accent
    static let pageSpacing: CGFloat = 12
    static let pageInset: CGFloat = 16
    static let cornerRadius: CGFloat = 18
}

func marketRunWithLimitedConcurrency<Element>(
    _ elements: [Element],
    maximumConcurrentRequests: Int = 3,
    operation: @escaping @Sendable (Element) async -> Void
) async {
    guard !elements.isEmpty else { return }
    let limit = min(max(maximumConcurrentRequests, 1), elements.count)
    await withTaskGroup(of: Void.self) { group in
        var nextIndex = 0
        for _ in 0..<limit {
            let element = elements[nextIndex]
            nextIndex += 1
            group.addTask { await operation(element) }
        }

        while await group.next() != nil {
            guard !Task.isCancelled else {
                group.cancelAll()
                return
            }
            guard nextIndex < elements.count else { continue }
            let element = elements[nextIndex]
            nextIndex += 1
            group.addTask { await operation(element) }
        }
    }
}

private struct MarketDetailRoute: Identifiable, Equatable {
    let symbol: String
    var id: String { symbol }
}

struct MarketView: View {
    @Binding private var showsDetail: Bool
    private let store: MarketStore
    private let sentimentStore: RetailSentimentStore
    private let onCompactHeaderChange: (Bool) -> Void
    @State private var globalRankingStore: GlobalRankingStore
    @State private var holdingsStore: FamousHoldingsStore
    @StateObject private var institutionResearchStore: InstitutionResearchStore
    @State private var investorShowsDetail = false
    @State private var retailInvestorShowsDetail = false
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
    @State private var pendingMarketDetail: MarketDetailRoute?
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

    @MainActor
    init(
        store: MarketStore,
        sentimentStore: RetailSentimentStore,
        showsDetail: Binding<Bool> = .constant(false),
        onCompactHeaderChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.store = store
        self.sentimentStore = sentimentStore
        self.onCompactHeaderChange = onCompactHeaderChange
        _showsDetail = showsDetail
        _globalRankingStore = State(initialValue: GlobalRankingStore())
        _holdingsStore = State(initialValue: FamousHoldingsStore())
        _institutionResearchStore = StateObject(wrappedValue: InstitutionResearchStore())
    }

    @MainActor
    init(
        showsDetail: Binding<Bool> = .constant(false),
        onCompactHeaderChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.init(
            store: MarketStore(),
            sentimentStore: RetailSentimentStore(),
            showsDetail: showsDetail,
            onCompactHeaderChange: onCompactHeaderChange
        )
    }

    var body: some View {
        MarketHomeView(
            store: store,
            sentimentStore: sentimentStore,
            onCompactHeaderChange: onCompactHeaderChange,
            onOpenMacro: {
                showsMacro = true
                showsDetail = true
            },
            rankingStore: globalRankingStore,
            onOpenGlobalRanking: {
                showsGlobalRanking = true
                showsDetail = true
            },
            holdingsStore: holdingsStore,
            researchStore: institutionResearchStore,
            onOpenInvestors: {
                showsInvestors = true
                showsDetail = true
            },
            onOpenInstitutionResearch: {
                showsInstitutionResearch = true
                showsDetail = true
            },
            onOpenIndustries: {
                showsIndustries = true
                showsDetail = true
            },
            onOpenMarketQuotes: { region in
                selectedMarketQuotesRegion = region
                showsDetail = true
            },
            onOpenMarketDetail: { symbol in
                selectedDetail = MarketDetailRoute(symbol: symbol)
                showsDetail = true
            },
            onOpenChinaMarketStructure: {
                showsChinaMarketStructure = true
                showsDetail = true
            },
            onOpenRetailInvestors: {
                showsRetailInvestors = true
                showsDetail = true
            }
        )
        .sheet(isPresented: $showsRetailInvestors, onDismiss: {
            retailInvestorShowsDetail = false
            showsDetail = false
        }) {
            RetailInvestorView(
                store: sentimentStore,
                marketStore: store,
                showsDetail: $retailInvestorShowsDetail,
                displaysSheetChrome: true
            )
            .presentationDetents([.fraction(0.52), .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationBackground(InvestmentDesign.surface)
            .presentationContentInteraction(.resizes)
        }
        .sheet(isPresented: $showsInvestors, onDismiss: {
            investorShowsDetail = false
            showsDetail = false
        }) {
            NavigationStack {
                FamousHoldingsView(store: holdingsStore, showsDetail: $investorShowsDetail)
            }
            .presentationDetents([.fraction(0.82), .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationBackground(InvestmentDesign.canvas)
            .presentationContentInteraction(.resizes)
        }
        .sheet(isPresented: $showsInstitutionResearch, onDismiss: {
            showsDetail = false
        }) {
            NavigationStack {
                InstitutionResearchView(store: institutionResearchStore)
            }
            .presentationDetents([.fraction(0.82), .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationBackground(InvestmentDesign.canvas)
            .presentationContentInteraction(.resizes)
        }
        .sheet(isPresented: $showsIndustries, onDismiss: {
            showsDetail = false
        }) {
            NavigationStack {
                IndustryPanoramaView()
            }
            .presentationDetents([.fraction(0.82), .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationBackground(InvestmentDesign.canvas)
            .presentationContentInteraction(.resizes)
        }
        .sheet(isPresented: $showsGlobalRanking, onDismiss: {
            showsDetail = false
        }) {
            NavigationStack {
                CountryGDPRankingView(store: globalRankingStore)
            }
            .presentationDetents([.fraction(0.82), .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationBackground(InvestmentDesign.surface)
            .presentationContentInteraction(.resizes)
        }
        .sheet(isPresented: $showsMacro, onDismiss: {
            showsDetail = false
        }) {
            NavigationStack {
                ChinaMacroView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationBackground(InvestmentDesign.canvas)
        }
        .sheet(item: $selectedMarketQuotesRegion, onDismiss: {
            if let route = pendingMarketDetail {
                pendingMarketDetail = nil
                selectedDetail = route
            } else {
                showsDetail = false
            }
        }) { region in
            MarketQuotesSheet(region: region, store: store) { symbol in
                pendingMarketDetail = MarketDetailRoute(symbol: symbol)
                selectedMarketQuotesRegion = nil
            }
            .presentationDetents([.fraction(0.72), .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationBackground(MarketStyle.surface)
            .presentationContentInteraction(.resizes)
        }
        .sheet(isPresented: $showsChinaMarketStructure, onDismiss: {
            showsDetail = false
        }) {
            ChinaMarketStructureSheet(structure: store.dashboard?.marketStructure)
                .presentationDetents([.fraction(0.62), .large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
                .presentationBackground(MarketStyle.surface)
                .presentationContentInteraction(.resizes)
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
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationBackground(MarketStyle.surface)
            .presentationContentInteraction(.resizes)
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await sentimentStore.preload(marketStore: store)
            await store.runUpdates()
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await sentimentStore.preload(marketStore: store)
            await sentimentStore.load(marketStore: store)
            async let hongKong: Void = sentimentStore.loadDetails(for: .hongKong)
            async let korea: Void = sentimentStore.loadDetails(for: .korea)
            async let unitedStates: Void = sentimentStore.loadDetails(for: .unitedStates)
            _ = await (hongKong, korea, unitedStates)
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
        .onAppear {
            showsDetail = selectedDetail != nil || showsMacro ||
                selectedMarketQuotesRegion != nil || showsGlobalRanking || showsInvestors ||
                showsInstitutionResearch || showsIndustries || showsChinaMarketStructure ||
                showsRetailInvestors
        }
        .onDisappear { showsDetail = false }
    }
}

private struct MarketHomeView: View {
    let store: MarketStore
    let sentimentStore: RetailSentimentStore
    let onCompactHeaderChange: (Bool) -> Void
    let onOpenMacro: () -> Void
    let rankingStore: GlobalRankingStore
    let onOpenGlobalRanking: () -> Void
    let holdingsStore: FamousHoldingsStore
    let researchStore: InstitutionResearchStore
    let onOpenInvestors: () -> Void
    let onOpenInstitutionResearch: () -> Void
    let onOpenIndustries: () -> Void
    let onOpenMarketQuotes: (MarketRegion) -> Void
    let onOpenMarketDetail: (String) -> Void
    let onOpenChinaMarketStructure: () -> Void
    let onOpenRetailInvestors: () -> Void
    @State private var macroStore = ChinaMacroStore()
    @Environment(\.rootTabIsActive) private var rootTabIsActive
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
    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        VStack(spacing: 0) {
                            MarketRegionPicker(store: store, selection: $selectedMarket)
                                .padding(.horizontal, MarketStyle.pageInset)
                                .padding(.top, 7)
                                .padding(.bottom, 2)

                            MarketTerminalHero(
                                store: store,
                                region: selectedMarket,
                                onOpenMarketQuotes: { onOpenMarketQuotes(selectedMarket) },
                                onOpenVIXHistory: { onOpenMarketDetail("^VIX") },
                                onOpenChinaMarketStructure: onOpenChinaMarketStructure
                            )
                            .simultaneousGesture(regionSwipeGesture)

                            if let error = regionalHealthMessage {
                                MarketErrorBanner(
                                    message: error,
                                    isRetrying: store.isRetrying
                                ) { await store.refresh() }
                                .padding(.horizontal, MarketStyle.pageInset)
                                .padding(.bottom, 8)
                            }

                            MarketRetailInvestorStrip(
                                store: sentimentStore,
                                onOpen: onOpenRetailInvestors
                            )

                            MarketEditorialFeed(
                                marketStore: store,
                                rankingStore: rankingStore,
                                holdingsStore: holdingsStore,
                                researchStore: researchStore,
                                macroStore: macroStore,
                                onOpenInstitutionResearch: onOpenInstitutionResearch,
                                onOpenIndustries: onOpenIndustries,
                                onOpenGlobalRanking: onOpenGlobalRanking,
                                onOpenInvestors: onOpenInvestors,
                                onOpenMacro: onOpenMacro
                            )
                            .id("market-research-entry-grid")
                        }
                        .padding(.bottom, 24)
                        .background(MarketStyle.canvas)
                    }
                    .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .top)
                    .background(MarketStyle.canvas)
                }
                .background(MarketStyle.canvas)
                .scrollIndicators(.hidden)
                .onAppear { onCompactHeaderChange(false) }
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--market-research-entries-preview") {
                        try? await Task.sleep(for: .seconds(2))
                        proxy.scrollTo("market-research-entry-grid", anchor: .center)
                    }
                    #endif
                }
                .task(id: rootTabIsActive) {
                    guard rootTabIsActive else { return }
                    async let research: Void = researchStore.load()
                    async let macro: Void = macroStore.load()
                    _ = await (research, macro)
                }
            }
            .overlay(alignment: .top) {
                MarketStyle.canvas
                    .frame(height: viewport.safeAreaInsets.top)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
        }
    }

    private var regionalHealthMessage: String? {
        let relevant = store.healthIssues.filter { selectedMarket.relevantHealthSymbols.contains($0.symbol) }
        if let summary = marketHealthSummary(relevant) { return summary }
        return store.healthIssues.isEmpty ? store.errorMessage : nil
    }

    private var regionSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                if let offset = marketRegionSwipeOffset(
                    horizontalDistance: value.translation.width,
                    verticalDistance: value.translation.height,
                    projectedHorizontalDistance: value.predictedEndTranslation.width
                ), let destination = marketAdjacentRegion(from: selectedMarket, offset: offset) {
                    selectedMarket = destination
                    UIAccessibility.post(notification: .announcement, argument: destination.rawValue)
                }
            }
    }
}

private struct MarketPageHeader: View {
    let store: MarketStore

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("市场脉搏")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("全球行情、情绪与研究线索")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 7, height: 7)
                Text(statusLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(MarketStyle.cardSurface, in: Capsule())
            .overlay {
                Capsule().stroke(MarketStyle.cardBorder, lineWidth: 0.8)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("市场脉搏，\(statusLabel)")
    }

    private var statusLabel: String {
        if store.isShowingCachedSnapshot { return "缓存行情" }
        if store.dashboard == nil { return "正在连接" }
        return store.hasOpenMarket ? "市场交易中" : "行情已同步"
    }

    private var statusTint: Color {
        if store.isShowingCachedSnapshot { return InvestmentDesign.warning }
        return store.dashboard == nil ? .secondary : MarketStyle.live
    }
}

private struct MarketSectionHeading: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct MarketResearchEntryGrid: View {
    let onOpenInstitutionResearch: () -> Void
    let onOpenIndustries: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            MarketResearchEntryCard(
                title: "机构研究",
                subtitle: "公开观点与原文",
                systemImage: "doc.text.magnifyingglass",
                action: onOpenInstitutionResearch
            )
            MarketResearchEntryCard(
                title: "产业全景",
                subtitle: "产业链与景气跟踪",
                systemImage: "square.3.layers.3d",
                action: onOpenIndustries
            )
        }
    }
}

private struct MarketResearchEntryCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MarketStyle.accent)
                        .frame(width: 34, height: 34)
                        .background(MarketStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
            .background(MarketStyle.cardSurface, in: RoundedRectangle(cornerRadius: MarketStyle.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MarketStyle.cornerRadius, style: .continuous)
                    .stroke(MarketStyle.cardBorder, lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: MarketStyle.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
        .accessibilityHint("打开详情")
    }
}

private struct GlobalRankingSummaryCard: View {
    let store: GlobalRankingStore
    let onOpen: () -> Void
    @Environment(\.rootTabIsActive) private var rootTabIsActive

    private var countryLeader: CountryGDP? { store.countryGDP?.countries.first }
    private var assetLeader: GlobalAsset? { store.globalAssets?.assets.first }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Label("全球排行", systemImage: "chart.bar.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    HStack(spacing: 3) {
                        Text("查看全部")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(MarketStyle.accent)
                }

                HStack(spacing: 0) {
                    summaryColumn(
                        title: "最大经济体",
                        name: countryLeader?.localizedName,
                        value: countryLeader.map { "$" + CountryGDPFormat.ranking($0.gdpCurrentUSD) },
                        badge: countryLeader.map { "GDP #\($0.rank)" },
                        failed: store.countryGDPLoadFailed
                    )

                    Rectangle()
                        .fill(MarketStyle.divider)
                        .frame(width: 0.5, height: 52)
                        .padding(.horizontal, 12)

                    summaryColumn(
                        title: "最大资产",
                        name: assetLeader?.name,
                        value: assetLeader.map { GlobalAssetsFormat.marketCap($0.marketCapUSD) },
                        badge: assetLeader.map { "资产 #\($0.rank)" },
                        failed: store.globalAssetsLoadFailed
                    )
                }

                Text("国家 GDP · 全球资产市值排行")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MarketStyle.cardSurface, in: RoundedRectangle(cornerRadius: MarketStyle.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MarketStyle.cornerRadius, style: .continuous)
                    .stroke(MarketStyle.cardBorder, lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: MarketStyle.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("全球排行")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("打开国家 GDP 与全球资产排行")
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await store.loadSummary()
        }
    }

    private func summaryColumn(
        title: String,
        name: String?,
        value: String?,
        badge: String?,
        failed: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(name ?? (failed ? "暂不可用" : "加载中"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            HStack(spacing: 7) {
                Text(value ?? "—")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if let badge {
                    Text(badge)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(MarketStyle.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(MarketStyle.accent.opacity(0.10), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityValue: String {
        let country = countryLeader.map { "最大经济体\($0.localizedName)" } ?? "最大经济体数据加载中"
        let asset = assetLeader.map { "最大资产\($0.name)" } ?? "最大资产数据加载中"
        return "\(country)，\(asset)"
    }
}

private struct FamousInvestorsSummaryCard: View {
    let store: FamousHoldingsStore
    let onOpen: () -> Void
    @Environment(\.rootTabIsActive) private var rootTabIsActive

    private var managers: [FamousHoldingsManager] {
        (store.holdings?.managers ?? []).sorted { managerPriority($0.key) < managerPriority($1.key) }
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Label("知名投资人", systemImage: "person.2.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    HStack(spacing: 3) {
                        Text("查看全部")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(MarketStyle.accent)
                }

                if managers.isEmpty {
                    HStack(spacing: 8) {
                        if store.isLoading {
                            ProgressView().controlSize(.small)
                        }
                        Text(store.errorMessage == nil ? "正在读取最新持仓披露" : "投资人持仓暂不可用")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 42)
                } else {
                    HStack(spacing: 12) {
                        HStack(spacing: -9) {
                            ForEach(Array(managers.prefix(3).enumerated()), id: \.element.key) { index, manager in
                                InvestorPortraitImage(manager: manager, contentMode: .fill)
                                    .frame(width: 38, height: 38)
                                    .clipShape(Circle())
                                    .overlay {
                                        Circle().stroke(MarketStyle.cardSurface, lineWidth: 2)
                                    }
                                    .zIndex(Double(managers.count - index))
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(compactSummaryText)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("SEC 13F 最新披露")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.trailing, 104)
                }

                Text("公开 13F 持仓 · 增减仓与组合变化")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MarketStyle.cardSurface, in: RoundedRectangle(cornerRadius: MarketStyle.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MarketStyle.cornerRadius, style: .continuous)
                    .stroke(MarketStyle.cardBorder, lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: MarketStyle.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("知名投资人")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("打开知名投资人的公开持仓")
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await store.load()
        }
    }

    private var summaryText: String {
        guard let holdings = store.holdings else { return "" }
        return "\(holdings.managers.count) 位投资人 · \(holdings.periodLabel)"
    }

    private var compactSummaryText: String {
        guard let holdings = store.holdings else { return "" }
        return "\(holdings.managers.count) 位 · \(holdings.periodLabel)"
    }

    private var accessibilityValue: String {
        guard !managers.isEmpty else { return store.errorMessage == nil ? "数据加载中" : "数据暂不可用" }
        return "\(summaryText)，\(managers.prefix(3).map(\.displayName).joined(separator: "、"))"
    }
}

private struct MarketHomeResearchRow: Identifiable {
    let source: String
    let date: String
    let title: String
    let summary: String?
    let target: String?

    var id: String { "\(source)-\(title)" }
}

func marketCompactResearchDate(_ value: String) -> String {
    let parts = value.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return value }
    return "\(parts[1])月\(parts[2])日"
}

private struct MarketEditorialFeed: View {
    let marketStore: MarketStore
    let rankingStore: GlobalRankingStore
    let holdingsStore: FamousHoldingsStore
    let researchStore: InstitutionResearchStore
    let macroStore: ChinaMacroStore
    let onOpenInstitutionResearch: () -> Void
    let onOpenIndustries: () -> Void
    let onOpenGlobalRanking: () -> Void
    let onOpenInvestors: () -> Void
    let onOpenMacro: () -> Void

    private let industries: [(title: String, symbol: String)] = [
        ("半导体", "NVDA"),
        ("软件与云", "MSFT"),
        ("消费电子", "AAPL")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VolatilityResearchSection()

            VStack(alignment: .leading, spacing: 8) {
                MarketSectionHeading("机构观点")
                researchFeed
            }

            VStack(alignment: .leading, spacing: 8) {
                MarketSectionHeading("行业机会")
                industryFeed
            }

            VStack(alignment: .leading, spacing: 8) {
                MarketSectionHeading("宏观观察")
                macroFeed
            }
        }
        .padding(.horizontal, MarketStyle.pageInset)
        .padding(.top, 14)
    }

    private var researchFeed: some View {
        Button(action: onOpenInstitutionResearch) {
            VStack(spacing: 0) {
                ForEach(Array(researchRows.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.source.uppercased()) · \(item.date)")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)

                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(item.title)
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if let target = item.target {
                                Text(target)
                                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                        }

                        if let summary = item.summary {
                            Text(summary)
                                .font(.system(size: 10.5, weight: .regular))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 5)

                    if index < researchRows.count - 1 { hairline }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(MarketStyle.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MarketStyle.cardBorder, lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("机构研究")
        .accessibilityHint("打开全部机构研究")
    }

    private var researchRows: [MarketHomeResearchRow] {
        let items = researchStore.payload?.items ?? []
        var selected: [InstitutionResearchItem] = []
        if let lead = items.first(where: { $0.presentation == .lead }) {
            selected.append(lead)
        }
        if let revision = items.first(where: { $0.presentation == .revision && $0.id != selected.first?.id }) {
            selected.append(revision)
        }
        for item in items where selected.count < 2 && !selected.contains(where: { $0.id == item.id }) {
            selected.append(item)
        }
        let rows = selected.prefix(2).map { item in
            MarketHomeResearchRow(
                source: item.institution,
                date: marketCompactResearchDate(item.publishedOn),
                title: item.title,
                summary: item.targetRevision == nil ? item.summary : nil,
                target: item.targetRevision.map { "标普目标 \($0.previousValue) → \($0.currentValue)" }
            )
        }
        if !rows.isEmpty { return rows }
        return [
            MarketHomeResearchRow(
                source: "Morgan Stanley",
                date: "7月22日",
                title: "更多股票加入牛市",
                summary: "市场领导力正在扩散，周期与价值板块接力",
                target: nil
            ),
            MarketHomeResearchRow(
                source: "Goldman Sachs",
                date: "5月28日",
                title: "盈利增长推动美股上行",
                summary: nil,
                target: "标普目标 7,600 → 8,000"
            )
        ]
    }

    private var industryFeed: some View {
        Button(action: onOpenIndustries) {
            VStack(spacing: 0) {
                ForEach(Array(industries.enumerated()), id: \.element.symbol) { index, industry in
                    industryRow(title: industry.title, symbol: industry.symbol)
                    if index < industries.count - 1 { hairline }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(MarketStyle.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MarketStyle.cardBorder, lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("行业机会")
        .accessibilityHint("打开产业链与景气详情")
    }

    private func industryRow(title: String, symbol: String) -> some View {
        let quote = marketStore.quote(symbol: symbol)
        let tint = quoteTint(quote)
        return HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .frame(width: 76, alignment: .leading)
            Sparkline(values: marketStore.trendValues(for: quote), color: tint, showsFill: false)
                .frame(width: 66, height: 23)
            Text(industryStatus(quote))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(quote?.formattedPercent ?? "—")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .frame(height: 34)
    }

    private func industryStatus(_ quote: MarketQuote?) -> String {
        guard let change = quote?.marketDisplayPercentValue else { return "等待行情" }
        if change >= 1 { return "景气上行" }
        if change >= 0 { return "温和复苏" }
        if change > -1 { return "库存改善" }
        return "震荡调整"
    }

    private var rankingFeed: some View {
        Button(action: onOpenGlobalRanking) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 5) {
                    let countries = Array((rankingStore.countryGDP?.countries ?? []).prefix(2))
                    if countries.isEmpty {
                        rankingPlaceholder(rank: 1, name: "美国", badge: "GDP #1", value: "读取中")
                        rankingPlaceholder(rank: 2, name: "中国", badge: "GDP #2", value: "读取中")
                    } else {
                        ForEach(countries) { country in
                            rankingPlaceholder(
                                rank: country.rank,
                                name: country.localizedName,
                                badge: "GDP #\(country.rank)",
                                value: CountryGDPFormat.ranking(country.gdpCurrentUSD)
                            )
                        }
                    }
                }

                Rectangle()
                    .fill(MarketStyle.divider)
                    .frame(width: 0.5, height: 82)

                VStack(spacing: 5) {
                    let assets = Array((rankingStore.globalAssets?.assets ?? []).prefix(2))
                    if assets.isEmpty {
                        rankingPlaceholder(rank: 1, name: "黄金", badge: "资产 #1", value: "读取中")
                        rankingPlaceholder(rank: 2, name: "美债", badge: "资产 #2", value: "读取中")
                    } else {
                        ForEach(assets) { asset in
                            rankingPlaceholder(
                                rank: asset.rank,
                                name: asset.name,
                                badge: "资产 #\(asset.rank)",
                                value: GlobalAssetsFormat.marketCap(asset.marketCapUSD)
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { hairline }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("全球经济与资产排行")
        .accessibilityHint("打开完整排行")
    }

    private func rankingPlaceholder(rank: Int, name: String, badge: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(String(format: "%02d", rank))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text(name)
                        .font(.system(size: 13.5, weight: .bold))
                        .lineLimit(1)
                    Text(badge)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(value)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var investorsFeed: some View {
        Button(action: onOpenInvestors) {
            HStack(spacing: 12) {
                if managers.isEmpty {
                    HStack(spacing: -7) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(Color.secondary.opacity(0.12))
                                .frame(width: 39, height: 39)
                                .overlay { Circle().stroke(MarketStyle.surface, lineWidth: 2) }
                        }
                    }
                } else {
                    HStack(spacing: -7) {
                        ForEach(Array(managers.prefix(3).enumerated()), id: \.element.key) { index, manager in
                            InvestorPortraitImage(manager: manager, contentMode: .fill)
                                .frame(width: 39, height: 39)
                                .clipShape(Circle())
                                .overlay { Circle().stroke(MarketStyle.surface, lineWidth: 2) }
                                .zIndex(Double(managers.count - index))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(managerNames)
                        .font(.system(size: 13.5, weight: .bold))
                        .lineLimit(1)
                    Text(investorActivity)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { hairline }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("知名投资人最新持仓")
        .accessibilityHint("打开公开持仓详情")
    }

    private var managers: [FamousHoldingsManager] {
        (holdingsStore.holdings?.managers ?? []).sorted { managerPriority($0.key) < managerPriority($1.key) }
    }

    private var managerNames: String {
        guard !managers.isEmpty else { return "巴菲特 · 达利欧 · 李录" }
        return managers.prefix(3).map(\.displayName).joined(separator: " · ")
    }

    private var investorActivity: String {
        guard let holdings = holdingsStore.holdings else { return "最新 13F · 正在读取组合变化" }
        return "\(holdings.periodLabel)   增持 \(holdings.summary.increased)   减持 \(holdings.summary.decreased)   新建仓 \(holdings.summary.new)"
    }

    private var macroFeed: some View {
        Button(action: onOpenMacro) {
            HStack(spacing: 0) {
                macroItem(title: "GDP", metric: .gdpGrowth)
                macroDivider
                macroItem(title: "CPI", metric: .inflation)
                macroDivider
                macroItem(title: "消费信心", metric: .consumerConfidence)
                macroDivider
                yieldMacroItem
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(MarketStyle.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MarketStyle.cardBorder, lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("宏观数据速览")
        .accessibilityHint("打开宏观观察")
    }

    private func macroItem(title: String, metric: ChinaMacroMetric) -> some View {
        let values = macroValues(metric)
        let latest = values.last
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(latest.map { macroValue($0, metric: metric) } ?? "—")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(macroDirection(values))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 1)
                Sparkline(values: values, color: .secondary, showsFill: false)
                    .frame(width: 27, height: 21)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var yieldMacroItem: some View {
        let quote = marketStore.quote(symbol: "^TNX")
        return VStack(alignment: .leading, spacing: 2) {
            Text("美债 10Y")
                .font(.system(size: 10.5, weight: .semibold))
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(quote.map { String(format: "%.2f%%", $0.price) } ?? "—")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(industryStatus(quote))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 1)
                Sparkline(values: marketStore.trendValues(for: quote), color: quoteTint(quote), showsFill: false)
                    .frame(width: 27, height: 21)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var macroDivider: some View {
        Rectangle()
            .fill(MarketStyle.divider)
            .frame(width: 0.5, height: 45)
            .padding(.horizontal, 5)
    }

    private func macroValues(_ metric: ChinaMacroMetric) -> [Double] {
        Array(macroStore.years.reversed()).compactMap { metric.value(in: $0) }
    }

    private func macroValue(_ value: Double, metric: ChinaMacroMetric) -> String {
        metric == .consumerConfidence ? String(format: "%.1f", value) : String(format: "%.1f%%", value)
    }

    private func macroDirection(_ values: [Double]) -> String {
        guard values.count >= 2 else { return macroStore.isLoading ? "更新中" : "暂无趋势" }
        let delta = values[values.count - 1] - values[values.count - 2]
        if delta > 0.05 { return "回升" }
        if delta < -0.05 { return "回落" }
        return "持平"
    }

    private var hairline: some View {
        Rectangle().fill(MarketStyle.divider).frame(height: 0.5)
    }
}

private struct MarketRetailInvestorStrip: View {
    let store: RetailSentimentStore
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarketSectionHeading("散户观点")

            Group {
                if let item = validSample {
                    Button {
                        onOpen()
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            sampleThumbnail(item)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text("散户样本")
                                        .font(.system(size: 13.5, weight: .bold))

                                    Text(item.nickname)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)

                                    moodBadge(item.label)
                                }

                                Text(summary(for: item))
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)

                                Text("\(RetailSentimentFormat.compactRelativeTime(item.createdAt)) · 公开视频")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .padding(12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("查看全部散户观点")
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("散户样本")
                            .font(.system(size: 13.5, weight: .bold))
                        Text(store.isLoading ? "正在加载最新观点" : "暂无有效样本")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .padding(12)
                }
            }
            .background(MarketStyle.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MarketStyle.cardBorder, lineWidth: 0.8)
            }
        }
        .padding(.horizontal, MarketStyle.pageInset)
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
    }

    private var validSample: InvestorMoodItem? {
        store.investorMood?.items.first { item in
            guard !item.stale else { return false }
            guard !item.analysis.contains("未涉及投资内容") else { return false }
            let content = ([item.description, item.analysis, item.transcript] + item.reasons)
                .joined(separator: " ")
                .lowercased()
            let investmentTerms = [
                "股票", "股市", "股民", "投资", "交易", "行情", "仓位", "持仓",
                "短线", "长线", "指数", "基金", "a股", "美股", "港股", "亏损", "盈利",
            ]
            return investmentTerms.contains(where: content.contains)
        }
    }

    private func sampleThumbnail(_ item: InvestorMoodItem) -> some View {
        ZStack {
            AsyncImage(url: item.directCoverURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else if phase.error != nil {
                    proxiedThumbnail(item)
                } else {
                    thumbnailPlaceholder
                }
            }

            Circle()
                .fill(.black.opacity(0.62))
                .frame(width: 23, height: 23)

            Image(systemName: "play.fill")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: 0.5)
        }
        .frame(width: 72, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func proxiedThumbnail(_ item: InvestorMoodItem) -> some View {
        AsyncImage(url: item.coverPlaybackURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                thumbnailPlaceholder
            }
        }
    }

    private var thumbnailPlaceholder: some View {
        Color(uiColor: .secondarySystemBackground)
            .overlay {
                Image(systemName: "video.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
    }

    private func moodBadge(_ label: String) -> some View {
        let tint = RetailSentimentFormat.moodColor(label)
        return Text(label)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func summary(for item: InvestorMoodItem) -> String {
        let candidates: [String?] = [item.reasons.first, item.analysis, item.description, item.transcript]
        for candidate in candidates {
            if let candidate,
               !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        return "当前样本暂无观点摘要"
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

func marketRegionSwipeOffset(
    horizontalDistance: CGFloat,
    verticalDistance: CGFloat,
    projectedHorizontalDistance: CGFloat
) -> Int? {
    guard abs(horizontalDistance) > abs(verticalDistance) * 1.2 else { return nil }
    guard abs(horizontalDistance) >= 44 || abs(projectedHorizontalDistance) >= 80 else { return nil }
    let directionDistance = abs(horizontalDistance) >= 44
        ? horizontalDistance
        : projectedHorizontalDistance
    return directionDistance < 0 ? 1 : -1
}

func marketRegionSwipeBlocksSelection(horizontalDistance: CGFloat, verticalDistance: CGFloat) -> Bool {
    abs(horizontalDistance) >= 12 && abs(horizontalDistance) > abs(verticalDistance) * 1.2
}

func marketAdjacentRegion(from current: MarketRegion, offset: Int) -> MarketRegion? {
    let regions = MarketRegion.allCases
    guard let currentIndex = regions.firstIndex(of: current) else { return nil }
    let destinationIndex = currentIndex + offset
    guard regions.indices.contains(destinationIndex) else { return nil }
    return regions[destinationIndex]
}

private struct MarketTerminalHero: View {
    let store: MarketStore
    let region: MarketRegion
    let onOpenMarketQuotes: () -> Void
    let onOpenVIXHistory: () -> Void
    let onOpenChinaMarketStructure: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedRange: MarketRange = .day

    private let chartRanges: [MarketRange] = [.day, .week, .month, .year]

    private var quote: MarketQuote? { store.quote(symbol: region.primarySymbol) }
    private var overnightQuote: MarketQuote? {
        guard region == .unitedStates, quote?.marketSession != "regular",
              let session = marketActiveIndexSession(store.dashboard?.indexSessions?[region.primarySymbol]) else { return nil }
        return session
    }
    private var displayedQuote: MarketQuote? { overnightQuote ?? quote }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 10) {
                Button(action: onOpenMarketQuotes) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 7) {
                            Text(heroTitle)
                                .font(.system(size: 18, weight: .bold))
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

                        Group {
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 10) {
                                    heroPrice
                                    heroChart.frame(height: 118)
                                }
                            } else {
                                HStack(alignment: .center, spacing: 18) {
                                    heroPrice.frame(width: 126, alignment: .leading)
                                    heroChart.frame(maxWidth: .infinity).frame(height: 96)
                                }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(MarketPressStyle())
                .accessibilityLabel(heroAccessibilityLabel)
                .accessibilityHint("打开指数与核心股票")

                HStack(spacing: 4) {
                    ForEach(chartRanges) { range in
                        Button {
                            selectedRange = range
                        } label: {
                            Text(range == .day ? "日内" : range.rawValue)
                                .font(.system(size: 11, weight: selectedRange == range ? .semibold : .medium))
                                .foregroundStyle(selectedRange == range ? .primary : .secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    selectedRange == range ? Color.secondary.opacity(0.16) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedRange == range ? .isSelected : [])
                    }
                }
                .padding(3)
                .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(14)
            .background(MarketStyle.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MarketStyle.cardBorder, lineWidth: 0.8)
            }

            temperatureMetrics
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
    }

    private var heroPrice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayedQuote.map { number($0.price, digits: cryptoPriceDigits($0.price, symbol: $0.symbol)) } ?? "—")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(heroPerformanceText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(heroPerformanceTint)
            Text(heroVolatilityText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.68)
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
                } else {
                    EuropeMarketMetrics(store: store)
                }
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 180 : 82)
            .background(MarketStyle.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MarketStyle.cardBorder, lineWidth: 0.8)
            }
        }
    }

    private func temperatureCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 66 : 88)
            .background(MarketStyle.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
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
        quote?.historicalSymbol ?? quote?.symbol ?? region.primarySymbol
    }

    private var selectedTrend: [Double] {
        if selectedRange == .day { return store.trendValues(for: displayedQuote) }
        return store.chartPresentation(symbol: chartSymbol, range: selectedRange)?.values ?? []
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
            return displayedQuote.map(marketHeroChangeText) ?? "等待行情"
        }
        guard let selectedPeriodReturn else { return "正在计算\(selectedRange.rawValue)收益率" }
        let prefix = selectedPeriodReturn >= 0 ? "+" : "−"
        return "\(selectedRange.rawValue)收益率 \(prefix)\(number(abs(selectedPeriodReturn), digits: 2))%"
    }

    private var heroPerformanceTint: Color {
        guard selectedRange != .day else { return quoteTint(displayedQuote) }
        guard let selectedPeriodReturn else { return .secondary }
        if selectedPeriodReturn > 0 { return MarketStyle.gain }
        if selectedPeriodReturn < 0 { return MarketStyle.loss }
        return .secondary
    }

    private var heroVolatilityText: String {
        guard let selectedPeriodVolatility else { return "波动率载入中" }
        return "年化波动率 \(number(selectedPeriodVolatility, digits: 2))%"
    }

    private var chartLabels: [String] {
        switch selectedRange {
        case .day:
            return overnightQuote == nil ? ["开盘", "盘中", "最新"] : ["夜盘开盘", "夜盘中", "最新"]
        case .week: return ["5日前", "本周", "最新"]
        case .month: return ["1月前", "本月", "最新"]
        case .year: return ["1年前", "年内", "最新"]
        case .quarter, .fiveYears, .maximum: return ["起点", "期间", "最新"]
        }
    }

    private var sessionLabel: String {
        if region == .crypto { return "24H 交易中" }
        if overnightQuote != nil { return "股票休市" }
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

    private var heroChart: some View {
        TerminalLeadChart(
            trend: selectedTrend,
            color: heroPerformanceTint,
            labels: chartLabels
        )
    }

    private var heroAccessibilityLabel: String {
        guard let displayedQuote else { return "\(heroTitle)，等待行情" }
        return "\(heroTitle)，最新价 \(number(displayedQuote.price, digits: cryptoPriceDigits(displayedQuote.price, symbol: displayedQuote.symbol)))，\(heroPerformanceText)，\(sessionLabel)"
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

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            ZStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.20))
                    .frame(height: 0.5)
                Sparkline(values: trend, color: color)
                    .padding(.vertical, 5)
            }
            HStack {
                Text(labels[0])
                Spacer()
                Text(labels[1])
                Spacer()
                Text(labels[2])
            }
            .font(.caption2)
            .foregroundStyle(Color.secondary)
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

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 17) {
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
                    .font(.system(size: 12, weight: weight))
                    .foregroundStyle(isSelected ? MarketStyle.accent : .primary)
                Capsule()
                    .fill(isSelected ? MarketStyle.accent : .clear)
                    .frame(height: 2)
            }
            .lineLimit(1)
            .frame(height: 36)
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
    let region: MarketRegion
    let store: MarketStore
    let onSelectQuote: (String) -> Void

    @State private var chinaScope: ChinaIndexScope = .core
    @State private var displayedLogoPaths: [String: String]

    init(region: MarketRegion, store: MarketStore, onSelectQuote: @escaping (String) -> Void) {
        self.region = region
        self.store = store
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
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Text("指数")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    if region == .china {
                        ChinaIndexScopePicker(selection: $chinaScope)
                    }

                    if indices.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在加载\(region.rawValue)市场指数")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                    } else {
                        ForEach(Array(indices.enumerated()), id: \.element.symbol) { index, quote in
                            quoteRow(quote)
                            if index < indices.count - 1 {
                                Divider().opacity(0.45).padding(.leading, 18)
                            }
                        }
                    }

                    if !stocks.isEmpty {
                        Divider().padding(.top, 14)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(stocksTitle).font(.headline)
                            if let selectionDescription {
                                Text(selectionDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                        ForEach(Array(stocks.enumerated()), id: \.element.symbol) { index, quote in
                            quoteRow(quote)
                            if index < stocks.count - 1 {
                                Divider().opacity(0.45).padding(.leading, 18)
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(MarketStyle.surface)
        }
        .task(id: requestID) {
            guard region != .commodity else { return }
            await marketRunWithLimitedConcurrency(requestedQuotes) { quote in
                await store.loadCompanyLogo(symbol: quote.symbol, name: quote.presentationName)
                guard let path = await store.companyLogoPaths[quote.symbol],
                      let url = marketCompanyLogoURL(path) else { return }
                _ = await MarketLogoImageCache.shared.image(for: url)
            }
            guard !Task.isCancelled else { return }
            displayedLogoPaths = store.companyLogoPaths
        }
        .task(id: "charts:\(requestID)") {
            await marketRunWithLimitedConcurrency(requestedQuotes) { quote in
                await store.loadChart(symbol: quote.symbol, range: .day)
            }
        }
    }

    private func quoteRow(_ quote: MarketQuote) -> some View {
        Button { onSelectQuote(quote.symbol) } label: {
            MarketIndexTableRow(
                quote: quote,
                overnightQuote: nil,
                trend: store.listTrendValues(for: quote),
                companyLogoPath: displayedLogoPaths[quote.symbol],
                showsCompanyLogo: true
            )
        }
        .buttonStyle(MarketPressStyle())
    }

    private var requestID: String {
        "\(region.dashboardID):\(requestedQuotes.map(\.symbol).joined(separator: ","))"
    }
}

private struct ChinaMarketStructureSheet: View {
    let structure: MarketStructure?

    var body: some View {
        NavigationStack {
            ScrollView {
                ChinaMarketStructurePanel(structure: structure)
            }
            .scrollIndicators(.hidden)
            .background(MarketStyle.surface)
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
        return signed(displayedChange, digits: cryptoChangeDigits(overnightQuote ?? quote))
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
    @State private var selectedRange: MarketRange
    @State private var presentedValuation: CompanyValuationHistoryRoute?

    init(symbol: String, store: MarketStore, onSelectSymbol: @escaping (String) -> Void) {
        self.symbol = symbol
        self.store = store
        self.onSelectSymbol = onSelectSymbol
        _selectedRange = State(initialValue: symbol == "^VIX" ? .month : .day)
    }

    private var quote: MarketQuote? { store.quote(symbol: symbol) }
    private var constituent: MarketIndexConstituent? { store.constituent(symbol: symbol) }
    private var companyLogoPath: String? { constituent?.logoPath ?? store.companyLogoPaths[symbol] }
    private var historicalSymbol: String { quote?.historicalSymbol ?? symbol }
    private var chartSymbol: String { quote?.symbol ?? symbol }
    private var chartFallbackSymbol: String? {
        guard historicalSymbol != chartSymbol else { return nil }
        return historicalSymbol
    }
    private var selectedRangeChart: MarketChart? {
        let primary = store.chartPresentation(symbol: chartSymbol, range: selectedRange)
        guard (primary?.points.count ?? 0) < 2,
              let chartFallbackSymbol else { return store.chart(symbol: chartSymbol, range: selectedRange) }
        return store.chart(symbol: chartFallbackSymbol, range: selectedRange)
    }
    private var selectedPeriodReturn: Double? {
        guard selectedRange != .day else { return nil }
        return selectedRangeChart?.periodReturn?.percent
    }
    private var selectedPeriodVolatility: Double? {
        selectedRangeChart?.periodVolatility?.percent
    }
    private var isIndex: Bool {
        store.dashboard?.coreIndices.contains(where: { $0.symbol == symbol }) == true
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
        ZStack {
            MarketStyle.surface.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    detailHeader
                    keyData

                    MarketDetailChart(
                        selectedRange: $selectedRange,
                        symbol: chartSymbol,
                        fallbackSymbol: chartFallbackSymbol,
                        store: store
                    )
                    .id(chartSymbol)

                    if showsCompanyProfile { companyProfile }
                    if isIndex {
                        MarketDetailBreadth(
                            title: isAShareIndex ? "市场温度" : "成分表现",
                            breadth: detailBreadth
                        )
                    }
                    MarketSummary(quote: quote, isIndex: isIndex)
                        .padding(.bottom, 18)
                        .overlay(alignment: .top) { Divider().padding(.horizontal, 18) }
                    if isIndex { componentStocks }
                    Text("数据来源：\(quote?.dataSource ?? "行情服务") · \(quote?.freshnessLabel ?? "更新中")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 22)
                        .padding(.bottom, 28)
                }
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityAction(.escape) { dismiss() }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $presentedValuation) { route in
            CompanyValuationHistorySheet(route: route)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
        }
        .task(id: historicalSymbol) {
            if isIndex { await store.loadIndexConstituents(symbol: historicalSymbol) }
            if !isIndex && !isCrypto {
                await store.loadChart(symbol: historicalSymbol, range: .year)
            }
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

                    if let xueqiuURL {
                        Button {
                            UIApplication.shared.open(xueqiuURL)
                        } label: {
                            Image("XueqiuMark")
                                .resizable()
                                .renderingMode(.original)
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("在雪球打开\(quote?.presentationName ?? symbol)")
                        .accessibilityHint("跳转到雪球股票详情页")
                        .accessibilityIdentifier("market-xueqiu-link")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(quote.map { number($0.marketDisplayPrice, digits: cryptoPriceDigits($0.marketDisplayPrice, symbol: $0.symbol)) } ?? "—")
                    .font(.system(size: 40, weight: .bold))
                    .monospacedDigit()
                    .tracking(-1.2)
                    .foregroundStyle(marketDisplayTint(quote))
                Text(detailPerformanceText)
                    .font(.system(size: 18, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(detailPerformanceTint)
                Text(detailVolatilityText)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(quote?.marketAsOfLabel ?? "行情更新中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    private var detailPerformanceText: String {
        if selectedRange == .day {
            return quote.map {
                "\(signed($0.marketDisplayChangeValue, digits: cryptoChangeDigits($0)))  \($0.marketDisplayFormattedPercent)"
            } ?? "等待行情数据"
        }
        guard let selectedPeriodReturn else { return "正在计算\(selectedRange.rawValue)收益率" }
        let prefix = selectedPeriodReturn >= 0 ? "+" : "−"
        return "\(selectedRange.rawValue)收益率  \(prefix)\(number(abs(selectedPeriodReturn), digits: 2))%"
    }

    private var detailPerformanceTint: Color {
        guard selectedRange != .day else { return marketDisplayTint(quote) }
        guard let selectedPeriodReturn else { return .secondary }
        if selectedPeriodReturn > 0 { return MarketStyle.gain }
        if selectedPeriodReturn < 0 { return MarketStyle.loss }
        return .secondary
    }

    private var detailVolatilityText: String {
        guard let selectedPeriodVolatility else { return "年化波动率载入中" }
        return "\(selectedRange.rawValue)年化波动率  \(number(selectedPeriodVolatility, digits: 2))%"
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
                metric("昨收", quote?.previousClose)
            }
            Divider()
            HStack(spacing: 0) {
                metric("成交量", quote?.volume, compact: true)
                metricDivider
                textMetric("振幅", amplitudeText)
                metricDivider
                textMetric("涨跌额", quote.map { signed($0.marketDisplayChangeValue, digits: cryptoChangeDigits($0)) } ?? "—", marketDisplayTint(quote))
                if !isIndex && !isCrypto {
                    metricDivider
                    metric(
                        "52周最低",
                        quote?.week52Low ?? market52WeekLow(store.chart(symbol: historicalSymbol, range: .year)),
                        MarketStyle.loss
                    )
                }
            }
            Divider()
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 4)
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

private struct MarketMovingAverageSeries {
    let period: Int
    let color: Color
    let values: [Double?]
}

private struct MarketDetailChart: View {
    @Binding var selectedRange: MarketRange
    let symbol: String
    let fallbackSymbol: String?
    let store: MarketStore
    @State private var selectedPointIndex: Int?

    private var primaryChart: MarketChart? { store.chart(symbol: symbol, range: selectedRange) }
    private var fallbackChart: MarketChart? {
        guard let fallbackSymbol else { return nil }
        return store.chart(symbol: fallbackSymbol, range: selectedRange)
    }
    private var primaryPresentation: MarketChartPresentation? {
        store.chartPresentation(symbol: symbol, range: selectedRange)
    }
    private var fallbackPresentation: MarketChartPresentation? {
        guard let fallbackSymbol else { return nil }
        return store.chartPresentation(symbol: fallbackSymbol, range: selectedRange)
    }
    private var usesFallbackChart: Bool {
        (primaryPresentation?.points.count ?? 0) < 2
            && (fallbackPresentation?.points.count ?? 0) >= 2
    }
    private var displayedSymbol: String { usesFallbackChart ? fallbackSymbol ?? symbol : symbol }
    private var chart: MarketChart? { usesFallbackChart ? fallbackChart : primaryChart }
    private var presentation: MarketChartPresentation? {
        usesFallbackChart ? fallbackPresentation : primaryPresentation
    }
    private var points: [MarketChartPoint] { presentation?.points ?? [] }
    private var values: [Double] { presentation?.values ?? [] }
    private var showsCandles: Bool { selectedRange != .day }
    private var plotFractions: [CGFloat] {
        showsCandles ? marketEvenChartFractions(count: points.count) : presentation?.xFractions ?? []
    }
    private var plotFractionGap: CGFloat {
        zip(plotFractions, plotFractions.dropFirst())
            .map { $1 - $0 }
            .filter { $0 > 0 }
            .min() ?? 1
    }
    private var movingAverages: [MarketMovingAverageSeries] {
        [
            MarketMovingAverageSeries(period: 5, color: .orange, values: marketMovingAverageValues(points, period: 5)),
            MarketMovingAverageSeries(period: 10, color: .purple, values: marketMovingAverageValues(points, period: 10)),
            MarketMovingAverageSeries(period: 20, color: MarketStyle.accent, values: marketMovingAverageValues(points, period: 20)),
            MarketMovingAverageSeries(period: 60, color: .secondary, values: marketMovingAverageValues(points, period: 60))
        ]
    }
    private var inspectedPointIndex: Int? {
        guard !points.isEmpty else { return nil }
        return min(max(selectedPointIndex ?? points.count - 1, 0), points.count - 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(MarketRange.allCases) { range in
                    Button {
                        selectedRange = range
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
            if let inspectedPointIndex {
                chartReadout(point: points[inspectedPointIndex], index: inspectedPointIndex)
            }
            ZStack {
                ChartGrid(
                    low: presentation?.low,
                    high: presentation?.high,
                    digits: presentation?.axisDigits ?? 2
                )
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
                } else if showsCandles {
                    MarketCandlestickChart(
                        points: points,
                        xFractions: plotFractions,
                        low: presentation?.low,
                        high: presentation?.high,
                        movingAverages: movingAverages
                    )
                        .id(selectedRange)
                        .padding(.leading, 48).padding(.top, 9).padding(.bottom, 6)
                } else {
                    MarketSessionLineChart(
                        points: points,
                        xFractions: plotFractions,
                        low: presentation?.low,
                        high: presentation?.high,
                        regularColor: chartColor,
                        interval: chart?.interval
                    )
                        .id(selectedRange)
                        .padding(.leading, 48).padding(.top, 9).padding(.bottom, 6)
                    if let sessionBreak = presentation?.sessionBreak {
                        MarketSessionBreakMarker(
                            sessionBreak: sessionBreak,
                            points: points,
                            xFractions: plotFractions
                        )
                        .padding(.leading, 48).padding(.top, 9).padding(.bottom, 6)
                    }
                }
                if !values.isEmpty, let previousClose = chart?.quote.previousClose {
                    ChartReferenceLine(
                        value: previousClose,
                        low: presentation?.low,
                        high: presentation?.high
                    )
                }
                if !values.isEmpty, let inspectedPointIndex {
                    let inspectedPoint = points[inspectedPointIndex]
                    let displayPrice = selectedPointIndex == nil
                        ? chart?.quote.price ?? inspectedPoint.close
                        : inspectedPoint.close
                    MarketChartPriceOverlay(
                        value: displayPrice,
                        xFraction: plotFractions.indices.contains(inspectedPointIndex) ? plotFractions[inspectedPointIndex] : 1,
                        low: presentation?.low,
                        high: presentation?.high,
                        digits: presentation?.axisDigits ?? 2,
                        tint: selectedPointIndex == nil
                            ? chartTint
                            : inspectedPoint.close >= inspectedPoint.open ? MarketStyle.gain : MarketStyle.loss,
                        showsCrosshair: selectedPointIndex != nil
                    )
                    .padding(.leading, 48).padding(.top, 9).padding(.bottom, 6)
                }
            }
            .frame(height: showsCandles ? 230 : 210)
            .padding(.top, 10)
            .overlay {
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard abs(value.translation.width) >= abs(value.translation.height) else {
                                        selectedPointIndex = nil
                                        return
                                    }
                                    let plotWidth = max(proxy.size.width - 48, 1)
                                    let fraction = (value.location.x - 48) / plotWidth
                                    selectedPointIndex = marketNearestChartIndex(
                                        fraction: fraction,
                                        fractions: plotFractions
                                    )
                                }
                                .onEnded { _ in selectedPointIndex = nil }
                        )
                }
            }
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
            if presentation?.hasVolume == true {
                VolumeBars(
                    points: points,
                    xFractions: plotFractions,
                    volumeCeiling: presentation?.volumeCeiling ?? 1,
                    fractionGap: plotFractionGap
                )
                    .frame(height: 48)
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
            selectedPointIndex = nil
            await store.loadChart(symbol: symbol, range: selectedRange)
            if marketChartDisplayPoints(primaryChart?.candles ?? []).count < 2,
               let fallbackSymbol {
                await store.loadChart(symbol: fallbackSymbol, range: selectedRange)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(selectedRange.rawValue)行情图表")
    }

    private func chartReadout(point: MarketChartPoint, index: Int) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 2) {
                Text(chartTime(point.timestamp, range: selectedRange, timezone: chart?.timezone))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                readoutValue("开", point.open)
                readoutValue("高", point.high)
                readoutValue("低", point.low)
                readoutValue("收", point.close)
            }
            HStack(spacing: 9) {
                Text("量 \(point.volume.map(compactNumber) ?? "—")")
                    .foregroundStyle(.secondary)
                if showsCandles {
                    ForEach(movingAverages, id: \.period) { series in
                        let value = series.values.indices.contains(index) ? series.values[index] : nil
                        Text("MA\(series.period) \(value.map { number($0, digits: presentation?.axisDigits ?? 2) } ?? "—")")
                            .foregroundStyle(series.color)
                    }
                } else if presentation?.extendedSessionLabel != nil {
                    legendDot("常规", color: chartColor)
                    legendDot("盘前/盘后/夜盘", color: MarketStyle.purple)
                }
                Spacer(minLength: 0)
            }
        }
        .font(.system(size: 9.5, weight: .medium))
        .monospacedDigit()
        .padding(.horizontal, 2)
        .padding(.top, 8)
    }

    private func readoutValue(_ label: String, _ value: Double) -> some View {
        Text("\(label) \(number(value, digits: presentation?.axisDigits ?? 2))")
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func legendDot(_ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private var timelineLabels: [String] {
        guard let first = points.first, let last = points.last else { return ["—", "—", "—"] }
        return [first, points[points.count / 2], last].map { chartTime($0.timestamp, range: selectedRange, timezone: chart?.timezone) }
    }

    private var chartCaption: String {
        let base = selectedRange.apiInterval == "1m" ? "分时走势" : "日 K 线"
        let dated = chart.map { "\(base) · \($0.tradingDate)" } ?? base
        let sessionText = presentation?.extendedSessionLabel.map { " · \($0)" } ?? ""
        let referenceText = usesFallbackChart ? " · 参考 \(displayedSymbol)" : ""
        return presentation?.hasVolume == true
            ? "\(dated)\(sessionText)\(referenceText) · 成交量"
            : "\(dated)\(sessionText)\(referenceText)"
    }
    private var chartColor: Color {
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
    let xFractions: [CGFloat]

    var body: some View {
        GeometryReader { proxy in
            let startIndex = points.firstIndex { $0.timestamp == sessionBreak.previousTimestamp } ?? 0
            let endIndex = points.firstIndex { $0.timestamp == sessionBreak.currentTimestamp } ?? startIndex
            let start = xFractions.indices.contains(startIndex) ? xFractions[startIndex] : 0
            let end = xFractions.indices.contains(endIndex) ? xFractions[endIndex] : start
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

private struct ChartReferenceLine: View {
    let value: Double
    let low: Double?
    let high: Double?

    var body: some View {
        GeometryReader { proxy in
            if let low, let high, high > low, value >= low, value <= high {
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
    let low: Double?
    let high: Double?
    let digits: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                HStack(spacing: 6) {
                    Text(axisLabel(index))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .leading)
                    Rectangle().fill(MarketStyle.divider).frame(height: 0.5)
                }
                if index < 4 { Spacer() }
            }
        }
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
    let interval: String?

    var body: some View {
        Canvas { context, size in
            guard points.count > 1,
                  xFractions.count == points.count,
                  let low,
                  let high else { return }
            let span = max(high - low, 0.000_001)
            func canvasPoint(_ point: MarketChartPoint, at index: Int) -> CGPoint {
                CGPoint(
                    x: size.width * xFractions[index],
                    y: size.height * (0.06 + CGFloat((high - point.close) / span) * 0.88)
                )
            }

            var segmentIndices: [Int] = []
            func drawSegment() {
                guard segmentIndices.count > 1,
                      let firstIndex = segmentIndices.first,
                      let lastIndex = segmentIndices.last else { return }
                var path = Path()
                path.move(to: canvasPoint(points[firstIndex], at: firstIndex))
                segmentIndices.dropFirst().forEach { index in
                    path.addLine(to: canvasPoint(points[index], at: index))
                }
                let firstPoint = points[firstIndex]
                let isRegular = firstPoint.session == nil || firstPoint.session == "regular"
                if isRegular {
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
                    with: .color(isRegular ? regularColor : MarketStyle.purple),
                    style: StrokeStyle(lineWidth: isRegular ? 1.7 : 2, lineCap: .round, lineJoin: .round)
                )
            }

            for index in points.indices {
                let point = points[index]
                if let previousIndex = segmentIndices.last {
                    let previous = points[previousIndex]
                    if marketChartShouldSplitSegment(previous: previous, current: point, interval: interval) {
                        drawSegment()
                        segmentIndices = []
                    }
                }
                segmentIndices.append(index)
            }
            drawSegment()
        }
        .accessibilityHidden(true)
    }
}

private struct MarketCandlestickChart: View {
    let points: [MarketChartPoint]
    let xFractions: [CGFloat]
    let low: Double?
    let high: Double?
    let movingAverages: [MarketMovingAverageSeries]

    var body: some View {
        Canvas { context, size in
            guard points.count > 1,
                  xFractions.count == points.count,
                  let low,
                  let high,
                  high > low else { return }
            let span = max(high - low, 0.000_001)
            let fractionGap = zip(xFractions, xFractions.dropFirst())
                .map { $1 - $0 }
                .filter { $0 > 0 }
                .min() ?? 1
            let candleWidth = min(max(size.width * fractionGap * 0.64, 1.2), 8)

            func y(_ value: Double) -> CGFloat {
                size.height * (0.06 + CGFloat((high - value) / span) * 0.88)
            }

            for index in points.indices {
                let point = points[index]
                let x = size.width * xFractions[index]
                let color: Color = point.close > point.open
                    ? MarketStyle.gain
                    : point.close < point.open ? MarketStyle.loss : .secondary
                var wick = Path()
                wick.move(to: CGPoint(x: x, y: y(point.high)))
                wick.addLine(to: CGPoint(x: x, y: y(point.low)))
                context.stroke(wick, with: .color(color), lineWidth: 0.8)

                let openY = y(point.open)
                let closeY = y(point.close)
                let bodyHeight = max(abs(closeY - openY), 1.2)
                let body = CGRect(
                    x: x - candleWidth / 2,
                    y: min(openY, closeY),
                    width: candleWidth,
                    height: bodyHeight
                )
                context.fill(Path(body), with: .color(color.opacity(0.9)))
            }

            for series in movingAverages {
                var path = Path()
                var hasCurrentSegment = false
                for index in points.indices {
                    guard series.values.indices.contains(index), let value = series.values[index] else {
                        hasCurrentSegment = false
                        continue
                    }
                    let chartPoint = CGPoint(x: size.width * xFractions[index], y: y(value))
                    if hasCurrentSegment {
                        path.addLine(to: chartPoint)
                    } else {
                        path.move(to: chartPoint)
                        hasCurrentSegment = true
                    }
                }
                context.stroke(
                    path,
                    with: .color(series.color.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 1.05, lineCap: .round, lineJoin: .round)
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
                let x = proxy.size.width * min(max(xFraction, 0), 1)
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
                        .font(.system(size: 9, weight: .semibold))
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
            guard points.count > 1, xFractions.count == points.count else { return }
            let barWidth = min(max(size.width * fractionGap * 0.72, 1), 8)

            for (index, point) in points.enumerated() {
                guard let volume = point.volume, volume > 0 else { continue }
                let height = max(2, size.height * CGFloat(min(volume, volumeCeiling) / volumeCeiling))
                let x = marketVolumeBarX(fraction: xFractions[index], width: size.width, barWidth: barWidth)
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
