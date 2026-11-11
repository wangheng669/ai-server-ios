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
    var peStatic: Double?
    var peType: String?
    var netIncomeTTM: Double?
    var week52Low: Double?
    let currency: String
    var fiscalYear: String?
    var fundamentalsSource: String?
    var fundamentalsAsOf: String?
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
    private(set) var lastLoadedAt: Date?
    private let fetch: () async throws -> CompanyResearchPayload
    private let refreshInterval: TimeInterval

    init(
        service: CompanyResearchService = CompanyResearchService(),
        refreshInterval: TimeInterval = 5 * 60
    ) {
        fetch = { try await service.fetch() }
        self.refreshInterval = refreshInterval
    }

    init(
        refreshInterval: TimeInterval = 5 * 60,
        fetch: @escaping () async throws -> CompanyResearchPayload
    ) {
        self.fetch = fetch
        self.refreshInterval = refreshInterval
    }

    func load(force: Bool = false, now: Date = Date()) async {
        guard !isLoading, force || companies.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            companies = try await fetch().companies
            lastLoadedAt = now
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "公司研究暂时无法载入"
        }
    }

    func loadIfNeeded(now: Date = Date()) async {
        let isStale = lastLoadedAt.map { now.timeIntervalSince($0) >= refreshInterval } ?? true
        guard lastLoadedAt == nil || isStale else { return }
        await load(force: true, now: now)
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
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedSection: Section = .overview
    @State private var financialRange: FinancialRange = .quarterly
    @State private var presentedCompany: CompanyResearchProfile?
    @State private var presentedValuation: CompanyValuationHistoryRoute?

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
                        .accessibilityIdentifier("company-home-loading")
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
            .appSheet(item: $presentedCompany) { company in
                companyPage(company)
                    .appPresentationDetents([.large])
                    .appPresentationCornerRadius(28)
            }
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await store.loadIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard rootTabIsActive, phase == .active else { return }
            Task { await store.loadIfNeeded() }
        }
    }

    private var companyHub: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(store.companies) { company in
                    companyHubCard(company)
                }
            }
            .padding(.horizontal, 11)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .background(CompanyScrollBounceConfigurator())
        .accessibilityIdentifier("company-home")
        .appSheet(item: hubValuationBinding) { route in
            valuationHistorySheet(route)
        }
    }

    private func companyHubCard(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { openCompany(company) } label: {
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
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Divider()

            HStack(spacing: 0) {
                Button { openCompany(company) } label: { hubMetric("总市值", marketCap(company.market)) }
                    .buttonStyle(.plain)
                hubValuationMetric(company, kind: .staticPE, value: formattedMultiple(company.market?.peStatic))
                hubValuationMetric(company, kind: .ttm, value: formattedMultiple(company.market?.pe))
                Button { openCompany(company) } label: { hubMetric("ROE", latestROE(company)) }
                    .buttonStyle(.plain)
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

    private func hubValuationMetric(_ company: CompanyResearchProfile, kind: CompanyPEKind, value: String) -> some View {
        Button { presentValuation(company, kind: kind) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    Text(kind.metricTitle.replacingOccurrences(of: "市盈率", with: "PE"))
                    Image(systemName: "chart.xyaxis.line")
                }
                .font(.caption2)
                .foregroundStyle(kind.color)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看历史变化曲线")
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
        .overlay(alignment: .bottomTrailing) {
            DetailSheetCloseButton(
                action: { presentedCompany = nil },
                accessibilityLabel: "关闭公司详情"
            )
            .padding(16)
        }
        .appSheet(item: $presentedValuation) { route in
            valuationHistorySheet(route)
        }
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
                dashboardMetric("总市值", marketCap(company.market))
                dashboardValuationMetric(company, kind: .staticPE, value: formattedMultiple(company.market?.peStatic))
                dashboardValuationMetric(company, kind: .ttm, value: formattedMultiple(company.market?.pe))
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
        VStack(alignment: .leading, spacing: 14) {
            nativeFinancialTrend(company)
            nativeOperatingSignals(company)
            nativeNextReport(company)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
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
                    Text(indicatorStatus(indicator.status, value: indicator.value))
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

    private func dashboardValuationMetric(_ company: CompanyResearchProfile, kind: CompanyPEKind, value: String) -> some View {
        Button { presentValuation(company, kind: kind) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Text(kind == .staticPE ? "PE 静" : "PE TTM")
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 10))
                .foregroundStyle(kind.color)
                Text(value).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.68)
            }
            .padding(.leading, 9)
            .frame(width: 76, height: 34, alignment: .leading)
            .overlay(alignment: .leading) { Divider().frame(height: 34) }
        }
        .buttonStyle(.plain)
    }

    private func indicatorStatus(_ status: String, value: String) -> String {
        if value.contains("待补充") { return "待补充" }
        if status.contains("改善") || status.contains("上升") { return "上升" }
        if status.contains("关注") || status.contains("观察") { return status }
        return "待验证"
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

    private func statusColor(_ status: String, accent: Color) -> Color {
        if status.contains("改善") || status.contains("增长") || status.contains("上升") || status.contains("完成") { return accent }
        if status.contains("承压") || status.contains("风险") { return .orange }
        return .secondary
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
                    valuationSummaryMetric(company, kind: .staticPE, value: formattedMultiple(company.market?.peStatic))
                    valuationSummaryMetric(company, kind: .ttm, value: formattedMultiple(company.market?.pe))
                    summaryMetric("总市值", marketCap(company.market))
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
        guard company.logoUrl.scheme == nil else {
            return MediaURL.image(company.logoUrl.absoluteString) ?? company.logoUrl
        }
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

    private func summaryMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func valuationSummaryMetric(_ company: CompanyResearchProfile, kind: CompanyPEKind, value: String) -> some View {
        Button { presentValuation(company, kind: kind) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    Text(kind.metricTitle)
                    Image(systemName: "chart.xyaxis.line").font(.caption2.weight(.semibold))
                }
                .font(.caption2)
                .foregroundStyle(kind.color)
                Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func openCompany(_ company: CompanyResearchProfile) {
        selectedSection = .overview
        presentedCompany = company
    }

    private var hubValuationBinding: Binding<CompanyValuationHistoryRoute?> {
        Binding(
            get: { presentedCompany == nil ? presentedValuation : nil },
            set: { presentedValuation = $0 }
        )
    }

    private func presentValuation(_ company: CompanyResearchProfile, kind: CompanyPEKind) {
        presentedValuation = CompanyValuationHistoryRoute(
            symbol: company.market?.symbol ?? company.ticker,
            name: company.shortName,
            initialKind: kind
        )
    }

    private func valuationHistorySheet(_ route: CompanyValuationHistoryRoute) -> some View {
        CompanyValuationHistorySheet(route: route)
            .appPresentationDetents([.large])
            .appPresentationCornerRadius(28)
    }

    private func marketPrice(_ market: CompanyResearchMarket?) -> String {
        guard let price = market?.price else { return "--" }
        return String(format: "%@%.2f", currencyPrefix(market?.currency), price)
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

    private func marketCap(_ market: CompanyResearchMarket?) -> String {
        guard let value = market?.marketCap else { return "--" }
        let prefix = currencyPrefix(market?.currency)
        if value >= 1_000_000_000_000 { return String(format: "%@%.2f万亿", prefix, value / 1_000_000_000_000) }
        if value >= 100_000_000 { return String(format: "%@%.0f亿", prefix, value / 100_000_000) }
        return String(format: "%@%.0f万", prefix, value / 10_000)
    }

    private func currencyPrefix(_ currency: String?) -> String {
        switch currency {
        case "CNY": return "¥"
        case "USD": return "$"
        case "HKD": return "HK$"
        case let code?: return "\(code) "
        case nil: return ""
        }
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
