import SwiftUI

private enum HoldingDetailFilter: String, CaseIterable, Identifiable {
    case current = "当前持仓"
    case new = "新建仓"
    case increased = "增持"
    case decreased = "减持"
    case unchanged = "未变动"
    case exited = "清仓"

    var id: Self { self }

    func matches(_ action: FamousHoldingAction) -> Bool {
        switch self {
        case .current: action != .exited
        case .new: action == .new
        case .increased: action == .increased
        case .decreased: action == .decreased
        case .unchanged: action == .unchanged
        case .exited: action == .exited
        }
    }
}

struct FamousHoldingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let manager: FamousHoldingsManager
    let store: FamousHoldingsStore
    @State private var filter = HoldingDetailFilter.current

    private func changes(_ detail: FamousHoldingsManager) -> [FamousHoldingChange] {
        let records: [FamousHoldingChange]
        if filter == .exited {
            records = detail.exitedPositions ?? []
        } else {
            let positions = detail.positions ?? []
            records = filter == .current ? positions : positions.filter { filter.matches($0.action) }
        }
        return records.sorted {
            filter == .exited
                ? ($0.previousValueUsd ?? $0.valueUsd) > ($1.previousValueUsd ?? $1.valueUsd)
                : $0.valueUsd > $1.valueUsd
        }
    }

    var body: some View {
        let detail = store.detail(for: manager)
        let resolvedManager = detail ?? manager
        let visibleChanges = detail.map(changes) ?? []
        VStack(spacing: 0) {
            filterBar(resolvedManager)
            if detail != nil { listHeader(count: visibleChanges.count) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(resolvedManager.displayName)的持仓")
                            .font(.title2.bold())
                        Text("\(quarterLabel(resolvedManager.reportDate)) · \(resolvedManager.positionsCount) 只 · \(compactUSD(resolvedManager.totalValueUsd))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    if detail != nil {
                        ForEach(Array(visibleChanges.enumerated()), id: \.element.id) { index, change in
                            holdingRow(change)
                            if index < visibleChanges.count - 1 {
                                Divider().overlay(HoldingsPalette.divider).padding(.leading, 72)
                            }
                        }
                    } else if let message = store.detailError(for: manager) {
                        ContentUnavailableView {
                            Label("完整持仓暂不可用", systemImage: "list.bullet.rectangle")
                        } description: {
                            Text(message)
                        } actions: {
                            Button("重新加载") { Task { await store.loadDetail(for: manager) } }
                        }
                    } else {
                        ContentLoadingPlaceholder(title: "正在读取完整持仓")
                    }
                    footer(resolvedManager)
                }
            }
            .scrollIndicators(.hidden)
            .background(HoldingsPalette.card)
        }
        .background(HoldingsPalette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: manager.reportIdentity) { await store.loadDetail(for: manager) }
    }

    private func filterBar(_ manager: FamousHoldingsManager) -> some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(HoldingDetailFilter.allCases) { item in
                        let count = filterCount(item, manager: manager)
                        Button { filter = item } label: {
                            Text("\(item.rawValue) \(count.map { String($0) } ?? "—")")
                                .font(.system(size: 12, weight: filter == item ? .semibold : .medium))
                                .foregroundStyle(filter == item ? Color.white : Color.secondary)
                                .padding(.horizontal, 13)
                                .frame(height: 32)
                                .background(
                                    filter == item ? HoldingsPalette.blue : Color.secondary.opacity(0.09),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.rawValue)
                        .accessibilityValue(count.map { "\($0) 条" } ?? "数量暂未返回")
                        .accessibilityIdentifier("holding-filter-\(item.rawValue)")
                        .accessibilityAddTraits(filter == item ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
            }
            .accessibilityIdentifier("holding-detail-filters")
            .scrollIndicators(.hidden)
            DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭持仓详情")
                .padding(.trailing, 12)
        }
        .padding(.vertical, 6)
    }

    private func listHeader(count: Int) -> some View {
        HStack {
            Text(filter == .exited ? "清仓记录" : filter.rawValue)
                .font(.system(size: 15, weight: .semibold))
            Text("\(count) 条")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(filter == .exited ? "按上期市值从高到低" : "按持仓市值从高到低")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .frame(height: 42)
        .background(HoldingsPalette.card)
        .overlay(alignment: .top) { Divider().overlay(HoldingsPalette.divider) }
        .overlay(alignment: .bottom) { Divider().overlay(HoldingsPalette.divider) }
    }

    private func holdingRow(_ change: FamousHoldingChange) -> some View {
        let color = actionColor(change.action)
        return HStack(spacing: 12) {
            HoldingsCompanyLogo(path: change.companyLogo, symbol: change.symbol, color: color, size: 40)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(change.symbol ?? "—")
                        .font(.system(size: 15, weight: .semibold))
                    Text(actionLabel(change))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(color.opacity(0.11), in: Capsule())
                }
                Text(change.name)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 5) {
                Text(filter == .exited ? percent(change.previousWeightPct) : percent(change.weightPct))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                Text(filter == .exited
                     ? "上期 \(compactUSD(change.previousValueUsd ?? change.valueUsd))"
                     : compactUSD(change.valueUsd))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 72)
        .accessibilityElement(children: .combine)
    }

    private func actionLabel(_ change: FamousHoldingChange) -> String {
        if change.action == .unchanged { return change.action.title }
        let arrow = change.weightChangePct >= 0 ? "↑" : "↓"
        return "\(arrow) \(change.action.title) \(percent(abs(change.weightChangePct)))"
    }

    private func filterCount(_ item: HoldingDetailFilter, manager: FamousHoldingsManager) -> Int? {
        switch item {
        case .current: manager.positionsCount
        case .new: manager.summary.new
        case .increased: manager.summary.increased
        case .decreased: manager.summary.decreased
        case .exited: manager.summary.exited
        case .unchanged: manager.summary.unchanged ?? manager.positions?.count(where: { $0.action == .unchanged })
        }
    }

    private func footer(_ resolvedManager: FamousHoldingsManager) -> some View {
        HStack {
            Text("数据来源：SEC 13F 申报")
            Spacer()
            if let holdingsCount = resolvedManager.holdingsCount, holdingsCount != resolvedManager.positionsCount {
                Text("USD · 原始 \(holdingsCount) 条 · 合并 \(resolvedManager.positionsCount) 只")
            } else {
                Text("货币单位：USD")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
    }

}
