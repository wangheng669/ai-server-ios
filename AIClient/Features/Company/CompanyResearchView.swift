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
            LazyVStack(alignment: .leading, spacing: 20) {
                if store.companies.count > 1 { companyPicker }
                hero(company)
                keyUpdatesCard(company)
                thesisCard(company)
                researchSection(company)
                sourcesSection(company)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .refreshable { await store.load(force: true) }
    }

    private func hero(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                companyLogo(company)
                VStack(alignment: .leading, spacing: 6) {
                    Text(company.shortName)
                        .font(.title2.bold())
                    Text("\(company.ticker)  ·  \(company.exchange)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(company.industry)
                    Text(company.location)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(company.tagline)
                .font(.body.weight(.medium))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 0) {
                ForEach(Array(company.metrics.enumerated()), id: \.element.label) { index, metric in
                    if index > 0 { Divider().frame(height: 36) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(metric.label).font(.caption2).foregroundStyle(.secondary)
                        Text(metric.value)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, index == 0 ? 0 : 14)
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var companyPicker: some View {
        HStack(spacing: 24) {
            ForEach(store.companies) { company in
                let isSelected = selectedCompany?.id == company.id
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selectedCompanyID = company.id }
                } label: {
                    Text(company.shortName)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? companyAccent(company) : Color.secondary)
                        .padding(.vertical, 9)
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(isSelected ? companyAccent(company) : .clear)
                                .frame(height: 3)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func thesisCard(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionEyebrow("核心判断")
            Text(company.thesis)
                .font(.title3.weight(.medium))
                .lineSpacing(6)
        }
        .padding(.vertical, 4)
    }

    private func keyUpdatesCard(_ company: CompanyResearchProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionEyebrow("关键进展")
                Spacer()
                Label(company.buyback.status, systemImage: company.buyback.status.contains("完成") ? "checkmark.circle.fill" : "clock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(companyAccent(company))
            }
            .padding(.bottom, 16)

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(companyAccent(company))
                    .frame(width: 38, height: 38)
                    .background(companyAccent(company).opacity(0.10), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 8) {
                    Text("累计回购").font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(company.buyback.amount).font(.title2.bold())
                        Text(company.buyback.percentage)
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Text("\(company.buyback.shares) · 成交区间 \(company.buyback.priceRange)")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(company.buyback.progressNote)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .lineSpacing(2)
                }
            }

            Divider().padding(.vertical, 16)

            HStack(spacing: 14) {
                Image(systemName: "calendar")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.purple)
                    .frame(width: 38, height: 38)
                    .background(Color.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text("下一财报 · \(company.nextReport.dateStatus)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(company.nextReport.reportType)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(reportDate(company.nextReport.expectedDate))
                        .font(.title3.bold())
                    Text("\(company.nextReport.expectedDate.prefix(4))年")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("数据截至 \(company.buyback.asOfDate)")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Link(destination: company.buyback.source.url) {
                    Label("查看公告", systemImage: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(companyAccent(company))
                }
            }
            .padding(.top, 16)
        }
        .padding(18)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20))
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
        AsyncImage(url: company.logoUrl) { phase in
            if case let .success(image) = phase {
                image
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            } else {
                Text(String(company.shortName.prefix(1)))
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 76, height: 48)
        .background(companyAccent(company), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        }
    }

    private func companyAccent(_ company: CompanyResearchProfile) -> Color {
        company.id == "wuliangye"
            ? Color(red: 0.08, green: 0.25, blue: 0.52)
            : Color(red: 0.52, green: 0.07, blue: 0.09)
    }

    private func reportDate(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3 else { return date }
        return "\(parts[1])月\(parts[2])日"
    }
}
