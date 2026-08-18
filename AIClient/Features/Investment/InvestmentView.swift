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
    static let page = Animation.smooth(duration: 0.24, extraBounce: 0)
}

private enum InvestmentSection: String, CaseIterable, Identifiable {
    case market = "市场"
    case sentiment = "情绪"
    case chinaMacro = "国内宏观"
    case institutionResearch = "机构研究"
    case holdings = "知名投资人"
    case industries = "产业全景"
    case gdp = "全球排行"

    var id: Self { self }

    var category: InvestmentCategory {
        switch self {
        case .market, .sentiment:
            .market
        case .chinaMacro, .gdp:
            .macro
        case .institutionResearch, .holdings, .industries:
            .research
        }
    }

    var subsectionTitle: String {
        switch self {
        case .market: "行情"
        case .sentiment: "情绪"
        case .chinaMacro: "国内"
        case .institutionResearch: "机构"
        case .holdings: "投资人"
        case .industries: "产业"
        case .gdp: "全球排行"
        }
    }
}

private enum InvestmentCategory: String, CaseIterable, Identifiable {
    case market = "市场"
    case macro = "宏观"
    case research = "研究"

    var id: Self { self }

    var sections: [InvestmentSection] {
        switch self {
        case .market:
            [.market, .sentiment]
        case .macro:
            [.chinaMacro, .gdp]
        case .research:
            [.institutionResearch, .holdings, .industries]
        }
    }

    var defaultSection: InvestmentSection {
        sections[0]
    }

    var icon: String {
        switch self {
        case .market: "chart.xyaxis.line"
        case .macro: "globe.asia.australia"
        case .research: "doc.text.magnifyingglass"
        }
    }
}

struct InvestmentView: View {
    @Binding private var showsDetail: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section: InvestmentSection
    @State private var marketShowsDetail = false
    @State private var holdingsShowsDetail = false
    @State private var headerIsCompact = false
    @State private var marketStore = MarketStore()
    @State private var sentimentStore = RetailSentimentStore()
    @State private var holdingsStore = FamousHoldingsStore()

    init(showsDetail: Binding<Bool> = .constant(false)) {
        _showsDetail = showsDetail
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--holdings-preview") {
            _section = State(initialValue: .holdings)
        } else if ProcessInfo.processInfo.arguments.contains("--industries-preview") {
            _section = State(initialValue: .industries)
        } else if ProcessInfo.processInfo.arguments.contains("--china-macro-preview") {
            _section = State(initialValue: .chinaMacro)
        } else if ProcessInfo.processInfo.arguments.contains("--institution-research-preview") {
            _section = State(initialValue: .institutionResearch)
        } else if ProcessInfo.processInfo.arguments.contains("--sentiment-preview") ||
                    ProcessInfo.processInfo.arguments.contains("--korea-leverage-preview") {
            _section = State(initialValue: .sentiment)
        } else if ProcessInfo.processInfo.arguments.contains("--gdp-preview") ||
                    ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--gdp-detail-preview=") }) {
            _section = State(initialValue: .gdp)
        } else {
            _section = State(initialValue: .market)
        }
        #else
        _section = State(initialValue: .market)
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            if !showsDetail {
                InvestmentHeader(selection: $section, isCompact: headerIsCompact && section == .market)
            }

            ZStack {
                sectionLayer(.market) {
                    MarketView(
                        store: marketStore,
                        showsDetail: $marketShowsDetail,
                        onCompactHeaderChange: { compact in
                            guard section == .market, headerIsCompact != compact else { return }
                            withAnimation(.easeOut(duration: 0.18)) { headerIsCompact = compact }
                        }
                    )
                }

                sectionLayer(.sentiment) {
                    RetailInvestorView(
                        store: sentimentStore,
                        marketStore: marketStore,
                        showsDetail: $showsDetail
                    )
                }

                sectionLayer(.chinaMacro) {
                    ChinaMacroView()
                }

                sectionLayer(.institutionResearch) {
                    InstitutionResearchView()
                }

                sectionLayer(.holdings) {
                    FamousHoldingsView(store: holdingsStore, showsDetail: $holdingsShowsDetail)
                }

                sectionLayer(.industries) {
                    IndustryPanoramaView()
                }

                sectionLayer(.gdp) {
                    CountryGDPRankingView(showsDetail: $showsDetail)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : InvestmentMotion.page, value: section)
        }
        .background(InvestmentDesign.canvas)
        .overlay(alignment: .bottomTrailing) {
            if !showsDetail {
                InvestmentCategorySelector(selection: $section)
                    .padding(.trailing, 14)
                    .padding(.bottom, section == .market ? 58 : 10)
            }
        }
        .onChange(of: marketShowsDetail) { _, value in showsDetail = value }
        .onChange(of: holdingsShowsDetail) { _, value in
            showsDetail = value
        }
        .onChange(of: section) { _, value in
            marketShowsDetail = false
            holdingsShowsDetail = false
            showsDetail = false
            headerIsCompact = false
        }
        .onDisappear {
            showsDetail = false
        }
    }

    private func sectionLayer<Content: View>(
        _ target: InvestmentSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isSelected = section == target

        return content()
            .opacity(isSelected ? 1 : 0)
            .scaleEffect(isSelected || reduceMotion ? 1 : 0.992)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
            .zIndex(isSelected ? 1 : 0)
    }
}

private struct InvestmentHeader: View {
    @Binding var selection: InvestmentSection
    let isCompact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionHighlight

    private var category: InvestmentCategory {
        selection.category
    }

    var body: some View {
        Group {
            if !isCompact {
                compactHeader
                    .id(category)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                    .background(InvestmentDesign.surface)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(InvestmentDesign.divider)
                            .frame(height: 0.5)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
            }
        }
        .animation(reduceMotion ? nil : InvestmentMotion.selection, value: category)
        .animation(reduceMotion ? nil : InvestmentMotion.selection, value: isCompact)
    }

    private var compactHeader: some View {
        HStack(spacing: 8) {
            ForEach(category.sections) { section in
                Button {
                    withAnimation(reduceMotion ? nil : InvestmentMotion.selection) {
                        selection = section
                    }
                } label: {
                    Text(section.subsectionTitle)
                        .font(.subheadline.weight(selection == section ? .semibold : .regular))
                        .foregroundStyle(secondaryColor(isSelected: selection == section))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background {
                            if selection == section {
                                Capsule()
                                    .fill(InvestmentDesign.accentSoft)
                                    .matchedGeometryEffect(
                                        id: "investment-subsection-selection",
                                        in: selectionHighlight
                                    )
                            } else {
                                Capsule().fill(InvestmentDesign.secondarySurface)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    private func secondaryColor(isSelected: Bool) -> Color {
        return isSelected ? InvestmentDesign.accent : .secondary
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
