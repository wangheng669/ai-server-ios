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
}

struct InvestmentView: View {
    @Binding private var showsDetail: Bool
    @State private var section: InvestmentSection
    @State private var marketShowsDetail = false
    @State private var holdingsShowsDetail = false
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
                InvestmentHeader(selection: $section)
            }

            TabView(selection: $section) {
                MarketView(store: marketStore, showsDetail: $marketShowsDetail)
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
        }
        .onDisappear {
            showsDetail = false
        }
    }
}

private struct InvestmentHeader: View {
    @Binding var selection: InvestmentSection

    private var usesDarkStyle: Bool {
        selection == .gdp
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 24) {
                    ForEach(InvestmentSection.allCases) { section in
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) {
                                selection = section
                                proxy.scrollTo(section, anchor: .center)
                            }
                        } label: {
                            VStack(spacing: 0) {
                                Text(section.rawValue)
                                    .font(.system(size: 14, weight: selection == section ? .semibold : .regular))
                                    .foregroundStyle(
                                        usesDarkStyle
                                            ? (selection == section ? Color.white : Color.white.opacity(0.6))
                                            : (selection == section ? Color.primary : Color.secondary)
                                    )
                                    .frame(height: 42)
                                Capsule()
                                    .fill(selection == section ? InvestmentDesign.accent : .clear)
                                    .frame(width: 18, height: 2.5)
                            }
                        }
                        .id(section)
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == section ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 18)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, value in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(value, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 6)
        .background(usesDarkStyle ? GDPDesign.midnight : InvestmentDesign.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(usesDarkStyle ? Color.white.opacity(0.08) : InvestmentDesign.divider)
                .frame(height: 0.5)
        }
        .animation(.easeOut(duration: 0.18), value: usesDarkStyle)
    }
}
