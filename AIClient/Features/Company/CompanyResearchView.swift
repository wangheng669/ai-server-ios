import Charts
import SwiftUI

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
    let market: CompanyResearchMarket?
    let updatedAt: Date
}

struct CompanyResearchFinancials: Decodable, Hashable {
    let unit: String
    let years: [CompanyResearchFinancialYear]
    let source: CompanyResearchSource
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
        let (data, response) = try await session.data(from: url)
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
    private enum Section: String, CaseIterable {
        case overview = "概览"
        case financial = "财务"
        case events = "事件"
        case sources = "资料"
    }

    @StateObject private var store: CompanyResearchStore
    @State private var selectedCompanyID: String?
    @State private var selectedSection: Section = .overview

    init() {
        _store = StateObject(wrappedValue: CompanyResearchStore())
    }

    init(store: CompanyResearchStore) {
        _store = StateObject(wrappedValue: store)
    }

    private var selectedCompanyBinding: Binding<String> {
        Binding(
            get: { selectedCompanyID ?? store.companies.first?.id ?? "" },
            set: {
                selectedCompanyID = $0
                selectedSection = .overview
            }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.companies.isEmpty {
                    ProgressView("正在读取研究档案")
                } else if !store.companies.isEmpty {
                    TabView(selection: selectedCompanyBinding) {
                        ForEach(store.companies) { company in
                            companyPage(company)
                                .tag(company.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                } else if let errorMessage = store.errorMessage {
                    ContentUnavailableView(errorMessage, systemImage: "building.2.crop.circle", description: Text("下拉或点击重试"))
                } else {
                    ContentUnavailableView("暂无公司", systemImage: "building.2", description: Text("公司档案将在服务端持续补充"))
                }
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await store.load() }
    }

    private func companyPage(_ company: CompanyResearchProfile) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    hero(company)
                        .id(Section.overview)
                    sectionTabs(company, proxy: proxy)
                    financialSection(company)
                        .id(Section.financial)
                    if let consensus = company.consensus {
                        consensusSection(consensus, company: company)
                    }
                    thesisCard(company)
                    eventSection(company)
                        .id(Section.events)
                    researchSection(company)
                    sourcesSection(company)
                        .id(Section.sources)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 48)
            }
            .refreshable { await store.load(force: true) }
        }
    }

    private func hero(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 14) {
                companyLogo(company)
                VStack(alignment: .leading, spacing: 5) {
                    Text(company.shortName).font(.title2.bold())
                    Text("\(company.ticker) · \(company.exchange)")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(company.industry)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .foregroundStyle(companyAccent(company))
                    .background(companyAccent(company).opacity(0.09), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(marketPrice(company.market))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(marketChange(company.market))
                        .font(.subheadline.bold())
                        .foregroundStyle(marketChangeColor(company.market))
                    Text(company.market?.status ?? "行情暂不可用")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                marketMetric("总市值", marketCap(company.market?.marketCap))
                marketMetric("市盈率", formattedMultiple(company.market?.pe))
                marketMetric("最新 ROE", latestROE(company))
            }

            pageIndicator(company)
        }
        .padding(.vertical, 4)
    }

    private func pageIndicator(_ company: CompanyResearchProfile) -> some View {
        HStack(spacing: 5) {
            ForEach(store.companies) { item in
                Capsule()
                    .fill(item.id == company.id ? companyAccent(company) : Color.secondary.opacity(0.18))
                    .frame(width: item.id == company.id ? 18 : 5, height: 5)
                    .animation(.easeInOut(duration: 0.2), value: company.id)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("第 \((store.companies.firstIndex(of: company) ?? 0) + 1) 页，共 \(store.companies.count) 页")
    }

    private func sectionTabs(_ company: CompanyResearchProfile, proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            ForEach(Section.allCases, id: \.self) { section in
                Button {
                    selectedSection = section
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(section, anchor: .top) }
                } label: {
                    compactTab(section.rawValue, selected: selectedSection == section, color: companyAccent(company))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func compactTab(_ title: String, selected: Bool, color: Color) -> some View {
        Text(title)
            .font(.subheadline.weight(selected ? .semibold : .medium))
            .foregroundStyle(selected ? color : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(selected ? color.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
    }

    private func thesisCard(_ company: CompanyResearchProfile) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "scope")
                .font(.headline.weight(.semibold))
                .foregroundStyle(companyAccent(company))
                .frame(width: 38, height: 38)
                .background(companyAccent(company).opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("核心判断").font(.headline)
                    Spacer()
                    Text("持续跟踪")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(companyAccent(company))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(companyAccent(company).opacity(0.08), in: Capsule())
                }
                Text(company.thesis)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(Color.secondary.opacity(0.1), lineWidth: 0.5) }
    }

    private func financialSection(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("经营趋势").font(.title3.bold())
                Spacer()
                Text("单位：\(company.financials.unit)").font(.caption).foregroundStyle(.secondary)
            }

            Chart(company.financials.years) { item in
                BarMark(x: .value("年度", item.year), y: .value("金额", item.revenue))
                    .foregroundStyle(companyAccent(company).opacity(0.18))
                    .cornerRadius(5)
                    .position(by: .value("指标", "营业收入"))
                BarMark(x: .value("年度", item.year), y: .value("金额", item.netProfit))
                    .foregroundStyle(companyAccent(company))
                    .cornerRadius(5)
                    .position(by: .value("指标", "归母净利润"))
            }
            .chartYAxis(.hidden)
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption) } }
            .frame(height: 150)

            HStack(spacing: 18) {
                Label("营业收入", systemImage: "square.fill")
                    .foregroundStyle(companyAccent(company).opacity(0.38))
                Label("归母净利润", systemImage: "square.fill")
                    .foregroundStyle(companyAccent(company))
                Spacer()
            }
            .font(.caption)

            if let latest = company.financials.years.last {
                HStack(spacing: 0) {
                    summaryMetric("营收", String(format: "%.1f", latest.revenue))
                    summaryMetric("归母净利润", String(format: "%.1f", latest.netProfit))
                    summaryMetric("ROE", String(format: "%.2f%%", latest.roe))
                }
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(Color.secondary.opacity(0.1), lineWidth: 0.5) }
    }

    private func eventSection(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("重要事件").font(.title3.bold())
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
        .padding(18)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(Color.secondary.opacity(0.1), lineWidth: 0.5) }
    }

    private func consensusSection(_ consensus: CompanyResearchConsensus, company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("市场一致预期").font(.title3.bold())
                Spacer()
                Text(consensus.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(companyAccent(company))
            }

            Text(consensus.period)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(consensus.metrics, id: \.label) { metric in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(metric.label).font(.subheadline.weight(.medium))
                        Text(metric.note).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(metric.value)
                        .font(.headline.monospacedDigit())
                        .multilineTextAlignment(.trailing)
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
        .padding(18)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(Color.secondary.opacity(0.1), lineWidth: 0.5) }
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

    private func researchSection(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionEyebrow("研究框架")
                .padding(.bottom, 8)
            researchGroup("看点", icon: "scope", items: company.highlights)
            Divider().padding(.leading, 38)
            researchGroup("壁垒", icon: "shield", items: company.moats)
            Divider().padding(.leading, 38)
            researchGroup("风险", icon: "exclamationmark.triangle", items: company.risks)
            Divider().padding(.leading, 38)
            researchGroup("跟踪", icon: "checklist", items: company.questions)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(Color.secondary.opacity(0.1), lineWidth: 0.5) }
    }

    private func researchGroup(_ title: String, icon: String, items: [String]) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
            }
        }
        .padding(.vertical, 18)
    }

    private func sourcesSection(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionEyebrow("原始资料")
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
    }

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }

    private func companyLogo(_ company: CompanyResearchProfile) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .systemBackground))
            companyLogoContent(company)
        }
        .frame(width: 58, height: 46)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
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

    private func marketMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
