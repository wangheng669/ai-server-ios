import Charts
import SwiftUI
import UIKit

enum HoldingsPalette {
    static let blue = Color(red: 0.16, green: 0.39, blue: 0.96)
    static let green = Color(red: 0.04, green: 0.68, blue: 0.44)
    static let orange = Color(red: 1.00, green: 0.39, blue: 0.08)
    static let red = Color(red: 0.94, green: 0.12, blue: 0.28)
    static let purple = Color(red: 0.52, green: 0.31, blue: 0.94)
    static let teal = Color(red: 0.08, green: 0.65, blue: 0.66)
    static let divider = Color(uiColor: .separator).opacity(0.55)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let canvas = Color(uiColor: .systemGroupedBackground)
}

private struct HoldingSector: Identifiable {
    let name: String
    let value: Double
    let color: Color
    var id: String { name }
}

struct FamousHoldingsView: View {
    let store: FamousHoldingsStore
    @Binding var showsDetail: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIndex = 0
    @State private var path: [String] = []

    private var managers: [FamousHoldingsManager] {
        (store.holdings?.managers ?? []).sorted { managerPriority($0.key) < managerPriority($1.key) }
    }

    var body: some View {
        NavigationStack(path: $path) {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HoldingsPalette.canvas.ignoresSafeArea())
            .task {
                await store.load()
                #if DEBUG
                if path.isEmpty,
                   let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--holdings-detail-preview=") }) {
                    path.append(String(argument.dropFirst("--holdings-detail-preview=".count)))
                }
                #endif
            }
            .navigationDestination(for: String.self) { key in
                if let manager = managers.first(where: { $0.key == key }) {
                    FamousHoldingDetailView(manager: manager, store: store)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: path) { _, value in showsDetail = !value.isEmpty }
        .onAppear { showsDetail = !path.isEmpty }
        .onDisappear { showsDetail = false }
    }

    private func overview(_ manager: FamousHoldingsManager) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                hero(manager)
                filingSummary(manager)
                filingInsights(manager)
                footer(manager)
            }
            .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.load(force: true) }
        .simultaneousGesture(managerSwipeGesture)
        .task(id: manager.key) { await store.loadDetail(managerKey: manager.key) }
    }

    private func hero(_ manager: FamousHoldingsManager) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.05, green: 0.06, blue: 0.10), Color(red: 0.13, green: 0.11, blue: 0.25)]
                    : [Color(uiColor: .systemBackground), Color(red: 0.70, green: 0.69, blue: 0.94)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [HoldingsPalette.purple.opacity(colorScheme == .dark ? 0.38 : 0.30), .clear],
                center: UnitPoint(x: 0.70, y: 0.42),
                startRadius: 8,
                endRadius: 190
            )

            investorImage(manager)
                .frame(width: 286, height: 264)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: 48, y: 5)

            if managers.indices.contains(selectedIndex + 1) {
                investorImage(managers[selectedIndex + 1])
                    .frame(width: 108, height: 230)
                    .offset(x: 45, y: 8)
                    .opacity(colorScheme == .dark ? 0.28 : 0.22)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .mask(
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    )
            }

            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.18, green: 0.16, blue: 0.42).opacity(colorScheme == .dark ? 0.96 : 0.88), location: 0),
                    .init(color: Color(red: 0.25, green: 0.24, blue: 0.58).opacity(colorScheme == .dark ? 0.52 : 0.42), location: 0.36),
                    .init(color: .clear, location: 0.64)
                ]),
                startPoint: colorScheme == .dark ? .leading : .bottomLeading,
                endPoint: colorScheme == .dark ? .trailing : .topTrailing
            )

            LinearGradient(
                colors: [.clear, HoldingsPalette.canvas.opacity(0.20)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 7) {
                Text("当前")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(HoldingsPalette.purple.opacity(0.90), in: RoundedRectangle(cornerRadius: 4))
                Text(manager.displayName).font(.system(size: 29, weight: .bold))
                Text(englishName(manager.key)).font(.system(size: 16, weight: .medium))
                Text(manager.institutionName)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                Text("公开披露 · 非实时")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .foregroundStyle(.white)
            .padding(.leading, 20)
            .padding(.bottom, 34)
            .frame(maxWidth: 245, alignment: .leading)

            if managers.indices.contains(selectedIndex + 1) {
                let next = managers[selectedIndex + 1]
                VStack(alignment: .trailing, spacing: 2) {
                    Text("下一位")
                    Text(next.displayName).fontWeight(.semibold)
                }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 14)
                .padding(.bottom, 58)
            }

            pageProgress
                .frame(maxWidth: .infinity, alignment: .bottom)
                .padding(.bottom, 12)

            ShareLink(item: "\(manager.displayName) · \(quarterLabel(manager.reportDate)) 公开持仓") {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.90))
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.14), in: Circle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 62)
            .padding(.trailing, 12)
        }
        .frame(height: 260)
        .clipped()
        .accessibilityAction(named: "下一个人物") { moveManager(by: 1) }
        .accessibilityAction(named: "上一个人物") { moveManager(by: -1) }
    }

    private func filingSummary(_ manager: FamousHoldingsManager) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text("持仓概览")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button { path.append(manager.key) } label: {
                    HStack(spacing: 4) {
                        Text("查看完整持仓")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)

            Divider().overlay(HoldingsPalette.divider)

            HStack(spacing: 0) {
                summaryItem("报告期", quarterLabel(manager.reportDate))
                summaryDivider
                summaryItem("披露日期", manager.filingDate)
                summaryDivider
                summaryItem("持仓数量", "\(manager.positionsCount) 只")
                summaryDivider
                summaryItem("持仓总市值", dollarValue(manager.totalValueUsd))
            }
        }
        .padding(.vertical, 14)
        .background(HoldingsPalette.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(HoldingsPalette.divider))
        .padding(.horizontal, 14)
    }

    private func summaryItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryDivider: some View {
        Rectangle().fill(HoldingsPalette.divider).frame(width: 1, height: 34)
    }

    private func filingInsights(_ manager: FamousHoldingsManager) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("本季度动作").font(.system(size: 17, weight: .bold))
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Spacer()
                Text("占比").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            filingActionRow("新建仓", manager.summary.new, HoldingsPalette.blue, manager.summary)
            filingActionRow("增持", manager.summary.increased, HoldingsPalette.green, manager.summary)
            filingActionRow("减持", manager.summary.decreased, HoldingsPalette.orange, manager.summary)
            filingActionRow("清仓", manager.summary.exited, HoldingsPalette.red, manager.summary)
            Text("基于持仓变动数量，占比合计 100%")
                .font(.system(size: 9)).foregroundStyle(.secondary)

            Divider().overlay(HoldingsPalette.divider)
            HStack {
                Text("变化最大").font(.system(size: 17, weight: .bold))
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Spacer()
                Text("按持仓权重变化").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ForEach(Array(manager.changes.sorted { abs($0.weightChangePct) > abs($1.weightChangePct) }.prefix(3))) { change in
                biggestChangeRow(change)
            }
            Text("仅显示本季度权重变化绝对值最大的 3 只持仓")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(HoldingsPalette.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(HoldingsPalette.divider))
        .padding(.horizontal, 14)
    }

    private func filingActionRow(_ title: String, _ value: Int, _ color: Color, _ summary: FamousHoldingsSummary) -> some View {
        let total = max(1, summary.new + summary.increased + summary.decreased + summary.exited)
        let share = Double(value) / Double(total)
        return HStack(spacing: 10) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.system(size: 12)).frame(width: 50, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.14))
                    Capsule().fill(color).frame(width: proxy.size.width * share)
                }
            }
            .frame(height: 10)
            Text("\(value) 只").font(.system(size: 13, weight: .medium)).monospacedDigit().frame(width: 44, alignment: .trailing)
            Text(percent(share * 100)).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit().frame(width: 38, alignment: .trailing)
        }
    }

    private func biggestChangeRow(_ change: FamousHoldingChange) -> some View {
        HStack(spacing: 10) {
            HoldingsCompanyLogo(path: change.companyLogo, symbol: displaySymbol(change), color: actionColor(change.action), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(displaySymbol(change)).font(.system(size: 14, weight: .semibold))
                    Text(chineseCompanyName(change)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(change.name).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(change.action.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(actionColor(change.action))
                .padding(.horizontal, 7).frame(height: 22)
                .background(actionColor(change.action).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .trailing, spacing: 2) {
                Text(signedPercent(change.weightChangePct))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(actionColor(change.action))
                Text("权重变化").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }

    private var pageProgress: some View {
        HStack(spacing: 5) {
            ForEach(managers.indices, id: \.self) { index in
                Capsule()
                    .fill(index == selectedIndex ? HoldingsPalette.purple : Color.white.opacity(0.18))
                    .frame(width: index == selectedIndex ? 22 : 14, height: 2)
            }
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
            Button { path.append(manager.key) } label: {
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

    private var managerSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20).onEnded { value in
            let translation = value.predictedEndTranslation
            guard abs(translation.width) > abs(translation.height), abs(translation.width) > 48 else { return }
            moveManager(by: translation.width < 0 ? 1 : -1)
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
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Text(String(manager.displayName.prefix(1)))
                    .font(.system(size: 90, weight: .bold))
                    .foregroundStyle(.white.opacity(0.2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(avatarTint(manager.key))
            }
        }
        .task(id: manager.key) {
            image = nil
            image = await ImageLoader.load(
                resolvedPortraitURL,
                targetSize: CGSize(width: UIScreen.main.bounds.width, height: 275)
            )
        }
    }

    private var resolvedPortraitURL: URL? {
        let value = manager.portraitUrl.flatMap { $0.isEmpty ? nil : $0 }
            ?? "/img/sec13f/\(manager.key).webp"
        return URL(string: value, relativeTo: ServerConfiguration.currentURL)?.absoluteURL
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
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
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

private func avatarTint(_ key: String) -> Color {
    switch key {
    case "ark": .purple
    case "berkshire": .blue
    case "duanyongping": .teal
    case "lilu": .indigo
    case "danbin": .orange
    case "bridgewater": .cyan
    case "soros": .red
    default: .gray
    }
}

private func englishName(_ key: String) -> String {
    switch key {
    case "ark": "Cathie Wood"
    case "berkshire": "Warren Buffett"
    case "duanyongping": "Duan Yongping"
    case "lilu": "Li Lu"
    case "danbin": "Dan Bin"
    case "bridgewater": "Ray Dalio"
    case "soros": "George Soros"
    case "sunmasayoshi": "Masayoshi Son"
    default: ""
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
