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

struct InvestmentView: View {
    @Binding private var showsDetail: Bool
    @State private var marketStore: MarketStore
    @State private var sentimentStore: RetailSentimentStore

    @MainActor
    init(
        showsDetail: Binding<Bool> = .constant(false),
        marketStore: MarketStore? = nil,
        sentimentStore: RetailSentimentStore? = nil
    ) {
        _showsDetail = showsDetail
        _marketStore = State(initialValue: marketStore ?? MarketStore())
        _sentimentStore = State(initialValue: sentimentStore ?? RetailSentimentStore())
    }

    var body: some View {
        MarketView(
            store: marketStore,
            sentimentStore: sentimentStore,
            showsDetail: $showsDetail
        )
    }
}
