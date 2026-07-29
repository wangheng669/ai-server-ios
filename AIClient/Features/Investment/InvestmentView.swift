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
    case holdings = "知名投资人"
    case industries = "产业全景"

    var id: Self { self }
}

struct InvestmentView: View {
    @Binding private var showsDetail: Bool
    @State private var section: InvestmentSection
    @State private var marketShowsDetail = false
    @State private var holdingsShowsDetail = false
    @State private var holdingsStore = FamousHoldingsStore()

    init(showsDetail: Binding<Bool> = .constant(false)) {
        _showsDetail = showsDetail
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--holdings-preview") {
            _section = State(initialValue: .holdings)
        } else if ProcessInfo.processInfo.arguments.contains("--industries-preview") {
            _section = State(initialValue: .industries)
        } else if ProcessInfo.processInfo.arguments.contains("--sentiment-preview") {
            _section = State(initialValue: .sentiment)
        } else {
            _section = State(initialValue: .market)
        }
        #else
        _section = State(initialValue: .market)
        #endif
    }

    var body: some View {
        Group {
            switch section {
            case .market:
                VStack(spacing: 0) {
                    if !marketShowsDetail {
                        InvestmentHeader(selection: $section)
                    }
                    MarketView(showsDetail: $marketShowsDetail)
                }
            case .sentiment:
                VStack(spacing: 0) {
                    if !showsDetail {
                        InvestmentHeader(selection: $section)
                    }
                    RetailInvestorView(showsDetail: $showsDetail)
                }
            case .holdings:
                VStack(spacing: 0) {
                    if !holdingsShowsDetail {
                        InvestmentHeader(selection: $section)
                    }
                    FamousHoldingsView(store: holdingsStore, showsDetail: $holdingsShowsDetail)
                }
            case .industries:
                VStack(spacing: 0) {
                    if !showsDetail {
                        InvestmentHeader(selection: $section)
                    }
                    IndustryPanoramaView()
                }
            }
        }
        .background(InvestmentDesign.canvas)
        .task {
            await holdingsStore.load()
            if let managers = holdingsStore.holdings?.managers {
                await InvestorPortraitLoader.preload(managers)
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
        }
        .onDisappear {
            showsDetail = false
        }
    }
}

private struct InvestmentHeader: View {
    @Binding var selection: InvestmentSection

    var body: some View {
        HStack(spacing: 24) {
            ForEach(InvestmentSection.allCases) { section in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = section }
                } label: {
                    VStack(spacing: 0) {
                        Text(section.rawValue)
                            .font(.system(size: 14, weight: selection == section ? .semibold : .regular))
                            .foregroundStyle(selection == section ? Color.primary : Color.secondary)
                            .frame(height: 42)
                        Capsule()
                            .fill(selection == section ? InvestmentDesign.accent : .clear)
                            .frame(width: 18, height: 2.5)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
        .background(InvestmentDesign.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(InvestmentDesign.divider)
                .frame(height: 0.5)
        }
    }
}
