import Charts
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
                    managerMenu
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
        .sheet(item: $selectedDetail) { route in
            NavigationStack {
                if let manager = managers.first(where: { $0.key == route.managerKey }) {
                    FamousHoldingDetailView(manager: manager, store: store)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationContentInteraction(.scrolls)
        }
        .onChange(of: selectedDetail) { _, value in showsDetail = value != nil }
        .onAppear { showsDetail = selectedDetail != nil }
        .onDisappear { showsDetail = false }
    }

    private func overview(_ manager: FamousHoldingsManager) -> some View {
        ScrollView {
            VStack(spacing: InvestmentDesign.sectionSpacing) {
                hero(manager)
                filingSummary(manager)
                filingInsights(manager)
                footer(manager)
            }
            .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.load(force: true) }
        .task(id: manager.key) { await store.loadDetail(managerKey: manager.key) }
    }

    private var managerMenu: some View {
        Menu {
            ForEach(Array(managers.enumerated()), id: \.element.key) { index, manager in
                Button {
                    selectManager(at: index)
                } label: {
                    Label(
                        manager.displayName,
                        systemImage: index == selectedIndex ? "checkmark.circle.fill" : "person.crop.circle"
                    )
                }
            }
        } label: {
            HStack(spacing: 8) {
                if managers.indices.contains(selectedIndex) {
                    InvestorPortraitImage(manager: managers[selectedIndex], contentMode: .fill)
                        .frame(width: 34, height: 34)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.34), lineWidth: 1))
                } else {
                    Image(systemName: "person.2.fill")
                        .frame(width: 34, height: 34)
                }

                Text("选择")
                    .font(.system(size: 13, weight: .bold))

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.leading, 6)
            .padding(.trailing, 13)
            .frame(height: 46)
            .background(HoldingsPalette.purple, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: HoldingsPalette.purple.opacity(0.28), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择投资人")
    }

    private func hero(_ manager: FamousHoldingsManager) -> some View {
        VStack(spacing: 15) {
            HStack(alignment: .center, spacing: 15) {
                InvestorPortraitImage(manager: manager, contentMode: .fill)
                    .frame(width: 76, height: 76)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(HoldingsPalette.purple.opacity(0.30), lineWidth: 1))

                VStack(alignment: .leading, spacing: 6) {
                    Text("公开持仓追踪")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(HoldingsPalette.purple)
                        .padding(.horizontal, 9)
                        .frame(height: 19)
                        .background(HoldingsPalette.purple.opacity(0.10), in: Capsule())
                    HStack(spacing: 6) {
                        Text(manager.displayName).font(.system(size: 21, weight: .semibold))
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(HoldingsPalette.indigo)
                    }
                    Text(englishName(manager))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        Text(manager.institutionName).lineLimit(1)
                        Text("·")
                        Text("SEC 13F")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }

            Button { selectedDetail = HoldingDetailRoute(managerKey: manager.key) } label: {
                HStack(spacing: 6) {
                    Text("查看完整持仓与变动")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HoldingsPalette.purple)
                .padding(.horizontal, 13)
                .frame(height: 38)
                .background(HoldingsPalette.purple.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(HoldingsPalette.card, in: RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius)
                .stroke(HoldingsPalette.divider)
        }
        .padding(.horizontal, 16)
        .accessibilityAction(named: "下一个人物") { moveManager(by: 1) }
        .accessibilityAction(named: "上一个人物") { moveManager(by: -1) }
    }

    private func filingSummary(_ manager: FamousHoldingsManager) -> some View {
        HStack(spacing: 0) {
            summaryItem("报告期", quarterLabel(manager.reportDate), "calendar")
            summaryDivider
            summaryItem("披露日期", manager.filingDate, "calendar.badge.clock")
            summaryDivider
            summaryItem("持仓数量", "\(manager.positionsCount) 只", "chart.pie.fill")
            summaryDivider
            summaryItem("持仓总市值", dollarValue(manager.totalValueUsd), "dollarsign.circle.fill")
        }
        .padding(.vertical, 15)
        .background(HoldingsPalette.card, in: RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius)
                .stroke(HoldingsPalette.divider)
        }
        .padding(.horizontal, 16)
    }

    private func summaryItem(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HoldingsPalette.purple)
                .frame(width: 30, height: 30)
                .background(HoldingsPalette.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryDivider: some View {
        Rectangle().fill(HoldingsPalette.divider).frame(width: 1, height: 34)
    }

    private func filingInsights(_ manager: FamousHoldingsManager) -> some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("本季度动作分布").font(.system(size: 16, weight: .bold))
                    Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(spacing: 18) {
                    actionDonut(manager.summary).frame(width: 138, height: 138)
                    VStack(spacing: 11) {
                        filingActionRow("新建仓", manager.summary.new, HoldingsPalette.blue, manager.summary)
                        filingActionRow("增持", manager.summary.increased, HoldingsPalette.green, manager.summary)
                        filingActionRow("减持", manager.summary.decreased, HoldingsPalette.orange, manager.summary)
                        filingActionRow("清仓", manager.summary.exited, HoldingsPalette.pink, manager.summary)
                    }
                    .frame(maxWidth: .infinity)
                }
                Text("基于持仓变动数量，占比合计 100%")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .padding(18)
            .background(HoldingsPalette.card, in: RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius)
                    .stroke(HoldingsPalette.divider)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("变化最大").font(.system(size: 16, weight: .bold))
                    Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Text("权重变化")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                let topChanges = Array(manager.changes.sorted { abs($0.weightChangePct) > abs($1.weightChangePct) }.prefix(3))
                ForEach(Array(topChanges.enumerated()), id: \.element.id) { index, change in
                    biggestChangeRow(change)
                    if index < topChanges.count - 1 {
                        Divider().overlay(HoldingsPalette.divider).padding(.leading, 52)
                    }
                }
                Text("仅显示本季度权重变化绝对值最大的 3 只持仓")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .padding(18)
            .background(HoldingsPalette.card, in: RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius)
                    .stroke(HoldingsPalette.divider)
            }
        }
        .padding(.horizontal, 16)
    }

    private func actionDonut(_ summary: FamousHoldingsSummary) -> some View {
        let values = [
            ("新建仓", summary.new, HoldingsPalette.blue),
            ("增持", summary.increased, HoldingsPalette.green),
            ("减持", summary.decreased, HoldingsPalette.orange),
            ("清仓", summary.exited, HoldingsPalette.pink)
        ]
        let total = summary.new + summary.increased + summary.decreased + summary.exited
        return ZStack {
            Chart(Array(values.enumerated()), id: \.offset) { _, item in
                SectorMark(angle: .value("数量", item.1), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .foregroundStyle(item.2)
                    .cornerRadius(2)
            }
            .chartLegend(.hidden)
            VStack(spacing: 1) {
                Text("\(total)")
                    .font(.system(size: 21, weight: .bold))
                    .monospacedDigit()
                Text("总变动")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func filingActionRow(_ title: String, _ value: Int, _ color: Color, _ summary: FamousHoldingsSummary) -> some View {
        let total = max(1, summary.new + summary.increased + summary.decreased + summary.exited)
        let share = Double(value) / Double(total)
        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 12))
            Spacer(minLength: 4)
            Text("\(value) 只")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
            Text(percent(share * 100))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
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

    private func actionBand(_ summary: FamousHoldingsSummary) -> some View {
        HStack(spacing: 0) {
            actionMetric("新建仓", summary.new, HoldingsPalette.blue)
            bandDivider
            actionMetric("增持", summary.increased, HoldingsPalette.green)
            bandDivider
            actionMetric("减持", summary.decreased, HoldingsPalette.orange)
            bandDivider
            actionMetric("清仓", summary.exited, HoldingsPalette.red)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider().overlay(HoldingsPalette.divider) }
        .overlay(alignment: .bottom) { Divider().overlay(HoldingsPalette.divider) }
        .padding(.horizontal, 14)
    }

    private var bandDivider: some View {
        Rectangle().fill(HoldingsPalette.divider).frame(width: 1, height: 50)
    }

    private func actionMetric(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(String(value))
                .font(.system(size: 22, weight: .medium, design: .serif))
                .monospacedDigit()
            Text("占比 \(percent(actionShare(value)))")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func valueBand(_ manager: FamousHoldingsManager) -> some View {
        HStack(spacing: 12) {
            Text("总持仓市值（USD）")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(dollarValue(manager.totalValueUsd))
                .font(.system(size: 20, weight: .medium, design: .serif))
                .monospacedDigit()
            Rectangle().fill(HoldingsPalette.divider).frame(width: 1, height: 24)
            Text("较上期变化")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(signedPercent(totalChange(manager)))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(HoldingsPalette.purple)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Divider().overlay(HoldingsPalette.divider) }
    }

    private func analysis(_ manager: FamousHoldingsManager) -> some View {
        HStack(alignment: .top, spacing: 0) {
            distribution(manager)
                .frame(width: 154)
            Rectangle().fill(HoldingsPalette.divider).frame(width: 1, height: 235)
            topHoldings(manager)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func distribution(_ manager: FamousHoldingsManager) -> some View {
        let sectors = sectorData(manager)
        return VStack(alignment: .leading, spacing: 7) {
            Text("持仓分布").font(.system(size: 14, weight: .semibold))
            ZStack {
                Chart(sectors) { sector in
                    SectorMark(
                        angle: .value("占比", sector.value),
                        innerRadius: .ratio(0.66),
                        angularInset: 1.2
                    )
                    .foregroundStyle(sector.color)
                }
                .chartLegend(.hidden)
                VStack(spacing: 2) {
                    Text("共 \(manager.positionsCount) 只")
                        .font(.system(size: 13, weight: .medium))
                    Text(dollarValue(manager.totalValueUsd))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, height: 112)
            ForEach(sectors.prefix(5)) { sector in
                HStack(spacing: 5) {
                    Circle().fill(sector.color).frame(width: 6, height: 6)
                    Text(sector.name).lineLimit(1)
                    Spacer()
                    Text(percent(sector.value)).monospacedDigit()
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 128)
            }
            Divider().overlay(HoldingsPalette.divider).frame(width: 128)
            HStack {
                Text("本期变动")
                Spacer()
                Text("\(manager.changesCount) 只").foregroundStyle(HoldingsPalette.purple)
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .frame(width: 128)
        }
    }

    private func topHoldings(_ manager: FamousHoldingsManager) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("前十大持仓").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("持仓占比").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .padding(.leading, 12)
            .padding(.bottom, 5)
            ForEach(Array(manager.changes.sorted { $0.weightPct > $1.weightPct }.prefix(10))) { change in
                HStack(spacing: 6) {
                    HoldingsCompanyLogo(path: change.companyLogo, symbol: displaySymbol(change), color: actionColor(change.action), size: 20)
                    Text(displaySymbol(change))
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 35, alignment: .leading)
                    Text(chineseCompanyName(change))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(percent(change.weightPct))
                        .font(.system(size: 9, weight: .medium))
                        .monospacedDigit()
                }
                .frame(height: 19)
                .padding(.leading, 12)
                .overlay(alignment: .bottom) { Divider().overlay(HoldingsPalette.divider).padding(.leading, 12) }
            }
            Button { selectedDetail = HoldingDetailRoute(managerKey: manager.key) } label: {
                HStack {
                    Text("查看全部持仓")
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 8))
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HoldingsPalette.purple)
                .padding(.leading, 12)
                .frame(height: 23)
            }
            .buttonStyle(.plain)
        }
    }

    private func sectorBar(_ manager: FamousHoldingsManager) -> some View {
        let sectors = sectorData(manager)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("行业配置").font(.system(size: 13, weight: .semibold))
                Text("（按市值占比）").font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Text("前五行业").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(sectors) { sector in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sector.name).lineLimit(1)
                            Text(percent(sector.value))
                        }
                        .font(.system(size: 8, weight: .medium))
                        .padding(.horizontal, 5)
                        .frame(width: proxy.size.width * sector.value / 100, height: 39, alignment: .leading)
                        .background(sector.color.opacity(0.76))
                        .clipped()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 39)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private func footer(_ manager: FamousHoldingsManager) -> some View {
        HStack {
            Text("数据来源：13F 申报文件")
            Spacer()
            Text("货币：USD")
        }
        .font(.system(size: 8))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.top, 9)
    }

    private func selectManager(at index: Int) {
        guard managers.indices.contains(index) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedIndex = index
        }
    }

    private func moveManager(by offset: Int) {
        let next = selectedIndex + offset
        guard managers.indices.contains(next) else { return }
        withAnimation(.easeInOut(duration: 0.22)) { selectedIndex = next }
    }

    private func actionShare(_ value: Int) -> Double {
        guard managers.indices.contains(selectedIndex) else { return 0 }
        let summary = managers[selectedIndex].summary
        let total = summary.new + summary.increased + summary.decreased + summary.exited
        return total == 0 ? 0 : Double(value) / Double(total) * 100
    }

    private func totalChange(_ manager: FamousHoldingsManager) -> Double {
        manager.changes.reduce(0) { $0 + $1.weightChangePct }
    }

    private func sectorData(_ manager: FamousHoldingsManager) -> [HoldingSector] {
        var totals: [String: Double] = [:]
        for change in manager.changes {
            totals[sectorName(displaySymbol(change)), default: 0] += max(0, change.weightPct)
        }
        let known = min(totals.values.reduce(0, +), 100)
        totals["其他", default: 0] += max(0, 100 - known)
        let colors: [String: Color] = [
            "信息技术": HoldingsPalette.purple,
            "非必需消费": HoldingsPalette.blue,
            "医疗保健": HoldingsPalette.teal,
            "金融": HoldingsPalette.orange,
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
