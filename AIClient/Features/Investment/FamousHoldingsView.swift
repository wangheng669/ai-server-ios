import SwiftUI

enum HoldingsPalette {
    static let blue = Color(red: 0.07, green: 0.49, blue: 0.98)
    static let green = Color(red: 0.06, green: 0.65, blue: 0.32)
    static let orange = Color.orange
    static let red = Color(red: 0.96, green: 0.18, blue: 0.22)
    static let divider = Color(uiColor: .separator).opacity(0.55)
}

struct FamousHoldingsView: View {
    let store: FamousHoldingsStore
    @Binding var showsDetail: Bool
    @State private var selectedManagerKey: String?
    @State private var path: [String] = []

    private var managers: [FamousHoldingsManager] {
        let filtered = selectedManagerKey.map { key in store.holdings?.managers.filter { $0.key == key } } ?? store.holdings?.managers
        return (filtered ?? []).sorted { managerPriority($0.key) < managerPriority($1.key) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let holdings = store.holdings {
                    filters(holdings)
                    summary(holdings.summary)
                    Divider().padding(.horizontal, 18).padding(.top, 14)
                    ForEach(managers) { manager in
                        managerSection(manager)
                    }
                    Text(holdings.disclaimer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                } else if store.isLoading {
                    ProgressView("正在读取公开持仓披露")
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if let error = store.errorMessage {
                    ContentUnavailableView {
                        Label("持仓数据暂不可用", systemImage: "chart.pie")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重新加载") { Task { await store.load(force: true) } }
                    }
                    .frame(minHeight: 320)
                }
            }
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.load(force: true) }
            .task {
                await store.load()
                #if DEBUG
                if path.isEmpty,
                   let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--holdings-detail-preview=") }) {
                    path.append(String(argument.dropFirst("--holdings-detail-preview=".count)))
                }
                #endif
            }
            .background(Color(uiColor: .systemBackground))
            .navigationDestination(for: String.self) { key in
                if let manager = store.holdings?.managers.first(where: { $0.key == key }) {
                    FamousHoldingDetailView(manager: manager, store: store)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: path) { _, value in showsDetail = !value.isEmpty }
        .onAppear { showsDetail = !path.isEmpty }
        .onDisappear { showsDetail = false }
    }

    private func filters(_ holdings: FamousHoldings) -> some View {
        HStack(spacing: 10) {
            Text(holdings.periodLabel)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12).frame(height: 38)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            Menu {
                Button("全部人物") { selectedManagerKey = nil }
                ForEach(holdings.managers) { manager in
                    Button(manager.displayName) { selectedManagerKey = manager.key }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedManagerName(in: holdings))
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12).frame(height: 38)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
            Spacer()
            Text("披露期 \(holdings.reportDate)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private func summary(_ value: FamousHoldingsSummary) -> some View {
        HStack(spacing: 0) {
            summaryMetric("新建仓", value.new, HoldingsPalette.blue)
            summaryMetric("增持", value.increased, HoldingsPalette.green)
            summaryMetric("减持", value.decreased, HoldingsPalette.orange)
            summaryMetric("清仓", value.exited, HoldingsPalette.red)
        }
        .padding(.top, 22)
        .padding(.horizontal, 8)
    }

    private func summaryMetric(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(String(value)).font(.system(size: 27, weight: .medium)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func managerSection(_ manager: FamousHoldingsManager) -> some View {
        return VStack(spacing: 0) {
            managerHeader(manager)
            HStack {
                Text("代码 / 公司")
                Spacer()
                Text("持仓权重变化")
                Spacer()
                Text("变化幅度")
            }
            .font(.caption2).foregroundStyle(.secondary)
            .padding(.horizontal, 18).padding(.vertical, 10)

            ForEach(manager.changes.prefix(3)) { change in
                HoldingChangeRow(change: change)
                Divider().padding(.leading, 64)
            }

            Button { path.append(manager.key) } label: {
                HStack(spacing: 6) {
                    Text("查看详细持仓")
                    Text("共 \(manager.changesCount) 只")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.blue)
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
        }
    }

    private func managerHeader(_ manager: FamousHoldingsManager) -> some View {
        HStack(spacing: 12) {
            FamousInvestorAvatar(name: manager.displayName, key: manager.key)
            VStack(alignment: .leading, spacing: 3) {
                Text(manager.displayName).font(.system(size: 17, weight: .semibold))
                Text(manager.institutionName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("\(quarterLabel(manager.reportDate)) 披露 · 申报 \(manager.filingDate)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            ManagerActionSummary(summary: manager.summary)
        }
        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 8)
        .overlay(alignment: .top) { Divider() }
    }

    private func selectedManagerName(in holdings: FamousHoldings) -> String {
        guard let selectedManagerKey,
              let manager = holdings.managers.first(where: { $0.key == selectedManagerKey }) else { return "全部人物" }
        return manager.displayName
    }

}

private struct ManagerActionSummary: View {
    let summary: FamousHoldingsSummary

    var body: some View {
        HStack(spacing: 8) {
            if summary.increased > 0 { badge("增持 \(summary.increased)", HoldingsPalette.green) }
            if summary.decreased > 0 { badge("减持 \(summary.decreased)", HoldingsPalette.orange) }
            if summary.exited > 0 { badge("清仓 \(summary.exited)", HoldingsPalette.red) }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.8), lineWidth: 0.8) }
    }
}

private struct HoldingChangeRow: View {
    let change: FamousHoldingChange
    private var color: Color {
        switch change.action {
        case .new: HoldingsPalette.blue
        case .increased: HoldingsPalette.green
        case .decreased: HoldingsPalette.orange
        case .exited: HoldingsPalette.red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            HoldingsCompanyLogo(path: change.companyLogo, symbol: change.symbol, color: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(change.symbol ?? "—").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(change.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 92, alignment: .leading)

            WeightChangeBar(previous: change.previousWeightPct, current: change.weightPct, color: color)
                .frame(maxWidth: .infinity)

            VStack(alignment: .trailing, spacing: 3) {
                Text(change.action.title).font(.caption2.weight(.semibold)).foregroundStyle(color)
                Text(signedPercent(change.weightChangePct)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(color)
            }
            .frame(width: 58, alignment: .trailing)
        }
        .padding(.horizontal, 18).frame(minHeight: 68)
        .accessibilityElement(children: .combine)
    }
}

private struct WeightChangeBar: View {
    let previous: Double
    let current: Double
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(percent(previous))
                Spacer()
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(color)
                Spacer()
                Text(percent(current))
            }
            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            GeometryReader { proxy in
                let maximum = max(previous, current, 0.01)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18)).frame(height: 3)
                    Capsule().fill(color).frame(width: proxy.size.width * current / maximum, height: 3)
                }
            }
            .frame(height: 3)
        }
    }
}

struct FamousInvestorAvatar: View {
    let name: String
    let key: String

    var body: some View {
        Group {
            if let assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(String(name.prefix(1)))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(avatarColor)
            }
        }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }

    private var assetName: String? {
        switch key {
        case "ark": "InvestorARK"
        case "berkshire": "InvestorBerkshire"
        case "duanyongping": "InvestorDuanYongping"
        case "lilu": "InvestorLiLu"
        case "danbin": "InvestorDanBin"
        case "bridgewater": "InvestorBridgewater"
        case "soros": "InvestorSoros"
        case "sunmasayoshi": "InvestorMasayoshiSon"
        default: nil
        }
    }

    private var avatarColor: Color {
        switch key {
        case "ark": .purple
        case "berkshire": .blue
        case "duanyongping": .teal
        case "lilu": .indigo
        case "danbin": .orange
        case "bridgewater": .cyan
        case "soros": .red
        case "sunmasayoshi": .mint
        default: .gray
        }
    }
}

struct HoldingsCompanyLogo: View {
    let path: String?
    let symbol: String?
    let color: Color

    var body: some View {
        Group {
            if let url = logoURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    private var fallback: some View {
        Image("CompanyFallback")
            .resizable()
            .scaledToFill()
            .overlay(alignment: .bottomTrailing) {
                if let symbol, !symbol.isEmpty {
                    Text(String(symbol.prefix(2)))
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 3))
                }
            }
    }

    private var logoURL: URL? {
        guard let path, !path.isEmpty else { return nil }
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
        return URL(string: path, relativeTo: ServerConfiguration.currentURL)?.absoluteURL
    }
}

private func managerPriority(_ key: String) -> Int {
    switch key {
    case "ark": 0
    case "berkshire": 1
    case "duanyongping": 2
    case "lilu": 3
    case "danbin": 4
    case "bridgewater": 5
    case "soros": 6
    case "sunmasayoshi": 7
    default: 99
    }
}

func quarterLabel(_ date: String) -> String {
    let parts = date.split(separator: "-").compactMap { Int($0) }
    guard parts.count >= 2 else { return date }
    return "\(parts[0]) Q\((parts[1] - 1) / 3 + 1)"
}

func percent(_ value: Double) -> String { String(format: "%.1f%%", value) }
func signedPercent(_ value: Double) -> String { String(format: "%@%.1f%%", value > 0 ? "+" : value < 0 ? "−" : "", abs(value)) }
