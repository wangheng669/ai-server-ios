import SwiftUI

private enum HoldingDetailFilter: String, CaseIterable, Identifiable {
    case all = "全部持仓"
    case increased = "增持"
    case decreased = "减持"
    case new = "新建仓"
    case exited = "清仓"

    var id: Self { self }

    func matches(_ action: FamousHoldingAction) -> Bool {
        switch self {
        case .all: true
        case .new: action == .new
        case .increased: action == .increased
        case .decreased: action == .decreased
        case .exited: action == .exited
        }
    }
}

struct FamousHoldingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let manager: FamousHoldingsManager
    let store: FamousHoldingsStore
    @State private var filter = HoldingDetailFilter.all
    @State private var compactRows = false

    private var resolvedManager: FamousHoldingsManager {
        store.managerDetails[manager.key] ?? manager
    }

    private var changes: [FamousHoldingChange] {
        resolvedManager.changes
            .filter { filter.matches($0.action) }
            .sorted { $0.weightPct > $1.weightPct }
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationHeader
            filterBar
            summaryCard
            listControls
            ScrollView {
                LazyVStack(spacing: 0) {
                    if store.loadingManagerKeys.contains(manager.key) && store.managerDetails[manager.key] == nil {
                        ProgressView("正在读取完整持仓")
                            .tint(.white)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                            holdingRow(change, index: index)
                            Divider().overlay(HoldingsPalette.divider).padding(.leading, 70)
                        }
                        if filter == .all, resolvedManager.positionsCount > changes.count {
                            otherHoldingsRow
                        }
                    }
                    footer
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.loadDetail(managerKey: manager.key) }
    }

    private var navigationHeader: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.07), in: Circle())
            }
            Spacer()
            Text("持仓详情")
                .font(.system(size: 19, weight: .semibold))
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease")
                Image(systemName: "magnifyingglass")
            }
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 76, height: 40)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var filterBar: some View {
        HStack(spacing: 0) {
            ForEach(HoldingDetailFilter.allCases) { item in
                Button { filter = item } label: {
                    VStack(spacing: 9) {
                        Text("\(item.rawValue) (\(filterCount(item)))")
                            .font(.system(size: 14, weight: filter == item ? .medium : .regular))
                            .foregroundStyle(filter == item ? HoldingsPalette.blue : .secondary)
                        Capsule()
                            .fill(filter == item ? HoldingsPalette.blue : .clear)
                            .frame(height: 3)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .bottom) { Divider().overlay(HoldingsPalette.divider) }
    }

    private var summaryCard: some View {
        HStack(spacing: 0) {
            detailMetric("总市值（USD）", compactUSD(resolvedManager.totalValueUsd), .white)
            Divider().frame(height: 42).overlay(HoldingsPalette.divider)
            detailMetric("持仓数量", String(resolvedManager.positionsCount), .white)
            Divider().frame(height: 42).overlay(HoldingsPalette.divider)
            detailMetric("较上期变化", signedPercent(totalChange), totalChange >= 0 ? HoldingsPalette.green : HoldingsPalette.orange)
        }
        .padding(.vertical, 16)
        .background(HoldingsPalette.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(HoldingsPalette.divider) }
        .padding(12)
    }

    private func detailMetric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 7) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .semibold)).foregroundStyle(color).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var listControls: some View {
        HStack {
            HStack(spacing: 0) {
                controlButton("list.bullet", selected: !compactRows) { compactRows = false }
                controlButton("list.dash", selected: compactRows) { compactRows = true }
            }
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            Spacer()
            Label("市值排序", systemImage: "chevron.down")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 13)
                .frame(height: 38)
                .background(Color.white.opacity(0.06), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func controlButton(_ icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 54, height: 38)
                .background(selected ? Color.white.opacity(0.07) : .clear)
        }
        .buttonStyle(.plain)
    }

    private func holdingRow(_ change: FamousHoldingChange, index: Int) -> some View {
        let color = actionColor(change.action)
        return HStack(spacing: 12) {
            HoldingsCompanyLogo(path: change.companyLogo, symbol: change.symbol, color: color)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(change.symbol ?? "—")
                        .font(.system(size: 15, weight: .semibold))
                    Text(change.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(actionLabel(change))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                Text(compactUSD(change.valueUsd))
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                TrendLine(direction: change.weightChangePct, seed: index)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 51, height: 18)
            }
            Text(percent(change.weightPct))
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: compactRows ? 64 : 78)
        .accessibilityElement(children: .combine)
    }

    private func actionLabel(_ change: FamousHoldingChange) -> String {
        let arrow = change.weightChangePct >= 0 ? "↑" : "↓"
        return "\(arrow) \(change.action.title) \(percent(abs(change.weightChangePct)))"
    }

    private func filterCount(_ item: HoldingDetailFilter) -> Int {
        if item == .all { return resolvedManager.positionsCount }
        return resolvedManager.changes.count { item.matches($0.action) }
    }

    private var otherHoldingsRow: some View {
        HStack {
            Text("其他持仓")
                .font(.system(size: 15, weight: .semibold))
            Text("(\(resolvedManager.positionsCount - changes.count) 只)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(compactUSD(otherValue))
                .font(.system(size: 15, weight: .medium))
            Text(percent(otherWeight))
                .font(.system(size: 15, weight: .medium))
                .frame(width: 52, alignment: .trailing)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .background(HoldingsPalette.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(HoldingsPalette.divider) }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var footer: some View {
        HStack {
            Text("数据来源：SEC 13F 申报")
            Spacer()
            Text("货币单位：USD")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
    }

    private var disclosedWeight: Double {
        resolvedManager.changes.reduce(0) { $0 + max(0, $1.weightPct) }
    }

    private var totalChange: Double {
        resolvedManager.changes.reduce(0) { $0 + $1.weightChangePct }
    }

    private var otherWeight: Double { max(0, 100 - min(disclosedWeight, 100)) }
    private var otherValue: Double { resolvedManager.totalValueUsd * otherWeight / 100 }
}

private struct TrendLine: Shape {
    let direction: Double
    let seed: Int

    func path(in rect: CGRect) -> Path {
        let rising = direction >= 0
        let base: [CGFloat] = rising
            ? [0.78, 0.38, 0.12, 0.32, 0.46, 0.68, 0.58, 0.74, 0.48, 0.28]
            : [0.74, 0.16, 0.38, 0.54, 0.72, 0.60, 0.82, 0.69, 0.86, 0.80]
        let offset = seed % 3
        var path = Path()
        for index in base.indices {
            let value = base[(index + offset) % base.count]
            let point = CGPoint(
                x: rect.minX + rect.width * CGFloat(index) / CGFloat(base.count - 1),
                y: rect.minY + rect.height * value
            )
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}
