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

    private var usesDarkStyle: Bool {
        selection == .gdp
    }

    var body: some View {
        Group {
            if !isCompact {
                compactHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                    .background(usesDarkStyle ? GDPDesign.midnight : InvestmentDesign.surface)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(usesDarkStyle ? Color.white.opacity(0.08) : InvestmentDesign.divider)
                            .frame(height: 0.5)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: usesDarkStyle)
        .animation(.easeOut(duration: 0.18), value: category)
        .animation(.easeOut(duration: 0.18), value: isCompact)
    }

    private var compactHeader: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(InvestmentCategory.allCases) { item in
                    Button(item.rawValue) { selection = item.defaultSection }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(category.rawValue).font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                }
                .foregroundStyle(primaryColor(isSelected: true))
                .frame(minHeight: 36)
            }
            Divider().frame(height: 22)
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

    private func primaryColor(isSelected: Bool) -> Color {
        if usesDarkStyle {
            return isSelected ? .white : .white.opacity(0.6)
        }
        return isSelected ? .primary : .secondary
    }

    private func secondaryColor(isSelected: Bool) -> Color {
        if usesDarkStyle {
            return isSelected ? .white : .white.opacity(0.72)
        }
        return isSelected ? InvestmentDesign.accent : .secondary
    }

    private func secondaryBackground(isSelected: Bool) -> Color {
        if usesDarkStyle {
            return isSelected ? InvestmentDesign.accent.opacity(0.9) : .white.opacity(0.08)
        }
        return isSelected ? InvestmentDesign.accentSoft : InvestmentDesign.secondarySurface
    }
}
