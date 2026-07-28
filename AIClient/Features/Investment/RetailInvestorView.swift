import Observation
import SwiftUI
import WebKit

struct RetailInvestorView: View {
    @Binding private var showsDetail: Bool
    @State private var store = RetailSentimentStore()
    @State private var path: [InvestorMoodRoute] = []
    @State private var selectedMarket: SentimentMarket = .china
    @State private var showsAllInvestorMood = false

    init(showsDetail: Binding<Bool> = .constant(false)) {
        _showsDetail = showsDetail
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    header
                    marketPicker
                    if let message = store.errorMessage {
                        errorBanner(message)
                    }
                    marketTemperatureCard
                    investorMoodCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemBackground))
            .refreshable {
                async let overview: Void = store.load(force: true)
                async let details: Void = store.loadDetails(for: selectedMarket, force: true)
                _ = await (overview, details)
            }
            .task { await store.load() }
            .task(id: selectedMarket) { await store.loadDetails(for: selectedMarket) }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: InvestorMoodRoute.self) { route in
                InvestorMoodWebView(route: route)
            }
        }
        .onChange(of: path) { _, path in showsDetail = !path.isEmpty }
        .onDisappear { showsDetail = false }
    }

    private var marketTemperatureCard: some View {
        let snapshot = store.snapshot(for: selectedMarket)
        let temperature = snapshot?.score
        let progress = CGFloat(min(max(temperature ?? 0, 0), 100) / 100)
        let breadth = selectedBreadth
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(temperature.map { String(Int($0.rounded())) } ?? "—")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("°")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot?.label.nonEmpty ?? "等待数据")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(temperatureColor(temperature))
                    Text("\(selectedMarket.title)市场温度")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                temperatureMetric(snapshot?.primaryTitle ?? "估值", value: snapshot?.primaryValue)
                Divider().frame(height: 34)
                temperatureMetric(snapshot?.secondaryTitle ?? "情绪", value: snapshot?.secondaryValue)
            }

            VStack(spacing: 5) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.20, green: 0.55, blue: 1), .yellow, .orange, .red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 8)
                        Circle()
                            .fill(Color(uiColor: .systemBackground))
                            .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
                            .frame(width: 14, height: 14)
                            .offset(x: max(0, min(proxy.size.width - 14, progress * proxy.size.width - 7)))
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 14)
                HStack {
                    Text("冷静")
                    Spacer()
                    Text("中性")
                    Spacer()
                    Text("过热")
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
            }

            Divider()
            HStack(spacing: 14) {
                compactBreadthMetric("涨", value: breadth.up, color: .red)
                compactBreadthMetric("跌", value: breadth.down, color: .green)
                compactBreadthMetric("平", value: breadth.flat, color: .secondary)
                Spacer()
                Text("估值 + 情绪等权")
                if let fetchedAt = snapshot?.fetchedAt {
                    Text("·")
                    Text(RetailSentimentFormat.shortTime(fetchedAt))
                }
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(selectedMarket.title)市场情绪 \(temperature.map { String(Int($0.rounded())) } ?? "暂无数据")")
    }

    private var marketPicker: some View {
        Picker("市场", selection: $selectedMarket) {
            ForEach(SentimentMarket.allCases) { market in
                Text(market.title).tag(market)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("选择市场情绪")
    }

    private var selectedBreadth: SentimentBreadth {
        if selectedMarket == .china, let breadth = store.breadth {
            return SentimentBreadth(up: breadth.up, down: breadth.down, flat: breadth.flat)
        }
        return store.constituentBreadth(for: selectedMarket)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("市场情绪")
                    .font(.system(size: 23, weight: .bold))
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
        .padding(.vertical, 3)
    }

    private var marketBreadthCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionTitle("市场广度", icon: "chart.bar.fill")
                Spacer()
                if let share = store.temperature?.latest.aiServer?.advancerShare?.value {
                    Text("上涨占比 \(String(format: "%.1f%%", share * 100))")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(HoldingsPalette.purple)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(HoldingsPalette.purple.opacity(0.1), in: Capsule())
                }
            }
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

    private var globalMarketBreadthCard: some View {
        let breadth = store.constituentBreadth(for: selectedMarket)
        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionTitle("核心成分表现", icon: "chart.bar.fill")
                Spacer()
                Text("样本 \(breadth.total)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(HoldingsPalette.purple)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(HoldingsPalette.purple.opacity(0.1), in: Capsule())
            }
            HStack(spacing: 0) {
                breadthMetric("上涨", value: breadth.up, color: .red)
                Divider().frame(height: 42)
                breadthMetric("下跌", value: breadth.down, color: .green)
                Divider().frame(height: 42)
                breadthMetric("平盘", value: breadth.flat, color: .secondary)
            }
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Rectangle().fill(Color.red.opacity(0.8)).frame(width: proxy.size.width * breadth.upRatio)
                    Rectangle().fill(Color.green.opacity(0.8)).frame(width: proxy.size.width * breadth.downRatio)
                    Rectangle().fill(Color.secondary.opacity(0.3))
                }
                .clipShape(Capsule())
            }
            .frame(height: 7)
            sourceLine(selectedMarket == .hongKong ? "恒生指数核心成分" : "标普 500 核心成分", suffix: store.dashboard?.generatedAt)
        }
        .sentimentCard()
    }

    private var globalMethodologyCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle(selectedMarket == .unitedStates ? "情绪驱动" : "计算口径", icon: "info.circle.fill")
            Text(store.snapshot(for: selectedMarket)?.detail ?? selectedMarket.detail)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                Text("散户观察")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Text("观点不计入温度")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            if store.investorMood?.items.isEmpty != false {
                placeholder("正在等待大曾子、王小雨等账号的最新有效样本")
            } else if let items = store.investorMood?.items {
                investorMoodSummary(items)

                let visibleItems = showsAllInvestorMood ? items : Array(items.prefix(3))
                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                    investorRow(item)
                    if index < visibleItems.count - 1 {
                        Divider().padding(.leading, 47)
                    }
                }

                if items.count > 3 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsAllInvestorMood.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(showsAllInvestorMood ? "收起" : "查看全部 \(items.count) 条")
                            Image(systemName: showsAllInvestorMood ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HoldingsPalette.purple)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(HoldingsPalette.purple.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 6)
    }

    private func investorMoodSummary(_ items: [InvestorMoodItem]) -> some View {
        let groupedItems: [String: [InvestorMoodItem]] = Dictionary(grouping: items) { item in
            item.label
        }
        let groups: [InvestorMoodCount] = groupedItems.map { label, values in
            InvestorMoodCount(label: label, count: values.count)
        }.sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs.label < rhs.label : lhs.count > rhs.count
        }

        return HStack(spacing: 12) {
            ForEach(groups) { group in
                HStack(spacing: 4) {
                    Circle()
                        .fill(RetailSentimentFormat.moodColor(group.label))
                        .frame(width: 6, height: 6)
                    Text("\(group.label) \(group.count)")
                }
            }
            Spacer(minLength: 0)
            Text("样本 \(items.count)")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func investorRow(_ item: InvestorMoodItem) -> some View {
        NavigationLink(value: InvestorMoodRoute(item: item)) {
            HStack(spacing: 9) {
                AsyncImage(url: URL(string: item.coverUrl)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable().scaledToFit().padding(8)
                            .foregroundStyle(HoldingsPalette.purple.opacity(0.65))
                    }
                }
                .frame(width: 38, height: 38)
                .background(HoldingsPalette.purple.opacity(0.08))
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.nickname)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(item.stale ? "\(item.label) · 旧样本" : item.label)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(RetailSentimentFormat.moodColor(item.label))
                        Spacer(minLength: 2)
                        Text(RetailSentimentFormat.relativeTime(item.createdAt))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Text(item.analysis.isEmpty ? (item.reasons.first ?? item.description) : item.analysis)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 3)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var methodologyNote: some View {
        Label("人物观点仅作观察样本，不计入市场情绪分数。", systemImage: "checkmark.shield.fill")
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

    private func temperatureMetric(_ title: String, value: Double?) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Text(value.map { String(format: "%.1f%%", $0) } ?? "—")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 58)
    }

    private func compactBreadthMetric(_ title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(title).foregroundStyle(.secondary)
            Text(value.formatted()).fontWeight(.semibold).foregroundStyle(color)
        }
    }

    private func temperatureColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        switch value {
        case 70...: return .orange
        case 30..<70: return HoldingsPalette.purple
        default: return .blue
        }
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

private struct InvestorMoodCount: Identifiable {
    var id: String { label }
    let label: String
    let count: Int
}

private struct InvestorMoodRoute: Hashable {
    let title: String
    let url: URL

    init(item: InvestorMoodItem) {
        title = item.nickname
        url = URL(string: item.url) ?? ServerConfiguration.currentURL
    }
}

private struct InvestorMoodWebView: View {
    let route: InvestorMoodRoute
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = InvestorMoodBrowserModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                Spacer()
                Text(route.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                ShareLink(item: route.url) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 6)

            if browser.isLoading {
                ProgressView(value: browser.progress)
                    .progressViewStyle(.linear)
            } else {
                Divider()
            }

            InvestorMoodWebPage(url: route.url, browser: browser)

            Divider()
            HStack {
                browserButton("chevron.left", enabled: browser.canGoBack) { browser.goBack() }
                Spacer()
                browserButton("chevron.right", enabled: browser.canGoForward) { browser.goForward() }
                Spacer()
                browserButton("arrow.clockwise", enabled: true) { browser.reload() }
                Spacer()
                ShareLink(item: browser.currentURL ?? route.url) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 50)
        }
        .background(Color(uiColor: .systemBackground))
        .toolbar(.hidden, for: .navigationBar)
    }

    private func browserButton(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 44, height: 44)
        }
        .disabled(!enabled)
    }
}

@MainActor
private final class InvestorMoodBrowserModel: ObservableObject {
    @Published var isLoading = true
    @Published var progress = 0.05
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentURL: URL?
    fileprivate weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
        update(from: webView)
    }

    func update(from webView: WKWebView) {
        isLoading = webView.isLoading
        progress = max(webView.estimatedProgress, 0.05)
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        currentURL = webView.url
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
}

private struct InvestorMoodWebPage: UIViewRepresentable {
    let url: URL
    @ObservedObject var browser: InvestorMoodBrowserModel

    func makeCoordinator() -> Coordinator {
        Coordinator(browser: browser)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.observe(webView)
        browser.attach(webView)
        webView.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url == nil else { return }
        webView.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20))
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let browser: InvestorMoodBrowserModel
        private var progressObservation: NSKeyValueObservation?

        init(browser: InvestorMoodBrowserModel) {
            self.browser = browser
        }

        func observe(_ webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self, weak webView] _, _ in
                guard let self, let webView else { return }
                Task { @MainActor in self.browser.update(from: webView) }
            }
        }

        func stopObserving() {
            progressObservation?.invalidate()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            browser.update(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            browser.update(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            browser.update(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            browser.update(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            browser.update(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}

@MainActor
@Observable
private final class RetailSentimentStore {
    private(set) var dashboard: MarketDashboard?
    private(set) var investorMood: InvestorMoodBoard?
    private(set) var temperature: MarketAShareTemperature?
    private(set) var hongKongConstituents: MarketIndexConstituents?
    private(set) var unitedStatesConstituents: MarketIndexConstituents?
    private(set) var hongKongValuationHistory: MarketHKValuationHistory?
    private(set) var hongKongCharts: [MarketChart] = []
    private(set) var unitedStatesValuationHistory: MarketUSValuationHistory?
    private(set) var unitedStatesCharts: [MarketChart] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let service: MarketService
    private var loaded = false
    private var loadedMarkets: Set<SentimentMarket> = []
    private var loadingMarkets: Set<SentimentMarket> = []

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

    func snapshot(for market: SentimentMarket) -> SentimentSnapshot? {
        switch market {
        case .china:
            guard let metrics = temperature?.latest.aiServer,
                  let score = metrics.compositeTemperature?.value else { return nil }
            return SentimentSnapshot(
                score: score,
                label: metrics.compositeTemperature?.label ?? "",
                primaryTitle: "估值温度",
                primaryValue: metrics.valuationPercentile?.value,
                secondaryTitle: "情绪温度",
                secondaryValue: metrics.sentimentPercentile?.value,
                formula: "估值与情绪各占 50%",
                fetchedAt: metrics.compositeTemperature?.fetchedAt,
                detail: "当前市场市盈率中位数与上涨家数占比，分别映射到历史百分位后等权合成。"
            )
        case .hongKong:
            let breadth = constituentBreadth(for: market)
            guard breadth.total > 0,
                  let valuationPercentile = hongKongValuationPercentile,
                  let sentimentPercentile = hongKongSentimentPercentile else { return nil }
            let score = (valuationPercentile + sentimentPercentile) / 2
            return SentimentSnapshot(
                score: score,
                label: SentimentSnapshot.label(for: score),
                primaryTitle: "估值温度",
                primaryValue: valuationPercentile,
                secondaryTitle: "情绪温度",
                secondaryValue: sentimentPercentile,
                formula: "估值与情绪各占 50%",
                fetchedAt: dashboard?.generatedAt,
                detail: "与 A 股采用相同公式：恒生指数当前市盈率的历史百分位，与核心成分上涨家数占比的近一年历史百分位等权合成。"
            )
        case .unitedStates:
            guard let valuationPercentile = unitedStatesValuationPercentile,
                  let sentimentPercentile = unitedStatesSentimentPercentile else { return nil }
            let score = (valuationPercentile + sentimentPercentile) / 2
            return SentimentSnapshot(
                score: score,
                label: SentimentSnapshot.label(for: score),
                primaryTitle: "估值温度",
                primaryValue: valuationPercentile,
                secondaryTitle: "情绪温度",
                secondaryValue: sentimentPercentile,
                formula: "估值与情绪各占 50%",
                fetchedAt: dashboard?.generatedAt,
                detail: "与 A 股采用相同公式：标普 500 当前市盈率的历史百分位，与核心成分上涨家数占比的近一年历史百分位等权合成。"
            )
        }
    }

    func constituentBreadth(for market: SentimentMarket) -> SentimentBreadth {
        let items: [MarketIndexConstituent]
        switch market {
        case .hongKong: items = hongKongConstituents?.items ?? []
        case .unitedStates: items = unitedStatesConstituents?.items ?? []
        case .china: items = []
        }
        var up = 0, down = 0, flat = 0
        for item in items {
            let change = item.quote.percentValue
            if change > 0.001 { up += 1 }
            else if change < -0.001 { down += 1 }
            else { flat += 1 }
        }
        return SentimentBreadth(up: up, down: down, flat: flat)
    }

    private var hongKongValuationPercentile: Double? {
        guard let values = hongKongValuationHistory?.pe.filter({ $0 > 0 }),
              let current = values.last, !values.isEmpty else { return nil }
        return percentile(of: current, in: values)
    }

    private var hongKongSentimentPercentile: Double? {
        breadthPercentile(for: .hongKong, charts: hongKongCharts)
    }

    private var unitedStatesValuationPercentile: Double? {
        guard let values = unitedStatesValuationHistory?.pe.filter({ $0 > 0 }),
              let current = values.first, !values.isEmpty else { return nil }
        return percentile(of: current, in: values)
    }

    private var unitedStatesSentimentPercentile: Double? {
        breadthPercentile(for: .unitedStates, charts: unitedStatesCharts)
    }

    private func breadthPercentile(for market: SentimentMarket, charts: [MarketChart]) -> Double? {
        let current = constituentBreadth(for: market).weightedAdvancerShare
        guard !charts.isEmpty else { return nil }
        var changesByDate: [Int64: [Double]] = [:]
        for chart in charts {
            let candles = chart.candles.sorted { $0.timestamp < $1.timestamp }
            guard candles.count > 1 else { continue }
            for index in 1..<candles.count {
                let previous = candles[index - 1].close
                guard previous > 0 else { continue }
                changesByDate[candles[index].timestamp, default: []].append((candles[index].close - previous) / previous)
            }
        }
        let historicalShares = changesByDate.values.compactMap { changes -> Double? in
            guard changes.count >= max(3, charts.count / 2) else { return nil }
            let up = changes.filter { $0 > 0.00001 }.count
            let flat = changes.filter { abs($0) <= 0.00001 }.count
            return (Double(up) + Double(flat) / 2) / Double(changes.count)
        }
        guard !historicalShares.isEmpty else { return nil }
        return percentile(of: current, in: historicalShares)
    }

    private func percentile(of value: Double, in samples: [Double]) -> Double {
        let less = samples.filter { $0 < value }.count
        let equal = samples.filter { abs($0 - value) < 0.000_001 }.count
        return 100 * (Double(less) + Double(equal) / 2) / Double(max(samples.count, 1))
    }

    func load(force: Bool = false) async {
        if loaded, !force { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        async let dashboardRequest = service.dashboard(refresh: force)
        async let moodRequest = service.investorMood()
        async let temperatureRequest = service.aShareTemperature()
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
        do {
            temperature = try await temperatureRequest
        } catch is CancellationError {
            return
        } catch {
            if dashboard == nil { errorMessage = error.localizedDescription }
        }
    }

    func loadDetails(for market: SentimentMarket, force: Bool = false) async {
        guard market != .china else { return }
        if loadedMarkets.contains(market), !force { return }
        guard loadingMarkets.insert(market).inserted else { return }
        defer { loadingMarkets.remove(market) }

        switch market {
        case .china:
            return
        case .hongKong:
            await loadHongKongDetails()
        case .unitedStates:
            await loadUnitedStatesDetails()
        }
        loadedMarkets.insert(market)
    }

    private func loadHongKongDetails() async {
        async let constituentsRequest = service.indexConstituents(symbol: "^HSI")
        async let valuationRequest = service.hongKongValuationHistory()
        do {
            hongKongConstituents = try await constituentsRequest
        } catch is CancellationError {
            return
        } catch {
            if dashboard == nil { errorMessage = error.localizedDescription }
        }
        if let constituents = hongKongConstituents {
            hongKongCharts = await withTaskGroup(of: MarketChart?.self) { group in
                for item in constituents.items {
                    group.addTask { [service] in
                        try? await service.chart(symbol: item.quote.symbol, range: .year)
                    }
                }
                var charts: [MarketChart] = []
                for await chart in group {
                    if let chart { charts.append(chart) }
                }
                return charts
            }
        }
        do {
            hongKongValuationHistory = try await valuationRequest
        } catch is CancellationError {
            return
        } catch {
            if dashboard == nil { errorMessage = error.localizedDescription }
        }
    }

    private func loadUnitedStatesDetails() async {
        async let constituentsRequest = service.indexConstituents(symbol: "^GSPC")
        async let valuationRequest = service.unitedStatesValuationHistory()
        do {
            unitedStatesConstituents = try await constituentsRequest
        } catch is CancellationError {
            return
        } catch {
            if dashboard == nil { errorMessage = error.localizedDescription }
        }
        if let constituents = unitedStatesConstituents {
            unitedStatesCharts = await withTaskGroup(of: MarketChart?.self) { group in
                for item in constituents.items {
                    group.addTask { [service] in
                        try? await service.chart(symbol: item.quote.symbol, range: .year)
                    }
                }
                var charts: [MarketChart] = []
                for await chart in group {
                    if let chart { charts.append(chart) }
                }
                return charts
            }
        }
        do {
            unitedStatesValuationHistory = try await valuationRequest
        } catch is CancellationError {
            return
        } catch {
            if dashboard == nil { errorMessage = error.localizedDescription }
        }
    }
}

private enum SentimentMarket: String, CaseIterable, Identifiable {
    case china
    case hongKong
    case unitedStates

    var id: Self { self }
    var title: String {
        switch self {
        case .china: "A 股"
        case .hongKong: "港股"
        case .unitedStates: "美股"
        }
    }
    var methodology: String {
        switch self {
        case .china: "估值与情绪各占 50%"
        case .hongKong: "估值与情绪各占 50%"
        case .unitedStates: "估值与情绪各占 50%"
        }
    }
    var detail: String {
        switch self {
        case .china: "结合估值与市场广度的历史百分位。"
        case .hongKong: "恒指估值与核心成分情绪各占 50%。"
        case .unitedStates: "标普估值与核心成分情绪各占 50%。"
        }
    }
}

private struct SentimentSnapshot {
    let score: Double
    let label: String
    let primaryTitle: String
    let primaryValue: Double?
    let secondaryTitle: String
    let secondaryValue: Double?
    let formula: String
    let fetchedAt: String?
    let detail: String

    static func label(for value: Double) -> String {
        switch value {
        case ..<10: "极冷"
        case ..<30: "偏冷"
        case ..<70: "正常"
        case ..<90: "偏热"
        default: "极热"
        }
    }
}

private struct SentimentBreadth {
    let up: Int
    let down: Int
    let flat: Int
    var total: Int { up + down + flat }
    var weightedAdvancerShare: Double { (Double(up) + Double(flat) / 2) / Double(max(total, 1)) }
    var upRatio: CGFloat { CGFloat(up) / CGFloat(max(total, 1)) }
    var downRatio: CGFloat { CGFloat(down) / CGFloat(max(total, 1)) }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
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
