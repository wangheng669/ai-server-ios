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

    private var resolvedManager: FamousHoldingsManager {
        store.managerDetails[manager.key] ?? manager
    }

    private var changes: [FamousHoldingChange] {
        let records: [FamousHoldingChange]
        if filter == .exited {
            records = resolvedManager.exitedPositions ?? resolvedManager.changes.filter { $0.action == .exited }
        } else {
            let positions = resolvedManager.positions ?? resolvedManager.changes.filter { $0.action != .exited }
            records = filter == .current ? positions : positions.filter { filter.matches($0.action) }
        }
        return records.sorted {
            filter == .exited
                ? ($0.previousValueUsd ?? $0.valueUsd) > ($1.previousValueUsd ?? $1.valueUsd)
                : $0.valueUsd > $1.valueUsd
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationHeader
            filterBar
            listHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    if store.loadingManagerKeys.contains(manager.key) && store.managerDetails[manager.key] == nil {
                        ProgressView("正在读取完整持仓")
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                            holdingRow(change)
                            if index < changes.count - 1 {
                                Divider().overlay(HoldingsPalette.divider).padding(.leading, 72)
                            }
                        }
                    }
                    footer
                }
            }
            .scrollIndicators(.hidden)
            .background(HoldingsPalette.card)
        }
        .background(HoldingsPalette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.loadDetail(managerKey: manager.key) }
    }

    private var navigationHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(resolvedManager.displayName)的持仓")
                    .font(.system(size: 21, weight: .semibold))
                HStack(spacing: 6) {
                    Text(quarterLabel(resolvedManager.reportDate))
                    Text("·")
                    Text("\(resolvedManager.positionsCount) 只")
                    Text("·")
                    Text(compactUSD(resolvedManager.totalValueUsd))
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(Color.secondary.opacity(0.10), in: Circle())
            }
            .accessibilityLabel("关闭持仓详情")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(HoldingDetailFilter.allCases) { item in
                    Button { filter = item } label: {
                        Text("\(item.rawValue) \(filterCount(item))")
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
                    .accessibilityAddTraits(filter == item ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 14)
    }

    private var listHeader: some View {
        HStack {
            Text(filter == .exited ? "清仓记录" : filter.rawValue)
                .font(.system(size: 15, weight: .semibold))
            Text("\(changes.count) 条")
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

    private func filterCount(_ item: HoldingDetailFilter) -> Int {
        if item == .current { return resolvedManager.positions?.count ?? resolvedManager.positionsCount }
        if item == .exited { return resolvedManager.exitedPositions?.count ?? resolvedManager.summary.exited }
        return (resolvedManager.positions ?? resolvedManager.changes).count { item.matches($0.action) }
    }

    private var footer: some View {
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
