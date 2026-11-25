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

struct FamousHoldingsView: View {
    let store: FamousHoldingsStore
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedKey: String?

    private var selectedManager: FamousHoldingsManager? {
        let managers = store.holdings?.managers ?? []
        return managers.first(where: { $0.key == selectedKey }) ?? managers.first
    }

    private var managerSelection: Binding<String?> {
        Binding(get: { selectedManager?.key }, set: { selectedKey = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let manager = selectedManager, let holdings = store.holdings, holdings.managers.count > 1 {
                    managerPicker(holdings.managers, selected: manager.key)
                } else {
                    Text("机构持仓")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 20)
                }
                DetailSheetCloseButton(action: onClose, accessibilityLabel: "关闭机构持仓")
                    .accessibilityIdentifier("detail-sheet-close")
                    .padding(.trailing, 12)
            }
            .padding(.top, 12)
            .overlay(alignment: .bottom) { Divider() }
            if let manager = selectedManager, let holdings = store.holdings {
                TabView(selection: managerSelection) {
                    ForEach(holdings.managers) { summary in
                        HoldingsPortfolio(store: store, summary: summary, disclaimer: holdings.disclaimer)
                            .tag(Optional(summary.key))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)
                .onChange(of: manager.key, initial: true) { selectedKey = manager.key }
                .task(id: manager.reportIdentity) { await store.loadDetail(for: manager) }
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
        .background(HoldingsPalette.card.ignoresSafeArea())
        .accessibilityAction(.escape) { onClose() }
        .task { await store.load() }
    }

    private func managerPicker(_ managers: [FamousHoldingsManager], selected: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(managers) { manager in
                        let isSelected = manager.key == selected
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                                selectedKey = manager.key
                            }
                        } label: {
                            Text(manager.displayName)
                                .font(.subheadline.weight(isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? ResearchDesign.accent : .secondary)
                                .fixedSize()
                                .padding(.horizontal, 12)
                                .frame(minHeight: 36)
                                .background(isSelected ? ResearchDesign.selection : ResearchDesign.fill,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(manager.key)
                        .accessibilityLabel("\(manager.institutionName)，\(manager.displayName)")
                        .accessibilityIdentifier("holding-manager-\(manager.key)")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.leading, 20)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selected, initial: true) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    proxy.scrollTo(selected, anchor: .center)
                }
            }
        }
        .accessibilityIdentifier("holding-manager-picker")
    }
}

private struct HoldingsPortfolio: View {
    let store: FamousHoldingsStore
    let summary: FamousHoldingsManager
    let disclaimer: String
    @State private var filter = HoldingPositionFilter.current
    @State private var isExpanded = false
    @ScaledMetric(relativeTo: .footnote) private var valueWidth: CGFloat = 82
    @ScaledMetric(relativeTo: .footnote) private var weightWidth: CGFloat = 58
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let previewCount = 4

    var body: some View {
        let detail = store.detail(for: summary)
        let manager = detail ?? summary
        let activeFilter = manager.canCompare ? filter : .current
        let positions = detail.map { activeFilter.positions(in: $0) } ?? []
        let preview = activeFilter == .current ? (manager.topPositions ?? []).prefix(previewCount) : []
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HoldingsPortfolioHeader(manager: manager)
                        .padding(.vertical, 10)
                        .id("holdings-top")
                    if store.errorMessage != nil {
                        Button {
                            Task { await store.load(force: true) }
                        } label: {
                            Label("刷新失败 · 正在显示已载入的申报", systemImage: "arrow.clockwise")
                                .font(.footnote.weight(.medium))
                        }
                        .frame(minHeight: 44)
                    }
                    if detail != nil {
                        positionList(positions, filter: activeFilter, canCompare: manager.canCompare)
                    } else {
                        if !preview.isEmpty {
                            columnHeadings(for: activeFilter)
                            ForEach(preview) { position in
                                positionLine(position, filter: activeFilter)
                            }
                        }
                        detailStatus
                    }
                    if detail == nil || isExpanded || positions.count <= previewCount {
                        FilingAnalysis(manager: manager, detail: detail, disclaimer: disclaimer)
                            .padding(.top, 12)
                    }
                }
                .frame(maxWidth: 660)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if detail != nil {
                    footer(manager: manager, filter: activeFilter, count: positions.count) {
                        isExpanded.toggle()
                        if !isExpanded { proxy.scrollTo("holdings-top", anchor: .top) }
                    }
                    .onChange(of: activeFilter) {
                        isExpanded = false
                        proxy.scrollTo("holdings-top", anchor: .top)
                    }
                }
            }
            .refreshable { await store.load(force: true) }
            .accessibilityIdentifier("holdings-scroll")
        }
    }

    @ViewBuilder
    private var detailStatus: some View {
        if let error = store.detailError(for: summary) {
            VStack(alignment: .leading, spacing: 4) {
                Text("持仓明细暂不可用").font(.subheadline.weight(.semibold))
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("重试") { Task { await store.loadDetail(for: summary) } }
                    .frame(minHeight: 44)
            }
            .padding(.top, 12)
        } else {
            ProgressView("正在读取完整持仓")
                .font(.footnote)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func positionList(
        _ positions: [FamousHoldingChange], filter: HoldingPositionFilter, canCompare: Bool
    ) -> some View {
        if positions.isEmpty {
            Text("该分类没有持仓")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            columnHeadings(for: filter)
            ForEach(positions.prefix(isExpanded ? positions.count : previewCount)) { position in
                let showsDetails = isExpanded || positions.count <= previewCount
                VStack(alignment: .leading, spacing: 0) {
                    positionLine(FamousHoldingPositionSummary(position), filter: filter)
                    HoldingPositionNotes(
                        position: position,
                        showsDetails: showsDetails,
                        showsChanges: canCompare && (filter != .current || showsDetails)
                    )
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func columnHeadings(for filter: HoldingPositionFilter) -> some View {
        if !dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: 8) {
                Text("公司").frame(maxWidth: .infinity, alignment: .leading)
                Text(filter == .exited ? "上期市值（亿美元）" : "市值（亿美元）")
                    .frame(width: valueWidth, alignment: .trailing)
                Text(filter == .exited ? "上期占比" : "占比")
                    .frame(width: weightWidth, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 7)
            .accessibilityHidden(true)
        }
    }

    private func positionLine(_ position: FamousHoldingPositionSummary, filter: HoldingPositionFilter) -> some View {
        let previous = filter == .exited
        let amountInHundredMillions = position.valueUsd / 100_000_000
        let amount = amountInHundredMillions > 0 && amountInHundredMillions < 0.01
            ? "<0.01" : amountInHundredMillions.formatted(.number.precision(.fractionLength(2)))
        let percentage = holdingPercent(position.weightPct)

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    positionIdentity(position)
                    Text("\(previous ? "上期市值" : "市值") \(exactHoldingUSD(position.valueUsd))")
                    Text("\(previous ? "上期占比" : "占比") \(percentage)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    positionIdentity(position)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(amount)
                        .frame(width: valueWidth, alignment: .trailing)
                        .accessibilityLabel("\(previous ? "上期市值" : "市值") \(exactHoldingUSD(position.valueUsd))")
                    Text(percentage)
                        .frame(width: weightWidth, alignment: .trailing)
                        .accessibilityLabel("\(previous ? "上期占比" : "占比") \(percentage)")
                }
            }
        }
        .font(.footnote.monospacedDigit())
        .padding(.vertical, 5)
        .frame(minHeight: 37)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }

    private func positionIdentity(_ position: FamousHoldingPositionSummary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(position.name)
                .font(.footnote.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let symbol = position.symbol, !symbol.isEmpty {
                Text(symbol)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func footer(
        manager: FamousHoldingsManager, filter: HoldingPositionFilter, count: Int, toggle: @escaping () -> Void
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                filterControl(manager: manager, filter: filter, count: count)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                expansionButton(count: count, toggle: toggle)
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 0) {
                filterControl(manager: manager, filter: filter, count: count)
                expansionButton(count: count, toggle: toggle)
            }
        }
        .frame(maxWidth: 660, alignment: .leading)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HoldingsPalette.card)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private func filterControl(manager: FamousHoldingsManager, filter activeFilter: HoldingPositionFilter, count: Int) -> some View {
        if let previousDate = manager.analytics.previousReportDate {
            Menu {
                Picker("较 \(quarterLabel(previousDate))", selection: $filter) {
                    ForEach(HoldingPositionFilter.allCases) { category in
                        Text("\(category.title) · \(category.count(in: manager)) 项").tag(category)
                    }
                }
            } label: {
                Label("\(activeFilter.title) · \(count) 项", systemImage: "chevron.up.chevron.down")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote.weight(.medium))
                    .frame(minHeight: 44)
            }
            .tint(.secondary)
            .accessibilityHint("切换持仓变动分类")
            .accessibilityIdentifier("holding-position-filters")
        } else {
            Text("\(count) 项持仓")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private func expansionButton(count: Int, toggle: @escaping () -> Void) -> some View {
        if count > previewCount {
            Button(action: toggle) {
                Label(isExpanded ? "收起" : "展开全部", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .foregroundStyle(ResearchDesign.accent)
            .accessibilityIdentifier("holding-position-expansion")
        }
    }
}

private struct HoldingsPortfolioHeader: View {
    let manager: FamousHoldingsManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                identity
                reportedValue(alignment: .leading)
            }
        } else {
            HStack(spacing: 10) {
                identity.frame(maxWidth: .infinity, alignment: .leading)
                reportedValue(alignment: .trailing).fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var identity: some View {
        HStack(spacing: 8) {
            InvestorPortraitImage(manager: manager)
            VStack(alignment: .leading, spacing: 3) {
                Text(manager.displayName)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("\(manager.institutionName) · \(quarterLabel(manager.reportDate))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func reportedValue(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(holdingUSD(manager.totalValueUsd))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(ResearchDesign.accent)
                .accessibilityLabel(exactHoldingUSD(manager.totalValueUsd))
            Text("申报市值")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FilingAnalysis: View {
    let manager: FamousHoldingsManager
    let detail: FamousHoldingsManager?
    let disclaimer: String
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    if let detail {
                        if let positions = detail.positions, !positions.isEmpty, detail.totalValueUsd > 0 {
                            allocation(positions, total: detail.totalValueUsd)
                        }
                        if detail.canCompare {
                            majorChanges(detail)
                        }
                        Divider()
                    }
                    FilingSource(manager: manager, disclaimer: disclaimer)
                }
                .padding(.bottom, 12)
            }
        } label: {
            Label("组合分析与申报来源", systemImage: "chart.bar.xaxis")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .tint(ResearchDesign.accent)
        .padding(.horizontal, 14)
        .researchPanel()
    }

    private func majorChanges(_ manager: FamousHoldingsManager) -> some View {
        let positions = (manager.positions ?? []) + (manager.exitedPositions ?? [])
        let changes = positions.filter { $0.weightChangePct != 0 }.sorted {
            let left = abs($0.weightChangePct)
            let right = abs($1.weightChangePct)
            return left == right ? $0.id < $1.id : left > right
        }
        return VStack(alignment: .leading, spacing: 12) {
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
        return VStack(alignment: .leading, spacing: 12) {
            Text("申报头寸构成")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
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

private struct FilingSource: View {
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
            Text("报告期末 \(manager.reportDate) · 申报日 \(manager.filingDate)")
            if let previousDate = manager.analytics.previousReportDate,
               let previousTotal = manager.analytics.previousTotalValueUsd, previousTotal > 0 {
                let change = manager.analytics.totalValueChangePct
                let amount = manager.analytics.totalValueChangeUsd
                let amountText = amount == 0 ? "" : "（\(amount < 0 ? "减少" : "增加") \(holdingUSD(abs(amount)))）"
                let value = Text(signedHoldingPercent(change) + amountText).foregroundStyle(weightChangeColor(change))
                Text("申报市值较 \(quarterLabel(previousDate)) \(value)")
            } else {
                Text("暂无可比较的上期市值")
            }
            Text("原始申报 \(manager.holdingsCount) 条 · 合并后 \(manager.positionsCount) 项")
            Text(disclaimer)
            Text("期权按标的证券价值计入申报市值。清仓表示上期有申报、本期未出现。")
            if manager.key == "ackman" {
                Text("头像为 [Senate Democrats 照片](https://commons.wikimedia.org/w/index.php?oldid=946520121)的裁切版 · [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/)")
            }
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
        .frame(width: 44, height: 44)
        .background(HoldingsPalette.blue.opacity(0.10), in: Circle())
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var assetName: String? {
        switch manager.key {
        case "ackman": "InvestorPortraitAckman"
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
    return "\(parts[0]) 年第 \((parts[1] - 1) / 3 + 1) 季度"
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
    let (amount, unit) = holdingUSDParts(value)
    return "\(amount) \(unit)"
}

private func holdingUSDParts(_ value: Double) -> (String, String) {
    if value >= 100_000_000 { return (String(format: "%.2f", value / 100_000_000), "亿美元") }
    if value >= 10_000 { return (String(format: "%.2f", value / 10_000), "万美元") }
    return (value.formatted(.number.precision(.fractionLength(0))), "美元")
}

func exactHoldingUSD(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0))) + " 美元"
}
