import SwiftUI

enum InvestmentDesign {
    static let accent = Color(red: 0.12, green: 0.40, blue: 0.96)
    static let accentSoft = accent.opacity(0.10)
    static let gain = Color(red: 0.94, green: 0.20, blue: 0.25)
    static let loss = Color(red: 0.03, green: 0.65, blue: 0.38)
    static let warning = Color(red: 0.96, green: 0.50, blue: 0.12)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .systemBackground)
    static let secondarySurface = Color(uiColor: .secondarySystemBackground)
    static let divider = Color(uiColor: .separator).opacity(0.42)
    static let pageInset: CGFloat = 16
    static let sectionSpacing: CGFloat = 10
    static let cornerRadius: CGFloat = 14
}

private enum InvestmentMotion {
    static let selection = Animation.smooth(duration: 0.28, extraBounce: 0)
    static let reveal = Animation.snappy(duration: 0.26, extraBounce: 0.03)
}

private enum InvestmentSection: String, CaseIterable, Identifiable {
    case market = "市场"
    case chinaMacro = "国内宏观"
    case institutionResearch = "机构研究"
    case holdings = "知名投资人"
    case industries = "产业全景"
    case gdp = "全球排行"

    var id: Self { self }

    var category: InvestmentCategory {
        switch self {
        case .market, .chinaMacro:
            .market
        case .institutionResearch, .holdings, .industries, .gdp:
            .research
        }
    }

    var subsectionTitle: String {
        switch self {
        case .market: "行情"
        case .chinaMacro: "国内"
        case .institutionResearch: "机构"
        case .holdings: "投资人"
        case .industries: "产业"
        case .gdp: "全球排行"
        }
    }

    var icon: String {
        switch self {
        case .market: "chart.line.uptrend.xyaxis"
        case .chinaMacro: "building.columns"
        case .institutionResearch: "doc.text.magnifyingglass"
        case .holdings: "person.crop.circle.badge.checkmark"
        case .industries: "square.3.layers.3d"
        case .gdp: "list.number"
        }
    }
}

private enum InvestmentCategory: String, CaseIterable, Identifiable {
    case market = "市场"
    case research = "研究"

    var id: Self { self }

    var sections: [InvestmentSection] {
        switch self {
        case .market:
            [.market]
        case .research:
            [.institutionResearch, .holdings, .industries, .gdp]
        }
    }

    var defaultSection: InvestmentSection {
        sections[0]
    }

    var icon: String {
        switch self {
        case .market: "chart.xyaxis.line"
        case .research: "doc.text.magnifyingglass"
        }
    }
}

struct InvestmentView: View {
    @Binding private var showsDetail: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @State private var section: InvestmentSection
    @State private var displayedSection: InvestmentSection
    @State private var contentOpacity = 1.0
    @State private var contentScale: CGFloat = 1
    @State private var contentOffset: CGFloat = 0
    @State private var transitionTask: Task<Void, Never>?
    @State private var holdingsShowsDetail = false
    @State private var marketStore = MarketStore()
    @State private var sentimentStore = RetailSentimentStore()
    @State private var holdingsStore = FamousHoldingsStore()

    init(showsDetail: Binding<Bool> = .constant(false)) {
        _showsDetail = showsDetail
        let initialSection: InvestmentSection
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--holdings-preview") {
            initialSection = .holdings
        } else if ProcessInfo.processInfo.arguments.contains("--industries-preview") {
            initialSection = .industries
        } else if ProcessInfo.processInfo.arguments.contains("--china-macro-preview") {
            initialSection = .chinaMacro
        } else if ProcessInfo.processInfo.arguments.contains("--institution-research-preview") {
            initialSection = .institutionResearch
        } else if ProcessInfo.processInfo.arguments.contains("--sentiment-preview") ||
                    ProcessInfo.processInfo.arguments.contains("--korea-leverage-preview") {
            initialSection = .market
        } else if ProcessInfo.processInfo.arguments.contains("--gdp-preview") ||
                    ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--gdp-detail-preview=") }) {
            initialSection = .gdp
        } else {
            initialSection = .market
        }
        #else
        initialSection = .market
        #endif
        _section = State(initialValue: initialSection)
        _displayedSection = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            selectedSectionContent
                .environment(\.rootTabIsActive, rootTabIsActive)
                .id(displayedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(contentOpacity)
                .scaleEffect(contentScale)
                .offset(y: contentOffset)
        }
        .background(InvestmentDesign.canvas)
        .overlay(alignment: .bottomTrailing) {
            if !showsDetail {
                HStack(alignment: .bottom, spacing: 8) {
                    if section.category.sections.count > 1 {
                        InvestmentSectionSelector(selection: $section)
                    }
                    InvestmentCategorySelector(selection: $section)
                }
                .padding(.trailing, 14)
                .padding(.bottom, 10)
            }
        }
        .onChange(of: holdingsShowsDetail) { _, value in
            showsDetail = value
        }
        .onChange(of: section) { _, value in
            transitionPage(to: value)
            holdingsShowsDetail = false
            showsDetail = false
        }
        .onDisappear {
            transitionTask?.cancel()
            showsDetail = false
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch displayedSection {
        case .market:
            MarketHubView(
                store: marketStore,
                sentimentStore: sentimentStore,
                showsDetail: $showsDetail
            )
        case .chinaMacro:
            ChinaMacroView()
        case .institutionResearch:
            InstitutionResearchView()
        case .holdings:
            FamousHoldingsView(store: holdingsStore, showsDetail: $holdingsShowsDetail)
        case .industries:
            IndustryPanoramaView()
        case .gdp:
            CountryGDPRankingView(showsDetail: $showsDetail)
        }
    }

    private func transitionPage(to target: InvestmentSection) {
        transitionTask?.cancel()
        guard displayedSection != target else { return }

        guard !reduceMotion else {
            displayedSection = target
            contentOpacity = 1
            contentScale = 1
            contentOffset = 0
            return
        }

        transitionTask = Task { @MainActor in
            withAnimation(.easeIn(duration: 0.10)) {
                contentOpacity = 0
                contentScale = 0.996
                contentOffset = -2
            }

            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, section == target else { return }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayedSection = target
                contentScale = 1.004
                contentOffset = 3
            }

            withAnimation(.easeOut(duration: 0.18)) {
                contentOpacity = 1
                contentScale = 1
                contentOffset = 0
            }
        }
    }
}

private struct MarketHubView: View {
    @Binding private var showsDetail: Bool
    private let store: MarketStore
    private let sentimentStore: RetailSentimentStore

    @MainActor
    init(
        store: MarketStore,
        sentimentStore: RetailSentimentStore,
        showsDetail: Binding<Bool>
    ) {
        self.store = store
        self.sentimentStore = sentimentStore
        _showsDetail = showsDetail
    }

    var body: some View {
        MarketView(
            store: store,
            sentimentStore: sentimentStore,
            showsDetail: $showsDetail
        )
    }
}

private struct InvestmentSectionSelector: View {
    @Binding var selection: InvestmentSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    private var sections: [InvestmentSection] {
        selection.category.sections
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            if isExpanded {
                VStack(alignment: .trailing, spacing: 7) {
                    ForEach(sections.filter { $0 != selection }) { item in
                        Button {
                            withAnimation(reduceMotion ? nil : InvestmentMotion.selection) {
                                selection = item
                                isExpanded = false
                            }
                        } label: {
                            selectorLabel(item, showsChevron: false)
                                .foregroundStyle(.primary)
                                .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
                                }
                                .shadow(color: Color.black.opacity(0.08), radius: 7, y: 3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.subsectionTitle)
                    }
                }
                .transition(
                    .move(edge: .bottom)
                        .combined(with: .scale(scale: 0.96, anchor: .bottomTrailing))
                        .combined(with: .opacity)
                )
            }

            Button {
                withAnimation(reduceMotion ? nil : InvestmentMotion.reveal) {
                    isExpanded.toggle()
                }
            } label: {
                selectorLabel(selection, showsChevron: true)
                    .foregroundStyle(InvestmentDesign.accent)
                    .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(InvestmentDesign.accent.opacity(0.24), lineWidth: 0.8)
                    }
                    .shadow(color: Color.black.opacity(0.10), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("投资子栏目")
            .accessibilityValue(selection.subsectionTitle)
            .accessibilityHint(isExpanded ? "轻点收起" : "轻点展开")
        }
        .sensoryFeedback(.selection, trigger: selection)
        .onChange(of: selection.category) { _, _ in
            isExpanded = false
        }
    }

    private func selectorLabel(
        _ item: InvestmentSection,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: item.icon)
                .font(.system(size: 14, weight: .semibold))

            Text(item.subsectionTitle)
                .font(.system(size: 14, weight: .semibold))

            if showsChevron {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 94, minHeight: 40)
        .contentShape(Rectangle())
    }
}

private struct InvestmentCategorySelector: View {
    @Binding var selection: InvestmentSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    private var category: InvestmentCategory {
        selection.category
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            if isExpanded {
                VStack(alignment: .trailing, spacing: 7) {
                    ForEach(InvestmentCategory.allCases.filter { $0 != category }) { item in
                        categoryButton(item)
                    }
                }
                .transition(
                    .move(edge: .bottom)
                        .combined(with: .scale(scale: 0.96, anchor: .bottomTrailing))
                        .combined(with: .opacity)
                )
            }

            Button {
                withAnimation(reduceMotion ? nil : InvestmentMotion.reveal) {
                    isExpanded.toggle()
                }
            } label: {
                selectorLabel(category, showsChevron: true)
                    .foregroundStyle(InvestmentDesign.accent)
                    .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(InvestmentDesign.accent.opacity(0.24), lineWidth: 0.8)
                    }
                    .shadow(color: Color.black.opacity(0.10), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("投资栏目")
            .accessibilityValue(category.rawValue)
            .accessibilityHint(isExpanded ? "轻点收起" : "轻点展开")
        }
        .sensoryFeedback(.selection, trigger: selection)
        .onChange(of: category) { _, _ in
            isExpanded = false
        }
    }

    private func categoryButton(_ item: InvestmentCategory) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : InvestmentMotion.selection) {
                selection = item.defaultSection
                isExpanded = false
            }
        } label: {
            selectorLabel(item, showsChevron: false)
                .foregroundStyle(.primary)
                .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.rawValue)
    }

    private func selectorLabel(
        _ item: InvestmentCategory,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: item.icon)
                .font(.system(size: 14, weight: .semibold))

            Text(item.rawValue)
                .font(.system(size: 14, weight: .semibold))

            if showsChevron {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 94, minHeight: 40)
        .contentShape(Rectangle())
    }
}
