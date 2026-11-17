import SwiftUI

/// Immutable report captured at delivery time, not a live dashboard.
struct NativeNotificationReport: Decodable {
    let version: Int
    let kind: String
    let title: String
    let subtitle: String?
    let generatedAt: String?
    let sections: [Section]?

    enum CodingKeys: String, CodingKey {
        case version, kind, title, subtitle, sections
        case generatedAt = "generated_at"
    }

    struct Section: Decodable {
        let id: String
        let title: String?
        let text: String?
        let metrics: [Metric]?
        let rows: [Row]?
    }
    struct Metric: Decodable {
        let label: String
        let value: String
        let unit: String?
        let tone: String?
    }
    struct Row: Decodable {
        let id: String
        let title: String
        let subtitle: String?
        let value: String?
        let detail: String?
        let url: String?
        let imageURL: String?
        enum CodingKeys: String, CodingKey {
            case id, title, subtitle, value, detail, url
            case imageURL = "image_url"
        }
    }
}

struct NativeReportNotificationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let report: NativeNotificationReport
    let links: [PushNotificationDetails.Link]
    @State private var browser: InAppBrowserDestination?
    @State private var query = ""

    private var rowsCount: Int { (report.sections ?? []).reduce(0) { $0 + ($1.rows?.count ?? 0) } }
    private var style: ReportStyle { ReportStyle(kind: report.kind) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    introduction
                    if rowsCount > 8 { searchField }
                    ForEach(Array((report.sections ?? []).enumerated()), id: \.offset) { _, section in
                        sectionCard(section)
                    }
                    if !(report.sections ?? []).isEmpty && !query.isEmpty && !hasMatches {
                        ContentUnavailableView.search(text: query)
                    }
                    if !links.isEmpty { sourceLinks }
                }
                .padding(.horizontal, 20).padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(HoldingsPalette.canvas.ignoresSafeArea())
        .inAppBrowserCover(item: $browser)
        .accessibilityIdentifier("native-report-\(report.kind)")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: style.symbol).foregroundStyle(style.color)
            Text(style.label).font(.headline)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary).frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.1), in: Circle())
            }.accessibilityLabel("关闭报告")
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(HoldingsPalette.card)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(report.title).font(.system(.title, design: .rounded).bold())
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            if let subtitle = nonempty(report.subtitle) {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let date = nonempty(report.generatedAt) {
                Label(date, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索报告内容", text: $query).textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(.secondary).accessibilityLabel("清除搜索")
            }
        }.padding(12).background(HoldingsPalette.card, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private func sectionCard(_ section: NativeNotificationReport.Section) -> some View {
        let rows = matchingRows(section)
        let sectionMatches = query.isEmpty || matches(section.title) || matches(section.text)
        if sectionMatches || !rows.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                if let title = nonempty(section.title) {
                    Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                }
                if sectionMatches, let text = nonempty(section.text) {
                    Text(text).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if sectionMatches, let metrics = section.metrics, !metrics.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 130), alignment: .leading)], alignment: .leading, spacing: 14) {
                        ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                            metricCell(metric)
                        }
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider() }
                    reportRow(row)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(HoldingsPalette.card, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func metricCell(_ metric: NativeNotificationReport.Metric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.label).font(.caption).foregroundStyle(.secondary)
            Text(metric.value + (nonempty(metric.unit).map { " " + $0 } ?? ""))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(toneColor(metric.tone)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }

    private func reportRow(_ row: NativeNotificationReport.Row) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let url = webURL(row.imageURL) {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() }
                        placeholder: { Color.secondary.opacity(0.08) }
                        .frame(width: 48, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.title).font(.body.weight(.semibold)).textSelection(.enabled)
                    if let subtitle = nonempty(row.subtitle) {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if let value = nonempty(row.value) {
                        Text(value).font(.system(.headline, design: .rounded)).foregroundStyle(style.color).monospacedDigit().textSelection(.enabled)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let detail = nonempty(row.detail) {
                Text(detail).font(.body).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = webURL(row.url) {
                Button { browser = InAppBrowserDestination(url: url) } label: {
                    Label("查看来源", systemImage: "arrow.up.right").font(.subheadline.weight(.medium))
                        .padding(.vertical, 6)
                }.tint(style.color).accessibilityLabel("查看来源：\(row.title)")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("相关链接").font(.headline)
            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                if webURL(link.url.absoluteString) != nil {
                    Button { browser = InAppBrowserDestination(url: link.url) } label: {
                        HStack { Text(link.label); Spacer(); Image(systemName: "arrow.up.right") }
                    }.padding(.vertical, 6).tint(style.color)
                }
            }
        }.padding(18).background(HoldingsPalette.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func matchingRows(_ section: NativeNotificationReport.Section) -> [NativeNotificationReport.Row] {
        let all = section.rows ?? []
        if query.isEmpty || matches(section.title) || matches(section.text) { return all }
        return all.filter { matches($0.title) || matches($0.subtitle) || matches($0.detail) || matches($0.value) }
    }
    private var hasMatches: Bool {
        (report.sections ?? []).contains { matches($0.title) || matches($0.text) || !matchingRows($0).isEmpty }
    }
    private func matches(_ text: String?) -> Bool { text?.localizedCaseInsensitiveContains(query) ?? false }
    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
    private func webURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
    private func toneColor(_ tone: String?) -> Color {
        switch tone {
        case "positive": return HoldingsPalette.green
        case "negative": return HoldingsPalette.red
        case "warning": return HoldingsPalette.orange
        default: return style.color
        }
    }
}

private struct ReportStyle {
    let label: String
    let symbol: String
    let color: Color
    init(kind: String) {
        switch kind {
        case "memory-price": (label, symbol, color) = ("存储价格", "memorychip", HoldingsPalette.blue)
        case "ashare": (label, symbol, color) = ("A 股市场", "chart.line.uptrend.xyaxis", HoldingsPalette.blue)
        case "market-sentiment": (label, symbol, color) = ("市场情绪", "gauge.with.dots.needle.50percent", HoldingsPalette.orange)
        case "arxiv": (label, symbol, color) = ("论文日报", "doc.text.magnifyingglass", HoldingsPalette.purple)
        case "reading": (label, symbol, color) = ("每日读书", "book", HoldingsPalette.teal)
        case "ai-usage", "translation-cost": (label, symbol, color) = ("模型费用", "chart.bar.doc.horizontal", HoldingsPalette.orange)
        case "observability", "flash-health": (label, symbol, color) = ("运行提醒", "exclamationmark.shield", HoldingsPalette.orange)
        case "flash": (label, symbol, color) = ("快讯", "bolt", HoldingsPalette.blue)
        default: (label, symbol, color) = ("焦点报告", "doc.text", HoldingsPalette.blue)
        }
    }
}
