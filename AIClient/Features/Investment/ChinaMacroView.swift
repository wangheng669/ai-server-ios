import Charts
import Observation
import SwiftUI

struct ChinaMacroYear: Identifiable, Equatable {
    let year: Int
    var inflation: Double?
    var lendingRate: Double?
    var depositRate: Double?
    var mortgageRate: Double?
    var privateCredit: Double?

    var id: Int { year }
}

enum ChinaMacroMetric: String, CaseIterable, Identifiable {
    case inflation
    case lendingRate
    case depositRate
    case mortgageRate
    case privateCredit

    var id: Self { self }

    var title: String {
        switch self {
        case .inflation: "通胀"
        case .lendingRate: "贷款利率"
        case .depositRate: "存款利率"
        case .mortgageRate: "房贷利率"
        case .privateCredit: "借贷水平"
        }
    }

    var longTitle: String {
        switch self {
        case .inflation: "居民消费价格年涨幅"
        case .lendingRate: "银行贷款利率"
        case .depositRate: "商业银行存款利率"
        case .mortgageRate: "5年期以上 LPR（房贷定价基准）"
        case .privateCredit: "私人部门银行信贷 / GDP"
        }
    }

    var color: Color {
        switch self {
        case .inflation: .orange
        case .lendingRate: InvestmentDesign.accent
        case .depositRate: .green
        case .mortgageRate: .pink
        case .privateCredit: .purple
        }
    }

    func value(in year: ChinaMacroYear) -> Double? {
        switch self {
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
        async let inflation = seriesOrEmpty("FP.CPI.TOTL.ZG")
        async let lendingRate = seriesOrEmpty("FR.INR.LEND")
        async let depositRate = seriesOrEmpty("FR.INR.DPST")
        async let privateCredit = seriesOrEmpty("FD.AST.PRVT.GD.ZS")
        let merged = await Self.merge(
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
        insert(inflation, keyPath: \.inflation)
        insert(lendingRate, keyPath: \.lendingRate)
        insert(depositRate, keyPath: \.depositRate)
        insert(mortgageRate, keyPath: \.mortgageRate)
        insert(privateCredit, keyPath: \.privateCredit)
        return years.values
            .filter {
                $0.inflation != nil || $0.lendingRate != nil || $0.depositRate != nil ||
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

struct ChinaMacroView: View {
    @State private var store = ChinaMacroStore()
    @State private var metric = ChinaMacroMetric.inflation

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                introduction
                if store.isLoading && store.years.isEmpty {
                    ProgressView("正在读取中国年度宏观数据")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if store.loadError && store.years.isEmpty {
                    ContentUnavailableView {
                        Label("宏观数据暂不可用", systemImage: "chart.line.downtrend.xyaxis")
                    } description: {
                        Text("世界银行数据服务暂未响应")
                    } actions: {
                        Button("重新加载") { Task { await store.load() } }
                    }
                    .frame(minHeight: 280)
                } else {
                    latestCards
                    trendCard
                    annualTable
                    sourceFooter
                }
            }
            .padding(.horizontal, InvestmentDesign.pageInset)
            .padding(.vertical, 14)
        }
        .background(InvestmentDesign.canvas)
        .refreshable { await store.load() }
        .task { if store.years.isEmpty { await store.load() } }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("中国年度宏观")
                .font(.system(size: 25, weight: .bold, design: .rounded))
            Text("把物价、贷款、存款、房贷定价基准与信贷规模放在同一条年度时间线上，观察资金价格与经济杠杆的长期变化。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var latestCards: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(ChinaMacroMetric.allCases) { item in
                    let latest = store.years.first { item.value(in: $0) != nil }
                    Button { metric = item } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(item.title, systemImage: icon(for: item))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item.color)
                            Text(latest.flatMap { item.value(in: $0) }.map { format($0) } ?? "—")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text(latest.map { "\(String($0.year))年 · %" } ?? "暂无数据")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 142, alignment: .leading)
                        .padding(14)
                        .background(metric == item ? item.color.opacity(0.10) : InvestmentDesign.surface)
                        .clipShape(RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius)
                                .stroke(metric == item ? item.color.opacity(0.55) : InvestmentDesign.divider, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(metric.longTitle)
                    .font(.headline)
                Text("年度值 · 单位 %")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Chart(store.years.reversed()) { item in
                if let value = metric.value(in: item) {
                    LineMark(x: .value("年份", item.year), y: .value(metric.title, value))
                        .foregroundStyle(metric.color)
                        .interpolationMethod(.monotone)
                    AreaMark(x: .value("年份", item.year), y: .value(metric.title, value))
                        .foregroundStyle(metric.color.opacity(0.12))
                        .interpolationMethod(.monotone)
                }
            }
            .chartXScale(domain: 1999...(Calendar.current.component(.year, from: Date()) + 1))
            .chartXAxis {
                AxisMarks(values: Array(stride(from: 2000, through: Calendar.current.component(.year, from: Date()), by: 5))) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisValueLabel {
                        if let year = value.as(Int.self) { Text(String(year)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisValueLabel { if let number = value.as(Double.self) { Text(format(number)) } }
                }
            }
            .frame(height: 220)
        }
        .padding(16)
        .background(InvestmentDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
    }

    private var annualTable: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                HStack {
                    Text("年份").frame(width: 52, alignment: .leading)
                    Text("通胀").frame(width: 58, alignment: .trailing)
                    Text("贷款").frame(width: 58, alignment: .trailing)
                    Text("存款").frame(width: 58, alignment: .trailing)
                    Text("房贷LPR").frame(width: 72, alignment: .trailing)
                    Text("信贷/GDP").frame(width: 78, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                ForEach(store.years) { item in
                    Divider().padding(.leading, 14)
                    HStack {
                        Text(String(item.year)).font(.subheadline.weight(.semibold)).frame(width: 52, alignment: .leading)
                        valueCell(item.inflation, width: 58)
                        valueCell(item.lendingRate, width: 58)
                        valueCell(item.depositRate, width: 58)
                        valueCell(item.mortgageRate, width: 72)
                        valueCell(item.privateCredit, width: 78)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
            }
            .frame(width: 460)
            .background(InvestmentDesign.surface)
            .clipShape(RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
        }
        .scrollIndicators(.hidden)
    }

    private var sourceFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("数据来源：世界银行、中国人民银行", systemImage: "checkmark.shield.fill")
                .font(.footnote.weight(.semibold))
            Text("通胀、贷款、存款与信贷规模来自世界银行；房贷利率采用中国人民银行每年最后一次公布的5年期以上LPR，当年显示最新值。它是房贷定价基准，并非每位借款人的实际执行利率。空白表示该年度源数据未公布。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func valueCell(_ value: Double?, width: CGFloat) -> some View {
        Text(value.map { format($0) } ?? "—")
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(value == nil ? Color.secondary : Color.primary)
            .frame(width: width, alignment: .trailing)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(abs(value) >= 100 ? 1 : 2)))
    }

    private func icon(for metric: ChinaMacroMetric) -> String {
        switch metric {
        case .inflation: "cart"
        case .lendingRate: "percent"
        case .depositRate: "banknote"
        case .mortgageRate: "house"
        case .privateCredit: "building.columns"
        }
    }
}

#Preview { ChinaMacroView() }
