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
            VStack(spacing: 14) {
                if let history {
                    hero(history)
                    summary(history)
                    trendChart(history)
                    annualList(history)
                    source(history)
                } else if isLoading {
                    hero(nil)
                    ProgressView("正在读取历史趋势")
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                } else {
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

    private func hero(_ history: CountryGDPHistory?) -> some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.23, blue: 0.57),
                    Color(red: 0.12, green: 0.42, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 80, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.08))
                .offset(x: 14, y: 12)

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Text(route.flag)
                        .font(.system(size: 34))
                        .frame(width: 54, height: 54)
                        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedName)
                            .font(.system(size: 23, weight: .bold))
                        Text("\(route.countryCode) · 名义 GDP")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.68))
                    }
                    Spacer()
                }

                if let latest = history?.points.last {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(latest.year) 年经济规模")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.68))
                        Text(CountryGDPFormat.compact(latest.gdpCurrentUSD))
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.72)
                            .lineLimit(1)
                    }
                } else {
                    Text("正在读取最新经济数据")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: InvestmentDesign.accent.opacity(0.16), radius: 14, y: 7)
    }

    private func summary(_ history: CountryGDPHistory) -> some View {
        let latest = history.points.last
        let previous = history.points.dropLast().last
        let growth = latest.flatMap { latest in
            previous.flatMap { $0.gdpCurrentUSD > 0 ? (latest.gdpCurrentUSD / $0.gdpCurrentUSD - 1) * 100 : nil }
        }
        return HStack(spacing: 9) {
            summaryCard(icon: "medal.fill", title: "全球排名", value: latest.map { "第 \($0.rank) 名" } ?? "—", tint: InvestmentDesign.warning)
            summaryCard(
                icon: "arrow.up.right",
                title: "同比变化",
                value: growth.map { "\($0 >= 0 ? "+" : "")\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "—",
                tint: (growth ?? 0) >= 0 ? InvestmentDesign.gain : InvestmentDesign.loss
            )
            summaryCard(
                icon: "calendar",
                title: "数据区间",
                value: history.points.first.map { "\($0.year)–\(latest?.year ?? $0.year)" } ?? "—",
                tint: InvestmentDesign.accent
            )
        }
    }

    private func summaryCard(icon: String, title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
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
        .padding(13)
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(InvestmentDesign.divider, lineWidth: 0.5)
        }
    }

    private func trendChart(_ history: CountryGDPHistory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GDP 长期走势")
                        .font(.system(size: 17, weight: .bold))
                    Text("\(history.points.first?.year ?? 0)–\(history.points.last?.year ?? 0) · 现价美元")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let first = history.points.first, let last = history.points.last, first.gdpCurrentUSD > 0 {
                    let totalGrowth = (last.gdpCurrentUSD / first.gdpCurrentUSD - 1) * 100
                    Text("区间 \(totalGrowth >= 0 ? "+" : "")\(totalGrowth, specifier: "%.0f")%")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(totalGrowth >= 0 ? InvestmentDesign.gain : InvestmentDesign.loss)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background((totalGrowth >= 0 ? InvestmentDesign.gain : InvestmentDesign.loss).opacity(0.09), in: Capsule())
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
                        .annotation(position: .top, alignment: .trailing) {
                            Text(CountryGDPFormat.compact(point.gdpCurrentUSD))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(InvestmentDesign.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(InvestmentDesign.accentSoft, in: Capsule())
                        }
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
            .frame(height: 230)
        }
        .padding(17)
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func annualList(_ history: CountryGDPHistory) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("历年数据").font(.system(size: 17, weight: .bold))
                    Text("名义 GDP 与当年全球位次")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "list.bullet")
                    .foregroundStyle(InvestmentDesign.accent)
            }
            .padding(16)
            ForEach(history.points.reversed()) { point in
                Divider().padding(.leading, 15)
                HStack {
                    Text(String(point.year))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(width: 42, alignment: .leading)
                    Text(CountryGDPFormat.compact(point.gdpCurrentUSD))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("全球 #\(point.rank)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(InvestmentDesign.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(InvestmentDesign.accentSoft, in: Capsule())
                }
                .padding(.horizontal, 15)
                .frame(height: 50)
                .background(point.id == history.points.last?.id ? InvestmentDesign.accent.opacity(0.035) : Color.clear)
            }
        }
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 18))
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
