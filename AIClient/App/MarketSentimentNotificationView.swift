import SwiftUI

struct MarketSentimentNotificationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize = 64.0
    @State private var selectedDays = "20"
    @State private var browser: InAppBrowserDestination?

    let report: NativeNotificationReport
    let links: [PushNotificationDetails.Link]

    private typealias Section = NativeNotificationReport.Section
    private typealias Row = NativeNotificationReport.Row

    private let accent = Color(red: 0.14, green: 0.33, blue: 0.55)
    private var summary: Section? { section("summary") }
    private var history: Section? { section("history") }
    private var source: Section? { section("source") }
    private var backtest: Section? { section("backtest-meta") }
    private var buyReference: Section? { section("current-buy") }
    private var staleMessage: String? {
        summary?.text?.components(separatedBy: .newlines).first { $0.hasPrefix("数据已过期") }
    }
    private var sourceTime: String? {
        source?.text?.components(separatedBy: .newlines).first { $0.hasPrefix("更新时间 ") }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(report.title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(InvestmentDesign.surface)
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let staleMessage {
                        Label(staleMessage, systemImage: "clock.badge.exclamationmark")
                            .font(.subheadline.weight(.medium))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
                    }
                    indexCard
                    if let backtest { backtestCard(backtest) }
                    if let stocks = populatedSection("stocks") {
                        panel {
                            heading("市场行情")
                            reportRows(stocks.rows ?? [], showDetailBesideValue: true)
                        }
                    }
                    if history != nil || populatedSection("trend") != nil || populatedSection("indicators") != nil {
                        panel {
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 16) {
                                    if let text = summary?.text {
                                        notes(text.components(separatedBy: .newlines)
                                            .filter { $0 != staleMessage }.joined(separator: "\n"))
                                    }
                                    if let history { sectionDetails(history) }
                                    if let trend = populatedSection("trend") { sectionDetails(trend) }
                                    if let indicators = populatedSection("indicators") { sectionDetails(indicators) }
                                }
                                .padding(.top, 12)
                            } label: {
                                heading("指数历史与情绪指标")
                            }
                        }
                    }
                    if source != nil || !links.isEmpty {
                        panel {
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 10) {
                                    if let text = source?.text { notes(text) }
                                    ForEach(links, id: \.self) { link in
                                        Button {
                                            browser = InAppBrowserDestination(url: link.url)
                                        } label: {
                                            Label(link.label, systemImage: "arrow.up.right")
                                                .font(.subheadline.weight(.medium))
                                        }
                                    }
                                }
                                .padding(.top, 12)
                            } label: {
                                heading("数据来源与说明")
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 60)
            }
        }
        .tint(accent)
        .background(InvestmentDesign.canvas.ignoresSafeArea())
        .floatingSheetClose("关闭报告", action: dismiss.callAsFunction)
        .inAppBrowserCover(item: $browser)
        .accessibilityIdentifier("native-report-market-sentiment")
    }

    private var indexCard: some View {
        let score = summary?.metrics?.first { $0.label == "指数" }
        let status = summary?.metrics?.first { $0.label == "当前情绪" }
        let change = summary?.metrics?.first { $0.label == "较上次" || $0.label == "较前收盘" }
        let rank = history?.rows?.first { $0.id == "0" }
        return panel {
            VStack(alignment: .leading, spacing: 4) {
                heading("恐惧与贪婪指数")
                if let sourceTime { notes(sourceTime, font: .caption) }
            }
            if let score {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 14) {
                        indexValue(score)
                        Spacer(minLength: 4)
                        indexContext(status: status, change: change, alignment: .trailing)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        indexValue(score)
                        indexContext(status: status, change: change, alignment: .leading)
                    }
                }
                if let value = Double(score.value), (0...100).contains(value) {
                    indexScale(value)
                }
            }
            Divider()
            if let rank {
                adaptiveRow {
                    Text("全历史位置").font(.subheadline.weight(.medium))
                } trailing: {
                    if let value = rank.value {
                        Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                    }
                    if let detail = rank.detail { notes(detail, font: .caption) }
                }
            } else {
                notes("暂无可用历史日记录")
            }
        }
    }

    private func indexValue(_ score: NativeNotificationReport.Metric) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(score.value)
                .font(.system(size: scoreSize, weight: .semibold))
                .tracking(-2)
            if let unit = score.unit {
                Text(unit).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("指数 \(score.value) \(score.unit ?? "")")
    }

    private func indexContext(
        status: NativeNotificationReport.Metric?,
        change: NativeNotificationReport.Metric?,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            if let status {
                let color = moodColor(status.tone)
                Text(status.value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            if let change {
                VStack(alignment: alignment, spacing: 2) {
                    Text(change.label).font(.caption).foregroundStyle(.secondary)
                    Text(change.value)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(moodColor(change.tone))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .fixedSize(horizontal: alignment == .trailing, vertical: true)
    }

    private func indexScale(_ score: Double) -> some View {
        let zones: [(width: CGFloat, color: Color)] = [
            (0.25, Color(red: 0.75, green: 0.30, blue: 0.28)),
            (0.20, Color(red: 0.86, green: 0.56, blue: 0.29)),
            (0.10, Color(red: 0.75, green: 0.74, blue: 0.62)),
            (0.20, Color(red: 0.46, green: 0.69, blue: 0.55)),
            (0.25, Color(red: 0.25, green: 0.57, blue: 0.46))
        ]
        return VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = max(0, proxy.size.width - 8)
                let marker = min(max(proxy.size.width * score / 100, 7), max(7, proxy.size.width - 7))
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(zones.indices, id: \.self) { index in
                            Rectangle()
                                .fill(zones[index].color)
                                .frame(width: width * zones[index].width)
                        }
                    }
                    .frame(height: 7)
                    .clipShape(Capsule())
                    Circle()
                        .fill(Color.primary)
                        .strokeBorder(InvestmentDesign.surface, lineWidth: 2)
                        .frame(width: 14, height: 14)
                        .position(x: marker, y: 7)
                }
                .frame(height: 14)
            }
            .frame(height: 14)
            HStack {
                Text("极度恐惧").frame(maxWidth: .infinity, alignment: .leading)
                Text("中性")
                Text("极度贪婪").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    private func backtestCard(_ backtest: Section) -> some View {
        let periods = buyReference?.rows ?? []
        let selected = periods.first { $0.id == selectedDays } ?? periods.first
        let metadata = backtest.text?.split(separator: "\n", maxSplits: 1).map(String.init) ?? []
        return panel {
            VStack(alignment: .leading, spacing: 4) {
                heading("QQQ · 相近情绪回测")
                if let match = buyReference?.text { notes(match, font: .caption) }
            }
            if let selected {
                if periods.count > 1 {
                    Picker("持有交易日", selection: Binding(
                        get: { selected.id },
                        set: { selectedDays = $0 }
                    )) {
                        ForEach(periods, id: \.id) { period in
                            Text("\(period.id) 日").tag(period.id)
                        }
                    }
                    .pickerStyle(.segmented)
                } else {
                    Text(selected.title).font(.subheadline.weight(.medium))
                }
                buyResults(selected)
                DisclosureGroup("所选期限明细") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let subtitle = selected.subtitle { notes(subtitle) }
                        if let detail = selected.detail { notes(statLines(detail)) }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline.weight(.medium))
            } else if metadata.count == 2 {
                Label(metadata[1], systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Divider()
            DisclosureGroup("回测口径与各情绪分组") {
                VStack(alignment: .leading, spacing: 12) {
                    if let text = metadata.first { notes(statLines(text)) }
                    if let selected, let grouped = section("backtest-\(selected.id)") {
                        sectionDetails(grouped, breakStatistics: true)
                    }
                }
                .padding(.top, 8)
            }
            .font(.subheadline.weight(.medium))
            if let panic = section("panic") {
                Divider()
                DisclosureGroup {
                    sectionDetails(panic, showTitle: false)
                        .padding(.top, 8)
                } label: {
                    Text(panic.title ?? "极度恐惧时的历史变动").font(.subheadline.weight(.medium))
                }
            }
        }
    }

    @ViewBuilder private func buyResults(_ row: Row) -> some View {
        if let detail = row.detail {
            let fields = detail.components(separatedBy: CharacterSet(charactersIn: "；，"))
            let metrics = [
                ("胜率", "历史盈利比例"),
                ("平均收益", "平均收益"),
                ("中位收益", "收益中位数")
            ].compactMap { key, label in
                fields.first { $0.hasPrefix(key) }.map { (label, String($0.dropFirst(key.count))) }
            }
            if metrics.isEmpty {
                notes(detail)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading),
                                         count: typeSize.isAccessibilitySize ? 1 : metrics.count), spacing: 10) {
                    ForEach(metrics, id: \.0) { metric in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.0).font(.caption).foregroundStyle(.secondary)
                            Text(metric.1)
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(accent)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if let sample = fields.first, sample.hasPrefix("样本") {
                    notes("\(sample) · 历史数据，供参考", font: .caption)
                }
            }
        }
    }

    private func sectionDetails(
        _ section: Section, showTitle: Bool = true, breakStatistics: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showTitle, let title = section.title { heading(title) }
            if let text = section.text { notes(text) }
            reportRows(section.rows ?? [], breakStatistics: breakStatistics)
        }
    }

    private func reportRows(
        _ rows: [Row], breakStatistics: Bool = false, showDetailBesideValue: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.id) { row in
                adaptiveRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title).font(.subheadline.weight(.medium))
                        if let subtitle = row.subtitle { notes(subtitle, font: .caption) }
                    }
                } trailing: {
                    if let value = row.value { Text(value).font(.subheadline.weight(.semibold)) }
                    if showDetailBesideValue, let detail = row.detail {
                        notes(detail, font: .caption)
                    }
                }
                if !showDetailBesideValue, let detail = row.detail, !detail.isEmpty {
                    notes(breakStatistics ? statLines(detail) : detail, font: .caption)
                }
                if row.id != rows.last?.id { Divider() }
            }
        }
    }

    private func adaptiveRow<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                leading()
                Spacer(minLength: 4)
                trailing()
            }
            VStack(alignment: .leading, spacing: 4) {
                leading()
                trailing()
            }
        }
        .monospacedDigit()
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.headline).accessibilityAddTraits(.isHeader)
    }

    private func notes(_ text: String, font: Font = .subheadline) -> some View {
        Text(text).font(font).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func section(_ id: String) -> Section? { report.sections?.first { $0.id == id } }

    private func populatedSection(_ id: String) -> Section? {
        report.sections?.first { $0.id == id && $0.rows?.isEmpty == false }
    }

    private func statLines(_ detail: String) -> String {
        detail.replacingOccurrences(of: "；", with: "\n")
    }

    private func moodColor(_ tone: String?) -> Color {
        switch tone {
        case "greed", "positive": Color(red: 0.12, green: 0.45, blue: 0.35)
        case "fear", "negative": Color(red: 0.67, green: 0.24, blue: 0.23)
        case "warning": Color(red: 0.54, green: 0.34, blue: 0.12)
        default: accent
        }
    }
}
