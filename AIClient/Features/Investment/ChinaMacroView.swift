import Charts
import Observation
import SwiftUI

private func chinaMacroTimestamp(_ date: Date?, includeYear: Bool = true) -> String {
    guard let date else { return "尚未完成刷新" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = includeYear ? "yyyy-MM-dd HH:mm" : "MM-dd HH:mm"
    return formatter.string(from: date)
}

struct ChinaMacroYear: Identifiable, Equatable {
    let year: Int
    var gdpGrowth: Double?
    var unemployment: Double?
    var inflation: Double?
    var lendingRate: Double?
    var depositRate: Double?
    var mortgageRate: Double?
    var householdLeverage: Double?
    var debtServiceRatio: Double?
    var incomeSurplusRate: Double?
    var consumerConfidence: Double?
    var electricityTotalGrowth: Double?
    var electricityPrimaryGrowth: Double?
    var electricitySecondaryGrowth: Double?
    var electricityTertiaryGrowth: Double?
    var electricityResidentialGrowth: Double?
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
    case householdLeverage
    case debtServiceRatio
    case incomeSurplusRate
    case consumerConfidence
    case electricityTotalGrowth
    case electricityPrimaryGrowth
    case electricitySecondaryGrowth
    case electricityTertiaryGrowth
    case electricityResidentialGrowth
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
        case .householdLeverage: "居民杠杆率"
        case .debtServiceRatio: "偿债率"
        case .incomeSurplusRate: "收支结余率"
        case .consumerConfidence: "消费信心"
        case .electricityTotalGrowth: "全社会"
        case .electricityPrimaryGrowth: "第一产业"
        case .electricitySecondaryGrowth: "第二产业"
        case .electricityTertiaryGrowth: "第三产业"
        case .electricityResidentialGrowth: "居民生活"
        case .privateCredit: "私人部门信贷"
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
        case .householdLeverage: "居民部门总信贷 / GDP"
        case .debtServiceRatio: "私人非金融部门偿债率"
        case .incomeSurplusRate: "居民收支结余率（估算）"
        case .consumerConfidence: "消费者信心指数"
        case .electricityTotalGrowth: "全社会用电量同比增速"
        case .electricityPrimaryGrowth: "第一产业用电量同比增速"
        case .electricitySecondaryGrowth: "第二产业用电量同比增速"
        case .electricityTertiaryGrowth: "第三产业用电量同比增速"
        case .electricityResidentialGrowth: "城乡居民生活用电量同比增速"
        case .privateCredit: "私人部门银行信贷 / GDP"
        }
    }

    var shortDescription: String {
        switch self {
        case .gdpGrowth: "衡量经济总量相较上一年的实际增长速度"
        case .unemployment: "失业人口占全部劳动力的比例"
        case .inflation: "居民日常消费的一篮子商品与服务价格变化"
        case .lendingRate: "银行向优质客户发放贷款时的参考利率"
        case .depositRate: "居民将资金存入银行可获得的年化回报"
        case .mortgageRate: "5年期以上LPR，常用于住房贷款定价参考"
        case .householdLeverage: "居民及服务居民的非营利机构总债务占GDP比例，反映家庭部门杠杆水平"
        case .debtServiceRatio: "私人非金融部门用于偿还本金和利息的收入占比；包含居民与非金融企业，不等同于居民房贷还款压力"
        case .incomeSurplusRate: "按（人均可支配收入－人均消费支出）÷人均可支配收入计算，是居民储蓄能力的近似观察值"
        case .consumerConfidence: "反映消费者对经济、收入和消费前景的主观判断；年度图取当年最后一个可用月"
        case .electricityTotalGrowth: "全社会用电量变化，是观察实体经济与生活需求活跃度的高频指标"
        case .electricityPrimaryGrowth: "农业、林业、牧业和渔业等第一产业用电变化"
        case .electricitySecondaryGrowth: "工业与建筑业等第二产业用电变化，更直接反映生产景气"
        case .electricityTertiaryGrowth: "服务业用电变化，辅助观察服务消费与数字经济活力"
        case .electricityResidentialGrowth: "城乡居民日常生活用电变化，辅助观察生活需求"
        case .privateCredit: "银行对私人部门信贷占GDP的比例，反映杠杆水平"
        }
    }

    var sourceName: String {
        switch self {
        case .mortgageRate: "中国人民银行"
        case .householdLeverage: "国际清算银行"
        case .debtServiceRatio: "国际清算银行"
        case .incomeSurplusRate: "国家统计局（估算）"
        case .consumerConfidence: "OECD"
        case .electricityTotalGrowth, .electricityPrimaryGrowth, .electricitySecondaryGrowth,
             .electricityTertiaryGrowth, .electricityResidentialGrowth: "国家能源局"
        default: "世界银行"
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
        case .householdLeverage: .indigo
        case .debtServiceRatio: .red
        case .incomeSurplusRate: .green
        case .consumerConfidence: .teal
        case .electricityTotalGrowth: .yellow
        case .electricityPrimaryGrowth: .green
        case .electricitySecondaryGrowth: .orange
        case .electricityTertiaryGrowth: .blue
        case .electricityResidentialGrowth: .pink
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
        case .householdLeverage: year.householdLeverage
        case .debtServiceRatio: year.debtServiceRatio
        case .incomeSurplusRate: year.incomeSurplusRate
        case .consumerConfidence: year.consumerConfidence
        case .electricityTotalGrowth: year.electricityTotalGrowth
        case .electricityPrimaryGrowth: year.electricityPrimaryGrowth
        case .electricitySecondaryGrowth: year.electricitySecondaryGrowth
        case .electricityTertiaryGrowth: year.electricityTertiaryGrowth
        case .electricityResidentialGrowth: year.electricityResidentialGrowth
        case .privateCredit: year.privateCredit
        }
    }

    var unitSuffix: String { self == .consumerConfidence ? "点" : "%" }
}

private struct ChinaMacroAPIEnvelope: Decodable { let data: ChinaMacroAPISnapshot }
private struct ChinaMacroAPISnapshot: Decodable {
    let observations: [ChinaMacroAPIObservation]
    let generatedAt: String

    enum CodingKeys: String, CodingKey {
        case observations
        case generatedAt = "generated_at"
    }
}
struct ChinaMacroAPIObservation: Decodable {
    let metricKey: String
    let period: String
    let value: Double

    enum CodingKeys: String, CodingKey {
        case metricKey = "metric_key"
        case period, value
    }
}

struct ChinaMacroService {
    private let session: URLSession
    private let appBaseURL: URL

    init(session: URLSession = .shared, appBaseURL: URL = ServerConfiguration.currentURL) {
        self.session = session
        self.appBaseURL = appBaseURL
    }

    func history() async throws -> (years: [ChinaMacroYear], generatedAt: Date) {
        let url = appBaseURL.appending(path: "api/ios/v1/economy/china-macro")
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let snapshot = try JSONDecoder().decode(ChinaMacroAPIEnvelope.self, from: data).data
        let years = Self.merge(snapshot.observations)
        guard !years.isEmpty, let generatedAt = Self.parseServerTimestamp(snapshot.generatedAt) else {
            throw URLError(.cannotParseResponse)
        }
        return (years, generatedAt)
    }

    static func parseServerTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    static func merge(_ observations: [ChinaMacroAPIObservation]) -> [ChinaMacroYear] {
        var years: [Int: ChinaMacroYear] = [:]
        for observation in observations {
            guard let year = Int(observation.period.prefix(4)), year >= 2000 else { continue }
            var item = years[year] ?? ChinaMacroYear(
                    year: year,
                    gdpGrowth: nil,
                    unemployment: nil,
                    inflation: nil,
                    lendingRate: nil,
                    depositRate: nil,
                    mortgageRate: nil,
                    householdLeverage: nil,
                    debtServiceRatio: nil,
                    incomeSurplusRate: nil,
                    consumerConfidence: nil,
                    electricityTotalGrowth: nil,
                    electricityPrimaryGrowth: nil,
                    electricitySecondaryGrowth: nil,
                    electricityTertiaryGrowth: nil,
                    electricityResidentialGrowth: nil,
                    privateCredit: nil
            )
            switch observation.metricKey {
            case "gdp_growth": item.gdpGrowth = observation.value
            case "unemployment": item.unemployment = observation.value
            case "inflation": item.inflation = observation.value
            case "lending_rate": item.lendingRate = observation.value
            case "deposit_rate": item.depositRate = observation.value
            case "mortgage_rate": item.mortgageRate = observation.value
            case "household_leverage": item.householdLeverage = observation.value
            case "debt_service_ratio": item.debtServiceRatio = observation.value
            case "income_surplus_rate": item.incomeSurplusRate = observation.value
            case "consumer_confidence": item.consumerConfidence = observation.value
            case "electricity_total_growth": item.electricityTotalGrowth = observation.value
            case "electricity_primary_growth": item.electricityPrimaryGrowth = observation.value
            case "electricity_secondary_growth": item.electricitySecondaryGrowth = observation.value
            case "electricity_tertiary_growth": item.electricityTertiaryGrowth = observation.value
            case "electricity_residential_growth": item.electricityResidentialGrowth = observation.value
            case "private_credit": item.privateCredit = observation.value
            default: continue
            }
            years[year] = item
        }
        return years.values
            .filter {
                $0.gdpGrowth != nil || $0.unemployment != nil || $0.inflation != nil ||
                    $0.lendingRate != nil || $0.depositRate != nil ||
                    $0.mortgageRate != nil || $0.householdLeverage != nil || $0.debtServiceRatio != nil ||
                    $0.incomeSurplusRate != nil || $0.consumerConfidence != nil || $0.electricityTotalGrowth != nil ||
                    $0.electricityPrimaryGrowth != nil || $0.electricitySecondaryGrowth != nil ||
                    $0.electricityTertiaryGrowth != nil || $0.electricityResidentialGrowth != nil || $0.privateCredit != nil
            }
            .sorted { $0.year > $1.year }
    }
}

@MainActor
@Observable
final class ChinaMacroStore {
    var years: [ChinaMacroYear] = []
    var isLoading = false
    var loadError = false
    var lastUpdatedAt: Date?
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
            let snapshot = try await service.history()
            years = snapshot.years
            loadError = years.isEmpty
            lastUpdatedAt = snapshot.generatedAt
        } catch is CancellationError {
            return
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
    case energy = "用电"

    var id: Self { self }

    var metrics: [ChinaMacroMetric] {
        switch self {
        case .overview: []
        case .growth: [.gdpGrowth, .unemployment]
        case .prices: [.inflation, .depositRate]
        case .rates: [.mortgageRate, .lendingRate, .depositRate]
        case .credit: [.householdLeverage, .debtServiceRatio, .incomeSurplusRate, .consumerConfidence, .privateCredit]
        case .energy: [.electricityTotalGrowth, .electricitySecondaryGrowth, .electricityTertiaryGrowth, .electricityResidentialGrowth, .electricityPrimaryGrowth]
        }
    }

    var title: String {
        switch self {
        case .overview: "中国经济脉搏"
        case .growth: "增长动能"
        case .prices: "价格与居民资金"
        case .rates: "利率环境"
        case .credit: "信用与杠杆"
        case .energy: "用电与实体活力"
        }
    }

}

private struct ChinaMacroPresentation: Identifiable {
    let metric: ChinaMacroMetric
    let year: Int?
    var id: String { "\(metric.rawValue)-\(year ?? -1)" }
}

struct ChinaMacroView: View {
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @State private var store = ChinaMacroStore()
    @State private var section = ChinaMacroSection.overview
    @State private var metric = ChinaMacroMetric.gdpGrowth
    @State private var selectedYear: Int?
    @State private var presentation: ChinaMacroPresentation?

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
                    snapshotBar
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
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            if store.years.isEmpty { await store.load() }
            if ProcessInfo.processInfo.arguments.contains("--china-macro-household-preview") {
                presentation = ChinaMacroPresentation(metric: .householdLeverage, year: nil)
            } else if ProcessInfo.processInfo.arguments.contains("--china-macro-confidence-preview") {
                section = .credit
                metric = .consumerConfidence
                presentation = ChinaMacroPresentation(metric: .consumerConfidence, year: nil)
            } else if ProcessInfo.processInfo.arguments.contains("--china-macro-energy-preview") {
                section = .energy
                metric = .electricityTotalGrowth
            } else if ProcessInfo.processInfo.arguments.contains("--china-macro-sheet-preview") {
                presentation = ChinaMacroPresentation(metric: .gdpGrowth, year: nil)
            }
        }
        .onChange(of: section) { _, newSection in
            if let first = newSection.metrics.first { metric = first }
            selectedYear = nil
        }
        .onChange(of: metric) { _, _ in selectedYear = nil }
        .sheet(item: $presentation) { item in
            ChinaMacroMetricSheet(
                metric: item.metric,
                years: store.years,
                initialYear: item.year,
                updatedAt: store.lastUpdatedAt
            )
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.hidden)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label(
                latestYear.map { "最新数据 \(String($0)) 年" } ?? "正在更新数据",
                systemImage: "calendar"
            )
            if let updatedAt = store.lastUpdatedAt {
                Label(chinaMacroTimestamp(updatedAt, includeYear: false), systemImage: "arrow.clockwise")
            }
            if store.isLoading && !store.years.isEmpty {
                ProgressView().controlSize(.mini)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
            ForEach(ChinaMacroSection.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { section = item }
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline.weight(section == item ? .semibold : .regular))
                        .foregroundStyle(section == item ? InvestmentDesign.accent : .secondary)
                        .frame(minWidth: 58)
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
    }

    private var snapshotBar: some View {
        HStack(spacing: 8) {
            snapshotItem(
                title: "增长",
                value: latest(.gdpGrowth).flatMap { ChinaMacroMetric.gdpGrowth.value(in: $0) },
                positiveText: "动能较强",
                neutralText: "温和增长",
                lowText: "动能偏弱",
                tint: InvestmentDesign.accent
            )
            snapshotItem(
                title: "物价",
                value: latest(.inflation).flatMap { ChinaMacroMetric.inflation.value(in: $0) },
                positiveText: "价格偏热",
                neutralText: "价格温和",
                lowText: "通胀低位",
                tint: .orange
            )
            snapshotItem(
                title: "利率",
                value: latest(.mortgageRate).flatMap { ChinaMacroMetric.mortgageRate.value(in: $0) },
                positiveText: "融资偏贵",
                neutralText: "利率适中",
                lowText: "利率较低",
                tint: .purple
            )
        }
    }

    private func snapshotItem(
        title: String,
        value: Double?,
        positiveText: String,
        neutralText: String,
        lowText: String,
        tint: Color
    ) -> some View {
        let status: String = if let value {
            value >= 5 ? positiveText : value >= 2 ? neutralText : lowText
        } else {
            "等待数据"
        }
        return VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(status)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(InvestmentDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                metrics: [.mortgageRate, .lendingRate, .depositRate],
                insight: "5年期LPR是房贷定价基准，实际利率还会加减点"
            )
            storyCard(
                section: .credit,
                icon: "figure.2.and.child.holdinghands",
                tint: .indigo,
                metrics: [.debtServiceRatio, .incomeSurplusRate, .consumerConfidence],
                insight: "把还款负担、居民结余能力与消费意愿放在一起观察"
            )
            storyCard(
                section: .energy,
                icon: "bolt.fill",
                tint: .yellow,
                metrics: [.electricityTotalGrowth, .electricitySecondaryGrowth, .electricityTertiaryGrowth],
                insight: "全社会用电观察总活力，第二产业更贴近工业生产，第三产业反映服务业需求"
            )
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
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { section = target }
                } label: {
                    HStack {
                    Label(target.title, systemImage: icon)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
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
    }

    private func metricSummary(_ item: ChinaMacroMetric) -> some View {
        let latest = latest(item)
        return Button {
            presentation = ChinaMacroPresentation(metric: item, year: latest?.year)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(latest.flatMap { item.value(in: $0) }.map { "\(format($0))\(item.unitSuffix)" } ?? "—")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(item.color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(latest.map { "\(String($0.year)) 年" } ?? "暂无数据")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Label("点按查看", systemImage: "rectangle.portrait.and.arrow.forward")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title)，打开详细数据")
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
        ScrollView(.horizontal, showsIndicators: false) {
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
                    .frame(minWidth: 88)
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
    }

    private var trendCard: some View {
        let displayed = selectedYear.flatMap { selected in
            store.years.first { $0.year == selected && metric.value(in: $0) != nil }
        } ?? latest(metric)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.longTitle).font(.headline)
                    Text("年度值 · 单位 \(metric.unitSuffix)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let displayed, let value = metric.value(in: displayed) {
                    Button {
                        presentation = ChinaMacroPresentation(metric: metric, year: displayed.year)
                    } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(format(value))\(metric.unitSuffix)")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(metric.color)
                        Text("\(String(displayed.year)) 年 · 查看详情")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    }
                    .buttonStyle(.plain)
                }
            }
            InteractiveMacroChart(
                metric: metric,
                years: store.years,
                selectedYear: $selectedYear,
                height: 235
            )
            Label("在曲线上左右滑动，数据会自动吸附到最近年份", systemImage: "hand.draw")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(InvestmentDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
    }

    private var recentValues: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("历史数据").font(.headline)
                    Text(historyRangeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("展示最近 \(min(metricYears.count, 12)) 年")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            ForEach(Array(metricYears.prefix(12))) { item in
                Divider().padding(.leading, 16)
                Button {
                    presentation = ChinaMacroPresentation(metric: metric, year: item.year)
                } label: {
                    HStack {
                    Text("\(String(item.year)) 年")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(metric.value(in: item).map { "\(format($0))\(metric.unitSuffix)" } ?? "—")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(metric.color)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            if metricYears.count > 12 {
                Divider().padding(.leading, 16)
                Button {
                    presentation = ChinaMacroPresentation(metric: metric, year: nil)
                } label: {
                    Label("在弹窗中查看全部 \(metricYears.count) 个年份", systemImage: "calendar.badge.clock")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
        }
        .background(InvestmentDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
    }

    private var sourceFooter: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("数据来源与更新时间", systemImage: "checkmark.shield.fill")
                .font(.footnote.weight(.semibold))
            Text("页面主体数据由后端定时采集并落库；世界银行 WDI：基础宏观指标；BIS：杠杆与偿债率；国家统计局：居民收支；OECD：消费信心；国家能源局：全社会及分产业用电；中国人民银行：LPR。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("各指标最新年份以数值旁标注为准；页面刷新于 \(updatedAtText)。LPR是房贷定价基准，并非个人实际执行利率。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var latestYear: Int? { store.years.first?.year }
    private var metricYears: [ChinaMacroYear] { store.years.filter { metric.value(in: $0) != nil } }
    private var historyRangeText: String {
        guard let newest = metricYears.first?.year, let oldest = metricYears.last?.year else { return "暂无年份" }
        return "共 \(metricYears.count) 年 · \(String(oldest))—\(String(newest))"
    }
    private var updatedAtText: String {
        chinaMacroTimestamp(store.lastUpdatedAt)
    }
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
        case .householdLeverage: "figure.2.and.child.holdinghands"
        case .debtServiceRatio: "creditcard.trianglebadge.exclamationmark"
        case .incomeSurplusRate: "tray.and.arrow.down"
        case .consumerConfidence: "person.crop.circle.badge.questionmark"
        case .electricityTotalGrowth: "bolt.fill"
        case .electricityPrimaryGrowth: "leaf"
        case .electricitySecondaryGrowth: "gearshape.2"
        case .electricityTertiaryGrowth: "building.2"
        case .electricityResidentialGrowth: "house.and.flag"
        case .privateCredit: "building.columns"
        }
    }
}

private struct InteractiveMacroChart: View {
    let metric: ChinaMacroMetric
    let years: [ChinaMacroYear]
    @Binding var selectedYear: Int?
    let height: CGFloat

    private var points: [ChinaMacroYear] {
        years
            .filter { metric.value(in: $0) != nil }
            .sorted { $0.year < $1.year }
    }

    private var selectedPoint: ChinaMacroYear? {
        guard let selectedYear else { return nil }
        return points.min { abs($0.year - selectedYear) < abs($1.year - selectedYear) }
    }

    var body: some View {
        Chart {
            ForEach(points) { item in
                if let value = metric.value(in: item) {
                    AreaMark(
                        x: .value("年份", item.year),
                        y: .value(metric.title, value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [metric.color.opacity(0.18), metric.color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(metric == .mortgageRate ? .stepEnd : .monotone)

                    LineMark(
                        x: .value("年份", item.year),
                        y: .value(metric.title, value)
                    )
                    .foregroundStyle(metric.color)
                    .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(metric == .mortgageRate ? .stepEnd : .monotone)
                }
            }

            if let selectedPoint, let value = metric.value(in: selectedPoint) {
                RuleMark(x: .value("选中年份", selectedPoint.year))
                    .foregroundStyle(metric.color.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                PointMark(
                    x: .value("选中年份", selectedPoint.year),
                    y: .value("选中数值", value)
                )
                .foregroundStyle(metric.color)
                .symbolSize(70)
            }
        }
        .chartXScale(domain: (points.first?.year ?? 2000)...(points.last?.year ?? 2026))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) {
                AxisGridLine().foregroundStyle(.secondary.opacity(0.10))
                AxisTick().foregroundStyle(.secondary.opacity(0.25))
                AxisValueLabel().font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) {
                AxisGridLine().foregroundStyle(.secondary.opacity(0.10))
                AxisValueLabel().font(.caption2)
            }
        }
        .chartXSelection(value: $selectedYear)
        .chartPlotStyle { plot in
            plot
                .background(metric.color.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(height: height)
        .onChange(of: selectedYear) { _, candidate in
            guard let candidate,
                  let nearest = points.min(by: { abs($0.year - candidate) < abs($1.year - candidate) }),
                  nearest.year != candidate else { return }
            selectedYear = nearest.year
        }
        .sensoryFeedback(.selection, trigger: selectedYear)
        .accessibilityLabel("\(metric.title)历史趋势图，可左右滑动选择年份")
    }
}

private struct ChinaMacroMetricSheet: View {
    @Environment(\.dismiss) private var dismiss
    let metric: ChinaMacroMetric
    let years: [ChinaMacroYear]
    let initialYear: Int?
    let updatedAt: Date?
    @State private var selectedYear: Int?

    private var points: [ChinaMacroYear] {
        years
            .filter { metric.value(in: $0) != nil }
            .sorted { $0.year < $1.year }
    }

    private var selectedPoint: ChinaMacroYear? {
        guard let selectedYear else { return points.last }
        return points.min { abs($0.year - selectedYear) < abs($1.year - selectedYear) }
    }

    private var selectedIndex: Int? {
        guard let selectedPoint else { return nil }
        return points.firstIndex(where: { $0.year == selectedPoint.year })
    }

    private var change: Double? {
        guard let index = selectedIndex, index > points.startIndex,
              let current = metric.value(in: points[index]),
              let previous = metric.value(in: points[index - 1]) else { return nil }
        return current - previous
    }

    private var average: Double? {
        let values = points.compactMap { metric.value(in: $0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var minimum: Double? { points.compactMap { metric.value(in: $0) }.min() }
    private var maximum: Double? { points.compactMap { metric.value(in: $0) }.max() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    metricIntro
                    selectedValueCard
                    chartCard
                    statistics
                    historyList
                    sourceNote
                }
                .padding(16)
            }
            .background(InvestmentDesign.canvas)
            .navigationTitle(metric.title)
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottomTrailing) {
                DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭宏观指标详情")
                    .padding(16)
            }
        }
        .onAppear { selectedYear = initialYear ?? points.last?.year }
    }

    private var metricIntro: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(metric.longTitle)
                .font(.title3.weight(.bold))
            Text(metric.shortDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label(metric.sourceName, systemImage: "building.columns")
                Label(
                    points.last.map { "最新 \(String($0.year)) 年" } ?? "暂无年份",
                    systemImage: "calendar"
                )
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            Label("刷新于 \(updatedAtText)", systemImage: "arrow.clockwise")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var selectedValueCard: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedPoint.map { "\(String($0.year)) 年" } ?? "暂无数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(selectedPoint.flatMap { metric.value(in: $0) }.map { "\(format($0))\(metric.unitSuffix)" } ?? "—")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(metric.color)
            }
            Spacer()
            if let change {
                let isFlat = abs(change) < 0.005
                Label(
                    isFlat ? "与上年基本持平" : "较上年 \(change > 0 ? "+" : "")\(format(change)) \(metric == .consumerConfidence ? "点" : "个百分点")",
                    systemImage: isFlat ? "arrow.right" : change > 0 ? "arrow.up.right" : "arrow.down.right"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(isFlat ? Color.secondary : change > 0 ? Color.red : Color.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background((isFlat ? Color.secondary : change > 0 ? Color.red : Color.green).opacity(0.08))
                .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(InvestmentDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("历史趋势").font(.headline)
                Spacer()
                Label("滑动查看", systemImage: "hand.draw")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            InteractiveMacroChart(
                metric: metric,
                years: years,
                selectedYear: $selectedYear,
                height: 260
            )
        }
        .padding(16)
        .background(InvestmentDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
    }

    private var statistics: some View {
        HStack(spacing: 8) {
            statisticCell("区间均值", value: average)
            statisticCell("历史低点", value: minimum)
            statisticCell("历史高点", value: maximum)
        }
    }

    private func statisticCell(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value.map { "\(format($0))\(metric.unitSuffix)" } ?? "—")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(metric.color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(InvestmentDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("完整年度明细").font(.headline)
                    Text("共 \(points.count) 年 · \(yearRangeText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "calendar")
                    .foregroundStyle(metric.color)
            }
            .padding(16)
            ForEach(points.reversed()) { item in
                Divider().padding(.leading, 16)
                Button { selectedYear = item.year } label: {
                    HStack {
                        Text("\(String(item.year)) 年")
                        Spacer()
                        Text(metric.value(in: item).map { "\(format($0))\(metric.unitSuffix)" } ?? "—")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(metric.color)
                        Image(systemName: selectedPoint?.year == item.year ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedPoint?.year == item.year ? metric.color : Color.secondary.opacity(0.35))
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .background(InvestmentDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
    }

    private var sourceNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("数据来源：\(sourceDetail)", systemImage: "checkmark.shield.fill")
                .font(.footnote.weight(.semibold))
            Text("指标数据覆盖 \(yearRangeText)，最新数据年份为 \(points.last.map { String($0.year) } ?? "—") 年。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("页面本次刷新：\(updatedAtText)。这是 App 获取数据的时间，不代表官方指标发布日期。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var yearRangeText: String {
        "\(points.first.map { String($0.year) } ?? "—")—\(points.last.map { String($0.year) } ?? "—") 年"
    }

    private var sourceDetail: String {
        switch metric {
        case .mortgageRate: "中国人民银行 · LPR公告"
        case .householdLeverage: "国际清算银行 · Credit to the non-financial sector"
        case .debtServiceRatio: "国际清算银行 · Debt service ratios"
        case .incomeSurplusRate: "国家统计局 · 全国居民收入和消费支出（App计算）"
        case .consumerConfidence: "OECD · Consumer opinion surveys（中国）"
        case .electricityTotalGrowth, .electricityPrimaryGrowth, .electricitySecondaryGrowth,
             .electricityTertiaryGrowth, .electricityResidentialGrowth: "国家能源局 · 全社会用电量"
        default: "世界银行 · World Development Indicators"
        }
    }

    private var updatedAtText: String {
        chinaMacroTimestamp(updatedAt)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(abs(value) >= 100 ? 1 : 2)))
    }
}

#Preview { ChinaMacroView() }
