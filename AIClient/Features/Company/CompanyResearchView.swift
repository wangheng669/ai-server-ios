import Charts
import SwiftUI
import UIKit

struct CompanyResearchResponse: Decodable {
    let data: CompanyResearchPayload
}

struct CompanyResearchPayload: Decodable {
    let companies: [CompanyResearchProfile]
    let updatedAt: Date?
}

struct CompanyResearchProfile: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let shortName: String
    let logoUrl: URL
    let ticker: String
    let exchange: String
    let industry: String
    let location: String
    let tagline: String
    let thesis: String
    let metrics: [CompanyResearchMetric]
    let highlights: [String]
    let moats: [String]
    let risks: [String]
    let questions: [String]
    let sources: [CompanyResearchSource]
    let buyback: CompanyResearchBuyback
    let nextReport: CompanyResearchReport
    let consensus: CompanyResearchConsensus?
    let financials: CompanyResearchFinancials
    let framework: CompanyResearchFramework?
    let business: [CompanyResearchBusinessStep]?
    let indicators: [CompanyResearchIndicator]?
    let updates: [CompanyResearchUpdate]?
    let market: CompanyResearchMarket?
    let updatedAt: Date
}

struct CompanyResearchFramework: Decodable, Hashable {
    let businessSummary: String
    let revenueModel: String
    let customers: String
    let pricingPower: String
    let financialQuality: String
    let competitivePosition: String
    let capitalAllocation: String
    let falsificationConditions: [String]
    let currentChanges: [CompanyResearchChange]
}

struct CompanyResearchChange: Decodable, Hashable {
    let label: String
    let detail: String
}

struct CompanyResearchBusinessStep: Decodable, Hashable, Identifiable {
    let key: String
    let title: String
    let detail: String
    var id: String { key }
}

struct CompanyResearchIndicator: Decodable, Hashable, Identifiable {
    let key: String
    let label: String
    let value: String
    let status: String
    let trend: String
    let note: String
    let asOfDate: String
    let source: CompanyResearchSource?
    var id: String { key }
}

struct CompanyResearchUpdate: Decodable, Hashable, Identifiable {
    let key: String
    let occurredOn: String
    let category: String
    let title: String
    let status: String
    let summary: String
    let impact: String
    let source: CompanyResearchSource?
    var id: String { key }
}

struct CompanyResearchFinancials: Decodable, Hashable {
    let unit: String
    let years: [CompanyResearchFinancialYear]
    let quarters: [CompanyResearchFinancialPeriod]?
    let forecasts: [CompanyResearchFinancialForecast]?
    let source: CompanyResearchSource
}

struct CompanyResearchFinancialForecast: Decodable, Hashable, Identifiable {
    let period: String
    let range: String
    let revenue: Double?
    let netProfit: Double?
    let note: String?

    var id: String { "\(range)-\(period)" }
}

struct CompanyResearchFinancialPeriod: Decodable, Hashable, Identifiable {
    let period: String
    let revenue: Double
    let netProfit: Double
    let note: String?

    var id: String { period }
}

struct CompanyResearchFinancialYear: Decodable, Hashable, Identifiable {
    let year: String
    let revenue: Double
    let netProfit: Double
    let roe: Double

    var id: String { year }
}

struct CompanyResearchMarket: Decodable, Hashable {
    let symbol: String
    let price: Double?
    let changePercent: String
    let marketCap: Double?
    let pe: Double?
    let currency: String
    let timestamp: Int64
    let status: String
}

struct CompanyResearchMetric: Decodable, Hashable {
    let label: String
    let value: String
    let note: String
}

struct CompanyResearchSource: Decodable, Hashable {
    let title: String
    let url: URL
}

struct CompanyResearchBuyback: Decodable, Hashable {
    let status: String
    let asOfDate: String
    let shares: String
    let amount: String
    let percentage: String
    let priceRange: String
    let purpose: String
    let progressNote: String
    let source: CompanyResearchSource
}

struct CompanyResearchReport: Decodable, Hashable {
    let reportType: String
    let expectedDate: String
    let dateStatus: String
    let note: String
    let source: CompanyResearchSource
}

struct CompanyResearchConsensus: Decodable, Hashable {
    let period: String
    let asOfDate: String
    let status: String
    let metrics: [CompanyResearchConsensusMetric]
    let note: String
    let source: CompanyResearchSource
}

struct CompanyResearchConsensusMetric: Decodable, Hashable {
    let label: String
    let value: String
    let note: String
}

struct CompanyResearchService {
    var baseURL: URL = ServerConfiguration.currentURL
    var session: URLSession = .shared

    func fetch() async throws -> CompanyResearchPayload {
        let url = baseURL.appending(path: "api/ios/v1/market/company-research")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CompanyResearchResponse.self, from: data).data
    }
}

@MainActor
final class CompanyResearchStore: ObservableObject {
    @Published private(set) var companies: [CompanyResearchProfile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private let service: CompanyResearchService

    init(service: CompanyResearchService = CompanyResearchService()) {
        self.service = service
    }

    func load(force: Bool = false) async {
        guard !isLoading, force || companies.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            companies = try await service.fetch().companies
        } catch {
            errorMessage = "公司研究暂时无法载入"
        }
    }
}

@MainActor
struct CompanyResearchView: View {
    private enum FinancialRange: String, CaseIterable {
        case quarterly = "季度"
        case annual = "年度"
    }

    private enum Section: String, CaseIterable {
        case overview = "快照"
        case business = "经营"
        case financial = "财务"
        case valuation = "估值"
        case research = "事件"
    }

    @StateObject private var store: CompanyResearchStore
    @State private var selectedSection: Section = .overview
    @State private var financialRange: FinancialRange = .quarterly

    init() {
        _store = StateObject(wrappedValue: CompanyResearchStore())
    }

    init(store: CompanyResearchStore) {
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.companies.isEmpty {
                    companyLoadingState
                } else if !store.companies.isEmpty {
                    companyHub
                } else if let errorMessage = store.errorMessage {
                    ContentUnavailableView(errorMessage, systemImage: "building.2.crop.circle", description: Text("请稍后重新进入公司页"))
                } else {
                    ContentUnavailableView("暂无公司", systemImage: "building.2", description: Text("公司档案将在服务端持续补充"))
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CompanyResearchProfile.self) { company in
                companyPage(company)
                    .navigationTitle(company.shortName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.visible, for: .navigationBar)
            }
        }
        .task { await store.load() }
    }

    private var companyHub: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("公司研究")
                        .font(.system(size: 28, weight: .bold))
                    Text("先比较，再深入理解一家公司")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 10)

                ForEach(store.companies) { company in
                    NavigationLink(value: company) {
                        companyHubCard(company)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { selectedSection = .overview })
                }
            }
            .padding(.horizontal, 11)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .background(CompanyScrollBounceConfigurator())
    }

    private func companyHubCard(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                companyLogo(company)
                VStack(alignment: .leading, spacing: 4) {
                    Text(company.shortName)
                        .font(.headline)
                    Text("\(company.ticker) · \(company.exchange)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(marketPrice(company.market))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(companyAccent(company))
                    Text(marketChange(company.market))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(marketChangeColor(company.market))
                }
            }

            Divider()

            HStack(spacing: 0) {
                hubMetric("总市值", marketCap(company.market?.marketCap))
                hubMetric("PE", formattedMultiple(company.market?.pe))
                hubMetric("ROE", latestROE(company))
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.045), lineWidth: 0.5)
        }
    }

    private func hubMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func companyPage(_ company: CompanyResearchProfile) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                hero(company)
                sectionTabs(company)
                selectedSectionContent(company)
            }
            .padding(.horizontal, 11)
            .padding(.top, 2)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .background(CompanyScrollBounceConfigurator())
    }

    private var companyLoadingState: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .frame(height: 150)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .frame(height: 44)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .frame(height: 280)
            Text("正在整理公司研究档案")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityLabel("正在整理公司研究档案")
    }

    private func hero(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                companyLogo(company)
                VStack(alignment: .leading, spacing: 5) {
                    Text(company.shortName)
                        .font(.system(size: 18, weight: .bold))
                    Text("\(company.ticker) · \(company.exchange)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\((store.companies.firstIndex(of: company) ?? 0) + 1)/\(store.companies.count)")
                    .font(.subheadline.monospacedDigit())
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)

            Divider()
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(marketPrice(company.market))
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(companyAccent(company))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(marketChange(company.market))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(marketChangeColor(company.market))
                        .lineLimit(1)
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
                dashboardMetric("总市值", marketCap(company.market?.marketCap))
                dashboardMetric("PE", formattedMultiple(company.market?.pe))
                dashboardMetric("ROE", latestROE(company))
            }
            .padding(.vertical, 5)
            .overlay(alignment: .bottom) { Divider() }
        }
        .padding(10)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.045), lineWidth: 0.5)
        }
        .padding(.top, 5)
        .padding(.bottom, 10)
    }

    private func pageIndicator(_ company: CompanyResearchProfile) -> some View {
        HStack(spacing: 5) {
            ForEach(store.companies) { item in
                Capsule()
                    .fill(item.id == company.id ? Color.white : Color.white.opacity(0.28))
                    .frame(width: item.id == company.id ? 18 : 5, height: 5)
                    .animation(.easeInOut(duration: 0.2), value: company.id)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("第 \((store.companies.firstIndex(of: company) ?? 0) + 1) 页，共 \(store.companies.count) 页")
    }

    private func sectionTabs(_ company: CompanyResearchProfile) -> some View {
        HStack(spacing: 0) {
            ForEach(Section.allCases, id: \.self) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedSection = section }
                } label: {
                    compactTab(section.rawValue, selected: selectedSection == section, color: companyAccent(company))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func compactTab(_ title: String, selected: Bool, color: Color) -> some View {
        Text(title)
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selected ? Color(uiColor: .systemBackground) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: selected ? color.opacity(0.09) : .clear, radius: 4, y: 2)
    }

    @ViewBuilder
    private func selectedSectionContent(_ company: CompanyResearchProfile) -> some View {
        switch selectedSection {
        case .overview:
            overviewSection(company)
        case .business:
            businessSection(company)
        case .financial:
            financialSection(company)
        case .valuation:
            valuationSection(company)
        case .research:
            researchTimelineSection(company)
        }
    }

    private func overviewSection(_ company: CompanyResearchProfile) -> some View {
        nativeOverview(company)
    }

    private func nativeOverview(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            nativeFinancialTrend(company)
            nativeOperatingSignals(company)
            nativeNextReport(company)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func nativeMetricStrip(_ company: CompanyResearchProfile) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                nativeMetricCard("最新价", marketPrice(company.market), note: marketChange(company.market), icon: "chart.line.uptrend.xyaxis", color: companyAccent(company))
                nativeMetricCard("总市值", marketCap(company.market?.marketCap), note: "当前市值", icon: "circle.grid.2x2", color: .indigo)
                nativeMetricCard("PE (TTM)", formattedMultiple(company.market?.pe), note: "滚动市盈率", icon: "percent", color: .blue)
                nativeMetricCard("ROE (TTM)", latestROE(company), note: company.financials.years.last?.year ?? "最新", icon: "gauge.with.dots.needle.50percent", color: .orange)
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    private func nativeMetricCard(_ label: String, _ value: String, note: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.1), in: Circle())
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Text(note).font(.caption2).foregroundStyle(note.hasPrefix("-") ? Color.green : color)
        }
        .padding(13)
        .frame(width: 136, height: 138, alignment: .topLeading)
        .background(Color(uiColor: .systemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 0.5)
        }
    }

    private func nativeFinancialTrend(_ company: CompanyResearchProfile) -> some View {
        let years = Array(company.financials.years.suffix(3))
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("财务趋势").font(.headline)
                    Text("营收与净利润 · \(company.financials.unit)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    nativeLegend("营收", color: companyAccent(company))
                    nativeLegend("净利润", color: .blue)
                }
            }

            Chart {
                ForEach(years) { item in
                    BarMark(x: .value("年度", item.year), y: .value("营收", item.revenue))
                        .position(by: .value("指标", "营收"))
                        .foregroundStyle(companyAccent(company).gradient)
                        .cornerRadius(4)
                    BarMark(x: .value("年度", item.year), y: .value("净利润", item.netProfit))
                        .position(by: .value("指标", "净利润"))
                        .foregroundStyle(Color.blue.gradient)
                        .cornerRadius(4)
                }
            }
            .chartLegend(.hidden)
            .chartYAxis(.hidden)
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2); AxisGridLine().foregroundStyle(.clear) } }
            .frame(height: 132)

            HStack(spacing: 0) {
                ForEach(years) { item in
                    VStack(spacing: 3) {
                        Text(item.year).font(.caption2).foregroundStyle(.secondary)
                        Text("ROE \(String(format: "%.2f%%", item.roe))").font(.caption.weight(.medium)).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 9)
            .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 0.5)
        }
    }

    private func nativeLegend(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 12, height: 4)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func nativeOperatingSignals(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("经营信号").font(.headline)
                Text("服务端最新研究状态").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            ForEach(Array((company.indicators ?? []).enumerated()), id: \.element.id) { index, indicator in
                if index > 0 { Divider().padding(.leading, 20) }
                HStack(spacing: 10) {
                    Circle()
                        .fill(nativeSignalColor(indicator.status))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(indicator.label).font(.subheadline.weight(.medium))
                        Text(indicator.note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(dashboardStatus(indicator.status, value: indicator.value))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(nativeSignalColor(indicator.status))
                }
                .padding(.vertical, 10)
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 0.5)
        }
    }

    private func nativeSignalColor(_ status: String) -> Color {
        if status.contains("改善") || status.contains("上升") { return .green }
        if status.contains("关注") || status.contains("观察") { return .orange }
        return .secondary
    }

    private func nativeNextReport(_ company: CompanyResearchProfile) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "calendar")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(companyAccent(company))
                .frame(width: 38, height: 38)
                .background(companyAccent(company).opacity(0.09), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("下次财报").font(.headline)
                Text("\(company.nextReport.reportType) · \(company.questions.count)项待验证")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(reportDate(company.nextReport.expectedDate))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(companyAccent(company))
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 0.5)
        }
    }

    private func dashboardMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.68)
        }
        .padding(.leading, 9)
        .frame(width: 76, height: 34, alignment: .leading)
        .overlay(alignment: .leading) { Divider().frame(height: 34) }
    }

    private func dashboardOverview(_ company: CompanyResearchProfile) -> some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                Text("公司仪表盘")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                Divider()
                HStack(spacing: 0) {
                    dashboardQuote(company)
                    Divider()
                    dashboardTrend(company)
                }
                .frame(height: 141)
                Divider()
                HStack(spacing: 0) {
                    dashboardQuality(company)
                    Divider()
                    dashboardVariables(company)
                }
                .frame(height: 120)
                Divider()
                HStack(spacing: 0) {
                    dashboardPeers()
                    Divider()
                    dashboardValuation(company)
                }
                .frame(height: 106)
            }
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.24), lineWidth: 0.7) }

            dashboardFinancialSummary(company)
            dashboardNextReport(company)
        }
        .padding(.top, 9)
    }

    private func dashboardQuote(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("行情快照").font(.system(size: 13, weight: .semibold))
            dashboardValueRow("最新价", marketPrice(company.market), accent: true)
            dashboardValueRow("涨跌幅", marketChange(company.market), accent: true)
            dashboardValueRow("总市值", marketCap(company.market?.marketCap))
            dashboardValueRow("PE (TTM)", formattedMultiple(company.market?.pe))
            dashboardValueRow("ROE (TTM)", latestROE(company))
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dashboardValueRow(_ label: String, _ value: String, accent: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(label)
            Spacer(minLength: 4)
            Text(value).monospacedDigit().foregroundStyle(accent ? Color.red : Color.primary)
        }
        .font(.system(size: 11))
    }

    private func dashboardTrend(_ company: CompanyResearchProfile) -> some View {
        let years = Array(company.financials.years.suffix(3))
        return VStack(alignment: .leading, spacing: 5) {
            Text("财务趋势").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 13) {
                Label("营收 (亿元)", systemImage: "minus").foregroundStyle(Color.red)
                Label("净利润 (亿元)", systemImage: "minus").foregroundStyle(Color.secondary)
            }
            .font(.system(size: 9))
            Chart {
                ForEach(years) { item in
                    LineMark(x: .value("年度", item.year), y: .value("营收", item.revenue), series: .value("指标", "营收"))
                        .foregroundStyle(Color.red)
                        .symbol(Circle())
                    PointMark(x: .value("年度", item.year), y: .value("营收", item.revenue))
                        .foregroundStyle(Color.red)
                        .annotation(position: .top, spacing: 2) {
                            Text(String(format: "%.2f", item.revenue)).font(.system(size: 7)).foregroundStyle(.primary)
                        }
                    LineMark(x: .value("年度", item.year), y: .value("净利润", item.netProfit), series: .value("指标", "净利润"))
                        .foregroundStyle(Color.secondary)
                        .symbol(Circle())
                    PointMark(x: .value("年度", item.year), y: .value("净利润", item.netProfit))
                        .foregroundStyle(Color.secondary)
                        .annotation(position: .top, spacing: 2) {
                            Text(String(format: "%.2f", item.netProfit)).font(.system(size: 7)).foregroundStyle(.primary)
                        }
                }
            }
            .chartXAxis { AxisMarks(values: years.map(\.year)) { _ in AxisValueLabel().font(.system(size: 8)); AxisGridLine().foregroundStyle(.clear) } }
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dashboardQuality(_ company: CompanyResearchProfile) -> some View {
        let latest = company.financials.years.last
        let previous = company.financials.years.dropLast().last
        let revenueStatus = (latest?.revenue ?? 0) >= (previous?.revenue ?? 0) ? "改善" : "中性"
        let profitStatus = (latest?.netProfit ?? 0) >= (previous?.netProfit ?? 0) ? "改善" : "中性"
        return dashboardStatusGroup("财务质量（\(latest?.year ?? "最新")）", rows: [
            ("增长", revenueStatus), ("盈利", profitStatus), ("现金", "待验证"), ("负债", "关注")
        ])
    }

    private func dashboardVariables(_ company: CompanyResearchProfile) -> some View {
        let indicators = company.indicators ?? []
        let rows = indicators.prefix(4).map { ($0.label, dashboardStatus($0.status, value: $0.value)) }
        return dashboardStatusGroup("经营变量（最新）", rows: rows)
    }

    private func dashboardPeers() -> some View {
        dashboardStatusGroup("同行坐标（白酒）", rows: [
            ("品牌力", "待补充"), ("渠道", "待补充"), ("增长", "待补充"), ("资本效率", "待补充")
        ])
    }

    private func dashboardValuation(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("估值带（PE）").font(.system(size: 13, weight: .semibold))
            HStack { Text("当前 PE (TTM)"); Spacer(); Text(formattedMultiple(company.market?.pe)).foregroundStyle(.red).fontWeight(.semibold) }
            HStack { Text("历史分位（近10年）"); Spacer(); dashboardBadge("待补充") }
        }
        .font(.system(size: 11))
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dashboardStatusGroup(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack { Text(row.0); Spacer(); dashboardBadge(row.1) }
                    .font(.system(size: 11))
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dashboardBadge(_ value: String) -> some View {
        let color: Color = value.contains("上升") || value.contains("改善") ? .red : value.contains("关注") || value.contains("观察") ? .orange : .secondary
        return Text(value)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .frame(minWidth: 43)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.22), lineWidth: 0.6) }
    }

    private func dashboardStatus(_ status: String, value: String) -> String {
        if value.contains("待补充") { return "待补充" }
        if status.contains("改善") || status.contains("上升") { return "上升" }
        if status.contains("关注") || status.contains("观察") { return status }
        return "待验证"
    }

    private func dashboardFinancialSummary(_ company: CompanyResearchProfile) -> some View {
        let years = Array(company.financials.years.suffix(3))
        return VStack(spacing: 0) {
            HStack { Text("财务摘要（合并报表）").fontWeight(.semibold); Spacer(); Text("单位：\(company.financials.unit)").foregroundStyle(.secondary) }
                .padding(.horizontal, 11).frame(height: 25)
            Divider()
            HStack(spacing: 0) {
                Text("").frame(maxWidth: .infinity)
                ForEach(years) { Text($0.year).frame(maxWidth: .infinity) }
            }.frame(height: 22)
            Divider()
            dashboardFinancialRow("营收", values: years.map { compactNumber($0.revenue) })
            dashboardFinancialRow("净利润", values: years.map { compactNumber($0.netProfit) })
            dashboardFinancialRow("ROE", values: years.map { String(format: "%.2f%%", $0.roe) })
            Divider()
            Text("现金流与利润质量 →").foregroundStyle(.red).fontWeight(.semibold).frame(height: 22)
        }
        .font(.system(size: 10))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay { RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.24), lineWidth: 0.7) }
    }

    private func dashboardFinancialRow(_ label: String, values: [String]) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Text(label).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 11)
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in Text(value).monospacedDigit().frame(maxWidth: .infinity) }
            }.frame(height: 19)
        }
    }

    private func dashboardNextReport(_ company: CompanyResearchProfile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar").font(.system(size: 18)).foregroundStyle(.red)
            Text("下次财报").fontWeight(.semibold)
            Text(reportDate(company.nextReport.expectedDate)).fontWeight(.semibold)
            Text("·")
            Text("\(max(company.questions.count, 1))项待验证").fontWeight(.semibold)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 13).frame(height: 32)
        .background(Color.red.opacity(0.035), in: RoundedRectangle(cornerRadius: 5))
        .overlay { RoundedRectangle(cornerRadius: 5).stroke(Color.red.opacity(0.14), lineWidth: 0.7) }
    }

    private func researchBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            content()
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func businessFlow(_ steps: [CompanyResearchBusinessStep], color: Color) -> some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                VStack(spacing: 5) {
                    Text("\(index + 1)").font(.caption2.bold()).foregroundStyle(color)
                    Text(step.title).font(.caption.bold()).multilineTextAlignment(.center)
                    Text(step.detail).font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
                }
                .frame(maxWidth: .infinity)
                if index < steps.count - 1 {
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary).padding(.top, 20)
                }
            }
        }
    }

    private func indicatorGrid(_ indicators: [CompanyResearchIndicator], color: Color) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
            ForEach(indicators) { indicator in
                VStack(alignment: .leading, spacing: 4) {
                    Text(indicator.label).font(.caption).foregroundStyle(.secondary)
                    Text(indicator.value.isEmpty ? indicator.status : indicator.value)
                        .font(.subheadline.bold())
                        .foregroundStyle(statusColor(indicator.status, accent: color))
                    Text(indicator.note).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                }
            }
        }
    }

    private func compactFinancialTable(_ company: CompanyResearchProfile) -> some View {
        let years = Array(company.financials.years.suffix(3))
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Text("").frame(maxWidth: .infinity)
                ForEach(years) { Text($0.year).font(.caption.bold()).frame(maxWidth: .infinity, alignment: .trailing) }
            }
            GridRow {
                Text("营收").font(.caption).foregroundStyle(.secondary)
                ForEach(years) { Text(compactNumber($0.revenue)).font(.caption.monospacedDigit()).frame(maxWidth: .infinity, alignment: .trailing) }
            }
            GridRow {
                Text("净利润").font(.caption).foregroundStyle(.secondary)
                ForEach(years) { Text(compactNumber($0.netProfit)).font(.caption.monospacedDigit()).frame(maxWidth: .infinity, alignment: .trailing) }
            }
            GridRow {
                Text("ROE").font(.caption).foregroundStyle(.secondary)
                ForEach(years) { Text(percent($0.roe)).font(.caption.monospacedDigit()).frame(maxWidth: .infinity, alignment: .trailing) }
            }
        }
    }

    private func statusColor(_ status: String, accent: Color) -> Color {
        if status.contains("改善") || status.contains("增长") || status.contains("上升") || status.contains("完成") { return accent }
        if status.contains("承压") || status.contains("风险") { return .orange }
        return .secondary
    }

    private func researchThesis(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            researchHeader("核心判断", subtitle: "这家公司最重要的研究主线", icon: "quote.opening", color: companyAccent(company))
            Text(company.thesis)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .researchCard(tint: companyAccent(company))
    }

    private func researchHeader(_ title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.subheadline.bold())
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func researchMetric(_ metric: CompanyResearchMetric, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metric.label).font(.caption2).foregroundStyle(.secondary)
            Text(metric.value).font(.subheadline.bold()).lineLimit(2).minimumScaleFactor(0.72)
            Text(metric.note).font(.caption2).foregroundStyle(color).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.065), in: RoundedRectangle(cornerRadius: 13))
    }

    private func researchListCard(title: String, subtitle: String, icon: String, items: [String], color: Color, numbered: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            researchHeader(title, subtitle: subtitle, icon: icon, color: color)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                researchPoint(item, marker: numbered ? "\(index + 1)" : nil, color: color)
            }
        }
        .researchCard()
    }

    private func researchCompactCard(title: String, icon: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundStyle(color)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(color).frame(width: 5, height: 5).padding(.top, 6)
                    Text(item).font(.caption).foregroundStyle(.primary).lineSpacing(2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.12), lineWidth: 0.8) }
    }

    private func researchPoint(_ text: String, marker: String?, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let marker { Text(marker).font(.caption2.bold()) }
                else { Image(systemName: "checkmark").font(.caption2.bold()) }
            }
            .foregroundStyle(color)
            .frame(width: 23, height: 23)
            .background(color.opacity(0.1), in: Circle())
            Text(text).font(.subheadline).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func companyFacts(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            researchHeader("公司资料", subtitle: company.name, icon: "building.2", color: companyAccent(company))
            factRow("上市市场", "\(company.ticker) · \(company.exchange)", icon: "building.columns")
            Divider()
            factRow("行业与地区", "\(company.industry) · \(company.location)", icon: "mappin.and.ellipse")
            Divider()
            factRow("更新时间", company.updatedAt.formatted(
                .dateTime.locale(Locale(identifier: "zh_CN")).month().day().hour().minute()
            ), icon: "clock")
        }
        .researchCard()
    }

    private func factRow(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
        }
    }

    private func emptySection(_ title: String, icon: String, detail: String) -> some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(detail))
            .frame(maxWidth: .infinity, minHeight: 230)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private func businessSection(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let framework = company.framework {
                researchBlock("商业模式") { Text(framework.businessSummary).font(.body).lineSpacing(5) }
                researchBlock("收入来源") { detailPair("怎么赚钱", framework.revenueModel); detailPair("客户是谁", framework.customers) }
                if let business = company.business, !business.isEmpty {
                    researchBlock("价值链") { businessFlow(business, color: companyAccent(company)) }
                }
                researchBlock("定价能力") { Text(framework.pricingPower).font(.body).lineSpacing(5) }
                researchBlock("竞争位置") { Text(framework.competitivePosition).font(.body).lineSpacing(5) }
                researchBlock("资本配置") { Text(framework.capitalAllocation).font(.body).lineSpacing(5) }
            } else {
                emptySection("商业资料待补充", icon: "arrow.triangle.branch", detail: "服务端尚未建立这家公司的商业模式档案")
            }
        }
        .padding(.top, 12)
    }

    private func detailPair(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            Text(value).font(.subheadline).lineSpacing(4)
        }
    }

    private func valuationSection(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            researchBlock("当前估值") {
                HStack {
                    summaryMetric("市盈率", formattedMultiple(company.market?.pe))
                    summaryMetric("总市值", marketCap(company.market?.marketCap))
                    summaryMetric("历史分位", "待补充")
                }
            }
            if let consensus = company.consensus {
                researchBlock("市场一致预期") {
                    Text(consensus.period).font(.caption).foregroundStyle(.secondary)
                    ForEach(consensus.metrics, id: \.label) { metric in
                        HStack {
                            Text(metric.label).font(.subheadline)
                            Spacer()
                            Text(metric.value).font(.subheadline.bold().monospacedDigit())
                        }
                        Text(metric.note).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(consensus.note).font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                }
            }
            researchBlock("估值说明") {
                Text("历史估值区间、同行估值与情景分析尚未形成可靠服务端数据，当前不展示推算目标价。")
                    .font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
            }
        }
        .padding(.top, 12)
    }

    private func researchTimelineSection(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            researchBlock("当前判断") {
                Text(company.thesis).font(.headline).lineSpacing(5)
                Label("持续验证", systemImage: "square.fill").font(.caption.bold()).foregroundStyle(companyAccent(company))
            }
            if let updates = company.updates, !updates.isEmpty {
                researchBlock("研究进展") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(updates.enumerated()), id: \.element.id) { index, update in
                            timelineRow(index + 1, update: update, color: companyAccent(company), showLine: index < updates.count - 1)
                        }
                    }
                }
            }
            researchBlock("支持论点 / 反方证据") {
                HStack(alignment: .top, spacing: 18) {
                    evidenceColumn("支持论点", company.moats, color: companyAccent(company))
                    Divider()
                    evidenceColumn("反方证据", company.risks, color: .secondary)
                }
            }
            if let conditions = company.framework?.falsificationConditions, !conditions.isEmpty {
                researchBlock("证伪条件") {
                    ForEach(Array(conditions.enumerated()), id: \.offset) { index, condition in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)").font(.caption.bold()).foregroundStyle(companyAccent(company))
                            Text(condition).font(.subheadline).lineSpacing(3)
                        }
                    }
                }
            }
            researchBlock("持续跟踪") {
                ForEach(company.questions, id: \.self) { Label($0, systemImage: "circle").font(.subheadline) }
            }
            sourcesSection(company)
        }
        .padding(.top, 12)
    }

    private func timelineRow(_ number: Int, update: CompanyResearchUpdate, color: Color, showLine: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text("\(number)").font(.caption.bold()).foregroundStyle(.white).frame(width: 24, height: 24).background(color, in: RoundedRectangle(cornerRadius: 4))
                if showLine { Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1, height: 62) }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(update.title).font(.headline); Spacer(); Text(update.status).font(.caption.bold()).foregroundStyle(statusColor(update.status, accent: color)) }
                if !update.occurredOn.isEmpty { Text(update.occurredOn).font(.caption2).foregroundStyle(.tertiary) }
                Text(update.summary).font(.caption).foregroundStyle(.secondary).lineSpacing(3)
            }
            .padding(.bottom, showLine ? 10 : 0)
        }
    }

    private func evidenceColumn(_ title: String, _ items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.subheadline.bold())
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Rectangle().fill(color).frame(width: 5, height: 5).padding(.top, 5)
                    Text(item).font(.caption).lineSpacing(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func financialSection(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("经营趋势").font(.title3.bold())
                    Text("历史财报 · 收入、利润与资本回报").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(company.financials.unit)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
            }

            Picker("财报周期", selection: $financialRange) {
                ForEach(FinancialRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .disabled((company.financials.quarters ?? []).isEmpty)

            Chart {
                ForEach(displayedFinancialPeriods(company)) { item in
                    if let revenue = item.revenue {
                        BarMark(x: .value("周期", item.period), y: .value("金额", revenue))
                            .foregroundStyle(item.isForecast ? Color.orange.opacity(0.28) : companyAccent(company).opacity(0.18))
                            .cornerRadius(5)
                            .position(by: .value("指标", "营业收入"))
                            .annotation(position: .top, spacing: 4) {
                                chartValueLabel(revenue, color: item.isForecast ? .orange : .secondary)
                            }
                    }
                    if let netProfit = item.netProfit {
                        BarMark(x: .value("周期", item.period), y: .value("金额", netProfit))
                            .foregroundStyle(item.isForecast ? Color.orange : companyAccent(company))
                            .cornerRadius(5)
                            .position(by: .value("指标", "归母净利润"))
                            .annotation(position: .top, spacing: 4) {
                                chartValueLabel(netProfit, color: item.isForecast ? .orange : companyAccent(company))
                            }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption) } }
            .chartYScale(domain: .automatic(includesZero: true))
            .chartYScale(range: .plotDimension(padding: 18))
            .frame(height: 168)

            HStack(spacing: 18) {
                Label("营业收入", systemImage: "square.fill")
                    .foregroundStyle(companyAccent(company).opacity(0.38))
                Label("归母净利润", systemImage: "square.fill")
                    .foregroundStyle(companyAccent(company))
                if hasForecast(company) {
                    Label("预测", systemImage: "square.fill")
                        .foregroundStyle(.orange)
                }
                Spacer()
            }
            .font(.caption)

            if financialRange == .quarterly,
               let latest = company.financials.quarters?.last,
               let previous = company.financials.quarters?.dropLast().last {
                Divider()
                Text("最新季度 · \(latest.period)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    changeMetric("营收", latest.revenue, growth: growth(latest.revenue, previous.revenue), color: companyAccent(company), changeLabel: "环比")
                    changeMetric("净利润", latest.netProfit, growth: growth(latest.netProfit, previous.netProfit), color: companyAccent(company), changeLabel: "环比")
                }
                if let note = latest.note, !note.isEmpty {
                    Label(note, systemImage: "info.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let latest = company.financials.years.last,
                      let previous = company.financials.years.dropLast().last {
                Divider()
                Text("最新年度 · \(latest.year)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    changeMetric("营收", latest.revenue, growth: growth(latest.revenue, previous.revenue), color: companyAccent(company))
                    changeMetric("净利润", latest.netProfit, growth: growth(latest.netProfit, previous.netProfit), color: companyAccent(company))
                    changeMetric("ROE", latest.roe, growth: latest.roe - previous.roe, color: companyAccent(company), isPercent: true)
                }
            }

            Divider()
            if financialRange == .quarterly, !(company.financials.quarters ?? []).isEmpty {
                quarterlyFinancialTable(company)
            } else {
                financialTable(company)
            }

            Link(destination: company.financials.source.url) {
                HStack {
                    Label("查看原始财报", systemImage: "doc.text")
                    Spacer()
                    Text(company.financials.source.title).lineLimit(1)
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(companyAccent(company))
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.045), radius: 12, y: 5)
    }

    private struct CompanyResearchChartPeriod: Identifiable {
        let period: String
        let revenue: Double?
        let netProfit: Double?
        let isForecast: Bool

        var id: String { "\(isForecast ? "forecast" : "actual")-\(period)" }
    }

    private func displayedFinancialPeriods(_ company: CompanyResearchProfile) -> [CompanyResearchChartPeriod] {
        let range = financialRange == .quarterly ? "quarterly" : "annual"
        let forecasts = (company.financials.forecasts ?? [])
            .filter { $0.range == range }
            .map { CompanyResearchChartPeriod(period: "\($0.period)E", revenue: $0.revenue, netProfit: $0.netProfit, isForecast: true) }
        if financialRange == .quarterly, let quarters = company.financials.quarters, !quarters.isEmpty {
            return quarters.map {
                CompanyResearchChartPeriod(period: $0.period, revenue: $0.revenue, netProfit: $0.netProfit, isForecast: false)
            } + forecasts
        }
        return company.financials.years.map {
            CompanyResearchChartPeriod(period: $0.year, revenue: $0.revenue, netProfit: $0.netProfit, isForecast: false)
        } + forecasts
    }

    private func hasForecast(_ company: CompanyResearchProfile) -> Bool {
        let range = financialRange == .quarterly ? "quarterly" : "annual"
        return company.financials.forecasts?.contains { $0.range == range } == true
    }

    private func quarterlyFinancialTable(_ company: CompanyResearchProfile) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                tableCell("季度", alignment: .leading, weight: .semibold)
                tableCell("营收", alignment: .trailing, weight: .semibold)
                tableCell("净利润", alignment: .trailing, weight: .semibold)
                tableCell("净利率", alignment: .trailing, weight: .semibold)
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)

            ForEach(Array((company.financials.quarters ?? []).enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider() }
                HStack(spacing: 4) {
                    tableCell(item.period, alignment: .leading, weight: .medium)
                    tableCell(compactNumber(item.revenue), alignment: .trailing, weight: .regular)
                    tableCell(compactNumber(item.netProfit), alignment: .trailing, weight: .regular)
                    tableCell(percent(item.netProfit / item.revenue * 100), alignment: .trailing, weight: .regular)
                }
                .padding(.vertical, 9)
            }
        }
        .font(.caption.monospacedDigit())
        .padding(12)
        .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private func financialTable(_ company: CompanyResearchProfile) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                tableCell("年度", alignment: .leading, weight: .semibold)
                tableCell("营收", alignment: .trailing, weight: .semibold)
                tableCell("净利润", alignment: .trailing, weight: .semibold)
                tableCell("净利率", alignment: .trailing, weight: .semibold)
                tableCell("ROE", alignment: .trailing, weight: .semibold)
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)

            ForEach(Array(company.financials.years.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider() }
                HStack(spacing: 4) {
                    tableCell(item.year, alignment: .leading, weight: .medium)
                    tableCell(compactNumber(item.revenue), alignment: .trailing, weight: .regular)
                    tableCell(compactNumber(item.netProfit), alignment: .trailing, weight: .regular)
                    tableCell(percent(item.netProfit / item.revenue * 100), alignment: .trailing, weight: .regular)
                    tableCell(percent(item.roe), alignment: .trailing, weight: .regular)
                }
                .padding(.vertical, 9)
            }
        }
        .font(.caption.monospacedDigit())
        .padding(12)
        .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private func tableCell(_ text: String, alignment: Alignment, weight: Font.Weight) -> some View {
        Text(text)
            .fontWeight(weight)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func changeMetric(_ label: String, _ value: Double, growth: Double, color: Color, isPercent: Bool = false, changeLabel: String = "同比") -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(isPercent ? percent(value) : compactNumber(value))
                .font(.subheadline.bold()).monospacedDigit()
            Text(isPercent ? "\(changeLabel) \(signedPercentPoint(growth))" : "\(changeLabel) \(signedPercent(growth))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(growth >= 0 ? color : .red)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func growth(_ current: Double, _ previous: Double) -> Double {
        guard previous != 0 else { return 0 }
        return (current / previous - 1) * 100
    }

    private func compactNumber(_ value: Double) -> String {
        if abs(value) >= 1_000 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }

    private func chartValueLabel(_ value: Double, color: Color) -> some View {
        Text(compactNumber(value))
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func percent(_ value: Double) -> String { String(format: "%.1f%%", value) }

    private func signedPercent(_ value: Double) -> String { String(format: "%+.1f%%", value) }

    private func signedPercentPoint(_ value: Double) -> String { String(format: "%+.1fpp", value) }

    private func eventSection(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("重要事件").font(.title3.bold())
                Spacer()
                Image(systemName: "bell.badge")
                    .foregroundStyle(companyAccent(company))
            }
            eventRow(
                color: companyAccent(company), icon: "arrow.triangle.2.circlepath",
                eyebrow: "股份回购 · \(company.buyback.status)",
                title: company.buyback.amount,
                detail: "\(company.buyback.shares) · \(company.buyback.priceRange)"
            )
            Divider().padding(.leading, 50)
            eventRow(
                color: .purple, icon: "calendar",
                eyebrow: "下一财报 · \(company.nextReport.dateStatus)",
                title: reportDate(company.nextReport.expectedDate),
                detail: company.nextReport.reportType
            )
            HStack {
                Text("回购数据截至 \(company.buyback.asOfDate)")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Link("查看公告 ↗", destination: company.buyback.source.url)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(companyAccent(company))
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.045), radius: 12, y: 5)
    }

    private func consensusSection(_ consensus: CompanyResearchConsensus, company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Label("市场一致预期", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.title3.bold())
                    .foregroundStyle(companyAccent(company))
                Spacer()
                Text(consensus.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(companyAccent(company))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(companyAccent(company).opacity(0.09), in: Capsule())
            }

            Text(consensus.period)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(Array(consensus.metrics.enumerated()), id: \.element.label) { index, metric in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(companyAccent(company))
                        .frame(width: 28, height: 28)
                        .background(companyAccent(company).opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                    Text(metric.value)
                        .font(.headline.monospacedDigit())
                    Text("\(metric.label) · \(metric.note)")
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Divider()
            Text(consensus.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            HStack {
                Text("截至 \(consensus.asOfDate)")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Link("数据来源 ↗", destination: consensus.source.url)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(companyAccent(company))
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(LinearGradient(colors: [companyAccent(company).opacity(0.07), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(companyAccent(company).opacity(0.14), lineWidth: 0.8) }
    }

    private func eventRow(color: Color, icon: String, eyebrow: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.headline.bold()).foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow).font(.caption).foregroundStyle(.secondary)
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private func sourcesSection(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("原始资料").font(.title3.bold())
                Spacer()
                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.secondary)
            }
            ForEach(company.sources, id: \.url) { source in
                Link(destination: source.url) {
                    HStack {
                        Text(source.title).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.vertical, 2)
                }
            }
            Text("档案更新于 \(company.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }

    private func companyLogo(_ company: CompanyResearchProfile) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(uiColor: .systemBackground))
            companyLogoContent(company)
        }
        .frame(width: 48, height: 38)
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(company.shortName)标志")
    }

    @ViewBuilder
    private func companyLogoContent(_ company: CompanyResearchProfile) -> some View {
        AsyncImage(url: resolvedCompanyLogoURL(company)) { phase in
            if case let .success(image) = phase {
                image
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            } else {
                Text(String(company.shortName.prefix(1)))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(companyAccent(company))
            }
        }
    }

    private func resolvedCompanyLogoURL(_ company: CompanyResearchProfile) -> URL {
        guard company.logoUrl.scheme == nil else { return company.logoUrl }
        let path = company.logoUrl.relativeString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return ServerConfiguration.currentURL.appending(path: path)
    }

    private func companyAccent(_ company: CompanyResearchProfile) -> Color {
        switch company.id {
        case "wuliangye": Color(red: 0.08, green: 0.25, blue: 0.52)
        case "pdd-holdings": Color(red: 0.83, green: 0.11, blue: 0.16)
        case "nvidia": Color(red: 0.20, green: 0.49, blue: 0.08)
        case "alphabet": Color(red: 0.10, green: 0.38, blue: 0.84)
        default: Color(red: 0.52, green: 0.07, blue: 0.09)
        }
    }

    private func heroMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.62))
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func summaryMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func marketPrice(_ market: CompanyResearchMarket?) -> String {
        guard let price = market?.price else { return "--" }
        let symbol = market?.currency == "CNY" ? "¥" : market?.currency == "USD" ? "$" : ""
        return String(format: "%@%.2f", symbol, price)
    }

    private func marketChangeColor(_ market: CompanyResearchMarket?) -> Color {
        guard let change = market?.changePercent else { return .secondary }
        if change.hasPrefix("-") { return .red }
        if change == "0" || change.hasPrefix("0.0") { return .secondary }
        return .green
    }

    private func marketChange(_ market: CompanyResearchMarket?) -> String {
        guard let change = market?.changePercent, !change.isEmpty else { return "--" }
        return change.contains("%") ? change : "\(change)%"
    }

    private func marketCap(_ value: Double?) -> String {
        guard let value else { return "--" }
        if value >= 1_000_000_000_000 { return String(format: "%.2f万亿", value / 1_000_000_000_000) }
        if value >= 100_000_000 { return String(format: "%.0f亿", value / 100_000_000) }
        return String(format: "%.0f万", value / 10_000)
    }

    private func formattedMultiple(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f×", value)
    }

    private func latestROE(_ company: CompanyResearchProfile) -> String {
        guard let value = company.financials.years.last?.roe else { return "--" }
        return String(format: "%.2f%%", value)
    }

    private func reportDate(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3 else { return date }
        return "\(parts[1])月\(parts[2])日"
    }
}

private struct CompanyScrollBounceConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        configure(from: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        configure(from: uiView)
    }

    private func configure(from view: UIView) {
        DispatchQueue.main.async {
            var ancestor = view.superview
            while let current = ancestor {
                if let scrollView = current as? UIScrollView {
                    scrollView.bounces = false
                    scrollView.alwaysBounceVertical = false
                    return
                }
                ancestor = current.superview
            }
        }
    }
}

private extension View {
    func researchCard(tint: Color? = nil) -> some View {
        padding(18)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .overlay(alignment: .topLeading) {
                        if let tint {
                            LinearGradient(
                                colors: [tint.opacity(0.1), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke((tint ?? .secondary).opacity(tint == nil ? 0.08 : 0.16), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.035), radius: 10, y: 4)
    }
}
