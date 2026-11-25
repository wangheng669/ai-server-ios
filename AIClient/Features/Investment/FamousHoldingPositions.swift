import SwiftUI

enum HoldingPositionFilter: CaseIterable, Identifiable {
    case current, new, increased, decreased, exited, unchanged

    var id: Self { self }

    var action: FamousHoldingAction? {
        switch self {
        case .current: nil
        case .new: .new
        case .increased: .increased
        case .decreased: .decreased
        case .exited: .exited
        case .unchanged: .unchanged
        }
    }

    var title: String { action?.title ?? "当前持仓" }

    func count(in manager: FamousHoldingsManager) -> Int {
        switch self {
        case .current: manager.positionsCount
        case .new: manager.summary.new
        case .increased: manager.summary.increased
        case .decreased: manager.summary.decreased
        case .exited: manager.summary.exited
        case .unchanged: manager.summary.unchanged
        }
    }

    func positions(in manager: FamousHoldingsManager) -> [FamousHoldingChange] {
        if self == .exited { return manager.exitedPositions ?? [] }
        let positions = manager.positions ?? []
        guard let action else { return positions }
        return positions.filter { $0.action == action }
    }
}

struct HoldingPositionNotes: View {
    let position: FamousHoldingChange
    let showsDetails: Bool
    let showsChanges: Bool

    var body: some View {
        let type = HoldingDisclosureType(position: position)
        if showsDetails || showsChanges || type != .shares {
            VStack(alignment: .leading, spacing: 4) {
                if type != .shares {
                    Text(type.rawValue)
                        .foregroundStyle(HoldingsPalette.blue)
                }
                if showsDetails {
                    let identifiers = [position.titleOfClass, position.cusip]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                    if !identifiers.isEmpty {
                        Text(identifiers)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                }
                if showsChanges {
                    Text(position.action.title)
                        .foregroundStyle(actionColor(position.action))
                    + Text(" · 权重 \(holdingPercentagePoints(position.weightChangePct))")
                        .foregroundStyle(weightChangeColor(position.weightChangePct))
                }
            }
            .font(.caption2)
            .padding(.bottom, 7)
        }
    }
}

struct HoldingPositionIdentity: View {
    let position: FamousHoldingChange

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(position.name)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            let identifiers = [position.symbol, position.titleOfClass]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            if !identifiers.isEmpty {
                Text(identifiers)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            let type = HoldingDisclosureType(position: position)
            if type != .shares {
                Text(type.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(HoldingsPalette.blue)
            }
        }
    }
}
