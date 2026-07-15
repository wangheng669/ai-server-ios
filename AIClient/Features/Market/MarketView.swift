import SwiftUI

private enum MarketStyle {
    static let canvas = Color(red: 0.978, green: 0.977, blue: 0.971)
    static let surface = Color(red: 0.998, green: 0.997, blue: 0.993)
    static let divider = Color.black.opacity(0.055)
    static let gain = Color(red: 0.96, green: 0.18, blue: 0.22)
    static let loss = Color(red: 0.06, green: 0.65, blue: 0.32)
    static let accent = Color(red: 0.07, green: 0.49, blue: 0.98)
    static let purple = Color(red: 0.50, green: 0.30, blue: 0.94)
}

struct MarketView: View {
    @Binding private var showsDetail: Bool
    @State private var store = MarketStore()
    @State private var path: [String] = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--market-detail-preview") ? ["^NDX"] : []
        #else
        []
        #endif
    }()

    init(showsDetail: Binding<Bool> = .constant(false)) { _showsDetail = showsDetail }

    var body: some View {
        NavigationStack(path: $path) {
            MarketHomeView(store: store) { path.append($0) }
                .navigationDestination(for: String.self) { symbol in
                    MarketIndexDetailView(symbol: symbol, store: store)
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .task { await store.runUpdates() }
        .onChange(of: path) { _, path in showsDetail = !path.isEmpty }
        .onAppear { showsDetail = !path.isEmpty }
        .onDisappear { showsDetail = false }
    }
}

private struct MarketHomeView: View {
    let store: MarketStore
    let onSelectIndex: (String) -> Void

    var body: some View {
        ZStack {
            MarketStyle.canvas.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("市场").font(.system(size: 32, weight: .bold)).tracking(-0.8)
                        Spacer()
                        MarketLiveStatus(store: store)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 7)

                    MarketMoodDashboard(dashboard: store.dashboard)
                    coreIndices
                    pageIndicator
                    sectionHeader("市场概览", trailing: "更多")
                    MarketBreadthCard(overview: store.dashboard?.ashareOverview, vix: store.quote(symbol: "^VIX"))
                    sectionHeader("热门板块", trailing: "更多")
                    MarketSectorsRow(sectors: store.dashboard?.ashareOverview?.hotSectors ?? [])
                    Color.clear.frame(height: 76)
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.refresh() }
        }
    }

    private var coreIndices: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("全球核心指数", trailing: "全部指数")
            ForEach(CoreRegion.all) { region in
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 22)
                    HStack(spacing: 8) {
                        ForEach(region.symbols, id: \.self) { symbol in
                            let quote = store.quote(symbol: symbol)
                            Button { if quote != nil { onSelectIndex(symbol) } } label: {
                                MarketCoreIndexCard(descriptor: CoreDescriptor(symbol: symbol), quote: quote)
                            }
                            .disabled(quote == nil)
                            .buttonStyle(MarketPressStyle())
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            Circle().fill(MarketStyle.accent).frame(width: 5, height: 5)
            Circle().fill(Color.secondary.opacity(0.22)).frame(width: 5, height: 5)
            Circle().fill(Color.secondary.opacity(0.22)).frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, -3)
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title).font(.system(size: 18, weight: .semibold)).tracking(-0.2)
            Spacer()
            HStack(spacing: 4) { Text(trailing); Image(systemName: "chevron.right") }
                .font(.system(size: 12.5)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }
}

private struct MarketLiveStatus: View {
    let store: MarketStore

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(store.errorMessage == nil ? MarketStyle.loss : Color.orange).frame(width: 6, height: 6)
            if store.isLoading && store.dashboard == nil {
                Text("加载中")
            } else if let date = store.lastUpdatedAt {
                Text(date.formatted(date: .omitted, time: .shortened))
            } else {
                Text("等待行情")
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.secondary)
        .accessibilityLabel(store.errorMessage ?? "行情实时更新")
    }
}

private struct MarketMoodDashboard: View {
    let dashboard: MarketDashboard?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("今日市场情绪").font(.system(size: 11.5)).foregroundStyle(.secondary)
                Text(dashboard?.sentiment?.ratingZh ?? "—").font(.system(size: 16.5, weight: .semibold))
                HStack(spacing: 10) {
                    MoodGauge(value: dashboard?.sentiment?.score)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("较前值").font(.system(size: 10.5)).foregroundStyle(.secondary)
                        Text(sentimentChange).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(sentimentTint)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(MarketStyle.divider).frame(width: 0.5)
            VStack(spacing: 0) {
                DashboardMetric(title: "风险指数 (VIX)", quote: dashboard?.metrics.first(where: { $0.symbol == "^VIX" }))
                Rectangle().fill(MarketStyle.divider).frame(height: 0.5)
                DashboardMetric(title: "美债10年收益率", quote: dashboard?.metrics.first(where: { $0.symbol == "^TNX" }), yield: true)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 118)
        .marketCard(cornerRadius: 11)
        .padding(.horizontal, 18)
    }

    private var sentimentChange: String {
        guard let current = dashboard?.sentiment?.score, let previous = dashboard?.sentiment?.previousClose else { return "—" }
        return signed(current - previous, digits: 1)
    }

    private var sentimentTint: Color {
        guard let current = dashboard?.sentiment?.score, let previous = dashboard?.sentiment?.previousClose else { return .secondary }
        return current >= previous ? MarketStyle.gain : MarketStyle.loss
    }
}

private struct DashboardMetric: View {
    let title: String
    let quote: MarketQuote?
    var yield = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 9.7)).foregroundStyle(.secondary).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value).font(.system(size: 16.5, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.72)
                    Text(percent).font(.system(size: 8.4, weight: .medium)).foregroundStyle(quoteTint(quote)).lineLimit(1).minimumScaleFactor(0.72)
                }
            }
            Spacer(minLength: 4)
            Sparkline(values: quote?.trend ?? [], color: quoteTint(quote), showsFill: false).frame(width: 50, height: 23)
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
    }

    private var value: String {
        guard let quote else { return "—" }
        return yield ? String(format: "%.2f%%", quote.price) : number(quote.price, digits: 1)
    }
    private var percent: String { quote?.formattedPercent ?? "—" }
}

private struct MoodGauge: View {
    let value: Double?
    var body: some View {
        ZStack {
            Circle().stroke(Color.black.opacity(0.055), lineWidth: 7)
            Circle().trim(from: 0, to: CGFloat(min(max(value ?? 0, 0), 100) / 100))
                .stroke(AngularGradient(colors: [.mint, .green], center: .center), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(value.map { String(Int($0.rounded())) } ?? "—").font(.system(size: 21, weight: .semibold)).monospacedDigit()
                Text("/100").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 62, height: 62)
    }
}

private struct MarketCoreIndexCard: View {
    let descriptor: CoreDescriptor
    let quote: MarketQuote?
    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(quote?.name ?? descriptor.name).font(.system(size: 10.8, weight: .medium)).lineLimit(1)
                Text(descriptor.code).font(.system(size: 8.5)).foregroundStyle(.secondary.opacity(0.75))
                Spacer(minLength: 1)
                Text(quote.map { number($0.price, digits: 2) } ?? "—")
                    .font(.system(size: 14.5, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                Text(quote.map { "\(signed($0.changeValue, digits: 2))  \($0.formattedPercent)" } ?? "等待实时数据")
                    .font(.system(size: 8.5, weight: .semibold)).monospacedDigit().foregroundStyle(quoteTint(quote)).lineLimit(1)
            }
            Sparkline(values: quote?.trend ?? [], color: quoteTint(quote)).frame(width: 56, height: 32)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .marketCard(cornerRadius: 9)
    }
}

private struct MarketBreadthCard: View {
    let overview: MarketAShareOverview?
    let vix: MarketQuote?

    var body: some View {
        let breadth = overview?.breadth
        HStack(alignment: .top, spacing: 10) {
            BreadthItem(title: "上涨家数", value: breadth.map { number(Double($0.up), digits: 0) } ?? "—", symbol: "arrow.up", tint: MarketStyle.gain, progress: ratio(breadth?.up, breadth?.total))
            BreadthItem(title: "下跌家数", value: breadth.map { number(Double($0.down), digits: 0) } ?? "—", symbol: "arrow.down", tint: MarketStyle.loss, progress: ratio(breadth?.down, breadth?.total))
            BreadthItem(title: "平盘家数", value: breadth.map { number(Double($0.flat), digits: 0) } ?? "—", symbol: "minus", tint: .gray, progress: ratio(breadth?.flat, breadth?.total))
            VStack(alignment: .leading, spacing: 6) {
                Text("恐慌指数 VIX").font(.system(size: 10.5)).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(vix.map { number($0.price, digits: 1) } ?? "—").font(.system(size: 15.5, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.72)
                    Text(vix?.formattedPercent ?? "—").font(.system(size: 8.8, weight: .medium)).foregroundStyle(quoteTint(vix)).lineLimit(1).minimumScaleFactor(0.7)
                }
                Sparkline(values: vix?.trend ?? [], color: quoteTint(vix)).frame(height: 22)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9).marketCard(cornerRadius: 10).padding(.horizontal, 18)
    }

    private func ratio(_ value: Int?, _ total: Int?) -> Double {
        guard let value, let total, total > 0 else { return 0 }
        return Double(value) / Double(total)
    }
}

private struct BreadthItem: View {
    let title: String, value: String, symbol: String
    let tint: Color
    let progress: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                Text(value).font(.system(size: 15.5, weight: .semibold)).monospacedDigit()
                Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
            }
            MarketProgress(value: progress, tint: tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarketSectorsRow: View {
    let sectors: [MarketSector]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sectors) { sector in
                    VStack(alignment: .leading, spacing: 7) {
                        Label(sector.name, systemImage: sectorSymbol(sector.name)).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                        Text(sector.changePercent).font(.system(size: 11, weight: .semibold)).foregroundStyle(sector.percentValue >= 0 ? MarketStyle.gain : MarketStyle.loss)
                        Text("实时板块涨幅").font(.system(size: 8.5)).foregroundStyle(.secondary)
                    }
                    .padding(9).frame(width: 98, height: 76, alignment: .topLeading).marketCard(cornerRadius: 9)
                }
                if sectors.isEmpty {
                    Text("板块数据加载中").font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 76)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 4)
        }
    }
}

private struct MarketIndexDetailView: View {
    let symbol: String
    let store: MarketStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRange = MarketRange.day
    @State private var isFollowing = false
    @State private var isFavorite = false

    private var quote: MarketQuote? { store.quote(symbol: symbol) }

    var body: some View {
        ZStack {
            MarketStyle.canvas.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 15) {
                    detailHeader
                    MarketDetailChart(selectedRange: $selectedRange, symbol: symbol, store: store)
                    keyData
                    MarketSummary(quote: quote, chart: store.chart(symbol: symbol, range: selectedRange))
                    componentStocks
                    Text("数据来源：\(quote?.dataSource ?? "行情服务") · \(quote?.freshnessLabel ?? "更新中")")
                        .font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 18)
                    Color.clear.frame(height: 20)
                }
                .padding(.top, 4)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                Spacer()
                Button { isFavorite.toggle() } label: { Image(systemName: isFavorite ? "star.fill" : "star") }
                ShareLink(item: "\(quote?.name ?? symbol) \(quote.map { number($0.price, digits: 2) } ?? "")") { Image(systemName: "square.and.arrow.up") }
            }
            .font(.system(size: 21, weight: .medium)).foregroundStyle(.primary)

            HStack(spacing: 10) {
                Image(systemName: CoreDescriptor(symbol: symbol).icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.blue)
                    .frame(width: 30, height: 30).background(Color.blue.opacity(0.10), in: Circle())
                Text(quote?.name ?? CoreDescriptor(symbol: symbol).name).font(.system(size: 22, weight: .semibold)).tracking(-0.35)
                Text(CoreDescriptor(symbol: symbol).code).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 5).background(Color.black.opacity(0.045), in: Capsule())
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(quote.map { number($0.price, digits: 2) } ?? "—").font(.system(size: 33, weight: .bold)).monospacedDigit().tracking(-0.8).foregroundStyle(quoteTint(quote))
                    Text(quote.map { "\(signed($0.changeValue, digits: 2))  \($0.formattedPercent)" } ?? "等待实时数据")
                        .font(.system(size: 16, weight: .semibold)).monospacedDigit().foregroundStyle(quoteTint(quote))
                    HStack(spacing: 7) {
                        Circle().fill(sessionColor).frame(width: 6, height: 6)
                        Text(sessionText)
                        if let timestamp = quote?.timestamp { Text(marketTimestamp(timestamp)) }
                    }
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { isFollowing.toggle() } label: {
                    Text(isFollowing ? "✓ 已自选" : "+ 自选").font(.system(size: 12.5, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Color.black.opacity(0.04), in: Capsule())
                }
                .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 18)
    }

    private var keyData: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("关键数据").font(.system(size: 17, weight: .semibold))
            Grid(horizontalSpacing: 10, verticalSpacing: 13) {
                GridRow { metric("开盘", quote?.openPrice); metric("最高", quote?.high, MarketStyle.gain); metric("最低", quote?.low, MarketStyle.loss); metric("昨收", quote?.previousClose) }
                GridRow { metric("成交量", quote?.volume, compact: true); metric("涨跌幅", quote?.percentValue, quoteTint(quote), suffix: "%"); metric("市盈率", quote?.pe); textMetric("状态", quote?.freshnessLabel ?? "更新中") }
            }
            .padding(12).marketCard(cornerRadius: 10)
        }
        .padding(.horizontal, 18)
    }

    private func metric(_ title: String, _ value: Double?, _ color: Color = .primary, compact: Bool = false, suffix: String = "") -> some View {
        textMetric(title, value.map { (compact ? compactNumber($0) : number($0, digits: 2)) + suffix } ?? "—", color)
    }

    private func textMetric(_ title: String, _ value: String, _ color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var componentStocks: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Text("热门成分股").font(.system(size: 17, weight: .semibold)); Spacer(); Text("实时行情  ›").font(.system(size: 12)).foregroundStyle(.secondary) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(store.dashboard?.components ?? []) { MarketStockCard(quote: $0) } }.padding(.vertical, 3)
            }
        }
        .padding(.horizontal, 18)
    }

    private var sessionText: String {
        switch quote?.marketSession { case "regular": "交易中"; case "pre": "盘前"; case "post", "after": "盘后"; default: "已收盘" }
    }
    private var sessionColor: Color { quote?.marketSession == "regular" ? MarketStyle.loss : .secondary }
}

private struct MarketDetailChart: View {
    @Binding var selectedRange: MarketRange
    let symbol: String
    let store: MarketStore

    private var chart: MarketChart? { store.chart(symbol: symbol, range: selectedRange) }
    private var values: [Double] { chart?.points.compactMap(\.displayValue) ?? [] }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(MarketRange.allCases) { range in
                    Button { selectedRange = range } label: {
                        VStack(spacing: 5) {
                            Text(range.rawValue).font(.system(size: 12, weight: selectedRange == range ? .semibold : .regular))
                            Capsule().fill(selectedRange == range ? MarketStyle.accent : Color.clear).frame(width: 18, height: 2)
                        }
                    }
                    .foregroundStyle(.primary).frame(maxWidth: .infinity)
                }
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 14)).frame(width: 28)
            }
            ZStack {
                ChartGrid(values: values)
                if values.isEmpty {
                    if store.loadingCharts.contains(ChartKey(symbol: symbol, range: selectedRange)) { ProgressView() }
                    else { Text("暂无该周期行情").font(.system(size: 12)).foregroundStyle(.secondary) }
                } else {
                    AreaChart(values: values, color: quoteTint(store.quote(symbol: symbol)))
                        .padding(.leading, 48).padding(.top, 9).padding(.bottom, 6)
                }
            }
            .frame(height: 158)
            HStack { Text("开始"); Spacer(); Text("中段"); Spacer(); Text("最新") }.font(.system(size: 9.5)).foregroundStyle(.secondary).padding(.leading, 48).padding(.trailing, 5)
            VolumeBars(points: chart?.points ?? []).frame(height: 23).padding(.leading, 48)
                .overlay(alignment: .topTrailing) { Text("成交量").font(.system(size: 9.5)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 18)
        .task(id: selectedRange) { await store.loadChart(symbol: symbol, range: selectedRange) }
    }
}

private struct ChartGrid: View {
    let values: [Double]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                HStack(spacing: 6) {
                    Text(axisLabel(index)).font(.system(size: 9.5)).foregroundStyle(.secondary).frame(width: 42, alignment: .leading)
                    Rectangle().fill(Color.black.opacity(0.025)).frame(height: 0.5)
                }
                if index < 4 { Spacer() }
            }
        }
    }

    private func axisLabel(_ index: Int) -> String {
        guard let min = values.min(), let max = values.max(), max > min else { return "—" }
        return number(max - (max - min) * Double(index) / 4, digits: 0)
    }
}

private struct AreaChart: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { proxy in
            let points = chartPoints(values, size: proxy.size)
            ZStack {
                Path { path in
                    guard let first = points.first, let last = points.last else { return }
                    path.move(to: CGPoint(x: first.x, y: proxy.size.height)); path.addLine(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: last.x, y: proxy.size.height)); path.closeSubpath()
                }.fill(LinearGradient(colors: [color.opacity(0.18), color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                Path { path in guard let first = points.first else { return }; path.move(to: first); points.dropFirst().forEach { path.addLine(to: $0) } }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.1, lineJoin: .round))
            }
        }
    }
}

private struct VolumeBars: View {
    let points: [MarketChartPoint]
    var body: some View {
        GeometryReader { proxy in
            let maxVolume = points.compactMap(\.volume).max() ?? 1
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(points.suffix(80)) { point in
                    let rising = (point.close ?? point.value ?? 0) >= (point.open ?? point.close ?? point.value ?? 0)
                    Rectangle().fill((rising ? MarketStyle.gain : MarketStyle.loss).opacity(0.68))
                        .frame(maxWidth: .infinity).frame(height: max(2, proxy.size.height * CGFloat((point.volume ?? 0) / maxVolume)))
                }
            }
        }
    }
}

private struct MarketSummary: View {
    let quote: MarketQuote?
    let chart: MarketChart?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: "waveform.path.ecg").foregroundStyle(.white).frame(width: 22, height: 22).background(MarketStyle.purple, in: Circle()); Text("市场摘要").font(.system(size: 16, weight: .semibold)); Spacer(); Text(quote?.freshnessLabel ?? "更新中").font(.system(size: 11)).foregroundStyle(.secondary) }
            Text(summary).font(.system(size: 12.5)).lineSpacing(3).foregroundStyle(.primary.opacity(0.86))
            HStack(spacing: 7) {
                ForEach(tags, id: \.self) { Text($0).font(.system(size: 10.5, weight: .medium)).foregroundStyle(MarketStyle.purple).padding(.horizontal, 9).padding(.vertical, 6).background(MarketStyle.purple.opacity(0.07), in: Capsule()) }
            }
        }
        .padding(14)
        .background(LinearGradient(colors: [MarketStyle.purple.opacity(0.06), Color.white.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(MarketStyle.purple.opacity(0.07), lineWidth: 0.5) }
        .padding(.horizontal, 18)
    }

    private var summary: String {
        guard let quote else { return "正在获取最新行情。" }
        let direction = quote.isUp ? "上涨" : "下跌"
        if let high = quote.high, let low = quote.low {
            return "\(quote.name)当前\(direction) \(String(format: "%.2f", abs(quote.percentValue)))%，最新 \(number(quote.price, digits: 2))，日内区间 \(number(low, digits: 2))–\(number(high, digits: 2))。数据由 \(quote.dataSource ?? "行情服务") \(quote.freshnessLabel)更新。"
        }
        return "\(quote.name)当前\(direction) \(String(format: "%.2f", abs(quote.percentValue)))%，最新 \(number(quote.price, digits: 2))。"
    }

    private var tags: [String] { [quote?.isUp == true ? "指数走强" : "指数走弱", quote?.marketSession == "regular" ? "交易中" : "非交易时段", chart?.points.isEmpty == false ? "分时可用" : "等待图表"] }
}

private struct MarketStockCard: View {
    let quote: MarketQuote
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: stockSymbol(quote.symbol)).font(.system(size: 17, weight: .semibold)).foregroundStyle(stockColor(quote.symbol))
                .frame(width: 30, height: 30).background(stockColor(quote.symbol).opacity(0.09), in: Circle())
            Text(quote.symbol).font(.system(size: 11.5, weight: .semibold))
            Text(quote.name).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
            Text(quote.formattedPercent).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(quoteTint(quote))
            Text(number(quote.price, digits: 2)).font(.system(size: 9.2, weight: .medium)).foregroundStyle(.secondary)
        }
        .padding(9).frame(width: 84, height: 104, alignment: .topLeading).marketCard(cornerRadius: 9)
    }
}

private struct Sparkline: View {
    let values: [Double]
    let color: Color
    var showsFill = true
    var body: some View {
        GeometryReader { proxy in
            let points = chartPoints(values, size: proxy.size)
            if points.count > 1 {
                ZStack {
                    if showsFill {
                        Path { path in
                            guard let first = points.first, let last = points.last else { return }
                            path.move(to: CGPoint(x: first.x, y: proxy.size.height)); path.addLine(to: first)
                            points.dropFirst().forEach { path.addLine(to: $0) }
                            path.addLine(to: CGPoint(x: last.x, y: proxy.size.height)); path.closeSubpath()
                        }.fill(LinearGradient(colors: [color.opacity(0.14), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    }
                    Path { path in guard let first = points.first else { return }; path.move(to: first); points.dropFirst().forEach { path.addLine(to: $0) } }
                        .stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                }
            } else {
                Capsule().fill(Color.secondary.opacity(0.12)).frame(height: 1)
            }
        }
    }
}

private struct MarketProgress: View {
    let value: Double
    let tint: Color
    var body: some View { GeometryReader { proxy in ZStack(alignment: .leading) { Capsule().fill(Color.black.opacity(0.06)); Capsule().fill(tint.opacity(0.85)).frame(width: proxy.size.width * min(max(value, 0), 1)) } }.frame(height: 5) }
}

private struct MarketPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.scaleEffect(configuration.isPressed ? 0.985 : 1).opacity(configuration.isPressed ? 0.88 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed) }
}

private extension View {
    func marketCard(cornerRadius: CGFloat) -> some View {
        background(MarketStyle.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.black.opacity(0.035), lineWidth: 0.5) }
            .shadow(color: Color.black.opacity(0.025), radius: 9, x: 0, y: 4)
    }
}

private struct CoreRegion: Identifiable {
    let title: String
    let symbols: [String]
    var id: String { title }
    static let all = [CoreRegion(title: "美国", symbols: ["^GSPC", "^NDX"]), CoreRegion(title: "中国 / 香港", symbols: ["000300.SS", "^HSTECH"]), CoreRegion(title: "欧洲", symbols: ["^STOXX50E", "^GDAXI"])]
}

private struct CoreDescriptor {
    let symbol: String
    var name: String { switch symbol { case "^GSPC": "标普500"; case "^NDX": "纳斯达克100"; case "000300.SS": "沪深300"; case "^HSTECH": "恒生科技指数"; case "^STOXX50E": "欧洲STOXX 50"; case "^GDAXI": "德国DAX"; default: symbol } }
    var code: String { switch symbol { case "^GSPC": "SPX"; case "^NDX": "NDX"; case "000300.SS": "000300.SH"; case "^HSTECH": "HSTECH"; case "^STOXX50E": "SX5E"; case "^GDAXI": "DAX"; default: symbol } }
    var icon: String { switch symbol { case "^NDX": "n.circle.fill"; case "000300.SS": "building.2.fill"; case "^HSTECH": "asterisk"; case "^STOXX50E": "globe.europe.africa.fill"; case "^GDAXI": "shield.fill"; default: "star.fill" } }
}

private func chartPoints(_ values: [Double], size: CGSize) -> [CGPoint] {
    let minValue = values.min() ?? 0, maxValue = values.max() ?? 1, range = max(maxValue - minValue, 0.01)
    return values.enumerated().map { CGPoint(x: size.width * CGFloat($0.offset) / CGFloat(max(values.count - 1, 1)), y: size.height * (1 - CGFloat(($0.element - minValue) / range))) }
}

private func quoteTint(_ quote: MarketQuote?) -> Color { guard let quote else { return .secondary }; return quote.isUp ? MarketStyle.gain : MarketStyle.loss }
private func number(_ value: Double, digits: Int) -> String { value.formatted(.number.grouping(.automatic).precision(.fractionLength(digits))) }
private func signed(_ value: Double, digits: Int) -> String { (value >= 0 ? "+" : "−") + number(abs(value), digits: digits) }
private func compactNumber(_ value: Double) -> String { value.formatted(.number.notation(.compactName).precision(.fractionLength(1))) }
private func marketTimestamp(_ timestamp: Int64) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000))
}
private func sectorSymbol(_ name: String) -> String { if name.contains("石油") || name.contains("能源") { return "drop.fill" }; if name.contains("医疗") { return "cross.case.fill" }; if name.contains("家具") { return "house.fill" }; return "chart.line.uptrend.xyaxis" }
private func stockSymbol(_ symbol: String) -> String { switch symbol { case "AAPL": "apple.logo"; case "MSFT": "square.grid.2x2.fill"; case "META": "infinity"; case "AMZN": "a.circle.fill"; default: "eye.fill" } }
private func stockColor(_ symbol: String) -> Color { switch symbol { case "AAPL": .primary; case "AMZN": .orange; case "NVDA": .green; default: .blue } }

#Preview { MarketView() }
