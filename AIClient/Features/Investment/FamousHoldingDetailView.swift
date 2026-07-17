import SwiftUI

private enum HoldingDetailFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case new = "新建仓"
    case increased = "增持"
    case decreased = "减持"
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
    let manager: FamousHoldingsManager
    let store: FamousHoldingsStore
    @State private var filter = HoldingDetailFilter.all

    private var resolvedManager: FamousHoldingsManager {
        store.managerDetails[manager.key] ?? manager
    }

    private var changes: [FamousHoldingChange] {
        resolvedManager.changes.filter { filter.matches($0.action) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                managerHero
                summaryGrid
                filterBar
                if store.loadingManagerKeys.contains(manager.key) && store.managerDetails[manager.key] == nil {
                    ProgressView("正在读取完整持仓")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ForEach(changes) { change in
                        detailRow(change)
                        Divider().padding(.leading, 72)
                    }
                }
                Text("数据来自公开 13F 披露，不代表当前实时持仓")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 22)
            }
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle("详细持仓")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { await store.loadDetail(managerKey: manager.key) }
    }

    private var managerHero: some View {
        HStack(spacing: 14) {
            FamousInvestorAvatar(name: resolvedManager.displayName, key: resolvedManager.key)
                .scaleEffect(1.25)
                .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(resolvedManager.displayName).font(.title2.bold())
                Text(resolvedManager.institutionName).font(.subheadline).foregroundStyle(.secondary)
                Text("\(quarterLabel(resolvedManager.reportDate)) · 申报 \(resolvedManager.filingDate)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 20)
    }

    private var summaryGrid: some View {
        VStack(spacing: 14) {
            HStack {
                metric("持仓市值", compactUSD(resolvedManager.totalValueUsd), .primary)
                metric("持仓数量", "\(resolvedManager.positionsCount)", .primary)
                metric("变化数量", "\(resolvedManager.changesCount)", .primary)
            }
            HStack {
                metric("新建仓", "\(resolvedManager.summary.new)", HoldingsPalette.blue)
                metric("增持", "\(resolvedManager.summary.increased)", HoldingsPalette.green)
                metric("减持", "\(resolvedManager.summary.decreased)", HoldingsPalette.orange)
                metric("清仓", "\(resolvedManager.summary.exited)", HoldingsPalette.red)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 18)
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(color).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HoldingDetailFilter.allCases) { item in
                    Button { filter = item } label: {
                        Text(item.rawValue)
                            .font(.subheadline.weight(filter == item ? .semibold : .regular))
                            .foregroundStyle(filter == item ? Color.white : Color.primary)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(filter == item ? Color.blue : Color.primary.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func detailRow(_ change: FamousHoldingChange) -> some View {
        let color = actionColor(change.action)
        return HStack(spacing: 12) {
            HoldingsCompanyLogo(path: change.companyLogo, symbol: change.symbol, color: color)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(change.symbol ?? "—").font(.subheadline.weight(.semibold))
                    Text(change.action.title).font(.caption2.weight(.semibold)).foregroundStyle(color)
                }
                Text(change.name).font(.subheadline).lineLimit(1)
                Text("市值 \(compactUSD(change.valueUsd))").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(percent(change.previousWeightPct)) → \(percent(change.weightPct))")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Text(signedPercent(change.weightChangePct))
                    .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(color)
            }
        }
        .padding(.horizontal, 18).frame(minHeight: 76)
    }
}

private func actionColor(_ action: FamousHoldingAction) -> Color {
    switch action {
    case .new: HoldingsPalette.blue
    case .increased: HoldingsPalette.green
    case .decreased: HoldingsPalette.orange
    case .exited: HoldingsPalette.red
    }
}

private func compactUSD(_ value: Double) -> String {
    if value >= 1_000_000_000 { return String(format: "$%.1fB", value / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "$%.1fM", value / 1_000_000) }
    return String(format: "$%.0f", value)
}
