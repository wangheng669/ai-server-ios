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
            VStack(alignment: .leading, spacing: 14) {
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
            .padding(.top, 6)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
        .background(HoldingsPalette.paper)
        .task { await load() }
        .refreshable { await load() }
    }

    private var industryPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(industries) { industry in
                    let selected = industry.id == selectedIndustry?.id
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { selectedID = industry.id }
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: industry.icon)
                                .font(.system(size: 22, weight: .semibold))
                                .frame(height: 30)
                            Text(industry.title)
                                .font(.system(size: 11, weight: selected ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selected ? HoldingsPalette.green : .secondary)
                        .frame(width: 72, height: 72)
                        .background(
                            selected ? HoldingsPalette.green.opacity(0.07) : .clear,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay {
                            if selected {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(HoldingsPalette.green.opacity(0.22))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func panorama(_ industry: IndustryPayload) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            scaleCard(industry)
            anchorStrip(industry)
            chainCard(industry)
            insightSection(industry)
            provenanceRow(industry)
        }
        .padding(.horizontal, 14)
        .animation(.easeOut(duration: 0.18), value: industry.id)
    }

    private func scaleCard(_ industry: IndustryPayload) -> some View {
        let parts = scaleValueParts(industry.scale.value)
        return VStack(alignment: .leading, spacing: 14) {
            Label("产业规模", systemImage: "chart.xyaxis.line")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(HoldingsPalette.ink)

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(industry.scale.period)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(parts.value)
                        .font(.system(size: 43, weight: .medium, design: .serif))
                        .foregroundStyle(HoldingsPalette.green)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(parts.unit)
                            .font(.system(size: 14, weight: .semibold))
                        if let growth = industry.scale.growth {
                            Text(growth)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(HoldingsPalette.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(HoldingsPalette.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(width: 130, alignment: .leading)

                if let history = industry.history, history.count >= 2 {
                    historyChart(history)
                        .frame(maxWidth: .infinity)
                        .frame(height: 132)
                }
            }

            HStack {
                Text(industry.scale.metric)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                sourceLink(industry.scale.source)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(HoldingsPalette.line))
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
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(HoldingsPalette.ink)
                }
        }
        .chartXAxis {
            AxisMarks(values: history.map { String($0.year) }) {
                AxisValueLabel().font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
        .chartYAxis(.hidden)
    }

    private func anchorStrip(_ industry: IndustryPayload) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(industry.anchors.enumerated()), id: \.offset) { index, anchor in
                    Label(anchor, systemImage: anchorIcon(index))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HoldingsPalette.ink)
                        .padding(.horizontal, 12)
                    if index != industry.anchors.indices.last {
                        Divider().frame(height: 20)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
    }

    private func chainCard(_ industry: IndustryPayload) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("产业链全景", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Text("企业映射")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 7) {
                ForEach(Array(industry.chain.enumerated()), id: \.element.id) { index, group in
                    chainColumn(group, companies: industry.companies.filter { $0.stageID == group.id }, index: index)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(HoldingsPalette.line))
    }

    private func chainColumn(
        _ group: IndustryPayload.ChainGroup,
        companies: [IndustryPayload.Company],
        index: Int
    ) -> some View {
        let color = chainColor(index)
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(group.level) · \(group.title)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .padding(.horizontal, 9)
                .background(color.opacity(0.07), in: arrowShape(index))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.offset) { itemIndex, item in
                    Label(item, systemImage: stageIcon(index, itemIndex))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HoldingsPalette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 7)
                    if itemIndex != group.items.indices.last {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 8)
            .background(color.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(color.opacity(0.18)))

            ForEach(companies) { company in
                companyCard(company, color: color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func companyCard(_ company: IndustryPayload.Company, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(company.monogram ?? String(company.name.prefix(2)))
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundStyle(color)
            Text(company.name)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
            if let ticker = company.ticker {
                Text(ticker)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(company.role)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(color.opacity(0.18)))
    }

    private func insightSection(_ industry: IndustryPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("产业观察", systemImage: "eye")
                .font(.system(size: 16, weight: .bold))

            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(industry.insights.enumerated()), id: \.element.id) { index, insight in
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: insightIcon(index))
                            .foregroundStyle(chainColor(index))
                        Text(insight.title)
                            .font(.system(size: 11, weight: .bold))
                        Text(insight.detail)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                    .padding(10)
                    .background(chainColor(index).opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(chainColor(index).opacity(0.12)))
                }
            }
        }
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
        .font(.system(size: 10))
        .padding(13)
        .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder
    private func sourceLink(_ source: IndustryPayload.Scale.Source) -> some View {
        if let url = source.url {
            Link(destination: url) {
                Label(source.name, systemImage: "arrow.up.right")
                    .labelStyle(.titleAndIcon)
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        } else {
            Text(source.name).font(.system(size: 9)).foregroundStyle(.secondary)
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

    private func stageIcon(_ column: Int, _ row: Int) -> String {
        let icons = [
            ["mountain.2", "circle.hexagongrid", "drop", "square.grid.3x3"],
            ["battery.100percent", "gearshape.2", "thermometer.medium", "car.side"],
            ["bolt.car", "building.2", "bolt", "wrench.and.screwdriver"]
        ]
        return icons[column % icons.count][row % icons[column % icons.count].count]
    }

    private func insightIcon(_ index: Int) -> String {
        ["chart.bar.xaxis", "leaf.circle", "bolt.car.circle"][index % 3]
    }

    private func chainColor(_ index: Int) -> Color {
        [Color(red: 0.74, green: 0.34, blue: 0.07), HoldingsPalette.green, HoldingsPalette.blue][index % 3]
    }

    private func arrowShape(_ index: Int) -> some InsettableShape {
        RoundedRectangle(cornerRadius: 9)
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
