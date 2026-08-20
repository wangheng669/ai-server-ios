import Charts
import SwiftUI

struct CountryGDPRoute: Hashable, Identifiable {
    let countryCode: String
    let iso2Code: String
    let countryName: String
    let gdpPerCapitaUSD: Double?

    var id: String { countryCode }

    init(country: CountryGDP) {
        countryCode = country.countryCode
        iso2Code = country.iso2Code
        countryName = country.localizedName
        gdpPerCapitaUSD = country.gdpPerCapitaUSD
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
    @State private var selectedYear: String?

    private var localizedName: String {
        if route.iso2Code == "CN" { return "中国" }
        return Locale(identifier: "zh-Hans_CN").localizedString(forRegionCode: route.iso2Code) ?? route.countryName
    }

    var body: some View {
        Group {
            if let history {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        hero(history)
                            .padding(.horizontal, InvestmentDesign.pageInset)
                            .padding(.top, 20)
                            .padding(.bottom, 24)

                        metricStrip(history)
                            .padding(.horizontal, InvestmentDesign.pageInset)
                            .padding(.bottom, 34)

                        trendSection(history)
                            .padding(.bottom, 36)

                        annualHistory(history)

                        source(history)
                            .padding(.horizontal, InvestmentDesign.pageInset)
                            .padding(.vertical, 24)
                    }
                }
                .scrollIndicators(.hidden)
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
        .background(InvestmentDesign.surface)
        .overlay(alignment: .bottomTrailing) {
            DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭国家 GDP 详情")
                .padding(16)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            detailHeader
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private var detailHeader: some View {
        HStack {
            Text("国家 GDP")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, InvestmentDesign.pageInset)
        .frame(height: 50)
        .background(InvestmentDesign.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(InvestmentDesign.divider)
                .frame(height: 0.5)
        }
    }

    private func hero(_ history: CountryGDPHistory?) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 11) {
                FlatCountryFlag(iso2Code: route.iso2Code, width: 46, height: 31)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizedName)
                        .font(.title2.bold())
                    Text("\(route.countryCode) · 世界银行")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .tracking(0.3)
                }
            }

            if let latest = history?.points.last {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GDP 总量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CountryGDPFormat.compact(latest.gdpCurrentUSD))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(verbatim: "\(latest.year) 年 · 现价美元口径")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("正在读取最新经济数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricStrip(_ history: CountryGDPHistory) -> some View {
        let latest = history.points.last
        let previous = history.points.dropLast().last
        let growth = latest.flatMap { latest in
            previous.flatMap { $0.gdpCurrentUSD > 0 ? (latest.gdpCurrentUSD / $0.gdpCurrentUSD - 1) * 100 : nil }
        }
        return HStack(spacing: 0) {
            metricCell("全球位次", latest.map { "\($0.rank)" } ?? "—", tint: .primary)
            metricCell(
                "同比变化",
                growth.map { "\($0 >= 0 ? "+" : "")\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "—",
                tint: (growth ?? 0) >= 0 ? InvestmentDesign.gain : InvestmentDesign.loss
            )
            metricCell(
                "人均 GDP",
                route.gdpPerCapitaUSD.map(CountryGDPFormat.perCapita) ?? "—",
                tint: .primary
            )
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(InvestmentDesign.divider)
                .frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(InvestmentDesign.divider)
                .frame(height: 0.5)
        }
    }

    private func metricCell(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func annualRow(_ point: CountryGDPHistoryPoint, isLatest: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(point.year))
                    .font(.body.weight(isLatest ? .semibold : .regular))
                Text("全球位次 \(point.rank)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(CountryGDPFormat.compact(point.gdpCurrentUSD))
                .font(.subheadline.weight(isLatest ? .semibold : .regular))
                .monospacedDigit()
        }
        .padding(.horizontal, InvestmentDesign.pageInset)
        .frame(minHeight: 58)
    }

    private func trendSection(_ history: CountryGDPHistory) -> some View {
        let selectedPoint = selectedYear.flatMap { year in
            history.points.first(where: { String($0.year) == year })
        }
        let focusedPoint = selectedPoint ?? history.points.last
        let yMaximum = chartMaximum(history)
        let yTicks = chartTicks(maximum: yMaximum)

        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("GDP 走势")
                        .font(.title3.bold())
                    Text(verbatim: "\(history.points.first?.year ?? 0)–\(history.points.last?.year ?? 0) · 现价美元")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let selectedPoint {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(selectedPoint.year))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(CountryGDPFormat.ranking(selectedPoint.gdpCurrentUSD))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                } else if let first = history.points.first, let last = history.points.last, first.gdpCurrentUSD > 0 {
                    let totalGrowth = (last.gdpCurrentUSD / first.gdpCurrentUSD - 1) * 100
                    Text("\(totalGrowth >= 0 ? "+" : "")\(totalGrowth, specifier: "%.0f")%")
                        .font(.subheadline.weight(.semibold))
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
                        colors: [InvestmentDesign.accent.opacity(0.18), InvestmentDesign.accent.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("年份", String(point.year)),
                    y: .value("GDP", point.gdpCurrentUSD)
                )
                .foregroundStyle(InvestmentDesign.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.15, lineCap: .round, lineJoin: .round))

                if point.id == focusedPoint?.id, let focusedPoint {
                    RuleMark(x: .value("选中年份", String(focusedPoint.year)))
                        .foregroundStyle(InvestmentDesign.accent.opacity(0.24))
                        .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))

                    PointMark(
                        x: .value("选中年份", String(focusedPoint.year)),
                        y: .value("GDP", focusedPoint.gdpCurrentUSD)
                    )
                    .foregroundStyle(InvestmentDesign.accent)
                    .symbolSize(48)
                }
            }
            .chartYScale(domain: 0...yMaximum)
            .chartXScale(range: .plotDimension(startPadding: 18, endPadding: 18))
            .chartYAxis {
                AxisMarks(position: .leading, values: yTicks) { value in
                    AxisGridLine()
                        .foregroundStyle(InvestmentDesign.divider.opacity(0.65))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(CountryGDPFormat.axis(amount))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: chartYears(history)) {
                    AxisValueLabel()
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    selectNearestYear(
                                        at: value.location.x,
                                        proxy: proxy,
                                        geometry: geometry,
                                        history: history
                                    )
                                }
                        )
                        .accessibilityLabel("GDP 历年趋势")
                        .accessibilityHint("在图表上左右滑动查看不同年份")
                }
            }
            .frame(height: 230)
        }
        .padding(.horizontal, InvestmentDesign.pageInset)
    }

    private func selectNearestYear(
        at locationX: CGFloat,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        history: CountryGDPHistory
    ) {
        guard !history.points.isEmpty,
              let plotFrame = proxy.plotFrame else { return }

        let frame = geometry[plotFrame]
        guard frame.width > 0 else { return }
        let relativeX = min(max(locationX - frame.minX, 0), frame.width)
        let progress = relativeX / frame.width
        guard let index = CountryGDPChartInteraction.nearestIndex(
            progress: progress,
            count: history.points.count
        ) else { return }
        selectedYear = String(history.points[index].year)
    }

    private func chartMaximum(_ history: CountryGDPHistory) -> Double {
        let maximum = history.points.map(\.gdpCurrentUSD).max() ?? 1
        let step = chartStep(for: maximum)
        return max(step, ceil(maximum / step) * step)
    }

    private func chartStep(for maximum: Double) -> Double {
        switch maximum {
        case 10_000_000_000_000...: return 5_000_000_000_000
        case 2_000_000_000_000...: return 1_000_000_000_000
        case 500_000_000_000...: return 250_000_000_000
        case 100_000_000_000...: return 50_000_000_000
        default: return max(1, maximum / 4)
        }
    }

    private func chartTicks(maximum: Double) -> [Double] {
        let step = chartStep(for: maximum)
        return stride(from: 0, through: maximum, by: step).map { $0 }
    }

    private func chartYears(_ history: CountryGDPHistory) -> [String] {
        let points = history.points
        guard points.count > 3 else { return points.map { String($0.year) } }
        return [
            String(points[0].year),
            String(points[points.count / 2].year),
            String(points[points.count - 1].year)
        ]
    }

    private func annualHistory(_ history: CountryGDPHistory) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("历年数据")
                    .font(.title3.bold())
                Spacer()
                Text("\(history.points.count) 年")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, InvestmentDesign.pageInset)
            .padding(.bottom, 12)

            LazyVStack(spacing: 0) {
                ForEach(Array(history.points.reversed().enumerated()), id: \.element.id) { index, point in
                    annualRow(point, isLatest: point.id == history.points.last?.id)
                    if index < history.points.count - 1 {
                        Divider()
                            .overlay(InvestmentDesign.divider)
                            .padding(.leading, InvestmentDesign.pageInset)
                    }
                }
            }
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

enum CountryGDPChartInteraction {
    static func nearestIndex(progress: CGFloat, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let clampedProgress = min(max(progress, 0), 1)
        return Int((clampedProgress * CGFloat(count - 1)).rounded())
    }
}
