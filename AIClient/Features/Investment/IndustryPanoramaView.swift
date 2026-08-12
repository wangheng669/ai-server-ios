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

    struct AutoSales: Decodable {
        struct Month: Decodable, Identifiable {
            let period: String
            let totalSales: Double
            let nevSales: Double
            let totalYoY: Double
            let nevYoY: Double
            let nevPenetrationRate: Double

            var id: String { period }

            enum CodingKeys: String, CodingKey {
                case period
                case totalSales = "total_sales"
                case nevSales = "nev_sales"
                case totalYoY = "total_yoy"
                case nevYoY = "nev_yoy"
                case nevPenetrationRate = "nev_penetration_rate"
            }
        }

        let period: String
        let unit: String
        let source: Scale.Source
        let monthly: [Month]
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
    let autoSales: AutoSales?
    let anchors: [String]
    let chain: [ChainGroup]
    let companies: [Company]
    let insights: [Insight]
    let provenance: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, icon, scale, history, anchors, chain, companies, insights, provenance
        case autoSales = "auto_sales"
    }
}

private enum AutoSalesMetric: String, CaseIterable, Identifiable {
    case total = "全部汽车"
    case nev = "新能源汽车"

    var id: Self { self }
}

private struct IndustryPanoramaService {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = ServerConfiguration.currentURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func industries() async throws -> [IndustryPayload] {
        let url = baseURL.appending(path: "api/ios/v1/industries/panorama")
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
    @State private var selectedStageID: String?
    @State private var isLoading = true
    @State private var loadError = false
    @State private var autoSalesMetric: AutoSalesMetric = .nev

    private var selectedIndustry: IndustryPayload? {
        industries.first(where: { $0.id == selectedID }) ?? industries.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
            .padding(.bottom, 112)
        }
        .scrollIndicators(.hidden)
        .background(InvestmentDesign.canvas)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: selectedID) { _, _ in
            selectedStageID = nil
        }
    }

    private var industryPicker: some View {
        VStack(spacing: 0) {
            HStack {
                Text("重点产业")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let selectedIndex = industries.firstIndex(where: { $0.id == selectedIndustry?.id }) {
                    Text("\(selectedIndex + 1) / \(industries.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 26) {
                        ForEach(industries) { industry in
                            let selected = industry.id == selectedIndustry?.id
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selectedID = industry.id
                                    proxy.scrollTo(industry.id, anchor: .center)
                                }
                            } label: {
                                VStack(spacing: 9) {
                                    Text(industry.title)
                                        .font(.system(size: 14, weight: selected ? .semibold : .regular))
                                        .lineLimit(1)
                                    Capsule()
                                        .fill(selected ? InvestmentDesign.accent : .clear)
                                        .frame(width: 18, height: 2)
                                }
                                .foregroundStyle(selected ? Color.primary : Color.secondary)
                                .contentShape(Rectangle())
                            }
                            .id(industry.id)
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(InvestmentDesign.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HoldingsPalette.line)
                .frame(height: 1)
        }
    }

    private func panorama(_ industry: IndustryPayload) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            industryIntroduction(industry)
            scaleSection(industry)
            if let sales = industry.autoSales, !sales.monthly.isEmpty {
                autoSalesSection(sales)
            }
            chainSection(industry)
            companySection(industry)
            if !industry.insights.isEmpty {
                insightSection(industry)
            }
            provenanceSection(industry)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .animation(.easeOut(duration: 0.18), value: industry.id)
    }

    private func industryIntroduction(_ industry: IndustryPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(industry.scale.period)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(InvestmentDesign.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(InvestmentDesign.accentSoft, in: Capsule())

            Text(industry.subtitle)
                .font(.system(size: 14))
                .foregroundStyle(HoldingsPalette.ink.opacity(0.68))
                .lineSpacing(4)

            if !industry.anchors.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(industry.anchors.enumerated()), id: \.offset) { index, anchor in
                            Label(anchor, systemImage: anchorIcon(index))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(HoldingsPalette.ink.opacity(0.8))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(InvestmentDesign.surface, in: Capsule())
                                .overlay(Capsule().stroke(HoldingsPalette.line))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func scaleSection(_ industry: IndustryPayload) -> some View {
        let parts = scaleValueParts(industry.scale.value)
        let history = industry.history ?? []

        return sectionContainer(number: "01", title: "规模与趋势") {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(industry.scale.metric)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(HoldingsPalette.ink.opacity(0.72))
                        Spacer()
                        sourceLink(industry.scale.source)
                    }

                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(parts.value)
                            .font(.system(size: 42, weight: .semibold, design: .rounded))
                            .foregroundStyle(InvestmentDesign.accent)
                            .minimumScaleFactor(0.62)
                            .lineLimit(1)
                        if !parts.unit.isEmpty {
                            Text(parts.unit)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(HoldingsPalette.ink)
                                .padding(.bottom, 5)
                        }
                        Spacer(minLength: 4)
                        if let growth = industry.scale.growth {
                            Label(growth, systemImage: growth.contains("-") ? "arrow.down.right" : "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(growth.contains("-") ? Color.red : HoldingsPalette.green)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(
                                    (growth.contains("-") ? Color.red : HoldingsPalette.green).opacity(0.07),
                                    in: Capsule()
                                )
                        }
                    }
                }

                if history.count >= 2 {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("历史变化")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text("\(String(history.first?.year ?? 0))–\(String(history.last?.year ?? 0))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        historyChart(history)
                            .frame(height: 176)
                    }
                    .padding(.top, 2)
                } else {
                    HStack(spacing: 9) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(InvestmentDesign.accent)
                        Text("该指标暂无连续可比历史序列，当前仅展示权威机构已发布的最新值。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                    .padding(12)
                    .background(InvestmentDesign.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(16)
            .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius).stroke(HoldingsPalette.line))
        }
    }

    private func historyChart(_ history: [IndustryPayload.HistoryPoint]) -> some View {
        Chart(history) { point in
            AreaMark(
                x: .value("年份", String(point.year)),
                y: .value("规模", point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [InvestmentDesign.accent.opacity(0.2), InvestmentDesign.accent.opacity(0.015)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("年份", String(point.year)),
                y: .value("规模", point.value)
            )
            .foregroundStyle(InvestmentDesign.accent)
            .lineStyle(StrokeStyle(lineWidth: 2))

            PointMark(
                x: .value("年份", String(point.year)),
                y: .value("规模", point.value)
            )
            .foregroundStyle(InvestmentDesign.accent)
            .symbolSize(34)
            .annotation(position: .top, spacing: 5) {
                Text(point.value.formatted(.number.precision(.fractionLength(0...1))))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(HoldingsPalette.ink)
            }
        }
        .chartXAxis {
            AxisMarks(values: history.map { String($0.year) }) {
                AxisGridLine().foregroundStyle(HoldingsPalette.line)
                AxisValueLabel()
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(HoldingsPalette.line)
                AxisValueLabel()
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func autoSalesSection(_ sales: IndustryPayload.AutoSales) -> some View {
        let latest = sales.monthly.last
        let previous = sales.monthly.dropLast().last
        let latestValue = latest.map { autoSalesMetric == .nev ? $0.nevSales : $0.totalSales } ?? 0
        let previousValue = previous.map { autoSalesMetric == .nev ? $0.nevSales : $0.totalSales }
        let yoy = latest.map { autoSalesMetric == .nev ? $0.nevYoY : $0.totalYoY } ?? 0
        let mom = previousValue.map { latestValue / $0 * 100 - 100 }

        return sectionContainer(number: "02", title: "汽车市场月报") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(sales.period)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    sourceLink(sales.source)
                }

                Picker("销量口径", selection: $autoSalesMetric) {
                    ForEach(AutoSalesMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    autoSalesStat(title: "最新月销量", value: "\(latestValue.formatted(.number.precision(.fractionLength(1))))\(sales.unit)", tint: InvestmentDesign.accent)
                    autoSalesStat(title: "同比", value: signedPercent(yoy), tint: yoy >= 0 ? HoldingsPalette.green : .red)
                    autoSalesStat(title: "环比", value: mom.map(signedPercent) ?? "—", tint: (mom ?? 0) >= 0 ? HoldingsPalette.green : .red)
                }

                Chart(sales.monthly) { point in
                    let value = autoSalesMetric == .nev ? point.nevSales : point.totalSales
                    AreaMark(
                        x: .value("月份", point.period),
                        y: .value("销量", value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [InvestmentDesign.accent.opacity(0.2), InvestmentDesign.accent.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("月份", point.period),
                        y: .value("销量", value)
                    )
                    .foregroundStyle(InvestmentDesign.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.2))
                }
                .chartXAxis {
                    AxisMarks(values: sales.monthly.enumerated().compactMap { index, item in
                        index.isMultiple(of: 2) ? item.period : nil
                    }) { value in
                        AxisGridLine().foregroundStyle(HoldingsPalette.line)
                        AxisValueLabel {
                            if let period = value.as(String.self) {
                                Text(String(period.suffix(2)) + "月")
                            }
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(HoldingsPalette.line)
                        AxisValueLabel().font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 190)

                if let latest {
                    HStack {
                        Label("新能源渗透率", systemImage: "bolt.car.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(HoldingsPalette.ink.opacity(0.72))
                        Spacer()
                        Text("\(latest.nevPenetrationRate.formatted(.number.precision(.fractionLength(1))))%")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(InvestmentDesign.accent)
                    }
                    .padding(12)
                    .background(InvestmentDesign.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(16)
            .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius).stroke(HoldingsPalette.line))
        }
    }

    private func autoSalesStat(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func signedPercent(_ value: Double) -> String {
        String(format: "%@%.1f%%", value >= 0 ? "+" : "", value)
    }

    private func chainSection(_ industry: IndustryPayload) -> some View {
        sectionContainer(number: "03", title: "产业链全景") {
            VStack(spacing: 12) {
                ForEach(Array(industry.chain.enumerated()), id: \.element.id) { index, group in
                    chainStage(group, companyCount: industry.companies.filter { $0.stageID == group.id }.count, index: index)
                }
            }
        }
    }

    private func chainStage(
        _ group: IndustryPayload.ChainGroup,
        companyCount: Int,
        index: Int
    ) -> some View {
        let color = chainColor(index)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text(group.level)
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 34)
                    .background(color, in: Capsule())

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(HoldingsPalette.ink)
                    Text("\(group.items.count) 个关键环节 · \(companyCount) 家代表企业")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .foregroundStyle(color.opacity(0.45))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(group.items.enumerated()), id: \.offset) { itemIndex, item in
                    HStack(spacing: 7) {
                        Image(systemName: chainItemIcon(index: index, itemIndex: itemIndex))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(color)
                            .frame(width: 22, height: 22)
                            .background(color.opacity(0.09), in: Circle())
                        Text(item)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(HoldingsPalette.ink.opacity(0.82))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                    .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(HoldingsPalette.line))
                }
            }
        }
        .padding(15)
        .background(color.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(color.opacity(0.16)))
    }

    private func companySection(_ industry: IndustryPayload) -> some View {
        let filteredCompanies = selectedStageID.map { stageID in
            industry.companies.filter { $0.stageID == stageID }
        } ?? industry.companies

        return sectionContainer(number: "04", title: "代表企业") {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal) {
                    HStack(spacing: 18) {
                        stageFilterButton(title: "全部", id: nil, count: industry.companies.count)
                        ForEach(industry.chain) { group in
                            stageFilterButton(
                                title: group.level,
                                id: group.id,
                                count: industry.companies.filter { $0.stageID == group.id }.count
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)

                LazyVStack(spacing: 10) {
                    ForEach(filteredCompanies) { company in
                        companyRow(company, industry: industry)
                    }
                }
            }
        }
    }

    private func stageFilterButton(title: String, id: String?, count: Int) -> some View {
        let selected = selectedStageID == id
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selectedStageID = id
            }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(selected ? InvestmentDesign.accent.opacity(0.75) : Color.secondary.opacity(0.55))
            }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? InvestmentDesign.accent : HoldingsPalette.ink.opacity(0.7))
            .padding(.bottom, 7)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(selected ? InvestmentDesign.accent : .clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func companyRow(_ company: IndustryPayload.Company, industry: IndustryPayload) -> some View {
        let stageIndex = industry.chain.firstIndex(where: { $0.id == company.stageID }) ?? 0
        let stage = industry.chain.first(where: { $0.id == company.stageID })
        let color = chainColor(stageIndex)

        return HStack(spacing: 12) {
            Text(company.monogram ?? String(company.name.prefix(2)))
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundStyle(color)
                .frame(width: 46, height: 46)
                .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(color.opacity(0.2)))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(company.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(HoldingsPalette.ink)
                    if let ticker = company.ticker {
                        Text(ticker)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(HoldingsPalette.line, in: Capsule())
                    }
                }
                Text(company.role)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let stage {
                Text(stage.level)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(color.opacity(0.07), in: Capsule())
            }
        }
        .padding(13)
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(HoldingsPalette.line))
    }

    private func insightSection(_ industry: IndustryPayload) -> some View {
        sectionContainer(number: "05", title: "研究观察") {
            VStack(spacing: 10) {
                ForEach(Array(industry.insights.enumerated()), id: \.element.id) { index, insight in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: insightIcon(index))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(chainColor(index))
                            .frame(width: 34, height: 34)
                            .background(chainColor(index).opacity(0.08), in: Circle())

                        VStack(alignment: .leading, spacing: 5) {
                            Text(insight.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(HoldingsPalette.ink)
                            Text(insight.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(HoldingsPalette.line))
                }
            }
        }
    }

    private func provenanceSection(_ industry: IndustryPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("数据口径与来源", systemImage: "checkmark.shield")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HoldingsPalette.ink)

            ForEach(Array(industry.provenance.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(InvestmentDesign.accent)
                        .frame(width: 4, height: 4)
                        .padding(.top, 6)
                    Text(item)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 13))
    }

    private func sectionContainer<Content: View>(
        number: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(number)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(InvestmentDesign.accent)
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(HoldingsPalette.ink)
            }
            content()
        }
    }

    @ViewBuilder
    private func sourceLink(_ source: IndustryPayload.Scale.Source) -> some View {
        if let url = source.url {
            Link(destination: url) {
                Label(source.name, systemImage: "arrow.up.right")
                    .labelStyle(.titleAndIcon)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        } else {
            Text(source.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
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
        for unit in ["万亿元", "亿元", "亿块", "万辆", "万家", "万架", "万台", "万颗", "次", "家"]
        where value.hasSuffix(unit) {
            return (String(value.dropLast(unit.count)), unit)
        }
        return (value, "")
    }

    private func anchorIcon(_ index: Int) -> String {
        ["scope", "point.3.connected.trianglepath.dotted", "building.2", "chart.line.uptrend.xyaxis"][index % 4]
    }

    private func insightIcon(_ index: Int) -> String {
        ["chart.bar.xaxis", "scope", "shield.checkered"][index % 3]
    }

    private func chainItemIcon(index: Int, itemIndex: Int) -> String {
        let icons = [
            ["cube.fill", "circle.grid.2x2.fill", "shippingbox.fill", "drop.fill", "square.stack.3d.up.fill", "bolt.fill"],
            ["gearshape.2.fill", "cpu.fill", "square.3.layers.3d", "wrench.and.screwdriver.fill", "building.2.fill"],
            ["network", "antenna.radiowaves.left.and.right", "server.rack", "chart.xyaxis.line", "person.2.fill"]
        ]
        let group = icons[index % icons.count]
        return group[itemIndex % group.count]
    }

    private func chainColor(_ index: Int) -> Color {
        [Color(red: 0.72, green: 0.34, blue: 0.08), HoldingsPalette.green, HoldingsPalette.blue][index % 3]
    }
}

private extension HoldingsPalette {
    static let paper = InvestmentDesign.canvas
    static let ink = Color.primary
    static let line = InvestmentDesign.divider
}

#Preview {
    IndustryPanoramaView()
}
