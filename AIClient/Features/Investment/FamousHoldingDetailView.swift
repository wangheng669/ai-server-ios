import SwiftUI

enum HoldingDetailFilter: CaseIterable, Identifiable {
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

struct FamousHoldingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let manager: FamousHoldingsManager
    let store: FamousHoldingsStore
    let disclaimer: String
    @State private var filter: HoldingDetailFilter
    @State private var query = ""

    init(manager: FamousHoldingsManager, store: FamousHoldingsStore, filter: HoldingDetailFilter, disclaimer: String) {
        self.manager = manager
        self.store = store
        self.disclaimer = disclaimer
        _filter = State(initialValue: filter)
    }

    var body: some View {
        let detail = store.detail(for: manager)
        let resolved = detail ?? manager
        VStack(alignment: .leading, spacing: 0) {
            header(resolved)
            if resolved.canCompare {
                filters(resolved)
            }
            if let detail {
                searchField
                positionsList(detail)
            } else if let error = store.detailError(for: manager) {
                ContentUnavailableView {
                    Label("持仓明细暂不可用", systemImage: "list.bullet.rectangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重新加载") { Task { await store.loadDetail(for: manager) } }
                }
                .frame(maxHeight: .infinity)
            } else {
                ContentLoadingPlaceholder(title: "正在读取完整持仓")
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HoldingsPalette.card.ignoresSafeArea())
        .floatingSheetClose("关闭持仓明细", action: dismiss.callAsFunction)
        .task(id: manager.reportIdentity) { await store.loadDetail(for: manager) }
    }

    private func header(_ manager: FamousHoldingsManager) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(manager.institutionName)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("\(quarterLabel(manager.reportDate)) · 报告期末 \(manager.reportDate)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("\(manager.positionsCount) 项持仓 · \(holdingUSD(manager.totalValueUsd))")
                .font(.subheadline.weight(.medium).monospacedDigit())
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HoldingsPalette.card)
    }

    private func filters(_ manager: FamousHoldingsManager) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(HoldingDetailFilter.allCases) { item in
                        Button {
                            filter = item
                        } label: {
                            Text("\(item.title) \(item.count(in: manager))")
                                .font(.footnote.weight(.semibold).monospacedDigit())
                                .foregroundStyle(filter == item ? Color.white : Color.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    filter == item ? HoldingsPalette.blue : InvestmentDesign.secondarySurface,
                                    in: Capsule()
                                )
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(item)
                        .accessibilityAddTraits(filter == item ? .isSelected : [])
                        .accessibilityIdentifier("holding-filter-\(item.title)")
                    }
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: filter, initial: true) {
                proxy.scrollTo(filter, anchor: .center)
            }
        }
        .scrollIndicators(.hidden)
        .background(HoldingsPalette.card)
        .accessibilityIdentifier("holding-detail-filters")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索申报名称或 CUSIP", text: $query)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(InvestmentDesign.secondarySurface, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(HoldingsPalette.card)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func positionsList(_ detail: FamousHoldingsManager) -> some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeFilter = detail.canCompare ? filter : .current
        let rows = activeFilter.positions(in: detail).filter {
            term.isEmpty || $0.originalName.localizedStandardContains(term)
                || $0.titleOfClass.localizedStandardContains(term) || $0.cusip.localizedStandardContains(term)
        }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(rows.count) 项").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(activeFilter == .exited ? "按上期申报市值排序" : "按申报市值排序")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 10)
                if rows.isEmpty {
                    ContentUnavailableView(
                        term.isEmpty ? "该分类没有持仓" : "未找到匹配的证券",
                        systemImage: "magnifyingglass"
                    )
                }
                ForEach(rows) { row in
                    HoldingPositionRow(position: row, isDetail: true, showsChanges: detail.canCompare)
                        .padding(.vertical, 12)
                    if row.id != rows.last?.id { Divider() }
                }
                Divider().padding(.top, 8)
                FilingSource(manager: detail, disclaimer: disclaimer)
                    .padding(.top, 8)
            }
            .frame(maxWidth: 660)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 82)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

struct HoldingPositionRow: View {
    let position: FamousHoldingChange
    var isDetail = false
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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    HoldingPositionIdentity(position: position, showsCUSIP: isDetail)
                    Spacer(minLength: 0)
                    metrics
                }
                VStack(alignment: .leading, spacing: 8) {
                    HoldingPositionIdentity(position: position, showsCUSIP: isDetail)
                    metrics
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            HoldingWeightBar(weight: weight, tint: HoldingsPalette.blue)
        }
        .accessibilityElement(children: .combine)
    }
}

struct HoldingPositionIdentity: View {
    let position: FamousHoldingChange
    var showsCUSIP = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(position.originalName)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(position.titleOfClass)
                .font(.footnote)
                .foregroundStyle(.secondary)

            let type = HoldingDisclosureType(position: position)
            if type != .shares {
                Text(type.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(HoldingsPalette.blue)
            }
            if showsCUSIP {
                Text(position.cusip)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
