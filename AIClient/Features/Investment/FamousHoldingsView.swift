import SwiftUI
import UIKit

enum HoldingsPalette {
    static let blue = InvestmentDesign.accent
    static let green = InvestmentDesign.loss
    static let orange = InvestmentDesign.warning
    static let red = InvestmentDesign.gain
    static let purple = InvestmentDesign.accent
    static let teal = Color(red: 0.08, green: 0.65, blue: 0.66)
    static let divider = InvestmentDesign.divider
    static let card = InvestmentDesign.surface
    static let canvas = InvestmentDesign.canvas
}

private struct HoldingDetailRoute: Identifiable {
    let manager: FamousHoldingsManager
    let filter: HoldingDetailFilter
    let disclaimer: String
    var id: FamousHoldingsReportIdentity { manager.reportIdentity }
}

struct FamousHoldingsView: View {
    let store: FamousHoldingsStore
    @State private var selectedKey: String?
    @State private var selectedDetail: HoldingDetailRoute?

    private var selectedManager: FamousHoldingsManager? {
        let managers = store.holdings?.managers ?? []
        return managers.first(where: { $0.key == selectedKey }) ?? managers.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let manager = selectedManager, let holdings = store.holdings {
                managerPicker(holdings.managers, selected: manager.key)
                overview(manager, holdings: holdings)
                    .id(manager.key)
            } else if store.isLoading || store.errorMessage == nil && store.holdings == nil {
                ContentLoadingPlaceholder(title: "正在读取 13F 申报", layout: .cards)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ContentUnavailableView {
                    Label("机构持仓暂不可用", systemImage: "chart.bar.doc.horizontal")
                } description: {
                    Text(store.errorMessage ?? "暂无公开申报")
                } actions: {
                    Button("重新加载") { Task { await store.load(force: true) } }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HoldingsPalette.canvas.ignoresSafeArea())
        .task {
            await store.load()
            #if DEBUG
            if selectedDetail == nil, let holdings = store.holdings,
               let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--holdings-detail-preview=") }),
               let manager = holdings.managers.first(where: { $0.key == String(argument.dropFirst("--holdings-detail-preview=".count)) }) {
                selectedDetail = HoldingDetailRoute(manager: manager, filter: .current, disclaimer: holdings.disclaimer)
            }
            #endif
        }
        .appSheet(item: $selectedDetail) { route in
            FamousHoldingDetailView(manager: route.manager, store: store, filter: route.filter, disclaimer: route.disclaimer)
                .appPresentationDetents([.large])
                .appPresentationCornerRadius(24)
                .appPresentationScrollsWithoutExpanding()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("机构持仓")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let holdings = store.holdings, !holdings.managers.isEmpty {
                Text("\(holdings.managers.count) 家机构")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .background(HoldingsPalette.card)
    }

    private func managerPicker(_ managers: [FamousHoldingsManager], selected: String) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(managers) { manager in
                    let isSelected = manager.key == selected
                    Button {
                        selectedKey = manager.key
                    } label: {
                        HStack(spacing: 7) {
                            InvestorPortraitImage(manager: manager)
                            Text(manager.displayName)
                                .font(.subheadline.weight(.semibold))
                                .fixedSize()
                        }
                        .foregroundStyle(isSelected ? HoldingsPalette.blue : Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ? HoldingsPalette.blue.opacity(0.10) : InvestmentDesign.secondarySurface,
                            in: Capsule()
                        )
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(manager.institutionName)，\(manager.displayName)")
                    .accessibilityIdentifier("holding-manager-\(manager.key)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 6)
        .background(HoldingsPalette.card)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityIdentifier("holding-manager-picker")
    }

    private func overview(_ manager: FamousHoldingsManager, holdings: FamousHoldings) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if store.errorMessage != nil {
                    Button {
                        Task { await store.load(force: true) }
                    } label: {
                        Label("刷新失败 · 正在显示上次申报数据", systemImage: "arrow.clockwise")
                            .font(.footnote.weight(.medium))
                    }
                    .frame(minHeight: 44)
                }
                filingCard(manager)
                topHoldings(manager)
                quarterlyActivity(manager)
                if let detail = store.detail(for: manager),
                   detail.reportIdentity == manager.reportIdentity {
                    if detail.canCompare {
                        majorChanges(detail)
                    }
                    if let positions = detail.positions, !positions.isEmpty, detail.totalValueUsd > 0 {
                        allocation(positions, total: detail.totalValueUsd)
                    }
                }
                FilingSource(manager: manager, disclaimer: holdings.disclaimer)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: 660)
            .padding(.horizontal, InvestmentDesign.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 82)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await store.load(force: true) }
        .accessibilityIdentifier("holdings-overview-scroll")
    }

    private func filingCard(_ manager: FamousHoldingsManager) -> some View {
        HoldingsPanel {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(manager.institutionName)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("报告期末 \(manager.reportDate)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(quarterLabel(manager.reportDate))
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(HoldingsPalette.blue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(HoldingsPalette.blue.opacity(0.10), in: Capsule())
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("申报持仓市值")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(holdingUSD(manager.totalValueUsd))
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
                    .accessibilityLabel(exactHoldingUSD(manager.totalValueUsd))
                if let previousDate = manager.analytics.previousReportDate,
                   let previousTotal = manager.analytics.previousTotalValueUsd, previousTotal > 0 {
                    let change = manager.analytics.totalValueChangePct
                    let difference = manager.analytics.totalValueChangeUsd
                    let direction = difference < 0 ? "减少" : "增加"
                    Text("较 \(quarterLabel(previousDate)) \(signedHoldingPercent(change))")
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(weightChangeColor(change))
                    if difference != 0 {
                        Text("\(direction) \(holdingUSD(abs(difference)))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("暂无可比较的上期市值")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top) {
                    filingMetric("持仓头寸", "\(manager.positionsCount) 项")
                    Spacer(minLength: 10)
                    filingMetric("SEC 申报日", manager.filingDate)
                }
                VStack(alignment: .leading, spacing: 10) {
                    filingMetric("持仓头寸", "\(manager.positionsCount) 项")
                    filingMetric("SEC 申报日", manager.filingDate)
                }
            }
        }
    }

    private func filingMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private func topHoldings(_ manager: FamousHoldingsManager) -> some View {
        HoldingsPanel {
            Text("主要持仓")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let detail = store.detail(for: manager), detail.reportIdentity == manager.reportIdentity {
                let positions = detail.positions ?? []
                let top = positions.prefix(10)
                if top.isEmpty {
                    Text("该申报没有持仓头寸").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(top.prefix(5)) { row in
                        HoldingPositionRow(position: row, showsChanges: false)
                    }
                    if detail.totalValueUsd > 0 {
                        let share = top.reduce(0) { $0 + $1.valueUsd } / detail.totalValueUsd * 100
                        Text("前 \(top.count) 项占申报市值 \(holdingPercent(share))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if store.detail(for: manager) != nil {
                Button("发现更新的申报，刷新总览") { Task { await store.load(force: true) } }
                    .font(.footnote)
            } else if let error = store.detailError(for: manager) {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("重试持仓明细") { Task { await store.loadDetail(for: manager) } }
                    .font(.footnote)
            } else {
                ProgressView("正在读取持仓明细")
                    .font(.footnote)
                    .padding(.vertical, 8)
            }
            Button {
                openDetail(manager, filter: .current)
            } label: {
                HStack {
                    Text("查看全部 \(manager.positionsCount) 项持仓")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(HoldingsPalette.blue)
        }
        .task(id: manager.reportIdentity) { await store.loadDetail(for: manager) }
    }

    private func quarterlyActivity(_ manager: FamousHoldingsManager) -> some View {
        HoldingsPanel {
            Text("季度持仓变化")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let previousDate = manager.analytics.previousReportDate {
                Text("对比 \(quarterLabel(previousDate)) · 按申报数量变化分类")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(HoldingDetailFilter.allCases.dropFirst()) { filter in
                        Button {
                            openDetail(manager, filter: filter)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(filter.count(in: manager))")
                                    .font(.title3.weight(.semibold).monospacedDigit())
                                Text(filter.title)
                                    .font(.footnote)
                            }
                            .foregroundStyle(filter.action.map(actionColor) ?? Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(InvestmentDesign.secondarySurface, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                Text("暂无上期申报可比较").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func majorChanges(_ manager: FamousHoldingsManager) -> some View {
        let positions = (manager.positions ?? []) + (manager.exitedPositions ?? [])
        let changes = positions.filter { $0.weightChangePct != 0 }.sorted {
            let left = abs($0.weightChangePct)
            let right = abs($1.weightChangePct)
            return left == right ? $0.id < $1.id : left > right
        }
        return HoldingsPanel {
            Text("主要权重变化")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if changes.isEmpty {
                Text("权重与上期相同").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("按权重变化绝对值排序")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(changes.prefix(3)) { change in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        HoldingPositionIdentity(position: change)
                        Spacer(minLength: 0)
                        Text(holdingPercentagePoints(change.weightChangePct))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(weightChangeColor(change.weightChangePct))
                            .fixedSize()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func allocation(_ positions: [FamousHoldingChange], total: Double) -> some View {
        let amounts = positions.reduce(into: [HoldingDisclosureType: Double]()) { values, position in
            values[HoldingDisclosureType(position: position), default: 0] += position.valueUsd
        }
        return HoldingsPanel {
            Text("申报头寸构成")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("按 13F 申报类型 · 占申报市值")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(HoldingDisclosureType.allCases.filter { amounts[$0] != nil }) { type in
                let weight = amounts[type, default: 0] / total * 100
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(type.rawValue).font(.subheadline)
                        Spacer(minLength: 8)
                        Text(holdingPercent(weight))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .fixedSize()
                    }
                    HoldingWeightBar(weight: weight, tint: HoldingsPalette.blue)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func openDetail(_ manager: FamousHoldingsManager, filter: HoldingDetailFilter) {
        guard let holdings = store.holdings else { return }
        selectedDetail = HoldingDetailRoute(manager: manager, filter: filter, disclaimer: holdings.disclaimer)
    }
}

struct HoldingsPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HoldingsPalette.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct HoldingWeightBar: View {
    let weight: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(tint.opacity(0.10))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * min(max(weight / 100, 0), 1))
                }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

struct FilingSource: View {
    let manager: FamousHoldingsManager
    let disclaimer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = manager.filingUrl {
                Link(destination: url) {
                    Label("SEC 13F 申报原文", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
            } else {
                Text("数据来源 · SEC 13F 申报").font(.footnote.weight(.semibold))
            }
            Text("原始申报 \(manager.holdingsCount) 条 · 合并后 \(manager.positionsCount) 项")
            Text(disclaimer)
            Text("期权按标的证券价值计入申报市值。清仓表示上期有申报、本期未出现。")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InvestorPortraitImage: View {
    let manager: FamousHoldingsManager

    var body: some View {
        Group {
            if let assetName, let portrait = UIImage(named: assetName) {
                Image(uiImage: portrait).resizable().scaledToFill()
            } else {
                Text(manager.displayName.prefix(1))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HoldingsPalette.blue)
            }
        }
        .frame(width: 24, height: 24)
        .background(HoldingsPalette.blue.opacity(0.10), in: Circle())
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var assetName: String? {
        switch manager.key {
        case "ark": "InvestorPortraitARK"
        case "berkshire": "InvestorPortraitBerkshire"
        case "duanyongping": "InvestorPortraitDuanYongping"
        case "lilu": "InvestorPortraitLiLu"
        case "danbin": "InvestorPortraitDanBin"
        case "bridgewater": "InvestorPortraitBridgewater"
        case "soros": "InvestorPortraitSoros"
        case "sunmasayoshi": "InvestorPortraitMasayoshiSon"
        default: nil
        }
    }
}

func actionColor(_ action: FamousHoldingAction) -> Color {
    switch action {
    case .new: HoldingsPalette.blue
    case .increased: HoldingsPalette.red
    case .decreased: HoldingsPalette.green
    case .exited: HoldingsPalette.orange
    case .unchanged: .secondary
    }
}

func weightChangeColor(_ change: Double) -> Color {
    if change > 0 { return HoldingsPalette.red }
    if change < 0 { return HoldingsPalette.green }
    return .secondary
}

func quarterLabel(_ date: String) -> String {
    let parts = date.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, (1...12).contains(parts[1]) else { return date }
    return "\(parts[0]) Q\((parts[1] - 1) / 3 + 1)"
}

func holdingPercent(_ value: Double) -> String {
    if value > 0, value < 0.01 { return "<0.01%" }
    return String(format: "%.2f%%", value)
}

func signedHoldingPercent(_ value: Double) -> String {
    signedHoldingNumber(value) + "%"
}

func holdingPercentagePoints(_ value: Double) -> String {
    signedHoldingNumber(value) + " 个百分点"
}

private func signedHoldingNumber(_ value: Double) -> String {
    guard value != 0 else { return "0.00" }
    let magnitude = abs(value)
    let sign = value > 0 ? "+" : "−"
    return sign + String(format: magnitude < 0.01 ? "%.4f" : "%.2f", magnitude)
}

func holdingUSD(_ value: Double) -> String {
    if value >= 100_000_000 { return String(format: "%.2f 亿美元", value / 100_000_000) }
    if value >= 10_000 { return String(format: "%.2f 万美元", value / 10_000) }
    return exactHoldingUSD(value)
}

func exactHoldingUSD(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0))) + " 美元"
}
