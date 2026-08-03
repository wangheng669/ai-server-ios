import Charts
import Observation
import SwiftUI

struct ChinaMacroYear: Identifiable, Equatable {
    let year: Int
    var inflation: Double?
    var lendingRate: Double?
    var privateCredit: Double?

    var id: Int { year }
}

enum ChinaMacroMetric: String, CaseIterable, Identifiable {
    case inflation
    case lendingRate
    case privateCredit

    var id: Self { self }

    var title: String {
        switch self {
        case .inflation: "通胀"
        case .lendingRate: "贷款利率"
        case .privateCredit: "借贷水平"
        }
    }

    var longTitle: String {
        switch self {
        case .inflation: "居民消费价格年涨幅"
        case .lendingRate: "银行贷款利率"
        case .privateCredit: "私人部门银行信贷 / GDP"
        }
    }

    var color: Color {
        switch self {
        case .inflation: .orange
        case .lendingRate: InvestmentDesign.accent
        case .privateCredit: .purple
        }
    }

    func value(in year: ChinaMacroYear) -> Double? {
        switch self {
        case .inflation: year.inflation
        case .lendingRate: year.lendingRate
        case .privateCredit: year.privateCredit
        }
    }
}

struct WorldBankIndicatorPoint: Decodable, Equatable {
    let year: Int
    let value: Double?

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

struct ChinaMacroService {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.worldbank.org/v2/country/CHN/indicator/")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func history() async throws -> [ChinaMacroYear] {
        async let inflation = seriesOrEmpty("FP.CPI.TOTL.ZG")
        async let lendingRate = seriesOrEmpty("FR.INR.LEND")
        async let privateCredit = seriesOrEmpty("FD.AST.PRVT.GD.ZS")
        let merged = await Self.merge(
            inflation: inflation,
            lendingRate: lendingRate,
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

    static func merge(
        inflation: [WorldBankIndicatorPoint],
        lendingRate: [WorldBankIndicatorPoint],
        privateCredit: [WorldBankIndicatorPoint]
    ) -> [ChinaMacroYear] {
        var years: [Int: ChinaMacroYear] = [:]
        func insert(_ points: [WorldBankIndicatorPoint], keyPath: WritableKeyPath<ChinaMacroYear, Double?>) {
            for point in points where point.year >= 2000 && point.year <= Calendar.current.component(.year, from: Date()) {
                var item = years[point.year] ?? ChinaMacroYear(year: point.year, inflation: nil, lendingRate: nil, privateCredit: nil)
                item[keyPath: keyPath] = point.value
                years[point.year] = item
            }
        }
        insert(inflation, keyPath: \.inflation)
        insert(lendingRate, keyPath: \.lendingRate)
        insert(privateCredit, keyPath: \.privateCredit)
        return years.values
            .filter { $0.inflation != nil || $0.lendingRate != nil || $0.privateCredit != nil }
            .sorted { $0.year > $1.year }
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
            Text("把物价、银行贷款利率与信贷规模放在同一条年度时间线上，观察资金价格与经济杠杆的长期变化。")
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
        VStack(spacing: 0) {
            HStack {
                Text("年份").frame(maxWidth: .infinity, alignment: .leading)
                Text("通胀").frame(width: 62, alignment: .trailing)
                Text("利率").frame(width: 62, alignment: .trailing)
                Text("信贷/GDP").frame(width: 78, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            ForEach(store.years) { item in
                Divider().padding(.leading, 14)
                HStack {
                    Text(String(item.year)).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                    valueCell(item.inflation, width: 62)
                    valueCell(item.lendingRate, width: 62)
                    valueCell(item.privateCredit, width: 78)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
        }
        .background(InvestmentDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
    }

    private var sourceFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("数据来源：世界银行开放数据", systemImage: "checkmark.shield.fill")
                .font(.footnote.weight(.semibold))
            Text("通胀为 CPI 年涨幅；利率为银行贷款利率；借贷水平为私人部门银行信贷占 GDP 比重。不同指标发布时间不同，空白表示该年度源数据未公布。")
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
        case .privateCredit: "building.columns"
        }
    }
}

#Preview { ChinaMacroView() }
