import Observation
import SwiftUI

struct RetailInvestorView: View {
    @State private var store = RetailSentimentStore()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                if let message = store.errorMessage {
                    errorBanner(message)
                }
                breadthTemperatureCard
                marketBreadthCard
                capitalCard
                sectorCard
                investorMoodCard
                methodologyNote
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable { await store.load(force: true) }
        .task { await store.load() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("市场情绪")
                    .font(.system(size: 27, weight: .bold))
                Text("行情事实与公开观点样本分开展示")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isLoading {
                ProgressView().controlSize(.small)
            } else if let updatedAt = store.dashboard?.ashareOverview?.fetchedAt {
                Text(RetailSentimentFormat.shortTime(updatedAt))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 5)
    }

    private var breadthTemperatureCard: some View {
        let score = store.breadthScore
        return HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: score / 100)
                    .stroke(
                        AngularGradient(colors: [HoldingsPalette.purple.opacity(0.55), HoldingsPalette.purple, .red], center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(store.breadth == nil ? "—" : String(Int(score.rounded())))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(store.breadthLabel)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(HoldingsPalette.purple)
                }
            }
            .frame(width: 112, height: 112)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("市场广度温度 (Int(score.rounded()))，(store.breadthLabel)")

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Text("市场广度温度")
                        .font(.system(size: 20, weight: .bold))
                    Text("计算值")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(HoldingsPalette.purple)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(HoldingsPalette.purple.opacity(0.1), in: Capsule())
                }
                Text("仅按上涨家数占上涨与下跌家数的比例计算，不混入博主观点。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if store.dashboard?.ashareOverview?.stale == true {
                    Label("行情快照已过期", systemImage: "clock.badge.exclamationmark")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .sentimentCard()
    }

    private var marketBreadthCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("市场广度", icon: "chart.bar.fill")
            HStack(spacing: 0) {
                breadthMetric("上涨", value: store.breadth?.up, color: .red)
                Divider().frame(height: 42)
                breadthMetric("下跌", value: store.breadth?.down, color: .green)
                Divider().frame(height: 42)
                breadthMetric("平盘", value: store.breadth?.flat, color: .secondary)
            }
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Rectangle().fill(Color.red.opacity(0.8)).frame(width: proxy.size.width * store.upRatio)
                    Rectangle().fill(Color.green.opacity(0.8)).frame(width: proxy.size.width * store.downRatio)
                    Rectangle().fill(Color.secondary.opacity(0.3))
                }
                .clipShape(Capsule())
            }
            .frame(height: 7)
            sourceLine(store.dashboard?.ashareOverview?.source ?? "A股行情快照", suffix: store.dashboard?.ashareOverview?.fetchedAt)
        }
        .sentimentCard()
    }

    private var capitalCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("资金与杠杆", icon: "arrow.left.arrow.right.circle.fill")
            HStack(alignment: .top, spacing: 12) {
                capitalMetric(
                    title: "ETF净申购估算",
                    value: RetailSentimentFormat.money(store.structure?.etfSubscription.latestEstimatedNetFlowCNY),
                    detail: store.structure.map { "\($0.etfSubscription.fundCount ?? 1)只主要ETF · \($0.etfSubscription.asOf)" } ?? "等待日频数据",
                    change: store.structure?.etfSubscription.latestEstimatedNetFlowCNY,
                    systemImage: "chart.pie.fill"
                )
                capitalMetric(
                    title: "两融余额",
                    value: RetailSentimentFormat.money(store.structure?.marginBalance.totalBalance),
                    detail: store.structure.map { "日变动 \(RetailSentimentFormat.money($0.marginBalance.latestChange)) · \($0.marginBalance.asOf)" } ?? "等待日频数据",
                    change: store.structure?.marginBalance.latestChange,
                    systemImage: "building.columns.fill"
                )
            }
            if let signal = store.structure?.combinedSignal {
                Label(signal.summary, systemImage: "waveform.path.ecg")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text("ETF流向为份额变化估算；两融数据按交易所日频口径展示。")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
        }
        .sentimentCard()
    }

    private var sectorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("板块热度", icon: "square.grid.2x2.fill")
            if store.sectors.isEmpty {
                placeholder("暂无板块行情")
            } else {
                ForEach(Array(store.sectors.prefix(5).enumerated()), id: \.element.id) { index, sector in
                    HStack(spacing: 10) {
                        Text(String(sector.rank ?? index + 1))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(sector.name)
                            .font(.system(size: 14.5, weight: .semibold))
                        Spacer()
                        if let movement = sector.rankChange, movement != 0 {
                            Label(String(abs(movement)), systemImage: movement > 0 ? "arrow.up" : "arrow.down")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(movement > 0 ? Color.red : Color.green)
                        }
                        Text(RetailSentimentFormat.percent(sector.percentValue))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(sector.percentValue >= 0 ? Color.red : Color.green)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .padding(.vertical, 7)
                    if index < min(store.sectors.count, 5) - 1 { Divider() }
                }
            }
            sourceLine(store.dashboard?.ashareOverview?.source ?? "A股板块行情", suffix: store.dashboard?.ashareOverview?.fetchedAt)
        }
        .sentimentCard()
    }

    private var investorMoodCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("散户观察", icon: "person.3.fill")
                Spacer()
                Text("公开视频样本")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }
            if store.investorMood?.items.isEmpty != false {
                placeholder("正在等待大曾子、王小雨等账号的最新有效样本")
            } else if let items = store.investorMood?.items {
                ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, item in
                    investorRow(item)
                    if index < min(items.count, 4) - 1 { Divider() }
                }
            }
            Text(store.investorMood?.disclaimer ?? "观点样本来自公开视频，不代表整体市场情绪，不构成投资建议。")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sentimentCard()
    }

    private func investorRow(_ item: InvestorMoodItem) -> some View {
        Link(destination: URL(string: item.url) ?? ServerConfiguration.currentURL) {
            HStack(spacing: 11) {
                AsyncImage(url: URL(string: item.coverUrl)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable().scaledToFit().padding(10)
                            .foregroundStyle(HoldingsPalette.purple.opacity(0.65))
                    }
                }
                .frame(width: 48, height: 48)
                .background(HoldingsPalette.purple.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(item.nickname)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        moodBadge(item.label, stale: item.stale)
                    }
                    Text(item.analysis.isEmpty ? (item.reasons.first ?? item.description) : item.analysis)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(RetailSentimentFormat.relativeTime(item.createdAt))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 3)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var methodologyNote: some View {
        Label("市场数据与人物观点采用不同口径，人物样本不计入市场广度温度。", systemImage: "checkmark.shield.fill")
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.primary)
    }

    private func breadthMetric(_ title: String, value: Int?, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 12.5)).foregroundStyle(.secondary)
            Text(value.map { $0.formatted() } ?? "—")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func capitalMetric(title: String, value: String, detail: String, change: Double?, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle((change ?? 0) >= 0 ? Color.red : Color.green)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11))
    }

    private func moodBadge(_ label: String, stale: Bool) -> some View {
        let color = RetailSentimentFormat.moodColor(label)
        return Text(stale ? "\(label) · 旧样本" : label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }

    private func sourceLine(_ source: String, suffix: String?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.seal")
            Text(source)
            if let suffix { Text("· " + RetailSentimentFormat.shortTime(suffix)) }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.tertiary)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12.5))
            .foregroundStyle(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

@MainActor
@Observable
private final class RetailSentimentStore {
    private(set) var dashboard: MarketDashboard?
    private(set) var investorMood: InvestorMoodBoard?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let service: MarketService
    private var loaded = false

    init(baseURL: URL = ServerConfiguration.currentURL) {
        service = MarketService(baseURL: baseURL)
    }

    var breadth: MarketBreadth? { dashboard?.ashareOverview?.breadth }
    var structure: MarketStructure? { dashboard?.marketStructure }
    var sectors: [MarketSector] { dashboard?.ashareOverview?.hotSectors ?? [] }
    var upRatio: CGFloat {
        guard let breadth else { return 0 }
        let total = max(breadth.up + breadth.down + breadth.flat, 1)
        return CGFloat(breadth.up) / CGFloat(total)
    }
    var downRatio: CGFloat {
        guard let breadth else { return 0 }
        let total = max(breadth.up + breadth.down + breadth.flat, 1)
        return CGFloat(breadth.down) / CGFloat(total)
    }
    var breadthScore: Double {
        guard let breadth else { return 0 }
        return Double(breadth.up) / Double(max(breadth.up + breadth.down, 1)) * 100
    }
    var breadthLabel: String {
        switch breadthScore {
        case 60...: "偏热"
        case 52..<60: "偏暖"
        case 45..<52: "均衡"
        case 35..<45: "偏冷"
        default: breadth == nil ? "等待数据" : "较冷"
        }
    }

    func load(force: Bool = false) async {
        if loaded, !force { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        async let dashboardRequest = service.dashboard(refresh: force)
        async let moodRequest = service.investorMood()
        do {
            dashboard = try await dashboardRequest
            loaded = true
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        do {
            investorMood = try await moodRequest
        } catch is CancellationError {
            return
        } catch {
            if dashboard == nil { errorMessage = error.localizedDescription }
        }
    }
}

private enum RetailSentimentFormat {
    static func money(_ value: Double?) -> String {
        guard let value else { return "—" }
        let absolute = abs(value)
        let sign = value > 0 ? "+" : value < 0 ? "−" : ""
        if absolute >= 1_000_000_000_000 { return sign + String(format: "%.2f万亿", absolute / 1_000_000_000_000) }
        if absolute >= 100_000_000 { return sign + String(format: "%.1f亿", absolute / 100_000_000) }
        if absolute >= 10_000 { return sign + String(format: "%.1f万", absolute / 10_000) }
        return sign + absolute.formatted(.number.precision(.fractionLength(0)))
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))) + "%"
    }

    static func shortTime(_ value: String) -> String {
        guard let date = isoDate(value) else { return value }
        return date.formatted(.dateTime.month().day().hour().minute())
    }

    static func relativeTime(_ value: String?) -> String {
        guard let value, let date = isoDate(value) else { return "时间未知" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    static func moodColor(_ label: String) -> Color {
        if label.contains("悲观") || label.contains("恐慌") { return .green }
        if label.contains("乐观") || label.contains("兴奋") { return .red }
        return HoldingsPalette.purple
    }

    private static func isoDate(_ value: String) -> Date? {
        fractionalISO.date(from: value) ?? standardISO.date(from: value)
    }

    private static let fractionalISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardISO = ISO8601DateFormatter()
}

private extension View {
    func sentimentCard() -> some View {
        padding(15)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 15))
            .overlay { RoundedRectangle(cornerRadius: 15).stroke(Color.secondary.opacity(0.1)) }
    }
}
