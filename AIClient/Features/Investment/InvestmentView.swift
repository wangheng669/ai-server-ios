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
        Group {
            switch section {
            case .market:
                VStack(spacing: 0) {
                    if !marketShowsDetail {
                        InvestmentHeader(selection: $section, floatsOverContent: false)
                    }
                    MarketView(showsDetail: $marketShowsDetail)
                }
            case .holdings:
                ZStack(alignment: .top) {
                    FamousHoldingsView(store: holdingsStore, showsDetail: $holdingsShowsDetail)
                    if !holdingsShowsDetail {
                        InvestmentHeader(selection: $section, floatsOverContent: true)
                            .padding(.top, 10)
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .onChange(of: marketShowsDetail) { _, value in showsDetail = value }
        .onChange(of: holdingsShowsDetail) { _, _ in showsDetail = false }
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
    let floatsOverContent: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(InvestmentSection.allCases) { section in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = section }
                } label: {
                    Text(section.rawValue)
                        .font(.system(size: 15, weight: selection == section ? .semibold : .regular))
                        .foregroundStyle(selection == section ? Color.white : Color.primary.opacity(0.62))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if selection == section {
                                RoundedRectangle(cornerRadius: 17)
                                    .fill(HoldingsPalette.purple)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(width: 184, height: 44)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(uiColor: .separator).opacity(0.45)))
        .frame(maxWidth: .infinity)
        .padding(.vertical, floatsOverContent ? 0 : 7)
    }
}
