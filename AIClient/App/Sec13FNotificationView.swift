import SwiftUI

/// A filing snapshot captured when this notification was sent, never the latest live portfolio.
struct Sec13FNotificationSnapshot: Decodable {
    let checkedAt: String
    let windowText: String
    let checked: Int
    let failed: Int
    let items: [Manager]
    let errors: [CheckError]

    struct CheckError: Decodable {
        let key: String
        let institutionName: String
        let error: String
    }

    struct Manager: Decodable {
        let key: String
        let cik: String?
        let institutionName: String
        let displayName: String?
        let accession: String?
        let previousAccession: String?
        let reportDate: String?
        let filingDate: String?
        let positionsCount: Int?
        let totalValueUsd: Double?
        let positions: [Position]?
        let exitedPositions: [Position]?

        var hasComparison: Bool { !(previousAccession ?? "").isEmpty }
        var allPositions: [Position] { (positions ?? []) + (exitedPositions ?? []) }
        func positions(matching filter: Sec13FFilter, query: String) -> [Position] {
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return allPositions.filter {
                (filter == .all || (filter == .changed && [.new, .increased, .decreased, .exited].contains($0.action(hasComparison: hasComparison))) || $0.action(hasComparison: hasComparison) == filter) &&
                (query.isEmpty || $0.nameOfIssuer.localizedCaseInsensitiveContains(query) ||
                 ($0.cusip ?? "").localizedCaseInsensitiveContains(query))
            }.sorted { ($0.valueUsd ?? $0.previousValueUsd ?? 0) > ($1.valueUsd ?? $1.previousValueUsd ?? 0) }
        }
    }

    struct Position: Decodable {
        let nameOfIssuer: String
        let titleOfClass: String?
        let cusip: String?
        let putCall: String?
        let sharesType: String?
        let shares: Double?
        let valueUsd: Double?
        let weightPct: Double?
        let previousShares: Double?
        let previousValueUsd: Double?
        let sharesChange: Double?
        let previousWeightPct: Double?
        let isNew: Bool?
        let isSoldOut: Bool?

        func action(hasComparison: Bool) -> Sec13FFilter {
            guard hasComparison else { return .uncompared }
            if isSoldOut == true { return .exited }
            if isNew == true { return .new }
            if (sharesChange ?? 0) > 0 { return .increased }
            if (sharesChange ?? 0) < 0 { return .decreased }
            return .unchanged
        }
    }
}

enum Sec13FFilter: String, CaseIterable, Identifiable {
    case changed = "全部变化"
    case all = "全部", new = "新建仓", increased = "增持", decreased = "减持", exited = "清仓"
    case unchanged = "未变动", uncompared = "未比较"
    var id: Self { self }
    var color: Color {
        switch self {
        case .increased: HoldingsPalette.red
        case .decreased: HoldingsPalette.green
        case .exited: Color.secondary
        default: HoldingsPalette.blue
        }
    }
}

struct Sec13FNotificationView: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: Sec13FNotificationSnapshot
    @State private var selectedIndex = 0
    @State private var detail: Sec13FDetailRoute?
    @State private var browser: InAppBrowserDestination?
    private var manager: Sec13FNotificationSnapshot.Manager? {
        snapshot.items.indices.contains(selectedIndex) ? snapshot.items[selectedIndex] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("13F 披露").font(.headline)
                Spacer()
                if snapshot.items.count > 1 {
                    Menu {
                        ForEach(Array(snapshot.items.enumerated()), id: \.offset) { index, item in
                            Button(item.displayName ?? item.institutionName) { selectedIndex = index }
                        }
                    } label: { Label("\(selectedIndex + 1)/\(snapshot.items.count)", systemImage: "chevron.down").font(.caption) }
                    .accessibilityLabel("选择披露机构")
                }
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "xmark").font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary).frame(width: 30, height: 30)
                        .background(Color.secondary.opacity(0.09), in: Circle())
                }.accessibilityLabel("关闭持仓更新")
            }.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let manager { brief(manager) }
                    else { ContentUnavailableView("本次没有持仓更新", systemImage: "doc.text.magnifyingglass") }
                    if !snapshot.errors.isEmpty {
                        Text("\(snapshot.failed) 家机构未完成检查").font(.footnote).foregroundStyle(HoldingsPalette.orange).padding(.top, 20)
                        ForEach(Array(snapshot.errors.enumerated()), id: \.offset) { _, error in
                            Text("\(error.institutionName)：\(error.error)").font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                        }
                    }
                }.padding(.horizontal, 22).padding(.bottom, 28)
            }.scrollIndicators(.hidden)
        }
        .background(HoldingsPalette.card.ignoresSafeArea())
        .accessibilityIdentifier("sec13f-notification-detail")
        .sheet(item: $detail) { route in
            Sec13FHoldingsListView(manager: route.manager, initialFilter: route.filter)
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .inAppBrowserCover(item: $browser)
    }

    @ViewBuilder private func brief(_ manager: Sec13FNotificationSnapshot.Manager) -> some View {
        HStack(spacing: 6) {
            Text(sec13FQuarter(manager.reportDate)).foregroundStyle(HoldingsPalette.blue)
            Text("·").foregroundStyle(.tertiary)
            Text("\(manager.filingDate ?? "日期未提供") 披露").foregroundStyle(.secondary)
        }.font(.caption)
        Text(manager.institutionName).font(.title2.weight(.semibold)).padding(.top, 9).accessibilityAddTraits(.isHeader)
        if let name = manager.displayName, !name.isEmpty {
            Text("\(name) · 季度持仓变化").font(.subheadline).foregroundStyle(.secondary).padding(.top, 7)
        }
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) { portfolioMetric(manager); Spacer(minLength: 16); countMetric(manager) }
            VStack(alignment: .leading, spacing: 15) { portfolioMetric(manager); countMetric(manager) }
        }.padding(.top, 25)
        if manager.hasComparison {
            HStack(spacing: 0) {
                ForEach([Sec13FFilter.new, .increased, .decreased, .exited]) { action in
                    Button { detail = .init(manager: manager, filter: action) } label: {
                        VStack(spacing: 6) {
                            Text("\(manager.allPositions.filter { $0.action(hasComparison: true) == action }.count)")
                                .font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(action.color)
                            Text(action.rawValue).font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).accessibilityIdentifier("sec13f-summary-\(action.rawValue)")
                }
            }.padding(.vertical, 16).background(HoldingsPalette.canvas, in: RoundedRectangle(cornerRadius: 12)).padding(.top, 22)
        } else {
            Text("本次未提供上期比较，以下仅展示已披露持仓。")
                .font(.footnote).foregroundStyle(.secondary).padding(.top, 22)
        }
        let changes = manager.positions(matching: manager.hasComparison ? .changed : .all, query: "")
        HStack {
            Text(manager.hasComparison ? "本季重点变化" : "主要持仓").font(.subheadline.weight(.semibold))
            Spacer()
            Text("按持仓规模").font(.caption2).foregroundStyle(.secondary)
        }.padding(.top, 30).padding(.bottom, 8)
        if manager.positions == nil && manager.exitedPositions == nil {
            Text("本次快照未包含持仓明细").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 20)
        } else if changes.isEmpty {
            Text("本次未发现数量变化").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 20)
        } else {
            ForEach(Array(changes.prefix(3).enumerated()), id: \.offset) { index, position in
                Button { detail = .init(manager: manager, filter: manager.hasComparison ? .changed : .all) } label: {
                    Sec13FCompactPositionRow(position: position, hasComparison: manager.hasComparison)
                }.buttonStyle(.plain)
                if index < min(3, changes.count) - 1 { Divider().padding(.leading, 48) }
            }
            Button { detail = .init(manager: manager, filter: manager.hasComparison ? .changed : .all) } label: {
                HStack {
                    Text(manager.hasComparison ? "查看全部 \(changes.count) 项变化" : "查看全部持仓")
                    Spacer(); Image(systemName: "arrow.right")
                }.font(.subheadline.weight(.medium)).foregroundStyle(HoldingsPalette.blue).padding(.vertical, 16)
            }.accessibilityIdentifier("sec13f-all-changes")
        }
        Divider()
        Button { detail = .init(manager: manager, filter: .all) } label: {
            HStack {
                Label("完整持仓与清仓记录", systemImage: "list.bullet.rectangle")
                Spacer()
                Text(manager.positionsCount.map { "\($0) 项持仓" } ?? "查看").foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }.font(.subheadline).foregroundStyle(.primary).padding(.vertical, 20)
        }.buttonStyle(.plain).accessibilityIdentifier("sec13f-full-holdings")
        if let url = sec13FFilingURL(manager) {
            Button { browser = InAppBrowserDestination(url: url) } label: {
                Label("SEC 原始申报", systemImage: "arrow.up.right").font(.caption)
            }.padding(.top, 6)
        }
        Text("季度末快照，不代表实时交易。增减持按数量变化计算。")
            .font(.caption2).foregroundStyle(.tertiary).padding(.top, 20)
        Text("已检查 \(snapshot.checked) 家 · \(snapshot.windowText)").font(.caption2).foregroundStyle(.tertiary).padding(.top, 6)
    }
    private func portfolioMetric(_ manager: Sec13FNotificationSnapshot.Manager) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(manager.totalValueUsd.map(sec13FMoney) ?? "未提供").font(.largeTitle.weight(.semibold)).monospacedDigit()
            Text("申报市值 · 美元").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func countMetric(_ manager: Sec13FNotificationSnapshot.Manager) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(manager.positionsCount.map(String.init) ?? "—").font(.title2.weight(.medium)).monospacedDigit()
            Text("当前持仓").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct Sec13FDetailRoute: Identifiable {
    let id = UUID()
    let manager: Sec13FNotificationSnapshot.Manager
    let filter: Sec13FFilter
}

private struct Sec13FHoldingsListView: View {
    @Environment(\.dismiss) private var dismiss
    let manager: Sec13FNotificationSnapshot.Manager
    @State private var filter: Sec13FFilter
    @State private var query = ""
    @State private var expanded = Set<Int>()
    @State private var browser: InAppBrowserDestination?
    init(manager: Sec13FNotificationSnapshot.Manager, initialFilter: Sec13FFilter) {
        self.manager = manager; _filter = State(initialValue: initialFilter)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text(manager.institutionName).font(.headline).padding(.vertical, 16)
                    if manager.positions == nil && manager.exitedPositions == nil {
                        ContentUnavailableView("未包含持仓明细", systemImage: "doc.text.magnifyingglass")
                    } else {
                        let positions = manager.positions(matching: filter, query: query)
                        if positions.isEmpty { ContentUnavailableView.search(text: query) }
                        ForEach(Array(positions.enumerated()), id: \.offset) { index, position in
                            Button {
                                if expanded.contains(index) { expanded.remove(index) } else { expanded.insert(index) }
                            } label: { Sec13FCompactPositionRow(position: position, hasComparison: manager.hasComparison) }
                                .buttonStyle(.plain)
                            if expanded.contains(index) {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text("\(position.isSoldOut == true ? "上期数量" : "持有数量")：\(((position.isSoldOut == true ? position.previousShares : position.shares) ?? 0).formatted()) \(position.sharesType ?? "")")
                                    if manager.hasComparison { Text("数量变化：\((position.sharesChange ?? 0).formatted(.number.sign(strategy: .always())))") }
                                    if let cusip = position.cusip { Text("CUSIP：\(cusip)") }
                                    if let title = position.titleOfClass { Text("类别：\(title)") }
                                    if let type = position.putCall { Text("期权：\(type)") }
                                }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(.leading, 48).padding(.bottom, 16)
                            }
                            Divider().padding(.leading, 48)
                        }
                    }
                    if let url = sec13FFilingURL(manager) {
                        Button { browser = InAppBrowserDestination(url: url) } label: { Label("SEC 原始申报", systemImage: "arrow.up.right") }.font(.footnote).padding(.top, 24)
                    }
                    Text("报告期 \(manager.reportDate ?? "未提供") · 披露 \(manager.filingDate ?? "未提供")").font(.caption).foregroundStyle(.secondary).padding(.top, 18)
                    if let accession = manager.accession { Text("申报编号 \(accession)").font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled).padding(.top, 6) }
                }.padding(.horizontal, 22).padding(.bottom, 28)
            }
            .accessibilityIdentifier("sec13f-holdings-list")
            .background(HoldingsPalette.card)
            .navigationTitle("持仓明细").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索公司或 CUSIP")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("返回") { dismiss() }.accessibilityIdentifier("sec13f-detail-back") }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(Sec13FFilter.allCases) { action in
                            Button(action.rawValue) { filter = action }.accessibilityIdentifier("sec13f-filter-\(action.rawValue)")
                        }
                    } label: { Label(filter.rawValue, systemImage: "line.3.horizontal.decrease") }.accessibilityIdentifier("sec13f-filter-menu")
                }
            }
            .onChange(of: filter) { _, _ in expanded.removeAll() }
            .onChange(of: query) { _, _ in expanded.removeAll() }
        }.inAppBrowserCover(item: $browser)
    }
}

private struct Sec13FCompactPositionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let position: Sec13FNotificationSnapshot.Position
    let hasComparison: Bool
    var body: some View {
        let action = position.action(hasComparison: hasComparison)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 11))
        layout {
            Text(String(position.nameOfIssuer.prefix(1))).font(.title3.weight(.medium)).foregroundStyle(.secondary)
                .frame(width: 36, height: 36).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(position.nameOfIssuer).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                Text("\(position.isSoldOut == true ? "上期占比" : "占比") \(((position.isSoldOut == true ? position.previousWeightPct : position.weightPct) ?? 0).formatted(.number.precision(.fractionLength(2))))%\(position.putCall.map { " · \($0)" } ?? "")")
                    .font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                Text("\(position.isSoldOut == true ? "上期 " : "")\(sec13FMoney((position.isSoldOut == true ? position.previousValueUsd : position.valueUsd) ?? 0))")
                    .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
                Text(actionText(action)).font(.caption2.weight(.medium)).foregroundStyle(action.color)
            }.fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 17)
    }
    private func actionText(_ action: Sec13FFilter) -> String {
        guard (action == .increased || action == .decreased), let previous = position.previousShares, previous > 0 else { return action.rawValue }
        let change = abs(position.sharesChange ?? 0) / previous * 100
        return "\(action.rawValue) \(change.formatted(.number.precision(.fractionLength(1))))%"
    }
}

private func sec13FMoney(_ value: Double) -> String {
    if abs(value) >= 100_000_000 { return "$\((value / 100_000_000).formatted(.number.precision(.fractionLength(0...2))))亿" }
    if abs(value) >= 10_000 { return "$\((value / 10_000).formatted(.number.precision(.fractionLength(0...2))))万" }
    return "$\(value.formatted(.number.precision(.fractionLength(0...2))))"
}
private func sec13FQuarter(_ date: String?) -> String {
    guard let date else { return "报告期未提供" }
    let parts = date.split(separator: "-")
    guard parts.count >= 2, let month = Int(parts[1]), (1...12).contains(month) else { return date }
    return "\(parts[0]) · 第\((month - 1) / 3 + 1)季度"
}
private func sec13FFilingURL(_ manager: Sec13FNotificationSnapshot.Manager) -> URL? {
    guard let cik = manager.cik, let number = Int(cik), let accession = manager.accession,
          accession.allSatisfy({ $0.isNumber || $0 == "-" }), !accession.isEmpty else { return nil }
    return URL(string: "https://www.sec.gov/Archives/edgar/data/\(number)/\(accession.replacingOccurrences(of: "-", with: ""))/\(accession)-index.html")
}

#if DEBUG
/// Deterministic preview data never used by the live notification route.
struct Sec13FNotificationPreview: View {
    @State private var presented = true
    private let data = #"{"checkedAt":"2026-11-16T15:00:00Z","windowText":"季度披露窗口 · 示例数据","checked":8,"failed":0,"errors":[],"items":[{"key":"berkshire","cik":"0001067983","institutionName":"伯克希尔哈撒韦","displayName":"巴菲特","accession":"0001067983-26-000001","previousAccession":"0001067983-26-000000","reportDate":"2026-09-30","filingDate":"2026-11-16","positionsCount":3,"totalValueUsd":264500000000,"positions":[{"nameOfIssuer":"APPLE INC","previousShares":301200000,"shares":300000000,"sharesType":"SH","valueUsd":52300000000,"weightPct":19.77,"sharesChange":-1200000},{"nameOfIssuer":"AMERICAN EXPRESS CO","previousShares":149500000,"shares":151000000,"sharesType":"SH","valueUsd":46700000000,"weightPct":17.66,"sharesChange":1500000},{"nameOfIssuer":"一条用于检查小屏幕长名称排版的公司名称 / ALPHABET INC CLASS A","shares":17300000,"sharesType":"SH","valueUsd":4500000000,"weightPct":1.7,"isNew":true,"sharesChange":17300000}],"exitedPositions":[{"nameOfIssuer":"SOLD COMPANY","isSoldOut":true,"sharesChange":-2000000,"previousShares":2000000,"previousWeightPct":0.12,"sharesType":"SH","previousValueUsd":300000000}]}]}"#
    var body: some View {
        Button("打开持仓更新") { presented = true }
            .sheet(isPresented: $presented) {
                // Exercise the production fetch/loading/router container, not a sheet bypass.
                PushNotificationDetailsView(destination: .init(id: UUID())) {
                    try await Task.sleep(for: .milliseconds(200))
                    let snapshot = try JSONDecoder().decode(Sec13FNotificationSnapshot.self, from: Data(data.utf8))
                    return PushNotificationDetails(title: "13F", body: "示例数据", links: nil, imageURL: nil, sec13f: snapshot)
                }
                .presentationDragIndicator(.visible)
            }
    }
}
#endif
