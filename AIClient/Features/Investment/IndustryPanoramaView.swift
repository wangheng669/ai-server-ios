import Charts
import SwiftUI

struct IndustryPanoramaResponse: Decodable {
    let success: Bool
    let data: IndustryPanoramaData
}

struct IndustryPanoramaData: Decodable {
    let version: String
    let industries: [IndustryPayload]
}

struct IndustryPayload: Decodable, Identifiable {
    struct Scale: Decodable {
        struct Source: Decodable {
            let name: String
            let url: URL?
        }

        let value: String
        let metric: String
        let period: String
        let growth: String?
        let source: Source
    }

    struct HistoryPoint: Decodable, Identifiable {
        let year: Int
        let value: Double
        let sourceURL: URL?

        var id: Int { year }

        enum CodingKeys: String, CodingKey {
            case year, value
            case sourceURL = "source_url"
        }
    }

    struct Company: Decodable, Identifiable {
        let id: String
        let name: String
        let monogram: String?
        let role: String
        let stageID: String?
        let ticker: String?

        enum CodingKeys: String, CodingKey {
            case id, name, monogram, role, ticker
            case stageID = "stage_id"
        }
    }

    struct ChainGroup: Decodable, Identifiable {
        let id: String
        let level: String
        let title: String
        let items: [String]
    }

    struct Insight: Decodable, Identifiable {
        let id: String
        let title: String
        let detail: String
    }

    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let scale: Scale
    let history: [HistoryPoint]?
    let anchors: [String]
    let chain: [ChainGroup]
    let companies: [Company]
    let insights: [Insight]
    let provenance: [String]
}

private struct IndustryPanoramaService {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = ServerConfiguration.currentURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func industries() async throws -> [IndustryPayload] {
        let url = baseURL.appending(path: "api/v1/industries/panorama")
        var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(IndustryPanoramaResponse.self, from: data)
        guard payload.success, !payload.data.industries.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return payload.data.industries
    }
}

struct IndustryPanoramaView: View {
    @State private var industries: [IndustryPayload] = []
    @State private var selectedID: String?
    @State private var isLoading = true
    @State private var loadError = false

    private var selectedIndustry: IndustryPayload? {
        industries.first(where: { $0.id == selectedID }) ?? industries.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !industries.isEmpty {
                    industryPicker
                }

                if let industry = selectedIndustry {
                    panorama(industry)
                } else if isLoading {
                    loadingState
                } else {
                    errorState
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
        .background(HoldingsPalette.paper)
        .task { await load() }
        .refreshable { await load() }
    }

    private var industryPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 30) {
                ForEach(industries) { industry in
                    let selected = industry.id == selectedIndustry?.id
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { selectedID = industry.id }
                    } label: {
                        VStack(spacing: 11) {
                            Text(industry.title)
                                .font(.system(size: 14, weight: selected ? .semibold : .regular))
                                .lineLimit(1)
                            Capsule()
                                .fill(selected ? HoldingsPalette.green : .clear)
                                .frame(width: 16, height: 2)
                        }
                        .foregroundStyle(selected ? HoldingsPalette.green : HoldingsPalette.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 9)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HoldingsPalette.line)
                .frame(height: 1)
        }
    }

    private func panorama(_ industry: IndustryPayload) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            scaleCard(industry)
            chainCard(industry)
            provenanceRow(industry)
        }
        .padding(.horizontal, 16)
        .animation(.easeOut(duration: 0.18), value: industry.id)
    }

    private func scaleCard(_ industry: IndustryPayload) -> some View {
        let parts = scaleValueParts(industry.scale.value)
        return VStack(alignment: .leading, spacing: 18) {
            sectionHeading(number: "01", title: "产业规模")

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 22) {
                    scaleSummary(parts: parts, industry: industry)
                        .frame(width: 148, alignment: .leading)

                    if let history = industry.history, history.count >= 2 {
                        historyChart(history)
                            .frame(maxWidth: .infinity)
                            .frame(height: 142)
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    scaleSummary(parts: parts, industry: industry)
                    if let history = industry.history, history.count >= 2 {
                        historyChart(history)
                            .frame(height: 150)
                    }
                }
            }

            HStack {
                Text(industry.scale.metric)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                sourceLink(industry.scale.source)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 10)
    }

    private func scaleSummary(
        parts: (value: String, unit: String),
        industry: IndustryPayload
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(industry.scale.period)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(parts.value)
                .font(.system(size: 48, weight: .medium, design: .serif))
                .foregroundStyle(HoldingsPalette.green)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(parts.unit)
                    .font(.system(size: 15, weight: .semibold))
                if let growth = industry.scale.growth {
                    Label(growth, systemImage: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(HoldingsPalette.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(HoldingsPalette.green.opacity(0.28)))
                }
            }
        }
    }

    private func historyChart(_ history: [IndustryPayload.HistoryPoint]) -> some View {
        Chart(history) { point in
            AreaMark(x: .value("年份", String(point.year)), y: .value("规模", point.value))
                .foregroundStyle(
                    LinearGradient(
                        colors: [HoldingsPalette.green.opacity(0.2), HoldingsPalette.green.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            LineMark(x: .value("年份", String(point.year)), y: .value("规模", point.value))
                .foregroundStyle(HoldingsPalette.green)
                .lineStyle(StrokeStyle(lineWidth: 1.7))
            PointMark(x: .value("年份", String(point.year)), y: .value("规模", point.value))
                .foregroundStyle(HoldingsPalette.green)
                .symbolSize(28)
                .annotation(position: .top, spacing: 3) {
                    Text(point.value.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(HoldingsPalette.ink)
                }
        }
        .chartXAxis {
            AxisMarks(values: history.map { String($0.year) }) {
                AxisValueLabel().font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .chartYAxis(.hidden)
    }

    private func anchorStrip(_ industry: IndustryPayload) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
            ForEach(Array(industry.anchors.enumerated()), id: \.offset) { index, anchor in
                HStack(spacing: 8) {
                    Image(systemName: anchorIcon(index))
                        .foregroundStyle(HoldingsPalette.green)
                        .frame(width: 24)
                    Text(anchor)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HoldingsPalette.ink)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 11))
                .overlay {
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(HoldingsPalette.line)
                    }
            }
        }
    }

    private func chainCard(_ industry: IndustryPayload) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                sectionHeading(number: "02", title: "产业链全景")
                Text("垂直整合分工明确，协同驱动产业价值链跃升")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            VStack(spacing: 0) {
                ForEach(Array(industry.chain.enumerated()), id: \.element.id) { index, group in
                    chainRow(
                        group,
                        companies: industry.companies.filter { $0.stageID == group.id },
                        index: index,
                        isLast: index == industry.chain.count - 1
                    )
                }
            }
        }
        .padding(.top, 18)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(HoldingsPalette.line)
                .frame(height: 1)
        }
    }

    private func chainRow(
        _ group: IndustryPayload.ChainGroup,
        companies: [IndustryPayload.Company],
        index: Int,
        isLast: Bool
    ) -> some View {
        let color = chainColor(index)
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text(group.level)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(color, in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.55), chainColor(index + 1).opacity(0.45)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2)
                        .frame(minHeight: 190)
                }
            }

            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(HoldingsPalette.ink)
                    Text(group.items.joined(separator: "  ·  "))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(color)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(color.opacity(0.16)))

                if companies.isEmpty {
                    Text("代表企业数据更新中")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: min(companies.count, 2)),
                        spacing: 10
                    ) {
                        ForEach(companies) { company in
                            companyCard(company, color: color)
                        }
                    }
                }
            }
            .padding(.bottom, isLast ? 0 : 18)
        }
    }

    private func companyCard(_ company: IndustryPayload.Company, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(company.monogram ?? String(company.name.prefix(2)))
                .font(.system(size: 12, weight: .bold, design: .serif))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.18)))

            VStack(alignment: .leading, spacing: 3) {
                Text(company.name)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                if let ticker = company.ticker {
                    Text(ticker)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(company.role)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.16)))
    }

    private func insightSection(_ industry: IndustryPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("产业观察", systemImage: "eye")
                .font(.system(size: 16, weight: .bold))

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(industry.insights.enumerated()), id: \.element.id) { index, insight in
                        insightCard(insight, index: index)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func insightCard(_ insight: IndustryPayload.Insight, index: Int) -> some View {
        let color = chainColor(index)
        return VStack(alignment: .leading, spacing: 6) {
            Image(systemName: insightIcon(index))
                .foregroundStyle(color)
            Text(insight.title)
                .font(.system(size: 13, weight: .bold))
            Text(insight.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .frame(width: 185, alignment: .topLeading)
        .frame(minHeight: 108, alignment: .topLeading)
        .padding(12)
        .background(color.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.12)))
    }

    private func provenanceRow(_ industry: IndustryPayload) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.shield")
            Text("数据口径与来源")
                .fontWeight(.semibold)
            Text(industry.provenance.joined(separator: " / "))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
        }
        .font(.system(size: 11))
        .padding(14)
        .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder
    private func sourceLink(_ source: IndustryPayload.Scale.Source) -> some View {
        if let url = source.url {
            Link(destination: url) {
                Label(source.name, systemImage: "arrow.up.right")
                    .labelStyle(.titleAndIcon)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        } else {
            Text(source.name).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在加载产业数据")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("产业数据暂时不可用")
                .font(.system(size: 15, weight: .semibold))
            Button("重新加载") { Task { await load() } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .accessibilityLabel(loadError ? "产业数据加载失败" : "产业数据为空")
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await IndustryPanoramaService().industries()
            industries = loaded
            if selectedID == nil || !loaded.contains(where: { $0.id == selectedID }) {
                selectedID = loaded.first?.id
            }
            loadError = false
        } catch {
            industries = []
            loadError = true
#if DEBUG
            print("[IndustryPanorama] load failed: \(error)")
#endif
        }
    }

    private func scaleValueParts(_ value: String) -> (value: String, unit: String) {
        for unit in ["万亿元", "亿元", "亿块", "万辆", "万家", "家"] where value.hasSuffix(unit) {
            return (String(value.dropLast(unit.count)), unit)
        }
        return (value, "")
    }

    private func anchorIcon(_ index: Int) -> String {
        ["battery.100percent", "gearshape.2", "car.side", "bolt.car"][index % 4]
    }

    private func insightIcon(_ index: Int) -> String {
        ["chart.bar.xaxis", "leaf.circle", "bolt.car.circle"][index % 3]
    }

    private func chainColor(_ index: Int) -> Color {
        [Color(red: 0.74, green: 0.34, blue: 0.07), HoldingsPalette.green, HoldingsPalette.blue][index % 3]
    }

    private func sectionHeading(number: String, title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(number)
                .font(.system(size: 31, weight: .medium, design: .serif))
                .foregroundStyle(HoldingsPalette.green)
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(HoldingsPalette.ink)
        }
    }

}

private extension HoldingsPalette {
    static let paper = Color(red: 0.975, green: 0.972, blue: 0.958)
    static let ink = Color(red: 0.09, green: 0.12, blue: 0.15)
    static let line = Color.black.opacity(0.08)
}

#Preview {
    IndustryPanoramaView()
}
