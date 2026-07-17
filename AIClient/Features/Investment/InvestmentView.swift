import SwiftUI

private enum InvestmentSection: String, CaseIterable, Identifiable {
    case market = "市场"
    case holdings = "持仓"

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
        _section = State(initialValue: ProcessInfo.processInfo.arguments.contains("--holdings-preview") ? .holdings : .market)
        #else
        _section = State(initialValue: .market)
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            if !marketShowsDetail && !holdingsShowsDetail {
                InvestmentHeader(selection: $section)
            }
            Group {
                switch section {
                case .market:
                    MarketView(showsDetail: $marketShowsDetail)
                case .holdings:
                    FamousHoldingsView(store: holdingsStore, showsDetail: $holdingsShowsDetail)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .onChange(of: marketShowsDetail) { _, value in showsDetail = value }
        .onChange(of: holdingsShowsDetail) { _, value in showsDetail = value }
        .onChange(of: section) { _, _ in
            marketShowsDetail = false
            holdingsShowsDetail = false
            showsDetail = false
        }
        .onDisappear { showsDetail = false }
    }
}

private struct InvestmentHeader: View {
    @Binding var selection: InvestmentSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("投资")
                .font(.system(size: 34, weight: .bold))
                .padding(.horizontal, 18)

            HStack(spacing: 34) {
                ForEach(InvestmentSection.allCases) { section in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { selection = section }
                    } label: {
                        VStack(spacing: 8) {
                            Text(section.rawValue)
                                .font(.system(size: 16, weight: selection == section ? .semibold : .regular))
                                .foregroundStyle(selection == section ? Color.blue : Color.secondary)
                            Capsule()
                                .fill(selection == section ? Color.blue : Color.clear)
                                .frame(width: 38, height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 8)
        .background(Color(uiColor: .systemBackground))
    }
}
