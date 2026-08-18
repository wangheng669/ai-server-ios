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

            TabView(selection: $section) {
                MarketView(
                    store: marketStore,
                    showsDetail: $marketShowsDetail,
                    onCompactHeaderChange: { compact in
                        guard section == .market, headerIsCompact != compact else { return }
                        withAnimation(.easeOut(duration: 0.18)) { headerIsCompact = compact }
                    }
                )
                    .tag(InvestmentSection.market)

                RetailInvestorView(
                    store: sentimentStore,
                    marketStore: marketStore,
                    showsDetail: $showsDetail
                )
                .tag(InvestmentSection.sentiment)

                ChinaMacroView()
                    .tag(InvestmentSection.chinaMacro)

                InstitutionResearchView()
                    .tag(InvestmentSection.institutionResearch)

                FamousHoldingsView(store: holdingsStore, showsDetail: $holdingsShowsDetail)
                    .tag(InvestmentSection.holdings)

                IndustryPanoramaView()
                    .tag(InvestmentSection.industries)

                CountryGDPRankingView(showsDetail: $showsDetail)
                    .tag(InvestmentSection.gdp)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
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
}

private struct InvestmentHeader: View {
    @Binding var selection: InvestmentSection
    let isCompact: Bool

    private var category: InvestmentCategory {
        selection.category
    }

    var body: some View {
        Group {
            if !isCompact {
                compactHeader
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
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: category)
        .animation(.easeOut(duration: 0.18), value: isCompact)
    }

    private var compactHeader: some View {
        HStack(spacing: 8) {
            ForEach(category.sections) { section in
                Button { selection = section } label: {
                    Text(section.subsectionTitle)
                        .font(.subheadline.weight(selection == section ? .semibold : .regular))
                        .foregroundStyle(secondaryColor(isSelected: selection == section))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(secondaryBackground(isSelected: selection == section), in: Capsule())
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

    private func secondaryBackground(isSelected: Bool) -> Color {
        return isSelected ? InvestmentDesign.accentSoft : InvestmentDesign.secondarySurface
    }
}

private struct InvestmentCategorySelector: View {
    @Binding var selection: InvestmentSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var category: InvestmentCategory {
        selection.category
    }

    var body: some View {
        Menu {
            ForEach(InvestmentCategory.allCases) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.24, extraBounce: 0)) {
                        selection = item.defaultSection
                    }
                } label: {
                    Label(
                        item.rawValue,
                        systemImage: item == category ? "checkmark" : item.icon
                    )
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 15, weight: .semibold))

                Text(category.rawValue)
                    .font(.system(size: 15, weight: .semibold))

                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minWidth: 108, minHeight: 46)
            .background(InvestmentDesign.accent, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
            }
            .shadow(color: InvestmentDesign.accent.opacity(0.24), radius: 10, y: 4)
            .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("投资栏目")
        .accessibilityValue(category.rawValue)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
