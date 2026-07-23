import SwiftUI

private enum InvestmentSection: String, CaseIterable, Identifiable {
    case market = "市场"
    case sentiment = "情绪"
    case holdings = "知名投资人"

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
                        InvestmentHeader(selection: $section, floatsOverContent: false)
                    }
                    MarketView(showsDetail: $marketShowsDetail)
                }
            case .sentiment:
                VStack(spacing: 0) {
                    InvestmentHeader(selection: $section, floatsOverContent: false)
                    RetailInvestorView()
                }
            case .holdings:
                ZStack(alignment: .top) {
                    FamousHoldingsView(store: holdingsStore, showsDetail: $holdingsShowsDetail)
                    if !holdingsShowsDetail {
                        InvestmentHeader(selection: $section, floatsOverContent: true)
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
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
    let floatsOverContent: Bool

    var body: some View {
        HStack(spacing: 17) {
            ForEach(InvestmentSection.allCases) { section in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = section }
                } label: {
                    VStack(spacing: 8) {
                        Text(section.rawValue)
                            .font(.system(size: 14, weight: selection == section ? .bold : .medium))
                            .foregroundStyle(selection == section ? HoldingsPalette.indigo : Color.secondary)
                        Capsule()
                            .fill(selection == section ? HoldingsPalette.indigo : .clear)
                            .frame(width: 16, height: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 22)
        .padding(.top, 6)
        .padding(.bottom, floatsOverContent ? 0 : 10)
    }
}
