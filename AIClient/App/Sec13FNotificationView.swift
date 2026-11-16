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
                (filter == .all || $0.action(hasComparison: hasComparison) == filter) &&
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
    case all = "全部", new = "新建仓", increased = "增持", decreased = "减持", exited = "清仓"
    case unchanged = "未变动", uncompared = "未比较"
    var id: Self { self }
    var color: Color {
        switch self {
        case .new, .increased: HoldingsPalette.red
        case .decreased, .exited: HoldingsPalette.green
        default: HoldingsPalette.blue
        }
    }
}

struct Sec13FNotificationView: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: Sec13FNotificationSnapshot
    @State private var filter = Sec13FFilter.all
    @State private var query = ""
    @State private var collapsed = Set<Int>()
    @State private var browser: InAppBrowserDestination?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                search
                filters
                ForEach(Array(snapshot.items.enumerated()), id: \.offset) { index, manager in
                    managerCard(manager, index: index)
                }
                if snapshot.items.isEmpty {
                    ContentUnavailableView("本次没有持仓更新", systemImage: "doc.text.magnifyingglass")
                }
                if !snapshot.errors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(snapshot.failed) 家机构未完成检查", systemImage: "exclamationmark.circle")
                            .font(.subheadline.weight(.semibold))
                        ForEach(Array(snapshot.errors.enumerated()), id: \.offset) { _, error in
                            Text("\(error.institutionName)：\(error.error)").font(.caption)
                        }
                    }
                    .foregroundStyle(HoldingsPalette.orange)
                }
                Text("13F 为季度末持仓快照，并非实时交易。增减持按持有数量变化区分，市值变化不等于买卖。仅涵盖申报范围内资产。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(snapshot.windowText).font(.caption).foregroundStyle(.tertiary)
            }
            .padding(20)
        }
        .background(HoldingsPalette.canvas.ignoresSafeArea())
        .accessibilityIdentifier("sec13f-notification-detail")
        .inAppBrowserCover(item: $browser)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("持仓披露", systemImage: "doc.text")
                    .font(.caption.weight(.semibold)).foregroundStyle(HoldingsPalette.blue)
                Spacer()
                DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭持仓更新")
            }
            Text("13F 持仓更新").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text("\(snapshot.items.count) 家机构有新披露 · 已检查 \(snapshot.checked) 家")
                .font(.subheadline).foregroundStyle(.secondary)
            if let date = ISO8601DateFormatter().date(from: snapshot.checkedAt) {
                Text(date, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索公司或 CUSIP", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("sec13f-search")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("清除搜索")
            }
        }
        .padding(12).background(HoldingsPalette.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Sec13FFilter.allCases) { item in
                    Button { filter = item } label: {
                        Text(item.rawValue).font(.subheadline.weight(.medium))
                            .padding(.horizontal, 15).padding(.vertical, 10)
                            .foregroundStyle(filter == item ? .white : Color.secondary)
                            .background(filter == item ? HoldingsPalette.blue : HoldingsPalette.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sec13f-filter-\(item.rawValue)")
                    .accessibilityAddTraits(filter == item ? .isSelected : [])
                }
            }
        }.scrollIndicators(.hidden)
    }

    private func managerCard(_ manager: Sec13FNotificationSnapshot.Manager, index: Int) -> some View {
        let positions = manager.positions(matching: filter, query: query)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if collapsed.contains(index) { collapsed.remove(index) } else { collapsed.insert(index) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(manager.institutionName).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                        if let name = manager.displayName, !name.isEmpty {
                            Text(name).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text("报告期 \(manager.reportDate ?? "未提供") · 披露 \(manager.filingDate ?? "未提供")")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: collapsed.contains(index) ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }.padding(16)
            }.buttonStyle(.plain)
            if !collapsed.contains(index) {
                HStack {
                    metric("申报市值", value: manager.totalValueUsd.map(money) ?? "未提供")
                    Spacer()
                    metric("当前持仓", value: manager.positionsCount.map { "\($0) 项" } ?? "未提供")
                }.padding(.horizontal, 16).padding(.bottom, 16)
                Divider().overlay(HoldingsPalette.divider)
                if manager.positions == nil && manager.exitedPositions == nil {
                    Text("本次快照未包含持仓明细").font(.subheadline).foregroundStyle(.secondary).padding(16)
                } else if positions.isEmpty {
                    Text("没有符合条件的持仓").font(.subheadline).foregroundStyle(.secondary).padding(16)
                } else {
                    LazyVStack(spacing: 0) {
                    ForEach(Array(positions.enumerated()), id: \.offset) { offset, position in
                        positionRow(position, hasComparison: manager.hasComparison)
                        if offset < positions.count - 1 { Divider().padding(.horizontal, 16) }
                    }
                    }
                }
                if let accession = manager.accession, !accession.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if let url = filingURL(cik: manager.cik, accession: accession) {
                            Button { browser = InAppBrowserDestination(url: url) } label: {
                                Label("查看 SEC 原始申报", systemImage: "arrow.up.right")
                            }
                                .font(.caption.weight(.medium))
                        }
                        Text("申报编号 \(accession)").font(.caption2).foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }.padding(16)
                }
            }
        }
        .background(HoldingsPalette.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }

    private func positionRow(_ position: Sec13FNotificationSnapshot.Position, hasComparison: Bool) -> some View {
        let action = position.action(hasComparison: hasComparison)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(position.nameOfIssuer).font(.subheadline.weight(.semibold)).textSelection(.enabled)
                Spacer(minLength: 0)
                Text(action.rawValue).font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .foregroundStyle(action.color).background(action.color.opacity(0.1), in: Capsule())
                    .fixedSize()
            }
            if let type = position.putCall, !type.isEmpty {
                Text(type).font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack { positionMetrics(position); Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 6) { positionMetrics(position) }
            }
            Text("\(position.isSoldOut == true ? "上期数量" : "持有数量") \(((position.isSoldOut == true ? position.previousShares : position.shares) ?? 0).formatted())\(position.sharesType.map { " \($0)" } ?? "")")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if hasComparison {
                Text("数量变化 \((position.sharesChange ?? 0).formatted(.number.sign(strategy: .always())))\(position.sharesType.map { " \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }.padding(16)
    }

    @ViewBuilder private func positionMetrics(_ position: Sec13FNotificationSnapshot.Position) -> some View {
        let exited = position.isSoldOut == true
        Text("\(exited ? "上期 " : "")\(money((exited ? position.previousValueUsd : position.valueUsd) ?? 0))").font(.subheadline.weight(.medium)).monospacedDigit()
        Text("\(exited ? "上期占比" : "占比") \(((exited ? position.previousWeightPct : position.weightPct) ?? 0).formatted(.number.precision(.fractionLength(2))))%")
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
    }

    private func filingURL(cik: String?, accession: String) -> URL? {
        guard let cik, let number = Int(cik),
              accession.allSatisfy({ $0.isNumber || $0 == "-" }), !accession.isEmpty else { return nil }
        return URL(string: "https://www.sec.gov/Archives/edgar/data/\(number)/\(accession.replacingOccurrences(of: "-", with: ""))/\(accession)-index.html")
    }

    private func money(_ value: Double) -> String {
        "$" + value.formatted(.number.notation(.compactName).precision(.fractionLength(0...2)))
    }
}

#if DEBUG
/// Deterministic preview data never used by the live notification route.
struct Sec13FNotificationPreview: View {
    @State private var presented = true
    private let data = #"{"checkedAt":"2026-11-16T15:00:00Z","windowText":"季度披露窗口 · 示例数据","checked":8,"failed":0,"errors":[],"items":[{"key":"berkshire","cik":"0001067983","institutionName":"伯克希尔哈撒韦","displayName":"巴菲特","accession":"0001067983-26-000001","previousAccession":"0001067983-26-000000","reportDate":"2026-09-30","filingDate":"2026-11-16","positionsCount":3,"totalValueUsd":264500000000,"positions":[{"nameOfIssuer":"APPLE INC","shares":300000000,"sharesType":"SH","valueUsd":52300000000,"weightPct":19.77,"sharesChange":-1200000},{"nameOfIssuer":"AMERICAN EXPRESS CO","shares":151000000,"sharesType":"SH","valueUsd":46700000000,"weightPct":17.66,"sharesChange":1500000},{"nameOfIssuer":"一条用于检查小屏幕长名称排版的公司名称 / ALPHABET INC CLASS A","shares":17300000,"sharesType":"SH","valueUsd":4500000000,"weightPct":1.7,"isNew":true,"sharesChange":17300000}],"exitedPositions":[{"nameOfIssuer":"SOLD COMPANY","isSoldOut":true,"sharesChange":-2000000,"previousShares":2000000,"previousWeightPct":0.12,"sharesType":"SH","previousValueUsd":300000000}]}]}"#
    var body: some View {
        Button("打开持仓更新") { presented = true }
            .sheet(isPresented: $presented) {
                if let snapshot = try? JSONDecoder().decode(Sec13FNotificationSnapshot.self, from: Data(data.utf8)) {
                    Sec13FNotificationView(snapshot: snapshot)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
            }
    }
}
#endif
