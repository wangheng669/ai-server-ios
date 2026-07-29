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
        ScrollView {
            VStack(spacing: 12) {
                hero
                if let history {
                    summary(history)
                    trendChart(history)
                    annualList(history)
                    source(history)
                } else if isLoading {
                    ProgressView("正在读取历史趋势")
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                } else {
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
            }
            .padding(.horizontal, InvestmentDesign.pageInset)
            .padding(.bottom, 100)
        }
        .background(InvestmentDesign.canvas)
        .scrollIndicators(.hidden)
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

    private var hero: some View {
        HStack(spacing: 14) {
            Text(route.flag)
                .font(.system(size: 38))
            VStack(alignment: .leading, spacing: 4) {
                Text(localizedName)
                    .font(.system(size: 24, weight: .bold))
                Text("\(route.countryCode) · 名义 GDP")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(InvestmentDesign.accent)
        }
        .padding(17)
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
    }

    private func summary(_ history: CountryGDPHistory) -> some View {
        let latest = history.points.last
        let previous = history.points.dropLast().last
        let growth = latest.flatMap { latest in
            previous.flatMap { $0.gdpCurrentUSD > 0 ? (latest.gdpCurrentUSD / $0.gdpCurrentUSD - 1) * 100 : nil }
        }
        return HStack(spacing: 9) {
            summaryCard(title: "最新规模", value: latest.map { CountryGDPFormat.compact($0.gdpCurrentUSD) } ?? "—", tint: InvestmentDesign.accent)
            summaryCard(title: "全球排名", value: latest.map { "第 \($0.rank) 名" } ?? "—", tint: InvestmentDesign.warning)
            summaryCard(
                title: "同比变化",
                value: growth.map { "\($0 >= 0 ? "+" : "")\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "—",
                tint: (growth ?? 0) >= 0 ? InvestmentDesign.gain : InvestmentDesign.loss
            )
        }
    }

    private func summaryCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func trendChart(_ history: CountryGDPHistory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("近 \(history.points.count) 年 GDP 走势")
                    .font(.system(size: 16, weight: .bold))
                Text("现价美元 · 名义值")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
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
        .padding(16)
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
    }

    private func annualList(_ history: CountryGDPHistory) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("历年数据").font(.system(size: 16, weight: .bold))
                Spacer()
                Text("全球排名").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(15)
            ForEach(history.points.reversed()) { point in
                Divider().padding(.leading, 15)
                HStack {
                    Text(String(point.year))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(width: 42, alignment: .leading)
                    Text(CountryGDPFormat.compact(point.gdpCurrentUSD))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("#\(point.rank)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(InvestmentDesign.accent)
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.horizontal, 15)
                .frame(height: 46)
            }
        }
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
    }

    private func source(_ history: CountryGDPHistory) -> some View {
        Link(destination: history.sourceURL) {
            Label("数据来源：世界银行 \(history.metric)", systemImage: "checkmark.shield.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 12))
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
