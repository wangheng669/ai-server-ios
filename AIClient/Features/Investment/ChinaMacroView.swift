import Charts
import Observation
import SwiftUI

struct ChinaMacroYear: Identifiable, Equatable {
    let year: Int
    var gdpGrowth: Double?
    var unemployment: Double?
    var inflation: Double?
    var lendingRate: Double?
    var depositRate: Double?
    var mortgageRate: Double?
    var privateCredit: Double?

    var id: Int { year }
}

enum ChinaMacroMetric: String, CaseIterable, Identifiable {
    case gdpGrowth
    case unemployment
    case inflation
    case lendingRate
    case depositRate
    case mortgageRate
    case privateCredit

    var id: Self { self }

    var title: String {
        switch self {
        case .gdpGrowth: "GDP"
        case .unemployment: "失业率"
        case .inflation: "通胀"
        case .lendingRate: "贷款利率"
        case .depositRate: "存款利率"
        case .mortgageRate: "房贷利率"
        case .privateCredit: "借贷水平"
        }
    }

    var longTitle: String {
        switch self {
        case .gdpGrowth: "国内生产总值年增长率"
        case .unemployment: "失业人口占劳动力比重"
        case .inflation: "居民消费价格年涨幅"
        case .lendingRate: "银行贷款利率"
        case .depositRate: "商业银行存款利率"
        case .mortgageRate: "5年期以上 LPR（房贷定价基准）"
        case .privateCredit: "私人部门银行信贷 / GDP"
        }
    }

    var color: Color {
        switch self {
        case .gdpGrowth: InvestmentDesign.accent
        case .unemployment: .cyan
        case .inflation: .orange
        case .lendingRate: InvestmentDesign.accent
        case .depositRate: .green
        case .mortgageRate: .pink
        case .privateCredit: .purple
        }
    }

    func value(in year: ChinaMacroYear) -> Double? {
        switch self {
        case .gdpGrowth: year.gdpGrowth
        case .unemployment: year.unemployment
        case .inflation: year.inflation
        case .lendingRate: year.lendingRate
        case .depositRate: year.depositRate
        case .mortgageRate: year.mortgageRate
        case .privateCredit: year.privateCredit
        }
    }
}

struct WorldBankIndicatorPoint: Decodable, Equatable {
    let year: Int
    let value: Double?

    init(year: Int, value: Double?) {
        self.year = year
        self.value = value
    }

    enum CodingKeys: String, CodingKey {
        case date, value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawYear = try container.decode(String.self, forKey: .date)
        guard let year = Int(rawYear) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: container, debugDescription: "Invalid year")
        }
        self.year = year
        self.value = try container.decodeIfPresent(Double.self, forKey: .value)
    }
}

struct WorldBankIndicatorResponse: Decodable {
    let points: [WorldBankIndicatorPoint]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        _ = try container.decode(WorldBankMetadata.self)
        points = try container.decode([WorldBankIndicatorPoint].self)
    }

    private struct WorldBankMetadata: Decodable {}
}

struct PBCMortgageAnnouncement: Equatable {
    let year: Int
    let month: Int
    let day: Int
    let url: URL

    var dateKey: Int { year * 10_000 + month * 100 + day }
}

struct ChinaMacroService {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.worldbank.org/v2/country/CHN/indicator/")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func history() async throws -> [ChinaMacroYear] {
        async let gdpGrowth = seriesOrEmpty("NY.GDP.MKTP.KD.ZG")
        async let unemployment = seriesOrEmpty("SL.UEM.TOTL.ZS")
        async let inflation = seriesOrEmpty("FP.CPI.TOTL.ZG")
        async let lendingRate = seriesOrEmpty("FR.INR.LEND")
        async let depositRate = seriesOrEmpty("FR.INR.DPST")
        async let privateCredit = seriesOrEmpty("FD.AST.PRVT.GD.ZS")
        let merged = await Self.merge(
            gdpGrowth: gdpGrowth,
            unemployment: unemployment,
            inflation: inflation,
            lendingRate: lendingRate,
            depositRate: depositRate,
            mortgageRate: [],
            privateCredit: privateCredit
        )
        guard !merged.isEmpty else { throw URLError(.cannotParseResponse) }
        return merged
    }

    private func seriesOrEmpty(_ indicator: String) async -> [WorldBankIndicatorPoint] {
        (try? await series(indicator)) ?? []
    }

    private func series(_ indicator: String) async throws -> [WorldBankIndicatorPoint] {
        let url = baseURL
            .appending(path: indicator)
            .appending(queryItems: [
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "per_page", value: "100")
            ])
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(WorldBankIndicatorResponse.self, from: data).points
    }

    func mortgageSeriesOrEmpty() async -> [WorldBankIndicatorPoint] {
        (try? await mortgageSeries()) ?? []
    }

    private func mortgageSeries() async throws -> [WorldBankIndicatorPoint] {
        let root = URL(string: "https://www.pbc.gov.cn")!
        let listPath = "/zhengcehuobisi/125207/125213/125440/3876551/"
        let listPages = ["index.html", "de24575c-2.html", "de24575c-3.html", "de24575c-4.html", "de24575c-5.html"]
        var announcements: [PBCMortgageAnnouncement] = []

        for page in listPages {
            guard let html = try? await html(at: root.appending(path: listPath + page)) else { continue }
            announcements.append(contentsOf: Self.parsePBCLPRAnnouncements(html: html, rootURL: root))
        }

        let latestByYear = Dictionary(grouping: announcements, by: \.year)
            .compactMap { _, values in values.max { $0.dateKey < $1.dateKey } }
            .sorted { $0.year > $1.year }

        var points: [WorldBankIndicatorPoint] = []
        for announcement in latestByYear {
            guard let detail = try? await html(at: announcement.url) else { continue }
            guard let value = Self.parseFiveYearLPR(html: detail) else { continue }
            points.append(WorldBankIndicatorPoint(year: announcement.year, value: value))
        }
        return points
    }

    private func html(at url: URL) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 AIServerClient", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return html
    }

    static func parsePBCLPRAnnouncements(html: String, rootURL: URL) -> [PBCMortgageAnnouncement] {
        let pattern = #"href=[\"']([^\"']+)[\"'][^>]*title=[\"'](20\d{2})年(\d{1,2})月(\d{1,2})日[^\"']*贷款市场报价利率"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard match.numberOfRanges == 5,
                  let pathRange = Range(match.range(at: 1), in: html),
                  let yearRange = Range(match.range(at: 2), in: html),
                  let monthRange = Range(match.range(at: 3), in: html),
                  let dayRange = Range(match.range(at: 4), in: html),
                  let year = Int(html[yearRange]),
                  let month = Int(html[monthRange]),
                  let day = Int(html[dayRange]),
                  let url = URL(string: String(html[pathRange]), relativeTo: rootURL)?.absoluteURL else { return nil }
            return PBCMortgageAnnouncement(year: year, month: month, day: day, url: url)
        }
    }

    static func parseFiveYearLPR(html: String) -> Double? {
        let pattern = #"5年期以上LPR为\s*([0-9]+(?:\.[0-9]+)?)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
              let valueRange = Range(match.range(at: 1), in: html) else { return nil }
        return Double(html[valueRange])
    }

    static func merge(
        gdpGrowth: [WorldBankIndicatorPoint],
        unemployment: [WorldBankIndicatorPoint],
        inflation: [WorldBankIndicatorPoint],
        lendingRate: [WorldBankIndicatorPoint],
        depositRate: [WorldBankIndicatorPoint],
        mortgageRate: [WorldBankIndicatorPoint],
        privateCredit: [WorldBankIndicatorPoint]
    ) -> [ChinaMacroYear] {
        var years: [Int: ChinaMacroYear] = [:]
        func insert(_ points: [WorldBankIndicatorPoint], keyPath: WritableKeyPath<ChinaMacroYear, Double?>) {
            for point in points where point.year >= 2000 && point.year <= Calendar.current.component(.year, from: Date()) {
                var item = years[point.year] ?? ChinaMacroYear(
                    year: point.year,
                    gdpGrowth: nil,
                    unemployment: nil,
                    inflation: nil,
                    lendingRate: nil,
                    depositRate: nil,
                    mortgageRate: nil,
                    privateCredit: nil
                )
                item[keyPath: keyPath] = point.value
                years[point.year] = item
            }
        }
        insert(gdpGrowth, keyPath: \.gdpGrowth)
        insert(unemployment, keyPath: \.unemployment)
        insert(inflation, keyPath: \.inflation)
        insert(lendingRate, keyPath: \.lendingRate)
        insert(depositRate, keyPath: \.depositRate)
        insert(mortgageRate, keyPath: \.mortgageRate)
        insert(privateCredit, keyPath: \.privateCredit)
        return years.values
            .filter {
                $0.gdpGrowth != nil || $0.unemployment != nil || $0.inflation != nil ||
                    $0.lendingRate != nil || $0.depositRate != nil ||
                    $0.mortgageRate != nil || $0.privateCredit != nil
            }
            .sorted { $0.year > $1.year }
    }

    static func mergingMortgage(
        _ points: [WorldBankIndicatorPoint],
        into years: [ChinaMacroYear]
    ) -> [ChinaMacroYear] {
        var merged = Dictionary(uniqueKeysWithValues: years.map { ($0.year, $0) })
        for point in points {
            var item = merged[point.year] ?? ChinaMacroYear(
                year: point.year,
                gdpGrowth: nil,
                unemployment: nil,
                inflation: nil,
                lendingRate: nil,
                depositRate: nil,
                mortgageRate: nil,
                privateCredit: nil
            )
            item.mortgageRate = point.value
            merged[point.year] = item
        }
        return merged.values.sorted { $0.year > $1.year }
    }
}

@MainActor
@Observable
final class ChinaMacroStore {
    var years: [ChinaMacroYear] = []
    var isLoading = false
    var loadError = false
    private let service: ChinaMacroService

    init(service: ChinaMacroService = ChinaMacroService()) {
        self.service = service
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = false
        defer { isLoading = false }
        do {
            years = try await service.history()
            loadError = years.isEmpty
            guard !years.isEmpty else { return }
            let mortgageRates = await service.mortgageSeriesOrEmpty()
            years = ChinaMacroService.mergingMortgage(mortgageRates, into: years)
        } catch {
            loadError = true
        }
    }
}

private enum ChinaMacroSection: String, CaseIterable, Identifiable {
    case overview = "总览"
    case growth = "增长"
    case prices = "物价"
    case rates = "利率"
    case credit = "信用"

    var id: Self { self }

    var metrics: [ChinaMacroMetric] {
        switch self {
        case .overview: []
        case .growth: [.gdpGrowth, .unemployment]
        case .prices: [.inflation, .depositRate]
        case .rates: [.mortgageRate, .lendingRate, .depositRate]
        case .credit: [.privateCredit, .lendingRate]
        }
    }

    var title: String {
        switch self {
        case .overview: "中国经济脉搏"
        case .growth: "增长动能"
        case .prices: "价格与居民资金"
        case .rates: "利率环境"
        case .credit: "信用与杠杆"
        }
    }
}

struct ChinaMacroView: View {
    @State private var store = ChinaMacroStore()
    @State private var section = ChinaMacroSection.overview
    @State private var metric = ChinaMacroMetric.gdpGrowth

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                header
                sectionPicker
                if store.isLoading && store.years.isEmpty {
                    ProgressView("正在读取中国宏观数据")
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if store.loadError && store.years.isEmpty {
                    unavailable
                } else if section == .overview {
                    overview
                    sourceFooter
                } else {
                    detail
                    sourceFooter
                }
            }
            .padding(.horizontal, InvestmentDesign.pageInset)
            .padding(.vertical, 14)
        }
        .background(InvestmentDesign.canvas)
        .refreshable { await store.load() }
        .task { if store.years.isEmpty { await store.load() } }
        .onChange(of: section) { _, newSection in
            if let first = newSection.metrics.first { metric = first }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(section.title)
                .font(.system(size: 27, weight: .bold, design: .rounded))
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(latestYear.map { "数据更新至 \(String($0)) 年" } ?? "正在更新数据")
                if store.isLoading && !store.years.isEmpty { ProgressView().controlSize(.mini) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sectionPicker: some View {
        HStack(spacing: 4) {
            ForEach(ChinaMacroSection.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { section = item }
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline.weight(section == item ? .semibold : .regular))
                        .foregroundStyle(section == item ? InvestmentDesign.accent : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(section == item ? InvestmentDesign.surface : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var unavailable: some View {
        ContentUnavailableView {
            Label("宏观数据暂不可用", systemImage: "chart.line.downtrend.xyaxis")
        } description: {
            Text("数据服务暂未响应")
        } actions: {
            Button("重新加载") { Task { await store.load() } }
        }
        .frame(minHeight: 300)
    }

    private var overview: some View {
        VStack(spacing: 14) {
            storyCard(
                section: .growth,
                icon: "chart.line.uptrend.xyaxis",
                tint: InvestmentDesign.accent,
                metrics: [.gdpGrowth, .unemployment],
                insight: growthInsight
            )
            storyCard(
                section: .prices,
                icon: "cart",
                tint: .orange,
                metrics: [.inflation, .depositRate],
                insight: "把居民物价变化与储蓄回报放在一起观察"
            )
            storyCard(
                section: .rates,
                icon: "house",
                tint: .purple,
                metrics: [.mortgageRate, .lendingRate, .privateCredit],
                insight: "5年期LPR是房贷定价基准，实际利率还会加减点"
            )
            Button {
                section = .credit
            } label: {
                HStack {
                    Image(systemName: "chart.bar.doc.horizontal")
                    Text("查看信用与杠杆历史")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.semibold))
                .padding(15)
                .background(InvestmentDesign.surface)
                .clipShape(RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
            }
            .buttonStyle(.plain)
        }
    }

    private func storyCard(
        section target: ChinaMacroSection,
        icon: String,
        tint: Color,
        metrics: [ChinaMacroMetric],
        insight: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(target.title, systemImage: icon)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(metrics.enumerated()), id: \.element) { index, item in
                        if index > 0 { Divider().frame(height: 48).padding(.horizontal, 10) }
                        metricSummary(item)
                    }
                }
                GeometryReader { proxy in
                    sparkline(metrics.first ?? .inflation, tint: tint)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                Text(insight)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InvestmentDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius)
                .stroke(InvestmentDesign.divider, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
        .onTapGesture { section = target }
        .accessibilityAddTraits(.isButton)
    }

    private func metricSummary(_ item: ChinaMacroMetric) -> some View {
        let latest = latest(item)
        return VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(latest.flatMap { item.value(in: $0) }.map { "\(format($0))%" } ?? "—")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(item.color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(latest.map { "\(String($0.year)) 年" } ?? "暂无数据")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sparkline(_ item: ChinaMacroMetric, tint: Color) -> some View {
        let years = store.years
            .filter { item.value(in: $0) != nil }
            .sorted { $0.year < $1.year }
        return Chart(years) { year in
            if let value = item.value(in: year) {
                LineMark(x: .value("年份", year.year), y: .value(item.title, value))
                    .foregroundStyle(tint)
                    .interpolationMethod(.monotone)
                AreaMark(x: .value("年份", year.year), y: .value(item.title, value))
                    .foregroundStyle(tint.opacity(0.08))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: (years.first?.year ?? 2000)...(years.last?.year ?? 2026))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    private var detail: some View {
        VStack(spacing: 14) {
            metricPicker
            trendCard
            recentValues
        }
    }

    private var metricPicker: some View {
        HStack(spacing: 8) {
            ForEach(section.metrics) { item in
                Button { metric = item } label: {
                    VStack(spacing: 5) {
                        Image(systemName: icon(for: item))
                        Text(item.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(metric == item ? item.color : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(metric == item ? item.color.opacity(0.10) : InvestmentDesign.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(metric == item ? item.color.opacity(0.4) : InvestmentDesign.divider, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.longTitle).font(.headline)
                    Text("年度值 · 单位 %").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let latest = latest(metric), let value = metric.value(in: latest) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(format(value))%")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(metric.color)
                        Text("\(String(latest.year)) 年").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Chart(store.years.reversed()) { item in
                if let value = metric.value(in: item) {
                    LineMark(x: .value("年份", item.year), y: .value(metric.title, value))
                        .foregroundStyle(metric.color)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(metric == .mortgageRate ? .stepEnd : .monotone)
                    AreaMark(x: .value("年份", item.year), y: .value(metric.title, value))
                        .foregroundStyle(metric.color.opacity(0.10))
                        .interpolationMethod(metric == .mortgageRate ? .stepEnd : .monotone)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.10))
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.10))
                    AxisValueLabel()
                }
            }
            .frame(height: 235)
        }
        .padding(16)
        .background(InvestmentDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
    }

    private var recentValues: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("最近数据")
                .font(.headline)
                .padding(16)
            ForEach(Array(metricYears.prefix(6))) { item in
                Divider().padding(.leading, 16)
                HStack {
                    Text("\(String(item.year)) 年")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(metric.value(in: item).map { "\(format($0))%" } ?? "—")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(metric.color)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(InvestmentDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
    }

    private var sourceFooter: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("世界银行 · 中国人民银行", systemImage: "checkmark.shield.fill")
                .font(.footnote.weight(.semibold))
            Text("GDP、失业、物价、存贷款与信贷指标采用年度数据；5年期以上LPR为房贷定价基准，并非个人实际执行利率。不同指标发布节奏不同，页面会标注各自年份。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var latestYear: Int? { store.years.first?.year }
    private var metricYears: [ChinaMacroYear] { store.years.filter { metric.value(in: $0) != nil } }
    private func latest(_ item: ChinaMacroMetric) -> ChinaMacroYear? { store.years.first { item.value(in: $0) != nil } }

    private var growthInsight: String {
        guard let value = latest(.gdpGrowth).flatMap({ ChinaMacroMetric.gdpGrowth.value(in: $0) }) else {
            return "观察经济增长与劳动力市场的长期变化"
        }
        return value >= 5 ? "经济增速保持较强韧性" : value >= 3 ? "经济维持温和增长" : "增长动能仍需修复"
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(abs(value) >= 100 ? 1 : 2)))
    }

    private func icon(for metric: ChinaMacroMetric) -> String {
        switch metric {
        case .gdpGrowth: "chart.line.uptrend.xyaxis"
        case .unemployment: "person.2"
        case .inflation: "cart"
        case .lendingRate: "percent"
        case .depositRate: "banknote"
        case .mortgageRate: "house"
        case .privateCredit: "building.columns"
        }
    }
}

#Preview { ChinaMacroView() }
