import Observation
import SwiftUI

struct RetailInvestorView: View {
    @Binding private var showsDetail: Bool
    private let store: RetailSentimentStore
    private let marketStore: MarketStore
    @State private var selectedMarket: SentimentMarket = .china
    @State private var interpretationItem: InvestorMoodItem?
    @State private var showsAllInvestorMood = false
    @Environment(\.rootTabIsActive) private var rootTabIsActive

    @MainActor
    init(
        store: RetailSentimentStore,
        marketStore: MarketStore,
        showsDetail: Binding<Bool> = .constant(false)
    ) {
        self.store = store
        self.marketStore = marketStore
        _showsDetail = showsDetail
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--korea-leverage-preview") {
            _selectedMarket = State(initialValue: .korea)
        }
        #endif
    }

    @MainActor
    init(showsDetail: Binding<Bool> = .constant(false)) {
        self.init(
            store: RetailSentimentStore(),
            marketStore: MarketStore(),
            showsDetail: showsDetail
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    marketPicker
                    if let message = selectedMarket == .china
                        ? store.errorMessage
                        : store.detailErrorMessage(for: selectedMarket) {
                        errorBanner(message) {
                            Task {
                                if selectedMarket == .china {
                                    await store.load(marketStore: marketStore, force: true)
                                } else {
                                    await store.loadDetails(for: selectedMarket, force: true)
                                }
                            }
                        }
                            .padding(.horizontal, 16)
                    }
                    if selectedMarket == .korea {
                        koreaLeverageContent
                    } else {
                        sentimentDecisionHero
                        if selectedMarket == .china {
                            chinaSupplementCard
                        }
                        methodologyNote
                    }
                }
                .padding(.bottom, 36)
            }
            .background(InvestmentDesign.canvas)
            .task(id: rootTabIsActive) {
                guard rootTabIsActive else { return }
                await store.load(marketStore: marketStore)
            }
            .task(id: "\(rootTabIsActive):\(selectedMarket.rawValue)") {
                guard rootTabIsActive else { return }
                await store.loadDetails(for: selectedMarket)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear { showsDetail = false }
        .onDisappear { showsDetail = false }
        .sheet(item: $interpretationItem) { item in
            InvestorVideoInterpretationSheet(item: item, service: store.service)
        }
    }

    @ViewBuilder
    private var koreaLeverageContent: some View {
        if let snapshot = store.koreaLeverage {
            KoreaLeverageOverview(snapshot: snapshot)
        } else if store.isLoadingKoreaLeverage {
            VStack(spacing: 12) {
                ProgressView()
                Text("正在读取韩国散户杠杆数据")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 80)
        } else {
            ContentUnavailableView(
                "暂无韩国杠杆数据",
                systemImage: "chart.line.downtrend.xyaxis",
                description: Text("服务器完成首次同步后会自动显示")
            )
            .padding(.vertical, 46)
        }
    }

    private var marketTemperatureCard: some View {
        let snapshot = store.snapshot(for: selectedMarket)
        let temperature = snapshot?.score
        let accent = temperatureColor(temperature)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("市场温度")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                if store.isLoading {
                    ProgressView().controlSize(.mini)
                } else if let fetchedAt = snapshot?.fetchedAt {
                    Text(RetailSentimentFormat.shortTime(fetchedAt))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            HStack(spacing: 14) {
                MarketTemperatureGauge(value: temperature ?? 0, accent: accent)
                    .frame(width: 126, height: 88)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(temperature.map { String(Int($0.rounded())) + "°" } ?? "—")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(accent)
                            .tracking(-1)
                            .contentTransition(.numericText())
                        Text(snapshot?.label.nonEmpty ?? "等待数据")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(temperatureNarrative(temperature))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    factorStateLine(
                        title: "估值",
                        value: snapshot?.primaryValue,
                        tint: .blue,
                        kind: .valuation
                    )
                    factorStateLine(
                        title: "情绪",
                        value: snapshot?.secondaryValue,
                        tint: accent,
                        kind: .sentiment
                    )
                }
            }
            .padding(14)
            .background(
                InvestmentDesign.secondarySurface,
                in: RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius, style: .continuous)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            Divider().overlay(InvestmentDesign.divider)
            marketBreadthOverview
        }
        .background(InvestmentDesign.surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(selectedMarket.title)市场情绪 \(temperature.map { String(Int($0.rounded())) } ?? "暂无数据")")
    }

    private var sentimentDecisionHero: some View {
        let snapshot = store.snapshot(for: selectedMarket)
        let score = snapshot?.score
        let breadth = selectedBreadth
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("市场情绪")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if store.isLoadingDetails(for: selectedMarket), snapshot == nil {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(store.detailLoadingMessage(for: selectedMarket))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                } else {
                    Label(snapshot?.label.nonEmpty ?? "等待数据", systemImage: sentimentSymbol(score))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(InvestmentDesign.accent)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(score.map { String(Int($0.rounded())) } ?? "—")
                    .font(.system(size: 50, weight: .medium, design: .rounded))
                    .foregroundStyle(InvestmentDesign.accent)
                    .tracking(-2)
                    .contentTransition(.numericText())
                Text("/ 100")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(sentimentVerdict(score))
                    .font(.system(size: 19, weight: .semibold))
                    .multilineTextAlignment(.trailing)
            }

            Text(decisionNarrative(score: score, breadth: breadth))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            VStack(spacing: 7) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.13))
                        Capsule()
                            .fill(InvestmentDesign.accent)
                            .frame(width: proxy.size.width * min(max((score ?? 0) / 100, 0), 1))
                    }
                }
                .frame(height: 4)
                HStack {
                    Text("冷静")
                    Spacer()
                    Text("均衡")
                    Spacer()
                    Text("活跃")
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
            }

            HStack(spacing: 0) {
                heroMetric("上涨占比", value: breadth.total > 0 ? "\(Int((breadth.upRatio * 100).rounded()))%" : "—", tint: .primary)
                heroDivider
                heroMetric("赚钱效应", value: breadthEffectLabel(breadth), tint: .primary)
                heroDivider
                heroMetric("估值位置", value: snapshot?.primaryValue.map { String(Int($0.rounded())) } ?? "—", tint: .primary)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(InvestmentDesign.surface)
    }

    private func heroMetric(_ title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var heroDivider: some View {
        Rectangle().fill(InvestmentDesign.divider).frame(width: 0.5, height: 28)
    }

    private var sentimentDecisionGrid: some View {
        let snapshot = store.snapshot(for: selectedMarket)
        let breadth = selectedBreadth
        return HStack(spacing: 10) {
            decisionMetricCard(
                title: "上涨占比",
                value: breadth.total > 0 ? String(format: "%.1f%%", breadth.upRatio * 100) : "—",
                detail: breadth.total > 0 ? "上涨 \(breadth.up) · 下跌 \(breadth.down)" : "等待行情数据",
                icon: "chart.bar.xaxis",
                tint: breadth.up >= breadth.down ? InvestmentDesign.gain : InvestmentDesign.loss
            )
            decisionMetricCard(
                title: "估值位置",
                value: snapshot?.primaryValue.map { String(Int($0.rounded())) } ?? "—",
                detail: snapshot?.primaryTitle.nonEmpty ?? "等待估值数据",
                icon: "scope",
                tint: .blue
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var actionPlaybook: some View {
        let score = store.snapshot(for: selectedMarket)?.score
        return VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("今日应对", systemImage: "checklist")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("基于当前情绪")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(actionSuggestions(score).enumerated()), id: \.offset) { index, suggestion in
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: actionSymbol(index))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(suggestion.tint)
                            .frame(width: 28, height: 28)
                            .background(suggestion.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
                        Text(suggestion.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(11)
                    .background(InvestmentDesign.secondarySurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(InvestmentDesign.surface)
        .overlay(alignment: .bottom) { Divider().overlay(InvestmentDesign.divider) }
    }

    private func actionSymbol(_ index: Int) -> String {
        ["slider.horizontal.3", "scope", "shield.checkered"][min(index, 2)]
    }

    private func decisionDriver(_ title: String, state: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9.5)).foregroundStyle(.tertiary)
            Text(state).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(InvestmentDesign.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func decisionMetricCard(title: String, value: String, detail: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(InvestmentDesign.secondarySurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sentimentVerdict(_ score: Double?) -> String {
        guard let score else { return "正在汇总市场" }
        switch score {
        case ..<30: return "市场偏谨慎"
        case ..<70: return "市场相对均衡"
        case ..<90: return "市场情绪升温"
        default: return "市场情绪过热"
        }
    }

    private func sentimentSymbol(_ score: Double?) -> String {
        guard let score else { return "waveform.path.ecg" }
        switch score {
        case ..<30: return "shield.lefthalf.filled"
        case ..<70: return "equal.circle.fill"
        default: return "flame.fill"
        }
    }

    private func decisionNarrative(score: Double?, breadth: SentimentBreadth) -> String {
        guard score != nil else { return "正在读取估值、市场广度与散户样本，稍后给出今日结论。" }
        if breadth.total == 0 { return temperatureNarrative(score) }
        if breadth.down > breadth.up { return "下跌家数占优，赚钱效应偏弱；先观察承接力度，再决定是否提高仓位。" }
        return "上涨家数占优，市场承接尚可；关注量能持续性，避免在情绪高点盲目追涨。"
    }

    private func breadthEffectLabel(_ breadth: SentimentBreadth) -> String {
        guard breadth.total > 0 else { return "待更新" }
        if breadth.upRatio >= 0.6 { return "较强" }
        if breadth.upRatio >= 0.42 { return "一般" }
        return "偏弱"
    }

    private func actionSuggestions(_ score: Double?) -> [(title: String, tint: Color)] {
        guard let score else { return [("等待数据", .secondary), ("保持观察", .blue), ("控制风险", .orange)] }
        if score < 30 { return [("控制仓位", InvestmentDesign.loss), ("等待确认", InvestmentDesign.warning), ("避免追高", .blue)] }
        if score < 70 { return [("均衡配置", .blue), ("精选个股", InvestmentDesign.warning), ("设置止损", InvestmentDesign.loss)] }
        return [("分批止盈", InvestmentDesign.gain), ("降低追涨", InvestmentDesign.warning), ("警惕拥挤", InvestmentDesign.loss)]
    }

    private enum TemperatureFactorKind {
        case valuation
        case sentiment
    }

    private func factorStateLine(
        title: String,
        value: Double?,
        tint: Color,
        kind: TemperatureFactorKind
    ) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .foregroundStyle(.primary)
            Text(factorState(value, kind: kind))
                .foregroundStyle(tint)
            if let value {
                Text(String(Int(value.rounded())))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 13, weight: .semibold))
    }

    private func factorState(_ value: Double?, kind: TemperatureFactorKind) -> String {
        guard let value else { return "待更新" }
        switch (kind, value) {
        case (.valuation, ..<20): return "极低"
        case (.valuation, ..<30): return "偏低"
        case (.valuation, ..<70): return "适中"
        case (.valuation, ..<90): return "偏高"
        case (.valuation, _): return "极高"
        case (.sentiment, ..<20): return "冰冻"
        case (.sentiment, ..<30): return "低迷"
        case (.sentiment, ..<70): return "平稳"
        case (.sentiment, ..<90): return "活跃"
        case (.sentiment, _): return "火热"
        }
    }

    private var marketPicker: some View {
        HStack(spacing: 0) {
            ForEach(SentimentMarket.allCases) { market in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedMarket = market
                    }
                } label: {
                    VStack(spacing: 9) {
                        Text(market.title)
                            .font(.system(size: 13, weight: selectedMarket == market ? .semibold : .regular))
                            .foregroundStyle(selectedMarket == market ? Color.primary : Color.secondary)
                        Capsule()
                            .fill(selectedMarket == market ? InvestmentDesign.accent : Color.clear)
                            .frame(width: 18, height: 2.5)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 11)
        .padding(.bottom, 8)
        .background(InvestmentDesign.surface)
        .accessibilityLabel("选择市场情绪")
    }

    private var selectedBreadth: SentimentBreadth {
        if selectedMarket == .china, let breadth = store.breadth {
            return SentimentBreadth(up: breadth.up, down: breadth.down, flat: breadth.flat)
        }
        return store.constituentBreadth(for: selectedMarket)
    }

    private var marketSignalStrip: some View {
        let snapshot = store.snapshot(for: selectedMarket)
        let breadth = selectedBreadth
        return HStack(spacing: 0) {
            signalMetric(
                title: "当前状态",
                value: snapshot?.label.nonEmpty ?? "等待数据",
                tint: temperatureColor(snapshot?.score)
            )
            signalDivider
            signalMetric(
                title: "上涨占比",
                value: breadth.total > 0 ? String(format: "%.1f%%", breadth.upRatio * 100) : "—",
                tint: breadth.up >= breadth.down ? InvestmentDesign.gain : InvestmentDesign.loss
            )
            signalDivider
            signalMetric(
                title: selectedMarket == .china ? "全市场" : "核心样本",
                value: breadth.total > 0 ? breadth.total.formatted() : "—",
                tint: .primary
            )
        }
        .padding(.vertical, 14)
        .background(InvestmentDesign.surface)
    }

    private func signalMetric(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var signalDivider: some View {
        Rectangle()
            .fill(InvestmentDesign.divider)
            .frame(width: 0.5, height: 28)
    }

    private var marketBreadthOverview: some View {
        let breadth = selectedBreadth
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("涨跌分布")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(selectedMarket == .china ? "全市场 \(breadth.total)" : "核心成分 \(breadth.total)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(InvestmentDesign.gain.opacity(0.86))
                        .frame(width: proxy.size.width * breadth.upRatio)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.32))
                        .frame(width: proxy.size.width * breadth.flatRatio)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(InvestmentDesign.loss.opacity(0.86))
                }
            }
            .frame(height: 10)

            HStack(spacing: 0) {
                compactBreadthSummary("上涨", value: breadth.up, color: InvestmentDesign.gain)
                compactBreadthSummary("平盘", value: breadth.flat, color: .secondary)
                compactBreadthSummary("下跌", value: breadth.down, color: InvestmentDesign.loss)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(InvestmentDesign.surface)
    }

    private var sectorHighlights: some View {
        let leaders = Array(store.sectors.prefix(3))

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("板块涨幅排行")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("约 10 分钟更新")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            if store.sectors.isEmpty {
                placeholder("正在整理板块涨幅")
            } else {
                ForEach(Array(leaders.enumerated()), id: \.element.id) { index, sector in
                    HStack(spacing: 10) {
                        Text(String(index + 1))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(index == 0 ? InvestmentDesign.accent : Color.secondary.opacity(0.58))
                            .frame(width: 14)
                        Text(sector.name)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(RetailSentimentFormat.percent(sector.percentValue))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .frame(width: 56, alignment: .trailing)
                    }
                    .frame(height: 38)
                    if index < leaders.count - 1 {
                        Divider().overlay(InvestmentDesign.divider).padding(.leading, 24)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var chinaSupplementCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectorHighlights
            Divider().overlay(InvestmentDesign.divider)
            investorMoodCard
        }
        .background(InvestmentDesign.surface)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("散户正在说")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("视频由后台自动解读")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            if store.investorMood?.items.isEmpty != false {
                placeholder("正在等待大曾子、王小雨等账号的最新有效样本")
            } else if let items = store.investorMood?.items {
                investorMoodSummary(items)
                investorMoodList(items)
            }
        }
        .padding(.vertical, 16)
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
                        .fill(InvestmentDesign.accent)
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
        .padding(.vertical, 2)
        .padding(.horizontal, 16)
    }

    private func investorMoodList(_ items: [InvestorMoodItem]) -> some View {
        let visibleItems = showsAllInvestorMood ? items : Array(items.prefix(2))
        return LazyVStack(spacing: 0) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                InvestorMoodVideoCard(
                    item: item,
                    onInterpret: { interpretationItem = item }
                )
                if index < visibleItems.count - 1 {
                    Divider()
                        .overlay(InvestmentDesign.divider)
                        .padding(.leading, 112)
                }
            }
            if items.count > 2 {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showsAllInvestorMood.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(showsAllInvestorMood ? "收起列表" : "查看全部 \(items.count) 条")
                        Image(systemName: showsAllInvestorMood ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(InvestmentDesign.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Divider().overlay(InvestmentDesign.divider) }
            }
        }
        .padding(.horizontal, 16)
    }

    private var methodologyNote: some View {
        Label("温度由估值和市场广度等权合成，人物观点不参与评分。", systemImage: "checkmark.shield.fill")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 2)
    }

    private var sectionGap: some View {
        InvestmentDesign.canvas
            .frame(height: InvestmentDesign.sectionSpacing)
    }

    private func sentimentFactor(title: String, value: Double?, icon: String, tint: Color) -> some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value.map { String(Int($0.rounded())) } ?? "—")
                .font(.system(size: 22, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
    }

    private func compactBreadthSummary(_ title: String, value: Int, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value.formatted())
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func temperatureNarrative(_ value: Double?) -> String {
        guard let value else { return "正在汇总最新市场信号" }
        switch value {
        case ..<10: return "风险偏好极低，市场处于深度冷静区"
        case ..<30: return "资金偏谨慎，机会与风险开始重新定价"
        case ..<70: return "多空力量相对均衡，市场情绪保持中性"
        case ..<90: return "风险偏好升温，需留意交易拥挤"
        default: return "情绪明显过热，波动风险正在累积"
        }
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
        case 90...: return InvestmentDesign.gain
        case 70..<90: return InvestmentDesign.warning
        default: return InvestmentDesign.accent
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

    private func errorBanner(_ message: String, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12.5))
                .foregroundStyle(.orange)
            Spacer(minLength: 8)
            Button("重试", action: retry)
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(InvestmentDesign.accent)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct MarketTemperatureGauge: View {
    let value: Double
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let normalizedValue = min(max(value, 0), 100) / 100
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height - 18)
            let radius = min(proxy.size.width / 2 - 12, proxy.size.height - 32)
            let needleAngle = 180 + normalizedValue * 180

            ZStack(alignment: .bottom) {
                Canvas { context, _ in
                    var track = Path()
                    track.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(180),
                        endAngle: .degrees(360),
                        clockwise: false
                    )
                    context.stroke(
                        track,
                        with: .color(Color(uiColor: .tertiarySystemFill)),
                        style: StrokeStyle(lineWidth: 18, lineCap: .butt)
                    )

                    var active = Path()
                    active.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(180),
                        endAngle: .degrees(180 + normalizedValue * 180),
                        clockwise: false
                    )
                    context.stroke(
                        active,
                        with: .color(accent),
                        style: StrokeStyle(lineWidth: 18, lineCap: .butt)
                    )

                    let radians = needleAngle * .pi / 180
                    let needleEnd = CGPoint(
                        x: center.x + cos(radians) * radius * 0.78,
                        y: center.y + sin(radians) * radius * 0.78
                    )
                    var needle = Path()
                    needle.move(to: center)
                    needle.addLine(to: needleEnd)
                    context.stroke(
                        needle,
                        with: .color(.primary),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)),
                        with: .color(.primary)
                    )
                }

                HStack {
                    Text("0°")
                    Spacer()
                    Text("100°")
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct InvestorMoodCount: Identifiable {
    var id: String { label }
    let label: String
    let count: Int
}

private struct InvestorVideoInterpretationSheet: View {
    let item: InvestorMoodItem
    let service: MarketService
    @Environment(\.dismiss) private var dismiss
    @State private var payload: InvestorVideoInterpretationResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.nickname).font(.headline)
                        Text(item.description.nonEmpty ?? "散户观点视频")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let payload, let interpretation = payload.interpretation {
                        interpretationContent(payload, interpretation: interpretation)
                    } else if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("正在获取视频解读…")
                                .font(.headline)
                            Text("首次处理可能需要一两分钟，完成后会直接使用缓存结果。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 52)
                    } else if payload?.status == "pending" {
                        ContentUnavailableView(
                            "后台解读中",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("服务端正在下载、压缩并解读这个视频，通常需要几分钟。")
                        )
                        Button("刷新状态") { Task { await interpret() } }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                    } else if let errorMessage {
                        ContentUnavailableView(
                            "视频解读暂不可用",
                            systemImage: "eye.slash",
                            description: Text(errorMessage)
                        )
                        Button("刷新状态") { Task { await interpret() } }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(18)
            }
            .navigationTitle("视频解读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task(id: item.id) { await interpret() }
    }

    private func interpretationContent(
        _ payload: InvestorVideoInterpretationResponse,
        interpretation: BilibiliVideoInterpretation
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(payload.cached ? "缓存结果" : "智谱完整视频解读", systemImage: "eye.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(payload.cached ? .green : .blue)
                Spacer()
                Text(payload.model).font(.caption).foregroundStyle(.secondary)
            }
            Text(interpretation.overview).font(.body).lineSpacing(5).textSelection(.enabled)
            bulletSection("画面与关键发现", interpretation.visualFindings)
            if !interpretation.timeline.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("视频时间线").font(.headline)
                    ForEach(Array(interpretation.timeline.enumerated()), id: \.offset) { _, event in
                        HStack(alignment: .top, spacing: 10) {
                            Text(event.time)
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(.blue)
                                .frame(width: 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title).font(.subheadline.weight(.semibold))
                                Text(event.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            bulletSection("观点、证据与风险观察", interpretation.creatorNotes)
            Label(
                payload.cached
                    ? "缓存结果，本次未新增模型费用"
                    : String(format: "本次模型处理成本约 ¥%.3f", payload.estimatedCostCNY),
                systemImage: payload.cached ? "bolt.horizontal.circle.fill" : "yensign.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(payload.cached ? .green : .orange)
        }
    }

    private func bulletSection(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !items.isEmpty { Text(title).font(.headline) }
            ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(.blue).frame(width: 6, height: 6).padding(.top, 7)
                    Text(text).font(.subheadline).lineSpacing(3)
                }
            }
        }
    }

    @MainActor
    private func interpret() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            payload = try await service.investorVideoInterpretationStatus(item)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct InvestorMoodVideoCard: View {
    let item: InvestorMoodItem
    let onInterpret: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Button(action: onInterpret) {
                thumbnail
                    .frame(width: 88, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.nickname)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    moodBadge
                    Spacer(minLength: 2)
                    Text(RetailSentimentFormat.relativeTime(item.createdAt))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
                Text(summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(action: onInterpret) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles.tv")
                        Text("查看视频解读")
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(InvestmentDesign.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            Color.black
            AsyncImage(url: item.coverPlaybackURL ?? MediaURL.image(item.coverUrl) ?? URL(string: item.coverUrl)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    LinearGradient(
                        colors: [.black, InvestmentDesign.accent.opacity(0.48)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            Circle()
                .fill(.black.opacity(0.58))
                .frame(width: 30, height: 30)
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: 1)
        }
        .clipped()
    }

    private var summary: String {
        item.analysis.nonEmpty ?? item.reasons.first?.nonEmpty ?? item.description.nonEmpty ?? "暂无观点摘要"
    }

    private var moodBadge: some View {
        return Text(item.stale ? "\(item.label) · 旧样本" : item.label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(InvestmentDesign.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(InvestmentDesign.accentSoft, in: Capsule())
    }
}

@MainActor
@Observable
final class RetailSentimentStore {
    private(set) var dashboard: MarketDashboard?
    private(set) var investorMood: InvestorMoodBoard?
    private(set) var temperature: MarketAShareTemperature?
    private(set) var koreaLeverage: MarketKoreaLeverage?
    private(set) var marketSnapshots: [SentimentMarket: MarketSentimentSnapshot] = [:]
    private(set) var isLoadingKoreaLeverage = false
    private(set) var koreaLeverageErrorMessage: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    let service: MarketService
    private var loaded = false
    private var loadedMarkets: Set<SentimentMarket> = []
    private var loadingMarkets: Set<SentimentMarket> = []
    private var detailErrors: [SentimentMarket: String] = [:]

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

    func isLoadingDetails(for market: SentimentMarket) -> Bool {
        loadingMarkets.contains(market)
    }

    func detailErrorMessage(for market: SentimentMarket) -> String? {
        detailErrors[market]
    }

    func detailLoadingMessage(for market: SentimentMarket) -> String {
        switch market {
        case .china:
            return "正在汇总数据"
        case .hongKong:
            return "读取港股情绪快照"
        case .unitedStates:
            return "读取美股情绪快照"
        case .korea:
            return "读取韩股情绪快照"
        }
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
            guard let remote = marketSnapshots[market] else { return nil }
            return SentimentSnapshot(
                score: remote.score,
                label: remote.label,
                primaryTitle: "估值温度",
                primaryValue: remote.valuationPercentile,
                secondaryTitle: "情绪温度",
                secondaryValue: remote.sentimentPercentile,
                formula: "估值与情绪各占 50%",
                fetchedAt: remote.fetchedAt,
                detail: "与 A 股采用相同公式：恒生指数当前市盈率的历史百分位，与核心成分上涨家数占比的近一年历史百分位等权合成。"
            )
        case .unitedStates:
            guard let remote = marketSnapshots[market] else { return nil }
            return SentimentSnapshot(
                score: remote.score,
                label: remote.label,
                primaryTitle: "估值温度",
                primaryValue: remote.valuationPercentile,
                secondaryTitle: "情绪温度",
                secondaryValue: remote.sentimentPercentile,
                formula: "估值与情绪各占 50%",
                fetchedAt: remote.fetchedAt,
                detail: "与 A 股采用相同公式：标普 500 当前市盈率的历史百分位，与核心成分上涨家数占比的近一年历史百分位等权合成。"
            )
        case .korea:
            return nil
        }
    }

    func constituentBreadth(for market: SentimentMarket) -> SentimentBreadth {
        if let breadth = marketSnapshots[market]?.breadth {
            return SentimentBreadth(up: breadth.up, down: breadth.down, flat: breadth.flat)
        }
        return SentimentBreadth(up: 0, down: 0, flat: 0)
    }

    func load(marketStore: MarketStore, force: Bool = false) async {
        if loaded, !force {
            dashboard = marketStore.dashboard ?? dashboard
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        async let moodRequest = service.investorMood()
        async let temperatureRequest = service.aShareTemperature()
        if force || marketStore.dashboard == nil {
            await marketStore.refresh(force: force)
        }
        guard !Task.isCancelled else { return }
        dashboard = marketStore.dashboard
        if dashboard != nil { errorMessage = nil }
        do {
            let mood = try await moodRequest
            investorMood = mood
            Task {
                await service.prewarmInvestorMoodVideos(mood.items)
            }
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
        loaded = dashboard != nil || investorMood != nil || temperature != nil
    }

    func loadDetails(for market: SentimentMarket, force: Bool = false) async {
        guard market != .china else { return }
        if loadedMarkets.contains(market), !force { return }
        guard loadingMarkets.insert(market).inserted else { return }
        defer { loadingMarkets.remove(market) }
        detailErrors[market] = nil

        let succeeded = switch market {
        case .china:
            true
        case .hongKong:
            await loadMarketSnapshot(for: market, force: force)
        case .unitedStates:
            await loadMarketSnapshot(for: market, force: force)
        case .korea:
            await loadMarketSnapshot(for: market, force: force)
        }
        guard !Task.isCancelled else { return }
        if succeeded {
            loadedMarkets.insert(market)
        } else {
            loadedMarkets.remove(market)
            if detailErrors[market] == nil {
                detailErrors[market] = "数据暂未完整返回"
            }
        }
    }

    private func loadMarketSnapshot(for market: SentimentMarket, force: Bool) async -> Bool {
        guard market != .china else { return true }
        if market == .korea { isLoadingKoreaLeverage = true }
        defer { if market == .korea { isLoadingKoreaLeverage = false } }
        let apiMarket = switch market {
        case .hongKong: "hong-kong"
        case .unitedStates: "united-states"
        case .korea: "korea"
        case .china: ""
        }
        do {
            let value = try await service.sentimentSnapshot(market: apiMarket, refresh: force)
            guard value.dataContract == "market_sentiment_snapshot_v1" else {
                detailErrors[market] = "情绪快照格式不受支持"
                return false
            }
            marketSnapshots[market] = value
            if market == .korea {
                koreaLeverage = value.koreaLeverage
                koreaLeverageErrorMessage = value.koreaLeverage == nil ? "韩国杠杆快照暂不可用" : nil
            }
            detailErrors[market] = nil
            return market == .korea ? value.koreaLeverage != nil : true
        } catch is CancellationError {
            return false
        } catch {
            detailErrors[market] = error.localizedDescription
            if market == .korea { koreaLeverageErrorMessage = error.localizedDescription }
            return false
        }
    }

}

enum SentimentMarket: String, CaseIterable, Identifiable {
    case china
    case hongKong
    case unitedStates
    case korea

    var id: Self { self }
    var title: String {
        switch self {
        case .china: "A 股"
        case .hongKong: "港股"
        case .unitedStates: "美股"
        case .korea: "韩股"
        }
    }
    var methodology: String {
        switch self {
        case .china: "估值与情绪各占 50%"
        case .hongKong: "估值与情绪各占 50%"
        case .unitedStates: "估值与情绪各占 50%"
        case .korea: "散户杠杆风险"
        }
    }
    var detail: String {
        switch self {
        case .china: "结合估值与市场广度的历史百分位。"
        case .hongKong: "恒指估值与核心成分情绪各占 50%。"
        case .unitedStates: "标普估值与核心成分情绪各占 50%。"
        case .korea: "融资、杠杆 ETF 与投资者存管金共同衡量散户杠杆压力。"
        }
    }
}

private struct KoreaLeverageOverview: View {
    let snapshot: MarketKoreaLeverage

    private var alertColor: Color {
        switch snapshot.alert.level {
        case "critical": InvestmentDesign.gain
        case "warning": InvestmentDesign.warning
        default: InvestmentDesign.loss
        }
    }

    private var alertTitle: String {
        switch snapshot.alert.level {
        case "critical": "杠杆高危"
        case "warning": "杠杆偏高"
        default: "杠杆正常"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("韩国散户杠杆")
                            .font(.system(size: 16, weight: .semibold))
                        Text("数据截至 \(formattedAsOf)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(alertTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(alertColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(alertColor.opacity(0.1), in: Capsule())
                }

                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text(snapshot.leverageThermometer.value, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .foregroundStyle(alertColor)
                        .tracking(-1.2)
                    Text("%")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(alertColor)
                    Spacer()
                    Text("预警 > \(snapshot.alert.thresholds.warning, format: .number.precision(.fractionLength(0)))%\n高危 > \(snapshot.alert.thresholds.critical, format: .number.precision(.fractionLength(0)))%")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                KoreaLeverageScale(
                    value: snapshot.leverageThermometer.value,
                    warning: snapshot.alert.thresholds.warning,
                    critical: snapshot.alert.thresholds.critical,
                    tint: alertColor
                )

                Text(snapshot.alert.message)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(InvestmentDesign.surface)

            InvestmentDesign.canvas.frame(height: InvestmentDesign.sectionSpacing)

            VStack(alignment: .leading, spacing: 0) {
                Text("杠杆压力")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                HStack(spacing: 0) {
                    metric(
                        "强平金额 5日均",
                        value: "\(String(format: "%.0f", snapshot.forcedLiquidation.fiveDayAverageBillionKRW)) 亿韩元",
                        detail: "10年 \(String(format: "%.0f", snapshot.forcedLiquidation.percentile10Y))% 分位"
                    )
                    divider
                    metric(
                        "R2 融资/存管金",
                        value: "\(String(format: "%.2f", snapshot.r2FinancingRatio.value))%",
                        detail: "10年 \(String(format: "%.1f", snapshot.r2FinancingRatio.percentile10Y))% 分位"
                    )
                }
                .padding(.bottom, 16)
                Divider().overlay(InvestmentDesign.divider)
                HStack(spacing: 0) {
                    metric("KOSPI", value: snapshot.indices.kospi.formatted(.number.precision(.fractionLength(0...2))), detail: "韩国综合指数")
                    divider
                    metric("数据新鲜度", value: snapshot.freshness.staleDays == 0 ? "当日" : "\(snapshot.freshness.staleDays) 天前", detail: "每日 14:25 同步")
                }
                .padding(.vertical, 16)
            }
            .background(InvestmentDesign.surface)

            InvestmentDesign.canvas.frame(height: InvestmentDesign.sectionSpacing)

            VStack(alignment: .leading, spacing: 9) {
                Label("数据口径", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("杠杆温度计 =（融资余额 + 杠杆 ETF 累计净申赎）/ 投资者存管金。数据由服务器保存，客户端不直接请求第三方。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(snapshot.source.name)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(InvestmentDesign.surface)
        }
    }

    private var divider: some View {
        Rectangle().fill(InvestmentDesign.divider).frame(width: 0.5, height: 52)
    }

    private func metric(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(detail).font(.system(size: 10.5)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private var formattedAsOf: String {
        guard snapshot.asOf.count == 8 else { return snapshot.asOf }
        return "\(snapshot.asOf.prefix(4))-\(snapshot.asOf.dropFirst(4).prefix(2))-\(snapshot.asOf.suffix(2))"
    }
}

private struct KoreaLeverageScale: View {
    let value: Double
    let warning: Double
    let critical: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.13))
                Capsule()
                    .fill(tint.opacity(0.86))
                    .frame(width: proxy.size.width * min(max(value / 60, 0), 1))
                marker(at: warning, width: proxy.size.width)
                marker(at: critical, width: proxy.size.width)
            }
        }
        .frame(height: 8)
        .accessibilityLabel("杠杆温度计 \(value, format: .number.precision(.fractionLength(1)))%")
    }

    private func marker(at value: Double, width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.36))
            .frame(width: 1, height: 12)
            .offset(x: width * min(max(value / 60, 0), 1))
    }
}

struct SentimentSnapshot {
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

struct SentimentBreadth {
    let up: Int
    let down: Int
    let flat: Int
    var total: Int { up + down + flat }
    var weightedAdvancerShare: Double { (Double(up) + Double(flat) / 2) / Double(max(total, 1)) }
    var upRatio: CGFloat { CGFloat(up) / CGFloat(max(total, 1)) }
    var flatRatio: CGFloat { CGFloat(flat) / CGFloat(max(total, 1)) }
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
        return date.formatted(
            .dateTime
                .locale(Locale(identifier: "zh_CN"))
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
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
