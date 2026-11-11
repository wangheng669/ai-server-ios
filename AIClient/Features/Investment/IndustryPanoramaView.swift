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
            let publishedAt: String?

            enum CodingKeys: String, CodingKey {
                case name, url
                case publishedAt = "published_at"
            }
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
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.httpStatus(http.statusCode) }
        let payload = try JSONDecoder().decode(IndustryPanoramaResponse.self, from: data)
        guard payload.success, !payload.data.industries.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return payload.data.industries
    }
}

struct IndustryMetricParts: Equatable {
    let qualifier: String
    let value: String
    let unit: String

    init(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: #"[0-9][0-9,.]*"#, options: .regularExpression) {
            qualifier = String(text[..<range.lowerBound])
            value = String(text[range])
            unit = String(text[range.upperBound...])
        } else {
            qualifier = ""
            value = text
            unit = ""
        }
    }
}

enum IndustryDataPresentation {
    static func monthLabel(_ period: String) -> String {
        let pieces = period.split(separator: "-")
        guard pieces.count == 2, let month = Int(pieces[1]), (1...12).contains(month) else { return period }
        return "\(pieces[0])年\(month)月"
    }

    static func monthlyChange(_ months: [IndustryPayload.AutoSales.Month], isNEV: Bool) -> Double? {
        let ordered = months.sorted { $0.period < $1.period }
        guard let latest = ordered.last, let previous = ordered.dropLast().last,
              let end = monthIndex(latest.period), let start = monthIndex(previous.period), end - start == 1 else { return nil }
        let currentValue = isNEV ? latest.nevSales : latest.totalSales
        let previousValue = isNEV ? previous.nevSales : previous.totalSales
        guard currentValue.isFinite, previousValue.isFinite, currentValue >= 0, previousValue > 0 else { return nil }
        return (currentValue / previousValue - 1) * 100
    }

    static func signedPercent(_ value: Double) -> String {
        (value >= 0 ? "+" : "") + value.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    private static func monthIndex(_ period: String) -> Int? {
        let pieces = period.split(separator: "-")
        guard pieces.count == 2, let year = Int(pieces[0]), let month = Int(pieces[1]), (1...12).contains(month) else { return nil }
        return year * 12 + month
    }
}

private enum IndustryPalette {
    static let canvas = Color(uiColor: .systemBackground)
    static let panel = Color(uiColor: .secondarySystemBackground)
    static let line = Color(uiColor: .separator).opacity(0.22)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.38, green: 0.84, blue: 0.73, alpha: 1)
            : UIColor(red: 0.04, green: 0.42, blue: 0.35, alpha: 1)
    })
    static let negative = Color.orange
}

private enum IndustryPane: String, CaseIterable {
    case overview = "总览", chain = "产业链", companies = "企业", research = "研究"
}

struct IndustryPanoramaView: View {
    var onClose: (() -> Void)?
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @State private var industries: [IndustryPayload] = []
    @State private var selectedID: String?
    @State private var pane: IndustryPane = .overview
    @State private var selectedStageID: String?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var selectedIndustry: IndustryPayload? {
        industries.first(where: { $0.id == selectedID }) ?? industries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if !industries.isEmpty {
                industryPicker
                panePicker
            }
            if let industry = selectedIndustry {
                TabView(selection: $pane) {
                    ForEach(IndustryPane.allCases, id: \.self) { page in
                        industryPage(industry, page: page)
                            .tag(page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .id(industry.id)
                .accessibilityIdentifier("industry-panorama-content")
            } else {
                ScrollView {
                    if isLoading {
                        ContentLoadingPlaceholder(title: "正在准备行业全景", rowCount: 4)
                            .padding(.horizontal, 22)
                    } else {
                        ContentUnavailableView {
                            Label("行业数据暂时不可用", systemImage: "chart.bar.xaxis")
                        } description: {
                            Text(errorMessage ?? "暂时没有可展示的行业数据")
                        } actions: {
                            Button("重新加载") { Task { await load() } }
                        }
                        .frame(minHeight: 360)
                    }
                }
                .refreshable { await load() }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if industries.isEmpty, let onClose {
                DetailSheetControls(closeLabel: "关闭行业全景", onClose: onClose)
                    .padding(12)
            }
        }
        .background(IndustryPalette.canvas)
        .tint(IndustryPalette.accent)
        .onChange(of: selectedID) { _, _ in selectedStageID = nil }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive, industries.isEmpty else { return }
            await load()
        }
    }

    private var industryPicker: some View {
        HStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(industries) { industry in
                            let selected = industry.id == selectedIndustry?.id
                            Button {
                                selectedID = industry.id
                            } label: {
                                Text(industry.title)
                                    .font(.subheadline.weight(selected ? .semibold : .medium))
                                    .foregroundStyle(selected ? IndustryPalette.canvas : .primary)
                                    .padding(.horizontal, 15)
                                    .frame(minHeight: 42)
                                    .background(selected ? IndustryPalette.accent : IndustryPalette.panel, in: Capsule())
                            }
                            .id(industry.id)
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.vertical, 10)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("industry-category-picker")
                .onChange(of: selectedID) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            Menu {
                ForEach(industries) { industry in
                    Button { selectedID = industry.id } label: {
                        if industry.id == selectedIndustry?.id {
                            Label(industry.title, systemImage: "checkmark")
                        } else {
                            Text(industry.title)
                        }
                    }
                }
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("全部行业")
            .accessibilityIdentifier("industry-directory")
            if let onClose {
                DetailSheetCloseButton(action: onClose, accessibilityLabel: "关闭行业全景")
            }
        }
        .padding(.trailing, 12)
    }

    private var panePicker: some View {
        HStack(spacing: 0) {
            ForEach(IndustryPane.allCases, id: \.self) { item in
                Button { withAnimation(.easeOut(duration: 0.22)) { pane = item } } label: {
                    VStack(spacing: 9) {
                        Text(item.rawValue)
                            .font(.subheadline.weight(pane == item ? .semibold : .regular))
                            .foregroundStyle(pane == item ? .primary : .secondary)
                        Capsule().fill(pane == item ? IndustryPalette.accent : .clear)
                            .frame(width: 26, height: 3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("industry-pane-\(item.rawValue)")
                .accessibilityAddTraits(pane == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) { IndustryPalette.line.frame(height: 0.5) }
    }

    private func industryHeading(_ industry: IndustryPayload) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(industry.title)
                    .font(.largeTitle.weight(.bold))
                    .tracking(-0.8)
                    .accessibilityIdentifier("industry-selected-title")
                Text(industry.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: industry.icon)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(IndustryPalette.accent)
                .frame(width: 56, height: 56)
                .background(IndustryPalette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func industryPage(_ industry: IndustryPayload, page: IndustryPane) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                industryHeading(industry)
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                paneContent(industry, page: page)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .refreshable { await load() }
        .accessibilityIdentifier("industry-page-\(page.rawValue)")
    }

    @ViewBuilder
    private func paneContent(_ industry: IndustryPayload, page: IndustryPane) -> some View {
        switch page {
        case .overview:
            IndustryOverview(industry: industry)
        case .chain:
            IndustryChain(industry: industry) { stage in
                selectedStageID = stage
                withAnimation(.easeOut(duration: 0.22)) { pane = .companies }
            }
        case .companies:
            IndustryCompanies(industry: industry, selectedStageID: $selectedStageID)
        case .research:
            IndustryResearch(industry: industry)
        }
    }

    @MainActor private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await IndustryPanoramaService().industries()
            guard !Task.isCancelled else { return }
            industries = loaded
            if selectedID == nil || !loaded.contains(where: { $0.id == selectedID }) { selectedID = loaded.first?.id }
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
            errorMessage = NetworkErrorPresentation.message(for: error)
        }
    }
}

private struct IndustryOverview: View {
    let industry: IndustryPayload
    @State private var showsMonthly = true
    @State private var salesMetric: AutoSalesMetric = .nev
    private var months: [IndustryPayload.AutoSales.Month] { (industry.autoSales?.monthly ?? []).sorted { $0.period < $1.period } }
    private var history: [IndustryPayload.HistoryPoint] { (industry.history ?? []).sorted { $0.year < $1.year } }
    private var isNEV: Bool { salesMetric == .nev }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if showsMonthly, let sales = industry.autoSales, let latest = months.last {
                monthlyHeadline(sales, latest: latest)
            } else {
                IndustryHeadline(
                    label: industry.scale.metric, period: industry.scale.period,
                    parts: IndustryMetricParts(industry.scale.value), growth: industry.scale.growth
                )
            }
            if !months.isEmpty || history.count > 1 {
                trendSection
            }
            if months.isEmpty || !showsMonthly {
                IndustrySourceNote(source: industry.scale.source, period: industry.scale.period)
            }
            if !industry.anchors.isEmpty {
                VStack(alignment: .leading, spacing: 13) {
                    IndustrySectionHeading(title: "关注环节", subtitle: "从业务理解这个行业")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                        ForEach(industry.anchors, id: \.self) { anchor in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(IndustryPalette.accent).frame(width: 5, height: 5).padding(.top, 7)
                                Text(anchor).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
            if months.isEmpty && history.count < 2 {
                Label("当前提供该统计期的规模数据，暂无连续历史序列。", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(IndustryPalette.panel, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func monthlyHeadline(_ sales: IndustryPayload.AutoSales, latest: IndustryPayload.AutoSales.Month) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            IndustryHeadline(
                label: isNEV ? "新能源汽车月销量" : "汽车月销量",
                period: IndustryDataPresentation.monthLabel(latest.period),
                parts: IndustryMetricParts((isNEV ? latest.nevSales : latest.totalSales).formatted(.number.precision(.fractionLength(1))) + sales.unit),
                growth: IndustryDataPresentation.signedPercent(isNEV ? latest.nevYoY : latest.totalYoY) + " 同比"
            )
            HStack(spacing: 0) {
                IndustrySecondaryMetric(
                    title: "销量环比",
                    value: IndustryDataPresentation.monthlyChange(months, isNEV: isNEV).map(IndustryDataPresentation.signedPercent) ?? "—"
                )
                IndustryPalette.line.frame(width: 1, height: 38).padding(.horizontal, 18)
                IndustrySecondaryMetric(title: "新能源渗透率", value: latest.nevPenetrationRate.formatted(.number.precision(.fractionLength(1))) + "%")
            }
            .padding(14)
            .background(IndustryPalette.panel, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("规模趋势").font(.title3.weight(.semibold))
                Spacer()
                if !months.isEmpty && history.count > 1 {
                    Picker("统计周期", selection: $showsMonthly) {
                        Text("月度").tag(true)
                        Text("年度").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 142)
                    .accessibilityIdentifier("industry-trend-period")
                }
            }
            if showsMonthly && !months.isEmpty, let sales = industry.autoSales {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sales.period).font(.subheadline.weight(.medium))
                        Text("单位：\(sales.unit)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("销量口径", selection: $salesMetric) {
                        ForEach(AutoSalesMetric.allCases) { item in Text(item.rawValue).tag(item) }
                    }
                    .pickerStyle(.menu)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("industry-sales-metric")
                }
                IndustryTrendChart(points: months.map {
                    IndustryTrendPoint(id: $0.period, label: String($0.period.suffix(2)) + "月", value: isNEV ? $0.nevSales : $0.totalSales)
                }, unit: sales.unit)
                IndustrySourceNote(source: sales.source, period: sales.period)
            } else if history.count > 1 {
                let parts = IndustryMetricParts(industry.scale.value)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(history.first!.year.description)—\(history.last!.year.description)")
                    Spacer()
                    Text("单位：\(parts.unit)")
                }
                .font(.caption).foregroundStyle(.secondary)
                IndustryTrendChart(points: history.map {
                    IndustryTrendPoint(id: String($0.year), label: String($0.year), value: $0.value)
                }, unit: parts.unit)
            }
        }
    }
}

private struct IndustryHeadline: View {
    let label: String
    let period: String
    let parts: IndustryMetricParts
    let growth: String?
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(period).font(.caption.weight(.medium)).foregroundStyle(IndustryPalette.accent)
                    .multilineTextAlignment(.trailing)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !parts.qualifier.isEmpty { Text(parts.qualifier).font(.title3).foregroundStyle(.secondary) }
                Text(parts.value)
                    .font(.system(size: numberSize, weight: .semibold, design: .rounded))
                    .tracking(-1.6).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityIdentifier("industry-primary-value")
                if !parts.unit.isEmpty {
                    Text(parts.unit).font(.title3.weight(.medium)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let growth {
                    HStack(spacing: 4) {
                        Image(systemName: growth.contains("-") || growth.contains("−") ? "arrow.down.right" : "arrow.up.right")
                        Text(growth)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(growth.contains("-") || growth.contains("−") ? IndustryPalette.negative : IndustryPalette.accent)
                    .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

private struct IndustrySecondaryMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IndustryTrendPoint: Identifiable {
    let id: String
    let label: String
    let value: Double
}

private struct IndustryTrendChart: View {
    let points: [IndustryTrendPoint]
    let unit: String
    private var ceiling: Double { max(1, (points.map(\.value).max() ?? 1) * 1.25) }

    var body: some View {
        Chart(points) { point in
            BarMark(x: .value("时期", point.label), y: .value("规模", point.value), width: .ratio(0.48))
                .cornerRadius(5)
                .foregroundStyle(point.id == points.last?.id ? IndustryPalette.accent : IndustryPalette.accent.opacity(0.28))
                .annotation(position: .top, spacing: 7) {
                    Text(point.value.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.caption.weight(.medium)).monospacedDigit()
                        .foregroundStyle(point.id == points.last?.id ? IndustryPalette.accent : .secondary)
                }
                .accessibilityLabel(point.label)
                .accessibilityValue(point.value.formatted() + unit)
        }
        .chartYScale(domain: 0...ceiling)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.caption).foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(IndustryPalette.line)
                AxisValueLabel().font(.caption2).foregroundStyle(Color.secondary)
            }
        }
        .frame(height: 186)
        .accessibilityIdentifier("industry-trend-chart")
    }
}

private struct IndustrySectionHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct IndustrySourceNote: View {
    let source: IndustryPayload.Scale.Source
    let period: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("来源")
                if let url = source.url {
                    Link(destination: url) {
                        Text(source.name) + Text(" ↗")
                    }
                } else { Text(source.name) }
            }
            .font(.caption).foregroundStyle(.secondary)
            Text("统计期：\(period)" + (source.publishedAt.map { "  ·  发布：" + String($0.prefix(10)) } ?? ""))
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IndustryChain: View {
    let industry: IndustryPayload
    let onShowCompanies: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            IndustrySectionHeading(title: "产业链结构", subtitle: "从供给到应用，共 \(industry.chain.count) 个环节。")
            ForEach(Array(industry.chain.enumerated()), id: \.element.id) { index, group in
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 10) {
                        Text(String(format: "%02d", index + 1))
                            .font(.subheadline.weight(.semibold).monospaced())
                            .foregroundStyle(IndustryPalette.accent)
                            .frame(width: 34, height: 34)
                            .background(IndustryPalette.accent.opacity(0.1), in: Circle())
                        Rectangle().fill(IndustryPalette.line).frame(width: 1)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(group.level).font(.caption.weight(.semibold)).foregroundStyle(IndustryPalette.accent)
                            Text(group.title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                            ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                                Text(item).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        let count = industry.companies.filter { $0.stageID == group.id }.count
                        if count > 0 {
                            Button { onShowCompanies(group.id) } label: {
                                HStack {
                                    Text("查看本环节企业 · \(count)")
                                    Image(systemName: "arrow.right")
                                }
                                .font(.subheadline.weight(.medium))
                                .frame(minHeight: 40)
                            }
                            .buttonStyle(.plain).foregroundStyle(IndustryPalette.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct IndustryCompanies: View {
    let industry: IndustryPayload
    @Binding var selectedStageID: String?
    private var companies: [IndustryPayload.Company] {
        guard let selectedStageID else { return industry.companies }
        return industry.companies.filter { $0.stageID == selectedStageID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            IndustrySectionHeading(title: "代表企业", subtitle: "按产业链环节查看，共收录 \(industry.companies.count) 家。")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    stageButton("全部", id: nil)
                    ForEach(industry.chain) { group in stageButton(group.level, id: group.id) }
                }
            }
            .scrollIndicators(.hidden)
            LazyVStack(spacing: 0) {
                ForEach(companies) { company in
                    HStack(alignment: .top, spacing: 13) {
                        Text(company.monogram ?? String(company.name.prefix(2)))
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(IndustryPalette.accent)
                            .frame(width: 48, height: 48)
                            .background(IndustryPalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(company.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                if let stage = industry.chain.first(where: { $0.id == company.stageID }) {
                                    Text(stage.level).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if let ticker = company.ticker {
                                Text(ticker).font(.caption.monospaced()).foregroundStyle(IndustryPalette.accent)
                            }
                            Text(company.role).font(.subheadline).foregroundStyle(.secondary)
                                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
                    .overlay(alignment: .bottom) { IndustryPalette.line.frame(height: 0.5) }
                }
            }
            if companies.isEmpty {
                Text("这个环节暂未收录代表企业。")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 20)
            }
        }
    }

    private func stageButton(_ title: String, id: String?) -> some View {
        Button { selectedStageID = id } label: {
            Text(title).font(.subheadline.weight(selectedStageID == id ? .semibold : .regular))
                .foregroundStyle(selectedStageID == id ? IndustryPalette.canvas : .primary)
                .padding(.horizontal, 17).frame(minHeight: 40)
                .background(selectedStageID == id ? IndustryPalette.accent : IndustryPalette.panel, in: Capsule())
        }
        .buttonStyle(.plain).accessibilityAddTraits(selectedStageID == id ? .isSelected : [])
    }
}

private struct IndustryResearch: View {
    let industry: IndustryPayload
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            IndustrySectionHeading(title: "研究观察", subtitle: "建立理解行业的线索")
            ForEach(industry.insights) { insight in
                VStack(alignment: .leading, spacing: 10) {
                    Text(insight.title).font(.title3.weight(.semibold))
                    Text(insight.detail).font(.body).foregroundStyle(.secondary)
                        .lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                .overlay(alignment: .leading) { IndustryPalette.accent.opacity(0.35).frame(width: 3) }
            }
            Divider().padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 15) {
                IndustrySectionHeading(title: "数据来源与口径", subtitle: "原始发布机构与参考资料")
                IndustrySourceNote(source: industry.scale.source, period: industry.scale.period)
                if let sales = industry.autoSales { IndustrySourceNote(source: sales.source, period: sales.period) }
                ForEach(Array(industry.provenance.enumerated()), id: \.offset) { _, item in
                    Label(item, systemImage: "checkmark.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview { IndustryPanoramaView() }
