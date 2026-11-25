import SwiftUI

enum InvestmentDesign {
    static let accent = Color(red: 0.12, green: 0.40, blue: 0.96)
    static let gain = Color(red: 0.94, green: 0.20, blue: 0.25)
    static let loss = Color(red: 0.03, green: 0.65, blue: 0.38)
    static let warning = Color(red: 0.96, green: 0.50, blue: 0.12)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .systemBackground)
    static let secondarySurface = Color(uiColor: .secondarySystemBackground)
    static let divider = Color(uiColor: .separator).opacity(0.42)
    static let pageInset: CGFloat = 16
    static let cornerRadius: CGFloat = 14
}

enum ResearchDesign {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.66, green: 0.78, blue: 1, alpha: 1)
            : UIColor(red: 0.15, green: 0.32, blue: 0.60, alpha: 1)
    })
    static let selection = accent.opacity(0.10)
    static let fill = Color(uiColor: .secondarySystemBackground)
    static let line = Color.primary.opacity(0.09)
    static let inset: CGFloat = 18
    static let radius: CGFloat = 14
}

extension View {
    func researchPanel(fill: Color = InvestmentDesign.surface) -> some View {
        let shape = RoundedRectangle(cornerRadius: ResearchDesign.radius)
        return background(fill, in: shape)
            .clipShape(shape)
            .overlay { shape.strokeBorder(ResearchDesign.line).allowsHitTesting(false) }
    }
}
