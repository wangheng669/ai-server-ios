import Charts
import SwiftUI

struct CountryGDPRoute: Hashable {
    let countryCode: String
    let iso2Code: String
    let countryName: String

    init(country: CountryGDP) {
        countryCode = country.countryCode
        iso2Code = country.iso2Code
        countryName = country.localizedName
    }

    var flag: String {
        iso2Code.uppercased().unicodeScalars.compactMap { scalar in
            UnicodeScalar(127397 + scalar.value).map(String.init)
        }.joined()
    }
}

struct CountryGDPHistoryResponse: Decodable {
    let success: Bool
    let data: CountryGDPHistory
}

struct CountryGDPHistory: Decodable {
    let countryCode: String
    let iso2Code: String
    let countryName: String
    let metric: String
    let unit: String
    let sourceName: String
    let sourceURL: URL
    let updatedAt: String
    let points: [CountryGDPHistoryPoint]

    enum CodingKeys: String, CodingKey {
        case metric, unit, points
        case countryCode = "country_code"
        case iso2Code = "iso2_code"
        case countryName = "country_name"
        case sourceName = "source_name"
        case sourceURL = "source_url"
        case updatedAt = "updated_at"
    }
}

struct CountryGDPHistoryPoint: Decodable, Identifiable {
    let year: Int
    let rank: Int
    let gdpCurrentUSD: Double

    var id: Int { year }

    enum CodingKeys: String, CodingKey {
        case year, rank
        case gdpCurrentUSD = "gdp_current_usd"
    }
}

struct CountryGDPDetailView: View {
    let route: CountryGDPRoute
    @Environment(\.dismiss) private var dismiss
    @State private var history: CountryGDPHistory?
    @State private var isLoading = true
    @State private var loadFailed = false

    private var localizedName: String {
        if route.iso2Code == "CN" { return "中国" }
        return Locale(identifier: "zh-Hans_CN").localizedString(forRegionCode: route.iso2Code) ?? route.countryName
    }

    var body: some View {
        Group {
            if let history {
                List {
                    Section {
                    hero(history)
                    }

                    Section("概览") {
                        summary(history)
                    }

                    Section {
                    trendChart(history)
                    } header: {
                        Text("GDP 长期走势")
                    }

                    Section("历年数据") {
                        ForEach(history.points.reversed()) { point in
                            annualRow(point, isLatest: point.id == history.points.last?.id)
                        }
                    }

                    Section {
                        source(history)
                    }
                }
                .listStyle(.insetGrouped)
            } else if isLoading {
                VStack(spacing: 20) {
                    hero(nil)
                    ProgressView("正在读取历史趋势")
                        .frame(maxWidth: .infinity)
                }
                .padding(InvestmentDesign.pageInset)
            } else {
                VStack(spacing: 20) {
                    hero(nil)
                    ContentUnavailableView {
                        Label("历史趋势暂不可用", systemImage: "chart.xyaxis.line")
                    } description: {
                        Text("服务器未返回该国家的历年 GDP 数据")
                    } actions: {
                        Button("重新加载") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(minHeight: 280)
                }
                .padding(InvestmentDesign.pageInset)
            }
        }
        .background(InvestmentDesign.canvas)
        .safeAreaInset(edge: .top, spacing: 0) {
            detailHeader
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(InvestmentDesign.secondarySurface, in: Circle())
            }
            .buttonStyle(.plain)
            Text("GDP 趋势")
                .font(.system(size: 17, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, InvestmentDesign.pageInset)
        .frame(height: 52)
        .background(.bar)
    }

    private func hero(_ history: CountryGDPHistory?) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text(route.flag)
                    .font(.system(size: 35))
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizedName)
                        .font(.title2.bold())
                    Text("\(route.countryCode) · 名义 GDP")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let latest = history?.points.last {
                VStack(alignment: .leading, spacing: 3) {
                    Text(CountryGDPFormat.compact(latest.gdpCurrentUSD))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(verbatim: "\(latest.year) 年经济规模")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("正在读取最新经济数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func summary(_ history: CountryGDPHistory) -> some View {
        let latest = history.points.last
        let previous = history.points.dropLast().last
        let period = history.points.first.map { "\($0.year)–\(latest?.year ?? $0.year)" } ?? "—"
        let growth = latest.flatMap { latest in
            previous.flatMap { $0.gdpCurrentUSD > 0 ? (latest.gdpCurrentUSD / $0.gdpCurrentUSD - 1) * 100 : nil }
        }
        return Group {
            LabeledContent("全球排名") {
                Text(latest.map { "第 \($0.rank) 名" } ?? "—")
                    .foregroundStyle(InvestmentDesign.accent)
            }
            LabeledContent("同比变化") {
                Text(growth.map { "\($0 >= 0 ? "+" : "")\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "—")
                    .foregroundStyle((growth ?? 0) >= 0 ? InvestmentDesign.gain : InvestmentDesign.loss)
            }
            LabeledContent("数据区间") {
                Text(verbatim: period)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }

    private func annualRow(_ point: CountryGDPHistoryPoint, isLatest: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(point.year))
                    .font(.body.weight(isLatest ? .semibold : .regular))
                Text("全球第 \(point.rank) 名")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(CountryGDPFormat.compact(point.gdpCurrentUSD))
                .font(.subheadline.weight(isLatest ? .semibold : .regular))
                .monospacedDigit()
        }
    }

    private func trendChart(_ history: CountryGDPHistory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(history.points.first?.year ?? 0)–\(history.points.last?.year ?? 0) · 现价美元")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let first = history.points.first, let last = history.points.last, first.gdpCurrentUSD > 0 {
                    let totalGrowth = (last.gdpCurrentUSD / first.gdpCurrentUSD - 1) * 100
                    Text("区间 \(totalGrowth >= 0 ? "+" : "")\(totalGrowth, specifier: "%.0f")%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(totalGrowth >= 0 ? InvestmentDesign.gain : InvestmentDesign.loss)
                }
            }
            Chart(history.points) { point in
                AreaMark(
                    x: .value("年份", String(point.year)),
                    y: .value("GDP", point.gdpCurrentUSD)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [InvestmentDesign.accent.opacity(0.28), InvestmentDesign.accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("年份", String(point.year)),
                    y: .value("GDP", point.gdpCurrentUSD)
                )
                .foregroundStyle(InvestmentDesign.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                PointMark(
                    x: .value("年份", String(point.year)),
                    y: .value("GDP", point.gdpCurrentUSD)
                )
                .foregroundStyle(InvestmentDesign.accent)
                .symbolSize(point.id == history.points.last?.id ? 46 : 16)

                if point.id == history.points.last?.id {
                    RuleMark(x: .value("最新年份", String(point.year)))
                        .foregroundStyle(InvestmentDesign.accent.opacity(0.18))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
            }
            .chartXScale(range: .plotDimension(startPadding: 18, endPadding: 18))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(InvestmentDesign.divider)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(CountryGDPFormat.axis(amount))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: history.points.enumerated().compactMap { index, point in
                    index.isMultiple(of: 3) || point.id == history.points.last?.id ? String(point.year) : nil
                }) { value in
                    AxisValueLabel {
                        if let year = value.as(String.self) {
                            Text(year)
                        }
                    }
                }
            }
            .frame(height: 220)
        }
    }

    private func source(_ history: CountryGDPHistory) -> some View {
        Link(destination: history.sourceURL) {
            Label("数据来源：世界银行 \(history.metric)", systemImage: "checkmark.shield.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func load() async {
        if history == nil { isLoading = true }
        loadFailed = false
        defer { isLoading = false }
        do {
            history = try await CountryGDPService().history(countryCode: route.countryCode)
        } catch {
            if history == nil { loadFailed = true }
        }
    }
}

extension CountryGDPFormat {
    static func axis(_ value: Double) -> String {
        if value >= 1_000_000_000_000 {
            return String(format: "%.0f万亿", value / 1_000_000_000_000)
        }
        return String(format: "%.0f亿", value / 100_000_000)
    }
}
