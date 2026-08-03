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
    let updatedAt: Date
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

struct CompanyResearchService {
    var baseURL: URL = ServerConfiguration.currentURL
    var session: URLSession = .shared

    func fetch() async throws -> CompanyResearchPayload {
        let url = baseURL.appending(path: "api/v1/market/company-research")
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
    @StateObject private var store: CompanyResearchStore
    @State private var selectedCompanyID: String?

    init() {
        _store = StateObject(wrappedValue: CompanyResearchStore())
    }

    init(store: CompanyResearchStore) {
        _store = StateObject(wrappedValue: store)
    }

    private var selectedCompany: CompanyResearchProfile? {
        store.companies.first { $0.id == selectedCompanyID } ?? store.companies.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.companies.isEmpty {
                    ProgressView("正在读取研究档案")
                } else if let company = selectedCompany {
                    companyPage(company)
                } else if let errorMessage = store.errorMessage {
                    ContentUnavailableView(errorMessage, systemImage: "building.2.crop.circle", description: Text("下拉或点击重试"))
                } else {
                    ContentUnavailableView("暂无公司", systemImage: "building.2", description: Text("公司档案将在服务端持续补充"))
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await store.load() }
    }

    private func companyPage(_ company: CompanyResearchProfile) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header(company)
                if store.companies.count > 1 { companyPicker }
                metricGrid(company.metrics)
                shareholderReturnSection(company)
                thesisCard(company)
                bulletSection("研究要点", icon: "scope", items: company.highlights, tint: .blue)
                bulletSection("竞争壁垒", icon: "shield.lefthalf.filled", items: company.moats, tint: .green)
                bulletSection("关键风险", icon: "exclamationmark.triangle", items: company.risks, tint: .orange)
                bulletSection("持续跟踪", icon: "checklist", items: company.questions, tint: .purple)
                sourcesSection(company)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .refreshable { await store.load(force: true) }
    }

    private func header(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Text(String(company.shortName.prefix(1)))
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(company.id == "wuliangye" ? Color(red: 0.10, green: 0.30, blue: 0.62) : Color(red: 0.66, green: 0.08, blue: 0.10), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text(company.shortName).font(.title2.bold())
                    Text("\(company.ticker) · \(company.exchange)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        tag(company.industry)
                        tag(company.location)
                    }
                }
            }
            Text(company.tagline)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("深度研究 · 服务端档案")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private var companyPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(store.companies) { company in
                    Button(company.shortName) { selectedCompanyID = company.id }
                        .buttonStyle(.borderedProminent)
                        .tint(selectedCompany?.id == company.id ? InvestmentDesign.accent : .gray)
                }
            }
        }
    }

    private func metricGrid(_ metrics: [CompanyResearchMetric]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(metrics, id: \.label) { metric in
                VStack(alignment: .leading, spacing: 5) {
                    Text(metric.label).font(.caption).foregroundStyle(.secondary)
                    Text(metric.value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.72)
                    Text(metric.note).font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 15))
            }
        }
    }

    private func thesisCard(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("核心研究命题", systemImage: "lightbulb.max.fill").font(.headline)
            Text(company.thesis).font(.body).foregroundStyle(.secondary).lineSpacing(4)
        }
        .padding(18)
        .background(Color(red: 0.98, green: 0.94, blue: 0.84), in: RoundedRectangle(cornerRadius: 18))
    }

    private func shareholderReturnSection(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("股东回报与财报", systemImage: "calendar.badge.clock")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("最近回购", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.bold())
                    Spacer()
                    Text(company.buyback.status)
                        .font(.caption.bold())
                        .foregroundStyle(company.buyback.status.contains("完成") ? .green : .blue)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background((company.buyback.status.contains("完成") ? Color.green : Color.blue).opacity(0.1), in: Capsule())
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(company.buyback.amount).font(.title2.bold())
                    Text(company.buyback.shares).font(.caption).foregroundStyle(.secondary)
                }
                Text("截至 \(company.buyback.asOfDate) · \(company.buyback.percentage)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("成交区间 \(company.buyback.priceRange)").font(.subheadline)
                Text(company.buyback.progressNote).font(.caption).foregroundStyle(.secondary).lineSpacing(2)
                Link(destination: company.buyback.source.url) {
                    Label("查看回购公告", systemImage: "doc.text.magnifyingglass")
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(14)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 15))

            HStack(spacing: 13) {
                Image(systemName: "calendar")
                    .font(.title2).foregroundStyle(.purple)
                    .frame(width: 42, height: 42)
                    .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("下一财报 · \(company.nextReport.dateStatus)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(company.nextReport.expectedDate).font(.title3.bold())
                    Text(company.nextReport.reportType).font(.subheadline)
                    Text(company.nextReport.note).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private func bulletSection(_ title: String, icon: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(tint)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 11) {
                    Text("\(index + 1)").font(.caption.bold()).foregroundStyle(tint)
                        .frame(width: 24, height: 24).background(tint.opacity(0.12), in: Circle())
                    Text(item).font(.subheadline).lineSpacing(3)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private func sourcesSection(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("原始资料", systemImage: "doc.text.magnifyingglass").font(.headline)
            ForEach(company.sources, id: \.url) { source in
                Link(destination: source.url) {
                    HStack { Text(source.title); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(.subheadline.weight(.medium))
                }
            }
            Text("档案更新于 \(company.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1), in: Capsule())
    }
}
