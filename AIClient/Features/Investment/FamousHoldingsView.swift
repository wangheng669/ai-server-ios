import SwiftUI
import UIKit

enum HoldingsPalette {
    static let blue = InvestmentDesign.accent
    static let green = InvestmentDesign.loss
    static let orange = InvestmentDesign.warning
    static let red = InvestmentDesign.gain
    static let purple = InvestmentDesign.accent
    static let indigo = InvestmentDesign.accent
    static let pink = Color(red: 0.91, green: 0.31, blue: 0.52)
    static let teal = Color(red: 0.08, green: 0.65, blue: 0.66)
    static let divider = InvestmentDesign.divider
    static let card = InvestmentDesign.surface
    static let canvas = InvestmentDesign.canvas
}

private struct HoldingSector: Identifiable {
    let name: String
    let value: Double
    let color: Color
    var id: String { name }
}

private struct HoldingDetailRoute: Identifiable, Equatable {
    let managerKey: String
    var id: String { managerKey }
}

struct FamousHoldingsView: View {
    let store: FamousHoldingsStore
    @Binding var showsDetail: Bool
    @State private var selectedIndex = 0
    @State private var selectedDetail: HoldingDetailRoute?
    @State private var isManagerSelectorExpanded = false

    private var managers: [FamousHoldingsManager] {
        (store.holdings?.managers ?? []).sorted { managerPriority($0.key) < managerPriority($1.key) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if managers.indices.contains(selectedIndex) {
                        let manager = managers[selectedIndex]
                        overview(store.managerDetails[manager.key] ?? manager)
                    } else if store.isLoading {
                        ProgressView("正在读取公开持仓披露").foregroundStyle(.secondary)
                    } else {
                        unavailableView
                    }
                }

                if managers.count > 1 {
                    if isManagerSelectorExpanded {
                        Color.black.opacity(0.08)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { closeManagerSelector() }
                            .transition(.opacity)
                    }

                    managerSelector
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HoldingsPalette.canvas.ignoresSafeArea())
            .task {
                await store.load()
                #if DEBUG
                if selectedDetail == nil,
                   let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--holdings-detail-preview=") }) {
                    selectedDetail = HoldingDetailRoute(
                        managerKey: String(argument.dropFirst("--holdings-detail-preview=".count))
                    )
                }
                #endif
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $selectedDetail, onDismiss: {
            showsDetail = false
        }) { route in
            NavigationStack {
                if let manager = managers.first(where: { $0.key == route.managerKey }) {
                    FamousHoldingDetailView(manager: manager, store: store)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationContentInteraction(.scrolls)
        }
        .onChange(of: selectedDetail) { _, value in
            if value != nil {
                showsDetail = true
            }
        }
        .onAppear { showsDetail = selectedDetail != nil }
        .onDisappear { showsDetail = false }
    }

    private func overview(_ manager: FamousHoldingsManager) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                hero(manager)
                sectionDivider
                portfolioSnapshot(manager)
                sectionDivider
                coreHoldings(manager)
                sectionDivider
                quarterlyActivity(manager)
                sectionDivider
                majorChanges(manager)
                footer(manager)
            }
            .background(HoldingsPalette.card)
            .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.load(force: true) }
        .task(id: manager.key) { await store.loadDetail(managerKey: manager.key) }
    }

    private var managerSelector: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if isManagerSelectorExpanded {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(managers.enumerated()), id: \.element.key) { index, manager in
                            managerOption(manager, at: index)
                        }
                    }
                    .padding(7)
                }
                .scrollIndicators(.hidden)
                .frame(width: 252)
                .frame(maxHeight: 356)
                .background(HoldingsPalette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(HoldingsPalette.divider, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 24, y: 10)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity),
                        removal: .scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity)
                    )
                )
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                    isManagerSelectorExpanded.toggle()
                }
            } label: {
                Group {
                    if managers.indices.contains(selectedIndex) {
                        InvestorPortraitImage(manager: managers[selectedIndex], contentMode: .fill)
                            .frame(width: 38, height: 38)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 38, height: 38)
                            .background(Color.secondary.opacity(0.10), in: Circle())
                    }
                }
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle().stroke(HoldingsPalette.purple.opacity(0.60), lineWidth: 1.5)
                }
                .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "选择投资人，当前\(managers.indices.contains(selectedIndex) ? managers[selectedIndex].displayName : "未选择")"
            )
            .accessibilityValue(isManagerSelectorExpanded ? "已展开" : "已收起")
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: isManagerSelectorExpanded)
    }

    private func managerOption(_ manager: FamousHoldingsManager, at index: Int) -> some View {
        Button {
            selectManager(at: index)
        } label: {
            HStack(spacing: 11) {
                InvestorPortraitImage(manager: manager, contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(
                            index == selectedIndex ? HoldingsPalette.purple.opacity(0.65) : HoldingsPalette.divider,
                            lineWidth: index == selectedIndex ? 2 : 1
                        )
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(manager.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(manager.institutionName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(HoldingsPalette.purple, in: Circle())
                    .opacity(index == selectedIndex ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 56)
            .background(
                index == selectedIndex ? HoldingsPalette.purple.opacity(0.09) : Color.clear,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(manager.displayName)，\(manager.institutionName)")
        .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
    }

    private func hero(_ manager: FamousHoldingsManager) -> some View {
        HStack(alignment: .center, spacing: 13) {
            InvestorPortraitImage(manager: manager, contentMode: .fill)
                .frame(width: 58, height: 58)
                .clipShape(Circle())
                .overlay(Circle().stroke(HoldingsPalette.purple.opacity(0.30), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(manager.displayName)
                        .font(.system(size: 20, weight: .bold))
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(HoldingsPalette.indigo)
                }
                Text("\(englishName(manager)) · \(manager.institutionName)")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(quarterLabel(manager.reportDate))
                    Text("披露 \(compactDate(manager.filingDate))")
                    Text("SEC 13F")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { selectedDetail = HoldingDetailRoute(managerKey: manager.key) } label: {
                VStack(spacing: 4) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 16, weight: .semibold))
                    Text("全部")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(HoldingsPalette.purple)
                .frame(width: 48, height: 48)
                .background(HoldingsPalette.purple.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看 \(manager.displayName) 的全部持仓")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .accessibilityAction(named: "下一个人物") { moveManager(by: 1) }
        .accessibilityAction(named: "上一个人物") { moveManager(by: -1) }
    }

    private func portfolioSnapshot(_ manager: FamousHoldingsManager) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                snapshotMetric(
                    "持仓市值",
                    dollarValue(manager.totalValueUsd),
                    portfolioValueChangeCaption(manager),
                    captionColor: portfolioValueChangeTint(manager)
                )
                summaryDivider
                snapshotMetric("持仓数量", "\(manager.positionsCount) 只", nil)
                summaryDivider
                snapshotMetric("前十集中度", percent(topTenConcentration(manager)), concentrationCaption(manager))
                summaryDivider
                snapshotMetric("季度变动", "\(manager.changesCount) 只", activityCaption(manager.summary))
            }

            sectorAllocation(manager)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func snapshotMetric(
        _ title: String,
        _ value: String,
        _ caption: String?,
        captionColor: Color = HoldingsPalette.purple
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            if let caption {
                Text(caption)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(captionColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 49, alignment: .leading)
    }

    private func sectorAllocation(_ manager: FamousHoldingsManager) -> some View {
        let sectors = Array(sectorData(manager).prefix(4))
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("行业配置")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                ForEach(sectors) { sector in
                    HStack(spacing: 3) {
                        Circle().fill(sector.color).frame(width: 5, height: 5)
                        Text("\(sector.name) \(percent(sector.value))")
                    }
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }

            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(sectors) { sector in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(sector.color)
                            .frame(width: max(3, proxy.size.width * sector.value / 100))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
        }
    }

    private func coreHoldings(_ manager: FamousHoldingsManager) -> some View {
        let positions = Array(currentPositions(manager).sorted { $0.weightPct > $1.weightPct }.prefix(5))
        return VStack(spacing: 0) {
            sectionHeader(
                title: "核心持仓",
                detail: "前 5 · 共 \(manager.positionsCount) 只",
                action: { selectedDetail = HoldingDetailRoute(managerKey: manager.key) }
            )

            ForEach(Array(positions.enumerated()), id: \.element.id) { index, position in
                compactHoldingRow(position, rank: index + 1)
                if index < positions.count - 1 {
                    Divider().overlay(HoldingsPalette.divider).padding(.leading, 60)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func compactHoldingRow(_ position: FamousHoldingChange, rank: Int) -> some View {
        let changeColor = changeTint(position)
        return HStack(spacing: 9) {
            Text("\(rank)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 11)
            HoldingsCompanyLogo(
                path: position.companyLogo,
                symbol: displaySymbol(position),
                color: actionColor(position.action),
                size: 30
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(displaySymbol(position))
                    .font(.system(size: 12.5, weight: .bold))
                Text(chineseCompanyName(position))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            holdingValue("权重", percent(position.weightPct), .primary, width: 54)
            holdingValue("市值", compactDollarValue(position.valueUsd), .primary, width: 61)
            holdingValue("变动", signedPercent(position.weightChangePct), changeColor, width: 54)
        }
        .frame(minHeight: 46)
        .accessibilityElement(children: .combine)
    }

    private func holdingValue(_ title: String, _ value: String, _ color: Color, width: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
        }
        .frame(width: width, alignment: .trailing)
    }

    private func quarterlyActivity(_ manager: FamousHoldingsManager) -> some View {
        VStack(spacing: 10) {
            sectionHeader(title: "季度动作", detail: "按变动持仓数量", action: nil)
            HStack(spacing: 0) {
                activityMetric("新建仓", manager.summary.new, HoldingsPalette.blue, manager.summary)
                summaryDivider
                activityMetric("增持", manager.summary.increased, HoldingsPalette.green, manager.summary)
                summaryDivider
                activityMetric("减持", manager.summary.decreased, HoldingsPalette.orange, manager.summary)
                summaryDivider
                activityMetric("清仓", manager.summary.exited, HoldingsPalette.pink, manager.summary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func activityMetric(
        _ title: String,
        _ value: Int,
        _ color: Color,
        _ summary: FamousHoldingsSummary
    ) -> some View {
        let total = max(1, summary.new + summary.increased + summary.decreased + summary.exited)
        return VStack(spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title).font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
                Text(percent(Double(value) / Double(total) * 100))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func majorChanges(_ manager: FamousHoldingsManager) -> some View {
        let changes = Array(manager.changes.sorted { abs($0.weightChangePct) > abs($1.weightChangePct) }.prefix(5))
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "主要调仓", detail: "按权重变化排序", action: nil)
            ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                biggestChangeRow(change)
                if index < changes.count - 1 {
                    Divider().overlay(HoldingsPalette.divider).padding(.leading, 52)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func sectionHeader(title: String, detail: String, action: (() -> Void)?) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            if let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(detail)
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 9.5, weight: .medium))
    }

    private func topTenConcentration(_ manager: FamousHoldingsManager) -> Double {
        currentPositions(manager)
            .sorted { $0.weightPct > $1.weightPct }
            .prefix(10)
            .reduce(0) { $0 + $1.weightPct }
    }

    private func concentrationCaption(_ manager: FamousHoldingsManager) -> String {
        guard let leader = currentPositions(manager).max(by: { $0.weightPct < $1.weightPct }) else { return "暂无持仓" }
        return "首位 \(percent(leader.weightPct))"
    }

    private func activityCaption(_ summary: FamousHoldingsSummary) -> String {
        let additions = summary.new + summary.increased
        let reductions = summary.decreased + summary.exited
        if additions == reductions { return "增减平衡" }
        return additions > reductions ? "增配偏多" : "减配偏多"
    }

    private func portfolioValueChangeCaption(_ manager: FamousHoldingsManager) -> String {
        guard let change = manager.valueChangeFromPreviousReport else { return "暂无上期数据" }
        let arrow = change.amountUsd > 0 ? "↑" : change.amountUsd < 0 ? "↓" : "→"
        return "\(arrow) \(compactDollarValue(abs(change.amountUsd))) \(signedPercent(change.percent))"
    }

    private func portfolioValueChangeTint(_ manager: FamousHoldingsManager) -> Color {
        guard let change = manager.valueChangeFromPreviousReport else { return .secondary }
        if change.amountUsd > 0 { return HoldingsPalette.red }
        if change.amountUsd < 0 { return HoldingsPalette.green }
        return .secondary
    }

    private func compactDate(_ value: String) -> String {
        let parts = value.split(separator: "-")
        guard parts.count == 3 else { return value }
        return "\(parts[1])-\(parts[2])"
    }

    private func compactDollarValue(_ value: Double) -> String {
        if value >= 1_000_000_000 { return String(format: "$%.1fB", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "$%.0fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "$%.0fK", value / 1_000) }
        return String(format: "$%.0f", value)
    }

    private var summaryDivider: some View {
        Rectangle().fill(HoldingsPalette.divider).frame(width: 1, height: 34)
    }

    private var sectionDivider: some View {
        Divider()
            .overlay(HoldingsPalette.divider)
            .padding(.horizontal, 20)
    }


    private func biggestChangeRow(_ change: FamousHoldingChange) -> some View {
        let tint = changeTint(change)
        return HStack(spacing: 12) {
            HoldingsCompanyLogo(path: change.companyLogo, symbol: displaySymbol(change), color: actionColor(change.action), size: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displaySymbol(change)).font(.system(size: 15, weight: .bold))
                    Text(change.action.title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(actionColor(change.action))
                        .padding(.horizontal, 6)
                        .frame(height: 17)
                        .background(actionColor(change.action).opacity(0.12), in: Capsule())
                }
                Text("\(chineseCompanyName(change)) · \(companyCategory(change))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(signedPercent(change.weightChangePct))
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(tint.opacity(0.13), in: Capsule())
                Text("权重变化").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }

    private func changeTint(_ change: FamousHoldingChange) -> Color {
        if change.action == .new { return HoldingsPalette.purple }
        return change.weightChangePct < 0 ? HoldingsPalette.red : HoldingsPalette.green
    }

    private func englishName(_ manager: FamousHoldingsManager) -> String {
        switch manager.key {
        case "ark": "Cathie Wood"
        case "berkshire": "Warren Buffett"
        case "duanyongping": "Duan Yongping"
        case "lilu": "Li Lu"
        case "danbin": "Dan Bin"
        case "bridgewater": "Ray Dalio"
        case "soros": "George Soros"
        case "sunmasayoshi": "Masayoshi Son"
        default: manager.displayName
        }
    }

    private func companyCategory(_ change: FamousHoldingChange) -> String {
        switch displaySymbol(change) {
        case "ROKU": "流媒体平台"
        case "CRCL", "COIN", "HOOD", "SQ": "金融科技"
        case "AVGO", "AMD", "NVDA": "半导体"
        default: sectorName(displaySymbol(change))
        }
    }

    private func footer(_ manager: FamousHoldingsManager) -> some View {
        HStack {
            Text("数据来源：13F 申报文件")
            Spacer()
            Text("货币：USD")
        }
        .font(.system(size: 8))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { sectionDivider }
    }

    private func selectManager(at index: Int) {
        guard managers.indices.contains(index) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
            selectedIndex = index
            isManagerSelectorExpanded = false
        }
    }

    private func closeManagerSelector() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
            isManagerSelectorExpanded = false
        }
    }

    private func moveManager(by offset: Int) {
        let next = selectedIndex + offset
        guard managers.indices.contains(next) else { return }
        withAnimation(.easeInOut(duration: 0.22)) { selectedIndex = next }
    }

    private func currentPositions(_ manager: FamousHoldingsManager) -> [FamousHoldingChange] {
        manager.positions ?? manager.changes.filter { $0.action != .exited }
    }

    private func sectorData(_ manager: FamousHoldingsManager) -> [HoldingSector] {
        var totals: [String: Double] = [:]
        for change in currentPositions(manager) {
            totals[sectorName(displaySymbol(change)), default: 0] += max(0, change.weightPct)
        }
        let known = min(totals.values.reduce(0, +), 100)
        totals["其他", default: 0] += max(0, 100 - known)
        let colors: [String: Color] = [
            "信息技术": HoldingsPalette.purple,
            "非必需消费": HoldingsPalette.orange,
            "医疗保健": HoldingsPalette.teal,
            "金融": HoldingsPalette.pink,
            "通信服务": HoldingsPalette.green,
            "其他": .gray
        ]
        return totals.map { HoldingSector(name: $0.key, value: $0.value, color: colors[$0.key] ?? .gray) }
            .sorted { $0.value > $1.value }
    }

    private func sectorName(_ symbol: String?) -> String {
        switch symbol?.uppercased() {
        case "TSLA", "RBLX", "AMZN", "NKE", "SHOP": "非必需消费"
        case "CRSP", "TEM", "TDOC", "RXRX", "BEAM": "医疗保健"
        case "COIN", "SQ", "HOOD": "金融"
        case "ROKU", "ZM", "META", "GOOG": "通信服务"
        case "AMD", "PLTR", "PATH", "NVDA", "AAPL": "信息技术"
        default: "其他"
        }
    }

    private func chineseCompanyName(_ change: FamousHoldingChange) -> String {
        switch displaySymbol(change) {
        case "TSLA": "特斯拉"
        case "AMD": "超威半导体"
        case "CRSP": "CRISPR疗法"
        case "RBLX": "罗布乐思"
        case "COIN": "Coinbase"
        case "SQ": "Block"
        case "ROKU": "Roku"
        case "HOOD": "Robinhood"
        case "SHOP": "Shopify"
        case "PLTR": "Palantir"
        case "ZM": "Zoom"
        case "PATH": "UiPath"
        default: change.name
        }
    }

    private func displaySymbol(_ change: FamousHoldingChange) -> String {
        if let symbol = change.symbol?.uppercased(), !symbol.isEmpty { return symbol }
        let name = change.name.uppercased()
        if name.contains("TESLA") { return "TSLA" }
        if name.contains("ADVANCED MICRO") { return "AMD" }
        if name.contains("CRISPR") { return "CRSP" }
        if name.contains("SHOPIFY") { return "SHOP" }
        if name.contains("PALANTIR") { return "PLTR" }
        if name.contains("TEMPUS") { return "TEM" }
        if name.contains("ROBINHOOD") { return "HOOD" }
        if name.contains("COINBASE") { return "COIN" }
        if name.contains("TERADYNE") { return "TER" }
        if name.contains("CIRCLE") { return "CRCL" }
        if name.contains("ROKU") { return "ROKU" }
        return "—"
    }

    private func investorImage(_ manager: FamousHoldingsManager) -> some View {
        InvestorPortraitImage(manager: manager)
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label("持仓数据暂不可用", systemImage: "chart.pie")
        } description: {
            Text(store.errorMessage ?? "暂时没有可展示的公开持仓")
        } actions: {
            Button("重新加载") { Task { await store.load(force: true) } }
        }
    }
}

private struct InvestorPortraitImage: View {
    let manager: FamousHoldingsManager
    var contentMode: ContentMode = .fit
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(InvestorPortraitLoader.placeholderColor(for: manager).gradient)

            Text(InvestorPortraitLoader.monogram(for: manager))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            }
        }
        .clipped()
        .task(id: manager.key) {
            image = InvestorPortraitLoader.bundledImage(for: manager)
            let loaded = await InvestorPortraitLoader.load(manager)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) { image = loaded }
        }
    }
}

enum InvestorPortraitLoader {
    @MainActor
    static func load(_ manager: FamousHoldingsManager) async -> UIImage? {
        if let remoteImage = await ImageLoader.load(url(for: manager), targetSize: targetSize) {
            return remoteImage
        }
        return bundledImage(for: manager)
    }

    @MainActor
    static func bundledImage(for manager: FamousHoldingsManager) -> UIImage? {
        UIImage(named: bundledAssetName(for: manager.key))
    }

    @MainActor
    static func preload(_ managers: [FamousHoldingsManager]) async {
        await withTaskGroup(of: Void.self) { group in
            for manager in managers {
                let portraitURL = url(for: manager)
                let size = targetSize
                group.addTask {
                    _ = await ImageLoader.load(portraitURL, targetSize: size)
                }
            }
        }
    }

    private static var targetSize: CGSize {
        CGSize(width: UIScreen.main.bounds.width, height: 275)
    }

    private static func url(for manager: FamousHoldingsManager) -> URL? {
        let value = manager.portraitUrl.flatMap { $0.isEmpty ? nil : $0 }
            ?? "/img/sec13f/\(manager.key).webp"
        return URL(string: value, relativeTo: ServerConfiguration.currentURL)?.absoluteURL
    }

    static func monogram(for manager: FamousHoldingsManager) -> String {
        let compact = manager.displayName
            .replacingOccurrences(of: "·", with: "")
            .replacingOccurrences(of: " ", with: "")
        return String(compact.prefix(2))
    }

    static func placeholderColor(for manager: FamousHoldingsManager) -> Color {
        let colors: [Color] = [
            HoldingsPalette.purple,
            HoldingsPalette.teal,
            HoldingsPalette.orange,
            HoldingsPalette.pink
        ]
        let value = manager.key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colors[value % colors.count]
    }

    private static func bundledAssetName(for key: String) -> String {
        switch key {
        case "ark": "InvestorPortraitARK"
        case "berkshire": "InvestorPortraitBerkshire"
        case "duanyongping": "InvestorPortraitDuanYongping"
        case "lilu": "InvestorPortraitLiLu"
        case "danbin": "InvestorPortraitDanBin"
        case "bridgewater": "InvestorPortraitBridgewater"
        case "soros": "InvestorPortraitSoros"
        case "sunmasayoshi": "InvestorPortraitMasayoshiSon"
        default: ""
        }
    }
}

struct HoldingsCompanyLogo: View {
    let path: String?
    let symbol: String?
    let color: Color
    var size: CGFloat = 42

    var body: some View {
        Group {
            if let url = logoURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() } else { fallback }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .background(color.opacity(0.16), in: Circle())
        .clipShape(Circle())
    }

    private var fallback: some View {
        Text(String((symbol ?? "—").prefix(2)))
            .font(.system(size: max(7, size * 0.28), weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var logoURL: URL? {
        guard let path, !path.isEmpty else { return nil }
        if let absolute = URL(string: path), absolute.scheme != nil {
            return MediaURL.image(absolute.absoluteString) ?? absolute
        }
        return URL(string: path, relativeTo: ServerConfiguration.currentURL)?.absoluteURL
    }
}

func actionColor(_ action: FamousHoldingAction) -> Color {
    switch action {
    case .new: HoldingsPalette.blue
    case .increased: HoldingsPalette.green
    case .decreased: HoldingsPalette.orange
    case .exited: HoldingsPalette.red
    case .unchanged: .secondary
    }
}

private func managerPriority(_ key: String) -> Int {
    ["ark", "berkshire", "duanyongping", "lilu", "danbin", "bridgewater", "soros", "sunmasayoshi"].firstIndex(of: key) ?? 99
}

func quarterLabel(_ date: String) -> String {
    let parts = date.split(separator: "-").compactMap { Int($0) }
    guard parts.count >= 2 else { return date }
    return "\(parts[0]) Q\((parts[1] - 1) / 3 + 1)"
}

func percent(_ value: Double) -> String { String(format: "%.1f%%", value) }
func signedPercent(_ value: Double) -> String { String(format: "%@%.1f%%", value > 0 ? "+" : value < 0 ? "−" : "", abs(value)) }
func compactUSD(_ value: Double) -> String {
    if value >= 100_000_000 { return String(format: "%.2f亿", value / 100_000_000) }
    if value >= 10_000 { return String(format: "%.0f万", value / 10_000) }
    return String(format: "%.0f", value)
}

private func dollarValue(_ value: Double) -> String {
    if value >= 1_000_000_000 { return String(format: "$%.3fB", value / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "$%.1fM", value / 1_000_000) }
    return String(format: "$%.0f", value)
}
