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

    func positions(in manager: FamousHoldingsManager, matching term: String) -> [FamousHoldingChange] {
        let positions = self == .exited ? manager.exitedPositions ?? [] : manager.positions ?? []
        let action = action
        guard action != nil || !term.isEmpty else { return positions }
        return positions.filter { position in
            (action == nil || position.action == action)
                && (term.isEmpty || position.name.localizedStandardContains(term)
                    || (position.symbol?.localizedStandardContains(term) ?? false)
                    || position.originalName.localizedStandardContains(term)
                    || position.titleOfClass.localizedStandardContains(term)
                    || position.cusip.localizedStandardContains(term))
        }
    }
}

struct HoldingPositionControls: View {
    let manager: FamousHoldingsManager
    let hasPositions: Bool
    @Binding var selection: HoldingPositionFilter
    @Binding var query: String
    @ScaledMetric(relativeTo: .footnote) private var filterWidth: CGFloat = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("持仓明细")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let previousDate = manager.analytics.previousReportDate {
                Text("较 \(quarterLabel(previousDate)) 的持仓数量变化")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: filterWidth), spacing: 6)], spacing: 6) {
                    ForEach(HoldingPositionFilter.allCases, content: filterButton)
                }
                .accessibilityIdentifier("holding-position-filters")
            } else {
                Text("\(manager.positionsCount) 项持仓 · 暂无上期申报可比较")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if hasPositions {
                searchField
                    .padding(.top, 3)
            }
        }
    }

    private func filterButton(_ filter: HoldingPositionFilter) -> some View {
        let isSelected = selection == filter
        return Button {
            selection = filter
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    Text(filter.title).fixedSize()
                    Text(filter.count(in: manager), format: .number).fixedSize()
                }
                VStack(spacing: 2) {
                    Text(filter.title)
                    Text(filter.count(in: manager), format: .number)
                }
            }
            .monospacedDigit()
            .font(.footnote.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? ResearchDesign.accent : .primary)
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? ResearchDesign.selection : ResearchDesign.fill, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.title)
        .accessibilityValue("\(filter.count(in: manager)) 项")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("holding-filter-\(filter.title)")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索公司、代码或 CUSIP", text: $query)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityIdentifier("holding-position-search")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .font(.subheadline)
        .padding(.leading, 12)
        .padding(.trailing, query.isEmpty ? 12 : 0)
        .frame(minHeight: 44)
        .background(ResearchDesign.fill, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct HoldingPositionRow: View {
    let position: FamousHoldingChange
    let showsChanges: Bool

    private var isExited: Bool { position.action == .exited }
    private var weight: Double { isExited ? position.previousWeightPct : position.weightPct }
    private var value: Double { isExited ? position.previousValueUsd : position.valueUsd }

    private var metrics: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(holdingPercent(weight))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .accessibilityLabel("\(isExited ? "上期权重" : "权重") \(holdingPercent(weight))")
            Text("\(isExited ? "上期 " : "")\(holdingUSD(value))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(isExited ? "上期" : "")申报市值 \(exactHoldingUSD(value))")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    HoldingPositionIdentity(position: position, showsCUSIP: true)
                    Spacer(minLength: 0)
                    metrics
                }
                VStack(alignment: .leading, spacing: 8) {
                    HoldingPositionIdentity(position: position, showsCUSIP: true)
                    metrics
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            if showsChanges {
                HStack(alignment: .firstTextBaseline) {
                    Text(position.action.title)
                        .foregroundStyle(actionColor(position.action))
                    Spacer(minLength: 6)
                    Text("权重 \(holdingPercentagePoints(position.weightChangePct))")
                        .foregroundStyle(weightChangeColor(position.weightChangePct))
                }
                .font(.footnote.weight(.medium).monospacedDigit())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct HoldingPositionIdentity: View {
    let position: FamousHoldingChange
    var showsCUSIP = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(position.name)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            let identifiers = [position.symbol, position.titleOfClass, showsCUSIP ? position.cusip : nil]
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
